import 'package:flutter/material.dart';

enum SnackBarType { info, success, error }


void showCustomSnackBar(BuildContext context, String message, {SnackBarType type = SnackBarType.info, Duration? duration}) {
  final color = (type == SnackBarType.success)
      ? Colors.green[700]
      : (type == SnackBarType.error)
          ? Colors.red[700]
          : Colors.grey[900];

  final textColor = Colors.white;

  final snack = SnackBar(
    content: Row(
      children: [
        Expanded(child: Text(message, style: TextStyle(color: textColor))),
      ],
    ),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    duration: duration ?? const Duration(seconds: 3),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    margin: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
  );

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snack);
  } else {
    // fallback: if no ScaffoldMessenger found, try root messenger
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).showSnackBar(snack);
    });
  }
}

