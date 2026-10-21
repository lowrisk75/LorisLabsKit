import SwiftUI

private func supportText(_ fr: String, _ en: String) -> String {
    Locale.current.language.languageCode?.identifier == "fr" ? fr : en
}

struct SupportJournalSettings: View {
    let client: FeedbackClient
    @State private var enabled = false
    @State private var error = false
    var body: some View {
        Section(supportText("Diagnostic local", "Local diagnostics")) {
            if client.features.diagnostics {
                Toggle(supportText("Conserver un journal technique local", "Keep a local technical journal"), isOn: Binding(
                    get: { enabled }, set: { value in
                        Task {
                            do { try await client.journal.setEnabled(value); enabled = value; self.error = false }
                            catch { enabled = await client.journal.isEnabled; self.error = true }
                        }
                    }))
                Text(supportText("24 heures, 1 000 événements maximum. Aucun envoi automatique. Vous choisissez les événements et confirmez chaque partage. Désactiver efface le journal local.",
                    "24 hours, at most 1,000 events. No automatic upload. You select events and confirm each delivery. Disabling erases the local journal."))
                    .font(.footnote)
                if error { Text(supportText("Le réglage n’a pas été entièrement appliqué. Réessayez.", "The setting was not fully applied. Retry.")) }
            } else {
                Text(supportText("La collecte technique n’est pas active dans cette version.", "Technical collection is inactive in this build."))
            }
        }.task { enabled = await client.journal.isEnabled }
    }
}

struct SupportAssistantView: View {
    let client: FeedbackClient
    @Binding var draft: String
    @Environment(\.dismiss) private var dismiss
    @State private var response: SupportAssistantReply?
    @State private var answer = ""
    @State private var work = ""
    @State private var turns = 0
    @State private var busy = false
    @State private var task: Task<Void, Never>?
    private let assistant = SupportAssistant()
    private var reviewDraft: String {
        let base = work.isEmpty ? draft : work
        let addition = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        return base + (addition.isEmpty ? "" : "\n" + addition)
    }
    var body: some View {
        NavigationStack {
            Form {
                Text(supportText("Assistant sur votre appareil. Aucun envoi ; les hypothèses restent à confirmer.", "Assistant on your device. Nothing is sent; hypotheses remain unconfirmed."))
                if let response {
                    Text(response.usedLocalModel ? supportText("Modèle local Apple", "Apple local model") : supportText("Parcours guidé", "Guided questionnaire")).font(.caption)
                    Text(response.question)
                    if !response.hypothesis.isEmpty { Text(response.hypothesis).foregroundStyle(.secondary) }
                    Text(supportText("Événements observés : ", "Observed events: ")+String(response.citedEventIDs.count)).font(.caption)
                }
                TextEditor(text: $answer).frame(minHeight: 100).accessibilityLabel(supportText("Votre précision", "Your clarification"))
                Button(supportText("Préciser le problème", "Refine the problem")) { next() }
                    .disabled(busy || turns >= (response?.usedLocalModel == false ? 3 : 6) || answer.count > 4000 || reviewDraft.count > 10000)
                if busy { ProgressView() }
                Button(supportText("Reprendre ce brouillon pour le relire", "Use this draft for review")) {
                    draft = reviewDraft; dismiss()
                }.disabled(busy || reviewDraft.count > 10000)
                if reviewDraft.count > 10000 {
                    Text(supportText("Raccourcissez le brouillon à 10 000 caractères avant de continuer.", "Shorten the draft to 10,000 characters before continuing."))
                }
            }
            .navigationTitle(supportText("Affiner la demande", "Refine your request"))
            .toolbar { Button(supportText("Fermer", "Close")) { task?.cancel(); dismiss() } }
            .onDisappear { task?.cancel() }
            .task { if work.isEmpty { work = draft; next() } }
        }
    }
    private func next() {
        guard !busy, turns < 6 else { return }
        let addition = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !addition.isEmpty { work += "\n"+addition; answer = "" }
        busy = true
        task = Task {
            defer { busy = false }
            let events = (try? await client.journal.snapshot()) ?? []
            guard !Task.isCancelled else { return }
            if let reply = try? await assistant.respond(description: work, evidence: events), !Task.isCancelled {
                if reply.usedLocalModel { response = reply } else {
                    let questions = [supportText("Quel résultat attendiez-vous à la place ?", "What did you expect instead?"),
                        supportText("Le problème se produit-il à chaque tentative ?", "Does it happen on every attempt?"),
                        supportText("Quelle action permet de reproduire le problème ?", "Which action reproduces the problem?")]
                    response = SupportAssistantReply(question: questions[min(turns, questions.count-1)], hypothesis: reply.hypothesis, citedEventIDs: reply.citedEventIDs)
                }
                turns += 1
            }
        }
    }
}

struct SupportDiagnosticReview: View {
    let client: FeedbackClient
    let ticket: FeedbackTicket
    @Environment(\.dismiss) private var dismiss
    @State private var events: [SupportDiagnosticEvent] = []
    @State private var selection: Set<UUID> = []
    @State private var confirmed = false
    @State private var busy = false
    @State private var error: String?
    @State private var reviewed: SupportDiagnosticBundle?
    @State private var hours = 24
    @State private var component = "all"
    private var filtered: [SupportDiagnosticEvent] {
        events.filter { (component == "all" || $0.component.rawValue == component)
            && $0.occurredAt >= Date().addingTimeInterval(-Double(hours)*3600) }
    }
    var body: some View {
        NavigationStack {
            List {
                Text(supportText("Choisissez les événements pertinents. Aucun texte métier ni secret ne doit être présent. Partage volontaire, conservation serveur maximale de 30 jours et suppression avec la demande.",
                    "Select relevant events. No business content or secrets may be present. Voluntary sharing, up to 30 days server retention, erased with your request."))
                if events.isEmpty { Text(supportText("Aucun événement local disponible.", "No local event is available.")) }
                Picker(supportText("Période", "Period"), selection: $hours) {
                    Text(supportText("1 heure", "1 hour")).tag(1)
                    Text(supportText("6 heures", "6 hours")).tag(6)
                    Text(supportText("24 heures", "24 hours")).tag(24)
                }.disabled(busy || reviewed != nil)
                Picker(supportText("Composant", "Component"), selection: $component) {
                    Text(supportText("Tous", "All")).tag("all")
                    ForEach(SupportDiagnosticPolicy.components(appID: client.profile.appID).sorted { $0.rawValue < $1.rawValue }, id: \.rawValue) { value in
                        Text(value.rawValue).tag(value.rawValue)
                    }
                }.disabled(busy || reviewed != nil)
                ForEach(filtered) { event in
                    Toggle(isOn: Binding(get: { selection.contains(event.id) }, set: { value in
                        if value { selection.insert(event.id) } else { selection.remove(event.id) }
                        confirmed = false; reviewed = nil
                    })) {
                        VStack(alignment: .leading) {
                            Text("\(event.component.rawValue) · \(event.operation.rawValue) · \(event.outcome.rawValue)")
                            Text("\(event.occurredAt.formatted()) · \(event.durationMilliseconds) ms · \(event.attemptCount)").font(.caption)
                        }
                    }.disabled(busy || reviewed != nil)
                }
                Button(supportText("Vérifier cette sélection", "Review this selection")) {
                    reviewed = try? SupportDiagnosticBundle(appID: client.profile.appID, reviewedEvents: events.filter { selection.contains($0.id) })
                    confirmed = false
                }.disabled(selection.isEmpty || busy)
                if let reviewed {
                    Text(supportText("Cette sélection exacte contient ", "This exact selection contains ")+String(reviewed.events.count)+supportText(" événements.", " events."))
                    Toggle(supportText("J’ai relu et j’autorise cet envoi", "I reviewed and authorize this delivery"), isOn: $confirmed).disabled(busy)
                    Button(supportText("Confirmer et joindre", "Confirm and attach")) {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await client.submitReviewedDiagnostics(reviewed, to: ticket); dismiss() }
                            catch { self.error = supportText("Envoi non confirmé. La sélection consentie peut être réessayée depuis l’aide.", "Delivery unconfirmed. Retry the consented selection from Help.") }
                        }
                    }.disabled(!confirmed || busy)
                    Button(supportText("Modifier la sélection", "Edit selection")) { self.reviewed = nil; confirmed = false }.disabled(busy)
                }
                if let error { Text(error).foregroundStyle(.red) }
                if busy { ProgressView() }
            }
            .onChange(of: hours) { _, _ in selection = []; confirmed = false; reviewed = nil }
            .onChange(of: component) { _, _ in selection = []; confirmed = false; reviewed = nil }
            .navigationTitle(supportText("Diagnostic de la demande", "Request diagnostics"))
            .toolbar { Button(supportText("Fermer", "Close")) { dismiss() }.disabled(busy) }
            .task {
                events = Array(((try? await client.journal.snapshot()) ?? []).suffix(150))
                selection = Set(events.map(\.id))
            }
        }
    }
}
