import 'package:hec_chat/feature/home/model/conversation_model.dart';

abstract class ConversationState {
  const ConversationState();
}

class ConversationInitial extends ConversationState {}

// Generic error state used by either flow
class ConversationError extends ConversationState {
  final String message;
  const ConversationError(this.message);
}

/* ---------------- All Conversations states ---------------- */
class AllConversationsLoading extends ConversationState {}

class AllConversationsLoaded extends ConversationState {
  final List<Conversation> allChats;
  final List<Conversation> filteredAllChats;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentQuery;

  const AllConversationsLoaded({
    required this.allChats,
    List<Conversation>? filteredAllChats,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentQuery = '',
  }) : filteredAllChats = filteredAllChats ?? allChats;

  bool get isSearching => currentQuery.isNotEmpty;
}

class AllConversationsError extends ConversationError {
  const AllConversationsError(super.message);
}

/* ---------------- Unread Conversations states ---------------- */
class UnreadConversationsLoading extends ConversationState {}

class UnreadConversationsLoaded extends ConversationState {
  final List<Conversation> unreadChats;
  final List<Conversation> filteredUnreadChats;
  final bool unreadHasMore;
  final bool unreadIsLoadingMore;
  final String unreadCurrentQuery;

  const UnreadConversationsLoaded({
    required this.unreadChats,
    List<Conversation>? filteredUnreadChats,
    this.unreadHasMore = false,
    this.unreadIsLoadingMore = false,
    this.unreadCurrentQuery = '',
  }) : filteredUnreadChats = filteredUnreadChats ?? unreadChats;

  bool get isSearchingUnread => unreadCurrentQuery.isNotEmpty;
}

class UnreadConversationsError extends ConversationError {
  const UnreadConversationsError(super.message);
}

// Backwards-compatibility: legacy consolidated state used by older UI checks
class ConversationLoading extends ConversationState {}

class ConversationLoaded extends ConversationState {
  final List<Conversation> allChats;
  final List<Conversation> filteredAllChats;
  final List<Conversation> unreadChats;
  final List<Conversation> filteredUnreadChats;

  final bool hasMore;
  final bool isLoadingMore;
  final bool unreadHasMore;
  final bool unreadIsLoadingMore;

  final String currentQuery;
  final String unreadCurrentQuery;

  const ConversationLoaded({
    required this.allChats,
    required this.filteredAllChats,
    required this.unreadChats,
    required this.filteredUnreadChats,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.unreadHasMore = false,
    this.unreadIsLoadingMore = false,
    this.currentQuery = '',
    this.unreadCurrentQuery = '',
  });

  ConversationLoaded copyWith({
    List<Conversation>? allChats,
    List<Conversation>? filteredAllChats,
    List<Conversation>? unreadChats,
    List<Conversation>? filteredUnreadChats,
    bool? hasMore,
    bool? isLoadingMore,
    bool? unreadHasMore,
    bool? unreadIsLoadingMore,
    String? currentQuery,
    String? unreadCurrentQuery,
  }) {
    return ConversationLoaded(
      allChats: allChats ?? this.allChats,
      filteredAllChats: filteredAllChats ?? this.filteredAllChats,
      unreadChats: unreadChats ?? this.unreadChats,
      filteredUnreadChats: filteredUnreadChats ?? this.filteredUnreadChats,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      unreadHasMore: unreadHasMore ?? this.unreadHasMore,
      unreadIsLoadingMore: unreadIsLoadingMore ?? this.unreadIsLoadingMore,
      currentQuery: currentQuery ?? this.currentQuery,
      unreadCurrentQuery: unreadCurrentQuery ?? this.unreadCurrentQuery,
    );
  }
}
