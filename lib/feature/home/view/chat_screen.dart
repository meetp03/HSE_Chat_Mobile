import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/constants/api_urls.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/cores/utils/utils.dart';
import 'package:hec_chat/feature/home/bloc/chat_cubit.dart';
import 'package:hec_chat/feature/home/bloc/chat_state.dart';
import 'package:hec_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hec_chat/feature/home/model/conversation_model.dart'
    show Conversation;
import 'package:hec_chat/feature/home/model/message_model.dart';
import 'package:hec_chat/feature/home/widgets/user_info_screen.dart';
import 'package:open_file/open_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:hec_chat/cores/utils/file_validation.dart';
import 'package:hec_chat/cores/utils/snackbar.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:just_audio/just_audio.dart';
import 'package:dio/dio.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hec_chat/cores/utils/gallery_helper.dart';
import 'package:hec_chat/feature/home/widgets/audio_player_inline.dart';
import '../../../cores/utils/read_more_widget.dart';
import '../widgets/audio_player_inline_local.dart';
import '../widgets/video_player.dart';
import '../widgets/video_player_local.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String? userAvatar;
  final bool isGroup;
  final bool isOnline;
  final Conversation? groupData;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.userName,
    this.userAvatar,
    this.groupData,
    this.isGroup = false,
    this.isOnline = false,
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
          if (kDebugMode) {
            print('Error restoring scroll position: $e');
          }
        }
      }

      _scrollOffsetBeforeLoad = null;
      _messageCountBeforeLoad = null;
    });
  }

  void _initializeChat() {
    final currentUserId = SharedPreferencesHelper.getCurrentUserId();
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

  //  Get local file path for sent messages
  String? _getLocalFilePath(Message message) {
    if (!message.isSentByMe) return null;
    return _sentMessageLocalPaths[message.id];
  }

  // Check if file exists locally
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
        AppStrings.messagingDisabledBlocked,
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
        AppStrings.cannotSendTogether,
        type: SnackBarType.error,
      );
      return;
    }

    if (!hasFile && !hasText) return;

    if (hasFile) {
      final localPath = _attachedFilePath!;
      // Validate file
      try {
        final f = File(localPath);
        if (!await f.exists()) {
          showCustomSnackBar(
            context,
            AppStrings.selectedFileNotFound,
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
        ].contains(ext)) {
          category = FileCategory.IMAGE;
        } else if ([
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
        showCustomSnackBar(
          context,
          AppStrings.validationFailed,
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
        // Store local path mapping
        // Get the message ID from state after successful send
        final state = context.read<ChatCubit>().state;
        if (state is ChatLoaded && state.messages.isNotEmpty) {
          final lastMessage = state.messages.last;
          if (lastMessage.isSentByMe) {
            // Map message ID to local file path
            _sentMessageLocalPaths[lastMessage.id] = localPath;
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
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      final audioExt = ValidationRules.audioExt
          .map((e) => e.replaceFirst('.', ''))
          .toList();
      if (audioExt.contains(ext)) {
        showCustomSnackBar(
          context,
          AppStrings.audioNotSupported,
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
      if (type == 1) {
        category = FileCategory.IMAGE;
      } else if (type == 2)
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
      if (kDebugMode) {
        print('Error picking file: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return WillPopScope(
      onWillPop: () async {
        final state = context.read<ChatCubit>().state;
        if (state is ChatLoaded && state.messages.isNotEmpty) {
          final last = state.messages.last;
          try {
            context.read<ConversationCubit>().markMessageAsRead(
              last.id,
              widget.userId,
            );
          } catch (e) {
            if (kDebugMode) {
              print('Failed to notify ConversationCubit about read: $e');
            }
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
            if (kDebugMode) {
              print('Failed to notify ConversationCubit about read: $e');
            }
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
        AppStrings.invalidRequestId,
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
          widget.groupData,
        );

        showCustomSnackBar(
          context,
          AppStrings.chatRequestAccepted,
          type: SnackBarType.success,
        );
      } else {
        showCustomSnackBar(
          context,
          AppStrings.failedToAcceptRequest,
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(
          context,
          '${AppStrings.error}: $e',
          type: SnackBarType.error,
        );
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
        AppStrings.invalidRequestId,
        type: SnackBarType.error,
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.declineChatRequest),
        content: Text('${AppStrings.areYouSureDecline} ${widget.userName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              AppStrings.decline,
              style: TextStyle(color: AppClr.error),
            ),
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
          AppStrings.chatRequestDeclined,
          type: SnackBarType.info,
        );

        // Navigate back after declining
        Navigator.pop(context);
      } else {
        showCustomSnackBar(
          context,
          AppStrings.failedToDeclineRequest,
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        showCustomSnackBar(
          context,
          '${AppStrings.error}: $e',
          type: SnackBarType.error,
        );
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

        return Stack(
          children: [
            // Messages list
            _buildMessagesList(),

            //  Chat request overlay
            if (shouldShowOverlay)
              Positioned.fill(
                child: Container(
                  color: AppClr.chatRequestOverlay,
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
                              AppStrings.chatRequest,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: AppClr.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${widget.userName} ${AppStrings.wantsToStartConversation}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: AppClr.gray700,
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
                                      side: const BorderSide(
                                        color: AppClr.declineButtonBorder,
                                      ),
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
                                                    AppClr.declineButtonBorder,
                                                  ),
                                            ),
                                          )
                                        : Text(
                                            AppStrings.decline,
                                            style: TextStyle(
                                              color: AppClr.declineButtonBorder,
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
                                                    AppClr.white,
                                                  ),
                                            ),
                                          )
                                        : Text(
                                            AppStrings.accept,
                                            style: TextStyle(
                                              color: AppClr.white,
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
        icon: const Icon(Icons.arrow_back, color: AppClr.white),
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
              if (kDebugMode) {
                print('Failed to notify ConversationCubit about read: $e');
              }
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
              if (kDebugMode) {
                print(
                'Failed to forward last message to ConversationCubit on back: $e',
              );
              }
            }
          }
          Navigator.pop(context, null);
        },
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppClr.white.withAlpha(60),
            backgroundImage: widget.userAvatar != null
                ? CachedNetworkImageProvider(widget.userAvatar!)
                : null,
            child: widget.userAvatar == null
                ? Text(
                    Utils.getInitials(widget.userName),
                    style: const TextStyle(
                      color: AppClr.white,
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
                    color: AppClr.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                BlocBuilder<ChatCubit, ChatState>(
                  builder: (context, state) {
                    if (state is ChatLoaded) {
                      return Text(
                        (!widget.isGroup && widget.isOnline)
                            ? AppStrings.online
                            : (widget.isGroup
                                  ? AppStrings.group
                                  : AppStrings.offline),
                        style: const TextStyle(
                          color: AppClr.textWhite70,
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
          icon: const Icon(Icons.info_outline, color: AppClr.white),
          onSelected: (value) {
            if (value == 'info') {
              _openUserInfo();
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'info',
              child: Row(
                children: [
                  Text(
                    widget.isGroup ? AppStrings.groupInfo : AppStrings.userInfo,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openUserInfo() {
    final cubit = context.read<ChatCubit>();
    final state = cubit.state;
    final isICurrentlyBlockedThisUser = (state is ChatLoaded)
        ? state.isIBlockedThem
        : false;
    final isThemCurrentlyBlockedMe = (state is ChatLoaded)
        ? state.isTheyBlockedMe
        : false;
    final groupModel = (state is ChatLoaded) ? state.commonGroupData : null;

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
      //  Rebuild when messages change
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
                const Icon(Icons.error_outline, size: 64, color: AppClr.error),
                const SizedBox(height: 16),
                Text('${AppStrings.error}: ${state.message}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _initializeChat,
                  child: const Text(AppStrings.retry),
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
                    color: AppClr.gray400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStrings.noMessagesYet,
                    style: TextStyle(color: AppClr.gray600, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.startConversation,
                    style: TextStyle(color: AppClr.gray500, fontSize: 14),
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

              // Use ValueKey to help Flutter identify when message content changes
              return KeyedSubtree(
                key: ValueKey(
                  '${msg.id}_${msg.updatedAt.millisecondsSinceEpoch}',
                ),
                child: _buildMessageBubble(msg),
              );
            },
          );
        }

        return Center(child: Text(AppStrings.noMessagesYet));
      },
    );
  }

  Widget _buildMessageBubble(Message message) {
    final kind = message.kind();

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
                color: AppClr.systemMessageBackground,
                border: Border.all(color: AppClr.systemMessageBorder, width: 1),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: message.isSentByMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
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

          // Message bubble - wraps content tightly
          Flexible(
            child: IntrinsicWidth(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72,
                ),
                child: GestureDetector(
                  onLongPress: () {
                    _showMessageActions(message);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: message.isSentByMe
                          ? AppClr.sentMessageColor
                          : AppClr.incomingMessageColor,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: message.isSentByMe
                            ? Radius.circular(18)
                            : Radius.circular(4),
                        bottomRight: message.isSentByMe
                            ? Radius.circular(4)
                            : Radius.circular(18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppClr.black.withAlpha(13),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: message.isSentByMe
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
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

                        // Message content (media or text)
                        if (kind != MessageKind.TEXT)
                          _buildMessageContent(message),

                        // Text messages with read more
                        if (kind == MessageKind.TEXT) ...[
                          ReadMoreHtml(
                            htmlContent: message.message,
                            maxLines: 6,
                          ),
                          const SizedBox(height: 4),
                        ],

                        // Timestamp and status
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.chatTime,
                              style: TextStyle(
                                color: message.isSentByMe
                                    ? AppClr.messageTimeColor
                                    : AppClr.gray600,
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
                                    ? AppClr.messageError
                                    : (message.status == 1
                                          ? AppClr.messageDelivered
                                          : AppClr.messageSent),
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

  //  Already has gesture handling
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
                _openImageViewerLocal(localPath, message.id);
              },
              onLongPress: () {
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
          onLongPress: () {
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
                          color: AppClr.imagePlaceholder,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          width: 200,
                          height: 150,
                          color: AppClr.imagePlaceholder,
                          child: const Icon(Icons.broken_image, size: 40),
                        ),
                      )
                    : Container(
                        width: 200,
                        height: 150,
                        color: AppClr.imagePlaceholder,
                        child: Icon(Icons.image, size: 48, color: AppClr.white),
                      ),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppClr.black.withOpacity(0.38),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? CircularProgressIndicator(
                            value: _downloadProgress[message.id],
                            backgroundColor: AppClr.white,
                            color: AppClr.white,
                          )
                        : const Icon(
                            Icons.download_rounded,
                            size: 40,
                            color: AppClr.white,
                          ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

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
                _openVideoPlayerLocal(localPath, message.id);
              },
              onLongPress: () {
                _showSenderMediaOptions(message, localPath);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 150,
                    decoration: BoxDecoration(
                      color: AppClr.videoBackground.withOpacity(0.87),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.videocam, size: 48, color: AppClr.white),
                  ),
                  const Icon(
                    Icons.play_circle_fill,
                    size: 56,
                    color: AppClr.white,
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
                  '${AppStrings.failedToOpenVideo}$e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () {
            _showMediaOptions(message, url);
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200,
                height: 150,
                decoration: BoxDecoration(
                  color: AppClr.videoBackground.withOpacity(0.87),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.videocam, size: 48, color: AppClr.white),
              ),
              if (!isCached)
                Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppClr.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: isDownloading
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: _downloadProgress[message.id],
                                backgroundColor: AppClr.white,
                                color: AppClr.white,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_downloadProgress[message.id]! * 100).toInt()}%',
                                style: const TextStyle(
                                  color: AppClr.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : const Icon(
                            Icons.cloud_download,
                            size: 40,
                            color: AppClr.white,
                          ),
                  ),
                )
              else
                const Icon(
                  Icons.play_circle_fill,
                  size: 56,
                  color: AppClr.white,
                ),
            ],
          ),
        );
      },
    );
  }

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
          _openAudioPlayerLocal(message, localPath);
        },
        onLongPress: () {
          _showSenderMediaOptions(message, localPath);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: message.isSentByMe
                ? AppClr.white.withAlpha(51) // 20% opacity
                : AppClr.gray100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppClr.audioBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppClr.audioIconBackground,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.headphones,
                  size: 20,
                  color: AppClr.white,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.fileName ?? AppStrings.audio,
                      style: TextStyle(
                        color: message.isSentByMe
                            ? AppClr.white
                            : AppClr.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppStrings.tapToPlay,
                      style: TextStyle(
                        color: message.isSentByMe
                            ? AppClr.white
                            : AppClr.gray600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.play_arrow,
                size: 24,
                color: AppClr.audioIconBackground,
              ),
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
            if (isCached) {
              _openAudioPlayer(message);
            } else {
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) _openAudioPlayer(message);
              } catch (e) {
                showCustomSnackBar(
                  context,
                  '${AppStrings.downloadFailed}$e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          onLongPress: () {
            _showMediaOptions(message, url);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? AppClr.white.withAlpha(51)
                  : AppClr.gray100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached ? AppClr.audioBorder : AppClr.gray300,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isCached
                        ? AppClr.audioIconBackground
                        : AppClr.gray300,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDownloading
                        ? Icons.downloading
                        : (isCached ? Icons.headphones : Icons.audiotrack),
                    size: 20,
                    color: AppClr.white,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.fileName ?? AppStrings.audio,
                        style: TextStyle(
                          color: message.isSentByMe
                              ? AppClr.white
                              : AppClr.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isDownloading
                            ? '${AppStrings.downloading} ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached
                                  ? AppStrings.tapToPlay
                                  : AppStrings.tapToDownload),
                        style: TextStyle(
                          color: message.isSentByMe
                              ? AppClr.white
                              : AppClr.gray600,
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
                      color: message.isSentByMe
                          ? AppClr.white
                          : AppClr.audioIconBackground,
                    ),
                  )
                else
                  Icon(
                    isCached ? Icons.play_arrow : Icons.download_rounded,
                    size: 24,
                    color: message.isSentByMe
                        ? AppClr.white
                        : AppClr.audioIconBackground,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  //  Open local image viewer
  void _openImageViewerLocal(String localPath, String messageId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppClr.black,
          appBar: AppBar(
            backgroundColor: AppClr.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppClr.white),
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

  // Open local video player
  Future<void> _openVideoPlayerLocal(String localPath, String messageId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppClr.black,
          appBar: AppBar(
            backgroundColor: AppClr.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppClr.white),
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

  //  Open local audio player
  void _openAudioPlayerLocal(Message message, String localPath) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppClr.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppClr.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(20),
        child: AudioPlayerInlineLocal(message: message, localPath: localPath),
      ),
    );
  }

  // Sender-specific media options (no download option)
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
                title: const Text(AppStrings.fileStoredLocally),
                subtitle: Text(localPath, style: const TextStyle(fontSize: 11)),
                enabled: false,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text(AppStrings.saveToGallery),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _saveToGallery(File(localPath));
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
    Color iconColor = AppClr.info;

    if (ext == '.pdf') {
      iconData = Icons.picture_as_pdf;
      iconColor = AppClr.error;
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
      iconColor = AppClr.gray700;
    }

    return FutureBuilder<FileInfo?>(
      future: DefaultCacheManager().getFileFromCache(url),
      builder: (context, snapshot) {
        final isCached = snapshot.data != null;
        final isDownloading =
            _downloadProgress[message.id] != null &&
            _downloadProgress[message.id]! < 1.0;

        return GestureDetector(
          //  Auto download and open (same as before on long press)
          onTap: () async {
            if (isCached) {
              // File already downloaded, just open it
              await _openDocument(url, message.id, ext);
            } else {
              // Download first, then open
              try {
                await _fetchAndCache(url, message.id);
                if (mounted) {
                  await _openDocument(url, message.id, ext);
                }
              } catch (e) {
                showCustomSnackBar(
                  context,
                  '${AppStrings.downloadFailed}$e',
                  type: SnackBarType.error,
                );
              }
            }
          },
          // LONG PRESS: Show options (download/cancel)
          onLongPress: () {
            _showMediaOptions(message, url);
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxWidth: 250),
            decoration: BoxDecoration(
              color: message.isSentByMe
                  ? AppClr.white.withAlpha(51)
                  : AppClr.gray100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCached ? iconColor : AppClr.gray300,
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
                        ? iconColor.withAlpha(51)
                        : AppClr.gray200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    iconData,
                    size: 28,
                    color: isCached ? iconColor : AppClr.gray600,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.message,
                        style: const TextStyle(
                          color: AppClr.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDownloading
                            ? '${AppStrings.downloading} ${(_downloadProgress[message.id]! * 100).toInt()}%'
                            : (isCached
                                  ? ext.toUpperCase().replaceFirst('.', '')
                                  : AppStrings.tapToDownload),
                        style: TextStyle(
                          color: isCached
                              ? iconColor
                              : AppClr.info,
                          fontSize: 11,
                          fontWeight: isCached
                              ? FontWeight.w600
                              : FontWeight.normal,
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
                      color: iconColor,
                    ),
                  )
                else
                  Icon(
                    isCached
                        ? Icons
                              .file_present
                        : Icons
                              .download_rounded,
                    size: 20,
                    color: isCached ? iconColor : AppClr.gray600,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
  // Helper methods for opening media

  void _openImageViewer(String url, String messageId, {bool isLocal = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppClr.black,
          appBar: AppBar(
            backgroundColor: AppClr.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: AppClr.white),
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
                  color: AppClr.white,
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
          AppStrings.videoNotAvailable,
          type: SnackBarType.error,
        );
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: AppClr.black,
            appBar: AppBar(
              backgroundColor: AppClr.transparent,
              elevation: 0,
              iconTheme: const IconThemeData(color: AppClr.white),
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
        '${AppStrings.failedToOpenVideo}$e',
        type: SnackBarType.error,
      );
    }
  }

  void _openAudioPlayer(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppClr.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppClr.white,
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

  void _showNoAppAvailableDialog(String filePath, String ext) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.noAppAvailable),
        content: Text(
          '${AppStrings.noAppFound}\n\n'
          '${AppStrings.installAppMessage}\n\n'
          '${AppStrings.fileSavedAt} ${p.basename(filePath)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _openDocument(String url, String messageId, String ext) async {
    try {
      final file = await _fetchAndCache(url, messageId);
      if (file == null) {
        showCustomSnackBar(
          context,
          AppStrings.documentNotAvailable,
          type: SnackBarType.error,
        );
        return;
      }

      final result = await OpenFile.open(file.path);

      if (result.type != ResultType.done) {
        // If open_file fails, show appropriate message
        if (result.type == ResultType.noAppToOpen) {
          _showNoAppAvailableDialog(file.path, ext);
        } else {
          showCustomSnackBar(
            context,
            '${AppStrings.failedToOpenDocument} ${result.message}',
            type: SnackBarType.error,
          );
        }
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        '${AppStrings.failedToOpenDocument}$e',
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

  Widget _buildReplyMessage(Message replyMessage) {
    // Get the display name based on context
    String displayName;

    if (widget.isGroup) {
      // In group chat: always show sender's name
      displayName = replyMessage.sender.name;
    } else {
      // In personal chat: show "You" for your messages, contact name for theirs
      if (replyMessage.isSentByMe) {
        displayName = AppStrings.you;
      } else {
        displayName = widget.userName;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppClr.replyBackground,
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

    // Work on a trimmed copy
    String html = message.trim();

    // Remove useless empty paragraphs and &nbsp;
    html = html
        .replaceAll(RegExp(r'<p>\s*&nbsp;\s*</p>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<p>\s*</p>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '')
        .trim();

    if (html.isEmpty) return '';

    // Detect if message contains an image
    final bool hasImage =
        html.contains('<img') ||
        html.toLowerCase().contains('class="image"') ||
        html.toLowerCase().contains("class='image'");

    // Extract plain text (strip all HTML tags)
    String plainText = html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Decode HTML entities (your existing logic – keep it!)
    plainText = plainText
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    plainText = plainText.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      try {
        return String.fromCharCode(int.parse(m[1]!));
      } catch (_) {
        return '';
      }
    });
    plainText = plainText.replaceAllMapped(RegExp(r'&#x([0-9A-Fa-f]+);'), (m) {
      try {
        return String.fromCharCode(int.parse(m[1]!, radix: 16));
      } catch (_) {
        return '';
      }
    });

    plainText = plainText.trim();

    // Final decision
    if (hasImage && plainText.isEmpty) {
      return AppStrings.photoLabel; // Only image
    }
    if (hasImage && plainText.isNotEmpty) {
      return AppStrings.photoLabel;
    }

    return plainText.isEmpty ? AppStrings.message : plainText;
  }

  Widget _buildMessageInput() {
    // Wrap in BlocBuilder and set buildWhen to rebuild on block status changes
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, current) {
        // Rebuild when:
        // 1. State type changes (Loading -> Loaded, etc.)
        if (previous.runtimeType != current.runtimeType) return true;

        // 2. Block status changes
        if (previous is ChatLoaded && current is ChatLoaded) {
          return previous.isIBlockedThem != current.isIBlockedThem ||
              previous.isTheyBlockedMe != current.isTheyBlockedMe ||
              previous.groupData?.chatRequestStatus !=
                  current.groupData?.chatRequestStatus;
        }

        return true;
      },
      builder: (context, state) {

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

        // Show different messages based on state
        if (isBlocked) {
          final blockMessage = state.isIBlockedThem
              ? AppStrings.messagingDisabledBlocked
              : AppStrings.messagingDisabledYouBlocked;

          return Container(
            padding: const EdgeInsets.all(12),
            color: AppClr.white,
            child: Center(
              child: Text(
                blockMessage,
                style: TextStyle(color: AppClr.gray600),
              ),
            ),
          );
        }

        if (isPendingRequest) {
          final isRecipient =
              state.groupData?.chatRequestTo ==
              SharedPreferencesHelper.getCurrentUserId().toString();

          return Container(
            padding: const EdgeInsets.all(12),
            color: AppClr.white,
            child: Center(
              child: Text(
                isRecipient
                    ? AppStrings.acceptToStartMessaging
                    : '${AppStrings.waitingForAcceptance} ${widget.userName}',
                style: TextStyle(
                  color: AppClr.gray600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }

        if (isDeclineRequest) {
          return Container(
            padding: const EdgeInsets.all(12),
            color: AppClr.white,
            child: Center(
              child: Text(
                AppStrings.chatRequestDeclinedStatus,
                style: TextStyle(
                  color: AppClr.gray600,
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
            color: AppClr.white,
            boxShadow: [
              BoxShadow(
                color: AppClr.black.withAlpha(13), // 5% opacity
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
                    color: AppClr.gray100,
                    border: Border(bottom: BorderSide(color: AppClr.gray300)),
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
                                  ? AppStrings.editMessageTitle
                                  : '${AppStrings.replyingTo} ${replyingTo!.sender.name}',
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
                                color: AppClr.gray600,
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
                            color: AppClr.gray100,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: TextField(
                            controller: _messageController,
                            focusNode: _focusNode,
                            decoration: InputDecoration(
                              hintText: editing != null
                                  ? AppStrings.editMessage
                                  : AppStrings.typeMessage,
                              hintStyle: TextStyle(color: AppClr.gray500),
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
                          icon: Icon(Icons.attach_file, color: AppClr.gray500),
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
                              color: AppClr.gray200,
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
                            color: AppClr.white,
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

  Future<void> _handleSendOrEdit() async {
    // Prevent double submission
    if (_isSending) {
      return;
    }

    final cubit = context.read<ChatCubit>();
    final editing = cubit.editingMessage;
    final replyingTo = cubit.replyingToMessage;

    final messageText = _messageController.text.trim();

    if (messageText.isEmpty && _attachedFilePath == null) return;

    //  Set flag to prevent double submission
    setState(() {
      _isSending = true;
    });

    try {
      // EDIT MODE
      if (editing != null) {
        if (messageText.isEmpty) {
          showCustomSnackBar(
            context,
            AppStrings.messageCannotBeEmpty,
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
            AppStrings.messageUpdated,
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
            AppStrings.replyCannotBeEmpty,
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
      //  Always reset the flag
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
        debugPrint('Cache hit for: $url (messageId:$messageId)');
        return cached.file;
      }
    } catch (e) {
      debugPrint('Cache check failed for $url: $e');
      // proceed to download
    }

    // If an identical fetch is already in progress, return that future
    if (_fetchFutures.containsKey(url)) {
      debugPrint('Reusing in-flight download for: $url');
      return _fetchFutures[url];
    }

    // Create the download future and store it so concurrent callers reuse it
    final future = (() async {
      final dio = DioClient();
      final cancelToken = CancelToken();
      _downloadTokens[messageId] = cancelToken;

      debugPrint('⬇Starting download: $url (messageId:$messageId)');
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
        debugPrint('Download complete: $url');
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
      if (saved) {
        showCustomSnackBar(
          context,
          AppStrings.savedToGallery,
          type: SnackBarType.success,
        );
      } else {
        showCustomSnackBar(
          context,
          AppStrings.failedToSaveToGallery,
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      showCustomSnackBar(
        context,
        'Error saving file: $e',
        type: SnackBarType.error,
      );
    }
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
                title: Text(
                  downloading ? AppStrings.cancelDownload : AppStrings.download,
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  if (downloading) {
                    final token = _downloadTokens[message.id];
                    token?.cancel('user_cancel');
                    _downloadProgress.remove(message.id);
                    setState(() {});
                    showCustomSnackBar(
                      context,
                      AppStrings.downloadCancelled,
                      type: SnackBarType.info,
                    );
                  } else {
                    try {
                      await _fetchAndCache(url, message.id);
                      setState(() {});
                      showCustomSnackBar(
                        context,
                        AppStrings.downloaded,
                        type: SnackBarType.success,
                      );
                    } catch (e) {
                      showCustomSnackBar(
                        context,
                        '${AppStrings.downloadFailed}$e',
                        type: SnackBarType.error,
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                title: const Text(AppStrings.reply),
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
                if (message.messageType == 0 &&
                    !message.message.trim().toLowerCase().contains(
                      'this message was deleted',
                    ) &&
                    !message.message.trim().toLowerCase().contains(
                      'message deleted',
                    ) &&
                    message.message.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text(AppStrings.edit),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.read<ChatCubit>().setEditingMessage(message);
                      _messageController.text = _parseMessage(message.message);
                      _focusNode.requestFocus();
                    },
                  ),

                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text(AppStrings.deleteForMe),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text(AppStrings.deleteMessage),
                        content: const Text(AppStrings.deleteForYouQuestion),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(false),
                            child: const Text(AppStrings.cancel),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dctx).pop(true),
                            child: const Text(AppStrings.confirmDelete),
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
                        AppStrings.messageDeleted,
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
                if (message.messageType == 0 &&
                    !message.message.trim().toLowerCase().contains(
                      'this message was deleted',
                    ) &&
                    !message.message.trim().toLowerCase().contains(
                      'message deleted',
                    ) &&
                    message.message.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.delete_forever),
                    title: const Text(AppStrings.deleteForEveryone),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text(AppStrings.deleteForEveryone),
                          content: const Text(
                            AppStrings.deleteForEveryoneQuestion,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(false),
                              child: const Text(AppStrings.cancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(dctx).pop(true),
                              child: const Text(AppStrings.confirmDelete),
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
                          AppStrings.messageDeletedForEveryone,
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
                title: const Text(AppStrings.cancel),
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
