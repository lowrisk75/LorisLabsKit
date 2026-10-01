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
