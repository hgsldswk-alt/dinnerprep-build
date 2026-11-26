import Foundation

struct PrepItem: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var minutes: Int?
    var pinned = false
    var builtIn = false

    var displayName: String { builtIn ? L.t(name) : name }

    static let examples = [
        PrepItem(id: "meat", name: "prep.meat", minutes: 15, pinned: true, builtIn: true),
        PrepItem(id: "rice", name: "prep.rice", minutes: 20, pinned: true, builtIn: true),
        PrepItem(id: "thaw", name: "prep.thaw", minutes: nil, builtIn: true)
    ]
}

struct MealPrep: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var minutes: Int
    var builtIn = false

    var displayName: String { builtIn ? L.t(name) : name }
}

struct MealDraft: Codable, Equatable {
    var id = UUID().uuidString
    var dinner: Date
    var zoneID: String
    var recipe: Int?
    var prep: [MealPrep] = []
    var buffer = 0
    var started = false

    init(dinner: Date, zoneID: String, recipe: Int? = nil) {
        self.dinner = dinner
        self.zoneID = zoneID
        self.recipe = recipe
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        dinner = try values.decode(Date.self, forKey: .dinner)
        zoneID = try values.decodeIfPresent(String.self, forKey: .zoneID) ?? TimeZone.current.identifier
        recipe = try values.decodeIfPresent(Int.self, forKey: .recipe)
        prep = try values.decodeIfPresent([MealPrep].self, forKey: .prep) ?? []
        buffer = try values.decodeIfPresent(Int.self, forKey: .buffer) ?? 0
        started = try values.decodeIfPresent(Bool.self, forKey: .started) ?? false
    }

    static func fresh(now: Date, calendar: Calendar) -> MealDraft {
        MealDraft(dinner: DinnerCalendar.nextClock(hour: 19, minute: 0, after: now, in: calendar),
                  zoneID: calendar.timeZone.identifier)
    }

    mutating func rollIfPast(now: Date, calendar: Calendar) -> Bool {
        guard dinner <= now else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: dinner)
        dinner = DinnerCalendar.nextClock(hour: parts.hour ?? 19, minute: parts.minute ?? 0,
                                          after: now, in: calendar)
        zoneID = calendar.timeZone.identifier
        id = UUID().uuidString
        started = false
        return true
    }

    func timing() throws -> DinnerMath.Result {
        try DinnerMath.calculate(dinner: dinner, recipe: recipe, prep: prep.map(\.minutes), buffer: buffer)
    }

    mutating func setPrepMinutes(_ minutes: Int, for item: PrepItem) {
        if let index = prep.firstIndex(where: { $0.id == item.id }) {
            prep[index].minutes = minutes
        } else {
            prep.append(MealPrep(id: item.id, name: item.name, minutes: minutes, builtIn: item.builtIn))
        }
    }
}

struct MealPreset: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var meal: MealDraft

    func nextMeal(now: Date, calendar: Calendar) -> MealDraft {
        let parts = calendar.dateComponents([.hour, .minute], from: meal.dinner)
        var next = meal
        next.id = UUID().uuidString
        next.dinner = DinnerCalendar.nextClock(hour: parts.hour ?? 19, minute: parts.minute ?? 0,
                                               after: now, in: calendar)
        next.zoneID = calendar.timeZone.identifier
        next.started = false
        return next
    }
}

struct CookingDay: Codable, Equatable {
    let key: String
}

struct ReminderTicket: Codable, Equatable {
    let mealID: String
    let start: Date
    let revision: UInt64

    var identifier: String { "dinnerprep.start." + mealID }
}

struct DinnerData: Codable, Equatable {
    var meal: MealDraft
    var items = PrepItem.examples
    var presets: [MealPreset] = []
    var days: [CookingDay] = []
    var milestoneDismissed = false
    var attemptedReviewVersion: String?
    var reminder: ReminderTicket?
    var reminderRevision: UInt64 = 0
    var autoRemind = false

    init(meal: MealDraft) { self.meal = meal }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        meal = try values.decode(MealDraft.self, forKey: .meal)
        items = try values.decodeIfPresent([PrepItem].self, forKey: .items) ?? PrepItem.examples
        presets = try values.decodeIfPresent([MealPreset].self, forKey: .presets) ?? []
        days = try values.decodeIfPresent([CookingDay].self, forKey: .days) ?? []
        milestoneDismissed = try values.decodeIfPresent(Bool.self, forKey: .milestoneDismissed) ?? false
        attemptedReviewVersion = try values.decodeIfPresent(String.self, forKey: .attemptedReviewVersion)
        reminder = try values.decodeIfPresent(ReminderTicket.self, forKey: .reminder)
        autoRemind = try values.decodeIfPresent(Bool.self, forKey: .autoRemind) ?? false
        reminderRevision = max(try values.decodeIfPresent(UInt64.self, forKey: .reminderRevision) ?? 0,
                               reminder?.revision ?? 0)
    }

    var personalIDs: [String] { items.filter { !$0.builtIn }.map(\.id) }
    var hasMilestone: Bool { days.count >= 7 }

    mutating func recordCooking(on date: Date, calendar: Calendar) {
        let key = DinnerCalendar.dayKey(date, in: calendar)
        guard !days.contains(where: { $0.key == key }) else { return }
        days.append(CookingDay(key: key))
    }
}
