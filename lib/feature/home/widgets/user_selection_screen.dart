// screens/user_selection_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
import 'package:hec_chat/feature/home/bloc/group_cubit.dart';
import 'package:hec_chat/feature/home/widgets/create_group_screen.dart';

class UserSelectionScreen extends StatefulWidget {
  const UserSelectionScreen({Key? key}) : super(key: key);

  @override
  State<UserSelectionScreen> createState() => _UserSelectionScreenState();
}

class _UserSelectionScreenState extends State<UserSelectionScreen> {
  final List<int> _selectedUsers = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    // Load initial users
    context.read<GroupCubit>().loadUsers(refresh: true);

    // Setup scroll listener for pagination
    _scrollController.addListener(_onScroll);

    // Setup search debounce
    _setupSearchController();
  }

  void _setupSearchController() {
    _searchController.addListener(() {
      if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        final query = _searchController.text.trim();
        context.read<GroupCubit>().searchUsers(query);
      });
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100 &&
        _scrollController.position.maxScrollExtent > 0) {
      context.read<GroupCubit>().loadMoreUsers();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.selectUsersTitle),
        backgroundColor: AppClr.primaryColor,
        foregroundColor: AppClr.white,
        actions: [
          if (_selectedUsers.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        CreateGroupScreen(selectedUserIds: _selectedUsers),
                  ),
                );
              },
              child: Text(
                AppStrings.nextButton,
                style: TextStyle(
                  color: AppClr.white,
                  fontSize: 16.0,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),
          // Selected Users Count
          _buildSelectedUsersInfo(),
          // Users List
          Expanded(child: _buildUsersList()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        decoration: InputDecoration(
          hintText: AppStrings.searchUsersHint,
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppClr.grey, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppClr.primaryColor, width: 2.0),
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              context.read<GroupCubit>().clearUsersSearch();
            },
          )
              : null,

          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildSelectedUsersInfo() {
    return BlocBuilder<GroupCubit, GroupState>(
      builder: (context, state) {
        if (state is GroupUsersLoaded && _selectedUsers.isNotEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppClr.primaryColor.withValues(alpha: 0.1),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${AppStrings.selectedLabel} ${_selectedUsers.length} ${AppStrings.usersLabel}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppClr.primaryColor,
                  ),
                ),
                if (_selectedUsers.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedUsers.clear();
                      });
                    },
                    child: Text(
                      AppStrings.clearAllButton,
                      style: TextStyle(
                        color: AppClr.errorColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildUsersList() {
    return BlocBuilder<GroupCubit, GroupState>(
      builder: (context, state) {
        if (state is GroupUsersLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is GroupUsersError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${AppStrings.errorPrefix}: ${state.message}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () =>
                      context.read<GroupCubit>().loadUsers(refresh: true),
                  child: const Text(AppStrings.retryButton),
                ),
              ],
            ),
          );
        } else if (state is GroupUsersLoaded) {
          return _buildUsersListView(state);
        }
        return const Center(child: Text(AppStrings.noUsersFound));
      },
    );
  }

  Widget _buildUsersListView(GroupUsersLoaded state) {
    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.currentQuery.isNotEmpty ? Icons.search_off : Icons.people,
              size: 64,
              color: AppClr.grey,
            ),
            const SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? '${AppStrings.noUsersFoundForQuery} "${state.currentQuery}"'
                  : AppStrings.noUsersFound,
              style: TextStyle(fontSize: 18, color: AppClr.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: state.users.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator for pagination
        if (index == state.users.length && state.hasMore) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = state.users[index];
        final isSelected = _selectedUsers.contains(user.id);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? AppClr.primaryColor
                : AppClr.avatarBackground,
            child: Text(
              user.name.substring(0, 1),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppClr.white : AppClr.black,
              ),
            ),
          ),
          title: Text(
            user.name,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          subtitle: Text(user.email),
          trailing: Checkbox(
            value: isSelected,
            onChanged: (value) {
              _toggleUserSelection(user.id);
            },
          ),
          onTap: () {
            _toggleUserSelection(user.id);
          },
        );
      },
    );
  }

  void _toggleUserSelection(int userId) {
    setState(() {
      if (_selectedUsers.contains(userId)) {
        _selectedUsers.remove(userId);
      } else {
        _selectedUsers.add(userId);
      }
    });
  }
}