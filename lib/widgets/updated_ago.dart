import 'dart:async';

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../services/moex_sync_service.dart';
import '../services/online_settings_service.dart';

/// «Обновлено 2 мин назад» — когда последний раз пришли котировки.
///
/// Подпись сама пересчитывается раз в полминуты, поэтому «только что» через
/// пять минут превращается в «5 мин назад» без перерисовки всего экрана.
/// Во время обновления пишет «обновляю…».
class UpdatedAgo extends StatefulWidget {
  /// Что дописать после времени, например « · торги идут».
  final String Function()? suffix;
  final TextStyle? style;

  const UpdatedAgo({super.key, this.suffix, this.style});

  /// Текст для момента [at] относительно [now]. Отдельно — чтобы проверить
  /// тестом без часов и виджетов.
  static String label(DateTime? at, DateTime now) {
    if (at == null) return 'ещё не обновлялось';
    final diff = now.difference(at);
    if (diff.inSeconds < 60) return 'обновлено только что';
    if (diff.inMinutes < 60) return 'обновлено ${diff.inMinutes} мин назад';
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return 'обновлено в $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return 'обновлено вчера в $hh:$mm';
    final dd = at.day.toString().padLeft(2, '0');
    final mo = at.month.toString().padLeft(2, '0');
    return 'обновлено $dd.$mo в $hh:$mm';
  }

  @override
  State<UpdatedAgo> createState() => _UpdatedAgoState();
}

class _UpdatedAgoState extends State<UpdatedAgo> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: OnlineSettingsService.version,
      builder: (context, _, __) => ValueListenableBuilder<bool>(
        valueListenable: MoexSyncService.refreshing,
        builder: (context, refreshing, __) {
          final style = widget.style ?? TextStyle(fontSize: 12, color: context.dim);
          final text = refreshing
              ? 'обновляю…'
              : UpdatedAgo.label(OnlineSettingsService.lastSyncAt, DateTime.now());
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (refreshing) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: context.accent),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  '$text${widget.suffix?.call() ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
