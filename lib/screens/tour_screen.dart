import 'package:flutter/material.dart';
import '../design/motion.dart';
import '../design/surfaces.dart';
import '../design/tokens.dart';
import '../services/tour_service.dart';

class _TourStep {
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  const _TourStep({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
  });
}

/// Обучение: короткий тур по приложению. Показывается один раз при первом
/// запуске, дальше — только по кнопке в настройках. Пропустить можно на любом
/// шаге: отметка о прохождении ставится в обоих случаях, чтобы тур не лез
/// снова при каждом старте.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key});

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  final _controller = PageController();
  int _index = 0;

  static const _steps = <_TourStep>[
    _TourStep(
      icon: Icons.account_balance_wallet_outlined,
      color: AppColors.cyan,
      title: 'Портфели',
      text: 'Стартовый экран — список портфелей. Внутри каждого своя история сделок, '
          'выплат и планов: брокерский счёт и ИИС удобно вести отдельно. Портфель можно '
          'закрыть — он останется в истории, но перестанет попадать в общую сводку.',
    ),
    _TourStep(
      icon: Icons.donut_large_outlined,
      color: AppColors.violet,
      title: 'Вкладка «Портфель»',
      text: 'Сверху — стоимость бумаг и прибыль. Ниже плитки показателей, состав портфеля '
          'с долями каждой бумаги и две диаграммы: по секторам и по бумагам. Тап по позиции '
          'открывает карточку бумаги.',
    ),
    _TourStep(
      icon: Icons.savings_outlined,
      color: AppColors.gold,
      title: 'Откуда берётся «Вложено своих»',
      text: 'Пополнения счёта записывать не нужно — приложение считает их само. Оно идёт по '
          'сделкам по датам и держит баланс: если на покупку денег не хватило, недостающая '
          'сумма и есть пополнение. Если Вы продали бумаги или получили дивиденды, а затем купили новые — '
          'вложено не вырастет, деньги остались внутри портфеля.',
    ),
    _TourStep(
      icon: Icons.north_east_rounded,
      color: AppColors.warning,
      title: 'Вывод денег — вручную',
      text: 'Автоматически вывод определить нельзя: деньги, лежащие на счёте, ничем не '
          'отличаются от снятых. Поэтому, если Вы сняли деньги у брокера, запишите это в карточке '
          'счёта — нажмите «Свободные деньги» на главной. Иначе следующая покупка спишется '
          'с денег, которых уже нет.',
    ),
    _TourStep(
      icon: Icons.show_chart_rounded,
      color: AppColors.positive,
      title: 'Вкладка «Биржа»',
      text: 'Все бумаги Мосбиржи с котировками, поиск и фильтры по типу. Здесь же курсы валют '
          'и графики индекса и валют за любой период. Тап по бумаге открывает её карточку — '
          'купить или продать можно прямо оттуда, даже если бумаги у Вас нет.',
    ),
    _TourStep(
      icon: Icons.cloud_download_outlined,
      color: AppColors.info,
      title: 'Онлайн-данные',
      text: 'По умолчанию приложение полностью офлайновое. Включите загрузку с биржи в разделе '
          '«Ещё» — появятся котировки, курсы валют, отрасли и логотипы бумаг. Обновление идёт, '
          'пока приложение открыто: во время торгов обновляются цены, а после закрытия загружаются '
          'последние значения и исторические графики. Биржа отдаёт данные с небольшой задержкой.',
    ),
    _TourStep(
      icon: Icons.swap_horiz_rounded,
      color: AppColors.cyan,
      title: 'Сделки, доход и планы',
      text: 'На вкладке «Сделки» записывается покупка или продажа — можно сразу несколько бумаг '
          'одной датой. «Доход» — полученные дивиденды и купоны. «Планы» — что и когда Вы собираетесь '
          'купить, с прогрессом по каждой цели.',
    ),
    _TourStep(
      icon: Icons.query_stats_rounded,
      color: AppColors.positive,
      title: 'Доходность за период',
      text: 'На странице портфеля можно выбрать период и увидеть прибыль, чистое вложение и выплаты. '
          'XIRR учитывает даты пополнений, а TWR показывает результат стратегии без их влияния.',
    ),
    _TourStep(
      icon: Icons.auto_graph_rounded,
      color: AppColors.violet,
      title: 'Прогноз выплат',
      text: 'Прогноз включает дивиденды и все известные будущие купоны за следующие 12 полных месяцев. '
          'Нажмите на карточку прогноза, чтобы открыть разбивку по месяцам.',
    ),
    _TourStep(
      icon: Icons.touch_app_outlined,
      color: AppColors.cyan,
      title: 'Графики котировок',
      text: 'Графики бумаг, индекса и валют можно листать в прошлое. Одним пальцем перемещайте период, '
          'а двумя выберите две точки, чтобы сравнить изменение цены между ними.',
    ),
    _TourStep(
      icon: Icons.file_download_outlined,
      color: AppColors.info,
      title: 'Импорт отчёта брокера',
      text: 'В разделе «Данные» можно импортировать брокерский отчёт. Перед сохранением приложение '
          'покажет найденные сделки, выплаты и строки, для которых требуется указать тикер.',
    ),
    _TourStep(
      icon: Icons.save_outlined,
      color: AppColors.violet,
      title: 'Резервные копии',
      text: 'Все данные лежат только на телефоне, поэтому бэкап — единственная страховка. '
          'В разделе «Данные» можно выгрузить всё в файл или включить автосохранение в папку: '
          'тогда копия обновляется сама при каждом изменении. В бэкап попадают и настройки.',
    ),
  ];

  Future<void> _finish() async {
    await TourService.setCompleted(true);
    if (mounted) Navigator.pop(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final isLast = _index == _steps.length - 1;

    return Scaffold(
      body: AuroraBackground(
        profit: 1,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _finish,
                  child: Text('Пропустить', style: TextStyle(color: context.dim)),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _steps.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _page(_steps[i], i),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_steps.length, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: AppDuration.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: active ? step.color : context.dim.withOpacity(0.35),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                child: Row(
                  children: [
                    if (_index > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _controller.previousPage(
                            duration: AppDuration.normal,
                            curve: AppCurves.enter,
                          ),
                          child: const Text('Назад'),
                        ),
                      ),
                    if (_index > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: GradientButton(
                        label: isLast ? 'Всё понятно' : 'Дальше',
                        icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                        onPressed: () {
                          if (isLast) {
                            _finish();
                          } else {
                            _controller.nextPage(
                              duration: AppDuration.normal,
                              curve: AppCurves.enter,
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _page(_TourStep step, int i) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FadeSlideIn(
            key: ValueKey('icon$i'),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [step.color.withOpacity(0.35), step.color.withOpacity(0.10)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(color: step.color.withOpacity(0.3), blurRadius: 30)],
              ),
              child: Icon(step.icon, size: 44, color: step.color),
            ),
          ),
          const SizedBox(height: 28),
          FadeSlideIn(
            key: ValueKey('title$i'),
            delay: const Duration(milliseconds: 90),
            child: Text(
              step.title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            key: ValueKey('text$i'),
            delay: const Duration(milliseconds: 160),
            child: Text(
              step.text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.55, color: context.dim),
            ),
          ),
        ],
      ),
    );
  }
}
