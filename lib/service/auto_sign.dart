import 'dart:async';
import 'dart:convert';

import '../api/active.dart';
import '../api/sign_in.dart';
import '../models/active.dart';
import '../models/course.dart';
import '../models/user.dart';
import '../api/course.dart';
import '../session/account.dart';
import '../setting/course_setting.dart';
import '../utils/logger.dart';
import '../utils/storage.dart';
import '../platform.dart';

/// 自动签到配置
class AutoSignConfig {
  bool enabled; // 总开关：收到推送自动签到
  bool scheduledEnabled; // 定时签到开关
  List<String> scheduledTimes; // 定时签到时间点，格式 "HH:mm"
  int pollIntervalSeconds; // 定时轮询间隔（秒）
  bool signAllAccounts; // 是否对所有已登录账号签到

  AutoSignConfig({
    this.enabled = false,
    this.scheduledEnabled = false,
    List<String>? scheduledTimes,
    this.pollIntervalSeconds = 30,
    this.signAllAccounts = true,
  }) : scheduledTimes = scheduledTimes ?? [];

  static const _key = 'auto_sign_config';

  static Future<AutoSignConfig> load() async {
    final raw = StorageManager.prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AutoSignConfig();
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return AutoSignConfig(
        enabled: map['enabled'] ?? false,
        scheduledEnabled: map['scheduledEnabled'] ?? false,
        scheduledTimes: (map['scheduledTimes'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        pollIntervalSeconds: map['pollIntervalSeconds'] ?? 30,
        signAllAccounts: map['signAllAccounts'] ?? true,
      );
    } catch (e) {
      logger.e('加载自动签到配置失败: $e');
      return AutoSignConfig();
    }
  }

  Future<void> save() async {
    await StorageManager.prefs.setString(_key, json.encode({
      'enabled': enabled,
      'scheduledEnabled': scheduledEnabled,
      'scheduledTimes': scheduledTimes,
      'pollIntervalSeconds': pollIntervalSeconds,
      'signAllAccounts': signAllAccounts,
    }));
  }
}

/// 自动签到服务
///
/// 功能：
/// 1. 自动签到：收到环信 IM 推送的签到活动消息时，自动执行签到
/// 2. 定时签到：按固定时间点 + 周期轮询检测新签到活动并自动签
class AutoSignService {
  AutoSignService._internal();
  static final AutoSignService _instance = AutoSignService._internal();
  factory AutoSignService() => _instance;

  AutoSignConfig _config = AutoSignConfig();
  AutoSignConfig get config => _config;

  Timer? _pollTimer;
  Timer? _scheduleTimer;

  // 已处理过的活动 id，避免重复签到
  final Set<String> _processedActiveIds = {};
  // 正在处理的活动 id，防止并发重复
  final Set<String> _inProgressIds = {};

  bool get isRunning => _pollTimer != null || _scheduleTimer != null;

  /// 初始化并启动后台任务
  Future<void> initialize() async {
    _config = await AutoSignConfig.load();
    _startTimers();
    logger.i('自动签到服务已初始化: enabled=${_config.enabled}, '
        'scheduled=${_config.scheduledEnabled}');
  }

  /// 更新配置并重启定时器
  Future<void> updateConfig(AutoSignConfig config) async {
    _config = config;
    await config.save();
    _startTimers();
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _scheduleTimer?.cancel();
    _pollTimer = null;
    _scheduleTimer = null;

    if (!_config.enabled) return;

    // 周期轮询：检测新签到活动
    if (_config.scheduledEnabled || _config.pollIntervalSeconds > 0) {
      _pollTimer = Timer.periodic(
        Duration(seconds: _config.pollIntervalSeconds),
        (_) => _pollForNewSignIns(),
      );
      // 启动后立即轮询一次
      Future.delayed(const Duration(seconds: 3), () => _pollForNewSignIns());
    }

    // 固定时间点签到
    if (_config.scheduledEnabled && _config.scheduledTimes.isNotEmpty) {
      _scheduleTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _checkScheduledTimes();
      });
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _scheduleTimer?.cancel();
  }

  /// 固定时间点检测
  void _checkScheduledTimes() {
    if (!_config.enabled || !_config.scheduledEnabled) return;
    final now = DateTime.now();
    final nowStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // 只允许在每分钟的 0~30 秒内触发一次，避免重复
    if (now.second > 30) return;

    for (final t in _config.scheduledTimes) {
      if (t.trim() == nowStr) {
        logger.i('命中定时签到时间点: $nowStr');
        _pollForNewSignIns(forceSign: true);
        break;
      }
    }
  }

  /// 收到推送活动消息时的自动签到入口
  ///
  /// 由 EasemobIM 在收到签到类活动消息时调用。
  Future<void> onActivityPushed(Active active, String courseId, String classId) async {
    if (!_config.enabled) return;
    // 只处理签到类活动
    if (active.activeType != ActiveType.signIn &&
        active.activeType != ActiveType.scheduledSignIn) {
      return;
    }
    logger.i('收到签到活动推送，准备自动签到: ${active.name}');
    await _autoSignActive(active, courseId, classId);
  }

  /// 轮询检测新签到活动
  Future<void> _pollForNewSignIns({bool forceSign = false}) async {
    if (!_config.enabled) return;
    if (!PlatformManager().isChaoxing) return; // 仅支持学习通
    if (!AccountManager.hasActiveSession()) return;

    try {
      final courseList = await CXCourseApi.getCoursesList();
      if (courseList == null || courseList.isEmpty) return;

      final currentUser = AccountManager.currentUser;
      if (currentUser == null) return;

      final api = CXCourseApi(currentUser);
      for (final course in courseList) {
        final classId = course.classId;
        final cpi = course.cpi;
        if (classId.isEmpty || cpi == null || cpi.isEmpty) continue;

        final activeList = await api.getActiveList(course.courseId, classId, cpi);
        if (activeList == null) continue;

        for (final active in activeList) {
          if (active.activeType != ActiveType.signIn &&
              active.activeType != ActiveType.scheduledSignIn) {
            continue;
          }
          // 只处理进行中的签到（status == true）
          if (!active.status) continue;
          // 未处理过的签到活动才自动签
          if (_processedActiveIds.contains(active.id) && !forceSign) continue;
          logger.i('轮询发现新签到活动: ${active.name}');
          await _autoSignActive(active, course.courseId, classId);
        }
      }
    } catch (e, st) {
      logger.e('轮询签到活动失败: $e\n$st');
    }
  }

  /// 执行单个签到活动的自动签到
  Future<void> _autoSignActive(Active active, String courseId, String classId) async {
    if (_inProgressIds.contains(active.id)) return;
    _inProgressIds.add(active.id);

    try {
      // 确定签到类型
      SignType signType;
      if (active.signType != null) {
        signType = active.signType!;
      } else {
        // 获取活动详情以确定签到类型
        final info = await ActiveApi.getActiveInfoWeb(active.id);
        final otherId = info?['otherId'];
        if (otherId == null) {
          _processedActiveIds.add(active.id);
          return;
        }
        try {
          signType = getSignTypeFromIndex(int.parse(otherId.toString()));
        } catch (e) {
          _processedActiveIds.add(active.id);
          return;
        }
      }

      // 获取需要签到的账号
      final accounts = _config.signAllAccounts
          ? AccountManager.allAccounts.where((u) => u.status).toList()
          : [AccountManager.currentUser!];

      // 查询各账号签到状态，跳过已签账号
      final needSign = <User>[];
      for (final user in accounts) {
        final attendInfo = await SignInApi.getAttendInfoWeb(active.id, userId: user.uid);
        final status = attendInfo?['status'];
        if (status == null || status == 0) {
          needSign.add(user);
        }
      }

      if (needSign.isEmpty) {
        logger.i('活动 ${active.name} 所有账号已签到，跳过');
        _processedActiveIds.add(active.id);
        return;
      }

      // 加载课程配置（位置/图片自动填充）
      final settings = await CourseSetting.getSettings(courseId);
      final location = settings?.location;
      final imageObjectIds = settings?.imageObjectIds ?? [];

      // 针对不同签到类型执行
      for (final user in needSign) {
        final result = await _signForType(
          signType, user, active, courseId, classId, location, imageObjectIds);
        if (result == 'success') {
          logger.i('账号 ${user.name} 自动签到成功: ${active.name}');
          _showNotification('自动签到成功', '${user.name} 已签到 ${active.name}');
        } else {
          logger.w('账号 ${user.name} 自动签到结果: $result');
        }
      }

      _processedActiveIds.add(active.id);
    } catch (e, st) {
      logger.e('自动签到异常: $e\n$st');
    } finally {
      _inProgressIds.remove(active.id);
    }
  }

  /// 按签到类型执行签到（不含 UI，直接调 API）
  Future<String?> _signForType(
    SignType signType,
    User user,
    Active active,
    String courseId,
    String classId,
    CourseLocation? location,
    List<String> imageObjectIds,
  ) async {
    final api = SignInApi(user);
    final address = location?.address;
    final lat = double.tryParse(location?.latitude ?? '');
    final lng = double.tryParse(location?.longitude ?? '');

    switch (signType) {
      case SignType.normal:
        // 普通签到（拍照签到需要 objectId）
        String? objectId;
        if (imageObjectIds.isNotEmpty) {
          objectId = imageObjectIds[0];
        }
        return await api.normalSign(courseId, active.id, objectId: objectId);

      case SignType.qrCode:
        // 二维码签到需要 enc，但自动场景无法获取动态二维码的 enc
        // 这里尝试从活动详情获取，通常无法自动完成，记录日志
        logger.w('二维码签到无法自动完成（需要动态二维码内容）: ${active.name}');
        return '二维码签到需要手动扫码';

      case SignType.pattern:
        // 手势签到需要手势密码，无法自动
        logger.w('手势签到无法自动完成（需要手势密码）: ${active.name}');
        return '手势签到需要手动输入';

      case SignType.code:
        // 签到码签到需要签到码，无法自动
        logger.w('签到码签到无法自动完成（需要签到码）: ${active.name}');
        return '签到码签到需要手动输入';

      case SignType.location:
        // 位置签到：使用课程配置的位置
        if (address == null || lat == null || lng == null) {
          logger.w('位置签到缺少位置配置: ${active.name}');
          return '位置签到需要先配置位置';
        }
        return await api.locationSign(
          courseId, active.id, address, lat, lng);

      default:
        return '未知签到类型';
    }
  }

  void _showNotification(String title, String body) {
    try {
      // 使用 ScaffoldMessenger 或系统通知（这里仅日志 + 可选弹窗）
      logger.i('[$title] $body');
    } catch (e) {
      logger.e('通知失败: $e');
    }
  }
}
