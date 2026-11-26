import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Route: Identifiable {
        case library, settings, planCard, milestone, paywall
        case fileImport([PrepTransferItem])

        var id: String {
            switch self {
            case .library: "library"
            case .settings: "settings"
            case .planCard: "planCard"
            case .milestone: "milestone"
            case .paywall: "paywall"
            case .fileImport: "fileImport"
            }
        }
    }

    enum Notice: String {
        case denied = "reminder.denied"
        case failed = "reminder.failed"
        case lost = "reminder.lost"
    }

    @Published private(set) var data: DinnerData
    @Published private(set) var now: Date
    @Published private(set) var zone: TimeZone
    @Published private(set) var ready = false
    @Published private(set) var confirmedReminder: ReminderTicket?
    @Published private(set) var notice: Notice?
    @Published private(set) var storageWarning = false
    @Published private(set) var shareRequested = false
    @Published private(set) var reviewPending = false
    @Published private(set) var testReminderCount: Int?
    @Published var route: Route?

    let store: StoreAccess
    let test: Bool
    private let arguments: [String]
    private let storage: LocalStorage
    private let reminders: any ReminderCenter
    private var lastWrite: Task<Void, Never>?
    private var notificationWork: Task<Void, Never>?
    private var storageReadable = true
    private var booting = false
    private var wentToBackground = false

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
        let testing = arguments.contains("-ui-testing")
        test = testing
        storage = LocalStorage(isolated: testing, reset: testing && arguments.contains("-reset"))
        if testing {
            reminders = TestReminders(arguments: arguments)
        } else {
            reminders = SystemReminders()
        }
        store = StoreAccess(arguments: arguments)
        let zone = testing ? TimeZone(secondsFromGMT: 0)! : TimeZone.current
        self.zone = zone
        let calendar = DinnerCalendar.calendar(in: zone)
        let current = testing
            ? DateComponents(calendar: calendar, year: 2026, month: 11, day: 23, hour: 17, minute: 45).date!
            : Date()
        let launchNow = testing && arguments.contains("-late") ? current.addingTimeInterval(33 * 60) : current
        now = launchNow
        testReminderCount = testing && arguments.contains("-assert-reminders") ? 0 : nil
        data = DinnerData(meal: .fresh(now: launchNow, calendar: calendar))
    }

    var calendar: Calendar { DinnerCalendar.calendar(in: zone) }
    var meal: MealDraft { data.meal }
    var timing: DinnerMath.Result? { try? meal.timing() }
    var hasPro: Bool { store.hasPro(at: test ? now : Date()) }

    func start() async {
        guard !ready, !booting else { return }
        booting = true
        var needsSave = false
        do {
            if let saved = try await storage.load() { data = saved }
            else { needsSave = true }
        } catch {
            storageWarning = true
            storageReadable = false
        }

        if test, arguments.contains(where: ["-sample", "-late", "-demo-library", "-demo-milestone", "-store-basic"].contains) {
            seed()
            needsSave = true
        }
        await store.start(at: now)
        let rolled = data.meal.rollIfPast(now: now, calendar: calendar)
        if rolled {
            data.reminder = nil
            data.reminderRevision &+= 1
        }
        if needsSave || rolled { persist() }

        await reconcile()
        ready = true
        if test && arguments.contains("-paywall") { route = .paywall }
    }

    private func seed() {
        data.meal.recipe = 35
        data.meal.buffer = 5
        data.meal.prep = [MealPrep(id: "meat", name: "prep.meat", minutes: 15, builtIn: true)]
        if arguments.contains("-store-basic") {
            data.meal.recipe = 55
            data.meal.buffer = 0
            data.meal.prep = []
        }
        if arguments.contains("-demo-library") {
            for (key, minutes) in [("demo.onions", 8), ("demo.beans", 25), ("demo.herbs", 5), ("demo.tray", 7)] {
                data.items.append(PrepItem(id: key, name: L.t(key), minutes: minutes))
            }
            data.presets = [MealPreset(id: "sample", name: L.t("demo.plan"), meal: data.meal)]
        }
        if arguments.contains("-demo-milestone") {
            for index in 1...6 {
                if let previous = calendar.date(byAdding: .day, value: -index, to: now) {
                    data.recordCooking(on: previous, calendar: calendar)
                }
            }
        }
    }

    func tick() {
        guard ready, !test else { return }
        let current = Date()
        if zone.identifier != TimeZone.current.identifier { zone = .current }
        if DinnerMath.minute(current) != DinnerMath.minute(now) { store.observe(current) }
        now = current
        if let ticket = data.reminder, ticket.start <= current { clearReminder() }
    }

    func wasBackgrounded() { wentToBackground = true }

    func becameActive() async {
        guard ready else { return }
        tick()
        if wentToBackground && !test {
            wentToBackground = false
            if data.meal.rollIfPast(now: now, calendar: calendar) {
                clearReminder()
                notice = nil
                persist()
            }
        }
        await store.resume(at: now)
        await reconcile()
    }

    private func persist() {
        guard storageReadable else { return }
        let snapshot = data
        let previous = lastWrite
        lastWrite = Task {
            await previous?.value
            do {
                try await storage.save(snapshot)
                self.storageWarning = false
            } catch {
                self.storageWarning = true
            }
        }
    }

    func updateMeal(remind: Bool = false, _ change: (inout MealDraft) -> Void) {
        tick()
        var edited = data.meal
        change(&edited)
        guard edited != data.meal else {
            if remind { enableReminder() }
            return
        }
        data.meal = edited
        notice = nil
        if let result = timing, !meal.started, result.start > now,
           remind || data.reminder != nil || data.autoRemind {
            if remind { data.autoRemind = true }
            schedule(result, requestPermission: remind)
        } else if data.reminder != nil {
            clearReminder()
        } else { persist() }
    }

    func setSuggestedDinner(_ dinner: Date) {
        updateMeal {
            $0.dinner = dinner
            $0.zoneID = zone.identifier
        }
    }

    var homeItems: [PrepItem] {
        var rows = Array(data.items.filter(\.pinned).prefix(3))
        for selected in meal.prep where !rows.contains(where: { $0.id == selected.id }) {
            rows.append(PrepItem(id: selected.id, name: selected.name, minutes: selected.minutes, builtIn: selected.builtIn))
        }
        return rows
    }

    func togglePrep(_ item: PrepItem) {
        if meal.prep.contains(where: { $0.id == item.id }) {
            updateMeal { $0.prep.removeAll { $0.id == item.id } }
        } else if let minutes = item.minutes {
            updateMeal { $0.prep.append(MealPrep(id: item.id, name: item.name, minutes: minutes, builtIn: item.builtIn)) }
        }
    }

    func setMealMinutes(_ minutes: Int, for item: PrepItem) {
        updateMeal { $0.setPrepMinutes(minutes, for: item) }
    }

    func canEdit(_ item: PrepItem) -> Bool {
        item.builtIn || PrepAccess.canEdit(item.id, orderedIDs: data.personalIDs, hasPro: hasPro)
    }

    var canAdd: Bool { hasPro || data.personalIDs.count < PrepAccess.freeItems }

    func saveItem(_ item: PrepItem) -> Bool {
        let wasPinned = data.items.first(where: { $0.id == item.id })?.pinned == true
        if let index = data.items.firstIndex(where: { $0.id == item.id }) {
            guard canEdit(data.items[index]) else { return false }
            data.items[index] = item
        } else {
            guard canAdd else { return false }
            data.items.append(item)
        }
        if item.pinned && !wasPinned {
            let olderPins = data.items.indices.filter { data.items[$0].pinned && data.items[$0].id != item.id }
            for index in olderPins.dropFirst(2) { data.items[index].pinned = false }
        }
        persist()
        return true
    }

    func removeItem(_ item: PrepItem) {
        data.items.removeAll { $0.id == item.id }
        persist()
    }

    func importPlan(_ incoming: [PrepTransferItem]) -> PrepImport {
        PrepImport(incoming: incoming, existing: data.items, hasPro: hasPro)
    }

    func applyImport(_ preview: PrepImport, incoming: [PrepTransferItem]) -> Bool {
        guard importPlan(incoming) == preview, !preview.accepted.isEmpty else { return false }
        data.items.append(contentsOf: preview.accepted.map { PrepItem(name: $0.name, minutes: $0.minutes) })
        persist()
        return true
    }

    var libraryExport: [PrepTransferItem] {
        data.items.compactMap { item in
            guard let minutes = item.minutes else { return nil }
            return PrepTransferItem(name: item.displayName, minutes: minutes)
        }
    }

    func savePreset(name: String, replacing existing: MealPreset? = nil) -> Bool {
        guard hasPro, timing != nil || existing != nil else { return false }
        if let existing, let index = data.presets.firstIndex(where: { $0.id == existing.id }) {
            data.presets[index].name = name
        } else {
            data.presets.append(MealPreset(name: name, meal: meal))
        }
        persist()
        return true
    }

    func removePreset(_ preset: MealPreset) {
        guard hasPro else { return }
        data.presets.removeAll { $0.id == preset.id }
        persist()
    }

    func movePreset(_ preset: MealPreset, offset: Int) {
        guard hasPro, let index = data.presets.firstIndex(where: { $0.id == preset.id }),
              data.presets.indices.contains(index + offset) else { return }
        data.presets.swapAt(index, index + offset)
        persist()
    }

    func applyPreset(_ preset: MealPreset) -> Bool {
        guard hasPro else { return false }
        clearReminder()
        data.meal = preset.nextMeal(now: test ? now : Date(), calendar: calendar)
        notice = nil
        persist()
        return true
    }

    func clearMeal() {
        clearReminder()
        data.meal = .fresh(now: test ? now : Date(), calendar: calendar)
        notice = nil
        persist()
    }

    func startedCooking() {
        tick()
        guard let timing, timing.start <= now, !meal.started else { return }
        data.meal.started = true
        data.recordCooking(on: now, calendar: calendar)
        if data.days.count >= 3 && data.attemptedReviewVersion != Self.version { reviewPending = true }
        clearReminder()
        persist()
    }

    func dismissMilestone() {
        data.milestoneDismissed = true
        persist()
    }

    func allowTestNotifications() {
        (reminders as? TestReminders)?.allowInSettings()
    }

    func enableReminder() {
        tick()
        guard let timing, timing.start > now, !meal.started, data.reminder == nil else { return }
        data.autoRemind = true
        schedule(timing, requestPermission: true)
    }

    func cancelReminderByUser() {
        data.autoRemind = false
        clearReminder()
    }

    func clearReminder() {
        guard let original = data.reminder ?? confirmedReminder else { return }
        data.reminderRevision &+= 1
        data.reminder = nil
        confirmedReminder = nil
        persist()
        enqueue { self.reminders.remove(original.identifier) }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = notificationWork
        notificationWork = Task {
            await previous?.value
            await operation()
            if self.testReminderCount != nil {
                self.testReminderCount = await self.reminders.pending().count
            }
        }
    }

    private func schedule(_ result: DinnerMath.Result, requestPermission: Bool) {
        let mayAsk = requestPermission || (data.reminder != nil && confirmedReminder == nil)
        data.reminderRevision &+= 1
        let ticket = ReminderTicket(mealID: meal.id, start: result.start, revision: data.reminderRevision)
        let zone = self.zone
        data.reminder = ticket
        confirmedReminder = nil
        notice = nil
        persist()
        enqueue {
            guard self.data.reminder == ticket else { return }
            do {
                let access = await self.reminders.authorization()
                var allowed = access == .allowed
                if access == .undecided && mayAsk { allowed = try await self.reminders.requestAuthorization() }
                guard self.data.reminder == ticket else { return }
                guard allowed else {
                    self.clearReminder()
                    self.notice = .denied
                    return
                }
                let now = self.test ? self.now : Date()
                guard ticket.start > now else { self.clearReminder(); return }
                try await self.reminders.add(ticket, dinner: result.dinner, zone: zone)
                if self.data.reminder == ticket {
                    self.confirmedReminder = ticket
                }
            } catch {
                guard self.data.reminder == ticket else { return }
                self.clearReminder()
                self.notice = .failed
            }
        }
    }

    private func reconcile() async {
        enqueue {
            let expected = self.data.reminder
            let access = await self.reminders.authorization()
            let requests = await self.reminders.pending()
            guard expected == self.data.reminder else { return }
            for identifier in requests.keys where identifier != expected?.identifier {
                self.reminders.remove(identifier)
            }
            guard let expected else { return }
            if access == .allowed && requests[expected.identifier] == expected.revision &&
                expected.start > (self.test ? self.now : Date()) {
                self.confirmedReminder = expected
            } else {
                self.clearReminder()
                self.notice = access == .denied ? .denied : .lost
            }
        }
        await notificationWork?.value
    }

    func shareBegan() { shareRequested = false }

    func shareFinished(completed: Bool) {
        if test && completed { shareRequested = true }
        if completed && data.hasMilestone && data.attemptedReviewVersion != Self.version {
            reviewPending = true
        }
    }

    func consumeReviewRequest() -> Bool {
        guard reviewPending, route == nil, data.reminder == confirmedReminder,
              notice == nil, !storageWarning, !store.busy else { return false }
        reviewPending = false
        data.attemptedReviewVersion = Self.version
        persist()
        return !test
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
