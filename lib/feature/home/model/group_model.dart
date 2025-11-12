// models/group_model.dart
class CreateGroupRequest {
  final String name;
  final List<int> members;
  final String description;
  final String? photoUrl;

  CreateGroupRequest({
    required this.name,
    required this.members,
    this.description = '',
    this.photoUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'members': members,
      'description': description,
      'photo_url': photoUrl,
    };
  }
}

class GroupMember {
  final int id;
  final String name;

  GroupMember({
    required this.id,
    required this.name,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      name: json['name'],
    );
  }
}

class Group {
  final String id;
  final String name;
  final String description;
  final String? photoUrl;
  final int privacy;
  final int groupType;
  final int createdBy;
  final String createdAt;
  final String updatedAt;
  final List<GroupMember> members;

  Group({
    required this.id,
    required this.name,
    required this.description,
    this.photoUrl,
    required this.privacy,
    required this.groupType,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.members,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'],
      name: json['name'],
      description: json['description'] ?? '',
      photoUrl: json['photo_url'],
      privacy: json['privacy'],
      groupType: json['group_type'],
      createdBy: json['created_by'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      members: (json['members'] as List)
          .map((member) => GroupMember.fromJson(member))
          .toList(),
    );
  }
}

class CreateGroupResponse {
  final bool success;
  final Group group;

  CreateGroupResponse({
    required this.success,
    required this.group,
  });

  factory CreateGroupResponse.fromJson(Map<String, dynamic> json) {
    return CreateGroupResponse(
      success: json['success'],
      group: Group.fromJson(json['group']),
    );
  }
}