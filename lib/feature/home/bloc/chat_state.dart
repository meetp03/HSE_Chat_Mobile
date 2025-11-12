// chat_state.dart
import 'package:hsc_chat/feature/home/model/message_model.dart';

abstract class ChatState {}

class ChatInitial extends ChatState {}

class ChatLoading extends ChatState {}

class ChatLoaded extends ChatState {
  final List<Message> messages;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isGroup;
  final Map<String, int> uploadProgress; // percent 0-100 per temp message id

  ChatLoaded({
    required this.messages,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.hasMore,
    this.isLoadingMore = false,
    this.uploadProgress = const {},
    required this.isGroup,
  });

  ChatLoaded copyWith({
    List<Message>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    Map<String, int>? uploadProgress,
  }) {
    return ChatLoaded(
      messages: messages ?? this.messages,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserAvatar: otherUserAvatar,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      isGroup: isGroup,
    );
  }
}

class ChatError extends ChatState {
  final String message;
  ChatError(this.message);
}