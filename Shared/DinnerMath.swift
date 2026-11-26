import Foundation

enum DinnerMath {
    static let maxMinutes = 2_880
    static let maxBuffer = 120
    static let maxTotal = 10_080

    enum Invalid: Error, Equatable {
        case recipe, prep, buffer, total
    }

    struct Result: Equatable {
        let start: Date
        let dinner: Date
        let recipe: Int
        let prep: Int
        let buffer: Int

        var total: Int { recipe + prep + buffer }

        func status(at now: Date) -> Status {
            let minute = DinnerMath.minute(now)
            guard minute >= start else { return .upcoming }
            return .startNow(late: Int(minute.timeIntervalSince(start) / 60),
                             earliestDinner: minute.addingTimeInterval(Double(total) * 60))
        }
    }

    enum Status: Equatable {
        case upcoming
        case startNow(late: Int, earliestDinner: Date)
    }

    static func minute(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: floor(date.timeIntervalSinceReferenceDate / 60) * 60)
    }

    static func parse(_ text: String, in range: ClosedRange<Int>) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12 else { return nil }
        var value = 0
        for digit in trimmed {
            guard digit.unicodeScalars.count == 1,
                  digit.unicodeScalars.first?.properties.numericType == .decimal,
                  let number = digit.wholeNumberValue else { return nil }
            value = value * 10 + number
            guard value <= range.upperBound else { return nil }
        }
        return range.contains(value) ? value : nil
    }

    static func calculate(dinner: Date, recipe: Int?, prep: [Int], buffer: Int) throws -> Result {
        guard let recipe, (1...maxMinutes).contains(recipe) else { throw Invalid.recipe }
        guard (0...maxBuffer).contains(buffer) else { throw Invalid.buffer }
        var extra = 0
        for item in prep {
            guard (1...maxMinutes).contains(item) else { throw Invalid.prep }
            extra += item
            guard extra + recipe + buffer <= maxTotal else { throw Invalid.total }
        }
        let dinner = minute(dinner)
        return Result(start: dinner.addingTimeInterval(-Double(recipe + extra + buffer) * 60),
                      dinner: dinner, recipe: recipe, prep: extra, buffer: buffer)
    }
}

enum DinnerCalendar {
    static func calendar(in zone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static func times(on day: Date, hour: Int, minute: Int, in calendar: Calendar) -> [Date] {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        let components = DateComponents(hour: hour, minute: minute, second: 0)
        let matches = [Calendar.RepeatedTimePolicy.first, .last].compactMap { policy -> Date? in
            guard let date = calendar.nextDate(after: dayStart.addingTimeInterval(-1),
                matching: components, matchingPolicy: .strict, repeatedTimePolicy: policy,
                direction: .forward), calendar.isDate(date, inSameDayAs: day) else { return nil }
            return date
        }
        return Array(Set(matches)).sorted()
    }

    static func nextClock(hour: Int, minute: Int, after now: Date, in calendar: Calendar) -> Date {
        var day = calendar.startOfDay(for: now)
        for _ in 0..<3 {
            if let date = times(on: day, hour: hour, minute: minute, in: calendar).first(where: { $0 > now }) {
                return date
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return now.addingTimeInterval(3_600)
    }

    static func dayKey(_ date: Date, in calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static func offset(_ date: Date, in zone: TimeZone) -> String {
        let offset = zone.secondsFromGMT(for: date) / 60
        let sign = offset < 0 ? "−" : "+"
        return "UTC\(sign)\(String(format: "%02d:%02d", abs(offset) / 60, abs(offset) % 60))"
    }
}
