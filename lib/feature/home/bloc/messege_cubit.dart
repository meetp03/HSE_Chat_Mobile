// cubit/message_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/network/api_response.dart';
import 'package:hsc_chat/feature/home/bloc/message_state.dart';
import 'package:hsc_chat/feature/home/model/blocked_user_model.dart';
import 'package:hsc_chat/feature/home/model/contact_model.dart';
import 'package:hsc_chat/feature/home/model/pagination_model.dart';
import 'package:hsc_chat/feature/home/model/user_model.dart';
import 'package:hsc_chat/feature/home/repository/message_repository.dart';

import '../../../cores/utils/shared_preferences.dart';

class MessageCubit extends Cubit<MessageState> {
  final MessageRepository _repository;

  // My Contacts pagination & search
  int _contactsCurrentPage = 1;
  bool _contactsHasMore = true;
  bool _contactsIsLoadingMore = false;
  String _contactsCurrentQuery = ''; // Add search query
  List<ContactModel> _contacts = [];

  // Users List pagination & search
  int _usersCurrentPage = 1;
  bool _usersHasMore = true;
  bool _usersIsLoadingMore = false;
  String _usersCurrentQuery = ''; // Add search query
  List<UserModel> _users = [];

  // Blocked Users pagination & search
  int _blockedUsersCurrentPage = 1;
  bool _blockedUsersHasMore = true;
  bool _blockedUsersIsLoadingMore = false;
  String _blockedUsersCurrentQuery = ''; // Add search query
  List<BlockedUserModel> _blockedUsers = [];

  int get userId => SharedPreferencesHelper.getCurrentUserId();

  MessageCubit({required MessageRepository repository})
    : _repository = repository,
      super(MessageInitial());

  /* --------------------------------------------------------------------- /
  /                         SEARCH METHODS                                /
  / --------------------------------------------------------------------- */

  // My Contacts Search
  void searchContacts(String query) {
    _contactsCurrentQuery = query.trim();
    if (_contactsCurrentQuery.isEmpty) {
      clearContactsSearch();
      return;
    }
    _contactsCurrentPage = 1;
    _contactsHasMore = true;
    _contacts = [];
    loadMyContacts(refresh: true);
  }

  void clearContactsSearch() {
    _contactsCurrentQuery = '';
    _contactsCurrentPage = 1;
    _contactsHasMore = true;
    _contacts = [];
    loadMyContacts(refresh: true);
  }

  // Users List Search
  void searchUsers(String query) {
    _usersCurrentQuery = query.trim();
    if (_usersCurrentQuery.isEmpty) {
      clearUsersSearch();
      return;
    }
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];
    loadUsersList(refresh: true);
  }

  void clearUsersSearch() {
    _usersCurrentQuery = '';
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];
    loadUsersList(refresh: true);
  }

  // Blocked Users Search
  void searchBlockedUsers(String query) {
    _blockedUsersCurrentQuery = query.trim();
    if (_blockedUsersCurrentQuery.isEmpty) {
      clearBlockedUsersSearch();
      return;
    }
    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsers = [];
    loadBlockedUsers(refresh: true);
  }

  void clearBlockedUsersSearch() {
    _blockedUsersCurrentQuery = '';
    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsers = [];
    loadBlockedUsers(refresh: true);
  }

  /* --------------------------------------------------------------------- /
  /                         MY CONTACTS                                   /
  / --------------------------------------------------------------------- */
  Future<void> loadMyContacts({bool refresh = false}) async {
    if (refresh) {
      _contactsCurrentPage = 1;
      _contactsHasMore = true;
      _contacts = [];
      if (!_contactsIsLoadingMore) {
        emit(MyContactsLoading());
      }
    } else if (_contactsIsLoadingMore) {
      return;
    }

    try {
      _contactsIsLoadingMore = !refresh;

      final ApiResponse<ContactResponse> response = await _repository
          .getMyContacts(
            userId: userId,
            page: _contactsCurrentPage,
            perPage: 10,
            query: _contactsCurrentQuery, // Pass search query
          );

      if (!response.success || response.data == null) {
        emit(MyContactsError(response.message ?? 'Failed to load contacts'));
        _contactsIsLoadingMore = false;
        return;
      }

      final List<ContactModel> newContacts = response.data?.contacts ?? [];
      final Pagination pagination = response.data!.pagination;

      if (refresh) {
        _contacts = newContacts;
      } else {
        // Remove duplicates and add new contacts
        for (var newContact in newContacts) {
          final isDuplicate = _contacts.any(
            (contact) => contact.id == newContact.id,
          );
          if (!isDuplicate) {
            _contacts.add(newContact);
          }
        }
      }

      _contactsHasMore = pagination.currentPage < pagination.totalPages;
      if (_contactsHasMore) {
        _contactsCurrentPage = pagination.currentPage + 1;
      }

      emit(
        MyContactsLoaded(
          contacts: List.from(_contacts),
          pagination: pagination,
          hasMore: _contactsHasMore,
          isLoadingMore: false,
          currentQuery: _contactsCurrentQuery, // Pass current query
        ),
      );

      _contactsIsLoadingMore = false;
    } catch (e) {
      _contactsIsLoadingMore = false;
      emit(MyContactsError(e.toString()));
    }
  }

  /* --------------------------------------------------------------------- /
  /                         USERS LIST                                    /
  / --------------------------------------------------------------------- */
  Future<void> loadUsersList({bool refresh = false}) async {
    if (refresh) {
      _usersCurrentPage = 1;
      _usersHasMore = true;
      _users = [];
      if (!_usersIsLoadingMore) {
        emit(UsersListLoading());
      }
    } else if (_usersIsLoadingMore) {
      return;
    }

    try {
      _usersIsLoadingMore = !refresh;

      final ApiResponse<UserResponse> response = await _repository.getUsersList(
        userId: userId,
        page: _usersCurrentPage,
        perPage: 10,
        query: _usersCurrentQuery, // Pass search query
      );

      if (!response.success || response.data == null) {
        emit(UsersListError(response.message ?? 'Failed to load users'));
        _usersIsLoadingMore = false;
        return;
      }

      final List<UserModel> newUsers = response.data!.users;
      final Pagination pagination = response.data!.pagination;

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

      _usersHasMore = pagination.currentPage < pagination.totalPages;
      if (_usersHasMore) {
        _usersCurrentPage = pagination.currentPage + 1;
      }

      emit(
        UsersListLoaded(
          users: List.from(_users),
          pagination: pagination,
          hasMore: _usersHasMore,
          isLoadingMore: false,
          currentQuery: _usersCurrentQuery, // Pass current query
        ),
      );

      _usersIsLoadingMore = false;
    } catch (e) {
      _usersIsLoadingMore = false;
      emit(UsersListError(e.toString()));
    }
  }

  /* --------------------------------------------------------------------- /
  /                         BLOCKED USERS                                 /
  / --------------------------------------------------------------------- */
  Future<void> loadBlockedUsers({bool refresh = false}) async {
    if (refresh) {
      _blockedUsersCurrentPage = 1;
      _blockedUsersHasMore = true;
      _blockedUsers = [];
      if (!_blockedUsersIsLoadingMore) {
        emit(BlockedUsersLoading());
      }
    } else if (_blockedUsersIsLoadingMore) {
      return;
    }

    try {
      _blockedUsersIsLoadingMore = !refresh;

      final ApiResponse<BlockedUserResponse> response = await _repository
          .getBlockedUsers(
            userId: userId,
            page: _blockedUsersCurrentPage,
            perPage: 10,
            query: _blockedUsersCurrentQuery, // Pass search query
          );

      if (!response.success || response.data == null) {
        emit(
          BlockedUsersError(response.message ?? 'Failed to load blocked users'),
        );
        _blockedUsersIsLoadingMore = false;
        return;
      }

      final List<BlockedUserModel> newBlockedUsers = response.data!.users;
      final Pagination pagination = response.data!.pagination;

      if (refresh) {
        _blockedUsers = newBlockedUsers;
      } else {
        // Remove duplicates and add new blocked users
        for (var newBlockedUser in newBlockedUsers) {
          final isDuplicate = _blockedUsers.any(
            (user) => user.id == newBlockedUser.id,
          );
          if (!isDuplicate) {
            _blockedUsers.add(newBlockedUser);
          }
        }
      }

      _blockedUsersHasMore = pagination.currentPage < pagination.totalPages;
      if (_blockedUsersHasMore) {
        _blockedUsersCurrentPage = pagination.currentPage + 1;
      }

      emit(
        BlockedUsersLoaded(
          blockedUsers: List.from(_blockedUsers),
          pagination: pagination,
          hasMore: _blockedUsersHasMore,
          isLoadingMore: false,
          currentQuery: _blockedUsersCurrentQuery, // Pass current query
        ),
      );

      _blockedUsersIsLoadingMore = false;
    } catch (e) {
      _blockedUsersIsLoadingMore = false;
      emit(BlockedUsersError(e.toString()));
    }
  }

  Future<void> loadMoreContacts() async {
    if (_contactsHasMore && !_contactsIsLoadingMore) {
      await loadMyContacts(refresh: false);
    }
  }

  Future<void> loadMoreUsers() async {
    if (_usersHasMore && !_usersIsLoadingMore) {
      await loadUsersList(refresh: false);
    }
  }

  Future<void> loadMoreBlockedUsers() async {
    if (_blockedUsersHasMore && !_blockedUsersIsLoadingMore) {
      await loadBlockedUsers(refresh: false);
    }
  }

  /* --------------------------------------------------------------------- /
  /                         TAB MANAGEMENT                                /
  / --------------------------------------------------------------------- */
  void loadTabData(int tabIndex) {
    switch (tabIndex) {
      case 0: // My Contacts
        loadMyContacts(refresh: true);
        break;
      case 1: // New Conversation
        loadUsersList(refresh: true);
        break;
      case 2: // Blocked Users
        loadBlockedUsers(refresh: true);
        break;
    }
  }

  /* --------------------------------------------------------------------- /
  /                         RESET                                        /
  / --------------------------------------------------------------------- */
  void reset() {
    _contactsCurrentPage = 1;
    _contactsHasMore = true;
    _contactsIsLoadingMore = false;
    _contactsCurrentQuery = ''; // Reset search query
    _contacts = [];

    _usersCurrentPage = 1;
    _usersHasMore = true;
    _usersIsLoadingMore = false;
    _usersCurrentQuery = ''; // Reset search query
    _users = [];

    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsersIsLoadingMore = false;
    _blockedUsersCurrentQuery = ''; // Reset search query
    _blockedUsers = [];

    emit(MessageInitial());
  }

  /// Send chat request to a user (from current user)
  Future<ApiResponse<void>> sendChatRequestTo(String toId) async {
    try {
      final resp = await _repository.sendChatRequest(
        fromId: userId,
        toId: toId,
      );
      return resp;
    } catch (e) {
      return ApiResponse<void>.error('Failed to send chat request: $e');
    }
  }
}
