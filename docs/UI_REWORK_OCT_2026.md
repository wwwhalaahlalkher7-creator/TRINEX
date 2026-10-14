# TRINEX-Admin UI rework — 2026-10

## Applied in this revision
- Removed the standalone media-upload section; image upload is available from the content editor.
- Student creation/editing no longer exposes email or academic level fields. The dialog clarifies that students manage these from their own account.
- Localized staff role labels in the staff form.
- Content types exposed in the content page are now News, Events, and Achievements; announcements are handled through the Notifications section rather than the content editor.
- Replaced manually entered ISO date fields with a date picker in the content editor.
- Removed the manual draft/published selector. Future-dated news and achievements are saved as drafts for the Worker scheduled publisher; items without a date use today's timestamp. Future events remain published and receive the “قريباً” category.
- Image selection uses the device gallery and shows an image preview after upload.
- Schedule route opens directly on the schedules view without the academic tab selector; start/end times use a time picker and visibly report صباحًا/مساءً.
- Added profile edit action to the account card using the existing `/auth/staff/me` API.
- Clarified the settings page purpose and retained guarded public settings editing.

## Integration notes
- Scheduled news/achievement publication depends on the backend Worker's scheduled trigger being configured and deployed.
- Profile updates require the deployed API to include the existing `PATCH /auth/staff/me` route.
- This source package was not compiled in this environment because Flutter/Dart SDKs are unavailable here. Run `flutter pub get`, `dart format lib`, and `flutter analyze` before release.
