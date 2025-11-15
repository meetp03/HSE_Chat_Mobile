// common_groups_response.dart
class CommonGroupsResponse {
  final bool success;
  final String message;
  final List<GroupModel> groups;

  CommonGroupsResponse({
    required this.success,
    required this.message,
    required this.groups,
  });

  factory CommonGroupsResponse.fromJson(Map<String, dynamic> json) {
    return CommonGroupsResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      groups: json['groups'] != null
          ? List<GroupModel>.from(
          json['groups'].map((x) => GroupModel.fromJson(x)))
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'groups': List<dynamic>.from(groups.map((x) => x.toJson())),
  };
}// group_model.dart
class GroupModel {
  final String id;
  final String name;
  final String? description;
  final String? image;
  final String? photoUrl;
  final int members;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  GroupModel({
    required this.id,
    required this.name,
    this.description,
    this.image,
    this.photoUrl,
    required this.members,
    this.createdAt,
    this.updatedAt,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unnamed Group',
      description: json['description']?.toString(),
      image: json['image']?.toString(),
      photoUrl: json['photo_url']?.toString() ?? json['image']?.toString(),
      members: _parseMembersCount(json['members']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'])
          : null,
    );
  }

  static int _parseMembersCount(dynamic members) {
    if (members is int) return members;
    if (members is String) return int.tryParse(members) ?? 0;
    if (members is List) return members.length;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'image': image,
    'photo_url': photoUrl,
    'members': members,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}// base_response.dart
class BaseResponse {
  final bool success;
  final String message;
  final dynamic data;

  BaseResponse({
    required this.success,
    required this.message,
    this.data,
  });

  factory BaseResponse.fromJson(Map<String, dynamic> json) {
    return BaseResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'message': message,
    'data': data,
  };
}