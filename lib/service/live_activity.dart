import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/logger.dart';
import '../utils/storage.dart';

/// 心情（与 iOS 侧 `mood` 字段一致）。
class PetMood {
  /// 平时：托管中但没在签到
  static const idle = 'idle';

  /// 刚签到成功
  static const happy = 'happy';

  /// 正在轮询/处理
  static const busy = 'busy';

  /// 已停止
  static const sleep = 'sleep';
}

/// 灵动岛上展示的账号统计。
///
/// 锁屏卡片会显示成「托管 N / 定时 N / 手动 N / AI 答题 N」四个小胶囊。
class LiveActivityStats {
  /// 托管（全自动）模式账号数
  final int autoCount;

  /// 定时模式账号数
  final int scheduledCount;

  /// 手动模式账号数
  final int manualCount;

  /// 已开启 AI 答题的账号数
  final int aiCount;

  const LiveActivityStats({
    this.autoCount = 0,
    this.scheduledCount = 0,
    this.manualCount = 0,
    this.aiCount = 0,
  });

  static const empty = LiveActivityStats();
}

/// iOS 灵动岛（Live Activity）服务。
///
/// 通过 MethodChannel 调用原生 ActivityKit，在灵动岛 / 锁屏「实时活动」上
/// 显示「蜡笔小新遛狗」的动画，用来表示 App 正在后台运行；点击即可回到 App。
///
/// 仅在 iOS 16.1+ 生效；其余环境静默降级。
///
/// 用法：
///   - [initialize] 注册回调（App 启动时调用一次）
///   - [show]       启动/显示（托管开始时）
///   - [update]     更新状态（签到成功/失败时）
///   - [hide]       结束（托管关闭时）
///   - [status]     查询原生侧状态（用于设置页诊断）
class LiveActivity {
  LiveActivity._internal();
  static final LiveActivity _instance = LiveActivity._internal();
  factory LiveActivity() => _instance;

  static const _channel = MethodChannel('com.gongan520.coursehelper/liveactivity');
  static const _enabledKey = 'live_activity_enabled';

  /// 是否启用灵动岛（由设置项控制）。
  bool _enabled = false;

  bool get isEnabled => _enabled;

  /// 最近一次原生返回的状态（systemEnabled / activityCount / state / lastError）。
  Map<String, dynamic>? _lastStatus;
  Map<String, dynamic>? get lastStatus => _lastStatus;

  /// 是否由「点击灵动岛」拉起的。
  bool _openedFromLiveActivity = false;
  bool get openedFromLiveActivity => _openedFromLiveActivity;

  /// 注册原生回调（只注册一次）。
  Future<void> initialize() async {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openedFromLiveActivity') {
        _openedFromLiveActivity = true;
        logger.i('从灵动岛进入 App');
        return null;
      }
      return null;
    });
  }

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

  /// 启动（或复用）灵动岛。
  Future<Map<String, dynamic>?> show({
    String statusText = '蜡笔小新正在守护你的课堂',
    String signedAccounts = '',
    LiveActivityStats stats = LiveActivityStats.empty,
    String mood = PetMood.idle,
    int signedCount = 0,
  }) async {
    if (!_enabled) return null;
    return _invoke('start', statusText, signedAccounts, stats, mood, signedCount);
  }

  /// 更新灵动岛状态；活动丢失时原生侧会自动重建。
  Future<Map<String, dynamic>?> update({
    String statusText = '蜡笔小新正在守护你的课堂',
    String signedAccounts = '',
    LiveActivityStats stats = LiveActivityStats.empty,
    String mood = PetMood.idle,
    int signedCount = 0,
  }) async {
    if (!_enabled) return null;
    return _invoke('update', statusText, signedAccounts, stats, mood, signedCount);
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

  /// 查询原生侧状态，用于设置页展示「为什么不显示」。
  Future<Map<String, dynamic>?> status() async {
    if (!Platform.isIOS) return null;
    try {
      final raw = await _channel.invokeMethod<Map>('status');
      final map = raw?.cast<String, dynamic>();
      _lastStatus = map;
      return map;
    } catch (e) {
      logger.w('灵动岛状态查询失败: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _invoke(
    String method,
    String statusText,
    String signedAccounts,
    LiveActivityStats stats,
    String mood,
    int signedCount,
  ) async {
    if (!Platform.isIOS) return null;
    try {
      final raw = await _channel.invokeMethod<Map>(method, {
        'statusText': statusText,
        'signedAccounts': signedAccounts,
        'autoCount': stats.autoCount,
        'scheduledCount': stats.scheduledCount,
        'manualCount': stats.manualCount,
        'aiCount': stats.aiCount,
        'mood': mood,
        'signedCount': signedCount,
      });
      final map = raw?.cast<String, dynamic>();
      _lastStatus = map;
      if (method == 'start') {
        logger.i('灵动岛已启动: $statusText');
      }
      final err = map?['lastError'];
      if (err is String && err.isNotEmpty) {
        logger.w('灵动岛原生侧提示: $err');
      }
      return map;
    } catch (e) {
      logger.w('灵动岛$method失败: $e');
      return null;
    }
  }
}
