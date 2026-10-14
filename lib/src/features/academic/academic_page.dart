import 'package:flutter/material.dart';

import '../../api_service.dart';

class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key, required this.api, required this.initialTab, this.scheduleOnly = false});
  final ApiService api;
  final int initialTab;
  final bool scheduleOnly;

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  final List<Map<String, dynamic>> _subjects = [];
  final List<Map<String, dynamic>> _materials = [];
  final List<Map<String, dynamic>> _schedules = [];
  final List<Map<String, dynamic>> _departments = [];
  final List<Map<String, dynamic>> _semesters = [];
  List<Map<String, dynamic>> _driveRuns = [];
  bool _loading = false;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.scheduleOnly ? 1 : 3, vsync: this, initialIndex: widget.scheduleOnly ? 0 : widget.initialTab.clamp(0, 2).toInt());
    _tabs.addListener(() { if (!_tabs.indexIsChanging && mounted) setState(() {}); });
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is List) return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (value is Map && value['data'] is List) return _rows(value['data']);
    return [];
  }

  Future<List<Map<String, dynamic>>> _fetch(String path) async {
    final result = await widget.api.get(path);
    return _rows(result['data'] ?? result);
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _fetch('/admin/subjects?limit=100'),
        _fetch('/admin/materials?limit=100'),
        _fetch('/admin/schedule?limit=100'),
        _fetch('/departments'),
        _fetch('/semesters'),
        _fetch('/admin/drive/sync-status'),
      ]);
      if (!mounted) return;
      setState(() {
        _replace(_subjects, results[0]);
        _replace(_materials, results[1]);
        _replace(_schedules, results[2]);
        _replace(_departments, results[3]);
        _replace(_semesters, results[4]);
        _driveRuns = results[5];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _replace(List<Map<String, dynamic>> target, List<Map<String, dynamic>> values) {
    target..clear()..addAll(values);
  }

  List<Map<String, dynamic>> get _activeRows {
    final rows = widget.scheduleOnly ? _schedules : switch (_tabs.index) {
      0 => _subjects,
      1 => _materials,
      _ => _driveRuns,
    };
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) => row.values.any((value) => value.toString().toLowerCase().contains(q))).toList();
  }

  int get _activeIndex => widget.scheduleOnly ? 2 : _tabs.index;
  String get _resource => switch (_activeIndex) { 0 => 'subjects', 1 => 'materials', 2 => 'schedule', _ => 'drive' };
  String get _title => switch (_activeIndex) { 0 => 'المقررات', 1 => 'المواد الدراسية', 2 => 'الجداول الأكاديمية', _ => 'مزامنة Google Drive' };

  Future<void> _syncDrive() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('بدء مزامنة Google Drive؟'),
      content: const Text('ستُحدّث المواد الموجودة وتُعطّل السجلات التي لم تعد موجودة في الفهرس. لن تُحذف الملفات من Drive بواسطة عملية المزامنة المعتادة.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بدء المزامنة'))],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _syncing = true);
    try {
      await widget.api.post('/admin/drive/sync');
      if (!mounted) return;
      _message('تم إرسال طلب المزامنة بنجاح.');
      await _loadAll();
    } catch (e) {
      if (mounted) _message('تعذرت المزامنة: $e', error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? Theme.of(context).colorScheme.error : null));
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    if (!widget.scheduleOnly && _tabs.index == 2) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AcademicEditor(
        resource: _resource,
        initial: item,
        subjects: _subjects,
        departments: _departments,
        semesters: _semesters,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final id = item?['id']?.toString();
      if (id == null || id.isEmpty) {
        await widget.api.post('/admin/$_resource', body: result);
      } else {
        await widget.api.patch('/admin/$_resource/$id', body: result);
      }
      _message(id == null ? 'تمت إضافة السجل.' : 'تم حفظ التعديلات.');
      await _loadAll();
    } catch (e) {
      if (mounted) _message('تعذر حفظ السجل: $e', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('تأكيد الحذف'),
      content: Text(_activeIndex == 1 && (item['drive_file_id'] ?? '').toString().isNotEmpty
          ? 'هل تريد حذف «${item['title'] ?? item['id']}»؟ قد يحذف الخادم ملف Google Drive المرتبط نهائيًا إذا كانت إعدادات التكامل تسمح بذلك.'
          : _activeIndex == 0
              ? 'هل تريد حذف المقرر «${item['name_ar'] ?? item['id']}»؟ قد يحذف الخادم المواد والجداول المرتبطة به، وقد يشمل ذلك ملفات Drive المرتبطة.'
              : 'هل تريد حذف «${item['title'] ?? item['name_ar'] ?? item['id']}»؟ قد يؤثر ذلك على البيانات المرتبطة.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف'))],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.delete('/admin/$_resource/$id');
      _message('تم حذف السجل.');
      await _loadAll();
    } catch (e) {
      if (mounted) _message('تعذر حذف السجل: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('الإدارة الأكاديمية', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('المقررات والمواد والجداول ومزامنة الملفات', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))])),
          IconButton(tooltip: 'تحديث البيانات', onPressed: _loading ? null : _loadAll, icon: const Icon(Icons.refresh)),
        ]),
        const SizedBox(height: 18),
        if (!widget.scheduleOnly) Card(clipBehavior: Clip.antiAlias, child: TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(icon: Icon(Icons.class_outlined), text: 'المقررات'), Tab(icon: Icon(Icons.menu_book_outlined), text: 'المواد الدراسية'), Tab(icon: Icon(Icons.cloud_sync_outlined), text: 'مزامنة Drive')])),
        if (widget.scheduleOnly) Text('الجداول الأكاديمية', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 14),
        if (!widget.scheduleOnly && _tabs.index != 2) TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'ابحث في $_title...', suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: () { _search.clear(); setState(() {}); }, icon: const Icon(Icons.close)))),
        if (!widget.scheduleOnly && _tabs.index != 2) const SizedBox(height: 12),
        if (widget.scheduleOnly || _tabs.index != 2) Align(alignment: AlignmentDirectional.centerStart, child: FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text('إضافة ${_activeIndex == 0 ? 'مقرر' : _activeIndex == 1 ? 'مادة' : 'موعد'}'))),
        if (!widget.scheduleOnly && _tabs.index != 2) const SizedBox(height: 12),
        if (_loading && _activeRows.isEmpty) const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_error != null && _activeRows.isEmpty) Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off_outlined, size: 42), const SizedBox(height: 12), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _loadAll, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))])))
        else if (!widget.scheduleOnly && _tabs.index == 2) Expanded(child: _buildDrive(theme))
        else Expanded(child: _activeRows.isEmpty ? Center(child: Text(_loading ? 'جارٍ التحميل...' : 'لا توجد سجلات مطابقة.')) : ListView.separated(itemCount: _activeRows.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (context, index) => _rowCard(_activeRows[index], theme))),
      ]),
    ));
  }

  Widget _rowCard(Map<String, dynamic> row, ThemeData theme) {
    final title = (row['title'] ?? row['name_ar'] ?? row['subject_name'] ?? 'سجل ${row['id'] ?? ''}').toString();
    final subtitle = switch (_activeIndex) {
      0 => 'القسم: ${row['department_id'] ?? '—'}  •  الفصل: ${row['semester_id'] ?? '—'}  •  الرمز: ${row['code'] ?? '—'}',
      1 => 'المقرر: ${_subjectLabel(row['subject_id'])}  •  المصدر: ${row['source'] ?? 'يدوي'}',
      _ => '${_dayLabel(row['day_of_week'])}  •  ${row['start_time'] ?? '--:--'} – ${row['end_time'] ?? '--:--'}  •  القاعة: ${row['room'] ?? '—'}',
    };
    return Card(child: ListTile(
      leading: CircleAvatar(child: Icon(_activeIndex == 0 ? Icons.class_outlined : _activeIndex == 1 ? Icons.menu_book_outlined : Icons.event_note_outlined)),
      title: Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(subtitle)),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(onSelected: (action) { if (action == 'edit') _edit(row); if (action == 'delete') _delete(row); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('تعديل')), PopupMenuItem(value: 'delete', child: Text('حذف'))]),
      onTap: () => _edit(row),
      dense: false,
    ));
  }

  Widget _buildDrive(ThemeData theme) => ListView(children: [
    Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Icon(Icons.cloud_sync_outlined, size: 30, color: theme.colorScheme.primary), const SizedBox(width: 12), Expanded(child: Text('مزامنة المواد من Google Drive', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 10),
      const Text('تستورد المزامنة فهرس الملفات من مصدر Drive المهيأ على الخادم. لا تُخزّن بيانات اعتماد Google داخل التطبيق.'),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _syncing ? null : _syncDrive, icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync), label: Text(_syncing ? 'جارٍ طلب المزامنة...' : 'بدء المزامنة')),
    ]))),
    const SizedBox(height: 8),
    Text('آخر عمليات المزامنة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    if (_driveRuns.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('لا توجد عمليات مزامنة مسجلة أو لا تتوفر صلاحية الوصول.'))),
    ..._driveRuns.map((run) => Card(child: ListTile(
      leading: Icon((run['status']?.toString() == 'success') ? Icons.check_circle_outline : (run['status']?.toString() == 'failed') ? Icons.error_outline : Icons.pending_outlined),
      title: Text('الحالة: ${_driveStatus(run['status'])}'),
      subtitle: Text('بدأت: ${run['started_at'] ?? '—'}\nالملفات: ${run['files_seen'] ?? 0}  •  أضيف/حُدّث: ${run['materials_upserted'] ?? 0}  •  عُطّل: ${run['materials_deactivated'] ?? 0}${(run['error_message'] ?? '').toString().isEmpty ? '' : '\nالخطأ: ${run['error_message']}'}'),
      isThreeLine: true,
    ))),
  ]);

  String _subjectLabel(dynamic id) {
    for (final subject in _subjects) {
      if (subject['id']?.toString() == id?.toString()) {
        return '${subject['name_ar'] ?? subject['id']}';
      }
    }
    return id?.toString() ?? '—';
  }

  String _dayLabel(dynamic value) {
    const days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
    final index = int.tryParse(value?.toString() ?? '');
    return index != null && index >= 0 && index < days.length ? days[index] : 'يوم غير محدد';
  }

  String _driveStatus(dynamic value) => switch (value?.toString()) { 'success' => 'نجحت', 'failed' => 'فشلت', 'running' => 'قيد التنفيذ', _ => value?.toString() ?? 'غير معروف' };
}

class _AcademicEditor extends StatefulWidget {
  const _AcademicEditor({required this.resource, required this.subjects, required this.departments, required this.semesters, this.initial});
  final String resource;
  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> subjects;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> semesters;
  @override
  State<_AcademicEditor> createState() => _AcademicEditorState();
}

class _AcademicEditorState extends State<_AcademicEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late String? _subjectId;
  late String? _departmentId;
  late String? _semesterId;
  late int _day;
  late bool _active;
  late bool _pinned;
  bool get _isSubject => widget.resource == 'subjects';
  bool get _isMaterial => widget.resource == 'materials';

  @override
  void initState() {
    super.initState();
    final item = widget.initial ?? {};
    final keys = _isSubject
        ? ['name_ar', 'name_en', 'code', 'sort_order']
        : _isMaterial
            ? ['title', 'description', 'drive_file_id', 'drive_url', 'mime_type', 'sort_order']
            : ['start_time', 'end_time', 'room', 'lecturer'];
    _controllers = {for (final key in keys) key: TextEditingController(text: (key == 'start_time' || key == 'end_time') ? _formatStoredTime(item[key]?.toString() ?? '') : item[key]?.toString() ?? '')};
    _subjectId = item['subject_id']?.toString();
    _departmentId = item['department_id']?.toString();
    _semesterId = item['semester_id']?.toString();
    _day = int.tryParse(item['day_of_week']?.toString() ?? '') ?? 0;
    _active = item['active'] == null ? true : (item['active'] == 1 || item['active'] == true);
    _pinned = item['pinned'] == 1 || item['pinned'] == true;
  }

  @override
  void dispose() { for (final controller in _controllers.values) { controller.dispose(); } super.dispose(); }

  String _formatStoredTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return value;
    final hour = int.tryParse(match.group(1)!) ?? 0;
    final minute = match.group(2)!;
    final suffix = hour >= 12 ? 'مساءً' : 'صباحًا';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:$minute $suffix';
  }

  String _apiTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(صباحًا|مساءً)$').firstMatch(value.trim());
    if (match == null) return value.trim();
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final evening = match.group(3) == 'مساءً';
    if (hour == 12) hour = 0;
    if (evening) hour += 12;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTime(String key) async {
    final current = _apiTime(_controllers[key]!.text);
    final parts = current.split(':');
    final initial = TimeOfDay(hour: parts.length == 2 ? (int.tryParse(parts[0]) ?? 8).clamp(0, 23).toInt() : 8, minute: parts.length == 2 ? (int.tryParse(parts[1]) ?? 0).clamp(0, 59).toInt() : 0);
    final picked = await showTimePicker(context: context, initialTime: initial, helpText: 'اختر الوقت', builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false), child: child!));
    if (picked == null || !mounted) return;
    final suffix = picked.period == DayPeriod.am ? 'صباحًا' : 'مساءً';
    final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    setState(() => _controllers[key]!.text = '$hour:${picked.minute.toString().padLeft(2, '0')} $suffix');
  }

  String _label(String key) => switch (key) {
    'name_ar' => 'اسم المقرر بالعربية', 'name_en' => 'اسم المقرر بالإنجليزية (اختياري)', 'code' => 'رمز المقرر',
    'sort_order' => 'ترتيب العرض', 'title' => 'عنوان المادة', 'description' => 'وصف المادة', 'drive_file_id' => 'معرّف ملف Drive (اختياري)',
    'drive_url' => 'رابط الملف (اختياري)', 'mime_type' => 'نوع الملف (اختياري)', 'start_time' => 'وقت البداية',
    'end_time' => 'وقت النهاية', 'room' => 'القاعة', 'lecturer' => 'المحاضر', _ => key,
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final result = <String, dynamic>{'active': _active ? 1 : 0};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      if (value.isEmpty) continue;
      if (entry.key == 'sort_order') { result[entry.key] = int.tryParse(value) ?? 0; } else if (entry.key == 'start_time' || entry.key == 'end_time') { result[entry.key] = _apiTime(value); } else { result[entry.key] = value; }
    }
    if (_isSubject) {
      if (_departmentId == null || _semesterId == null) { _showError('اختر القسم والفصل الدراسي.'); return; }
      result.addAll({'department_id': _departmentId, 'semester_id': _semesterId});
    } else if (_isMaterial) {
      if (_subjectId == null) { _showError('اختر المقرر المرتبط بالمادة.'); return; }
      result['subject_id'] = _subjectId;
      result['pinned'] = _pinned ? 1 : 0;
      result['source'] = widget.initial?['source'] ?? 'manual';
    } else {
      if (_subjectId == null || _departmentId == null || _semesterId == null) { _showError('اختر المقرر والقسم والفصل.'); return; }
      result.addAll({'subject_id': _subjectId, 'department_id': _departmentId, 'semester_id': _semesterId, 'day_of_week': _day});
    }
    Navigator.pop(context, result);
  }

  void _showError(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'إضافة ${_isSubject ? 'مقرر' : _isMaterial ? 'مادة دراسية' : 'موعد دراسي'}' : 'تعديل السجل'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_isSubject || !_isMaterial) _dropdown('القسم الأكاديمي', _departmentId, widget.departments, (v) => setState(() { _departmentId = v; _subjectId = null; }), 'name_ar'),
      if (_isSubject || !_isMaterial) _dropdown('الفصل الدراسي', _semesterId, widget.semesters, (v) => setState(() { _semesterId = v; _subjectId = null; }), 'name_ar'),
      if (_isMaterial || !_isSubject) _dropdown('المقرر', _subjectId, widget.subjects.where((s) => (_departmentId == null || s['department_id']?.toString() == _departmentId) && (_semesterId == null || s['semester_id']?.toString() == _semesterId)).toList(), (v) => setState(() => _subjectId = v), 'name_ar'),
      if (!_isSubject && !_isMaterial) DropdownButtonFormField<int>(value: _day, decoration: const InputDecoration(labelText: 'اليوم'), items: const [DropdownMenuItem(value: 0, child: Text('الأحد')), DropdownMenuItem(value: 1, child: Text('الاثنين')), DropdownMenuItem(value: 2, child: Text('الثلاثاء')), DropdownMenuItem(value: 3, child: Text('الأربعاء')), DropdownMenuItem(value: 4, child: Text('الخميس')), DropdownMenuItem(value: 5, child: Text('الجمعة')), DropdownMenuItem(value: 6, child: Text('السبت'))], onChanged: (v) => setState(() => _day = v ?? 0)),
      ..._controllers.entries.map((entry) => Padding(padding: const EdgeInsets.only(top: 10), child: TextFormField(controller: entry.value, readOnly: entry.key == 'start_time' || entry.key == 'end_time', onTap: entry.key == 'start_time' || entry.key == 'end_time' ? () => _pickTime(entry.key) : null, decoration: InputDecoration(labelText: _label(entry.key), suffixIcon: entry.key == 'start_time' || entry.key == 'end_time' ? const Icon(Icons.schedule_outlined) : null, hintText: entry.key == 'start_time' || entry.key == 'end_time' ? 'اختر الساعة والدقيقة' : null), keyboardType: entry.key == 'sort_order' ? TextInputType.number : TextInputType.text, validator: (v) => entry.key == 'title' && (v == null || v.trim().isEmpty) ? 'العنوان مطلوب' : entry.key == 'name_ar' && (v == null || v.trim().isEmpty) ? 'اسم المقرر مطلوب' : null))),
      if (_isMaterial) CheckboxListTile(value: _pinned, onChanged: (v) => setState(() => _pinned = v ?? false), contentPadding: EdgeInsets.zero, title: const Text('تثبيت المادة في الأعلى')),
      SwitchListTile(value: _active, onChanged: (v) => setState(() => _active = v), contentPadding: EdgeInsets.zero, title: const Text('نشط')),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: _save, child: const Text('حفظ'))],
  );

  Widget _dropdown(String label, String? value, List<Map<String, dynamic>> options, ValueChanged<String?> onChanged, String titleKey) {
    final validValue = options.any((row) => row['id']?.toString() == value) ? value : null;
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
      value: validValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.map((row) => DropdownMenuItem(value: row['id']?.toString(), child: Text('${row[titleKey] ?? row['name'] ?? row['id']}  •  ${row['id']}', overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
    ));
  }
}
