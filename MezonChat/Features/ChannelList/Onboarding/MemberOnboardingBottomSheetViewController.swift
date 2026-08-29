import UIKit

struct MemberOnboardingMissionRow {
    let title: String
    let subtitle: String
    let isCompleted: Bool
    let isActionable: Bool
    let onPress: () -> Void
}

final class MemberOnboardingBottomSheetViewController: UIViewController {

    @available(iOS 15.0, *)
    private static let seventyPercentDetentId = UISheetPresentationController.Detent.Identifier("mezon.memberOnboarding.seventyPercent")

    private static let missionIconName = "ClanSetting/InstallAppIcon"
    private static let missionIconBackground = UIColor(red: 0.93, green: 0.28, blue: 0.60, alpha: 1)

    private let finishedStep: Int
    private let totalSteps: Int
    private let missions: [MemberOnboardingMissionRow]

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let headerGradientView = UIView()
    private var headerGradientLayer: CAGradientLayer?

    init(finishedStep: Int, totalSteps: Int, missions: [MemberOnboardingMissionRow]) {
        self.finishedStep = finishedStep
        self.totalSteps = totalSteps
        self.missions = missions
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSheet()
        buildContent()
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        headerGradientLayer?.frame = headerGradientView.bounds
    }

    private func configureSheet() {
        if #available(iOS 15.0, *) {
            guard let sheet = sheetPresentationController else { return }
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
            if #available(iOS 16.0, *) {
                let seventyDetent = UISheetPresentationController.Detent.custom(
                    identifier: Self.seventyPercentDetentId
                ) { context in
                    context.maximumDetentValue * 0.7
                }
                sheet.detents = [seventyDetent, .large()]
                sheet.selectedDetentIdentifier = Self.seventyPercentDetentId
            } else {
                sheet.detents = [.medium(), .large()]
                sheet.selectedDetentIdentifier = .medium
            }
        }
    }

    private func buildContent() {
        view.backgroundColor = UIColor.theme.primary

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])

        contentStack.addArrangedSubview(makeHeaderSection())
        for mission in missions {
            contentStack.addArrangedSubview(makeMissionRow(mission))
        }
    }

    private func makeHeaderSection() -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        headerGradientView.translatesAutoresizingMaskIntoConstraints = false
        headerGradientView.layer.cornerRadius = 16.swh
        headerGradientView.clipsToBounds = true
        wrapper.addSubview(headerGradientView)

        let gradient = CAGradientLayer()
        gradient.startPoint = CGPoint(x: 1, y: 0.5)
        gradient.endPoint = CGPoint(x: 0, y: 0.5)
        headerGradientView.layer.insertSublayer(gradient, at: 0)
        headerGradientLayer = gradient

        let heroContainer = UIView()
        heroContainer.translatesAutoresizingMaskIntoConstraints = false
        headerGradientView.addSubview(heroContainer)

        let outerRing = makeCircleView(size: 100.swh, color: UIColor.theme.primary.withAlphaComponent(0.9))
        let midRing = makeCircleView(size: 86.swh, color: UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 0.2))
        let innerCircle = makeCircleView(size: 50.swh, color: UIColor(red: 0.20, green: 0.55, blue: 0.98, alpha: 1))
        let heroIcon = UIImageView(
            image: UIImage(named: "ClanSetting/OnboardingIcon")?.withRenderingMode(.alwaysOriginal)
        )
        heroIcon.translatesAutoresizingMaskIntoConstraints = false
        heroIcon.contentMode = .scaleAspectFit

        heroContainer.addSubview(outerRing)
        heroContainer.addSubview(midRing)
        heroContainer.addSubview(innerCircle)
        heroContainer.addSubview(heroIcon)

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.OnboardingMember.actionTitle)
        titleLabel.font = .systemFont(ofSize: 24.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let descLabel = UILabel()
        descLabel.text = L(
            L10n.OnboardingMember.actionDescription,
            finishedStep,
            totalSteps
        )
        descLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        descLabel.textColor = UIColor.theme.textDisabled
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        headerGradientView.addSubview(titleLabel)
        headerGradientView.addSubview(descLabel)

        NSLayoutConstraint.activate([
            headerGradientView.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 8.sh),
            headerGradientView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            headerGradientView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            headerGradientView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),

            heroContainer.topAnchor.constraint(equalTo: headerGradientView.topAnchor, constant: 24.sh),
            heroContainer.centerXAnchor.constraint(equalTo: headerGradientView.centerXAnchor),
            heroContainer.widthAnchor.constraint(equalToConstant: 100.swh),
            heroContainer.heightAnchor.constraint(equalToConstant: 100.swh),

            outerRing.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            outerRing.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            midRing.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            midRing.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            innerCircle.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            innerCircle.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            heroIcon.centerXAnchor.constraint(equalTo: heroContainer.centerXAnchor),
            heroIcon.centerYAnchor.constraint(equalTo: heroContainer.centerYAnchor),
            heroIcon.widthAnchor.constraint(equalToConstant: 32.swh),
            heroIcon.heightAnchor.constraint(equalToConstant: 32.swh),

            titleLabel.topAnchor.constraint(equalTo: heroContainer.bottomAnchor, constant: 20.sh),
            titleLabel.leadingAnchor.constraint(equalTo: headerGradientView.leadingAnchor, constant: 24.sw),
            titleLabel.trailingAnchor.constraint(equalTo: headerGradientView.trailingAnchor, constant: -24.sw),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            descLabel.leadingAnchor.constraint(equalTo: headerGradientView.leadingAnchor, constant: 24.sw),
            descLabel.trailingAnchor.constraint(equalTo: headerGradientView.trailingAnchor, constant: -24.sw),
            descLabel.bottomAnchor.constraint(equalTo: headerGradientView.bottomAnchor, constant: -24.sh),
        ])

        return wrapper
    }

    private func makeMissionRow(_ mission: MemberOnboardingMissionRow) -> UIView {
        let row = MemberOnboardingActionControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = UIColor.theme.secondary
        row.layer.cornerRadius = 20.swh
        row.layer.borderWidth = 1
        row.layer.borderColor = UIColor.theme.border.cgColor
        row.isUserInteractionEnabled = mission.isActionable
        row.alpha = mission.isActionable ? 1 : 0.55
        row.onPress = { [weak self] in
            guard mission.isActionable else { return }
            self?.dismiss(animated: true) {
                mission.onPress()
            }
        }

        let iconWrap = UIView()
        iconWrap.backgroundColor = Self.missionIconBackground
        iconWrap.layer.cornerRadius = 14.swh
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.isUserInteractionEnabled = false

        let iconView = UIImageView(
            image: UIImage(named: Self.missionIconName)?.withRenderingMode(.alwaysOriginal)
        )
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconWrap.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = mission.title
        titleLabel.font = .systemFont(ofSize: 15.sf, weight: .medium)
        titleLabel.textColor = UIColor.theme.textStrong
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false

        let subtitleLabel = UILabel()
        subtitleLabel.text = mission.subtitle
        subtitleLabel.font = .systemFont(ofSize: 11.sf, weight: .regular)
        subtitleLabel.textColor = UIColor.theme.text
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.isUserInteractionEnabled = false
        subtitleLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.isUserInteractionEnabled = false

        let trailingAccessory = Self.makeTrailingAccessory(
            isCompleted: mission.isCompleted,
            showsArrow: mission.isActionable && !mission.isCompleted
        )

        row.addSubview(iconWrap)
        row.addSubview(textStack)
        row.addSubview(trailingAccessory)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 60.sh),

            iconWrap.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16.sw),
            iconWrap.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconWrap.widthAnchor.constraint(equalToConstant: 28.swh),
            iconWrap.heightAnchor.constraint(equalToConstant: 28.swh),

            iconView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18.swh),
            iconView.heightAnchor.constraint(equalToConstant: 18.swh),

            textStack.leadingAnchor.constraint(equalTo: iconWrap.trailingAnchor, constant: 8.sw),
            textStack.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAccessory.leadingAnchor, constant: -8.sw),
            textStack.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 10.sh),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor, constant: -10.sh),

            trailingAccessory.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16.sw),
            trailingAccessory.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 8.sh),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8.sh),
        ])
        return container
    }

    private static func makeTrailingAccessory(isCompleted: Bool, showsArrow: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isUserInteractionEnabled = false

        let size: CGFloat = 24.swh
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
        ])

        if isCompleted {
            container.backgroundColor = UIColor(red: 0.18, green: 0.75, blue: 0.45, alpha: 1)
            container.layer.cornerRadius = size / 2

            let tickView = UIImageView()
            tickView.translatesAutoresizingMaskIntoConstraints = false
            tickView.contentMode = .scaleAspectFit
            tickView.isUserInteractionEnabled = false
            tickView.image = UIImage.mezonSystemImage(
                "checkmark",
                withConfiguration: MezonSymbolConfiguration(pointSize: 14.sf, weight: .bold)
            )?.mezonTinted(.white, renderingMode: .alwaysOriginal)
            container.addSubview(tickView)
            NSLayoutConstraint.activate([
                tickView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                tickView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                tickView.widthAnchor.constraint(equalToConstant: 14.swh),
                tickView.heightAnchor.constraint(equalToConstant: 14.swh),
            ])
        } else if showsArrow {
            let arrowView = UIImageView()
            arrowView.translatesAutoresizingMaskIntoConstraints = false
            arrowView.contentMode = .scaleAspectFit
            arrowView.isUserInteractionEnabled = false
            arrowView.image = UIImage.mezonSystemImage(
                "chevron.right",
                withConfiguration: MezonSymbolConfiguration(pointSize: 22.sf, weight: .semibold)
            )?.mezonTinted(UIColor.theme.text, renderingMode: .alwaysOriginal)
            container.addSubview(arrowView)
            NSLayoutConstraint.activate([
                arrowView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                arrowView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                arrowView.widthAnchor.constraint(equalToConstant: size),
                arrowView.heightAnchor.constraint(equalToConstant: size),
            ])
        }

        return container
    }

    private func makeCircleView(size: CGFloat, color: UIColor) -> UIView {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = color
        view.layer.cornerRadius = size / 2
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size),
        ])
        return view
    }

    private func applyTheme() {
        view.backgroundColor = UIColor.theme.primary
        let theme = UIColor.theme
        headerGradientLayer?.colors = [
            theme.primary.cgColor,
            theme.primaryGradient.cgColor,
            theme.primaryGradient.cgColor,
        ]
    }

    @objc private func themeDidChange() {
        applyTheme()
    }
}

private final class MemberOnboardingActionControl: UIControl {
    var onPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(handlePress), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handlePress() {
        onPress?()
    }
}
