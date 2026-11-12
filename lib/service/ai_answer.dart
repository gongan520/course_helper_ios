import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/logger.dart';
import '../utils/storage.dart';

/// AI 答题配置。
///
/// 字段含义：
/// - [apiKey]：DeepSeek API 密钥；
/// - [baseUrl]：API 基础地址（默认 https://api.deepseek.com）；
/// - [model]：模型名（默认 deepseek-chat，可换成 deepseek-reasoner 或其他 OpenAI 兼容模型）。
class AiAnswerConfig {
  String apiKey;
  String baseUrl;
  String model;

  AiAnswerConfig({
    this.apiKey = '',
    this.baseUrl = 'https://api.deepseek.com',
    this.model = 'deepseek-chat',
  });

  factory AiAnswerConfig.fromJson(Map<String, dynamic> json) {
    return AiAnswerConfig(
      apiKey: json['apiKey'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? 'https://api.deepseek.com',
      model: json['model'] as String? ?? 'deepseek-chat',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'model': model,
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

  /// 是否已配置 API 密钥。
  bool get isConfigured => config.apiKey.trim().isNotEmpty;

  /// 调用 AI 生成答案。
  ///
  /// [question]：题目内容；[type]：题型；[options]：选项列表（判断/填空/简答时可能为 null）。
  /// 成功返回答案字符串，失败返回 null。
  Future<String?> answer({
    required String question,
    required String type,
    List<String>? options,
  }) async {
    final cfg = config;
    if (!isConfigured) {
      logger.e('AI 答题：未配置 API 密钥');
      return null;
    }

    final prompt = _buildPrompt(question: question, type: type, options: options);

    // 使用独立的 Dio 实例，避免污染学习通/雨课堂的 cookie/header。
    final dio = Dio(
      BaseOptions(
        baseUrl: cfg.baseUrl,
        connectTimeout: const Duration(seconds: 60),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    try {
      final response = await dio.post(
        '/chat/completions',
        options: Options(
          headers: {
            'Authorization': 'Bearer ${cfg.apiKey}',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': cfg.model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
          'stream': false,
        },
      );

      final content = response.data['choices'][0]['message']['content'];
      if (content == null) {
        logger.e('AI 答题：响应缺少 content');
        return null;
      }
      return content.toString();
    } on DioException catch (e) {
      logger.e('AI 答题请求失败: ${e.type} - ${e.message}');
      return null;
    } catch (e) {
      logger.e('AI 答题解析失败: $e');
      return null;
    }
  }

  /// 根据题型构造 prompt，让 AI 只返回答案本身。
  String _buildPrompt({
    required String question,
    required String type,
    List<String>? options,
  }) {
    switch (type) {
      case 'single':
        final lines = <String>[
          '请从以下选项中选择唯一正确答案，只回复选项字母（如 A、B、C、D），不要任何解释。',
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
          '请从以下选项中选择所有正确答案（可能多个），只回复选项字母组合（如 ABD），不要任何解释。',
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
        return '请判断以下说法是否正确，只回复"正确"或"错误"两个字，不要任何解释。\n题目：$question';

      case 'blank':
        return '请回答以下填空题，只回复填空的答案，多个空用分号分隔，不要任何解释。\n题目：$question';

      case 'short':
        return '请回答以下题目，给出简洁、准确的答案，直接回复答案内容，不要复述题目。\n题目：$question';

      default:
        // 未知题型按简答处理。
        return '请回答以下题目，给出简洁、准确的答案，直接回复答案内容，不要复述题目。\n题目：$question';
    }
  }
}
