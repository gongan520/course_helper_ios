import 'package:flutter/material.dart';

import '../models/user.dart';
import '../service/ai_answer.dart';
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
  // 当前展开定时时间段设置面板的账号 uid
  final Set<String> _expandedUids = {};

  // AI 答题配置输入框控制器
  late final TextEditingController _aiApiKeyController;
  late final TextEditingController _aiBaseUrlController;
  late final TextEditingController _aiModelController;

  @override
  void initState() {
    super.initState();
    _config = AutoSignService().config;
    final aiConfig = AiAnswerService().config;
    _aiApiKeyController = TextEditingController(text: aiConfig.apiKey);
    _aiBaseUrlController = TextEditingController(text: aiConfig.baseUrl);
    _aiModelController = TextEditingController(text: aiConfig.model);
    _loadHistory();
  }

  @override
  void dispose() {
    _aiApiKeyController.dispose();
    _aiBaseUrlController.dispose();
    _aiModelController.dispose();
    super.dispose();
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

  Future<void> _addTimeRange(String uid) async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: '选择开始时间',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: start,
      helpText: '选择结束时间',
    );
    if (end == null || !mounted) return;

    setState(() {
      final cfg = _config.scheduledOf(uid);
      cfg.timeRanges.add(
        TimeRange(start: _formatTimeOfDay(start), end: _formatTimeOfDay(end)),
      );
    });
    _maybeHintCrossDay(start, end);
  }

  Future<void> _editTimeRange(String uid, TimeRange range) async {
    final start = await showTimePicker(
      context: context,
      initialTime: _parseTimeOfDay(range.start),
      helpText: '修改开始时间',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: _parseTimeOfDay(range.end),
      helpText: '修改结束时间',
    );
    if (end == null || !mounted) return;

    setState(() {
      range.start = _formatTimeOfDay(start);
      range.end = _formatTimeOfDay(end);
    });
    _maybeHintCrossDay(start, end);
  }

  /// 结束时间早于开始时间即视为跨天时间段，给出提示
  void _maybeHintCrossDay(TimeOfDay start, TimeOfDay end) {
    final startM = start.hour * 60 + start.minute;
    final endM = end.hour * 60 + end.minute;
    if (startM <= endM) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已设置跨天时间段（如 22:00-01:00），将覆盖次日凌晨'),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  TimeOfDay _parseTimeOfDay(String hm) {
    final parts = hm.split(':');
    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
    return TimeOfDay(hour: h, minute: m);
  }

  void _onModeTap(String uid, AutoSignMode mode) {
    setState(() {
      final current = _config.modeOf(uid);
      if (mode == AutoSignMode.scheduled) {
        if (current == AutoSignMode.scheduled) {
          // 已处于定时模式，再点一次切换面板展开/收起
          if (_expandedUids.contains(uid)) {
            _expandedUids.remove(uid);
          } else {
            _expandedUids.add(uid);
          }
        } else {
          _config.setMode(uid, mode);
          _expandedUids.add(uid);
        }
      } else {
        _config.setMode(uid, mode);
        _expandedUids.remove(uid);
      }
    });
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
        onTap: () => _onModeTap(uid, mode),
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
                InkWell(
                  onTap: _showAiAnswerDialog,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 16,
                          color: Color(0xFF7E57C2),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AI 答题',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7E57C2),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
            if (mode == AutoSignMode.scheduled &&
                _expandedUids.contains(user.uid)) ...[
              const SizedBox(height: 12),
              _buildSchedulePanel(user.uid),
            ],
          ],
        ),
      ),
    );
  }

  // ============ AI 答题说明对话框 ============

  void _showAiAnswerDialog() {
    final configured = AiAnswerService().isConfigured;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 答题'),
        content: Text(
          '使用 AI（DeepSeek 等）在考试/作业中自动生成答案。\n\n'
          '使用方法：\n'
          '1. 在自动签到设置页底部配置 AI API 密钥\n'
          '2. 打开某个测验/练习活动\n'
          '3. 点击答题页的"AI 答题"按钮自动生成答案'
          '${configured ? '' : '\n\n当前未配置 API 密钥。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
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

  // ============ 定时时间段设置面板 ============

  Widget _buildSchedulePanel(String uid) {
    final scheme = Theme.of(context).colorScheme;
    final cfg = _config.scheduledOf(uid);
    const accent = Color(0xFF7E57C2);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 18, color: accent),
              const SizedBox(width: 6),
              const Text(
                '定时时间段设置',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _expandedUids.remove(uid)),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    size: 20,
                    color: scheme.outline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '可添加多个时间段，时间段内会像托管一样持续盯课，有签到就自动签。\n'
            '开始时间晚于结束时间即视为跨天（如 22:00-01:00）。',
            style: TextStyle(fontSize: 12, color: scheme.outline, height: 1.5),
          ),
          const SizedBox(height: 10),
          _buildTimeRangeList(uid, cfg),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _addTimeRange(uid),
              icon: const Icon(Icons.add),
              label: const Text('添加时间段'),
              style: OutlinedButton.styleFrom(foregroundColor: accent),
            ),
          ),
          const SizedBox(height: 12),
          _buildRepeatSelector(cfg),
        ],
      ),
    );
  }

  Widget _buildTimeRangeList(String uid, ScheduledAccountConfig cfg) {
    final scheme = Theme.of(context).colorScheme;
    const accent = Color(0xFF7E57C2);

    if (cfg.timeRanges.isEmpty) {
      return Text(
        '暂无时间段，点击下方按钮添加',
        style: TextStyle(fontSize: 13, color: scheme.outline),
      );
    }

    return Column(
      children: [
        for (final range in cfg.timeRanges)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: InkWell(
                    onTap: () => _editTimeRange(uid, range),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${range.start} → ${range.end}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Icon(
                            Icons.edit_outlined,
                            size: 15,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => cfg.timeRanges.remove(range)),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 18, color: scheme.outline),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRepeatSelector(ScheduledAccountConfig cfg) {
    final scheme = Theme.of(context).colorScheme;
    const accent = Color(0xFF7E57C2);

    const options = [
      ('everyday', '每天'),
      ('workday', '工作日'),
      ('weekend', '周末'),
      ('custom', '自定义'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生效周期',
          style: TextStyle(fontSize: 12, color: scheme.outline),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in options)
              ChoiceChip(
                label: Text(opt.$2),
                selected: cfg.repeatType == opt.$1,
                selectedColor: accent.withValues(alpha: 0.18),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: cfg.repeatType == opt.$1
                      ? accent
                      : scheme.onSurfaceVariant,
                  fontWeight: cfg.repeatType == opt.$1
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => cfg.repeatType = opt.$1),
              ),
          ],
        ),
        if (cfg.repeatType == 'custom') ...[
          const SizedBox(height: 10),
          Text(
            '选择星期（可多选）',
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  label: Text(_weekdayLabel(d)),
                  selected: cfg.weekdays.contains(d),
                  selectedColor: accent.withValues(alpha: 0.18),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: cfg.weekdays.contains(d)
                        ? accent
                        : scheme.onSurfaceVariant,
                  ),
                  onSelected: (selected) => setState(() {
                    if (selected) {
                      if (!cfg.weekdays.contains(d)) cfg.weekdays.add(d);
                    } else {
                      cfg.weekdays.remove(d);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _weekdayLabel(int d) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[d - 1];
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

  // ============ AI 答题设置 ============

  Widget _buildAiAnswerSection() {
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
            // 标题行
            Row(
              children: [
                Icon(Icons.smart_toy_outlined, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                const Text(
                  'AI 答题设置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '接入 DeepSeek 等 OpenAI 兼容 AI，用于考试/作业自动生成答案。',
              style: TextStyle(fontSize: 12, color: scheme.outline, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aiApiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API 密钥',
                hintText: 'sk-...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aiBaseUrlController,
              decoration: const InputDecoration(
                labelText: 'API 地址',
                hintText: 'https://api.deepseek.com',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _aiModelController,
              decoration: const InputDecoration(
                labelText: '模型名',
                hintText: 'deepseek-chat',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (_aiApiKeyController.text.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '未配置 API 密钥，AI 答题不可用',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saveAiConfig,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存 AI 配置'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAiConfig() async {
    final cfg = AiAnswerConfig(
      apiKey: _aiApiKeyController.text.trim(),
      baseUrl: _aiBaseUrlController.text.trim(),
      model: _aiModelController.text.trim(),
    );
    await AiAnswerService().updateConfig(cfg);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存')),
      );
    }
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
              '• 定时：在设定的时间段内像托管一样持续盯课自动签到，可添加多个时间段\n'
              '• 手动：不自动，保持原样手动签到',
              style: TextStyle(fontSize: 13, height: 1.6, color: scheme.outline),
            ),
          ),

          _buildAccountList(),

          const SizedBox(height: 4),
          _buildGeneralSection(),
          _buildHistorySection(),
          _buildAiAnswerSection(),

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
