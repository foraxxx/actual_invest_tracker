import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Оборачивает карточку в лёгкий 3D-наклон и металлизированный блик,
/// реагирующие на данные гироскопа устройства — при наклоне телефона
/// карточка слегка "поворачивается" в перспективе, а по её поверхности
/// смещается диагональная полоса света (голографический эффект).
///
/// На устройствах/платформах без гироскопа (или в эмуляторе без сенсора)
/// поток событий просто не приходит — тогда карточка остаётся статичной
/// без наклона, без ошибок и крашей.
class TiltShineCard extends StatefulWidget {
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  const TiltShineCard({super.key, required this.child, this.borderRadius = const BorderRadius.all(Radius.circular(24))});

  @override
  State<TiltShineCard> createState() => _TiltShineCardState();
}

class _TiltShineCardState extends State<TiltShineCard> with SingleTickerProviderStateMixin {
  StreamSubscription<GyroscopeEvent>? _sub;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Ограничение угла наклона: сырые данные гироскопа могут давать очень
  // большие углы, а нам нужен лёгкий, "премиальный" наклон, а не кувырок.
  static const _maxTilt = 0.16;

  // Целевые углы, накапливаемые из потока гироскопа (может обновляться
  // рывками, с непостоянной частотой).
  double _targetX = 0;
  double _targetY = 0;

  // Фактически отображаемые углы — на каждом кадре отрисовки плавно
  // "догоняют" целевые с экспоненциальным сглаживанием, независимым от
  // частоты кадров и от частоты событий сенсора. Это и даёт плавность:
  // карточка больше не дёргается вслед за каждым отдельным отсчётом
  // гироскопа, а тянется к цели с постоянной, кадро-независимой скоростью.
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    try {
      _sub = gyroscopeEventStream().listen(
        (event) {
          // Интегрируем скорость вращения в затухающую цель наклона —
          // простая, но достаточно живая имитация без полноценного
          // фьюжна с акселерометром. Сама отрисовка сглаживается отдельно
          // в _onTick, поэтому здесь setState не нужен. Меньший коэффициент
          // усиления и более сильное затухание цели убирают дрожание от
          // шумных показаний гироскопа ещё до того, как они попадут в
          // покадровую интерполяцию.
          _targetX = (_targetX * 0.94 + event.y * 0.035).clamp(-_maxTilt, _maxTilt);
          _targetY = (_targetY * 0.94 + event.x * 0.035).clamp(-_maxTilt, _maxTilt);
        },
        onError: (_) {
          // сенсор недоступен на этой платформе/устройстве — просто не наклоняем
        },
        cancelOnError: true,
      );
    } catch (_) {
      // пакет/платформа не поддерживает гироскоп — карточка остаётся плоской
    }
  }

  void _onTick(Duration elapsed) {
    final dtMs = (elapsed - _lastTick).inMilliseconds;
    _lastTick = elapsed;
    // Пропускаем первый кадр (dt от нуля) и аномально большие паузы
    // (например, после сворачивания приложения).
    if (!mounted || dtMs <= 0 || dtMs > 200) return;

    // Экспоненциальное сглаживание типа "критически демпфированной пружины":
    // на каждом кадре текущее значение подтягивается к целевому на долю
    // расстояния, зависящую от прошедшего времени — плавно на любом FPS.
    // Большая постоянная времени (170 мс) даёт максимально мягкий, без
    // единого рывка, ход карточки за целью.
    final t = 1 - math.exp(-dtMs / 170.0);
    final newX = _tiltX + (_targetX - _tiltX) * t;
    final newY = _tiltY + (_targetY - _tiltY) * t;
    if ((newX - _tiltX).abs() > 0.0002 || (newY - _tiltY).abs() > 0.0002) {
      setState(() {
        _tiltX = newX;
        _tiltY = newY;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0016)
      ..rotateX(_tiltY)
      ..rotateY(_tiltX);

    return Transform(
      alignment: Alignment.center,
      transform: matrix,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Stack(
          children: [
            widget.child,
            IgnorePointer(
              child: Align(
                alignment: Alignment(_tiltX * 10, _tiltY * 10 - 0.4),
                child: Transform.rotate(
                  angle: math.pi / 4,
                  child: Container(
                    width: 260,
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0),
                          Colors.white.withOpacity(0.10),
                          Colors.white.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
