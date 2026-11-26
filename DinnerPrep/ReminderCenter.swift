import Foundation
import UserNotifications

@MainActor
protocol ReminderCenter: AnyObject {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func add(_ ticket: ReminderTicket, dinner: Date, zone: TimeZone) async throws
    func remove(_ id: String)
    func pending() async -> [String: UInt64]
}

enum ReminderAuthorization { case undecided, allowed, denied }

@MainActor
final class SystemReminders: ReminderCenter {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        switch (await center.notificationSettings()).authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .undecided
        default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func add(_ ticket: ReminderTicket, dinner: Date, zone: TimeZone) async throws {
        let content = UNMutableNotificationContent()
        content.title = L.t("reminder.notificationTitle")
        content.body = L.f("reminder.notificationBody", L.time(dinner, zone: zone))
        content.sound = .default
        content.userInfo = ["revision": NSNumber(value: ticket.revision)]
        let utc = TimeZone(secondsFromGMT: 0)!
        let calendar = DinnerCalendar.calendar(in: utc)
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: ticket.start)
        parts.calendar = calendar
        parts.timeZone = utc
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        try await center.add(UNNotificationRequest(identifier: ticket.identifier, content: content, trigger: trigger))
    }

    func remove(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func pending() async -> [String: UInt64] {
        let requests = await center.pendingNotificationRequests()
        return requests.reduce(into: [:]) { revisions, request in
            guard request.identifier.hasPrefix("dinnerprep.start.") else { return }
            revisions[request.identifier] = (request.content.userInfo["revision"] as? NSNumber)?.uint64Value ?? 0
        }
    }
}

@MainActor
final class TestReminders: ReminderCenter {
    private var access: ReminderAuthorization
    private var requests: [String: UInt64] = [:]
    private let fail: Bool

    init(arguments: [String]) {
        access = arguments.contains("-denied") ? .denied : .undecided
        fail = arguments.contains("-reminder-failure")
    }

    func authorization() async -> ReminderAuthorization { access }

    func requestAuthorization() async throws -> Bool {
        guard access != .denied else { return false }
        access = .allowed
        return true
    }

    func add(_ ticket: ReminderTicket, dinner: Date, zone: TimeZone) async throws {
        if fail { throw CocoaError(.fileWriteUnknown) }
        requests[ticket.identifier] = ticket.revision
    }

    func remove(_ id: String) { requests[id] = nil }
    func pending() async -> [String: UInt64] { requests }

    func allowInSettings() { access = .allowed }
}
