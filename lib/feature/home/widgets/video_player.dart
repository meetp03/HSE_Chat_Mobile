// Small helper widget to play a cached video file using Chewie.
import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerViewer extends StatefulWidget {
  final String url;
  final String messageId;
  const VideoPlayerViewer({
    super.key,
    required this.url,
    required this.messageId,
  });

  @override
  State<VideoPlayerViewer> createState() => _VideoPlayerViewerState();
}

class _VideoPlayerViewerState extends State<VideoPlayerViewer> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final info = await DefaultCacheManager().getFileFromCache(widget.url);
      final file = info?.file;
      if (file != null) {
        _controller = VideoPlayerController.file(file);
        await _controller!.initialize();
        _chewie = ChewieController(
          videoPlayerController: _controller!,
          autoPlay: true,
          looping: false,
        );
        setState(() {});
      }
    } catch (e) {
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

