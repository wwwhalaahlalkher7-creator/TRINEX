import 'package:flutter/material.dart';
import '../../api_service.dart';

class FeedbackReportsPage extends StatefulWidget {
  const FeedbackReportsPage({super.key, required this.api});
  final ApiService api;

  @override
  State<FeedbackReportsPage> createState() => _FeedbackReportsPageState();
}

class _FeedbackReportsPageState extends State<FeedbackReportsPage> {
  String _status = 'open';
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.api.get('/admin/moderation/feedback?status=$_status&limit=100');
      if (mounted) setState(() => _items = _rows(response['data']));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _category(String value) => switch (value) {
    'suggestion' => 'مقترح أو تحسين',
    'bug' => 'مشكلة تقنية',
    'content' => 'مشكلة في مادة أو محتوى',
    _ => 'أخرى',
  };

  Future<void> _review(Map<String, dynamic> item, String status) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final notesController = TextEditingController(text: item['adminNotes']?.toString() ?? '');
    final notes = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(switch (status) {
          'in_review' => 'بدء مراجعة البلاغ',
          'resolved' => 'إنهاء البلاغ',
          'dismissed' => 'رفض البلاغ',
          _ => 'إعادة فتح البلاغ',
        }),
        content: TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'ملاحظات الإدارة (اختيارية)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, notesController.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    notesController.dispose();
    if (notes == null) return;

    setState(() => _busy.add(id));
    try {
      await widget.api.patch('/admin/moderation/feedback/$id', body: {
        'status': status,
        if (notes.trim().isNotEmpty) 'adminNotes': notes.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث حالة المقترح أو البلاغ.')));
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث البلاغ: $error')));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: _load,
    child: ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('المقترحات والبلاغات', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          const Text('استقبل اقتراحات الطلاب ومشكلاتهم التقنية والأكاديمية، ثم تابع حالتها وسجّل ملاحظات الإدارة.'),
        ])),
        IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final option in const [
          ('open', 'جديدة'),
          ('in_review', 'قيد المراجعة'),
          ('resolved', 'منجزة'),
          ('dismissed', 'مرفوضة'),
        ])
          FilterChip(
            label: Text(option.$2),
            selected: _status == option.$1,
            onSelected: (selected) {
              if (!selected || _status == option.$1) return;
              setState(() => _status = option.$1);
              _load();
            },
          ),
      ]),
      if (_loading && _items.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
      if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('تعذر تحميل المقترحات والبلاغات: $_error'),
        TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      ]))),
      if (!_loading && _error == null && _items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('لا توجد رسائل بهذه الحالة.'))),
      for (final item in _items) Card(
        margin: const EdgeInsets.only(top: 10),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Chip(label: Text(_category('${item['category'] ?? 'other'}'))),
            Text('${item['createdAt'] ?? '—'}', style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 4),
          Text('${item['title'] ?? 'بدون عنوان'}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          SelectableText('${item['details'] ?? ''}'),
          const SizedBox(height: 8),
          Text('الطالب: ${item['studentName'] ?? 'غير معروف'} • الرقم الجامعي: ${item['studentNumber'] ?? 'غير متاح'}'),
          if ((item['screen'] ?? '').toString().isNotEmpty) Text('المصدر: ${item['screen']}'),
          if ((item['adminNotes'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('ملاحظات الإدارة: ${item['adminNotes']}'),
          ),
          if (_status == 'open' || _status == 'in_review') Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: _busy.contains(item['id']?.toString()) ? null : () => _review(item, 'dismissed'), child: const Text('رفض')),
            FilledButton.tonal(onPressed: _busy.contains(item['id']?.toString()) ? null : () => _review(item, 'in_review'), child: const Text('قيد المراجعة')),
            FilledButton(onPressed: _busy.contains(item['id']?.toString()) ? null : () => _review(item, 'resolved'), child: const Text('تمت المعالجة')),
          ]),
          if (_status == 'resolved' || _status == 'dismissed') TextButton(
            onPressed: _busy.contains(item['id']?.toString()) ? null : () => _review(item, 'open'),
            child: const Text('إعادة فتح'),
          ),
        ])),
      ),
    ]),
  );
}
