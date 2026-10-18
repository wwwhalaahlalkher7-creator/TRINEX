# TRINEX Admin — Content and Notifications Fix

Date: 2026-10-18

## Content navigation

- Replaced the custom tappable selector for News, Activities, and Achievements with standard Material buttons that visibly indicate the active section and expose conventional touch/accessibility behavior.
- Tapping the active section refreshes its data.
- Added request revision tracking so a slower response from a previously selected section cannot overwrite the selected section's list.
- The Activities label now matches the Arabic wording used elsewhere while retaining the documented `/admin/activities` API resource.

## Notification management

- Added announcement creation from the Notifications page; newly created announcements start as drafts.
- Added local search and status filters.
- Added title/body/type editing, target department/semester selection when lookup lists load, publish date and expiry date fields, and validation that expiry does not precede publication.
- Added status summaries, audience/reads counts, and clearer status labels.
- Added explicit publish/approve and return-to-draft actions, delete with confirmation, and separate confirmed target-list preparation.
- The send/target-list action is disabled in the UI when the publication date is still in the future. This UI check is not a replacement for backend enforcement.
- Added widget tests for content section switching and draft creation.

## API boundary and verification

This ZIP contains the Flutter admin client, not the backend Worker source. The changes use documented routes: `/admin/notifications`, `/admin/announcements`, `/admin/notifications/send`, `/departments`, and `/semesters`. Backend behavior and live delivery were not changed or verified.

Flutter/Dart SDK is unavailable in the editing environment. Run `dart format lib test`, `flutter analyze --no-fatal-infos`, and `flutter test` in CI or a Flutter-enabled environment before release. Live API tests should also verify announcement creation/deletion permissions and server-side enforcement of `publish_at`/`expires_at`.
