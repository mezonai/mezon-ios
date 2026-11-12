import UIKit

extension UIView {
    /// Assign an automation ID without changing VoiceOver grouping or labels.
    @discardableResult
    func identified(by identifier: String) -> Self {
        accessibilityIdentifier = identifier
        return self
    }
}
