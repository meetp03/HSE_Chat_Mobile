import 'package:hec_chat/feature/home/model/blocked_user_model.dart';
import 'package:hec_chat/feature/home/model/contact_model.dart';
import 'package:hec_chat/feature/home/model/pagination_model.dart';

abstract class MessageState {
  const MessageState();
}

class MessageInitial extends MessageState {}

// My Contacts States
class MyContactsLoading extends MessageState {}

class MyContactsLoaded extends MessageState {
  final List<ContactModel> contacts;
  final Pagination pagination;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentQuery;

  const MyContactsLoaded({
    required this.contacts,
    required this.pagination,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentQuery = '',
  });

  MyContactsLoaded copyWith({
    List<ContactModel>? contacts,
    Pagination? pagination,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentQuery,
  }) {
    return MyContactsLoaded(
      contacts: contacts ?? this.contacts,
      pagination: pagination ?? this.pagination,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }
}

class MyContactsError extends MessageState {
  final String message;
  const MyContactsError(this.message);
}

// Users List States
class UsersListLoading extends MessageState {}

class UsersListLoaded extends MessageState {
  final List<ContactModel> users;
  final Pagination pagination;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentQuery;

  const UsersListLoaded({
    required this.users,
    required this.pagination,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentQuery = '',
  });

  UsersListLoaded copyWith({
    List<ContactModel>? users,
    Pagination? pagination,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentQuery,
  }) {
    return UsersListLoaded(
      users: users ?? this.users,
      pagination: pagination ?? this.pagination,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }
}

class UsersListError extends MessageState {
  final String message;
  const UsersListError(this.message);
}

// Blocked Users States
class BlockedUsersLoading extends MessageState {}

class BlockedUsersLoaded extends MessageState {
  final List<BlockedUserModel> blockedUsers;
  final Pagination pagination;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentQuery;

  const BlockedUsersLoaded({
    required this.blockedUsers,
    required this.pagination,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentQuery = '',
  });

  BlockedUsersLoaded copyWith({
    List<BlockedUserModel>? blockedUsers,
    Pagination? pagination,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentQuery,
  }) {
    return BlockedUsersLoaded(
      blockedUsers: blockedUsers ?? this.blockedUsers,
      pagination: pagination ?? this.pagination,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }
}

class BlockedUsersError extends MessageState {
  final String message;
  const BlockedUsersError(this.message);
}
