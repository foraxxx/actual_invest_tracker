import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../design/format.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../services/analytics_service.dart';
import '../services/payout_forecast_service.dart';
import '../widgets/ticker_avatar.dart';

/// Итоги портфеля в формате коротких «сторис» — пролистываются свайпом или
/// тапом, сами переключаются по таймеру (полоска сверху показывает прогресс),
/// в конце — кнопка «поделиться» текстовой сводкой.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key});

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

class _StorySlide {
  final String eyebrow;
  final Widget content;
  final Color accent;
  const _StorySlide({required this.eyebrow, required this.content, required this.accent});
}

class _WrappedScreenState extends State<WrappedScreen> with SingleTickerProviderStateMixin {
  final _pageController = PageController();
  late final AnimationController _progress;
  int _index = 0;
  bool _paused = false;
  late final List<_StorySlide> _slides;
  late final String _shareText;

  static const _slideDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _buildSlides();
    _progress = AnimationController(vsync: this, duration: _slideDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      })
      ..forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _restartProgress() {
    _progress
      ..reset()
      ..forward();
  }

  void _next() {
    if (_index < _slides.length - 1) {
      _pageController.nextPage(duration: AppDuration.normal, curve: AppCurves.enter);
    }
  }

  void _prev() {
    if (_index > 0) {
      _pageController.previousPage(duration: AppDuration.normal, curve: AppCurves.enter);
    }
  }

  void _buildSlides() {
    final value = AnalyticsService.currentPortfolioValueRub();
    final unrealized = AnalyticsService.totalUnrealizedPnlRub();
    final realized = AnalyticsService.totalRealizedPnlRub();
    final income = AnalyticsService.totalIncome(f: PeriodFilter.all);
    final totalProfit = unrealized + realized + income;
    final topTicker = AnalyticsService.topHoldingTicker();
    final concentration = AnalyticsService.topHoldingConcentrationPct();
    // Тот же расчёт, что на главной и в выплатах: по графику купонов и
    // динамике дивидендов самой бумаги.
    final forecast = PayoutForecastService.portfolioForecast().total;
    final xirr = AnalyticsService.xirrPercent();

    final String riskLabel;
    final Color riskColor;
    if (concentration >= 50) {
      riskLabel = 'Высокая концентрация';
      riskColor = AppColors.negative;
    } else if (concentration >= 25) {
      riskLabel = 'Умеренная концентрация';
      riskColor = AppColors.warning;
    } else {
      riskLabel = 'Хорошая диверсификация';
      riskColor = AppColors.positive;
    }

    _slides = [
      _StorySlide(
        eyebrow: 'ИТОГИ ПОРТФЕЛЯ',
        accent: AppColors.cyan,
        content: _bigNumberSlide(
          title: 'Сейчас портфель стоит',
          value: value,
          color: AppColors.cyan,
        ),
      ),
      _StorySlide(
        eyebrow: 'ГЛАВНЫЙ АКТИВ',
        accent: AppColors.violet,
        content: topTicker == null
            ? _textSlide('Пока в портфеле нет бумаг — самое время начать')
            : _topAssetSlide(topTicker, concentration),
      ),
      _StorySlide(
        eyebrow: 'ПРИБЫЛЬ',
        accent: AppColors.pnl(totalProfit),
        content: _bigNumberSlide(
          title: totalProfit >= 0 ? 'Суммарно Вы заработали' : 'Суммарный результат',
          value: totalProfit,
          color: AppColors.pnl(totalProfit),
          showSign: true,
        ),
      ),
      _StorySlide(
        eyebrow: 'УРОВЕНЬ РИСКА',
        accent: riskColor,
        content: _riskSlide(riskLabel, riskColor, concentration, xirr),
      ),
      _StorySlide(
        eyebrow: 'ВЫПЛАТЫ',
        accent: AppColors.positive,
        content: _bigNumberSlide(
          title: 'Дивидендами и купонами получено',
          value: income,
          color: AppColors.positive,
          subtitle: forecast > 0
              ? '12 месяцев со следующего месяца: ≈ ${Fmt.money(forecast)}'
              : null,
        ),
      ),
      _StorySlide(
        eyebrow: 'ГОТОВО',
        accent: AppColors.gold,
        content: _shareSlide(),
      ),
    ];

    _shareText = 'Мой портфель в Invest Tracker: ${Fmt.money(value)}, '
        'общая прибыль ${Fmt.signedMoney(totalProfit)}'
        '${topTicker != null ? ", главный актив — $topTicker" : ""}.';
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_index];
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // Фон живёт отдельно от PageView, чтобы цвет плавно перетекал
          // из одной истории в другую, а не прыгал вместе со страницей.
          AnimatedContainer(
            duration: AppDuration.slow,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.75),
                radius: 1.35,
                colors: [slide.accent.withOpacity(0.28), AppColors.darkBg],
              ),
            ),
          ),
          SafeArea(
            child: Stack(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: (details) {
                    final w = MediaQuery.of(context).size.width;
                    if (details.globalPosition.dx < w / 3) {
                      _prev();
                    } else {
                      _next();
                    }
                  },
                  onLongPressStart: (_) {
                    setState(() => _paused = true);
                    _progress.stop();
                  },
                  onLongPressEnd: (_) {
                    setState(() => _paused = false);
                    _progress.forward();
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _slides.length,
                    onPageChanged: (i) {
                      setState(() => _index = i);
                      _restartProgress();
                    },
                    itemBuilder: (context, i) => _slideBody(_slides[i], i),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 14,
                  right: 14,
                  child: Row(
                    children: List.generate(_slides.length, (i) {
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2.5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.white.withOpacity(0.22),
                          ),
                          child: i < _index
                              ? Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    color: Colors.white,
                                  ),
                                )
                              : i == _index
                                  ? AnimatedBuilder(
                                      animation: _progress,
                                      builder: (context, _) => FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: _progress.value,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(2),
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                        ),
                      );
                    }),
                  ),
                ),
                Positioned(
                  top: 20,
                  right: 6,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                if (_paused)
                  Positioned(
                    bottom: 22,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        'пауза',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11, letterSpacing: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slideBody(_StorySlide slide, int i) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 56, 28, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeSlideIn(
            key: ValueKey('eyebrow$i'),
            offsetY: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: slide.accent,
                    boxShadow: [BoxShadow(color: slide.accent, blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  slide.eyebrow,
                  style: TextStyle(
                    color: slide.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          FadeSlideIn(
            key: ValueKey('content$i'),
            delay: const Duration(milliseconds: 120),
            offsetY: 22,
            child: slide.content,
          ),
        ],
      ),
    );
  }

  Widget _bigNumberSlide({
    required String title,
    required double value,
    required Color color,
    bool showSign = false,
    String? subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.35),
        ),
        const SizedBox(height: 14),
        RollingNumber(
          value: value,
          duration: const Duration(milliseconds: 1400),
          formatter: (v) => showSign ? Fmt.signedMoney(v) : Fmt.money(v),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
            shadows: [BoxShadow(color: color.withOpacity(0.55), blurRadius: 26)],
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 18),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.4),
          ),
        ],
      ],
    );
  }

  Widget _topAssetSlide(String ticker, double concentration) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Больше всего в портфеле занимает',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 24),
        TickerAvatar(ticker: ticker, size: 92),
        const SizedBox(height: 18),
        Text(
          ticker,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.violet.withOpacity(0.18),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: AppColors.violet.withOpacity(0.45)),
          ),
          child: Text(
            '${concentration.toStringAsFixed(0)}% портфеля',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _riskSlide(String label, Color color, double concentration, double? xirr) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.14),
            boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 34)],
          ),
          child: Icon(
            concentration >= 50 ? Icons.warning_amber_rounded : Icons.shield_outlined,
            color: color,
            size: 46,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 23, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          'Топ-бумага занимает ${concentration.toStringAsFixed(0)}% портфеля',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        if (xirr != null) ...[
          const SizedBox(height: 26),
          Text(
            'ДОХОДНОСТЬ (XIRR)',
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 10.5, letterSpacing: 1.6),
          ),
          const SizedBox(height: 4),
          Text(
            '${xirr >= 0 ? "+" : ""}${xirr.toStringAsFixed(1)}% годовых',
            style: TextStyle(
              color: AppColors.pnl(xirr),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ],
    );
  }

  Widget _textSlide(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
    );
  }

  Widget _shareSlide() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.gold, AppColors.gold.withOpacity(0.35)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 32)],
          ),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 20),
        const Text(
          'Вот и всё на сегодня',
          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Загляните снова, когда портфель подрастёт',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () => Share.share(_shareText),
          icon: const Icon(Icons.ios_share_rounded, size: 18),
          label: const Text('Поделиться итогами'),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть', style: TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
