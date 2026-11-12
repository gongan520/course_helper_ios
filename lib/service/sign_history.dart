import 'dart:convert';

import '../utils/storage.dart';

/// 单条签到历史记录
class SignHistoryRecord {
  final DateTime time;
  final String accountName; // 账号名
  final String platform; // 平台显示名（学习通 / 雨课堂）
  final String target; // 课程 / 活动名称
  final bool success; // 是否签到成功

  SignHistoryRecord({
    required this.time,
    required this.accountName,
    required this.platform,
    required this.target,
    required this.success,
  });

  factory SignHistoryRecord.fromJson(Map<String, dynamic> json) {
    return SignHistoryRecord(
      time: DateTime.fromMillisecondsSinceEpoch(json['time'] ?? 0),
      accountName: json['accountName']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      success: json['success'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'time': time.millisecondsSinceEpoch,
        'accountName': accountName,
        'platform': platform,
        'target': target,
        'success': success,
      };
}

/// 签到历史记录存储（持久化到本地）
class SignHistoryStore {
  SignHistoryStore._internal();
  static final SignHistoryStore _instance = SignHistoryStore._internal();
  factory SignHistoryStore() => _instance;

  static const _key = 'auto_sign_history';
  static const _maxEntries = 50;

  List<SignHistoryRecord> _records = [];
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = StorageManager.prefs.getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = json.decode(raw) as List;
        _records = list
            .map((e) => SignHistoryRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _records = [];
      }
    }
    _loaded = true;
  }

  /// 最近 [limit] 条记录，按时间倒序
  Future<List<SignHistoryRecord>> recent({int limit = 10}) async {
    await _ensureLoaded();
    final sorted = List<SignHistoryRecord>.from(_records)
      ..sort((a, b) => b.time.compareTo(a.time));
    return sorted.take(limit).toList();
  }

  /// 新增一条记录
  Future<void> add(SignHistoryRecord record) async {
    await _ensureLoaded();
    _records.insert(0, record);
    if (_records.length > _maxEntries) {
      _records = _records.sublist(0, _maxEntries);
    }
    await _save();
  }

  /// 清空所有记录
  Future<void> clear() async {
    await _ensureLoaded();
    _records.clear();
    await _save();
  }

  Future<void> _save() async {
    await StorageManager.prefs.setString(
      _key,
      json.encode(_records.map((e) => e.toJson()).toList()),
    );
  }
}
