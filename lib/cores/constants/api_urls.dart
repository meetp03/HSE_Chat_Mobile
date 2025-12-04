class ApiUrls {
  // base url for login - CHANGE THIS TO YOUR BACKEND URL
  static const String baseUrlForLogin =
      'https://mock-api.example.com/api/login'; // Mock login URL
  // main base url - CHANGE THIS TO YOUR BACKEND URL
  static const String baseUrl = 'https://mock-api.example.com'; // Mock base URL
  // conversation URLs
  static const String conversations =
      '$baseUrl/api/messages/conversations-list';
  static const String unreadConversations =
      '$baseUrl/api/messages/conversations-unread';

  // Message Tab URLs
  static const String myContacts = '$baseUrl/api/core/users/get-my-contacts';
  static const String usersList = '$baseUrl/api/core/users/users-list';
  static const String blockedUsers = '$baseUrl/api/core/users/blocked-users';
  static const String createGroup = '$baseUrl/api/messages/group/create';
  static const String commonGroup = '$baseUrl/api/messages/groups/common';
  static const String groupBase = '$baseUrl/api/messages/groups';
  static const String blockUnblockUsers = '$baseUrl/api/core/users';
  static const String getNotification =
      '$baseUrl/api/notifications/get-notifications';
  static const String markAllNotificationsRead =
      '$baseUrl/api/notifications/mark-all-read';
  // Chat URLs
  static const String sendMessage = '$baseUrl/api/messages/send-message';
  static const String readMessage = '$baseUrl/api/messages/read-message';
  static const String sendChatRequest =
      '$baseUrl/api/messages/send-chat-request';
}
