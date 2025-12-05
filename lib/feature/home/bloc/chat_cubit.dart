import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/socket_service.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/home/bloc/chat_state.dart';
import 'package:hec_chat/feature/home/model/conversation_model.dart' show Conversation;
import 'package:hec_chat/feature/home/model/message_model.dart';
import 'package:hec_chat/feature/home/model/chat_models.dart';
import 'package:hec_chat/feature/home/repository/chat_repository.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class ChatCubit extends Cubit<ChatState> {
  final IChatRepository _chatRepository;
  final SocketService _socketService;
  StreamSubscription? _socketSubscription;
  // Generic fallback listener registered with SocketService.addMessageListener
  Function(dynamic)? _genericSocketListener;

  int _currentPage = 1;
  final int _limit = 15;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  String? _otherUserId;
  bool? _isGroup;

  ChatCubit({
    required IChatRepository chatRepository,
    required SocketService socketService,
  }) : _chatRepository = chatRepository,
       _socketService = socketService,
       super(ChatInitial()){
// Listen ONCE when cubit is created – global block/unblock
    _socketService.onBlockUnblock((data) {
      _handleBlockUnblockEvent(data);
    });
  }

  int get currentUserId => SharedPreferencesHelper.getCurrentUserId();

  Message? _replyingToMessage;
  Message? _editingMessage;

  // Get the message being replied to
  Message? get replyingToMessage => _replyingToMessage;

  // Get the message being edited
  Message? get editingMessage => _editingMessage;

  // Set a message to reply to
  void setReplyingTo(Message? message) {
    _replyingToMessage = message;
    _editingMessage = null; // Clear edit mode when replying
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(currentState.copyWith(messages: currentState.messages));
    }
  }

  // Set a message to edit
  void setEditingMessage(Message? message) {
    _editingMessage = message;
    _replyingToMessage = null; // Clear reply mode when editing
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(currentState.copyWith(messages: currentState.messages));
    }
  }

  // Clear reply/edit mode
  void clearReplyEditMode() {
    _replyingToMessage = null;
    _editingMessage = null;
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      emit(currentState.copyWith(messages: currentState.messages));
    }
  }

  // Edit an existing message
  Future<String?> editMessage({
    required String messageId,
    required String newMessage,
  }) async {
    if (state is! ChatLoaded) return 'Chat not loaded';

    try {

      final response = await _chatRepository.editMessage(
        messageId: messageId,
        newMessage: newMessage,
      );

      if (response.success && response.data != null) {
        final updatedMessageData = response.data!.data.message;
        final updatedMessage = Message.fromJson(
          updatedMessageData,
          currentUserId,
        );

        // Update the message in the list
        if (state is ChatLoaded) {
          final currentState = state as ChatLoaded;
          final updatedMessages = currentState.messages.map((msg) {
            return msg.id == messageId ? updatedMessage : msg;
          }).toList();

          emit(currentState.copyWith(messages: updatedMessages));
        }

        // Clear editing mode
        clearReplyEditMode();

        if (kDebugMode) {
          print('✅ Message edited successfully');
        }
        return null;
      } else {
        return response.message ?? 'Failed to edit message';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error editing message: $e');
      }
      return 'Failed to edit message: $e';
    }
  }

  // Send a reply to a message
  Future<String?> sendReply({
    required String message,
    required Message replyToMessage,
  }) async {
    if (state is! ChatLoaded || _otherUserId == null || _isGroup == null) {
      return 'Invalid chat state';
    }

    try {
      if (kDebugMode) {
        print('Sending reply to message: ${replyToMessage.id}');
      }

      // Use the full MongoDB _id directly
      final replyToId = replyToMessage.id;

      final response = await _chatRepository.replyToMessage(
        conversationId: _otherUserId!,
        message: message,
        replyToMessageId: replyToId,
        toId: _otherUserId!,
        isGroup: _isGroup ?? false,
      );

      if (response.success && response.data != null) {
        final messageData = response.data!.data.message;
        final newMessage = Message.fromJson(messageData, currentUserId);

        // Add the new reply message to the list
        if (state is ChatLoaded) {
          final currentState = state as ChatLoaded;
          final updatedMessages = [...currentState.messages, newMessage];
          final dedupedMessages = _dedupeMessages(updatedMessages);

          emit(currentState.copyWith(messages: dedupedMessages));
        }

        // Clear reply mode
        clearReplyEditMode();

        if (kDebugMode) {
          print('Reply sent successfully');
        }
        return null;
      } else {
        return response.message ?? 'Failed to send reply';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending reply: $e');
      }
      return 'Failed to send reply: $e';
    }
  }


  Future<void> loadConversations(
      int userId,
      String otherUserId,
      bool isGroup,
      Conversation? initialConversationData,
      ) async {
    try {
      emit(ChatLoading());

      final response = await _chatRepository.getConversations(
        userId: userId,
        otherUserId: otherUserId,
        isGroup: isGroup,
        page: 1,
        limit: _limit,
      );

      if (response.success && response.data != null) {
        // Pass currentUserId (not group ID) for proper alignment
        // Server returns conversations in newest->oldest. Convert to
        // oldest->newest for UI-friendly chronological ordering.
        final raw = (response.data?.data.conversations ?? [])
            .map((json) => Message.fromJson(json, userId))
            .toList()
            .reversed
            .toList();

        // Deduplicate loaded messages (server sometimes returns repeats)
        final conversations = _dedupeMessages(raw);

        final conversationId = isGroup
            ? (response.data?.data.group['id']?.toString() ?? otherUserId)
            : otherUserId;

        _otherUserId = conversationId;
        _isGroup = isGroup;
        _currentPage = 1;
        _hasMore = response.data?.meta.hasMore ?? false;

        if (kDebugMode) {
          print('Loaded ${conversations.length} messages');
        }
        if (conversations.isNotEmpty) {
          final first = conversations.first;
          final last = conversations.last;
          if (kDebugMode) {
            print(
            'Conversation order: first(createdAt)=${first.createdAt.toIso8601String()} id=${first.id} isSentByMe=${first.isSentByMe}',
          );
          }
          if (kDebugMode) {
            print(
            'Conversation order: last(createdAt)=${last.createdAt.toIso8601String()} id=${last.id} isSentByMe=${last.isSentByMe}',
          );
          }
        }
        if (kDebugMode) {
          print('Stored conversation ID: $_otherUserId');
        }

        await markAsRead();
        _setupSocketListeners();
        _socketService.joinConversation(conversationId);

        final group = response.data?.data.group;
        final user = response.data?.data.user;

        final otherUserName = isGroup
            ? (group?['name']?.toString() ?? 'Unknown Group')
            : (user?['name']?.toString() ?? 'Unknown User');

        final otherUserAvatar = isGroup
            ? (group?['photo_url']?.toString())
            : (user?['photo_url']?.toString());

        // EXTRACT BLOCKED FROM USER DATA
        final isTheyBlockedMe = user?['is_blocked'] == true;
        final isIBlockedThem = user?['is_blocked_by_auth_user'] == true;


        // Extract chat request data from API response
        String? chatRequestStatus;
        String? chatRequestFrom;
        String? chatRequestTo;
        String? chatRequestId;

        final rawConversations = response.data?.data.conversations ?? [];
        if (rawConversations.isNotEmpty) {
          final firstConv = rawConversations.first as Map<String, dynamic>?;
          if (firstConv != null) {
            chatRequestStatus = firstConv['chat_request_status']?.toString();
            chatRequestFrom = firstConv['chat_request_from']?.toString();
            chatRequestTo = firstConv['chat_request_to']?.toString();
            chatRequestId = firstConv['chat_request_id']?.toString();

            if (kDebugMode) {
              print('📨 Chat Request Status: $chatRequestStatus');
              print('📨 Chat Request From: $chatRequestFrom');
              print('📨 Chat Request To: $chatRequestTo');
              print('📨 Chat Request ID: $chatRequestId');
            }

          }
        }

        //  BUILD GROUP DATA FROM API RESPONSE
        ChatGroup? groupModel;
        if (isGroup && group != null) {
          try {
            groupModel = ChatGroup.fromJson(group);
            if (kDebugMode) {
              print(
              'Group data extracted: ${groupModel.name} with ${groupModel.members.length} members',
            );
            }
          } catch (e) {
            if (kDebugMode) {
              print('Failed to parse group into ChatGroup: $e');
            }
            groupModel = null;
          }
        }

        // Update initial conversation data with loaded info
        Conversation? updatedConversationData;
        if (initialConversationData != null) {
          updatedConversationData = initialConversationData.copyWith(
            chatRequestStatus: chatRequestStatus ?? initialConversationData.chatRequestStatus,
            chatRequestFrom: chatRequestFrom ?? initialConversationData.chatRequestFrom,
            chatRequestTo: chatRequestTo ?? initialConversationData.chatRequestTo,
            chatRequestId: chatRequestId ?? initialConversationData.chatRequestId,
          );
        }

        emit(
          ChatLoaded(
            messages: conversations,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            hasMore: _hasMore,
            isGroup: isGroup,
            commonGroupData: groupModel,
            isIBlockedThem: isIBlockedThem,
            isTheyBlockedMe: isTheyBlockedMe,
            groupData: updatedConversationData,
          ),
        );
      } else {
        emit(ChatError(response.message ?? 'Failed to load messages'));
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading messages: $e');
      }
      emit(ChatError('Failed to load messages: $e'));
    }
  }
  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _otherUserId == null || _isGroup == null) {
      return;
    }

    try {
      _isLoadingMore = true;
      emit((state as ChatLoaded).copyWith(isLoadingMore: true));

      if (kDebugMode) {
        print('Loading more messages - page: ${_currentPage + 1}');
      }

      final response = await _chatRepository.getConversations(
        userId: currentUserId,
        otherUserId: _otherUserId!,
        isGroup: _isGroup ?? false,
        page: _currentPage + 1,
        limit: _limit,
      );

      if (response.success && response.data != null) {
        // Server returns the page in newest->oldest for that page chunk.
        // Convert to oldest->newest and prepend (older messages) to current list.
        final rawNew = (response.data?.data.conversations ?? [])
            .map((json) => Message.fromJson(json, currentUserId))
            .toList()
            .reversed
            .toList();

        final newMessages = _dedupeMessages(rawNew);

        final currentState = state as ChatLoaded;
        // Prepend older messages and dedupe final list
        final allRaw = [...newMessages, ...currentState.messages];
        final allMessages = _dedupeMessages(allRaw);

        _currentPage++;
        _hasMore = response.data!.meta.hasMore;
        _isLoadingMore = false;

        if (kDebugMode) {
          print('Loaded ${newMessages.length} more messages');
        }

        emit(
          currentState.copyWith(
            messages: allMessages,
            hasMore: _hasMore,
            isLoadingMore: false,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading more messages: $e');
      }
      _isLoadingMore = false;
      if (state is ChatLoaded) {
        emit((state as ChatLoaded).copyWith(isLoadingMore: false));
      }
    }
  }

  // Sends a message or file. Returns null on success, otherwise returns an error message.
  Future<String?> sendMessage({
    required String message,
    String? replyTo,
    String? filePath,
  }) async {
    if (state is! ChatLoaded || _otherUserId == null || _isGroup == null) {
      if (kDebugMode) {
        print('Cannot send message - invalid state');
      }
      return 'Invalid chat state';
    }

    final currentState = state as ChatLoaded;

    // Enforce mutual exclusion: cannot send text + file in same request
    final hasText = message.trim().isNotEmpty;
    final hasFile = filePath != null && filePath.isNotEmpty;
    if (hasText && hasFile) {
      if (kDebugMode) {
        print('Cannot send both text and file in same request');
      }
      return 'Cannot send both text and file';
    }

    // Generate a temp id for optimistic UI
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    // FILE UPLOAD FLOW
    if (hasFile) {
      // Quick existence check only; UI already validated file before calling Cubit.
      final file = File(filePath);
      if (!await file.exists()) return 'Selected file not found.';

      // Infer file extension (lowercase) for message_type mapping
      final fileExt = p.extension(file.path).toLowerCase();

      // Map extension to server message_type (defaults provided)
      int inferredMessageType = 1;
      if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(fileExt)) {
        inferredMessageType = 1; // images
      } else if ([
        '.mp4',
        '.mov',
        '.mkv',
        '.webm',
        '.avi',
        '.3gp',
      ].contains(fileExt)) {
        inferredMessageType = 5; // videos (server observed)
      } else if (['.mp3', '.m4a', '.wav', '.aac'].contains(fileExt)) {
        inferredMessageType = 4; // audio (fallback guess)
      }

      // Create optimistic temp message (file-only)
      final tempMessage = Message(
        id: tempId,
        fromId: currentUserId,
        toId: _otherUserId!,
        message: '',
        status: 0,
        messageType: inferredMessageType,
        fileName: p.basename(file.path),
        fileUrl: null,
        replyTo: replyTo,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        sender: Sender(
          id: currentUserId,
          name: SharedPreferencesHelper.getCurrentUserName(),
          photoUrl: SharedPreferencesHelper.getCurrentUserPhotoUrl(),
        ),
        isSentByMe: true,
      );

      // Append optimistic message
      emit(
        currentState.copyWith(
          messages: [...currentState.messages, tempMessage],
        ),
      );

      // Upload with progress
      try {
        void onProgress(int sent, int total) {
          final pct = total > 0
              ? (sent / total * 100).clamp(0, 100).toInt()
              : 0;
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap[tempId] = pct;
            emit(s.copyWith(uploadProgress: updatedMap));
          }
          if (kDebugMode) {
            print('📤 Upload progress for $tempId: $pct% ($sent/$total)');
          }
        }

        if (kDebugMode) {
          print(
            '📤 ChatCubit: calling repository.sendFileMultipart for $filePath',
          );
        }
        // backend expects `message_type = 1` for multipart attachments
        // Always send 1 for multipart payloads; use `inferredMessageType` only for optimistic UI rendering.
        final resp = await _chatRepository.sendFileMultipart(
          toId: _otherUserId!,
          isGroup: _isGroup ?? false,
          filePath: file.path,
          // note: we intentionally pass 1 below (repo will set message_type=1)
          messageType: 1,
          message:
              '', // backend may require non-empty; repo sends basename fallback
          replyTo: replyTo,
          isMyContact: 1,
          onSendProgress: onProgress,
        );

        if (kDebugMode) {
          print(
            'ChatCubit: repository returned success=${resp.success} message=${resp.message}',
          );
        }
        if (resp.success && resp.data != null) {
          final serverMsgMap = resp.data!.data.message;

          final serverMsg = Message.fromJson(serverMsgMap, currentUserId);

          // Replace temp message with server message & clear progress
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            final updated = s.messages
                .map((m) => m.id == tempId ? serverMsg : m)
                .toList();
            final exists = updated.any((m) => m.id == serverMsg.id);
            final finalMessages = exists ? updated : [...updated, serverMsg];
            emit(
              s.copyWith(messages: finalMessages, uploadProgress: updatedMap),
            );
          }

          if (kDebugMode) {
            print('File message sent successfully: ${resp.data}');
          }
          return null;
        } else {
          final err = resp.message ?? 'Failed to send file. Please try again.';
          if (kDebugMode) {
            print('ChatCubit: repository reported failure: $err');
          }
          if (kDebugMode) {
            print('ChatCubit: File send response payload: ${resp.data}');
          }

          // mark temp message as failed and clear progress
          _markMessageAsFailed(tempId);
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            emit(s.copyWith(uploadProgress: updatedMap));
          }

          return err;
        }
      } catch (e) {
        // Log detailed exception for debugging but return a generic message to UI
        if (kDebugMode) {
          print('Error sending file multipart: $e');
        }
        _markMessageAsFailed(tempId);
        if (state is ChatLoaded) {
          final s = state as ChatLoaded;
          final updatedMap = Map<String, int>.from(s.uploadProgress);
          updatedMap.remove(tempId);
          emit(s.copyWith(uploadProgress: updatedMap));
        }
        return 'Upload failed. Please try again.';
      }
    }

    // TEXT-ONLY FLOW
    // Create optimistic temp message and append
    final textTempId = tempId; // keep stable id
    final textTempMessage = Message(
      id: textTempId,
      fromId: currentUserId,
      toId: _otherUserId!,
      message: message,
      status: 0,
      messageType: 0,
      fileName: null,
      fileUrl: null,
      replyTo: replyTo,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sender: Sender(
        id: currentUserId,
        name: SharedPreferencesHelper.getCurrentUserName(),
        photoUrl: SharedPreferencesHelper.getCurrentUserPhotoUrl(),
      ),
      isSentByMe: true,
    );

    emit(
      currentState.copyWith(
        messages: [...currentState.messages, textTempMessage],
      ),
    );

    try {
      final response = await _chatRepository.sendMessage(
        toId: _otherUserId!,
        message: message,
        isGroup: _isGroup!,
        replyTo: replyTo,
      );

      if (response.success && response.data != null) {
        final messageData = response.data!.data.message;
        final serverMessage = Message.fromJson(messageData, currentUserId);

        if (state is ChatLoaded) {
          final latest = state as ChatLoaded;
          final updatedMessages = latest.messages.map((msg) {
            return msg.id == textTempId ? serverMessage : msg;
          }).toList();

          final exists = updatedMessages.any((m) => m.id == serverMessage.id);
          final finalMessages = exists
              ? updatedMessages
              : [...updatedMessages, serverMessage];

          emit(latest.copyWith(messages: finalMessages));
        }

        return null;
      } else {
        final err = response.message ?? 'Failed to send message';
        if (kDebugMode) {
          print('Failed to send message: $err');
        }
        _markMessageAsFailed(textTempId);
        return err;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending message: $e');
      }
      _markMessageAsFailed(textTempId);
      return 'Failed to send message. Please try again.';
    }
  }

  void _markMessageAsFailed(String messageId) {
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      final failedMessages = currentState.messages.map((msg) {
        return msg.id == messageId ? msg.copyWith(status: -1) : msg;
      }).toList();

      emit(currentState.copyWith(messages: failedMessages));
    }
  }

  Future<void> markAsRead() async {
    if (_otherUserId == null || _isGroup == null) return;

    try {

      await _chatRepository.markAsRead(
        userId: currentUserId,
        otherUserId: _otherUserId!,
        isGroup: _isGroup!,
      );

    } catch (e) {
      if (kDebugMode) {
        print('Failed to mark as read: $e');
      }
    }
  }

  void _handleBlockUnblockEvent(Map<String, dynamic> data) {
    try {
      final blockedBy = data['blockedBy']?.toString();
      final blockedTo = data['blockedTo'] as Map<String, dynamic>?;
      final isBlocked = data['isBlocked'] == true;
      final type = data['type']?.toString();

      if (kDebugMode) {
        print('Processing block/unblock event:');
        print('   - blockedBy: $blockedBy');
        print('   - currentUserId: $currentUserId');
        print('   - isBlocked: $isBlocked');
        print('   - type: $type');
      }


      // not relevant -> ignore
      final blockedToId = blockedTo?['id']?.toString();

      // Determine which flag to update:
      // - If auth user performed the action (blockedBy == currentUserId)
      //   and target is the other user -> update isIBlockedThem.
      // - If other user performed the action (blockedBy == _otherUserId)
      //   and target is the auth user -> update isTheyBlockedMe.
      bool? newisIBlockedThem;
      bool? newisTheyBlockedMe;

      if (blockedBy == currentUserId.toString() &&
          blockedToId == _otherUserId) {
        newisIBlockedThem = isBlocked;
      } else if (blockedBy == _otherUserId &&
          blockedToId == currentUserId.toString()) {
        newisTheyBlockedMe = isBlocked;
      } else {
        // if event references the other user as target (blockedTo == other),
        // but blockedBy isn't explicit, we can conservatively set isIBlockedThem
        if (blockedToId == _otherUserId && blockedBy != null) {
          // if someone blocked the other user and the actor isn't the auth user,
          // we can interpret that the auth user did not block them.
          newisIBlockedThem = blockedBy == currentUserId.toString()
              ? isBlocked
              : null;
        }
      }

      // Only proceed if event is relevant to this conversation
      final relevant =
          blockedBy == _otherUserId ||
          blockedToId == _otherUserId ||
          blockedBy == currentUserId.toString() ||
          blockedToId == currentUserId.toString();

      if (!relevant) return;

      if (isClosed) return; // avoid emitting after close

      if (state is ChatLoaded) {
        final currentState = state as ChatLoaded;
        // fallback to existing values when null
        final updatedisIBlockedThem =
            newisIBlockedThem ?? currentState.isIBlockedThem;
        final updatedisTheyBlockedMe =
            newisTheyBlockedMe ?? currentState.isTheyBlockedMe;

        emit(
          currentState.copyWith(
            isIBlockedThem: updatedisIBlockedThem,
            isTheyBlockedMe: updatedisTheyBlockedMe,
          ),
        );

        try {
          if (kDebugMode) {
            print('Block status updated in UI');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error notifying conversation cubit: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling block/unblock event: $e');
      }
    }
  }

  void _setupSocketListeners() {
    if (_otherUserId == null || _isGroup == null) return;
    _socketService.cleanupChatListeners(_otherUserId!);
    _socketService.addMessageListener((dynamic raw) {
      try {
        if (raw is Map<String, dynamic>) {
          final event = raw['event'];
          final data = raw['data'];

          if (event == 'user.block_unblock' && data is Map<String, dynamic>) {
            _handleBlockUnblockEvent(data);
          }

          // Handle UserEvent actions such as delete-for-everyone
          if (event == 'UserEvent' && data is Map<String, dynamic>) {
            final action = data['action'] ?? data['type'];
            if (action == 'message_deleted_for_everyone' || action == 'message_deleted') {
              _handleMessageDeletedEvent(data);
            }
          }
        }
      } catch (e) {
        if (kDebugMode) print('Error processing socket message: $e');
      }
    });

    _socketService.onNewMessage(_otherUserId!, _isGroup!, currentUserId, (
      newMessage,
    ) {
      if (state is! ChatLoaded) return;

      // Early-id check: if we already have this message ID, try to replace when
      // incoming message is newer or its content changed (this fixes "delete for everyone" updates)
      try {
        final currentState = state as ChatLoaded;
        if (newMessage.id.isNotEmpty) {
          final existingIndex = currentState.messages.indexWhere((m) => m.id.isNotEmpty && m.id == newMessage.id);
          if (existingIndex >= 0) {
            final existing = currentState.messages[existingIndex];
            final shouldReplace = newMessage.updatedAt.isAfter(existing.updatedAt) || newMessage.message != existing.message;
            if (shouldReplace) {
              if (kDebugMode) print('Replacing existing message ${newMessage.id} with updated socket message');
              final updatedMessages = List<Message>.from(currentState.messages);
              updatedMessages[existingIndex] = newMessage;
              final deduped = _dedupeMessages(updatedMessages);
              emit(currentState.copyWith(messages: deduped));

              if (!newMessage.isSentByMe) markAsRead();
            } else {
              if (kDebugMode) print('Skipping socket message (already present and not newer): ${newMessage.id}');
            }
            return;
          }
        }

        if (kDebugMode) {
          print('Received new message via socket: ${newMessage.id}');
          print('Message from: ${newMessage.fromId}, Current user: $currentUserId');
          print('Is sent by me: ${newMessage.isSentByMe}');
        }

        // Append incoming message and dedupe as a safety net
        final appended = [...currentState.messages, newMessage];
        final deduped = _dedupeMessages(appended);
        emit(currentState.copyWith(messages: deduped));

        if (!newMessage.isSentByMe) markAsRead();
      } catch (e) {
        if (kDebugMode) print('Error handling onNewMessage: $e');
      }
    });

    _socketService.onTyping(_otherUserId!, (isTyping) {
    });


    // Generic fallback: listen to all socket messages and handle any that
    // match this conversation's from/to id. This catches cases when the
    // server emits a slightly different event shape or timing causes the
    // per-conversation wrapper to miss the event.
    _genericSocketListener = (dynamic raw) {
      try {
        // raw may be {'event': 'UserEvent', 'data': {...}} or {'event':'new_message', 'data':...}
        final Map<String, dynamic> wrapper = raw is Map<String, dynamic>
            ? (raw['data'] is Map<String, dynamic>
                  ? {'event': raw['event'], 'data': raw['data']}
                  : raw)
            : {};
        final payload = wrapper['data'] ?? raw;
        if (payload == null || payload is! Map<String, dynamic>) return;

        final conv = payload['conversation'] ?? payload;
        if (conv == null || conv is! Map<String, dynamic>) return;

        final toId = conv['to_id']?.toString();
        final fromId = conv['from_id']?.toString();

        if (toId == _otherUserId || fromId == _otherUserId) {
          final newMessage = Message.fromJson(conv, currentUserId);
          if (state is! ChatLoaded) return;
          final currentState = state as ChatLoaded;

          // Append and dedupe centrally
          if (kDebugMode) {
            print(
              'Fallback listener appending message ${newMessage.id} for conv $_otherUserId',
            );
          }
          final appended = [...currentState.messages, newMessage];
          final deduped = _dedupeMessages(appended);
          emit(currentState.copyWith(messages: deduped));
          if (!newMessage.isSentByMe) markAsRead();
        }
      } catch (e) {
        if (kDebugMode) print('Generic socket listener error: $e');
      }
    };

    _socketService.addMessageListener(_genericSocketListener!);
  }

  // Handle server "delete for everyone" events and update the open chat
  void _handleMessageDeletedEvent(Map<String, dynamic> data) {
    try {
      if (kDebugMode) print('🗑️ Handling message deleted event: $data');

      final deletedMap = (data['deleted_message'] ??
          data['deletedMessage'] ??
          data['previousMessage'] ??
          data) as Map<String, dynamic>?;

      if (deletedMap == null) {
        if (kDebugMode) {
          print('No deleted message data found in event');
        }
        return;
      }

      final idCandidates = <String?>[
        deletedMap['_id']?.toString(),
        deletedMap['id']?.toString(),
        data['id']?.toString(),
      ].where((e) => e != null).map((e) => e!).toList();

      if (idCandidates.isEmpty) {
        if (kDebugMode) {
          print('No valid message ID found in delete event');
        }
        return;
      }

      if (kDebugMode) {
        print('Looking for message with IDs: $idCandidates');
      }

      if (state is ChatLoaded) {
        final s = state as ChatLoaded;

        // Find if message exists in current list
        final messageExists = s.messages.any((m) => idCandidates.contains(m.id));

        if (!messageExists) {
          if (kDebugMode) {
            print('Deleted message not found in current chat');
          }
          return;
        }

        final updated = s.messages.map((m) {
          final matches = idCandidates.contains(m.id);
          if (matches) {
            if (kDebugMode) {
              print('Found matching message ${m.id}, replacing with deleted version');
            }

            try {
              // Try to parse the server's deleted message payload
              final replaced = Message.fromJson(deletedMap, currentUserId);
              if (kDebugMode) {
                print('Successfully parsed deleted message: "${replaced.message}"');
              }
              return replaced;
            } catch (e) {
              if (kDebugMode) {
                print('Failed to parse deleted message map: $e');
              }
              // Fallback: just update the text
              return m.copyWith(
                message: deletedMap['message']?.toString() ?? 'This message was deleted',
                updatedAt: DateTime.now(), // Update timestamp to force UI rebuild
              );
            }
          }
          return m;
        }).toList();

        // Always emit new state, even if content looks similar
        emit(s.copyWith(
          messages: updated,
          // Force a new list instance to ensure Flutter detects the change
        ));

        // Refresh conversation list
        try {
          _socketService.requestConversations();
        } catch (e) {
          if (kDebugMode) {
            print('Failed to request conversations refresh: $e');
          }
        }

        if (kDebugMode) {
          print('Message deleted event processed successfully');
        }
      } else {
        if (kDebugMode) {
          print('Cannot process delete event - chat not loaded');
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error handling message deleted event: $e');
        print('Stack trace: $stackTrace');
      }

    }
  }
  void dispose() {

    if (_otherUserId != null) {
      _socketService.cleanupChatListeners(_otherUserId!);
      _socketService.leaveConversation(_otherUserId!);
    }

    if (_genericSocketListener != null) {
      _socketService.removeMessageListener(_genericSocketListener!);
      _genericSocketListener = null;
    }

    _socketSubscription?.cancel();
    _replyingToMessage = null;
    _editingMessage = null;
  }

  @override
  Future<void> close() {
    dispose();
    return super.close();
  }


  // Remove duplicates while keeping chronological order (oldest->newest)

  List<Message> _dedupeMessages(List<Message> messages) {
    final out = <Message>[];
    final seenIds = <String>{};

    for (var m in messages) {
      //  PRIMARY: Use MongoDB _id for deduplication (most reliable)
      if (m.id.isNotEmpty) {
        if (seenIds.contains(m.id)) {
          if (kDebugMode) {
            print('Skipping duplicate by id: ${m.id}');
          }
          continue;
        }
        seenIds.add(m.id);
        out.add(m);
        continue;
      }

      // FALLBACK: For messages without ID (temporary messages only)
      // Use timestamp + fromId to avoid false positives
      final fallbackKey = '${m.fromId}|${m.createdAt.millisecondsSinceEpoch}';
      if (seenIds.contains(fallbackKey)) {
        if (kDebugMode) {
          print('Skipping duplicate by fallback key: $fallbackKey');
        }
        continue;
      }
      seenIds.add(fallbackKey);
      out.add(m);
    }

    return out;
  }

  // Delete a message for me (remove from this client's view). Returns null on success or error message.
  Future<String?> deleteMessageForMe({
    required String conversationId,
    required String previousMessageId,
    required String targetMessageId,
  }) async {
    if (state is! ChatLoaded) return 'Chat not loaded';
    try {
      if (kDebugMode) {
        print(
        '🗑Requesting delete-for-me: $targetMessageId in conv $conversationId',
      );
      }
      final resp = await _chatRepository.deleteMessageForMe(
        conversationId: conversationId,
        previousMessageId: previousMessageId,
      );

      if (resp.success) {
        // Remove the message locally
        if (state is ChatLoaded) {
          final s = state as ChatLoaded;
          final updated = s.messages
              .where((m) => m.id != targetMessageId)
              .toList();
          emit(s.copyWith(messages: updated));
        }
        return null;
      } else {
        return resp.message ?? 'Failed to delete message';
      }
    } catch (e) {
      if (kDebugMode) {
        print('deleteMessageForMe error: $e');
      }
      return 'Failed to delete message: $e';
    }
  }

  //Delete message for everyone in the conversation (server-side). Returns null on success else error.
  Future<String?> deleteMessageForEveryone({
    required String conversationId,
    required String previousMessageId,
    required String targetMessageId,
  }) async {
    if (state is! ChatLoaded) return 'Chat not loaded';
    try {
      if (kDebugMode) {
        print(
        'Requesting delete-for-everyone: $targetMessageId in conv $conversationId',
      );
      }
      final resp = await _chatRepository.deleteMessageForEveryone(
        conversationId: conversationId,
        previousMessageId: previousMessageId,
      );

      if (resp.success) {
        // Remove locally as well
        if (state is ChatLoaded) {
          final s = state as ChatLoaded;
          // Instead of removing the message locally, replace it with the
          // server-provided "deleted" payload so UI shows "This message was deleted"
          Map<String, dynamic>? deletedPayload;
          try {
            // server may provide previousMessage or previous_message or deleted_message
            deletedPayload = resp.data?.previousMessage as Map<String, dynamic>? ??
                resp.data?.deletedMessage as Map<String, dynamic>? ??
                resp.data?.data?.deleted_message as Map<String, dynamic>?;
          } catch (_) {
            deletedPayload = null;
          }

          final updated = s.messages.map((m) {
            if (m.id == targetMessageId) {
              if (deletedPayload != null) {
                try {
                  return Message.fromJson(deletedPayload, currentUserId);
                } catch (_) {
                  return m.copyWith(message: deletedPayload['message']?.toString() ?? 'This message was deleted');
                }
              }
              return m.copyWith(message: 'This message was deleted');
            }
            return m;
          }).toList();

          emit(s.copyWith(messages: updated));

          // Ask the socket/service to refresh conversations so the conversation
          // preview / last-message shown on home updates consistently.
          try {
            _socketService.requestConversations();
          } catch (_) {}
         }
         return null;
       } else {
         return resp.message ?? 'Failed to delete message for everyone';
       }
     } catch (e) {
       if (kDebugMode) {
         print('deleteMessageForEveryone error: $e');
       }
       return 'Failed to delete message for everyone: $e';
     }
  }

  //Public aliases so UI code can call either `deleteMessageForMe`/`deleteMessageForEveryone` or the shorter `deleteForMe`/`deleteForEveryone` depending on preference.
  Future<String?> deleteForMe({
    required String conversationId,
    required String previousMessageId,
    required String targetMessageId,
  }) async {
    return deleteMessageForMe(
      conversationId: conversationId,
      previousMessageId: previousMessageId,
      targetMessageId: targetMessageId,
    );
  }

  Future<String?> deleteForEveryone({
    required String conversationId,
    required String previousMessageId,
    required String targetMessageId,
  }) async {
    return deleteMessageForEveryone(
      conversationId: conversationId,
      previousMessageId: previousMessageId,
      targetMessageId: targetMessageId,
    );
  }
}
