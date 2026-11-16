import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import '../utils/storage.dart';

/// iOS 灵动岛（Live Activity）服务。
///
/// 通过 MethodChannel 调用原生 ActivityKit，在灵动岛 / 锁屏「实时活动」上
/// 显示签到状态。仅在 iOS 16.1+ 生效；其余环境静默降级。
///
/// 用法：
///   - [show]     启动/显示灵动岛（托管开始时）
///   - [update]   更新状态（签到成功/失败时）
///   - [hide]     结束灵动岛（托管关闭时）
///
/// 开关状态通过 [loadEnabled] 从本地读取，[setEnabled] 修改并持久化。
class LiveActivity {
  LiveActivity._internal();
  static final LiveActivity _instance = LiveActivity._internal();
  factory LiveActivity() => _instance;

  static const _channel = MethodChannel('com.gongan520.coursehelper/liveactivity');
  static const _enabledKey = 'live_activity_enabled';

  /// 是否启用灵动岛（由设置项控制）。
  bool _enabled = false;

  bool get isEnabled => _enabled;

  /// 从本地加载开关状态。
  Future<void> loadEnabled() async {
    try {
      _enabled = StorageManager.prefs.getBool(_enabledKey) ?? false;
    } catch (e) {
      _enabled = false;
    }
  }

  /// 修改开关并持久化。
  Future<void> setEnabled(bool v) async {
    _enabled = v;
    try {
      await StorageManager.prefs.setBool(_enabledKey, v);
    } catch (e) {
      logger.w('灵动岛开关保存失败: $e');
    }
    if (!v) {
      // 关闭时立即结束灵动岛
      await hide();
    }
  }

  /// 启动灵动岛。
  Future<void> show({
    required String statusText,
    String signedAccounts = '',
    int hostingCount = 0,
  }) async {
    if (!_enabled) return;
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('start', {
        'statusText': statusText,
        'signedAccounts': signedAccounts,
        'hostingCount': hostingCount,
      });
      logger.i('灵动岛已启动: $statusText');
    } catch (e) {
      logger.w('灵动岛启动失败: $e');
    }
  }

  /// 更新灵动岛状态。
  Future<void> update({
    required String statusText,
    String signedAccounts = '',
    int hostingCount = 0,
  }) async {
    if (!_enabled) return;
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('update', {
        'statusText': statusText,
        'signedAccounts': signedAccounts,
        'hostingCount': hostingCount,
      });
    } catch (e) {
      logger.w('灵动岛更新失败: $e');
    }
  }

  /// 结束灵动岛。
  Future<void> hide() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      logger.w('灵动岛结束失败: $e');
    }
  }
}

