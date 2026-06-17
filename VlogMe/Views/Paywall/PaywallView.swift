import SwiftUI
import StoreKit

struct PaywallView: View {

    enum Context { case export, camera, generic }

    @EnvironmentObject private var entitlements: Entitlements
    @Environment(\.dismiss) private var dismiss

    var context: Context = .generic
    @State private var selectedPlan: String = Entitlements.annualID
    @State private var isPurchasing = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    benefitsList
                        .padding(.top, 36)
                    pricingCards
                        .padding(.top, 28)
                    purchaseButton
                        .padding(.top, 20)
                    restoreButton
                        .padding(.top, 12)
                    legalNote
                        .padding(.top, 16)
                        .padding(.bottom, 48)
                }
                .padding(.horizontal, 24)
            }

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(10)
                            .background(Color.white.opacity(0.1), in: Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .task { await entitlements.loadProducts() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            if context == .export {
                MascotSpeech(
                    message: "Ta vidéo est prête ! 🎬\nPasse à Pro pour\nla télécharger.",
                    size: 110,
                    accessory: .star
                )
                .padding(.top, 40)
            } else {
                ZStack {
                    Circle()
                        .fill(Color.accentOrange.opacity(0.15))
                        .frame(width: 100, height: 100)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.accentOrange)
                }
                .padding(.top, 56)
            }

            Text("VlogMe Pro")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(context == .export ? "Exporte et partage tes vlogs." : "Filmez sans limites.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Benefits

    private var benefitsList: some View {
        VStack(spacing: 16) {
            benefitRow(icon: "infinity", color: Color.accentOrange,
                       title: "Durée illimitée",
                       detail: "Plus de limite à 2 min — vloggez autant que vous voulez.")
            benefitRow(icon: "4k.tv.fill", color: .blue,
                       title: "Export 4K",
                       detail: "Qualité maximale pour un rendu impeccable.")
            benefitRow(icon: "music.note", color: .green,
                       title: "Musique de fond",
                       detail: "Ajoutez vos morceaux préférés à vos vlogs.")
            benefitRow(icon: "wand.and.stars", color: .purple,
                       title: "Toutes les futures fonctions",
                       detail: "Accès prioritaire aux prochaines mises à jour.")
        }
    }

    private func benefitRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
            }
            Spacer()
        }
    }

    // MARK: - Pricing cards

    private var pricingCards: some View {
        VStack(spacing: 12) {
            if entitlements.isLoadingProducts {
                ProgressView().tint(Color.accentOrange)
            } else if entitlements.products.isEmpty {
                Text("Tarifs indisponibles pour l'instant.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                if let annual = entitlements.annual {
                    planCard(product: annual, isPopular: true)
                }
                if let monthly = entitlements.monthly {
                    planCard(product: monthly, isPopular: false)
                }
            }
        }
    }

    private func planCard(product: Product, isPopular: Bool) -> some View {
        let isSelected = selectedPlan == product.id
        return Button { selectedPlan = product.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.id == Entitlements.annualID ? "Annuel" : "Mensuel")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                        if isPopular, let pct = entitlements.savingsPercent, pct > 0 {
                            Text("−\(pct)%")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentOrange, in: Capsule())
                        }
                    }
                    if product.id == Entitlements.annualID {
                        Text(annualMonthlyLabel(product))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(product.id == Entitlements.annualID ? "/ an" : "/ mois")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentOrange.opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentOrange : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func annualMonthlyLabel(_ product: Product) -> String {
        let monthly = product.price / 12
        return "soit \(monthly.formatted(product.priceFormatStyle)) / mois"
    }

    // MARK: - Purchase button

    private var purchaseButton: some View {
        Button {
            guard let product = entitlements.products.first(where: { $0.id == selectedPlan }) else { return }
            isPurchasing = true
            Task {
                await entitlements.purchase(product)
                isPurchasing = false
                if entitlements.isPro { dismiss() }
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text("Passer à Pro")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                entitlements.products.isEmpty
                    ? Color.white.opacity(0.2)
                    : Color.accentOrange,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .disabled(entitlements.products.isEmpty || isPurchasing)
    }

    // MARK: - Restore + legal

    private var restoreButton: some View {
        Button {
            Task { await entitlements.restorePurchases() }
        } label: {
            Text("Restaurer les achats")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                .underline()
        }
    }

    private var legalNote: some View {
        Text("L'abonnement se renouvelle automatiquement. Résiliable à tout moment depuis les Réglages.")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.25))
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }
}
