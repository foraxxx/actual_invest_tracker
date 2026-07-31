import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/services/backup_crypto_service.dart';

void main() {
  test('AES-GCM сохраняет и восстанавливает JSON', () {
    const source = '{"version":4,"purchases":[]}';
    final encrypted = BackupCryptoService.encrypt(source, 'correct horse');
    final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
    expect(envelope['version'], 2);
    expect(envelope['cipher'], 'aes-256-gcm');
    expect(BackupCryptoService.decrypt(encrypted, 'correct horse'), source);
  });

  test('изменённый шифротекст не проходит проверку целостности', () {
    final encrypted = BackupCryptoService.encrypt('{"version":4}', 'secret');
    final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
    final data = envelope['data'] as String;
    envelope['data'] = '${data.substring(0, data.length - 2)}AA';
    expect(
      () => BackupCryptoService.decrypt(jsonEncode(envelope), 'secret'),
      throwsFormatException,
    );
  });

  test('опасное число итераций отклоняется до вычисления ключа', () {
    final encrypted = BackupCryptoService.encrypt('{"version":4}', 'secret');
    final envelope = jsonDecode(encrypted) as Map<String, dynamic>
      ..['iterations'] = 2000000000;
    expect(
      () => BackupCryptoService.decrypt(jsonEncode(envelope), 'secret'),
      throwsFormatException,
    );
  });
}
