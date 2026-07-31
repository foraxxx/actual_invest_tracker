import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Шифрование резервных копий.
///
/// Бэкап уезжает в облако, в мессенджер или просто лежит в «Загрузках», а
/// внутри — весь портфель. Поэтому файл можно закрыть паролем: содержимое
/// шифруется AES, ключ выводится из пароля, а в файле остаётся только конверт
/// со случайной солью и вектором инициализации.
///
/// Пароль хранится на устройстве — иначе автосохранение пришлось бы
/// подтверждать вручную при каждом изменении данных. Защищается именно файл,
/// а не приложение.
class BackupCryptoService {
  static const boxName = 'backup_crypto';
  static const _enabledKey = 'enabled';
  static const _passwordKey = 'password';
  static const _securePasswordKey = 'invest_tracker_backup_password';

  /// Столько раз прогоняется пароль через хеш при выводе ключа. Больше —
  /// дольше подбирать перебором, но и дольше открывать файл на слабом
  /// телефоне.
  static const _iterations = 120000;
  static const _minIterations = 10000;
  static const _maxIterations = 1000000;

  static late Box<String> _box;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static String? _password;

  static final ValueNotifier<int> version = ValueNotifier(0);

  static Future<void> init() async {
    _box = await Hive.openBox<String>(boxName);
    _password = await _secureStorage.read(key: _securePasswordKey);
    // Одноразовая миграция пароля из незашифрованного Hive в системное
    // защищённое хранилище.
    final legacy = _box.get(_passwordKey);
    if ((_password == null || _password!.isEmpty) &&
        legacy != null &&
        legacy.isNotEmpty) {
      await _secureStorage.write(key: _securePasswordKey, value: legacy);
      _password = legacy;
    }
    await _box.delete(_passwordKey);
  }

  static bool get enabled => _box.get(_enabledKey) == '1' && password != null;

  static String? get password {
    final value = _password;
    return (value == null || value.isEmpty) ? null : value;
  }

  static bool get hasPassword => password != null;

  static Future<void> setPassword(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await _secureStorage.write(key: _securePasswordKey, value: trimmed);
    _password = trimmed;
    await _box.put(_enabledKey, '1');
    version.value++;
  }

  static Future<void> setEnabled(bool value) async {
    await _box.put(_enabledKey, value ? '1' : '0');
    version.value++;
  }

  /// Полностью убирает пароль — новые бэкапы снова будут открытыми.
  static Future<void> clear() async {
    await _secureStorage.delete(key: _securePasswordKey);
    _password = null;
    await _box.put(_enabledKey, '0');
    version.value++;
  }

  /// Похоже ли содержимое файла на зашифрованный бэкап.
  static bool looksEncrypted(String content) {
    try {
      final json = jsonDecode(content);
      return json is Map && json['encrypted'] == true && json['data'] is String;
    } catch (_) {
      return false;
    }
  }

  /// Заворачивает JSON в конверт с шифротекстом.
  static String encrypt(String plainJson, String password) {
    final salt = _randomBytes(16);
    final iv = _randomBytes(12);
    final key = enc.Key(_deriveKey(password, salt));

    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainJson, iv: enc.IV(iv));

    return const JsonEncoder.withIndent('  ').convert({
      'encrypted': true,
      'version': 2,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _iterations,
      'cipher': 'aes-256-gcm',
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'data': encrypted.base64,
      // Подсказка для того, кто откроет файл текстовым редактором.
      'note': 'Файл зашифрован паролем в приложении Invest Tracker',
    });
  }

  /// Достаёт JSON из конверта. Бросает исключение, если пароль не подошёл.
  static String decrypt(String envelopeJson, String password) {
    final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
    final salt = base64Decode('${envelope['salt']}');
    final iv = base64Decode('${envelope['iv']}');
    final iterations = (envelope['iterations'] as num?)?.toInt() ?? _iterations;
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const FormatException('Некорректные параметры шифрования');
    }

    final key = enc.Key(_deriveKey(password, salt, iterations: iterations));
    final version = (envelope['version'] as num?)?.toInt() ?? 1;
    if (version != 2 || envelope['cipher'] != 'aes-256-gcm') {
      throw const FormatException(
        'Устаревший формат шифрования не поддерживается',
      );
    }
    if (salt.length != 16 || iv.length != 12) {
      throw const FormatException('Некорректные параметры шифрования');
    }
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));

    final String plain;
    try {
      plain = encrypter.decrypt64('${envelope['data']}', iv: enc.IV(iv));
    } catch (_) {
      throw const FormatException('Неверный пароль');
    }

    // Расшифровалось «во что-то» — проверяем, что это действительно наш JSON:
    // при неверном пароле обычно получается мусор, а не читаемая структура.
    try {
      jsonDecode(plain);
    } catch (_) {
      throw const FormatException('Неверный пароль');
    }
    return plain;
  }

  static Uint8List _deriveKey(String password, Uint8List salt, {int iterations = _iterations}) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }
}
