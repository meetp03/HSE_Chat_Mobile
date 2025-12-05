import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hec_chat/cores/constants/app_colors.dart';
import 'package:hec_chat/cores/constants/app_strings.dart';
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
        title: const Text(AppStrings.about),
        backgroundColor: AppClr.primaryColor,
        foregroundColor: AppClr.white,
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
          side: BorderSide(color: AppClr.primaryColor.withOpacity(0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CircleAvatar(
                radius: 50,
                backgroundColor: AppClr.primaryColor.withOpacity(0.1),
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
              child: Text('${AppStrings.error}: ${state.message}'),
            );
          } else if (state is UserInfoLoaded) {
            _commonGroups = state.groups;
            if (_commonGroups.isEmpty) {
              body = const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  AppStrings.noCommonGroups,
                  style: TextStyle(
                    color: AppClr.grey,
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
              side: BorderSide(color: AppClr.primaryColor.withOpacity(0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.commonGroups,
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
        backgroundColor: AppClr.primaryColor.withOpacity(0.1),
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
      subtitle: Text('${group.members} ${AppStrings.members}'),
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
              AppStrings.channelInformation,
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
                  '${AppStrings.members} (${members.length})',
                  style: TextStyle(
                    color: AppClr.primaryColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (_isCurrentUserAdmin(grp)) ...[
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add, color: AppClr.successGreen),
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
                        color: isAdmin ? AppClr.adminBadge : AppClr.memberBadge,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAdmin ? AppStrings.admin : AppStrings.member,
                        style: const TextStyle(
                          color: AppClr.white,
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
                                      color: AppClr.adminDismissIcon,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(AppStrings.dismissAsAdmin),
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
                                      color: AppClr.errorRed,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppStrings.removeMember,
                                      style: TextStyle(color: AppClr.errorRed),
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
                                      color: AppClr.makeAdminIcon,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(AppStrings.makeAdmin),
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
                                      color: AppClr.errorRed,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      AppStrings.removeMember,
                                      style: TextStyle(color: AppClr.errorRed),
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
                            title: const Text(AppStrings.deleteChannel),
                            content: const Text(
                              AppStrings.deleteChannelConfirm,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text(AppStrings.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text(
                                  AppStrings.delete,
                                  style: TextStyle(color: AppClr.errorRed),
                                ),
                              ),
                            ],
                          ),
                        );

                        if (confirm != true) return;

                        if (groupId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(AppStrings.invalidGroupId),
                              backgroundColor: AppClr.errorRed,
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
                                AppStrings.channelDeletedSuccessfully,
                                type: SnackBarType.success,
                              );
                            }

                            if (mounted) {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            }
                          } else {
                            if (kDebugMode) {
                              print('Channel deletion returned false');
                            }
                            if (mounted) {
                              showCustomSnackBar(
                                context,
                                AppStrings.failedToDeleteChannel,
                                type: SnackBarType.error,
                              );
                            }
                          }
                        } catch (e) {
                          if (kDebugMode) {
                            print('Error in delete channel: $e');
                          }
                          if (mounted) {
                            showCustomSnackBar(
                              context,
                              AppStrings.failedToDeleteChannel,
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
                label: const Text(AppStrings.deleteChannel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppClr.errorRed,
                  foregroundColor: AppClr.white,
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
        // Warning when they blocked you (conditionally shown)
        if (_isTheyBlockedMe) ...[
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: AppClr.blockedWarningBackground,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.block, color: AppClr.errorRed, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.youAreBlocked,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppClr.errorRed,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppStrings.blockedUserMessage,
                          style: TextStyle(color: AppClr.grey600, fontSize: 13),
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

        // Block/Unblock toggle (always shown)
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          color: AppClr.blockSectionBackground,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.blockUser,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppClr.primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.blockUserDescription,
                  style: TextStyle(color: AppClr.grey600),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isIBlockedThem
                          ? AppStrings.blocked
                          : AppStrings.notBlocked,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _isIBlockedThem
                            ? AppClr.errorRed
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
                              value
                                  ? AppStrings.userBlocked
                                  : AppStrings.userUnblocked,
                              type: SnackBarType.success,
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            showCustomSnackBar(
                              context,
                              '${AppStrings.failedTo} ${value ? AppStrings.block : AppStrings.unblock} ${AppStrings.user}',
                              type: SnackBarType.error,
                            );
                          }
                        }
                      },
                      activeThumbColor: AppClr.errorRed,
                      activeTrackColor: AppClr.switchActiveTrack,
                      inactiveThumbColor: AppClr.primaryColor,
                      inactiveTrackColor: AppClr.switchInactiveTrack,
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
        title: const Text(AppStrings.makeAdmin),
        content: Text(
          '${AppStrings.makeAdminConfirm} ${member.name} ${AppStrings.anAdminQuestion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _makeAdmin(member, group);
            },
            child: Text(
              AppStrings.makeAdmin,
              style: const TextStyle(color: AppClr.successGreen),
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
        title: const Text(AppStrings.dismissAsAdmin),
        content: Text(
          '${AppStrings.dismissAsAdminConfirm} ${member.name} ${AppStrings.asAdminQuestion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _dismissAsAdmin(member, group);
            },
            child: Text(
              AppStrings.dismiss,
              style: const TextStyle(color: AppClr.adminDismissIcon),
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
        title: const Text(AppStrings.removeMember),
        content: Text(
          '${AppStrings.removeMemberConfirm} ${member.name} ${AppStrings.fromThisChannelQuestion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _removeMember(member, group);
            },
            child: Text(
              AppStrings.remove,
              style: const TextStyle(color: AppClr.errorRed),
            ),
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
              '${member.name} ${AppStrings.isNowAnAdmin}',
              type: SnackBarType.success,
            );
          } else {
            showCustomSnackBar(
              context,
              '${AppStrings.failedToMake} ${member.name} ${AppStrings.adminLowercase}',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(
            context,
            '${AppStrings.error}: $e',
            type: SnackBarType.error,
          );
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
              if (idx >= 0) {
                group.members[idx] = ChatMember(
                  id: member.id,
                  name: member.name,
                  email: member.email,
                  photoUrl: member.photoUrl,
                  role: 0,
                );
              }
            });
            showCustomSnackBar(
              context,
              '${member.name} ${AppStrings.dismissedAsAdmin}',
              type: SnackBarType.success,
            );
          } else {
            showCustomSnackBar(
              context,
              '${AppStrings.failedToDismiss} ${member.name}',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(
            context,
            '${AppStrings.error}: $e',
            type: SnackBarType.error,
          );
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
              '${member.name} ${AppStrings.removedFromChannel}',
              type: SnackBarType.success,
            );

            // Refresh conversations and unread counts on home screen
            try {
              final conversationCubit = context.read<ConversationCubit>();
              await conversationCubit.refresh();
              await conversationCubit.refreshUnread();
            } catch (e) {
              if (kDebugMode) {
                print(
                  '⚠️ Failed to refresh conversations after removeMember: $e',
                );
              }
            }

            // Navigate back to home (first route)
            if (mounted) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          } else {
            showCustomSnackBar(
              context,
              '${AppStrings.failedToRemove} ${member.name}',
              type: SnackBarType.error,
            );
          }
        })
        .catchError((e) {
          Navigator.of(context).pop();
          showCustomSnackBar(
            context,
            '${AppStrings.error}: $e',
            type: SnackBarType.error,
          );
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
          title: const Text(AppStrings.editGroup),
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
                    backgroundColor: AppClr.primaryColor.withOpacity(0.1),
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
                    labelText: AppStrings.groupName,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.groupDescription,
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
              child: const Text(AppStrings.cancel),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final description = descriptionController.text.trim();

                if (name.isEmpty) {
                  showCustomSnackBar(
                    context,
                    AppStrings.groupNameCannotBeEmpty,
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
                      AppStrings.groupUpdatedSuccessfully,
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
                      if (kDebugMode) {
                        print('Failed to refresh conversations: $e');
                      }
                    }
                  } else {
                    showCustomSnackBar(
                      context,
                      AppStrings.failedToUpdateGroup,
                      type: SnackBarType.error,
                    );
                  }
                } catch (e) {
                  Navigator.of(context).pop(); // Close loading
                  Navigator.of(ctx).pop(); // Close dialog
                  showCustomSnackBar(
                    context,
                    '${AppStrings.errorUpdatingGroup}: $e',
                    type: SnackBarType.error,
                  );
                }
              },
              child: const Text(AppStrings.saveChanges),
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
            title: const Text(AppStrings.addMembers),
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
                        hintText: AppStrings.searchContacts,
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
                          return Center(
                            child: Text(
                              '${AppStrings.error}: ${state.message}',
                            ),
                          );
                        } else if (state is MyContactsLoaded) {
                          final contacts = state.contacts.where((contact) {
                            // Exclude members already in the group
                            return !group.members.any(
                              (member) => member.id == contact.id,
                            );
                          }).toList();

                          if (contacts.isEmpty) {
                            return const Center(
                              child: Text(AppStrings.noContactsAvailableToAdd),
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
                child: const Text(AppStrings.cancel),
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
                              AppStrings.membersAddedSuccessfully,
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
                              if (kDebugMode) {
                                print('Failed to refresh conversations: $e');
                              }
                            }
                          } else {
                            showCustomSnackBar(
                              context,
                              AppStrings.failedToAddMembers,
                              type: SnackBarType.error,
                            );
                          }
                        } catch (e) {
                          Navigator.of(context).pop(); // Close loading
                          Navigator.of(ctx).pop(); // Close dialog
                          showCustomSnackBar(
                            context,
                            '${AppStrings.errorAddingMembers}: $e',
                            type: SnackBarType.error,
                          );
                        }
                      },
                child: Text(
                  '${AppStrings.addSelectedMembers} (${selectedMembers.length})',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
