// chat_cubit.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/home/bloc/chat_state.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:hsc_chat/feature/home/repository/chat_repository.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

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

  /// Sends a message or file. Returns null on success, otherwise returns an error message.
  Future<String?> sendMessage({required String message, String? replyTo, String? filePath}) async {
    if (state is! ChatLoaded || _otherUserId == null || _isGroup == null) {
      print('❌ Cannot send message - invalid state');
      return 'Invalid chat state';
    }

    final currentState = state as ChatLoaded;

    // Enforce mutual exclusion: cannot send text + file in same request
    final hasText = message.trim().isNotEmpty;
    final hasFile = filePath != null && filePath.isNotEmpty;
    if (hasText && hasFile) {
      print('❌ Cannot send both text and file in same request');
      return 'Cannot send both text and file';
    }

    print('📤 Sending message to: $_otherUserId (isGroup: $_isGroup)');
    print('👤 From user ID: $currentUserId');

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
      } else if (['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'].contains(fileExt)) {
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
      emit(currentState.copyWith(messages: [...currentState.messages, tempMessage]));

      // Upload with progress
      try {
        void onProgress(int sent, int total) {
          final pct = total > 0 ? (sent / total * 100).clamp(0, 100).toInt() : 0;
          if (this.state is ChatLoaded) {
            final s = this.state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap[tempId] = pct;
            emit(s.copyWith(uploadProgress: updatedMap));
          }
          if (kDebugMode) print('📤 Upload progress for $tempId: $pct% ($sent/$total)');
        }

        if (kDebugMode) print('📤 ChatCubit: calling repository.sendFileMultipart for $filePath');
        // IMPORTANT: backend expects `message_type = 1` for multipart attachments
        // Always send 1 for multipart payloads; use `inferredMessageType` only for optimistic UI rendering.
        final resp = await _chatRepository.sendFileMultipart(
          toId: _otherUserId!,
          isGroup: _isGroup ?? false,
          filePath: file.path,
          // note: we intentionally pass 1 below (repo will set message_type=1)
          messageType: 1,
          message: '', // backend may require non-empty; repo sends basename fallback
          replyTo: replyTo,
          isMyContact: 1,
          onSendProgress: onProgress,
        );

        if (kDebugMode) print('📦 ChatCubit: repository returned success=${resp.success} message=${resp.message}');
        if (resp.success && resp.data != null) {
          final serverMsgMap = resp.data!.data.message;

          final serverMsg = Message.fromJson(serverMsgMap, currentUserId);

          // Replace temp message with server message & clear progress
          if (this.state is ChatLoaded) {
            final s = this.state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            final updated = s.messages.map((m) => m.id == tempId ? serverMsg : m).toList();
            final exists = updated.any((m) => m.id == serverMsg.id);
            final finalMessages = exists ? updated : [...updated, serverMsg];
            emit(s.copyWith(messages: finalMessages, uploadProgress: updatedMap));
          }

          if (kDebugMode) print('✅ File message sent successfully: ${resp.data}');
          return null;
        } else {
          final err = resp.message ?? 'Failed to send file. Please try again.';
          print('❌ ChatCubit: repository reported failure: $err');
          if (kDebugMode) print('❌ ChatCubit: File send response payload: ${resp.data}');

          // mark temp message as failed and clear progress
          _markMessageAsFailed(tempId);
          if (this.state is ChatLoaded) {
            final s = this.state as ChatLoaded;
            final updatedMap = Map<String, int>.from(s.uploadProgress);
            updatedMap.remove(tempId);
            emit(s.copyWith(uploadProgress: updatedMap));
          }

          return err;
        }
      } catch (e) {
        // Log detailed exception for debugging but return a generic message to UI
        print('❌ Error sending file multipart: $e');
        _markMessageAsFailed(tempId);
        if (this.state is ChatLoaded) {
          final s = this.state as ChatLoaded;
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

    emit(currentState.copyWith(messages: [...currentState.messages, textTempMessage]));

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

        if (this.state is ChatLoaded) {
          final latest = this.state as ChatLoaded;
          final updatedMessages = latest.messages.map((msg) {
            return msg.id == textTempId ? serverMessage : msg;
          }).toList();

          final exists = updatedMessages.any((m) => m.id == serverMessage.id);
          final finalMessages = exists ? updatedMessages : [...updatedMessages, serverMessage];

          emit(latest.copyWith(messages: finalMessages));
        }

        return null;
      } else {
        final err = response.message ?? 'Failed to send message';
        print('❌ Failed to send message: $err');
        _markMessageAsFailed(textTempId);
        return err;
      }
    } catch (e) {
      print('❌ Error sending message: $e');
      _markMessageAsFailed(textTempId);
      return 'Failed to send message. Please try again.';
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
      // tighten fuzzy window to 5 seconds to avoid collapsing distinct messages
      final timeDiff = m.createdAt.difference(candidate.createdAt).inSeconds.abs();
      if (sameSender && sameText && timeDiff <= 5) {
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
    final seenIds = <String>{};
    for (var m in messages) {
      // If server provided an ID, prefer exact-id dedupe (safe and reliable)
      if (m.id.isNotEmpty) {
        if (seenIds.contains(m.id)) {
          print('🔇 Skipping duplicate by id: ${m.id}');
          continue;
        }
        // still run fuzzy list check to avoid exact duplicates in `out`
        if (_isDuplicateInList(out, m)) {
          print('🔇 Skipping duplicate by list check: ${m.id}');
          continue;
        }
        seenIds.add(m.id);
        out.add(m);
        continue;
      }

      // For messages without id (temporary/edge cases), fall back to fingerprint
      final fp = '${m.fromId}|${_normalizeText(m.message)}|${m.fileUrl ?? ''}|${m.messageType}|${m.createdAt.millisecondsSinceEpoch}';
      if (seenFp.contains(fp)) {
        print('🔇 Skipping duplicate fingerprint (no id): fp=$fp');
        continue;
      }

      if (_isDuplicateInList(out, m)) {
        print('🔇 Skipping duplicate by list check (no id): ${m.id}');
        continue;
      }

      seenFp.add(fp);
      out.add(m);
    }
    return out;
  }
}
