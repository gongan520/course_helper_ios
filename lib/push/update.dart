import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../main.dart' show navigatorKey;
import '../utils/storage.dart';

class Update {
  static const _skipVersionKey = 'skip_version';

  static const _latestReleaseUrl = 'https://api.github.com/repos/gongan520/course_helper_ios/releases/latest';
  static const _latestReleasePageUrl = 'https://github.com/gongan520/course_helper_ios/releases/latest';

  static Future<void> checkUpdate({bool ignoreSkip = false}) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      final response = await dio.get(_latestReleaseUrl);
      final data = response.data;
      final latestVersion = data['tag_name']?.toString().replaceAll('v', '') ?? '';
      final skipVersion = StorageManager.prefs.getString(_skipVersionKey) ?? '';

      // 从 release 资产里找 IPA 下载直链，找不到再退回页面链接
      String downloadUrl = data['html_url'] ?? _latestReleasePageUrl;
      final assets = data['assets'];
      if (assets is List && assets.isNotEmpty) {
        for (final a in assets) {
          final name = a['name']?.toString() ?? '';
          final url = a['browser_download_url']?.toString() ?? '';
          if (name.toLowerCase().endsWith('.ipa') && url.isNotEmpty) {
            downloadUrl = url;
            break;
          }
        }
      }

      final hasNewer = (ignoreSkip || latestVersion != skipVersion) &&
          _isNewerVersion(latestVersion, currentVersion);

      if (hasNewer) {
        _showUpdateDialog(
          latestVersion: latestVersion,
          releaseNotes: data['body'] ?? '暂无更新说明',
          downloadUrl: downloadUrl,
        );
      } else if (ignoreSkip) {
        // 手动检查：无新版本时给出明确反馈，避免"点了没反应"的错觉
        _showToast('当前已是最新版本 v$currentVersion');
      }
    } catch (e) {
      // 手动检查失败时也要给出反馈（自动检查则静默）
      if (ignoreSkip) {
        _showToast('检查更新失败，请检查网络后重试');
      }
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
                  final uri = Uri.parse(downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
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