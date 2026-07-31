/// Локальное расписание фондового рынка Мосбиржи.
///
/// Оно используется только как энергосберегающий предохранитель для частых
/// запросов котировок. Ручное обновление всегда остаётся доступным, а редкие
/// справочные запросы (купоны, дивиденды и параметры бумаг) живут отдельно.
class MoexTradingScheduleService {
  MoexTradingScheduleService._();

  static const _moscowOffset = Duration(hours: 3);
  static const _openMinute = 6 * 60 + 50;
  static const _closeMinute = 23 * 60 + 50;
  static const _finalRefreshMinute = 5; // 00:05 — с учётом задержки ISS.

  static DateTime moscowNow([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().add(_moscowOffset);

  static bool isTradingSession([DateTime? now]) {
    final msk = moscowNow(now);
    if (!_isWeekday(msk)) return false;
    final minute = msk.hour * 60 + msk.minute;
    return minute >= _openMinute && minute < _closeMinute;
  }

  /// После завершения вечерней сессии делаем ровно одно позднее обновление,
  /// чтобы забрать финальные бесплатные котировки с задержкой ISS.
  static bool needsFinalRefresh(DateTime? lastSync, [DateTime? now]) {
    final msk = moscowNow(now);
    if (msk.hour != 0 || msk.minute < _finalRefreshMinute) return false;
    final previousDay = msk.subtract(const Duration(days: 1));
    if (!_isWeekday(previousDay)) return false;
    if (lastSync == null) return true;

    final lastMsk = moscowNow(lastSync);
    final finalBoundary = DateTime.utc(msk.year, msk.month, msk.day, 0, _finalRefreshMinute);
    return lastMsk.isBefore(finalBoundary);
  }

  /// Задержка до следующего полезного автоматического пробуждения таймера.
  static Duration nextAutomaticDelay(int openIntervalSeconds, [DateTime? now]) {
    final msk = moscowNow(now);
    if (isTradingSession(now)) return Duration(seconds: openIntervalSeconds);

    final finalToday = DateTime.utc(msk.year, msk.month, msk.day, 0, _finalRefreshMinute);
    if (msk.isBefore(finalToday)) return finalToday.difference(msk);

    final minute = msk.hour * 60 + msk.minute;
    if (_isWeekday(msk) && minute >= _closeMinute) {
      final finalAfterClose = DateTime.utc(msk.year, msk.month, msk.day)
          .add(const Duration(days: 1, minutes: _finalRefreshMinute));
      return finalAfterClose.difference(msk);
    }

    var day = DateTime.utc(msk.year, msk.month, msk.day);
    if (minute >= _openMinute) {
      day = day.add(const Duration(days: 1));
    }
    while (!_isWeekday(day)) {
      day = day.add(const Duration(days: 1));
    }
    final nextOpen = day.add(const Duration(minutes: _openMinute));
    return nextOpen.difference(msk);
  }

  static String statusLabel([DateTime? now]) =>
      isTradingSession(now) ? 'Торги идут' : 'Биржа закрыта';

  static bool _isWeekday(DateTime date) =>
      date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
}
