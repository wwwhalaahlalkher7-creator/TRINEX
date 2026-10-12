# TRINEX-Admin — Admin Capability Parity Audit

This document maps the legacy `Union-App/website/admin` capabilities to the native Flutter admin and the existing TRINEX API. The website admin directory is removed from the delivered project; the public website and backend source remain in place.

## Native screens and API connections

| Legacy capability | Flutter destination | Backend contract | Status in source |
|---|---|---|---|
| Dashboard / overview counts | Overview | `GET /admin/dashboard/overview` | Connected; includes an independent `/health` status check |
| Students | Users → Students | `/admin/students`, `/departments`, `/semesters` | CRUD and active-state controls present |
| Staff / roles | Users → Staff | `/admin/staff` | CRUD, role assignment, active-state, password reset are present; server permissions remain authoritative |
| News | Content → News | `/admin/news` | CRUD, status, dates, metadata and image upload/link supported |
| Activities / events | Content → Events | `/admin/activities` (maps to backend `events`) | Corrected route mapping; CRUD and event metadata supported |
| Achievements | Content → Achievements | `/admin/achievements` | CRUD, date, badge, highlights and image URL/upload supported; backend creates/refreshes linked notification drafts |
| Announcements | Content → Announcements | `/admin/announcements` | CRUD, type, audience IDs, publish/expiry dates and status supported |
| Academic subjects | Academic workspace | `/admin/subjects` | CRUD present |
| Study materials | Academic workspace | `/admin/materials` | CRUD and Drive sync status present; direct upload of a new Drive PDF is not provided by the legacy API/UI either |
| Schedules | Academic workspace | `/admin/schedule` | CRUD present; backend creates/refreshes linked notification drafts for meaningful schedule changes |
| Google Drive sync | Academic workspace | `/admin/drive/sync`, `/admin/drive/sync-status` | Connected; action requires confirmation |
| Comments / replies | Moderation | `/admin/moderation/comments`, `/admin/moderation/replies` | Status moderation and reply deletion present |
| Public chat reports | Chat reports | `/admin/moderation/chat-reports` | Added native list, status filters, resolve/dismiss, and message hide/keep actions |
| Notifications | Notifications | `/admin/notifications`, `/admin/notifications/send`, `/admin/announcements/:id` | Added draft editing and explicit approve/publish step; sending remains a separate confirmed action |
| Media upload | Content editor and Media | `POST /admin/media` | Added upload from content editor; JPEG/PNG/WebP, 3 MB limit, server validates and returns URL |
| Audit log and authentication events | Security | `/admin/audit-logs`, `/admin/security/auth-events` | Read-only; sensitive fields redacted in detail view |
| Eino usage/monitoring | Eino monitor | `/admin/security/eino-monitor` | Added provider/task summaries, request statuses, latency, quota limits, recent telemetry and privacy notice |
| Site display settings | Settings | `/admin/settings` | Restricted to `public.*` and `Logo`, matching the legacy adapter's safe settings scope |
| Staff account / password | Account | `/auth/staff/change-password`, `/auth/logout` | Connected |

## Notification workflow

The backend source already creates or refreshes editable drafts for new schedule/material/achievement records and for meaningful changes to those records. The Flutter notification screen now supports:

1. Reviewing the generated draft.
2. Editing its title/body/type and target department/semester.
3. Explicitly approving/publishing it.
4. Sending/updating its target list only as a separate action after publication.

Publishing does not claim that push notifications were delivered; actual device delivery depends on the backend dispatch configuration.

## Security and source integrity

- The legacy `website/admin` source directory is removed from the migration package.
- The public website source and backend source remain present.
- Admin navigation is filtered by role for usability; API authorization remains the source of truth.
- The Eino monitor uses the backend's privacy-preserving telemetry contract and does not display prompts, responses, student IDs, IP addresses, or file contents.

## Verification limits

Source-level route and feature wiring was reviewed, but this editing environment does not have Flutter/Dart installed. Therefore `dart format`, `flutter analyze`, `flutter test`, platform builds, and live API integration tests were not run here. The package must not be considered release-verified until those checks pass in CI and the changed flows are tested with authorized test accounts against the target API.

The source code's presence is not proof that production secrets, Cloudflare routes, D1 migrations, R2 media storage, or push delivery are configured. In particular, verify the deployed backend has migrations through `0038_content_notification_drafts.sql` and that `/admin/security/eino-monitor` and `/admin/moderation/chat-reports` are deployed before relying on those screens in production.
