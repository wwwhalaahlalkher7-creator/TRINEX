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
  final Set<String> _sending = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.api.get('/admin/notifications?limit=100');
      final raw = response['data'];
      final rows = raw is List
          ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      if (mounted) { setState(() => _items = rows); }
    } catch (e) {
      if (mounted) { setState(() => _error = e.toString()); }
    } finally {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _editDraft(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'draft') { return; }
    final title = TextEditingController(text: item['title']?.toString() ?? '');
    final body = TextEditingController(text: item['body']?.toString() ?? '');
    final type = TextEditingController(text: item['type']?.toString() ?? 'general');
    final department = TextEditingController(text: item['target_department_id']?.toString() ?? '');
    final semester = TextEditingController(text: item['target_semester_id']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (context) => AlertDialog(
      title: const Text('تحرير مسودة الإشعار'),
      content: SizedBox(width: 520, child: Form(key: formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: title, decoration: const InputDecoration(labelText: 'العنوان'), validator: (v) => v == null || v.trim().isEmpty ? 'العنوان مطلوب' : null),
        const SizedBox(height: 10), TextFormField(controller: body, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'نص الإشعار'), validator: (v) => v == null || v.trim().isEmpty ? 'النص مطلوب' : null),
        const SizedBox(height: 10), TextFormField(controller: type, decoration: const InputDecoration(labelText: 'النوع / فئة الإشعار')),
        const SizedBox(height: 10), TextFormField(controller: department, decoration: const InputDecoration(labelText: 'معرّف القسم المستهدف (اتركه فارغًا للكل)')),
        const SizedBox(height: 10), TextFormField(controller: semester, decoration: const InputDecoration(labelText: 'معرّف الفصل المستهدف (اتركه فارغًا للكل)')),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')), FilledButton(onPressed: () { if (formKey.currentState!.validate()) { Navigator.pop(context, {'title': title.text.trim(), 'body': body.text.trim(), 'type': type.text.trim().isEmpty ? 'general' : type.text.trim(), 'target_department_id': department.text.trim().isEmpty ? null : department.text.trim(), 'target_semester_id': semester.text.trim().isEmpty ? null : semester.text.trim()}); } }, child: const Text('حفظ المسودة'))],
    ));
    title.dispose(); body.dispose(); type.dispose(); department.dispose(); semester.dispose();
    if (result == null || !mounted) { return; }
    try {
      await widget.api.patch('/admin/announcements/$id', body: result);
      if (!mounted) { return; }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ المسودة. لم يتم إرسالها.')));
      await _load();
    } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ المسودة: $e'))); } }
  }

  Future<void> _approveDraft(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'draft') { return; }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('اعتماد المسودة؟'),
      content: Text('سيتم نشر «${item['title'] ?? 'الإشعار'}» لتصبح جاهزة للإرسال. الاعتماد لا يعني إرسالها تلقائيًا.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('اعتماد ونشر'))],
    ));
    if (confirmed != true || !mounted) { return; }
    try {
      await widget.api.patch('/admin/announcements/$id', body: {'status': 'published'});
      if (!mounted) { return; }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اعتماد الإشعار ونشره. لم يُرسل تلقائيًا.')));
      await _load();
    } catch (e) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر اعتماد المسودة: $e'))); } }
  }

  Future<void> _send(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'published') { return; }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال الإشعار؟'),
        content: Text('سيُجهّز «${item['title'] ?? 'الإعلان'}» للإرسال إلى الطلاب النشطين المطابقين للقسم والمستوى المحددين. الإرسال المتكرر آمن ولا ينشئ استهدافات مكررة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأكيد الإرسال')),
        ],
      ),
    );
    if (confirmed != true || !mounted) { return; }
    setState(() => _sending.add(id));
    try {
      final result = await widget.api.post('/admin/notifications/send', body: {'announcementId': id});
      final data = result['data'] is Map ? Map<String, dynamic>.from(result['data'] as Map) : result;
      if (!mounted) { return; }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تجهيز الإشعار. عدد المستهدفين: ${data['targets'] ?? '—'}، الجدد: ${data['newTargets'] ?? '—'}.')));
      await _load();
    } catch (e) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الإشعار: $e'))); }
    } finally {
      if (mounted) { setState(() => _sending.remove(id)); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
        children: [
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('الإشعارات', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('إدارة مسودات الإشعارات المرتبطة بالمحتوى واعتمادها قبل إرسال الإعلانات المنشورة إلى الطلاب.', style: theme.textTheme.bodyMedium),
            ])),
            IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Row(children: [
            Icon(Icons.info_outline), SizedBox(width: 12), Expanded(child: Text('هذه العملية تضيف المستهدفين وقوائم التسليم داخل النظام. إرسال إشعارات Push فعليًا يعتمد على عامل التسليم وإعدادات مزود الإشعارات على الخادم.')),
          ]))),
          const SizedBox(height: 12),
          if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(36), child: Center(child: CircularProgressIndicator())),
          if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('تعذر تحميل الإشعارات: $_error'))),
          if (!_loading && _error == null && _items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('لا توجد إعلانات في سجل الإشعارات بعد. أنشئ إعلانًا من قسم المحتوى ثم انشره.'))),
          for (final item in _items) ...[
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.campaign_outlined, size: 24), const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item['title']?.toString() ?? 'إعلان بلا عنوان', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text('النوع: ${item['type'] ?? 'عام'}  •  الحالة: ${item['status'] ?? 'غير محددة'}'),
                  const SizedBox(height: 5),
                  Text('المستهدفون: ${item['targets'] ?? 0}  •  قرؤوا: ${item['reads'] ?? 0}'),
                  if ((item['publish_at'] ?? '').toString().isNotEmpty) Text('موعد النشر: ${item['publish_at']}'),
                ])),
              ]),
              const SizedBox(height: 12),
              Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
                if (item['status'] == 'draft') ...[
                  OutlinedButton.icon(onPressed: () => _editDraft(item), icon: const Icon(Icons.edit_outlined), label: const Text('تحرير المسودة')),
                  FilledButton.tonalIcon(onPressed: () => _approveDraft(item), icon: const Icon(Icons.fact_check_outlined), label: const Text('اعتماد ونشر')),
                ],
                FilledButton.tonalIcon(
                  onPressed: item['status'] == 'published' && !_sending.contains(item['id']?.toString()) ? () => _send(item) : null,
                  icon: _sending.contains(item['id']?.toString()) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
                  label: const Text('إرسال / تحديث الاستهداف'),
                ),
              ]),
            ]))),
          ],
        ],
      ),
    );
  }
}
