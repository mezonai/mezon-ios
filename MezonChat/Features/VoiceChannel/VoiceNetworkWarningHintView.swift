import UIKit

final class VoiceNetworkWarningHintView: UIView {

    private static let fillColor = UIColor(rgb: 0xFDE8D7)
    private static let textColor = UIColor(rgb: 0x202124)
    private static let iconColor = UIColor(rgb: 0xB45309)
    private static let cornerRadius: CGFloat = 16

    let arrowView = UIView()
    var onDismiss: (() -> Void)?

    private let bubble = UIView()
    private let iconBadge = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let textStack = UIStackView()
    private let closeButton = UIButton(type: .custom)
    private let arrowLayer = CAShapeLayer()

    init(title: String, body: String) {
        super.init(frame: .zero)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = Self.fillColor
        bubble.layer.cornerRadius = Self.cornerRadius
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.2
        bubble.layer.shadowRadius = 12
        bubble.layer.shadowOffset = CGSize(width: 0, height: 6)

        iconBadge.translatesAutoresizingMaskIntoConstraints = false
        iconBadge.backgroundColor = Self.iconColor.withAlphaComponent(0.15)
        iconBadge.layer.cornerRadius = 16

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(
            systemName: "exclamationmark.triangle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        )
        iconView.tintColor = Self.iconColor
        iconView.contentMode = .center

        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Self.textColor
        titleLabel.text = title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = Self.textColor.withAlphaComponent(0.75)
        bodyLabel.text = body
        bodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(bodyLabel)
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.axis = .vertical
        textStack.spacing = 2

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
        iconBadge.addSubview(iconView)
        bubble.addSubview(iconBadge)
        bubble.addSubview(textStack)
        bubble.addSubview(closeButton)

        let arrowCentered = arrowView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor)
        arrowCentered.priority = .defaultLow
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
            iconBadge.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 16),
            iconBadge.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            iconBadge.topAnchor.constraint(greaterThanOrEqualTo: bubble.topAnchor, constant: 12),
            iconBadge.widthAnchor.constraint(equalToConstant: 32),
            iconBadge.heightAnchor.constraint(equalToConstant: 32),
            iconView.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            textStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -12),
            textStack.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -12),
            closeButton.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
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
        bubble.layoutIfNeeded()
        let textWidth = textStack.bounds.width
        if textWidth > 0, titleLabel.preferredMaxLayoutWidth != textWidth {
            titleLabel.preferredMaxLayoutWidth = textWidth
            bodyLabel.preferredMaxLayoutWidth = textWidth
            superview?.setNeedsLayout()
        }
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
