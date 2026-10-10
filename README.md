# TRINEX Admin — Flutter (Android / iOS / Windows)

This is the new, independent native Flutter admin app. It is intentionally separate from the existing student Flutter app and does not modify or delete `website/admin`.

## Current starter milestone

Implemented:
- Responsive navigation shell: desktop sidebar, mobile drawer, compact bottom navigation.
- Arabic-first login screen using the existing `/api/v1/auth/staff/login` endpoint.
- Session persisted through `flutter_secure_storage`.
- Dashboard overview reads `/api/v1/admin/dashboard/overview`.
- API base URL override through `--dart-define`.
- Navigation placeholders for the current admin modules, so the feature map is visible while modules are ported.

Not yet complete:
- CRUD and upload flows for students, staff, content, materials, schedules, moderation, settings, audit/security, and Eino monitoring.
- Full role/permission-aware navigation.
- Token refresh parity with the web dashboard.
- Automated API integration tests, Windows packaging verification, and iOS signing/release setup.
- Full Arabic/English localization and light/dark theme preferences.

**This starter is not a replacement for the website dashboard yet. Do not remove the existing website admin.**

## Requirements

Install Flutter (stable) and platform toolchains:
- Android: Android SDK / Android Studio.
- iOS: macOS with Xcode for build/sign/release. Windows or Linux cannot produce a signed iOS app.
- Windows: Windows 10/11 with Visual Studio 2022 and the "Desktop development with C++" workload.

## Run locally

```bash
flutter pub get
flutter create --platforms=android,ios,windows .
flutter run -d windows
# or select an Android/iOS device in `flutter devices`
```

If platform folders already exist, do not recreate them unnecessarily.

## Build examples

```bash
flutter build apk --release --dart-define=TRINEX_API_BASE_URL=https://leo-association-api.www-halaahlalkher7.workers.dev/api/v1
flutter build appbundle --release --dart-define=TRINEX_API_BASE_URL=https://leo-association-api.www-halaahlalkher7.workers.dev/api/v1
flutter build windows --release --dart-define=TRINEX_API_BASE_URL=https://leo-association-api.www-halaahlalkher7.workers.dev/api/v1
# iOS build/signing must run on macOS:
flutter build ios --release --dart-define=TRINEX_API_BASE_URL=https://leo-association-api.www-halaahlalkher7.workers.dev/api/v1
```

Do not commit signing keys, passwords, access tokens, or real admin credentials.

## Existing backend contract verified from the supplied Union-App archive

- Login: `POST /auth/staff/login`, body `{ "userId": "...", "password": "..." }`
- Dashboard summary: `GET /admin/dashboard/overview`
- Eino usage: `GET /admin/security/eino-usage?hours=24`
- Health check: `GET /health`
- Protected requests use `Authorization: Bearer <token>`.
- API responses may be wrapped in `{ "success": true, "data": ... }`.

Default API URL matches the current `website/admin/config.js`. Use the build-time define if the production API URL changes.

## Module parity checklist

| Existing web module | Flutter module | Status |
|---|---|---|
| Dashboard overview | Overview | Starter wired to API |
| Students | Students | Navigation placeholder |
| Staff / users | Staff & permissions | Navigation placeholder |
| Content / news / announcements | Content | Navigation placeholder |
| Materials / Drive sync | Materials | Navigation placeholder |
| Schedule | Schedule | Navigation placeholder |
| Moderation / comments / replies | Moderation | Navigation placeholder |
| Security / audit logs / auth events | Security | Navigation placeholder |
| Eino usage / monitor | Eino monitor | Navigation placeholder |
| Site settings | Settings | Navigation placeholder |
| Account / password change | Account | Basic session info only |

## Safe migration policy

1. Keep `website/admin` live while Flutter modules are implemented.
2. Compare each module's read/write operations and permission cases against the web implementation.
3. Test against a non-production/test account and safe test data first.
4. Do not remove web files, build copy steps, or CI checks until all modules pass the parity checklist and the owner explicitly approves removal.
