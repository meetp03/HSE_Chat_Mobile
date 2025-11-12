import 'package:flutter/material.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/constants/app_text_styles.dart';
class CenteredDividerWithText extends StatelessWidget {
  final String text;
  final Color dividerColor;
  final double dividerThickness;
  final double dividerHeight;
  final TextStyle? textStyle;

  const CenteredDividerWithText({
    super.key,
    required this.text,
    this.dividerColor = AppClr.grey400,
    this.dividerThickness = 1.0,
    this.dividerHeight = 20.0,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Divider(
              color: dividerColor,
              thickness: dividerThickness,
              height: dividerHeight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              text,
              style:
                  textStyle ??
                  plusJakartaTextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: AppClr.textLight,
                  ),
            ),
          ),
          Expanded(
            child: Divider(
              color: dividerColor,
              thickness: dividerThickness,
              height: dividerHeight,
            ),
          ),
        ],
      ),
    );
  }
}
