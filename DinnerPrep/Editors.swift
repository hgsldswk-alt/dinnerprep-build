import SwiftUI

struct MinutesEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let range: ClosedRange<Int>
    let hint: String
    let id: String
    let canRemind: (Int) -> Bool
    let onRemind: ((Int) -> Void)?
    let preview: (Int) -> String?
    let onSave: (Int) -> Void
    @State private var input: String
    @FocusState private var focused: Bool

    init(title: String, initial: Int?, range: ClosedRange<Int>, hint: String, id: String,
         canRemind: @escaping (Int) -> Bool = { _ in false }, onRemind: ((Int) -> Void)? = nil,
         preview: @escaping (Int) -> String?, onSave: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.hint = hint
        self.id = id
        self.canRemind = canRemind
        self.onRemind = onRemind
        self.preview = preview
        self.onSave = onSave
        _input = State(initialValue: initial.map(String.init) ?? "")
    }

    private var value: Int? { DinnerMath.parse(input, in: range) }

    var body: some View {
        Page(L.t(title), detail: L.t(hint), close: "action.cancel", closeID: id + ".cancel",
             onClose: { dismiss() }) {
            TextField(L.t("field.minutes"), text: $input)
                .keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                .focused($focused)
                .accessibilityIdentifier(id + ".minutes")
            if let value {
                Text(L.minutes(value)).font(.title.bold()).foregroundStyle(Palette.accentText)
                if let start = preview(value) {
                    Note(text: start).accessibilityIdentifier(id + ".preview")
                }
            } else {
                Note(text: L.f("field.range", range.lowerBound, range.upperBound))
                    .accessibilityIdentifier(id + ".validation")
            }
            let reminderAvailable = value.map(canRemind) == true
            if let onRemind {
                Button(L.t("reminder.saveAndSet")) {
                    guard let value, canRemind(value) else { return }
                    dismiss()
                    onRemind(value)
                }
                .buttonStyle(DinnerButtonStyle(primary: reminderAvailable))
                .disabled(!reminderAvailable)
                .accessibilityIdentifier(id + ".remind")
            }
            Button(L.t("action.done")) {
                guard let value else { return }
                onSave(value)
                dismiss()
            }
            .buttonStyle(DinnerButtonStyle(primary: !reminderAvailable))
            .disabled(value == nil)
            .accessibilityIdentifier(id + ".done")
        }
        .task { focused = true }
        .presentationDetents([.large])
    }
}

struct DinnerTimeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date
    @State private var clock: Date
    private let initial: Date
    private let calendar: Calendar
    private let preview: (Date) -> String?
    private let onSave: (Date) -> Void
    private static let clockCalendar = DinnerCalendar.calendar(in: TimeZone(secondsFromGMT: 0)!)

    init(initial: Date, calendar: Calendar, preview: @escaping (Date) -> String?, onSave: @escaping (Date) -> Void) {
        self.initial = DinnerMath.minute(initial)
        self.calendar = calendar
        self.preview = preview
        self.onSave = onSave
        let parts = calendar.dateComponents([.hour, .minute], from: initial)
        let seconds = (parts.hour ?? 19) * 3_600 + (parts.minute ?? 0) * 60
        _day = State(initialValue: initial)
        _clock = State(initialValue: Date(timeIntervalSinceReferenceDate: Double(seconds)))
    }

    private var times: [Date] {
        let parts = Self.clockCalendar.dateComponents([.hour, .minute], from: clock)
        guard let hour = parts.hour, let minute = parts.minute else { return [] }
        return DinnerCalendar.times(on: day, hour: hour, minute: minute, in: calendar)
    }

    var body: some View {
        let times = self.times
        let selection = times.count == 1 ? times.first : times.first { $0 == initial }
        Page(L.t("home.dinner"), detail: L.t("date.editHint"), close: "action.cancel",
             closeID: "dinner.cancel", onClose: { dismiss() }) {
            DatePicker(L.t("home.dinner"), selection: $clock, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.calendar, Self.clockCalendar)
                .environment(\.timeZone, Self.clockCalendar.timeZone)
                .accessibilityIdentifier("dinner.time")
            Note(text: L.t("date.label"))
            DatePicker(L.t("date.label"), selection: $day, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.calendar, calendar)
                .environment(\.timeZone, calendar.timeZone)
                .accessibilityIdentifier("dinner.date")
            if times.count > 1 {
                Note(text: L.t("date.repeated"))
                ForEach(times, id: \.self) { time in
                    Button {
                        save(time)
                    } label: {
                        DetailRow(title: L.time(time, zone: calendar.timeZone),
                                  detail: DinnerCalendar.offset(time, in: calendar.timeZone),
                                  value: selection == time ? L.t("action.selected") : nil)
                    }
                    .buttonStyle(.plain)
                    .panel()
                    .accessibilityAddTraits(selection == time ? .isSelected : [])
                    .accessibilityIdentifier("dinner.offset." + DinnerCalendar.offset(time, in: calendar.timeZone))
                }
            }
            if let selection {
                Text(L.time(selection, zone: calendar.timeZone)).font(.title.bold()).foregroundStyle(Palette.accentText)
                if let start = preview(selection) {
                    Note(text: start).accessibilityIdentifier("dinner.preview")
                }
            } else if times.isEmpty {
                Note(text: L.t("date.missing"))
                    .accessibilityIdentifier("dinner.validation")
            }
            Button(L.t("action.done")) {
                guard let selection else { return }
                save(selection)
            }
            .buttonStyle(DinnerButtonStyle(primary: true))
            .disabled(selection == nil)
            .accessibilityIdentifier("dinner.done")
        }
    }

    private func save(_ value: Date) {
        onSave(value)
        dismiss()
    }
}
