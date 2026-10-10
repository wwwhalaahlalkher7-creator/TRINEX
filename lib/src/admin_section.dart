import 'package:flutter/material.dart';

enum AdminSection {
  overview('نظرة عامة', Icons.space_dashboard_outlined),
  students('الطلاب', Icons.school_outlined),
  staff('الموظفون والصلاحيات', Icons.manage_accounts_outlined),
  content('المحتوى', Icons.article_outlined),
  materials('المواد الدراسية', Icons.menu_book_outlined),
  schedule('الجداول', Icons.calendar_month_outlined),
  moderation('الإشراف والتعليقات', Icons.gavel_outlined),
  notifications('الإشعارات', Icons.notifications_active_outlined),
  media('رفع الوسائط', Icons.perm_media_outlined),
  security('الأمان وسجل التدقيق', Icons.shield_outlined),
  eino('مراقبة إينو', Icons.monitor_heart_outlined),
  settings('الإعدادات', Icons.settings_outlined),
  account('حسابي', Icons.person_outline);

  const AdminSection(this.title, this.icon);
  final String title;
  final IconData icon;
}
