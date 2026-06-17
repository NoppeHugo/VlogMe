import StoreKit
import Combine

enum ExportResolution {
    case hd1080
    case uhd4K

    var scale: CGFloat {
        switch self {
        case .hd1080: return 1
        case .uhd4K:  return 2
        }
    }

    var label: String {
        switch self {
        case .hd1080: return "1080p"
        case .uhd4K:  return "4K"
        }
    }
}

@MainActor
final class Entitlements: ObservableObject {

    static let monthlyID = "com.hugonoppe.vlogme.pro.monthly"
    static let annualID  = "com.hugonoppe.vlogme.pro.annual"

    @Published private(set) var isPro: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoadingProducts: Bool = false
    @Published var purchaseError: String?

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = listenForTransactions()
        Task { await refreshStatus() }
    }

    deinit { updateTask?.cancel() }

    // MARK: - Computed capabilities

    var exportResolution: ExportResolution { isPro ? .uhd4K : .hd1080 }
    var includesOutro: Bool { false }
    var canExport: Bool { isPro }
    // Plus de limite de durée — l'enregistrement est illimité pour tous.

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var annual: Product?  { products.first { $0.id == Self.annualID } }

    var savingsPercent: Int? {
        guard let m = monthly, let a = annual, m.price > 0 else { return nil }
        let annualMonthly = a.price / 12
        let savings = (1 - annualMonthly / m.price) * 100
        return max(0, Int(truncating: savings as NSDecimalNumber))
    }

    // MARK: - StoreKit

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        do {
            let loaded = try await Product.products(for: [Self.monthlyID, Self.annualID])
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            // Unavailable in dev — fail silently
        }
        isLoadingProducts = false
    }

    func purchase(_ product: Product) async {
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
                await refreshStatus()
                Analytics.track(.purchaseCompleted, [
                    "product_id": product.id,
                    "price": (product.price as NSDecimalNumber).doubleValue
                ])
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshStatus()
            Analytics.track(.purchaseRestored, ["is_pro": isPro])
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func refreshStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.monthlyID || tx.productID == Self.annualID {
                hasPro = true
            }
        }
        isPro = hasPro
        Analytics.setPro(hasPro)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refreshStatus()
                }
            }
        }
    }
}
