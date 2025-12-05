import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/cores/network/socket_service.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/home/bloc/conversation_state.dart';
import 'package:hec_chat/feature/home/model/conversation_model.dart';
import 'package:hec_chat/feature/home/repository/conversation_repository.dart';
import 'package:hec_chat/feature/home/repository/message_repository.dart';
import 'package:hec_chat/cores/network/dio_client.dart';
import '../../../cores/constants/api_urls.dart';

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
      if (kDebugMode) {
        print('Error loading conversations: $e');
      }
      emit(ConversationError(e.toString()));
    }
  }

  //  Accept chat request
  Future<bool> acceptChatRequest(String requestId) async {
    try {
      if (kDebugMode) {
        print('Accepting chat request: $requestId');
      }

      final resp = await _repo.acceptChatRequest(requestId: requestId);

      if (!resp.success) {
        if (kDebugMode) {
          print('Accept request API failed: ${resp.message}');
        }
        return false;
      }

      // Update conversation locally
      _allConversations = _allConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'accepted');
        }
        return c;
      }).toList();

      _unreadConversations = _unreadConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'accepted');
        }
        return c;
      }).toList();

      _emitUnifiedLoadedState();
      if (kDebugMode) {
        print('Chat request accepted locally');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error accepting chat request: $e');
      }
      return false;
    }
  }

  //   Decline chat request
  Future<bool> declineChatRequest(String requestId) async {
    try {
      final resp = await _repo.declineChatRequest(requestId: requestId);

      if (!resp.success) {
        if (kDebugMode) {
          print('Decline request API failed: ${resp.message}');
        }
        return false;
      }

      // Update conversation locally
      _allConversations = _allConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'declined');
        }
        return c;
      }).toList();

      _unreadConversations = _unreadConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'declined');
        }
        return c;
      }).toList();

      _emitUnifiedLoadedState();
      if (kDebugMode) {
        print('Chat request declined locally');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error declining chat request: $e');
      }
      return false;
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
      if (kDebugMode) {
        print('Error loading unread conversations: $e');
      }
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

  // Delete a conversation (by groupId or user conv id). Returns true on success.
  Future<bool> deleteConversation(String conversationId) async {
    try {
      final resp = await _repo.deleteConversation(
        conversationId: conversationId,
      );
      if (!resp.success) {
        if (kDebugMode) {
          print('deleteConversation API failed: ${resp.message}');
        }
        return false;
      }

      // Remove from in-memory lists
      _allConversations.removeWhere(
        (c) =>
            (c.isGroup ? c.groupId == conversationId : c.id == conversationId),
      );
      _unreadConversations.removeWhere(
        (c) =>
            (c.isGroup ? c.groupId == conversationId : c.id == conversationId),
      );

      // Update filtered lists if needed
      _emitUnifiedLoadedState();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error in deleteConversation: $e');
      }
      return false;
    }
  }

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
    emit(ConversationInitial());
  }

  /* ---------------------------------------------------------------------
                           SOCKET LISTENERS
   --------------------------------------------------------------------- */

  void _listenToSocket() {
    _socket.addMessageListener((raw) {
      if (raw is! Map<String, dynamic>) return;

      final event = raw['event']?.toString();
      final data = raw['data'];
      final action = data?['action']?.toString() ?? data?['type']?.toString();

      // Handle by ACTION only (ignore event type)
      _handleSocketAction(action, data);
    });
  }

  /* ---------------------------------------------------------------------
                   CENTRALIZED ACTION ROUTER
   --------------------------------------------------------------------- */

  void _handleSocketAction(String? action, dynamic data) {
    if (action == null || data == null) return;

    switch (action) {
      // GROUP 1: MESSAGE ACTIONS
      case 'new_message':
        _handleNewMessage(data);
        break;

      case 'messages_read':
        _handleMessagesRead(data);
        break;

      // GROUP 2: GROUP MANAGEMENT ACTIONS

      case 'members_added':
        _handleMembersAdded(data);
        break;

      case 'admin_promoted':
        _handleAdminPromoted(data);
        break;

      case 'admin_dismissed':
        _handleAdminDismissed(data);
        break;

      case 'member_removed':
        _handleMemberRemoved(data);
        break;

      case 'member_left':
        _handleMemberLeft(data);
        break;

      case 'group_created':
        _handleGroupCreated(data);
        break;

      case 'group_updated':
        _handleGroupUpdated(data);
        break;

      case 'deleted':
        _handleGroupDeleted(data['group_id']?.toString());
        break;

      // GROUP 3: CONVERSATION ACTIONS
      case 'chat_request':
        _handleChatRequest(data);
        break;

      case 'chat_request_accepted':
        _handleChatRequestAccepted(data);
        break;

      case 'chat_request_declined':
        _handleChatRequestDeclined(data);
        break;

      case 'new_conversation':
        _handleConversationEvent(data);
        break;

      // Handle message deletion events so conversation preview updates
      case 'message_deleted_for_everyone':
      case 'message_deleted':
        _handleMessageDeletedForConversation(data);
        break;

      // UNKNOWN ACTIONS
      default:
        if (kDebugMode) {
          print('Unhandled action: $action');
        }
        break;
    }
  }

  // Handle when an admin is promoted in a group
  void _handleAdminPromoted(dynamic payload) {
    try {
      final groupId = payload['group_id']?.toString();
      if (groupId == null || groupId.isEmpty) {
        if (kDebugMode) {
          print('No group_id in admin_promoted payload');
        }
        return;
      }

      // Extract system message for last message preview
      final systemMessage = payload['systemMessage'] ?? payload['notification'];
      final lastMessageText =
          systemMessage?['message']?.toString() ??
          systemMessage?['body']?.toString() ??
          'Admin promoted';

      bool changed = false;

      // Update conversations with new last message
      _allConversations = _allConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          changed = true;
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      // Re-sort to move to top
      if (changed) {
        _allConversations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }

      _unreadConversations = _unreadConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Conversation updated after admin_promoted');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling admin_promoted: $e');
      }
    }
  }

  // Handle when an admin is dismissed in a group
  void _handleAdminDismissed(dynamic payload) {
    try {
      final groupId = payload['group_id']?.toString();
      if (groupId == null || groupId.isEmpty) {
        if (kDebugMode) {
          print('No group_id in admin_dismissed payload');
        }
        return;
      }

      // Extract system message
      final systemMessage = payload['systemMessage'] ?? payload['notification'];
      final lastMessageText =
          systemMessage?['message']?.toString() ??
          systemMessage?['body']?.toString() ??
          'Admin dismissed';

      bool changed = false;

      _allConversations = _allConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          changed = true;
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _allConversations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }

      _unreadConversations = _unreadConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Conversation updated after admin_dismissed');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling admin_dismissed: $e');
      }
    }
  }

  // temporary method
  void _handleMemberRemoved(dynamic payload) {
    try {
      final groupId = payload['group_id']?.toString();
      final removedUserId = payload['removed_user_id']?.toString();
      final removedBy = payload['removed_by']?.toString();

      if (groupId == null || groupId.isEmpty) {
        if (kDebugMode) {
          print('No group_id in member_removed payload');
        }
        return;
      }

      if (removedUserId == null || removedUserId.isEmpty) {
        if (kDebugMode) {
          print('No removed_user_id in member_removed payload');
        }
        return;
      }

      // Check if the current user was removed (either by someone else OR by themselves)
      final isCurrentUserRemoved = removedUserId == _currentUserId.toString();

      if (isCurrentUserRemoved) {
        if (kDebugMode) {
          print('Current user was removed from group: $groupId');
        }

        // Remove the group from conversations completely
        _allConversations = _allConversations
            .where((c) => !(c.isGroup && c.groupId == groupId))
            .toList();

        _unreadConversations = _unreadConversations
            .where((c) => !(c.isGroup && c.groupId == groupId))
            .toList();

        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Group removed from conversations (current user removed)');
        }
        return;
      }

      // If another member was removed (not current user), just update the last message
      final systemMessage = payload['systemMessage'] ?? payload['notification'];
      final lastMessageText =
          systemMessage?['message']?.toString() ??
          systemMessage?['body']?.toString() ??
          'Member removed';

      bool changed = false;

      _allConversations = _allConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          changed = true;
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _allConversations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }

      _unreadConversations = _unreadConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Conversation updated after member_removed (other member)');
        }
      } else {
        if (kDebugMode) {
          print('Group $groupId not found in conversations');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling member_removed: $e');
      }
    }
  }

  // Handle when a member leaves a group
  void _handleMemberLeft(dynamic payload) {
    try {
      final groupId = payload['group_id']?.toString();
      final leftUserId = payload['left_user_id']?.toString();

      if (groupId == null || groupId.isEmpty) {
        if (kDebugMode) {
          print('No group_id in member_left payload');
        }
        return;
      }

      // Check if the current user left the group
      final isCurrentUserLeft = leftUserId == _currentUserId.toString();

      if (isCurrentUserLeft) {
        print('Current user left group: $groupId');
        // Remove the group from conversations
        _allConversations = _allConversations
            .where((c) => !(c.isGroup && c.groupId == groupId))
            .toList();

        _unreadConversations = _unreadConversations
            .where((c) => !(c.isGroup && c.groupId == groupId))
            .toList();

        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Group removed from conversations after leaving');
        }
        return;
      }

      // If another member left, update the last message
      final systemMessage = payload['systemMessage'] ?? payload['notification'];
      final lastMessageText =
          systemMessage?['message']?.toString() ??
          systemMessage?['body']?.toString() ??
          'Member left';

      bool changed = false;

      _allConversations = _allConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          changed = true;
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _allConversations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }

      _unreadConversations = _unreadConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Conversation updated after member_left');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling member_left: $e');
      }
    }
  }

  void _handleMembersAdded(dynamic payload) {
    try {
      final groupId = payload['group_id']?.toString();
      if (groupId == null || groupId.isEmpty) {
        if (kDebugMode) {
          print('No group_id in members_added payload');
        }
        return;
      }

      // Extract system message for last message preview
      final systemMessage = payload['systemMessage'] ?? payload['notification'];
      final lastMessageText =
          systemMessage?['message']?.toString() ??
          systemMessage?['body']?.toString() ??
          'Members added to group';

      bool changed = false;

      // Update existing conversations with new last message
      _allConversations = _allConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          changed = true;
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      _unreadConversations = _unreadConversations.map((c) {
        if (c.isGroup && c.groupId == groupId) {
          return c.copyWith(
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Conversation updated after members_added');
        }
      } else {
        // Group might be new to this user - refresh to get it
        if (kDebugMode) {
          print('Group not found locally, refreshing conversations');
        }
        loadConversations(refresh: true);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling members_added: $e');
      }
    }
  }

  // update conversation preview when a message is deleted (for everyone)
  void _handleMessageDeletedForConversation(dynamic payload) {
    try {
      if (payload == null) return;

      // deleted message may be under deleted_message / deletedMessage / previousMessage
      final deletedMap =
          (payload['deleted_message'] ??
                  payload['deletedMessage'] ??
                  payload['previousMessage'] ??
                  payload)
              as Map<String, dynamic>?;
      if (deletedMap == null) return;

      final deletedId = (deletedMap['_id'] ?? deletedMap['id'] ?? payload['id'])
          ?.toString();
      if (deletedId == null) return;

      // Determine conversation key (group or direct)
      final groupId =
          (deletedMap['group_id'] ??
                  payload['group_id'] ??
                  payload['to_id'] ??
                  payload['conversation_id'])
              ?.toString();
      final fromId = (deletedMap['from_id'] ?? payload['from_id'])?.toString();
      final toId = (deletedMap['to_id'] ?? payload['to_id'])?.toString();

      bool changed = false;

      // Update all conversations list
      _allConversations = _allConversations.map((c) {
        final matches = c.isGroup
            ? (groupId != null && (c.groupId == groupId || c.id == groupId))
            : (c.id == fromId ||
                  c.id == toId ||
                  c.id == deletedMap['conversation_id']?.toString());

        if (matches) {
          changed = true;

          // If the deleted message was the conversation's last message, we need to find a new lastMessage.
          if (c.messages != null && c.messages!.isNotEmpty) {
            final remaining = c.messages!
                .where((m) => m.id != deletedId)
                .toList();
            if (remaining.isNotEmpty) {
              final last = remaining.last;
              // Safely read the last message text/timestamp from either Message model
              final String lastMsgText = (last.content.isNotEmpty)
                  ? last.content
                  : (last.message);
              final DateTime lastTs = last.timestamp;
              return c.copyWith(lastMessage: lastMsgText, timestamp: lastTs);
            }
          }

          // Fallback: show server-provided deleted message text or a generic placeholder
          final rawText =
              deletedMap['message']?.toString() ?? 'This message was deleted';
          return c.copyWith(lastMessage: rawText, timestamp: DateTime.now());
        }
        return c;
      }).toList();

      // Update unread list similarly
      _unreadConversations = _unreadConversations.map((c) {
        final matches = c.isGroup
            ? (groupId != null && (c.groupId == groupId || c.id == groupId))
            : (c.id == fromId ||
                  c.id == toId ||
                  c.id == deletedMap['conversation_id']?.toString());

        if (matches) {
          // Try to compute an updated lastMessage
          if (c.messages != null && c.messages!.isNotEmpty) {
            final remaining = c.messages!
                .where((m) => m.id != deletedId)
                .toList();
            if (remaining.isNotEmpty) {
              final last = remaining.last;
              final String lastMsgText = (last.content.isNotEmpty)
                  ? last.content
                  : (last.message);
              final DateTime lastTs = last.timestamp;
              return c.copyWith(lastMessage: lastMsgText, timestamp: lastTs);
            }
          }
          final rawText =
              deletedMap['message']?.toString() ?? 'This message was deleted';
          return c.copyWith(lastMessage: rawText, timestamp: DateTime.now());
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print(
            'Conversation preview updated after delete-for-everyone for id $deletedId',
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print(
          'Error handling message_deleted_for_everyone in ConversationCubit: $e',
        );
      }
    }
  }

  //   Handle new chat request
  void _handleChatRequest(dynamic payload) {
    try {
      final conv = _extractConversationFromPayload(payload);
      if (conv == null) {
        if (kDebugMode) {
          print('Failed to extract conversation from chat_request');
        }
        return;
      }

      // Only increment badge if we're the recipient
      if (conv.chatRequestTo == _currentUserId.toString()) {
        // Add or update conversation
        final existingIndex = _allConversations.indexWhere(
          (c) => (c.isGroup ? c.groupId == conv.groupId : c.id == conv.id),
        );

        if (existingIndex >= 0) {
          _allConversations[existingIndex] = conv;
        } else {
          _allConversations.insert(0, conv);
        }

        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Chat request added to conversations');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling chat_request: $e');
      }
    }
  }

  //  Handle chat request accepted
  void _handleChatRequestAccepted(dynamic payload) {
    try {
      final requestId =
          payload['chat_request_id']?.toString() ?? payload['id']?.toString();

      if (requestId == null) {
        if (kDebugMode) {
          print('No request ID in accepted payload');
        }
        return;
      }

      bool changed = false;

      _allConversations = _allConversations.map((c) {
        if (c.chatRequestId == requestId) {
          changed = true;
          return c.copyWith(chatRequestStatus: 'accepted');
        }
        return c;
      }).toList();

      _unreadConversations = _unreadConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'accepted');
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Chat request marked as accepted');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling chat_request_accepted: $e');
      }
    }
  }

  //   Handle chat request declined
  void _handleChatRequestDeclined(dynamic payload) {
    try {
      final requestId =
          payload['chat_request_id']?.toString() ?? payload['id']?.toString();

      if (requestId == null) {
        if (kDebugMode) {
          print('No request ID in declined payload');
        }
        return;
      }

      bool changed = false;

      _allConversations = _allConversations.map((c) {
        if (c.chatRequestId == requestId) {
          changed = true;
          return c.copyWith(chatRequestStatus: 'declined');
        }
        return c;
      }).toList();

      _unreadConversations = _unreadConversations.map((c) {
        if (c.chatRequestId == requestId) {
          return c.copyWith(chatRequestStatus: 'declined');
        }
        return c;
      }).toList();

      if (changed) {
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Chat request marked as declined');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling chat_request_declined: $e');
      }
    }
  }

  // HELPER: Extract conversation from various payload shapes
  Conversation? _extractConversationFromPayload(dynamic payload) {
    try {
      if (payload is! Map<String, dynamic>) return null;

      final conv = payload['conversation'] ?? payload;
      if (conv is! Map<String, dynamic>) return null;

      return Conversation.fromJson(conv);
    } catch (e) {
      if (kDebugMode) {
        print('Error extracting conversation: $e');
      }
      return null;
    }
  }

  /* ---------------------------------------------------------------------
                GROUP 1: MESSAGE HANDLERS
--------------------------------------------------------------------- */

  void _handleNewMessage(dynamic payload) {
    // Extract message
    final msg = _extractMessageMap(payload);
    if (msg == null) {
      if (kDebugMode) {
        print('Failed to extract message');
      }
      return;
    }

    // Create unique message ID candidate (may be null-like)
    final messageId = msg['_id']?.toString();

    bool appearsDuplicateAndStale() {
      if (messageId == null || messageId.isEmpty) return false;
      // Look through conversations' message caches if available.
      for (final conv in [..._allConversations, ..._unreadConversations]) {
        if (conv.messages == null) continue;
        Message? found;
        for (final m in conv.messages!) {
          if (m.id == messageId) {
            found = m;
            break;
          }
        }
        if (found != null) {
          // If incoming created_at is not newer than existing message, treat as stale
          final incomingTs = _parseTimestamp(msg);
          final existingTs = found.timestamp;
          final incomingText = _formatLastMessage(msg);
          final existingText = found.content;
          if (!incomingTs.isAfter(existingTs) && incomingText == existingText) {
            return true;
          }
        }
      }
      return false;
    }

    if (appearsDuplicateAndStale()) {
      if (kDebugMode) {
        print('Skipping stale duplicate message: ${messageId ?? '<no-id>'}');
      }
      return;
    }

    final isGroup = _isGroupMessage(msg);
    if (kDebugMode) {
      print('Processing ${isGroup ? "group" : "direct"} message: $messageId');
    }
    _updateConversationWithMessage(msg);
  }

  void _handleMessagesRead(dynamic payload) {
    try {
      if (payload == null) return;

      // Extract all possible field names
      final readCount =
          int.tryParse(
            '${payload['read_count'] ?? payload['readCount'] ?? 0}',
          ) ??
          0;

      final groupId =
          (payload['group_id'] ??
                  payload['groupId'] ??
                  payload['channel'] ??
                  payload['conversation_id'] ??
                  payload['conversationId'] ??
                  payload['to_id'] ??
                  payload['toId'])
              ?.toString();

      final otherUserId =
          (payload['other_user_id'] ??
                  payload['otherUserId'] ??
                  payload['otherUser'] ??
                  payload['other_user'] ??
                  payload['other'])
              ?.toString();

      final byUser =
          (payload['by'] ??
                  payload['by_id'] ??
                  payload['user_id'] ??
                  payload['actor'] ??
                  payload['userId'])
              ?.toString();

      final performedByMe =
          byUser != null && byUser == _currentUserId.toString();
      String? convKey = groupId ?? otherUserId;

      // Try to extract from nested conversation
      if (convKey == null || convKey.isEmpty) {
        try {
          final conv = payload['conversation'] ?? payload;
          if (conv is Map<String, dynamic>) {
            convKey =
                (conv['group_id'] ??
                        conv['groupId'] ??
                        conv['to_id'] ??
                        conv['toId'] ??
                        conv['from_id'] ??
                        conv['fromId'] ??
                        conv['sender_id'] ??
                        conv['sender'])
                    ?.toString();
          }
        } catch (_) {}
      }

      // Nothing actionable
      if ((readCount <= 0) &&
          !performedByMe &&
          (convKey == null || convKey.isEmpty)) {
        if (kDebugMode) {
          print('messages_read: No actionable data');
        }
        return;
      }

      bool changed = false;

      // Helper to match conversation
      bool matchesConv(Conversation conv) {
        final convGroupId = conv.groupId ?? conv.id;
        if (convKey != null && convKey.isNotEmpty && convGroupId == convKey) {
          return true;
        }
        if (otherUserId != null &&
            otherUserId.isNotEmpty &&
            conv.id == otherUserId) {
          return true;
        }
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
          if (kDebugMode) {
            print('messages_read applied (by me): convKey=$convKey');
          }
        } else {
          if (kDebugMode) {
            print('messages_read by me processed but no match found');
          }
        }
        return;
      }

      // Decrement unread count
      if (readCount > 0) {
        _allConversations = _allConversations.map((conv) {
          if (matchesConv(conv)) {
            final nextUnread = (conv.unreadCount - readCount).clamp(
              0,
              conv.unreadCount,
            );
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
                final newUnread = (conv.unreadCount - readCount).clamp(
                  0,
                  conv.unreadCount,
                );
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
          if (kDebugMode) {
            print(
              'messages_read applied: convKey=$convKey, readCount=$readCount',
            );
          }
        } else {
          if (kDebugMode) {
            print('messages_read handled but no match found');
          }
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        print('Exception in _handleMessagesRead: $e\n$st');
      }
    }
  }

  /* ---------------------------------------------------------------------
                GROUP 2: GROUP MANAGEMENT HANDLERS
   --------------------------------------------------------------------- */

  void _handleGroupCreated(Map<String, dynamic>? data) {
    if (data == null) return;

    try {
      final createdGroup =
          data['created_group'] ?? data['group'] ?? data['groupData'];

      if (createdGroup != null && createdGroup is Map<String, dynamic>) {
        final groupId = createdGroup['id']?.toString();
        final groupName = createdGroup['name']?.toString() ?? 'New Group';

        //  Handle photo URL construction
        String? photoUrl = createdGroup['photo_url']?.toString();
        if (photoUrl != null &&
            photoUrl.isNotEmpty &&
            !photoUrl.startsWith('http')) {
          photoUrl = '${ApiUrls.baseUrl}/$photoUrl';
        }

        // Get system message
        final systemMessage = data['systemMessage'] ?? data['notification'];
        final lastMessageText =
            systemMessage?['message']?.toString() ??
            systemMessage?['body']?.toString() ??
            'Group created';

        // Check if group already exists
        final existingIndex = _allConversations.indexWhere(
          (c) => c.isGroup && c.groupId == groupId,
        );

        if (existingIndex >= 0) {
          // Update existing
          _allConversations[existingIndex] = _allConversations[existingIndex]
              .copyWith(
                title: groupName,
                lastMessage: lastMessageText,
                timestamp: DateTime.now(),
                avatarUrl: photoUrl,
              );
        } else {
          // Create new conversation
          final newConv = Conversation(
            id: groupId ?? '',
            groupId: groupId,
            title: groupName,
            email: '',
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
            unreadCount: 0,
            avatarUrl: photoUrl,
            isGroup: true,
            isUnread: false,
            isOnline: false,
            isActive: false,
          );

          // Insert at the beginning of the list
          _allConversations.insert(0, newConv);
        }

        // Always emit state to update UI
        _emitUnifiedLoadedState();
        if (kDebugMode) {
          print('Group created/updated: $groupName with photo: $photoUrl');
        }
        return;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in group_created: $e');
      }
    }
  }

  void _handleGroupUpdated(Map<String, dynamic>? data) {
    if (data == null) return;

    // Extract group_id from root level
    final gid = data['group_id']?.toString();

    if (gid == null || gid.isEmpty) {
      if (kDebugMode) {
        print('No group_id in group_updated payload');
      }
      return;
    }

    // Extract updated_group data - it has a complex nested structure
    final updatedGroup = data['updated_group'];

    if (updatedGroup == null) {
      if (kDebugMode) {
        print('No updated_group data');
      }
      return;
    }

    // The actual group data is inside _doc
    final groupData = updatedGroup['_doc'] as Map<String, dynamic>?;

    if (groupData == null) {
      if (kDebugMode) {
        print('No _doc in updated_group');
      }
      return;
    }

    //Check for photo_url at multiple levels
    // Priority: root level photo_url > _doc photo_url
    String? photoUrl;

    // Check root level first (sometimes socket sends full URL here)
    if (updatedGroup['photo_url'] != null &&
        updatedGroup['photo_url'].toString().isNotEmpty) {
      photoUrl = updatedGroup['photo_url'].toString();
    }

    // Fallback to _doc photo_url
    if (photoUrl == null &&
        groupData['photo_url'] != null &&
        groupData['photo_url'].toString().isNotEmpty) {
      photoUrl = groupData['photo_url'].toString();
    }

    // If photo_url is relative path, construct full URL
    if (photoUrl != null && !photoUrl.startsWith('http')) {
      photoUrl = '${ApiUrls.baseUrl}/$photoUrl/$photoUrl';
    }

    if (kDebugMode) {
      print('Extracted group data: name=${groupData['name']}, photo=$photoUrl');
    }

    // Extract system message for last message update
    final systemMessage = data['systemMessage'] ?? data['notification'];
    final lastMessageText =
        systemMessage?['message']?.toString() ??
        systemMessage?['body']?.toString();

    bool changed = false;

    // Update in all conversations list
    _allConversations = _allConversations.map((c) {
      if (c.isGroup && c.groupId == gid) {
        changed = true;

        final newName = groupData['name']?.toString() ?? c.title;
        // Use the properly constructed photoUrl
        final newPhoto = photoUrl ?? c.avatarUrl;

        if (kDebugMode) {
          print('Updating conversation: $newName with photo: $newPhoto');
        }

        // Update last message if available
        if (lastMessageText != null && lastMessageText.isNotEmpty) {
          return c.copyWith(
            title: newName,
            avatarUrl: newPhoto,
            lastMessage: lastMessageText,
            timestamp: DateTime.now(),
          );
        } else {
          return c.copyWith(
            title: newName,
            avatarUrl: newPhoto,
            timestamp: DateTime.now(),
          );
        }
      }
      return c;
    }).toList();

    // Re-sort to put updated group at top
    if (changed) {
      _allConversations.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    // Update in unread conversations list
    _unreadConversations = _unreadConversations.map((c) {
      if (c.isGroup && c.groupId == gid) {
        final newName = groupData['name']?.toString() ?? c.title;
        final newPhoto = photoUrl ?? c.avatarUrl;

        // Update last message in unread list too
        if (lastMessageText != null && lastMessageText.isNotEmpty) {
          return c.copyWith(
            title: newName,
            avatarUrl: newPhoto,
            lastMessage: lastMessageText,
          );
        } else {
          return c.copyWith(title: newName, avatarUrl: newPhoto);
        }
      }
      return c;
    }).toList();

    if (changed) {
      _emitUnifiedLoadedState();
      if (kDebugMode) {
        print(
          'Group updated successfully: ${groupData['name']} with photo: $photoUrl',
        );
      }
    } else {
      if (kDebugMode) {
        print('Group $gid not found in local conversations');
      }
      // Optionally refresh to get the group
      loadConversations(refresh: true);
    }
  }

  void _handleGroupDeleted(String? groupId) {
    if (groupId == null || groupId.isEmpty) {
      if (kDebugMode) {
        print('group_deleted: No group ID');
      }
      return;
    }

    final beforeCount = _allConversations.length;

    _allConversations = _allConversations
        .where((c) => !(c.isGroup && c.groupId == groupId))
        .toList();

    _unreadConversations = _unreadConversations
        .where((c) => !(c.isGroup && c.groupId == groupId))
        .toList();

    if (_allConversations.length != beforeCount) {
      _emitUnifiedLoadedState();
      if (kDebugMode) {
        print('Removed conversations for deleted group: $groupId');
      }
    }
  }

  /* ---------------------------------------------------------------------
                  GROUP 3: CONVERSATION HANDLERS
  --------------------------------------------------------------------- */

  void _handleConversationEvent(dynamic payload) {
    try {
      if (payload == null) return;

      final conv = (payload is Map<String, dynamic>)
          ? (payload['conversation'] ?? payload)
          : null;

      if (conv == null || conv is! Map<String, dynamic>) {
        if (kDebugMode) {
          print('conversation_event: No usable data, refreshing');
        }
        loadConversations(refresh: true);
        return;
      }

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
            (conv['group'] != null
                ? 'App\\Models\\Group'
                : 'App\\Models\\Conversation'),
        'group_id':
            conv['group_id'] ??
            conv['groupId'] ??
            (conv['group'] != null ? conv['group']['id'] : null),
        'message': conv['message'] ?? conv['body'] ?? conv['title'] ?? '',
        'message_type': conv['message_type'] ?? conv['type'] ?? 0,
        'created_at':
            conv['created_at'] ??
            conv['createdAt'] ??
            DateTime.now().toIso8601String(),
        'sender': conv['sender'] ?? conv['user'] ?? conv['from_user'],
        'group': conv['group'] ?? conv['created_group'],
      };

      _handleNewMessage({'conversation': msg});
    } catch (e) {
      if (kDebugMode) {
        print('Error in conversation_event: $e');
      }
      loadConversations(refresh: true);
    }
  }

  /* ---------------------------------------------------------------------
                           MESSAGE EXTRACTION
   --------------------------------------------------------------------- */

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
        'group_name': c['group'] != null
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
      if (kDebugMode) {
        print('extractMessage error: $e');
      }
      return null;
    }
  }

  /* ---------------------------------------------------------------------
                        CONVERSATION UPDATE
   --------------------------------------------------------------------- */

  void _updateConversationWithMessage(Map<String, dynamic> msg) {
    final convId = _conversationIdFromMessage(msg);
    final isGroup = _isGroupMessage(msg);
    final lastText = _formatLastMessage(msg);
    final ts = _parseTimestamp(msg);
    final own = _isOwnMessage(msg);

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
        if (kDebugMode) {
          print(
            'Incoming message ts <= existing ts, skipping update for conv $convId',
          );
        }
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
      if (kDebugMode) {
        print('Updated conversation lists - Last message: $lastText');
      }
      _emitUnifiedLoadedState();
    } else {
      if (kDebugMode) {
        print('Conversation not found, creating new');
      }
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
      isOnline: false,
      isActive: false,
    );

    _allConversations = [newConv, ..._allConversations];
    if (!_isOwnMessage(msg)) {
      _unreadConversations = [newConv, ..._unreadConversations];
    }

    if (kDebugMode) {
      print('Created new conversation (from socket)');
    }
    _emitUnifiedLoadedState();

    if (!isGroup && _isOwnMessage(msg)) {
      _updateConversationTitleFromUserId(convId);
    }
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

      final users = resp.data!.contacts;
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
      if (kDebugMode) {
        print('Failed to update conversation title from user id: $e');
      }
    }
  }

  /* ---------------------------------------------------------------------
                           HELPERS
 --------------------------------------------------------------------- */

  bool _isOwnMessage(Map<String, dynamic> msg) {
    final from = msg['from_id']?.toString();
    final currentId = _currentUserId.toString();
    final isOwn = from == currentId;
    return isOwn;
  }

  String _formatLastMessage(Map<String, dynamic> msg) {
    final txt = msg['message']?.toString() ?? '';
    if (txt.contains('<img')) return 'Photo';
    if (txt.contains('<video')) return 'Video';
    if (txt.contains('<audio')) return 'Audio';
    if (txt.contains('<a href')) return 'File';

    final cleaned = txt.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return cleaned;
  }

  DateTime _parseTimestamp(Map<String, dynamic> msg) {
    final raw = msg['created_at']?.toString();
    return raw != null
        ? DateTime.tryParse(raw) ?? DateTime.now()
        : DateTime.now();
  }

  /* ---------------------------------------------------------------------
                           PUBLIC API
   --------------------------------------------------------------------- */

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

  /* ---------------------------------------------------------------------
                           CONVERSATION ID
   --------------------------------------------------------------------- */

  String _conversationIdFromMessage(Map<String, dynamic> msg) {
    final groupId = msg['group_id']?.toString();
    final toType = msg['to_type']?.toString();
    final toId = msg['to_id']?.toString();

    // Priority 1: Group ID
    if (groupId != null && groupId.isNotEmpty && groupId != '0') {
      return groupId;
    }

    // Priority 2: to_type contains Group
    if (toType?.contains('Group') == true) {
      return toId ?? 'unknown';
    }

    // Priority 3: to_id contains UUID format (groups use UUIDs)
    if (toId != null && toId.contains('-')) {
      return toId;
    }

    // Priority 4: Direct message - use other user's ID
    final own = _isOwnMessage(msg);
    final other = own ? toId : msg['from_id']?.toString();

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
