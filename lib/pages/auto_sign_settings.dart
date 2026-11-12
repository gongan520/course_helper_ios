import 'package:flutter/material.dart';

import '../service/auto_sign.dart';
import '../session/account.dart';

/// 自动签到 / 定时签到设置页
///
/// 每个账号独立选择模式：托管（自动）/ 定时 / 手动
class AutoSignSettingsPage extends StatefulWidget {
  const AutoSignSettingsPage({super.key});

  @override
  State<AutoSignSettingsPage> createState() => _AutoSignSettingsPageState();
}

class _AutoSignSettingsPageState extends State<AutoSignSettingsPage> {
  late AutoSignConfig _config;

  @override
  void initState() {
    super.initState();
    _config = AutoSignService().config;
  }

  Future<void> _save() async {
    await AutoSignService().updateConfig(_config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置已保存')),
      );
    }
  }

  Future<void> _addTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) {
      final formatted =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      if (!_config.scheduledTimes.contains(formatted)) {
        setState(() {
          _config.scheduledTimes.add(formatted);
          _config.scheduledTimes.sort();
        });
      }
    }
  }

  /// 构建单个账号的模式三选一按钮组
  Widget _buildModeSelector(String uid) {
    final current = _config.modeOf(uid);

    Widget _btn(AutoSignMode mode, String label, Color activeColor) {
      final selected = current == mode;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: InkWell(
            onTap: () => setState(() => _config.setMode(uid, mode)),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? activeColor
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: selected
                    ? Border.all(color: activeColor, width: 1)
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        _btn(AutoSignMode.auto, '托管', const Color(0xFF2BBBAD)),
        _btn(AutoSignMode.scheduled, '定时', const Color(0xFF7E57C2)),
        _btn(AutoSignMode.manual, '手动', const Color(0xFF90A4AE)),
      ],
    );
  }

  /// 构建账号列表
  Widget _buildAccountList() {
    final accounts = AccountManager.allAccounts;
    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '暂无已登录账号，请先在账号页登录。',
          style: TextStyle(fontSize: 13),
        ),
      );
    }

    final hasScheduled = _config.accountModes.values
        .any((v) => v == AutoSignMode.scheduled.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶部说明
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '为每个账号单独选择签到模式：\n'
            '• 托管：检测到签到活动/正在上课时自动签到\n'
            '• 定时：仅在设定的时间点自动签到\n'
            '• 手动：不自动，保持原样手动签到',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),

        // 账号行
        for (final user in accounts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                // 账号名
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.isRainClassroom ? '雨课堂' : '学习通',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                // 模式三选一
                Expanded(
                  flex: 4,
                  child: _buildModeSelector(user.uid),
                ),
              ],
            ),
          ),

        // 定时时间点（有定时账号时显示）
        if (hasScheduled) ...[
          const SizedBox(height: 8),
          Text(
            '定时签到时间点',
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontWeight: FontWeight.w500,
            ),
          ),
          for (final time in _config.scheduledTimes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: Text(time),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() {
                  _config.scheduledTimes.remove(time);
                }),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addTime,
              icon: const Icon(Icons.add),
              label: const Text('添加时间点'),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 轮询间隔
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer),
          title: const Text('检测间隔'),
          trailing: DropdownButton<int>(
            value: _config.pollIntervalSeconds,
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 秒')),
              DropdownMenuItem(value: 30, child: Text('30 秒')),
              DropdownMenuItem(value: 60, child: Text('1 分钟')),
              DropdownMenuItem(value: 120, child: Text('2 分钟')),
            ],
            onChanged: (v) => setState(
              () => _config.pollIntervalSeconds = v ?? 30,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('自动签到设置'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildAccountList(),

          const SizedBox(height: 16),

          // 说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '说明：\n'
              '• 雨课堂「托管」：轮询检测正在上课的课程，自动签到。\n'
              '• 学习通「托管」：收到签到推送时自动签到。\n'
              '• 二维码、手势、签到码签到因需要动态内容，无法自动完成。\n'
              '• 位置签到需要先在课程设置中配置好签到位置。\n'
              '• 拍照签到需要先在课程设置中配置好图片。',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
          ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('保存设置'),
          ),
        ],
      ),
    );
  }
}
