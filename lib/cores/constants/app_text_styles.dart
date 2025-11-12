import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Font families
String? workSansFamily = GoogleFonts.workSans().fontFamily;
String? plusJakartaFamily = GoogleFonts.plusJakartaSans().fontFamily;

/// WorkSans style helper
TextStyle workSansTextStyle({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
}) {
  return TextStyle(
    fontFamily: workSansFamily,
    color: color ?? AppClr.white,
    fontSize: fontSize ?? 14,
    fontWeight: fontWeight ?? FontWeight.normal,
    decoration: TextDecoration.none, // Ensure no underline
  );
}

/// PlusJakarta style helper
TextStyle plusJakartaTextStyle({
  Color? color,
  double? fontSize,
  FontWeight? fontWeight,
}) {
  return TextStyle(
    fontFamily: plusJakartaFamily,
    color: color ?? AppClr.black,
    fontSize: fontSize ?? 14,
    fontWeight: fontWeight ?? FontWeight.normal,
    decoration: TextDecoration.none, // Ensure no underline
  );
}

/// General text widget
Widget appText(
  String text, {
  TextStyle? style,
  TextAlign? align,
  int? maxLines,
}) => Text(
  text,
  style: style ?? plusJakartaTextStyle(), // Default to Plus Jakarta
  textAlign: align,
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
);

/// RichText widget with tappable span
Widget richText(
  String text, {
  TextStyle? style,
  String? richText,
  TextStyle? richTextStyle,
  void Function()? onTap,
}) => RichText(
  text: TextSpan(
    text: text,
    style: style ?? plusJakartaTextStyle(), // Default to Plus Jakarta
    children: [
      TextSpan(
        text: richText,
        style: richTextStyle ?? plusJakartaTextStyle(),
        recognizer: TapGestureRecognizer()..onTap = onTap,
      ),
    ],
  ),
);

/// Centralized text styles
class AppTextStyles {
  // Headlines (Plus Jakarta default)
  static TextStyle h1 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: AppClr.textPrimary,
  );

  static TextStyle h2 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: AppClr.textPrimary,
  );

  static TextStyle h3 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: AppClr.textPrimary,
  );

  static TextStyle h4 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppClr.textPrimary,
  );

  static TextStyle h5 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: AppClr.textPrimary,
  );

  static TextStyle h6 = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppClr.textPrimary,
  );

  // Body Text
  static TextStyle bodyLarge = TextStyle(
    fontFamily: workSansFamily, // Use WorkSans for body
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppClr.textPrimary,
  );

  static TextStyle bodyMedium = TextStyle(
    fontFamily: workSansFamily,
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: AppClr.textPrimary,
  );

  static TextStyle bodySmall = TextStyle(
    fontFamily: workSansFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppClr.textSecondary,
  );

  // Button Text (Plus Jakarta)
  static TextStyle buttonText = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppClr.white,
  );

  static TextStyle buttonTextSmall = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppClr.white,
  );

  // Caption
  static TextStyle caption = TextStyle(
    fontFamily: workSansFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppClr.textLight,
  );

  // Label
  static TextStyle label = TextStyle(
    fontFamily: plusJakartaFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppClr.textSecondary,
  );
}
