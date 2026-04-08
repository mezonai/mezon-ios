import UIKit

enum ApplicationBadge {
    static func setCount(_ count: Int) {
        let clamped = max(0, count)
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = clamped
        }
    }
}
