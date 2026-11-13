import 'dart:async';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/active.dart';
import '../api/sign_in.dart';
import '../models/active.dart';
import '../models/course.dart';
import '../models/user.dart';
import '../api/course.dart';
import '../push/notification.dart';
import '../session/account.dart';
import '../setting/course_setting.dart';
import '../utils/logger.dart';
import '../utils/storage.dart';
import '../platform.dart';
import 'sign_history.dart';

/// 单个账号的签到模式
enum AutoSignMode {
  manual, // 手动：不自动，保持原样
  auto, // 托管：收到活动/检测到课程自动签到
  scheduled, // 定时：到时间点自动签到
}

/// 一个时间段（24 小时制）
class TimeRange {
  String start; // "HH:mm"
  String end;   // "HH:mm"
  TimeRange({required this.start, required this.end});

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
  static TimeRange fromJson(Map<String, dynamic> j) => TimeRange(
        start: j['start']?.toString() ?? '',
        end: j['end']?.toString() ?? '',
      );
}

/// 单个账号的定时签到配置
class ScheduledAccountConfig {
  List<TimeRange> timeRanges; // 时间段列表
  String repeatType; // 'everyday' | 'workday' | 'weekend' | 'custom'
  List<int> weekdays; // 1-7（周一=1 ... 周日=7），repeatType=='custom' 时生效

  ScheduledAccountConfig({
    List<TimeRange>? timeRanges,
    this.repeatType = 'everyday',
    List<int>? weekdays,
  })  : timeRanges = timeRanges ?? [],
        weekdays = weekdays ?? [];

  Map<String, dynamic> toJson() => {
        'timeRanges': timeRanges.map((e) => e.toJson()).toList(),
        'repeatType': repeatType,
        'weekdays': weekdays,
      };

  static ScheduledAccountConfig fromJson(Map<String, dynamic>? j) {
    if (j == null) return ScheduledAccountConfig();
    return ScheduledAccountConfig(
      timeRanges: (j['timeRanges'] as List?)
              ?.map((e) => TimeRange.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          [],
      repeatType: j['repeatType']?.toString() ?? 'everyday',
      weekdays: (j['weekdays'] as List?)
              ?.map((e) => int.tryParse(e.toString()) ?? 0)
              .where((e) => e >= 1 && e <= 7)
              .toList() ??
          [],
    );
  }
}

/// 自动签到配置
class AutoSignConfig {
  int pollIntervalSeconds; // 轮询间隔（秒）
  // 每个账号 uid -> 定时签到配置
  Map<String, ScheduledAccountConfig> scheduledAccounts; // uid -> 时间段配置
  // 每个账号 uid -> 模式
  Map<String, String> accountModes; // uid -> AutoSignMode.name
  bool notifyOnResult; // 签到成功/失败时是否弹系统通知

  AutoSignConfig({
    this.pollIntervalSeconds = 30,
    Map<String, ScheduledAccountConfig>? scheduledAccounts,
    Map<String, String>? accountModes,
    this.notifyOnResult = true,
  })  : scheduledAccounts = scheduledAccounts ?? {},
        accountModes = accountModes ?? {};

  static const _key = 'auto_sign_config_v3';

  static Future<AutoSignConfig> load() async {
    final raw = StorageManager.prefs.getString(_key);
    if (raw == null || raw.isEmpty) return AutoSignConfig();
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return AutoSignConfig(
        pollIntervalSeconds: map['pollIntervalSeconds'] ?? 30,
        scheduledAccounts: (map['scheduledAccounts'] as Map?)
                ?.map((k, v) => MapEntry(
                    k.toString(),
                    ScheduledAccountConfig.fromJson(
                        (v as Map).cast<String, dynamic>())))
                ??
            {},
        accountModes: (map['accountModes'] as Map?)
            ?.map((k, v) => MapEntry(k.toString(), v.toString()))
            ?? {},
        notifyOnResult: map['notifyOnResult'] ?? true,
      );
    } catch (e) {
      logger.e('加载自动签到配置失败: $e');
      return AutoSignConfig();
    }
  }

  Future<void> save() async {
    await StorageManager.prefs.setString(_key, json.encode({
      'pollIntervalSeconds': pollIntervalSeconds,
      'scheduledAccounts':
          scheduledAccounts.map((k, v) => MapEntry(k, v.toJson())),
      'accountModes': accountModes,
      'notifyOnResult': notifyOnResult,
    }));
  }

  /// 获取指定账号的定时配置（不存在则创建并返回，保证可原地修改并持久化）
  ScheduledAccountConfig scheduledOf(String uid) {
    return scheduledAccounts.putIfAbsent(uid, () => ScheduledAccountConfig());
  }

  /// 设置指定账号的定时配置
  void setScheduled(String uid, ScheduledAccountConfig cfg) {
    scheduledAccounts[uid] = cfg;
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

/// 需要手动签到的记录（动态二维码等无法自动完成的场景）
class PendingManualSign {
  final String userName;
  final String courseName;
  final String courseId;
  final String lessonId;
  final DateTime time;

  PendingManualSign({
    required this.userName,
    required this.courseName,
    required this.courseId,
    required this.lessonId,
    required this.time,
  });
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

  // 已处理过的活动/课程 id，避免重复签到
  final Set<String> _processedIds = {};
  // 正在处理的 id，防止并发重复
  final Set<String> _inProgressIds = {};
  // 待手动签到清单：key 为 'rc|uid|lessonId'
  final Map<String, PendingManualSign> _pendingManualSigns = {};
  Map<String, PendingManualSign> get pendingManualSigns =>
      Map.unmodifiable(_pendingManualSigns);

  // 学习通待手动签到清单：无法自动签到的活动 id（二维码/手势/签到码）
  final Set<String> _pendingChaoxingManualIds = {};
  Set<String> get pendingChaoxingManualIds =>
      Set.unmodifiable(_pendingChaoxingManualIds);

  /// 学习通活动是否在待手动清单中
  bool isChaoxingManualPending(String activeId) =>
      _pendingChaoxingManualIds.contains(activeId);

  /// 手动签到完成后，从待手动清单移除
  void markChaoxingManuallySigned(String activeId) =>
      _pendingChaoxingManualIds.remove(activeId);

  bool get isRunning => _pollTimer != null;

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
    _pollTimer = null;

    // 没有任何账号开启自动/定时则完全不轮询
    if (!_config.hasAnyActive) return;

    // 周期轮询：托管模式 + 定时模式（时间段内）都走同一套托管轮询逻辑。
    // 定时模式账号是否在窗口内由 _accountsForPoll 动态判断，窗口外自动跳过。
    if (_config.pollIntervalSeconds > 0) {
      _pollTimer = Timer.periodic(
        Duration(seconds: _config.pollIntervalSeconds),
        (_) => _pollSignIns(),
      );
      // 启动后立即轮询一次
      Future.delayed(const Duration(seconds: 3), () => _pollSignIns());
    }
  }

  void dispose() {
    _pollTimer?.cancel();
  }

  /// 定时模式账号：返回当前落在其任一时间段内的账号集合。
  /// 时间段外返回空（不轮询），时间段内持续返回（持续托管轮询）。
  Set<String> _scheduledInWindowUids() {
    final now = DateTime.now();
    final weekday = now.weekday; // 周一=1 ... 周日=7
    final nowStr = _hhmm(now);
    final inWindow = <String>{};

    for (final user in _accountsFor(AutoSignMode.scheduled)) {
      final cfg = _config.scheduledAccounts[user.uid];
      if (cfg == null) continue;
      if (!_matchesRepeat(cfg, weekday)) continue;
      if (cfg.timeRanges.isEmpty) continue;
      for (final range in cfg.timeRanges) {
        if (_inTimeRange(nowStr, range.start, range.end)) {
          inWindow.add(user.uid);
          break;
        }
      }
    }
    return inWindow;
  }

  /// repeatType 是否匹配当前星期几
  bool _matchesRepeat(ScheduledAccountConfig cfg, int weekday) {
    switch (cfg.repeatType) {
      case 'everyday':
        return true;
      case 'workday':
        return weekday >= 1 && weekday <= 5;
      case 'weekend':
        return weekday >= 6 && weekday <= 7;
      case 'custom':
        return cfg.weekdays.contains(weekday);
      default:
        return false;
    }
  }

  /// 当前时刻 "HH:mm" 是否落在 [start, end] 内（支持跨天）
  bool _inTimeRange(String nowStr, String start, String end) {
    final nowM = _minutesOfDay(nowStr);
    final startM = _minutesOfDay(start);
    final endM = _minutesOfDay(end);
    if (startM <= endM) {
      return nowM >= startM && nowM <= endM;
    }
    // 跨天时间段：如 22:00-01:00
    return nowM >= startM || nowM <= endM;
  }

  /// "HH:mm" -> 当日分钟数
  int _minutesOfDay(String hm) {
    final parts = hm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return h * 60 + m;
  }

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

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

  /// 需要轮询签到的账号：
  /// - 托管模式：scheduledOnly=false 时始终处理
  /// - 定时模式：仅当其当前落在某个时间段内时处理（时间段内等同托管，持续轮询）
  List<User> _accountsForPoll({required bool scheduledOnly}) {
    // 定时模式账号当前所在窗口
    final inWindow = _scheduledInWindowUids();

    return AccountManager.allAccounts.where((u) {
      if (!u.status) return false;
      final m = _config.modeOf(u.uid);
      if (m == AutoSignMode.auto) {
        // 托管：scheduledOnly 时不处理
        return !scheduledOnly;
      }
      if (m == AutoSignMode.scheduled) {
        // 定时：必须落在时间段内才处理（时间段内持续轮询，等同托管）
        return inWindow.contains(u.uid);
      }
      return false;
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

      // 课程名映射：onLesson 仅含 courseId/lessonId，通过课程列表补全课程名
      final courses = await RCCourseApi.getCoursesList(onLesson, user.uid) ?? const <Course>[];
      final courseByLesson = <String, Course>{};
      for (final c in courses) {
        final lid = c.lessonId;
        if (lid != null && lid.isNotEmpty) courseByLesson[lid] = c;
      }

      for (final lesson in onLesson) {
        final lessonId = lesson['lessonId']?.toString();
        if (lessonId == null || lessonId.isEmpty) continue;

        final key = 'rc|${user.uid}|$lessonId';
        // 已成功签到或已判定需手动，则跳过，避免重复签到
        if (_processedIds.contains(key)) continue;
        // 防止并发轮询对同一 lesson 重复签到
        if (_inProgressIds.contains(key)) continue;
        _inProgressIds.add(key);

        try {
          final course = courseByLesson[lessonId];
          final courseId = course?.courseId ?? lesson['courseId']?.toString() ?? '';
          final courseName = course?.name ??
              (lesson['courseName'] ??
                      lesson['name'] ??
                      lesson['course_name'] ??
                      lessonId)
                  .toString();

          // 直接签到（checkIn 内部会 joinIfNotIn 进班并返回结果）
          final result = await api.checkIn(lessonId);
          if (result == 0) {
            logger.i('雨课堂账号 ${user.name} 自动签到成功: $courseName ($lessonId)');
            _showNotification('雨课堂签到成功', '${user.name} 已签到 $courseName');
            _recordSignHistory(
              account: user.name,
              platform: '雨课堂',
              course: courseName,
              signType: '普通签到',
              result: '成功',
            );
            // 签到成功后才标记已处理，避免下一轮重复签到
            _processedIds.add(key);
            // 位置签到补全
            await _autoRainLocationCheckIn(user, api, courseName, courseId, lessonId);
          } else if (result == 50070) {
            // 动态二维码签到降级：确认状态并记入待手动清单（终态，标记已处理）
            await _handleRainDynamicQrCode(user, api, courseName, courseId, lessonId);
            _processedIds.add(key);
          } else {
            // 失败（如签到尚未开始）：不标记已处理，下一轮继续重试，
            // 保证老师中途发起的签到能被后续轮询捕获
            logger.w('雨课堂账号 ${user.name} 课程 $courseName 签到返回码: $result');
            _recordSignHistory(
              account: user.name,
              platform: '雨课堂',
              course: courseName,
              signType: '普通签到',
              result: '失败(返回码 $result)',
            );
          }
        } finally {
          _inProgressIds.remove(key);
        }
      }
    }
  }

  /// 动态二维码签到（50070）降级处理：尝试确认签到状态，未签则记入待手动清单
  Future<void> _handleRainDynamicQrCode(
    User user,
    RCCourseApi api,
    String courseName,
    String courseId,
    String lessonId,
  ) async {
    // 尝试确认当前签到状态
    Map<String, dynamic>? status;
    try {
      status = await api.getCheckIn();
    } catch (e) {
      logger.w('雨课堂账号 ${user.name} 查询签到状态失败: $e');
    }

    if (status != null && status['signed'] == true) {
      logger.i('雨课堂账号 ${user.name} 课程 $courseName 已签到（动态二维码状态确认）');
      _showNotification('雨课堂签到成功', '${user.name} 已签到 $courseName');
      _recordSignHistory(
        account: user.name,
        platform: '雨课堂',
        course: courseName,
        signType: '普通签到',
        result: '成功',
      );
      return;
    }

    // 记录到待手动清单并通知
    _pendingManualSigns['rc|${user.uid}|$lessonId'] = PendingManualSign(
      userName: user.name,
      courseName: courseName,
      courseId: courseId,
      lessonId: lessonId,
      time: DateTime.now(),
    );
    logger.w('雨课堂账号 ${user.name} 课程 $courseName 开启动态二维码签到，需手动扫码');
    _showNotification('雨课堂需手动签到', '${user.name} 课程 $courseName 需手动扫码');
    _recordSignHistory(
      account: user.name,
      platform: '雨课堂',
      course: courseName,
      signType: '普通签到',
      result: '需手动扫码',
    );
  }

  /// 位置签到补全：checkIn 成功后若需要位置签到，用课程配置的位置自动提交
  Future<void> _autoRainLocationCheckIn(
    User user,
    RCCourseApi api,
    String courseName,
    String courseId,
    String lessonId,
  ) async {
    Map<String, dynamic>? status;
    try {
      status = await api.getCheckIn();
    } catch (e) {
      logger.w('雨课堂账号 ${user.name} 查询位置签到状态失败: $e');
    }
    if (status == null) return;
    if (status['signed'] == true) return; // 已签到
    if (status['needLocationSignIn'] != true) return; // 无需位置签到

    final settings = await CourseSetting.getSettings(courseId);
    final location = settings?.location;
    if (location == null) {
      logger.w('雨课堂账号 ${user.name} 课程 $courseName 需要位置签到，但未配置位置');
      _showNotification(
          '雨课堂需手动签到', '${user.name} 课程 $courseName 需要位置签到，请手动签到');
      _recordSignHistory(
        account: user.name,
        platform: '雨课堂',
        course: courseName,
        signType: '位置签到',
        result: '未配置位置',
      );
      return;
    }
    final lat = double.tryParse(location.latitude);
    final lng = double.tryParse(location.longitude);
    if (lat == null || lng == null) {
      logger.w('雨课堂账号 ${user.name} 课程 $courseName 位置配置无效');
      _recordSignHistory(
        account: user.name,
        platform: '雨课堂',
        course: courseName,
        signType: '位置签到',
        result: '位置配置无效',
      );
      return;
    }

    final submit = await api.submitLocationCheckIn(lessonId, lat, lng, location.address);
    if (submit != null && submit['code'] == 0) {
      logger.i('雨课堂账号 ${user.name} 课程 $courseName 位置签到成功');
      _showNotification('雨课堂签到成功', '${user.name} 已签到 $courseName（位置）');
      _recordSignHistory(
        account: user.name,
        platform: '雨课堂',
        course: courseName,
        signType: '位置签到',
        result: '成功',
      );
    } else {
      logger.w('雨课堂账号 ${user.name} 课程 $courseName 位置签到失败: $submit');
      _recordSignHistory(
        account: user.name,
        platform: '雨课堂',
        course: courseName,
        signType: '位置签到',
        result: '失败',
      );
    }
  }

  // ============ 学习通 ============

  /// 学习通：轮询活动列表，对托管/定时账号自动签到
  Future<void> _pollChaoxing({required bool scheduledOnly}) async {
    if (!AccountManager.hasActiveSession()) return;

    final accounts = _accountsForPoll(scheduledOnly: scheduledOnly);
    if (accounts.isEmpty) return;

    // 按账号遍历：每个托管账号各自拉取课程与活动，避免只签当前会话账号
    for (final user in accounts) {
      final courseList = await CXCourseApi.getCoursesList(userId: user.uid);
      if (courseList == null || courseList.isEmpty) continue;

      final api = CXCourseApi(user);
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
          logger.i('轮询发现新签到活动: ${active.name} (账号 ${user.name})');
          await _autoSignChaoxingActive(
              active, course.courseId, classId,
              scheduledOnly: scheduledOnly, courseName: course.name);
        }
      }
    }
  }

  /// 执行学习通单个签到活动的自动签到
  Future<void> _autoSignChaoxingActive(
    Active active,
    String courseId,
    String classId, {
    required bool scheduledOnly,
    String? courseName,
  }) async {
    // 已处理过（成功或已判定无法自动）则不再重复处理，避免重复签到
    if (_processedIds.contains(active.id)) return;
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

      // 查询各账号签到状态，仅对明确「未签到」(status == 0) 的账号签到，避免重复签到
      final needSign = <User>[];
      for (final user in accounts) {
        final attendInfo = await SignInApi.getAttendInfoWeb(active.id, userId: user.uid);
        final status = attendInfo?['status'];
        if (status == 0) {
          // 明确未签到
          needSign.add(user);
        } else if (status == null) {
          // 状态查询失败，无法确定是否已签，跳过以免重复签到
          logger.w('账号 ${user.name} 签到状态查询失败，跳过（避免重复签到）');
        } else {
          // status: 1 已签 / 2 教师代签 / 4-12 请假、缺勤、迟到、早退、过期等，均视为已处理
          logger.i('账号 ${user.name} 已处理（status=$status），跳过');
        }
      }

      if (needSign.isEmpty) {
        logger.i('活动 ${active.name} 所有账号已签到，跳过');
        _processedIds.add(active.id);
        return;
      }

      // 二维码/手势/签到码需要现场扫码、手势密码、签到码，均无法从活动详情获取，
      // 记入待手动签到清单，而不是静默跳过
      if (signType == SignType.qrCode ||
          signType == SignType.pattern ||
          signType == SignType.code) {
        _pendingChaoxingManualIds.add(active.id);
        final label = _signTypeLabel(signType);
        final courseLabel = courseName ?? active.name;
        final names = needSign.map((u) => u.name).join('、');
        logger.w('活动「${active.name}」为$label，无法自动签到，'
            '已加入待手动签到清单（待签账号：$names）');
        for (final user in needSign) {
          _recordSignHistory(
            account: user.name,
            platform: '学习通',
            course: courseLabel,
            signType: label,
            result: '需手动签到',
          );
        }
        _processedIds.add(active.id);
        return;
      }

      // 加载课程配置（位置/图片自动填充）
      final settings = await CourseSetting.getSettings(courseId);
      final location = settings?.location;
      final imageObjectIds = settings?.imageObjectIds ?? [];

      // 针对不同签到类型执行
      final courseLabel = courseName ?? active.name;
      for (final user in needSign) {
        final result = await _signForType(
          signType, user, active, courseId, classId, location, imageObjectIds);
        if (result == 'success') {
          logger.i('账号 ${user.name} 自动签到成功: ${active.name}');
          _showNotification('自动签到成功', '${user.name} 已签到 ${active.name}');
          _recordSignHistory(
            account: user.name,
            platform: '学习通',
            course: courseLabel,
            signType: _signTypeLabel(signType),
            result: '成功',
          );
        } else {
          logger.w('账号 ${user.name} 自动签到结果: $result');
          _recordSignHistory(
            account: user.name,
            platform: '学习通',
            course: courseLabel,
            signType: _signTypeLabel(signType),
            result: result ?? '失败',
          );
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
      NotificationService().show(
        title: title,
        body: body,
        androidDetails: const AndroidNotificationDetails(
          'auto_sign_channel',
          '自动签到',
          channelDescription: '自动签到结果通知',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
      );
    } catch (e) {
      logger.e('通知失败: $e');
    }
  }

  /// 写入一条签到历史记录（异步、不阻塞签到流程）
  void _recordSignHistory({
    required String account,
    required String platform,
    required String course,
    required String signType,
    required String result,
  }) {
    unawaited(SignHistoryStore().add(SignHistoryRecord(
      time: DateTime.now(),
      accountName: account,
      platform: platform,
      target: '$course · $signType',
      success: result == '成功',
    )));
  }
}

/// 签到类型的中文描述
String _signTypeLabel(SignType type) {
  switch (type) {
    case SignType.normal:
      return '普通签到';
    case SignType.qrCode:
      return '二维码签到';
    case SignType.pattern:
      return '手势签到';
    case SignType.location:
      return '位置签到';
    case SignType.code:
      return '签到码签到';
  }
}
