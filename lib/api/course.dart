import 'api_service.dart';
import '../utils/encrypt.dart';
import '../utils/logger.dart';
import '../models/active.dart';
import '../models/course.dart';

class CXCourseApi extends Api {
  CXCourseApi([super.user]);

  /// 获取课程列表
  static Future<Map<String, dynamic>?> getCourses({String? userId}) async {
    final url = 'https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&getTchClazzType=1&mcode=';
    
    final response = await ApiService.sendRequest(url, userId: userId);
    return response?.data;
  }

  /// 获取处理后的课程列表
  static Future<List<Course>?> getCoursesList({String? userId}) async {
    final coursesData = await getCourses(userId: userId);
    
    if (coursesData == null || coursesData['result'] != 1) {
      return null;
    }

    List<Course> courses = [];
    List<dynamic> channelList = coursesData['channelList'];

    for (var channel in channelList) {
      if (channel['content']['course'] != null) {
        courses.add(Course.fromCXJson(channel));
      }
    }

    return courses.where((course) => course.state).toList();
  }

  /// 获取加入课程时间作为参数
  Future<String?> getJoinClassTime(String courseId, String classId, String cpi) async {
    final url = 'https://mooc1-api.chaoxing.com/gas/clazzperson';
    final params = {
      'courseid': courseId,
      'clazzid': classId,
      'userid': user!.uid,
      'personid': cpi,
      'view': 'json',
      'fields': 'clazzid,popupagreement,personid,clazzname,createtime'
    };

    final response = await ApiService.sendRequest(url, params: params, userId: user?.uid);
    if (response == null) return null;

    return response.data['data'][0]['createtime'];
  }

  /// 获取任务活动列表
  Future<Map<String, dynamic>?> getTaskActivityList(String courseId, String classId, String cpi, String joinClassTime) async {
    final url = 'https://mobilelearn.chaoxing.com/ppt/activeAPI/taskactivelist';

    final params = {
      'courseId': courseId,
      'classId': classId,
      'uid': user!.uid,
      'cpi': cpi,
      'joinclasstime': joinClassTime
    };
    params.addAll(EncryptionUtil.getEncParams(params));

    final response = await ApiService.sendRequest(url, method: 'GET', params: params, userId: user?.uid);
    return response?.data;
  }

  /// 获取任务活动列表（Web）
  static Future<Map<String, dynamic>?> getTaskActivityListWeb(String courseId, String classId, {String? userId}) async {
    final url = 'https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist';

    final timeStampMS = DateTime.now().millisecondsSinceEpoch.toString();
    final params = {
      'fid': '0',
      'courseId': courseId,
      'classId': classId,
      'showNotStartedActive': '0',
      '_': timeStampMS
    };

    final response = await ApiService.sendRequest(url, method: 'GET', params: params, userId: userId);
    return response?.data;
  }

  /// 获取合并处理后的活动列表
  Future<List<Active>?> getActiveList(String courseId, String classId, String cpi) async {
    final joinClassTime = await getJoinClassTime(courseId, classId, cpi) ?? '';
      
    final results = await Future.wait([
      getTaskActivityList(courseId, classId, cpi, joinClassTime),
      getTaskActivityListWeb(courseId, classId, userId: user?.uid),
    ]);
      
    final taskData = results[0];
    final webTaskData = results[1];

    if (taskData == null || webTaskData == null) {
      return null;
    }

    List<Active> contentList = [];
    List<dynamic> activeList = taskData['activeList'];
    List<dynamic> webActiveList = webTaskData['data']['activeList'];

    Map<String, dynamic> activeMap = {
      for (var activeItem in webActiveList) activeItem['id'].toString(): activeItem
    };

    for (var activeData in activeList) {
      Active active = Active.fromJson(activeData);
      String activeId = activeData['id'].toString();

      if (activeMap.containsKey(activeId)) {
        var activeItem = activeMap[activeId];
        if (active.status) {
          if (active.description.isEmpty) {
            active.description = activeItem['nameFour'];
          }
        }

        if (active.activeType == ActiveType.signIn ||
            active.activeType == ActiveType.signOut) {
          final otherId = activeItem['otherId'];
          if (otherId != null) {
            try {
              active.signType = getSignTypeFromIndex(int.parse(otherId));
            } catch (e) {
              logger.e('解析 otherId 失败：$otherId, 错误：$e');
            }
          }
        }
      }
      contentList.add(active);
    }

    return contentList;
  }
}

class RCCourseApi extends Api {
  RCCourseApi([super.user]);

  // userId -> [bearerToken, lessonToken]
  static final Map<String, List<String>> _tokens = {};

  /// 获取当前用户的 bearerToken
  String? get bearerToken => _tokens[user!.uid]?[0];

  String? get lessonToken => _tokens[user!.uid]?[1];

  void _setToken(String bearerToken, String lessonToken) {
    _tokens[user!.uid] = [bearerToken, lessonToken];
  }

  static Future<Map<String, dynamic>?> getCourses({String? userId}) async {
    final url = '/v/course_meta/learning_list/';
    final response = await ApiService.sendRequest(url, userId: userId);
    return response?.data;
  }

  /// 获取该账号自己选修的全部课程 ID 集合（权威归属数据源）。
  ///
  /// 直接来自 `/v/course_meta/learning_list/`（学习列表），这是账号真正选修的课，
  /// 不包含「历史上被 joinIfNotIn 误拉进别人教室」的脏数据。
  ///
  /// 返回 null 表示「拿不到权威数据」（接口失败 / 结构异常），
  /// 此时调用方应当**跳过该账号的自动签到**而不是放行 —— 宁可不签，不可串签。
  static Future<Set<String>?> getOwnCourseIds({String? userId}) async {
    final courses = await getCourses(userId: userId);
    if (courses == null) return null;

    final data = courses['data'];
    if (data is! List || data.isEmpty) return null;

    final ids = <String>{};
    for (final item in data) {
      if (item is! Map) continue;
      // 兼容多种字段名：course_id / courseId / id，以及嵌套的 course 对象
      final direct = item['course_id'] ??
          item['courseId'] ??
          item['id'];
      if (direct != null && direct.toString().isNotEmpty) {
        ids.add(direct.toString());
        continue;
      }
      // 有些版本把课程对象嵌在 course 字段下
      final nested = item['course'];
      if (nested is Map) {
        final nid = nested['course_id'] ?? nested['id'];
        if (nid != null && nid.toString().isNotEmpty) {
          ids.add(nid.toString());
        }
      }
    }
    if (ids.isEmpty) return null;
    return ids;
  }

  /// 获取正在上课的课程
  static Future<List<dynamic>?> getOnLesson({String? userId}) async {
    // final url = '/api/v3/classroom/on-lesson-upcoming-exam';
    final url = '/api/v3/classroom/on-lesson';
    final response = await ApiService.sendRequest(url, userId: userId);
    if (response?.data['code'] == 0){
      return response?.data['data']['onLessonClassrooms'];
    }
    return null;
  }

  /// 获取处理后的课程列表
  static Future<List<Course>?> getCoursesList([List<dynamic>? onLessonCourses, String? userId]) async {
    late Map<String, dynamic>? courses;
    if (onLessonCourses == null) {
      final results = await Future.wait([getCourses(userId: userId), getOnLesson(userId: userId)]);
      courses = results[0] as Map<String, dynamic>?;
      onLessonCourses = results[1] as List<dynamic>?;
    } else {
      courses = await getCourses(userId: userId);
    }

    if (courses == null || onLessonCourses == null) {
      return null;
    }
    final data = courses['data'];
    if (data == null || data.isEmpty || onLessonCourses.isEmpty) {
      return null;
    }

    Map<String, dynamic> coursesMap = {
      for (var courseItem in courses['data']) courseItem['course_id'].toString(): courseItem
    };

    List<Course> contentList = [];

    for (var onLessonCourseItem in onLessonCourses){
      final String courseId = onLessonCourseItem['courseId'];
      if (coursesMap.containsKey(courseId)) {
        var courseItem = coursesMap[courseId];
        courseItem['lesson_id'] = onLessonCourseItem['lessonId'];
        final courseObject = Course.fromRCJson(courseItem);
        contentList.add(courseObject);
      }
    }

    return contentList;
  }

  Future<int?> checkIn(String lessonId) async {
    final url = '/api/v3/lesson/checkin';
    final jsonData = {
      'source': 21,
      'lessonId': lessonId,
      // joinIfNotIn 设为 false：不再把账号强行拉进「不在这节课」的教室。
      // 之前的 true 是串课污染的源头 —— 账号 A 一旦被误触发签到 B 的课，
      // A 就被永久拉进 B 的教室，之后 getOnLesson 会一直返回 B 的课。
      // 现在签到前已经用 getOwnCourseIds 校验了课程归属，不属于自己的课根本不会走到这里。
      'joinIfNotIn': false
    };
    final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData, userId: user?.uid);
    if (response == null) return null;
    
    final data = response.data;
    final int code = data['code'];
    if (code == 0) {
      final bearerToken = response.headers.value('set-auth')!;
      final lessonToken = data['data']['lessonToken'];
      _setToken(bearerToken, lessonToken);
      return 0;
    } else {
      return code;
    }
  }

  Future<int?> scan(String qrCodeUrl) async {
    final url = '/api/v3/app/scan';
    final jsonData = {'url': qrCodeUrl};
    final response = await ApiService.sendRequest(url, method: 'POST', body: jsonData, userId: user?.uid);
    if (response == null) return null;
    
    final data = response.data;
    final int code = data['code'];
    if (code == 0) {
      final lessonId = data['data']['value'];
      final response = await checkIn(lessonId);
      return response;
    } else {
      return code;
    }
  }

  /// 获取签到状态
  Future<Map<String, dynamic>?> getCheckIn() async {
    final url = '/api/v3/lesson/location-checkin/eligibility';
    final headers = {'authorization': 'Bearer $bearerToken'};
    final response = await ApiService.sendRequest(url, headers: headers, userId: user?.uid);
    if (response == null) return null;

    // {'needLocationSignIn': False, 'signed': True, 'mode': 'signed', 'checkInTime': 1789133627322, 'address': ''}
    return response.data;
  }

  Future<Map<String, dynamic>?> submitLocationCheckIn(String lessonId, double latitude, double longitude, String address) async {
    final url = '/api/v3/lesson/location-checkin/submit';
    final headers = {'authorization': 'Bearer $bearerToken'};
    final jsonData = {
      "lat": latitude,
      "lng": longitude,
      "lessonId": lessonId,
      "source": 54,
      "address": address
    };
    final response = await ApiService.sendRequest(url, method: 'POST', headers: headers, body: jsonData, userId: user?.uid);
    if (response == null) return null;

    return response.data;
  }

  Future<Map<String, dynamic>?> getPresentation(String presentationId) async {
    final url = '/api/v3/lesson/presentation/fetch?presentation_id=$presentationId';
    if (bearerToken == null) {
      return null;
    }
    final headers = {'authorization': 'Bearer $bearerToken'};
    final response = await ApiService.sendRequest(url, headers: headers, userId: user?.uid);
    return response?.data['data'];
  }

  /// 提交答案
  Future<Map<String, dynamic>?> answer(String problemId, int problemType,
      {bool retry = false, int? time, List<String>? options, String? content, List<String>? imageUrls}) async {
    final url = retry ?
    '/api/v3/lesson/problem/retry' : '/api/v3/lesson/problem/answer';
    if (bearerToken == null) {
      return null;
    }
    final headers = {'authorization': 'Bearer $bearerToken'};
    final timeStampMS = time ?? DateTime.now().millisecondsSinceEpoch;
    late dynamic result;
    if (problemType == 5) {
      var pics = [];
      if (imageUrls != null) {
        for (var imageUrl in imageUrls) {
          pics.add({
            'pic': imageUrl,
            'thumb': '$imageUrl?imageView2/2/w/568'
          });
        }
      } else {
        pics = [{'pic': '', 'thumb': ''}];
      }
      result = {'content': content ?? '', 'pics': pics, 'videos': []};
    } else {
      result = options;
    }
    var jsonData = {
      'problemId': problemId,
      'dt': timeStampMS,
      'problemType': problemType,
      'result': result
    };
    if (retry) {
      jsonData['retry_times'] = null;
      jsonData = {'problems': [jsonData]};
    }
    final response = await ApiService.sendRequest(url, method: 'POST', headers: headers, body: jsonData, userId: user?.uid);
    return response?.data;
  }
}