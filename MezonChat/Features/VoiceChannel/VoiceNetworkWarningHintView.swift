import UIKit

final class VoiceNetworkWarningHintView: UIView {

    private static let fillColor = UIColor(rgb: 0xFDE8D7)
    private static let textColor = UIColor(rgb: 0x202124)
    private static let cornerRadius: CGFloat = 16

    let arrowView = UIView()
    var onDismiss: (() -> Void)?

    private let bubble = UIView()
    private let messageLabel = UILabel()
    private let closeButton = UIButton(type: .custom)
    private let arrowLayer = CAShapeLayer()

    init(message: String) {
        super.init(frame: .zero)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = Self.fillColor
        bubble.layer.cornerRadius = Self.cornerRadius
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.2
        bubble.layer.shadowRadius = 12
        bubble.layer.shadowOffset = CGSize(width: 0, height: 6)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = Self.textColor
        messageLabel.text = message

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(
            UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
            for: .normal
        )
        closeButton.tintColor = Self.textColor.withAlphaComponent(0.7)
        closeButton.accessibilityLabel = L(L10n.Common.close)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowLayer.fillColor = Self.fillColor.cgColor
        arrowView.layer.addSublayer(arrowLayer)

        addSubview(bubble)
        addSubview(arrowView)
        bubble.addSubview(messageLabel)
        bubble.addSubview(closeButton)

        let arrowCentered = arrowView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor)
        arrowCentered.priority = .defaultLow
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 16),
            messageLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -16),
            messageLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            closeButton.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 14),
            closeButton.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
            arrowView.topAnchor.constraint(equalTo: bubble.bottomAnchor),
            arrowView.bottomAnchor.constraint(equalTo: bottomAnchor),
            arrowView.widthAnchor.constraint(equalToConstant: 12),
            arrowView.heightAnchor.constraint(equalToConstant: 6),
            arrowView.leadingAnchor.constraint(greaterThanOrEqualTo: bubble.leadingAnchor, constant: 20),
            arrowView.trailingAnchor.constraint(lessThanOrEqualTo: bubble.trailingAnchor, constant: -20),
            arrowCentered,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = arrowView.bounds.size
        let arrow = UIBezierPath()
        arrow.move(to: .zero)
        arrow.addLine(to: CGPoint(x: size.width, y: 0))
        arrow.addLine(to: CGPoint(x: size.width / 2, y: size.height))
        arrow.close()
        arrowLayer.path = arrow.cgPath
        bubble.layer.shadowPath = UIBezierPath(roundedRect: bubble.bounds, cornerRadius: Self.cornerRadius).cgPath
    }

    @objc private func closeTapped() {
        onDismiss?()
    }
}
