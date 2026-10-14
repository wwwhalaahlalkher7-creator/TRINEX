import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api_service.dart';
import '../../admin_permissions.dart';

enum _ContentKind { news, events, achievements, announcements }

extension on _ContentKind {
  String get endpoint => switch (this) {
        _ContentKind.news => 'news',
        // The backend exposes the events table through the legacy 'activities' resource.
        _ContentKind.events => 'activities',
        _ContentKind.achievements => 'achievements',
        _ContentKind.announcements => 'announcements',
      };
  String get label => switch (this) {
        _ContentKind.news => 'الأخبار',
        _ContentKind.events => 'الفعاليات',
        _ContentKind.achievements => 'الإنجازات',
        _ContentKind.announcements => 'الإعلانات والإشعارات',
      };
  IconData get icon => switch (this) {
        _ContentKind.news => Icons.article_outlined,
        _ContentKind.events => Icons.event_outlined,
        _ContentKind.achievements => Icons.emoji_events_outlined,
        _ContentKind.announcements => Icons.campaign_outlined,
      };
}

class ContentPage extends StatefulWidget {
  const ContentPage({super.key, required this.api, required this.role, this.announcementsOnly = false});
  final ApiService api;
  final String role;
  final bool announcementsOnly;

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
    _kinds = widget.announcementsOnly
        ? [_ContentKind.announcements]
        : [
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

  String _formatArabicDate(dynamic raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '');
    if (value == null) return raw?.toString() ?? '';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year}  $hour:$minute';
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final isCreate = item == null;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContentEditor(api: widget.api, kind: _kind, initial: item),
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

  bool _announcementCanSend(Map<String, dynamic> item) {
    if (item['status'] != 'published') return false;
    final now = DateTime.now();
    final publishAt = DateTime.tryParse(item['publish_at']?.toString() ?? '')?.toLocal();
    final expiresAt = DateTime.tryParse(item['expires_at']?.toString() ?? '')?.toLocal();
    if (publishAt != null && publishAt.isAfter(now)) return false;
    if (expiresAt != null && !expiresAt.isAfter(now)) return false;
    return true;
  }

  String _announcementSendTooltip(Map<String, dynamic> item) {
    if (item['status'] != 'published') return 'انشر الإعلان أولًا';
    final now = DateTime.now();
    final publishAt = DateTime.tryParse(item['publish_at']?.toString() ?? '')?.toLocal();
    final expiresAt = DateTime.tryParse(item['expires_at']?.toString() ?? '')?.toLocal();
    if (publishAt != null && publishAt.isAfter(now)) return 'سيُجهّز الإشعار تلقائيًا عند موعد النشر';
    if (expiresAt != null && !expiresAt.isAfter(now)) return 'انتهت صلاحية الإعلان';
    return 'إرسال الإعلان كإشعار';
  }

  Future<void> _approveAnnouncement(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'draft') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اعتماد مسودة الإعلان؟'),
        content: Text('سيُنشر «${item['title'] ?? 'الإعلان'}» ويصبح مؤهلًا للتجهيز عند موعد النشر. لن يُرسل إشعار فوري إذا كان موعده مستقبلًا.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد ونشر')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.patch('/admin/announcements/$id', body: {'status': 'published'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اعتماد الإعلان ونشره.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر اعتماد الإعلان: $error')));
    }
  }

  Future<void> _sendAnnouncement(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || !_announcementCanSend(item)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال الإعلان كإشعار؟'),
        content: Text('سيُجهّز «${item['title'] ?? 'الإعلان'}» للإرسال إلى الطلاب النشطين المطابقين للقسم والمستوى المحددين. هذه العملية لا تنشئ استهدافات مكررة عند تكرارها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد الإرسال')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final response = await widget.api.post('/admin/notifications/send', body: {'announcementId': id});
      final data = response['data'] is Map ? Map<String, dynamic>.from(response['data'] as Map) : response;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تجهيز الإشعار. المستهدفون: ${data['targets'] ?? '—'}، المستهدفون الجدد: ${data['newTargets'] ?? '—'}.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الإشعار: $error')));
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
            Text('إدارة الأخبار والفعاليات والإنجازات، وإنشاء الإعلانات وتجهيزها كإشعارات للطلاب من مكان واحد.', style: theme.textTheme.bodyMedium),
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
                  if (_kind == _ContentKind.announcements && item['targets'] != null)
                    Chip(avatar: const Icon(Icons.people_alt_outlined, size: 16), label: Text('المستهدفون ${item['targets']}'), visualDensity: VisualDensity.compact),
                  if (_kind == _ContentKind.announcements && item['reads'] != null)
                    Chip(avatar: const Icon(Icons.mark_email_read_outlined, size: 16), label: Text('المقروء ${item['reads']}'), visualDensity: VisualDensity.compact),
                  if ((item['publish_at'] ?? '').toString().isNotEmpty)
                    Text('موعد النشر: ${_formatArabicDate(item['publish_at'])}', style: theme.textTheme.bodySmall),
                  if ((item['event_at'] ?? '').toString().isNotEmpty)
                    Text('موعد الفعالية: ${_formatArabicDate(item['event_at'])}', style: theme.textTheme.bodySmall),
                  if ((item['achieved_at'] ?? '').toString().isNotEmpty)
                    Text('تاريخ الإنجاز: ${_formatArabicDate(item['achieved_at'])}', style: theme.textTheme.bodySmall),
                  if ((item['created_at'] ?? '').toString().isNotEmpty) Text('تاريخ الإضافة: ${_formatArabicDate(item['created_at'])}', style: theme.textTheme.bodySmall),
                ]),
              ])),
              if (_kind == _ContentKind.announcements && item['status'] == 'draft')
                IconButton(
                  tooltip: 'اعتماد ونشر المسودة',
                  onPressed: canEdit ? () => _approveAnnouncement(item) : null,
                  icon: const Icon(Icons.fact_check_outlined),
                ),
              if (_kind == _ContentKind.announcements && item['status'] == 'published')
                IconButton(
                  tooltip: _announcementSendTooltip(item),
                  onPressed: _announcementCanSend(item) ? () => _sendAnnouncement(item) : null,
                  icon: Icon(
                    _announcementCanSend(item) ? Icons.send_outlined : Icons.schedule_outlined,
                  ),
                ),
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
  const _ContentEditor({required this.api, required this.kind, this.initial});
  final ApiService api;
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
  late final TextEditingController _publishAt;
  late final TextEditingController _expiresAt;
  late final TextEditingController _targetDepartment;
  late final TextEditingController _targetSemester;
  late final TextEditingController _highlightsTitle;
  late final TextEditingController _highlights;

  bool _busy = false;
  bool _uploadingImage = false;
  final ImagePicker _imagePicker = ImagePicker();
  String? _imageError;

  Future<void> _pickAndUploadImage() async {
    String filename; Uint8List? selectedBytes;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result == null || result.files.isEmpty || !mounted) return;
      filename = result.files.single.name; selectedBytes = result.files.single.bytes;
    } else {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 1800);
      if (picked == null || !mounted) return;
      filename = picked.name; selectedBytes = await picked.readAsBytes();
    }
    final bytes = selectedBytes;
    if (bytes == null || bytes.isEmpty) { setState(() => _imageError = 'تعذر قراءة الصورة من المعرض.'); return; }
    if (bytes.length > 3 * 1024 * 1024) { setState(() => _imageError = 'الحد الأقصى للصورة 3 ميغابايت. اختر صورة أصغر.'); return; }
    final ext = filename.split('.').last.toLowerCase();
    final type = switch (ext) { 'jpg' || 'jpeg' => 'image/jpeg', 'png' => 'image/png', 'webp' => 'image/webp', _ => 'image/jpeg' };
    setState(() { _uploadingImage = true; _imageError = null; });
    try {
      final uploaded = await widget.api.uploadImage(bytes: bytes, filename: filename, contentType: type);
      final url = uploaded['url']?.toString() ?? '';
      if (url.isEmpty) throw const ApiServiceException('لم يُرجع الخادم رابط الصورة.');
      if (mounted) setState(() => _imageUrl.text = url);
    } catch (e) { if (mounted) setState(() => _imageError = e.toString()); }
    finally { if (mounted) setState(() => _uploadingImage = false); }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final existing = DateTime.tryParse(controller.text.trim());
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: existing ?? now, firstDate: DateTime(2000), lastDate: DateTime(2100), helpText: 'اختر التاريخ');
    if (picked != null) setState(() => controller.text = DateTime(picked.year, picked.month, picked.day, 12).toIso8601String());
  }

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
    _publishAt = TextEditingController(text: (item['publish_at'] ?? item['event_at'] ?? '').toString());
    _expiresAt = TextEditingController(text: item['expires_at']?.toString() ?? '');
    _targetDepartment = TextEditingController(text: item['target_department_id']?.toString() ?? '');
    _targetSemester = TextEditingController(text: item['target_semester_id']?.toString() ?? '');
    _highlightsTitle = TextEditingController(text: item['highlights_title']?.toString() ?? 'أبرز المحاور');
    final rawHighlights = item['highlights'];
    var highlightsText = rawHighlights?.toString() ?? '';
    if (rawHighlights is List) {
      highlightsText = rawHighlights.join('\n');
    } else if (rawHighlights is String && rawHighlights.trim().startsWith('[')) {
      try { final parsed = jsonDecode(rawHighlights); if (parsed is List) highlightsText = parsed.join('\n'); } catch (_) { /* Keep the original value visible for manual correction. */ }
    }
    _highlights = TextEditingController(text: highlightsText);

  }

  @override
  void dispose() {
    _title.dispose(); _imageUrl.dispose(); _body.dispose(); _category.dispose(); _publisher.dispose(); _location.dispose(); _type.dispose(); _eventAt.dispose(); _endAt.dispose(); _achievedAt.dispose(); _publishAt.dispose(); _expiresAt.dispose(); _targetDepartment.dispose(); _targetSemester.dispose(); _highlightsTitle.dispose(); _highlights.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    // Use a predictable local calendar date when the administrator leaves the
    // date empty; serialize it as an ISO timestamp only at the API boundary.
    final today = DateTime.now();
    final dateController = widget.kind == _ContentKind.events ? _eventAt : widget.kind == _ContentKind.achievements ? _achievedAt : _publishAt;
    if (dateController.text.trim().isEmpty && widget.kind != _ContentKind.announcements) {
      // Keep the selected calendar day stable across time zones. Noon local time
      // avoids an ISO midnight timestamp being interpreted as the previous day.
      dateController.text = DateTime(today.year, today.month, today.day, 12).toIso8601String();
    }
    final dateText = dateController.text.trim();
    final parsedDate = DateTime.tryParse(dateText)?.toLocal();
    final nowLocal = DateTime.now();
    final futureDate = parsedDate != null && DateTime(parsedDate.year, parsedDate.month, parsedDate.day).isAfter(DateTime(nowLocal.year, nowLocal.month, nowLocal.day));

    // Reject contradictory date ranges before writing them to the API.
    final publishDate = DateTime.tryParse(_publishAt.text.trim());
    final expiryDate = DateTime.tryParse(_expiresAt.text.trim());
    if (widget.kind == _ContentKind.news && publishDate != null && expiryDate != null && !expiryDate.isAfter(publishDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاريخ انتهاء الخبر يجب أن يأتي بعد تاريخ النشر.')));
      return;
    }
    final eventDate = DateTime.tryParse(_eventAt.text.trim());
    final eventEndDate = DateTime.tryParse(_endAt.text.trim());
    if (widget.kind == _ContentKind.events && eventDate != null && eventEndDate != null && eventEndDate.isBefore(eventDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نهاية الفعالية لا يمكن أن تسبق موعد بدايتها.')));
      return;
    }
    if (widget.kind == _ContentKind.announcements && publishDate != null && expiryDate != null && !expiryDate.isAfter(publishDate)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتهاء صلاحية الإعلان يجب أن يكون بعد موعد نشره.')));
      return;
    }

    final payload = <String, dynamic>{'title': title, 'status': widget.kind == _ContentKind.events ? 'published' : futureDate ? 'draft' : 'published'};
    // Keep the editor's category untouched. The upcoming label is derived for the
    // saved event only, so changing a date later cannot erase a category the user entered.
    final eventCategory = widget.kind == _ContentKind.events && futureDate
        ? 'قريباً'
        : _category.text.trim();
    switch (widget.kind) {
      case _ContentKind.news:
        payload.addAll({'body': body, 'category': _category.text.trim(), 'publisher': _publisher.text.trim(), 'image_url': _imageUrl.text.trim(), 'publish_at': _publishAt.text.trim(), 'expires_at': _expiresAt.text.trim()});
        break;
      case _ContentKind.events:
        payload.addAll({'body': body, 'category': eventCategory, 'publisher': _publisher.text.trim(), 'image_url': _imageUrl.text.trim(), 'location': _location.text.trim(), 'event_at': _eventAt.text.trim(), 'end_at': _endAt.text.trim()});
        break;
      case _ContentKind.achievements:
        payload.addAll({'description': body, 'intro': body, 'highlights_title': _highlightsTitle.text.trim(), 'highlights': jsonEncode(_highlights.text.split('\n').map((line) => line.trim()).where((line) => line.isNotEmpty).toList()), 'publisher': _publisher.text.trim(), 'badge': _category.text.trim(), 'image_url': _imageUrl.text.trim(), 'achieved_at': _achievedAt.text.trim()});
        break;
      case _ContentKind.announcements:
        payload.addAll({'body': body, 'type': _type.text.trim().isEmpty ? 'general' : _type.text.trim(), 'target_department_id': _targetDepartment.text.trim().isEmpty ? null : _targetDepartment.text.trim(), 'target_semester_id': _targetSemester.text.trim().isEmpty ? null : _targetSemester.text.trim(), 'publish_at': _publishAt.text.trim().isEmpty ? null : _publishAt.text.trim(), 'expires_at': _expiresAt.text.trim().isEmpty ? null : _expiresAt.text.trim()});
        break;
    }
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
        TextFormField(controller: _category, decoration: InputDecoration(labelText: widget.kind == _ContentKind.achievements ? 'شارة الإنجاز (اختياري)' : 'التصنيف (اختياري)')),
        const SizedBox(height: 12),
        TextFormField(controller: _publisher, decoration: const InputDecoration(labelText: 'اسم الناشر (اختياري)')),
      ],
      if (widget.kind == _ContentKind.news) ...[
        const SizedBox(height: 12), _DateField(controller: _publishAt, label: 'تاريخ النشر', onTap: () => _pickDate(_publishAt), onClear: () => setState(() => _publishAt.clear())),
        const SizedBox(height: 12), _DateField(controller: _expiresAt, label: 'تاريخ انتهاء الصلاحية', onTap: () => _pickDate(_expiresAt), onClear: () => setState(() => _expiresAt.clear())),
      ],
      if (widget.kind == _ContentKind.events) ...[
        const SizedBox(height: 12), TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'المكان (اختياري)')),
        const SizedBox(height: 12), _DateField(controller: _eventAt, label: 'موعد الفعالية', onTap: () => _pickDate(_eventAt), onClear: () => setState(() => _eventAt.clear())),
        const SizedBox(height: 12), _DateField(controller: _endAt, label: 'نهاية الفعالية', onTap: () => _pickDate(_endAt), onClear: () => setState(() => _endAt.clear())),
      ],
      if (widget.kind == _ContentKind.achievements) ...[
        const SizedBox(height: 12), _DateField(controller: _achievedAt, label: 'تاريخ الإنجاز', onTap: () => _pickDate(_achievedAt), onClear: () => setState(() => _achievedAt.clear())),
        const SizedBox(height: 12), TextFormField(controller: _highlightsTitle, decoration: const InputDecoration(labelText: 'عنوان أبرز المحاور')),
        const SizedBox(height: 12), TextFormField(controller: _highlights, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'أبرز المحاور (كل محور في سطر)')),
      ],
      if (widget.kind == _ContentKind.announcements) ...[
        const SizedBox(height: 12), TextFormField(controller: _type, decoration: const InputDecoration(labelText: 'نوع الإعلان (مثل general أو urgent)')),
        const SizedBox(height: 12), TextFormField(controller: _targetDepartment, decoration: const InputDecoration(labelText: 'معرّف القسم المستهدف (اختياري)')),
        const SizedBox(height: 12), TextFormField(controller: _targetSemester, decoration: const InputDecoration(labelText: 'معرّف الفصل المستهدف (اختياري)')),
        const SizedBox(height: 12), _DateField(controller: _publishAt, label: 'موعد النشر', onTap: () => _pickDate(_publishAt), onClear: () => setState(() => _publishAt.clear())),
        const SizedBox(height: 12), _DateField(controller: _expiresAt, label: 'موعد انتهاء الإشعار', onTap: () => _pickDate(_expiresAt), onClear: () => setState(() => _expiresAt.clear())),
      ],
      if (widget.kind == _ContentKind.news || widget.kind == _ContentKind.events || widget.kind == _ContentKind.achievements) ...[
        const SizedBox(height: 18),
        Align(alignment: AlignmentDirectional.centerStart, child: Text('الصورة (اختياري)', style: Theme.of(context).textTheme.titleSmall)),
        const SizedBox(height: 8),
        if (_imageUrl.text.isNotEmpty) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_imageUrl.text, height: 150, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 80, child: Center(child: Text('تعذرت معاينة الصورة الحالية.'))))),
        Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(onPressed: _uploadingImage ? null : _pickAndUploadImage, icon: _uploadingImage ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined), label: Text(_uploadingImage ? 'جارٍ رفع الصورة…' : 'اختيار صورة من المعرض'))),
        if (_imageError != null) Align(alignment: AlignmentDirectional.centerStart, child: Text(_imageError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
    ])))),
    actions: [TextButton(onPressed: (_busy || _uploadingImage) ? null : () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: (_busy || _uploadingImage) ? null : _save, child: const Text('حفظ'))],
  );
}


class _DateField extends StatelessWidget {
  const _DateField({required this.controller, required this.label, required this.onTap, required this.onClear});
  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  String _displayDate() {
    final value = DateTime.tryParse(controller.text.trim());
    if (value == null) return 'اختر من التقويم';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
  }

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: '$label (اختياري)',
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (controller.text.trim().isNotEmpty) IconButton(tooltip: 'مسح التاريخ', onPressed: onClear, icon: const Icon(Icons.close)),
          const Padding(padding: EdgeInsetsDirectional.only(end: 12), child: Icon(Icons.calendar_month_outlined)),
        ]),
      ),
      child: Text(_displayDate(), style: TextStyle(color: controller.text.trim().isEmpty ? Theme.of(context).hintColor : null)),
    ),
  );
}
