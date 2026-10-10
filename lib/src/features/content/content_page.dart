import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../admin_permissions.dart';

enum _ContentKind { news, events, achievements, announcements }

extension on _ContentKind {
  String get endpoint => switch (this) {
        _ContentKind.news => 'news',
        _ContentKind.events => 'events',
        _ContentKind.achievements => 'achievements',
        _ContentKind.announcements => 'announcements',
      };
  String get label => switch (this) {
        _ContentKind.news => 'الأخبار',
        _ContentKind.events => 'الفعاليات',
        _ContentKind.achievements => 'الإنجازات',
        _ContentKind.announcements => 'الإعلانات',
      };
  IconData get icon => switch (this) {
        _ContentKind.news => Icons.article_outlined,
        _ContentKind.events => Icons.event_outlined,
        _ContentKind.achievements => Icons.emoji_events_outlined,
        _ContentKind.announcements => Icons.campaign_outlined,
      };
}

class ContentPage extends StatefulWidget {
  const ContentPage({super.key, required this.api, required this.role});
  final ApiService api;
  final String role;

  @override
  State<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<ContentPage> {
  late final List<_ContentKind> _kinds;
  _ContentKind _kind = _ContentKind.news;
  String _status = 'all';
  String _query = '';
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final isSuper = widget.role == AdminPermissions.superAdmin;
    final canNotify = isSuper;
    _kinds = [
      _ContentKind.news,
      _ContentKind.events,
      _ContentKind.achievements,
      if (canNotify) _ContentKind.announcements,
    ];
    _kind = _kinds.first;
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.api.get('/admin/${_kind.endpoint}?limit=100');
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

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    return _items.where((item) {
      final statusMatches = _status == 'all' || (item['status']?.toString() ?? 'draft') == _status;
      final text = '${item['title'] ?? ''} ${item['body'] ?? item['description'] ?? ''} ${item['category'] ?? ''}'.toLowerCase();
      return statusMatches && (q.isEmpty || text.contains(q));
    }).toList();
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final isCreate = item == null;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContentEditor(kind: _kind, initial: item),
    );
    if (result == null || !mounted) return;
    try {
      final id = item?['id']?.toString();
      if (id == null || id.isEmpty) {
        await widget.api.post('/admin/${_kind.endpoint}', body: result);
      } else {
        await widget.api.patch('/admin/${_kind.endpoint}/$id', body: result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isCreate ? 'تم إنشاء السجل.' : 'تم حفظ التعديلات.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ المحتوى: $error')));
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المحتوى؟'),
        content: Text('سيتم حذف «${item['title'] ?? 'هذا السجل'}» نهائيًا. قد تُحذف التفاعلات المرتبطة به أيضًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف نهائيًا')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.delete('/admin/${_kind.endpoint}/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المحتوى.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الحذف: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canEdit = widget.role == AdminPermissions.superAdmin ||
        widget.role == AdminPermissions.contentManager;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('إدارة المحتوى', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('إدارة السجلات المنشورة مباشرة عبر واجهة الخادم المعتمدة.', style: theme.textTheme.bodyMedium),
          ]),
          if (canEdit) FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('إضافة محتوى')),
        ]),
        const SizedBox(height: 20),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final kind in _kinds) ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  avatar: Icon(kind.icon, size: 18),
                  label: Text(kind.label),
                  selected: _kind == kind,
                  onSelected: (_) {
                    setState(() { _kind = kind; _items = []; _status = 'all'; });
                    _load();
                  },
                ),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 300, child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'البحث في العنوان والوصف', isDense: true),
            onChanged: (value) => setState(() => _query = value),
          )),
          SizedBox(width: 170, child: DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(labelText: 'حالة النشر', isDense: true),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('كل الحالات')),
              DropdownMenuItem(value: 'draft', child: Text('مسودة')),
              DropdownMenuItem(value: 'published', child: Text('منشور')),
            ],
            onChanged: (value) => setState(() => _status = value ?? 'all'),
          )),
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), label: const Text('تحديث')),
        ]),
        const SizedBox(height: 18),
        if (_loading && _items.isEmpty)
          const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator()))
        else if (_error != null && _items.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.cloud_off_outlined, size: 32), const SizedBox(height: 8),
            const Text('تعذر تحميل المحتوى', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6), Text(_error!), const SizedBox(height: 12),
            FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
          ])))
        else if (_filtered.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(children: [
            const Icon(Icons.inbox_outlined, size: 40), const SizedBox(height: 10),
            const Text('لا توجد سجلات مطابقة.', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4), Text('غيّر عوامل التصفية أو أضف سجلًا جديدًا.', style: theme.textTheme.bodyMedium),
          ])))
        else ...[
          Row(children: [Expanded(child: Text('${_kind.label} (${_filtered.length})', style: theme.textTheme.titleMedium)), if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))]),
          const SizedBox(height: 10),
          for (final item in _filtered) Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(_kind.icon, color: theme.colorScheme.primary)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item['title']?.toString() ?? 'بلا عنوان', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text((item['body'] ?? item['description'] ?? item['intro'] ?? '').toString(), maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  Chip(label: Text((item['status'] ?? 'draft') == 'published' ? 'منشور' : 'مسودة'), visualDensity: VisualDensity.compact),
                  if ((item['category'] ?? '').toString().isNotEmpty) Chip(label: Text(item['category'].toString()), visualDensity: VisualDensity.compact),
                  if ((item['created_at'] ?? '').toString().isNotEmpty) Text(item['created_at'].toString(), style: theme.textTheme.bodySmall),
                ]),
              ])),
              if (canEdit) PopupMenuButton<String>(
                tooltip: 'إجراءات السجل',
                onSelected: (value) { if (value == 'edit') _edit(item); if (value == 'delete') _delete(item); },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل'), contentPadding: EdgeInsets.zero)),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'), contentPadding: EdgeInsets.zero)),
                ],
              ),
            ])),
          ),
        ],
      ],
    );
  }
}

class _ContentEditor extends StatefulWidget {
  const _ContentEditor({required this.kind, this.initial});
  final _ContentKind kind;
  final Map<String, dynamic>? initial;
  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _imageUrl;
  late final TextEditingController _body;
  late final TextEditingController _category;
  late final TextEditingController _publisher;
  late final TextEditingController _location;
  late final TextEditingController _type;
  late final TextEditingController _eventAt;
  late final TextEditingController _endAt;
  late final TextEditingController _achievedAt;
  late String _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initial ?? {};
    _title = TextEditingController(text: item['title']?.toString() ?? '');
    _imageUrl = TextEditingController(text: item['image_url']?.toString() ?? '');
    _body = TextEditingController(text: (item['body'] ?? item['description'] ?? item['intro'] ?? '').toString());
    _category = TextEditingController(text: item['category']?.toString() ?? '');
    _publisher = TextEditingController(text: item['publisher']?.toString() ?? '');
    _location = TextEditingController(text: item['location']?.toString() ?? '');
    _type = TextEditingController(text: item['type']?.toString() ?? 'general');
    _eventAt = TextEditingController(text: item['event_at']?.toString() ?? '');
    _endAt = TextEditingController(text: item['end_at']?.toString() ?? '');
    _achievedAt = TextEditingController(text: item['achieved_at']?.toString() ?? '');
    _status = item['status']?.toString() ?? 'draft';
  }

  @override
  void dispose() {
    _title.dispose(); _imageUrl.dispose(); _body.dispose(); _category.dispose(); _publisher.dispose(); _location.dispose(); _type.dispose(); _eventAt.dispose(); _endAt.dispose(); _achievedAt.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    final payload = <String, dynamic>{'title': title, 'status': _status};
    switch (widget.kind) {
      case _ContentKind.news:
        payload.addAll({'body': body, 'category': _category.text.trim(), 'publisher': _publisher.text.trim(), 'image_url': _imageUrl.text.trim()});
        break;
      case _ContentKind.events:
        payload.addAll({'body': body, 'category': _category.text.trim(), 'publisher': _publisher.text.trim(), 'image_url': _imageUrl.text.trim(), 'location': _location.text.trim(), 'event_at': _eventAt.text.trim(), 'end_at': _endAt.text.trim()});
        break;
      case _ContentKind.achievements:
        payload.addAll({'description': body, 'publisher': _publisher.text.trim(), 'badge': _category.text.trim(), 'image_url': _imageUrl.text.trim(), 'achieved_at': _achievedAt.text.trim()});
        break;
      case _ContentKind.announcements:
        payload.addAll({'body': body, 'type': _type.text.trim().isEmpty ? 'general' : _type.text.trim()});
        break;
    }
    setState(() => _busy = true);
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'إضافة ${widget.kind.label}' : 'تعديل ${widget.kind.label}'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Form(key: _formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'العنوان'), validator: (v) => v == null || v.trim().isEmpty ? 'العنوان مطلوب' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _body, minLines: 3, maxLines: 7, decoration: InputDecoration(labelText: widget.kind == _ContentKind.achievements ? 'الوصف' : 'المحتوى'), validator: (v) => v == null || v.trim().isEmpty ? 'المحتوى مطلوب' : null),
      if (widget.kind == _ContentKind.news || widget.kind == _ContentKind.events || widget.kind == _ContentKind.achievements) ...[
        const SizedBox(height: 12),
        TextFormField(controller: _imageUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'رابط الصورة (اختياري)', hintText: 'https://…')),
      ],
      if (widget.kind == _ContentKind.news || widget.kind == _ContentKind.events || widget.kind == _ContentKind.achievements) ...[
        const SizedBox(height: 12),
        TextFormField(controller: _category, decoration: InputDecoration(labelText: widget.kind == _ContentKind.achievements ? 'شارة الإنجاز (اختياري)' : 'التصنيف (اختياري)')),
        const SizedBox(height: 12),
        TextFormField(controller: _publisher, decoration: const InputDecoration(labelText: 'اسم الناشر (اختياري)')),
      ],
      if (widget.kind == _ContentKind.events) ...[
        const SizedBox(height: 12), TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'المكان (اختياري)')),
        const SizedBox(height: 12), TextFormField(controller: _eventAt, decoration: const InputDecoration(labelText: 'موعد الفعالية بصيغة ISO (اختياري، مثل 2026-11-05T10:00:00Z)')),
        const SizedBox(height: 12), TextFormField(controller: _endAt, decoration: const InputDecoration(labelText: 'نهاية الفعالية بصيغة ISO (اختياري)')),
      ],
      if (widget.kind == _ContentKind.achievements) ...[
        const SizedBox(height: 12), TextFormField(controller: _achievedAt, decoration: const InputDecoration(labelText: 'تاريخ الإنجاز بصيغة ISO (اختياري)')),
      ],
      if (widget.kind == _ContentKind.announcements) ...[
        const SizedBox(height: 12), TextFormField(controller: _type, decoration: const InputDecoration(labelText: 'نوع الإعلان (مثل general)')),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(value: _status, decoration: const InputDecoration(labelText: 'حالة النشر'), items: const [DropdownMenuItem(value: 'draft', child: Text('مسودة')), DropdownMenuItem(value: 'published', child: Text('منشور'))], onChanged: (v) { if (v != null) setState(() => _status = v); }),
    ])))),
    actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ'))],
  );
}
