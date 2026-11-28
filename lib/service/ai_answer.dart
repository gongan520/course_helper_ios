import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/logger.dart';
import '../utils/storage.dart';

/// AI 答题配置。
///
/// 字段含义：
/// - [apiKey]：API 密钥；
/// - [baseUrl]：API 基础地址（默认 https://api.deepseek.com）；
/// - [model]：模型名（默认 deepseek-chat，可换成 deepseek-reasoner 或其他 OpenAI 兼容模型）；
/// - [visionModel]：能看图的模型名。题目带图片（波形图、电路图、表格截图等）时优先用它；
///   留空则退回 [model]，此时 [model] 必须本身支持图片输入。
class AiAnswerConfig {
  String apiKey;
  String baseUrl;
  String model;
  String visionModel;

  AiAnswerConfig({
    this.apiKey = '',
    this.baseUrl = 'https://api.deepseek.com',
    this.model = 'deepseek-chat',
    this.visionModel = '',
  });

  factory AiAnswerConfig.fromJson(Map<String, dynamic> json) {
    return AiAnswerConfig(
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? 'https://api.deepseek.com',
      model: json['model'] as String? ?? 'deepseek-chat',
      visionModel: json['visionModel'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
      'visionModel': visionModel,
    };
  }
}

/// AI 答题服务（单例）。
///
/// 在考试/作业场景下，题目不返回正确答案时，用 AI 生成答案。
/// 默认使用 DeepSeek，但 baseUrl/model 可配置，方便换成其他兼容 OpenAI 接口的 AI。
class AiAnswerService {
  AiAnswerService._internal();

  static final AiAnswerService _instance = AiAnswerService._internal();

  factory AiAnswerService() => _instance;

  /// 配置在 SharedPreferences 中的存储 key。
  static const _key = 'ai_answer_config';

  /// 每个账号的 AI 答题开关状态：uid -> 是否启用。
  static const _enabledKey = 'ai_answer_enabled_accounts';

  /// 实时读取配置（不缓存，方便设置页改了立刻生效）。
  AiAnswerConfig get config {
    try {
      final raw = StorageManager.prefs.getString(_key);
      if (raw == null || raw.isEmpty) {
        return AiAnswerConfig();
      }
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return AiAnswerConfig.fromJson(json);
      }
      return AiAnswerConfig();
    } catch (e) {
      logger.e('读取 AI 答题配置失败: $e');
      return AiAnswerConfig();
    }
  }

  /// 保存配置。
  Future<void> updateConfig(AiAnswerConfig cfg) async {
    await StorageManager.prefs.setString(_key, jsonEncode(cfg.toJson()));
  }

  /// 获取所有账号的 AI 答题开关状态。
  Map<String, bool> get enabledAccounts {
    try {
      final raw = StorageManager.prefs.getString(_enabledKey);
      if (raw == null || raw.isEmpty) return {};
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return json.map((k, v) => MapEntry(k.toString(), v == true));
      }
      return {};
    } catch (e) {
      logger.e('读取 AI 答题账号开关失败: $e');
      return {};
    }
  }

  /// 某个账号是否启用了 AI 答题。
  bool isEnabledFor(String uid) => enabledAccounts[uid] == true;

  /// 设置某个账号的 AI 答题开关。
  Future<void> setEnabledFor(String uid, bool enabled) async {
    final map = enabledAccounts;
    map[uid] = enabled;
    await StorageManager.prefs.setString(_enabledKey, jsonEncode(map));
  }

  /// 是否已配置 API 密钥。
  bool get isConfigured => config.apiKey.trim().isNotEmpty;

  /// 是否配置了专门的视觉模型（题目带图时用）。
  bool get hasVisionModel => config.visionModel.trim().isNotEmpty;

  /// Dio 实例池。
  ///
  /// 原来每答一题都 `Dio(...)` 新建一个，等于每次重新做 DNS + TCP + TLS 握手，
  /// 白花 0.3~1 秒。复用实例能走 keep-alive 连接，第二题起几乎没有握手开销。
  static final Map<String, Dio> _dioPool = {};

  static Dio _dioFor(String baseUrl) {
    final raw = baseUrl.trim();
    final key = raw.isEmpty ? 'https://api.deepseek.com' : raw;
    return _dioPool.putIfAbsent(
      key,
      () => Dio(
        BaseOptions(
          baseUrl: key,
          // 超时全部收紧：目标是「题目解锁到提交 15 秒内」。
          // 连接 3 秒、整体 9 秒，给图片下载和提交各留出余量。
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 9),
          sendTimeout: const Duration(seconds: 6),
        ),
      ),
    );
  }

  /// 按题型限制输出长度。
  ///
  /// 不加限制时模型会把答案写成一整段解释，光等它生成就要好几秒。
  /// 选项类只允许 8~16 个 token，基本上一个字都不多写。
  static int _maxTokensFor(String type) {
    switch (type) {
      case 'single':
      case 'judge':
        // 留 16 而不是 8：有些模型会输出「答案：A」这种前缀，8 个 token 可能被截断
        return 16;
      case 'multiple':
        return 32;
      case 'blank':
        return 200;
      default:
        return 600;
    }
  }

  /// 调用 AI 生成答案。
  ///
  /// [question]：题目文字（已去掉 HTML 标签）；
  /// [type]：题型；
  /// [options]：选项列表（判断/填空/简答时可能为 null）；
  /// [images]：题目配图的 data URL 列表。
  ///   非空时按多模态请求发送，模型取 [AiAnswerConfig.visionModel]，
  ///   未配置则用 [AiAnswerConfig.model]（此时该模型必须支持看图）。
  ///
  /// 成功返回答案字符串，失败返回 null。
  ///
  /// [timeout] 覆盖默认的 9 秒整体超时。调用方按「整题总预算」传入剩余时间，
  /// 保证从题目解锁到提交不超过 15 秒。
  Future<String?> answer({
    required String question,
    required String type,
    List<String>? options,
    List<String>? images,
    Duration? timeout,
  }) async {
    final cfg = config;
    if (!isConfigured) {
      logger.e('AI 答题：未配置 API 密钥');
      return null;
    }

    final pics = images?.where((e) => e.isNotEmpty).toList() ?? const <String>[];
    final hasImage = pics.isNotEmpty;

    // 有图时必须换成能看图的模型，否则模型只能对着文字瞎猜
    final vision = cfg.visionModel.trim();
    final model = hasImage && vision.isNotEmpty ? vision : cfg.model;

    final prompt = _buildPrompt(
      question: _trimQuestion(question),
      type: type,
      options: options,
      hasImage: hasImage,
    );

    final dio = _dioFor(cfg.baseUrl);
    final headers = {
      'Authorization': 'Bearer ${cfg.apiKey}',
      'Content-Type': 'application/json',
    };
    // 单题总预算由调用方给，这里按剩余时间收紧，避免一条题把整节课的节奏拖住
    final reqOptions = Options(
      headers: headers,
      receiveTimeout: timeout,
    );

    Map<String, dynamic> payload(Object content) => {
          'model': model,
          'messages': [
            {'role': 'user', 'content': content},
          ],
          'temperature': 0.1,
          'max_tokens': _maxTokensFor(type),
          'stream': false,
        };

    try {
      Response response;
      try {
        response = await dio.post(
          '/chat/completions',
          options: reqOptions,
          data: payload(hasImage ? _multiModalContent(prompt, pics) : prompt),
        );
      } on DioException catch (e) {
        // 只有「模型明确不接受图片」（400/415/422）才退回纯文本重试 ——
        // 这种情况几乎瞬间返回，重试不亏。
        // 超时（无 status）绝对不能重试：再等一轮 10 秒就直接冲出 15 秒了。
        final status = e.response?.statusCode ?? 0;
        final rejectedImage = status == 400 || status == 415 || status == 422;
        if (!hasImage || !rejectedImage) rethrow;

        logger.w('AI 答题：模型不接受图片（$status），退回纯文本');
        response = await dio.post(
          '/chat/completions',
          options: reqOptions,
          data: payload(prompt),
        );
      }

      final content = _readContent(response.data);
      if (content == null || content.trim().isEmpty) {
        logger.e('AI 答题：响应缺少 content');
        return null;
      }
      return content;
    } on DioException catch (e) {
      logger.e('AI 答题请求失败: ${e.type} - ${e.message}'
          '${e.response?.statusCode != null ? ' (${e.response?.statusCode})' : ''}');
      return null;
    } catch (e) {
      logger.e('AI 答题解析失败: $e');
      return null;
    }
  }

  /// 题干截断。
  ///
  /// PPT 里有些题干会把整页讲义都塞进来，几千字直接拖慢首字延迟。
  /// 1500 字足够容纳任何一道题的题干，超出的部分对作答没有帮助。
  static String _trimQuestion(String q) {
    const limit = 1500;
    final s = q.trim();
    if (s.length <= limit) return s;
    return '${s.substring(0, limit)}…';
  }

  /// OpenAI 多模态格式：文本 + 若干图片。
  ///
  /// `detail: low` 让服务端先把图缩到 512×512 再推理：
  /// 上传体积小（大图 base64 能到几 MB）、推理也快，是 15 秒目标的关键。
  /// 波形图这类题如果因为缩图看不清，可以按题型把这里换成 original。
  static List<Map<String, dynamic>> _multiModalContent(
    String text,
    List<String> images,
  ) {
    return [
      {'type': 'text', 'text': text},
      for (final img in images)
        {
          'type': 'image_url',
          'image_url': {'url': img, 'detail': 'low'},
        },
    ];
  }

  /// 取响应里的答案正文。
  ///
  /// 多数接口是 `choices[0].message.content` 字符串，
  /// 部分模型会返回 content 数组（`[{type:text, text:...}]`），这里统一处理。
  static String? _readContent(dynamic data) {
    if (data is! Map) return null;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final msg = choices[0] is Map ? (choices[0] as Map)['message'] : null;
    if (msg is! Map) return null;
    final content = msg['content'];
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map && part['text'] != null) buf.write(part['text']);
      }
      return buf.isEmpty ? null : buf.toString();
    }
    return null;
  }

  /// 根据题型构造 prompt，让 AI 只返回答案本身。
  String _buildPrompt({
    required String question,
    required String type,
    List<String>? options,
    bool hasImage = false,
  }) {
    // 题目带图时统一加一句交代，否则模型容易忽略图片
    const imageHint =
        '（题目附有图片，图中含有解题所需的关键信息 —— 例如波形、坐标轴、电路或表格，'
        '请先仔细读图再作答。）\n';

    final prefix = hasImage ? imageHint : '';

    switch (type) {
      case 'single':
        final lines = <String>[
          '${prefix}请从以下选项中选择唯一正确答案，只回复选项字母（如 A、B、C、D），不要任何解释。',
          '题目：$question',
          '选项：',
        ];
        if (options != null) {
          for (var i = 0; i < options.length; i++) {
            lines.add('${String.fromCharCode(65 + i)}. ${options[i]}');
          }
        }
        return lines.join('\n');

      case 'multiple':
        final lines = <String>[
          '${prefix}请从以下选项中选择所有正确答案（可能多个），只回复选项字母组合（如 ABD），不要任何解释。',
          '题目：$question',
          '选项：',
        ];
        if (options != null) {
          for (var i = 0; i < options.length; i++) {
            lines.add('${String.fromCharCode(65 + i)}. ${options[i]}');
          }
        }
        return lines.join('\n');

      case 'judge':
        return '${prefix}请判断以下说法是否正确，只回复"正确"或"错误"两个字，不要任何解释。\n题目：$question';

      case 'blank':
        return '${prefix}请回答以下填空题，只回复填空的答案，多个空用分号分隔，不要任何解释。\n题目：$question';

      case 'short':
        return '${prefix}请回答以下题目，给出简洁、准确的答案，直接回复答案内容，不要复述题目。\n'
            '题目：$question';

      default:
        // 未知题型按简答处理。
        return '${prefix}请回答以下题目，给出简洁、准确的答案，直接回复答案内容，不要复述题目。\n'
            '题目：$question';
    }
  }
}
