"""Bounded host contract checks. Never writes a live app checkout."""
from pathlib import Path
import datetime, json, os, shutil, subprocess


def filova_contracts(rollout):
    state, app = rollout.app_for('filova')
    proof = rollout.PROOF / 'filova'
    harness = proof / 'HostContracts'
    assert not harness.exists(), 'Keep prior evidence; choose a new checkpoint for a rerun'
    build = Path('/Volumes/DeveloperStorage/BuildScratch/Auto/Filova/portfolio-sdk-contracts-20261015')
    assert not build.exists()
    resource = {'kind': 'buildDirectory', 'path': str(build), 'state': 'active',
                'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'purpose': 'Isolated Filova service contracts, no app launch or live checkout write'}
    resource = rollout.record_resource(state, resource)
    rollout.save_state(state)
    source = harness / 'Sources/Filova'
    tests = harness / 'Tests/FilovaContracts'
    source.mkdir(parents=True)
    tests.mkdir(parents=True)
    service = proof / 'candidate-files/Filova/Core/FilovaServices.swift'
    test_source = proof / 'candidate-files/FilovaTests/LorisLabsIntegrationTests.swift'
    shutil.copy2(service, source / service.name)
    manifest = '''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "FilovaHostContracts", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "SDK_ROOT")], targets: [
        .target(name: "Filova", dependencies: [
            .product(name: "LorisLabsKit", package: "LorisLabsKit"),
            .product(name: "LorisReports", package: "LorisLabsKit")]),
        .testTarget(name: "FilovaContracts", dependencies: ["Filova"])
    ])
'''.replace('SDK_ROOT', str(rollout.ROOT))
    (harness / 'Package.swift').write_text(manifest)
    text = test_source.read_text()
    # Test logic is kept; only fixtures gain independent storage, fail-closed
    # transports, resource observation and cleanup. Production source is exact.
    text = text.replace('''        let defaults = UserDefaults(suiteName: "FilovaSDKTests." + UUID().uuidString)!''', '''        let suite = "LorisLabsKit.FilovaContracts." + UUID().uuidString
        let registry = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FILOVA_CONTRACT_RESOURCES"]!)
        let handle = try! FileHandle(forWritingTo: registry)
        try! handle.seekToEnd()
        try! handle.write(contentsOf: Data((suite + "\\n").utf8))
        try! handle.close()
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(suite, forKey: "qualification.suite")''')
    text = text.replace('FilovaServices(defaults: defaults, reviews: reviews)',
                        'isolatedServices(defaults: defaults, reviews: reviews)')
    text = text.replace('FilovaServices(defaults: defaults, reviews: services.reviews)',
                        'isolatedServices(defaults: defaults, reviews: services.reviews)')
    text = text.replace('let (services, _) = fixture()', 'let (services, defaults) = fixture()')
    for fixture in ['fixture()', 'fixture(minimumLaunches: 2)']:
        before = '        let (services, defaults) = ' + fixture
        text = text.replace(before, before + '\n        defer { clean(defaults) }')
    marker = '    private func fixture('
    helpers = '''    private func isolatedServices(defaults: UserDefaults, reviews: SmartReviewPromptManager) -> FilovaServices {
        FilovaServices(defaults: defaults, reviews: reviews,
            feedbackConfiguration: FeedbackConfiguration(directory: URL(fileURLWithPath:
                ProcessInfo.processInfo.environment["FILOVA_CONTRACT_STORAGE"]!)),
            feedbackTransport: RejectNetwork(), feedbackTickets: RejectTicketAccess())
    }
    private func clean(_ defaults: UserDefaults) {
        guard let suite = defaults.string(forKey: "qualification.suite") else { return }
        defaults.removePersistentDomain(forName: suite)
    }
'''
    assert marker in text
    text = text.replace(marker, helpers + marker, 1)
    text += '''
private struct RejectNetwork: FeedbackHTTPTransport {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        XCTFail("Closed-gate service contracts must never perform network I/O")
        throw ContractError.unexpectedIO
    }
}
private struct RejectTicketAccess: FeedbackTicketStorage {
    func load() throws -> [FeedbackTicket] {
        XCTFail("Service contracts must not read the user Keychain")
        throw ContractError.unexpectedIO
    }
    func save(_ tickets: [FeedbackTicket]) throws {
        XCTFail("Service contracts must not write the user Keychain")
        throw ContractError.unexpectedIO
    }
}
private enum ContractError: Error { case unexpectedIO }
'''
    (tests / test_source.name).write_text(text)
    registry = proof / 'host-contract-resources.txt'
    registry.write_text('')
    provenance = {'serviceSourceSHA256': rollout.digest(service),
                  'copiedServiceSHA256': rollout.digest(source / service.name),
                  'originalTestsSHA256': rollout.digest(test_source),
                  'fixtureChanges': ['isolated feedback directory', 'network/Keychain rejectors',
                                     'registered and removed unique UserDefaults suites'],
                  'scope': 'Four original service contract bodies on macOS; not full app or native UI qualification'}
    assert provenance['serviceSourceSHA256'] == provenance['copiedServiceSHA256']
    (proof / 'HOST-CONTRACT-PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
    log = proof / 'host-contracts.log'
    env = os.environ.copy()
    env['FILOVA_CONTRACT_STORAGE'] = str(build / 'feedback')
    env['FILOVA_CONTRACT_RESOURCES'] = str(registry)
    command = ['swift', 'test', '--package-path', str(harness), '--scratch-path', str(build),
               '-c', 'release', '--filter', 'LorisLabsIntegrationTests']
    with log.open('w') as output:
        process = subprocess.Popen(command, cwd=rollout.ROOT, env=env,
                                   stdout=output, stderr=subprocess.STDOUT)
        process_resource = {'kind': 'process', 'path': 'pid:' + str(process.pid), 'state': 'active',
                            'purpose': 'filova isolated service contract tests'}
        process_resource = rollout.record_resource(state, process_resource)
        rollout.save_state(state)
        try:
            code = process.wait(timeout=900)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise
        finally:
            process_resource['state'] = 'completed'
            rollout.save_state(state)
    app['validations'].append({'check': 'Four original Filova service contracts in isolated macOS harness',
                               'exitCode': code, 'log': str(log.relative_to(rollout.ROOT)),
                               'sourceSHA256': rollout.digest(service)})
    rollout.save_state(state)
    print('Filova service contracts exit', code, flush=True)
    assert code == 0


def clean_filova_contracts(rollout):
    import re, plistlib
    state, app = rollout.app_for('filova')
    proof = rollout.PROOF / 'filova'
    build = Path('/Volumes/DeveloperStorage/BuildScratch/Auto/Filova/portfolio-sdk-contracts-20261015')
    resource = next(r for r in state['resources'] if r['path'] == str(build))
    assert resource['state'] == 'active'
    assert not [r for r in state['resources'] if r['state'] == 'active' and
                r.get('purpose') == 'filova isolated service contract tests']
    suites = (proof / 'host-contract-resources.txt').read_text().splitlines()
    for suite in suites:
        assert re.fullmatch(r'LorisLabsKit\.FilovaContracts\.[0-9A-Fa-f-]{36}', suite)
        check = subprocess.run(['/usr/bin/defaults', 'read', suite],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if check.returncode == 0 and check.stdout.strip() != b'{\n}':
            subprocess.run(['/usr/bin/defaults', 'delete', suite], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        verify = subprocess.run(['/usr/bin/defaults', 'read', suite],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        assert verify.returncode != 0 or verify.stdout.strip() == b'{\n}', 'Our isolated defaults domain must be cleared'
        # removePersistentDomain can leave an empty plist; defaults delete then
        # reports no keys. Remove only this recorded UUID domain's empty file.
        plist = Path.home() / 'Library/Preferences' / (suite + '.plist')
        if plist.exists():
            assert not plist.is_symlink() and plistlib.loads(plist.read_bytes()) == {}
            plist.unlink()
        assert not plist.exists()
        state['resources'].append({'kind': 'userDefaultsSuite', 'path': suite, 'state': 'removed',
                                   'plistPath': str(plist),
                                   'creationRegistry': str((proof / 'host-contract-resources.txt').relative_to(rollout.ROOT))})
    assert not (build / 'feedback').exists(), 'Closed fixtures must not create support storage'
    shutil.rmtree(build)
    resource['state'] = 'removed'
    app['completed'].append('Four original Filova service contract bodies passed on macOS against exact service source; fixtures isolated, no network/Keychain access; owned resources cleaned')
    rollout.save_state(state)
    result = {'checkedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'testsPassed': 4, 'serviceSourceExact': True, 'fullAppOrUIQualified': False,
              'defaultsSuitesCleared': len(suites), 'feedbackStorageCreated': False,
              'buildResourcesRemoved': not build.exists()}
    (proof / 'HOST-CONTRACT-RESULT.json').write_text(json.dumps(result, indent=2) + '\n')
    capsule = json.loads((proof / 'CANDIDATE.json').read_text())
    capsule['validations'] = app['validations']
    (proof / 'CANDIDATE.json').write_text(json.dumps(capsule, indent=2) + '\n')
    print('Filova contract resources cleaned; tests', result['testsPassed'],
          'owned defaults suites cleared', len(suites), flush=True)


def millrace_tests(rollout):
    state, app = rollout.app_for('millrace')
    assert app['writer'] == 'Codex-exclusive-confirmed' and app['status'] == 'validated'
    proof = rollout.PROOF / 'millrace'
    package = Path(app['candidate']) / 'Millrace/Packages/MillraceSupport'
    build = Path('/Volumes/DeveloperStorage/BuildScratch/Auto/millrace/portfolio-sdk-20261015')
    assert any(r['path'] == str(build) and r['state'] == 'active' for r in state['resources'])
    temporary = build / 'support-test-data'
    assert not temporary.exists()
    resource = {'kind': 'testDirectory', 'path': str(temporary), 'state': 'active',
                'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'purpose': 'Owned root for existing Millrace support test fixture directories'}
    resource = rollout.record_resource(state, resource)
    rollout.save_state(state)
    temporary.mkdir(parents=True)
    tests = package / 'Tests/MillraceSupportTests/MillraceSupportTests.swift'
    original = tests.read_bytes()
    original_hash = rollout.digest(tests)
    before = 'directory = FileManager.default.temporaryDirectory.appendingPathComponent('
    after = 'directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MILLRACE_TEST_DATA"]!, isDirectory: true).appendingPathComponent('
    assert tests.read_text().count(before) == 1
    tests.write_text(tests.read_text().replace(before, after, 1))
    (proof / 'SUPPORT-TEST-PROVENANCE.json').write_text(json.dumps({
        'originalSupportTestsSHA256': original_hash,
        'fixtureSupportTestsSHA256': rollout.digest(tests),
        'fixtureChange': 'Only temporary directory root is injected; all original support test bodies are unchanged',
        'portfolioTestsSHA256': rollout.digest(package / 'Tests/MillraceSupportTests/MillracePortfolioTests.swift'),
        'scope': 'Nine preserved support tests plus two tests of vendored catalogue/icon resources and Mac/Scan self-exclusion; synthetic transport only'
    }, indent=2) + '\n')
    log = proof / 'support-portfolio-tests.log'
    env = os.environ.copy()
    env['MILLRACE_TEST_DATA'] = str(temporary)
    command = ['swift', 'test', '--package-path', str(package), '--scratch-path', str(build / 'support-tests'),
               '-c', 'release', '--filter', 'MillraceSupportTests|MillracePortfolioTests']
    try:
        with log.open('w') as output:
            process = subprocess.Popen(command, cwd=rollout.ROOT, env=env,
                                       stdout=output, stderr=subprocess.STDOUT)
            process_resource = {'kind': 'process', 'path': 'pid:' + str(process.pid), 'state': 'active',
                                'purpose': 'millrace preserved support and portfolio tests'}
            process_resource = rollout.record_resource(state, process_resource)
            rollout.save_state(state)
            try:
                code = process.wait(timeout=900)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                raise
            finally:
                process_resource['state'] = 'completed'
                rollout.save_state(state)
    finally:
        tests.write_bytes(original)
        assert rollout.digest(tests) == original_hash
        shutil.rmtree(temporary)
        resource['state'] = 'removed'
        rollout.save_state(state)
    app['validations'].append({'check': 'Preserved support and vendored portfolio tests on macOS',
                               'exitCode': code, 'log': str(log.relative_to(rollout.ROOT)),
                               'originalSupportTestFixtureRestored': True})
    rollout.save_state(state)
    print('Millrace support/portfolio tests exit', code, flush=True)
    assert code == 0
