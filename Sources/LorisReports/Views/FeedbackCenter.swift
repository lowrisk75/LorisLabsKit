// Screens target iOS/macOS/visionOS; tvOS/watchOS keep the non-UI layers.
#if !os(tvOS) && !os(watchOS)
import SwiftUI

/// A native support surface shared by all apps; conversations require no user account.
public struct FeedbackCenter: View {
    private let profile: FeedbackAppProfile
    @State private var client: FeedbackClient
    private let contextProvider: (any DiagnosticContextProvider)?
    private let notifications: SupportNotificationCoordinator?
    @State private var notificationTicket: FeedbackTicket?
    @State private var diagnosticsEnabled = false
    @State private var tickets: [FeedbackTicket] = []
    @State private var unread: [String: Int] = [:]
    @State private var pending: [ReportEnvelope] = []
    @State private var showCompose = false
    @State private var error: String?
    public init(profile: FeedbackAppProfile, client: FeedbackClient? = nil, contextProvider: (any DiagnosticContextProvider)? = nil, notifications: SupportNotificationCoordinator? = nil) {
        self.profile = profile; self._client = State(initialValue: client ?? FeedbackClient(profile: profile)); self.contextProvider = contextProvider; self.notifications = notifications
    }
    public var body: some View {
        List {
            Section {
                Button { showCompose = true } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: "square.and.pencil").accessibilityHidden(true)
                        Text(t("Nouvelle demande", "New request"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(t("Un problème, une idée ou une question. Échangez directement avec notre équipe.", "A problem, an idea or a question. Talk directly with our team."))
                    .foregroundStyle(.secondary)
            }
            if !pending.isEmpty {
                Section(t("En attente d’envoi", "Waiting to send")) {
                    ForEach(pending, id: \.clientReportID) { report in
                        VStack(alignment: .leading) {
                            Text(report.title)
                            Button(t("Annuler l’envoi", "Cancel delivery")) { Task { try? await client.cancelPending(report.clientReportID); await reload() } }
                        }
                    }
                    Button(t("Réessayer les envois", "Retry delivery")) {
                        Task { do { try await client.retryPending(); await reload() } catch { self.error = t("Envoi non confirmé. Réessayez plus tard.", "Delivery not confirmed. Try again later.") } }
                    }
                }
            }
            Section(t("Mes conversations", "My conversations")) {
                if tickets.isEmpty { Text(t("Vos demandes apparaîtront ici.", "Your requests will appear here.")) }
                ForEach(tickets) { ticket in
                    NavigationLink {
                        FeedbackConversationView(client: client, ticket: ticket, notifications: notifications)
                    } label: {
                        HStack {
                            Text(ticket.reference)
                            Spacer()
                            if let count = unread[ticket.reference], count > 0 {
                                Text("\(count)").font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.tint.opacity(0.15), in: Capsule())
                                    .accessibilityLabel("\(count) " + t("réponses non lues", "unread replies"))
                            }
                        }
                    }
                }
            }
            SupportJournalSettings(client: client)
            if client.features.diagnostics {
                Button(t("Réessayer les diagnostics confirmés", "Retry confirmed diagnostics")) {
                    Task { do { try await client.retryReviewedDiagnostics() } catch { self.error = t("Envoi non confirmé.", "Delivery unconfirmed.") } }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(t("Aide et idées", "Help and ideas"))
        .navigationDestination(item: $notificationTicket) { ticket in
            FeedbackConversationView(client: client, ticket: ticket, notifications: notifications)
        }
        .onChange(of: notifications?.route, initial: true) { _, route in
            guard let route else { return }
            Task {
                notificationTicket = try? await client.ticketForNotification(route: route)
                if notificationTicket == nil { error = t("Cette conversation n’est plus accessible sur cet appareil.", "This conversation is no longer accessible on this device.") }
                notifications?.clearRoute()
            }
        }
        .task { await notifications?.resume(); await reload() }
        .refreshable { await reload() }
        .sheet(isPresented: $showCompose, onDismiss: { Task { await reload() } }) {
            NavigationStack { FeedbackComposer(client: client, profile: profile, provider: contextProvider) }
        }
    }
    private func reload() async {
        do { diagnosticsEnabled = await client.diagnostics.isEnabled; tickets = try await client.tickets(); pending = try await client.pendingReports(); error = nil
            // Sequential reads avoid flooding the API on a large local history.
            for ticket in tickets.prefix(100) {
                guard !Task.isCancelled else { return }
                if let activity = try? await client.activity(ticket) { unread[ticket.reference] = activity.unreadTeamMessages }
            }
        }
        catch { self.error = t("Impossible de lire vos conversations.", "Unable to read your conversations.") }
    }
}

private func t(_ french: String, _ english: String) -> String {
    Locale.current.language.languageCode?.identifier == "fr" ? french : english
}

private struct FeedbackComposer: View {
    let client: FeedbackClient
    let profile: FeedbackAppProfile
    let provider: (any DiagnosticContextProvider)?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ReportKind = .bug
    @State private var description = ""
    @State private var includeDiagnostics = false
    @State private var showingAssistant = false
    @State private var envelope: ReportEnvelope?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        Form {
            if let envelope {
                Section(t("Avant l’envoi", "Before sending")) {
                    Text(envelope.description)
                    Text("\(profile.displayName) · \(envelope.app.appVersion) (\(envelope.app.appBuild))")
                    Text("OS · \(envelope.app.osVersion)")
                    ForEach(envelope.structuredContext.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: envelope.structuredContext[key] ?? "")
                    }
                    Text(t("Aucun email requis. Vous pourrez lire et envoyer des réponses ici. Le contenu et la conversation sont conservés au maximum 90 jours ; suppression disponible dans la conversation.", "No email required. Read and send replies here. Content and conversation are retained for at most 90 days; deletion is available in the conversation."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(t("Modifier", "Edit")) {
                        Task {
                            do { try await client.cancelPending(envelope.clientReportID); self.envelope = nil }
                            catch { self.error = t("Impossible de modifier l’envoi en attente.", "Unable to edit the pending report.") }
                        }
                    }.disabled(busy)
                    Button(t("Confirmer et envoyer", "Confirm and send")) { Task { await submit(envelope) } }
                        .disabled(busy)
                }
            } else {
                Picker(t("Votre demande", "Your request"), selection: $kind) {
                    Text(t("Signaler un problème", "Report a problem")).tag(ReportKind.bug)
                    Text(t("Proposer une idée", "Suggest an improvement")).tag(ReportKind.featureRequest)
                    Text(t("Poser une question", "Ask a question")).tag(ReportKind.question)
                }
                TextEditor(text: $description).frame(minHeight: 140)
                    .accessibilityLabel(t("Description de la demande", "Request description"))
                if client.features.assistant {
                    Button(t("M’aider à préciser le problème", "Help me refine the problem")) { showingAssistant = true }
                }
                if provider != nil { Toggle(t("Joindre les codes de diagnostic", "Attach diagnostic codes"), isOn: $includeDiagnostics) }
                Text(t("N’incluez pas de mot de passe ni de contenu personnel.", "Do not include passwords or personal content.")).font(.footnote)
                Button(t("Vérifier avant l’envoi", "Review before sending")) { Task { await prepare() } }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || description.count > 10000 || busy)
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .sheet(isPresented: $showingAssistant) { SupportAssistantView(client: client, draft: $description) }
        .navigationTitle(t("Contacter l’équipe", "Contact the team"))
        .toolbar { Button(t("Fermer", "Close")) { dismiss() }.disabled(busy) }
    }
    private func prepare() async {
        busy = true; defer { busy = false }
        let values = includeDiagnostics ? await provider?.context() ?? [] : []
        var context: [String: String] = [:]
        var categories: [String: ReportDataCategory] = [:]
        for value in values where profile.allowedFields.contains(value.field) {
            context[value.field.rawValue] = value.code; categories[value.field.rawValue] = value.category
        }
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        #if os(macOS)
        let platform = ReportPlatform.macOS
        #elseif os(visionOS)
        let platform = ReportPlatform.visionOS
        #elseif os(iOS)
        let platform = ReportPlatform.iOS
        #else
        let platform = ReportPlatform.other
        #endif
        do {
            let report = try ReportEnvelope(schemaVersion: 2, kind: kind, title: String(text.prefix(120)), description: text,
                app: ReportAppContext(appID: profile.appID,
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                    platform: platform, osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                    locale: Locale.current.identifier), structuredContext: context, contextCategories: categories,
                consent: ConsentReceipt(noticeVersion: "sdk-2026-10-01", categories: Set([.userDescription, .appMetadata]).union(categories.values)))
            envelope = try ReportRedactionPipeline().redact(report)
            error = nil
        } catch { self.error = t("Le contexte ne respecte pas les règles de confidentialité. Désactivez les diagnostics pour envoyer votre message.", "The context does not meet privacy rules. Disable diagnostics to send your message.") }
    }
    private func submit(_ envelope: ReportEnvelope) async {
        busy = true; defer { busy = false }
        do { _ = try await client.submit(envelope); dismiss() }
        catch { self.error = t("Envoi impossible. Votre texte est conservé, vous pouvez réessayer.", "Unable to send. Your text is preserved; you can retry.") }
    }
}

private struct FeedbackConversationView: View {
    let client: FeedbackClient
    let ticket: FeedbackTicket
    let notifications: SupportNotificationCoordinator?
    @State private var conversation: FeedbackConversation?
    @State private var messages: [FeedbackMessage] = []
    @State private var reply = ""
    @State private var pendingReply: PendingFeedbackReply?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDeletion = false
    @State private var showingAssistant = false
    @State private var showingDiagnostics = false
    @State private var deletionState: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if deletionState == "pending" {
                Section {
                    Text(t("Suppression en cours. Actualisez pour vérifier son achèvement.", "Deletion is pending. Refresh to confirm completion."))
                }
            }
            if conversation == nil, let operation = pendingReply {
                Section(t("Répondre", "Reply")) { pendingReplyContent(operation) }
            }
            if let conversation {
                Section(conversation.title) { Text(conversation.description) }
                ForEach(messages) { message in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(message.author == "team" ? "LorisLabs" : t("Vous", "You")).font(.headline)
                        Text(message.body)
                        if let version = message.targetVersion { Text("\(message.kind == "planned" ? t("Version prévue", "Planned version") : t("Version disponible", "Available version")) : \(version)").font(.caption) }
                        if let url = message.validatedBetaURL { Link(t("Tester avec TestFlight", "Test with TestFlight"), destination: url) }
                    }
                }
                if conversation.hasMore { Button(t("Messages suivants", "Next messages")) { Task { await load(append: true) } } }
                Section(t("Répondre", "Reply")) {
                    if let operation = pendingReply {
                        pendingReplyContent(operation)
                    } else {
                        TextEditor(text: $reply).frame(minHeight: 100).disabled(busy).accessibilityLabel(t("Votre réponse", "Your reply")).accessibilityIdentifier("support.reply.editor")
                        Button(t("Envoyer", "Send")) { Task { await send() } }.accessibilityIdentifier("support.reply.send")
                            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || reply.count > 10000)
                        Button(conversation.state == "resolved" ? t("Rouvrir", "Reopen") : t("Problème résolu", "Problem resolved")) {
                            Task { await changeState(conversation.state == "resolved" ? "reopened" : "resolved") }
                        }.disabled(busy)
                    }
                }
                if client.features.notifications, let notifications {
                    Section(t("Notifications du support", "Support notifications")) {
                        Text(t("Une alerte générique ouvre cette conversation. Aucun message privé sur l’écran verrouillé.", "A generic alert opens this conversation. No private message on the lock screen."))
                        if notifications.preferences[ticket.reference] == true {
                            Button(t("Désactiver pour cette demande", "Disable for this request")) { Task { await notifications.disable(for: ticket) } }
                        } else {
                            Button(t("M’avertir des réponses", "Notify me of replies")) { Task { await notifications.enable(for: ticket) } }
                        }
                        if let error = notifications.error { Text(error).font(.footnote) }
                    }
                }
                if client.features.assistant, pendingReply == nil {
                    Button(t("M’aider à préparer un complément", "Help prepare a clarification")) { showingAssistant = true }
                }
                if client.features.diagnostics {
                    Button(t("Joindre un diagnostic revu", "Attach reviewed diagnostics")) { showingDiagnostics = true }
                }
                Button(t("Supprimer ma demande", "Delete my request"), role: .destructive) { confirmDeletion = true }
                    .disabled(deletionState == "pending")
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView() }
        }
        .sheet(isPresented: $showingAssistant) { SupportAssistantView(client: client, draft: $reply) }
        .sheet(isPresented: $showingDiagnostics) { SupportDiagnosticReview(client: client, ticket: ticket) }
        .navigationTitle(ticket.reference)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(t("Supprimer cette conversation ?", "Delete this conversation?"), isPresented: $confirmDeletion) {
            Button(t("Demander la suppression", "Request deletion"), role: .destructive) {
                Task {
                    do {
                        try await client.requestDeletion(ticket)
                        deletionState = "pending"
                        self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false
                        error = nil
                    } catch {
                        self.error = t("Suppression impossible. Réessayez.", "Deletion failed. Please retry.")
                    }
                }
            }
        }
    }
    @ViewBuilder private func pendingReplyContent(_ operation: PendingFeedbackReply) -> some View {
        Text(operation.expired
            ? t("La confirmation a expiré. Le texte local a été effacé ; aucun nouvel envoi ne sera créé pour contourner cette opération incertaine.", "Confirmation expired. Local text was erased; no new delivery will bypass this uncertain operation.")
            : t("Une action confirmée attend son accusé. Elle sera vérifiée avant tout réessai.", "A confirmed action is waiting for acknowledgement. It will be checked before retrying."))
            .accessibilityIdentifier("support.reply.pending")
        if !operation.expired {
            Text(operation.body).accessibilityIdentifier("support.reply.pending.body")
            Button(t("Vérifier et réessayer", "Check and retry")) { Task { await retryReply() } }
                .disabled(busy).accessibilityIdentifier("support.reply.retry")
        }
    }
    private func load(append: Bool = false) async {
        do {
            pendingReply = try await client.pendingReply(for: ticket)
            deletionState = try await client.deletionStatus(ticket)
            if deletionState == "completed" { self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false; dismiss(); return }
            if deletionState == "pending" { self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false; error = nil; return }
            try await client.reconcilePendingReply(ticket)
            pendingReply = try await client.pendingReply(for: ticket)
            let result = try await client.conversation(ticket, after: append ? messages.last?.id ?? 0 : 0)
            conversation = result; messages = append ? messages + result.messages : result.messages
            if let last = messages.last { try await client.markRead(ticket, messageID: last.id) }
            error = nil
        } catch ReportTransportError.rejected(statusCode: 410) {
            self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false
            self.error = t("L’accès à cette conversation a été retiré ou la demande a été supprimée.", "Access to this conversation was revoked or the request was deleted.")
        } catch { self.error = t("Impossible de charger la conversation. Actualisez pour réessayer.", "Unable to load the conversation. Refresh to retry.") }
    }
    private func send() async {
        guard let conversation else { return }
        busy = true; defer { busy = false }
        do { try await client.reply(reply, to: ticket, version: conversation.version, clientMessageID: UUID()); reply = ""; await load() }
        catch ReportTransportError.rejected(statusCode: 410) {
            self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false
            self.error = t("L’accès à cette conversation a été retiré.", "Access to this conversation was revoked.")
        }
        catch { pendingReply = try? await client.pendingReply(for: ticket); self.error = t("Réponse non confirmée. Actualisez puis réessayez.", "Reply not confirmed. Refresh and retry.") }
    }
    private func retryReply() async {
        busy = true; defer { busy = false }
        do { try await client.retryPendingReply(ticket); reply = ""; await load() }
        catch ReportTransportError.rejected(statusCode: 410) {
            self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false
            self.error = t("L’accès à cette conversation a été retiré.", "Access to this conversation was revoked.")
        }
        catch { pendingReply = try? await client.pendingReply(for: ticket); self.error = t("Action non confirmée. Aucun nouvel identifiant n’a été créé.", "Action not confirmed. No new identifier was created.") }
    }
    private func changeState(_ state: String) async {
        guard let conversation else { return }
        busy = true; defer { busy = false }
        do { try await client.reply(state, to: ticket, version: conversation.version, clientMessageID: UUID(), kind: state); await load() }
        catch ReportTransportError.rejected(statusCode: 410) {
            self.conversation = nil; messages = []; reply = ""; pendingReply = nil; showingAssistant = false; showingDiagnostics = false
            self.error = t("L’accès à cette conversation a été retiré.", "Access to this conversation was revoked.")
        }
        catch { pendingReply = try? await client.pendingReply(for: ticket); self.error = t("Modification non confirmée. Actualisez.", "Change not confirmed. Please refresh.") }
    }
}

#endif
