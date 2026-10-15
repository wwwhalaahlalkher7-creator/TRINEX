import 'package:flutter/material.dart';
import '../../api_service.dart';

class ChatReportsPage extends StatefulWidget {
  const ChatReportsPage({super.key, required this.api});
  final ApiService api;
  @override
  State<ChatReportsPage> createState() => _ChatReportsPageState();
}

class _ChatReportsPageState extends State<ChatReportsPage> {
  String _status = 'open';
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  final Set<String> _busy = {};
  @override
  void initState() { super.initState(); _load(); }
  List<Map<String, dynamic>> _rows(dynamic value) => value is List ? value.whereType<Map>().map((e) => Map<String,dynamic>.from(e)).toList() : [];
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try { final r = await widget.api.get('/admin/moderation/chat-reports?status=$_status&limit=100'); if (mounted) { setState(() => _items = _rows(r['data'])); } }
    catch(e) { if(mounted) { setState(() => _error = e.toString()); } }
    finally { if(mounted) { setState(() => _loading = false); } }
  }
  Future<void> _review(Map<String,dynamic> item, String status, String? messageStatus) async {
    final id = item['id']?.toString() ?? ''; if(id.isEmpty) { return; }
    setState(() => _busy.add(id));
    try { await widget.api.patch('/admin/moderation/chat-reports/$id', body: {'status':status, if(messageStatus != null) 'messageStatus':messageStatus});
      if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث البلاغ وحالة الرسالة.'))); await _load();
    } catch(e) { if(mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحديث البلاغ: $e'))); } }
    finally { if(mounted) { setState(() => _busy.remove(id)); } }
  }
  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(20), children: [
    Row(children:[Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,children:[Text('بلاغات الدردشة',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:5),const Text('مراجعة البلاغات على رسائل الدردشة العامة وحسم البلاغ مع الإجراء المطلوب للرسالة.') ])),IconButton(onPressed:_loading?null:_load,icon:const Icon(Icons.refresh))]),
    const SizedBox(height:12), SegmentedButton<String>(segments:const[ButtonSegment(value:'open',label:Text('مفتوحة')),ButtonSegment(value:'reviewed',label:Text('تمت مراجعتها')),ButtonSegment(value:'dismissed',label:Text('مرفوضة'))],selected:{_status},onSelectionChanged:(s){setState(()=>_status=s.first);_load();}),
    if(_loading&&_items.isEmpty)const Padding(padding:EdgeInsets.all(30),child:Center(child:CircularProgressIndicator())),
    if(_error!=null)Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('تعذر تحميل البلاغات: $_error'),TextButton(onPressed:_load,child:const Text('إعادة المحاولة'))]))),
    if(!_loading&&_error==null&&_items.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(22),child:Text('لا توجد بلاغات بهذه الحالة.'))),
    for(final item in _items) Card(margin:const EdgeInsets.only(top:10),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('بلاغ: ${item['reason']??'سبب غير محدد'}',style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:6),
      Text('الرسالة: ${item['messageBody']??'غير متاحة'}'),Text('صاحب الرسالة: ${item['authorName']??'غير معروف'} • المبلّغ: ${item['reporterName']??'غير معروف'}'),
      if((item['details']??'').toString().isNotEmpty)Text('التفاصيل: ${item['details']}'),Text('التاريخ: ${item['createdAt']??'—'}'),
      if(_status=='open')Wrap(spacing:8,runSpacing:8,children:[OutlinedButton(onPressed:_busy.contains(item['id']?.toString())?null:()=>_review(item,'dismissed',null),child:const Text('رفض البلاغ')),FilledButton.tonal(onPressed:_busy.contains(item['id']?.toString())?null:()=>_review(item,'reviewed','visible'),child:const Text('مراجعة والإبقاء')),FilledButton(onPressed:_busy.contains(item['id']?.toString())?null:()=>_review(item,'reviewed','hidden'),child:const Text('إخفاء الرسالة'))]),
    ]))),
  ]));
}
