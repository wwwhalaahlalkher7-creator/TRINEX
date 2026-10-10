import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../design_system/trinex_theme.dart';

enum _ModerationKind { comments, replies }

class ModerationPage extends StatefulWidget {
  const ModerationPage({super.key, required this.api});
  final ApiService api;

  @override
  State<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<ModerationPage> {
  _ModerationKind _kind = _ModerationKind.comments;
  String _status = 'visible';
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _endpoint => _kind == _ModerationKind.comments
      ? '/admin/moderation/comments'
      : '/admin/moderation/replies';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.api.get('$_endpoint?status=$_status&limit=100');
      final raw = response['data'];
      final rows = raw is List
          ? raw.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
          : <Map<String, dynamic>>[];
      if (mounted) setState(() => _items = rows);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(Map<String, dynamic> item, String status) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _busyIds.add(id));
    try {
      final path = _kind == _ModerationKind.comments
          ? '/admin/moderation/comments/$id'
          : '/admin/moderation/replies/$id';
      await widget.api.patch(path, body: {'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تحديث الحالة إلى «${_statusLabel(status)}».')),
      );
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث الحالة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _deleteReply(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الرد نهائيًا؟'),
        content: const Text('سيُحذف الرد من قاعدة البيانات، ولا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف نهائيًا')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyIds.add(id));
    try {
      await widget.api.delete('/admin/moderation/replies/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الرد.')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حذف الرد: $error')));
      }
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
      children: [
        Text('الإشراف والتعليقات', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 27)),
        const SizedBox(height: 7),
        Text('راجع تفاعلات الطلاب، وغيّر حالة التعليقات والردود وفق صلاحيات حسابك.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<_ModerationKind>(
            segments: const [
              ButtonSegment(value: _ModerationKind.comments, label: Text('التعليقات'), icon: Icon(Icons.mode_comment_outlined)),
              ButtonSegment(value: _ModerationKind.replies, label: Text('الردود'), icon: Icon(Icons.reply_outlined)),
            ],
            selected: {_kind},
            onSelectionChanged: (selection) {
              setState(() { _kind = selection.first; _items = []; });
              _load();
            },
          ),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(labelText: 'حالة العرض', isDense: true),
              items: const [
                DropdownMenuItem(value: 'visible', child: Text('ظاهرة')),
                DropdownMenuItem(value: 'hidden', child: Text('مخفية')),
                DropdownMenuItem(value: 'deleted', child: Text('محذوفة')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() { _status = value; _items = []; });
                _load();
              },
            ),
          ),
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
        ]),
        const SizedBox(height: 18),
        if (_loading && _items.isEmpty)
          const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
        else if (_error != null && _items.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.cloud_off_outlined, size: 30),
            const SizedBox(height: 10),
            const Text('تعذر تحميل التفاعلات', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ])))
        else if (_items.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(children: [
            const Icon(Icons.inbox_outlined, size: 38, color: TrinexColors.muted),
            const SizedBox(height: 10),
            const Text('لا توجد نتائج بهذه الحالة.', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('يمكنك تغيير حالة العرض أو تحديث القائمة.', style: theme.textTheme.bodyMedium),
          ])))
        else ...[
          Row(children: [
            Expanded(child: Text(_kind == _ModerationKind.comments ? 'التعليقات (${_items.length})' : 'الردود (${_items.length})', style: theme.textTheme.titleMedium)),
            if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 10),
          for (final item in _items) _ModerationCard(
            item: item,
            kind: _kind,
            busy: _busyIds.contains(item['id']?.toString() ?? ''),
            onStatusChanged: (status) => _changeStatus(item, status),
            onDelete: () => _deleteReply(item),
          ),
        ],
      ],
    );
  }
}

class _ModerationCard extends StatelessWidget {
  const _ModerationCard({
    required this.item,
    required this.kind,
    required this.busy,
    required this.onStatusChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> item;
  final _ModerationKind kind;
  final bool busy;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (item['full_name'] ?? 'طالب غير معروف').toString();
    final body = (kind == _ModerationKind.comments ? item['body'] : item['body'])?.toString() ?? 'لا يوجد نص';
    final status = item['status']?.toString() ?? 'visible';
    final createdAt = item['created_at']?.toString() ?? '';
    final subtitle = kind == _ModerationKind.comments
        ? 'رقم الطالب: ${(item['student_number'] ?? '—')}  •  الردود: ${(item['reply_count'] ?? 0)}'
        : 'رد على: ${(item['comment_body'] ?? 'تعليق غير متاح')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: const Color(0xFFEFF3FF), foregroundColor: TrinexColors.brand, child: Icon(kind == _ModerationKind.comments ? Icons.mode_comment_outlined : Icons.reply_outlined)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ])),
            _StatusPill(status: status),
          ]),
          const SizedBox(height: 14),
          SelectableText(body, style: const TextStyle(height: 1.5)),
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(createdAt, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: busy || status == 'visible' ? null : () => onStatusChanged('visible'),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('إظهار'),
            ),
            OutlinedButton.icon(
              onPressed: busy || status == 'hidden' ? null : () => onStatusChanged('hidden'),
              icon: const Icon(Icons.visibility_off_outlined, size: 18),
              label: const Text('إخفاء'),
            ),
            if (kind == _ModerationKind.comments)
              OutlinedButton.icon(
                onPressed: busy || status == 'deleted' ? null : () => onStatusChanged('deleted'),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('وضع علامة محذوف'),
              )
            else
              TextButton.icon(
                onPressed: busy ? null : onDelete,
                icon: const Icon(Icons.delete_forever_outlined, size: 18),
                label: const Text('حذف نهائيًا'),
                style: TextButton.styleFrom(foregroundColor: TrinexColors.danger),
              ),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ]),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = status == 'visible'
        ? TrinexColors.success
        : status == 'hidden'
            ? TrinexColors.warning
            : TrinexColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'visible': return 'ظاهرة';
    case 'hidden': return 'مخفية';
    case 'deleted': return 'محذوفة';
    default: return status;
  }
}
