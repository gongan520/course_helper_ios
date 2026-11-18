import 'package:flutter/material.dart';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../platform.dart';
import '../../api/course.dart';
import '../../api/api_service.dart';
import '../../session/account.dart';
import '../../models/course.dart';
import '../../models/active.dart';
import '../../models/user.dart';
import '../../utils/logger.dart';
import '../widget/scan.dart';
import '../widget/avatar.dart';
import '../actives/sign_in/sign_in.dart';
import '../actives/topic_discuss.dart';
import '../actives/quiz.dart';
import '../actives/evaluate.dart';
import '../actives/vote.dart';
import '../actives/questionnaire.dart';
import '../actives/pick.dart';
import 'content.dart';
import '../presentation.dart';
import '../push/groups.dart';
import '../../push/easemob.dart';
import '../../push/notification.dart';


class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key});

  @override
  State<CoursesPage> createState() => _CoursesPageState();

  static void navigateToActive(BuildContext context, Active active, String courseId, String classId, String cpi) {
    if (!active.status) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该活动已结束')),
      );
      return;
    }

    switch (active.activeType) {
      case ActiveType.signIn:
      case ActiveType.signOut:
      case ActiveType.scheduledSignIn:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SignInPage(
              active: active,
              courseId: courseId,
              classId: classId,
              cpi: cpi
            ),
          ),
        );
        break;
      
      case ActiveType.topicDiscuss:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TopicDiscussPage(active: active),
          ),
        );
        break;
      
      case ActiveType.quiz:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuizPage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;
      
      case ActiveType.evaluation:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EvaluatePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;
      
      case ActiveType.vote:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VotePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;

      case ActiveType.questionnaire:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QuestionnairePage(
              active: active,
              courseId: courseId,
              classId: classId
            ),
          ),
        );
        break;

      case ActiveType.pick:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PickPage(active: active),
          ),
        );
        break;

      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该活动类型暂不支持'),
          ),
        );
    }
  }
}

final GlobalKey coursesPageKey = GlobalKey();

class _CoursesPageState extends State<CoursesPage> with WidgetsBindingObserver {
  List<Course> _courses = [];
  bool _isLoading = true;
  StreamSubscription? _accountChangeSubscription;
  StreamSubscription? _messageStoreSubscription;
  Timer? _refreshTimer;
  List<dynamic> _lastOnLessonCourses = [];
  bool _hasInitialOnLessonData = false;
  bool _isVisible = false;

  void refreshCourses() {
    _loadCourses();
  }

  void onVisibilityChanged(bool visible) {
    _isVisible = visible;
    if (visible) {
      _startPeriodicRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  /// 使用在线课堂数据更新课程列表
  void updateWithOnLessonCourses(List<Map<String, dynamic>>? onLessonCourses) {
    _loadCourses(onLessonCourses);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isVisible = true;
    _loadCourses();

    // 消息未读变化时重绘
    _messageStoreSubscription =
        ActivityMessageStore().changes.listen((_) {
          if (mounted) setState(() {});
        });

    // 监听账户变更事件
    _accountChangeSubscription =
        AccountChangeNotifier().accountChanges.listen((_) {
          ActivityMessageStore().clearAll();
          if (mounted) {
            _lastOnLessonCourses = [];
            _hasInitialOnLessonData = false;
            _loadCourses();
          }
          _startPeriodicRefresh();
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _refreshTimer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _startPeriodicRefresh();
    }
  }

  void _startPeriodicRefresh() {
    if (!_isVisible || PlatformManager().isChaoxing) return;

    if (_refreshTimer != null && _refreshTimer!.isActive) return;

    // 6 秒一轮：3 秒时请求过密，服务端限流反而更容易出现列表抖动
    _refreshTimer = Timer.periodic(const Duration(seconds: 6), (_) async {
      if (!mounted || !AccountManager.hasActiveSession()) return;

      // 锁定本次请求所属账号。
      // 不传 uid 时接口会退回全局 currentSessionId，而它可能被后台任务或
      // 其他账号的请求改掉，结果就是把别人正在上的课刷进当前账号的列表里
      // （同一门课不同教学班时尤其明显）。
      final uid = AccountManager.currentUser?.uid;
      if (uid == null) return;

      try {
        final onLessonCourses = await RCCourseApi.getOnLesson(userId: uid);
        if (onLessonCourses == null || !mounted) return;
        // 请求期间用户切换了账号：这批数据属于旧账号，直接丢弃
        if (AccountManager.currentSessionId != uid) return;

        if (!const DeepCollectionEquality().equals(_lastOnLessonCourses, onLessonCourses)) {
          final newCourseIds = _hasInitialOnLessonData ?
          _diffNewCourseIds(_lastOnLessonCourses, onLessonCourses) : <String>[];
          _lastOnLessonCourses = onLessonCourses;
          _hasInitialOnLessonData = true;
          await _loadCourses(onLessonCourses, uid: uid);
          if (newCourseIds.isNotEmpty) {
            _notifyNewLessons(newCourseIds);
          }
        }
      } catch (e) {
        logger.e('Periodic refresh error: $e');
      }
    });
  }

  List<String> _diffNewCourseIds(List<dynamic> previous, List<dynamic> current) {
    final previousIds = previous
        .map((e) => (e['courseId'] ?? '').toString())
        .toSet();
    return current
        .where((e) => !previousIds.contains((e['courseId'] ?? '').toString()))
        .map((e) => (e['courseId'] ?? '').toString())
        .toList();
  }

  void _notifyNewLessons(List<String> courseIds) {
    for (final courseId in courseIds) {
      final course = _courses.firstWhereOrNull((c) => c.courseId == courseId);
      final name = course?.name;
      NotificationService().show(
        title: '课堂开始',
        body: '$name 开始上课了',
        androidDetails: const AndroidNotificationDetails(
          'lesson_start_channel',
          '课堂开始',
          channelDescription: '雨课堂课堂开始上课通知',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public
        ),
      );
    }
  }

  /// 加载课程列表。
  ///
  /// [uid] 显式指定要加载哪个账号的课。不传则取当前账号快照，
  /// 保证「请求期间切换了账号」时不会把旧账号的数据写进新账号的列表。
  Future<void> _loadCourses([List<dynamic>? onLessonCourses, String? uid]) async {
    setState(() {
      _isLoading = true;
    });

    if (!AccountManager.hasActiveSession()) {
      setState(() {
        _courses = [];
        _isLoading = false;
      });
      return;
    }

    final targetUid = uid ?? AccountManager.currentUser?.uid;

    try {
      late List<Course>? coursesData;
      if (PlatformManager().isChaoxing) {
        coursesData = await CXCourseApi.getCoursesList();
      } else if (PlatformManager().isRainClassroom) {
        coursesData = await RCCourseApi.getCoursesList(onLessonCourses, targetUid);
      }

      // 期间又切了账号：这批结果属于上一个账号，丢弃而不是覆盖
      if (!mounted) return;
      if (targetUid != null && AccountManager.currentSessionId != targetUid) return;

      if (coursesData != null && coursesData.isNotEmpty) {
        setState(() {
          _courses = coursesData!;
          _isLoading = false;
        });
      } else {
        setState(() {
          _courses = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _courses = [];
        _isLoading = false;
      });
    }
  }

  Future<void> handleScanContent(String result) async {
    if (!AccountManager.hasActiveSession()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('二维码内容'),
              content: SelectableText(result),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      });
      return;
    }
  
    if (result.startsWith('http')) {
      try {
        final uri = Uri.parse(result);
        final baseUrl = uri.origin + uri.path;
        final params = uri.queryParameters;
  
        // 判断是否为签到 URL
        if (baseUrl == 'https://mobilelearn.chaoxing.com/widget/sign/e') {
          if (!PlatformManager().isChaoxing) {
            await PlatformManager().setPlatform(PlatformType.chaoxing);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自动切换平台为学习通')),
            );
          }
          if (!AccountManager.hasActiveSession()) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('提示'),
                  content: const Text('没有可用账号'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
            return;
          }
  
          final activeId = params['id'];
          if (activeId != null) {
            final response = await ApiService.sendRequest(result, responseType: ResponseType.plain, allowRedirects: false);
            if (response == null) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请求失败')),
              );
              return;
            }
            final locationUrl = response.headers['location']?.first;

            final uri = Uri.parse(locationUrl!);
            final params = uri.queryParameters;

            final classId = params['classId'] ?? '';
            final decodedRcode = Uri.decodeComponent(params['rcode']!);
            RegExp encRegex = RegExp(r'enc=([^&\s]+)');
            Match? match = encRegex.firstMatch(decodedRcode);

            if (match != null) {
              final enc = match.group(1);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SignInPage(
                    active: Active(
                        type: 2,
                        id: activeId,
                        name: '二维码签到',
                        description: '',
                        startTime: 0,
                        url: '',
                        attendNum: 0,
                        status: true,
                        signType: SignType.qrCode
                    ),
                    courseId: '',
                    classId: classId,
                    cpi: '',
                    enc: enc
                  ),
                ),
              );
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('未找到 enc 参数')),
              );
            }
          }
        } else if (baseUrl.contains('.yuketang.cn/api/v3/lesson/check-in/dynamic-qr-code')){
          if (!PlatformManager().isRainClassroom) {
            await PlatformManager().setPlatform(PlatformType.rainClassroom);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('自动切换平台为雨课堂')),
            );
          }
          if (!AccountManager.hasActiveSession()) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  content: const Text('没有可用账号'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                );
              },
            );
            return;
          }
  
          await _multiScan(context, result);
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('扫描到链接'),
                  content: SelectableText(result),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    ),
                  ],
                );
              },
            );
          });
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL 解析失败：$e')),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描结果：$result')),
      );
    }
  }

  /// 从雨课堂动态二维码链接里尽量解析 lessonId（解析不到返回 null）
  String? _lessonIdFromQrUrl(String url) {
    try {
      final q = Uri.parse(url).queryParameters;
      for (final key in const ['lessonId', 'lesson_id', 'lessonid']) {
        final v = q[key];
        if (v != null && v.isNotEmpty) return v;
      }
      final m = RegExp(r'lessonId[=/](\d+)', caseSensitive: false).firstMatch(url);
      if (m != null) return m.group(1);
    } catch (e) {
      logger.w('解析二维码链接 lessonId 失败: $e');
    }
    return null;
  }

  /// 找出「确实有这节课」的账号
  Future<List<User>> _accountsHavingLesson(String lessonId) async {
    final result = <User>[];
    for (final user in AccountManager.allAccounts) {
      try {
        final onLesson = await RCCourseApi.getOnLesson(userId: user.uid);
        final has = onLesson?.any(
              (e) => e['lessonId']?.toString() == lessonId,
            ) ??
            false;
        if (has) result.add(user);
      } catch (e) {
        logger.w('检查账号 ${user.name} 是否在课堂 $lessonId 失败: $e');
      }
    }
    return result;
  }

  /// 扫码签到。
  ///
  /// 只对「本就在这节课里」的账号扫码：scan 成功后内部会 checkIn，
  /// 而 checkIn 带 joinIfNotIn，会把无关账号强行拉进别人的课堂。
  Future<void> _multiScan(BuildContext context, String qrCodeUrl) async {
    if (AccountManager.allAccounts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的账号进行签到'))
      );
      return;
    }

    final lessonId = _lessonIdFromQrUrl(qrCodeUrl);
    var targets = lessonId == null
        ? <User>[]
        : await _accountsHavingLesson(lessonId);
    if (lessonId == null) {
      logger.w('二维码链接中未解析到 lessonId，仅当前账号扫码签到');
    } else {
      logger.i('扫码签到 lessonId=$lessonId，命中账号 '
          '${targets.length}/${AccountManager.allAccounts.length}');
    }

    // 当前会话账号始终保留（用户主动扫的码）
    final current = AccountManager.currentUser;
    if (current != null && !targets.any((u) => u.uid == current.uid)) {
      targets = [current];
    }

    if (targets.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的账号进行签到'))
      );
      return;
    }

    final allAccounts = targets;
  
    setState(() {
      _isLoading = true;
    });
  
    int successCount = 0;
    final List<String> failedAccounts = [];
  
    final results = await ApiService.sendForEachUser(
      allAccounts,
      (user) async {
        final api = RCCourseApi(user);
        return await api.scan(qrCodeUrl);
      },
    );

    for (int i = 0; i < results.length; i++) {
      final status = results[i];
      final user = allAccounts[i];
      
      if (status == 0) {
        successCount++;
      } else if (status == 51203) {
        failedAccounts.add('${user.name} (动态二维码过期)');
      } else {
        failedAccounts.add('${user.name} (错误码：$status)');
      }
    }
    
  
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  
    _showMultiScanResult(context, successCount, allAccounts.length, failedAccounts);
  }

  /// 显示所有签到结果
  void _showMultiScanResult(BuildContext context, int successCount, int totalCount, List<String> failedAccounts) {
    String message = '签到完成！\n成功: $successCount/$totalCount';
    if (failedAccounts.isNotEmpty) {
      message += '\n\n失败账号:\n${failedAccounts.join('\n')}';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          successCount == totalCount ? '全部签到成功' : '部分失败',
          style: TextStyle(
            color: successCount == totalCount ? Colors.green : Colors.orange,
          ),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  List<Course> _sortedCourses() {
    final unread = _courses
        .where((c) => ActivityMessageStore().countOf(c.courseId, c.classId) > 0)
        .toList();
    final rest = _courses
        .where((c) => ActivityMessageStore().countOf(c.courseId, c.classId) == 0)
        .toList();
    return [...unread, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final courses = _sortedCourses();
    return Scaffold(
      appBar: AppBar(
        title: const Text('课程'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (PlatformManager().isChaoxing)
            IconButton(
              icon: const Icon(Icons.group),
              tooltip: '群聊',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GroupsPage(),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ScanPage(
                    onScanResult: handleScanContent,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCourses,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _courses.isEmpty
            ? Center(
                child: Text(
                  PlatformManager().isRainClassroom ? '暂无正在上课的课程' : '暂无内容',
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              )
            : ListView.builder(
                itemCount: courses.length,
                itemBuilder: (context, index) {
                  final course = courses[index];
                  final count = ActivityMessageStore().countOf(course.courseId, course.classId);

                  Widget avatar;
                  if (course.image.isNotEmpty) {
                    avatar = AvatarWidget(
                      imageUrl: course.image,
                      size: 50,
                      borderRadius: 6,
                      iconSize: 25,
                    );
                  } else {
                    avatar = Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.school,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          size: 25,
                        ),
                      ),
                    );
                  }

                  final card = Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: InkWell(
                      onTap: () {
                        ActivityMessageStore().clear(course.courseId, course.classId);
                        Navigator.push(
                          context,
                          PlatformManager().isChaoxing ?
                          MaterialPageRoute(
                            builder: (context) => CourseContentPage(
                              courseId: course.courseId,
                              courseName: course.name,
                              classId: course.classId,
                              cpi: course.cpi!
                            ),
                          ) : MaterialPageRoute(
                            builder: (context) => PresentationPage(
                              lessonId: course.lessonId!,
                              title: course.name
                            ),
                          ),
                        );
                      },
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (count > 0)
                                      Badge(
                                        label: Text('$count'),
                                        child: avatar
                                      )
                                    else
                                      avatar,
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            course.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            course.teacher,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
          
                                const SizedBox(height: 5),
                                if (course.note != null)
                                  Text(
                                    course.note!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (course.schools != null)
                                  Text(
                                    course.schools!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                if (course.beginDate != null && course.endDate != null)
                                  Text(
                                    '开课时间：${course.beginDate} 至 ${course.endDate}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 16,
                            top: 0,
                            bottom: 0,
                            child: Align(
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.chevron_right,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  return card;
                },
              ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountChangeSubscription?.cancel();
    _messageStoreSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
