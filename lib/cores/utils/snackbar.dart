import 'package:flutter/material.dart';

enum SnackBarType { info, success, error }

void showCustomSnackBar(
    BuildContext context,
    String message, {
      SnackBarType type = SnackBarType.info,
      Duration? duration,
    }) {
  // ✅ Check if context is still valid before showing dialog
  if (!context.mounted) {
    print('⚠️ Cannot show snackbar: context is not mounted');
    return;
  }

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
    builder: (dialogContext) {
      // ✅ Auto-dismiss with proper context checking
      Future.delayed(duration ?? const Duration(seconds: 3), () {
        // Use dialogContext (from builder) instead of outer context
        // This context is tied to the dialog's lifecycle
        if (dialogContext.mounted && Navigator.of(dialogContext).canPop()) {
          Navigator.of(dialogContext).pop();
        }
      });

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(dialogContext).size.height * 0.8,
            maxWidth: MediaQuery.of(dialogContext).size.width * 0.8,
          ),
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
          child: SingleChildScrollView(
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
        ),
      );
    },
  );
}