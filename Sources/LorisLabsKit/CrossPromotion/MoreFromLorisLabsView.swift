import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Rows for an existing List/Form. Uses local official icons, with no tracking or network fetch.
public struct MoreFromLorisLabsView: View {
    private let apps: [LorisLabsApp]
    public init(currentBundleIdentifier: String) { apps = LorisLabsApp.othersThan(currentBundleIdentifier) }
    public init(apps: [LorisLabsApp]) { self.apps = apps }
    public var body: some View {
        ForEach(apps) { LorisLabsAppRow(app: $0) }
    }
}

private struct LorisLabsAppRow: View {
    let app: LorisLabsApp
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconSize = 44.0

    var body: some View {
        Link(destination: app.appStoreURL) {
            HStack(alignment: .center, spacing: 12) {
                Group {
                    if let icon = PortfolioIconCache.image(for: app) {
                        icon.resizable().scaledToFit()
                    } else {
                        Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                    }
                }
                .frame(width: min(iconSize, 72), height: min(iconSize, 72))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.localizedName(locale: locale)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(app.localizedTagline(locale: locale)).font(.subheadline).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the App Store", bundle: .module))
        .accessibilityIdentifier("lorislabs.app.\(app.ascAppId)")
    }
}

/// Full destination for a Settings menu or sheet. The current app is always excluded.
public struct LorisLabsAppsMenu: View {
    private let currentBundleIdentifier: String
    public init(currentBundleIdentifier: String) { self.currentBundleIdentifier = currentBundleIdentifier }
    public var body: some View {
        List {
            Section {
                MoreFromLorisLabsView(currentBundleIdentifier: currentBundleIdentifier)
            } header: {
                Text("Made by LorisLabs", bundle: .module)
            } footer: {
                Text("Availability and supported devices are shown on the App Store.", bundle: .module)
            }
        }
        .navigationTitle(Text("More from LorisLabs", bundle: .module))
        .accessibilityIdentifier("lorislabs.apps.menu")
    }
}

/// Place inside an existing NavigationStack in Settings.
public struct LorisLabsAppsLink: View {
    private let currentBundleIdentifier: String
    public init(currentBundleIdentifier: String) { self.currentBundleIdentifier = currentBundleIdentifier }
    public var body: some View {
        NavigationLink {
            LorisLabsAppsMenu(currentBundleIdentifier: currentBundleIdentifier)
        } label: {
            Label { Text("More from LorisLabs", bundle: .module) } icon: { Image(systemName: "square.grid.2x2") }
        }
        .accessibilityIdentifier("lorislabs.apps.open")
    }
}

@MainActor
private enum PortfolioIconCache {
    private static var images: [String: Image] = [:]
    static func image(for app: LorisLabsApp) -> Image? {
        if let image = images[app.ascAppId] { return image }
        guard let url = app.iconURL else { return nil }
        #if canImport(UIKit)
        guard let native = UIImage(contentsOfFile: url.path) else { return nil }
        let image = Image(uiImage: native)
        #elseif canImport(AppKit)
        guard let native = NSImage(contentsOf: url) else { return nil }
        let image = Image(nsImage: native)
        #else
        return nil
        #endif
        #if canImport(UIKit) || canImport(AppKit)
        images[app.ascAppId] = image
        return image
        #endif
    }
}
