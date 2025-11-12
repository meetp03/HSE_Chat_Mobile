// chat_cubit.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/home/bloc/chat_state.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:hsc_chat/feature/home/repository/chat_repository.dart';

class ChatCubit extends Cubit<ChatState> {
  final ChatRepository _chatRepository;
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
    required ChatRepository chatRepository,
    required SocketService socketService,
  }) : _chatRepository = chatRepository,
        _socketService = socketService,
        super(ChatInitial());

  int get currentUserId => SharedPreferencesHelper.getCurrentUserId();

  Future<void> loadConversations(
      int userId,
      String otherUserId,
      bool isGroup,
      ) async {
    try {
      emit(ChatLoading());

      print('📥 Loading conversations for: $otherUserId (isGroup: $isGroup)');
      print('👤 Current user ID: $userId');

      final response = await _chatRepository.getConversations(
        userId: userId,
        otherUserId: otherUserId,
        isGroup: isGroup,
        page: 1,
        limit: _limit,
      );

      if (response.success && response.data != null) {
        // ✅ Pass currentUserId (not group ID) for proper alignment
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

        print('✅ Loaded ${conversations.length} messages');
        if (conversations.isNotEmpty) {
          final first = conversations.first;
          final last = conversations.last;
          print('🧭 Conversation order: first(createdAt)=${first.createdAt.toIso8601String()} id=${first.id} isSentByMe=${first.isSentByMe}');
          print('🧭 Conversation order: last(createdAt)=${last.createdAt.toIso8601String()} id=${last.id} isSentByMe=${last.isSentByMe}');
        }
        print('🆔 Stored conversation ID: $_otherUserId');

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

        emit(
          ChatLoaded(
            messages: conversations,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            hasMore: _hasMore,
            isGroup: isGroup,
          ),
        );
      } else {
        emit(ChatError(response.message ?? 'Failed to load messages'));
      }
    } catch (e) {
      print('❌ Error loading messages: $e');
      emit(ChatError('Failed to load messages: $e'));
    }
  }

  Future<void> loadMoreMessages() async {
    if (_isLoadingMore || !_hasMore || _otherUserId == null || _isGroup == null)
      return;

    try {
      _isLoadingMore = true;
      emit((state as ChatLoaded).copyWith(isLoadingMore: true));

      print('📥 Loading more messages - page: ${_currentPage + 1}');

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

        print('✅ Loaded ${newMessages.length} more messages');

        emit(
          currentState.copyWith(
            messages: allMessages,
            hasMore: _hasMore,
            isLoadingMore: false,
          ),
        );
      }
    } catch (e) {
      print('❌ Error loading more messages: $e');
      _isLoadingMore = false;
      if (state is ChatLoaded) {
        emit((state as ChatLoaded).copyWith(isLoadingMore: false));
      }
    }
  }

  /// Send either a text message OR a file upload. If filePath is provided,
  /// message must be empty/null. Enforces mutual exclusion.
  Future<void> sendMessage({required String message, String? replyTo, String? filePath}) async {
    if (state is! ChatLoaded || _otherUserId == null || _isGroup == null) {
      print('❌ Cannot send message - invalid state');
      return;
    }

    final currentState = state as ChatLoaded;

    // Enforce mutual exclusion: cannot send text + file in same request
    final hasText = message.trim().isNotEmpty;
    final hasFile = filePath != null && filePath.isNotEmpty;
    if (hasText && hasFile) {
      print('❌ Cannot send both text and file in same request');
      return;
    }

    print('📤 Sending message to: $_otherUserId (isGroup: $_isGroup)');
    print('👤 From user ID: $currentUserId');

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final tempMessage = Message(
      id: tempId,
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

    // Append temp message to the end (oldest->newest ordering)
    emit(
      currentState.copyWith(messages: [...currentState.messages, tempMessage]),
    );

    // If it's a file upload, perform multipart upload flow
    if (hasFile) {
      // Replace temp message with media-specific temp fields
      final fileName = filePath!.split('/').last;
      final tempFileMessage = tempMessage.copyWith(
        messageType: 1,
        fileName: fileName,
        message: '',
      );
      // update messages list
      final updatedList = (state as ChatLoaded).messages.map((m) => m.id == tempId ? tempFileMessage : m).toList();
      emit((state as ChatLoaded).copyWith(messages: updatedList));

      try {
        void onProgress(int sent, int total) {
          final pct = total > 0 ? (sent / total * 100).clamp(0, 100).toInt() : 0;
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap[tempId] = pct;
            emit(s.copyWith(uploadProgress: updatedMap));
          }
          if (kDebugMode) print('📤 Upload progress for $tempId: $pct% ($sent/$total)');
        }

        final resp = await _chatRepository.sendFileMultipart(
          toId: _otherUserId!,
          isGroup: _isGroup ?? false,
          filePath: filePath,
          messageType: 1,
          message: '', // backend expects message but treat as empty; fallback handled in repo
          replyTo: replyTo,
          isMyContact: 1,
          onSendProgress: onProgress,
        );

        if (resp.success && resp.data != null) {
          final serverMsgMap = resp.data!.data.message;
          final serverMsg = Message.fromJson(serverMsgMap, currentUserId);
          // Clear progress and replace temp
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            final updated = s.messages.map((m) => m.id == tempId ? serverMsg : m).toList();
            final exists = updated.any((m) => m.id == serverMsg.id);
            final finalMessages = exists ? updated : [...updated, serverMsg];
            emit(s.copyWith(messages: finalMessages, uploadProgress: updatedMap));
          }
          if (kDebugMode) print('✅ File message sent successfully: ${resp.data}');
          return;
        } else {
          print('❌ Failed to send file message: ${resp.message}');
          _markMessageAsFailed(tempId);
          if (state is ChatLoaded) {
            final s = state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            emit(s.copyWith(uploadProgress: updatedMap));
          }
          return;
        }
      } catch (e) {
        print('❌ Error sending file multipart: $e');
        if (state is ChatLoaded) {
          final s = state as ChatLoaded;
          final updatedMap = Map<String, int>.from(s.uploadProgress);
          updatedMap.remove(tempId);
          emit(s.copyWith(uploadProgress: updatedMap));
        }
        _markMessageAsFailed(tempId);
        return;
      }
    }

    try {
      final response = await _chatRepository.sendMessage(
        toId: _otherUserId!,
        message: message,
        isGroup: _isGroup!,
        replyTo: replyTo,
      );

      if (response.success && response.data != null) {
        print('✅ Message sent successfully');

        // ✅ FIX: response.data.message is always Map<String, dynamic>
        final messageData = response.data!.data.message;

        // Convert Map to Message object
        final serverMessage = Message.fromJson(messageData, currentUserId);

        // Replace temp message with server message in the latest state
        if (state is ChatLoaded) {
          final latest = state as ChatLoaded;
          final updatedMessages = latest.messages.map((msg) {
            return msg.id == tempId ? serverMessage : msg;
          }).toList();

          // If tempMessage wasn't found (edge case), append serverMessage
          final exists = updatedMessages.any((m) => m.id == serverMessage.id);
          final finalMessages = exists
              ? updatedMessages
              : [...updatedMessages, serverMessage];

          emit(latest.copyWith(messages: finalMessages));
        }

        // Return raw server payload for caller (e.g., ConversationCubit)
        return;
      } else {
        print('❌ Failed to send message: ${response.message}');
        _markMessageAsFailed(tempId);
        return;
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      _markMessageAsFailed(tempId);
      return;
    }
  }

  void _markMessageAsFailed(String messageId) {
    if (state is ChatLoaded) {
      final currentState = state as ChatLoaded;
      final failedMessages = currentState.messages.map((msg) {
        return msg.id == messageId
            ? msg.copyWith(status: -1)
            : msg;
      }).toList();

      emit(currentState.copyWith(messages: failedMessages));
    }
  }

  Future<void> markAsRead() async {
    if (_otherUserId == null || _isGroup == null) return;

    try {
      print('📖 Marking messages as read for: $_otherUserId');

      await _chatRepository.markAsRead(
        userId: currentUserId,
        otherUserId: _otherUserId!,
        isGroup: _isGroup!,
      );

      print('✅ Messages marked as read');
    } catch (e) {
      print('❌ Failed to mark as read: $e');
    }
  }

  void _setupSocketListeners() {
    if (_otherUserId == null || _isGroup == null) return;

    print('🔌 Setting up socket listeners for: $_otherUserId');
    print('👤 Current user ID: $currentUserId');

    _socketService.cleanupChatListeners(_otherUserId!);

    _socketService.onNewMessage(_otherUserId!, _isGroup!, currentUserId, (
        newMessage,
        ) {
      print('📨 Received new message via socket: ${newMessage.id}');
      print('👤 Message from: ${newMessage.fromId}, Current user: $currentUserId');
      print('🔍 Is sent by me: ${newMessage.isSentByMe}');

      if (state is! ChatLoaded) return;

      final currentState = state as ChatLoaded;

      final exists = _isDuplicateInList(currentState.messages, newMessage);

      if (!exists) {
        print('✅ Adding new message to chat');

        // Append new incoming message at the end (oldest->newest)
        final appended = [...currentState.messages, newMessage];
        final deduped = _dedupeMessages(appended);
        emit(currentState.copyWith(messages: deduped));

        if (!newMessage.isSentByMe) {
          markAsRead();
        }
      } else {
        print('⭐ Message already exists, skipping');
      }
    });

    _socketService.onTyping(_otherUserId!, (isTyping) {
      print('⌨️ User typing status: $isTyping');
    });

    print('✅ Socket listeners setup complete');

    // Generic fallback: listen to all socket messages and handle any that
    // match this conversation's from/to id. This catches cases when the
    // server emits a slightly different event shape or timing causes the
    // per-conversation wrapper to miss the event.
    _genericSocketListener = (dynamic raw) {
      try {
        // raw may be {'event': 'UserEvent', 'data': {...}} or {'event':'new_message', 'data':...}
        final Map<String, dynamic> wrapper = raw is Map<String, dynamic>
            ? (raw['data'] is Map<String, dynamic> ? {'event': raw['event'], 'data': raw['data']} : raw)
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
          final exists = _isDuplicateInList(currentState.messages, newMessage);
          if (!exists) {
            if (kDebugMode) print('🔁 Fallback listener adding message ${newMessage.id} for conv $_otherUserId');
            final appended = [...currentState.messages, newMessage];
            final deduped = _dedupeMessages(appended);
            emit(currentState.copyWith(messages: deduped));
            if (!newMessage.isSentByMe) markAsRead();
          }
        }
      } catch (e) {
        if (kDebugMode) print('⚠️ Generic socket listener error: $e');
      }
    };

    _socketService.addMessageListener(_genericSocketListener!);
  }

  void dispose() {
    print('🧹 Disposing ChatCubit');

    if (_otherUserId != null) {
      _socketService.cleanupChatListeners(_otherUserId!);
      _socketService.leaveConversation(_otherUserId!);
    }

    if (_genericSocketListener != null) {
      _socketService.removeMessageListener(_genericSocketListener!);
      _genericSocketListener = null;
    }

    _socketSubscription?.cancel();
  }

  @override
  Future<void> close() {
    dispose();
    return super.close();
  }

  // Normalize text: remove HTML tags and trim
  String _normalizeText(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  // Return true if `candidate` appears to be a duplicate of any in list
  bool _isDuplicateInList(List<Message> list, Message candidate) {
    final candText = _normalizeText(candidate.message);
    final candFingerprint = '${candidate.fromId}|$candText|${candidate.fileUrl ?? ''}|${candidate.messageType}';

    for (var m in list) {
      // Exact id match
      if (m.id.isNotEmpty && candidate.id.isNotEmpty && m.id == candidate.id) {
        print('🔁 Duplicate detected by id: existing=${m.id} candidate=${candidate.id}');
        return true;
      }

      // Fingerprint match (same sender + content/file + type)
      final mText = _normalizeText(m.message);
      final mFingerprint = '${m.fromId}|$mText|${m.fileUrl ?? ''}|${m.messageType}';
      if (mFingerprint == candFingerprint) {
        print('🔁 Duplicate detected by fingerprint: existing=${m.id} candidate=${candidate.id} fp=$mFingerprint');
        return true;
      }

      // Fallback: same sender, same text and within 60s
      final sameSender = m.fromId == candidate.fromId;
      final sameText = mText == candText && candText.isNotEmpty;
      final timeDiff = m.createdAt.difference(candidate.createdAt).inSeconds.abs();
      if (sameSender && sameText && timeDiff <= 60) {
        print('🔁 Duplicate detected by fuzzy match: existing=${m.id} candidate=${candidate.id} dt=$timeDiff s');
        return true;
      }
    }
    return false;
  }

  // Remove duplicates while keeping chronological order (oldest->newest)
  List<Message> _dedupeMessages(List<Message> messages) {
    final out = <Message>[];
    final seenFp = <String>{};
    for (var m in messages) {
      final fp = '${m.fromId}|${_normalizeText(m.message)}|${m.fileUrl ?? ''}|${m.messageType}';
      if (seenFp.contains(fp)) {
        print('🔇 Skipping duplicate fingerprint: ${m.id} fp=$fp');
        continue;
      }

      if (_isDuplicateInList(out, m)) {
        print('🔇 Skipping duplicate by list check: ${m.id}');
        continue;
      }

      seenFp.add(fp);
      out.add(m);
    }
    return out;
  }
}
