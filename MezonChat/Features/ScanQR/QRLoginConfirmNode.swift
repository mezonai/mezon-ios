import AsyncDisplayKit
import UIKit

final class QRLoginConfirmNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let iconNode = ASDisplayNode()
    private let logoNode = ASImageNode()
    private let titleNode = ASTextNode()
    private let subtitleNode = ASTextNode()
    private let loginButton = ASButtonNode()
    private let cancelButton = ASButtonNode()
    private let backgroundGradientLayer = CAGradientLayer()
    private let buttonBgNode = ASDisplayNode { CAGradientLayer() }

    var onLogin: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStartTalking: (() -> Void)?

    private let theme: ThemeAttributes
    private var isSuccess: Bool = false

    init(theme: ThemeAttributes) {
        self.theme = theme
        super.init()
        setupNodes()
    }

    private func setupNodes() {
        containerNode.backgroundColor = theme.secondary
        containerNode.cornerRadius = 20
        containerNode.clipsToBounds = true

        iconNode.backgroundColor = .clear
        iconNode.style.preferredSize = CGSize(width: 100, height: 100)

        logoNode.image = UIImage(named: "Setting/LogoMezon")?.withRenderingMode(.alwaysOriginal)
        logoNode.style.preferredSize = CGSize(width: 80, height: 80)
        logoNode.contentMode = .scaleAspectFit
        iconNode.addSubnode(logoNode)

        titleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.logInOnNewDevice),
            attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: theme.white,
                .paragraphStyle: centeredParagraphStyle(),
            ])

        subtitleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.neverScanLoginQR),
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: hex("#EF4444"),
                .paragraphStyle: centeredParagraphStyle(),
            ])

        startButtonNodes()
        
        cancelButton.setTitle(
            L(L10n.Common.cancel), with: .systemFont(ofSize: 16, weight: .medium),
            with: theme.white, for: .normal)
        cancelButton.addTarget(
            self, action: #selector(cancelTapped), forControlEvents: .touchUpInside)

        self.addSubnode(containerNode)
        containerNode.addSubnode(iconNode)
        containerNode.addSubnode(logoNode)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(subtitleNode)
        containerNode.addSubnode(buttonBgNode)
        containerNode.addSubnode(loginButton)
        containerNode.addSubnode(cancelButton)
    }

    private func startButtonNodes() {
        loginButton.backgroundColor = .clear
        loginButton.setTitle(
            L(L10n.Login.logIn), with: .systemFont(ofSize: 16, weight: .bold),
            with: .white, for: .normal)
        loginButton.cornerRadius = 8
        loginButton.style.height = ASDimensionMake(48)
        loginButton.addTarget(
            self, action: #selector(loginTapped), forControlEvents: .touchUpInside)
        
        buttonBgNode.style.height = ASDimensionMake(48)
    }

    override func didLoad() {
        super.didLoad()
        setupBackgroundGradient()
        setupGradientIcon()
        setupButtonGradient()
    }

    private func setupBackgroundGradient() {
        backgroundGradientLayer.locations = [0, 0.5, 1]
        backgroundGradientLayer.colors = theme.loginGradientColors.map { $0.cgColor }
        // Frame will be handled in layout()
        layer.insertSublayer(backgroundGradientLayer, at: 0)
    }

    override func layout() {
        super.layout()
        backgroundGradientLayer.frame = bounds
        if let gl = buttonBgNode.layer as? CAGradientLayer {
            gl.frame = buttonBgNode.bounds
        }
    }

    private func setupButtonGradient() {
        if let gl = buttonBgNode.layer as? CAGradientLayer {
            gl.startPoint = CGPoint(x: 0, y: 0.5)
            gl.endPoint = CGPoint(x: 1, y: 0.5)
            gl.colors = [
                hex("#501794").cgColor,
                hex("#3E70A1").cgColor,
            ]
            gl.cornerRadius = 12
        }
    }

    func setSuccess(_ success: Bool) {
        self.isSuccess = success
        titleNode.attributedText = NSAttributedString(
            string: success ? L(L10n.QRScanner.youAreIn) : L(L10n.QRScanner.loginConfirm),
            attributes: [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: theme.white,
                .paragraphStyle: centeredParagraphStyle(),
            ])

        subtitleNode.attributedText = NSAttributedString(
            string: success
                ? L(L10n.QRScanner.youAreLoggedInDesktop) : L(L10n.QRScanner.neverScanLoginQR),
            attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: success ? theme.textNormal : hex("#EF4444"),
                .paragraphStyle: centeredParagraphStyle(),
            ])

        loginButton.setTitle(
            success ? L(L10n.QRScanner.startTalking) : L(L10n.Login.logIn),
            with: .systemFont(ofSize: 16, weight: .bold), with: theme.white, for: .normal)
        cancelButton.isHidden = success

        self.setNeedsLayout()
    }

    private func setupGradientIcon() {
        let gradient = CAGradientLayer()
        gradient.frame = iconNode.bounds
        gradient.colors = [theme.bgViolet.cgColor, hex("#EC4899").cgColor]  // Purple to Pink
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)

        let shape = CAShapeLayer()
        shape.path = UIBezierPath(ovalIn: iconNode.bounds.insetBy(dx: 5, dy: 5)).cgPath
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = UIColor.black.cgColor
        shape.lineWidth = 4

        gradient.mask = shape
        iconNode.layer.addSublayer(gradient)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let logoCenter = ASCenterLayoutSpec(centeringOptions: .XY, child: logoNode)
        let iconWithLogo = ASOverlayLayoutSpec(child: iconNode, overlay: logoCenter)
        iconWithLogo.style.alignSelf = .center

        titleNode.style.alignSelf = .center
        subtitleNode.style.alignSelf = .center

        let loginButtonWithBg = ASOverlayLayoutSpec(child: buttonBgNode, overlay: loginButton)

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 24,
            justifyContent: .center,
            alignItems: .stretch,
            children: [iconWithLogo, titleNode, subtitleNode, loginButtonWithBg, cancelButton]
        )

        let containerInsetEnabled = ASInsetLayoutSpec(
            insets: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24), child: contentStack)

        loginButton.style.width = ASDimensionMakeWithFraction(1.0)
        buttonBgNode.style.width = ASDimensionMakeWithFraction(1.0)
        cancelButton.style.alignSelf = .center
        containerNode.style.minWidth = ASDimensionMakeWithPoints(300)
        containerNode.style.maxWidth = ASDimensionMakeWithPoints(constrainedSize.max.width - 40)

        _ = ASWrapperLayoutSpec(layoutElement: containerInsetEnabled)
        containerNode.layoutSpecBlock = { _, _ in return containerInsetEnabled }

        return ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: .minimumXY, child: containerNode)
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    @objc private func loginTapped() {
        if isSuccess {
            onStartTalking?()
        } else {
            onLogin?()
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }
}

private func hex(_ value: String, alpha: CGFloat = 1) -> UIColor {
    var str = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("#") { str = String(str.dropFirst()) }
    let scanner = Scanner(string: str)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return UIColor(
        red: CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >> 8) & 0xFF) / 255,
        blue: CGFloat(rgb & 0xFF) / 255,
        alpha: alpha
    )
}

