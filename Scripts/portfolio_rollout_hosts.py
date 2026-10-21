from pathlib import Path
import shutil

def replace(path,before,after,count=1):
 s=path.read_text();assert s.count(before)==count,(str(path),before[:90],s.count(before));path.write_text(s.replace(before,after))

def prepare_404(candidate,source):
 shutil.copy2(source/'Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift',candidate/'Packages/LorisLabsKit/Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift')
 pbx=candidate/'404.xcodeproj/project.pbxproj'
 replace(pbx,'/* Begin PBXBuildFile section */','/* Begin PBXBuildFile section */\n\t\tE60000000000000000000001 /* LorisLabsKit in Frameworks */ = {isa = PBXBuildFile; productRef = E60000000000000000000002 /* LorisLabsKit */; };')
 replace(pbx,'\t\t\t\t79F13EC183B89971E44A4FFA /* LorisReports in Frameworks */,','\t\t\t\t79F13EC183B89971E44A4FFA /* LorisReports in Frameworks */,\n\t\t\t\tE60000000000000000000001 /* LorisLabsKit in Frameworks */,')
 replace(pbx,'\t\t\t\t292326B31222E4984921893E /* LorisReports */,','\t\t\t\t292326B31222E4984921893E /* LorisReports */,\n\t\t\t\tE60000000000000000000002 /* LorisLabsKit */,')
 replace(pbx,'/* Begin XCSwiftPackageProductDependency section */','/* Begin XCSwiftPackageProductDependency section */\n\t\tE60000000000000000000002 /* LorisLabsKit */ = {isa = XCSwiftPackageProductDependency; package = 294A3AD48CD8CDF315389A69; productName = LorisLabsKit; };')
 app=candidate/'404/_04App.swift';replace(app,'    init() {','    init() {\n        _ = ReviewPromptPolicy.reviews')
 model=candidate/'404/Discovery/DiscoveryViewModel.swift';s=model.read_text().replace('import Foundation','import Foundation\nimport LorisLabsKit',1)
 before='''            if !devices.isEmpty && error == nil {
                ReviewPromptPolicy.recordSuccessfulScan()
                completedScanCount += 1
            }''';assert before in s;s=s.replace(before,'''            ReviewPromptPolicy.reviews.recordCompletedAction()
            completedScanCount += 1''')
 start=s.index('/// When 404 may ask for an App Store review:');s=s[:start]+'''/// Shared conservative policy; legacy attempts retain a full cooldown after migration.
@MainActor
enum ReviewPromptPolicy {
    static let reviews = makeManager()
    static func makeManager(defaults: UserDefaults = .standard, now: Date = Date()) -> SmartReviewPromptManager {
        let previous = defaults.string(forKey: "reviewPrompt.lastPromptedVersion").map {
            ReviewAttempt(version: $0, date: now)
        }
        return SmartReviewPromptManager(userDefaults: defaults, bundleIdentifier: "com.lorislab.app404", previousAttempt: previous)
    }
}
''';model.write_text(s)
 view=candidate/'404/Discovery/DiscoveryView.swift';s=view.read_text().replace('import StoreKit','import LorisLabsKit',1).replace('    @Environment(\\.requestReview) var requestReview\n','')
 modifier='''            .reviewPromptWhenIdle(ReviewPromptPolicy.reviews,
                isIdle: !viewModel.isScanning && viewModel.selectedDevice == nil && !isSelectMode
                    && searchText.isEmpty && !showUpgradeSheet && !showImportSheet && !showHealthPopover
                    && !isLoadingHealth && !showComparison && !showSnapshotSelector && !showSensorSheet && !showFilterSheet)'''
 s=s.replace('            .onChange(of: viewModel.completedScanCount) { askForReviewIfEarned() }',modifier).replace('        .onChange(of: viewModel.completedScanCount) { askForReviewIfEarned() }',modifier)
 start=s.index('    private func askForReviewIfEarned()');end=s.index('\n}',start);s=s[:start]+s[end:];view.write_text(s)
 for r in ['404/Settings/AppSettingsView.swift','404/Settings/Tabs/AboutSettingsTab.swift']:
  p=candidate/r;replace(p,'import LorisReports','import LorisReports\nimport LorisLabsKit');replace(p,'                Link(destination: SupportLinks.documentation) {','                LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.app404")\n\n                Link(destination: SupportLinks.documentation) {')
 tests=candidate/'404Tests/ReviewPromptPolicyTests.swift';tests.write_text('''import Foundation
import Testing
@testable import _04

@MainActor @Suite("Conservative review migration")
struct ReviewPromptPolicyTests {
    @Test func oldCountsCannotPromptAtLaunch() {
        let suite = "review-migration-\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(900, forKey: "reviewPrompt.successfulScans")
        let manager = ReviewPromptPolicy.makeManager(defaults: defaults)
        for _ in 0..<10 { manager.recordCompletedAction() }
        #expect(!manager.shouldPromptNow)
    }
    @Test func legacyAttemptIsPreservedConservatively() {
        let suite = "review-attempt-\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set("1.0", forKey: "reviewPrompt.lastPromptedVersion")
        _ = ReviewPromptPolicy.makeManager(defaults: defaults, now: date)
        #expect(defaults.object(forKey: "lorislabskit.review.lastPromptDate") as? Date == date)
        #expect(defaults.string(forKey: "lorislabskit.review.promptedForVersion") == "1.0")
    }
}
''')
 return ['404.xcodeproj/project.pbxproj','404/_04App.swift','404/Discovery/DiscoveryViewModel.swift','404/Discovery/DiscoveryView.swift','404/Settings/AppSettingsView.swift','404/Settings/Tabs/AboutSettingsTab.swift','404Tests/ReviewPromptPolicyTests.swift']

def prepare_kiosk(candidate,freeze):
 import re,subprocess
 freeze(candidate,'Packages/LorisLabsKit',['LorisLabsKit'])
 yml=candidate/'project.yml';s=yml.read_text();s=s.replace('packages:\n','packages:\n  LorisLabsKit:\n    path: Packages/LorisLabsKit\n',1)
 for target in ['KioskTV','KioskDisplay','KioskDisplayMac','KioskBridge','KioskBridgeQA','KioskAdmin']:
  start=s.index('\n  '+target+':',s.index('targets:'));m=re.search(r'\n  \w+:',s[start+1:]);end=start+1+m.start() if m else len(s)
  section=s[start:end];assert '    dependencies:\n' in section;section=section.replace('    dependencies:\n','    dependencies:\n      - package: LorisLabsKit\n        product: LorisLabsKit\n',1);s=s[:start]+section+s[end:]
 yml.write_text(s)
 for rel,needle in [('Apps/KioskAdmin/AdminDashboardView.swift','            if showsHelpAndSupport {'),('Apps/KioskBridge/BridgeAdminView.swift','        Section("Meeting titles") {')]:
  p=candidate/rel;s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
  s=s.replace('    @Bindable var model:', '    @State private var showsOtherApps = false\n    @Environment(\\.locale) private var portfolioLocale\n    @Bindable var model:',1)
  button='''            Button { showsOtherApps = true } label: {
                Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("meetglow.apps.open")
'''
  if 'AdminDashboard' in rel:s=s.replace(needle,button+needle,1)
  else:s=s.replace(needle,'''        Section {
'''+button+'''        }
'''+needle,1)
  anchor='        .tint(Color.administrationAccent)' if 'AdminDashboard' in rel else '            .navigationTitle(selection?.title ?? "Meetglow")'
  assert anchor in s;s=s.replace(anchor,anchor+'''
        .sheet(isPresented: $showsOtherApps) {
            NavigationStack {
                LorisLabsAppsMenu(currentBundleIdentifier: "com.kevinnadjarian.kiosk")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { showsOtherApps = false }
                    } }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
        }''',1);p.write_text(s)
 p=candidate/'Apps/KioskTV/Overlays/DisplayMenuView.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1).replace('    @Bindable var model:','    @State private var showsOtherApps = false\n    @Environment(\\.locale) private var portfolioLocale\n    @Bindable var model:',1)
 anchor='            if let notice = model.pairingNotice {';assert anchor in s;s=s.replace(anchor,'''            Button { showsOtherApps = true } label: {
                Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
            }
            .displayFont(.bodyEmphasis)
            .accessibilityIdentifier("tv.menu.apps")
'''+anchor,1)
 anchor='        .task { await model.refreshEnrollmentState() }';assert anchor in s;s=s.replace(anchor,anchor+'''
        .sheet(isPresented: $showsOtherApps) {
            #if os(tvOS)
            KioskPortfolioTVView { showsOtherApps = false }
            #else
            NavigationStack {
                LorisLabsAppsMenu(currentBundleIdentifier: "com.kevinnadjarian.kiosk")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { showsOtherApps = false }
                    } }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
            #endif
        }''',1)
 s+='''
#if os(tvOS)
/// App Store destinations are handed to a phone, without leaving the managed display.
private struct KioskPortfolioTVView: View {
    let close: () -> Void
    @Environment(\\.locale) private var locale
    @State private var selected: LorisLabsApp?
    var body: some View {
        NavigationStack {
            List {
                ForEach(LorisLabsApp.othersThan("com.kevinnadjarian.kiosk")) { app in
                    Button { selected = app } label: {
                        HStack(spacing: 24) {
                            if let url = app.bundledIconURL, let icon = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: icon).resizable().scaledToFit().frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true)
                            }
                            VStack(alignment: .leading) {
                                Text(app.localizedName(locale: locale))
                                Text(app.localizedTagline(locale: locale)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Close", action: close)
            }
            .navigationTitle(PortfolioText.title(locale: locale))
        }
        .sheet(item: $selected) { app in
            KioskOverlay {
                Text(app.localizedName(locale: locale)).displayFont(.hero)
                KioskQRCodeView(url: app.appStoreURL)
                Text(verbatim: app.appStoreURL.absoluteString).displayFont(.code)
                Text("Scan this code with your phone, or type the address in a browser.").displayFont(.body)
                Button("Close") { selected = nil }
            }
        }
    }
}
#endif
''';p.write_text(s)
 result=subprocess.run(['xcodegen','generate'],cwd=candidate,capture_output=True,text=True);assert result.returncode==0,result.stderr
 return ['project.yml','Kiosk.xcodeproj/project.pbxproj','Apps/KioskAdmin/AdminDashboardView.swift','Apps/KioskBridge/BridgeAdminView.swift','Apps/KioskTV/Overlays/DisplayMenuView.swift','Packages/LorisLabsKit']

def prepare_velya(candidate,freeze):
 import subprocess
 freeze(candidate,'Packages/LorisLabsKit',['LorisLabsKit'])
 yml=candidate/'project.yml';s=yml.read_text().replace('packages:\n','packages:\n  LorisLabsKit:\n    path: Packages/LorisLabsKit\n',1)
 needle='    dependencies:\n      - package: VelyaFeedbackSDK';assert needle in s;s=s.replace(needle,'    dependencies:\n      - package: LorisLabsKit\n        product: LorisLabsKit\n      - package: VelyaFeedbackSDK',1);yml.write_text(s)
 p=candidate/'Velya/AppRating.swift';s=p.read_text();end=s.index('/// One-shot, value-first commercial prompt.')
 s='''import Foundation
import LorisLabsKit

/// Local usage only. Native requests are deferred to an idle Insights screen.
@MainActor
enum AppRating {
    nonisolated static let wakeCountKey = "velya_rating_wakeCount"
    static let reviews = makeReviewManager()
    static func makeReviewManager(defaults: UserDefaults = .standard, now: Date = Date()) -> SmartReviewPromptManager {
        let previous = defaults.string(forKey: "velya_rating_promptedVersion").map { ReviewAttempt(version: $0, date: now) }
        return SmartReviewPromptManager(userDefaults: defaults, bundleIdentifier: "com.lorislab.velya", previousAttempt: previous)
    }
    static func recordSuccessfulWake() {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: wakeCountKey) + 1, forKey: wakeCountKey)
        reviews.recordCompletedAction()
    }
    nonisolated static var successfulWakeCount: Int { UserDefaults.standard.integer(forKey: wakeCountKey) }
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6774200791?action=write-review")!
}

'''+s[end:];p.write_text(s)
 p=candidate/'Velya/VelyaApp.swift';replace(p,'    init() {','    init() {\n        _ = AppRating.reviews')
 p=candidate/'Velya/ContentView.swift';s=p.read_text().replace('import StoreKit','import StoreKit\nimport LorisLabsKit',1).replace('    @Environment(\\.requestReview) private var requestReview\n','')
 before='''            } else if phase == .active, AppRating.shouldPrompt {
                // Avoid stacking the rating prompt on top of the value-first Pro sheet.
                AppRating.markPrompted()
                requestReview()
            }''';assert before in s;s=s.replace(before,'            }')
 needle='                InsightsView(sleepTracker: sleepTracker)';assert needle in s;s=s.replace(needle,needle+'''
                    .reviewPromptWhenIdle(AppRating.reviews,
                        isIdle: selectedTab == 1 && !showPaywall && !showingWidgetSettings && !confirmingAwake
                            && !processingControlRequests && wakeMood.pendingAlarmID == nil && notificationCard.pending == nil
                            && VelyaLaunchPolicy.allowsRuntimeSideEffects(isAutomation: VelyaApp.isAutomation),
                        additionalEligibility: {
                            UIApplication.shared.applicationState == .active && UIApplication.shared.connectedScenes
                                .compactMap { $0 as? UIWindowScene }.flatMap(\\.windows)
                                .allSatisfy { $0.rootViewController?.presentedViewController == nil }
                        })''',1)
 needle='                navRow("book.fill", String(localized: "Guide & Privacy")) { GuidePrivacyView() }';assert needle in s;s=s.replace(needle,'''                navRow("square.grid.2x2", PortfolioText.title()) {
                    LorisLabsAppsMenu(currentBundleIdentifier: "com.lorislab.velya")
                }
                .accessibilityIdentifier("velya.settings.apps")
                hairline
'''+needle,1);p.write_text(s)
 subprocess.run(['xcodegen','generate'],cwd=candidate,check=True,capture_output=True)
 return ['project.yml','Velya.xcodeproj/project.pbxproj','Velya/AppRating.swift','Velya/VelyaApp.swift','Velya/ContentView.swift','Packages/LorisLabsKit']

def add_package_dependencies(candidate,targets,freeze):
 import re
 freeze(candidate,'Packages/LorisLabsKit',['LorisLabsKit','LorisReports'])
 p=candidate/'project.yml';s=p.read_text()
 package='  LorisLabsKit:\n    path: Packages/LorisLabsKit\n'
 if 'packages:\n' in s:s=s.replace('packages:\n','packages:\n'+package,1)
 else:s=s.replace('targets:\n','packages:\n'+package+'\ntargets:\n',1)
 for target in targets:
  start=s.index('\n  '+target+':',s.index('targets:'));m=re.search(r'\n  [A-Za-z]\w*[-\w]*:',s[start+1:]);end=start+1+m.start() if m else len(s)
  section=s[start:end];deps='    dependencies:\n      - package: LorisLabsKit\n        product: LorisLabsKit\n      - package: LorisLabsKit\n        product: LorisReports\n'
  if '    dependencies:\n' in section:section=section.replace('    dependencies:\n',deps,1)
  else:section=section.rstrip()+'\n'+deps
  s=s[:start]+section+s[end:]
 p.write_text(s)

def write_help(candidate,folder,appID,name,bundle):
 p=candidate/folder/'PortfolioHelpView.swift';assert not p.exists()
 p.write_text('''import SwiftUI
import LorisLabsKit
import LorisReports

/// No automatic context, diagnostic journal, background flush or permission request.
struct PortfolioHelpView: View {
    @Environment(\\.locale) private var locale
    private var french: Bool { locale.language.languageCode?.identifier == "fr" }
    private var messagingEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LorisReportsBackendAllowed") as? Bool == true
            && Bundle.main.object(forInfoDictionaryKey: "LorisReportsMessagingVerified") as? Bool == true
    }
    var body: some View {
        List {
            Section {
                if messagingEnabled {
                    NavigationLink {
                        FeedbackMigrationCenter(profile: .init(appID: "APP_ID", displayName: "APP_NAME", allowedFields: [])) {
                            Link(french ? "Contacter par e-mail" : "Contact by email", destination: URL(string: "mailto:support@lorislab.fr")!)
                        }
                    } label: {
                        Label(french ? "Retours, bugs et idées" : "Feedback, bugs and ideas", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                Link(french ? "Contacter par e-mail" : "Contact by email", destination: URL(string: "mailto:support@lorislab.fr")!)
                Link(french ? "Site LorisLabs" : "LorisLabs website", destination: URL(string: "https://lorislab.fr")!)
            } header: { Text(french ? "Assistance" : "Support") }
            Section { LorisLabsAppsLink(currentBundleIdentifier: "BUNDLE_ID") }
        }
        .navigationTitle(french ? "Aide" : "Help")
    }
}
'''.replace('APP_ID',appID).replace('APP_NAME',name).replace('BUNDLE_ID',bundle))
 return str(p.relative_to(candidate))

def help_sheet(s,anchor):
 assert anchor in s
 sheet='''
        .sheet(isPresented: $showsPortfolioHelp) {
            NavigationStack {
                PortfolioHelpView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button(portfolioLocale.language.languageCode?.identifier == "fr" ? "Fermer" : "Close") { showsPortfolioHelp = false }
                    } }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 540)
            #endif
        }'''
 return s.replace(anchor,anchor+sheet,1)

def prepare_new(candidate,key,freeze):
 import subprocess
 configs={
 'kalou':(['Kalou'],'Sources/Nimo','kalou','Kalou','com.lorislab.kalou','Sources/Nimo/Settings/SettingsView.swift'),
 'rampart':(['Rampart'],'App','rampart','Rampart','com.lorislab.rampart','App/Settings/SettingsView.swift'),
 'halte':(['Halte'],'Halte','halte','Halte','com.lorislab.halte','Halte/Library/LibraryView.swift'),
 'mela':(['Mela'],'Mela','mela','Mela','com.lorislab.mela','Mela/Views/ParentToolsView.swift'),
 'aegis':(['Aegis-iOS','Aegis-macOS'],'Aegis','aegis','Aegis','com.lorislab.aegis','Aegis/Views/SettingsView.swift')}
 targets,folder,appID,name,bundle,view=configs[key];add_package_dependencies(candidate,targets,freeze)
 help=write_help(candidate,folder,appID,name,bundle);p=candidate/view;s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
 s=s.replace('    var body: some View {','    @State private var showsPortfolioHelp = false\n    @Environment(\\.locale) private var portfolioLocale\n\n    var body: some View {',1) if key!='aegis' else s.replace('  var body: some View {','  @State private var showsPortfolioHelp = false\n  @Environment(\\.locale) private var portfolioLocale\n\n  var body: some View {',1)
 if key=='kalou':
  anchor='                section("À propos") {';assert anchor in s;s=s.replace(anchor,anchor+'''
                    Button { showsPortfolioHelp = true } label: {
                        row(icon: "square.grid.2x2", tint: Palette.secondary, title: PortfolioText.title(locale: portfolioLocale), trailing: .disclosure(nil))
                    }.buttonStyle(.plain)
                    divider''',1);s=help_sheet(s,'        .background(Palette.canvas.ignoresSafeArea())')
 elif key=='rampart':
  start=s.index('                // More from LorisLabs');end=s.index('                // About',start)
  s=s[:start]+'''                SectionLabel("More from LorisLabs")
                Button { showsPortfolioHelp = true } label: {
                    SettingRow(icon: "square.grid.2x2", label: PortfolioText.title(locale: portfolioLocale), sub: nil, value: nil, first: true)
                }.buttonStyle(.plain).instrumentCard()

'''+s[end:]
  s=help_sheet(s,'        .background(Pal.screen.ignoresSafeArea())')
 elif key=='halte':
  anchor='                    PrivacyLine().padding(.top, 24)';assert anchor in s;s=s.replace(anchor,'''                    Button { showsPortfolioHelp = true } label: {
                        Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
'''+anchor,1);s=help_sheet(s,'            .background(HalteColor.screenBg.ignoresSafeArea())')
  j=candidate/'Halte/Journal/JournalView.swift';t=j.read_text();t=t.replace('    @Environment(\\.requestReview) private var requestReview\n','').replace('    @AppStorage("reviewPromptedVersion") private var reviewPromptedVersion = ""\n','').replace('        maybeRequestReview()\n','');start=t.index('    /// Ask for an App Store rating');end=t.index('    @ViewBuilder private var premiumOrAha',start);t=t[:start]+'''    // Automatic ratings stay off in the fraud-protection flow. Reading history is not a completed task.

'''+t[end:];j.write_text(t)
 elif key=='mela':
  needle='                            row("heart", String(localized: "Support Mela"), last: true, action: onSupport)';assert needle in s;s=s.replace(needle,needle+'''
                            row("square.grid.2x2", PortfolioText.title(locale: portfolioLocale), last: true) {
                                guard gate.isUnlocked else { return }
                                showsPortfolioHelp = true
                            }''',1)
  s=help_sheet(s,'        .preferredColorScheme(.light)');s=s.replace('                PortfolioHelpView()','                Group { if gate.isUnlocked { PortfolioHelpView() } }',1);s=s.replace('        .preferredColorScheme(.light)','        .onChange(of: gate.isUnlocked) { _, unlocked in if !unlocked { showsPortfolioHelp = false } }\n        .preferredColorScheme(.light)',1)
 elif key=='aegis':
  needle='              // Security';assert needle in s;s=s.replace(needle,'''              Button { showsPortfolioHelp = true } label: {
                Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
                  .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              }

'''+needle,1);# Existing app owns the navigation stack and presentation chain.
  # Attach outside the existing stack, before its current sheet chain.
  anchor='      .sheet(isPresented: $showSplitVault, onDismiss: {';assert anchor in s;s=s.replace(anchor,'''      .sheet(isPresented: $showsPortfolioHelp) {
        NavigationStack {
          PortfolioHelpView().toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Close") { showsPortfolioHelp = false }
          } }
        }
      }
'''+anchor,1)
 p.write_text(s)
 if key=='aegis':
  p=candidate/'Aegis/macOS/AegisMainWindowView.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
  anchor='  private var settingsPanel: some View {';assert anchor in s;s=s.replace(anchor,'  @State private var showsPortfolioHelp = false\n  @Environment(\\.locale) private var portfolioLocale\n\n'+anchor,1)
  anchor='        settingsSection("Security") {';assert anchor in s;s=s.replace(anchor,'''        settingsSection("LorisLabs") {
          Button { showsPortfolioHelp = true } label: {
            Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
              .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          }
          .sheet(isPresented: $showsPortfolioHelp) {
            NavigationStack { PortfolioHelpView().toolbar { ToolbarItem(placement: .confirmationAction) {
              Button("Close") { showsPortfolioHelp = false }
            } } }.frame(minWidth: 480, minHeight: 540)
          }
        }
'''+anchor,1);p.write_text(s)
 subprocess.run(['xcodegen','generate'],cwd=candidate,check=True,capture_output=True)
 project={'kalou':'Kalou','rampart':'Rampart','halte':'Halte','mela':'Mela','aegis':'Aegis'}[key]
 touched=['project.yml',project+'.xcodeproj/project.pbxproj',view,help,'Packages/LorisLabsKit']
 if key=='halte':touched.append('Halte/Journal/JournalView.swift')
 if key=='aegis':touched.append('Aegis/macOS/AegisMainWindowView.swift')
 return touched

def prepare_aurora(candidate,freeze):
 freeze(candidate,'Packages/LorisLabsKit',['LorisLabsKit','LorisReports'])
 help=write_help(candidate,'AuroraPulse','aurorapulse','AuroraPulse','com.lorislab.aurorapulse')
 p=candidate/'AuroraPulse/Views/Settings/SettingsView.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
 s=s.replace('    var body: some View {','    @State private var showsPortfolioHelp = false\n    @Environment(\\.locale) private var portfolioLocale\n\n    var body: some View {',1)
 anchor='                        dataSourcesSection';assert anchor in s;s=s.replace(anchor,anchor+'''
                        Button { showsPortfolioHelp = true } label: {
                            Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .padding(.horizontal, APSpacing.lg)''',1);s=help_sheet(s,'        .preferredColorScheme(.dark)');p.write_text(s)
 p=candidate/'AuroraPulse.xcodeproj/project.pbxproj'
 replace(p,'/* Begin PBXBuildFile section */','''/* Begin PBXBuildFile section */
        E70000000000000000000001 /* LorisLabsKit in Frameworks */ = {isa = PBXBuildFile; productRef = E70000000000000000000003; };
        E70000000000000000000002 /* LorisReports in Frameworks */ = {isa = PBXBuildFile; productRef = E70000000000000000000004; };''')
 before='''\t\t5BA4362F2F5E10A100F7917C /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (''';replace(p,before,before+'\n                E70000000000000000000001,\n                E70000000000000000000002,')
 replace(p,'\t\t\tname = AuroraPulse;\n\t\t\tproductName = AuroraPulse;','\t\t\tname = AuroraPulse;\n            packageProductDependencies = (E70000000000000000000003, E70000000000000000000004);\n\t\t\tproductName = AuroraPulse;')
 replace(p,'\t\t\tpreferredProjectObjectVersion = 77;','\t\t\tpreferredProjectObjectVersion = 77;\n            packageReferences = (E70000000000000000000005);')
 replace(p,'/* End XCConfigurationList section */','''/* End XCConfigurationList section */
/* Begin XCLocalSwiftPackageReference section */
        E70000000000000000000005 /* Packages/LorisLabsKit */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/LorisLabsKit; };
/* End XCLocalSwiftPackageReference section */
/* Begin XCSwiftPackageProductDependency section */
        E70000000000000000000003 /* LorisLabsKit */ = {isa = XCSwiftPackageProductDependency; package = E70000000000000000000005; productName = LorisLabsKit; };
        E70000000000000000000004 /* LorisReports */ = {isa = XCSwiftPackageProductDependency; package = E70000000000000000000005; productName = LorisReports; };
/* End XCSwiftPackageProductDependency section */''')
 return ['AuroraPulse.xcodeproj/project.pbxproj','AuroraPulse/Views/Settings/SettingsView.swift',help,'Packages/LorisLabsKit']

def prepare_entrofold(candidate,freeze):
 import subprocess
 app=candidate/'EntroFoldArchive';add_package_dependencies(app,['EntroFold Archive'],freeze)
 write_help(app,'EntroFoldArchive','entrofold-archive','EntroFold Archive','com.lorislab.entrofold-archive')
 p=app/'EntroFoldArchive/PortfolioHelpView.swift';s=p.read_text();s+='''
@MainActor
enum PortfolioEngagement {
    static let reviews = SmartReviewPromptManager(bundleIdentifier: "com.lorislab.entrofold-archive")
}
''';p.write_text(s)
 p=app/'EntroFoldArchive/EntroFoldArchiveApp.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
 s=s.replace('    private var preferredColorScheme:', '    @Environment(\\.openWindow) private var openWindow\n    init() { _ = PortfolioEngagement.reviews }\n\n    private var preferredColorScheme:',1)
 needle='                Button("EntroFold Archive Help") {';assert needle in s;s=s.replace(needle,'''                Button(PortfolioText.title()) { openWindow(id: "lorislabs-help") }
'''+needle,1)
 needle='''        .commands {''';assert needle in s
 # Add the dedicated help window after the main scene command block.
 end=s.index('\n    }\n\n    @ViewBuilder',s.index('    var body: some Scene'))
 s=s[:end]+'''
        Window("LorisLabs", id: "lorislabs-help") {
            NavigationStack { PortfolioHelpView() }.frame(minWidth: 480, minHeight: 540)
        }
'''+s[end:];p.write_text(s)
 p=app/'EntroFoldArchive/PreferencesView.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1)
 needle='''        TabView {
''';assert needle in s;s=s.replace(needle,needle+'''            NavigationStack { PortfolioHelpView() }
                .tabItem { Label("LorisLabs", systemImage: "square.grid.2x2") }
''',1);p.write_text(s)
 p=app/'EntroFoldArchive/ArchiveViewModel.swift';s=p.read_text();needle='''                // Show completion sheet (will load archive when dismissed)''';assert needle in s;s=s.replace(needle,'''                PortfolioEngagement.reviews.recordCompletedAction()

'''+needle,1);p.write_text(s)
 p=app/'EntroFoldArchive/ContentView.swift';s=p.read_text().replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1);needle='''        .onReceive(NotificationCenter.default.publisher(for: .createArchive))''';assert needle in s
 s=s.replace(needle,'''        .reviewPromptWhenIdle(PortfolioEngagement.reviews,
            isIdle: !viewModel.isProcessing && !viewModel.showCompletionSheet && !viewModel.showSelectiveExtractionSheet
                && !viewModel.showComparisonView && !viewModel.showPreferences && viewModel.error == nil
                && viewModel.infoMessage == nil && viewModel.previewItem == nil,
            additionalEligibility: {
                NSApp.modalWindow == nil && !NSApp.windows.contains { $0.attachedSheet != nil }
                    && !NSApp.windows.contains { $0.isVisible && $0.title == "LorisLabs" }
                    && !(NSApp.keyWindow?.firstResponder is NSTextView)
            })
'''+needle,1);p.write_text(s)
 subprocess.run(['xcodegen','generate'],cwd=app,check=True,capture_output=True)
 return ['EntroFoldArchive/'+r for r in ['project.yml','EntroFold Archive.xcodeproj/project.pbxproj','EntroFoldArchive/PortfolioHelpView.swift','EntroFoldArchive/EntroFoldArchiveApp.swift','EntroFoldArchive/PreferencesView.swift','EntroFoldArchive/ArchiveViewModel.swift','EntroFoldArchive/ContentView.swift','Packages/LorisLabsKit']]
