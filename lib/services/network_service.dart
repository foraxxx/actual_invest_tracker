import 'dart:io';

import 'package:flutter/foundation.dart';

/// Определение VPN на устройстве.
///
/// Отдельного API для этого нет, но VPN на Android и iOS всегда поднимает
/// виртуальный сетевой интерфейс с узнаваемым именем — по нему и смотрим.
/// Это подсказка, а не точная диагностика: часть VPN-приложений работает
/// иначе, поэтому плашку показываем только вместе с ошибкой загрузки.
class NetworkService {
  NetworkService._();

  static const _vpnPrefixes = ['tun', 'tap', 'ppp', 'ipsec', 'utun', 'ppoe', 'wg'];

  static final ValueNotifier<bool> vpnDetected = ValueNotifier(false);

  static Future<bool> checkVpn() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      final found = interfaces.any(
        (i) => _vpnPrefixes.any((p) => i.name.toLowerCase().startsWith(p)),
      );
      vpnDetected.value = found;
      return found;
    } catch (_) {
      // На части устройств список интерфейсов недоступен — молча считаем,
      // что VPN нет, чтобы не пугать пользователя ложной плашкой.
      return false;
    }
  }
}
