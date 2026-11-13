import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../main.dart' show navigatorKey;
import '../utils/storage.dart';

class Update {
  static const _skipVersionKey = 'skip_version';

  // 多源版本信息地址（依次尝试，全部国内可直连且实时）
  // fastly.jsdelivr.net 与 jsdelivr.b-cdn.net 均为 jsDelivr 国内直连节点，无顽固缓存
  static const _versionUrlList = [
    'https://fastly.jsdelivr.net/gh/gongan520/course_helper_ios@main/version.json',
    'https://jsdelivr.b-cdn.net/gh/gongan520/course_helper_ios@main/version.json',
    'https://gh-proxy.com/https://raw.githubusercontent.com/gongan520/course_helper_ios/main/version.json',
  ];
  static const _latestReleasePageUrl = 'https://github.com/gongan520/course_helper_ios/releases/latest';

  static Future<void> checkUpdate({bool ignoreSkip = false}) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 8);
    dio.options.receiveTimeout = const Duration(seconds: 8);

    Map<String, dynamic>? data;
    for (final url in _versionUrlList) {
      try {
        final response = await dio.get(url);
        if (response.data is Map) {
          data = (response.data as Map).cast<String, dynamic>();
          break;
        }
      } catch (_) {
        // 尝试下一个源
      }
    }

    if (data == null) {
      if (ignoreSkip) {
        _showToast('检查更新失败，请检查网络后重试');
      }
      return;
    }

    final latestVersion = data['version']?.toString() ?? '';
    final skipVersion = StorageManager.prefs.getString(_skipVersionKey) ?? '';

    final hasNewer = (ignoreSkip || latestVersion != skipVersion) &&
        _isNewerVersion(latestVersion, currentVersion);

    if (hasNewer) {
      _showUpdateDialog(
        latestVersion: latestVersion,
        releaseNotes: data['release_notes']?.toString() ?? '暂无更新说明',
        downloadUrl: data['ipa_url']?.toString() ?? _latestReleasePageUrl,
      );
    } else if (ignoreSkip) {
      _showToast('当前已是最新版本 v$currentVersion');
    }
  }

  static void _showToast(String msg) {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final latestNum = i < latestParts.length ? latestParts[i] : 0;
        final currentNum = i < currentParts.length ? currentParts[i] : 0;

        if (latestNum > currentNum) return true;
        if (latestNum < currentNum) return false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 下载 IPA：github.com 直链国内慢，自动加国内加速前缀，失败则回退原直链
  static Future<void> _launchDownload(String downloadUrl) async {
    final urls = <String>[downloadUrl];
    if (downloadUrl.contains('github.com')) {
      urls.insert(
        0,
        'https://gh-proxy.com/$downloadUrl',
      );
    }
    for (final u in urls) {
      final uri = Uri.parse(u);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {
        // 尝试下一个
      }
    }
  }

  static void _showUpdateDialog({
    required String latestVersion,
    required String releaseNotes,
    required String downloadUrl
  }) {
    showDialog(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最新版本: v$latestVersion',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(releaseNotes),
            ],
          ),
        ),
        actions: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await StorageManager.prefs.setString(_skipVersionKey, latestVersion);
                },
                child: const Text('跳过该版本'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await _launchDownload(downloadUrl);
                },
                child: const Text('前往下载'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}