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

  /// Ближайший рабочий день не позже [d]. Если до него пришлось бы уйти в
  /// прошлый месяц — ближайший рабочий день после, в том же месяце.
  static DateTime payDay(DateTime d) {
    var x = DateTime(d.year, d.month, d.day);
    while (!isWorkDay(x)) {
      x = DateTime(x.year, x.month, x.day - 1);
    }
    if (x.month == d.month) return x;
    x = DateTime(d.year, d.month, d.day);
    while (!isWorkDay(x) && x.month == d.month) {
      x = DateTime(x.year, x.month, x.day + 1);
    }
    return x.month == d.month ? x : DateTime(d.year, d.month, d.day);
  }
}
