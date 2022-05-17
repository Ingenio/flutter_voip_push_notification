import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Message handler for incoming notification
///
/// [isLocal] is true if this is a notification from a message scheduled locally
/// or false if its a remote voip push notification
/// [message] contains the notification payload see link below for how to parse this data
/// https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CreatingtheNotificationPayload.html#//apple_ref/doc/uid/TP40008194-CH10-SW1
typedef Future<dynamic> MessageHandler(bool isLocal, Map<String, dynamic> notification);

class NotificationSettings {
  const NotificationSettings({
    this.sound = true,
    this.alert = true,
    this.badge = true,
  });

  NotificationSettings._fromMap(Map<String, bool> settings)
      : sound = settings['sound'] ?? false,
        alert = settings['alert'] ?? false,
        badge = settings['badge'] ?? false;

  final bool sound;
  final bool alert;
  final bool badge;

  @visibleForTesting
  Map<String, dynamic> toMap() {
    return <String, bool>{'sound': sound, 'alert': alert, 'badge': badge};
  }

  @override
  String toString() => 'PushNotificationSettings ${toMap()}';
}

class LocalNotification {
  const LocalNotification({
    required this.alertBody,
    required this.alertAction,
    this.soundName,
    this.category,
    this.userInfo,
  });

  /// The message displayed in the notification alert.
  final String alertBody;

  /// The [action] displayed beneath an actionable notification. Defaults to "view";
  final String alertAction;

  /// The sound played when the notification is fired (optional).
  final String? soundName;

  /// The category of this notification, required for actionable notifications (optional).
  final String? category;

  /// An optional object containing additional notification data.
  final Map<String, dynamic>? userInfo;

  @visibleForTesting
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'alertBody': alertBody,
      'alertAction': alertAction,
      'soundName': soundName,
      'category': category,
      'userInfo': userInfo
    };
  }

  @override
  String toString() => 'LocalNotification ${toMap()}';
}

class FlutterVoipPushNotification {
  factory FlutterVoipPushNotification() => _instance;

  @visibleForTesting
  FlutterVoipPushNotification.private(MethodChannel channel) : _channel = channel {
    print('[FlutterVoipPushNotificationPlugin] constructor on Dart side ${getFormmatedTime()}');
  }

  static final FlutterVoipPushNotification _instance =
      FlutterVoipPushNotification.private(const MethodChannel('com.peerwaya/flutter_voip_push_notification'));

  static const _messageChannelName = 'flutter.ingenio.com/on_message';
  static const _resumeChannelName = 'flutter.ingenio.com/on_resume';

  static final _messageChannelStream = const EventChannel(_messageChannelName).receiveBroadcastStream();
  static final _resumeChannelStream = const EventChannel(_resumeChannelName).receiveBroadcastStream();

  final MethodChannel _channel;
  late String _token;

  final StreamController<String> _tokenStreamController = StreamController<String>.broadcast();

  /// Fires when a new device token is generated.
  Stream<String> get onTokenRefresh {
    return _tokenStreamController.stream;
  }

  /// Sets up [MessageHandler] for incoming messages.
  void configure() {
    print('[FlutterVoipPushNotificationPlugin] configure on Dart side ${getFormmatedTime()}');
    _channel.setMethodCallHandler(_handleMethod);
    _channel.invokeMethod<void>('configure');
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    final Map map = call.arguments.cast<String, dynamic>();
    switch (call.method) {
      case "onToken":
        _token = map["deviceToken"];
        _tokenStreamController.add(_token);
        return null;
      default:
        throw UnsupportedError("Unrecognized JSON message");
    }
  }

  Stream<Map<String, dynamic>> get onMessageReceived {
    return _messageChannelStream.map((dynamic event) => _parseEvent(event));
  }

  Stream<Map<String, dynamic>> get onResumeReceived {
    return _resumeChannelStream.map((dynamic event) => _parseEvent(event));
  }

  Map<String, dynamic> _parseEvent(Map message) {
    print('[FlutterVoipPushNotificationPlugin] _parseEvent on Dart side ${getFormmatedTime()}');
    return message.cast<String, dynamic>();
  }

  /// Returns the locally cached push token
  Future<String?> getToken() async {
    return await _channel.invokeMethod<String>('getToken');
  }

  String getFormmatedTime() {
    DateTime now = DateTime.now();
    final DateFormat formatter = DateFormat('HH:mm:ss.SSS');
    return formatter.format(now);
  }

  /// Prompts the user for notification permissions the first time
  /// it is called.
  Future<void> requestNotificationPermissions([NotificationSettings iosSettings = const NotificationSettings()]) async {
    _channel.invokeMethod<void>('requestNotificationPermissions', iosSettings.toMap());
  }

  /// Schedules the local [notification] for immediate presentation.
  Future<void> presentLocalNotification(LocalNotification notification) async {
    await _channel.invokeMethod<void>('presentLocalNotification', notification.toMap());
  }
}
