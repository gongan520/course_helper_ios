import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  int _nextId = 0;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true
    );
    await _plugin.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    _initialized = true;
  }

  Future<void> show({
    required String title,
    required String body,
    String? payload,
    String? threadId,
    required AndroidNotificationDetails androidDetails,
  }) async {
    await initialize();

    // threadId 用于区分不同账号的通知：
    // iOS 上映射为 threadIdentifier，Android 上映射为 groupKey。
    // 相同 threadId 的通知会归为一组，不同 threadId 的通知则分开显示，
    // 从而保证「登几个账号就弹几条签到通知」，不被系统合并。
    final darwinDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      threadIdentifier: threadId,
    );

    await _plugin.show(
      id: _nextId++,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
      ),
    );
  }
}
