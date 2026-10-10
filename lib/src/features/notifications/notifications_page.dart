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
      if (mounted) setState(() => _items = rows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || item['status'] != 'published') return;
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
    if (confirmed != true || !mounted) return;
    setState(() => _sending.add(id));
    try {
      final result = await widget.api.post('/admin/notifications/send', body: {'announcementId': id});
      final data = result['data'] is Map ? Map<String, dynamic>.from(result['data'] as Map) : result;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تجهيز الإشعار. عدد المستهدفين: ${data['targets'] ?? '—'}، الجدد: ${data['newTargets'] ?? '—'}.')));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال الإشعار: $e')));
    } finally {
      if (mounted) setState(() => _sending.remove(id));
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
              Text('إدارة إرسال الإعلانات المنشورة إلى الطلاب عبر نظام الاستهداف الحالي.', style: theme.textTheme.bodyMedium),
            ])),
            IconButton(onPressed: _loading ? null : _load, tooltip: 'تحديث', icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            const Icon(Icons.info_outline), const SizedBox(width: 12), Expanded(child: Text('هذه العملية تضيف المستهدفين وقوائم التسليم داخل النظام. إرسال إشعارات Push فعليًا يعتمد على عامل التسليم وإعدادات مزود الإشعارات على الخادم.')),
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
              Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.tonalIcon(
                onPressed: item['status'] == 'published' && !_sending.contains(item['id']?.toString()) ? () => _send(item) : null,
                icon: _sending.contains(item['id']?.toString()) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
                label: const Text('إرسال / تحديث الاستهداف'),
              )),
            ]))),
          ],
        ],
      ),
    );
  }
}
