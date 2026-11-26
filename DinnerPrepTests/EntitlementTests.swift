import XCTest

final class EntitlementTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testThirtyDaysFromFirstPaidOpenIncludingFreeUpgrade() {
        var access = Entitlement(firstOpen: start)
        let upgrade = start.addingTimeInterval(200 * 86_400)
        access.observe(start, free: true)
        XCTAssertNil(access.proStartedAt)
        XCTAssertTrue(access.hasPro(at: upgrade, free: true))
        access.observe(upgrade, free: false)
        XCTAssertEqual(access.trialStart, upgrade)
        XCTAssertEqual(access.remainingDays(at: upgrade), 30)
        XCTAssertTrue(access.hasPro(at: upgrade.addingTimeInterval(30 * 86_400 - 1), free: false))
        XCTAssertFalse(access.hasPro(at: upgrade.addingTimeInterval(30 * 86_400), free: false))
    }

    func testFreshLaunchFallsBackToFirstOpenAndHasNoPermanentTrialBranch() {
        let access = Entitlement(firstOpen: start)
        XCTAssertEqual(access.trialStart, start)
        XCTAssertFalse(access.hasPro(at: start.addingTimeInterval(-1), free: false))
        XCTAssertFalse(access.hasPro(at: start.addingTimeInterval(31 * 86_400), free: false))
    }

    func testReceiptDoesNotRestartAnExistingTrialAndCanRestoreOlderStart() {
        var access = Entitlement(firstOpen: start, proStartedAt: start)
        access.applyTrialReceipt(originalDate: start.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(access.trialStart, start)
        let earlierReceipt = start.addingTimeInterval(-20 * 86_400)
        access.applyTrialReceipt(originalDate: earlierReceipt)
        XCTAssertEqual(access.trialStart, earlierReceipt)
        XCTAssertEqual(access.remainingDays(at: start), 10)
    }

    func testClockRollbackVerifiedPurchaseAndRefund() throws {
        var access = Entitlement(firstOpen: start)
        access.observe(start, free: false)
        let expired = start.addingTimeInterval(40 * 86_400)
        access.observe(expired, free: false)
        XCTAssertFalse(access.hasPro(at: start, free: false))
        access.purchasedPro = true
        var cached = try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(access))
        XCTAssertTrue(cached.hasPro(at: expired, free: false))
        cached.purchasedPro = false
        XCTAssertFalse(cached.hasPro(at: expired, free: false))
    }

    func testPersonalLimitKeepsDataAvailable() {
        let ids = ["one", "two", "three", "four"]
        XCTAssertFalse(PrepAccess.canEdit("four", orderedIDs: ids, hasPro: false))
        XCTAssertTrue(PrepAccess.canEdit("three", orderedIDs: ids, hasPro: false))
        XCTAssertTrue(PrepAccess.canEdit("four", orderedIDs: ids, hasPro: true))
        XCTAssertEqual(PrepAccess.availableSlots(currentCount: ids.count, hasPro: false), 0)
        XCTAssertEqual(PrepAccess.availableSlots(currentCount: 2, hasPro: false), 1)
    }
}
