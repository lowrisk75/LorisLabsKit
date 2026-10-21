#!/usr/bin/env python3
"""Bounded, guarded local SDK rollout. Never commits, publishes or changes services."""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil,subprocess,sys,copy,fcntl,os
import portfolio_rollout_hosts as hosts
import portfolio_reserved_hosts as reserved
ROOT=Path('/Users/kevin/GitHub/LorisLabsKit')
PROOF=ROOT/'Qualification/PortfolioRollout-20261015'
STATE=PROOF/'STATE.json'
SOURCE=PROOF/'sdk-source'
TEMP=Path('/private/tmp/lorislabs-portfolio-sdk-20261015')

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None

BASELINES={}
def read_state():
 state=json.loads(STATE.read_text());BASELINES[id(state)]=copy.deepcopy(state);return state
def record_resource(state,resource):
 # Reusing a previously removed path must update the same object. Duplicates
 # can otherwise make a later checkpoint restore the old "removed" state.
 existing=next((r for r in state['resources'] if r['path']==resource['path']),None)
 if existing is not None:existing.update(resource);return existing
 state['resources'].append(resource);return resource
def save_state(state):
 # Different build processes must never overwrite another project's newer checkpoint.
 before=BASELINES.get(id(state),{})
 assert len({r['path'] for r in state['resources']})==len(state['resources']),'Duplicate resource identities must be reconciled before checkpointing'
 with (PROOF/'STATE.lock').open('a') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX);latest=json.loads(STATE.read_text())
  for field,value in state.items():
   if field in ['apps','resources']:continue
   if before.get(field)!=value:latest[field]=value
  for field,identity in [('apps','key'),('resources','path')]:
   previous={v[identity]:v for v in before.get(field,[])};current={v[identity]:v for v in latest.get(field,[])}
   for item in state.get(field,[]):
    old=previous.get(item[identity],{})
    if item==old:continue
    dest=current.setdefault(item[identity],{})
    for name,value in item.items():
     if old.get(name)!=value:dest[name]=value
   latest[field]=list(current.values())
  temporary=PROOF/('STATE.'+str(os.getpid())+'.tmp');temporary.write_text(json.dumps(latest,ensure_ascii=False,indent=2)+'\n');temporary.replace(STATE)
  BASELINES[id(state)]=copy.deepcopy(state)
def app_for(key):
 state=read_state();app=next(a for a in state['apps'] if a['key']==key)
 assert key.replace('-','').isalnum() and app['candidate']==str(TEMP/key)
 return state,app

def freeze_package(candidate,relative,products):
 dest=candidate/relative;dest.mkdir(parents=True,exist_ok=True)
 for product in products:shutil.copytree(SOURCE/'Sources'/product,dest/'Sources'/product,dirs_exist_ok=True)
 libs=',\n        '.join('.library(name: "'+p+'", targets: ["'+p+'"])' for p in products)
 targets=',\n        '.join('.target(name: "'+p+'", resources: [.process("Resources")])' for p in products)
 (dest/'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\n\n// Frozen canonical SDK source/resources; hashes recorded in UPSTREAM-ENGAGEMENT.json.\nlet package = Package(name: "LorisLabsKit", platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v17), .visionOS(.v1)],\n    products: [\n        '+libs+'\n    ], targets: [\n        '+targets+'\n    ])\n')
 provenance={'source':'LorisLabsKit local reviewed working tree','scope':products,'snapshotUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':{str(p.relative_to(dest)):digest(p) for p in (dest/'Sources').rglob('*') if p.is_file()}}
 (dest/'UPSTREAM-ENGAGEMENT.json').write_text(json.dumps(provenance,indent=2)+'\n')

def replace(path,before,after,count=1):
 s=path.read_text();assert s.count(before)==count,(str(path),before[:100],s.count(before));path.write_text(s.replace(before,after))

def prepare_typemetrics(candidate):
 freeze_package(candidate,'Packages/LorisLabsKit',['LorisLabsKit'])
 pbx=candidate/'TypeMetrics.xcodeproj/project.pbxproj'
 before='''\t\tA18CB15484CF6084C6802DC7 /* XCRemoteSwiftPackageReference "LorisLabsKit" */ = {
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/lowrisk75/LorisLabsKit.git";
\t\t\trequirement = {
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 0.8.0;
\t\t\t};
\t\t};
'''
 s=pbx.read_text();assert before in s;s=s.replace(before,'');s=s.replace('/* Begin XCLocalSwiftPackageReference section */','/* Begin XCLocalSwiftPackageReference section */\n\t\tA18CB15484CF6084C6802DC7 /* XCLocalSwiftPackageReference "LorisLabsKit" */ = {isa = XCLocalSwiftPackageReference; relativePath = Packages/LorisLabsKit; };');s=s.replace('XCRemoteSwiftPackageReference "LorisLabsKit"','XCLocalSwiftPackageReference "LorisLabsKit"');pbx.write_text(s)
 app=candidate/'TypeMetrics/TypeMetricsApp.swift';s=app.read_text().replace('import GameKit','import GameKit\nimport LorisLabsKit',1).replace('''    init() {
''','''    init() {
        _ = TypeMetricsEngagement.reviews
''',1);s+='''
/// One private review history per app, independent of scores, purchases and learner content.
@MainActor
enum TypeMetricsEngagement {
    static let reviews = SmartReviewPromptManager(bundleIdentifier: "com.LorisLabs.typemetrics")
    static func completedPractice(isAdult: Bool) {
        guard isAdult else { reviews.cancelPendingReview(); return }
        reviews.recordCompletedAction()
    }
}
''';app.write_text(s)
 model=candidate/'ViewModel/TypingTestViewModel.swift';replace(model,'        saveSession()\n','''        saveSession()
        if hasStartedTyping && !typedText.isEmpty {
            TypeMetricsEngagement.completedPractice(isAdult: activeProfile?.learnerGroup == .adult)
        }
''')
 results=candidate/'View/ResultsView.swift';replace(results,'import SwiftUI','import SwiftUI\nimport LorisLabsKit');replace(results,'        .onAppear { SoundManager.shared.playSuccess() }','''        .onAppear { SoundManager.shared.playSuccess() }
        .reviewPromptWhenIdle(TypeMetricsEngagement.reviews, isIdle: profile?.learnerGroup == .adult)''')
 typing=candidate/'View/TypingTestView.swift';s=typing.read_text();s=s.replace('import SwiftUI','import SwiftUI\nimport LorisLabsKit',1);needle='''                fingerPathHistory: []
            )''';assert needle in s;s=s.replace(needle,needle+'''\n            .reviewPromptWhenIdle(TypeMetricsEngagement.reviews, isIdle: viewModel.activeProfile?.learnerGroup == .adult)''',1);typing.write_text(s)
 settings=candidate/'View/SettingsView.swift';s=settings.read_text().replace('import TypeMetricsFeedbackSDK','import TypeMetricsFeedbackSDK\nimport LorisLabsKit',1);s=s.replace('    @State private var showProductSupport = false','    @State private var showProductSupport = false\n    @State private var showOtherApps = false\n    @Environment(\\.locale) private var locale')
 s=s.replace('''                Button("Visit Website") { askParent(.open(Self.websiteURL)) }''','''                Button("Visit Website") { askParent(.open(Self.websiteURL)) }
                Button { askParent(.otherApps) } label: {
                    Label(PortfolioText.title(locale: locale), systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("typemetrics.apps.open")''')
 s=s.replace('''        .sheet(isPresented: $showProductSupport) {''','''        .sheet(isPresented: $showOtherApps) {
            NavigationStack {
                LorisLabsAppsMenu(currentBundleIdentifier: "com.LorisLabs.typemetrics")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Close") { showOtherApps = false }
                        }
                    }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
        }
        .sheet(isPresented: $showProductSupport) {''');s=s.replace('        case support\n','        case support\n        case otherApps\n');s=s.replace('''        case .export:
''','''        case .otherApps: showOtherApps = true
        case .export:
''',1);settings.write_text(s)
 return ['TypeMetrics.xcodeproj/project.pbxproj','TypeMetrics/TypeMetricsApp.swift','ViewModel/TypingTestViewModel.swift','View/ResultsView.swift','View/TypingTestView.swift','View/SettingsView.swift','Packages/LorisLabsKit']

def prepare_bridge(candidate):
 # Its existing SDK snapshot already matches canonical engagement. Preserve all other modules.
 src=candidate/'LumenBridge/Services/BridgeSupport.swift';s=src.read_text();start=s.index('                    ForEach(LorisLabsApp.othersThan(');end=s.index('\n                }\n            }',start)
 s=s[:start]+'''                    LorisLabsAppsLink(currentBundleIdentifier: "com.lorislabapp.lumenbridge")'''+s[end:]
 start=s.index('struct BridgeReviewOpportunity: ViewModifier {');s=s[:start]+'''struct BridgeReviewOpportunity: ViewModifier {
    let interactionInProgress: Bool
    func body(content: Content) -> some View {
        content.reviewPromptWhenIdle(BridgeSupport.review,
            isIdle: !interactionInProgress, additionalEligibility: { NSApp.modalWindow == nil
                && !NSApp.windows.contains(where: { $0.attachedSheet != nil })
                && !OnboardingWindowPresenter.shared.isVisible && !BridgeSupportWindow.shared.isVisible })
    }
}
''';src.write_text(s)
 return ['LumenBridge/Services/BridgeSupport.swift']

def prepare_weave(candidate):
 freeze_package(candidate,'Packages/LorisLabsKit',['LorisLabsKit','LorisReports'])
 replace(candidate/'project.yml','path: ../../LorisLabsKit','path: Packages/LorisLabsKit')
 p=candidate/'Weave.xcodeproj/project.pbxproj';s=p.read_text();assert 'relativePath = ../../LorisLabsKit;' in s;s=s.replace('../../LorisLabsKit','Packages/LorisLabsKit');p.write_text(s)
 p=candidate/'Sources/Core/LorisLabsIntegration.swift';s=p.read_text()
 s=s.replace('''    /// A usable remote stream is one meaningful success. Repeated state updates
    /// within the same connection never increment the counter again.''','''    /// A completed usable remote session creates one opportunity, after disconnect.
    /// Repeated status updates and abandoned connections never increment it.''')
 s=s.replace('                review.recordSuccessMoment()\n','')
 s=s.replace('            countedInteractions.remove(id)','            if countedInteractions.remove(id) != nil { review.recordCompletedAction() }')
 start=s.index('struct WeaveReviewPromptCoordinator: View {');end=s.index('\nstruct WeaveHelpSettingsView',start)
 s=s[:start]+'''struct WeaveReviewPromptCoordinator: View {
    @Environment(SmartReviewPromptManager.self) private var review
    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .reviewPromptWhenIdle(review)
    }
}
'''+s[end:]
 s=s.replace('    @Environment(\\.requestReview) private var requestReview\n','')
 start=s.index('                Section(String(localized: "Reviews"');end=s.index('                Section(String(localized: "More from LorisLabs"',start);s=s[:start]+s[end:]
 s=s.replace('MoreFromLorisLabsView(currentBundleIdentifier: currentBundleIdentifier)','LorisLabsAppsLink(currentBundleIdentifier: currentBundleIdentifier)');p.write_text(s)
 return ['project.yml','Weave.xcodeproj/project.pbxproj','Sources/Core/LorisLabsIntegration.swift','Packages/LorisLabsKit']

PREPARERS={'typemetrics':prepare_typemetrics,'lumen-bridge':prepare_bridge,'weave':prepare_weave,'404':lambda c:hosts.prepare_404(c,SOURCE),'kiosk':lambda c:hosts.prepare_kiosk(c,freeze_package)}
PREPARERS['velya']=lambda c:hosts.prepare_velya(c,freeze_package)
PREPARERS['aurorapulse']=lambda c:hosts.prepare_aurora(c,freeze_package)
def prepare_seve_coordinator(candidate):
 # Seve already has its reviewed integration and a separate frozen Reports fork.
 # Refresh only the later Core API addition and the corresponding provenance hash.
 relative='Packages/LorisLabsKit/Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift'
 source=SOURCE/'Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift'
 assert digest(source)==digest(ROOT/'Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift')
 provenance=candidate/'Packages/LorisLabsKit/UPSTREAM.json'
 record=json.loads(provenance.read_text())
 source_relative='Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift'
 assert digest(candidate/relative)==record['files'][source_relative], 'Unrecorded Seve coordinator changes'
 shutil.copy2(source,candidate/relative)
 record['files'][source_relative]=digest(source)
 record.setdefault('followups',[]).append({'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'scope':'Core coordinator additionalEligibility API only; original Reports and host sources preserved',
  'files':{source_relative:digest(source)}})
 provenance.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
 return [relative,'Packages/LorisLabsKit/UPSTREAM.json']

PREPARERS['seve']=prepare_seve_coordinator
PREPARERS['entrofold']=lambda c:hosts.prepare_entrofold(c,freeze_package)
PREPARERS['kernel']=lambda c:reserved.prepare_kernel(c,SOURCE)
PREPARERS['filova']=reserved.prepare_filova
PREPARERS['clasp']=lambda c:reserved.prepare_clasp(c,SOURCE)
for reservedkey in ['millrace','siliconpass','vif']:
 PREPARERS[reservedkey]=lambda c,k=reservedkey:getattr(reserved,'prepare_'+k)(c,SOURCE)
for reservedkey in ['lumen','sinkhole']:
 PREPARERS[reservedkey]=lambda c,k=reservedkey:getattr(reserved,'prepare_'+k)(c,freeze_package)
for newkey in ['kalou','rampart','halte','mela','aegis']:
 PREPARERS[newkey]=lambda c,k=newkey:hosts.prepare_new(c,k,freeze_package)
BUILDS={
 'seve':[('iOS',['-project','PRISM.xcodeproj','-scheme','PRISM','-configuration','Release','-destination','generic/platform=iOS'])],
 'lumen':[(lane,['-project','Lumen for Frigate.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','LumenMac','generic/platform=macOS'),('iOS','Lumen for Frigate','generic/platform=iOS'),('tvOS','LumenTV','generic/platform=tvOS')]],
 'sinkhole':[('iOS',['-project','Sinkhole.xcodeproj','-scheme','Sinkhole','-configuration','Release','-destination','generic/platform=iOS']),('Home-macOS',[])],
 'millrace':[(lane,['-project','Millrace/Millrace.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','Millrace','generic/platform=macOS'),('iOS','MillraceCompanion','generic/platform=iOS')]],
 'siliconpass':[(lane,['-project','SiliconPass.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','SiliconPass-macOS','generic/platform=macOS'),('iOS','SiliconPass-iOS','generic/platform=iOS')]],
 'vif':[(lane,['-project','apple/Vif.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','Vif (macOS)','generic/platform=macOS'),('iOS','Vif (iOS)','generic/platform=iOS')]],
 'clasp':[(lane,['-project','Clasp 2.xcodeproj','-scheme','Clasp','-configuration','Release','-destination',destination]) for lane,destination in [('macOS','generic/platform=macOS'),('iOS','generic/platform=iOS')]],
 'kernel':[(lane,['-project','Kernel.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','Kernel','generic/platform=macOS'),('iOS','KernelMobile','generic/platform=iOS')]],
 'filova':[(lane,['-project','Filova.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','FilovaMac','generic/platform=macOS'),('iOS','Filova','generic/platform=iOS')]],
 'entrofold':[('macOS',['-project','EntroFoldArchive/EntroFold Archive.xcodeproj','-scheme','EntroFold Archive','-configuration','Release','-destination','generic/platform=macOS'])],
 'aurorapulse':[('iOS',['-project','AuroraPulse.xcodeproj','-scheme','AuroraPulse','-configuration','Release','-destination','generic/platform=iOS'])],
 'kalou':[('iOS',['-project','Kalou.xcodeproj','-scheme','Kalou','-configuration','Release','-destination','generic/platform=iOS'])],
 'mela':[('iOS',['-project','Mela.xcodeproj','-scheme','Mela','-configuration','Release','-destination','generic/platform=iOS'])],
 'halte':[('iOS',['-project','Halte.xcodeproj','-scheme','Halte','-configuration','Release','-destination','generic/platform=iOS'])],
 'rampart':[(lane,['-project','Rampart.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','Rampart_macOS','generic/platform=macOS'),('iOS','Rampart_iOS','generic/platform=iOS')]],
 'aegis':[(lane,['-project','Aegis.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('macOS','Aegis-macOS','generic/platform=macOS'),('iOS','Aegis-iOS','generic/platform=iOS')]],
 'velya':[('iOS',['-project','Velya.xcodeproj','-scheme','Velya','-configuration','Release','-destination','generic/platform=iOS'])],
 'kiosk':[(lane,['-project','Kiosk.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for lane,scheme,destination in [('KioskBridge','KioskBridge','generic/platform=macOS'),('KioskAdmin','KioskAdmin','generic/platform=iOS'),('KioskTV','KioskStoreCaptureTV','generic/platform=tvOS'),('KioskDisplay','KioskDisplay','generic/platform=iOS'),('KioskDisplayMac','KioskDisplayMac','generic/platform=macOS'),('KioskBridgeQA','KioskStoreCaptureMac','generic/platform=macOS')]],
 '404':[(lane,['-project','404.xcodeproj','-scheme','404','-configuration','Release','-destination',destination]) for lane,destination in [('macOS','generic/platform=macOS'),('iOS','generic/platform=iOS')]],
 'typemetrics':[('macOS',['-project','TypeMetrics.xcodeproj','-scheme','TypeMetrics','-configuration','Release','-destination','generic/platform=macOS']),('iOS',['-project','TypeMetrics.xcodeproj','-scheme','TypeMetrics','-configuration','Release','-destination','generic/platform=iOS'])],
 'lumen-bridge':[('macOS',['-project','LumenBridge.xcodeproj','-scheme','LumenBridge','-configuration','Release','-destination','generic/platform=macOS'])],
 'weave':[(name,['-project','Weave.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination]) for name,scheme,destination in [('Host-macOS','WeaveHost','generic/platform=macOS'),('Viewer-macOS','WeaveViewer','generic/platform=macOS'),('Mobile-iOS','WeaveMobile','generic/platform=iOS')]]
}

def prepare(key):
 state,app=app_for(key);candidate=Path(app['candidate']);assert app['status']=='candidate-captured'
 touched=PREPARERS[key](candidate);write_plan(state,app,touched)

def write_plan(state,app,touched):
 key=app['key'];candidate=Path(app['candidate']);appProof=PROOF/key;plan=[]
 baseline=json.loads((appProof/'BASELINE.json').read_text())
 for relative in touched:
  source=candidate/relative
  files=[source] if source.is_file() else [p for p in source.rglob('*') if p.is_file()]
  for path in files:
   rel=str(path.relative_to(candidate));before=baseline.get(rel);after=digest(path)
   if before!=after:plan.append({'path':rel,'before':before,'after':after})
 (appProof/'PLAN.json').write_text(json.dumps(plan,indent=2)+'\n');app['status']='prepared';app['completed'].append('Host menu and conservative review hooks prepared; existing support preserved');save_state(state);print(key,'prepared',len(plan),'files',flush=True)

def generate(key):
 state,app=app_for(key);assert key=='kiosk' and app['status']=='candidate-captured';candidate=Path(app['candidate'])
 with (PROOF/key/'xcodegen.log').open('w') as log:subprocess.run(['xcodegen','generate'],cwd=candidate,stdout=log,stderr=subprocess.STDOUT,check=True)
 write_plan(state,app,['project.yml','Kiosk.xcodeproj/project.pbxproj','Apps/KioskAdmin/AdminDashboardView.swift','Apps/KioskBridge/BridgeAdminView.swift','Apps/KioskTV/Overlays/DisplayMenuView.swift','Packages/LorisLabsKit'])

def replan(key):
 state,app=app_for(key);assert app['status'] in ['prepared','build-failed','validated']
 plan=json.loads((PROOF/key/'PLAN.json').read_text())
 write_plan(state,app,[e['path'] for e in plan])

def artifacts(key):
 state,app=app_for(key);assert key=='aegis' and app['status']=='prepared'
 build=Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'
 if not any(r['path']==str(build) for r in state['resources']):state['resources'].append({'kind':'buildDirectory','path':str(build),'state':'active','purpose':'Isolated host build and copied existing Rust libraries'});save_state(state)
 dest=build/'existing-rust';proof={}
 for triple in ['universal-apple-darwin','aarch64-apple-ios']:
  for name in ['libaegis_crypto_core.a','libaegis_vault_format.a']:
   source=Path(app['root'])/'target'/triple/'release'/name;target=dest/triple/'release'/name
   target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target);proof[str(source)]={'sha256':digest(source),'copySHA256':digest(target)}
 link=Path(app['candidate'])/'target';assert not link.exists();link.symlink_to(dest,target_is_directory=True)
 (PROOF/key/'prebuilt-rust.json').write_text(json.dumps(proof,indent=2)+'\n')

def refresh(key):
 state,app=app_for(key);candidate=Path(app['candidate']);assert app['status'] in ['prepared','validated']
 proof=PROOF/key;plan=json.loads((proof/'PLAN.json').read_text());paths={e['path'] for e in plan}
 relative='Packages/LorisLabsKit/Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift'
 shutil.copy2(SOURCE/'Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift',candidate/relative);paths.add(relative)
 provenance=candidate/'Packages/LorisLabsKit/UPSTREAM-ENGAGEMENT.json'
 if provenance.exists():
  d=json.loads(provenance.read_text());d['files']['Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift']=digest(candidate/relative);provenance.write_text(json.dumps(d,indent=2)+'\n');paths.add(str(provenance.relative_to(candidate)))
 if key=='lumen-bridge':
  p=candidate/'LumenBridge/Services/BridgeSupport.swift'
  replace(p,'isIdle: !interactionInProgress && NSApp.modalWindow == nil','isIdle: !interactionInProgress, additionalEligibility: { NSApp.modalWindow == nil')
  replace(p,'&& !OnboardingWindowPresenter.shared.isVisible && !BridgeSupportWindow.shared.isVisible)','&& !OnboardingWindowPresenter.shared.isVisible && !BridgeSupportWindow.shared.isVisible })')
 plan=[{'path':r,'before':digest(Path(app['root'])/r),'after':digest(candidate/r)} for r in sorted(paths) if digest(Path(app['root'])/r)!=digest(candidate/r)]
 (proof/'PLAN.json').write_text(json.dumps(plan,indent=2)+'\n');app['status']='prepared';app['completed'].append('Native modal state rechecked at attempt time, including changes during pause');save_state(state)

def capture(key):
 # Capturing reads the host and writes only our isolated candidate. The apply gate
 # remains closed while another writer owns the live checkout.
 state=read_state();app=next(a for a in state['apps'] if a['key']==key);assert app['status']=='inspected'
 candidate=TEMP/key;assert not candidate.exists();proof=PROOF/key;proof.mkdir(exist_ok=True)
 app['candidate']=str(candidate);record_resource(state,{'kind':'sourceCandidate','path':str(candidate),'state':'active','createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat()});save_state(state)
 excluded={'.git','.build','build','target','DerivedData','node_modules','.agents','.codex','.claude','audit-output','Qualification'}
 def ignore(parent,names):return [n for n in names if n in excluded or n.endswith(('.xcarchive','.xcresult','.zip'))]
 root=Path(app['root']);shutil.copytree(root,candidate,ignore=ignore)
 baseline={str(p.relative_to(candidate)):digest(p) for p in candidate.rglob('*') if p.is_file() and p.name!='.DS_Store'}
 drift=[rel for rel,h in baseline.items() if digest(root/rel)!=h]
 (proof/'BASELINE.json').write_text(json.dumps(baseline,indent=2)+'\n')
 app['captureDrift']=drift;app['status']='candidate-captured' if not drift else 'capture-unstable'
 app['completed'].append('Independent source candidate captured without writing to the host; copy hashes compared with live files');save_state(state);print(key,'captured',len(baseline),'files; source drift',len(drift))
 assert not drift,'Host changed during source capture; inspect/rebase before preparation'

def resume(key):
 state=read_state();assert not TEMP.exists()
 now=datetime.datetime.now(datetime.timezone.utc).isoformat()
 resource=next(r for r in state['resources'] if r['path']==str(TEMP));resource.update(state='active',createdAt=now,purpose='Continuation: isolated candidates for reserved hosts')
 state['resumedAt']=now;state['missionStatus']='Preparing reserved hosts in isolated copies; live writing remains with existing sessions';save_state(state)
 TEMP.mkdir(mode=0o700)

def mirror(key):
 state=read_state();dest=TEMP/'LorisLabsKit';assert not dest.exists()
 record_resource(state,{'kind':'sourceSDK','path':str(dest),'state':'active','createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':'Read-only dependency mirror for isolated hosts with sibling SDK references'});save_state(state)
 dest.mkdir();shutil.copy2(ROOT/'Package.swift',dest/'Package.swift')
 for folder in ['Sources','Tests']:shutil.copytree(ROOT/folder,dest/folder,ignore=shutil.ignore_patterns('.DS_Store','__pycache__'))
 (PROOF/'SDK-MIRROR-HASHES.json').write_text(json.dumps({str(p.relative_to(dest)):digest(p) for p in dest.rglob('*') if p.is_file()},indent=2)+'\n')
 print('Canonical SDK mirrored for source-isolated builds')

def cleanup(key):
 state,app=app_for(key);assert app['status']=='applied'
 for resource in state['resources']:
  p=Path(resource['path'])
  if resource['state']=='active' and (p==TEMP/key or p==Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'):
   shutil.rmtree(p,ignore_errors=False);resource['state']='removed'
 app['status']='complete';app['candidateStatus']='applied-and-cleaned';app['remaining']=[];save_state(state);print(key,'own resources removed')

def finish(key):
 state=read_state()
 assert all(a['status']=='complete' for a in state['apps'] if a['writer']!='active-other-session')
 for resource in state['resources']:
  if resource['kind']=='toolJob' and resource.get('project')=='404':resource['state']='completed'
  if resource['state']!='active':continue
  p=Path(resource['path'])
  if resource['kind']=='sourceDirectory' and p==TEMP:
   if p.exists():
    assert not any(p.iterdir()),'source parent must be empty';p.rmdir()
   else:resource['alreadyAbsentAtCleanup']=True
   resource['state']='removed'
  elif resource['kind']=='buildDirectory' and p==Path('/Volumes/DeveloperStorage/BuildScratch/Auto/LorisLabsKit/portfolio-sdk-20261015'):
   if p.exists():shutil.rmtree(p)
   else:resource['alreadyAbsentAtCleanup']=True
   resource['state']='removed'
 assert not [r for r in state['resources'] if r['state']=='active']
 state['localRolloutFinishedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 state['remainingScope']='Eight reserved checkouts retain their existing writers; native UI, signed distribution and any new support activation remain separately unqualified.'
 save_state(state);print('All owned temporary source/build resources removed; reserved checkouts untouched')

def build(key):
 state,app=app_for(key);assert app['status'] in ['prepared','build-failed'];candidate=Path(app['candidate']);build=Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'
 app['status']='validating';save_state(state)
 existing=next((r for r in state['resources'] if r['path']==str(build)),None)
 if existing is None:
  assert not build.exists(),'Unrecorded build folder already exists'
  state['resources'].append({'kind':'buildDirectory','path':str(build),'state':'active','createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat()});save_state(state)
 elif existing['state']!='active':
  assert not build.exists(),'Removed mission build folder was recreated by another owner'
  existing.update(state='active',createdAt=datetime.datetime.now(datetime.timezone.utc).isoformat());save_state(state)
 for lane,args in BUILDS[key]:
  log=PROOF/key/(lane+'-build.log');archive_log(state,app,log);command=['xcodebuild',*args,'-derivedDataPath',str(build),'CODE_SIGNING_ALLOWED=NO','build']
  if key=='sinkhole' and lane=='Home-macOS':command=['swift','build','--package-path',str(candidate/'Home/MacApp'),'--scratch-path',str(build/'home'),'-c','release']
  env=os.environ.copy()
  if key=='velya':env['LORISIOT_PACKAGE_PATH']='/Users/kevin/GitHub/LorisIoT'
  try:
   with log.open('w') as output:
    process=subprocess.Popen(command,cwd=candidate,env=env,stdout=output,stderr=subprocess.STDOUT)
    resource={'kind':'process','path':'pid:'+str(process.pid),'state':'active','createdAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'purpose':key+' '+lane+' isolated xcodebuild'}
    resource=record_resource(state,resource);save_state(state)
    try:code=process.wait(timeout=1800)
    except subprocess.TimeoutExpired:
     process.terminate()
     try:process.wait(timeout=20)
     except subprocess.TimeoutExpired:process.kill();process.wait()
     raise
    finally:resource['state']='completed';save_state(state)
  except subprocess.TimeoutExpired:
   app['status']='build-failed';app['blockers'].append(lane+' build timed out; no result claimed');save_state(state);raise
  app['validations'].append({'lane':lane,'check':'Release build unsigned','exitCode':code,'log':str(log.relative_to(ROOT))});app['status']='validating' if code==0 else 'build-failed';save_state(state);print(key,lane,code,flush=True)
  if code:raise SystemExit(code)
 app['status']='validated';app['remaining']=(['writer handoff, fresh live-source rebase and revalidation'] if app['writer']=='active-other-session' else [])+['apply with hash guards','cleanup'];save_state(state)

def engagement_tests(key):
 state,app=app_for(key);assert key in ['kernel','clasp'] and app['status'] in ['validated','build-failed']
 relative={'kernel':'Dependencies/KernelEngagement','clasp':'LorisLabsKit'}[key]
 build=Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'/'engagement-tests'
 assert any(r['path']==str(build.parent) for r in state['resources'])
 log=PROOF/key/'engagement-tests.log';archive_log(state,app,log)
 command=['swift','test','--package-path',str(Path(app['candidate'])/relative),'--scratch-path',str(build),'-c','release','--filter','ReviewPolicyTests|SmartReviewPromptManagerTests|LorisLabsAppTests']
 with log.open('w') as output:
  process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
  resource={'kind':'process','path':'pid:'+str(process.pid),'state':'active','purpose':key+' isolated engagement tests'};resource=record_resource(state,resource);save_state(state)
  try:code=process.wait(timeout=900)
  except subprocess.TimeoutExpired:
   process.terminate();process.wait(timeout=20);raise
  finally:resource['state']='completed';save_state(state)
 app['validations'].append({'check':'Embedded engagement policy and catalogue tests','exitCode':code,'log':str(log.relative_to(ROOT))});save_state(state);print(key,'engagement tests',code);assert code==0

def archive_log(state,app,log):
 if not log.exists():return
 n=1
 while log.with_name(log.stem+'-previous-'+str(n)+log.suffix).exists():n+=1
 previous=log.with_name(log.stem+'-previous-'+str(n)+log.suffix);log.rename(previous)
 for validation in app['validations']:
  if validation.get('log')==str(log.relative_to(ROOT)):validation['log']=str(previous.relative_to(ROOT))
 save_state(state)

def filova_contracts(key):
 assert key=='filova'
 import portfolio_host_contracts
 portfolio_host_contracts.filova_contracts(sys.modules[__name__])

def clean_contracts(key):
 assert key=='filova'
 import portfolio_host_contracts
 portfolio_host_contracts.clean_filova_contracts(sys.modules[__name__])

def millrace_tests(key):
 assert key=='millrace'
 import portfolio_host_contracts
 portfolio_host_contracts.millrace_tests(sys.modules[__name__])

def support_build(key):
 state,app=app_for(key);assert key=='vif' and app['status']=='build-failed'
 build=Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'
 assert any(r['path']==str(build) for r in state['resources'])
 log=PROOF/key/'support-build.log';archive_log(state,app,log)
 command=['swift','build','--package-path',str(Path(app['candidate'])/'apple/Packages/VifFeedbackSDK'),'--scratch-path',str(build/'support'),'-c','release']
 with log.open('w') as output:
  process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
  resource={'kind':'process','path':'pid:'+str(process.pid),'state':'active','purpose':key+' isolated support package build'};resource=record_resource(state,resource);save_state(state)
  try:code=process.wait(timeout=900)
  except subprocess.TimeoutExpired:
   process.terminate();process.wait(timeout=20);raise
  finally:resource['state']='completed';save_state(state)
 app['validations'].append({'check':'Support/Core package Release build only; full host FFI gate remains unqualified','exitCode':code,'log':str(log.relative_to(ROOT))});save_state(state);print(key,'support package build',code);assert code==0

def help_qualification(key):
 state,app=app_for(key);assert key=='vif' and app['status']=='build-failed'
 candidate=Path(app['candidate']);folder=candidate/'SDKHelpQualification';folder.mkdir(exist_ok=False)
 hashes={}
 for name in ['VifHelpView.swift','VifNotices.swift']:
  source=candidate/'apple/Shared'/name;shutil.copy2(source,folder/name);hashes[name]=digest(source)
 (PROOF/key/'HELP-SOURCE-HASHES.json').write_text(json.dumps(hashes,indent=2)+'\n')
 (folder/'HelpApp.swift').write_text('import SwiftUI\n@main struct HelpApp: App { var body: some Scene { WindowGroup { NavigationStack { VifHelpView() } } } }\n')
 yml='''name: VifHelpQualification
options:
  deploymentTarget:
    iOS: "17.0"
    macOS: "14.0"
settings:
  base:
    SWIFT_VERSION: "6.0"
    GENERATE_INFOPLIST_FILE: YES
packages:
  VifFeedbackSDK:
    path: ../apple/Packages/VifFeedbackSDK
targets:
'''
 for lane,platform in [('Mac','macOS'),('Mobile','iOS')]:
  yml+='''  Help'''+lane+''':
    type: application
    platform: '''+platform+'''
    sources: [HelpApp.swift, VifHelpView.swift, VifNotices.swift]
    dependencies:
      - package: VifFeedbackSDK
        product: VifSupport
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.lorislab.qualification.vifhelp.'''+lane.lower()+'''\n'''
 (folder/'project.yml').write_text(yml)
 log=PROOF/key/'help-xcodegen.log'
 with log.open('w') as output:subprocess.run(['xcodegen','generate'],cwd=folder,stdout=output,stderr=subprocess.STDOUT,check=True)
 for lane,scheme,destination in [('macOS','HelpMac','generic/platform=macOS'),('iOS','HelpMobile','generic/platform=iOS')]:
  state,app=app_for(key);build=Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015'
  log=PROOF/key/('help-'+lane+'-build.log')
  command=['xcodebuild','-project','VifHelpQualification.xcodeproj','-scheme',scheme,'-configuration','Release','-destination',destination,'-derivedDataPath',str(build/'help'),'CODE_SIGNING_ALLOWED=NO','build']
  with log.open('w') as output:
   process=subprocess.Popen(command,cwd=folder,stdout=output,stderr=subprocess.STDOUT)
   resource={'kind':'process','path':'pid:'+str(process.pid),'state':'active','purpose':key+' '+lane+' help-only build'};resource=record_resource(state,resource);save_state(state)
   try:code=process.wait(timeout=900)
   except subprocess.TimeoutExpired:
    process.terminate();process.wait(timeout=20);raise
   finally:resource['state']='completed';save_state(state)
  app['validations'].append({'lane':lane,'check':'Exact help/notices source qualification build only; full host FFI gate remains unqualified','exitCode':code,'log':str(log.relative_to(ROOT))});save_state(state);print(key,lane,'help build',code,flush=True);assert code==0

def export_candidate(key):
 import difflib
 state,app=app_for(key);assert app['status'] in ['validated','build-failed']
 authorized=app['writer']=='Codex-exclusive-confirmed'
 assert app['writer']=='active-other-session' or (authorized and app['status']=='validated')
 proof=PROOF/key;candidate=Path(app['candidate']);plan=json.loads((proof/'PLAN.json').read_text());dest=proof/'candidate-files';dest.mkdir(exist_ok=True)
 baseline=json.loads((proof/'BASELINE.json').read_text())
 baseline_conflicts=[rel for rel,expected in baseline.items() if digest(Path(app['root'])/rel)!=expected]
 conflicts=[];patch=[]
 for entry in plan:
  rel=entry['path'];after=candidate/rel;assert digest(after)==entry['after'],'candidate changed after plan: '+rel
  target=dest/rel;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(after,target);assert digest(target)==entry['after']
  live=Path(app['root'])/rel
  if digest(live)!=entry['before']:conflicts.append(rel);continue
  old=live.read_bytes() if live.is_file() else b'';new=after.read_bytes()
  try:before=old.decode('utf-8');nexttext=new.decode('utf-8')
  except UnicodeDecodeError:continue
  patch+=difflib.unified_diff(before.splitlines(keepends=True),nexttext.splitlines(keepends=True),fromfile='a/'+rel if old else '/dev/null',tofile='b/'+rel)
 (proof/'REVIEW.patch').write_text(''.join(patch))
 requirements='Exclusive writer transfer, fresh live-source rebase, validation and new guarded plan before applying'
 if authorized:requirements='Fresh baseline and exact candidate guards before application'
 if baseline_conflicts:requirements='Live source changed since capture; fresh source reconciliation and revalidation required before application'
 capsule={'exportedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'sourceRoot':app['root'],'applicationAllowed':authorized and not conflicts and not baseline_conflicts,'requires':requirements,'files':len(plan),'liveChangedPlanFiles':conflicts,'liveChangedBaselineFiles':baseline_conflicts,'validations':app['validations'],'status':app['status'],'scope':'Changed SDK and host source only; no private session transcript; review patch omits paths changed by the existing writer'}
 (proof/'CANDIDATE.json').write_text(json.dumps(capsule,ensure_ascii=False,indent=2)+'\n');app['capsule']=str(proof.relative_to(ROOT));app['liveChangedPlanFiles']=conflicts;app['liveChangedBaselineFiles']=baseline_conflicts;app['completed'].append('Changed candidate source and reviewable diffs exported durably; live hosts untouched');save_state(state);print(key,'exported',len(plan),'files;',len(conflicts),'live plan conflicts;',len(baseline_conflicts),'live baseline conflicts')

def clean_candidate(key):
 state,app=app_for(key);assert app['writer']=='active-other-session' and app.get('capsule')
 proof=PROOF/key;plan=json.loads((proof/'PLAN.json').read_text())
 for e in plan:assert digest(proof/'candidate-files'/e['path'])==e['after'],'export must be verified before cleanup'
 assert not [r for r in state['resources'] if r['kind']=='process' and r['state']=='active' and r.get('purpose','').startswith(key+' ')]
 for resource in state['resources']:
  p=Path(resource['path'])
  if resource['state']=='active' and p in [TEMP/key,Path('/Volumes/DeveloperStorage/BuildScratch/Auto')/key/'portfolio-sdk-20261015']:
   shutil.rmtree(p);resource['state']='removed'
 app['candidateStatus']='exported-and-cleaned';app['remaining']=['writer handoff','fresh live-source rebase from capsule and revalidation','guarded application'];save_state(state);print(key,'owned candidate/build resources removed; capsule retained')

def clean_mirror(key):
 state=read_state();assert not [r for r in state['resources'] if r['kind']=='sourceCandidate' and r['state']=='active']
 for resource in state['resources']:
  p=Path(resource['path'])
  if resource['state']=='active' and resource['kind']=='sourceSDK' and p==TEMP/'LorisLabsKit':shutil.rmtree(p);resource['state']='removed'
 resource=next(r for r in state['resources'] if r['path']==str(TEMP));assert not any(TEMP.iterdir());TEMP.rmdir();resource['state']='removed'
 applied=sum(a['status'] in ['applied','complete'] for a in state['apps']);reserved_count=sum(a['writer']=='active-other-session' for a in state['apps'])
 state['missionStatus']=f'{applied} live integrations applied; {reserved_count} reserved candidates exported, pending exclusive writer transfer and fresh rebase';save_state(state);print('Owned temporary source parent removed; no source candidates remain')

def apply(key):
 state,app=app_for(key);assert app['writer']!='active-other-session','writer handoff pending';assert app['status']=='validated'
 candidate=Path(app['candidate']);live=Path(app['root']);appProof=PROOF/key;plan=json.loads((appProof/'PLAN.json').read_text());baseline=json.loads((appProof/'BASELINE.json').read_text())
 for rel,expected in baseline.items():assert digest(live/rel)==expected,'live file changed during qualification: '+rel
 for entry in plan:
  relative=Path(entry['path']);assert not relative.is_absolute() and '..' not in relative.parts
  assert digest(live/relative)==entry['before'];assert digest(candidate/relative)==entry['after']
 backup=appProof/'before-apply';backup.mkdir(exist_ok=False)
 written=[]
 try:
  for entry in plan:
   relative=entry['path'];target=live/relative;before=backup/relative
   assert digest(target)==entry['before'],'live file changed immediately before write: '+relative
   if target.exists():before.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(target,before)
   target.parent.mkdir(parents=True,exist_ok=True);written.append(entry);shutil.copy2(candidate/relative,target)
   assert digest(target)==entry['after']
  changed={e['path'] for e in plan}
  for relative,expected in baseline.items():
   if relative not in changed:assert digest(live/relative)==expected
 except BaseException:
  for entry in reversed(written):
   target=live/entry['path'];before=backup/entry['path']
   if before.exists():shutil.copy2(before,target)
   else:target.unlink(missing_ok=True)
  raise
 app['status']='applied';app['completed'].append('Applied exact candidate with hash guards; all unrelated baseline source/configuration files preserved');app['remaining']=['cleanup'];save_state(state);(appProof/'APPLIED.json').write_text(json.dumps({'appliedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'files':len(plan),'hashesMatch':True,'unrelatedBaselinePreserved':True},indent=2)+'\n');print(key,'applied',len(plan),'files',flush=True)

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('action',choices=['resume','mirror','capture','prepare','generate','replan','artifacts','refresh','build','engagement_tests','filova_contracts','clean_contracts','millrace_tests','support_build','help_qualification','export_candidate','clean_candidate','clean_mirror','apply','cleanup','finish']);parser.add_argument('key',choices=[a['key'] for a in read_state()['apps']]);args=parser.parse_args();globals()[args.action](args.key)
