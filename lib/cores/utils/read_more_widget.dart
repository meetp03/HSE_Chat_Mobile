 import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';

class ReadMoreHtml extends StatefulWidget {
  final String htmlContent;
  final int maxLines;
  final TextStyle? readMoreStyle;

  const ReadMoreHtml({
    Key? key,
    required this.htmlContent,
    this.maxLines = 6,
    this.readMoreStyle,
  }) : super(key: key);

  @override
  State<ReadMoreHtml> createState() => _ReadMoreHtmlState();
}

class _ReadMoreHtmlState extends State<ReadMoreHtml> {
  bool _isExpanded = false;
  bool _showReadMore = false;
  static const double _lineHeight = 22.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
  }

  @override
  void didUpdateWidget(ReadMoreHtml old) {
    super.didUpdateWidget(old);
    if (old.htmlContent != widget.htmlContent) {
      _isExpanded = false;
      _showReadMore = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkHeight());
    }
  }

  void _checkHeight() {
    if (!mounted) return;
    final height = context.size?.height ?? 0;
    final maxAllowed = _lineHeight * widget.maxLines + 150;

    if (height > maxAllowed) {
      setState(() => _showReadMore = true);
    }
  }

  void _openImage(String src) {
    late Uint8List bytes;

    if (src.startsWith('data:image')) {
      // Extract base64 part safely
      final commaIndex = src.indexOf(',');
      if (commaIndex == -1) return;
      final base64String = src.substring(commaIndex + 1);
      bytes = base64Decode(base64String);
    } else {
      // Network image - let Image.network handle it
      showDialog(
        context: context,
        builder: (_) => _buildImageDialog(Image.network(src, fit: BoxFit.contain)),
      );
      return;
    }

    // Use MemoryImage with error handling
    final image = Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error, color: Colors.white70, size: 48),
              SizedBox(height: 8),
              Text("Failed to load image", style: TextStyle(color: Colors.white70)),
            ],
          ),
        );
      },
    );

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => _buildImageDialog(image),
      );
    }
  }

  Widget _buildImageDialog(Widget imageWidget) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              maxScale: 4.0,
              child: imageWidget,
            ),
          ),
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 34),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = _lineHeight * widget.maxLines + 400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: _isExpanded ? double.infinity : maxHeight,
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: HtmlWidget(
              widget.htmlContent,
              textStyle: const TextStyle(fontSize: 14, height: 1.5),
              customStylesBuilder: (element) {
                if (element.localName == 'strong' || element.localName == 'b') {
                  return {'font-weight': 'bold'};
                }
                if (element.localName == 'ul') return {'padding-left': '30px', 'margin': '0'};
                if (element.localName == 'ol') return {'padding-left': '20px', 'margin': '0'};
                if (element.localName == 'li') return {'margin': '0', 'padding': '0'};
                if (element.localName == 'p' || element.localName == 'div') {
                  return {'margin': '0 0 4px 0', 'padding': '0'};
                }
                if (element.localName == 'figure') return {'margin': '8px 0'};
                return null;
              },
              onTapImage: (image) {
                final src = image.sources.first.url;
                if (src.isNotEmpty) {
                  _openImage(src);
                }
              },
            ),
          ),
        ),

        if (_showReadMore)
          GestureDetector(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _isExpanded ? "Show less" : "Read more",
                style: widget.readMoreStyle ??
                    TextStyle(
                      color: AppClr.primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}