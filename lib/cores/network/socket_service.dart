import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/home/model/message_model.dart';
import 'package:hec_chat/feature/notification/notification_repository.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../constants/api_urls.dart';

class SocketService with WidgetsBindingObserver {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  final List<Function(dynamic)> _messageListeners = [];

  // Socket event callbacks
  Function(void Function())? onConnectCallback;
  Function(void Function())? onDisconnectCallback;
  Function(void Function(String))? onErrorCallback;

  void initializeSocket(String token) {
    try {
      _socket = IO.io(
        ApiUrls.baseUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .setAuth({'token': token})
            .build(),
      );

      if (kDebugMode) {
        print('Initializing socket with token: $token');
      }
      _setupSocketListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Socket initialization error: $e');
      }
    }
  }

  final Map<String, List<Function(dynamic)>> _eventListeners = {};

  // Store per-conversation wrappers for UserEvent so we can remove them individually
  final Map<String, List<Function(dynamic)>> _userEventConversationListeners =
      {};

  // conversation-specific listener registers late (e.g., Chat screen opens
  // after a socket event), we can replay recent messages to it.
  final Map<String, List<dynamic>> _pendingMessages = {};

  // Generic event listener registration
  void on(String event, Function(dynamic) callback) {
    if (!_eventListeners.containsKey(event)) {
      _eventListeners[event] = [];
      // Setup socket listener for this event type
      _socket?.on(event, (data) {
        _notifyEventListeners(event, data);
      });
    }
    _eventListeners[event]!.add(callback);
  }

  void off(String event, Function(dynamic) callback) {
    if (_eventListeners.containsKey(event)) {
      _eventListeners[event]!.remove(callback);
      if (_eventListeners[event]!.isEmpty) {
        _eventListeners.remove(event);
        _socket?.off(event);
      }
    }
  }

  void offAll(String event) {
    _eventListeners.remove(event);
    _socket?.off(event);
  }

  void _notifyEventListeners(String event, dynamic data) {
    // Buffer new_message events for UserEvent so late listeners can be replayed
    try {
      if (event == 'UserEvent' && data is Map<String, dynamic>) {
        final action = data['action'] ?? data['type'];
        if (action == 'new_message') {
          final conv = data['conversation'] ?? data;
          if (conv is Map<String, dynamic>) {
            // Determine a conversation key: prefer group_id, else to_id/from_id
            final groupId = conv['group_id']?.toString();
            final toId = conv['to_id']?.toString();
            final fromId = conv['from_id']?.toString();
            final key = groupId ?? toId ?? fromId;
            if (kDebugMode) {
              print(
                'Buffering new_message for key: $key (group:$groupId to:$toId from:$fromId)',
              );
            }
            if (key != null) {
              final list = _pendingMessages.putIfAbsent(key, () => []);
              list.add(data);
              // keep only last 50 messages per conversation
              if (list.length > 50) list.removeAt(0);
              if (kDebugMode) {
                print('Pending buffer size for $key: ${list.length}');
              }
            }
          }
        }
      }
    } catch (_) {}

    if (_eventListeners.containsKey(event)) {
      for (var listener in _eventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          if (kDebugMode) print('Event listener threw: $e');
        }
      }
    }
  }

  void onNewMessage(
    String conversationId,
    bool isGroup,
    int currentUserId,
    Function(Message) callback,
  ) {
    // Register a wrapper so we can remove this listener later for a specific conversation
    void wrapper(dynamic data) {
      try {
        if (data == null) return;
        final action = data['action'] ?? data['type'];
        if (action != 'new_message') return;

        final conv = data['conversation'];
        if (conv == null) return;

        final toId = conv['to_id']?.toString();
        final toType = conv['to_type']?.toString();
        final fromId = conv['from_id']?.toString();

        final isForChat = isGroup
            ? (toId == conversationId && toType?.contains('Group') == true)
            : (fromId == conversationId || toId == conversationId);

        if (kDebugMode) {
          print(
            'wrapper check for convKey=$conversationId: toId=$toId fromId=$fromId toType=$toType -> isForChat=$isForChat',
          );
        }

        if (isForChat) {
          callback(Message.fromJson(conv, currentUserId));
        }
      } catch (_) {}
    }

    on('UserEvent', wrapper);
    _userEventConversationListeners
        .putIfAbsent(conversationId, () => [])
        .add(wrapper);

    // Replay any pending buffered messages for this conversation immediately
    try {
      final pending = _pendingMessages[conversationId];
      if (pending != null && pending.isNotEmpty) {
        for (var p in List<dynamic>.from(pending)) {
          try {
            wrapper(p);
          } catch (_) {}
        }
        // Optionally clear buffer after replaying
        _pendingMessages.remove(conversationId);
      }
    } catch (_) {}
  }

  void onTyping(String otherUserId, Function(bool) callback) {
    on('typing', (data) {
      if (data['conversationId'] == otherUserId && data['isTyping'] != null) {
        callback(data['isTyping']);
      }
    });
  }

  //Remove per-conversation UserEvent listeners (registered via [onNewMessage])
  void removeChatListener(String conversationId) {
    final wrappers = _userEventConversationListeners.remove(conversationId);
    if (wrappers == null) return;
    for (var w in wrappers) {
      try {
        off('UserEvent', w);
      } catch (_) {}
    }
  }

  void cleanupChatListeners(String otherUserId) {
    // Only remove listeners related to this particular conversation to avoid
    removeChatListener(otherUserId);

    // typing and message_read listeners are chat-scoped; safe to remove all
    offAll('typing');
    offAll('message_read');
  }

  String get _currentUserId {
    final userId = SharedPreferencesHelper.getCurrentUserId();
    return userId.toString();
  }

  void sendGroupEvent({
    required String action,
    required String groupId,
    Map<String, dynamic>? groupData,
  }) {
    final eventData = {
      'action': action,
      'group_id': groupId,
      'group': groupData,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _socket?.emit('GroupEvent', eventData);

    if (kDebugMode) {
      print('Emitted GroupEvent: $eventData');
    }
  }

  // Notification badge fields (merged from NotificationBadgeService)
  final ValueNotifier<int> unseenCount = ValueNotifier<int>(0);
  String? apiBaseUrl;
  String? authToken;
  int? loggedInUserId;
  String? selectedConversationId;
  String? selectedConversationType;
  Timer? _resyncTimer;
  final Set<String> _processedNotificationIds = <String>{};
  DateTime? _lastUnseenFetch;
  bool _isFetchingUnseen = false;

  // Initialize notification badge config. Call once after creating SocketService.
  void initNotificationBadge({
    required String apiBase,
    String? token,
    int? userId,
  }) {
    apiBaseUrl = apiBase;
    authToken = token;
    loggedInUserId = userId;

    // Register the observer to listen to app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
  }

  // Optionally set currently open conversation to avoid incrementing badge for active convo
  void setSelectedConversation({String? id, String? type}) {
    selectedConversationId = id;
    selectedConversationType = type;
  }

  bool _isOwnAction(Map<String, dynamic> data) {
    if (loggedInUserId == null) return false;
    final fromId =
        data['from_id'] ??
        data['added_by'] ??
        data['removed_by'] ??
        data['creator_id'] ??
        data['left_user_id'] ??
        data['by_user_id'];
    if (fromId == null) return false;
    try {
      return int.tryParse(fromId.toString()) == loggedInUserId;
    } catch (_) {
      return false;
    }
  }

  bool _isForSelectedConversation(Map<String, dynamic> data) {
    if (selectedConversationId == null) return false;

    final groupId =
        data['group_id'] ??
        data['groupId'] ??
        data['channel'] ??
        data['channel_id'];
    if (groupId != null &&
        selectedConversationType == 'group' &&
        groupId.toString() == selectedConversationId) {
      return true;
    }

    final convo = data['conversation'] ?? data;
    final dynamic convoTo = (convo is Map)
        ? (convo['to_id'] ?? convo['to'])
        : null;
    final dynamic convoFrom = (convo is Map)
        ? (convo['from_id'] ?? convo['from'])
        : null;
    final toId = convoTo ?? data['to_id'] ?? data['to'];
    final fromId = convoFrom ?? data['from_id'] ?? data['from'];
    if (selectedConversationType != 'group') {
      if (toId != null && toId.toString() == selectedConversationId)
        return true;
      if (fromId != null && fromId.toString() == selectedConversationId)
        return true;
    }

    return false;
  }

  void _incrementFromSocket(dynamic data, {String? id}) {
    if (id != null) _processedNotificationIds.add(id);
    final current = unseenCount.value;
    unseenCount.value = current + 1;
    if (kDebugMode)
      print('SocketService: unseenCount -> ${unseenCount.value} (from socket)');
  }

  // Refresh unseen count from the API (debounced). Use [force] to bypass debounce.
  Future<void> refreshUnseenCount({bool force = false}) async {
    // Simple debounce to avoid duplicate rapid API calls
    final now = DateTime.now();
    if (!force && _lastUnseenFetch != null) {
      final diff = now.difference(_lastUnseenFetch!);
      if (diff < const Duration(seconds: 2)) {
        if (kDebugMode)
          print('SocketService: skipping unseen fetch (debounced)');
        return;
      }
    }

    if (_isFetchingUnseen) {
      if (kDebugMode) print('SocketService: unseen fetch already in progress');
      return;
    }

    _isFetchingUnseen = true;
    try {
      final repo = NotificationRepository();
      final count = await repo.fetchUnseenCount();
      if (count != null) {
        unseenCount.value = count;
        if (kDebugMode)
          print(
            'SocketService: fetched unseenCount=$count (from API - authoritative)',
          );
      } else {
        if (kDebugMode)
          print('SocketService: API returned null for unseen count');
      }
      _lastUnseenFetch = DateTime.now();
    } catch (e) {
      if (kDebugMode) print('SocketService: failed to fetch unseen count: $e');
    } finally {
      _isFetchingUnseen = false;
    }
  }

  void resetUnseenCount() {
    unseenCount.value = 0;
    if (kDebugMode) print('SocketService: unseenCount reset to 0');
  }

  void _handleBadgeEvent(dynamic raw) {
    try {
      final Map<String, dynamic> data = (raw is String)
          ? json.decode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);
      final actionRaw = data['action'] ?? data['type'] ?? '';
      final action = actionRaw.toString().toLowerCase();

      // Handle DECREMENT for messages_read event
      if (action == 'messages_read') {
        final readCount =
            int.tryParse('${data['read_count'] ?? data['readCount'] ?? 1}') ??
            1;
        final byUser = (data['by'] ?? data['by_id'] ?? data['user_id'])
            ?.toString();
        final performedByMe =
            byUser != null && byUser == loggedInUserId.toString();

        // Only decrement if performed by current user
        if (performedByMe) {
          final current = unseenCount.value;
          unseenCount.value = (current - readCount).clamp(0, current);
          if (kDebugMode)
            print(
              'unseenCount -> ${unseenCount.value} (decremented by $readCount)',
            );
        }
        return;
      }

      const incrementActions = <String>{
        'group_created',
        'members_added',
        'member_removed',
        'member_left',
        'chat_request',
        'chat_request_accepted',
        'chat_request_declined',
        'admin_promoted',
        'admin_dismissed',
        'group_updated',
        'new_message',
        'message_updated',
      };

      dynamic nestedNotification =
          data['notification'] ??
          data['systemMessage'] ??
          data['created_group'] ??
          data['conversation'];

      final nestedType = (nestedNotification is Map)
          ? (nestedNotification['type'] ??
                nestedNotification['message_type'] ??
                nestedNotification['title'])
          : null;

      final nestedId = (nestedNotification is Map)
          ? (nestedNotification['id'] ??
                nestedNotification['_id'] ??
                nestedNotification['system_message_id'])
          : null;

      final nestedTypeStr = nestedType?.toString().toLowerCase();
      final shouldIncrementBasedOnNestedType =
          nestedTypeStr != null &&
          (nestedTypeStr.contains('group_member') ||
              nestedTypeStr.contains('group_created') ||
              nestedTypeStr.contains('member_added') ||
              nestedTypeStr.contains('member_removed') ||
              nestedTypeStr.contains('member_left'));

      final notifIdStr = nestedId?.toString();

      //  Check for duplicate
      if (notifIdStr != null &&
          _processedNotificationIds.contains(notifIdStr)) {
        if (kDebugMode) print('Skipping duplicate notification: $notifIdStr');
        return;
      }

      if (incrementActions.contains(action) ||
          shouldIncrementBasedOnNestedType) {
        // Don't increment if it's user's own action
        if (_isOwnAction(data)) {
          if (kDebugMode) print('Skipping own action: $action');
          return;
        }

        // Don't increment if notification is for currently active conversation
        if (_isForSelectedConversation(data)) {
          if (kDebugMode)
            print('Skipping notification for active conversation');
          return;
        }

        _incrementFromSocket(data, id: notifIdStr);
      }
    } catch (e) {
      if (kDebugMode) print('Error in _handleBadgeEvent: $e');
      // Best-effort: if parsing fails, try to increment once
      try {
        _incrementFromSocket(raw);
      } catch (_) {}
    }
  }

  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      _isConnected = true;
      if (kDebugMode) {
        print('Socket connected');
      }
      onConnectCallback?.call(() {});
      joinUserRoom(_currentUserId);
      // Resync authoritative unseen notifications count when socket connects
      try {
        refreshUnseenCount();
      } catch (_) {}
    });

    _socket?.onDisconnect((_) {
      _isConnected = false;
      if (kDebugMode) {
        print('Socket disconnected');
      }
      onDisconnectCallback?.call(() {});
    });

    // Listen to UserEvent only
    _socket?.on('UserEvent', (data) {
      if (kDebugMode) {
        print('UserEvent received: $data');
      }
      // Update badge logic
      _handleBadgeEvent(data);
      _notifyMessageListeners({'event': 'UserEvent', 'data': data});
    });

    _socket?.on('GroupEvent', (data) {
      if (kDebugMode) {
        print('GroupEvent received: $data');
      }
      _handleBadgeEvent(data);
      _notifyMessageListeners({'event': 'GroupEvent', 'data': data});
    });
    _socket?.on('user.block_unblock', (data) {
      if (kDebugMode) print('BLOCK EVENT: $data');
      _notifyEventListeners('user.block_unblock', data);
      _notifyMessageListeners({'event': 'user.block_unblock', 'data': data});
    });

    // Optional: Support old events
    _socket?.on(
      'block_user',
      (data) => _notifyEventListeners('user.block_unblock', {
        'blockedBy': data['blocked_by'],
        'blockedTo': data['blocked_to'],
        'isBlocked': true,
      }),
    );

    _socket?.on(
      'unblock_user',
      (data) => _notifyEventListeners('user.block_unblock', {
        'blockedBy': data['blocked_by'],
        'blockedTo': data['blocked_to'],
        'isBlocked': false,
      }),
    );
    // Some servers emit a top-level 'new_message' event in addition to or
    // instead of embedding it in 'UserEvent'. Forward those events into the
    // same UserEvent pipeline so onNewMessage wrappers get them.
    _socket?.on('new_message', (data) {
      if (kDebugMode)
        print('new_message received (forwarded to UserEvent): $data');
      try {
        final shaped =
            (data is Map<String, dynamic> && data.containsKey('conversation'))
            ? {
                'action': 'new_message',
                'conversation': data['conversation'],
                'user_id': data['user_id'],
                'sender_id': data['sender_id'],
              }
            : data;
        // Forward to the UserEvent pipeline
        _notifyEventListeners('UserEvent', shaped);
        // Also notify general message listeners
        _notifyMessageListeners({'event': 'new_message', 'data': data});
      } catch (e) {
        if (kDebugMode) print('Failed to forward new_message: $e');
      }
    });

    // Debug: Listen to ALL events
    _socket?.onAny((event, data) {
      print('[ALL EVENTS] Socket event: "$event" with data: $data');
    });
    _socket?.on('messages_read', (data) {
      _notifyEventListeners('messages_read', data);
      // Also forward to the generic message listeners so parts of the app
      // that registered via addMessageListener receive the notification.
      _notifyMessageListeners({'event': 'messages_read', 'data': data});
    });
  }

  void requestConversations() {
    _socket?.emit('get_conversations');
  }
  // Add these inside SocketService class (near other on/off methods)

  void onBlockUnblock(Function(dynamic data) callback) {
    on('user.block_unblock', callback);
  }

  void offBlockUnblock(Function(dynamic data) callback) {
    off('user.block_unblock', callback);
  }

  void connect() {
    _socket?.connect();
  }

  void joinUserRoom(String userId) {
    _socket?.emit('join', 'user.$userId');
    if (kDebugMode) {
      print('👤 Joined user room: user.$userId');
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _isConnected = false;
  }

  void joinConversation(String conversationId) {
    _socket?.emit('join_conversation', {'conversationId': conversationId});
  }

  void leaveConversation(String conversationId) {
    _socket?.emit('leave_conversation', {'conversationId': conversationId});
  }

  void sendMessage(Map<String, dynamic> messageData) {
    _socket?.emit('send_message', messageData);
  }

  void sendTypingIndicator(String conversationId, bool isTyping) {
    _socket?.emit('typing', {
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  void markMessageAsRead(String messageId, String conversationId) {
    _socket?.emit('mark_read', {
      'messageId': messageId,
      'conversationId': conversationId,
    });
  }

  void addMessageListener(Function(dynamic) listener) {
    _messageListeners.add(listener);
  }

  void removeMessageListener(Function(dynamic) listener) {
    _messageListeners.remove(listener);
  }

  void _notifyMessageListeners(dynamic data) {
    for (var listener in _messageListeners) {
      listener(data);
    }
  }

  bool get isConnected => _isConnected;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Resync unseen count when the app is resumed (debounced)
      _resyncUnseenCount();
    }
  }

  void _resyncUnseenCount() {
    // Cancel any pending resync timer
    _resyncTimer?.cancel();
    // Debounce resyncing unseen count
    _resyncTimer = Timer(const Duration(seconds: 2), () {
      refreshUnseenCount();
    });
  }

  void dispose() {
    disconnect();
    _messageListeners.clear();
    _socket?.dispose();
    // dispose badge notifier
    try {
      unseenCount.dispose();
    } catch (_) {}
    // Unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    // Cancel any pending resync timer
    try {
      _resyncTimer?.cancel();
    } catch (_) {}
  }
}
