import SwiftUI
import UIKit

/// Emballe `UIActivityViewController` (la share sheet iOS native) pour SwiftUI (cf. §6.2).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
