import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/api_urls.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/home/bloc/chat_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/chat_state.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot send text and file together.')));
      return;
    }

    if (!hasFile && !hasText) return;

    if (hasFile) {
      final path = _attachedFilePath!;
      print('📤 Sending file: $path');
      await context.read<ChatCubit>().sendMessage(message: '', filePath: path);
      // clear attachment after sending
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
    await context.read<ChatCubit>().sendMessage(message: message);
    _messageController.clear();
    _scrollToBottom();
  }

  Future<void> _openFilePicker() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null) return;
      final file = result.files.first;
      if (file.path == null) return;
      final path = file.path!;

      final lower = path.toLowerCase();
      final imageExt = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'];
      final videoExt = ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'];
      int type = 4;
      for (var e in imageExt) if (lower.endsWith(e)) type = 1;
      for (var e in videoExt) if (lower.endsWith(e)) type = 2;

      // If user has typed text, prevent attaching
      if (_messageController.text.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please clear text before attaching a file.')));
        return;
      }

      setState(() {
        _attachedFilePath = path;
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
              }
            };
            context.read<ConversationCubit>().processRawMessage(payload);
          } catch (e) {
            print('⚠️ Failed to forward last message to ConversationCubit on pop: $e');
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
                }
              };
              context.read<ConversationCubit>().processRawMessage(payload);
            } catch (e) {
              print('⚠️ Failed to forward last message to ConversationCubit on back: $e');
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
                ? Icon(
                    widget.isGroup ? Icons.group : Icons.person,
                    size: 18,
                    color: Colors.white,
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
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onSelected: (value) {
            // Handle menu actions
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'info', child: Text('View Info')),
            const PopupMenuItem(value: 'mute', child: Text('Mute')),
            const PopupMenuItem(value: 'clear', child: Text('Clear Chat')),
          ],
        ),
      ],
    );
  }

  Widget _buildMessagesList() {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        // Only act on ChatLoaded states
        if (state is! ChatLoaded) return;

        // If we're in the middle of requesting older messages, wait until
        // the loading flag is cleared, then restore the previous scroll
        // position. Also, when isLoadingMore is true, don't auto-scroll.
        if (state.isLoadingMore) return;

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
      // Centered full-row system message styled as a blue pill with white text.
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
                color: Color(0xFFBFDBFE),
                border: Border.all(
                  color: const Color(0xff1E40AF).withValues(alpha: .5),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _parseMessage(message.message),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff1E40AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
                        color: Colors.black.withAlpha((0.05 * 255).round()),
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
                              if (kind == MessageKind.IMAGE) {
                                final url = _buildMediaUrl(message);
                                if (url != null && url.isNotEmpty) {
                                  showDialog(
                                    context: ctx,
                                    builder: (_) => Dialog(
                                      child: GestureDetector(
                                        onTap: () => Navigator.pop(ctx),
                                        child: CachedNetworkImage(
                                          imageUrl: url,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } else if (kind == MessageKind.VIDEO) {
                                final url = _buildMediaUrl(message);
                                if (url != null && url.isNotEmpty) {
                                  showDialog(
                                    context: ctx,
                                    builder: (_) => Dialog(
                                      child: Container(
                                        width: 400,
                                        height: 300,
                                        color: Colors.black,
                                        child: Center(
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.play_circle_fill,
                                              size: 64,
                                              color: Colors.white,
                                            ),
                                            onPressed: () async {
                                              if (await canLaunchUrl(
                                                Uri.parse(url),
                                              ))
                                                await launchUrl(Uri.parse(url));
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              } else if (kind == MessageKind.FILE ||
                                  kind == MessageKind.AUDIO) {
                                final url = message.fileUrl;
                                if (url != null &&
                                    url.isNotEmpty &&
                                    await canLaunchUrl(Uri.parse(url))) {
                                  await launchUrl(Uri.parse(url));
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

    // Use an if/else chain instead of switch to avoid exhaustive-match issues
    if (kind == MessageKind.SYSTEM) {
      return const SizedBox.shrink();
    } else if (kind == MessageKind.IMAGE) {
      final url = _buildMediaUrl(message);
      if (url == null || url.isEmpty) return const SizedBox.shrink();
      return GestureDetector(
        onTap: () async {
          if (await canLaunchUrl(Uri.parse(url))) {
            await launchUrl(Uri.parse(url));
          }
          print('🖼️ Image tapped: $url');
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
      return GestureDetector(
        onTap: () async {
          if (await canLaunchUrl(Uri.parse(url)))
            await launchUrl(Uri.parse(url));
        },
        child: Stack(
          alignment: Alignment.center,
          children: const [
            SizedBox(
              width: 200,
              height: 120,
              child: ColoredBox(color: Colors.black12),
            ),
            Icon(Icons.play_circle_fill, size: 48, color: Colors.white70),
          ],
        ),
      );
    } else if (kind == MessageKind.AUDIO) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            onPressed: () async {
              final url = message.fileUrl;
              if (url != null && await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            },
          ),
          Text(message.fileName ?? 'Audio'),
        ],
      );
    } else if (kind == MessageKind.FILE) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file, size: 20),
          const SizedBox(width: 8),
          Flexible(child: Text(message.fileName ?? 'File')),
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            onPressed: () async {
              final url = message.fileUrl;
              if (url != null && await canLaunchUrl(Uri.parse(url))) {
                await launchUrl(Uri.parse(url));
              }
            },
          ),
        ],
      );
    }

    // TEXT and any unknown kinds: render nothing here (text is rendered below)
    return const SizedBox.shrink();
  }

  String? _extractFirstImgSrc(String html) {
    final pattern = "<img[^>]+src=[\"']?([^\"'>]+)[\"']?";
    final reg = RegExp(pattern, caseSensitive: false);
    final m = reg.firstMatch(html);
    return m?.group(1);
  }

  String? _extractFirstVideoSrc(String html) {
    final pattern = "<video[^>]+src=[\"']?([^\"'>]+)[\"']?";
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
        color: Colors.black.withAlpha((0.1 * 255).round()),
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
            color: Colors.black.withAlpha((0.05 * 255).round()),
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
                        : (_attachedFileType == 2 ? const Icon(Icons.videocam, size: 20) : const Icon(Icons.insert_drive_file, size: 20)),
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
    return '${m.fromId}|$txt|${m.fileUrl ?? ''}|${m.messageType}';
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
}
