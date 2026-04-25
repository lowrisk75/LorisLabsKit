import SwiftUI

/// Drop-in cross-promotion list, intended for Settings → "More from LorisLabs" sections.
/// Tapping a row opens the App Store sheet via `SKOverlay` (in-app, no Safari bounce).
///
/// Usage:
/// ```swift
/// Section("More from LorisLabs") {
///     MoreFromLorisLabsView(currentBundleIdentifier: Bundle.main.bundleIdentifier!)
/// }
/// ```
public struct MoreFromLorisLabsView: View {
    private let apps: [LorisLabsApp]

    public init(currentBundleIdentifier: String) {
        self.apps = LorisLabsApp.othersThan(currentBundleIdentifier)
    }

    public init(apps: [LorisLabsApp]) {
        self.apps = apps
    }

    public var body: some View {
        ForEach(apps) { app in
            LorisLabsAppRow(app: app)
        }
    }
}

private struct LorisLabsAppRow: View {
    let app: LorisLabsApp
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            openURL(app.itmsURL)
        } label: {
            HStack(spacing: 12) {
                AppIconPlaceholder(initials: initials(for: app.name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(app.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ")
        return words.prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

private struct AppIconPlaceholder: View {
    let initials: String
    var body: some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(.tint)
            .frame(width: 36, height: 36)
            .overlay(
                Text(initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            )
    }
}

#Preview {
    Form {
        Section("More from LorisLabs") {
            MoreFromLorisLabsView(currentBundleIdentifier: "com.lorislab.lumenforfrigate.Lumen-for-Frigate")
        }
    }
}
