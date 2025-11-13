import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';

typedef FetchAndCache = Future<File?> Function(String url, String messageId);

class AudioPlayerInline extends StatefulWidget {
  final Message message;
  final FetchAndCache fetchAndCache;
  const AudioPlayerInline({super.key, required this.message, required this.fetchAndCache});

  @override
  State<AudioPlayerInline> createState() => _AudioPlayerInlineState();
}

class _AudioPlayerInlineState extends State<AudioPlayerInline> {
  late final AudioPlayer _player;
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureAndPlay() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final url = widget.message.fileUrl ?? widget.message.fileName ?? '';
      final file = await widget.fetchAndCache(url, widget.message.id);
      if (file == null) throw Exception('File not available');
      await _player.setFilePath(file.path);
      await _player.play();
      setState(() {
        _playing = true;
      });
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          setState(() => _playing = false);
        }
      });
    } catch (e) {
      if (mounted) showCustomSnackBar(context, 'Playback failed: $e', type: SnackBarType.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_playing ? Icons.pause : Icons.play_arrow),
          onPressed: _ensureAndPlay,
        ),
        Flexible(child: Text(widget.message.fileName ?? 'Audio', overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
