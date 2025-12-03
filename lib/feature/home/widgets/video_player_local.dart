// NEW: Local video player widget
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerViewerLocal extends StatefulWidget {
  final String localPath;
  final String messageId;

  const VideoPlayerViewerLocal({
    Key? key,
    required this.localPath,
    required this.messageId,
  }) : super(key: key);

  @override
  State<VideoPlayerViewerLocal> createState() => _VideoPlayerViewerLocalState();
}

class _VideoPlayerViewerLocalState extends State<VideoPlayerViewerLocal> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _controller = VideoPlayerController.file(File(widget.localPath));
      await _controller!.initialize();
      _chewie = ChewieController(
        videoPlayerController: _controller!,
        autoPlay: true,
        looping: false,
      );
      setState(() {});
    } catch (e) {
      debugPrint('⚠️ Local video init failed: $e');
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chewie == null ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Chewie(controller: _chewie!);
  }
}

