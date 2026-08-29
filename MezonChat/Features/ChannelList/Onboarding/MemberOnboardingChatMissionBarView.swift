import UIKit

final class MemberOnboardingChatMissionBarView: UIControl {

    static let preferredHeight: CGFloat = 56

    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let topSeparator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.theme.secondary
        clipsToBounds = true
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)

        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.backgroundColor = UIColor.theme.border
        addSubview(topSeparator)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.image = UIImage.mezonSystemImage("number", withConfiguration: MezonSymbolConfiguration(pointSize: 16.sf, weight: .semibold))?
            .mezonTinted(UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
        iconView.isUserInteractionEnabled = false

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.numberOfLines = 1
        titleLabel.isUserInteractionEnabled = false

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.text
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isUserInteractionEnabled = false

        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            topSeparator.topAnchor.constraint(equalTo: topAnchor),
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.heightAnchor.constraint(equalToConstant: 0.5),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12.sw),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20.swh),
            iconView.heightAnchor.constraint(equalToConstant: 20.swh),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16.sw),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10.sh),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2.sh),
            subtitleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8.sh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
        topSeparator.backgroundColor = UIColor.theme.border
        titleLabel.textColor = UIColor.theme.textStrong
        subtitleLabel.textColor = UIColor.theme.text
        iconView.image = UIImage.mezonSystemImage("number", withConfiguration: MezonSymbolConfiguration(pointSize: 16.sf, weight: .semibold))?
            .mezonTinted(UIColor.theme.textStrong, renderingMode: .alwaysOriginal)
    }

    @objc private func handleTap() {
        onTap?()
    }
}
