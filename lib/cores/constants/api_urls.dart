class ApiUrls {
  // TODO  : set these to your backend API base URL(s).
  // Example: const String baseUrl = 'https://api.yourdomain.com';
  static const String baseUrl = 'https://YOUR_API_BASE_URL';
  // Optional separate login endpoint (if your backend uses a different domain/path)
  static const String baseUrlForLogin =
      'https://YOUR_LOGIN_BASE_URL_OR_SAME_AS_BASEURL';

  // Endpoints (built from baseUrl). Buyers: change `baseUrl` above to point to your server.
  static const String conversations =
      '${baseUrl}/api/messages/conversations-list';
  static const String unreadConversations =
      '${baseUrl}/api/messages/conversations-unread';

  // Message Tab URLs
  static const String myContacts = '${baseUrl}/api/core/users/get-my-contacts';
  static const String usersList = '${baseUrl}/api/core/users/users-list';
  static const String blockedUsers = '${baseUrl}/api/core/users/blocked-users';
  static const String createGroup = '${baseUrl}/api/messages/group/create';
  static const String commonGroup = '${baseUrl}/api/messages/groups/common';
  static const String groupBase = '${baseUrl}/api/messages/groups';
  static const String blockUnblockUsers = '${baseUrl}/api/core/users';
  static const String getNotification =
      '${baseUrl}/api/notifications/get-notifications';
  static const String markAllNotificationsRead =
      '${baseUrl}/api/notifications/mark-all-read';

  // Chat URLs
  static const String sendMessage = '${baseUrl}/api/messages/send-message';
  static const String readMessage = '${baseUrl}/api/messages/read-message';
  static const String sendChatRequest =
      '${baseUrl}/api/messages/send-chat-request';
}
