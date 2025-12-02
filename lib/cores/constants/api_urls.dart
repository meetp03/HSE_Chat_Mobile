class ApiUrls {
  static const String baseUrlForLogin =
      'https://hecdev.sonomainfotech.in/api/login';
  static const String baseUrl = 'https://hecdev-apichat.sonomainfotech.in/api/';

  static const String conversations = '${baseUrl}messages/conversations-list';
  static const String unreadConversations =
      '${baseUrl}messages/conversations-unread';

  // Message Tab URLs
  static const String myContacts = '${baseUrl}core/users/get-my-contacts';
  static const String usersList = '${baseUrl}core/users/users-list';
  static const String blockedUsers = '${baseUrl}core/users/blocked-users';
  static const String createGroup = '${baseUrl}messages/group/create';
  static const String commonGroup = '${baseUrl}messages/groups/common';
  static const String groupBase = '${baseUrl}messages/groups';
  static const String blockUnblockUsers = '${baseUrl}core/users';
  static const String getNotification = '${baseUrl}notifications/get-notifications';
  static const String markAllNotificationsRead = '${baseUrl}notifications/mark-all-read';
  // Chat URLs
  static const String sendMessage = '${baseUrl}messages/send-message';
  static const String readMessage = '${baseUrl}messages/read-message';
  static const String sendChatRequest = '${baseUrl}messages/send-chat-request';
}
