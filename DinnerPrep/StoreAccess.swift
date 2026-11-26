import Foundation
import StoreKit
import SwiftUI

@MainActor
final class StoreAccess: ObservableObject {
    @Published private(set) var entitlement = Entitlement()
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var busy = false
    @Published private(set) var message: String?
    @Published private(set) var ready = false

    private let vault = EntitlementVault()
    private let test: Bool
    private let expired: Bool
    private let purchased: Bool
    private(set) var free: Bool
    private var updates: Task<Void, Never>?
    private var persistence: Task<Void, Never>?
    private var vaultAvailable = false
    private var loadedVault = false
    private var lastProUpdate: Date?

    init(arguments: [String]) {
        let testing = arguments.contains("-ui-testing")
        test = testing
        expired = testing && (arguments.contains("-expired") || arguments.contains("-paywall"))
        purchased = testing && arguments.contains("-purchased")
        free = Launch.isFree(arguments: arguments)
    }

    func hasPro(at now: Date) -> Bool { ready && entitlement.hasPro(at: now, free: free) }

    func start(at now: Date) async {
        guard !ready else { return }
        if test {
            let start = expired ? now.addingTimeInterval(-31 * 86_400) : now
            entitlement = Entitlement(firstOpen: start, proStartedAt: free ? nil : start, purchasedPro: purchased)
            ready = true
            return
        }
        await loadVault(at: now)
        ready = true
        guard !free else { return }
        updates = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update, self.accept(transaction) {
                    await transaction.finish()
                }
            }
        }
        Task { await refresh() }
    }

    func observe(_ now: Date) {
        guard ready, vaultAvailable, !test else { return }
        var updated = entitlement
        updated.observe(now, free: free)
        if updated != entitlement { store(updated) }
    }

    func resume(at now: Date) async {
        guard ready, !test else { return }
        if loadedVault {
            let needsRetry = !vaultAvailable
            vaultAvailable = true
            observe(now)
            if needsRetry { store(entitlement) }
        } else { await loadVault(at: now) }
        if !free { await refresh() }
    }

    private func loadVault(at now: Date) async {
        do {
            var loaded = try await vault.load() ?? Entitlement(firstOpen: now)
            loaded.purchasedPro = loaded.purchasedPro || entitlement.purchasedPro
            if let receipt = entitlement.trialClaimedAt { loaded.applyTrialReceipt(originalDate: receipt) }
            loaded.observe(now, free: free)
            vaultAvailable = true
            loadedVault = true
            store(loaded)
        } catch {
            if !ready {
                entitlement = Entitlement(firstOpen: now.addingTimeInterval(-Entitlement.trialDuration))
            }
        }
    }

    private func store(_ value: Entitlement) {
        entitlement = value
        guard vaultAvailable else { return }
        let previous = persistence
        persistence = Task {
            await previous?.value
            do { try await vault.save(value) }
            catch { self.vaultAvailable = false }
        }
    }

    private func refresh(clearMissing: Bool = false) async {
        let updateAtStart = lastProUpdate
        var foundPro = false
        for await verification in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else { continue }
            if transaction.productID == Launch.proID && transaction.revocationDate == nil { foundPro = true }
            _ = accept(transaction)
        }
        if !foundPro, let result = await StoreKit.Transaction.latest(for: Launch.proID),
           case .verified(let latest) = result, latest.revocationDate != nil {
            _ = accept(latest)
        } else if clearMissing && !foundPro && updateAtStart == lastProUpdate {
            var updated = entitlement
            updated.purchasedPro = false
            if updated != entitlement { store(updated) }
        }
    }

    private func accept(_ transaction: StoreKit.Transaction) -> Bool {
        var updated = entitlement
        switch transaction.productID {
        case Launch.proID:
            let effectiveDate = transaction.revocationDate ?? transaction.purchaseDate
            guard lastProUpdate.map({ $0 <= effectiveDate }) ?? true else { return true }
            lastProUpdate = effectiveDate
            updated.purchasedPro = transaction.revocationDate == nil
        case Launch.trialID:
            if transaction.revocationDate == nil { updated.applyTrialReceipt(originalDate: transaction.originalPurchaseDate) }
        default:
            return false
        }
        if updated != entitlement { store(updated) }
        return true
    }

    func loadProducts() async {
        guard !free, !test else { return }
        do {
            let available = try await Product.products(for: [Launch.proID, Launch.trialID])
            let eligible = available.filter { $0.type == .nonConsumable }
            products = Dictionary(uniqueKeysWithValues: eligible.map { ($0.id, $0) })
        } catch {
            message = L.t("store.unavailable")
        }
    }

    func price() -> String? {
        test ? L.t("store.testPrice") : products[Launch.proID]?.displayPrice
    }

    func buy(_ id: String) async {
        guard !busy, !free, !test else { return }
        busy = true
        message = nil
        defer { busy = false }
        if products[id] == nil { await loadProducts() }
        guard let product = products[id] else {
            message = L.t("store.unavailable")
            return
        }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard accept(transaction) else { return }
                await transaction.finish()
                message = L.t(id == Launch.proID ? "store.unlocked" : "store.receiptSaved")
            case .success(.unverified):
                message = L.t("store.verifyFailed")
            case .pending:
                message = L.t("store.pending")
            case .userCancelled:
                break
            @unknown default:
                message = L.t("store.unavailable")
            }
        } catch {
            message = L.t("store.unavailable")
        }
    }

    func restore() async {
        guard !busy, !free, !test else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh(clearMissing: true)
            message = L.t(entitlement.purchasedPro || entitlement.trialClaimedAt != nil
                ? "store.restored" : "store.nothingToRestore")
        } catch {
            message = L.t("store.restoreFailed")
        }
    }
}
