"""Prepare only source-isolated copies of hosts reserved to other writers."""
from pathlib import Path
import shutil,json,hashlib

def replace(path,before,after,count=1):
 s=path.read_text();assert s.count(before)==count,(str(path),before[:80],s.count(before));path.write_text(s.replace(before,after))

def copy_engagement(candidate,relative,source):
 dest=candidate/relative
 for folder in ['Review','CrossPromotion','Resources']:
  shutil.copytree(source/'Sources/LorisLabsKit'/folder,dest/'Sources/LorisLabsKit'/folder,dirs_exist_ok=True)
 paths=[relative+'/Sources/LorisLabsKit/'+folder for folder in ['Review','CrossPromotion','Resources']]
 meta=dest/'UPSTREAM-ENGAGEMENT-20261015.json'
 meta.write_text(json.dumps({'source':'LorisLabsKit reviewed local working tree','scope':['Review','CrossPromotion','Resources'],
  'files':{str(p.relative_to(dest)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['Review','CrossPromotion','Resources'] for p in (dest/'Sources/LorisLabsKit'/folder).rglob('*') if p.is_file()}},indent=2)+'\n')
 return paths+[str(meta.relative_to(candidate))]

def prepare_kernel(c,source):
 paths=copy_engagement(c,'Dependencies/KernelEngagement',source)
 p=c/'Dependencies/KernelEngagement/Package.swift';s=p.read_text();start=s.index('sources: [');end=s.index('], resources:',start);s=s[:start]+'sources: ["Review", "CrossPromotion"'+s[end:];p.write_text(s);paths.append('Dependencies/KernelEngagement/Package.swift')
 p=c/'Support/KernelIntegration.swift';s=p.read_text();start=s.index('    private var otherApps:');end=s.index('    var body:',start);s=s[:start]+s[end:]
 start=s.index('                Section(KernelIntegration.text("More from LorisLabs"))');end=s.index('\n            }\n            .navigationTitle',start)
 s=s[:start]+'''                Section {
                    LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.kernel")
                }'''+s[end:];p.write_text(s);paths.append('Support/KernelIntegration.swift')
 paths+=prepare_kernel_window(c)
 p=c/'Mobile/Sources/UI/WorksheetView.swift';s=p.read_text().replace('import StoreKit','import LorisLabsKit',1).replace('    @State private var reviewAttempt: UUID?\n','').replace('    @Environment(\\.requestReview) private var requestReview\n','')
 s=s.replace('                KernelIntegration.review.recordSuccessMoment()\n','').replace('                reviewAttempt = UUID()','                KernelIntegration.review.recordCompletedAction()')
 start=s.index('        .task(id: reviewAttempt)');end=s.index('        .sheet(isPresented: $model.isShowingOutputSheet)',start)
 s=s[:start]+'''        .reviewPromptWhenIdle(KernelIntegration.review,
            isIdle: model.phase == .intake && !isShowingHelp && !isShowingConversions && !isPickingFiles
                && !isPickingPhotos && !model.isShowingOutputSheet,
            additionalEligibility: {
                #if DEBUG
                guard ProcessInfo.processInfo.environment["KERNEL_TEST_FIXTURE"] == nil else { return false }
                #endif
                return true
            })
'''+s[end:];p.write_text(s);paths.append('Mobile/Sources/UI/WorksheetView.swift')
 paths+=prepare_kernel_tests(c)
 return paths

def prepare_kernel_window(c):
 p=c/'Kernel/Sources/UI/KernelWindow.swift';s=p.read_text().replace('import StoreKit','import LorisLabsKit',1).replace('    @State private var reviewAttempt: UUID?\n','').replace('    @Environment(\\.requestReview) private var requestReview\n','')
 s=s.replace('KernelIntegration.review.recordSuccessMoment()','KernelIntegration.review.recordCompletedAction()').replace('                reviewAttempt = UUID()\n','')
 start=s.index('        .task(id: reviewAttempt)');end=s.index('        // Entitlements resolve once',start)
 s=s[:start]+'''        .reviewPromptWhenIdle(KernelIntegration.review,
            isIdle: !isShowingHelp && !isShowingConversions && !model.isRunning && !model.isImporting
                && !model.isAgentThinking && !model.planPending && model.pendingUpgrade == nil && proofs.verdicts.isEmpty,
            additionalEligibility: {
                #if DEBUG
                guard ProcessInfo.processInfo.environment["KERNEL_UITEST"] != "1" else { return false }
                #endif
                return NSApp.modalWindow == nil && !NSApp.windows.contains { $0.attachedSheet != nil }
                    && !(NSApp.keyWindow?.firstResponder is NSTextView)
            })
'''+s[end:];p.write_text(s);return ['Kernel/Sources/UI/KernelWindow.swift']

def prepare_kernel_tests(c):
 base='Dependencies/KernelEngagement/Tests/LorisLabsKitTests/'
 p=c/(base+'SmartReviewPromptManagerTests.swift')
 replace(p,'        let mgr = SmartReviewPromptManager(','''        // Threshold tests control time explicitly; production keeps its quiet-session defaults.
        var config = config
        config.minimumSessionDuration = 0
        config.minimumCompletionDelay = 0
        let mgr = SmartReviewPromptManager(''')
 replace(p,'        clock.date = start.addingTimeInterval(120 * 86_400)\n        #expect(mgr.shouldPromptNow)', '        clock.date = start.addingTimeInterval(120 * 86_400)\n        #expect(!mgr.shouldPromptNow) // Historical usage cannot trigger a new-session review.\n        mgr.recordCompletedAction()\n        #expect(mgr.shouldPromptNow)')
 p=c/(base+'ReviewPolicyTests.swift');s=p.read_text().replace('attemptedThisSession: false)', 'attemptedThisSession: false, completedThisSession: true)');p.write_text(s)
 update_catalogue_test(c/(base+'SmartReviewPromptManagerTests.swift'))
 return [base+'SmartReviewPromptManagerTests.swift',base+'ReviewPolicyTests.swift']

def prepare_filova(c):
 p=c/'Filova/Shared/LorisIntegrationViews.swift';s=p.read_text();start=s.index('    private var portfolio:');end=s.index('    var body:',start);s=s[:start]+s[end:]
 s=s.replace('MoreFromLorisLabsView(apps: portfolio)','LorisLabsAppsLink(currentBundleIdentifier: FilovaServices.bundleIdentifier)')
 s=s.replace('    @Environment(\\.requestReview) private var requestReview\n','')
 needle='''        content
            .onAppear { visible = true; schedule() }''';assert needle in s;s=s.replace(needle,'''        content
            .reviewPromptWhenIdle(services.reviews, isIdle: !blocked && !services.isInteracting)
            .onAppear { visible = true; schedule() }''',1)
 s=s.replace('            services.reviews.requestIfAppropriate(via: requestReview)\n','');p.write_text(s)
 p=c/'Filova/Core/FilovaServices.swift';replace(p,'self.reviews = reviews ?? SmartReviewPromptManager(userDefaults: defaults,','self.reviews = reviews ?? SmartReviewPromptManager(configuration: .init(minimumCompletionDelay: 3), userDefaults: defaults,')
 replace(p,'reviews.recordSuccessMoment()','reviews.recordCompletedAction()')
 paths=['Filova/Shared/LorisIntegrationViews.swift','Filova/Core/FilovaServices.swift']
 paths+=prepare_filova_tests(c)
 return paths

def prepare_filova_tests(c):
 path='FilovaTests/LorisLabsIntegrationTests.swift';p=c/path
 replace(p,'minimumActiveDays: 1),','minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0),')
 replace(p,'XCTAssertTrue(FilovaServices.feedbackServiceValidated)','XCTAssertEqual(FilovaServices.feedbackServiceValidated, FilovaFeedbackGates.forBuild().deliveryEnabled)')
 return [path]

def prepare_clasp(c,source):
 paths=copy_engagement(c,'LorisLabsKit',source)
 p=c/'LorisLabsKit/Package.swift';replace(p,'.target(name: "LorisLabsKit"),','.target(name: "LorisLabsKit", resources: [.process("Resources")]),');paths.append('LorisLabsKit/Package.swift')
 p=c/'Clasp/ViewModels/ClipboardHistoryViewModel.swift';s=p.read_text()
 for _ in range(2):
  start=s.index('        // Request App Store review after 10th paste');end=s.index('        // Track item access count',start);s=s[:start]+s[end:]
 p.write_text(s);paths.append('Clasp/ViewModels/ClipboardHistoryViewModel.swift')
 p=c/'Clasp/Core/SnippetEngine.swift';s=p.read_text();start=s.index('        // Request App Store review after first snippet expansion');end=s.index('        SoundManager.play(.snippetExpanded)',start);p.write_text(s[:start]+s[end:]);paths.append('Clasp/Core/SnippetEngine.swift')
 p=c/'Clasp/Core/ReviewHelper.swift';p.write_text('''import Foundation

/// Reviews are voluntary from Help. Clipboard, snippets and referral flows never interrupt work.
enum ReviewHelper {
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6759068382?action=write-review")!
}
''');paths.append('Clasp/Core/ReviewHelper.swift')
 p=c/'Clasp/Referral/ClaspReferralReviewPrompts.swift';s=p.read_text();start=s.index('    // MARK: - Prompt Triggers');end=s.index('    // MARK: - Debug / Testing',start)
 s=s[:start]+'''    // Kept for existing referral observers. Referral/payment events never select reviewers.
    static func maybePromptAfterRedeem() async {}
    static func maybePromptOnFirstConfirmedReferral() async {}
    static func maybePromptOnTier5Unlock() async {}

'''+s[end:];start=s.index('import Foundation');s='// Referral tracking compatibility; automatic review requests are disabled.\n'+s[start:];s=s.replace('import StoreKit\n','').replace('    /// Records the first redeem timestamp so we can delay the prompt by 3+ days.','    /// Preserves the existing first-redeem timestamp independently of reviews.');p.write_text(s);paths.append('Clasp/Referral/ClaspReferralReviewPrompts.swift')
 p=c/'Clasp/Views/Settings/CabinetSettingsView.swift';replace(p,'import SwiftUI','import SwiftUI\nimport LorisLabsKit')
 replace(p,'struct HelpSections: View {\n','struct HelpSections: View {\n    @State private var showOtherApps = false\n    @Environment(\\.locale) private var locale\n')
 replace(p,'            SectionCard(title: "About") {','''            SectionCard(title: PortfolioText.title(locale: locale)) {
                Button { showOtherApps = true } label: {
                    Label(PortfolioText.title(locale: locale), systemImage: "square.grid.2x2")
                }
            }
            SectionCard(title: "About") {
                Link(destination: ReviewHelper.writeReviewURL) {
                    Label(String(localized: "Write a Review"), systemImage: "star")
                }''')
 # Only the HelpSections trailing body, avoiding any other settings sheet.
 s=p.read_text();start=s.index('struct HelpSections: View {');tail=s[start:];needle='''        }
    }
}

#endif''';assert needle in tail;tail=tail.replace(needle,'''        }
        .sheet(isPresented: $showOtherApps) {
            NavigationStack {
                LorisLabsAppsMenu(currentBundleIdentifier: "com.lorislab.claspapp")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Close")) { showOtherApps = false }
                        }
                    }
            }
            .frame(minWidth: 480, minHeight: 540)
        }
    }
}

#endif''');p.write_text(s[:start]+tail);paths.append('Clasp/Views/Settings/CabinetSettingsView.swift')
 p=c/'Clasp/Views/IOSSettingsTab.swift';replace(p,'import SwiftUI','import SwiftUI\nimport LorisLabsKit')
 replace(p,'                Section(String(localized: "About")) {','''                Section(String(localized: "About")) {
                    LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.claspapp")
                    Link(destination: ReviewHelper.writeReviewURL) {
                        Label(String(localized: "Write a Review"), systemImage: "star")
                    }''');paths.append('Clasp/Views/IOSSettingsTab.swift')
 paths+=prepare_clasp_tests(c)
 return paths

def prepare_clasp_tests(c):
 path='LorisLabsKit/Tests/LorisLabsKitTests/SmartReviewPromptManagerTests.swift';p=c/path
 s=p.read_text().replace('minimumDaysSinceInstall: 0)', 'minimumDaysSinceInstall: 0, minimumActiveDays: 1)').replace('errorBlackoutDays: 7)', 'errorBlackoutDays: 7, minimumActiveDays: 1)')
 s=s.replace('        let mgr = SmartReviewPromptManager(','''        // Threshold fixtures skip elapsed-time guards; production retains the quiet-session defaults.
        var config = config
        config.minimumSessionDuration = 0
        config.minimumCompletionDelay = 0
        let mgr = SmartReviewPromptManager(''',1)
 for name,newname in [('recentErrorBlocksPrompt','pastErrorDoesNotSelectReviewers'),('activeFreeTrialBlocksPrompt','trialDoesNotSelectReviewers')]:
  start=s.index('    @Test func '+name);end=s.index('    @Test func ',start+1);part=s[start:end].replace(name,newname).replace('#expect(!mgr.shouldPromptNow)','#expect(mgr.shouldPromptNow)');s=s[:start]+part+s[end:]
 p.write_text(s);update_catalogue_test(p);return [path]

def update_catalogue_test(p):
 s=p.read_text().replace('$0.name == "Clasp"', '$0.bundleIdentifier == "com.lorislab.claspapp"');p.write_text(s)

def embed_core_in_support(c,relative,target,source):
 paths=copy_engagement(c,relative,source)
 p=c/relative/'Package.swift'
 replace(p,'    targets: [','    targets: [\n        .target(name: "LorisLabsKit", resources: [.process("Resources")]),')
 replace(p,'.target(name: "'+target+'", dependencies: ["LorisReports"])','.target(name: "'+target+'", dependencies: ["LorisReports", "LorisLabsKit"])')
 return paths+[relative+'/Package.swift']

def prepare_millrace(c,source):
 relative='Millrace/Packages/MillraceSupport';paths=embed_core_in_support(c,relative,'MillraceSupport',source)
 replace(c/relative/'Package.swift','.testTarget(name: "MillraceSupportTests", dependencies: ["MillraceSupport"])','.testTarget(name: "MillraceSupportTests", dependencies: ["MillraceSupport", "LorisLabsKit"])')
 path=relative+'/Sources/MillraceSupport/MillraceHelpView.swift';p=c/path;replace(p,'import LorisReports','import LorisReports\nimport LorisLabsKit')
 replace(p,'                if let session {','''                HelpSection(PortfolioText.title(locale: locale)) {
                    LorisLabsAppsLink(currentBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.lorislab.Millrace")
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("millrace.help.apps")
                }
                if let session {''')
 paths.append(path)
 path=relative+'/Tests/MillraceSupportTests/MillracePortfolioTests.swift'
 (c/path).write_text('''import XCTest
import LorisLabsKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class MillracePortfolioTests: XCTestCase {
    func testVendoredCatalogueAndOfficialIconsAreAvailableOffline() throws {
        let apps = LorisLabsApp.portfolio
        XCTAssertFalse(apps.isEmpty)
        XCTAssertEqual(Set(apps.map(\\.ascAppId)).count, apps.count)
        for app in apps {
            let icon = try XCTUnwrap(app.bundledIconURL, app.name)
            XCTAssertTrue(icon.isFileURL)
            #if canImport(AppKit)
            XCTAssertNotNil(NSImage(contentsOf: icon), app.name)
            #elseif canImport(UIKit)
            XCTAssertNotNil(UIImage(contentsOfFile: icon.path), app.name)
            #endif
            XCTAssertEqual(app.appStoreURL.scheme, "https")
            XCTAssertEqual(app.appStoreURL.host, "apps.apple.com")
            XCTAssertTrue(app.appStoreURL.path.hasSuffix("id" + app.ascAppId))
            XCTAssertFalse(app.localizedTagline(locale: Locale(identifier: "fr_FR")).isEmpty)
        }
    }

    func testBothShippingAppsExcludeThemselvesAndKeepTheirCompanion() {
        let identifiers = ["com.lorislab.Millrace", "com.lorislab.MillraceScan"]
        for identifier in identifiers {
            XCTAssertTrue(LorisLabsApp.portfolio.contains { $0.bundleIdentifier == identifier })
            for variant in [identifier, identifier.uppercased(), identifier + ".debug"] {
                let others = LorisLabsApp.othersThan(variant)
                XCTAssertFalse(others.contains { $0.bundleIdentifier == identifier })
                XCTAssertTrue(others.contains { identifiers.contains($0.bundleIdentifier) && $0.bundleIdentifier != identifier })
            }
        }
    }
}
''')
 return paths+[path]

def prepare_siliconpass(c,source):
 relative='Integrations/SiliconPassSupport';paths=embed_core_in_support(c,relative,'SiliconPassSupport',source)
 path=relative+'/Sources/SiliconPassSupport/SiliconPassAppsLink.swift';p=c/path;p.write_text('''import SwiftUI
import LorisLabsKit

/// Offline portfolio only. No vault dependency, storage or automatic review request.
public struct SiliconPassAppsLink: View {
    public init() {}
    public var body: some View {
        LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.siliconpass")
    }
}
''');paths.append(path)
 path='App/Support/SPAppSupport.swift';p=c/path;replace(p,'            List {','            List {\n                SiliconPassAppsLink()')
 return paths+[path]

def prepare_vif(c,source):
 relative='apple/Packages/VifFeedbackSDK';paths=copy_engagement(c,relative,source)
 p=c/relative/'Package.swift';replace(p,'    targets: [','    targets: [\n        .target(name: "LorisLabsKit", resources: [.process("Resources")], swiftSettings: [.unsafeFlags(privacyFlags, .when(configuration: .release))]),')
 replace(p,'.target(name: "VifSupport", dependencies: ["LorisReports"],','.target(name: "VifSupport", dependencies: ["LorisReports", "LorisLabsKit"],');paths.append(relative+'/Package.swift')
 path=relative+'/Sources/VifSupport/VifAppsMenu.swift';p=c/path;p.write_text('''import SwiftUI
import LorisLabsKit

/// Offline menu; transfers, pairing and permissions never trigger review requests.
public struct VifAppsMenu: View {
    public init() {}
    public var body: some View {
        LorisLabsAppsMenu(currentBundleIdentifier: "com.lorislab.vifbench")
    }
}
''');paths.append(path)
 path='apple/Shared/VifHelpView.swift';p=c/path;replace(p,'    @State private var showsNotices = false','    @State private var showsNotices = false\n    @State private var showsOtherApps = false')
 replace(p,'        .safeAreaInset(edge: .bottom) {\n','''        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
            Button { showsOtherApps = true } label: {
                Label(VifHelpText.text("Autres apps LorisLabs", "More from LorisLabs"), systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("vif.apps.open")
''')
 replace(p,'            .padding().frame(maxWidth: .infinity).background(.bar)','            }\n            .padding().frame(maxWidth: .infinity).background(.bar)')
 replace(p,'        .sheet(isPresented: $showsNotices) {','''        .sheet(isPresented: $showsOtherApps) {
            NavigationStack {
                VifAppsMenu().toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(VifHelpText.done) { showsOtherApps = false }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 540)
            #endif
        }
        .sheet(isPresented: $showsNotices) {''')
 return paths+[path]

def prepare_sinkhole(c,freeze):
 freeze(c,'Packages/LorisLabsKit',['LorisLabsKit'])
 paths=['Packages/LorisLabsKit'];p=c/'Sinkhole.xcodeproj/project.pbxproj'
 replace(p,'/* Begin PBXBuildFile section */','''/* Begin PBXBuildFile section */
        E80000000000000000000001 /* LorisLabsKit in Frameworks */ = {isa = PBXBuildFile; productRef = E80000000000000000000002; };''')
 anchor='''\t\t5BA298F22F640A24003303F1 /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (''';replace(p,anchor,anchor+'\n                E80000000000000000000001,')
 replace(p,'\t\t\tname = Sinkhole;\n\t\t\tpackageProductDependencies = (','\t\t\tname = Sinkhole;\n\t\t\tpackageProductDependencies = (\n                E80000000000000000000002,')
 replace(p,'\t\t\tpackageReferences = (','\t\t\tpackageReferences = (\n                E80000000000000000000003,')
 replace(p,'/* End XCConfigurationList section */','''/* End XCConfigurationList section */
/* Begin XCLocalSwiftPackageReference section */
        E80000000000000000000003 = {isa = XCLocalSwiftPackageReference; relativePath = Packages/LorisLabsKit; };
/* End XCLocalSwiftPackageReference section */
/* Begin XCSwiftPackageProductDependency section */
        E80000000000000000000002 = {isa = XCSwiftPackageProductDependency; package = E80000000000000000000003; productName = LorisLabsKit; };
/* End XCSwiftPackageProductDependency section */''');paths.append('Sinkhole.xcodeproj/project.pbxproj')
 path='Sinkhole/Views/Settings/SettingsView.swift';p=c/path;replace(p,'import SwiftUI','import SwiftUI\nimport LorisLabsKit');replace(p,'                Section(String(localized: "Help & Legal")) {','''                Section(String(localized: "Help & Legal")) {
                    LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.sinkhole")''');paths.append(path)
 path='Home/MacApp/Package.swift';p=c/path;replace(p,'targets: [.executableTarget(name:"SinkholeHome", swiftSettings:','dependencies: [.package(path:"../../Packages/LorisLabsKit")], targets: [.executableTarget(name:"SinkholeHome", dependencies:[.product(name:"LorisLabsKit",package:"LorisLabsKit")], swiftSettings:');paths.append(path)
 path='Home/MacApp/Sources/SinkholeHome/HomeView.swift';p=c/path;replace(p,'import SwiftUI','import SwiftUI\nimport LorisLabsKit');replace(p,'    @State private var confirmClear = false','    @State private var confirmClear = false\n    @State private var showsOtherApps = false\n    @Environment(\\.locale) private var portfolioLocale')
 anchor='    private var settings: some View {\n        VStack(alignment:.leading,spacing:16) {';replace(p,anchor,anchor+'''
            Button { showsOtherApps = true } label: {
                Label(PortfolioText.title(locale: portfolioLocale), systemImage: "square.grid.2x2")
            }
            .sheet(isPresented: $showsOtherApps) {
                NavigationStack {
                    LorisLabsAppsMenu(currentBundleIdentifier: "com.lorislab.sinkhole")
                        .toolbar { ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "Close")) { showsOtherApps = false }
                        } }
                }.frame(minWidth: 480, minHeight: 540)
            }''');paths.append(path)
 return paths

def prepare_lumen(c,freeze):
 import re
 freeze(c,'Packages/LorisLabsKit',['LorisLabsKit']);paths=['Packages/LorisLabsKit']
 path='Lumen for Frigate.xcodeproj/project.pbxproj';p=c/path;s=p.read_text();start=s.index('\t\t53B42A4B03D5123301B8AD29 /* XCRemoteSwiftPackageReference "LorisLabsKit" */ = {');end=s.index('\n\t\t5B600F3F',start);s=s[:start]+s[end:]
 s=s.replace('/* Begin XCLocalSwiftPackageReference section */','''/* Begin XCLocalSwiftPackageReference section */
        53B42A4B03D5123301B8AD29 /* XCLocalSwiftPackageReference "LorisLabsKit" */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/LorisLabsKit; };''');s=s.replace('XCRemoteSwiftPackageReference "LorisLabsKit"','XCLocalSwiftPackageReference "LorisLabsKit"');p.write_text(s);paths.append(path)
 path='Lumen for Frigate/Services/LumenReviewMoments.swift';p=c/path;s=p.read_text();start=s.index('    /// True for the first connection');end=s.index('    /// Lumen could not reach',start);tracking=s[start:end]
 p.write_text('''import SwiftUI
import LorisLabsKit

/// One process owner. Passive connections, alerts and referrals never create review opportunities.
/// Automatic prompts stay disabled until a foreground pause outside camera/video flows is qualified.
@MainActor
enum LumenReviewMoments {
    static let configuration = SmartReviewPromptManager.Configuration()
    static let recorder = SmartReviewPromptManager(configuration: configuration,
        bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.lorislab.lumenforfrigate.Lumen-for-Frigate")
    private static let lastConnectedSuccessKey = "Lumen.review.lastConnectedSuccess"
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6760238729?action=write-review")!
    static func openedAlert() {}
    static func connected() {}
    static func connectionFailed() {}
    static func completedEvent() { recorder.recordCompletedAction() }
'''+tracking+'}\n');paths.append(path)
 path='Lumen for Frigate/Lumen_for_FrigateApp.swift';p=c/path;s=p.read_text();s=re.sub(r'    @State private var reviewManager = SmartReviewPromptManager\(\n.*?\n    \)', '    @State private var reviewManager = LumenReviewMoments.recorder',s,count=1,flags=re.S)
 start=s.index('            let mgr = SmartReviewPromptManager(');end=s.index('            mgr.recordLaunch()',start);s=s[:start]+'            let mgr = LumenReviewMoments.recorder\n'+s[end:]
 start=s.index('                .task {\n                    // Trigger review prompts');end=s.index('                // Feed the rating rules:',start);s=s[:start]+s[end:];s=s.replace('''                // Feed the rating rules: reaching Frigate counts as Lumen
                // working; a connection error holds the ask back a few days.''','''                // Compatibility observers do not create review opportunities.''');p.write_text(s);paths.append(path)
 path='Lumen for Frigate/Views/EventDetailView.swift';p=c/path;replace(p,'LumenReviewMoments.askIfAppropriate(via: requestReview, subscription: subscription)','LumenReviewMoments.completedEvent()');s=p.read_text().replace('    @Environment(\\.requestReview) private var requestReview\n','');s=s.replace('''            // Closing an event is a natural pause to ask for a rating —
            // but never right after a paywall or when the event didn't load.''','''            // Record completed viewing only. No review is requested during dismissal.''');p.write_text(s);paths.append(path)
 path='Lumen for Frigate/Referral/LumenReferralReviewPrompts.swift';p=c/path;s=p.read_text();s=re.sub(r'(    static func maybePrompt\w+\(.*?\n    \) async \{).*?\n    }',r'\1\n        // Referral/payment activity never selects reviewers.\n    }',s,flags=re.S);start=s.index('@available');s='import SwiftUI\nimport StoreKit\nimport LorisLabsKit\n\n// Referral tracking compatibility. Automatic referral review requests are disabled.\n'+s[start:];p.write_text(s);paths.append(path)
 for path,anchor in [('Lumen for Frigate/Views/Settings/SettingsView+InfoData.swift','            Link(destination: URL(string: "https://lorislab.fr")!) {'),('Lumen for Frigate/Views/MacSettingsView.swift','            Section("Links") {')]:
  p=c/path;replace(p,'import SwiftUI','import SwiftUI\nimport LorisLabsKit')
  if 'MacSettingsView' in path:replace(p,anchor,anchor+'\n                LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.lumenforfrigate.Lumen-for-Frigate")')
  else:replace(p,anchor,'            LorisLabsAppsLink(currentBundleIdentifier: "com.lorislab.lumenforfrigate.Lumen-for-Frigate")\n\n'+anchor)
  paths.append(path)
 path='LumenTV/TVSettingsView.swift';p=c/path;replace(p,'import SwiftUI','import SwiftUI\nimport UIKit\nimport LorisLabsKit\nimport CoreImage.CIFilterBuiltins');replace(p,'        Section("About") {','''        Section("About") {
            NavigationLink { LumenPortfolioTVView() } label: {
                Label(PortfolioText.title(), systemImage: "square.grid.2x2")
            }''')
 with p.open('a') as output:output.write(LUMEN_TV_PORTFOLIO)
 return paths+[path]+prepare_lumentv_wiring(c)

def extract_internal_pro_qualification(c):
 path='Lumen for Frigate/Services/DevUnlockService.swift';p=c/path;s=p.read_text();start=s.index('/// Process-scoped owner qualification.');end=s.index('// The developer unlock',start)
 dest='Lumen for Frigate/Services/InternalProQualification.swift';q=c/dest;assert not q.exists();q.write_text('import Foundation\n\n'+s[start:end]);p.write_text(s[:start]+s[end:]);return [path,dest]

def prepare_lumentv_wiring(c):
 import subprocess
 paths=extract_internal_pro_qualification(c)
 p=c/'Lumen for Frigate.xcodeproj/project.pbxproj'
 model=json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(p)]));objects=model['objects']
 target=next(v for v in objects.values() if v.get('isa')=='PBXNativeTarget' and v.get('name')=='LumenTV')
 phase=next(x for x in target['buildPhases'] if objects[x]['isa']=='PBXSourcesBuildPhase')
 s=p.read_text();assert 'E90000000000000000000001' not in s
 s=s.replace('/* Begin PBXBuildFile section */','''/* Begin PBXBuildFile section */
        E90000000000000000000001 /* PaywallMetrics.swift in Sources */ = {isa = PBXBuildFile; fileRef = E90000000000000000000003; };
        E90000000000000000000002 /* InternalProQualification.swift in Sources */ = {isa = PBXBuildFile; fileRef = E90000000000000000000004; };''',1)
 s=s.replace('/* Begin PBXFileReference section */','''/* Begin PBXFileReference section */
        E90000000000000000000003 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Lumen for Frigate/Subscription/PaywallMetrics.swift"; sourceTree = SOURCE_ROOT; };
        E90000000000000000000004 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "Lumen for Frigate/Services/InternalProQualification.swift"; sourceTree = SOURCE_ROOT; };''',1)
 start=s.index('\t\t'+phase+' /* Sources */ = {');end=s.index('\n\t\t};',start);part=s[start:end];assert '\t\t\tfiles = (' in part;part=part.replace('\t\t\tfiles = (','\t\t\tfiles = (\n                E90000000000000000000001,\n                E90000000000000000000002,',1);p.write_text(s[:start]+part+s[end:]);return paths

LUMEN_TV_PORTFOLIO='''
/// Hand App Store destinations to a phone; tvOS does not open web/store links here.
private struct LumenPortfolioTVView: View {
    @Environment(\\.locale) private var locale
    var body: some View {
        List {
            ForEach(LorisLabsApp.othersThan("com.lorislab.lumenforfrigate.tv.LumenTV")) { app in
                NavigationLink {
                    VStack(spacing: 32) {
                        Text(app.localizedName(locale: locale)).font(.title)
                        if let image = qr(app.appStoreURL) {
                            Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 360, height: 360).padding(24).background(.white)
                                .accessibilityLabel(locale.language.languageCode?.identifier == "fr" ? "Code QR App Store" : "App Store QR code")
                        }
                        Text(locale.language.languageCode?.identifier == "fr" ? "Scannez avec votre téléphone pour ouvrir l’App Store." : "Scan with your phone to open the App Store.")
                        Text(app.appStoreURL.absoluteString).font(.caption)
                    }.padding(40)
                } label: {
                    HStack(spacing: 24) {
                        if let url = app.iconURL, let icon = UIImage(contentsOfFile: url.path) {
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
        }.navigationTitle(PortfolioText.title(locale: locale))
    }
    private func qr(_ url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}
'''
