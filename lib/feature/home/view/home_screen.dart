import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/network/dio_client.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/shared_preferences.dart';
import 'package:hsc_chat/cores/utils/utils.dart';
import 'package:hsc_chat/feature/home/bloc/chat_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_state.dart';
import 'package:hsc_chat/feature/home/bloc/group_cubit.dart';
import 'package:hsc_chat/feature/home/model/conversation_model.dart';
import 'package:hsc_chat/feature/home/repository/chat_repository.dart';
import 'package:hsc_chat/feature/home/repository/message_repository.dart';
import 'package:hsc_chat/feature/home/view/chat_screen.dart';
import 'package:hsc_chat/feature/home/widgets/contacts_screen.dart';
import 'package:hsc_chat/feature/home/widgets/user_selection_screen.dart';
import 'package:hsc_chat/routes/navigation_service.dart';
import 'package:hsc_chat/routes/routes.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Separate search controllers for each tab
  final TextEditingController _allChatsSearchController =
      TextEditingController();
  final TextEditingController _unreadChatsSearchController =
      TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final ScrollController _unreadScrollController = ScrollController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounce;

  // Get current search controller based on active tab
  TextEditingController get _currentSearchController {
    return _tabController.index == 0
        ? _allChatsSearchController
        : _unreadChatsSearchController;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // Rebuild to show correct search controller
      // When switching to Unread tab, load unread conversations lazily if not loaded
      if (_tabController.index == 1) {
        final cubit = context.read<ConversationCubit>();
        if (cubit.unreadChats.isEmpty) {
          cubit.loadUnreadConversations();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = SharedPreferencesHelper.getCurrentUserToken();
      context.read<ConversationCubit>().initializeSocketConnection(token);
      // Only load all conversations initially; unread will be loaded when user switches to that tab
      context.read<ConversationCubit>().loadConversations();
    });

    _scrollController.addListener(_onScroll);
    _unreadScrollController.addListener(_onUnreadScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<ConversationCubit>().loadMore();
    }
  }

  void _onUnreadScroll() {
    if (_unreadScrollController.position.pixels >=
        _unreadScrollController.position.maxScrollExtent - 200) {
      context.read<ConversationCubit>().loadMoreUnread();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _allChatsSearchController.dispose();
    _unreadChatsSearchController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _unreadScrollController
      ..removeListener(_onUnreadScroll)
      ..dispose();
    _searchFocusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () {
      if (_tabController.index == 0) {
        context.read<ConversationCubit>().search(query.trim());
      } else {
        context.read<ConversationCubit>().searchUnread(query.trim());
      }
    });
  }

  void _clearSearch() {
    final currentController = _currentSearchController;
    currentController.clear();

    if (_tabController.index == 0) {
      context.read<ConversationCubit>().clearSearch();
    } else {
      context.read<ConversationCubit>().clearUnreadSearch();
    }

    _searchFocusNode.unfocus();
    setState(() {}); // Rebuild to hide close icon
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performLogout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _performLogout() async {
    context.read<ConversationCubit>().reset();
    await SharedPreferencesHelper.clear();
    SocketService().disconnect();
    if (!mounted) return;
    NavigationService.pushNamedAndRemoveUntil(RouteNames.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxScrolled) => [
          SliverAppBar(
            backgroundColor: AppClr.primaryColor,
            pinned: true,
            floating: false,
            elevation: 0,
            title: Row(
              children: [
                const Text(
                  'Conversations',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SocketService().isConnected
                        ? Colors.green
                        : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            actions: [
              // Notification Icon Button
              IconButton(
                icon: const Icon(Icons.notifications, color: Colors.white),
                onPressed: () {
                  // Add notification functionality here
                },
              ),

              /*   // Message Icon Button
              IconButton(
                icon: const Icon(Icons.message, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MessageScreen(),
                    ),
                  );
                },
              ),*/

              // Plus Icon Button
              IconButton(
                icon: const Icon(Icons.group_add_outlined, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BlocProvider(
                        create: (context) =>
                            GroupCubit(MessageRepository(DioClient())),
                        child: const UserSelectionScreen(),
                      ),
                    ),
                  ).then((_) {
                    // Refresh conversations when returning from group creation
                    context.read<ConversationCubit>().refresh();
                  });
                },
              ),
              // Existing Popup Menu Button
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (value) {
                  if (value == 'logout') {
                    _showLogoutDialog();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Logout'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(child: _buildSearchBar()),

          SliverToBoxAdapter(
            child: BlocBuilder<ConversationCubit, ConversationState>(
              builder: (context, state) {
                // Determine active tab and use cubit's getters as authoritative source for counts
                final activeTab = _tabController.index;

                final count = activeTab == 0
                    ? (context.read<ConversationCubit>().currentQuery.isNotEmpty
                          ? context
                                .read<ConversationCubit>()
                                .filteredAllChats
                                .length
                          : context.read<ConversationCubit>().allChats.length)
                    : (context.read<ConversationCubit>().unreadQuery.isNotEmpty
                          ? context
                                .read<ConversationCubit>()
                                .filteredUnreadChats
                                .length
                          : context
                                .read<ConversationCubit>()
                                .unreadChats
                                .length);

                final isSearching = activeTab == 0
                    ? context.read<ConversationCubit>().currentQuery.isNotEmpty
                    : context.read<ConversationCubit>().unreadQuery.isNotEmpty;

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Spacer(),
                      if (isSearching)
                        Text(
                          '$count results',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      else if (activeTab == 1 &&
                          context
                              .read<ConversationCubit>()
                              .unreadChats
                              .isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppClr.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${context.read<ConversationCubit>().unreadChats.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTabBarDelegate(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey[600],
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  indicator: BoxDecoration(
                    color: AppClr.primaryColor,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'All Chats'),
                    Tab(text: 'Unread Chats'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: BlocBuilder<ConversationCubit, ConversationState>(
          builder: (context, state) {
            final cubit = context.read<ConversationCubit>();

            Widget buildAllTab() {
              if (state is ConversationLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ConversationError) {
                return Center(child: Text('Error: ${state.message}'));
              }

              final isSearching = cubit.currentQuery.isNotEmpty;
              final chats = isSearching
                  ? cubit.filteredAllChats
                  : cubit.allChats;
              return _buildChatList(
                chats,
                cubit.hasMoreConversations,
                cubit.isLoadingMoreConversations,
                isSearching,
                controller: _scrollController,
              );
            }

            Widget buildUnreadTab() {
              if (state is ConversationLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (state is ConversationError) {
                return Center(child: Text('Error: ${(state).message}'));
              }

              final isSearching = cubit.unreadQuery.isNotEmpty;
              final chats = isSearching
                  ? cubit.filteredUnreadChats
                  : cubit.unreadChats;
              return _buildChatList(
                chats,
                cubit.hasMoreUnread,
                cubit.isLoadingMoreUnread,
                isSearching,
                controller: _unreadScrollController,
              );
            }

            return TabBarView(
              controller: _tabController,
              children: [buildAllTab(), buildUnreadTab()],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppClr.primaryColor,
        child: const Icon(Icons.chat, color: Colors.white),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MessageScreen()),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    final currentController = _currentSearchController;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: Colors.white,
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(25),
        ),
        child: TextField(
          controller: currentController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),

            // Show close icon ONLY when there's text in the current controller
            suffixIcon: currentController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close, color: Colors.black),
                    onPressed: _clearSearch,
                  )
                : null,

            hintText: 'Search conversations...',
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
            border: InputBorder.none,
          ),
          onChanged: (value) {
            _onSearchChanged(value);
            setState(() {}); // Rebuild to show/hide close icon
          },
        ),
      ),
    );
  }

  Widget _buildChatList(
    List<Conversation> chats,
    bool hasMore,
    bool isLoadingMore,
    bool isSearching, {
    required ScrollController controller,
  }) {
    if (chats.isEmpty) {
      // Searching: show 'No results found' immediately
      if (isSearching) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'No results found',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ],
          ),
        );
      }

      // Default (All Chats or unread not requested): if pagination is in-progress show loader
      if (hasMore || isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              isSearching ? 'No results found' : 'No conversations yet',
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    // Local debounce flag to avoid firing loadMore multiple times during one overscroll
    bool _canCall = true;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        try {
          final metrics = notification.metrics;
          // Use extentAfter which is the remaining scrollable content below
          if (metrics.extentAfter <= 200) {
            if (!isLoadingMore && hasMore && _canCall) {
              _canCall = false;
              Future.delayed(
                const Duration(milliseconds: 300),
                () => _canCall = true,
              );
              if (controller == _scrollController) {
                context.read<ConversationCubit>().loadMore();
              } else if (controller == _unreadScrollController) {
                context.read<ConversationCubit>().loadMoreUnread();
              } else {
                context.read<ConversationCubit>().loadMore();
                context.read<ConversationCubit>().loadMoreUnread();
              }
            }
          }
        } catch (e) {
          // ignore
        }
        return false;
      },
      child: ListView.builder(
        key: PageStorageKey(
          controller == _scrollController
              ? 'all_chats_list'
              : 'unread_chats_list',
        ),
        controller: controller,
        padding: EdgeInsets.zero,
        primary: false,
        physics: const ClampingScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // Always include a footer row when we have items so we can show either
        // a loading spinner (if loading more) or a 'No more conversations' note
        // when pagination finished.
        itemCount: chats.length + 1,
        itemBuilder: (context, index) {
          if (index == chats.length) {
            // Footer
            if (isLoadingMore || hasMore) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No more conversations',
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
              ),
            );
          }
          return _buildChatItem(chats[index]);
        },
      ),
    );
  }

  Widget _buildChatItem(Conversation conv) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        radius: 25,
        // Subtle tint using primary color with low opacity
        backgroundColor: AppClr.primaryColor.withAlpha(25),
        backgroundImage: conv.avatarUrl != null
            ? CachedNetworkImageProvider(conv.avatarUrl!)
            : null,
        child: conv.avatarUrl == null
            ? Text(
                Utils.getInitials(conv.title),
                style: TextStyle(
                  color: AppClr.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              )
            : null,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conv.title,
              style: TextStyle(
                fontWeight: conv.isUnread ? FontWeight.w600 : FontWeight.w500,
                fontSize: 16,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conv.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppClr.primaryColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                conv.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            conv.lastMessage.isNotEmpty ? conv.lastMessage : 'No messages',
            style: TextStyle(
              color: conv.isUnread ? Colors.black87 : Colors.grey[600],
              fontWeight: conv.isUnread ? FontWeight.w500 : FontWeight.normal,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              // if (conv.isGroup) ...[
              //   Icon(Icons.group, size: 14, color: Colors.grey[600]),
              //   const SizedBox(width: 6),
              //   Text(
              //     '${conv.participants?.length ?? 0} members',
              //     style: const TextStyle(color: Colors.grey, fontSize: 12),
              //   ),
              //   const SizedBox(width: 12),
              // ],
              Text(
                conv.formattedTime,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),

      onTap: () {
        print('🎯 Opening chat: ${conv.title}');
        print('📝 Conversation ID: ${conv.id}');
        print('👥 Is Group: ${conv.isGroup}');
        print('🆔 Group ID: ${conv.groupId}');
        print('👤 User ID: ${conv.id}');

        final chatId = conv.groupId;

        if (chatId!.isEmpty) {
          print('❌ Error: Invalid chat ID');
          showCustomSnackBar(
            context,
            'Cannot open chat: Invalid ID',
            type: SnackBarType.error,
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BlocProvider(
              create: (context) => ChatCubit(
                chatRepository: ChatRepository(DioClient()),
                socketService: SocketService(),
              ),
              child: ChatScreen(
                userId: conv.id,
                userName: conv.title,
                userEmail: conv.email,
                userAvatar: conv.avatarUrl,
                isGroup: conv.isGroup,
                groupData: conv,

              ),
            ),
          ),
        ).then((result) {
          // If ChatScreen returned a payload (latest message), update
          // ConversationCubit locally without calling the API.
          if (result != null) {
            try {
              context.read<ConversationCubit>().processRawMessage(result);
            } catch (e) {
              print('⚠️ Failed to process returned message: $e');
            }
          }
        });
      },
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyTabBarDelegate({required this.child});

  @override
  double get minExtent => 50;
  @override
  double get maxExtent => 50;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: Colors.white, child: child);
  }

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return false;
  }
}
