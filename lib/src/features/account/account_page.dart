import 'package:flutter/material.dart';

import '../../api_service.dart';
import '../../session_store.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.api, required this.session, required this.onSignOut});
  final ApiService api;
  final AdminSession session;
  final VoidCallback onSignOut;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hideCurrent = true;
  bool _hideNext = true;
  bool _profileBusy = false;
  String? _email;
  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.session.displayName;
  }

  @override
  void dispose() { _current.dispose(); _next.dispose(); _confirm.dispose(); super.dispose(); }

  Future<void> _editProfile() async {
    if (_profileBusy) return;
    setState(() => _profileBusy = true);
    final nameController = TextEditingController(text: _displayName);
    final emailController = TextEditingController(text: _email ?? '');
    try {
      final profile = await widget.api.get('/auth/staff/me');
      final name = (profile['display_name'] ?? profile['displayName'] ?? _displayName).toString();
      final email = (profile['email'] ?? _email ?? '').toString();
      nameController.text = name;
      emailController.text = email;
      if (!mounted) return;
      final formKey = GlobalKey<FormState>();
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('تعديل بيانات المشرف'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    autofocus: true,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person_outline)),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'أدخل الاسم'
                        : value.trim().length > 120 ? 'الاسم طويل جدًا' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined)),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return null;
                      return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)
                          ? null
                          : 'أدخل بريدًا إلكترونيًا صحيحًا';
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, {
                    'displayName': nameController.text.trim(),
                    'email': emailController.text.trim(),
                  });
                }
              },
              child: const Text('حفظ التعديلات'),
            ),
          ],
        ),
      );
      if (result == null || !mounted) return;
      await widget.api.patch('/auth/staff/me', body: result);
      final store = SessionStore();
      final currentSession = await store.readIncludingExpired() ?? widget.session;
      await store.save(AdminSession(
        accessToken: currentSession.accessToken,
        refreshToken: currentSession.refreshToken,
        displayName: result['displayName']!,
        role: currentSession.role,
        expiresAt: currentSession.expiresAt,
      ));
      if (!mounted) return;
      setState(() {
        _displayName = result['displayName']!;
        _email = result['email'];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث بيانات المشرف بنجاح.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث بيانات المشرف: $error')),
        );
      }
    } finally {
      nameController.dispose();
      emailController.dispose();
      if (mounted) setState(() => _profileBusy = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.api.post('/auth/staff/change-password', body: {
        'currentPassword': _current.text,
        'newPassword': _next.text,
      });
      _current.clear(); _next.clear(); _confirm.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور. أُبطلت الجلسات الأخرى لهذا الحساب.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير كلمة المرور: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    Text('حسابي', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
    const SizedBox(height: 6),
    const Text('بيانات الجلسة الحالية وأمان حساب الإدارة.'),
    const SizedBox(height: 18),
    Card(child: Stack(children: [
      Padding(padding: const EdgeInsets.fromLTRB(18, 46, 18, 18), child: Row(children: [
        CircleAvatar(radius: 28, child: Text(_displayName.isEmpty ? '؟' : _displayName.substring(0, 1))),
        const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_displayName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4), Text('الدور: ${_roleLabel(widget.session.role)}'),
          const SizedBox(height: 4), const Text('رموز الجلسة محفوظة باستخدام التخزين الآمن على الجهاز.'),
        ])),
      ])),
      PositionedDirectional(start: 6, top: 4, child: IconButton(tooltip: 'تعديل بيانات المشرف', onPressed: _profileBusy ? null : _editProfile, icon: _profileBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.edit_outlined))),
    ])),
    const SizedBox(height: 14),
    Card(child: Padding(padding: const EdgeInsets.all(18), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('تغيير كلمة المرور', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6), const Text('يجب أن تكون كلمة المرور الجديدة من 8 إلى 256 حرفًا، وألا تطابق الحالية.'),
      const SizedBox(height: 16),
      TextFormField(controller: _current, obscureText: _hideCurrent, decoration: InputDecoration(labelText: 'كلمة المرور الحالية', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _hideCurrent = !_hideCurrent), icon: Icon(_hideCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => v == null || v.isEmpty ? 'أدخل كلمة المرور الحالية' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _next, obscureText: _hideNext, decoration: InputDecoration(labelText: 'كلمة المرور الجديدة', prefixIcon: const Icon(Icons.password_outlined), suffixIcon: IconButton(onPressed: () => setState(() => _hideNext = !_hideNext), icon: Icon(_hideNext ? Icons.visibility_outlined : Icons.visibility_off_outlined))), validator: (v) => v == null || v.length < 8 || v.length > 256 ? 'استخدم 8 إلى 256 حرفًا' : null),
      const SizedBox(height: 12),
      TextFormField(controller: _confirm, obscureText: _hideNext, decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور الجديدة', prefixIcon: Icon(Icons.check_circle_outline)), validator: (v) => v != _next.text ? 'كلمتا المرور غير متطابقتين' : null),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _busy ? null : _changePassword, icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.key_outlined), label: const Text('حفظ كلمة المرور')),
    ])))),
    const SizedBox(height: 14),
    OutlinedButton.icon(onPressed: widget.onSignOut, icon: const Icon(Icons.logout), label: const Text('تسجيل الخروج من الحساب')),
  ]);

  String _roleLabel(String role) => switch (role) {
    'super_admin' => 'مدير النظام',
    'content_manager' => 'مدير المحتوى',
    'academic_manager' => 'مدير الشؤون الأكاديمية',
    _ => role.isEmpty ? 'غير محدد' : role,
  };
}
