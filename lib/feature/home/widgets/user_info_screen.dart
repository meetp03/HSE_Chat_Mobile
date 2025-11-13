import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hsc_chat/cores/constants/app_colors.dart';

class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? userEmail;
  final bool isBlocked;

  const UserInfoScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.userEmail,
    required this.isBlocked,
  }) : super(key: key);

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  late bool _isBlocked;
  List<Map<String, dynamic>> _commonGroups = [];

  @override
  void initState() {
    super.initState();
    _isBlocked = widget.isBlocked;
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _commonGroups = [
        {
          'id': '1',
          'name': 'Flutter Developers',
          'members': 15,
          'image': null,
        },
        {
          'id': '2',
          'name': 'Project Team',
          'members': 8,
          'image': null,
        },
      ];
    });
  }

  Future<void> _toggleBlockStatus() async {
    try {
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() {
        _isBlocked = !_isBlocked;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBlocked
                ? '${widget.userName} has been blocked'
                : '${widget.userName} has been unblocked',
          ),
          backgroundColor:
          _isBlocked ? Colors.red : AppClr.primaryColor,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update block status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About User'),
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
            _buildCommonGroupsSection(),
            const SizedBox(height: 24),
            _buildBlockSection(),
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
                  _getInitials(widget.userName),
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
              if (widget.userEmail != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.userEmail!,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'User ID: ${widget.userId}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommonGroupsSection() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppClr.primaryColor.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            if (_commonGroups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No common groups',
                  style: TextStyle(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              )
            else
              Column(
                children: _commonGroups
                    .map((group) => _buildGroupItem(group))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupItem(Map<String, dynamic> group) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: AppClr.primaryColor.withOpacity(0.1),
        child: group['image'] != null
            ? ClipOval(
          child: CachedNetworkImage(
            imageUrl: group['image']!,
            fit: BoxFit.cover,
            width: 40,
            height: 40,
          ),
        )
            : Text(
          _getInitials(group['name']),
          style: TextStyle(
            fontSize: 12,
            color: AppClr.primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      title: Text(
        group['name'],
        style: TextStyle(
          color: AppClr.primaryColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text('${group['members']} members'),
      onTap: () {
        // TODO: Navigate to group chat
      },
    );
  }

  Widget _buildBlockSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),

      ),
      color: _isBlocked
          ? Colors.red.withOpacity(0.05)
          : AppClr.primaryColor.withOpacity(0.05),
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
              _isBlocked
                  ? 'You have blocked this user. They cannot send you messages.'
                  : 'Block this user to stop receiving messages from them.',
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isBlocked ? 'Blocked' : 'Not Blocked',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: _isBlocked ? Colors.red : AppClr.primaryColor,
                  ),
                ),
                Switch(
                  value: _isBlocked,
                  onChanged: (value) => _toggleBlockStatus(),
                  activeColor: Colors.red,
                  inactiveTrackColor:
                  AppClr.primaryColor.withOpacity(0.4),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    return name.isNotEmpty
        ? name.trim().split(' ').map((l) => l[0]).take(2).join().toUpperCase()
        : '';
  }
}
