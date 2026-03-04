import UIKit

extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach { addSubview($0) }
    }

    @discardableResult
    func pinToAutoLayout() -> Self {
        translatesAutoresizingMaskIntoConstraints = false
        return self
    }

    func pinEdges(to view: UIView? = nil, insets: UIEdgeInsets = .zero) {
        guard let target = view ?? superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: target.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: target.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: target.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: target.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func pinToSafeArea(of view: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -insets.bottom),
        ])
    }
}
