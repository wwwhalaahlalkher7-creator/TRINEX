import 'admin_section.dart';

/// UI-level navigation visibility matching backend role IDs.
/// This is only a usability layer; backend authorization remains authoritative.
abstract final class AdminPermissions {
  static const superAdmin = 'super_admin';
  static const contentManager = 'content_manager';
  static const academicManager = 'academic_manager';
  static const moderator = 'moderator';

  static bool canSee(String role, AdminSection section) {
    switch (role) {
      case superAdmin:
        return true;
      case contentManager:
        return const {AdminSection.overview, AdminSection.content, AdminSection.media, AdminSection.account}
            .contains(section);
      case academicManager:
        return const {
          AdminSection.overview,
          AdminSection.students,
          AdminSection.materials,
          AdminSection.schedule,
          AdminSection.account,
        }.contains(section);
      case moderator:
        return const {
          AdminSection.overview,
          AdminSection.moderation,
          AdminSection.notifications,
          AdminSection.account,
        }.contains(section);
      default:
        // Unknown or future roles receive the least-privilege navigation.
        return const {AdminSection.overview, AdminSection.account}.contains(section);
    }
  }

  static String roleLabel(String role) {
    switch (role) {
      case superAdmin:
        return 'مدير النظام';
      case contentManager:
        return 'مدير المحتوى';
      case academicManager:
        return 'مدير الشؤون الأكاديمية';
      case moderator:
        return 'مشرف التفاعل';
      default:
        return role.isEmpty ? 'دور غير محدد' : role;
    }
  }
}
