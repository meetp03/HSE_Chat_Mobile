# SeparateChat – Full Documentation

Version: 1.0.0
Platform: Flutter (Android + iOS)
Backend: React + TypeScript  
Notifications: Firebase Cloud Messaging (FCM Only)

📚 Table of Contents

- Introduction
- Features
- Folder Structure
- Requirements
- Installation Guide
- API Setup (React + TypeScript Backend)
- Firebase FCM Setup (Notifications Only)
- App Configuration (Frontend Setup)
- Changing App Name, Icon & Package Name
- Building APK / AAB
- FAQ
- Troubleshooting
- Credits & Support

1. 🚀 Introduction

SeparateChat is a clean, fully working Flutter Chat App UI + integration with your own API (React + TypeScript).
Firebase is used ONLY for sending push notifications, not for chat.

2. ⭐ Features

✔ Flutter-based chat UI

- One-to-one conversations
- Message send/receive
- Seen/Delivered indicators
- Online/offline status (from API)

✔ Backend (React + TypeScript)

- Authentication
- Chat API endpoints
- Message list / send message
- Notification token store
- Chat socket (optional)

✔ Firebase (Notifications Only)

- Foreground notifications
- Background notifications

✔ App-Level Features

- Clean architecture
- Secure API integration
- Error handling

3. 📂 Folder Structure

separatechat/
│── android/
│── ios/
│── lib/
│   ├── core/
│   ├── features/
│   ├── routes/
│   └── main.dart
│── images/
│── pubspec.yaml
│── README.md
│── Documentation.md

4. 📌 Requirements

For Flutter App

- Flutter 3.10 or above
- Android Studio / VS Code
- Dart SDK
- Firebase account (only FCM)

For Backend

- Node.js 18+
- React + TypeScript
- Express.js (optional)
- Database (MongoDB / PostgreSQL / MySQL)

5. 🛠 Installation Guide

5.1 Extract the Source Code

5.2 Install Dependencies

Run:

```bash
flutter pub get
```

5.3 Configure API Base URL

Edit the API base URL in your project. Example file:

`lib/core/api_urls.dart`

```text
class ApiUrls {
  static const baseUrl = "https://your-backend-domain.com/api";
}
```

Update `baseUrl` to point to your backend.

6. 🔌 API Setup (React + TypeScript Backend)

Your backend must provide the following endpoints and behavior. Adjust paths as needed to match the mobile app's expectations.

6.1 Authentication

- POST /auth/login
- 
6.2 Chat API

- GET /messages/:userId/conversations (or similar) — fetch conversation list
- POST /messages/:toId/conversations — fetch conversation messages (or GET /messages/:conversationId?page=1)
- POST /messages/send-message — send a message
- POST /messages/read-message — mark messages read

6.3 Store FCM Token

- POST /user/updatePushToken

Request payload example:

```text
{ "userId": 12, "fcmToken": "token_here" }
```

6.4 (Optional) WebSocket Events

If you use socket.io or a websocket server, the app expects the following events:

- join_room
- typing
- new_message
- messages_read
- message_deleted
- message_deleted_for_everyone

Event payloads should match what the mobile module expects — check the logging output in the app to verify exact fields.

7. 🔥 Firebase FCM Setup (Notifications Only)

7.1 Create Firebase Project

- Go to: https://console.firebase.google.com
- Create a new project
- Add Android App
- Download `google-services.json`
- Place in: `android/app/google-services.json`

7.2 Add iOS App

- Add iOS app in Firebase console
- Download `GoogleService-Info.plist`
- Place in: `ios/Runner/GoogleService-Info.plist`

7.3 Enable Cloud Messaging

- In Firebase console → Cloud Messaging → enable API

8. 📲 App Configuration (Frontend)

8.1 Initialize Firebase

In `lib/main.dart`, ensure Firebase is initialized. Example steps (pseudocode):

- Call WidgetsFlutterBinding.ensureInitialized() at the start of main().
- Initialize Firebase by calling Firebase.initializeApp().
- Register a background message handler via FirebaseMessaging (if used).

8.2 Register Device Token

Obtain the FCM token and send it to your backend. Example steps:

- Use FirebaseMessaging.instance.getToken() to get the device token.
- POST the token to your API endpoint `/user/updatePushToken` with a JSON payload containing the current user id and the token, for example: { "userId": 12, "fcmToken": "token_here" }.

8.3 Receive Message

Register listeners for incoming notifications:

- Listen for foreground messages and handle them (show local notification and/or update UI).
- Listen for notification taps (onMessageOpenedApp) and navigate to the chat screen if payload contains a conversation id.

9. 🎨 Change App Name, Icon & Package

9.1 Change App Name

Edit:

- `android/app/src/main/AndroidManifest.xml` — change `android:label`
- `ios/Runner/Info.plist` — change display name

9.2 Change Package Name

Run:

```bash
flutter pub run change_app_package_name:main com.your.newname
```

Or update manually in:

- `AndroidManifest.xml`
- `android/app/build.gradle`
- `MainActivity` files
- iOS Runner project (Bundle Identifier)

9.3 Change App Icon

Replace PNG files in `assets/icons/` and run:

```bash
flutter pub run flutter_launcher_icons:main
```

9.4 Change Images (Logos, etc.)

The app uses images for logos and other UI elements, defined in `lib/cores/constants/image_paths.dart`.

To change images:

1. Replace the image files in the `images/` folder with your new images.

2. Update the paths in `image_paths.dart` if the filenames change.

Example:

```dart
class AppImg {
  static const String _images = 'images/';
  static const String appLogo = '${_images}your_new_logo.png';
  static const String logoutLogo = '${_images}your_new_logout.png';
}
```

3. Ensure the images are declared in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - images/
```

This allows you to customize logos and other images easily.

10. 📦 Build APK / AAB

Debug APK

```bash
flutter build apk
```

Release APK

```bash
flutter build apk --release
```

For Play Store AAB

```bash
flutter build appbundle --release
```

12. 🔧 Troubleshooting

Issue — Solution

- FCM not working — Check API key, update token, enable Cloud Messaging
- API not reachable — Check base URL, CORS, HTTPS
- Messages not loading — Check pagination API
- App crashes on startup — Missing Firebase config file

