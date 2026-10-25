import 'package:flutter/material.dart';

/// Подсказка снизу «Удалено · Вернуть» на 5 секунд — вместо окна
/// «Удалить?». Удаление случайным свайпом можно отменить.
void showUndoSnack(BuildContext context, String text, VoidCallback onUndo) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: 'Вернуть', onPressed: onUndo),
    ));
}
