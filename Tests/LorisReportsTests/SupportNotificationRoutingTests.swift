import XCTest
@testable import LorisReports

@MainActor
final class SupportNotificationRoutingTests: XCTestCase {
    private func coordinator(enabled: Bool) -> SupportNotificationCoordinator {
        let client = FeedbackClient(profile: .lumen, configuration: .init(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            serverAuthorizationApproved: true, nativeQualificationApproved: true,
            features: .init(notifications: enabled)))
        return .init(client: client, topic: "synthetic.topic", environment: "sandbox", registerWithAPNs: {
            XCTFail("Routing must never register or request permission")
        })
    }
    func testClosedCapabilityRejectsSupportRoutes() {
        let coordinator = coordinator(enabled: false)
        XCTAssertFalse(coordinator.handleNotification(userInfo: ["loris_support_route": UUID().uuidString]))
        XCTAssertNil(coordinator.route)
    }
    func testOnlyOpaqueSupportRouteIsAcceptedAndCanBeCleared() {
        let coordinator = coordinator(enabled: true), route = UUID()
        XCTAssertFalse(coordinator.handleNotification(userInfo: ["business_route": route.uuidString]))
        XCTAssertFalse(coordinator.handleNotification(userInfo: ["loris_support_route": "PRIVATE-MESSAGE"]))
        XCTAssertNil(coordinator.route)
        XCTAssertTrue(coordinator.handleNotification(userInfo: ["loris_support_route": route.uuidString]))
        XCTAssertEqual(coordinator.route, route)
        coordinator.clearRoute()
        XCTAssertNil(coordinator.route)
    }
}
