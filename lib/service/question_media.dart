import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../api/api_service.dart';
import '../platform.dart';
import '../utils/logger.dart';

/// 题目里的图片处理。
///
/// 雨课堂的题干是 HTML 片段，形如：
///   `<p>请给出下图 4ASK 所表示数字信息（　）。</p><p><img src="..."/></p>`
/// 只把文字交给 AI，模型看不到波形图/电路图，就只能瞎猜。
/// 这里负责：提取图片地址 → 带账号 cookie 下载 → 转成 data URL，
/// 供多模态接口以 `image_url` 的方式读取。
class QuestionMedia {
  /// data URL 缓存（同一张图不重复下载）。null 表示下载失败，也缓存，避免反复重试。
  static final Map<String, String?> _cache = {};

  /// 单张图片大小上限。超过就跳过：base64 后体积会膨胀约 1.33 倍，
  /// 太大既拖慢答题又可能超过接口限制。
  static const _maxBytes = 2 * 1024 * 1024;

  /// 从 HTML 里提取图片地址（按出现顺序去重）。
  static List<String> extractImageUrls(String html) {
    if (html.isEmpty || !html.contains('<img')) return const [];
    final re = RegExp(
      r'''<img[^>]*?\ssrc\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final out = <String>[];
    for (final m in re.allMatches(html)) {
      final url = m.group(1)?.trim();
      if (url == null || url.isEmpty) continue;
      // 跳过 base64 内联图（本来就已经是 data URL）
      if (url.startsWith('data:')) continue;
      if (!out.contains(url)) out.add(url);
    }
    return out;
  }

  /// 题干里是否带图。
  static bool hasImage(String html) => extractImageUrls(html).isNotEmpty;

  /// HTML 转纯文本：去标签、反转义实体、压缩空白。
  ///
  /// 直接把 HTML 丢给模型会浪费 token，也容易让它把标签当内容。
  static String htmlToText(String html) {
    if (html.isEmpty) return '';
    var s = html;

    // 换行语义的标签先转成换行，避免两段文字粘在一起
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|li|tr|h[1-6])\s*>', caseSensitive: false), '\n');

    // 图片位置留一个占位提示，让模型知道这里有图
    s = s.replaceAll(RegExp(r'<img[^>]*>', caseSensitive: false), '［图片］');

    // 去掉其余标签
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');

    // 常见实体
    s = s
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”');

    // 压缩空白，但保留段落换行
    s = s.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n');
    return s.trim();
  }

  /// 把题干里的图片全部转成 data URL。
  ///
  /// [uid] 用于带上对应账号的 cookie —— 有些题目图片是需要登录态才能取的。
  static Future<List<String>> dataUrls(String html, {String? uid}) async {
    final urls = extractImageUrls(html);
    if (urls.isEmpty) return const [];

    final out = <String>[];
    for (final url in urls) {
      final data = await dataUrl(url, uid: uid);
      if (data != null) out.add(data);
      // 单题最多带 3 张：再多意义不大，还会拉长响应时间
      if (out.length >= 3) break;
    }
    return out;
  }

  /// 下载单张图片并转成 data URL；失败返回 null。
  static Future<String?> dataUrl(String url, {String? uid}) async {
    final absolute = _absolute(url);
    if (_cache.containsKey(absolute)) return _cache[absolute];

    try {
      final resp = await ApiService.sendRequest(
        absolute,
        responseType: ResponseType.bytes,
        userId: uid,
        receiveTimeoutSeconds: 20,
        allowRedirects: false,
      );
      final raw = resp?.data;
      if (raw is! List<int> || raw.isEmpty) {
        logger.w('题目图片下载失败（无内容）: $absolute');
        _cache[absolute] = null;
        return null;
      }
      if (raw.length > _maxBytes) {
        logger.w('题目图片过大（${(raw.length / 1024).round()}KB），跳过: $absolute');
        _cache[absolute] = null;
        return null;
      }

      final bytes = Uint8List.fromList(raw);
      final mime = _sniffMime(bytes);
      final data = 'data:$mime;base64,${base64Encode(bytes)}';
      _cache[absolute] = data;
      return data;
    } catch (e) {
      logger.w('题目图片下载异常: $absolute $e');
      _cache[absolute] = null;
      return null;
    }
  }

  /// 清空缓存（题量大时避免内存一直涨）。
  static void clearCache() => _cache.clear();

  /// 相对地址补全为绝对地址。
  static String _absolute(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';

    var base = 'https://www.yuketang.cn';
    try {
      if (PlatformManager().isRainClassroom) {
        base = ApiService.serverBaseUrlMap[PlatformManager().currentServer] ?? base;
      }
    } catch (_) {}

    if (url.startsWith('/')) return '$base$url';
    return '$base/$url';
  }

  /// 按文件头判断 MIME，避免服务端 content-type 不准导致接口拒收。
  static String _sniffMime(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 6 &&
        b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
      return 'image/gif';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/png';
  }
}
