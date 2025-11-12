import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_state.dart';
import 'package:hsc_chat/feature/home/model/conversation_model.dart';
import 'package:hsc_chat/feature/home/repository/conversation_repository.dart';
import 'package:hsc_chat/feature/home/repository/message_repository.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';

class ConversationCubit extends Cubit<ConversationState> {
  final ConversationRepository _repo;
  final SocketService _socket = SocketService();

  ConversationCubit(this._repo) : super(ConversationInitial()) {
    _listenToSocket();
  }

  // ALL chats pagination
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String _currentQuery = '';
  List<Conversation> _allConversations = [];

  // UNREAD chats pagination
  int _unreadCurrentPage = 1;
  bool _unreadHasMore = true;
  bool _unreadIsLoadingMore = false;
  String _unreadCurrentQuery = '';
  List<Conversation> _unreadConversations = [];

  // Track processed messages to avoid duplicates
  final Set<String> _processedMessageIds = {};

  // Simplified loading: we will emit ConversationLoading when a full fetch
  // (initial or refresh) starts. Pagination uses 'isLoadingMore' flags.
  // Note: no additional 'initialLoaded' flags are needed.

  void search(String query) {
    _currentQuery = query.trim();
    if (_currentQuery.isEmpty) {
      clearSearch();
      return;
    }
    _currentPage = 1;
    _hasMore = true;
    _allConversations = [];
    loadConversations(refresh: true);
  }

  void clearSearch() {
    _currentQuery = '';
    _currentPage = 1;
    _hasMore = true;
    _allConversations = [];
    loadConversations(refresh: true);
  }

  void searchUnread(String query) {
    _unreadCurrentQuery = query.trim();
    if (_unreadCurrentQuery.isEmpty) {
      clearUnreadSearch();
      return;
    }
    _unreadCurrentPage = 1;
    _unreadHasMore = true;
    _unreadConversations = [];
    loadUnreadConversations(refresh: true);
  }

  void clearUnreadSearch() {
    _unreadCurrentQuery = '';
    _unreadCurrentPage = 1;
    _unreadHasMore = true;
    _unreadConversations = [];
    loadUnreadConversations(refresh: true);
  }

  Future<void> loadConversations({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      _allConversations = [];
      emit(ConversationLoading());
    } else if (_isLoadingMore) {
      return;
    } else if (_currentPage == 1 && _allConversations.isEmpty) {
      // initial load
      emit(ConversationLoading());
    }

    try {
      _isLoadingMore = !refresh;

      final ApiResponse<ConversationResponse> resp = await _repo.getConversations(page: _currentPage, query: _currentQuery);

      if (!resp.success || resp.data == null) {
        emit(ConversationError(resp.message ?? 'Failed to load'));
        _isLoadingMore = false;
        return;
      }

      final List<Conversation> newConversations = resp.data!.data.conversations;
      // Note: no special initial flags required; emit loaded state below
      final Meta? meta = resp.data?.meta;
      final int currentPage = meta?.currentPage ?? 1;
      final int lastPage = meta?.lastPage ?? 1;
      final int perPage = meta?.perPage ?? 10;
      final int total = meta?.total ?? 0;

      // Determine hasMore robustly: prefer explicit flag, fallback to page math
      final bool metaHasNext = meta?.hasNextPage ?? false;
      final bool computedHasNext = (currentPage < lastPage) || (currentPage * perPage) < total;

      if (refresh) {
        _allConversations = newConversations;
      } else {
        for (var newConv in newConversations) {
          bool isDuplicate = _allConversations.any((existingConv) {
            if (newConv.isGroup && existingConv.isGroup) {
              return existingConv.groupId == newConv.groupId;
            }
            return existingConv.id == newConv.id;
          });

          if (!isDuplicate) {
            _allConversations.add(newConv);
          }
        }
      }

      _hasMore = metaHasNext || computedHasNext;
      _currentPage = _hasMore ? (currentPage + 1) : currentPage;

      // emit a unified ConversationLoaded so older UI checks (state is ConversationLoaded)
      _emitUnifiedLoadedState();
      _isLoadingMore = false;
    } catch (e) {
      _isLoadingMore = false;
      print('❌ Error loading conversations: $e');
      emit(ConversationError(e.toString()));
    }
  }

  Future<void> loadMore() async {
    if (_hasMore && !_isLoadingMore) {
      await loadConversations(refresh: false);
    }
  }

  Future<void> loadUnreadConversations({bool refresh = false}) async {
    if (refresh) {
      _unreadCurrentPage = 1;
      _unreadHasMore = true;
      _unreadConversations = [];
      emit(ConversationLoading());
    } else if (_unreadIsLoadingMore) {
      return;
    } else if (_unreadCurrentPage == 1 && _unreadConversations.isEmpty) {
      // initial unread load
      emit(ConversationLoading());
    }

    try {
      _unreadIsLoadingMore = !refresh;

      final ApiResponse<ConversationResponse> resp = await _repo.getUnreadConversations(page: _unreadCurrentPage, query: _unreadCurrentQuery);

      if (!resp.success || resp.data == null) {
        emit(ConversationError(resp.message ?? 'Failed to load unread'));
        _unreadIsLoadingMore = false;
        return;
      }

      final List<Conversation> newUnreadConversations =
          resp.data?.data.conversations ?? [];
      // Note: no special initial flags required; emit loaded state below
      final Meta? meta = resp.data?.meta;
      final int currentPage = meta?.currentPage ?? 1;
      final int lastPage = meta?.lastPage ?? 1;
      final int perPage = meta?.perPage ?? 10;
      final int total = meta?.total ?? 0;

      final bool metaHasNext = meta?.hasNextPage ?? false;
      final bool computedHasNext = (currentPage < lastPage) || (currentPage * perPage) < total;

      if (refresh) {
        _unreadConversations = newUnreadConversations;
      } else {
        for (var newConv in newUnreadConversations) {
          bool isDuplicate = _unreadConversations.any((existingConv) {
            if (newConv.isGroup && existingConv.isGroup) {
              return existingConv.groupId == newConv.groupId;
            }
            return existingConv.id == newConv.id;
          });

          if (!isDuplicate) {
            _unreadConversations.add(newConv);
          }
        }
      }

      _unreadHasMore = metaHasNext || computedHasNext;
      _unreadCurrentPage = _unreadHasMore ? (currentPage + 1) : currentPage;

      // emit unified loaded state so UI that checks for ConversationLoaded updates
      _emitUnifiedLoadedState();
      _unreadIsLoadingMore = false;
    } catch (e) {
      _unreadIsLoadingMore = false;
      print('❌ Error loading unread conversations: $e');
      emit(ConversationError(e.toString()));
    }
  }

  Future<void> loadMoreUnread() async {
    if (_unreadHasMore && !_unreadIsLoadingMore) {
      await loadUnreadConversations(refresh: false);
    }
  }

  List<Conversation> _getFilteredAllChats() {
    if (_currentQuery.isEmpty) return _allConversations;
    final lower = _currentQuery.toLowerCase();
    return _allConversations
        .where(
          (c) =>
      c.title.toLowerCase().contains(lower) ||
          c.lastMessage.toLowerCase().contains(lower),
    )
        .toList();
  }

  List<Conversation> _getFilteredUnreadChats() {
    if (_unreadCurrentQuery.isEmpty) return _unreadConversations;
    final lower = _unreadCurrentQuery.toLowerCase();
    return _unreadConversations
        .where(
          (c) =>
      c.title.toLowerCase().contains(lower) ||
          c.lastMessage.toLowerCase().contains(lower),
    )
        .toList();
  }

  // Emit only the AllConversationsLoaded state
  void _emitAllLoadedState() {
    // Keep for compatibility if later needed, but primary emission is unified
    _emitUnifiedLoadedState();
  }

  // Emit only the UnreadConversationsLoaded state
  void _emitUnreadLoadedState() {
    // Primary emission is unified
    _emitUnifiedLoadedState();
  }

  // Emit the legacy unified ConversationLoaded that contains both lists
  void _emitUnifiedLoadedState() {
    emit(ConversationLoaded(
      allChats: List.from(_allConversations),
      filteredAllChats: _getFilteredAllChats(),
      unreadChats: List.from(_unreadConversations),
      filteredUnreadChats: _getFilteredUnreadChats(),
      hasMore: _hasMore,
      isLoadingMore: _isLoadingMore,
      unreadHasMore: _unreadHasMore,
      unreadIsLoadingMore: _unreadIsLoadingMore,
      currentQuery: _currentQuery,
      unreadCurrentQuery: _unreadCurrentQuery,
    ));
  }

  Future<void> refresh() => loadConversations(refresh: true);
  Future<void> refreshUnread() => loadUnreadConversations(refresh: true);

  // Public getters so UI can access current data regardless of emitted state
  List<Conversation> get allChats => List.unmodifiable(_allConversations);
  List<Conversation> get filteredAllChats => _getFilteredAllChats();
  bool get hasMoreConversations => _hasMore;
  bool get isLoadingMoreConversations => _isLoadingMore;
  String get currentQuery => _currentQuery;

  List<Conversation> get unreadChats => List.unmodifiable(_unreadConversations);
  List<Conversation> get filteredUnreadChats => _getFilteredUnreadChats();
  bool get hasMoreUnread => _unreadHasMore;
  bool get isLoadingMoreUnread => _unreadIsLoadingMore;
  String get unreadQuery => _unreadCurrentQuery;

  int get _currentUserId {
    final userId = SharedPreferencesHelper.getCurrentUserId();
    return userId;
  }

  void reset() {
    _allConversations = [];
    _currentPage = 1;
    _hasMore = true;
    _currentQuery = '';
    _isLoadingMore = false;
    _unreadConversations = [];
    _unreadCurrentPage = 1;
    _unreadHasMore = true;
    _unreadCurrentQuery = '';
    _unreadIsLoadingMore = false;
    _processedMessageIds.clear();
    emit(ConversationInitial());
  }

  /* --------------------------------------------------------------------- */
  /*                         SOCKET LISTENERS                              */
  /* --------------------------------------------------------------------- */
  void _listenToSocket() {
    _socket.addMessageListener((raw) {
      if (raw is! Map<String, dynamic>) return;
      final event = raw['event']?.toString();
      final data = raw['data'];

      print('🔄 Socket event received - Event: $event');

      switch (event) {
        case 'UserEvent':
          _handleUserEvent(data);
          break;
        case 'GroupEvent':
          _handleGroupEvent(data);
          break;
        case 'new_message':
        // Handle standalone new_message events
          _handleStandaloneNewMessage(data);
          break;
        default:
          break;
      }
    });
  }

  void _handleGroupEvent(dynamic payload) {
    final action = payload['action'] ?? payload['type'];
    print('🔵 Handling GroupEvent - Action: $action');

    if (action == 'new_message') {
      _handleNewMessage(payload, fromGroupEvent: true);
    } else if (action == 'messages_read') {
      _handleMessagesRead(payload);
    }
  }

  void _handleUserEvent(dynamic payload) {
    final action = payload['action'] ?? payload['type'];
    print('🔵 Handling UserEvent - Action: $action');

    if (action == 'new_message') {
      // Process ALL messages from UserEvent (both group and direct)
      _handleNewMessage(payload, fromUserEvent: true);
    } else if (action == 'messages_read') {
      _handleMessagesRead(payload);
    } else if (action == 'chat_request' || action == 'existing_chat' || action == 'new_conversation') {
      // Backend sends conversation-level events when a chat request is created or an existing chat should be shown.
      // Treat these as conversation events and update/create local conversation entries so UI shows latest list without manual refresh.
      _handleConversationEvent(payload);
    }
  }

  /// Handle conversation-level events (chat_request, existing_chat, etc.)
  void _handleConversationEvent(dynamic payload) {
    try {
      final msg = _extractMessageMap(payload);
      if (msg == null) return;

      final messageId = msg['_id']?.toString() ?? '${msg['from_id']}_${msg['to_id']}_${msg['created_at']}';
      // prevent duplicates
      if (_processedMessageIds.contains(messageId)) {
        print('⏭️ Conversation event already processed: $messageId');
        return;
      }
      _processedMessageIds.add(messageId);
      if (_processedMessageIds.length > 100) {
        final toRemove = _processedMessageIds.length - 100;
        _processedMessageIds.removeAll(_processedMessageIds.take(toRemove));
      }

      // If we already have local conversation lists, update them directly
      if (_allConversations.isNotEmpty || _unreadConversations.isNotEmpty) {
        _updateConversationWithMessage(msg);
      } else {
        // If no local data yet, fetch from server
        loadConversations(refresh: true);
      }
    } catch (e) {
      print('❌ Error handling conversation event: $e');
    }
  }

  void _handleStandaloneNewMessage(dynamic payload) {
    print('🔵 Handling standalone new_message event');
    // Only process if it hasn't been processed by UserEvent/GroupEvent
    _handleNewMessage(payload, fromStandalone: true);
  }

  void _handleNewMessage(
      dynamic payload, {
        bool fromUserEvent = false,
        bool fromGroupEvent = false,
        bool fromStandalone = false,
      }) {
    final source = fromUserEvent
        ? 'UserEvent'
        : fromGroupEvent
        ? 'GroupEvent'
        : 'standalone';
    print('🔵 Handling new_message from $source');

    // Extract message to get unique ID
    final msg = _extractMessageMap(payload);
    if (msg == null) {
      print('❌ Failed to extract message from payload');
      return;
    }

    // Create unique message ID to prevent duplicates
    final messageId = msg['_id']?.toString() ??
        '${msg['from_id']}_${msg['to_id']}_${msg['created_at']}';

    // Skip if already processed
    if (_processedMessageIds.contains(messageId)) {
      print('⏭️ Message already processed: $messageId (from $source)');
      return;
    }

    // Mark as processed
    _processedMessageIds.add(messageId);

    // Clean up old processed IDs (keep only last 100)
    if (_processedMessageIds.length > 100) {
      final toRemove = _processedMessageIds.length - 100;
      _processedMessageIds.removeAll(_processedMessageIds.take(toRemove));
    }

    final isGroup = _isGroupMessage(msg);
    print('✅ Processing ${isGroup ? "group" : "direct"} message: $messageId (from $source)');
    _updateConversationWithMessage(msg);
  }
// conversation_cubit.dart (inside ConversationCubit)
  void _handleMessagesRead(dynamic payload) {
    try {
      if (payload == null) return;

      // Accept multiple possible field names coming from different server shapes
      final int readCount = int.tryParse('${payload['read_count'] ?? payload['readCount'] ?? payload['readCount'] ?? 0}') ?? 0;
      final String? groupId = (payload['group_id'] ?? payload['groupId'] ?? payload['channel'] ?? payload['conversation_id'] ?? payload['conversationId'] ?? payload['to_id'] ?? payload['toId'])?.toString();
      final String? otherUserId = (payload['other_user_id'] ?? payload['otherUserId'] ?? payload['otherUser'] ?? payload['other_user'] ?? payload['other'])?.toString();
      final String? byUser = (payload['by'] ?? payload['by_id'] ?? payload['user_id'] ?? payload['actor'] ?? payload['userId'])?.toString();

      // If readCount is zero but the read was performed by current user, we still want
      // to clear unread badge locally (server sometimes sends 0 but indicates read via "by").
      final bool performedByMe = byUser != null && byUser == _currentUserId.toString();

      // If nothing to match on, try to derive from nested shapes
      String? convKey = groupId ?? otherUserId;
      if (convKey == null || convKey.isEmpty) {
        // Try to inspect nested conversation field
        try {
          final conv = (payload['conversation'] ?? payload['conversation'] ?? payload);
          if (conv is Map<String, dynamic>) {
            convKey = (conv['group_id'] ?? conv['groupId'] ?? conv['to_id'] ?? conv['toId'] ?? conv['to'])?.toString();
            if (convKey == null || convKey.isEmpty) {
              // For direct messages, use from_id or to_id
              convKey = (conv['from_id'] ?? conv['fromId'] ?? conv['sender_id'] ?? conv['sender'] ?? conv['to_id'] ?? conv['toId'])?.toString();
            }
          }
        } catch (_) {}
      }

      if ((readCount <= 0) && !performedByMe && (convKey == null || convKey.isEmpty)) {
        // Nothing actionable
        print('⚠️ _handleMessagesRead: no actionable data (readCount=0 and not by current user and no conv key)');
        return;
      }

      bool changed = false;

      // Helper to check match for a conversation
      bool _matchesConv(Conversation conv) {
        final convGroupId = conv.groupId ?? conv.id;
        // group match
        if (convKey != null && convKey.isNotEmpty && convGroupId == convKey) return true;
        // direct match by user ids
        if (otherUserId != null && otherUserId.isNotEmpty && conv.id == otherUserId) return true;
        // match by payload 'by' when conversation id equals by (rare)
        if (byUser != null && conv.id == byUser) return true;
        return false;
      }

      // If performed by me -> clear unread for matches
      if (performedByMe) {
        final oldAll = _allConversations;
        final updatedAll = oldAll.map((conv) {
          if (_matchesConv(conv)) {
            if (conv.unreadCount != 0) changed = true;
            return conv.copyWith(unreadCount: 0, isUnread: false, lastReadAt: DateTime.now());
          }
          return conv;
        }).toList();

        final updatedUnread = _unreadConversations.where((conv) => !_matchesConv(conv)).toList();

        if (changed) {
          _allConversations = updatedAll;
          _unreadConversations = updatedUnread;
          _emitAllLoadedState();
          print('📣 messages_read applied (by me): convKey=$convKey by=$byUser readCount=$readCount');
        } else {
          print('messages_read by me processed but no matching conversation had unread badges');
        }

        return;
      }

      // Otherwise, use readCount to decrement unread counts (if server sent explicit count)
      if (readCount > 0) {
        _allConversations = _allConversations.map((conv) {
          if (_matchesConv(conv)) {
            final nextUnread = (conv.unreadCount - readCount).clamp(0, conv.unreadCount);
            if (nextUnread != conv.unreadCount) {
              changed = true;
              return conv.copyWith(unreadCount: nextUnread, lastReadAt: DateTime.now());
            }
          }
          return conv;
        }).toList();

        _unreadConversations = _unreadConversations.map((conv) {
          if (_matchesConv(conv)) {
            final newUnread = (conv.unreadCount - readCount).clamp(0, conv.unreadCount);
            if (newUnread != conv.unreadCount) {
              changed = true;
              return conv.copyWith(unreadCount: newUnread, lastReadAt: DateTime.now());
            }
          }
          return conv;
        }).where((c) => c.unreadCount > 0).toList();

        if (changed) {
          _emitAllLoadedState();
          print('📣 messages_read applied: groupId=$convKey by=$byUser readCount=$readCount');
          final updated = _allConversations.where((c) => _matchesConv(c)).toList();
          print('📣 Updated conversations after messages_read count=${updated.length}');
          for (var c in updated) {
            print('   - conv id=${c.id} groupId=${c.groupId} unread=${c.unreadCount}');
          }
        } else {
          print('messages_read handled but no matching conversations found locally');
        }

        return;
      }

      // If we reached here, nothing changed and readCount was zero and not by current user
    } catch (e, st) {
      print('Exception in _handleMessagesRead: $e\n$st');
    }
  }
/*
  void _handleMessagesRead(dynamic payload) {
    print('📖 Handling messages_read event');

    if (state is! ConversationLoaded) return;

    final groupId = payload['group_id']?.toString();
    final userId = payload['user_id']?.toString();
    final byUserId = payload['by']?.toString();

    // Determine the conversation ID
    String? conversationId;
    if (groupId != null) {
      conversationId = groupId;
    } else if (userId != null) {
      conversationId = userId;
    }

    if (conversationId == null) {
      print('⚠️ No valid conversation ID in messages_read event');
      return;
    }

    // Only process if message was read by current user
    if (byUserId == _currentUserId.toString()) {
      print('📖 Marking messages as read for conversation: $conversationId');

      final st = state as ConversationLoaded;

      // Update in ALL chats - mark as read
      final updatedAll = st.allChats.map((c) {
        final matches = (c.isGroup && c.groupId == conversationId) ||
            (!c.isGroup && c.id == conversationId);

        if (matches) {
          return c.copyWith(
            unreadCount: 0,
            isUnread: false,
          );
        }
        return c;
      }).toList();

      // Remove from UNREAD chats
      final updatedUnread = st.unreadChats.where((c) {
        final matches = (c.isGroup && c.groupId == conversationId) ||
            (!c.isGroup && c.id == conversationId);
        return !matches; // Keep only non-matching conversations
      }).toList();

      _allConversations = updatedAll;
      _unreadConversations = updatedUnread;

      print('✅ Updated conversations after messages_read');
      _emitLoadedState();
    }
  }
  */

  /* --------------------------------------------------------------------- */
  /*                         MESSAGE EXTRACTION                            */
  /* --------------------------------------------------------------------- */
  Map<String, dynamic>? _extractMessageMap(dynamic payload) {
    try {
      if (payload is! Map<String, dynamic>) return null;
      final c = payload['conversation'] ?? payload;

      // Get sender info and receiver/other user info if available
      final sender = c['sender'] ?? c['user'] ?? payload['from_user'] ?? payload['fromUser'] ?? c['from_user'];
      final toUser = c['to_user'] ?? payload['to_user'] ?? c['receiver'] ?? payload['receiver'] ?? c['user'];

      return {
        '_id': c['_id'] ?? c['id'],
        'from_id': c['from_id'] ?? sender?['id'],
        'to_id': c['to_id'],
        'to_type': c['to_type'],
        'group_id': c['group_id'] ?? c['groupId'],
        'message': c['message'] ?? payload['message'] ?? '',
        'group_name': c['group'] != null ? (c['group']['name'] ?? c['group']['title']) : (c['group_name'] ?? payload['group_name']),
        'message_type': c['message_type'] ?? 0,
        'created_at': c['created_at'] ?? c['createdAt'] ?? DateTime.now().toIso8601String(),
        'sender': sender,
        'to_user': toUser,
      };
    } catch (e) {
      print('❌ extractMessage error: $e');
      return null;
    }
  }

  /* --------------------------------------------------------------------- */
  /*                         CONVERSATION UPDATE                           */
  /* --------------------------------------------------------------------- */
  void _updateConversationWithMessage(Map<String, dynamic> msg) {
    // Operate directly on internal lists so updates work even when the
    // ConversationCubit UI state hasn't emitted ConversationLoaded yet.
    final convId = _conversationIdFromMessage(msg);
    final isGroup = _isGroupMessage(msg);
    final lastText = _formatLastMessage(msg);
    final ts = _parseTimestamp(msg);
    final own = _isOwnMessage(msg);

    print('🟢 Updating conversation - ID: $convId, isGroup: $isGroup, isOwn: $own');

    final msgId = (msg['_id'] ?? msg['id'])?.toString();
    final fromId = msg['from_id']?.toString();
    final toId = msg['to_id']?.toString();
    final groupId = msg['group_id']?.toString();

    // Work on copies and then assign back to avoid mutating while iterating
    final all = List<Conversation>.from(_allConversations);
    final unread = List<Conversation>.from(_unreadConversations);

    int idx = -1;
    for (var i = 0; i < all.length; i++) {
      final c = all[i];

      final matchesGroup = c.isGroup && (
        (groupId != null && c.groupId == groupId) ||
        (toId != null && c.groupId == toId) ||
        (c.groupId == convId)
      );

      final matchesDirect = !c.isGroup && (
        (c.id == convId) ||
        (msgId != null && c.id == msgId) ||
        (fromId != null && c.id == fromId) ||
        (toId != null && c.id == toId) ||
        (c.groupId != null && c.groupId == groupId)
      );

      if ((isGroup && matchesGroup) || (!isGroup && matchesDirect)) {
        idx = i;
        break;
      }
    }

    if (idx >= 0) {
      final old = all[idx];
      // If incoming message timestamp is older or equal to stored timestamp,
      // treat it as duplicate/unchanged and do not reorder or change unread counts.
      if (ts.isBefore(old.timestamp) || ts.isAtSameMomentAs(old.timestamp)) {
        print('⏭️ Incoming message ts <= existing ts, skipping update for conv $convId');
        return;
      }
      final newUnread = own ? old.unreadCount : old.unreadCount + 1;
      final updated = old.copyWith(
        lastMessage: lastText,
        timestamp: ts,
        unreadCount: newUnread,
        isUnread: newUnread > 0,
      );

      // Move updated conversation to top in 'all'
      all.removeAt(idx);
      all.insert(0, updated);

      // Update unread list
      if (!own) {
        final uIdx = unread.indexWhere((c) => (!isGroup && !c.isGroup && c.id == updated.id) || (isGroup && c.isGroup && c.groupId == updated.groupId));
        if (uIdx >= 0) {
          unread.removeAt(uIdx);
        }
        unread.insert(0, updated);
      } else {
        // If own message, ensure it's not listed as unread
        unread.removeWhere((c) => (!isGroup && !c.isGroup && c.id == updated.id) || (isGroup && c.isGroup && c.groupId == updated.groupId));
      }

      _allConversations = all;
      _unreadConversations = unread;
      print('✅ Updated conversation lists - Last message: $lastText');
      _emitAllLoadedState();
    } else {
      print('⚠️ Conversation not found, creating new');
      _createConversationFromMessage(msg, convId, isGroup);
    }
  }

  void _createConversationFromMessage(
      Map<String, dynamic> msg,
      String convId,
      bool isGroup,
      ) {
    // Create conversation entry from the incoming message even if UI hasn't
    // previously loaded conversations. Prefer to_user when current user is
    // the sender so we don't show the current user's name as the conversation title.
    final sender = msg['sender'] as Map<String, dynamic>?;
    final toUser = msg['to_user'] as Map<String, dynamic>?;

    String title;
    if (isGroup) {
      title = msg['group_name']?.toString() ?? 'New Group';
    } else {
      if (_isOwnMessage(msg)) {
        title = toUser?['name']?.toString() ?? sender?['name']?.toString() ?? 'Unknown User';
      } else {
        title = sender?['name']?.toString() ?? toUser?['name']?.toString() ?? 'Unknown User';
      }
    }

    final avatar = isGroup
        ? null
        : ( ( ! _isOwnMessage(msg) ? (sender?['photo_url'] ?? sender?['photoUrl']) : (toUser?['photo_url'] ?? toUser?['photoUrl']) )?.toString() );

    final newConv = Conversation(
      id: convId,
      groupId: isGroup ? convId : null,
      title: title,
      lastMessage: _formatLastMessage(msg),
      timestamp: _parseTimestamp(msg),
      unreadCount: _isOwnMessage(msg) ? 0 : 1,
      avatarUrl: avatar,
      isGroup: isGroup,
      isUnread: !_isOwnMessage(msg),
    );

    // Insert at top of internal lists
    _allConversations = [newConv, ..._allConversations];
    if (!_isOwnMessage(msg)) {
      _unreadConversations = [newConv, ..._unreadConversations];
    }

    print('✅ Created new conversation (from socket)');
    _emitAllLoadedState();

    // Try quick user lookup to replace placeholders if needed
    if (!isGroup && _isOwnMessage(msg)) {
      _updateConversationTitleFromUserId(convId);
    }

    // Also refresh conversations in background to get authoritative data
    Future.microtask(() async {
      try {
        await loadConversations(refresh: true);
      } catch (_) {}
    });
  }

  // Lazy message repository to query users when needed
  MessageRepository? _messageRepo;

  Future<MessageRepository> get _msgRepo async {
    _messageRepo ??= MessageRepository(DioClient());
    return _messageRepo!;
  }

  Future<void> _updateConversationTitleFromUserId(String userIdStr) async {
    try {
      final userId = int.tryParse(userIdStr) ?? 0;
      if (userId == 0) return;

      final repo = await _msgRepo;
      // Fetch first page with more items to find the user quickly
      final resp = await repo.getUsersList(userId: _currentUserId, page: 1, perPage: 50);
      if (!resp.success || resp.data == null) return;

      final users = resp.data!.users;
      final matches = users.where((u) => u.id == userId).toList();
      if (matches.isEmpty) return;
      final found = matches.first;

      // Update the conversation title in internal lists and emit updated states
      final updatedAll = _allConversations.map((c) {
        if (!c.isGroup && c.id == userIdStr) {
          return c.copyWith(title: found.name, avatarUrl: null);
        }
        return c;
      }).toList();

      final updatedUnread = _unreadConversations.map((c) {
        if (!c.isGroup && c.id == userIdStr) {
          return c.copyWith(title: found.name, avatarUrl: null);
        }
        return c;
      }).toList();

      _allConversations = updatedAll;
      _unreadConversations = updatedUnread;
      // Emit both updated states so UI reflects changes regardless of active tab
      _emitAllLoadedState();
      _emitUnreadLoadedState();
    } catch (e) {
      print('❌ Failed to update conversation title from user id: $e');
    }
  }

  /* --------------------------------------------------------------------- */
  /*                         HELPERS                                       */
  /* --------------------------------------------------------------------- */
  bool _isOwnMessage(Map<String, dynamic> msg) {
    final from = msg['from_id']?.toString();
    final currentId = _currentUserId.toString();
    final isOwn = from == currentId;
    print('👤 Message from: $from, Current user: $currentId, Is own: $isOwn');
    return isOwn;
  }

  String _formatLastMessage(Map<String, dynamic> msg) {
    final txt = msg['message']?.toString() ?? '';
    if (txt.contains('<img')) return 'Photo';
    if (txt.contains('<video')) return 'Video';
    if (txt.contains('<audio')) return 'Audio';
    if (txt.contains('<a href')) return 'File';

    // Remove HTML tags and trim
    final cleaned = txt.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    print('📝 Formatted message: "${cleaned}"');
    return cleaned;
  }

  DateTime _parseTimestamp(Map<String, dynamic> msg) {
    final raw = msg['created_at']?.toString();
    return raw != null
        ? DateTime.tryParse(raw) ?? DateTime.now()
        : DateTime.now();
  }

  /* --------------------------------------------------------------------- */
  /*                         PUBLIC API                                    */
  /* --------------------------------------------------------------------- */
  void initializeSocketConnection(String token) {
    _socket.initializeSocket(token);
    _socket.connect();
    _socket.joinUserRoom(_currentUserId.toString());
    _socket.requestConversations();
  }

  // Public API: allow external callers (e.g., after closing ChatScreen)
  // to forward a raw message payload (same shape as socket payload) so
  // the conversation lists are updated locally without calling the API.
  void processRawMessage(dynamic payload) {
    // Reuse existing new message handling pipeline. Treat as standalone
    // so it won't be duplicated by other listeners.
    _handleNewMessage(payload, fromStandalone: true);
  }

  void joinConversation(String convId) => _socket.joinConversation(convId);
  void leaveConversation(String convId) => _socket.leaveConversation(convId);

  void sendMessage({
    required String conversationId,
    required String content,
    required String senderId,
  }) {
    _socket.sendMessage({
      'conversationId': conversationId,
      'content': content,
      'senderId': senderId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  void markMessageAsRead(String msgId, String convId) {
    _socket.markMessageAsRead(msgId, convId);

    // Update internal lists locally so UI updates immediately without refetch.
    bool changed = false;
    _allConversations = _allConversations.map((c) {
      if ((c.isGroup && c.groupId == convId) || (!c.isGroup && c.id == convId)) {
        changed = true;
        return c.copyWith(unreadCount: 0, isUnread: false);
      }
      return c;
    }).toList();

    final beforeUnreadLen = _unreadConversations.length;
    _unreadConversations = _unreadConversations.where((c) {
      final matches = (c.isGroup && c.groupId == convId) || (!c.isGroup && c.id == convId);
      return !matches;
    }).toList();

    if (changed || _unreadConversations.length != beforeUnreadLen) {
      // Emit both states so whichever tab is active will update
      _emitAllLoadedState();
      _emitUnreadLoadedState();
    }
  }

  void sendTyping(String convId, bool typing) =>
      _socket.sendTypingIndicator(convId, typing);

  @override
  Future<void> close() {
    _socket.dispose();
    return super.close();
  }

  /* --------------------------------------------------------------------- */
  /*                         CONVERSATION ID                              */
  /* --------------------------------------------------------------------- */
  String _conversationIdFromMessage(Map<String, dynamic> msg) {
    final groupId = msg['group_id']?.toString();
    final toId = msg['to_id']?.toString();
    final toType = msg['to_type']?.toString();

    // Priority 1: Group ID
    if (groupId != null && groupId.isNotEmpty && groupId != '0') {
      print('📋 Conversation ID from group_id: $groupId');
      return groupId;
    }

    // Priority 2: to_type contains Group
    if (toType?.contains('Group') == true) {
      print('📋 Conversation ID from to_id (Group type): $toId');
      return toId ?? 'unknown';
    }

    // Priority 3: to_id contains UUID format (groups use UUIDs)
    if (toId != null && toId.contains('-')) {
      print('📋 Conversation ID from to_id (UUID): $toId');
      return toId;
    }

    // Priority 4: Direct message - use other user's ID
    final own = _isOwnMessage(msg);
    final other = own ? toId : msg['from_id']?.toString();
    print('📋 Conversation ID from ${own ? "to_id" : "from_id"}: $other');

    return other?.toString() ?? 'unknown';
  }

  bool _isGroupMessage(Map<String, dynamic> msg) {
    final groupId = msg['group_id']?.toString();
    final toType = msg['to_type']?.toString();
    final toId = msg['to_id']?.toString();

    final isGroup =
        (groupId != null && groupId.isNotEmpty && groupId != '0') ||
            toType?.contains('Group') == true ||
            (toId != null && toId.contains('-'));

    return isGroup;
  }
}

