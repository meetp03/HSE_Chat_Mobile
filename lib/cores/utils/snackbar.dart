/*
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

*/
import 'package:flutter/material.dart';

enum SnackBarType { info, success, error }

void showCustomSnackBar(BuildContext context, String message, {SnackBarType type = SnackBarType.info, Duration? duration}) {
  final color = (type == SnackBarType.success)
      ? Colors.green[700]
      : (type == SnackBarType.error)
      ? Colors.red[700]
      : Colors.grey[900];

  final icon = (type == SnackBarType.success)
      ? Icons.check_circle
      : (type == SnackBarType.error)
      ? Icons.error
      : Icons.info;

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      // Auto-dismiss after duration
      Future.delayed(duration ?? const Duration(seconds: 3), () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(40),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                blurRadius: 20,
                color: Colors.black.withOpacity(0.1),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: color,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}