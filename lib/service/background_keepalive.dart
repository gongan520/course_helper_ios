import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/logger.dart';

/// iOS 后台保活服务。
///
/// 原理：通过 MethodChannel 调用原生 CoreLocation 的后台定位
/// （`allowsBackgroundLocationUpdates = true`），让 iOS 允许 App 在后台
/// 持续运行，从而保证签到轮询 Timer 和雨课堂 WebSocket 在后台不被冻结。
///
/// 仅在 iOS 上生效；Android 端无需此机制（有前台服务）。
class BackgroundKeepAlive {
  BackgroundKeepAlive._internal();
  static final BackgroundKeepAlive _instance = BackgroundKeepAlive._internal();
  factory BackgroundKeepAlive() => _instance;

  static const _channel = MethodChannel('com.gongan520.coursehelper/keepalive');

  bool _started = false;

  /// 启动后台保活（幂等，重复调用无副作用）。
  Future<void> start() async {
    if (_started) return;
    if (!Platform.isIOS) return; // 仅 iOS 需要后台定位保活

    try {
      await _channel.invokeMethod('startBackgroundLocation');
      _started = true;
      logger.i('后台定位保活已启动');
    } on PlatformException catch (e) {
      logger.e('后台定位保活启动失败: ${e.message}');
    } catch (e) {
      logger.e('后台定位保活异常: $e');
    }
  }
}
