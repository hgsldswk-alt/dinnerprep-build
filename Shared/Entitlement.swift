import Foundation

struct Entitlement: Codable, Equatable {
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var lastSeen: Date?
    var purchasedPro = false

    static let trialDuration: TimeInterval = 30 * 86_400

    var trialStart: Date {
        let local = proStartedAt ?? firstOpen
        return min(local, trialClaimedAt ?? local)
    }

    var trialEnd: Date { trialStart.addingTimeInterval(Self.trialDuration) }

    func observedTime(_ now: Date) -> Date { max(now, lastSeen ?? now) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        let observed = observedTime(now)
        return free || purchasedPro || (observed >= trialStart && observed < trialEnd)
    }

    mutating func observe(_ now: Date, free: Bool = Launch.isFree) {
        if !free, proStartedAt == nil { proStartedAt = now }
        lastSeen = observedTime(now)
    }

    mutating func applyTrialReceipt(originalDate: Date) {
        trialClaimedAt = min(trialClaimedAt ?? originalDate, originalDate)
    }

    func remainingDays(at now: Date) -> Int {
        max(0, Int(ceil(trialEnd.timeIntervalSince(observedTime(now)) / 86_400)))
    }
}

enum PrepAccess {
    static let freeItems = 3

    static func canEdit(_ id: String, orderedIDs: [String], hasPro: Bool) -> Bool {
        hasPro || orderedIDs.prefix(freeItems).contains(id)
    }

    static func availableSlots(currentCount: Int, hasPro: Bool) -> Int {
        hasPro ? .max : max(0, freeItems - currentCount)
    }
}
