import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: StoreAccess
    @Environment(\.dismiss) private var dismiss
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) { self.onClose = onClose }

    var body: some View {
        Page(L.t("store.title"), close: "action.close", closeID: "paywall.close",
             onClose: { if let onClose { onClose() } else { dismiss() } }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(status).font(.footnote.bold()).foregroundStyle(Palette.accentText)
                    .accessibilityIdentifier("paywall.status")
                Text(L.t("store.headline")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                feature("store.morePrep")
                feature("store.reuse")
                feature("store.organize")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(fill: Palette.tint)

            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("store.stillFree")).font(.headline)
                Note(text: L.t("store.freeFeatures"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel()

            if !store.entitlement.purchasedPro {
                Button(store.price().map { L.f("store.buyPrice", $0) } ?? L.t("store.buy")) {
                    Task { await store.buy(Launch.proID) }
                }
                .buttonStyle(DinnerButtonStyle(primary: true))
                .disabled(store.busy)
                .accessibilityIdentifier("paywall.buy")
                Note(text: L.t("store.oneTime"))
            }

            if store.entitlement.trialClaimedAt == nil && !store.entitlement.purchasedPro {
                Button(L.t("store.claimTrial")) { Task { await store.buy(Launch.trialID) } }
                    .buttonStyle(DinnerButtonStyle())
                    .disabled(store.busy)
                    .accessibilityIdentifier("paywall.trial")
                Note(text: L.t("store.trialNote"))
            }

            Button(L.t("store.restore")) { Task { await store.restore() } }
                .buttonStyle(LinkButtonStyle())
                .disabled(store.busy)
                .accessibilityIdentifier("paywall.restore")
            if let message = store.message { Note(text: message).accessibilityIdentifier("paywall.message") }
        }
        .task { await store.loadProducts() }
    }

    private var status: String {
        if store.entitlement.purchasedPro { return L.t("store.unlocked") }
        if !model.hasPro { return L.t("store.ended") }
        let days = store.entitlement.remainingDays(at: model.now)
        return L.f(days == 1 ? "store.dayLeft" : "store.daysLeft", days)
    }

    private func feature(_ key: String) -> some View {
        Label(L.t(key), systemImage: "checkmark")
            .font(.subheadline.weight(.semibold))
    }
}
