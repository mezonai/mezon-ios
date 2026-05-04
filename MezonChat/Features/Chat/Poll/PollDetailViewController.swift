import AsyncDisplayKit
import UIKit

final class PollDetailViewController: UIViewController {

    private let question: String
    private let totalVotes: Int
    private let options: [PollOptionDisplay]
    private var selectedIndex: Int
    private var votersByOption: [Int: [PollVoter]]
    private let isLoading: Bool

    private let overlayView = UIView()
    private let containerView = UIView()
    private let headerStack = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let subtitleLabel = UILabel()
    private let bodyView = UIView()
    private let leftScrollView = UIScrollView()
    private let leftStackView = UIStackView()
    private let rightScrollView = UIScrollView()
    private let rightStackView = UIStackView()
    private let dividerView = UIView()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()

    private static let blurpleAlpha = UIColor(red: 88/255, green: 101/255, blue: 242/255, alpha: 0.2)
    private static let maxVisibleOptions = 5
    private static let optionRowHeight: CGFloat = 40
    private static let optionGap: CGFloat = 8
    private static let avatarSize: CGFloat = 32

    init(
        question: String,
        totalVotes: Int,
        options: [PollOptionDisplay],
        votersByOption: [Int: [PollVoter]],
        isLoading: Bool
    ) {
        self.question = question
        self.totalVotes = totalVotes
        self.options = options
        self.selectedIndex = options.first?.index ?? 0
        self.votersByOption = votersByOption
        self.isLoading = isLoading
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.view.alpha = 0
        UIView.animate(withDuration: 0.15) {
            self.view.alpha = 1
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateVoters(_ voters: [Int: [PollVoter]]) {
        self.votersByOption = voters
        updateRightColumn()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupOverlay()
        setupContainer()
        setupHeader()
        setupBody()
        updateRightColumn()
    }

    private func setupOverlay() {
        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        overlayView.frame = view.bounds
        overlayView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(overlayView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissModal))
        overlayView.addGestureRecognizer(tap)
    }

    private func setupContainer() {
        let t = UIColor.theme
        containerView.backgroundColor = t.primary
        containerView.layer.cornerRadius = 12
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.mezonBorder.cgColor
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            containerView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.85),
        ])

        let containerTap = UITapGestureRecognizer()
        containerView.addGestureRecognizer(containerTap)
    }

    private func setupHeader() {
        let t = UIColor.theme

        titleLabel.text = question
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = t.textStrong
        titleLabel.numberOfLines = 2

        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        closeButton.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        closeButton.tintColor = t.textStrong
        closeButton.addTarget(self, action: #selector(dismissModal), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.spacing = 8
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(closeButton)

        containerView.addSubview(headerStack)
        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),
        ])

        let voteWord = totalVotes > 1 ? L(L10n.Poll.votes) : L(L10n.Poll.vote)
        subtitleLabel.text = "\(totalVotes) \(voteWord)"
        subtitleLabel.font = .systemFont(ofSize: 14)
        subtitleLabel.textColor = t.textStrong
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            subtitleLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            subtitleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
        ])
    }

    private func setupBody() {
        let t = UIColor.theme

        bodyView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bodyView)

        let topBorder = UIView()
        topBorder.backgroundColor = UIColor.mezonBorder
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(topBorder)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            topBorder.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            bodyView.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            bodyView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bodyView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])

        let visibleCount = min(options.count, Self.maxVisibleOptions)
        let optionsHeight = CGFloat(visibleCount) * Self.optionRowHeight
            + CGFloat(max(visibleCount - 1, 0)) * Self.optionGap + 24
        let minHeight: CGFloat = max(200, optionsHeight)
        bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: minHeight).isActive = true

        leftScrollView.translatesAutoresizingMaskIntoConstraints = false
        leftScrollView.showsVerticalScrollIndicator = options.count > Self.maxVisibleOptions
        bodyView.addSubview(leftScrollView)

        leftStackView.axis = .vertical
        leftStackView.spacing = Self.optionGap
        leftStackView.translatesAutoresizingMaskIntoConstraints = false
        leftScrollView.addSubview(leftStackView)

        dividerView.backgroundColor = UIColor.mezonBorder
        dividerView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(dividerView)

        rightScrollView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.showsVerticalScrollIndicator = true
        bodyView.addSubview(rightScrollView)

        rightStackView.axis = .vertical
        rightStackView.spacing = 6
        rightStackView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.addSubview(rightStackView)

        NSLayoutConstraint.activate([
            leftScrollView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            leftScrollView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            leftScrollView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
            leftScrollView.widthAnchor.constraint(equalTo: bodyView.widthAnchor, multiplier: 0.42),

            leftStackView.topAnchor.constraint(equalTo: leftScrollView.topAnchor, constant: 12),
            leftStackView.leadingAnchor.constraint(equalTo: leftScrollView.leadingAnchor, constant: 12),
            leftStackView.trailingAnchor.constraint(equalTo: leftScrollView.trailingAnchor, constant: -12),
            leftStackView.bottomAnchor.constraint(lessThanOrEqualTo: leftScrollView.bottomAnchor, constant: -12),
            leftStackView.widthAnchor.constraint(equalTo: leftScrollView.widthAnchor, constant: -24),

            dividerView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: leftScrollView.trailingAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            rightScrollView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            rightScrollView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            rightScrollView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),

            rightStackView.topAnchor.constraint(equalTo: rightScrollView.topAnchor, constant: 12),
            rightStackView.leadingAnchor.constraint(equalTo: rightScrollView.leadingAnchor, constant: 12),
            rightStackView.trailingAnchor.constraint(equalTo: rightScrollView.trailingAnchor, constant: -12),
            rightStackView.bottomAnchor.constraint(lessThanOrEqualTo: rightScrollView.bottomAnchor, constant: -12),
            rightStackView.widthAnchor.constraint(equalTo: rightScrollView.widthAnchor, constant: -24),
        ])

        for option in options {
            let optionView = createOptionItemView(option: option, isActive: option.index == selectedIndex)
            leftStackView.addArrangedSubview(optionView)
        }

        loadingIndicator.color = t.textStrong
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.addSubview(loadingIndicator)
        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: rightScrollView.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: rightScrollView.centerYAnchor),
        ])
        if isLoading { loadingIndicator.startAnimating() }

        emptyLabel.text = L(L10n.Poll.noVotesYet)
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = t.textDisabled
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        rightScrollView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: rightScrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: rightScrollView.centerYAnchor),
        ])
    }

    private func createOptionItemView(option: PollOptionDisplay, isActive: Bool) -> UIView {
        let t = UIColor.theme
        let container = UIView()
        container.layer.cornerRadius = 8
        container.backgroundColor = isActive ? Self.blurpleAlpha : .clear
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = option.label
        label.font = .systemFont(ofSize: 14)
        label.textColor = t.textStrong
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        let countLabel = UILabel()
        countLabel.text = "\(option.voteCount)"
        countLabel.font = .systemFont(ofSize: 14)
        countLabel.textColor = t.textDisabled
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        container.addSubview(countLabel)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: Self.optionRowHeight),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.7),

            countLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8)
        ])

        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.lineBreakMode = .byTruncatingTail

        let tap = OptionTapGesture(target: self, action: #selector(handleOptionSelect(_:)))
        tap.optionIndex = option.index
        container.addGestureRecognizer(tap)

        return container
    }

    @objc private func handleOptionSelect(_ gesture: OptionTapGesture) {
        selectedIndex = gesture.optionIndex
        for (i, view) in leftStackView.arrangedSubviews.enumerated() {
            if i < options.count {
                view.backgroundColor = options[i].index == selectedIndex ? Self.blurpleAlpha : .clear
            }
        }
        updateRightColumn()
    }

    private func updateRightColumn() {
        rightStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let voters = votersByOption[selectedIndex] ?? []

        loadingIndicator.stopAnimating()

        if voters.isEmpty {
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
            let t = UIColor.theme

            for voter in voters {
                let voterView = UIView()
                voterView.translatesAutoresizingMaskIntoConstraints = false

                let avatarContainer = UIView()
                avatarContainer.layer.cornerRadius = Self.avatarSize / 2
                avatarContainer.clipsToBounds = true
                avatarContainer.backgroundColor = .colorAvatarDefault
                avatarContainer.translatesAutoresizingMaskIntoConstraints = false

                let avatarImageView = UIImageView()
                avatarImageView.contentMode = .scaleAspectFill
                avatarImageView.translatesAutoresizingMaskIntoConstraints = false
                avatarContainer.addSubview(avatarImageView)

                let placeholderLabel = UILabel()
                placeholderLabel.text = String(voter.displayName.prefix(1)).uppercased()
                placeholderLabel.font = .systemFont(ofSize: 12, weight: .semibold)
                placeholderLabel.textColor = .white
                placeholderLabel.textAlignment = .center
                placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
                avatarContainer.addSubview(placeholderLabel)

                if !voter.avatar.isEmpty, let url = URL(string: voter.avatar) {
                    placeholderLabel.isHidden = true
                    let proxyURL = ImgproxyURL.create(from: voter.avatar, width: 64, height: 64)
                    if let cachedImage = ImageCache.shared.memoryImage(forKey: proxyURL)
                        ?? ImageCache.shared.memoryImage(forKey: voter.avatar) {
                        avatarImageView.image = cachedImage
                    } else {
                        avatarImageView.image = nil
                        Task {
                            if let data = try? await URLSession.shared.data(from: URL(string: proxyURL) ?? url).0,
                               let image = UIImage(data: data) {
                                await MainActor.run {
                                    avatarImageView.image = image
                                }
                            }
                        }
                    }
                } else {
                    avatarImageView.image = nil
                    placeholderLabel.isHidden = false
                }

                let nameLabel = UILabel()
                nameLabel.text = voter.displayName
                nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
                nameLabel.textColor = t.textStrong
                nameLabel.numberOfLines = 1
                nameLabel.translatesAutoresizingMaskIntoConstraints = false

                let usernameLabel = UILabel()
                usernameLabel.text = voter.username
                usernameLabel.font = .systemFont(ofSize: 12)
                usernameLabel.textColor = t.textDisabled
                usernameLabel.numberOfLines = 1
                usernameLabel.translatesAutoresizingMaskIntoConstraints = false

                let infoStack = UIStackView(arrangedSubviews: [nameLabel, usernameLabel])
                infoStack.axis = .vertical
                infoStack.spacing = 0
                infoStack.translatesAutoresizingMaskIntoConstraints = false

                voterView.addSubview(avatarContainer)
                voterView.addSubview(infoStack)

                NSLayoutConstraint.activate([
                    voterView.heightAnchor.constraint(equalToConstant: 44),
                    avatarContainer.leadingAnchor.constraint(equalTo: voterView.leadingAnchor),
                    avatarContainer.centerYAnchor.constraint(equalTo: voterView.centerYAnchor),
                    avatarContainer.widthAnchor.constraint(equalToConstant: Self.avatarSize),
                    avatarContainer.heightAnchor.constraint(equalToConstant: Self.avatarSize),
                    avatarImageView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
                    avatarImageView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
                    avatarImageView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
                    avatarImageView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
                    placeholderLabel.centerXAnchor.constraint(equalTo: avatarContainer.centerXAnchor),
                    placeholderLabel.centerYAnchor.constraint(equalTo: avatarContainer.centerYAnchor),
                    infoStack.leadingAnchor.constraint(equalTo: avatarContainer.trailingAnchor, constant: 10),
                    infoStack.centerYAnchor.constraint(equalTo: voterView.centerYAnchor),
                    infoStack.trailingAnchor.constraint(equalTo: voterView.trailingAnchor),
                ])

                rightStackView.addArrangedSubview(voterView)
            }
        }
    }

    @objc private func dismissModal() {
        UIView.animate(withDuration: 0.15, animations: {
            self.view.alpha = 0
        }) { _ in
            self.dismiss(animated: false)
        }
    }
}

private class OptionTapGesture: UITapGestureRecognizer {
    var optionIndex: Int = 0
}
