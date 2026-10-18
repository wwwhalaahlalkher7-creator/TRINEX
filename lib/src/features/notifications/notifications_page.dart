import 'package:flutter/material.dart';

import '../../api_service.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.api});
  final ApiService api;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  String _query = '';
  String _statusFilter = 'all';
  final Set<String> _sending = {};
  final Set<String> _deleting = {};
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _semesters = [];
  int _loadRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadAudienceOptions();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.get('/admin/notifications?limit=100');
      final raw = response['data'];
      final rows = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (mounted && revision == _loadRevision) {
        setState(() => _items = rows);
      }
    } catch (e) {
      if (mounted && revision == _loadRevision) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && revision == _loadRevision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadAudienceOptions() async {
    try {
      final responses = await Future.wait([
        widget.api.get('/departments'),
        widget.api.get('/semesters'),
      ]);
      List<Map<String, dynamic>> rows(dynamic value) => value is List
          ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _departments = rows(responses[0]['data']);
          _semesters = rows(responses[1]['data']);
        });
      }
    } catch (_) {
      // Content management remains available with ID fields if lookup lists
      // cannot be loaded; a temporary lookup failure must not hide notifications.
    }
  }

  DateTime? _date(dynamic value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  bool _isScheduled(Map<String, dynamic> item) {
    final publishAt = _date(item['publish_at']);
    return item['status'] == 'published' &&
        publishAt != null && publishAt.isAfter(DateTime.now());
  }

  String _statusLabel(Map<String, dynamic> item) {
    final status = item['status']?.toString().trim() ?? '';
    if (status == 'draft') return 'مسودة';
    if (_isScheduled(item) || status == 'scheduled') return 'مجدول';
    if (status == 'published') return 'منشور';
    if (status == 'queued') return 'قيد التجهيز';
    if (status == 'sent') return 'تم الإرسال';
    if (status == 'failed') return 'تعذر الإرسال';
    if (status == 'cancelled') return 'ملغي';
    if (status == 'archived') return 'مؤرشف';
    return status.isEmpty ? 'غير محددة' : status;
  }

  List<Map<String, dynamic>> get _filteredItems {
    final query = _query.trim().toLowerCase();
    return _items.where((item) {
      final status = item['status']?.toString() ?? '';
      final matchesStatus = switch (_statusFilter) {
        'draft' => status == 'draft',
        'published' => status == 'published' || status == 'scheduled',
        'other' => status != 'draft' && status != 'published' && status != 'scheduled',
        _ => true,
      };
      final searchable = '${item['title'] ?? ''} ${item['body'] ?? ''} ${item['type'] ?? ''} ${item['target_department_id'] ?? ''} ${item['target_semester_id'] ?? ''}'
          .toLowerCase();
      return matchesStatus && (query.isEmpty || searchable.contains(query));
    }).toList();
  }

  int _countStatus(String status) =>
      _items.where((item) => item['status'] == status).length;

  int _countAllTargets() => _items.fold<int>(
      0, (sum, item) => sum + (_asInt(item['targets'])));

  int _countAllReads() => _items.fold<int>(
      0, (sum, item) => sum + (_asInt(item['reads'])));

  int _asInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;

  String _audienceLabel(List<Map<String, dynamic>> rows, String id) {
    for (final row in rows) {
      if (row['id']?.toString() == id) {
        return (row['name_ar'] ?? row['name'] ?? row['title'] ?? row['code'] ?? id).toString();
      }
    }
    return id;
  }

  Future<void> _editAnnouncement([Map<String, dynamic>? item]) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AnnouncementEditor(
        initial: item,
        departments: _departments,
        semesters: _semesters,
      ),
    );
    if (result == null || !mounted) return;

    final id = item?['id']?.toString();
    try {
      if (id == null || id.isEmpty) {
        await widget.api.post('/admin/announcements', body: result);
      } else {
        await widget.api.patch('/admin/announcements/$id', body: result);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(id == null || id.isEmpty
            ? 'تم إنشاء مسودة الإشعار.'
            : 'تم حفظ تعديلات الإشعار.'),
      ));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ الإشعار: $e')),
        );
      }
    }
  }

  Future<void> _changeStatus(
    Map<String, dynamic> item, {
    required String nextStatus,
    required String title,
    required String message,
    required String successMessage,
  }) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.patch('/admin/announcements/$id', body: {
        'status': nextStatus,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تغيير حالة الإشعار: $e')),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الإشعار؟'),
        content: Text(
          'سيُحذف «${item['title'] ?? 'هذا الإشعار'}» من إدارة الإشعارات. لا يمكن التراجع عن هذا الإجراء من التطبيق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف الإشعار'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(id));
    try {
      await widget.api.delete('/admin/announcements/$id');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف الإشعار.')),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حذف الإشعار: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  Future<void> _send(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'published' || _isScheduled(item)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال الإشعار؟'),
        content: Text(
          'سيُجهّز «${item['title'] ?? 'الإعلان'}» للإرسال إلى الطلاب النشطين المطابقين للقسم والفصل المحددين. الإرسال المتكرر آمن ولا ينشئ استهدافات مكررة. تجهيز قائمة المستهدفين لا يضمن وصول إشعار Push إلى الجهاز.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد الإرسال'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sending.add(id));
    try {
      final result = await widget.api.post(
        '/admin/notifications/send',
        body: {'announcementId': id},
      );
      final data = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'] as Map)
          : result;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'تم تجهيز الإشعار. المستهدفون: ${data['targets'] ?? '—'}، الجدد: ${data['newTargets'] ?? '—'}.',
        ),
      ));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تجهيز الإشعار للإرسال: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(id));
    }
  }

  Widget _stat(String label, int value, IconData icon) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20),
            const SizedBox(width: 9),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredItems;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('إدارة الإشعارات', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text('أنشئ الإشعارات، راجع محتواها وجمهورها، ثم اعتمدها وجهّزها للإرسال.', style: theme.textTheme.bodyMedium),
              ]),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث'),
                ),
                FilledButton.icon(
                  onPressed: () => _editAnnouncement(),
                  icon: const Icon(Icons.add_alert_outlined),
                  label: const Text('إنشاء إشعار'),
                ),
              ]),
            ],
          ),
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline),
                SizedBox(width: 10),
                Expanded(child: Text('النشر يجعل الإشعار جاهزًا للتجهيز، لكنه لا يعني أن إشعار Push وصل إلى أجهزة الطلاب. زر الإرسال يحدّث قائمة المستهدفين على الخادم، ويعتمد التسليم الفعلي على إعدادات خدمة الإشعارات.')),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _stat('كل الإشعارات', _items.length, Icons.notifications_outlined),
            _stat('المسودات', _countStatus('draft'), Icons.edit_note_outlined),
            _stat('المنشورة', _countStatus('published'), Icons.campaign_outlined),
            _stat('المستهدفون', _countAllTargets(), Icons.groups_outlined),
            _stat('القراءات', _countAllReads(), Icons.mark_email_read_outlined),
          ]),
          const SizedBox(height: 14),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'بحث في العنوان والنص والنوع ومعرّفات الاستهداف',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('الكل'), selected: _statusFilter == 'all', onSelected: (_) => setState(() => _statusFilter = 'all')),
            ChoiceChip(label: const Text('المسودات'), selected: _statusFilter == 'draft', onSelected: (_) => setState(() => _statusFilter = 'draft')),
            ChoiceChip(label: const Text('المنشورة / المجدولة'), selected: _statusFilter == 'published', onSelected: (_) => setState(() => _statusFilter = 'published')),
            ChoiceChip(label: const Text('حالات أخرى'), selected: _statusFilter == 'other', onSelected: (_) => setState(() => _statusFilter = 'other')),
          ]),
          const SizedBox(height: 10),
          if (_loading && _items.isEmpty)
            const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تعذر تحميل الإشعارات: $_error'),
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))),
            ]))),
          if (!_loading && _error == null && filtered.isEmpty)
            Card(child: Padding(padding: const EdgeInsets.all(26), child: Column(children: [
              const Icon(Icons.notifications_off_outlined, size: 38),
              const SizedBox(height: 10),
              Text(_items.isEmpty ? 'لا توجد إشعارات حتى الآن.' : 'لا توجد إشعارات تطابق البحث والتصفية.'),
              const SizedBox(height: 8),
              if (_items.isEmpty) FilledButton.icon(onPressed: () => _editAnnouncement(), icon: const Icon(Icons.add), label: const Text('إنشاء أول إشعار')),
            ]))),
          if (filtered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('النتائج: ${filtered.length}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            for (final item in filtered) _notificationCard(item, theme),
          ],
        ],
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> item, ThemeData theme) {
    final id = item['id']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final busySending = _sending.contains(id);
    final busyDeleting = _deleting.contains(id);
    final canEdit = status == 'draft' || status == 'published';
    final canSend = status == 'published' && !_isScheduled(item) && !busySending;
    final publishAt = item['publish_at']?.toString();
    final expiresAt = item['expires_at']?.toString();
    final department = item['target_department_id']?.toString();
    final semester = item['target_semester_id']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.notifications_active_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['title']?.toString() ?? 'إشعار بلا عنوان', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Chip(label: Text(_statusLabel(item)), visualDensity: VisualDensity.compact),
                Chip(label: Text('النوع: ${item['type'] ?? 'عام'}'), visualDensity: VisualDensity.compact),
              ]),
            ])),
            if (busyDeleting) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if ((item['body'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(item['body'].toString(), maxLines: 5, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _detail(Icons.groups_outlined, 'المستهدفون: ${item['targets'] ?? 0}'),
            _detail(Icons.mark_email_read_outlined, 'القراءات: ${item['reads'] ?? 0}'),
            if (department != null && department.isNotEmpty) _detail(Icons.account_tree_outlined, 'القسم: ${_audienceLabel(_departments, department)}'),
            if (semester != null && semester.isNotEmpty) _detail(Icons.school_outlined, 'الفصل: ${_audienceLabel(_semesters, semester)}'),
            if (publishAt != null && publishAt.isNotEmpty) _detail(Icons.schedule_outlined, 'النشر: $publishAt'),
            if (expiresAt != null && expiresAt.isNotEmpty) _detail(Icons.event_busy_outlined, 'الانتهاء: $expiresAt'),
          ]),
          const Divider(height: 24),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            if (canEdit)
              OutlinedButton.icon(
                onPressed: busyDeleting ? null : () => _editAnnouncement(item),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('تحرير المحتوى'),
              ),
            if (status == 'draft')
              FilledButton.tonalIcon(
                onPressed: busyDeleting ? null : () => _changeStatus(
                  item,
                  nextStatus: 'published',
                  title: 'اعتماد الإشعار ونشره؟',
                  message: 'سيصبح الإشعار منشورًا أو مجدولًا حسب تاريخ النشر. هذا الإجراء لا يرسل إشعار Push تلقائيًا.',
                  successMessage: 'تم اعتماد الإشعار ونشره.',
                ),
                icon: const Icon(Icons.publish_outlined),
                label: const Text('اعتماد ونشر'),
              ),
            if (status == 'published')
              OutlinedButton.icon(
                onPressed: busyDeleting ? null : () => _changeStatus(
                  item,
                  nextStatus: 'draft',
                  title: 'إرجاع الإشعار إلى مسودة؟',
                  message: 'سيتوقف ظهوره كإشعار منشور داخل الإدارة. هذا لا يسحب إشعارًا سبق تجهيزه أو تسليمه للطلاب.',
                  successMessage: 'تم إرجاع الإشعار إلى مسودة.',
                ),
                icon: const Icon(Icons.undo_outlined),
                label: const Text('إرجاع لمسودة'),
              ),
            if (status == 'published')
              FilledButton.tonalIcon(
                onPressed: canSend && !busyDeleting ? () => _send(item) : null,
                icon: busySending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined),
                label: Text(_isScheduled(item) ? 'لم يحن موعد الإرسال' : 'إرسال / تحديث الاستهداف'),
              ),
            OutlinedButton.icon(
              onPressed: busyDeleting ? null : () => _delete(item),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _detail(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)],
      );
}

class _AnnouncementEditor extends StatefulWidget {
  const _AnnouncementEditor({
    this.initial,
    required this.departments,
    required this.semesters,
  });
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> semesters;

  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _type;
  late final TextEditingController _department;
  late final TextEditingController _semester;
  String? _selectedDepartment;
  String? _selectedSemester;
  late final TextEditingController _publishAt;
  late final TextEditingController _expiresAt;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    _title = TextEditingController(text: item?['title']?.toString() ?? '');
    _body = TextEditingController(text: item?['body']?.toString() ?? '');
    _type = TextEditingController(text: item?['type']?.toString() ?? 'general');
    _department = TextEditingController(text: item?['target_department_id']?.toString() ?? '');
    _semester = TextEditingController(text: item?['target_semester_id']?.toString() ?? '');
    _selectedDepartment = _optionValue(widget.departments, _department.text);
    _selectedSemester = _optionValue(widget.semesters, _semester.text);
    _publishAt = TextEditingController(text: _dateInput(item?['publish_at']));
    _expiresAt = TextEditingController(text: _dateInput(item?['expires_at']));
  }

  String _rowName(Map<String, dynamic> row) =>
      (row['name_ar'] ?? row['name'] ?? row['title'] ?? row['code'] ?? row['id'] ?? 'غير محدد').toString();

  String? _optionValue(List<Map<String, dynamic>> rows, String value) {
    if (value.trim().isEmpty) return '';
    return rows.any((row) => row['id']?.toString() == value) ? value : null;
  }

  List<DropdownMenuItem<String>> _audienceOptions(
    List<Map<String, dynamic>> rows,
    String? currentValue,
    String emptyLabel,
  ) {
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(value: '', child: Text(emptyLabel)),
    ];
    for (final row in rows) {
      final id = row['id']?.toString() ?? '';
      if (id.isEmpty || items.any((entry) => entry.value == id)) continue;
      items.add(DropdownMenuItem<String>(value: id, child: Text(_rowName(row), overflow: TextOverflow.ellipsis)));
    }
    final hasCurrent = currentValue != null && items.any((entry) => entry.value == currentValue);
    if (currentValue != null && currentValue.isNotEmpty && !hasCurrent) {
      items.add(DropdownMenuItem<String>(value: currentValue, child: Text('المعرّف الحالي: $currentValue')));
    }
    return items;
  }

  String _dateInput(dynamic value) {
    final date = value == null ? null : DateTime.tryParse(value.toString());
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _type.dispose();
    _department.dispose();
    _semester.dispose();
    _publishAt.dispose();
    _expiresAt.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'اختر التاريخ',
    );
    if (picked == null || !mounted) return;
    final month = picked.month.toString().padLeft(2, '0');
    final day = picked.day.toString().padLeft(2, '0');
    setState(() => controller.text = '${picked.year}-$month-$day');
  }

  String? _optionalIsoDate(String value) {
    if (value.trim().isEmpty) return null;
    final date = DateTime.tryParse(value.trim());
    if (date == null) return null;
    return DateTime(date.year, date.month, date.day).toIso8601String();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final publishAt = _optionalIsoDate(_publishAt.text);
    final expiresAt = _optionalIsoDate(_expiresAt.text);
    if (_publishAt.text.trim().isNotEmpty && publishAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاريخ النشر غير صالح.')));
      return;
    }
    if (_expiresAt.text.trim().isNotEmpty && expiresAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاريخ الانتهاء غير صالح.')));
      return;
    }
    if (publishAt != null && expiresAt != null && DateTime.parse(expiresAt).isBefore(DateTime.parse(publishAt))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تاريخ الانتهاء يجب ألا يسبق تاريخ النشر.')));
      return;
    }

    final result = <String, dynamic>{
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'type': _type.text.trim().isEmpty ? 'general' : _type.text.trim(),
      'target_department_id': _department.text.trim().isEmpty ? null : _department.text.trim(),
      'target_semester_id': _semester.text.trim().isEmpty ? null : _semester.text.trim(),
      'publish_at': publishAt,
      'expires_at': expiresAt,
    };
    if (widget.initial == null) result['status'] = 'draft';
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isCreate = widget.initial == null;
    return AlertDialog(
      title: Text(isCreate ? 'إنشاء إشعار جديد' : 'تحرير محتوى الإشعار'),
      content: SizedBox(
        width: 540,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.68),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'عنوان الإشعار'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'العنوان مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _body,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'نص الإشعار'),
                  validator: (value) => value == null || value.trim().isEmpty ? 'نص الإشعار مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _type,
                  decoration: const InputDecoration(labelText: 'النوع (مثال: عام، أكاديمي، جدول)'),
                ),
                const SizedBox(height: 12),
                if (widget.departments.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDepartment ?? _department.text.trim(),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'القسم المستهدف'),
                    items: _audienceOptions(
                      widget.departments,
                      _department.text.trim(),
                      'كل الأقسام',
                    ),
                    onChanged: (value) => setState(() {
                      _selectedDepartment = value;
                      _department.text = value ?? '';
                    }),
                  )
                else
                  TextFormField(
                    controller: _department,
                    decoration: const InputDecoration(labelText: 'معرّف القسم المستهدف (فارغ = كل الأقسام)'),
                  ),
                const SizedBox(height: 12),
                if (widget.semesters.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSemester ?? _semester.text.trim(),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الفصل المستهدف'),
                    items: _audienceOptions(
                      widget.semesters,
                      _semester.text.trim(),
                      'كل الفصول',
                    ),
                    onChanged: (value) => setState(() {
                      _selectedSemester = value;
                      _semester.text = value ?? '';
                    }),
                  )
                else
                  TextFormField(
                    controller: _semester,
                    decoration: const InputDecoration(labelText: 'معرّف الفصل المستهدف (فارغ = كل الفصول)'),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _publishAt,
                  readOnly: true,
                  onTap: () => _pickDate(_publishAt),
                  decoration: const InputDecoration(labelText: 'تاريخ النشر / الجدولة (اختياري)', suffixIcon: Icon(Icons.calendar_month_outlined)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiresAt,
                  readOnly: true,
                  onTap: () => _pickDate(_expiresAt),
                  decoration: const InputDecoration(labelText: 'تاريخ انتهاء الصلاحية (اختياري)', suffixIcon: Icon(Icons.event_busy_outlined)),
                ),
                if (isCreate) ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('سيُحفظ الإشعار كمسودة أولًا، ولن يُنشر أو يُجهّز للإرسال قبل اعتمادك له.'),
                  ),
                ] else if (widget.initial?['status'] == 'published') ...[
                  const SizedBox(height: 12),
                  const Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('حفظ التعديلات لا يعيد إرسال الإشعار تلقائيًا إلى الطلاب.'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: const Text('حفظ')),
      ],
    );
  }
}
