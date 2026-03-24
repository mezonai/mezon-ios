import AsyncDisplayKit
import UIKit

final class WelcomeController: ViewController {
    private let context: AccountContext
    private var welcomeNode: WelcomeContainerNode { displayNode as! WelcomeContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        displayNode = WelcomeContainerNode(
            onStartTapped: { [weak self] in
                guard let self = self else { return }
                let loginVC = LoginViewController(context: self.context)
                self.navigationController?.pushViewController(loginVC, animated: true)
            }
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleLanguageChange),
            name: LanguageManager.didChangeNotification, object: nil)
    }

    override func containerLayoutUpdated(
        _ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition
    ) {
        super.containerLayoutUpdated(layout, transition: transition)
        welcomeNode.updateLayout(layout: layout, transition: transition)
    }

    @objc private func handleLanguageChange() {
        welcomeNode.refreshLocalizedStrings()
    }
}

final class WelcomeContainerNode: ASDisplayNode {
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let imageNode = ASImageNode()
    private let startButton = ASButtonNode()
    private let gradientLayer = CAGradientLayer()
    // Separate background node so button text is never obscured by the gradient
    private let buttonBgNode = ASDisplayNode { CAGradientLayer() }

    private let onStartTapped: () -> Void

    init(onStartTapped: @escaping () -> Void) {
        self.onStartTapped = onStartTapped
        super.init()

        imageNode.image = UIImage(named: "Auth/welcomeMezon")?.withRenderingMode(.alwaysOriginal)
        imageNode.contentMode = .scaleAspectFit

        startButton.backgroundColor = .clear
        startButton.cornerRadius = 12
        startButton.clipsToBounds = true
        startButton.addTarget(
            self, action: #selector(startTapped), forControlEvents: .touchUpInside)

        refreshLocalizedStrings()
    }

    override func didLoad() {
        super.didLoad()

        // Insert gradient behind everything
        gradientLayer.locations = [0, 0.5, 1]
        let attrs = ThemeManager.shared.attributes
        gradientLayer.colors = attrs.loginGradientColors.map { $0.cgColor }
        gradientLayer.frame = bounds
        view.layer.insertSublayer(gradientLayer, at: 0)

        // Setup button background gradient (behind the button node, text stays visible)
        if let gl = buttonBgNode.layer as? CAGradientLayer {
            gl.startPoint = CGPoint(x: 0, y: 0.5)
            gl.endPoint = CGPoint(x: 1, y: 0.5)
            gl.colors = [
                UIColor(hex: 0x501794).cgColor,
                UIColor(hex: 0x3E70A1).cgColor,
            ]
            gl.cornerRadius = 12
        }

        // Add subnodes manually so they render above the gradient
        addSubnode(buttonBgNode)
        addSubnode(titleNode)
        addSubnode(subtitleNode)
        addSubnode(imageNode)
        addSubnode(startButton)
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: self, frame: CGRect(origin: .zero, size: layout.size))
        layoutContent(size: layout.size, insets: layout.insets(options: []))
    }

    private func layoutContent(size: CGSize, insets: UIEdgeInsets) {
        let width = size.width
        let height = size.height
        let hPad: CGFloat = 24
        gradientLayer.frame = CGRect(origin: .zero, size: size)

        // Title
        let titleSize = titleNode.measure(
            CGSize(width: width - hPad * 2, height: .greatestFiniteMagnitude))
        let titleY: CGFloat = 160
        titleNode.frame = CGRect(
            x: hPad, y: titleY, width: width - hPad * 2, height: titleSize.height)

        // Subtitle
        let subtitleSize = subtitleNode.measure(
            CGSize(width: width - hPad * 2 - 30, height: .greatestFiniteMagnitude))
        let subtitleY = titleY + titleSize.height + 10
        subtitleNode.frame = CGRect(
            x: hPad, y: subtitleY, width: width - hPad * 2, height: subtitleSize.height)

        // Button
        let buttonH: CGFloat = 50
        let buttonY = height - 90 - buttonH
        let buttonWidth = width - hPad * 2
        let buttonFrame = CGRect(x: hPad, y: buttonY, width: buttonWidth, height: buttonH)
        buttonBgNode.frame = buttonFrame
        startButton.frame = buttonFrame

        // Image
        let availableTop = subtitleY + subtitleSize.height - 80
        let availableBottom = buttonY - 20
        let imageSize: CGFloat = min(width - 40, availableBottom - availableTop)
        let imageMidY = availableTop + (availableBottom - availableTop) / 2
        imageNode.frame = CGRect(
            x: (width - imageSize) / 2, y: imageMidY - imageSize / 2,
            width: imageSize, height: imageSize
        )
    }

    func refreshLocalizedStrings() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.Welcome.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.loginTitleColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        subtitleNode.attributedText = NSAttributedString(
            string: L(L10n.Welcome.subtitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.loginSubtitleColor,
                .paragraphStyle: paragraphStyle,
            ]
        )

        startButton.setAttributedTitle(
            NSAttributedString(
                string: L(L10n.Welcome.startNow),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
            ),
            for: .normal
        )
    }

    @objc private func startTapped() {
        onStartTapped()
    }
}

extension UIColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
