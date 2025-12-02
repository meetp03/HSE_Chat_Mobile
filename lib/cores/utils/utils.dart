import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:intl/intl.dart';

class Utils {
  static String getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return (parts[0][0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }

  /// Format UTC time to local time with date comparison
  static String formatConversationTime(DateTime utcTime) {
    try {
      // Convert to local time
      final localTime = utcTime.toLocal();

      // Format for display
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final messageDay = DateTime(localTime.year, localTime.month, localTime.day);

      // Format time based on date
      final timeFormat = DateFormat('h:mm a'); // e.g., 11:00 AM

      if (messageDay == today) {
        return timeFormat.format(localTime); // Show time only for today
      } else if (messageDay == yesterday) {
        return 'Yesterday ${timeFormat.format(localTime)}';
      } else if (now.difference(localTime).inDays < 7) {
        final dayFormat = DateFormat('EEE'); // Mon, Tue, etc.
        return '${dayFormat.format(localTime)} ${timeFormat.format(localTime)}';
      } else {
        final dateFormat = DateFormat('MMM d'); // Dec 1
        return '${dateFormat.format(localTime)} ${timeFormat.format(localTime)}';
      }
    } catch (e) {
      print('Error formatting conversation time: $e');
      return '';
    }
  }

  /// Format UTC time to simple time (just hours and minutes)
  static String formatTimeOnly(DateTime utcTime) {
    try {
      final localTime = utcTime.toLocal();
      return DateFormat('h:mm a').format(localTime); // 11:00 AM
    } catch (e) {
      print('Error formatting time only: $e');
      return '';
    }
  }

  /// Format UTC time to relative time (e.g., "2 hours ago")
  static String formatRelativeTime(DateTime utcTime) {
    try {
      final localTime = utcTime.toLocal();
      final now = DateTime.now();
      final difference = now.difference(localTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return DateFormat('MMM d').format(localTime);
      }
    } catch (e) {
      print('Error formatting relative time: $e');
      return '';
    }
  }

  /// Parse UTC date string to DateTime object with robust error handling
  static DateTime parseUtcDate(dynamic value) {
    try {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is int) {
        // Heuristic: if it's > 10^12 it's milliseconds, else seconds
        if (value > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(value);
        }
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is String) {
        // Try parsing directly
        DateTime? parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;

        // Try common date formats
        final formats = [
          'yyyy-MM-dd HH:mm:ss',
          'yyyy-MM-ddTHH:mm:ss',
          'yyyy-MM-dd',
          'dd-MM-yyyy HH:mm:ss',
          'MM/dd/yyyy HH:mm:ss',
        ];

        for (final format in formats) {
          try {
            final dateFormat = DateFormat(format);
            return dateFormat.parse(value);
          } catch (_) {}
        }

        // Try parsing as int string
        final maybeInt = int.tryParse(value);
        if (maybeInt != null) return parseUtcDate(maybeInt);
      }
      return DateTime.now();
    } catch (e) {
      print('Error parsing UTC date: $e');
      return DateTime.now();
    }
  }

  /// Get debug info for timezone debugging
  static String getDebugTimeInfo(DateTime utcTime) {
    try {
      final local = utcTime.toLocal();
      final utc = utcTime.toUtc();

      return '''
Original UTC: ${utcTime.toIso8601String()}
Local Time: ${local.toIso8601String()}
UTC Time: ${utc.toIso8601String()}
Formatted Local: ${DateFormat('h:mm a').format(local)}
Timezone Offset: ${utcTime.timeZoneOffset}
Chat Time: ${formatTimeOnly(utcTime)}
  ''';
    } catch (e) {
      return 'Error getting time info: $e';
    }
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

 }