import 'package:flutter/material.dart';

import '../../api_service.dart';

class EinoMonitorPage extends StatefulWidget {
  const EinoMonitorPage({super.key, required this.api});
  final ApiService api;

  @override
  State<EinoMonitorPage> createState() => _EinoMonitorPageState();
}

class _EinoMonitorPageState extends State<EinoMonitorPage> {
  int _hours = 24;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _data = {};

  List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
      : <Map<String, dynamic>>[];

  int _int(dynamic value) => int.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await widget.api.getEinoMonitor(hours: _hours, limit: 100);
      final nested = response['data'];
      final data = nested is Map ? Map<String, dynamic>.from(nested) : response;
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() { super.initState(); _load(); }

  @override
  Widget build(BuildContext context) {
    final summary = _rows(_data['summary']);
    final providers = _rows(_data['providers']);
    final tasks = _rows(_data['tasks']);
    final recent = _rows(_data['recent']);
    final total = summary.fold<int>(0, (sum, row) => sum + _int(row['count']));
    final success = summary.where((row) => row['status'] == 'success')
        .fold<int>(0, (sum, row) => sum + _int(row['count']));
    final units = summary.fold<int>(0, (sum, row) => sum + _int(row['costUnits']));
    final latencyWeighted = summary.fold<int>(0, (sum, row) =>
        sum + _int(row['count']) * _int(row['avgLatencyMs']));
    final privacy = _data['privacy'] is Map ? Map<String, dynamic>.from(_data['privacy'] as Map) : <String, dynamic>{};

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مراقبة إينو', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
              SizedBox(height: 5),
              Text('طلبات التشغيل والمزودات والحصص والأخطاء دون عرض محتوى محادثات الطلاب.'),
            ])),
            IconButton(tooltip: 'تحديث', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          ]),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('الفترة الزمنية', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 6, label: Text('6 ساعات')),
                ButtonSegment(value: 24, label: Text('24 ساعة')),
                ButtonSegment(value: 72, label: Text('3 أيام')),
                ButtonSegment(value: 168, label: Text('7 أيام')),
              ],
              selected: {_hours},
              onSelectionChanged: _loading ? null : (values) { setState(() => _hours = values.first); _load(); },
            ),
          ]))),
          if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تعذّر تحميل بيانات المراقبة: $_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Align(alignment: AlignmentDirectional.centerEnd, child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))),
          ]))),
          if (_loading && _data.isEmpty) const Padding(padding: EdgeInsets.all(35), child: Center(child: CircularProgressIndicator())),
          if (_data.isNotEmpty) ...[
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 850 ? 4 : constraints.maxWidth > 500 ? 2 : 1;
              final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
              final stats = <(String, String, IconData)>[
                ('الطلبات', total.toString(), Icons.send_outlined),
                ('نسبة النجاح', total == 0 ? '—' : '${(success * 100 / total).round()}%', Icons.check_circle_outline),
                ('متوسط الاستجابة', total == 0 ? '—' : '${(latencyWeighted / total).round()} ms', Icons.timer_outlined),
                ('الوحدات المستهلكة', units.toString(), Icons.speed_outlined),
              ];
              return Wrap(spacing: 10, runSpacing: 10, children: stats.map((item) => SizedBox(width: width, child: Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(item.$3), const SizedBox(height: 10), Text(item.$1), const SizedBox(height: 5), Text(item.$2, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))]))))).toList());
            }),
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('حدود الخصوصية', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('الاحتفاظ بالسجل: ${privacy['retentionDays'] ?? 14} يومًا. لا تُعرض مطالبات الطلاب أو الردود أو أرقامهم أو عناوين IP أو محتويات الملفات.'),
            ]))),
            _dataTable('المزودات', ['المزود', 'الطلبات', 'نجاح', 'فشل', 'متوسط الزمن', 'الوحدات'], providers, ['provider', 'requests', 'successes', 'failures', 'avgLatencyMs', 'costUnits'], suffixes: const {4: ' ms'}),
            _dataTable('أنواع المهام', ['المهمة', 'الطلبات', 'نجاح', 'متوسط الزمن', 'الوحدات'], tasks, ['task', 'requests', 'successes', 'avgLatencyMs', 'costUnits'], suffixes: const {3: ' ms'}),
            _dataTable('آخر الطلبات', ['الوقت', 'القدرة', 'المهمة', 'الحالة', 'المزود', 'النموذج', 'الزمن', 'الوحدات', 'Fallback'], recent, ['occurredAt', 'capability', 'task', 'status', 'provider', 'model', 'latencyMs', 'costUnits', 'fallback'], suffixes: const {6: ' ms'}),
          ],
        ],
      ),
    );
  }

  Widget _dataTable(String title, List<String> headers, List<Map<String, dynamic>> rows, List<String> keys, {Map<int, String> suffixes = const {}}) {
    return Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      if (rows.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد بيانات ضمن الفترة المحددة.'))
      else SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
        columns: headers.map((header) => DataColumn(label: Text(header))).toList(),
        rows: rows.map((row) => DataRow(cells: List.generate(keys.length, (index) {
          final value = row[keys[index]];
          final text = value == null ? '—' : value is bool ? (value ? 'نعم' : 'لا') : value.toString();
          return DataCell(SelectableText('$text${suffixes[index] ?? ''}'));
        }))).toList(),
      )),
    ])));
  }
}
