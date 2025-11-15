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
      emit(ConversationLoading());
    }

    try {
      _isLoadingMore = !refresh;

      final ApiResponse<ConversationResponse> resp = await _repo
          .getConversations(page: _currentPage, query: _currentQuery);

      if (!resp.success || resp.data == null) {
        emit(ConversationError(resp.message ?? 'Failed to load'));
        _isLoadingMore = false;
        return;
      }

      final List<Conversation> newConversations = resp.data!.data.conversations;
      final Meta? meta = resp.data?.meta;
      final int currentPage = meta?.currentPage ?? 1;
      final int lastPage = meta?.lastPage ?? 1;
      final int perPage = meta?.perPage ?? 10;
      final int total = meta?.total ?? 0;

      final bool metaHasNext = meta?.hasNextPage ?? false;
      final bool computedHasNext =
          (currentPage < lastPage) || (currentPage * perPage) < total;

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
      emit(ConversationLoading());
    }

    try {
      _unreadIsLoadingMore = !refresh;

      final ApiResponse<ConversationResponse> resp = await _repo
          .getUnreadConversations(
        page: _unreadCurrentPage,
        query: _unreadCurrentQuery,
      );

      if (!resp.success || resp.data == null) {
        emit(ConversationError(resp.message ?? 'Failed to load unread'));
        _unreadIsLoadingMore = false;
        return;
      }

      final List<Conversation> newUnreadConversations =
          resp.data?.data.conversations ?? [];
      final Meta? meta = resp.data?.meta;
      final int currentPage = meta?.currentPage ?? 1;
      final int lastPage = meta?.lastPage ?? 1;
      final int perPage = meta?.perPage ?? 10;
      final int total = meta?.total ?? 0;

      final bool metaHasNext = meta?.hasNextPage ?? false;
      final bool computedHasNext =
          (currentPage < lastPage) || (currentPage * perPage) < total;

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

  void _emitUnifiedLoadedState() {
    emit(
      ConversationLoaded(
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
      ),
    );
  }

  Future<void> refresh() => loadConversations(refresh: true);
  Future<void> refreshUnread() => loadUnreadConversations(refresh: true);

  // Public getters
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
      final action = data?['action']?.toString() ?? data?['type']?.toString();

      print('🔄 Socket: event=$event, action=$action');

      // ✅ Handle by ACTION only (ignore event type)
      _handleSocketAction(action, data);
    });
  }

  /* --------------------------------------------------------------------- */
  /*                    CENTRALIZED ACTION ROUTER                          */
  /* --------------------------------------------------------------------- */

  void _handleSocketAction(String? action, dynamic data) {
    if (action == null || data == null) return;

    switch (action) {
    // ══════════════════════════════════════════════════════════════
    // GROUP 1: MESSAGE ACTIONS
    // ══════════════════════════════════════════════════════════════
      case 'new_message':
        _handleNewMessage(data);
        break;

      case 'messages_read':
        _handleMessagesRead(data);
        break;

    // ══════════════════════════════════════════════════════════════
    // GROUP 2: GROUP MANAGEMENT ACTIONS
    // ══════════════════════════════════════════════════════════════
      case 'group_created':
        _handleGroupCreated(data);
        break;

      case 'group_updated':
        _handleGroupUpdated(data['group'] as Map<String, dynamic>?);
        break;

      case 'group_deleted':
      case 'deleted':
        _handleGroupDeleted(data['group_id']?.toString());
        break;

    // ══════════════════════════════════════════════════════════════
    // GROUP 3: CONVERSATION ACTIONS
    // ══════════════════════════════════════════════════════════════
      case 'chat_request':
      case 'existing_chat':
      case 'new_conversation':
        _handleConversationEvent(data);
        break;

    // ══════════════════════════════════════════════════════════════
    // UNKNOWN ACTIONS
    // ══════════════════════════════════════════════════════════════
      default:
        print('ℹ️ Unhandled action: $action');
        break;
    }
  }

  /* --------------------------------------------------------------------- */
  /*                    GROUP 1: MESSAGE HANDLERS                          */
  /* --------------------------------------------------------------------- */

  void _handleNewMessage(dynamic payload) {
    print('📨 Processing new_message');

    // Extract message
    final msg = _extractMessageMap(payload);
    if (msg == null) {
      print('❌ Failed to extract message');
      return;
    }

    // Create unique message ID
    final messageId = msg['_id']?.toString() ??
        '${msg['from_id']}_${msg['to_id']}_${msg['created_at']}';

    // ✅ Deduplication check
    if (_processedMessageIds.contains(messageId)) {
      print('⏭️ Skipping duplicate message: $messageId');
      return;
    }

    // Mark as processed
    _processedMessageIds.add(messageId);

    // Clean up old IDs (keep last 100)
    if (_processedMessageIds.length > 100) {
      final toRemove = _processedMessageIds.length - 100;
      _processedMessageIds.removeAll(_processedMessageIds.take(toRemove));
    }

    final isGroup = _isGroupMessage(msg);
    print('✅ Processing ${isGroup ? "group" : "direct"} message: $messageId');
    _updateConversationWithMessage(msg);
  }

  void _handleMessagesRead(dynamic payload) {
    try {
      if (payload == null) return;

      // Extract all possible field names
      final readCount = int.tryParse(
          '${payload['read_count'] ?? payload['readCount'] ?? 0}'
      ) ?? 0;

      final groupId = (
          payload['group_id'] ??
              payload['groupId'] ??
              payload['channel'] ??
              payload['conversation_id'] ??
              payload['conversationId'] ??
              payload['to_id'] ??
              payload['toId']
      )?.toString();

      final otherUserId = (
          payload['other_user_id'] ??
              payload['otherUserId'] ??
              payload['otherUser'] ??
              payload['other_user'] ??
              payload['other']
      )?.toString();

      final byUser = (
          payload['by'] ??
              payload['by_id'] ??
              payload['user_id'] ??
              payload['actor'] ??
              payload['userId']
      )?.toString();

      final performedByMe = byUser != null && byUser == _currentUserId.toString();
      String? convKey = groupId ?? otherUserId;

      // Try to extract from nested conversation
      if (convKey == null || convKey.isEmpty) {
        try {
          final conv = payload['conversation'] ?? payload;
          if (conv is Map<String, dynamic>) {
            convKey = (
                conv['group_id'] ??
                    conv['groupId'] ??
                    conv['to_id'] ??
                    conv['toId'] ??
                    conv['from_id'] ??
                    conv['fromId'] ??
                    conv['sender_id'] ??
                    conv['sender']
            )?.toString();
          }
        } catch (_) {}
      }

      // Nothing actionable
      if ((readCount <= 0) && !performedByMe && (convKey == null || convKey.isEmpty)) {
        print('⚠️ messages_read: No actionable data');
        return;
      }

      bool changed = false;

      // Helper to match conversation
      bool matchesConv(Conversation conv) {
        final convGroupId = conv.groupId ?? conv.id;
        if (convKey != null && convKey.isNotEmpty && convGroupId == convKey) return true;
        if (otherUserId != null && otherUserId.isNotEmpty && conv.id == otherUserId) return true;
        if (byUser != null && conv.id == byUser) return true;
        return false;
      }

      // If performed by current user -> clear unread
      if (performedByMe) {
        _allConversations = _allConversations.map((conv) {
          if (matchesConv(conv)) {
            if (conv.unreadCount != 0) changed = true;
            return conv.copyWith(
              unreadCount: 0,
              isUnread: false,
              lastReadAt: DateTime.now(),
            );
          }
          return conv;
        }).toList();

        _unreadConversations = _unreadConversations
            .where((conv) => !matchesConv(conv))
            .toList();

        if (changed) {
          _emitUnifiedLoadedState();
          print('📣 messages_read applied (by me): convKey=$convKey');
        } else {
          print('ℹ️ messages_read by me processed but no match found');
        }
        return;
      }

      // Decrement unread count
      if (readCount > 0) {
        _allConversations = _allConversations.map((conv) {
          if (matchesConv(conv)) {
            final nextUnread = (conv.unreadCount - readCount).clamp(0, conv.unreadCount);
            if (nextUnread != conv.unreadCount) {
              changed = true;
              return conv.copyWith(
                unreadCount: nextUnread,
                lastReadAt: DateTime.now(),
              );
            }
          }
          return conv;
        }).toList();

        _unreadConversations = _unreadConversations
            .map((conv) {
          if (matchesConv(conv)) {
            final newUnread = (conv.unreadCount - readCount).clamp(0, conv.unreadCount);
            if (newUnread != conv.unreadCount) {
              changed = true;
              return conv.copyWith(
                unreadCount: newUnread,
                lastReadAt: DateTime.now(),
              );
            }
          }
          return conv;
        })
            .where((c) => c.unreadCount > 0)
            .toList();

        if (changed) {
          _emitUnifiedLoadedState();
          print('📣 messages_read applied: convKey=$convKey, readCount=$readCount');
        } else {
          print('ℹ️ messages_read handled but no match found');
        }
      }
    } catch (e, st) {
      print('❌ Exception in _handleMessagesRead: $e\n$st');
    }
  }

  /* --------------------------------------------------------------------- */
  /*                  GROUP 2: GROUP MANAGEMENT HANDLERS                   */
  /* --------------------------------------------------------------------- */

  void _handleGroupCreated(Map<String, dynamic>? data) {
    if (data == null) return;

    print('🆕 Processing group_created');

    try {
      // Priority 1: Use system message if available
      final systemMessage =
          data['systemMessage'] ??
              data['conversation'] ??
              data['notification'];

      if (systemMessage != null && systemMessage is Map<String, dynamic>) {
        if (systemMessage.containsKey('message') || systemMessage.containsKey('_id')) {
          _handleConversationEvent({'conversation': systemMessage});
          return;
        }
      }

      // Priority 2: Build from group data
      final createdGroup =
          data['created_group'] ??
              data['group'] ??
              data['groupData'];

      if (createdGroup != null && createdGroup is Map<String, dynamic>) {
        final groupId = createdGroup['id']?.toString();
        final creatorId =
            data['creator_id']?.toString() ??
                createdGroup['created_by']?.toString();

        final convMap = {
          '_id': data['notification']?['id'] ?? '${groupId}_created',
          'from_id': creatorId,
          'to_id': groupId,
          'to_type': 'App\\Models\\Group',
          'group_id': groupId,
          'message':
          data['notification']?['body'] ??
              data['notification']?['title'] ??
              'Group created',
          'message_type': 9,
          'created_at': DateTime.now().toIso8601String(),
          'sender': {
            'id': creatorId,
            'name': createdGroup['name'] ?? 'Group',
          },
          'group': createdGroup,
        };

        _handleConversationEvent({'conversation': convMap});
        return;
      }

      // Fallback: Refresh from server
      print('⚠️ group_created: No usable data, refreshing');
      loadConversations(refresh: true);

    } catch (e) {
      print('❌ Error in group_created: $e');
      loadConversations(refresh: true);
    }
  }

  void _handleGroupUpdated(Map<String, dynamic>? group) {
    if (group == null) return;

    final gid = (
        group['id'] ??
            group['group_id'] ??
            group['groupId']
    )?.toString();

    if (gid == null || gid.isEmpty) return;

    print('♻️ Processing group_updated: $gid');

    bool changed = false;

    _allConversations = _allConversations.map((c) {
      if (c.isGroup && c.groupId == gid) {
        changed = true;
        return c.copyWith(
          title: (group['name'] ?? group['title'])?.toString() ?? c.title,
          avatarUrl: (group['photo_url'] ?? group['photoUrl'])?.toString() ?? c.avatarUrl,
        );
      }
      return c;
    }).toList();

    _unreadConversations = _unreadConversations.map((c) {
      if (c.isGroup && c.groupId == gid) {
        return c.copyWith(
          title: (group['name'] ?? group['title'])?.toString() ?? c.title,
          avatarUrl: (group['photo_url'] ?? group['photoUrl'])?.toString() ?? c.avatarUrl,
        );
      }
      return c;
    }).toList();

    if (changed) {
      _emitUnifiedLoadedState();
      print('✅ Group updated: $gid');
    }
  }

  void _handleGroupDeleted(String? groupId) {
    if (groupId == null || groupId.isEmpty) {
      print('⚠️ group_deleted: No group ID');
      return;
    }

    print('🗑️ Processing group_deleted: $groupId');

    final beforeCount = _allConversations.length;

    _allConversations = _allConversations
        .where((c) => !(c.isGroup && c.groupId == groupId))
        .toList();

    _unreadConversations = _unreadConversations
        .where((c) => !(c.isGroup && c.groupId == groupId))
        .toList();

    if (_allConversations.length != beforeCount) {
      _emitUnifiedLoadedState();
      print('✅ Removed conversations for deleted group: $groupId');
    }
  }

  /* --------------------------------------------------------------------- */
  /*                 GROUP 3: CONVERSATION HANDLERS                        */
  /* --------------------------------------------------------------------- */

  void _handleConversationEvent(dynamic payload) {
    try {
      if (payload == null) return;

      final conv = (payload is Map<String, dynamic>)
          ? (payload['conversation'] ?? payload)
          : null;

      if (conv == null || conv is! Map<String, dynamic>) {
        print('⚠️ conversation_event: No usable data, refreshing');
        loadConversations(refresh: true);
        return;
      }

      print('💬 Processing conversation_event');

      // Map to message-like shape
      final msg = <String, dynamic>{
        '_id': conv['_id'] ?? conv['id'],
        'from_id':
        conv['from_id'] ??
            conv['fromId'] ??
            conv['creator_id'] ??
            conv['created_by'],
        'to_id':
        conv['to_id'] ??
            conv['toId'] ??
            conv['group_id'] ??
            conv['groupId'],
        'to_type':
        conv['to_type'] ??
            conv['toType'] ??
            (conv['group'] != null ? 'App\\Models\\Group' : 'App\\Models\\Conversation'),
        'group_id':
        conv['group_id'] ??
            conv['groupId'] ??
            (conv['group'] != null ? conv['group']['id'] : null),
        'message':
        conv['message'] ??
            conv['body'] ??
            conv['title'] ??
            '',
        'message_type': conv['message_type'] ?? conv['type'] ?? 0,
        'created_at':
        conv['created_at'] ??
            conv['createdAt'] ??
            DateTime.now().toIso8601String(),
        'sender':
        conv['sender'] ??
            conv['user'] ??
            conv['from_user'],
        'group': conv['group'] ?? conv['created_group'],
      };

      _handleNewMessage({'conversation': msg});

    } catch (e) {
      print('❌ Error in conversation_event: $e');
      loadConversations(refresh: true);
    }
  }

  /* --------------------------------------------------------------------- */
  /*                         MESSAGE EXTRACTION                            */
  /* --------------------------------------------------------------------- */

  Map<String, dynamic>? _extractMessageMap(dynamic payload) {
    try {
      if (payload is! Map<String, dynamic>) return null;

      final c = payload['conversation'] ?? payload;

      final sender =
          c['sender'] ??
              c['user'] ??
              payload['from_user'] ??
              payload['fromUser'] ??
              c['from_user'];

      final toUser =
          c['to_user'] ??
              payload['to_user'] ??
              c['receiver'] ??
              payload['receiver'] ??
              c['user'];

      return {
        '_id': c['_id'] ?? c['id'],
        'from_id': c['from_id'] ?? sender?['id'],
        'to_id': c['to_id'],
        'to_type': c['to_type'],
        'group_id': c['group_id'] ?? c['groupId'],
        'message': c['message'] ?? payload['message'] ?? '',
        'group_name':
        c['group'] != null
            ? (c['group']['name'] ?? c['group']['title'])
            : (c['group_name'] ?? payload['group_name']),
        'message_type': c['message_type'] ?? 0,
        'created_at':
        c['created_at'] ??
            c['createdAt'] ??
            DateTime.now().toIso8601String(),
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

    final all = List<Conversation>.from(_allConversations);
    final unread = List<Conversation>.from(_unreadConversations);

    int idx = -1;
    for (var i = 0; i < all.length; i++) {
      final c = all[i];

      final matchesGroup =
          c.isGroup &&
              ((groupId != null && c.groupId == groupId) ||
                  (toId != null && c.groupId == toId) ||
                  (c.groupId == convId));

      final matchesDirect =
          !c.isGroup &&
              ((c.id == convId) ||
                  (msgId != null && c.id == msgId) ||
                  (fromId != null && c.id == fromId) ||
                  (toId != null && c.id == toId) ||
                  (c.groupId != null && c.groupId == groupId));

      if ((isGroup && matchesGroup) || (!isGroup && matchesDirect)) {
        idx = i;
        break;
      }
    }

    if (idx >= 0) {
      final old = all[idx];
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

      all.removeAt(idx);
      all.insert(0, updated);

      // Update unread list
      if (!own) {
        final uIdx = unread.indexWhere(
              (c) =>
          (!isGroup && !c.isGroup && c.id == updated.id) ||
              (isGroup && c.isGroup && c.groupId == updated.groupId),
        );
        if (uIdx >= 0) {
          unread.removeAt(uIdx);
        }
        unread.insert(0, updated);
      } else {
        unread.removeWhere(
              (c) =>
          (!isGroup && !c.isGroup && c.id == updated.id) ||
              (isGroup && c.isGroup && c.groupId == updated.groupId),
        );
      }

      _allConversations = all;
      _unreadConversations = unread;
      print('✅ Updated conversation lists - Last message: $lastText');
      _emitUnifiedLoadedState();
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
    final sender = msg['sender'] as Map<String, dynamic>?;
    final toUser = msg['to_user'] as Map<String, dynamic>?;

    String title;
    if (isGroup) {
      title = msg['group_name']?.toString() ?? 'New Group';
    } else {
      if (_isOwnMessage(msg)) {
        title =
            toUser?['name']?.toString() ??
                sender?['name']?.toString() ??
                'Unknown User';
      } else {
        title =
            sender?['name']?.toString() ??
                toUser?['name']?.toString() ??
                'Unknown User';
      }
    }

    final avatar = isGroup
        ? null
        : ((!_isOwnMessage(msg)
        ? (sender?['photo_url'] ?? sender?['photoUrl'])
        : (toUser?['photo_url'] ?? toUser?['photoUrl']))
        ?.toString());

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
      email: '',
    );

    _allConversations = [newConv, ..._allConversations];
    if (!_isOwnMessage(msg)) {
      _unreadConversations = [newConv, ..._unreadConversations];
    }

    print('✅ Created new conversation (from socket)');
    _emitUnifiedLoadedState();

    if (!isGroup && _isOwnMessage(msg)) {
      _updateConversationTitleFromUserId(convId);
    }

    Future.microtask(() async {
      try {
        await loadConversations(refresh: true);
      } catch (_) {}
    });
  }

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
      final resp = await repo.getUsersList(
        userId: _currentUserId,
        page: 1,
        perPage: 50,
      );
      if (!resp.success || resp.data == null) return;

      final users = resp.data!.users;
      final matches = users.where((u) => u.id == userId).toList();
      if (matches.isEmpty) return;
      final found = matches.first;

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
      _emitUnifiedLoadedState();
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

  void processRawMessage(dynamic payload) {
    _handleNewMessage(payload);
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

    bool changed = false;
    _allConversations = _allConversations.map((c) {
      if ((c.isGroup && c.groupId == convId) ||
          (!c.isGroup && c.id == convId)) {
        changed = true;
        return c.copyWith(unreadCount: 0, isUnread: false);
      }
      return c;
    }).toList();

    final beforeUnreadLen = _unreadConversations.length;
    _unreadConversations = _unreadConversations.where((c) {
      final matches =
          (c.isGroup && c.groupId == convId) || (!c.isGroup && c.id == convId);
      return !matches;
    }).toList();

    if (changed || _unreadConversations.length != beforeUnreadLen) {
      _emitUnifiedLoadedState();
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