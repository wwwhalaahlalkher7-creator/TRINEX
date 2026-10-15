import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'package:flutter/material.dart';

import '../../api_service.dart';

class ScannerImportDialog extends StatefulWidget {
  const ScannerImportDialog({super.key, required this.api, required this.type,
    required this.departments, required this.semesters, this.subjects = const []});
  final ApiService api;
  final String type; // students | schedule
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> semesters;
  final List<Map<String, dynamic>> subjects;

  @override
  State<ScannerImportDialog> createState() => _ScannerImportDialogState();
}

class _ScannerImportDialogState extends State<ScannerImportDialog> {
  String? _departmentId;
  String? _semesterId;
  String? _operationId;
  String? _expiresAt;
  String? _filename;
  String? _error;
  bool _working = false;
  bool _review = false;
  int _countdown = 10;
  Timer? _countdownTimer;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _existingSchedules = [];
  final List<String> _notes = [];

  bool get _students => widget.type == 'students';
  @override
  void dispose() { _countdownTimer?.cancel(); super.dispose(); }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 10);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _countdown = (_countdown - 1).clamp(0, 10); });
      if (_countdown == 0) { timer.cancel(); }
    });
  }
  List<Map<String, dynamic>> get _availableSubjects => widget.subjects.where((s) =>
    '${s['department_id']}' == '$_departmentId' && '${s['semester_id']}' == '$_semesterId' && (s['active'] == 1 || s['active'] == true || s['active'] == null)).toList();

  String _name(Map<String, dynamic> row) => (row['name_ar'] ?? row['name'] ?? row['title'] ?? row['id'] ?? '').toString();
  String _firstName(Iterable<Map<String, dynamic>> rows) => rows.isEmpty ? '—' : _name(rows.first);
  String _digits(String value) {
    const ar = '٠١٢٣٤٥٦٧٨٩'; const fa = '۰۱۲۳۴۵۶۷۸۹';
    return value.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${ar.indexOf(m[0]!)}')
      .replaceAllMapped(RegExp('[۰-۹]'), (m) => '${fa.indexOf(m[0]!)}');
  }
  String _time(dynamic value) {
    final raw = _digits('${value ?? ''}').trim();
    final m = RegExp(r'^(\d{1,2})(?::(\d{1,2}))?$').firstMatch(raw);
    if (m == null) { return raw; }
    final h = int.tryParse(m.group(1)!) ?? -1; final min = int.tryParse(m.group(2) ?? '0') ?? -1;
    if (h < 0 || h > 23 || min < 0 || min > 59) { return raw; }
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
  String _header(String value) => _digits(value).toLowerCase().replaceAll(RegExp(r'[\s_\-ـ]+'), '').replaceAll(RegExp(r'[أإآ]'), 'ا').replaceAll('ة','ه');

  Future<void> _pickAndScan() async {
    if (_departmentId == null || _semesterId == null) { setState(() => _error = 'اختر القسم والفصل الدراسي قبل بدء المسح.'); return; }
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'pdf', 'png', 'jpg', 'jpeg', 'webp', 'tif', 'tiff'], withData: true, allowMultiple: false);
    if (picked == null || picked.files.isEmpty) { return; }
    final file = picked.files.single;
    if (file.size <= 0) { setState(() => _error = 'الملف فارغ. اختر ملفًا يحتوي على بيانات ثم أعد المحاولة.'); return; }
    if (file.size > 100 * 1024 * 1024) { setState(() => _error = 'الملف كبير جدًا. اختر ملفًا أصغر ثم أعد المحاولة.'); return; }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) { setState(() => _error = 'تعذر قراءة الملف من الجهاز. أعد اختياره وحاول مجددًا.'); return; }
    setState(() { _working = true; _error = null; _filename = file.name; _notes.clear(); });
    try {
      final created = await widget.api.post('/admin/imports', body: {
        'type': widget.type, 'departmentId': _departmentId, 'semesterId': _semesterId, 'records': <dynamic>[]
      });
      _operationId = created['id']?.toString();
      _expiresAt = created['expiresAt']?.toString();
      if (!_students) {
        final existing = await widget.api.get('/admin/schedule?limit=100');
        final rawExisting = existing['data'];
        _existingSchedules = rawExisting is List ? rawExisting.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).where((r) => '${r['department_id']}' == _departmentId && '${r['semester_id']}' == _semesterId && (r['active'] == 1 || r['active'] == true || r['active'] == null)).toList() : [];
      }
      if (_operationId == null || _operationId!.isEmpty) { throw const ApiServiceException('لم يتم إنشاء عملية استيراد صالحة.'); }
      final ext = file.extension?.toLowerCase() ?? '';
      List<Map<String, dynamic>> parsed;
      if (ext == 'csv') {
        parsed = _parseGrid(CsvToListConverter(shouldParseNumbers: false).convert(utf8.decode(bytes, allowMalformed: true)));
      } else if (ext == 'xlsx') {
        final workbook = Excel.decodeBytes(bytes);
        if (workbook.tables.isEmpty || workbook.tables.values.every((sheet) => sheet.rows.isEmpty)) {
          throw const ApiServiceException('ملف Excel فارغ أو لا يحتوي على أوراق قابلة للقراءة.');
        }
        final sheet = workbook.tables.values.firstWhere((sheet) => sheet.rows.isNotEmpty);
        parsed = _parseGrid(sheet.rows.map((r) => r.map((c) => c?.value?.toString() ?? '').toList()).toList());
      } else if (['pdf','png','jpg','jpeg','webp','tif','tiff'].contains(ext)) {
        final mime = ext == 'pdf' ? 'application/pdf' : (ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : (ext == 'tif' || ext == 'tiff' ? 'image/tiff' : 'image/jpeg')));
        final compressed = await _prepareOcrUpload(bytes, file.name, mime);
        final result = await widget.api.uploadImportOcr(bytes: compressed.bytes, filename: compressed.filename, contentType: compressed.contentType);
        final text = result['text']?.toString() ?? '';
        parsed = _parseOcrText(text);
        if (parsed.isEmpty) {
          _notes.add('تم استخراج النص، لكن لم يمكن تحويله تلقائيًا إلى سجلات منظمة. أضف السجلات يدويًا في المراجعة، وتحقق من كل حقل.');
          _notes.add('النص المستخرج: ${text.length > 2500 ? '${text.substring(0, 2500)}…' : text}');
        }
      } else {
        throw const ApiServiceException('نوع الملف غير مدعوم. استخدم CSV أو Excel أو PDF أو صورة واضحة.');
      }
      if (parsed.length > 2000) { throw const ApiServiceException('اكتُشف أكثر من 2000 سجل. قسّم الملف إلى ملفات أصغر ثم أعد المحاولة.'); }
      if (parsed.isEmpty) {
        if (_students) { parsed = [_studentRow(), _studentRow()]; }
        else parsed = [_scheduleRow(), _scheduleRow()];
        _notes.add('لم يتم التعرف على سجلات كاملة؛ الحقول الفارغة ظاهرة للمراجعة. أكملها أو احذف الصفوف غير المطلوبة.');
      }
      if (!_students && _availableSubjects.isEmpty) { _notes.add('لا توجد مواد نشطة لهذا القسم والفصل الدراسي. تحقق من النطاق أو أضف المواد أولًا.'); }
      await widget.api.patch('/admin/imports/$_operationId', body: {'records': parsed});
      if (!mounted) { return; }
      setState(() { _rows = parsed; _review = true; _countdown = 10; });
      _countdownTimer?.cancel();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) { timer.cancel(); return; }
        setState(() { _countdown = (_countdown - 1).clamp(0, 10); });
        if (_countdown == 0) { timer.cancel(); }
      });
    } catch (e) {
      if (_operationId != null && !_review) { try { await widget.api.delete('/admin/imports/$_operationId'); } catch (_) {} _operationId = null; }
      if (mounted) { setState(() => _error = _friendlyError(e)); }
    } finally {
      // Source bytes are intentionally not retained in the review state.
      if (mounted) { setState(() => _working = false); }
    }
  }

  Future<_PreparedOcrUpload> _prepareOcrUpload(Uint8List source, String filename, String mime) async {
    const maxBytes = 1024 * 1024 - 1024; // leave a small multipart/provider margin
    final lower = filename.toLowerCase();
    Uint8List working = source;
    String outputName = filename;
    String outputMime = mime;

    if (mime == 'application/pdf' || lower.endsWith('.pdf')) {
      PdfDocument? document;
      PdfPage? page;
      try {
        document = await PdfDocument.openData(source);
        if (document.pagesCount > 1) {
          throw const ApiServiceException('IMPORT_MULTIPAGE_FILE: يجب أن يحتوي PDF على صفحة واحدة فقط.');
        }
        if (document.pagesCount < 1) { throw const ApiServiceException('ملف PDF لا يحتوي على صفحات قابلة للقراءة.'); }
        page = await document.getPage(1);
        final scale = (1800 / page.width).clamp(1.0, 2.0);
        final rendered = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: PdfPageImageFormat.jpeg,
          quality: 82,
        );
        if (rendered == null || rendered.bytes.isEmpty) {
          throw const ApiServiceException('تعذر ضغط صفحة PDF. جرّب صورة JPG واضحة أو أدخل البيانات يدويًا.');
        }
        working = rendered.bytes;
        outputName = '${filename.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')}.jpg';
        outputMime = 'image/jpeg';
      } finally {
        await page?.close();
        await document?.close();
      }
    }

    if (working.length <= maxBytes) { return _PreparedOcrUpload(working, outputName, outputMime); }

    final decoded = img.decodeImage(working);
    if (decoded == null) {
      throw const ApiServiceException('تعذر قراءة الصورة أو ضغطها. جرّب صورة JPG أو PNG واضحة.');
    }
    img.Image current = decoded;
    // Try high quality first. If the image is still too large, reduce its
    // longest edge gradually even when the source dimensions are below 900px.
    // This avoids repeatedly encoding the same small image and gives the
    // algorithm a predictable lower bound before we reject unreadable output.
    final outputFilename = '${outputName.replaceAll(RegExp(r'\.[^.]+$', caseSensitive: false), '')}.jpg';
    const qualities = <int>[90, 86, 82, 78, 74, 70, 66, 62];
    for (var pass = 0; pass < 7; pass++) {
      for (final quality in qualities) {
        final encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
        if (encoded.length <= maxBytes) {
          return _PreparedOcrUpload(encoded, outputFilename, 'image/jpeg');
        }
      }
      final longestEdge = current.width > current.height ? current.width : current.height;
      if (longestEdge <= 1000) { break; }
      final targetEdge = (longestEdge * 0.82).round().clamp(1000, longestEdge - 1);
      final factor = targetEdge / longestEdge;
      final resized = img.copyResize(current,
        width: (current.width * factor).round().clamp(1, current.width),
        height: (current.height * factor).round().clamp(1, current.height),
        interpolation: img.Interpolation.average);
      current = resized;
    }
    // Final conservative attempt at the readability floor; do not degrade
    // indefinitely just to satisfy the provider size limit.
    for (final quality in <int>[72, 66, 60, 54]) {
      final encoded = Uint8List.fromList(img.encodeJpg(current, quality: quality));
      if (encoded.length <= maxBytes) { return _PreparedOcrUpload(encoded, outputFilename, 'image/jpeg'); }
    }
    throw const ApiServiceException('IMPORT_FILE_OVER_PROVIDER_LIMIT: تعذر تجهيز الملف لقراءة النص مع الحفاظ على وضوحه.');
  }

  String _friendlyError(Object error) {
    final value = error.toString();
    if (value.contains('IMPORT_MULTIPAGE_FILE')) { return 'يحتوي المستند على أكثر من صفحة. أدرج صفحة واحدة فقط ثم أعد المسح؛ يمكن أن تحتوي الصفحة الواحدة على أسطر كثيرة.'; }
    if (value.contains('IMPORT_OCR_NOT_CONFIGURED') || value.contains('IMPORT_OCR_AUTH_FAILED')) { return 'تعذّر الاتصال بخدمة قراءة النص. أبلغ مسؤول النظام.'; }
    if (value.contains('IMPORT_FILE_OVER_PROVIDER_LIMIT') || value.contains('IMPORT_OCR_PROVIDER_SIZE_LIMIT')) { return 'تعذّر إرسال الملف إلى خدمة قراءة النص. جرّب صورة أصغر مع الحفاظ على وضوح الجدول.'; }
    if (value.contains('IMPORT_OCR_QUOTA_EXCEEDED')) { return 'خدمة قراءة النص وصلت إلى حد الاستخدام الحالي. جرّب لاحقًا أو أدخل البيانات يدويًا.'; }
    if (value.contains('IMPORT_OCR_TIMEOUT')) { return 'استغرق استخراج النص وقتًا طويلًا. جرّب مرة أخرى أو أدخل البيانات يدويًا.'; }
    if (value.contains('IMPORT_OCR_UNAVAILABLE')) { return 'خدمة قراءة النص غير متاحة مؤقتًا. جرّب مرة أخرى بعد قليل.'; }
    if (value.contains('IMPORT_OCR_PROVIDER_REJECTED')) { return 'تعذّر على خدمة قراءة النص معالجة الملف. جرّب صورة JPG واضحة أو أدخل البيانات يدويًا.'; }
    if (value.contains('IMPORT_OCR_FAILED')) { return 'تعذّر استخراج النص. جرّب مرة أخرى، وإذا تكرر الخطأ فأبلغ مسؤول النظام.'; }
    if (value.contains('IMPORT_FILE_TYPE_UNSUPPORTED')) { return 'نوع الملف غير مدعوم. اختر ملف CSV أو Excel أو PDF أو صورة.'; }
    if (value.contains('IMPORT_FILE_TOO_LARGE')) { return 'تعذر معالجة الملف بسبب حجمه. جرّب نسخة أصغر.'; }
    if (value.contains('IMPORT_OCR_EMPTY')) { return 'لم يتمكن الماسح من قراءة نص واضح. جرّب صورة أوضح.'; }
    return value.replaceFirst('Exception: ', '');
  }

  Map<String, dynamic> _studentRow() => {'studentNumber': '', 'fullName': '', 'email': ''};
  Map<String, dynamic> _scheduleRow() => {'subjectId': '', 'subjectName': '', 'dayOfWeek': 0, 'startTime': '', 'endTime': '', 'room': '', 'lecturer': '', 'existingId': ''};

  List<Map<String, dynamic>> _parseGrid(List<List<dynamic>> grid) {
    final nonEmpty = grid.map((r) => r.map((c) => _digits('$c').trim()).toList()).where((r) => r.any((c) => c.isNotEmpty)).toList();
    if (nonEmpty.isEmpty) { throw const ApiServiceException('لم يعثر الملف على صفوف تحتوي بيانات.'); }
    final headers = nonEmpty.first.map(_header).toList();
    int find(List<String> names) => headers.indexWhere((h) => names.any((n) => h == _header(n) || h.contains(_header(n))));
    if (_students) {
      final n = find(['الرقم الجامعي','رقم الطالب','studentnumber','studentid','idnumber','number']);
      final f = find(['اسم الطالب','الاسم الكامل','الاسم','fullname','studentname','name']);
      final e = find(['البريد الالكتروني','البريد','email','emailaddress']);
      final hasHeader = n >= 0 || f >= 0 || e >= 0;
      final data = hasHeader ? nonEmpty.skip(1) : nonEmpty;
      final numberIndex = n >= 0 ? n : 0; final nameIndex = f >= 0 ? f : 1;
      return data.map((r) => {'studentNumber': _cell(r, numberIndex), 'fullName': _cell(r, nameIndex), 'email': e >= 0 ? _cell(r,e) : _cell(r,2)}).toList();
    }
    final sub = find(['المادة','اسم المادة','المقرر','subject','subjectname','course']);
    final day = find(['اليوم','day','dayofweek']);
    final start = find(['بداية','وقت البداية','من','start','starttime']);
    final end = find(['نهاية','وقت النهاية','الى','إلى','end','endtime']);
    if (sub < 0 && day < 0 && start < 0 && end < 0) {
      _notes.add('لم تُعرف عناوين أعمدة الجدول تلقائيًا. راجع الحقول يدويًا وأكمل اليوم والمادة والأوقات.');
      return nonEmpty.skip(1).map((r) => _scheduleRow()).toList();
    }
    final data = nonEmpty.skip(1);
    return data.map((r) {
      final subjectName = _cell(r, sub); final matched = _availableSubjects.where((s) => _header(_name(s)) == _header(subjectName) || _header(s['name_en'] ?? '') == _header(subjectName)).toList();
      return {'subjectId': matched.length == 1 ? '${matched.first['id']}' : '', 'subjectName': subjectName,
        'dayOfWeek': _dayNumber(_cell(r, day)), 'startTime': _time(_cell(r, start)), 'endTime': _time(_cell(r, end)), 'room': '', 'lecturer': ''};
    }).toList();
  }

  String _cell(List<String> row, int i) => i >= 0 && i < row.length ? row[i].trim() : '';
  String _dayName(dynamic value) { final day = int.tryParse('$value') ?? 0; return const ['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'][day.clamp(0,6).toInt()]; }
  int _dayNumber(String value) {
    final v = _header(value);
    const names = {'الاحد':0,'sunday':0,'الاثنين':1,'monday':1,'الثلاثاء':2,'tuesday':2,'الاربعاء':3,'wednesday':3,'الخميس':4,'thursday':4,'الجمعة':5,'friday':5,'السبت':6,'saturday':6};
    return int.tryParse(v) != null ? int.parse(v).clamp(0,6).toInt() : (names[v] ?? 0);
  }

  List<Map<String, dynamic>> _parseOcrText(String text) {
    final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final tableRows = <List<String>>[];
    for (final line in lines) {
      if (!line.contains('|')) { continue; }
      final cells = line.split('|').map((c) => c.trim()).toList();
      if (cells.isNotEmpty && cells.first.isEmpty) { cells.removeAt(0); }
      if (cells.isNotEmpty && cells.last.isEmpty) { cells.removeLast(); }
      if (cells.isEmpty || cells.every((c) => c.isEmpty || RegExp(r'^:?-{2,}:?$').hasMatch(c))) { continue; }
      tableRows.add(cells);
    }
    if (tableRows.isNotEmpty) { return _parseGrid(tableRows); }
    // A plain OCR transcript is intentionally not guessed into records. Return
    // empty so the reviewer gets editable blank rows and an explicit warning.
    return [];
  }

  void _addRow() { setState(() { _error = null; _rows.add(_students ? _studentRow() : _scheduleRow()); }); _startCountdown(); }
  void _removeRow(int index) { setState(() { _error = null; _rows.removeAt(index); }); _startCountdown(); }
  void _change(int i, String key, dynamic value) { setState(() { _error = null; _rows[i][key] = value; }); _startCountdown(); }
  Future<void> _closeDialog() async {
    final id = _operationId;
    if (id != null) { try { await widget.api.delete('/admin/imports/$id'); } catch (_) {} }
    if (mounted) { Navigator.of(context).pop(false); }
  }

  Future<void> _commit() async {
    if (_operationId == null) { return; }
    setState(() { _working = true; _error = null; });
    try {
      final validation = await widget.api.post('/admin/imports/$_operationId/validate', body: {'records': _rows});
      if (validation['valid'] != true) {
        final errors = validation['errors'] is List ? (validation['errors'] as List).whereType<Map>().toList() : <Map>[];
        final message = errors.take(12).map((e) => 'السجل ${(int.tryParse('${e['index']}') ?? -1) + 1}: ${e['message'] ?? 'تحقق من البيانات'}').join('\n');
        if (mounted) { setState(() => _error = 'لم يتم الحفظ. صحح الأخطاء التالية أو احذف السجلات غير المطلوبة ثم أعد الاعتماد:\n$message'); }
        return;
      }
      await widget.api.patch('/admin/imports/$_operationId', body: {'records': _rows});
      final result = await widget.api.post('/admin/imports/$_operationId/commit', body: {'records': _rows});
      if (!mounted) { return; }
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم اعتماد الاستيراد. السجلات المحفوظة: ${result['saved'] ?? 0}')));
    } catch (e) {
      if (mounted && e.toString().contains('IMPORT_EXPIRED')) {
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انتهت مهلة عملية الاستيراد. ارجع إلى صفحة الطلاب أو الجداول وابدأ عملية جديدة.')));
      } else if (mounted) { setState(() => _error = _friendlyError(e)); }
    } finally { if (mounted) { setState(() => _working = false); } }
  }

  @override
  Widget build(BuildContext context) {
    final title = _students ? 'مسح واستيراد الطلاب' : 'مسح واستيراد الجدول';
    return Dialog.fullscreen(child: SafeArea(child: Column(children: [
      AppBar(title: Text(title), leading: IconButton(onPressed: _working ? null : _closeDialog, icon: const Icon(Icons.close)), automaticallyImplyLeading: false),
      Expanded(child: !_review ? _setupView() : _reviewView()),
    ])));
  }

  Widget _setupView() => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('اختر القسم والفصل، ثم حدّد الملف لمراجعته قبل الحفظ.'), const SizedBox(height: 18),
    DropdownButtonFormField<String>(initialValue: _departmentId, decoration: const InputDecoration(labelText: 'القسم', border: OutlineInputBorder()), items: widget.departments.map((d) => DropdownMenuItem(value: '${d['id']}', child: Text(_name(d)))).toList(), onChanged: _working ? null : (v) => setState(() => _departmentId = v)),
    const SizedBox(height: 12),
    DropdownButtonFormField<String>(initialValue: _semesterId, decoration: const InputDecoration(labelText: 'الفصل الدراسي', border: OutlineInputBorder()), items: widget.semesters.map((s) => DropdownMenuItem(value: '${s['id']}', child: Text(_name(s)))).toList(), onChanged: _working ? null : (v) => setState(() => _semesterId = v)),
    if (_error != null) _errorBanner(_error!), if (_working) const LinearProgressIndicator(),
    const SizedBox(height: 16), FilledButton.icon(onPressed: _working ? null : _pickAndScan, icon: const Icon(Icons.document_scanner_outlined), label: const Text('اختيار الملف وبدء المسح')),
  ]);

  Widget _reviewView() => Column(children: [
    Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12)),
            child: Icon(_students ? Icons.groups_2_outlined : Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_students ? 'مراجعة الطلاب المستخرجين' : 'مراجعة الجدول المستخرج',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(_filename ?? 'ملف مستورد', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _infoChip(Icons.layers_outlined, '${_rows.length} ${_students ? 'سجل طالب' : 'حصة'}'),
          _infoChip(Icons.apartment_outlined, _firstName(widget.departments.where((d) => '${d['id']}' == _departmentId))),
          _infoChip(Icons.school_outlined, _firstName(widget.semesters.where((s) => '${s['id']}' == _semesterId))),
        ]),
        if (_expiresAt != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(
          'تنتهي صلاحية المراجعة: $_expiresAt', style: Theme.of(context).textTheme.bodySmall)),
        ..._notes.map((n) => Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: .55), borderRadius: BorderRadius.circular(10)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
            const SizedBox(width: 8), Expanded(child: Text(n, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer))),
          ]))),
        if (_error != null) _errorBanner(_error!),
      ]),
    ),
    Expanded(child: _rows.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, size: 42, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 8), const Text('لا توجد سجلات للمراجعة'),
          const SizedBox(height: 4), Text('أضف سجلًا يدويًا أو ارجع لاختيار ملف آخر.', style: Theme.of(context).textTheme.bodySmall),
        ])))
      : ListView.separated(padding: const EdgeInsets.fromLTRB(12, 12, 12, 16), itemCount: _rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _students ? _studentEditor(i) : _scheduleEditor(i))),
    Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: _working ? null : _addRow,
            icon: const Icon(Icons.add), label: const Text('إضافة سجل'), style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)))),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: FilledButton.icon(onPressed: _working || _rows.isEmpty || _countdown > 0 ? null : _commit,
            icon: _working ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.verified_outlined),
            label: Text(_countdown > 0 ? 'اعتماد بعد $_countdown ثوانٍ' : 'اعتماد وحفظ السجلات'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)))),
        ]),
        const SizedBox(height: 6),
        Text('لن تُحفظ أي بيانات قبل الضغط على «اعتماد وحفظ السجلات».', textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ),
  ]);

  Widget _infoChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15), const SizedBox(width: 5),
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium))]));

  Widget _cardHeading({required IconData icon, required String title, required int index, required VoidCallback onDelete}) => Row(children: [
    Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 19, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$title $index', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      Text('القيم التالية ستُحفظ عند الاعتماد', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ])),
    IconButton(tooltip: 'حذف هذا السجل', onPressed: onDelete, icon: const Icon(Icons.delete_outline),
      style: IconButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error)),
  ]);

  Widget _editorCard({required Widget child}) => Card(
    margin: EdgeInsets.zero, elevation: 0, color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
    child: Padding(padding: const EdgeInsets.all(14), child: child));

  Widget _sectionLabel(String text) => Padding(padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Align(alignment: AlignmentDirectional.centerStart, child: Text(text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700))));

  Widget _studentEditor(int i) {
    final row = _rows[i];
    return _editorCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cardHeading(icon: Icons.person_outline, title: 'الطالب', index: i + 1, onDelete: () => _removeRow(i)),
      _sectionLabel('بيانات الطالب التي ستُضاف'),
      const SizedBox(height: 4),
      TextFormField(key: ValueKey('student-number-$i'), initialValue: '${row['studentNumber'] ?? ''}',
        decoration: const InputDecoration(labelText: 'الرقم الجامعي', prefixIcon: Icon(Icons.badge_outlined), border: OutlineInputBorder()),
        onChanged: (v) => _change(i, 'studentNumber', _digits(v).trim())),
      const SizedBox(height: 10),
      TextFormField(key: ValueKey('student-name-$i'), initialValue: '${row['fullName'] ?? ''}',
        decoration: const InputDecoration(labelText: 'اسم الطالب', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
        onChanged: (v) => _change(i, 'fullName', v)),
      const SizedBox(height: 10),
      TextFormField(key: ValueKey('student-email-$i'), initialValue: '${row['email'] ?? ''}',
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'البريد الإلكتروني (اختياري)', prefixIcon: Icon(Icons.alternate_email), border: OutlineInputBorder()),
        onChanged: (v) => _change(i, 'email', v)),
    ]));
  }

  Widget _scheduleEditor(int i) {
    final row = _rows[i]; final day = int.tryParse('${row['dayOfWeek']}') ?? 0;
    final subjectName = _firstName(_availableSubjects.where((s) => '${s['id']}' == '${row['subjectId']}'));
    final start = '${row['startTime'] ?? ''}'; final end = '${row['endTime'] ?? ''}';
    return _editorCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _cardHeading(icon: Icons.event_note_outlined, title: 'الحصة', index: i + 1, onDelete: () => _removeRow(i)),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.calendar_today_outlined, size: 17, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 7),
            Text(_dayName(row['dayOfWeek']), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(), Icon(Icons.access_time, size: 17, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 5),
            Text('${start.isEmpty ? '—' : start} – ${end.isEmpty ? '—' : end}', style: Theme.of(context).textTheme.labelLarge),
          ]),
          const SizedBox(height: 7),
          Text(subjectName == '—' ? ((row['subjectName'] ?? '').toString().isEmpty ? 'لم تُحدّد المادة بعد' : '${row['subjectName']} • تحتاج إلى ربط بمادة') : subjectName,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          if ('${row['room'] ?? ''}'.trim().isNotEmpty || '${row['lecturer'] ?? ''}'.trim().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 5), child: Text([
              if ('${row['room'] ?? ''}'.trim().isNotEmpty) 'القاعة: ${row['room']}',
              if ('${row['lecturer'] ?? ''}'.trim().isNotEmpty) 'المحاضر: ${row['lecturer']}',
            ].join(' • '), style: Theme.of(context).textTheme.bodySmall)),
        ])),
      _sectionLabel('تعديل البيانات قبل الحفظ'),
      DropdownButtonFormField<String>(key: ValueKey('existing-$i-${row['existingId']}'),
        initialValue: _existingSchedules.any((s) => '${s['id']}' == '${row['existingId']}') ? '${row['existingId']}' : '',
        decoration: const InputDecoration(labelText: 'الإجراء', helperText: 'اختياري: استبدال حصة موجودة', border: OutlineInputBorder()),
        items: [const DropdownMenuItem<String>(value: '', child: Text('إضافة حصة جديدة')),
          ..._existingSchedules.map((s) => DropdownMenuItem<String>(value: '${s['id']}', child: Text(
            '${_firstName(_availableSubjects.where((sub) => '${sub['id']}' == '${s['subject_id']}'))} • ${_dayName(s['day_of_week'])} • ${s['start_time']}–${s['end_time']}', overflow: TextOverflow.ellipsis)))],
        onChanged: (v) => _change(i, 'existingId', v ?? '')),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(key: ValueKey('subject-$i-${row['subjectId']}'),
        initialValue: _availableSubjects.any((s) => '${s['id']}' == '${row['subjectId']}') ? '${row['subjectId']}' : null,
        decoration: const InputDecoration(labelText: 'المادة', border: OutlineInputBorder()),
        items: _availableSubjects.map((s) => DropdownMenuItem(value: '${s['id']}', child: Text(_name(s)))).toList(),
        onChanged: (v) { setState(() { _error = null; _rows[i]['subjectId'] = v ?? ''; _rows[i]['subjectName'] = _firstName(_availableSubjects.where((s) => '${s['id']}' == v)); }); _startCountdown(); }),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(key: ValueKey('day-$i-$day'), initialValue: day.clamp(0, 6).toInt(),
        decoration: const InputDecoration(labelText: 'اليوم', border: OutlineInputBorder()),
        items: const [DropdownMenuItem(value:0,child:Text('الأحد')),DropdownMenuItem(value:1,child:Text('الاثنين')),DropdownMenuItem(value:2,child:Text('الثلاثاء')),DropdownMenuItem(value:3,child:Text('الأربعاء')),DropdownMenuItem(value:4,child:Text('الخميس')),DropdownMenuItem(value:5,child:Text('الجمعة')),DropdownMenuItem(value:6,child:Text('السبت'))],
        onChanged: (v) => _change(i, 'dayOfWeek', v ?? 0)),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: TextFormField(key: ValueKey('start-$i'), initialValue: start, keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: 'وقت البداية', hintText: '08:00', border: OutlineInputBorder()), onChanged: (v) => _change(i, 'startTime', _time(v)))),
        const SizedBox(width: 10), Expanded(child: TextFormField(key: ValueKey('end-$i'), initialValue: end, keyboardType: TextInputType.datetime,
        decoration: const InputDecoration(labelText: 'وقت النهاية', hintText: '10:00', border: OutlineInputBorder()), onChanged: (v) => _change(i, 'endTime', _time(v))))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: TextFormField(key: ValueKey('room-$i'), initialValue: '${row['room'] ?? ''}',
        decoration: const InputDecoration(labelText: 'القاعة (اختياري)', border: OutlineInputBorder()), onChanged: (v) => _change(i, 'room', v))),
        const SizedBox(width: 10), Expanded(child: TextFormField(key: ValueKey('lecturer-$i'), initialValue: '${row['lecturer'] ?? ''}',
        decoration: const InputDecoration(labelText: 'المحاضر (اختياري)', border: OutlineInputBorder()), onChanged: (v) => _change(i, 'lecturer', v)))]),
    ]));
  }

  Widget _errorBanner(String message) => Container(margin: const EdgeInsets.symmetric(vertical: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer, borderRadius: BorderRadius.circular(10)), child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)));
}

class _PreparedOcrUpload {
  const _PreparedOcrUpload(this.bytes, this.filename, this.contentType);
  final Uint8List bytes;
  final String filename;
  final String contentType;
}
