import UIKit

enum Haptics {
    static func impact(intensity: Double) {
        guard AppSettings.hapticsEnabled else { return }
        Task { @MainActor in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: CGFloat(min(max(intensity, 0), 1)))
        }
    }

    static func success() {
        guard AppSettings.hapticsEnabled else { return }
        Task { @MainActor in
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
