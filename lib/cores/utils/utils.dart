import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';

class Utils {
  // Generate random string
  static String generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(
          (DateTime.now().millisecondsSinceEpoch * 9301 + 49297) % chars.length,
        ),
      ),
    );
  }

  /// Convert DateTime or String to dd/MM/yyyy format
  static String formatToDDMMYYYY(dynamic value) {
    try {
      if (value is DateTime) {
        return DateFormat('dd/MM/yyyy').format(value);
      } else if (value is String) {
        DateTime parsed = DateTime.parse(value);
        return DateFormat('dd/MM/yyyy').format(parsed);
      } else {
        return value.toString();
      }
    } catch (e) {
      return value.toString(); // fallback if parsing fails
    }
  }

  // Define the gradient as a constant
  static LinearGradient commonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.fromRGBO(255, 255, 255, 0.5),
      Color.fromRGBO(255, 255, 255, 0.0),
    ],
  );

  // Show keyboard
  static void showKeyboard(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());
  }

  // Hide keyboard
  static void hideKeyboard(BuildContext context) {
    FocusScope.of(context).unfocus();
  }

  // Get screen size
  static Size getScreenSize(BuildContext context) {
    return MediaQuery.of(context).size;
  }

  // Check if device is tablet
  static bool isTablet(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.shortestSide >= 600;
  }

  // Get time ago string
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  // Calculate BMI
  static double calculateBMI(double weight, double height) {
    return weight / ((height / 100) * (height / 100));
  }

  // Get BMI category
  static String getBMICategory(double bmi) {
    if (bmi < 18.5) {
      return 'Underweight';
    } else if (bmi < 25) {
      return 'Normal';
    } else if (bmi < 30) {
      return 'Overweight';
    } else {
      return 'Obese';
    }
  }

  static Widget getSVG({
    required String path,
    double? height,
    double? width,
    Color? color,
    BoxFit fit = BoxFit.contain,
  }) {
    return SvgPicture.asset(
      path,
      height: height,
      width: width,
      color: color,
      fit: fit,
    );
  }

  // Debounce function
  static Timer? _debounceTimer;
  static void debounce(
    VoidCallback action, {
    Duration delay = const Duration(milliseconds: 500),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, action);
  }
}
