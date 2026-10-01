import SwiftUI

/// A native support surface shared by all apps; conversations require no user account.
public struct FeedbackCenter: View {
    private let profile: FeedbackAppProfile
    @State private var client: FeedbackClient
    private let contextProvider: (any DiagnosticContextProvider)?
    @State private var diagnosticsEnabled = false
    @State private var tickets: [FeedbackTicket] = []
    @State private var unread: [String: Int] = [:]
    @State private var pending: [ReportEnvelope] = []
    @State private var showCompose = false
    @State private var error: String?
    public init(profile: FeedbackAppProfile, client: FeedbackClient? = nil, contextProvider: (any DiagnosticContextProvider)? = nil) {
        self.profile = profile; self._client = State(initialValue: client ?? FeedbackClient(profile: profile)); self.contextProvider = contextProvider
    }
    public var body: some View {
        List {
            Section {
                Button { showCompose = true } label: { Label(t("Nouvelle demande", "New request"), systemImage: "square.and.pencil") }
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
                        FeedbackConversationView(client: client, ticket: ticket)
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
            Section(t("Diagnostics facultatifs", "Optional diagnostics")) {
                Toggle(t("Partager les diagnostics techniques", "Share technical diagnostics"), isOn: Binding(
                    get: { diagnosticsEnabled }, set: { enabled in
                        Task { do { try await client.diagnostics.setEnabled(enabled); diagnosticsEnabled = enabled }
                        catch { self.error = t("Impossible de modifier ce réglage.", "Unable to change this setting.") } }
                    }))
                Text(t("Codes d’erreur, états techniques et version de l’app. Aucun contenu personnel ni capture. Envoi lorsque l’app est active, conservation 30 jours. Désactiver arrête les nouveaux envois et efface la file locale.", "Error codes, technical states and app version. No personal content or screenshots. Sent while the app is active, retained for 30 days. Disabling stops new uploads and clears the local queue."))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(t("Supprimer les diagnostics déjà envoyés", "Delete uploaded diagnostics"), role: .destructive) {
                    Task { do { try await client.diagnostics.deleteUploadedDiagnostics(); diagnosticsEnabled = false }
                    catch { diagnosticsEnabled = await client.diagnostics.isEnabled; self.error = t("Envois désactivés. Suppression distante non confirmée ; réessayez.", "Uploads disabled. Remote deletion not confirmed; retry.") } }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle(t("Aide et idées", "Help and ideas"))
        .task { await reload() }
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
                if provider != nil { Toggle(t("Joindre les codes de diagnostic", "Attach diagnostic codes"), isOn: $includeDiagnostics) }
                Text(t("N’incluez pas de mot de passe ni de contenu personnel.", "Do not include passwords or personal content.")).font(.footnote)
                Button(t("Vérifier avant l’envoi", "Review before sending")) { Task { await prepare() } }
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).count < 3 || description.count > 10000 || busy)
            }
            if busy { ProgressView() }
            if let error { Text(error).foregroundStyle(.red) }
        }
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
    @State private var conversation: FeedbackConversation?
    @State private var messages: [FeedbackMessage] = []
    @State private var reply = ""
    @State private var messageID = UUID()
    @State private var lastSubmittedReply: String?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDeletion = false
    @State private var deletionState: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List {
            if deletionState == "pending" {
                Section {
                    Text(t("Suppression en cours. Actualisez pour vérifier son achèvement.", "Deletion is pending. Refresh to confirm completion."))
                }
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
                    TextEditor(text: $reply).frame(minHeight: 100).disabled(busy).accessibilityLabel(t("Votre réponse", "Your reply"))
                    Button(t("Envoyer", "Send")) { Task { await send() } }
                        .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy || reply.count > 10000)
                    Button(conversation.state == "resolved" ? t("Rouvrir", "Reopen") : t("Problème résolu", "Problem resolved")) {
                        Task { await changeState(conversation.state == "resolved" ? "reopened" : "resolved") }
                    }.disabled(busy)
                }
                Button(t("Supprimer ma demande", "Delete my request"), role: .destructive) { confirmDeletion = true }
                    .disabled(deletionState == "pending")
            }
            if let error { Text(error).foregroundStyle(.red) }
            if busy { ProgressView() }
        }
        .navigationTitle(ticket.reference)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(t("Supprimer cette conversation ?", "Delete this conversation?"), isPresented: $confirmDeletion) {
            Button(t("Demander la suppression", "Request deletion"), role: .destructive) {
                Task {
                    do {
                        try await client.requestDeletion(ticket)
                        deletionState = "pending"
                        error = nil
                    } catch {
                        self.error = t("Suppression impossible. Réessayez.", "Deletion failed. Please retry.")
                    }
                }
            }
        }
    }
    private func load(append: Bool = false) async {
        do {
            deletionState = try await client.deletionStatus(ticket)
            if deletionState == "completed" { dismiss(); return }
            if deletionState == "pending" { error = nil; return }
            let result = try await client.conversation(ticket, after: append ? messages.last?.id ?? 0 : 0)
            conversation = result; messages = append ? messages + result.messages : result.messages
            if let last = messages.last { try await client.markRead(ticket, messageID: last.id) }
            error = nil
        } catch { self.error = t("Impossible de charger la conversation. Actualisez pour réessayer.", "Unable to load the conversation. Refresh to retry.") }
    }
    private func send() async {
        guard let conversation else { return }
        busy = true; defer { busy = false }
        if lastSubmittedReply != reply { messageID = UUID(); lastSubmittedReply = reply }
        do { try await client.reply(reply, to: ticket, version: conversation.version, clientMessageID: messageID); reply = ""; messageID = UUID(); await load() }
        catch { self.error = t("Réponse non confirmée. Actualisez puis réessayez.", "Reply not confirmed. Refresh and retry.") }
    }
    private func changeState(_ state: String) async {
        guard let conversation else { return }
        busy = true; defer { busy = false }
        do { try await client.reply(state, to: ticket, version: conversation.version, clientMessageID: UUID(), kind: state); await load() }
        catch { self.error = t("Modification non confirmée. Actualisez.", "Change not confirmed. Please refresh.") }
    }
}
