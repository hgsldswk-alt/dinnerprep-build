import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 62.0
    @Binding var editorOpen: Bool
    @State private var editor: Edit?
    @State private var choosingPrepFile = false
    @State private var readingPrepFile = false
    @State private var prepFileError = false

    private enum Edit: Identifiable {
        case recipe, dinner, buffer, prep(PrepItem)

        var id: String {
            switch self {
            case .recipe: "recipe"
            case .dinner: "dinner"
            case .buffer: "buffer"
            case .prep(let item): item.id
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                header
                hero
                fields
                prepSection
                actions
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
        }
        .pageSurface()
        .disabled(readingPrepFile)
        .modifier(PrepFilePicker(isPresented: $choosingPrepFile, reading: $readingPrepFile, onRead: { values in
            model.route = .fileImport(values)
        }, onError: { prepFileError = true }))
        .sheet(item: $editor) { edit in
            editing(edit)
        }
        .onChange(of: editor != nil || choosingPrepFile || readingPrepFile) { _, open in editorOpen = open }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(L.t("app.name")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            Button(L.t("settings.title")) { model.route = .settings }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("home.settings")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let result = model.timing {
                switch result.status(at: model.now) {
                case .upcoming:
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .bottom) {
                            mainClock(result)
                            Spacer(minLength: 12)
                            dinnerClock(result, alignment: .trailing)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            mainClock(result)
                            dinnerClock(result, alignment: .leading)
                        }
                    }
                    breakdown(result)
                case .startNow(let late, let estimate):
                    Text(late == 0 ? L.t("home.onTime") : L.f("home.lateBy", L.minutes(late)))
                        .font(.footnote.bold()).foregroundStyle(Palette.accentText)
                        .accessibilityIdentifier("home.late")
                    Text(L.t("home.startNow")).font(.largeTitle.bold())
                        .accessibilityIdentifier("home.startTime")
                    Divider()
                    HStack {
                        Note(text: L.t("home.earliest"))
                        Spacer(minLength: 6)
                        Text(time(estimate)).font(.headline).monospacedDigit()
                            .accessibilityIdentifier("home.earliestTime")
                    }
                    Note(text: L.f("home.lateExplanation", time(model.now), L.minutes(result.total)))
                    dinnerClock(result, alignment: .leading)
                }
            } else {
                Text(L.t("home.startBy")).font(.footnote.bold()).foregroundStyle(Palette.accentText)
                Text(L.t(model.meal.recipe == nil ? "home.addRecipe" : "home.invalidPlan"))
                    .font(.title.bold())
                Note(text: L.t(model.meal.recipe == nil ? "home.recipeHint" : "home.totalLimit"))
            }
            if model.meal.zoneID != model.zone.identifier {
                Note(text: L.f("date.originalZone", model.meal.zoneID.replacingOccurrences(of: "_", with: " ")))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(fill: Palette.tint)
    }

    private func mainClock(_ result: DinnerMath.Result) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(L.t("home.startBy")).font(.footnote.bold()).foregroundStyle(Palette.accentText)
            Text(time(result.start)).font(.system(size: clockSize, weight: .bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.54)
                .accessibilityIdentifier("home.startTime")
            if !model.calendar.isDate(result.start, inSameDayAs: result.dinner) ||
                !model.calendar.isDate(result.start, inSameDayAs: model.now) {
                Note(text: day(result.start))
            }
        }
        .layoutPriority(1)
    }

    private func dinnerClock(_ result: DinnerMath.Result, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Note(text: L.t("home.dinner"))
            Text(time(result.dinner)).font(.subheadline.bold()).monospacedDigit()
            if !model.calendar.isDate(result.dinner, inSameDayAs: model.now) ||
                !model.calendar.isDate(result.start, inSameDayAs: result.dinner) {
                Note(text: day(result.dinner))
            }
        }
    }

    private func breakdown(_ result: DinnerMath.Result) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            let segments = [result.recipe, result.prep, result.buffer]
            let colors = [Palette.accentText, Palette.mid, Palette.soft]
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(segments.indices, id: \.self) { index in
                        if segments[index] > 0 {
                            Capsule().fill(colors[index])
                                .padding(.trailing, 2)
                                .frame(width: geometry.size.width * CGFloat(segments[index]) / CGFloat(result.total))
                        }
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 6) {
                measure("home.recipePart", L.minutes(result.recipe))
                measure("home.extra", L.f("minutes.plus", result.prep))
                measure("home.buffer", L.f("minutes.plus", result.buffer))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.breakdown")
    }

    private func measure(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Note(text: L.t(key))
            Text(value).font(.footnote.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: some View {
        HStack(alignment: .top, spacing: 8) {
            field("home.recipeTime", model.meal.recipe.map(L.minutes) ?? L.t("home.addMinutes"),
                  detail: nil, id: "home.recipe") { editor = .recipe }
            field("home.dinner", time(model.meal.dinner), detail: day(model.meal.dinner), id: "home.dinner") { editor = .dinner }
        }
    }

    private func field(_ key: String, _ value: String, detail: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Note(text: L.t(key))
                Text(value).font(.headline).monospacedDigit()
                if let detail { Note(text: detail) }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .contentShape(Rectangle())
            .panel(radius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var prepSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("home.extra")).font(.headline)
                    Note(text: L.t("home.extraHint"))
                }
                Spacer(minLength: 6)
                Button(L.t("library.title")) { model.route = .library }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("home.library")
            }
            if !model.homeItems.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.homeItems) { item in
                        if item.id != model.homeItems.first?.id { Divider() }
                        PrepChoice(item: item, scope: "home") { editor = .prep(item) }
                    }
                }
                .panel()
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    bufferButton
                    Spacer(minLength: 8)
                    importFileButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    bufferButton
                    importFileButton
                }
            }
            if prepFileError { Note(text: L.t("import.invalidFile")).accessibilityIdentifier("home.importNotice") }
        }
    }

    private var bufferButton: some View {
        Button(model.meal.buffer > 0 ? L.f("home.bufferFormat", L.minutes(model.meal.buffer)) : L.t("home.addBuffer")) {
            editor = .buffer
        }
        .buttonStyle(LinkButtonStyle())
        .accessibilityIdentifier("home.buffer")
    }

    private var importFileButton: some View {
        Button(L.t("library.importFile")) {
            prepFileError = false
            choosingPrepFile = true
        }
        .buttonStyle(LinkButtonStyle())
        .accessibilityIdentifier("home.importFile")
    }

    private var actions: some View {
        VStack(spacing: 7) {
            if let count = model.testReminderCount {
                Text(String(count)).accessibilityIdentifier("test.reminderCount")
            }
            if model.storageWarning { Note(text: L.t("storage.unavailable")) }
            if let notice = model.notice {
                Note(text: L.t(notice.rawValue)).accessibilityIdentifier("reminder.notice")
                if notice == .denied {
                    Button(L.t("reminder.openSettings")) {
                        if model.test {
                            model.allowTestNotifications()
                        } else if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("reminder.settings")
                }
            }
            if model.meal.started {
                Note(text: L.t("home.cookingRecorded")).accessibilityIdentifier("home.cookingRecorded")
            } else if let timing = model.timing,
                      case .startNow(_, let estimate) = timing.status(at: model.now) {
                if timing.dinner != estimate {
                    Button(L.f("home.useTime", time(estimate))) { model.setSuggestedDinner(estimate) }
                        .buttonStyle(DinnerButtonStyle(primary: true))
                        .accessibilityIdentifier("home.suggest")
                }
                Button(L.t("home.startedCooking")) { model.startedCooking() }
                    .buttonStyle(DinnerButtonStyle(primary: timing.dinner == estimate))
                    .accessibilityIdentifier("home.started")
            } else if let ticket = model.data.reminder {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L.t(model.confirmedReminder == nil ? "reminder.saving" : "reminder.set"))
                            .font(.subheadline.bold()).accessibilityIdentifier("reminder.status")
                        Note(text: L.f("date.dayTime", day(ticket.start), time(ticket.start)))
                            .accessibilityIdentifier("reminder.time")
                    }
                    Spacer(minLength: 8)
                    Button(L.t("reminder.cancel")) { model.cancelReminderByUser() }
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("reminder.cancel")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .panel(fill: Palette.tint, radius: 13)
            } else {
                Button(model.timing.map { L.f("reminder.at", time($0.start)) } ?? L.t("reminder.action")) {
                    model.enableReminder()
                }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(model.timing == nil)
                .accessibilityIdentifier("reminder.enable")
            }
            if model.timing != nil {
                Button(L.t("share.plan")) { model.route = .planCard }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("home.planCard")
            }
            if model.data.hasMilestone && !model.data.milestoneDismissed {
                HStack {
                    Button(L.t("share.milestone")) { model.route = .milestone }
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("home.milestone")
                    Spacer()
                    Button(L.t("action.hide")) { model.dismissMilestone() }
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("home.hideMilestone")
                }
                .padding(.horizontal, 8)
                .panel(fill: Palette.tint)
            }
        }
    }

    @ViewBuilder private func editing(_ edit: Edit) -> some View {
        switch edit {
        case .recipe:
            MinutesEditor(title: "home.recipeTime", initial: model.meal.recipe, range: 1...DinnerMath.maxMinutes,
                          hint: "home.recipeHint", id: "recipe",
                          canRemind: { value in
                guard !model.meal.started, let result = editedTiming({ $0.recipe = value }) else { return false }
                return result.start > model.now
            }, onRemind: { value in
                model.updateMeal(remind: true) { $0.recipe = value }
            }, preview: { value in
                previewStart { $0.recipe = value }
            }) { value in
                model.updateMeal { $0.recipe = value }
            }
        case .buffer:
            MinutesEditor(title: "home.buffer", initial: model.meal.buffer, range: 0...DinnerMath.maxBuffer,
                          hint: "home.bufferHint", id: "buffer", preview: { value in
                previewStart { $0.buffer = value }
            }) { value in
                model.updateMeal { $0.buffer = value }
            }
        case .prep(let item):
            MinutesEditor(title: "home.mealMinutes", initial: model.meal.prep.first(where: { $0.id == item.id })?.minutes ?? item.minutes,
                          range: 1...DinnerMath.maxMinutes, hint: "home.mealMinutesHint", id: "prep", preview: { value in
                previewStart { $0.setPrepMinutes(value, for: item) }
            }) { value in
                model.setMealMinutes(value, for: item)
            }
        case .dinner:
            DinnerTimeEditor(initial: model.meal.dinner, calendar: model.calendar, preview: { value in
                previewStart { $0.dinner = value }
            }) { value in
                model.setSuggestedDinner(value)
            }
        }
    }

    private func previewStart(_ change: (inout MealDraft) -> Void) -> String? {
        guard let result = editedTiming(change) else { return nil }
        return L.f("home.previewStart", L.f("date.dayTime", day(result.start), time(result.start)))
    }

    private func editedTiming(_ change: (inout MealDraft) -> Void) -> DinnerMath.Result? {
        var edited = model.meal
        change(&edited)
        return try? edited.timing()
    }

    private func time(_ date: Date) -> String { L.time(date, zone: model.zone) }
    private func day(_ date: Date) -> String { L.day(date, relativeTo: model.now, calendar: model.calendar) }
}

struct PrepChoice: View {
    @EnvironmentObject private var model: AppModel
    let item: PrepItem
    let scope: String
    let edit: () -> Void

    private var selection: MealPrep? { model.meal.prep.first { $0.id == item.id } }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if item.minutes != nil || selection != nil { model.togglePrep(item) } else { edit() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selection == nil ? "square" : "checkmark.square.fill")
                        .foregroundStyle(Palette.accentText).accessibilityHidden(true)
                    Text(verbatim: selection?.displayName ?? item.displayName).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == nil ? [] : .isSelected)
            .accessibilityIdentifier(scope + ".toggle." + item.id)

            Button((selection?.minutes ?? item.minutes).map(L.minutes) ?? L.t("library.setTime"), action: edit)
                .buttonStyle(LinkButtonStyle())
                .padding(.trailing, 6)
                .accessibilityLabel(L.f("library.editLabel", selection?.displayName ?? item.displayName))
                .accessibilityIdentifier(scope + ".minutes." + item.id)
        }
    }
}
