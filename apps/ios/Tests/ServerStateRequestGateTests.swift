import XCTest
@testable import Enzo

final class ServerStateRequestGateTests: XCTestCase {
    func testRejectsAnOlderResponseAfterANewerRequestStarts() {
        var gate = ServerStateRequestGate()
        let older = gate.beginRequest()
        let newer = gate.beginRequest()

        XCTAssertFalse(gate.accepts(older))
        XCTAssertTrue(gate.accepts(newer))
    }
}
