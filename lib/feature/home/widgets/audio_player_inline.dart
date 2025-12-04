
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:hec_chat/feature/home/model/message_model.dart';

class AudioPlayerInline extends StatefulWidget {
  final Message message;
  final Future<File?> Function(String url, String messageId) fetchAndCache;

  const AudioPlayerInline({
    super.key,
    required this.message,
    required this.fetchAndCache,
  });

  @override
  State<AudioPlayerInline> createState() => _AudioPlayerInlineState();
}

class _AudioPlayerInlineState extends State<AudioPlayerInline> {
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
      final url = widget.message.fileUrl;
      if (url == null || url.isEmpty) {
        setState(() {
          _error = 'Invalid audio URL';
          _isLoading = false;
        });
        return;
      }

      // Get cached file or download it
      final file = await widget.fetchAndCache(url, widget.message.id);
      if (file == null) {
        setState(() {
          _error = 'Failed to load audio';
          _isLoading = false;
        });
        return;
      }

      _player = AudioPlayer();
      await _player!.setFilePath(file.path);

      // Listen to player state
      _player!.playerStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _isPlaying = state.playing;
          });
        }
      });

      // Listen to duration
      _player!.durationStream.listen((duration) {
        if (mounted && duration != null) {
          setState(() {
            _duration = duration;
          });
        }
      });

      // Listen to position
      _player!.positionStream.listen((position) {
        if (mounted) {
          setState(() {
            _position = position;
          });
        }
      });

      // Auto-dispose when playback completes
      _player!.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _player?.seek(Duration.zero);
          _player?.pause();
        }
      });

      setState(() {
        _isLoading = false;
      });
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

  void _togglePlayPause() {
    if (_player == null) return;
    if (_isPlaying) {
      _player!.pause();
    } else {
      _player!.play();
    }
  }

  void _seek(double value) {
    if (_player == null) return;
    final position = Duration(milliseconds: value.toInt());
    _player!.seek(position);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Audio icon and title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.audiotrack,
                  size: 32,
                  color: Colors.blue,
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
                    Text(
                      widget.message.sender.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Progress slider
          Slider(
            value: _position.inMilliseconds.toDouble(),
            max: _duration.inMilliseconds.toDouble().clamp(1.0, double.infinity),
            onChanged: _seek,
            activeColor: Colors.blue,
            inactiveColor: Colors.grey[300],
          ),
          // Time labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Playback controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Skip backward 10s
              IconButton(
                icon: const Icon(Icons.replay_10),
                iconSize: 32,
                onPressed: () {
                  final newPos = _position - const Duration(seconds: 10);
                  _player?.seek(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),
              const SizedBox(width: 24),
              // Play/Pause button
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: 40,
                  onPressed: _togglePlayPause,
                ),
              ),
              const SizedBox(width: 24),
              // Skip forward 10s
              IconButton(
                icon: const Icon(Icons.forward_10),
                iconSize: 32,
                onPressed: () {
                  final newPos = _position + const Duration(seconds: 10);
                  _player?.seek(newPos > _duration ? _duration : newPos);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Speed control (optional)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Speed: ',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              ...[ 0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: InkWell(
                    onTap: () {
                      _player?.setSpeed(speed);
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (_player?.speed ?? 1.0) == speed
                            ? Colors.blue
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${speed}x',
                        style: TextStyle(
                          fontSize: 11,
                          color: (_player?.speed ?? 1.0) == speed
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}