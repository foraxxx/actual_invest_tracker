/// Рабочие и нерабочие дни в России — для дат зарплаты и аванса.
///
/// По Трудовому кодексу (ст. 136), если день выплаты выпадает на выходной или
/// нерабочий праздник, деньги платят накануне — в ближайший рабочий день
/// раньше.
///
/// Учтены выходные, все государственные праздники и правило «праздник в
/// выходной — следующий понедельник свободен». Переносы выходных, которые
/// правительство объявляет каждый год отдельно, заранее не известны: если
/// день не совпал, его можно поправить вручную в конкретном месяце.
class WorkCalendar {
  WorkCalendar._();

  /// Праздники, кроме новогодних каникул: (месяц, день).
  static const _holidays = <(int, int)>[(2, 23), (3, 8), (5, 1), (5, 9), (6, 12), (11, 4)];

  static bool _weekend(DateTime d) => d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  static bool isHoliday(DateTime d) {
    // Новогодние каникулы — с 1 по 8 января; 31 декабря в последние годы
    // тоже выходной.
    if (d.month == 1 && d.day <= 8) return true;
    if (d.month == 12 && d.day == 31) return true;
    for (final (m, day) in _holidays) {
      if (d.month == m && d.day == day) return true;
      // Праздник в субботу или воскресенье — выходным становится понедельник.
      final h = DateTime(d.year, m, day);
      if (_weekend(h) && d.weekday == DateTime.monday) {
        final diff = DateTime(d.year, d.month, d.day).difference(h).inDays;
        if (diff == 1 || diff == 2) return true;
      }
    }
    return false;
  }

  static bool isWorkDay(DateTime d) => !_weekend(d) && !isHoliday(d);

  /// День выплаты: [d] или ближайший к нему рабочий день того же месяца.
  static DateTime payDay(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    if (isWorkDay(day)) return day;
    // Ближайший рабочий день этого же месяца; при равном расстоянии — более
    // ранний. Суббота → пятница, воскресенье → понедельник, а если понедельник
    // уже в следующем месяце — пятница.
    for (var k = 1; k <= 31; k++) {
      final before = DateTime(d.year, d.month, d.day - k);
      if (before.month == d.month && isWorkDay(before)) return before;
      final after = DateTime(d.year, d.month, d.day + k);
      if (after.month == d.month && isWorkDay(after)) return after;
    }
    return day;
  }

}
