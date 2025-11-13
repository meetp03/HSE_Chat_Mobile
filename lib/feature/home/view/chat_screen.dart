import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/cores/utils/utils.dart';
import 'package:hsc_chat/feature/home/bloc/chat_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/chat_state.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:hsc_chat/feature/home/widgets/user_info_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:hsc_chat/cores/utils/file_validation.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:pdfx/pdfx.dart';
import 'package:dio/dio.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hsc_chat/cores/utils/gallery_helper.dart';
import 'package:hsc_chat/feature/home/view/_audio_player_inline.dart';

// Use MessageKind and kind() defined in the model (message_model.dart)

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;
  final bool isGroup;

  const ChatScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.isGroup = false,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Timer? _typingTimer;
  bool _isTyping = false;
  String? _attachedFilePath;
  int? _attachedFileType; // 1=image,2=video,4=file
  // Download/caching & playback helpers
  final Map<String, CancelToken> _downloadTokens = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, AudioPlayer> _audioPlayers = {};
  // Memoization for in-flight fetches / thumbnails to avoid duplicate downloads
  final Map<String, Future<File?>> _fetchFutures = {};
  final Map<String, Future<File?>> _thumbFutures = {};
  // Optional: last reported progress to reduce setState churn
  final Map<String, double> _lastReportedProgress = {};

  // Load-more / scroll preservation helpers
  bool _pendingLoadMore = false;
  double? _prevMaxScrollExtent;
  double? _prevScrollOffset;
  // When true we recently restored viewport after a load-more and should
  // suppress the usual auto-scroll-to-bottom triggered by ChatLoaded emits.
  bool _restoringAfterLoadMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _scrollController.addListener(_onScroll);
  }

  // NEW: scroll to bottom **every time the cubit emits a new list**
  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final target = pos.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _initializeChat() {
    final currentUserId = SharedPreferencesHelper.getCurrentUserId();
    print('🚀 Initializing chat with user: ${widget.userId}');

    context.read<ChatCubit>().loadConversations(
      currentUserId,
      widget.userId,
      widget.isGroup,
    );
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    const threshold = 100.0;
    // With normal ListView (oldest->newest), older messages are above. Load
    // more when scrolled near the top (pixels <= threshold).
    if (pos.pixels <= threshold) {
      final state = context.read<ChatCubit>().state;
      if (state is ChatLoaded && state.hasMore && !state.isLoadingMore) {
        // Capture offsets so we can restore scroll position after prepend
        try {
          _pendingLoadMore = true;
          _prevMaxScrollExtent = _scrollController.position.maxScrollExtent;
          _prevScrollOffset = _scrollController.offset;
        } catch (_) {
          _prevMaxScrollExtent = null;
          _prevScrollOffset = null;
        }
        context.read<ChatCubit>().loadMoreMessages();
      }
    }
  }

  Future<void> _sendMessage() async {
    final caption = _messageController.text.trim();

    final hasFile = _attachedFilePath != null && _attachedFilePath!.isNotEmpty;
    final hasText = caption.isNotEmpty;

    if (hasFile && hasText) {
      // Shouldn't happen due to UI constraints, but guard anyway
      showCustomSnackBar(
        context,
        'Cannot send text and file together.',
        type: SnackBarType.error,
      );
      return;
    }

    if (!hasFile && !hasText) return;

    if (hasFile) {
      final path = _attachedFilePath!;
      print('📤 Sending file: $path');
      // Double-check validation right before send to avoid calling API with invalid files
      try {
        final f = File(path);
        if (!await f.exists()) {
          showCustomSnackBar(
            context,
            'Selected file not found.',
            type: SnackBarType.error,
          );
          return;
        }
        // infer category
        final ext = p.extension(path).toLowerCase();
        FileCategory category = FileCategory.GENERIC;
        if ([
          '.png',
          '.jpg',
          '.jpeg',
          '.gif',
          '.webp',
          '.bmp',
          '.heic',
          '.heif',
        ].contains(ext))
          category = FileCategory.IMAGE;
        else if ([
          '.mp4',
          '.mov',
          '.mkv',
          '.webm',
          '.avi',
          '.3gp',
        ].contains(ext))
          category = FileCategory.VIDEO;
        else if (ValidationRules.audioExt.contains(ext))
          category = FileCategory.AUDIO;
        else if (ValidationRules.docExt.contains(ext))
          category = FileCategory.DOCUMENT;

        final validation = await validateFileByCategory(f, category);
        if (!validation.isValid) {
          showCustomSnackBar(
            context,
            validation.message,
            type: SnackBarType.error,
          );
          return;
        }
      } catch (e) {
        print('⚠️ Validation check failed before send: $e');
        showCustomSnackBar(
          context,
          'Failed to validate file before upload.',
          type: SnackBarType.error,
        );
        return;
      }
      if (kDebugMode)
        print(
          '✅ Local validation OK — calling ChatCubit.sendMessage for file: $path',
        );
      final error = await context.read<ChatCubit>().sendMessage(
        message: '',
        filePath: path,
      );
      // clear attachment after sending attempt
      setState(() {
        _attachedFilePath = null;
        _attachedFileType = null;
      });
      if (error != null) {
        showCustomSnackBar(context, error, type: SnackBarType.error);
      }
      _scrollToBottom();
      return;
    }

    // Text-only send
    final message = caption;
    print('📤 Sending message: $message');
    final error = await context.read<ChatCubit>().sendMessage(message: message);
    if (error != null) {
      // keep the typed text so user can retry/edit; show friendly error
      showCustomSnackBar(context, error, type: SnackBarType.error);
    } else {
      _messageController.clear();
      _scrollToBottom();
    }
  }

  Future<void> _openFilePicker() async {
    try {
      // Restrict picker to allowed extensions (images, video, documents) - explicitly exclude audio
      final allowedExt = <String>[
        // images
        'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif',
        // videos
        'mp4', 'mov', 'mkv', 'webm', 'avi', '3gp',
        // documents
        'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv',
      ];

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExt,
        allowMultiple: false,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.path == null) return;
      final path = file.path!;

      // Defensive check: if user somehow picked an audio file (some platforms allow typing extension), block it.
      final ext = p
          .extension(path)
          .toLowerCase()
          .replaceFirst('.', ''); // e.g. 'mp3'
      final audioExt = ValidationRules.audioExt
          .map((e) => e.replaceFirst('.', ''))
          .toList();
      if (audioExt.contains(ext)) {
        showCustomSnackBar(
          context,
          'Audio files are not supported here. Please select an image, video, or document.',
          type: SnackBarType.error,
        );
        return;
      }

      final lower = path.toLowerCase();
      final imageExt = [
        '.png',
        '.jpg',
        '.jpeg',
        '.gif',
        '.webp',
        '.bmp',
        '.heic',
        '.heif',
      ];
      final videoExt = ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'];
      int type = 4; // default generic file
      for (var e in imageExt) if (lower.endsWith(e)) type = 1;
      for (var e in videoExt) if (lower.endsWith(e)) type = 2;

      // Validate file using validation helpers
      final f = File(path);
      FileCategory category = FileCategory.GENERIC;
      if (type == 1)
        category = FileCategory.IMAGE;
      else if (type == 2)
        category = FileCategory.VIDEO;
      else {
        final ext = p.extension(path).toLowerCase();
        if (ValidationRules.docExt.contains(ext))
          category = FileCategory.DOCUMENT;
        else if (ValidationRules.audioExt.contains(ext))
          category = FileCategory.AUDIO;
      }

      final validation = await validateFileByCategory(f, category);
      if (!validation.isValid) {
        showCustomSnackBar(
          context,
          validation.message,
          type: SnackBarType.error,
        );
        return;
      }

      setState(() {
        _attachedFilePath = validation.file?.path ?? path;
        _attachedFileType = type;
      });
    } catch (e) {
      print('⚠️ Error picking file: $e');
    }
  }

  void _onTyping() {
    if (!_isTyping) {
      _isTyping = true;
      // Send typing indicator via socket
      // context.read<ChatCubit>().sendTypingIndicator(true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      // Send stop typing indicator
      // context.read<ChatCubit>().sendTypingIndicator(false);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Mark as read when app comes back to foreground
    if (state == AppLifecycleState.resumed) {
      context.read<ChatCubit>().markAsRead();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // First time the cubit is already ChatLoaded → scroll now
    final s = context.read<ChatCubit>().state;
    if (s is ChatLoaded && s.messages.isNotEmpty) {
      Future.microtask(() => _scrollToBottom(animate: false));
    }
  }

  @override
  void dispose() {
    print('🧹 Disposing chat screen');
    WidgetsBinding.instance.removeObserver(this);
    // Dispose audio players
    for (var p in _audioPlayers.values) {
      p.dispose();
    }
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return WillPopScope(
      onWillPop: () async {
        // When popping, return the latest message payload so the
        // conversation list can be updated without an API refresh.
        print('⬅️ Going back from chat');
        final state = context.read<ChatCubit>().state;
        // If we have messages, mark last message as read via ConversationCubit
        // so the HomeScreen gets an immediate local update (and socket will
        // broadcast to other clients). This avoids waiting for API roundtrip.
        if (state is ChatLoaded && state.messages.isNotEmpty) {
          final last = state.messages.last;
          try {
            context.read<ConversationCubit>().markMessageAsRead(
              last.id,
              widget.userId,
            );
          } catch (e) {
            print('⚠️ Failed to notify ConversationCubit about read: $e');
          }

          // Also forward the last message payload so conversation list shows
          // the latest message immediately even if HomeScreen reloads data.
          try {
            final payload = {
              'conversation': {
                '_id': last.id,
                'from_id': last.fromId,
                'to_id': last.toId,
                'message': last.message,
                'created_at': last.createdAt.toIso8601String(),
                'sender': {
                  'id': last.sender.id,
                  'name': last.sender.name,
                  'photo_url': last.sender.photoUrl,
                },
                'message_type': last.messageType,
                'file_url': last.fileUrl,
                'file_name': last.fileName,
                'group_id': widget.isGroup ? widget.userId : null,
              },
            };
            context.read<ConversationCubit>().processRawMessage(payload);
          } catch (e) {
            print(
              '⚠️ Failed to forward last message to ConversationCubit on pop: $e',
            );
          }
        }
        Navigator.pop(context, null);
        return false;
      },
      child: Scaffold(
        backgroundColor: AppClr.chatBackground,
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildMessagesList()),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppClr.primaryColor,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          // Trigger the same pop logic as WillPopScope
          final state = context.read<ChatCubit>().state;
          if (state is ChatLoaded && state.messages.isNotEmpty) {
            final last = state.messages.last;
            try {
              context.read<ConversationCubit>().markMessageAsRead(
                last.id,
                widget.userId,
              );
            } catch (e) {
              print('⚠️ Failed to notify ConversationCubit about read: $e');
            }
            try {
              final payload = {
                'conversation': {
                  '_id': last.id,
                  'from_id': last.fromId,
                  'to_id': last.toId,
                  'message': last.message,
                  'created_at': last.createdAt.toIso8601String(),
                  'sender': {
                    'id': last.sender.id,
                    'name': last.sender.name,
                    'photo_url': last.sender.photoUrl,
                  },
                  'message_type': last.messageType,
                  'file_url': last.fileUrl,
                  'file_name': last.fileName,
                  'group_id': widget.isGroup ? widget.userId : null,
                },
              };
              context.read<ConversationCubit>().processRawMessage(payload);
            } catch (e) {
              print(
                '⚠️ Failed to forward last message to ConversationCubit on back: $e',
              );
            }
          }
          Navigator.pop(context, null);
        },
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            backgroundImage: widget.userAvatar != null
                ? CachedNetworkImageProvider(widget.userAvatar!)
                : null,
            child: widget.userAvatar == null
                ? Text(
              Utils.getInitials(widget.userName),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                BlocBuilder<ChatCubit, ChatState>(
                  builder: (context, state) {
                    if (state is ChatLoaded) {
                      return Text(
                        widget.isGroup ? 'Group' : 'online',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.info_outline, color: Colors.white),
          onSelected: (value) {
            if (value == 'info') {
              _openUserInfo();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'info',
              child: Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 8),
                  Text('User Info'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
  void _openUserInfo() {
    // TODO: Replace with actual user data from your state/cubit
    final isCurrentlyBlocked = false; // Get this from your state management

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserInfoScreen(
          userId: widget.userId,
          userName: widget.userName,
          userAvatar: widget.userAvatar,
          userEmail: 'user@example.com', // TODO: Get actual user email
          isBlocked: isCurrentlyBlocked,
        ),
      ),
    );
  }
  Widget _buildMessagesList() {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        // Only act on ChatLoaded states
        if (state is! ChatLoaded) return;

        // If we had requested load-more (older messages) restore previous
        // viewport so the user remains looking at the same message.
        if (_pendingLoadMore) {
          // Wait for the new frame so ListView has the new children and
          // updated scroll metrics. We set _restoringAfterLoadMore to true
          // so that the subsequent ChatLoaded emit (with updated messages)
          // doesn't trigger an unwanted scroll-to-bottom.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scrollController.hasClients) {
              _pendingLoadMore = false;
              _restoringAfterLoadMore = false;
              return;
            }

            final newMax = _scrollController.position.maxScrollExtent;
            if (_prevMaxScrollExtent != null && _prevScrollOffset != null) {
              final delta = newMax - _prevMaxScrollExtent!;
              // Keep the user's viewport anchored by adding the delta to
              // previous offset. Use jumpTo to avoid animating unexpectedly.
              final target = (_prevScrollOffset! + delta).clamp(0.0, newMax);
              try {
                _scrollController.jumpTo(target);
              } catch (_) {
                // ignore - if jump fails just continue
              }
            }
            // Leave _restoringAfterLoadMore true until we've observed the
            // next non-loading state to suppress auto-scroll there as well.
            _pendingLoadMore = false;
            _prevMaxScrollExtent = null;
            _prevScrollOffset = null;
            _restoringAfterLoadMore = true;
          });

          return;
        }

        // If we're in the middle of requesting older messages, don't auto-scroll.
        if (state.isLoadingMore) return;

        // If we just restored the viewport for load-more, suppress the
        // automatic scroll-to-bottom for this emission so the user's
        // position remains stable. Clear the flag afterwards.
        if (_restoringAfterLoadMore) {
          _restoringAfterLoadMore = false;
          return;
        }

        // Normal new message arrival → scroll to bottom
        _scrollToBottom();
      },
      builder: (context, state) {
        if (state is ChatLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is ChatError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('Error: ${state.message}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initializeChat,
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (state is ChatLoaded) {
          final messages = state.messages;
          // UI-level dedupe: sometimes duplicates still arrive due to
          // server overlap; remove adjacent/global duplicates before
          // rendering to avoid duplicate bubbles.
          final visibleMessages = _uniqueMessages(messages);

          if (messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isGroup ? Icons.group : Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(color: Colors.grey[600], fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Send a message to start the conversation',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            );
          }

          // Normal chronological ListView: oldest at top, newest at bottom.
          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: visibleMessages.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              // Show loading indicator at top (index 0) when loading more
              if (state.isLoadingMore && index == 0) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              final messageIndex = state.isLoadingMore ? index - 1 : index;
              final msg = visibleMessages[messageIndex];
              return _buildMessageBubble(msg);
            },
          );
        }

        return const Center(child: Text('No messages'));
      },
    );
  }

  Widget _buildMessageBubble(Message message) {
    final kind = message.kind();

    // If it's a SYSTEM message render it as a standalone centered blue bubble
    if (kind == MessageKind.SYSTEM) {
      // Centered full-row system message styled as a purple pill with light opacity.
      final maxWidth = MediaQuery.of(context).size.width * 0.85;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppClr.primaryColor.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppClr.primaryColor.withValues(alpha: 0.3),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _parseMessage(message.message),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppClr.primaryColor,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final showAvatar = !message.isSentByMe && widget.isGroup;

    // Determine upload progress for temp messages
    int? uploadPct;
    final s = context.read<ChatCubit>().state;
    if (s is ChatLoaded) uploadPct = s.uploadProgress[message.id];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Incoming message avatar
          if (showAvatar) ...[
            CircleAvatar(
              radius: 12,
              backgroundColor: AppClr.primaryColor.withAlpha(
                (0.1 * 255).round(),
              ),
              backgroundImage: message.sender.photoUrl != null
                  ? CachedNetworkImageProvider(message.sender.photoUrl!)
                  : null,
              child: message.sender.photoUrl == null
                  ? Text(
                      message.sender.name[0].toUpperCase(),
                      style: const TextStyle(fontSize: 10),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],

          // Message bubble
          Flexible(
            child: Align(
              alignment: message.isSentByMe
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Limit message width to ~70% of screen width
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: message.isSentByMe
                        ? AppClr.sentMessageColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Builder(
                    builder: (ctx) {
                      final kind = message.kind();
                      final isMedia = kind != MessageKind.TEXT;

                      return Column(
                        crossAxisAlignment: message.isSentByMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          if (widget.isGroup && !message.isSentByMe) ...[
                            Text(
                              message.sender.name,
                              style: TextStyle(
                                color: AppClr.primaryColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],

                          if (message.replyMessage != null)
                            _buildReplyMessage(message.replyMessage!),

                          // Message content
                          GestureDetector(
                            onTap: () async {
                              final kind = message.kind();
                              final url = _buildMediaUrl(message);
                              if (kind == MessageKind.IMAGE) {
                                if (url != null && url.isNotEmpty) {
                                  // Show an in-app preview dialog with zoom/pan instead of launching external URL
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => Dialog(
                                      insetPadding: const EdgeInsets.all(8),
                                      backgroundColor: Colors.transparent,
                                      child: GestureDetector(
                                        onTap: () => Navigator.of(ctx).pop(),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Container(
                                            color: Colors.black,
                                            child: InteractiveViewer(
                                              panEnabled: true,
                                              minScale: 1.0,
                                              maxScale: 4.0,
                                              child: CachedNetworkImage(
                                                imageUrl: url,
                                                placeholder: (context, url) =>
                                                    Container(
                                                      width: double.infinity,
                                                      height: 300,
                                                      color: Colors.black12,
                                                      child: const Center(
                                                        child:
                                                            CircularProgressIndicator(),
                                                      ),
                                                    ),
                                                errorWidget:
                                                    (
                                                      context,
                                                      url,
                                                      error,
                                                    ) => Container(
                                                      width: double.infinity,
                                                      height: 300,
                                                      color: Colors.black12,
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } else if (kind == MessageKind.VIDEO) {
                                final url = _buildMediaUrl(message);
                                if (url != null && url.isNotEmpty) {
                                  // Open in-app video dialog
                                  await _openVideoDialog(url, message.id);
                                }
                              } else if (kind == MessageKind.AUDIO) {
                                // show inline player in bottom sheet
                                showModalBottomSheet(
                                  context: ctx,
                                  builder: (_) => Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: _audioPlayerWidget(message),
                                  ),
                                );
                              } else if (kind == MessageKind.FILE) {
                                if (url != null && url.isNotEmpty) {
                                  final ext = p.extension(url).toLowerCase();
                                  if (ext == '.pdf') {
                                    await _openPdfViewer(url, message.id);
                                  } else {
                                    try {
                                      final file = await _fetchAndCache(
                                        url,
                                        message.id,
                                      );
                                      if (file != null) {
                                        final uri = Uri.file(file.path);
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri);
                                        } else {
                                          showCustomSnackBar(
                                            context,
                                            'Cannot open file.',
                                            type: SnackBarType.error,
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      showCustomSnackBar(
                                        context,
                                        'Failed to open file: $e',
                                        type: SnackBarType.error,
                                      );
                                    }
                                  }
                                }
                              }
                            },
                            child: _buildMessageContent(message),
                          ),

                          if (isMedia)
                            const SizedBox(height: 6)
                          else
                            const SizedBox(height: 8),

                          // For TEXT messages, show text below
                          if (kind == MessageKind.TEXT) ...[
                            Text(
                              _parseMessage(message.message),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],

                          // Timestamp and status
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatTime(message.createdAt),
                                style: TextStyle(
                                  color: message.isSentByMe
                                      ? Colors.black54
                                      : Colors.grey[600],
                                  fontSize: 11,
                                ),
                              ),
                              if (uploadPct != null) ...[
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 60,
                                  child: LinearProgressIndicator(
                                    value: (uploadPct / 100),
                                    minHeight: 6,
                                  ),
                                ),
                              ],
                              if (message.isSentByMe) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  message.status == -1
                                      ? Icons.error_outline
                                      : (message.status == 1
                                            ? Icons.done_all
                                            : Icons.done),
                                  size: 14,
                                  color: message.status == -1
                                      ? Colors.red
                                      : (message.status == 1
                                            ? Colors.blue[600]
                                            : Colors.grey),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(Message message) {
    final kind = message.kind();

    if (kind == MessageKind.SYSTEM) {
      return const SizedBox.shrink();
    } else if (kind == MessageKind.IMAGE) {
      final url = _buildMediaUrl(message);
      if (url == null || url.isEmpty) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => Dialog(
              insetPadding: const EdgeInsets.all(8),
              backgroundColor: Colors.transparent,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    placeholder: (context, url) => Container(
                      width: double.infinity,
                      height: 300,
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: double.infinity,
                      height: 300,
                      color: Colors.black12,
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.white70,
                      ),
                    ),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: url,
            placeholder: (context, url) => Container(
              width: 180,
              height: 120,
              color: Colors.grey[200],
              child: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              width: 180,
              height: 120,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image),
            ),
            width: 180,
            height: 120,
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (kind == MessageKind.VIDEO) {
      final url = _buildMediaUrl(message);
      if (url == null || url.isEmpty) return const SizedBox.shrink();

      // DON'T auto-generate thumbnail - just show placeholder with play button
      return GestureDetector(
        onLongPress: () => _showMediaOptions(message, url),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Static placeholder - no thumbnail generation
            Container(
              width: 200,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.videocam,
                size: 48,
                color: Colors.white54,
              ),
            ),
            // Play button
            const Icon(Icons.play_circle_fill, size: 56, color: Colors.white70),
            // Download indicator
            Positioned(
              right: 8,
              top: 8,
              child: FutureBuilder<FileInfo?>(
                future: DefaultCacheManager().getFileFromCache(url),
                builder: (context, snapshot) {
                  final isCached = snapshot.data != null;
                  final isDownloading =
                      _downloadProgress[message.id] != null &&
                      _downloadProgress[message.id]! < 1.0;

                  if (isDownloading) {
                    return SizedBox(
                      width: 36,
                      height: 36,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: _downloadProgress[message.id],
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          ),
                          const Icon(
                            Icons.downloading,
                            size: 14,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    );
                  }

                  if (!isCached) {
                    return Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.cloud_download,
                        color: Colors.white,
                        size: 20,
                      ),
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
                  );
                },
              ),
            ),
            // Tap area
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    // Check if cached
                    final cached = await DefaultCacheManager().getFileFromCache(
                      url,
                    );
                    if (cached != null) {
                      // Already cached, play directly
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) {
                            return Scaffold(
                              backgroundColor: Colors.black,
                              appBar: AppBar(
                                backgroundColor: Colors.black,
                                iconTheme: const IconThemeData(
                                  color: Colors.white,
                                ),
                              ),
                              body: Center(
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: VideoPlayerViewer(
                                    url: url,
                                    messageId: message.id,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    } else {
                      // Not cached, download first
                      try {
                        await _fetchAndCache(url, message.id);
                        setState(() {}); // Refresh to show cached state
                        showCustomSnackBar(
                          context,
                          'Download complete. Tap again to play.',
                          type: SnackBarType.success,
                        );
                      } catch (e) {
                        showCustomSnackBar(
                          context,
                          'Download failed: $e',
                          type: SnackBarType.error,
                        );
                      }
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      );
    } else if (kind == MessageKind.AUDIO) {
      final url = _buildMediaUrl(message);
      if (url == null || url.isEmpty) return const SizedBox.shrink();

      return FutureBuilder<FileInfo?>(
        future: DefaultCacheManager().getFileFromCache(url),
        builder: (context, snapshot) {
          final isCached = snapshot.data != null;
          final isDownloading =
              _downloadProgress[message.id] != null &&
              _downloadProgress[message.id]! < 1.0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached ? Colors.green : Colors.grey.withOpacity(0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.audiotrack,
                  size: 20,
                  color: isCached ? Colors.green : Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    message.fileName ?? 'Audio',
                    style: TextStyle(
                      color: isCached ? Colors.green[700] : Colors.black87,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (isDownloading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: _downloadProgress[message.id],
                      strokeWidth: 2,
                    ),
                  )
                else if (!isCached)
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () async {
                      try {
                        await _fetchAndCache(url, message.id);
                        setState(() {});
                        showCustomSnackBar(
                          context,
                          'Download complete',
                          type: SnackBarType.success,
                        );
                      } catch (e) {
                        showCustomSnackBar(
                          context,
                          'Download failed: $e',
                          type: SnackBarType.error,
                        );
                      }
                    },
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.play_arrow, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: _audioPlayerWidget(message),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      );
    } else if (kind == MessageKind.FILE) {
      final url = message.fileUrl;
      if (url == null || url.isEmpty) return const SizedBox.shrink();

      return GestureDetector(
        onLongPress: () => _showMediaOptions(message, url),
        child: FutureBuilder<FileInfo?>(
          future: DefaultCacheManager().getFileFromCache(url),
          builder: (context, snapshot) {
            final isCached = snapshot.data != null;
            final isDownloading =
                _downloadProgress[message.id] != null &&
                _downloadProgress[message.id]! < 1.0;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCached ? Colors.green : Colors.grey.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.insert_drive_file,
                    size: 20,
                    color: isCached ? Colors.green : Colors.grey[700],
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message.fileName ?? 'File',
                      style: TextStyle(
                        color: isCached ? Colors.green[700] : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isDownloading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: _downloadProgress[message.id],
                        strokeWidth: 2,
                      ),
                    )
                  else if (!isCached)
                    IconButton(
                      icon: const Icon(Icons.download_rounded, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        try {
                          await _fetchAndCache(url, message.id);
                          setState(() {});
                          showCustomSnackBar(
                            context,
                            'Download complete',
                            type: SnackBarType.success,
                          );
                        } catch (e) {
                          showCustomSnackBar(
                            context,
                            'Download failed: $e',
                            type: SnackBarType.error,
                          );
                        }
                      },
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        try {
                          final file = await _fetchAndCache(url, message.id);
                          if (file != null) {
                            final ext = p.extension(file.path).toLowerCase();
                            if (ext == '.pdf') {
                              await _openPdfViewer(url, message.id);
                            } else {
                              final uri = Uri.file(file.path);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              } else {
                                showCustomSnackBar(
                                  context,
                                  'Cannot open file.',
                                  type: SnackBarType.error,
                                );
                              }
                            }
                          }
                        } catch (e) {
                          showCustomSnackBar(
                            context,
                            'Failed to open file: $e',
                            type: SnackBarType.error,
                          );
                        }
                      },
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String? _extractFirstImgSrc(String html) {
    final pattern = r'<img[^>]*src="([^"]*)"';
    final reg = RegExp(pattern, caseSensitive: false);
    final m = reg.firstMatch(html);
    return m?.group(1);
  }

  String? _extractFirstVideoSrc(String html) {
    final pattern = r'<video[^>]*src="([^"]*)"';
    final reg = RegExp(pattern, caseSensitive: false);
    final m = reg.firstMatch(html);
    return m?.group(1);
  }

  Widget _buildReplyMessage(Message replyMessage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppClr.primaryColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyMessage.sender.name,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: AppClr.primaryColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _parseMessage(replyMessage.message),
            style: const TextStyle(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _parseMessage(String message) {
    if (message.isEmpty) return '';

    // Remove HTML tags
    String out = message.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    // Decode common named entities
    out = out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    // Decode numeric entities like &#123; and hex &#x1F600;
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      try {
        final code = int.parse(m[1]!);
        return String.fromCharCode(code);
      } catch (_) {
        return '';
      }
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      try {
        final code = int.parse(m[1]!, radix: 16);
        return String.fromCharCode(code);
      } catch (_) {
        return '';
      }
    });

    return out.trim();
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  onChanged: (value) => _onTyping(),
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Attach button
            if (_attachedFilePath == null) ...[
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                onPressed: _openFilePicker,
              ),
            ] else ...[
              // show small preview
              GestureDetector(
                onTap: () {
                  // remove attached
                  setState(() {
                    _attachedFilePath = null;
                    _attachedFileType = null;
                  });
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: _attachedFileType == 1
                        ? const Icon(Icons.image, size: 20)
                        : (_attachedFileType == 2
                              ? const Icon(Icons.videocam, size: 20)
                              : const Icon(Icons.insert_drive_file, size: 20)),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: AppClr.primaryColor,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // attachment UI removed - only text messages supported

  @override
  bool get wantKeepAlive => true;

  // Create a stable fingerprint for a message for UI-level dedupe
  String _fingerprint(Message m) {
    final txt = _parseMessage(m.message);
    // include server id to make fingerprint unique per message
    return '${m.id}|${m.fromId}|$txt|${m.fileUrl ?? ''}|${m.messageType}|${m.createdAt.millisecondsSinceEpoch}';
  }

  List<Message> _uniqueMessages(List<Message> messages) {
    final seen = <String>{};
    final out = <Message>[];
    for (var m in messages) {
      final fp = _fingerprint(m);
      if (seen.contains(fp)) continue;
      seen.add(fp);
      out.add(m);
    }
    return out;
  }

  String? _buildMediaUrl(Message message) {
    // Prefer explicit fileUrl from payload
    final fUrl = message.fileUrl;
    if (fUrl != null && fUrl.isNotEmpty) return _normalizeUrl(fUrl);

    // If API provides a fileName (e.g. 'uploads/..'), build full URL using server host
    final fName = message.fileName;
    if (fName != null && fName.isNotEmpty) {
      // Base host (no '/api/') - matches server file_url format
      const base = ApiUrls.baseUrl;
      String candidate;
      if (fName.startsWith('http')) {
        candidate = fName;
      } else if (fName.startsWith('/'))
        candidate = base + fName.substring(1);
      else
        candidate = base + fName;
      return _normalizeUrl(candidate);
    }

    // Fallback: try to extract from HTML in message body
    final img = _extractFirstImgSrc(message.message);
    if (img != null && img.isNotEmpty) return _normalizeUrl(img);
    final vid = _extractFirstVideoSrc(message.message);
    if (vid != null && vid.isNotEmpty) return _normalizeUrl(vid);

    return null;
  }

  String? _normalizeUrl(String raw) {
    var url = raw.trim();
    // If there are multiple http(s) occurrences, take the last one (fix duplicated prefixes)
    final lastHttp = url.lastIndexOf('http');
    if (lastHttp > 0) url = url.substring(lastHttp);

    // Fix protocol-relative URLs
    if (url.startsWith('//')) url = 'https:$url';

    // Replace spaces
    url = url.replaceAll(' ', '%20');

    // Ensure it starts with http
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      url = 'https://$url';
    }

    // Validate
    try {
      final parsed = Uri.parse(url);
      if (!parsed.hasScheme ||
          !(parsed.scheme == 'http' || parsed.scheme == 'https'))
        return null;
      return parsed.toString();
    } catch (_) {
      return null;
    }
  }

  // Fetch a file and cache it using flutter_cache_manager. Returns local File.
  Future<File?> _fetchAndCache(String url, String messageId) async {
    if (url.isEmpty) return null;

    final cacheManager = DefaultCacheManager();

    // Fast cache check
    try {
      final cached = await cacheManager.getFileFromCache(url);
      if (cached != null) {
        debugPrint('📥 Cache hit for: $url (messageId:$messageId)');
        return cached.file;
      }
    } catch (e) {
      debugPrint('⚠️ Cache check failed for $url: $e');
      // proceed to download
    }

    // If an identical fetch is already in progress, return that future
    if (_fetchFutures.containsKey(url)) {
      debugPrint('🔁 Reusing in-flight download for: $url');
      return _fetchFutures[url];
    }

    // Create the download future and store it so concurrent callers reuse it
    final future = (() async {
      final dio = DioClient();
      final cancelToken = CancelToken();
      _downloadTokens[messageId] = cancelToken;

      debugPrint('⬇️ Starting download: $url (messageId:$messageId)');
      try {
        final resp = await dio.downloadBytes(
          url,
          onReceiveProgress: (count, total) {
            final pct = (total > 0) ? (count / total) : 0.0;
            _downloadProgress[messageId] = pct;
            // throttle UI updates: only call setState when progress changed enough
            final last = _lastReportedProgress[messageId] ?? -1.0;
            if ((pct - last).abs() > 0.02 || pct == 1.0) {
              _lastReportedProgress[messageId] = pct;
              if (mounted) setState(() {});
            }
          },
          cancelToken: cancelToken,
        );

        final bytes = resp.data as List<int>?;
        if (bytes == null) throw Exception('Empty download');

        await cacheManager.putFile(
          url,
          Uint8List.fromList(bytes),
          fileExtension: p.extension(url),
        );
        final info = await cacheManager.getFileFromCache(url);
        debugPrint('✅ Download complete: $url');
        return info?.file;
      } finally {
        _downloadProgress.remove(messageId);
        _downloadTokens.remove(messageId);
        _lastReportedProgress.remove(messageId);
      }
    })();

    _fetchFutures[url] = future;

    try {
      final file = await future;
      return file;
    } finally {
      // remove stored future so subsequent calls will re-check cache
      _fetchFutures.remove(url);
    }
  }

  Future<File?> _getVideoThumbnail(String url, String messageId) async {
    if (url.isEmpty) return null;

    final cacheManager = DefaultCacheManager();
    final thumbKey = '${url}_thumb.jpg';

    // If thumb cached, return quickly
    try {
      final cached = await cacheManager.getFileFromCache(thumbKey);
      if (cached != null) {
        debugPrint('📥 Thumbnail cache hit for $url');
        return cached.file;
      }
    } catch (e) {
      debugPrint('⚠️ Thumb cache check failed: $e');
    }

    // Reuse in-flight thumbnail generation
    if (_thumbFutures.containsKey(thumbKey)) {
      debugPrint('🔁 Reusing in-flight thumbnail for $url');
      return _thumbFutures[thumbKey];
    }

    final future = (() async {
      // Ensure video is downloaded first (reuses _fetchAndCache which also memoizes)
      final videoFile = await _fetchAndCache(url, messageId);
      if (videoFile == null) return null;

      final data = await VideoThumbnail.thumbnailData(
        video: videoFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      );
      if (data == null) return null;

      await cacheManager.putFile(thumbKey, data, fileExtension: '.jpg');
      final info = await cacheManager.getFileFromCache(thumbKey);
      return info?.file;
    })();

    // Store the future for reuse
    _thumbFutures[thumbKey] = future;

    try {
      final result = await future;
      return result;
    } catch (e) {
      if (kDebugMode) print('⚠️ Thumbnail generation failed: $e');
      return null;
    } finally {
      // Clean up the future cache when done
      _thumbFutures.remove(thumbKey);
    }
  }

  // Save a file (image/video) to the gallery. Requests permissions where required.
  Future<void> _saveToGallery(File file) async {
    try {
      if (Platform.isAndroid) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          showCustomSnackBar(
            context,
            'Storage permission required to save files.',
            type: SnackBarType.error,
          );
          return;
        }
      } else if (Platform.isIOS) {
        final status = await Permission.photos.request();
        if (!status.isGranted) {
          showCustomSnackBar(
            context,
            'Photos permission required to save files.',
            type: SnackBarType.error,
          );
          return;
        }
      }

      final bytes = await file.readAsBytes();
      final pathStr = file.path;
      final ext = p.extension(pathStr).toLowerCase();
      bool saved = false;
      if (ext == '.mp4' || ext == '.mov' || ext == '.mkv' || ext == '.webm') {
        saved = await GalleryHelper.saveVideo(pathStr) ?? false;
      } else {
        saved = await GalleryHelper.saveImage(pathStr) ?? false;
      }
      if (saved)
        showCustomSnackBar(
          context,
          'Saved to gallery',
          type: SnackBarType.success,
        );
      else
        showCustomSnackBar(
          context,
          'Failed to save to gallery',
          type: SnackBarType.error,
        );
    } catch (e) {
      showCustomSnackBar(
        context,
        'Error saving file: $e',
        type: SnackBarType.error,
      );
    }
  }

  // Open video dialog (downloads if necessary and plays cached file)
  Future<void> _openVideoDialog(String url, String messageId) async {
    try {
      final file = await _fetchAndCache(url, messageId);
      if (file == null) {
        showCustomSnackBar(
          context,
          'Video not available',
          type: SnackBarType.error,
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Center(
                  child: Hero(
                    tag: 'media_$messageId',
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: VideoPlayerViewer(url: url, messageId: messageId),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    } catch (e) {
      showCustomSnackBar(
        context,
        'Failed to open video: $e',
        type: SnackBarType.error,
      );
    }
  }

  // Open PDF viewer using pdfx package (downloads file first)
  Future<void> _openPdfViewer(String url, String messageId) async {
    try {
      final file = await _fetchAndCache(url, messageId);
      if (file == null) {
        showCustomSnackBar(
          context,
          'PDF not available',
          type: SnackBarType.error,
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) {
            final controller = PdfController(
              document: PdfDocument.openFile(file.path),
            );
            return Scaffold(
              appBar: AppBar(title: const Text('Document')),
              body: PdfView(controller: controller),
            );
          },
        ),
      );
    } catch (e) {
      showCustomSnackBar(
        context,
        'Failed to open PDF: $e',
        type: SnackBarType.error,
      );
    }
  }

  // Minimal audio player widget: plays cached audio file using just_audio
  Widget _audioPlayerWidget(Message message) {
    return AudioPlayerInline(message: message, fetchAndCache: _fetchAndCache);
  }

  // Show download / save / share options for a message (long-press)
  void _showMediaOptions(Message message, String url) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final downloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  downloading ? Icons.cancel : Icons.download_rounded,
                ),
                title: Text(downloading ? 'Cancel download' : 'Download'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (downloading) {
                    final token = _downloadTokens[message.id];
                    token?.cancel('user_cancel');
                    _downloadProgress.remove(message.id);
                    setState(() {});
                    showCustomSnackBar(
                      context,
                      'Download cancelled',
                      type: SnackBarType.info,
                    );
                  } else {
                    try {
                      await _fetchAndCache(url, message.id);
                      setState(() {});
                      showCustomSnackBar(
                        context,
                        'Downloaded',
                        type: SnackBarType.success,
                      );
                    } catch (e) {
                      showCustomSnackBar(
                        context,
                        'Download failed: $e',
                        type: SnackBarType.error,
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save to gallery'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  try {
                    final file = await _fetchAndCache(url, message.id);
                    if (file != null) await _saveToGallery(file);
                  } catch (e) {
                    showCustomSnackBar(
                      context,
                      'Save failed: $e',
                      type: SnackBarType.error,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  showCustomSnackBar(
                    context,
                    'Share not implemented',
                    type: SnackBarType.info,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

// Small helper widget to play a cached video file using Chewie.
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
      if (kDebugMode) print('⚠️ Video viewer init failed: $e');
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
