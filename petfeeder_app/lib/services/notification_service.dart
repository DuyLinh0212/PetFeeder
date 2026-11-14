import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const _enabledKey = 'push_notifications_enabled';
  static const _installationIdKey = 'push_installation_id';
  static const _fidKey = 'push_firebase_installation_id';
  static const _channelId = 'petfeeder_alerts';
  static const _channelName = 'Cảnh báo máy cho ăn';
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _registrationSubscription;
  FirebaseMessaging? _messaging;
  bool _initialized = false;
  bool _initializing = false;
  bool _configured = false;

  bool get supportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool get _hasDartOptions =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  bool get configured => _configured;

  Future<void> initialize() async {
    if (_initialized || _initializing || !supportedPlatform) {
      return;
    }
    _initializing = true;
    try {
      if (Firebase.apps.isEmpty) {
        if (_hasDartOptions) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: _apiKey,
              appId: _appId,
              messagingSenderId: _senderId,
              projectId: _projectId,
            ),
          );
        } else if (defaultTargetPlatform == TargetPlatform.android) {
          // Android reads the app options generated from google-services.json.
          await Firebase.initializeApp();
        } else {
          return;
        }
      }

      _messaging = FirebaseMessaging.instance;
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              _channelName,
              description: 'Thông báo trạng thái và cảnh báo từ thiết bị.',
              importance: Importance.high,
            ),
          );
      await _messaging!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        _showForegroundMessage,
      );
      _registrationSubscription = _messaging!.onRegistered.listen((fid) async {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool(_enabledKey) == true) {
          try {
            await prefs.setString(_fidKey, fid);
            await _register(fid);
          } catch (error) {
            debugPrint('PetFeeder: không cập nhật được mã cài đặt FCM: $error');
          }
        }
      });
      _initialized = true;
      _configured = true;

      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_enabledKey) == true) {
        final fid = prefs.getString(_fidKey);
        if (fid != null && fid.isNotEmpty) await _register(fid);
        await _messaging!.register();
      }
    } catch (error) {
      debugPrint('PetFeeder: không khởi tạo được thông báo đẩy: $error');
    } finally {
      _initializing = false;
    }
  }

  Future<bool> isEnabled() async {
    if (!_initialized || _messaging == null) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) != true) return false;
    final settings = await _messaging!.getNotificationSettings();
    final permitted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!permitted) await prefs.setBool(_enabledKey, false);
    return permitted;
  }

  Future<bool> requestPermissionAndEnable() async {
    if (!supportedPlatform) {
      throw StateError('Thông báo đẩy hiện hỗ trợ Android và iOS.');
    }
    if (!configured || !_initialized || _messaging == null) {
      throw StateError(
        'App chưa được cấu hình Firebase. Xem docs/FCM_NOTIFICATIONS.md.',
      );
    }

    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final permitted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!permitted) {
      throw StateError('Bạn chưa cho phép PetFeeder gửi thông báo.');
    }

    final registeredFid = _messaging!.onRegistered.first.timeout(
      const Duration(seconds: 15),
      onTimeout: () =>
          throw StateError('Firebase chưa cấp mã cài đặt cho App.'),
    );
    await _messaging!.register();
    final fid = await registeredFid;
    final pushReady = await _register(fid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fidKey, fid);
    await prefs.setBool(_enabledKey, true);
    return pushReady;
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    final messaging = _messaging;
    if (messaging == null) return;
    final fid = prefs.getString(_fidKey);
    try {
      if (fid != null && fid.isNotEmpty) await _unregister(fid);
    } catch (error) {
      debugPrint('PetFeeder: không gỡ được đăng ký thông báo: $error');
    } finally {
      try {
        await messaging.unregister();
      } catch (error) {
        debugPrint('PetFeeder: không hủy được đăng ký Firebase: $error');
      }
      await prefs.remove(_fidKey);
    }
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_installationIdKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final value = base64UrlEncode(bytes).replaceAll('=', '');
    await prefs.setString(_installationIdKey, value);
    return value;
  }

  Future<bool> _register(String fid) async =>
      ApiService().registerNotificationFid(
        fid: fid,
        installationId: await _installationId(),
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      );

  Future<void> _unregister(String fid) async =>
      ApiService().unregisterNotificationFid(
        fid: fid,
        installationId: await _installationId(),
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      );

  Future<void> _showForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) != true) return;
    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? 'PetFeeder',
      body: notification.body ?? '',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Thông báo trạng thái và cảnh báo từ thiết bị.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> dispose() async {
    await _messageSubscription?.cancel();
    await _registrationSubscription?.cancel();
  }
}
