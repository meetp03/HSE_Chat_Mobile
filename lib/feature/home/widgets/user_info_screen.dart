import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';
import 'package:hsc_chat/cores/network/socket_service.dart';
import 'package:hsc_chat/cores/utils/snackbar.dart';
import 'package:hsc_chat/cores/utils/utils.dart';
import 'package:hsc_chat/feature/home/bloc/conversation_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/user_info_cubit.dart';
import 'package:hsc_chat/feature/home/bloc/user_info_state.dart';
import 'package:hsc_chat/feature/home/model/common_groups_response.dart';
import 'package:hsc_chat/feature/home/repository/user_repository.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? userEmail;
  final bool isIBlockedThem;
  final bool isTheyBlockedMe;
  final bool isGroup;
  final Map<String, dynamic>? groupData;

  const UserInfoScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.userEmail,
    required this.isIBlockedThem,
    required this.isTheyBlockedMe,
    this.isGroup = false,
    this.groupData,
  }) : super(key: key);

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  late bool _isIBlockedThem;
  late bool _isTheyBlockedMe;
  List<dynamic> _commonGroups = [];
  late final UserInfoCubit _cubit;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _isIBlockedThem = widget.isIBlockedThem;
    print('🔒 Initial isIBlockedThem: $_isIBlockedThem');
    _isTheyBlockedMe = widget.isTheyBlockedMe;
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
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppClr.primaryColor,
                ),
              ),
              if (!widget.isGroup && widget.userEmail != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.userEmail!,
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'User ID: ${widget.userId}',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
      onTap: () {
        // TODO: Navigate to group chat
      },
    );
  }

  Widget _buildGroupDetailSection() {
    final raw = widget.groupData;
    if (raw == null) {
      print('❌ No group data provided');
      return const SizedBox.shrink();
    }

    print('🔍 Raw group data type: ${raw.runtimeType}');
    print('🔍 Raw group data: $raw');

    // Handle both Map and Conversation types
    Map<String, dynamic>? groupMap;
    groupMap = raw;
    print('✅ Using raw Map directly');

    // Extract data using the actual field names from your debug output
    final groupId = groupMap['id']?.toString() ?? '';
    final groupName = groupMap['name']?.toString() ?? 'Unnamed Group';
    final groupPhotoUrl = groupMap['photo_url']?.toString() ?? '';
    final groupDescription = groupMap['description']?.toString() ?? '';
    final members = groupMap['members'] as List<dynamic>? ?? [];

    print('📍 Group ID: $groupId');
    print('📍 Group Name: $groupName');
    print('📍 Group Photo: $groupPhotoUrl');
    print('📍 Group Description: $groupDescription');
    print('📍 Group members count: ${members.length}');
    print('📍 Group members: ${members.map((m) => m['name']).toList()}');

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Channel Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppClr.primaryColor,
              ),
            ),
            const SizedBox(height: 12),

            // Group Photo
            if (groupPhotoUrl.isNotEmpty)
              Center(
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: groupPhotoUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppClr.primaryColor.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.group, color: AppClr.primaryColor),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Group Name
            Text(
              groupName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),

            // Group Description
            if (groupDescription.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                groupDescription,
                style: const TextStyle(color: Colors.grey),
              ),
            ],

            const SizedBox(height: 16),

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
              ],
            ),
            const SizedBox(height: 12),

            // Members List - using the actual member structure from your debug output
            ...members.map((member) {
              final memberMap = member as Map<String, dynamic>;
              final memberName = memberMap['name']?.toString() ?? 'Unknown';
              final memberEmail = memberMap['email']?.toString() ?? '';
              final memberAvatarUrl = memberMap['photo_url']?.toString();
              final memberRole = memberMap['role'] ?? 0;
              final isGroupAdmin = memberRole == 1;
print(memberMap['role']);
               return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundColor: AppClr.primaryColor.withAlpha(30),
                  backgroundImage:
                      memberAvatarUrl != null && memberAvatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(memberAvatarUrl)
                      : null,
                  child: memberAvatarUrl == null
                      ? Text(
                          Utils.getInitials(memberName),
                          style: TextStyle(
                            color: AppClr.primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                title: Text(
                  memberName,
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: memberEmail.isNotEmpty ? Text(memberEmail) : null,
                trailing: memberRole.isNotEmpty
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isGroupAdmin ? Colors.orange : Colors.grey,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          isGroupAdmin ? 'Admin' : 'Member',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
              );
            }),

            const SizedBox(height: 16),

            // Delete Button (only show if user is admin/owner)
            /*
            ElevatedButton.icon(
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Channel deleted'),
                              backgroundColor: Colors.green,
                            ),
                          );
                          Navigator.of(
                            context,
                          ).pop(); // Close user info after deletion
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Failed to delete channel'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error deleting channel: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
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
*/
            ElevatedButton.icon(
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
            color: Colors.red.withOpacity(0.05),
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
                      activeColor: Colors.red,
                      activeTrackColor: Colors.red.withOpacity(0.5),
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
}
