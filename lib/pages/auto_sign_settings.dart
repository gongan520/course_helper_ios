import 'package:flutter/material.dart';

import '../service/auto_sign.dart';

/// 自动签到 / 定时签到设置页
class AutoSignSettingsPage extends StatefulWidget {
  const AutoSignSettingsPage({super.key});

  @override
  State<AutoSignSettingsPage> createState() => _AutoSignSettingsPageState();
}

class _AutoSignSettingsPageState extends State<AutoSignSettingsPage> {
  late AutoSignConfig _config;
  final TextEditingController _timeController = TextEditingController();

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
          // 自动签到总开关
          SwitchListTile(
            title: const Text('自动签到'),
            subtitle: const Text('收到签到活动推送时，后台自动完成签到'),
            value: _config.enabled,
            onChanged: (v) => setState(() => _config.enabled = v),
          ),

          // 所有账号签到
          SwitchListTile(
            title: const Text('为所有账号签到'),
            subtitle: const Text('开启后对所有已登录账号签到，关闭则仅当前账号'),
            value: _config.signAllAccounts,
            onChanged: _config.enabled
                ? (v) => setState(() => _config.signAllAccounts = v)
                : null,
          ),

          const Divider(),

          // 定时签到
          SwitchListTile(
            title: const Text('定时签到'),
            subtitle: const Text('在设定的时间点自动检查并签到'),
            value: _config.scheduledEnabled,
            onChanged: _config.enabled
                ? (v) => setState(() => _config.scheduledEnabled = v)
                : null,
          ),

          if (_config.scheduledEnabled) ...[
            // 定时时间点列表
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '定时时间点',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            for (final time in _config.scheduledTimes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.schedule),
                title: Text(time),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() {
                    _config.scheduledTimes.remove(time);
                  }),
                ),
              ),
            OutlinedButton.icon(
              onPressed: _addTime,
              icon: const Icon(Icons.add),
              label: const Text('添加时间点'),
            ),

            const SizedBox(height: 8),
            ListTile(
              dense: true,
              leading: const Icon(Icons.timer),
              title: const Text('轮询间隔'),
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

          const SizedBox(height: 24),

          // 提示
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '说明：\n'
              '• 自动签到仅支持学习通平台的「普通签到」和「位置签到」。\n'
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
