import 'package:hec_chat/feature/home/model/message_model.dart'  ;
import 'package:hec_chat/feature/home/model/chat_models.dart';
import '../model/conversation_model.dart' hide Message;

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
  final Map<String, int> uploadProgress;
  final bool isIBlockedThem;
  final bool isTheyBlockedMe;
  final ChatGroup? commonGroupData;
  final Conversation? groupData;


  ChatLoaded({
    required this.messages,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    required this.hasMore,
    this.isLoadingMore = false,
    this.uploadProgress = const {},
    required this.isGroup,
    this.commonGroupData,
    this.isIBlockedThem = false,
    this.isTheyBlockedMe = false,
    this.groupData,
  });

  ChatLoaded copyWith({
    List<Message>? messages,
    bool? hasMore,
    bool? isLoadingMore,
    Map<String, int>? uploadProgress,
    bool? isIBlockedThem,
    bool? isTheyBlockedMe,
    ChatGroup? commonGroupData,
    Conversation? groupData,

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
      isTheyBlockedMe: isTheyBlockedMe ?? this.isTheyBlockedMe,
      isIBlockedThem: isIBlockedThem ?? this.isIBlockedThem,
      commonGroupData: commonGroupData ?? this.commonGroupData,
      groupData: groupData ?? this.groupData,
    );
  }
}

class ChatError extends ChatState {
  final String message;
  ChatError(this.message);
}
