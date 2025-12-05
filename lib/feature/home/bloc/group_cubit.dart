import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/feature/home/model/contact_model.dart';
import 'package:hec_chat/feature/home/model/pagination_model.dart';
import 'package:hec_chat/feature/home/repository/message_repository.dart';
import 'package:hec_chat/feature/home/model/group_model.dart';
part 'group_state.dart';

class GroupCubit extends Cubit<GroupState> {
  final MessageRepository _repository;

  // Users list pagination & search
  int _usersCurrentPage = 1;
  bool _usersHasMore = true;
  bool _usersIsLoadingMore = false;
  String _usersCurrentQuery = '';
  List<ContactModel> _users = [];

  GroupCubit(this._repository) : super(GroupInitial());

  /* ---------------------------------------------------------------------
                           USERS LIST WITH PAGINATION & SEARCH
   --------------------------------------------------------------------- */

  // Search users
  void searchUsers(String query) {
    _usersCurrentQuery = query.trim();
    if (_usersCurrentQuery.isEmpty) {
      clearUsersSearch();
      return;
    }
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];
    loadUsers(refresh: true);
  }

  void clearUsersSearch() {
    _usersCurrentQuery = '';
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];
    loadUsers(refresh: true);
  }

  // Load users with pagination and search
  Future<void> loadUsers({bool refresh = false}) async {
    if (refresh) {
      _usersCurrentPage = 1;
      _usersHasMore = true;
      _users = [];
      if (!_usersIsLoadingMore) {
        emit(GroupUsersLoading());
      }
    } else if (_usersIsLoadingMore) {
      return;
    }

    try {
      _usersIsLoadingMore = !refresh;

      final ApiResponse<ContactResponse> response = await _repository
          .getUsersList(
            userId: SharedPreferencesHelper.getCurrentUserId(),
            page: _usersCurrentPage,
            perPage: 20,
            query: _usersCurrentQuery,
          );

      if (!response.success || response.data == null) {
        emit(GroupUsersError(response.message ?? 'Failed to load users'));
        _usersIsLoadingMore = false;
        return;
      }

      final List<ContactModel> newUsers = response.data!.contacts;
      final pagination = response.data?.pagination ?? Pagination();

      if (refresh) {
        _users = newUsers;
      } else {
        // Remove duplicates and add new users
        for (var newUser in newUsers) {
          final isDuplicate = _users.any((user) => user.id == newUser.id);
          if (!isDuplicate) {
            _users.add(newUser);
          }
        }
      }

      final currentPage = pagination.currentPage ?? 1;
      final totalPages = pagination.totalPages ?? 1;

      _usersHasMore = currentPage < totalPages;
      if (_usersHasMore) {
        _usersCurrentPage = currentPage + 1;
      }
      emit(
        GroupUsersLoaded(
          users: List.from(_users),
          hasMore: _usersHasMore,
          isLoadingMore: false,
          currentQuery: _usersCurrentQuery,
        ),
      );

      _usersIsLoadingMore = false;
    } catch (e) {
      _usersIsLoadingMore = false;
      emit(GroupUsersError(e.toString()));
    }
  }

  Future<void> loadMoreUsers() async {
    if (_usersHasMore && !_usersIsLoadingMore) {
      await loadUsers(refresh: false);
    }
  }

  /* ---------------------------------------------------------------------
                           GROUP CREATION
   --------------------------------------------------------------------- */
  Future<void> createGroup({
    required String name,
    required List<int> members,
    String description = '',
    String? photoPath,
  }) async {
    emit(GroupCreating());

    try {
      final response = await _repository.createGroup(
        name: name,
        members: members,
        description: description,
        photoPath: photoPath,
      );

      if (response.success && response.data != null) {
        emit(GroupCreated(group: response.data!.group));
      } else {
        emit(GroupError(response.message ?? 'Failed to create group'));
      }
    } catch (e) {
      emit(GroupError(e.toString()));
    }
  }

  void reset() {
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _usersIsLoadingMore = false;
    _usersCurrentQuery = '';
    _users = [];
    emit(GroupInitial());
  }
}
