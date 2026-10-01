import SwiftUI

/// Final consent gate for direct delivery. Merely presenting this view performs no network request.
public struct ReportConsentReviewView: View {
    private let envelope: ReportEnvelope
    private let transport: any ReportTransport
    private let theme: any BugReportTheme
    private let onAccepted: (@Sendable (ReportDeliveryReceipt) -> Void)?

    @State private var selectedCategories: Set<ReportDataCategory>
    @State private var isSubmitting = false
    @State private var receipt: ReportDeliveryReceipt?
    @State private var errorMessage: String?

    public init(
        envelope: ReportEnvelope,
        transport: any ReportTransport,
        theme: any BugReportTheme = DefaultBugReportTheme(),
        onAccepted: (@Sendable (ReportDeliveryReceipt) -> Void)? = nil
    ) {
        self.envelope = envelope
        self.transport = transport
        self.theme = theme
        self.onAccepted = onAccepted
        _selectedCategories = State(initialValue: envelope.consent.categories)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HeaderCard(
                    icon: "checkmark.shield.fill",
                    title: String(localized: "Review before sending", bundle: .module),
                    subtitle: String(localized: "Nothing is sent until you confirm. Optional data can be removed below.", bundle: .module),
                    theme: theme
                )

                ThemedCard(theme: theme) {
                    VStack(alignment: .leading, spacing: 10) {
                        consentRow(.userDescription, mandatory: true)
                        consentRow(.appMetadata, mandatory: true)
                        consentRow(.deviceMetadata, mandatory: true)
                        ForEach(optionalCategories, id: \.self) { category in
                            consentRow(category, mandatory: false)
                        }
                    }
                }

                if !envelope.artifacts.isEmpty {
                    ThemedCard(theme: theme) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diagnostic files")
                                .font(theme.headlineFont)
                            ForEach(envelope.artifacts) { artifact in
                                HStack {
                                    Image(systemName: selectedCategories.contains(artifact.category) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(theme.accent)
                                    VStack(alignment: .leading) {
                                        Text(artifact.filename).font(theme.calloutFont)
                                        Text("\(artifact.mediaType) · \(artifact.sizeBytes) bytes · max \(artifact.retentionDays) days")
                                            .font(theme.caption2Font)
                                            .foregroundStyle(theme.textTertiary)
                                    }
                                }
                            }
                        }
                    }
                }

                if let receipt {
                    ThemedCard(theme: theme) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Report received", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(theme.success)
                            Text(receipt.publicReference).font(.system(.body, design: .monospaced))
                            Text("Keep this reference to follow up or request deletion.")
                                .font(theme.captionFont).foregroundStyle(theme.textSecondary)
                        }
                    }
                } else {
                    if let errorMessage {
                        Text(errorMessage).font(theme.captionFont).foregroundStyle(theme.destructive)
                    }
                    PrimaryButton(
                        label: isSubmitting ? String(localized: "Sending…", bundle: .module) : String(localized: "Confirm and Send", bundle: .module),
                        icon: "paperplane.fill",
                        theme: theme
                    ) {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("Report Preview")
    }

    private var optionalCategories: [ReportDataCategory] {
        ReportDataCategory.allCases.filter {
            ![.userDescription, .appMetadata, .deviceMetadata].contains($0)
                && envelope.consent.categories.contains($0)
        }
    }

    @ViewBuilder
    private func consentRow(_ category: ReportDataCategory, mandatory: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { selectedCategories.contains(category) },
            set: { enabled in
                guard !mandatory else { return }
                if enabled { selectedCategories.insert(category) }
                else { selectedCategories.remove(category) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.label).font(theme.calloutFont)
                if mandatory {
                    Text("Required to understand this report")
                        .font(theme.caption2Font).foregroundStyle(theme.textTertiary)
                }
            }
        }
        .disabled(mandatory)
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let selected = try envelope.selecting(categories: selectedCategories)
            let accepted = try await transport.submit(selected)
            await MainActor.run {
                receipt = accepted
                isSubmitting = false
                onAccepted?(accepted)
            }
        } catch {
            await MainActor.run {
                errorMessage = String(localized: "The report could not be sent. You can retry without losing it.", bundle: .module)
                isSubmitting = false
            }
        }
    }
}

private extension ReportDataCategory {
    var label: String {
        switch self {
        case .userDescription: "Description and reproduction steps"
        case .appMetadata: "App version and build"
        case .deviceMetadata: "Device model and OS version"
        case .connectionLogs: "Redacted connection logs"
        case .systemDiagnostics: "Crash and system diagnostics"
        case .screenshot: "Screenshots selected for this report"
        case .contactEmail: "Email address for follow-up"
        case .remoteAI: "Structured analysis by remote AI"
        }
    }
}
