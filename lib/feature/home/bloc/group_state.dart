part of 'group_cubit.dart';

abstract class GroupState {
  const GroupState();
}

class GroupInitial extends GroupState {}

// User selection states with pagination & search
class GroupUsersLoading extends GroupState {}

class GroupUsersLoaded extends GroupState {
  final List<ContactModel> users;
  final bool hasMore;
  final bool isLoadingMore;
  final String currentQuery;

  const GroupUsersLoaded({
    required this.users,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.currentQuery = '',
  });

  GroupUsersLoaded copyWith({
    List<ContactModel>? users,
    bool? hasMore,
    bool? isLoadingMore,
    String? currentQuery,
  }) {
    return GroupUsersLoaded(
      users: users ?? this.users,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }
}

class GroupUsersError extends GroupState {
  final String message;
  const GroupUsersError(this.message);
}

// Group creation states
class GroupCreating extends GroupState {}

class GroupCreated extends GroupState {
  final Group group;
  const GroupCreated({required this.group});
}

class GroupError extends GroupState {
  final String message;
  const GroupError(this.message);
}
