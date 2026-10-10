import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api_service.dart';

class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.api});
  final ApiService api;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage> {
  bool _uploading = false;
  String? _error;
  String? _url;
  String? _meta;

  Future<void> _pickAndUpload() async {
    setState(() { _error = null; });
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() => _error = 'تعذر قراءة الملف من الجهاز. حاول اختيار الصورة مرة أخرى.');
      return;
    }
    final ext = (file.extension ?? '').toLowerCase();
    final type = switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => '',
    };
    if (type.isEmpty) {
      setState(() => _error = 'نوع الصورة غير مدعوم.');
      return;
    }
    if (bytes.length > 3 * 1024 * 1024) {
      setState(() => _error = 'حجم الصورة ${_formatBytes(bytes.length)}؛ الحد الأقصى 3 ميغابايت.');
      return;
    }
    setState(() { _uploading = true; _url = null; _meta = null; });
    try {
      final response = await widget.api.uploadImage(bytes: bytes, filename: file.name, contentType: type);
      final raw = response['data'];
      final data = raw is Map ? Map<String, dynamic>.from(raw) : response;
      final url = data['url']?.toString() ?? '';
      if (url.isEmpty) throw const ApiServiceException('نجح الطلب دون أن يعيد الخادم رابط الصورة.');
      if (mounted) setState(() { _url = url; _meta = '${file.name} • ${_formatBytes(bytes.length)} • $type'; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  String _formatBytes(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';

  Future<void> _copyUrl() async {
    final url = _url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الصورة.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(padding: const EdgeInsets.fromLTRB(20, 22, 20, 32), children: [
      Text('رفع الوسائط', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text('رفع الصور إلى تخزين الوسائط المعتمد على الخادم واستخدام الرابط في المحتوى.', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.verified_user_outlined), SizedBox(width: 10), Expanded(child: Text('قيود الرفع'))]),
        const SizedBox(height: 12),
        const Text('• الأنواع المسموحة: JPEG وPNG وWebP.\n• الحد الأقصى للصورة الواحدة: 3 ميغابايت.\n• يتحقق الخادم من توقيع الملف ونوعه وحصة التخزين.\n• قد يكون الرفع غير متاح إذا لم يُضبط مخزن الوسائط في بيئة الخادم.'),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: _uploading ? null : _pickAndUpload, icon: _uploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.upload_file), label: Text(_uploading ? 'جارٍ الرفع…' : 'اختيار صورة ورفعها')),
        if (_error != null) ...[const SizedBox(height: 14), SelectableText('تعذر الرفع: $_error', style: TextStyle(color: theme.colorScheme.error))],
      ]))),
      if (_url != null) ...[
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.check_circle_outline, color: theme.colorScheme.primary), const SizedBox(width: 10), Text('اكتمل الرفع', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))]),
          const SizedBox(height: 8),
          Text(_meta ?? ''),
          const SizedBox(height: 12),
          SelectableText(_url!),
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerEnd, child: FilledButton.tonalIcon(onPressed: _copyUrl, icon: const Icon(Icons.copy), label: const Text('نسخ الرابط'))),
          const SizedBox(height: 8),
          const Text('يمكن لصق الرابط في حقل رابط الصورة داخل سجل المحتوى. حذف الملفات غير المرتبطة ينفذه تنظيف الخادم لاحقًا.'),
        ]))),
      ],
    ]);
  }
}
