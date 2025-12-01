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
import 'package:hsc_chat/feature/home/model/conversation_model.dart'
    show Conversation;
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
import 'package:permission_handler/permission_handler.dart';
import 'package:hsc_chat/cores/utils/gallery_helper.dart';
import 'package:hsc_chat/feature/home/view/_audio_player_inline.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String? userAvatar;
  final bool isGroup;
  final Conversation? groupData;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.userName,
    this.userAvatar,
    this.groupData,
    this.isGroup = false,
  });

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
  int? _attachedFileType;
  //   Track chat request action loading state
  bool _isAcceptLoading = false;
  bool _isDeclineLoading = false;
  // Download/caching & playback helpers
  final Map<String, CancelToken> _downloadTokens = {};
  final Map<String, double> _downloadProgress = {};
  final Map<String, AudioPlayer> _audioPlayers = {};
  final Map<String, Future<File?>> _fetchFutures = {};
  final Map<String, Future<File?>> _thumbFutures = {};
  final Map<String, double> _lastReportedProgress = {};
  // Track local file paths for sent messages
  final Map<String, String> _sentMessageLocalPaths = {};
  // Scroll management for load-more
  bool _isLoadingMore = false;
  bool _shouldScrollToBottom = true;
  double? _scrollOffsetBeforeLoad;
  int? _messageCountBeforeLoad;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeChat();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final pixels = position.pixels;
    final maxScroll = position.maxScrollExtent;

    // Check if user scrolled to top (to load older messages)
    // Top means pixels close to 0
    if (pixels <= 100 && !_isLoadingMore) {
      final state = context.read<ChatCubit>().state;
      if (state is ChatLoaded && state.hasMore && !state.isLoadingMore) {
        _loadMoreOldMessages();
      }
    }

    // Determine if user is near bottom (within 200px of maxScroll)
    // If user is at bottom, we should auto-scroll for new messages
    _shouldScrollToBottom = (maxScroll - pixels) < 200;
  }

  Future<void> _loadMoreOldMessages() async {
    if (_isLoadingMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    // Save current scroll position and message count
    if (_scrollController.hasClients) {
      _scrollOffsetBeforeLoad = _scrollController.offset;
      final state = context.read<ChatCubit>().state;
      if (state is ChatLoaded) {
        _messageCountBeforeLoad = state.messages.length;
      }
    }

    // Trigger load more
    await context.read<ChatCubit>().loadMoreMessages();

    setState(() {
      _isLoadingMore = false;
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final position = _scrollController.position;
      final target = position.maxScrollExtent;

      if (target <= 0) return;

      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _restoreScrollAfterLoadMore() {
    if (!mounted || !_scrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final state = context.read<ChatCubit>().state;
      if (state is! ChatLoaded) return;

      final currentCount = state.messages.length;
      final previousCount = _messageCountBeforeLoad ?? currentCount;
      final newMessagesLoaded = currentCount - previousCount;

      if (newMessagesLoaded > 0) {
        // Calculate approximate height per message (adjust based on your design)
        // This is a rough estimate - you may need to tune this value
        final estimatedHeight = newMessagesLoaded * 80.0;

        try {
          final targetOffset = (_scrollOffsetBeforeLoad ?? 0) + estimatedHeight;
          _scrollController.jumpTo(
            targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        } catch (e) {
          print('⚠️ Error restoring scroll: $e');
        }
      }

      _scrollOffsetBeforeLoad = null;
      _messageCountBeforeLoad = null;
    });
  }

  void _initializeChat() {
    final currentUserId = SharedPreferencesHelper.getCurrentUserId();
    print('🚀 Initializing chat with user: ${widget.userId}');

    context.read<ChatCubit>().loadConversations(
      currentUserId,
      widget.userId,
      widget.isGroup,
      widget.groupData,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<ChatCubit>().state;
    if (s is ChatLoaded && s.messages.isNotEmpty) {
      Future.microtask(() => _scrollToBottom(animate: false));
    }
  }

  @override
  void dispose() {
    print('🧹 Disposing chat screen');
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    for (var p in _audioPlayers.values) {
      p.dispose();
    }
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  // NEW: Get local file path for sent messages
  String? _getLocalFilePath(Message message) {
    if (!message.isSentByMe) return null;
    return _sentMessageLocalPaths[message.id];
  }

  // NEW: Check if file exists locally
  Future<bool> _fileExistsLocally(String path) async {
    try {
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }

  // Store local path when sending file
  Future<void> _sendMessage() async {
    final currentState = context.read<ChatCubit>().state;
    if (currentState is ChatLoaded && currentState.isIBlockedThem) {
      showCustomSnackBar(
        context,
        'You have blocked this user. Unblock to send messages.',
        type: SnackBarType.error,
      );
      return;
    }
    // Clear reply/edit mode when sending new message
    context.read<ChatCubit>().clearReplyEditMode();

    final caption = _messageController.text.trim();
    final hasFile = _attachedFilePath != null && _attachedFilePath!.isNotEmpty;
    final hasText = caption.isNotEmpty;

    if (hasFile && hasText) {
      showCustomSnackBar(
        context,
        'Cannot send text and file together.',
        type: SnackBarType.error,
      );
      return;
    }

    if (!hasFile && !hasText) return;

    if (hasFile) {
      final localPath = _attachedFilePath!;
      print('📤 Sending file: $localPath');

      // Validate file
      try {
        final f = File(localPath);
        if (!await f.exists()) {
          showCustomSnackBar(
            context,
            'Selected file not found.',
            type: SnackBarType.error,
          );
          return;
        }

        final ext = p.extension(localPath).toLowerCase();
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

      // Send the file
      final error = await context.read<ChatCubit>().sendMessage(
        message: '',
        filePath: localPath,
      );

      if (error != null) {
        showCustomSnackBar(context, error, type: SnackBarType.error);
      } else {
        // SUCCESS: Store local path mapping
        // Get the message ID from state after successful send
        final state = context.read<ChatCubit>().state;
        if (state is ChatLoaded && state.messages.isNotEmpty) {
          final lastMessage = state.messages.last;
          if (lastMessage.isSentByMe) {
            // Map message ID to local file path
            _sentMessageLocalPaths[lastMessage.id] = localPath;
            print('✅ Mapped ${lastMessage.id} → $localPath');
          }
        }
      }

      // Clear attachment
      setState(() {
        _attachedFilePath = null;
        _attachedFileType = null;
      });

      _scrollToBottom();
      return;
    }

    // Text-only send
    final message = caption;
    print('📤 Sending message: $message');
    final error = await context.read<ChatCubit>().sendMessage(message: message);
    if (error != null) {
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
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return WillPopScope(
      onWillPop: () async {
        // Mirror previous WillPopScope behavior: forward latest message to
        // ConversationCubit and then pop the route. Return false to prevent
        // default pop handler (we manually pop).
        print('⬅️ Going back from chat');
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
                'group_id': widget.isGroup
                    ? widget.groupData?.groupId
                    : null,
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
            Expanded(child: _buildMessagesWithOverlay()),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAcceptRequest(Conversation? conversationData) async {
    final requestId = conversationData?.chatRequestId;

    if (requestId == null || requestId.isEmpty) {
      showCustomSnackBar(
        context,
        'Invalid request ID',
        type: SnackBarType.error,
      );
      return;
    }

    setState(() => _isAcceptLoading = true);

    try {
      final success = await context.read<ConversationCubit>().acceptChatRequest(
        requestId,
      );

      if (!mounted) return;

      if (success) {
        // Reload conversations to get fresh data
        await context.read<ChatCubit>().loadConversations(
          SharedPreferencesHelper.getCurrentUserId(),
          widget.userId,
          widget.isGroup,
          widget.groupData, // ✅ Pass conversation data
        );

        showCustomSnackBar(
          context,
          'Chat request accepted',
          type: SnackBarType.success,
        );
      } else {
        showCustomSnackBar(
          context,
          'Failed to accept chat request',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, 'Error: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isAcceptLoading = false);
      }
    }
  }

  Future<void> _handleDeclineRequest(Conversation? conversationData) async {
    final requestId = conversationData?.chatRequestId;

    if (requestId == null || requestId.isEmpty) {
      showCustomSnackBar(
        context,
        'Invalid request ID',
        type: SnackBarType.error,
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Chat Request'),
        content: Text(
          'Are you sure you want to decline the chat request from ${widget.userName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Decline', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeclineLoading = true);

    try {
      final success = await context
          .read<ConversationCubit>()
          .declineChatRequest(requestId);

      if (!mounted) return;

      if (success) {
        showCustomSnackBar(
          context,
          'Chat request declined',
          type: SnackBarType.info,
        );

        // Navigate back after declining
        Navigator.pop(context);
      } else {
        showCustomSnackBar(
          context,
          'Failed to decline chat request',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(context, 'Error: $e', type: SnackBarType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isDeclineLoading = false);
      }
    }
  }

  //  Wrap messages list with chat request overlay
  Widget _buildMessagesWithOverlay() {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        //  Get chat request data from loaded state's groupData (Conversation object)
        final conversationData = state is ChatLoaded
            ? state.groupData
            : widget.groupData;

        final chatRequestStatus = conversationData?.chatRequestStatus;
        final chatRequestTo = conversationData?.chatRequestTo;

        final currentUserId = SharedPreferencesHelper.getCurrentUserId();

        // Parse chatRequestTo to int for comparison
        final chatRequestToInt = chatRequestTo != null
            ? int.tryParse(chatRequestTo)
            : null;

        final shouldShowOverlay =
            chatRequestStatus == 'pending' && chatRequestToInt == currentUserId;

        print('👁️ Should show overlay: $shouldShowOverlay');
        print('📋 Chat Request Status: $chatRequestStatus');
        print('📋 Chat Request To: $chatRequestTo (parsed: $chatRequestToInt)');
        print('📋 Current User ID: $currentUserId');
        print('📋 Conversation Data: $conversationData');

        return Stack(
          children: [
            // Messages list
            _buildMessagesList(),

            //  Chat request overlay
            if (shouldShowOverlay)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.7),
                  child: Center(
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.mark_email_unread,
                              size: 48,
                              color: AppClr.primaryColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Chat Request',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppClr.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${widget.userName} wants to start a conversation with you.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _isDeclineLoading
                                        ? null
                                        : () => _handleDeclineRequest(
                                            conversationData,
                                          ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      side: BorderSide(color: Colors.red),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: _isDeclineLoading
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.red,
                                                  ),
                                            ),
                                          )
                                        : Text(
                                            'Decline',
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _isAcceptLoading
                                        ? null
                                        : () => _handleAcceptRequest(
                                            conversationData,
                                          ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      backgroundColor: AppClr.primaryColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: _isAcceptLoading
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            'Accept',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
                  'group_id': widget.isGroup ? widget.groupData?.groupId : null,
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
            PopupMenuItem(
              value: 'info',
              child: Row(
                children: [Text(widget.isGroup ? 'Group Info' : 'User Info')],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openUserInfo() {
    // Read ChatCubit data *before* pushing a new route. Using the new route's
    // builder context to read providers can cause ProviderNotFoundException.
    final cubit = context.read<ChatCubit>();
    final state = cubit.state;
    final isICurrentlyBlockedThisUser = (state is ChatLoaded)
        ? state.isIBlockedThem
        : false;
    final isThemCurrentlyBlockedMe = (state is ChatLoaded)
        ? state.isTheyBlockedMe
        : false;
    // state.groupData is already a ChatGroup? (typed in ChatLoaded)
    final groupModel = (state is ChatLoaded) ? state.commonGroupData : null;

    print('ℹ️ Opening user info for $groupModel');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => UserInfoScreen(
          userId: widget.userId,
          userName: widget.userName,
          userAvatar: widget.userAvatar,
          userEmail: widget.userEmail,
          isGroup: widget.isGroup,
          groupData: groupModel,
          isIBlockedThem: isICurrentlyBlockedThisUser,
          isTheyBlockedMe: isThemCurrentlyBlockedMe,
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is! ChatLoaded) return;

        // If we just finished loading more old messages, restore scroll position
        if (_scrollOffsetBeforeLoad != null &&
            _messageCountBeforeLoad != null) {
          _restoreScrollAfterLoadMore();
          return;
        }

        // If user is near bottom and new message arrived, scroll to bottom
        if (_shouldScrollToBottom && !state.isLoadingMore) {
          _scrollToBottom(animate: true);
        }
      },
      // ✅ ADD THIS: Rebuild when messages change
      buildWhen: (previous, current) {
        if (previous is ChatLoaded && current is ChatLoaded) {
          // Rebuild if message count changes OR if any message content changed
          if (previous.messages.length != current.messages.length) {
            return true;
          }

          // Check if any message was updated (deleted, edited, etc.)
          for (int i = 0; i < previous.messages.length; i++) {
            final prevMsg = previous.messages[i];
            final currMsg = current.messages[i];

            if (prevMsg.id == currMsg.id &&
                (prevMsg.message != currMsg.message ||
                    prevMsg.updatedAt != currMsg.updatedAt)) {
              print('🔄 Message ${currMsg.id} was updated, rebuilding list');
              return true;
            }
          }
        }
        return true; // Default: always rebuild on state change
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

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            itemCount: visibleMessages.length + (state.isLoadingMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (state.isLoadingMore && index == 0) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }

              final messageIndex = state.isLoadingMore ? index - 1 : index;
              final msg = visibleMessages[messageIndex];

              // ✅ Use ValueKey to help Flutter identify when message content changes
              return KeyedSubtree(
                key: ValueKey('${msg.id}_${msg.updatedAt.millisecondsSinceEpoch}'),
                child: _buildMessageBubble(msg),
              );
            },
          );
        }

        return const Center(child: Text('No messages'));
      },
    );
  }
  Widget _buildMessageBubble(Message message) {
    final kind = message.kind();
    if (message.replyMessage != null) {
      _debugReplyMessage(message);
    }
    // If it's a SYSTEM message render it as a standalone centered blue bubble
    if (kind == MessageKind.SYSTEM) {
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
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: message.isSentByMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      // Group sender name
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

                      // Reply message
                      if (message.replyMessage != null)
                        _buildReplyMessage(message.replyMessage!),

                      // ✅ Message content (media types have their own gestures)
                      _buildMessageContent(message),

                      // Spacing
                      if (kind != MessageKind.TEXT)
                        const SizedBox(height: 6)
                      else
                        const SizedBox(height: 8),

                      // ✅ For TEXT messages, wrap text in GestureDetector
                      if (kind == MessageKind.TEXT) ...[
                        GestureDetector(
                          onLongPress: () {
                            print('🔍 Long pressed TEXT message ${message.id}');
                            _showMessageActions(message);
                          },

                          child: Text(
                            _parseMessage(message.message),
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 16,
                            ),
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
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  /*
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
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
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
                              print('🔍 Long pressed message ${message.id}');
                            },
                            behavior: HitTestBehavior.opaque,
                            onLongPress: () {
                              print('🔍 Long pressed message ${message.id}');
                              _showMessageActions(message);
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
*/

  /*
  Widget _buildMessageContent(Message message) {
    final kind = message.kind();

    if (kind == MessageKind.SYSTEM) {
      return const SizedBox.shrink();
    } else if (kind == MessageKind.IMAGE) {
      return _buildImageContent(message);
    } else if (kind == MessageKind.VIDEO) {
      return _buildVideoContent(message);
    } else if (kind == MessageKind.AUDIO) {
      return _buildAudioContent(message);
    } else if (kind == MessageKind.FILE) {
      return _buildFileContent(message);
    }

    return const SizedBox.shrink();
  }
*/
  Widget _buildMessageContent(Message message) {
    final kind = message.kind();

    if (kind == MessageKind.SYSTEM) {
      return const SizedBox.shrink();
    } else if (kind == MessageKind.IMAGE) {
      return _buildImageContent(message);
    } else if (kind == MessageKind.VIDEO) {
      return _buildVideoContent(message);
    } else if (kind == MessageKind.AUDIO) {
      return _buildAudioContent(message);
    } else if (kind == MessageKind.FILE) {
      return _buildFileContent(message);
    }

    return const SizedBox.shrink();
  }

  // ✅ IMAGE: Already has gesture handling
  Widget _buildImageContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          final fileExists = snapshot.data ?? false;

          if (fileExists) {
            return GestureDetector(
              onTap: () {
                print('🖼️ Tapped local image ${message.id}');
                _openImageViewerLocal(localPath, message.id);
              },
              onLongPress: () {
                print('🔍 Long pressed local image ${message.id}');
                _showSenderMediaOptions(message, localPath);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(localPath),
                  width: 200,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }

          return _buildImageContentReceiver(message, url);
        },
      );
    }

    return _buildImageContentReceiver(message, url);
  }
  // IMAGE: Show thumbnail, tap to view full screen
  /*
  Widget _buildImageContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    // For SENDER: Check if we have local file path
    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          final fileExists = snapshot.data ?? false;

          if (fileExists) {
            // SENDER: Show from local file (NO DOWNLOAD)
            return GestureDetector(
              onTap: () => _openImageViewerLocal(localPath, message.id),
              onLongPress: () => _showSenderMediaOptions(message, localPath),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(localPath),
                  width: 200,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ),
            );
          }

          // Fallback: local file not found, download from server
          return _buildImageContentReceiver(message, url);
        },
      );
    }

    // RECEIVER: Download from server
    return _buildImageContentReceiver(message, url);
  }
*/

  /*
  Widget _buildImageContentReceiver(Message message, String url) {
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            if (isCached) {
              _openImageViewer(url, message.id);
            } else {
              await _fetchAndCache(url, message.id);
              if (mounted) {
                _openImageViewer(url, message.id);
              }
            }
          },
          onLongPress: () => _showMediaOptions(message, url),
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isCached
                    ? CachedNetworkImage(
                        imageUrl: url,
                        width: 200,
                        height: 150,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, size: 40),
                        ),
                      )
                    : Container(
                        width: 200,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.image,
                          size: 48,
                          color: Colors.white70,
                        ),
                      ),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? CircularProgressIndicator(
                            value: _downloadProgress[message.id],
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          )
                        : const Icon(
                            Icons.download_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
*/
  Widget _buildImageContentReceiver(Message message, String url) {
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            print('🖼️ Tapped remote image ${message.id}');
            if (isCached) {
              _openImageViewer(url, message.id);
            } else {
              await _fetchAndCache(url, message.id);
              if (mounted) {
                _openImageViewer(url, message.id);
              }
            }
          },
          onLongPress: () {
            print('🔍 Long pressed remote image ${message.id}');
            _showMediaOptions(message, url);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isCached
                    ? CachedNetworkImage(
                        imageUrl: url,
                        width: 200,
                        height: 150,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 200,
                          height: 150,
                          color: Colors.grey[300],
                          child: const Icon(Icons.broken_image, size: 40),
                        ),
                      )
                    : Container(
                        width: 200,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.image,
                          size: 48,
                          color: Colors.white70,
                        ),
                      ),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? CircularProgressIndicator(
                            value: _downloadProgress[message.id],
                            backgroundColor: Colors.white24,
                            color: Colors.white,
                          )
                        : const Icon(
                            Icons.download_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /*
  // VIDEO: Show thumbnail with play button
  Widget _buildVideoContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    // For SENDER: Check if we have local file path
    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          final fileExists = snapshot.data ?? false;

          if (fileExists) {
            // SENDER: Show local video (NO DOWNLOAD)
            return GestureDetector(
              onTap: () => _openVideoPlayerLocal(localPath, message.id),
              onLongPress: () => _showSenderMediaOptions(message, localPath),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                  const Icon(
                    Icons.play_circle_fill,
                    size: 56,
                    color: Colors.white,
                  ),
                ],
              ),
            );
          }

          // Fallback: download from server
          return _buildVideoContentReceiver(message, url);
        },
      );
    }

    // RECEIVER: Download from server
    return _buildVideoContentReceiver(message, url);
  }

  Widget _buildVideoContentReceiver(Message message, String url) {
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            if (isCached) {
              await _openVideoPlayer(url, message.id);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) {
                  await _openVideoPlayer(url, message.id);
                }
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () => _showMediaOptions(message, url),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.videocam,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: _downloadProgress[message.id],
                                backgroundColor: Colors.white24,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_downloadProgress[message.id]! * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : const Icon(
                            Icons.cloud_download,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_fill,
                  size: 56,
                  color: Colors.white,
                ),
            ],
          ),
        );
      },
    );
  }
*/
  Widget _buildVideoContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          final fileExists = snapshot.data ?? false;

          if (fileExists) {
            return GestureDetector(
              onTap: () {
                print('🎥 Tapped local video ${message.id}');
                _openVideoPlayerLocal(localPath, message.id);
              },
              onLongPress: () {
                print('🔍 Long pressed local video ${message.id}');
                _showSenderMediaOptions(message, localPath);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      size: 48,
                      color: Colors.white54,
                    ),
                  ),
                  const Icon(
                    Icons.play_circle_fill,
                    size: 56,
                    color: Colors.white,
                  ),
                ],
              ),
            );
          }

          return _buildVideoContentReceiver(message, url);
        },
      );
    }

    return _buildVideoContentReceiver(message, url);
  }

  Widget _buildVideoContentReceiver(Message message, String url) {
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            print('🎥 Tapped remote video ${message.id}');
            if (isCached) {
              await _openVideoPlayer(url, message.id);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) {
                  await _openVideoPlayer(url, message.id);
                }
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () {
            print('🔍 Long pressed remote video ${message.id}');
            _showMediaOptions(message, url);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.videocam,
                  size: 48,
                  color: Colors.white54,
                ),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: _downloadProgress[message.id],
                                backgroundColor: Colors.white24,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_downloadProgress[message.id]! * 100).toInt()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : const Icon(
                            Icons.cloud_download,
                            size: 40,
                            color: Colors.white,
                          ),
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_fill,
                  size: 56,
                  color: Colors.white,
                ),
            ],
          ),
        );
      },
    );
  }

  /*
  // AUDIO: Show audio tile with name and play button
  Widget _buildAudioContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return _buildAudioTile(
              message: message,
              isLocal: true,
              localPath: localPath,
            );
          }
          return _buildAudioTile(message: message, isLocal: false, url: url);
        },
      );
    }

    return _buildAudioTile(message: message, isLocal: false, url: url);
  }

  Widget _buildAudioTile({
    required Message message,
    required bool isLocal,
    String? localPath,
    String? url,
  }) {
    if (isLocal && localPath != null) {
      // SENDER: Show local audio
      return GestureDetector(
        onTap: () => _openAudioPlayerLocal(message, localPath),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isSentByMe
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headphones,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? 'Audio',
                      style: TextStyle(
                        color: message.isSentByMe
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to play',
                      style: TextStyle(
                        color: message.isSentByMe
                            ? Colors.white70
                            : Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_arrow, size: 24, color: Colors.green),
            ],
          ),
        ),
      );
    }
    // RECEIVER: Show download/cached audio
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url!),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            if (isCached) {
              _openAudioPlayer(message);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) _openAudioPlayer(message);
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached
                    ? Colors.green
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCached ? Colors.green : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDownloading
                        ? Icons.downloading
                        : (isCached ? Icons.headphones : Icons.audiotrack),
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'Audio',
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white
                              : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDownloading
                            ? 'Downloading ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached ? 'Tap to play' : 'Tap to download'),
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white70
                              : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isDownloading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress[message.id],
                      strokeWidth: 2,
                      color: message.isSentByMe ? Colors.white : Colors.green,
                    ),
                  )
                else
                  Icon(
                    isCached ? Icons.play_arrow : Icons.download_rounded,
                    size: 24,
                    color: message.isSentByMe ? Colors.white : Colors.green,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
*/
  Widget _buildAudioContent(Message message) {
    final url = _buildMediaUrl(message);
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final localPath = _getLocalFilePath(message);
    if (localPath != null && message.isSentByMe) {
      return FutureBuilder<bool>(
        future: _fileExistsLocally(localPath),
        builder: (context, snapshot) {
          if (snapshot.data == true) {
            return _buildAudioTile(
              message: message,
              isLocal: true,
              localPath: localPath,
            );
          }
          return _buildAudioTile(message: message, isLocal: false, url: url);
        },
      );
    }

    return _buildAudioTile(message: message, isLocal: false, url: url);
  }

  Widget _buildAudioTile({
    required Message message,
    required bool isLocal,
    String? localPath,
    String? url,
  }) {
    if (isLocal && localPath != null) {
      return GestureDetector(
        onTap: () {
          print('🎵 Tapped local audio ${message.id}');
          _openAudioPlayerLocal(message, localPath);
        },
        onLongPress: () {
          print('🔍 Long pressed local audio ${message.id}');
          _showSenderMediaOptions(message, localPath);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isSentByMe
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headphones,
                  size: 20,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? 'Audio',
                      style: TextStyle(
                        color: message.isSentByMe
                            ? Colors.white
                            : Colors.black87,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to play',
                      style: TextStyle(
                        color: message.isSentByMe
                            ? Colors.white70
                            : Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_arrow, size: 24, color: Colors.green),
            ],
          ),
        ),
      );
    }

    // Remote audio
    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url!),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            print('🎵 Tapped remote audio ${message.id}');
            if (isCached) {
              _openAudioPlayer(message);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) _openAudioPlayer(message);
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () {
            print('🔍 Long pressed remote audio ${message.id}');
            _showMediaOptions(message, url);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached
                    ? Colors.green
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCached ? Colors.green : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDownloading
                        ? Icons.downloading
                        : (isCached ? Icons.headphones : Icons.audiotrack),
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'Audio',
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white
                              : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDownloading
                            ? 'Downloading ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached ? 'Tap to play' : 'Tap to download'),
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white70
                              : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isDownloading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress[message.id],
                      strokeWidth: 2,
                      color: message.isSentByMe ? Colors.white : Colors.green,
                    ),
                  )
                else
                  Icon(
                    isCached ? Icons.play_arrow : Icons.download_rounded,
                    size: 24,
                    color: message.isSentByMe ? Colors.white : Colors.green,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // NEW: Open local image viewer
  void _openImageViewerLocal(String localPath, String messageId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(localPath), fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  // NEW: Open local video player
  Future<void> _openVideoPlayerLocal(String localPath, String messageId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: VideoPlayerViewerLocal(
              localPath: localPath,
              messageId: messageId,
            ),
          ),
        ),
      ),
    );
  }

  // NEW: Open local audio player
  void _openAudioPlayerLocal(Message message, String localPath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: AudioPlayerInlineLocal(message: message, localPath: localPath),
      ),
    );
  }

  // NEW: Sender-specific media options (no download option)
  void _showSenderMediaOptions(Message message, String localPath) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('File stored locally'),
                subtitle: Text(localPath, style: const TextStyle(fontSize: 11)),
                enabled: false,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Save to Gallery'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _saveToGallery(File(localPath));
                },
              ),
              ListTile(
                leading: const Icon(Icons.share),
                title: const Text('Share'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // TODO: Implement share
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileContent(Message message) {
    final url = message.fileUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final ext = p.extension(message.fileName ?? url).toLowerCase();
    IconData iconData = Icons.insert_drive_file;
    Color iconColor = Colors.blue;

    if (ext == '.pdf') {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['.doc', '.docx'].contains(ext)) {
      iconData = Icons.description;
      iconColor = Colors.blue[700]!;
    } else if (['.xls', '.xlsx'].contains(ext)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green[700]!;
    } else if (['.ppt', '.pptx'].contains(ext)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange[700]!;
    } else if (ext == '.txt') {
      iconData = Icons.text_snippet;
      iconColor = Colors.grey[700]!;
    }

    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            print('📄 Tapped file ${message.id}');
            if (isCached) {
              await _openDocument(url, message.id, ext);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) {
                  await _openDocument(url, message.id, ext);
                }
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () {
            print('🔍 Long pressed file ${message.id}');
            _showMediaOptions(message, url);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 250),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached
                    ? iconColor
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCached
                        ? iconColor.withValues(alpha: 0.2)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    iconData,
                    size: 28,
                    color: isCached ? iconColor : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'Document',
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white
                              : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDownloading
                            ? 'Downloading ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached
                                  ? ext.toUpperCase().replaceFirst('.', '')
                                  : 'Tap to download'),
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white70
                              : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isDownloading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress[message.id],
                      strokeWidth: 2,
                      color: message.isSentByMe ? Colors.white : iconColor,
                    ),
                  )
                else
                  Icon(
                    isCached ? Icons.open_in_new : Icons.download_rounded,
                    size: 20,
                    color: message.isSentByMe ? Colors.white : iconColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  // FILE/DOCUMENT: Show document icon with name
  /*
  Widget _buildFileContent(Message message) {
    final url = message.fileUrl;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final ext = p.extension(message.fileName ?? url).toLowerCase();
    IconData iconData = Icons.insert_drive_file;
    Color iconColor = Colors.blue;

    // Icon based on file type
    if (ext == '.pdf') {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['.doc', '.docx'].contains(ext)) {
      iconData = Icons.description;
      iconColor = Colors.blue[700]!;
    } else if (['.xls', '.xlsx'].contains(ext)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green[700]!;
    } else if (['.ppt', '.pptx'].contains(ext)) {
      iconData = Icons.slideshow;
      iconColor = Colors.orange[700]!;
    } else if (ext == '.txt') {
      iconData = Icons.text_snippet;
      iconColor = Colors.grey[700]!;
    }

    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          onTap: () async {
            if (isCached) {
              await _openDocument(url, message.id, ext);
            } else {
              // Download first
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) {
                  await _openDocument(url, message.id, ext);
                }
              } catch (e) {
                showCustomSnackBar(
                  context,
                  'Download failed: $e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () => _showMediaOptions(message, url),
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 250),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached
                    ? iconColor
                    : Colors.grey.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Document icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCached
                        ? iconColor.withValues(alpha: 0.2)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    iconData,
                    size: 28,
                    color: isCached ? iconColor : Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 12),
                // File info
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? 'Document',
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white
                              : Colors.black87,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDownloading
                            ? 'Downloading ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached
                                  ? ext.toUpperCase().replaceFirst('.', '')
                                  : 'Tap to download'),
                        style: TextStyle(
                          color: message.isSentByMe
                              ? Colors.white70
                              : Colors.grey[600],
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Action indicator
                if (isDownloading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: _downloadProgress[message.id],
                      strokeWidth: 2,
                      color: message.isSentByMe ? Colors.white : iconColor,
                    ),
                  )
                else
                  Icon(
                    isCached ? Icons.open_in_new : Icons.download_rounded,
                    size: 20,
                    color: message.isSentByMe ? Colors.white : iconColor,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
*/

  // Helper methods for opening media

  void _openImageViewer(String url, String messageId, {bool isLocal = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (!isLocal)
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  onPressed: () async {
                    final file = await _fetchAndCache(url, messageId);
                    if (file != null) {
                      await _saveToGallery(file);
                    }
                  },
                ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: url,
                placeholder: (context, url) =>
                    const CircularProgressIndicator(),
                errorWidget: (context, url, error) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 64,
                ),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openVideoPlayer(String url, String messageId) async {
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
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: VideoPlayerViewer(url: url, messageId: messageId),
            ),
          ),
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

  void _openAudioPlayer(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: AudioPlayerInline(
          message: message,
          fetchAndCache: _fetchAndCache,
        ),
      ),
    );
  }

  Future<void> _openDocument(String url, String messageId, String ext) async {
    try {
      final file = await _fetchAndCache(url, messageId);
      if (file == null) {
        showCustomSnackBar(
          context,
          'Document not available',
          type: SnackBarType.error,
        );
        return;
      }

      if (ext == '.pdf') {
        // Open PDF viewer
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) {
              final controller = PdfController(
                document: PdfDocument.openFile(file.path),
              );
              return Scaffold(
                appBar: AppBar(
                  title: Text(p.basename(file.path)),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        // Implement share functionality
                      },
                    ),
                  ],
                ),
                body: PdfView(controller: controller),
              );
            },
          ),
        );
      } else {
        // For other document types, try to open with system viewer
        final uri = Uri.file(file.path);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          showCustomSnackBar(
            context,
            'No app available to open this file type',
            type: SnackBarType.error,
          );
        }
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        'Failed to open document: $e',
        type: SnackBarType.error,
      );
    }
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
  // DEBUGGING: Add this method to help identify the issue
  // ============================================================================

  void _debugReplyMessage(Message message) {
    if (message.replyMessage != null) {
      print('🔍 DEBUG Reply Info:');
      print('  Current Message ID: ${message.id}');
      print('  Current Message Text: ${_parseMessage(message.message)}');
      print('  Reply To ID: ${message.replyTo}');
      print('  Reply Message ID: ${message.replyMessage!.id}');
      print(
        '  Reply Message Text: ${_parseMessage(message.replyMessage!.message)}',
      );
      print('  Reply Sender Name: ${message.replyMessage!.sender.name}');
      print('  Reply isSentByMe: ${message.replyMessage!.isSentByMe}');
    }
  }

  Widget _buildReplyMessage(Message replyMessage) {
    // Get the display name based on context
    String displayName;

    if (widget.isGroup) {
      // In group chat: always show sender's name
      displayName = replyMessage.sender.name;
    } else {
      // In personal chat: show "You" for your messages, contact name for theirs
      if (replyMessage.isSentByMe) {
        displayName = 'You';
      } else {
        displayName = widget.userName;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: AppClr.primaryColor, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            displayName,
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
    // ✅ CRITICAL: Wrap in BlocBuilder and set buildWhen to rebuild on block status changes
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, current) {
        // Rebuild when:
        // 1. State type changes (Loading -> Loaded, etc.)
        if (previous.runtimeType != current.runtimeType) return true;

        // 2. Block status changes
        if (previous is ChatLoaded && current is ChatLoaded) {
          return previous.isIBlockedThem != current.isIBlockedThem ||
              previous.isTheyBlockedMe != current.isTheyBlockedMe ||
              previous.groupData?.chatRequestStatus != current.groupData?.chatRequestStatus;
        }

        return true;
      },
      builder: (context, state) {
        print('🔄 Message input rebuilding - State: ${state.runtimeType}');

        // Check if blocked OR if chat request is pending
        final isBlocked =
            state is ChatLoaded &&
                (state.isIBlockedThem || state.isTheyBlockedMe);

        final isPendingRequest =
            state is ChatLoaded &&
                state.groupData?.chatRequestStatus == 'pending';

        final isDeclineRequest =
            state is ChatLoaded &&
                state.groupData?.chatRequestStatus == 'declined';

        // ✅ Add debug logging
        if (state is ChatLoaded) {
          print('📊 Block Status Debug:');
          print('   - isIBlockedThem: ${state.isIBlockedThem}');
          print('   - isTheyBlockedMe: ${state.isTheyBlockedMe}');
          print('   - Chat Request Status: ${state.groupData?.chatRequestStatus}');
          print('   - Should Show Blocked UI: $isBlocked');
        }

        // Show different messages based on state
        if (isBlocked) {
          final blockMessage = state is ChatLoaded && state.isIBlockedThem
              ? 'Messaging disabled – this user is blocked'
              : 'Messaging disabled – you are blocked by this user';

          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Center(
              child: Text(
                blockMessage,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        if (isPendingRequest) {
          final isRecipient =
              state is ChatLoaded &&
                  state.groupData?.chatRequestTo ==
                      SharedPreferencesHelper.getCurrentUserId().toString();

          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Center(
              child: Text(
                isRecipient
                    ? 'Accept the chat request to start messaging'
                    : 'Waiting for ${widget.userName} to accept your request',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }

        if (isDeclineRequest) {
          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Center(
              child: Text(
                'Chat request has been declined',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }

        // Normal message input (existing code)
        final cubit = context.read<ChatCubit>();
        final replyingTo = cubit.replyingToMessage;
        final editing = cubit.editingMessage;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply/Edit indicator
              if (replyingTo != null || editing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        editing != null ? Icons.edit : Icons.reply,
                        size: 20,
                        color: AppClr.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              editing != null
                                  ? 'Edit message'
                                  : 'Replying to ${replyingTo!.sender.name}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppClr.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _parseMessage(
                                editing?.message ?? replyingTo!.message,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          cubit.clearReplyEditMode();
                          _messageController.clear();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // Message input area
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
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
                              hintText: editing != null
                                  ? 'Edit message...'
                                  : 'Type a message...',
                              hintStyle: TextStyle(color: Colors.grey[500]),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (value) => _handleSendOrEdit(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Show attach button only when not editing
                      if (editing == null && _attachedFilePath == null) ...[
                        IconButton(
                          icon: const Icon(
                            Icons.attach_file,
                            color: Colors.grey,
                          ),
                          onPressed: _openFilePicker,
                        ),
                      ] else if (_attachedFilePath != null) ...[
                        GestureDetector(
                          onTap: () {
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
                                  : const Icon(
                                Icons.insert_drive_file,
                                size: 20,
                              )),
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
                          icon: Icon(
                            editing != null ? Icons.check : Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _handleSendOrEdit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  /*
  Widget _buildMessageInput() {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final isBlocked =
            state is ChatLoaded &&
                (state.isIBlockedThem || state.isTheyBlockedMe);

        if (isBlocked) {
          return Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Center(
              child: Text(
                'Messaging disabled – this user is blocked',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          );
        }

        final cubit = context.read<ChatCubit>();
        final replyingTo = cubit.replyingToMessage;
        final editing = cubit.editingMessage;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply/Edit indicator
              if (replyingTo != null || editing != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    border: Border(
                      bottom: BorderSide(color: Colors.grey[300]!),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        editing != null ? Icons.edit : Icons.reply,
                        size: 20,
                        color: AppClr.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              editing != null ? 'Edit message' : 'Replying to ${replyingTo!.sender.name}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppClr.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _parseMessage(editing?.message ?? replyingTo!.message),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          cubit.clearReplyEditMode();
                          _messageController.clear();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // Message input area
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                              hintText: editing != null ? 'Edit message...' : 'Type a message...',
                              hintStyle: TextStyle(color: Colors.grey[500]),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (value) => _handleSendOrEdit(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Show attach button only when not editing
                      if (editing == null && _attachedFilePath == null) ...[
                        IconButton(
                          icon: const Icon(Icons.attach_file, color: Colors.grey),
                          onPressed: _openFilePicker,
                        ),
                      ] else if (_attachedFilePath != null) ...[
                        GestureDetector(
                          onTap: () {
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
                                  : const Icon(
                                Icons.insert_drive_file,
                                size: 20,
                              )),
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
                          icon: Icon(
                            editing != null ? Icons.check : Icons.send,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: _handleSendOrEdit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
*/
  // attachment UI removed - only text messages supported
  Future<void> _handleSendOrEdit() async {
    // ✅ Prevent double submission
    if (_isSending) {
      print('⏳ Already sending, ignoring duplicate call');
      return;
    }

    final cubit = context.read<ChatCubit>();
    final editing = cubit.editingMessage;
    final replyingTo = cubit.replyingToMessage;

    final messageText = _messageController.text.trim();

    if (messageText.isEmpty && _attachedFilePath == null) return;

    // ✅ Set flag to prevent double submission
    setState(() {
      _isSending = true;
    });

    try {
      // EDIT MODE
      if (editing != null) {
        if (messageText.isEmpty) {
          showCustomSnackBar(
            context,
            'Message cannot be empty',
            type: SnackBarType.error,
          );
          return;
        }

        final htmlMessage = '<p>$messageText</p>';

        final error = await cubit.editMessage(
          messageId: editing.id,
          newMessage: htmlMessage,
        );

        if (error != null) {
          showCustomSnackBar(context, error, type: SnackBarType.error);
        } else {
          _messageController.clear();
          showCustomSnackBar(
            context,
            'Message updated',
            type: SnackBarType.success,
          );
          _scrollToBottom();
        }
        return;
      }

      // REPLY MODE
      if (replyingTo != null) {
        if (messageText.isEmpty) {
          showCustomSnackBar(
            context,
            'Reply cannot be empty',
            type: SnackBarType.error,
          );
          return;
        }

        final htmlMessage = '<p>$messageText</p>';

        final error = await cubit.sendReply(
          message: htmlMessage,
          replyToMessage: replyingTo,
        );

        if (error != null) {
          showCustomSnackBar(context, error, type: SnackBarType.error);
        } else {
          _messageController.clear();
          _scrollToBottom();
        }
        return;
      }

      // NORMAL SEND MODE
      await _sendMessage();
    } finally {
      // ✅ Always reset the flag
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  String _fingerprint(Message m) {
    final txt = _parseMessage(m.message);
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

        final bytes = resp.data; // List<int>? from DioClient.downloadBytes
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

  /*
  // Show actions for a message (Delete for me / Delete for everyone)
  void _showMessageActions(Message message) {
    final isSender = message.isSentByMe;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSender) ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for me'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete message'),
                        content: const Text('Delete this message for you?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    final prevId = _findPreviousMessageId(message.id);
                    final cubit = context.read<ChatCubit>();
                    final err = await cubit.deleteForMe(
                      conversationId: message.id,
                      previousMessageId: prevId ?? '',
                      targetMessageId: message.id,
                    );
                    if (err == null) {
                      showCustomSnackBar(
                        context,
                        'Message deleted',
                        type: SnackBarType.success,
                      );
                    } else {
                      showCustomSnackBar(
                        context,
                        err,
                        type: SnackBarType.error,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Delete for everyone'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete for everyone'),
                        content: const Text(
                          'This will remove the message for all participants. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final prevId = _findPreviousMessageId(message.id);
                    final cubit = context.read<ChatCubit>();
                    final err = await cubit.deleteForEveryone(
                      conversationId: message.id,
                      previousMessageId: prevId ?? '',
                      targetMessageId: message.id,
                    );
                    if (err == null) {
                      showCustomSnackBar(
                        context,
                        'Message deleted for everyone',
                        type: SnackBarType.success,
                      );
                    } else {
                      showCustomSnackBar(
                        context,
                        err,
                        type: SnackBarType.error,
                      );
                    }
                  },
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for me'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete message'),
                        content: const Text('Delete this message for you?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    final prevId = _findPreviousMessageId(message.id);
                    final cubit = context.read<ChatCubit>();
                    final err = await cubit.deleteForMe(
                      conversationId: message.id,
                      previousMessageId: prevId ?? '',
                      targetMessageId: message.id,
                    );
                    if (err == null) {
                      showCustomSnackBar(
                        context,
                        'Message deleted',
                        type: SnackBarType.success,
                      );
                    } else {
                      showCustomSnackBar(
                        context,
                        err,
                        type: SnackBarType.error,
                      );
                    }
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
*/
  void _showMessageActions(Message message) {
    final isSender = message.isSentByMe;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply option - shown for both sender and receiver
              ListTile(
                leading: const Icon(Icons.reply),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  // Set the message to reply to
                  context.read<ChatCubit>().setReplyingTo(message);
                  // Focus on the text field
                  _focusNode.requestFocus();
                },
              ),

              // Additional options only for sender (my messages)
              if (isSender) ...[
                // Only allow editing text messages (not files/media)
                if (message.messageType == 0 &&
                    message.message.isNotEmpty &&
                    (message.fileUrl == null || message.fileUrl!.isEmpty)) ...[
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit'),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      // Set the message to edit and populate text field
                      context.read<ChatCubit>().setEditingMessage(message);
                      _messageController.text = _parseMessage(message.message);
                      _focusNode.requestFocus();
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Delete for me'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete message'),
                        content: const Text('Delete this message for you?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    final prevId = _findPreviousMessageId(message.id);
                    final cubit = context.read<ChatCubit>();
                    final err = await cubit.deleteForMe(
                      conversationId: message.id,
                      previousMessageId: prevId ?? '',
                      targetMessageId: message.id,
                    );
                    if (err == null) {
                      showCustomSnackBar(
                        context,
                        'Message deleted',
                        type: SnackBarType.success,
                      );
                    } else {
                      showCustomSnackBar(
                        context,
                        err,
                        type: SnackBarType.error,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Delete for everyone'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Delete for everyone'),
                        content: const Text(
                          'This will remove the message for all participants. Continue?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true) return;

                    final prevId = _findPreviousMessageId(message.id);
                    final cubit = context.read<ChatCubit>();
                    final err = await cubit.deleteForEveryone(
                      conversationId: message.id,
                      previousMessageId: prevId ?? '',
                      targetMessageId: message.id,
                    );
                    if (err == null) {
                      showCustomSnackBar(
                        context,
                        'Message deleted for everyone',
                        type: SnackBarType.success,
                      );
                    } else {
                      showCustomSnackBar(
                        context,
                        err,
                        type: SnackBarType.error,
                      );
                    }
                  },
                ),
              ],

              // Cancel option - shown for everyone
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      },
    );
  } // Find previous message id in current loaded messages; returns null if none

  String? _findPreviousMessageId(String messageId) {
    final state = context.read<ChatCubit>().state;
    if (state is! ChatLoaded) return null;
    final msgs = state.messages;
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx <= 0) return '';
    return msgs[idx - 1].id;
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

// NEW: Local video player widget
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

// NEW: Local audio player widget
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
