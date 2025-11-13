import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/feature/home/bloc/message_state.dart';
import 'package:hsc_chat/feature/home/bloc/messege_cubit.dart';
import 'package:hsc_chat/feature/home/view/chat_screen.dart';
import 'package:hsc_chat/cores/utils/providers.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({Key? key}) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Scroll controllers for each tab
  final ScrollController _contactsScrollController = ScrollController();
  final ScrollController _usersScrollController = ScrollController();
  final ScrollController _blockedUsersScrollController = ScrollController();

  // Search controllers for each tab
  final TextEditingController _contactsSearchController =
      TextEditingController();
  final TextEditingController _usersSearchController = TextEditingController();
  final TextEditingController _blockedUsersSearchController =
      TextEditingController();

  // Search focus nodes
  final FocusNode _contactsSearchFocus = FocusNode();
  final FocusNode _usersSearchFocus = FocusNode();
  final FocusNode _blockedUsersSearchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // Setup scroll listeners
    _setupScrollController(_contactsScrollController, () {
      context.read<MessageCubit>().loadMoreContacts();
    });

    _setupScrollController(_usersScrollController, () {
      context.read<MessageCubit>().loadMoreUsers();
    });

    _setupScrollController(_blockedUsersScrollController, () {
      context.read<MessageCubit>().loadMoreBlockedUsers();
    });

    // Listen to tab changes
    _tabController.addListener(_onTabChanged);

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageCubit>().loadMyContacts(refresh: true);
    });

    // Listen to search controller changes with debounce
    _setupSearchController(_contactsSearchController, (query) {
      context.read<MessageCubit>().searchContacts(query);
    });

    _setupSearchController(_usersSearchController, (query) {
      context.read<MessageCubit>().searchUsers(query);
    });

    _setupSearchController(_blockedUsersSearchController, (query) {
      context.read<MessageCubit>().searchBlockedUsers(query);
    });
  }

  void _setupScrollController(
    ScrollController controller,
    VoidCallback onLoadMore,
  ) {
    controller.addListener(() {
      if (controller.position.pixels >=
              controller.position.maxScrollExtent - 100 &&
          controller.position.maxScrollExtent > 0) {
        onLoadMore();
      }
    });
  }

  void _setupSearchController(
    TextEditingController controller,
    Function(String) onSearch,
  ) {
    // Simple debounce implementation
    Timer? _debounce;
    controller.addListener(() {
      if (_debounce?.isActive ?? false) _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        onSearch(controller.text);
      });
    });
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      final cubit = context.read<MessageCubit>();
      cubit.loadTabData(_tabController.index);

      // Clear search focus when changing tabs
      _contactsSearchFocus.unfocus();
      _usersSearchFocus.unfocus();
      _blockedUsersSearchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _contactsScrollController.dispose();
    _usersScrollController.dispose();
    _blockedUsersScrollController.dispose();
    _contactsSearchController.dispose();
    _usersSearchController.dispose();
    _blockedUsersSearchController.dispose();
    _contactsSearchFocus.dispose();
    _usersSearchFocus.dispose();
    _blockedUsersSearchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start New Conversation'),
        backgroundColor: AppClr.primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'My Contacts'),
            Tab(text: 'New Conversation'),
            Tab(text: 'Blocked Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // My Contacts Tab
          _buildContactsTab(),

          // New Conversation Tab
          _buildUsersListTab(),

          // Blocked Users Tab
          _buildBlockedUsersTab(),
        ],
      ),
    );
  }

  Widget _buildContactsTab() {
    return Column(
      children: [
        // Search Bar
        _buildSearchBar(
          controller: _contactsSearchController,
          focusNode: _contactsSearchFocus,
          hintText: 'Search contacts...',
          onClear: () {
            _contactsSearchController.clear();
            context.read<MessageCubit>().clearContactsSearch();
          },
        ),
        Expanded(
          child: BlocBuilder<MessageCubit, MessageState>(
            builder: (context, state) {
              if (state is MyContactsLoading) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is MyContactsError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: ${state.message}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context
                            .read<MessageCubit>()
                            .loadMyContacts(refresh: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              } else if (state is MyContactsLoaded) {
                return _buildContactsList(state);
              }
              return const Center(child: Text('No contacts found'));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUsersListTab() {
    return Column(
      children: [
        // Search Bar
        _buildSearchBar(
          controller: _usersSearchController,
          focusNode: _usersSearchFocus,
          hintText: 'Search users...',
          onClear: () {
            _usersSearchController.clear();
            context.read<MessageCubit>().clearUsersSearch();
          },
        ),
        Expanded(
          child: BlocBuilder<MessageCubit, MessageState>(
            builder: (context, state) {
              if (state is UsersListLoading) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is UsersListError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: ${state.message}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context
                            .read<MessageCubit>()
                            .loadUsersList(refresh: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              } else if (state is UsersListLoaded) {
                return _buildUsersList(state);
              }
              return const Center(child: Text('No users found'));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBlockedUsersTab() {
    return Column(
      children: [
        // Search Bar
        _buildSearchBar(
          controller: _blockedUsersSearchController,
          focusNode: _blockedUsersSearchFocus,
          hintText: 'Search blocked users...',
          onClear: () {
            _blockedUsersSearchController.clear();
            context.read<MessageCubit>().clearBlockedUsersSearch();
          },
        ),
        Expanded(
          child: BlocBuilder<MessageCubit, MessageState>(
            builder: (context, state) {
              if (state is BlockedUsersLoading) {
                return const Center(child: CircularProgressIndicator());
              } else if (state is BlockedUsersError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: ${state.message}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context
                            .read<MessageCubit>()
                            .loadBlockedUsers(refresh: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              } else if (state is BlockedUsersLoaded) {
                return _buildBlockedUsersList(state);
              }
              return const Center(child: Text('No blocked users found'));
            },
          ),
        ),
      ],
    );
  }

  // Reusable Search Bar Widget
  Widget _buildSearchBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear)
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppClr.primaryColor, width: 2.0),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildContactsList(MyContactsLoaded state) {
    if (state.contacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.currentQuery.isNotEmpty ? Icons.search_off : Icons.contacts,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? 'No contacts found for "${state.currentQuery}"'
                  : 'No contacts found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _contactsScrollController,
      itemCount: state.contacts.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.contacts.length && state.hasMore) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final contact = state.contacts[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AppClr.primaryColor.withAlpha(25),
            backgroundImage: contact.photoUrl != null
                ? CachedNetworkImageProvider(contact.photoUrl!)
                : null,
            child: contact.photoUrl == null
                ? Text(
                    contact.name.substring(0, 1),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          title: Text(contact.name),
          subtitle: Text(contact.email),
          trailing: contact.isOnline
              ? const Icon(Icons.circle, color: Colors.green, size: 12)
              : null,
          onTap: () {
            _startConversation(contact.id, contact.name, false);
          },
        );
      },
    );
  }

  Widget _buildUsersList(UsersListLoaded state) {
    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.currentQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.person_add,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? 'No users found for "${state.currentQuery}"'
                  : 'No users found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _usersScrollController,
      itemCount: state.users.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.users.length && state.hasMore) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = state.users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.green.shade100,
            child: Text(
              user.name.substring(0, 1),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(user.name),
          subtitle: Text(user.email),
          trailing: IconButton(
            icon: Icon(Icons.message, color: AppClr.primaryColor),
            onPressed: () {
              _startConversation(user.id, user.name, false);
            },
          ),
        );
      },
    );
  }

  Widget _buildBlockedUsersList(BlockedUsersLoaded state) {
    if (state.blockedUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.currentQuery.isNotEmpty ? Icons.search_off : Icons.block,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? 'No blocked users found for "${state.currentQuery}"'
                  : 'No blocked users found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _blockedUsersScrollController,
      itemCount: state.blockedUsers.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.blockedUsers.length && state.hasMore) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = state.blockedUsers[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.red.shade100,
            backgroundImage: user.photoUrl != null
                ? CachedNetworkImageProvider(user.photoUrl!)
                : null,
            child: user.photoUrl == null
                ? const Icon(Icons.block, color: Colors.red)
                : null,
          ),
          title: Text(user.name),
          subtitle: Text(user.email),
          trailing: TextButton(
            onPressed: () {
              // pass the actual user id
              _showUnblockDialog(user.name, user.id);
            },
            child: const Text('UNBLOCK', style: TextStyle(color: Colors.blue)),
          ),
        );
      },
    );
  }

  Future<void> _startConversation(
    int userId,
    String userName,
    bool isGroup,
  ) async {
    print('Starting conversation with $userName (ID: $userId)');

    final messageCubit = context.read<MessageCubit>();

    // Show loading message using custom snackbar
    showCustomSnackBar(
      context,
      'Sending chat request...',
      type: SnackBarType.success,
      duration: const Duration(seconds: 10),
    );

    try {
      final resp = await messageCubit.sendChatRequestTo(userId.toString());

      if (!mounted) return;
      // hide loading and show result
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (resp.success) {
        showCustomSnackBar(
          context,
          resp.message ?? 'Chat request sent',
          type: SnackBarType.success,
        );

        // Navigate to chat screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BlocProvider(
              create: (_) => Providers.createChatCubit(),
              child: ChatScreen(
                userId: userId.toString(),
                userName: userName,
                userAvatar: null,
                isGroup: isGroup,
              ),
            ),
          ),
        );
      } else {
        showCustomSnackBar(
          context,
          resp.message ?? 'Failed to send chat request',
          type: SnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      showCustomSnackBar(
        context,
        'Failed to send chat request: $e',
        type: SnackBarType.error,
      );
    }
  }

  void _showUnblockDialog(String username, int userId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock $username?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              // Add unblock API call here
              Navigator.pop(context);
              showCustomSnackBar(
                context,
                '$username has been unblocked',
                type: SnackBarType.success,
              );
              // Refresh blocked users list
              context.read<MessageCubit>().loadBlockedUsers(refresh: true);
            },
            child: const Text('UNBLOCK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
}
