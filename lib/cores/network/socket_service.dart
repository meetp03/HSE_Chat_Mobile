// lib/cores/network/socket_service.dart
import 'package:flutter/foundation.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/feature/home/model/message_model.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
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
        'https://hecdev-apichat.sonomainfotech.in',
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .setExtraHeaders({'Authorization': 'Bearer $token'})
            .setAuth({
          'token': token,
        })
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
  final Map<String, List<Function(dynamic)>> _userEventConversationListeners = {};

  // Buffer pending 'new_message' events per conversation so that when a
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
              print('🧾 Buffering new_message for key: $key (group:$groupId to:$toId from:$fromId)');
            }
            if (key != null) {
              final list = _pendingMessages.putIfAbsent(key, () => []);
              list.add(data);
              // keep only last 50 messages per conversation
              if (list.length > 50) list.removeAt(0);
              if (kDebugMode) {
                print('🧾 Pending buffer size for $key: ${list.length}');
              }
            }
          }
        }
      }
    } catch (_) {
      // ignore buffering errors
    }

    if (_eventListeners.containsKey(event)) {
      for (var listener in _eventListeners[event]!) {
        try {
          listener(data);
        } catch (e) {
          if (kDebugMode) print('⚠️ Event listener threw: $e');
        }
      }
    }
  }

  void onNewMessage(String conversationId, bool isGroup, int currentUserId, Function(Message) callback) {
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
          print('🔍 wrapper check for convKey=$conversationId: toId=$toId fromId=$fromId toType=$toType -> isForChat=$isForChat');
        }

        if (isForChat) {
          callback(Message.fromJson(conv, currentUserId));
        }
      } catch (_) {
        // Swallow parsing errors in socket callbacks to avoid breaking the event loop
      }
    }

    on('UserEvent', wrapper);
    _userEventConversationListeners.putIfAbsent(conversationId, () => []).add(wrapper);

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
    } catch (_) {
      // ignore replay errors
    }
  }

  void onTyping(String otherUserId, Function(bool) callback) {
    on('typing', (data) {
      if (data['conversationId'] == otherUserId && data['isTyping'] != null) {
        callback(data['isTyping']);
      }
    });
  }

  /// Remove per-conversation UserEvent listeners (registered via [onNewMessage])
  void removeChatListener(String conversationId) {
    final wrappers = _userEventConversationListeners.remove(conversationId);
    if (wrappers == null) return;
    for (var w in wrappers) {
      try {
        off('UserEvent', w);
      } catch (_) {
        // ignore
      }
    }
  }

  void cleanupChatListeners(String otherUserId) {
    // Only remove listeners related to this particular conversation to avoid
    // tearing down global UserEvent listeners used elsewhere.
    removeChatListener(otherUserId);

    // typing and message_read listeners are chat-scoped; safe to remove all
    offAll('typing');
    offAll('message_read');
  }

  String get _currentUserId {
    final userId = SharedPreferencesHelper.getCurrentUserId();
    return userId.toString();
  }
// In SocketService.dart - Add method to send group events
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
      print('👥 Emitted GroupEvent: $eventData');
    }
  }
  void _setupSocketListeners() {
    _socket?.onConnect((_) {
      _isConnected = true;
      if (kDebugMode) {
        print('✅ Socket connected');
      }
      onConnectCallback?.call(() {});
      joinUserRoom(_currentUserId);
    });

    _socket?.onDisconnect((_) {
      _isConnected = false;
      if (kDebugMode) {
        print('❌ Socket disconnected');
      }
      onDisconnectCallback?.call(() {});
    });

    // Listen to UserEvent only
    _socket?.on('UserEvent', (data) {
      if (kDebugMode) {
        print('📨 UserEvent received: $data');
      }
      _notifyMessageListeners({'event': 'UserEvent', 'data': data});
    });

    _socket?.on('GroupEvent', (data) {
      if (kDebugMode) {
        print('📨 GroupEvent received: $data');
      }
      _notifyMessageListeners({'event': 'GroupEvent', 'data': data});
    });

    // Some servers emit a top-level 'new_message' event in addition to or
    // instead of embedding it in 'UserEvent'. Forward those events into the
    // same UserEvent pipeline so onNewMessage wrappers get them.
    _socket?.on('new_message', (data) {
      if (kDebugMode) print('📨 new_message received (forwarded to UserEvent): $data');
      try {
        // Wrap the payload in a UserEvent-like shape if necessary
        final shaped = (data is Map<String, dynamic> && data.containsKey('conversation'))
            ? {'action': 'new_message', 'conversation': data['conversation'], 'user_id': data['user_id'], 'sender_id': data['sender_id']}
            : data;
        // Forward to the UserEvent pipeline
        _notifyEventListeners('UserEvent', shaped);
        // Also notify general message listeners
        _notifyMessageListeners({'event': 'new_message', 'data': data});
      } catch (e) {
        if (kDebugMode) print('⚠️ Failed to forward new_message: $e');
      }
    });
    // NEW: Listen for block/unblock events
    _socket?.on('user.block_unblock', (data) {
      if (kDebugMode) {
        print('🔒 Block/Unblock event received: $data');
      }
      _notifyMessageListeners({'event': 'user.block_unblock', 'data': data});
    });
    _socket?.on('conversation_updated', (data) {
      if (kDebugMode) {
        print('🔄 conversation_updated received: $data');
      }
      _notifyMessageListeners({'event': 'conversation_updated', 'data': data});
    });

    // Debug: Listen to ALL events
    _socket?.onAny((event, data) {
      print('🔍 [ALL EVENTS] Socket event: "$event" with data: $data');
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

  void dispose() {
    disconnect();
    _messageListeners.clear();
    _socket?.dispose();
  }
}