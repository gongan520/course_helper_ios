import 'package:flutter/material.dart';

import '../models/user.dart';
import '../service/auto_sign.dart';
import '../service/sign_history.dart';
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
  List<SignHistoryRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _config = AutoSignService().config;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await SignHistoryStore().recent(limit: 5);
    if (mounted) {
      setState(() => _history = list);
    }
  }

  Future<void> _clearHistory() async {
    await SignHistoryStore().clear();
    if (mounted) {
      setState(() => _history = []);
    }
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该时间点已存在')),
        );
      }
    }
  }

  // ============ 模式相关工具 ============

  String _modeLabel(AutoSignMode mode) {
    switch (mode) {
      case AutoSignMode.auto:
        return '托管';
      case AutoSignMode.scheduled:
        return '定时';
      case AutoSignMode.manual:
        return '手动';
    }
  }

  Color _modeColor(AutoSignMode mode) {
    switch (mode) {
      case AutoSignMode.auto:
        return const Color(0xFF2BBBAD);
      case AutoSignMode.scheduled:
        return const Color(0xFF7E57C2);
      case AutoSignMode.manual:
        return const Color(0xFF90A4AE);
    }
  }

  // ============ 平台相关工具 ============

  String _platformLabel(User user) => user.isRainClassroom ? '雨课堂' : '学习通';

  Color _platformColor(User user) =>
      user.isRainClassroom ? const Color(0xFF43A047) : const Color(0xFF1E88E5);

  IconData _platformIcon(User user) =>
      user.isRainClassroom ? Icons.cloud_outlined : Icons.menu_book_outlined;

  // ============ 构建账号模式三选一按钮组 ============

  Widget _buildModeSelector(String uid) {
    return Row(
      children: [
        _modeButton(uid, AutoSignMode.auto, Icons.auto_awesome, '托管'),
        const SizedBox(width: 6),
        _modeButton(uid, AutoSignMode.scheduled, Icons.schedule, '定时'),
        const SizedBox(width: 6),
        _modeButton(uid, AutoSignMode.manual, Icons.touch_app, '手动'),
      ],
    );
  }

  Widget _modeButton(
    String uid,
    AutoSignMode mode,
    IconData icon,
    String label,
  ) {
    final selected = _config.modeOf(uid) == mode;
    final color = _modeColor(mode);
    final onSurfaceVariant =
        Theme.of(context).colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _config.setMode(uid, mode)),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected
                ? color
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============ 账号卡片列表 ============

  Widget _buildAccountList() {
    final accounts = AccountManager.allAccounts;
    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_off_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '暂无已登录账号，请先在账号页登录。',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final user in accounts) _buildAccountCard(user),
      ],
    );
  }

  Widget _buildAccountCard(User user) {
    final mode = _config.modeOf(user.uid);
    final platformColor = _platformColor(user);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 账号信息行
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: platformColor.withValues(alpha: 0.12),
                  child: Icon(_platformIcon(user), color: platformColor, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          _chip(_platformLabel(user), platformColor),
                          const SizedBox(width: 6),
                          _chip(
                            user.status ? '已启用' : '已停用',
                            user.status
                                ? const Color(0xFF43A047)
                                : scheme.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 当前模式提示
            Row(
              children: [
                Text(
                  '签到模式',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
                const Spacer(),
                Text(
                  '当前：${_modeLabel(mode)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _modeColor(mode),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildModeSelector(user.uid),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500),
      ),
    );
  }

  // ============ 定时签到时间点 ============

  Widget _buildScheduleSection() {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '定时签到时间点',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '定时模式下的账号将在这些时间点自动签到',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 10),
            if (_config.scheduledTimes.isEmpty)
              Text(
                '暂无时间点，点击下方按钮添加',
                style: TextStyle(fontSize: 13, color: scheme.outline),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final time in _config.scheduledTimes)
                    InputChip(
                      label: Text(time),
                      avatar: const Icon(Icons.access_time, size: 16),
                      deleteIconColor: scheme.outline,
                      onDeleted: () => setState(() {
                        _config.scheduledTimes.remove(time);
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addTime,
                icon: const Icon(Icons.add),
                label: const Text('添加时间点'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ 通用设置（通知 + 检测间隔） ============

  Widget _buildGeneralSection() {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('签到结果通知'),
            subtitle: const Text('签到成功或失败时弹出系统通知'),
            value: _config.notifyOnResult,
            onChanged: (v) => setState(() => _config.notifyOnResult = v),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
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
      ),
    );
  }

  // ============ 签到历史记录 ============

  Widget _buildHistorySection() {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '签到历史记录',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_history.isNotEmpty)
                  TextButton(
                    onPressed: _clearHistory,
                    child: const Text('清空'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '暂无签到记录',
                  style: TextStyle(fontSize: 13, color: scheme.outline),
                ),
              )
            else
              for (final record in _history) _buildHistoryTile(record),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(SignHistoryRecord record) {
    final okColor = const Color(0xFF43A047);
    final failColor = Theme.of(context).colorScheme.error;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        record.success ? Icons.check_circle : Icons.cancel,
        color: record.success ? okColor : failColor,
        size: 20,
      ),
      title: Text(
        '${record.accountName} · ${record.target}',
        style: const TextStyle(fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${record.platform} · ${_formatTime(record.time)}',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  // ============ 主界面 ============

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('自动签到设置'),
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部说明
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '为每个账号单独选择签到模式：\n'
              '• 托管：检测到签到活动/正在上课时自动签到\n'
              '• 定时：仅在设定的时间点自动签到\n'
              '• 手动：不自动，保持原样手动签到',
              style: TextStyle(fontSize: 13, height: 1.6, color: scheme.outline),
            ),
          ),

          _buildAccountList(),

          const SizedBox(height: 4),
          _buildScheduleSection(),
          _buildGeneralSection(),
          _buildHistorySection(),

          // 说明
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
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
