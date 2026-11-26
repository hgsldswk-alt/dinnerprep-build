import XCTest

final class DinnerMathTests: XCTestCase {
    private let utc = DinnerCalendar.calendar(in: TimeZone(secondsFromGMT: 0)!)

    private func date(_ day: Int = 23, _ hour: Int, _ minute: Int, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testBackplanAndUncheckingPrep() throws {
        let first = try DinnerMath.calculate(dinner: date(23, 19, 0), recipe: 35, prep: [15], buffer: 5)
        XCTAssertEqual(first.start, date(23, 18, 5))
        XCTAssertEqual(first.total, 55)
        XCTAssertEqual(first.status(at: date(23, 18, 4).addingTimeInterval(59)), .upcoming)

        let unchecked = try DinnerMath.calculate(dinner: first.dinner, recipe: 35, prep: [], buffer: 5)
        XCTAssertEqual(unchecked.start, date(23, 18, 20))
    }

    func testLateAndExactlyOnTime() throws {
        let result = try DinnerMath.calculate(dinner: date(23, 19, 0), recipe: 35, prep: [15], buffer: 5)
        XCTAssertEqual(result.status(at: date(23, 18, 5)), .startNow(late: 0, earliestDinner: result.dinner))
        XCTAssertEqual(result.status(at: date(23, 18, 18).addingTimeInterval(48)),
                       .startNow(late: 13, earliestDinner: date(23, 19, 13)))
    }

    func testCrossMidnightAndTimeZoneConversion() throws {
        let result = try DinnerMath.calculate(dinner: date(24, 0, 50), recipe: 35, prep: [15], buffer: 5)
        XCTAssertEqual(result.start, date(23, 23, 55))
        let japan = DinnerCalendar.calendar(in: TimeZone(identifier: "Asia/Tokyo")!)
        XCTAssertEqual(japan.component(.hour, from: result.start), 8)
        XCTAssertEqual(japan.component(.day, from: result.start), 24)
        XCTAssertEqual(result.dinner.timeIntervalSince(result.start), 55 * 60)
    }

    func testDSTRejectsGapAndOffersBothOffsets() {
        let zone = TimeZone(identifier: "America/New_York")!
        let calendar = DinnerCalendar.calendar(in: zone)
        let spring = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        XCTAssertTrue(DinnerCalendar.times(on: spring, hour: 2, minute: 30, in: calendar).isEmpty)
        let fall = date(1, 12, 0, calendar: calendar)
        let choices = DinnerCalendar.times(on: fall, hour: 1, minute: 30, in: calendar)
        XCTAssertEqual(choices.map { DinnerCalendar.offset($0, in: zone) }, ["UTC−04:00", "UTC−05:00"])
        XCTAssertEqual(choices.last?.timeIntervalSince(choices.first ?? fall), 3_600)
    }

    func testInvalidInputsAndLimits() throws {
        let dinner = date(23, 19, 0)
        let invalid: [(Int?, [Int], Int, DinnerMath.Invalid)] = [
            (nil, [], 0, .recipe), (0, [], 0, .recipe), (2_881, [], 0, .recipe),
            (35, [0], 0, .prep), (35, [2_881], 0, .prep),
            (35, [], -1, .buffer), (35, [], 121, .buffer),
            (2_880, [2_880, 2_880, 1_320], 121, .buffer),
            (2_880, [2_880, 2_880, 1_321], 120, .total)
        ]
        for (recipe, prep, buffer, expected) in invalid {
            XCTAssertThrowsError(try DinnerMath.calculate(dinner: dinner, recipe: recipe, prep: prep, buffer: buffer)) {
                XCTAssertEqual($0 as? DinnerMath.Invalid, expected)
            }
        }
        XCTAssertEqual(try DinnerMath.calculate(dinner: dinner, recipe: 2_880, prep: [2_880, 2_880, 1_320],
                                                buffer: 120).total, 10_080)
        for input in ["", "—", "1.5", "+10", "1 0", "½", "12:30", "99999999999999999", "2881"] {
            XCTAssertNil(DinnerMath.parse(input, in: 1...2_880), input)
        }
        XCTAssertEqual(DinnerMath.parse(" ３５ ", in: 1...2_880), 35)
        XCTAssertEqual(DinnerMath.parse("0", in: 0...120), 0)
    }

    func testNextDinnerPreservesDraftAndClearsStartedFlag() {
        var meal = MealDraft(dinner: date(23, 19, 0), zoneID: utc.timeZone.identifier, recipe: 35)
        let firstID = meal.id
        meal.prep = [MealPrep(id: "meat", name: "prep.meat", minutes: 15, builtIn: true)]
        meal.buffer = 5
        meal.started = true
        XCTAssertTrue(meal.rollIfPast(now: date(23, 19, 10), calendar: utc))
        XCTAssertEqual(meal.dinner, date(24, 19, 0))
        XCTAssertNotEqual(meal.id, firstID)
        XCTAssertEqual(meal.prep.first?.minutes, 15)
        XCTAssertEqual(meal.recipe, 35)
        XCTAssertEqual(meal.buffer, 5)
        XCTAssertFalse(meal.started)
    }

    func testOldDraftDefaultsAndStorageRoundTrip() throws {
        let legacy = Data(#"{"meal":{"dinner":10000,"recipe":35}}"#.utf8)
        let migrated = try JSONDecoder().decode(DinnerData.self, from: legacy)
        XCTAssertEqual(migrated.meal.recipe, 35)
        XCTAssertEqual(migrated.meal.zoneID, TimeZone.current.identifier)
        XCTAssertEqual(migrated.meal.buffer, 0)
        XCTAssertTrue(migrated.meal.prep.isEmpty)
        XCTAssertEqual(migrated.items, PrepItem.examples)
        XCTAssertEqual(try JSONDecoder().decode(DinnerData.self, from: JSONEncoder().encode(migrated)), migrated)
    }

    func testMilestoneCountsDistinctLocalDays() {
        var data = DinnerData(meal: .fresh(now: date(23, 9, 0), calendar: utc))
        for day in 1...6 {
            data.recordCooking(on: date(day, 18, 0), calendar: utc)
            data.recordCooking(on: date(day, 20, 0), calendar: utc)
        }
        XCTAssertEqual(data.days.count, 6)
        XCTAssertFalse(data.hasMilestone)
        data.recordCooking(on: date(7, 18, 0), calendar: utc)
        XCTAssertTrue(data.hasMilestone)
    }
}
