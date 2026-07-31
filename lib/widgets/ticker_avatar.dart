import 'dart:io';
import 'package:flutter/material.dart';
import '../services/moex_service.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';
import '../services/logo_service.dart';

/// Показывает загруженный пользователем логотип бумаги, если он есть, иначе
/// генерирует стабильную (одинаковую между запусками) градиентную аватарку
/// с инициалами тикера. В редизайне добавлены мягкое цветное свечение под
/// аватаркой и тонкая светлая кромка — так иконки не «прилипают» к фону
/// карточек и выглядят объёмно на обеих темах.
class TickerAvatar extends StatelessWidget {
  final String ticker;
  final double size;
  final bool glow;

  const TickerAvatar({super.key, required this.ticker, this.size = 42, this.glow = true});

  static const List<List<Color>> _palettes = [
    [Color(0xFF7C6CFF), Color(0xFFB39DFF)],
    [Color(0xFF00C48C), Color(0xFF5BE7B5)],
    [Color(0xFFFF8A5B), Color(0xFFFFC29B)],
    [Color(0xFF3DA9FC), Color(0xFF8ACDFF)],
    [Color(0xFFFF5C93), Color(0xFFFF9BC0)],
    [Color(0xFFEF4444), Color(0xFFFF8A80)],
    [Color(0xFF06B6D4), Color(0xFF7DE3F4)],
    [Color(0xFFF5B027), Color(0xFFFFD87A)],
    [Color(0xFF8B5CF6), Color(0xFFC4A6FF)],
    [Color(0xFF475569), Color(0xFF94A3B8)],
  ];

  List<Color> get _gradient {
    // Хэш по кодам символов — стабилен между запусками, поэтому у бумаги
    // всегда один и тот же цвет.
    final hash = ticker.codeUnits.fold<int>(0, (a, b) => a + b * 31);
    return _palettes[hash.abs() % _palettes.length];
  }

  /// Что за бумага — по режиму торгов с биржи, а если её там нет, то по виду
  /// тикера: у облигаций он начинается с RU000, у ОФЗ — с SU.
  IconData? get _kindIcon {
    final upper = ticker.toUpperCase();
    final board = MoexSyncService.marketSnapshot.value[upper]?.board;

    if (board == 'TQOB' || upper.startsWith('SU')) return Icons.account_balance_rounded;
    if (board == 'TQCB' || upper.startsWith('RU000')) return Icons.receipt_long_rounded;
    if (board == 'TQTF') return Icons.pie_chart_rounded;
    return null;
  }

  String get _initials {
    if (ticker.isEmpty) return '?';
    final clean = ticker.replaceAll(RegExp(r'[^A-Za-zА-Яа-я0-9]'), '');
    if (clean.isEmpty) return '?';
    return clean.length >= 2 ? clean.substring(0, 2).toUpperCase() : clean.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем LogoService.version, чтобы аватарка перерисовалась на любом
    // экране сразу после смены/удаления логотипа.
    return ValueListenableBuilder<int>(
      valueListenable: LogoService.version,
      builder: (context, _, __) {
        final logoPath = LogoService.getPath(ticker);
        if (logoPath == null && OnlineSettingsService.enabled) {
          // Тянем логотип только для бумаг, которые реально попали на экран:
          // на вкладке «Биржа» строк тысячи, и грузить всё подряд нельзя.
          // Повторные попытки отсекает сам LogoService.
          final isin = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()]?.isin;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final quote = MoexSyncService.marketSnapshot.value[ticker.toUpperCase()];
            if (await LogoService.fetchIfMissing(
              ticker,
              isin: isin,
              companyName: quote?.shortName,
            )) {
              return;
            }
            // Своего логотипа нет — берём логотип эмитента. Так облигации
            // получают картинку компании, которая их выпустила.
            final issuer = await MoexService.issuerShareFor(ticker);
            if (issuer == null) return;
            await LogoService.forgetFailedAttempt(ticker);
            await LogoService.fetchIfMissing(
              ticker,
              isin: isin,
              issuerTicker: issuer,
              issuerIsin: await MoexService.isinOf(issuer),
              companyName: quote?.shortName,
              issuerName: await MoexService.nameOf(issuer),
            );
          });
        }
        final colors = _gradient;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: glow
                ? [
                    BoxShadow(
                      color: colors.first.withOpacity(0.38),
                      blurRadius: size * 0.32,
                      offset: Offset(0, size * 0.12),
                    ),
                  ]
                : null,
          ),
          child: logoPath != null
              ? ClipOval(
                  child: Image.file(
                    File(logoPath),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => _fallback(colors),
                  ),
                )
              : _fallback(colors),
        );
      },
    );
  }

  Widget _fallback(List<Color> colors) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 1),
      ),
      alignment: Alignment.center,
      // У облигаций и фондов буквы тикера ничего не говорят — «RU000A10CBA2»
      // превращается в «RU». Вместо них рисуем знак по типу бумаги, и заглушка
      // выглядит намеренной, а не пустой.
      child: _kindIcon != null
          ? Icon(_kindIcon, color: Colors.white, size: size * 0.46)
          : Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.35,
                letterSpacing: -0.6,
              ),
            ),
    );
  }
}
