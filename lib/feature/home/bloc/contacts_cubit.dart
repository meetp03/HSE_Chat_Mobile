// cubit/message_cubit.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/network/api_response.dart';
import 'package:hec_chat/feature/home/bloc/contacts_state.dart';
import 'package:hec_chat/feature/home/model/blocked_user_model.dart';
import 'package:hec_chat/feature/home/model/contact_model.dart';
import 'package:hec_chat/feature/home/model/pagination_model.dart';
import 'package:hec_chat/feature/home/model/user_model.dart';
import 'package:hec_chat/feature/home/repository/message_repository.dart';

import '../../../cores/utils/shared_preferences.dart';

class MessageCubit extends Cubit<MessageState> {
  final MessageRepository _repository;

  // My Contacts pagination & search
  int _contactsCurrentPage = 1;
  bool _contactsHasMore = true;
  bool _contactsIsLoadingMore = false;
  String _contactsCurrentQuery = '';
  List<ContactModel> _contacts = [];

  // Users List pagination & search
  int _usersCurrentPage = 1;
  bool _usersHasMore = true;
  bool _usersIsLoadingMore = false;
  String _usersCurrentQuery = '';
  List<ContactModel> _users = [];

  // Blocked Users pagination & search
  int _blockedUsersCurrentPage = 1;
  bool _blockedUsersHasMore = true;
  bool _blockedUsersIsLoadingMore = false;
  String _blockedUsersCurrentQuery = '';
  List<BlockedUserModel> _blockedUsers = [];

  int get userId => SharedPreferencesHelper.getCurrentUserId();

  MessageCubit({required MessageRepository repository})
      : _repository = repository,
        super(MessageInitial());

  /* --------------------------------------------------------------------- /
  /                         SEARCH METHODS                                /
  / --------------------------------------------------------------------- */

  Future<void> searchContacts(String query) async {
    final trimmedQuery = query.trim();
    _contactsCurrentQuery = trimmedQuery;

    // Reset pagination state
    _contactsCurrentPage = 1;
    _contactsHasMore = true;
    _contacts = [];

    // Emit loading state
    emit(MyContactsLoading());

    await loadMyContacts(refresh: true);
  }

  Future<void> clearContactsSearch() async {
    _contactsCurrentQuery = '';
    _contactsCurrentPage = 1;
    _contactsHasMore = true;
    _contacts = [];

    emit(MyContactsLoading());

    await loadMyContacts(refresh: true);
  }

  // Users List Search
  Future<void> searchUsers(String query) async {
    _usersCurrentQuery = query.trim();
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];

    emit(UsersListLoading());
    await loadUsersList(refresh: true);
  }

  Future<void> clearUsersSearch() async {
    _usersCurrentQuery = '';
    _usersCurrentPage = 1;
    _usersHasMore = true;
    _users = [];

    emit(UsersListLoading());
    await loadUsersList(refresh: true);
  }

  // Blocked Users Search
  Future<void> searchBlockedUsers(String query) async {
    _blockedUsersCurrentQuery = query.trim();
    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsers = [];

    emit(BlockedUsersLoading());
    await loadBlockedUsers(refresh: true);
  }

  Future<void> clearBlockedUsersSearch() async {
    _blockedUsersCurrentQuery = '';
    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsers = [];

    emit(BlockedUsersLoading());
    await loadBlockedUsers(refresh: true);
  }

  /* --------------------------------------------------------------------- /
  /                         MY CONTACTS                                   /
  / --------------------------------------------------------------------- */
  Future<void> loadMyContacts({bool refresh = false}) async {
    // Prevent duplicate loading
    if (_contactsIsLoadingMore && !refresh) return;

    // ✅ Don't load if there's no more data
    if (!refresh && !_contactsHasMore) return;

    if (refresh) {
      _contactsCurrentPage = 1;
      _contactsHasMore = true;
      _contacts = [];
      emit(MyContactsLoading());
    }

    _contactsIsLoadingMore = true;

    try {
      print('🔍 Loading contacts with query: "$_contactsCurrentQuery"');

      final response = await _repository.getMyContacts(
        userId: userId,
        page: _contactsCurrentPage,
        perPage: 10,
        query: _contactsCurrentQuery,
      );

      if (!response.success || response.data == null) {
        emit(MyContactsError(response.message ?? 'Failed to load contacts'));
        return;
      }

      final newContacts = response.data!.contacts;
      final pagination = response.data!.pagination;

      print('📦 Received ${newContacts.length} contacts for query: "$_contactsCurrentQuery"');

      // ✅ FIX: If we received no contacts and we're not on page 1, there's no more data
      if (newContacts.isEmpty && _contactsCurrentPage > 1) {
        _contactsHasMore = false;
        emit(MyContactsLoaded(
          contacts: List.from(_contacts),
          pagination: pagination ?? Pagination(),
          hasMore: false,
          isLoadingMore: false,
          currentQuery: _contactsCurrentQuery,
        ));
        _contactsIsLoadingMore = false;
        return;
      }

      // Replace list on search/refresh, append on pagination
      if (refresh || _contactsCurrentPage == 1) {
        _contacts = newContacts;
      } else {
        final Set<int> existingIds = _contacts.map((c) => c.id).toSet();
        final filteredNew = newContacts.where((c) => !existingIds.contains(c.id)).toList();
        _contacts.addAll(filteredNew);
      }

      // ✅ Update pagination - check both pagination data AND if we received contacts
      final currentPage = pagination?.currentPage ?? 1;
      final totalPages = pagination?.totalPages ?? 1;

      // If we received fewer contacts than requested, or we're on the last page, no more data
      _contactsHasMore = (currentPage < totalPages) && (newContacts.length >= 10);
      _contactsCurrentPage = _contactsHasMore ? currentPage + 1 : currentPage;

      emit(MyContactsLoaded(
        contacts: List.from(_contacts),
        pagination: pagination ?? Pagination(),
        hasMore: _contactsHasMore,
        isLoadingMore: false,
        currentQuery: _contactsCurrentQuery,
      ));

    } catch (e) {
      print('❌ Error loading contacts: $e');
      emit(MyContactsError(e.toString()));
    } finally {
      _contactsIsLoadingMore = false;
    }
  }

  /* --------------------------------------------------------------------- /
  /                         USERS LIST                                    /
  / --------------------------------------------------------------------- */
  Future<void> loadUsersList({bool refresh = false}) async {
    if (!refresh && !_usersHasMore) return;

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

      final ApiResponse<ContactResponse> response = await _repository
          .getUsersList(
        userId: userId,
        page: _usersCurrentPage,
        perPage: 10,
        query: _usersCurrentQuery,
      );

      if (!response.success || response.data == null) {
        emit(UsersListError(response.message ?? 'Failed to load users'));
        _usersIsLoadingMore = false;
        return;
      }

      final List<ContactModel> newUsers = response.data!.contacts;
      final Pagination? pagination = response.data!.pagination;

      // ✅ FIX: If no users received and not on first page, stop loading
      if (newUsers.isEmpty && _usersCurrentPage > 1) {
        _usersHasMore = false;
        emit(UsersListLoaded(
          users: List.from(_users),
          pagination: pagination ?? Pagination(),
          hasMore: false,
          isLoadingMore: false,
          currentQuery: _usersCurrentQuery,
        ));
        _usersIsLoadingMore = false;
        return;
      }

      if (refresh) {
        _users = newUsers;
      } else {
        for (var newUser in newUsers) {
          final isDuplicate = _users.any((user) => user.id == newUser.id);
          if (!isDuplicate) {
            _users.add(newUser);
          }
        }
      }

      if (pagination != null) {
        final currentPage = pagination.currentPage ?? 1;
        final totalPages = pagination.totalPages ?? 1;

        // ✅ Check both pagination and actual data received
        _usersHasMore = (currentPage < totalPages) && (newUsers.length >= 10);
        if (_usersHasMore) {
          _usersCurrentPage = currentPage + 1;
        }
      } else {
        _usersHasMore = false;
      }

      emit(
        UsersListLoaded(
          users: List.from(_users),
          pagination: pagination ?? Pagination(),
          hasMore: _usersHasMore,
          isLoadingMore: false,
          currentQuery: _usersCurrentQuery,
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
    if (!refresh && !_blockedUsersHasMore) return;

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
        query: _blockedUsersCurrentQuery,
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

      // ✅ FIX: If no blocked users received and not on first page, stop loading
      if (newBlockedUsers.isEmpty && _blockedUsersCurrentPage > 1) {
        _blockedUsersHasMore = false;
        emit(BlockedUsersLoaded(
          blockedUsers: List.from(_blockedUsers),
          pagination: pagination,
          hasMore: false,
          isLoadingMore: false,
          currentQuery: _blockedUsersCurrentQuery,
        ));
        _blockedUsersIsLoadingMore = false;
        return;
      }

      if (refresh) {
        _blockedUsers = newBlockedUsers;
      } else {
        for (var newBlockedUser in newBlockedUsers) {
          final isDuplicate = _blockedUsers.any(
                (user) => user.id == newBlockedUser.id,
          );
          if (!isDuplicate) {
            _blockedUsers.add(newBlockedUser);
          }
        }
      }

      final currentPage = pagination.currentPage ?? 1;
      final totalPages = pagination.totalPages ?? 1;

      // ✅ Check both pagination and actual data received
      _blockedUsersHasMore = (currentPage < totalPages) && (newBlockedUsers.length >= 10);
      if (_blockedUsersHasMore) {
        _blockedUsersCurrentPage = currentPage + 1;
      }

      emit(
        BlockedUsersLoaded(
          blockedUsers: List.from(_blockedUsers),
          pagination: pagination,
          hasMore: _blockedUsersHasMore,
          isLoadingMore: false,
          currentQuery: _blockedUsersCurrentQuery,
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
    _contactsCurrentQuery = '';
    _contacts = [];

    _usersCurrentPage = 1;
    _usersHasMore = true;
    _usersIsLoadingMore = false;
    _usersCurrentQuery = '';
    _users = [];

    _blockedUsersCurrentPage = 1;
    _blockedUsersHasMore = true;
    _blockedUsersIsLoadingMore = false;
    _blockedUsersCurrentQuery = '';
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