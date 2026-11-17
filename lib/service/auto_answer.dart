import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/course.dart';
import '../models/presentation.dart';
import '../models/user.dart';
import '../platform.dart';
import '../push/notification.dart';
import '../utils/logger.dart';
import 'ai_answer.dart';
import 'auto_sign.dart';

/// 后台多课堂自动答题引擎。
///
/// 与页面内的答题不同，这里不依赖用户打开课堂页：
/// 为每个「开启 AI 答题的托管/定时账号 × 该账号正在上课的课堂」
/// 各建一条独立的课堂 WebSocket，监听题目解锁事件，
/// 拉到题目内容后调用 AI 生成答案，并用**该账号自己**提交。
///
/// 约束：
/// - 仅雨课堂（学习通没有这套课堂 WebSocket 推送）；
/// - 账号需为「托管」或「定时且处于时间段内」，因为建立课堂连接需要
///   先 checkIn 取得 lessonToken（这一步同时完成签到）。
class AutoAnswerEngine {
  AutoAnswerEngine._internal();
  static final AutoAnswerEngine _instance = AutoAnswerEngine._internal();
  factory AutoAnswerEngine() => _instance;

  /// 每节课一个后台会话，key = 'uid|lessonId'
  final Map<String, _LessonSession> _sessions = {};

  /// 已提交成功的题目，key = 'uid|problemId'（与页面共享，避免重复提交）
  final Set<String> _answered = {};
  final Set<String> _answering = {};

  /// 被页面接管的课堂（用户正打开着该课堂页），后台不再重复连接，
  /// 避免同一账号同一节课建两条 WebSocket 被服务端互踢。
  final Set<String> _paused = {};

  Timer? _syncTimer;
  bool _syncing = false;

  /// 课程列表缓存（uid → courseId 集合），避免每轮同步都重复拉取
  final Map<String, Set<String>> _courseCache = {};
  final Map<String, DateTime> _courseCacheAt = {};
  static const _courseCacheTtl = Duration(minutes: 5);

  /// 该账号是否已经答过这道题（页面侧也用它去重）
  bool hasAnswered(String uid, String problemId) =>
      _answered.contains('$uid|$problemId');

  /// 标记该账号这道题已答（页面提交成功后调用）
  void markAnswered(String uid, String problemId) =>
      _answered.add('$uid|$problemId');

  /// 当前正在后台跟课的课堂数量（用于设置页展示）
  int get sessionCount => _sessions.length;

  /// 启动后台答题引擎（可重复调用：已运行则忽略；之前因未配置而未启动的，配置好后会真正启动）
  void start() {
    if (_syncTimer != null) return;

    if (!AiAnswerService().isConfigured) {
      logger.i('后台答题未启动：尚未配置 AI API 密钥');
      return;
    }

    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) => _sync());
    Future.delayed(const Duration(seconds: 8), _sync);
    logger.i('后台多课堂答题引擎已启动');
  }

  /// 停止并清理所有连接
  Future<void> stop() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    await _closeAll('引擎停止');
  }

  /// 配置变化后重启（例如刚填好 API 密钥）
  Future<void> restart() async {
    await stop();
    start();
  }

  /// 页面打开某节课：后台让出该课堂，由页面自己处理
  void pauseSession(String uid, String lessonId) {
    final key = '$uid|$lessonId';
    _paused.add(key);
    final session = _sessions[key];
    if (session != null) {
      unawaited(_closeSession(session, '页面已接管该课堂'));
    }
  }

  /// 页面关闭该节课：恢复后台跟课
  void resumeSession(String uid, String lessonId) {
    _paused.remove('$uid|$lessonId');
  }

  // ============ 同步：账号 → 正在上的课 ============

  Future<void> _sync() async {
    if (_syncing) return;
    if (!AiAnswerService().isConfigured) {
      await _closeAll('未配置 AI 密钥');
      return;
    }
    // 学习通走的是另一套推送，这里只处理雨课堂课堂 WebSocket
    if (!PlatformManager().isRainClassroom) {
      await _closeAll('当前平台不是雨课堂');
      return;
    }

    final accounts = AutoSignService()
        .activeAccountsForAutomation
        .where((u) => AiAnswerService().isEnabledFor(u.uid))
        .toList();

    if (accounts.isEmpty) {
      await _closeAll('没有开启 AI 答题的托管/定时账号');
      return;
    }

    _syncing = true;
    try {
      final alive = <String>{};

      for (final user in accounts) {
        List<dynamic>? onLesson;
        try {
          onLesson = await RCCourseApi.getOnLesson(userId: user.uid);
        } catch (e) {
          logger.w('后台答题：拉取 ${user.name} 的上课列表失败: $e');
          continue;
        }
        // 拿不到就当作未知：保留该账号已有会话，本轮不判定下课
        if (onLesson == null) {
          for (final k in _sessions.keys) {
            if (k.startsWith('${user.uid}|')) alive.add(k);
          }
          continue;
        }

        // 课程归属校验：不属于该账号的课不接（避免替别人上课）
        Set<String>? ownCourseIds = _courseCache[user.uid];
        final cachedAt = _courseCacheAt[user.uid];
        final expired =
            cachedAt == null || DateTime.now().difference(cachedAt) > _courseCacheTtl;
        if (ownCourseIds == null || expired) {
          try {
            final courses = await RCCourseApi.getCoursesList(onLesson, user.uid);
            if (courses != null && courses.isNotEmpty) {
              ownCourseIds = courses
                  .map((c) => c.courseId)
                  .where((id) => id.isNotEmpty)
                  .toSet();
              _courseCache[user.uid] = ownCourseIds;
              _courseCacheAt[user.uid] = DateTime.now();
            }
          } catch (e) {
            logger.w('后台答题：拉取 ${user.name} 课程列表失败: $e');
          }
        }

        for (final lesson in onLesson) {
          final lessonId = lesson['lessonId']?.toString();
          if (lessonId == null || lessonId.isEmpty) continue;

          final courseId = lesson['courseId']?.toString() ?? '';
          if (ownCourseIds != null &&
              ownCourseIds.isNotEmpty &&
              courseId.isNotEmpty &&
              !ownCourseIds.contains(courseId)) {
            continue;
          }

          final key = '${user.uid}|$lessonId';
          // 页面正在打开这节课，交给页面自己跟，后台不重复连接
          if (_paused.contains(key)) continue;
          alive.add(key);

          final existing = _sessions[key];
          if (existing == null) {
            final session = _LessonSession(user: user, lessonId: lessonId);
            _sessions[key] = session;
            unawaited(_connect(session));
          } else {
            existing.misses = 0;
            if (existing.ws == null && !existing.connecting) {
              unawaited(_connect(existing));
            }
          }
        }
      }

      // 清理已下课的会话（连续两轮不在上课列表里才关，避免接口抖动误杀）
      for (final key in _sessions.keys.toList()) {
        if (alive.contains(key)) continue;
        final session = _sessions[key];
        if (session == null) continue;
        session.misses++;
        if (session.misses >= 2) {
          await _closeSession(session, '课堂已结束');
        }
      }
    } catch (e, st) {
      logger.e('后台答题同步异常: $e\n$st');
    } finally {
      _syncing = false;
    }
  }

  // ============ 单个课堂连接 ============

  Future<void> _connect(_LessonSession s) async {
    if (s.closed || s.connecting) return;
    s.connecting = true;
    s.reconnectTimer?.cancel();
    s.reconnectTimer = null;

    try {
      final api = RCCourseApi(s.user);

      // checkIn 同时完成两件事：签到 + 取得该课堂的 lessonToken（WebSocket 鉴权用）
      final code = await api.checkIn(s.lessonId);
      final token = api.lessonToken;
      if (token == null || token.isEmpty) {
        logger.w('后台答题：${s.user.name} 课堂 ${s.lessonId} 未取到 lessonToken'
            '（checkIn 返回码 $code），稍后重试');
        _scheduleReconnect(s);
        return;
      }

      final server = PlatformManager().currentServer.name;
      final wsUrl = server == 'yuketang'
          ? 'wss://www.yuketang.cn/wsapp/'
          : 'wss://$server.yuketang.cn/wsapp/';
      final ws = await WebSocket.connect(wsUrl);
      if (s.closed) {
        await ws.close();
        return;
      }
      s.ws = ws;

      ws.add(jsonEncode({
        'op': 'hello',
        'userid': s.user.uid,
        'role': 'student',
        'auth': token,
        'lessonid': s.lessonId,
      }));

      s.sub = ws.listen(
        (message) => _onMessage(s, message),
        onDone: () {
          if (s.closed) return;
          logger.i('后台答题：${s.user.name} 课堂 ${s.lessonId} 连接关闭');
          s.ws = null;
          _scheduleReconnect(s);
        },
        onError: (e) {
          if (s.closed) return;
          logger.w('后台答题：${s.user.name} 课堂 ${s.lessonId} 连接错误: $e');
          s.ws = null;
          _scheduleReconnect(s);
        },
      );

      logger.i('后台答题：${s.user.name} 已接入课堂 ${s.lessonId}');
    } catch (e) {
      logger.e('后台答题连接失败（${s.user.name}/${s.lessonId}）: $e');
      _scheduleReconnect(s);
    } finally {
      s.connecting = false;
    }
  }

  void _scheduleReconnect(_LessonSession s) {
    if (s.closed) return;
    s.reconnectTimer?.cancel();
    s.reconnectTimer = Timer(const Duration(seconds: 30), () {
      if (!s.closed) unawaited(_connect(s));
    });
  }

  Future<void> _closeSession(_LessonSession s, String reason) async {
    if (s.closed) return;
    s.closed = true;
    s.reconnectTimer?.cancel();
    s.reconnectTimer = null;
    _sessions.remove(s.key);
    try {
      await s.sub?.cancel();
      await s.ws?.close();
    } catch (_) {}
    s.ws = null;
    s.sub = null;
    logger.i('后台答题：关闭 ${s.user.name} 课堂 ${s.lessonId}（$reason）');
  }

  Future<void> _closeAll(String reason) async {
    for (final s in _sessions.values.toList()) {
      await _closeSession(s, reason);
    }
  }

  // ============ 消息处理 ============

  void _onMessage(_LessonSession s, dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      if (data is! Map) return;
      final op = data['op'];

      switch (op) {
        case 'hello':
          // 老师结束课堂
          if (data['message'] == 'lesson finished') {
            unawaited(_closeSession(s, '课堂已结束'));
            return;
          }
          final presentationId = data['presentation']?.toString();
          final timeline = data['timeline'] as List?;
          final slideIndex = data['slideindex'];
          String? latestPresId = presentationId;
          if (timeline != null) {
            for (final e in timeline.reversed) {
              if (e is Map && e['type'] == 'slide' && e['pres'] != null) {
                latestPresId = e['pres'].toString();
                break;
              }
            }
          }
          if (latestPresId != null && latestPresId.isNotEmpty) {
            unawaited(_loadSlides(s, latestPresId));
          }
          if (slideIndex is int) {
            _updateSlideIndex(s, slideIndex);
          }
          break;

        case 'showpresentation':
          final presentationId = data['presentation']?.toString();
          if (presentationId != null && presentationId.isNotEmpty) {
            unawaited(_loadSlides(s, presentationId));
          }
          final slideIndex = data['slideindex'];
          if (slideIndex is int) {
            _updateSlideIndex(s, slideIndex);
          }
          break;

        case 'slide':
        case 'slidenav':
          final slide = data['slide'];
          final slideIndex = op == 'slide' ? data['slideindex'] : (slide is Map ? slide['si'] : null);
          if (slideIndex is int) {
            _updateSlideIndex(s, slideIndex);
          }
          break;

        case 'unlockproblem':
          final problemData = data['problem'];
          if (problemData is Map) {
            final problemId = problemData['prob']?.toString();
            if (problemId != null && problemId.isNotEmpty) {
              unawaited(_answerProblem(s, problemId, problemData));
            }
          }
          break;
      }
    } catch (e) {
      logger.w('后台答题：解析消息失败 $e');
    }
  }

  /// 拉取课件，缓存「题目 id → 题目内容」，供 unlockproblem 时使用
  Future<void> _loadSlides(_LessonSession s, String presentationId) async {
    if (s.presentationId == presentationId && s.problems.isNotEmpty) return;
    try {
      final api = RCCourseApi(s.user);
      final data = await api.getPresentation(presentationId);
      if (data == null) {
        logger.w('后台答题：${s.user.name} 拉取课件 $presentationId 失败');
        return;
      }
      final presentation = Presentation.fromJson(data);
      s.presentationId = presentationId;
      s.courseName ??= presentation.title;
      s.problems.clear();
      s.slides = presentation.slides;
      for (final slide in presentation.slides) {
        final problem = slide.problem;
        if (problem != null && problem.problemId.isNotEmpty) {
          s.problems[problem.problemId] = problem;
        }
      }
      _updateSlideIndex(s, s.currentSlideIndex + 1);
      logger.i('后台答题：${s.user.name} 课件已加载，'
          '题目 ${s.problems.length} 道（课堂 ${s.lessonId}）');
    } catch (e) {
      logger.e('后台答题：加载课件异常 $e');
    }
  }

  /// 更新当前放映页码（事件里的页码从 1 开始，列表下标从 0 开始）
  void _updateSlideIndex(_LessonSession s, int slideIndex) {
    final idx = slideIndex > 0 ? slideIndex - 1 : 0;
    s.currentSlideIndex = idx;
    if (idx >= 0 && idx < s.slides.length) {
      s.currentProblem = s.slides[idx].problem;
    }
  }

  /// 找出事件对应的题目内容。
  ///
  /// 优先按题目 id 精确匹配；事件 id 与课件里的 problemId 不一定完全一致，
  /// 因此再用「当前放映页的题目」「唯一一道未答过的题」兜底。
  Problem? _resolveProblem(_LessonSession s, String problemId) {
    final exact = s.problems[problemId];
    if (exact != null) return exact;

    final current = s.currentProblem;
    if (current != null &&
        !_answered.contains('${s.user.uid}|${current.problemId}')) {
      return current;
    }

    for (final slide in s.slides) {
      final p = slide.problem;
      if (p == null) continue;
      if (_answered.contains('${s.user.uid}|${p.problemId}')) continue;
      return p;
    }
    return null;
  }

  // ============ 答题 ============

  Future<void> _answerProblem(
      _LessonSession s, String problemId, Map eventProblem) async {
    final key = '${s.user.uid}|$problemId';
    if (_answered.contains(key) || _answering.contains(key)) return;
    if (!AiAnswerService().isEnabledFor(s.user.uid)) return;

    _answering.add(key);
    try {
      // 题目内容来自课件，可能比解锁事件稍晚到，短暂重试
      Problem? problem = _resolveProblem(s, problemId);
      for (var i = 0; i < 5 && problem == null; i++) {
        await Future.delayed(const Duration(milliseconds: 600));
        problem = _resolveProblem(s, problemId);
      }
      if (problem == null) {
        logger.w('后台答题：${s.user.name} 未找到题目 $problemId 的内容，跳过');
        return;
      }

      final payload = await _buildAnswer(problem);
      if (payload == null) {
        logger.w('后台答题：${s.user.name} 题目 $problemId AI 未生成答案');
        return;
      }

      final api = RCCourseApi(s.user);
      final dt = eventProblem['dt'];
      // 用课件里的题目 id 提交（与页面保持一致，服务端以课件 id 为准）
      final submitId = problem.problemId.isNotEmpty ? problem.problemId : problemId;
      final resp = await api.answer(
        submitId,
        problem.problemType,
        time: dt is int ? dt : null,
        options: payload.options,
        content: payload.content,
      );

      if (resp != null && resp['code'] == 0) {
        // 事件 id 与课件 id 都标记，保证页面/后台两侧都能正确去重
        _answered.add(key);
        _answered.add('${s.user.uid}|$submitId');
        final name = s.courseName ?? s.lessonId;
        logger.i('后台答题成功：${s.user.name} · $name · 题目 $submitId');
        _notify('AI 答题成功', '${s.user.name} 已在「$name」自动提交答案',
            threadId: s.user.uid);
      } else {
        logger.w('后台答题提交失败：${s.user.name} 题目 $problemId，'
            '返回 ${resp?['code']} ${resp?['msg'] ?? ''}');
      }
    } catch (e, st) {
      logger.e('后台答题异常: $e\n$st');
    } finally {
      _answering.remove(key);
    }
  }

  /// 按题型生成提交内容，与页面内答题保持一致的格式
  Future<_AnswerPayload?> _buildAnswer(Problem problem) async {
    final question = problem.body;
    final options = problem.options
            ?.map((o) => o.value)
            .where((v) => v.isNotEmpty)
            .toList() ??
        <String>[];

    switch (problem.problemType) {
      case 1: // 单选（判断题在课件里也是单选）
        final raw = await AiAnswerService()
            .answer(question: question, type: 'single', options: options);
        if (raw == null) return null;
        final key = _mapLetterToKey(raw, problem.options);
        return key == null ? null : _AnswerPayload(options: [key]);

      case 2: // 多选
      case 3: // 投票题按多选处理
        final raw = await AiAnswerService()
            .answer(question: question, type: 'multiple', options: options);
        if (raw == null) return null;
        final keys = _mapLettersToKeys(raw, problem.options);
        return keys.isEmpty ? null : _AnswerPayload(options: keys);

      case 4: // 填空
        final raw = await AiAnswerService()
            .answer(question: question, type: 'blank', options: null);
        if (raw == null) return null;
        final blanks = problem.blanks;
        if (blanks.isEmpty) return _AnswerPayload(options: [raw]);
        final parts = raw.split(';').map((e) => e.trim()).toList();
        return _AnswerPayload(
          options: List.generate(
            blanks.length,
            (i) => i < parts.length ? parts[i] : '',
          ),
        );

      case 5: // 主观题
      default:
        final raw = await AiAnswerService()
            .answer(question: question, type: 'short', options: null);
        if (raw == null) return null;
        return _AnswerPayload(content: raw, options: const []);
    }
  }

  /// 把 AI 返回的单个字母映射为选项 key
  String? _mapLetterToKey(String raw, List<ProblemOption>? options) {
    if (options == null || options.isEmpty) return null;
    final letter = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (letter.isEmpty) return null;
    final idx = letter.codeUnitAt(0) - 65;
    if (idx >= 0 && idx < options.length) return options[idx].key;
    for (final o in options) {
      if (o.key.toUpperCase() == letter) return o.key;
    }
    return null;
  }

  /// 把 AI 返回的字母组合（如 ABD）映射为选项 key 列表
  List<String> _mapLettersToKeys(String raw, List<ProblemOption>? options) {
    if (options == null || options.isEmpty) return [];
    final letters = raw.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    final keys = <String>[];
    for (var i = 0; i < letters.length; i++) {
      final idx = letters.codeUnitAt(i) - 65;
      if (idx >= 0 && idx < options.length) {
        final k = options[idx].key;
        if (!keys.contains(k)) keys.add(k);
      }
    }
    if (keys.isEmpty) {
      for (final o in options) {
        if (letters.contains(o.key.toUpperCase())) keys.add(o.key);
      }
    }
    return keys;
  }

  void _notify(String title, String body, {String? threadId}) {
    unawaited(NotificationService().show(
      title: title,
      body: body,
      threadId: threadId,
      androidDetails: const AndroidNotificationDetails(
        'ai_answer_channel',
        'AI 自动答题',
        channelDescription: '后台自动答题结果通知',
        importance: Importance.high,
        priority: Priority.high,
        visibility: NotificationVisibility.public,
      ),
    ));
  }
}

/// 单个「账号 × 课堂」的后台会话
class _LessonSession {
  _LessonSession({required this.user, required this.lessonId});

  final User user;
  final String lessonId;

  String? courseName;
  WebSocket? ws;
  StreamSubscription? sub;
  String? presentationId;

  /// 课件页列表与题目索引（problemId → 题目）
  List<PresentationSlide> slides = const [];
  int currentSlideIndex = 0;
  Problem? currentProblem;
  final Map<String, Problem> problems = {};

  bool connecting = false;
  bool closed = false;
  int misses = 0;
  Timer? reconnectTimer;

  String get key => '${user.uid}|$lessonId';
}

/// 待提交的答案
class _AnswerPayload {
  final List<String>? options;
  final String? content;

  const _AnswerPayload({this.options, this.content});
}
