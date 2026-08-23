import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Set when initialisation fails for good (a missing icon resource, a plugin
  /// registration problem). Notifications are a courtesy here -- a task must
  /// still run and report through the UI when they are unavailable -- so every
  /// entry point below turns into a no-op rather than rethrowing on each call.
  bool _unavailable = false;
  bool? _notificationsAllowed;
  int _nextNotificationId = 1000;

  Future<void> init() async {
    if (_initialized || _unavailable) return;

    // Android renders the status-bar icon as a flat silhouette from the alpha
    // channel alone, so the full-colour launcher icon would show up there as a
    // solid white blob. ic_notification is an alpha-only version of the same
    // artwork, padded to leave the margin the status bar expects.
    //
    // The bare resource name, not '@drawable/ic_notification': the plugin feeds
    // this straight to Resources.getIdentifier with "drawable" as the default
    // type, and the qualified form fails that lookup even though the resource
    // is in the APK -- which is the invalid_icon PlatformException.
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    try {
      await _notificationsPlugin.initialize(initializationSettings);
      _initialized = true;
    } catch (e) {
      _unavailable = true;
      developer.log('Notification init failed, continuing without them: $e');
    }
  }

  Future<bool> requestPermission() async {
    if (!_initialized) await init();
    if (_unavailable) return false;
    if (_notificationsAllowed != null) return _notificationsAllowed!;

    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestNotificationsPermission();
    _notificationsAllowed = granted ?? true;
    return _notificationsAllowed!;
  }

  Future<void> showTaskCompleteNotification(String title, String body) async {
    if (!_initialized) await init();
    if (_unavailable) return;
    if (!await requestPermission()) return;

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'task_completion_channel',
          'Task Completions',
          channelDescription: 'Notifications for when a task completes',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          category: AndroidNotificationCategory.status,
          styleInformation: BigTextStyleInformation(body),
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      _nextNotificationId++,
      title,
      body,
      platformChannelSpecifics,
    );
  }
}
