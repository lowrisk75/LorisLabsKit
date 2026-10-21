# Feedback v2 — integration contract

Local implementation, 2026-10-01. The public service and app releases have not been deployed by this change.

Add the `LorisReports` package product to the main application. Keep one client per app for the process lifetime and inject the same instance into the UI and lifecycle hooks:

```swift
import LorisReports

let feedback = FeedbackClient(profile: .velya)
// Present inside a NavigationStack, from Settings → Help.
FeedbackCenter(profile: .velya, client: feedback,
    contextProvider: VelyaDiagnosticContext(scheduler: .unknown, permission: .unknown))
```

Use `.lumen` with `LumenDiagnosticContext`, or `.eclair` with `EclairDiagnosticContext`. `unknown` is a real absence of evidence, not a success. Map authoritative app state to these closed enums. Do not infer “alarm rang” from a scheduled alarm or a stop action. Never pass raw logs, URLs, camera names, images, Health data, coordinates, VINs, tokens or user content as technical codes.

No request occurs merely by constructing the client. The user reviews and confirms a report; optional diagnostic context defaults off. The outbox stores the already redacted, consented envelope for up to seven days, bounded to 10 MiB. Private conversation capabilities live in device-only Keychain. Network requests require HTTPS and reject redirects. A lost receipt can be retried with the same identity. Conversations are polled on opening/refresh; background delivery and push are not implemented.

Automatic diagnostic recording is a distinct, default-off permission. Its journal is local (24 hours, 1,000 events, 2 MiB) and has no network side effect during `record`. For an authoritative technical state:

```swift
try await feedback.diagnostics.record(field: .schedulerState, code: "confirmed")
// At a safe foreground idle point, with real app/build/OS metadata:
try await feedback.diagnostics.flush(app: appContext)
```

Velya must call this only after reliable alarm arming; never await support networking on the scheduler, audio, wake, CarPlay or stream critical path. A host must wire actual recording and idle flush hooks before advertising automatic collection. Disabling cancels uploads and clears the local queue. Separate deletion removes uploaded batches via a persistent server tombstone. A request already received before cancellation can remain until deletion or 30-day expiry.

Use `FeedbackCenter` for private user/team conversations. The operator can publish normal replies, identified issues, a planned version, a validated TestFlight invitation, an available version, resolve/reopen. Report text and conversation content are retained by the service for at most 90 days; the user can request earlier deletion from the conversation. A minimized structured case without message text may remain for at most 365 days. “Available” is an operator assertion in this implementation; automated App Store version verification is still required before automatic publication can be added. The beta URL accepts only Apple's public invitation format.

## Reviews

`SmartReviewPromptManager` now defaults to 14 days, 5 meaningful completions, 3 active days and a 120-day cooldown. These are experiment defaults, not measured conversion guarantees. Paid/trial status, satisfaction answers and error history do not filter eligibility. Only attempt the native StoreKit prompt during an idle, unblocked foreground experience. Set `interactionInProgress` while an important task is active. The attempt is recorded, not a verified display or submitted review. Its clock is injectable so apps can prove the day and cooldown boundaries deterministically without changing production time.

A manual “Write a review” link and Help stay independently reachable. Do not introduce a “Do you like the app?” gate. Personal activity summaries must use actual locally observed events; e.g. “You completed X mornings” only if the app records that fact. They must not imply Apple actually displayed a review sheet.

## Migration and release gates

- Existing envelope v1 construction stays source-compatible; decoding handles a missing `context_categories` map. New `FeedbackClient` requires v2 with consent-classified bounded context.
- Velya currently lacks the package dependency. Lumen currently points at a remote SDK revision. Éclair requires XcodeGen changes. Pin an actually published SDK revision (or use a deliberate local development override), update each app's privacy declarations and then build/test the complete app. This SDK change alone does not switch their support flows.
- Keep existing support accessible until the public HTTPS endpoint, deletion worker and backup restoration gate pass.
- v2 attachments, verified email notifications, MetricKit ingestion, message-level remote-AI consent, push/unread badges and unattended retry backoff are not implemented here. The UI does not offer email or attachments.
- No iOS device, VoiceOver, Dynamic Type or app archive validation is implied by macOS package tests.

## Qualification update — 2026-10-05

The public Help page and its app-list endpoint responded on this date; the operator
dashboard redirected to Authentik. This supersedes earlier rollout notes about an
unpublished public ingress, but does not prove an end-to-end native production flow.

`FeedbackAppProfile.vif` is available for Vif, with bounded transfer/permission
context. Adding this profile does not enable the app on the server. The observed
live app allowlist did not include `vif`; the CRM deployment template now includes
it, while the remote-agent allowlist remains unchanged.

The CRM and operator frontend received local fixes for deleted/expired inbox rows,
HTTP 410 handling, stale selection responses and unsent replies. Qualification:
81 backend tests, 3 web API tests, 5 DOM component tests, TypeScript checks and the
isolated support production build passed. The SDK's macOS package tests also passed.
The CRM/dashboard fixes were subsequently deployed and a synthetic staging report
completed submission, operator reply, public HTTPS reading and confirmed erasure.
The available inbox returned to zero. Vif enablement and native device integration
remain open. See [SupportDeployment-2026-10-05.md](SupportDeployment-2026-10-05.md)
for deployment evidence, preserved server differences and remaining gates.

## Security hardening — 2026-10-07

`DiagnosticJournal` now uploads through the same bounded `FeedbackHTTPTransport` as reports
(64 KiB response ceiling checked before download, redirects rejected, no cookies, cache or
credential storage), accepts a `transport:` for tests, ignores a `diagnostics.json` above 2 MiB
and rejects a server challenge that is not `^[A-Za-z0-9._~-]{8,512}$`. The previous private
`URLSession.download` path verified the size only after writing the full body to disk.

`Tests/LorisReportsTests/SecurityContractTests.swift` now proves the contract claims that had
no executable test: TestFlight invitation URL validation, no network during `record`, the
24 h / 1,000-event bounds, cancellation of uploads on disable, inert journal without
qualification, HTTPS-only and credential-free endpoints, the 10 MiB outbox ceiling and
`userTextOnly` rejection of context and device metadata. These tests use a synthetic deletion
token and never touch the device Keychain. They were type-checked, not executed, on this date;
run `swift test` before relying on them. Still open: idempotent single-pass redaction, IP/host and
phone-number redaction rules shared with the server, forcing the data-protection Keychain on
macOS without an access group, TLS pinning, and privacy-manifest additions once push or
MetricKit features are enabled.
