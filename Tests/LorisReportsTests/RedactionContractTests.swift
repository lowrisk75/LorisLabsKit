import Foundation
import XCTest
@testable import LorisReports

final class RedactionContractTests: XCTestCase {
    struct Case: Decodable { let input: String; let once: String; let twice: String }
    func testSwiftAndServerCanonicalizationAgreeOnSyntheticVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "server-redaction", withExtension: "json"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        let pipeline = ReportRedactionPipeline()
        for value in cases {
            XCTAssertEqual(pipeline.redact(value.input), value.once)
            XCTAssertEqual(pipeline.redact(value.once), value.twice)
        }
    }
}
