import Foundation

private final class LocalizationBundle: NSObject {}

enum L {
    static func t(_ key: String) -> String {
        NSLocalizedString(key, bundle: Bundle(for: LocalizationBundle.self), comment: "")
    }

    static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: arguments)
    }

    static func minutes(_ value: Int) -> String { f("minutes.format", value) }

    static func time(_ date: Date, zone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func day(_ date: Date, relativeTo now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return t("date.today") }
        if let next = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: next) { return t("date.tomorrow") }
        if let previous = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: previous) { return t("date.yesterday") }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }
}
