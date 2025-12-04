import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/utils/shared_preferences.dart';
import 'package:hec_chat/cores/utils/snackbar.dart';
import 'package:hec_chat/cores/utils/utils.dart';
import 'package:hec_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hec_chat/feature/home/bloc/user_info_cubit.dart';
import 'package:hec_chat/feature/home/bloc/user_info_state.dart';
import 'package:hec_chat/feature/home/bloc/contacts_cubit.dart';
import 'package:hec_chat/feature/home/bloc/contacts_state.dart';
import 'package:hec_chat/feature/home/model/chat_models.dart';
import 'package:hec_chat/feature/home/model/common_groups_response.dart';
import 'package:hec_chat/feature/home/repository/user_repository.dart';
import 'package:hec_chat/feature/home/repository/message_repository.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../../cores/network/dio_client.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? userEmail;
  final bool isIBlockedThem;
  final bool isTheyBlockedMe;
  final bool isGroup;
  final ChatGroup? groupData;

  const UserInfoScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.userEmail,
    required this.isIBlockedThem,
    required this.isTheyBlockedMe,
    this.isGroup = false,
    this.groupData,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  late bool _isIBlockedThem;
  late bool _isTheyBlockedMe;
  List<GroupModel> _commonGroups = [];
  late final UserInfoCubit _cubit;
  bool _isDeleting = false;
  ChatGroup? _currentGroupData;

  @override
  void initState() {
    super.initState();
    _isIBlockedThem = widget.isIBlockedThem;
    _isTheyBlockedMe = widget.isTheyBlockedMe;
    _currentGroupData = widget.groupData;
    _cubit = UserInfoCubit(UserRepository());
    _cubit.loadUserInfo(otherUserId: int.tryParse(widget.userId) ?? 0);
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        backgroundColor: AppClr.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions:
            widget.isGroup &&
                _currentGroupData != null &&
                _isCurrentUserAdmin(_currentGroupData!)
            ? [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: _showEditGroupDialog,
                ),
              ]
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildProfileSection(),
            const SizedBox(height: 24),
            if (widget.isGroup) ...[
              _buildGroupDetailSection(),
              const SizedBox(height: 24),
            ] else ...[
              _buildCommonGroupsSection(),
              const SizedBox(height: 24),
              _buildBlockSection(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    return SizedBox(
      width: double.infinity,
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppClr.primaryColor.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppClr.primaryColor.withValues(alpha: 0.1),
                backgroundImage: widget.userAvatar != null
                    ? CachedNetworkImageProvider(widget.userAvatar!)
                    : null,
                child: widget.userAvatar == null
                    ? Text(
                        Utils.getInitials(widget.userName),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppClr.primaryColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                widget.userName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppClr.primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonGroupsSection() {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<UserInfoCubit, UserInfoState>(
        builder: (context, state) {
          Widget body;
          if (state is UserInfoLoading) {
            body = const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          } else if (state is UserInfoError) {
            body = Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Error: ${state.message}'),
            );
          } else if (state is UserInfoLoaded) {
            _commonGroups = state.groups;
            if (_commonGroups.isEmpty) {
              body = const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No common groups',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            } else {
              body = Column(
                children: _commonGroups
                    .map((group) => _buildGroupItem(group))
                    .toList(),
              );
            }
          } else {
            body = const SizedBox.shrink();
          }

          return Card(
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: AppClr.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Common Groups',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppClr.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  body,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupItem(GroupModel group) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppClr.primaryColor.withValues(alpha: 0.1),
        child: group.image != null && group.image!.isNotEmpty
            ? ClipOval(
                child: CachedNetworkImage(
                  imageUrl: group.image!,
                  fit: BoxFit.cover,
                  width: 40,
                  height: 40,
                  errorWidget: (context, url, error) => Text(
                    Utils.getInitials(group.name),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppClr.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
            : Text(
                Utils.getInitials(group.name),
                style: TextStyle(
                  fontSize: 12,
                  color: AppClr.primaryColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
      title: Text(
        group.name,
        style: TextStyle(
          color: AppClr.primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text('${group.members} members'),
      onTap: () {},
    );
  }

  Widget _buildGroupDetailSection() {
    final grp = _currentGroupData;
    if (grp == null || grp.id.isEmpty) return const SizedBox.shrink();

    final groupId = grp.id;
    final members = grp.members;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Channel Information',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppClr.primaryColor,
              ),
            ),
            const SizedBox(height: 12),

            // Members Section
            Row(
              children: [
                Text(
                  'Members (${members.length})',
                  style: TextStyle(
                    color: AppClr.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (_isCurrentUserAdmin(grp)) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, color: Colors.green),
                    onPressed: _showAddMembersDialog,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),

            // Members List - using the typed ChatMember
            ...members.map((member) {
              final m = member;
              final isAdmin = (m.role == 1);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppClr.primaryColor.withAlpha(30),
                  backgroundImage: m.photoUrl != null && m.photoUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(m.photoUrl!)
                      : null,
                  child: m.photoUrl == null
                      ? Text(
                          Utils.getInitials(m.name),
                          style: TextStyle(
                            color: AppClr.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  m.name,
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: m.email != null && m.email!.isNotEmpty
                    ? Text(m.email!)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Role badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isAdmin ? Colors.orange : Colors.grey,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAdmin ? 'Admin' : 'Member',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // 3-dot menu for admin users (don't show for current user)
                    if (_isCurrentUserAdmin(grp)) ...[
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: AppClr.primaryColor,
                          size: 20,
                        ),
                        onSelected: (value) =>
                            _handleMemberMenuAction(value, m, grp),
                        itemBuilder: (BuildContext context) {
                          // Show different options based on member role
                          if (isAdmin) {
                            // For admin members: Dismiss as Admin and Remove Member
                            return [
                              PopupMenuItem<String>(
                                value: 'dismiss_admin',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.admin_panel_settings_outlined,
                                      size: 20,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Dismiss as Admin'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'remove_member',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_remove,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Remove Member',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ];
                          } else {
                            // For regular members: Make Admin and Remove Member
                            return [
                              PopupMenuItem<String>(
                                value: 'make_admin',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.admin_panel_settings,
                                      size: 20,
                                      color: Colors.green,
                                    ),
                                    const SizedBox(width: 8),
                                    Text('Make Admin'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<String>(
                                value: 'remove_member',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.person_remove,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Remove Member',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ];
                          }
                        },
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isDeleting
                    ? null
                    : () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Delete Channel'),
                            content: const Text(
                              'Are you sure you want to delete this channel? This action cannot be undone.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        if (groupId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invalid group id'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _isDeleting = true;
                        });
                        final otherUserId = int.tryParse(widget.userId) ?? 0;

                        try {
                          final ok = await _cubit.deleteGroup(
                            groupId: groupId,
                            otherUserId: otherUserId,
                          );

                          if (ok) {
                            final conversationCubit = context
                                .read<ConversationCubit>();

                            await conversationCubit.refresh();
                            await conversationCubit.refreshUnread();

                            if (mounted) {
                              showCustomSnackBar(
                                context,
                                'Channel deleted successfully',
                                type: SnackBarType.success,
                              );
                            }

                            if (mounted) {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            }
                          } else {
                            print('❌ Channel deletion returned false');
                            if (mounted) {
                              showCustomSnackBar(
                                context,
                                'Failed to delete channel',
                                type: SnackBarType.error,
                              );
                            }
                          }
                        } catch (e) {
                          print('❌ Error in delete channel: $e');
                          if (mounted) {
                            showCustomSnackBar(
                              context,
                              'Failed to delete channel',
                              type: SnackBarType.error,
                            );
                          }
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isDeleting = false;
                            });
                          }
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete Channel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockSection() {
    return Column(
      children: [
        // Card 1: Warning when they blocked you (conditionally shown)
        if (_isTheyBlockedMe) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: Colors.red.withAlpha((0.05 * 255).round()),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.block, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'You are blocked',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This user has blocked you. You cannot send messages to them.',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Card 2: Block/Unblock toggle (always shown)
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: AppClr.primaryColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Block User',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppClr.primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Block this user to stop receiving messages from them.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isIBlockedThem ? 'Blocked' : 'Not Blocked',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _isIBlockedThem
                            ? Colors.red
                            : AppClr.primaryColor,
                      ),
                    ),
                    Switch(
                      value: _isIBlockedThem,
                      onChanged: (value) async {
                        final otherUserId = int.tryParse(widget.userId) ?? 0;
                        try {
                          await _cubit.toggleBlock(
                            otherUserId: otherUserId,
                            block: value,
                          );

                          if (!mounted) return;

                          setState(() {
                            _isIBlockedThem = value;
                          });

                          // Refresh conversation list to reflect change
                          try {
                            final conv = context.read<ConversationCubit>();
                            await conv.refresh();
                            await conv.refreshUnread();
                          } catch (_) {}

                          if (mounted) {
                            showCustomSnackBar(
                              context,
                              value ? 'User blocked' : 'User unblocked',
                              type: SnackBarType.success,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            showCustomSnackBar(
                              context,
                              'Failed to ${value ? 'block' : 'unblock'} user',
                              type: SnackBarType.error,
                            );
                          }
                        }
                      },
                      activeThumbColor: Colors.red,
                      activeTrackColor: Colors.red.withAlpha(
                        (0.5 * 255).round(),
                      ),
                      inactiveThumbColor: AppClr.primaryColor,
                      inactiveTrackColor: AppClr.primaryColor.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Check if current user is admin of the group
  bool _isCurrentUserAdmin(ChatGroup group) {
    final currentUserId = SharedPreferencesHelper.getCurrentUserId();
    final currentMember = group.members.firstWhere(
      (member) => member.id == currentUserId,
      orElse: () => ChatMember(id: 0, name: '', role: 0),
    );
    return currentMember.role == 1;
  }

  // Check if the member is the current user
  bool _isCurrentUser(ChatMember member) {
    final currentUserId = SharedPreferencesHelper.getCurrentUserId();
    return member.id == currentUserId;
  }

  // Handle member menu actions
  void _handleMemberMenuAction(
    String action,
    ChatMember member,
    ChatGroup group,
  ) {
    switch (action) {
      case 'make_admin':
        _showMakeAdminConfirmation(member, group);
        break;
      case 'dismiss_admin':
        _showDismissAdminConfirmation(member, group);
        break;
      case 'remove_member':
        _showRemoveMemberConfirmation(member, group);
        break;
    }
  }

  void _showMakeAdminConfirmation(ChatMember member, ChatGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Make Admin'),
        content: Text('Are you sure you want to make ${member.name} an admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _makeAdmin(member, group);
            },
            child: const Text(
              'Make Admin',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  void _showDismissAdminConfirmation(ChatMember member, ChatGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dismiss as Admin'),
        content: Text(
          'Are you sure you want to dismiss ${member.name} as admin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _dismissAsAdmin(member, group);
            },
            child: const Text(
              'Dismiss',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveMemberConfirmation(ChatMember member, ChatGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text(
          'Are you sure you want to remove ${member.name} from this channel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _removeMember(member, group);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _makeAdmin(ChatMember member, ChatGroup group) {
    // Call cubit to make admin
    final memberId = member.id ?? 0;
    final groupId = group.id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    _cubit
        .makeAdmin(groupId: groupId, memberId: memberId)
        .then((ok) {
          Navigator.of(context).pop();
          if (ok) {
            // Update local member role
            setState(() {
              final idx = group.members.indexWhere((m) => m.id == member.id);
              if (idx >= 0) {
                group.members[idx] = ChatMember(
                  id: member.id,
                  name: member.name,
                  email: member.email,
                  photoUrl: member.photoUrl,
                  role: 1,
                );
              }
            });
            showCustomSnackBar(
              context,
              '${member.name} is now an admin',
              type: SnackBarType.success,
            );
          } else {
            showCustomSnackBar(
              context,
              'Failed to make ${member.name} admin',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(context, 'Error: $e', type: SnackBarType.error);
        });
  }

  void _dismissAsAdmin(ChatMember member, ChatGroup group) {
    final memberId = member.id ?? 0;
    final groupId = group.id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    _cubit
        .dismissAdmin(groupId: groupId, memberId: memberId)
        .then((ok) {
          Navigator.of(context).pop();
          if (ok) {
            setState(() {
              final idx = group.members.indexWhere((m) => m.id == member.id);
              if (idx >= 0)
                group.members[idx] = ChatMember(
                  id: member.id,
                  name: member.name,
                  email: member.email,
                  photoUrl: member.photoUrl,
                  role: 0,
                );
            });
            showCustomSnackBar(
              context,
              '${member.name} dismissed as admin',
              type: SnackBarType.success,
            );
          } else {
            showCustomSnackBar(
              context,
              'Failed to dismiss ${member.name}',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(context, 'Error: $e', type: SnackBarType.error);
        });
  }

  void _removeMember(ChatMember member, ChatGroup group) {
    final memberId = member.id ?? 0;
    final groupId = group.id;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    _cubit
        .removeMember(groupId: groupId, memberId: memberId)
        .then((ok) async {
          Navigator.of(context).pop();
          if (ok) {
            // Update local member list
            setState(() {
              group.members.removeWhere((m) => m.id == member.id);
            });

            showCustomSnackBar(
              context,
              '${member.name} removed from channel',
              type: SnackBarType.success,
            );

            // Refresh conversations and unread counts on home screen
            try {
              final conversationCubit = context.read<ConversationCubit>();
              await conversationCubit.refresh();
              await conversationCubit.refreshUnread();
            } catch (e) {
              // ignore errors here but log if needed
              print(
                '⚠️ Failed to refresh conversations after removeMember: $e',
              );
            }

            // Navigate back to home (first route)
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } else {
            showCustomSnackBar(
              context,
              'Failed to remove ${member.name}',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(context, 'Error: $e', type: SnackBarType.error);
        });
  }

  void _showEditGroupDialog() {
    final group = _currentGroupData;
    if (group == null) return;

    final nameController = TextEditingController(text: group.name);
    final descriptionController = TextEditingController(
      text: group.description ?? '',
    );
    File? selectedImage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image picker
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final pickedFile = await picker.pickImage(
                      source: ImageSource.gallery,
                    );
                    if (pickedFile != null) {
                      setState(() {
                        selectedImage = File(pickedFile.path);
                      });
                    }
                  },
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppClr.primaryColor.withValues(alpha: 0.1),
                    backgroundImage: selectedImage != null
                        ? FileImage(selectedImage!)
                        : (group.photoUrl != null && group.photoUrl!.isNotEmpty
                              ? CachedNetworkImageProvider(group.photoUrl!)
                              : null),
                    child:
                        selectedImage == null &&
                            (group.photoUrl == null || group.photoUrl!.isEmpty)
                        ? Icon(Icons.camera_alt, color: AppClr.primaryColor)
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Group Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final description = descriptionController.text.trim();

                if (name.isEmpty) {
                  showCustomSnackBar(
                    context,
                    'Group name cannot be empty',
                    type: SnackBarType.error,
                  );
                  return;
                }

                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  final updatedGroup = await _cubit.updateGroup(
                    groupId: group.id,
                    name: name,
                    description: description,
                    photo: selectedImage,
                  );

                  Navigator.of(context).pop(); // Close loading
                  Navigator.of(ctx).pop(); // Close dialog

                  if (updatedGroup != null) {
                    showCustomSnackBar(
                      context,
                      'Group updated successfully',
                      type: SnackBarType.success,
                    );
                    // Update local group data with server response
                    setState(() {
                      _currentGroupData = updatedGroup;
                    });
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                    // Refresh conversations to update group data in list
                    try {
                      final conversationCubit = context
                          .read<ConversationCubit>();
                      await conversationCubit.refresh();
                      await conversationCubit.refreshUnread();
                    } catch (e) {
                      print('Failed to refresh conversations: $e');
                    }
                  } else {
                    showCustomSnackBar(
                      context,
                      'Failed to update group',
                      type: SnackBarType.error,
                    );
                  }
                } catch (e) {
                  Navigator.of(context).pop(); // Close loading
                  Navigator.of(ctx).pop(); // Close dialog
                  showCustomSnackBar(
                    context,
                    'Error updating group: $e',
                    type: SnackBarType.error,
                  );
                }
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMembersDialog() {
    final group = _currentGroupData;
    if (group == null) return;

    final selectedMembers = <int>{};

    showDialog(
      context: context,
      builder: (ctx) => BlocProvider(
        create: (_) =>
            MessageCubit(repository: MessageRepository(DioClient()))
              ..loadMyContacts(refresh: true),

        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Add Members'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (query) {
                        context.read<MessageCubit>().searchContacts(query);
                      },
                    ),
                  ),
                  // Contacts List
                  Expanded(
                    child: BlocBuilder<MessageCubit, MessageState>(
                      builder: (context, state) {
                        if (state is MyContactsLoading) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (state is MyContactsError) {
                          return Center(child: Text('Error: ${state.message}'));
                        } else if (state is MyContactsLoaded) {
                          final contacts = state.contacts.where((contact) {
                            // Exclude members already in the group
                            return !group.members.any(
                              (member) => member.id == contact.id,
                            );
                          }).toList();

                          if (contacts.isEmpty) {
                            return const Center(
                              child: Text('No contacts available to add'),
                            );
                          }

                          return ListView.builder(
                            itemCount: contacts.length,
                            itemBuilder: (context, index) {
                              final contact = contacts[index];
                              final isSelected = selectedMembers.contains(
                                contact.id,
                              );

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      selectedMembers.add(contact.id);
                                    } else {
                                      selectedMembers.remove(contact.id);
                                    }
                                  });
                                },
                                title: Text(contact.name),
                                subtitle: Text(contact.email),
                                secondary: CircleAvatar(
                                  backgroundColor: AppClr.primaryColor
                                      .withAlpha(25),
                                  backgroundImage: contact.photoUrl != null
                                      ? CachedNetworkImageProvider(
                                          contact.photoUrl!,
                                        )
                                      : null,
                                  child: contact.photoUrl == null
                                      ? Text(
                                          contact.name.substring(0, 1),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            },
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedMembers.isEmpty
                    ? null
                    : () async {
                        // Show loading
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) =>
                              const Center(child: CircularProgressIndicator()),
                        );

                        try {
                          final success = await _cubit.addMembers(
                            groupId: group.id,
                            memberIds: selectedMembers.toList(),
                          );

                          Navigator.of(context).pop(); // Close loading
                          Navigator.of(ctx).pop(); // Close dialog

                          if (success) {
                            showCustomSnackBar(
                              context,
                              'Members added successfully',
                              type: SnackBarType.success,
                            );
                            Navigator.of(context).pop();
                            Navigator.of(context).pop();
                            Navigator.of(context).pop();
                            // Refresh conversations
                            try {
                              final conversationCubit = context
                                  .read<ConversationCubit>();
                              await conversationCubit.refresh();
                              await conversationCubit.refreshUnread();
                            } catch (e) {
                              print('Failed to refresh conversations: $e');
                            }
                          } else {
                            showCustomSnackBar(
                              context,
                              'Failed to add members',
                              type: SnackBarType.error,
                            );
                          }
                        } catch (e) {
                          Navigator.of(context).pop(); // Close loading
                          Navigator.of(ctx).pop(); // Close dialog
                          showCustomSnackBar(
                            context,
                            'Error adding members: $e',
                            type: SnackBarType.error,
                          );
                        }
                      },
                child: Text('Add Selected Members (${selectedMembers.length})'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
