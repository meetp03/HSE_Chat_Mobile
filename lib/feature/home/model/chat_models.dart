// chat_models.dart
// Typed models for chat API user/group payloads used in info screens and cubits.

class ChatUser {
  final int? id;
  final String? name;
  final String? email;
  final String? photoUrl;
  final bool? isBlockedByAuthUser;
  final bool? isBlocked;

  ChatUser({
    this.id,
    this.name,
    this.email,
    this.photoUrl,
    this.isBlockedByAuthUser,
    this.isBlocked,
  });

  factory ChatUser.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ChatUser();
    return ChatUser(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id'] ?? ''}'),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      isBlockedByAuthUser: json['is_blocked_by_auth_user'] == true,
      isBlocked: json['is_blocked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photo_url': photoUrl,
        'is_blocked_by_auth_user': isBlockedByAuthUser,
        'is_blocked': isBlocked,
      };
}

class ChatMember {
  final int? id;
  final String name;
  final String? email;
  final String? photoUrl;
  final int role; // pivot.role

  ChatMember({
    this.id,
    required this.name,
    this.email,
    this.photoUrl,
    this.role = 0,
  });

  factory ChatMember.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ChatMember(name: 'Unknown');
    final pivot = json['pivot'] as Map<String, dynamic>?;
    return ChatMember(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id'] ?? ''}'),
      name: json['name']?.toString() ?? 'Unknown',
      email: json['email']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      role: pivot != null ? (pivot['role'] is int ? pivot['role'] : int.tryParse('${pivot['role'] ?? 0}') ?? 0) : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photo_url': photoUrl,
        'role': role,
      };
}

class ChatGroup {
  final String id;
  final String name;
  final String? description;
  final String? photoUrl;
  final int privacy;
  final int groupType;
  final int? createdBy;
  final List<ChatMember> members;

  ChatGroup({
    required this.id,
    required this.name,
    this.description,
    this.photoUrl,
    this.privacy = 0,
    this.groupType = 0,
    this.createdBy,
    this.members = const [],
  });

  factory ChatGroup.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ChatGroup(id: '', name: '');
    final users = json['users'] as List<dynamic>? ?? json['members'] as List<dynamic>? ?? [];
    return ChatGroup(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Group',
      description: json['description']?.toString(),
      photoUrl: json['photo_url']?.toString(),
      privacy: json['privacy'] is int ? json['privacy'] : int.tryParse('${json['privacy'] ?? 0}') ?? 0,
      groupType: json['group_type'] is int ? json['group_type'] : int.tryParse('${json['group_type'] ?? 0}') ?? 0,
      createdBy: json['created_by'] is int ? json['created_by'] : int.tryParse('${json['created_by'] ?? ''}'),
      members: users.map((u) => ChatMember.fromJson(u as Map<String, dynamic>?)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'photo_url': photoUrl,
        'privacy': privacy,
        'group_type': groupType,
        'created_by': createdBy,
        'members': members.map((m) => m.toJson()).toList(),
      };
}
