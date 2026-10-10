import 'package:flutter/material.dart';
import 'api_service.dart';
import 'session_store.dart';

enum AdminSection {
  overview('نظرة عامة', Icons.space_dashboard_outlined),
  students('الطلاب', Icons.school_outlined),
  staff('الموظفون والصلاحيات', Icons.manage_accounts_outlined),
  content('المحتوى', Icons.article_outlined),
  materials('المواد الدراسية', Icons.menu_book_outlined),
  schedule('الجداول', Icons.calendar_month_outlined),
  moderation('الإشراف والتعليقات', Icons.gavel_outlined),
  security('الأمان وسجل التدقيق', Icons.shield_outlined),
  eino('مراقبة إينو', Icons.monitor_heart_outlined),
  settings('الإعدادات', Icons.settings_outlined),
  account('حسابي', Icons.person_outline);

  const AdminSection(this.title, this.icon);
  final String title;
  final IconData icon;
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, required this.sessionStore});
  final ApiService api;
  final SessionStore sessionStore;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  AdminSession? _session;
  bool _checkingSession = true;
  AdminSection _section = AdminSection.overview;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await widget.sessionStore.read();
    if (!mounted) return;
    setState(() {
      _session = session;
      _checkingSession = false;
    });
  }

  Future<void> _signOut() async {
    await widget.api.logout();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSession) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session == null) {
      return LoginScreen(
        api: widget.api,
        onLoggedIn: (session) => setState(() => _session = session),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        final isCompact = constraints.maxWidth < 600;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(width: 270, child: _NavigationRailPanel(
                  selected: _section,
                  onSelect: (section) => setState(() => _section = section),
                  session: _session!,
                  onSignOut: _signOut,
                )),
                const VerticalDivider(width: 1),
                Expanded(child: _buildPage()),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(_section.title),
            actions: [
              IconButton(
                tooltip: 'تسجيل الخروج',
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: _NavigationRailPanel(
                selected: _section,
                onSelect: (section) {
                  setState(() => _section = section);
                  Navigator.of(context).pop();
                },
                session: _session!,
                onSignOut: _signOut,
              ),
            ),
          ),
          body: _buildPage(),
          bottomNavigationBar: isCompact ? _CompactBottomBar(
            selected: _section,
            onSelect: (section) => setState(() => _section = section),
          ) : null,
        );
      },
    );
  }

  Widget _buildPage() {
    switch (_section) {
      case AdminSection.overview:
        return DashboardPage(api: widget.api, session: _session!);
      case AdminSection.account:
        return _InfoPage(
          title: 'حسابي',
          icon: Icons.person_outline,
          message: 'الاسم: ${_session!.displayName}\nالدور: ${_session!.role}\n\nإدارة كلمة المرور وإعدادات الحساب ستُربط في مرحلة الحساب والأمان.',
        );
      default:
        return _InfoPage(
          title: _section.title,
          icon: _section.icon,
          message: 'تم تجهيز هذه الوحدة في هيكل التنقل. سيتم تنفيذ وظائفها وربط عملياتها بالـBackend في مراحل النقل التالية، مع مطابقة وظائف لوحة الموقع الحالية.',
        );
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.api, required this.onLoggedIn});
  final ApiService api;
  final ValueChanged<AdminSession> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _userController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final session = await widget.api.login(_userController.text, _passwordController.text);
      if (mounted) widget.onLoggedIn(session);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 68, height: 68,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.admin_panel_settings_outlined,
                          size: 36, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(height: 20),
                      Text('TRINEX Admin',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      const Text('تسجيل دخول المشرفين والموظفين'),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _userController,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(labelText: 'اسم المستخدم أو المعرّف'),
                        validator: (value) => value == null || value.trim().isEmpty ? 'أدخل اسم المستخدم' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        validator: (value) => value == null || value.isEmpty ? 'أدخل كلمة المرور' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('تسجيل الدخول'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'تُحفظ الجلسة في التخزين الآمن للجهاز. الصلاحيات النهائية يفرضها الخادم.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.api, required this.session});
  final ApiService api;
  final AdminSession session;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final stats = await widget.api.getDashboardOverview();
      if (mounted) setState(() => _stats = stats);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _number(String key) => int.tryParse(_stats?[key]?.toString() ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 12,
            spacing: 12,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('مركز التحكم', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text('مرحبًا ${widget.session.displayName}، هذه نظرة عامة على المنصة.'),
              ]),
              OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('تحديث البيانات')),
            ],
          ),
          const SizedBox(height: 24),
          if (_loading && _stats == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null && _stats == null)
            _ErrorPanel(message: _error!, onRetry: _load)
          else
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1150 ? 4 : constraints.maxWidth >= 700 ? 2 : 1;
              final width = (constraints.maxWidth - (columns - 1) * 14) / columns;
              final items = [
                _StatData('إجمالي الطلاب', _number('students'), Icons.school_outlined, const Color(0xFF246BFD)),
                _StatData('الطلاب النشطون', _number('activeStudents'), Icons.verified_user_outlined, const Color(0xFF16865B)),
                _StatData('المواد الدراسية', _number('materials'), Icons.menu_book_outlined, const Color(0xFF8B5CF6)),
                _StatData('المحتوى المنشور', _number('news'), Icons.article_outlined, const Color(0xFFE58A19)),
              ];
              return Wrap(
                spacing: 14, runSpacing: 14,
                children: items.map((item) => SizedBox(
                  width: width,
                  child: _StatCard(data: item),
                )).toList(),
              );
            }),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEAF1FF), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.info_outline, color: Color(0xFF246BFD)),
                ),
                const SizedBox(width: 14),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('نسخة البناء الأولية', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  SizedBox(height: 6),
                  Text('تم تجهيز تسجيل الدخول، التخزين الآمن للجلسة، الاتصال بواجهة الإحصائيات، والتنقل المتجاوب. بقية وحدات الإدارة ستُنقل تدريجيًا وتُختبر مقابل لوحة الموقع قبل اعتماد الاستبدال.'),
                ])),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text('تعذر تحديث البيانات: $_error')),
          Text('مستخدم الجلسة: ${widget.session.displayName}  •  الدور: ${widget.session.role}'),
        ],
      ),
    );
  }
}

class _StatData {
  const _StatData(this.title, this.value, this.icon, this.color);
  final String title;
  final int value;
  final IconData icon;
  final Color color;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.data});
  final _StatData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: data.color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)),
            child: Icon(data.icon, color: data.color),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data.title, style: const TextStyle(color: Color(0xFF667085))),
            const SizedBox(height: 6),
            Text(data.value.toString(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          ])),
        ]),
      ),
    );
  }
}

class _NavigationRailPanel extends StatelessWidget {
  const _NavigationRailPanel({
    required this.selected,
    required this.onSelect,
    required this.session,
    required this.onSignOut,
  });

  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;
  final AdminSession session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.admin_panel_settings_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TRINEX', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
                Text('لوحة الإدارة', style: TextStyle(color: Colors.black54, fontSize: 12)),
              ])),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final section in AdminSection.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      selected: selected == section,
                      selectedTileColor: const Color(0xFFEAF1FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      leading: Icon(section.icon),
                      title: Text(section.title, style: const TextStyle(fontSize: 14)),
                      onTap: () => onSelect(section),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(session.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(session.role, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: OutlinedButton.icon(
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactBottomBar extends StatelessWidget {
  const _CompactBottomBar({required this.selected, required this.onSelect});
  final AdminSection selected;
  final ValueChanged<AdminSection> onSelect;

  @override
  Widget build(BuildContext context) {
    const compactSections = [
      AdminSection.overview,
      AdminSection.students,
      AdminSection.content,
      AdminSection.materials,
      AdminSection.account,
    ];
    final selectedIndex = compactSections.indexOf(selected);
    return NavigationBar(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) => onSelect(compactSections[index]),
      destinations: compactSections.map((section) => NavigationDestination(
        icon: Icon(section.icon),
        label: section.title,
      )).toList(),
    );
  }
}

class _InfoPage extends StatelessWidget {
  const _InfoPage({required this.title, required this.icon, required this.message});
  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(message),
            ]),
          ),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.cloud_off_outlined, size: 32),
          const SizedBox(height: 10),
          const Text('تعذر تحميل لوحة المعلومات', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(message),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
        ]),
      ),
    );
  }
}
