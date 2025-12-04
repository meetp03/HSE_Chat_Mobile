 import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../model/message_model.dart';


class AudioPlayerInlineLocal extends StatefulWidget {
  final Message message;
  final String localPath;

  const AudioPlayerInlineLocal({
    super.key,
    required this.message,
    required this.localPath,
  });

  @override
  State<AudioPlayerInlineLocal> createState() => _AudioPlayerInlineLocalState();
}

class _AudioPlayerInlineLocalState extends State<AudioPlayerInlineLocal> {
  AudioPlayer? _player;
  bool _isLoading = true;
  String? _error;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      _player = AudioPlayer();
      await _player!.setFilePath(widget.localPath);

      _player!.playerStateStream.listen((state) {
        if (mounted) setState(() => _isPlaying = state.playing);
      });

      _player!.durationStream.listen((duration) {
        if (mounted && duration != null) setState(() => _duration = duration);
      });

      _player!.positionStream.listen((position) {
        if (mounted) setState(() => _position = position);
      });

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Error loading audio: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.audiotrack,
                  size: 32,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.message.fileName ?? 'Audio',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Playing from local file',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Slider(
            value: _position.inMilliseconds.toDouble(),
            max: _duration.inMilliseconds.toDouble().clamp(
              1.0,
              double.infinity,
            ),
            onChanged: (val) {
              _player?.seek(Duration(milliseconds: val.toInt()));
            },
            activeColor: Colors.green,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _formatDuration(_duration),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              iconSize: 40,
              onPressed: () {
                if (_isPlaying) {
                  _player!.pause();
                } else {
                  _player!.play();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
