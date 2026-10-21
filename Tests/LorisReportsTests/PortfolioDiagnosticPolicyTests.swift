import XCTest
@testable import LorisReports

final class PortfolioDiagnosticPolicyTests: XCTestCase {
    func testNewSupportIntegrationsAcceptOnlyCommonTechnicalComponents() {
        for appID in ["kernel", "kiosk", "millrace"] {
            XCTAssertEqual(SupportDiagnosticPolicy.components(appID: appID), [.support, .ui], appID)
        }
        XCTAssertTrue(SupportDiagnosticPolicy.components(appID: "unregistered-app").isEmpty)
    }

    func testOptedInJournalsRecordSupportEventsForNewIntegrations() async throws {
        for appID in ["kernel", "kiosk", "millrace"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let journal = SupportDiagnosticJournal(appID: appID, directory: root, qualified: true)
            let event = SupportDiagnosticEvent(correlationID: UUID(), component: .support,
                                               operation: .read, outcome: .unavailable)
            try await journal.record(event)
            let beforeConsent = try await journal.snapshot()
            XCTAssertTrue(beforeConsent.isEmpty, appID)
            try await journal.setEnabled(true)
            try await journal.record(event)
            try await journal.record(.init(correlationID: UUID(), component: .unlock,
                                          operation: .unlock, outcome: .failed))
            let events = try await journal.snapshot()
            XCTAssertEqual(events, [event], appID)
            _ = try SupportDiagnosticBundle(appID: appID, reviewedEvents: events)
            try await journal.setEnabled(false)
            let afterRevocation = try await journal.snapshot()
            XCTAssertTrue(afterRevocation.isEmpty, appID)
        }
    }
}
