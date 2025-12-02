import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/feature/home/bloc/contacts_state.dart';
import 'package:hsc_chat/feature/home/bloc/contacts_cubit.dart';
import 'package:hsc_chat/feature/home/view/chat_screen.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hsc_chat/feature/home/repository/user_repository.dart';
import '../../../cores/network/dio_client.dart';
import '../../../cores/network/socket_service.dart';
import '../bloc/chat_cubit.dart';
import '../bloc/conversation_cubit.dart';
import '../repository/chat_repository.dart';

class MessageScreen extends StatefulWidget {
  const MessageScreen({Key? key}) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final ScrollController _contactsScrollController = ScrollController();
  final ScrollController _usersScrollController = ScrollController();
  final ScrollController _blockedUsersScrollController = ScrollController();

  final TextEditingController _contactsSearchController = TextEditingController();
  final TextEditingController _usersSearchController = TextEditingController();
  final TextEditingController _blockedUsersSearchController = TextEditingController();

  final FocusNode _contactsSearchFocus = FocusNode();
  final FocusNode _usersSearchFocus = FocusNode();
  final FocusNode _blockedUsersSearchFocus = FocusNode();

  Timer? _contactsDebounce;
  Timer? _usersDebounce;
  Timer? _blockedUsersDebounce;

  //  Track last search query to prevent unnecessary calls
  String _lastContactsQuery = '';
  String _lastUsersQuery = '';
  String _lastBlockedUsersQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _setupScrollController(_contactsScrollController, () {
      context.read<MessageCubit>().loadMoreContacts();
    });

    _setupScrollController(_usersScrollController, () {
      context.read<MessageCubit>().loadMoreUsers();
    });

    _setupScrollController(_blockedUsersScrollController, () {
      context.read<MessageCubit>().loadMoreBlockedUsers();
    });

    _tabController.addListener(_onTabChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessageCubit>().loadMyContacts(refresh: true);
    });

    _contactsSearchController.addListener(_onContactsSearchChanged);
    _usersSearchController.addListener(_onUsersSearchChanged);
    _blockedUsersSearchController.addListener(_onBlockedUsersSearchChanged);
  }

  void _onContactsSearchChanged() {
    final query = _contactsSearchController.text.trim();

    //  Cancel previous timer
    _contactsDebounce?.cancel();

    // Set new timer
    _contactsDebounce = Timer(const Duration(milliseconds: 500), () {
      //  Only search if query actually changed
      if (query != _lastContactsQuery) {
        print('🔎 Contacts search: "$_lastContactsQuery" → "$query"');
        _lastContactsQuery = query;

        if (query.isEmpty) {
          context.read<MessageCubit>().clearContactsSearch();
        } else {
          context.read<MessageCubit>().searchContacts(query);
        }
      }
    });
  }

  void _onUsersSearchChanged() {
    final query = _usersSearchController.text.trim();
    _usersDebounce?.cancel();
    _usersDebounce = Timer(const Duration(milliseconds: 500), () {
      if (query != _lastUsersQuery) {
        _lastUsersQuery = query;
        if (query.isEmpty) {
          context.read<MessageCubit>().clearUsersSearch();
        } else {
          context.read<MessageCubit>().searchUsers(query);
        }
      }
    });
  }

  void _onBlockedUsersSearchChanged() {
    final query = _blockedUsersSearchController.text.trim();
    _blockedUsersDebounce?.cancel();
    _blockedUsersDebounce = Timer(const Duration(milliseconds: 500), () {
      if (query != _lastBlockedUsersQuery) {
        _lastBlockedUsersQuery = query;
        if (query.isEmpty) {
          context.read<MessageCubit>().clearBlockedUsersSearch();
        } else {
          context.read<MessageCubit>().searchBlockedUsers(query);
        }
      }
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

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      final cubit = context.read<MessageCubit>();
      cubit.loadTabData(_tabController.index);
      _contactsSearchFocus.unfocus();
      _usersSearchFocus.unfocus();
      _blockedUsersSearchFocus.unfocus();
    }
  }

  @override
  void dispose() {
    _contactsDebounce?.cancel();
    _usersDebounce?.cancel();
    _blockedUsersDebounce?.cancel();
    _contactsSearchController.removeListener(_onContactsSearchChanged);
    _usersSearchController.removeListener(_onUsersSearchChanged);
    _blockedUsersSearchController.removeListener(_onBlockedUsersSearchChanged);
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
          _buildContactsTab(),
          _buildUsersListTab(),
          _buildBlockedUsersTab(),
        ],
      ),
    );
  }

  Widget _buildContactsTab() {
    return Column(
      children: [
        _buildSearchBar(
          controller: _contactsSearchController,
          focusNode: _contactsSearchFocus,
          hintText: 'Search contacts...',
          onClear: () {
            _contactsSearchController.clear();
            // Listener will handle the search automatically
          },
        ),
        Expanded(
          child: BlocBuilder<MessageCubit, MessageState>(
            builder: (context, state) {

              if (state is MyContactsLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is MyContactsError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(state.message),
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
              }

              if (state is MyContactsLoaded) {
                final contacts = state.contacts;
                final query = state.currentQuery;

                if (query.isNotEmpty && contacts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search_off, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No contacts found for "$query"',
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            _contactsSearchController.clear();
                          },
                          child: const Text('Clear Search'),
                        ),
                      ],
                    ),
                  );
                }

                if (contacts.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.contacts, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No contacts yet',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _contactsScrollController,
                  itemCount: contacts.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == contacts.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final contact = contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppClr.primaryColor.withAlpha(25),
                        backgroundImage: contact.photoUrl != null
                            ? CachedNetworkImageProvider(contact.photoUrl!)
                            : null,
                        child: contact.photoUrl == null
                            ? Text(
                          contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )
                            : null,
                      ),
                      title: Text(contact.name),
                      subtitle: Text(contact.email),
                      trailing: contact.isOnline
                          ? Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      )
                          : null,
                      onTap: () => _startConversation(
                        contact.id,
                        contact.name,
                        contact.photoUrl,
                        contact.email,
                        false,
                      ),
                    );
                  },
                );
              }

              return const SizedBox();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUsersListTab() {
    return Column(
      children: [
        _buildSearchBar(
          controller: _usersSearchController,
          focusNode: _usersSearchFocus,
          hintText: 'Search users...',
          onClear: () {
            _usersSearchController.clear();
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
        _buildSearchBar(
          controller: _blockedUsersSearchController,
          focusNode: _blockedUsersSearchFocus,
          hintText: 'Search blocked users...',
          onClear: () {
            _blockedUsersSearchController.clear();
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

  Widget _buildSearchBar({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: onClear,
              )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.grey, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppClr.primaryColor, width: 2.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUsersList(UsersListLoaded state) {
    if (state.users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.currentQuery.isNotEmpty ? Icons.search_off : Icons.person_add,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? 'No users found for "${state.currentQuery}"'
                  : 'No users found',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
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
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(user.name),
          subtitle: Text(user.email),
          trailing: IconButton(
            icon: Icon(Icons.message, color: AppClr.primaryColor),
            onPressed: () {
              _startConversation(user.id, user.name, "", user.email, false);
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
            const SizedBox(height: 16),
            Text(
              state.currentQuery.isNotEmpty
                  ? 'No blocked users found for "${state.currentQuery}"'
                  : 'No blocked users found',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
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
              _showUnblockDialog(user.name, user.id);
            },
            child: const Text('UNBLOCK', style: TextStyle(color: Colors.blue)),
          ),
        );
      },
    );
  }


  Future<void> _startConversation(
      int? userId,
      String userName,
      String? photoUrl,
      String email,
      bool isGroup,
      ) async {
    print('Starting conversation with $userName (ID: $userId)');

    final messageCubit = context.read<MessageCubit>();

    try {
      final resp = await messageCubit.sendChatRequestTo(userId.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (resp.success) {
        // Check if existing conversation was found
        final isExistingConversation = resp.message?.toLowerCase().contains('existing conversation') ?? false;

        if (isExistingConversation) {
          // Navigate to chat screen for existing conversation
          showCustomSnackBar(
            context,
            'Opening existing conversation...',
            type: SnackBarType.info,
          );

          // Navigate to chat screen
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => BlocProvider(
                create: (context) => ChatCubit(
                  chatRepository: ChatRepository(DioClient()),
                  socketService: SocketService(),
                ),
                child: ChatScreen(
                  userId: userId.toString(),
                  userName: userName,
                  userEmail: email,
                  userAvatar: photoUrl,
                  isGroup: isGroup,
                  groupData: null,
                  isOnline: false,
                ),
              ),
            ),
          ).then((_) {
            // Refresh conversations when returning
            try {
              context.read<ConversationCubit>().refresh();
            } catch (e) {
              print('Failed to refresh conversations: $e');
            }
          });
        } else {
          // New chat request sent
          showCustomSnackBar(
            context,
            resp.message ?? 'Chat request sent',
            type: SnackBarType.success,
          );
        }
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
      builder: (context) {
        bool isLoading = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Unblock User'),
              content: Text('Are you sure you want to unblock $username?'),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.pop(context),
                  child: const Text('CANCEL'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                    setState(() => isLoading = true);
                    try {
                      final currentUserId = context.read<MessageCubit>().userId;
                      final repo = UserRepository();
                      final success = await repo.blockUnblock(
                        currentUserId: currentUserId,
                        userId: userId,
                        isBlocked: false,
                      );
                      if (mounted) Navigator.pop(context);
                      if (success) {
                        showCustomSnackBar(
                          context,
                          '$username has been unblocked',
                          type: SnackBarType.success,
                        );

                        try {
                          context.read<MessageCubit>().loadBlockedUsers(refresh: true);
                        } catch (_) {}
                      } else {
                        showCustomSnackBar(
                          context,
                          'Failed to unblock $username. Please try again.',
                          type: SnackBarType.error,
                        );
                      }
                    } catch (e) {
                      if (mounted) Navigator.pop(context);
                      showCustomSnackBar(
                        context,
                        'Error while unblocking: ${e.toString()}',
                        type: SnackBarType.error,
                      );
                    }
                  },
                  child: isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('UNBLOCK', style: TextStyle(color: Colors.blue)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}