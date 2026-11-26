import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreAccess
    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen = .settings
    @State private var confirmingClear = false
    @State private var confirmingDelete = false
    @State private var deleting: MealPreset?

    private enum Screen {
        case settings, presets, edit(MealPreset?), card(DinnerMath.Result, [MealPrep]), milestone, paywall
    }

    var body: some View {
        switch screen {
        case .settings: settings
        case .presets: presets
        case .edit(let preset):
            PresetEditor(preset: preset, onClose: { screen = .presets }) { name in
                if model.savePreset(name: name, replacing: preset) { screen = .presets }
                else { screen = .paywall }
            }
        case .card(let result, let prep):
            CardView(timing: result, prep: prep, onClose: { screen = .presets }, autoShare: true)
        case .milestone: CardView(onClose: { screen = .settings })
        case .paywall: PaywallView(onClose: { screen = .settings })
        }
    }

    private var settings: some View {
        Page(L.t("settings.title"), closeID: "settings.done", onClose: { dismiss() }) {
            groupButton("settings.savedPlans", detail: nil, id: "settings.savedPlans") { screen = .presets }
            if model.data.hasMilestone {
                groupButton("share.milestone", detail: nil, id: "settings.milestone") { screen = .milestone }
            }
            if !store.free {
                groupButton("store.title", detail: trialStatus, id: "settings.pro") { screen = .paywall }
            }
            groupButton("settings.clearMeal", detail: nil, id: "settings.clearMeal") { confirmingClear = true }
            Note(text: L.t("settings.privacy"))
        }
        .alert(L.t("settings.clearTitle"), isPresented: $confirmingClear) {
            Button(L.t("settings.clearMeal"), role: .destructive) {
                model.clearMeal()
                dismiss()
            }
            Button(L.t("action.cancel"), role: .cancel) {}
        } message: {
            Text(L.t("settings.clearHint"))
        }
    }

    private var trialStatus: String {
        if store.entitlement.purchasedPro { return L.t("store.unlocked") }
        if !model.hasPro { return L.t("store.ended") }
        let days = store.entitlement.remainingDays(at: model.now)
        return L.f(days == 1 ? "store.dayLeft" : "store.daysLeft", days)
    }

    private func groupButton(_ title: String, detail: String?, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DetailRow(title: L.t(title), detail: detail, value: "›")
        }
        .buttonStyle(.plain)
        .panel()
        .accessibilityIdentifier(id)
    }

    private var presets: some View {
        Page(L.t("settings.savedPlans"), detail: L.t("presets.subtitle"), close: "action.back",
             closeID: "presets.back", onClose: { screen = .settings }) {
            if model.data.presets.isEmpty { Note(text: L.t("presets.empty")) }
            ForEach(Array(model.data.presets.enumerated()), id: \.element.id) { index, preset in
                presetRow(preset, index: index)
            }
            Button(L.t("presets.saveMeal")) { screen = model.hasPro ? .edit(nil) : .paywall }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(model.timing == nil)
                .accessibilityIdentifier("presets.save")
        }
        .alert(L.t("presets.deleteTitle"), isPresented: $confirmingDelete, presenting: deleting) { preset in
            Button(L.t("action.delete"), role: .destructive) { model.removePreset(preset) }
            Button(L.t("action.cancel"), role: .cancel) {}
        } message: { _ in
            Text(L.t("presets.deleteHint"))
        }
    }

    private func presetRow(_ preset: MealPreset, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            let result = try? preset.meal.timing()
            DetailRow(title: preset.name, detail: presetDetail(preset, result: result))
            if !preset.meal.prep.isEmpty {
                ForEach(preset.meal.prep) { item in
                    Note(text: L.f("share.item", item.displayName, L.minutes(item.minutes)))
                        .padding(.horizontal, 12)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { presetActions(preset, result: result) }
                VStack(alignment: .leading, spacing: 4) { presetActions(preset, result: result) }
            }
            .padding(.horizontal, 8)
            Menu {
                Button(L.t("action.rename")) { screen = model.hasPro ? .edit(preset) : .paywall }
                    .accessibilityIdentifier("presets.rename." + preset.id)
                if index > 0 {
                    Button(L.t("presets.moveUp")) {
                        if model.hasPro { model.movePreset(preset, offset: -1) } else { screen = .paywall }
                    }
                    .accessibilityIdentifier("presets.up." + preset.id)
                }
                if index < model.data.presets.count - 1 {
                    Button(L.t("presets.moveDown")) {
                        if model.hasPro { model.movePreset(preset, offset: 1) } else { screen = .paywall }
                    }
                    .accessibilityIdentifier("presets.down." + preset.id)
                }
                Button(L.t("action.delete"), role: .destructive) {
                    if model.hasPro {
                        deleting = preset
                        confirmingDelete = true
                    } else { screen = .paywall }
                }
                .accessibilityIdentifier("presets.delete." + preset.id)
            } label: {
                Label(L.t("presets.manage"), systemImage: "ellipsis.circle")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
            .padding(.horizontal, 12)
            .accessibilityIdentifier("presets.manage." + preset.id)
        }
        .padding(.bottom, 5)
        .panel()
    }

    @ViewBuilder private func presetActions(_ preset: MealPreset, result: DinnerMath.Result?) -> some View {
        Button(L.t("presets.use")) {
            if model.applyPreset(preset) { dismiss() } else { screen = .paywall }
        }
        .buttonStyle(LinkButtonStyle())
        .accessibilityIdentifier("presets.use." + preset.id)
        if let result {
            Button(L.t("action.share")) { screen = .card(result, preset.meal.prep) }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("presets.share." + preset.id)
        }
    }

    private func presetDetail(_ preset: MealPreset, result: DinnerMath.Result?) -> String? {
        guard let result else { return nil }
        let zone = TimeZone(identifier: preset.meal.zoneID) ?? model.zone
        return L.f("presets.summary", L.time(result.dinner, zone: zone), L.minutes(result.recipe), L.minutes(result.buffer))
    }
}

struct PresetEditor: View {
    let preset: MealPreset?
    let onClose: () -> Void
    let onSave: (String) -> Void
    @State private var name: String

    init(preset: MealPreset?, onClose: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.preset = preset
        self.onClose = onClose
        self.onSave = onSave
        _name = State(initialValue: preset?.name ?? "")
    }

    var body: some View {
        let clean = PrepCode.cleanedName(name)
        Page(L.t(preset == nil ? "presets.saveMeal" : "action.rename"), close: "action.cancel",
             closeID: "presetEdit.cancel", onClose: onClose) {
            TextField(L.t("field.name"), text: $name)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("presetEdit.name")
            if !name.isEmpty && clean == nil { Note(text: L.t("field.nameLimit")) }
            Button(L.t("action.save")) { if let clean { onSave(clean) } }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(clean == nil)
                .accessibilityIdentifier("presetEdit.save")
        }
    }
}
