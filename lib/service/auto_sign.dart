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

/// 单个账号的签到模式
enum AutoSignMode {
  manual, // 手动：不自动，保持原样
  auto, // 托管：收到活动/检测到课程自动签到
  scheduled, // 定时：到时间点自动签到
}

/// 自动签到配置
class AutoSignConfig {
  int pollIntervalSeconds; // 轮询间隔（秒）
  List<String> scheduledTimes; // 定时签到时间点，格式 "HH:mm"
  // 每个账号 uid -> 模式
  Map<String, String> accountModes; // uid -> AutoSignMode.name

  AutoSignConfig({
    this.pollIntervalSeconds = 30,
    List<String>? scheduledTimes,
    Map<String, String>? accountModes,
  })  : scheduledTimes = scheduledTimes ?? [],
        accountModes = accountModes ?? {};

  static const _key = 'auto_sign_config_v2';

  static Future<AutoSignConfig> load() async {
    final raw = StorageManager.prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AutoSignConfig();
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return AutoSignConfig(
        pollIntervalSeconds: map['pollIntervalSeconds'] ?? 30,
        scheduledTimes: (map['scheduledTimes'] as List?)
            ?.map((e) => e.toString())
            .toList() ?? [],
        accountModes: (map['accountModes'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString()))
            ?? {},
      );
    } catch (e) {
      logger.e('加载自动签到配置失败: $e');
      return AutoSignConfig();
    }
  }

  Future<void> save() async {
    await StorageManager.prefs.setString(_key, json.encode({
      'pollIntervalSeconds': pollIntervalSeconds,
      'scheduledTimes': scheduledTimes,
      'accountModes': accountModes,
    }));
  }

  /// 获取指定账号的签到模式，默认手动
  AutoSignMode modeOf(String uid) {
    final raw = accountModes[uid];
    if (raw == null) return AutoSignMode.manual;
    return AutoSignMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => AutoSignMode.manual,
    );
  }

  /// 设置指定账号的模式
  void setMode(String uid, AutoSignMode mode) {
    accountModes[uid] = mode.name;
  }

  /// 是否有任何账号开启了自动或定时签到
  bool get hasAnyActive {
    return accountModes.values.any(
      (v) => v == AutoSignMode.auto.name || v == AutoSignMode.scheduled.name,
    );
  }
}

/// 自动签到服务
///
/// 功能：
/// 1. 托管（自动）：雨课堂轮询正在上课的课自动签到；学习通收到环信推送自动签
/// 2. 定时：到固定时间点自动签到
/// 3. 手动：不自动，保持原样
///
/// 每个账号独立设置模式（托管/定时/手动）。
class AutoSignService {
  AutoSignService._internal();
  static final AutoSignService _instance = AutoSignService._internal();
  factory AutoSignService() => _instance;

  AutoSignConfig _config = AutoSignConfig();
  AutoSignConfig get config => _config;

  Timer? _pollTimer;
  Timer? _scheduleTimer;

  // 已处理过的活动/课程 id，避免重复签到
  final Set<String> _processedIds = {};
  // 正在处理的 id，防止并发重复
  final Set<String> _inProgressIds = {};

  bool get isRunning => _pollTimer != null || _scheduleTimer != null;

  /// 初始化并启动后台任务
  Future<void> initialize() async {
    _config = await AutoSignConfig.load();
    _startTimers();
    logger.i('自动签到服务已初始化: 账号模式数=${_config.accountModes.length}');
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

    // 没有任何账号开启自动/定时则完全不轮询
    if (!_config.hasAnyActive) return;

    // 周期轮询：托管模式检测签到（雨课堂轮询课程、学习通轮询活动）
    if (_config.pollIntervalSeconds > 0) {
      _pollTimer = Timer.periodic(
        Duration(seconds: _config.pollIntervalSeconds),
        (_) => _pollSignIns(),
      );
      // 启动后立即轮询一次
      Future.delayed(const Duration(seconds: 3), () => _pollSignIns());
    }

    // 固定时间点检测（定时模式）
    if (_config.scheduledTimes.isNotEmpty) {
      _scheduleTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        _checkScheduledTimes();
      });
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _scheduleTimer?.cancel();
  }

  /// 固定时间点检测（定时模式账号）
  void _checkScheduledTimes() {
    if (_config.scheduledTimes.isEmpty) return;
    final now = DateTime.now();
    final nowStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    // 只允许在每分钟的 0~30 秒内触发一次，避免重复
    if (now.second > 30) return;

    for (final t in _config.scheduledTimes) {
      if (t.trim() == nowStr) {
        logger.i('命中定时签到时间点: $nowStr');
        _pollSignIns(scheduledOnly: true);
        break;
      }
    }
  }

  /// 收到推送活动消息时的自动签到入口（仅学习通环信推送）
  ///
  /// 由 EasemobIM 在收到签到类活动消息时调用。
  Future<void> onActivityPushed(Active active, String courseId, String classId) async {
    // 只处理签到类活动
    if (active.activeType != ActiveType.signIn &&
        active.activeType != ActiveType.scheduledSignIn) {
      return;
    }
    logger.i('收到签到活动推送，准备自动签到: ${active.name}');
    await _autoSignChaoxingActive(active, courseId, classId, scheduledOnly: false);
  }

  /// 周期轮询签到
  ///
  /// [scheduledOnly] 为 true 时只处理「定时」模式的账号，否则处理「托管」+「定时」。
  Future<void> _pollSignIns({bool scheduledOnly = false}) async {
    if (!_config.hasAnyActive) return;
    try {
      if (PlatformManager().isRainClassroom) {
        await _pollRainClassroom(scheduledOnly: scheduledOnly);
      } else {
        await _pollChaoxing(scheduledOnly: scheduledOnly);
      }
    } catch (e, st) {
      logger.e('轮询签到失败: $e\n$st');
    }
  }

  /// 筛选出指定模式下需要处理的账号
  List<User> _accountsFor(AutoSignMode mode) {
    return AccountManager.allAccounts.where((u) {
      if (!u.status) return false;
      return _config.modeOf(u.uid) == mode;
    }).toList();
  }

  /// 托管模式账号（scheduledOnly=false 时）或定时模式账号（true 时）
  List<User> _accountsForPoll({required bool scheduledOnly}) {
    if (scheduledOnly) {
      return _accountsFor(AutoSignMode.scheduled);
    }
    // 托管 + 定时都要处理
    return AccountManager.allAccounts.where((u) {
      if (!u.status) return false;
      final m = _config.modeOf(u.uid);
      return m == AutoSignMode.auto || m == AutoSignMode.scheduled;
    }).toList();
  }

  // ============ 雨课堂 ============

  /// 雨课堂：轮询正在上课的课程，对托管/定时账号自动签到
  Future<void> _pollRainClassroom({required bool scheduledOnly}) async {
    final accounts = _accountsForPoll(scheduledOnly: scheduledOnly);
    if (accounts.isEmpty) return;

    for (final user in accounts) {
      final api = RCCourseApi(user);
      // 获取该账号正在上课的课程
      final onLesson = await RCCourseApi.getOnLesson(userId: user.uid);
      if (onLesson == null || onLesson.isEmpty) continue;

      for (final lesson in onLesson) {
        final lessonId = lesson['lessonId']?.toString();
        if (lessonId == null || lessonId.isEmpty) continue;

        final key = 'rc|${user.uid}|$lessonId';
        if (_processedIds.contains(key)) continue;
        _processedIds.add(key);

        // 直接签到（checkIn 内部会 joinIfNotIn 进班并返回结果）
        final result = await api.checkIn(lessonId);
        if (result == 0) {
          logger.i('雨课堂账号 ${user.name} 自动签到成功: $lessonId');
          _showNotification('雨课堂签到成功', '${user.name} 已签到 $lessonId');
        } else if (result == 50070) {
          // 该课堂已开启动态二维码签到，需扫码，无法自动
          logger.w('雨课堂账号 ${user.name} 课程 $lessonId 开启动态二维码签到，需手动扫码');
        } else {
          logger.w('雨课堂账号 ${user.name} 签到返回码: $result');
        }
      }
    }
  }

  // ============ 学习通 ============

  /// 学习通：轮询活动列表，对托管/定时账号自动签到
  Future<void> _pollChaoxing({required bool scheduledOnly}) async {
    if (!AccountManager.hasActiveSession()) return;

    final courseList = await CXCourseApi.getCoursesList();
    if (courseList == null || courseList.isEmpty) return;

    final accounts = _accountsForPoll(scheduledOnly: scheduledOnly);
    if (accounts.isEmpty) return;

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
        if (!active.status) continue;
        if (_processedIds.contains(active.id)) continue;
        logger.i('轮询发现新签到活动: ${active.name}');
        await _autoSignChaoxingActive(
            active, course.courseId, classId, scheduledOnly: scheduledOnly);
      }
    }
  }

  /// 执行学习通单个签到活动的自动签到
  Future<void> _autoSignChaoxingActive(
    Active active,
    String courseId,
    String classId, {
    required bool scheduledOnly,
  }) async {
    if (_inProgressIds.contains(active.id)) return;
    _inProgressIds.add(active.id);

    try {
      // 确定签到类型
      SignType signType;
      if (active.signType != null) {
        signType = active.signType!;
      } else {
        final info = await ActiveApi.getActiveInfoWeb(active.id);
        final otherId = info?['otherId'];
        if (otherId == null) {
          _processedIds.add(active.id);
          return;
        }
        try {
          signType = getSignTypeFromIndex(int.parse(otherId.toString()));
        } catch (e) {
          _processedIds.add(active.id);
          return;
        }
      }

      // 获取需要签到的账号（按模式筛选）
      final accounts = _accountsForPoll(scheduledOnly: scheduledOnly);
      if (accounts.isEmpty) {
        _processedIds.add(active.id);
        return;
      }

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
        _processedIds.add(active.id);
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

      _processedIds.add(active.id);
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
        String? objectId;
        if (imageObjectIds.isNotEmpty) {
          objectId = imageObjectIds[0];
        }
        return await api.normalSign(courseId, active.id, objectId: objectId);

      case SignType.qrCode:
        logger.w('二维码签到无法自动完成（需要动态二维码内容）: ${active.name}');
        return '二维码签到需要手动扫码';

      case SignType.pattern:
        logger.w('手势签到无法自动完成（需要手势密码）: ${active.name}');
        return '手势签到需要手动输入';

      case SignType.code:
        logger.w('签到码签到无法自动完成（需要签到码）: ${active.name}');
        return '签到码签到需要手动输入';

      case SignType.location:
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
      logger.i('[$title] $body');
    } catch (e) {
      logger.e('通知失败: $e');
    }
  }
}
