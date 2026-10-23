import UIKit
import AsyncDisplayKit

private enum AvatarSkeletonPalette {
    static let shimmerKey = "avatar.skeleton.shimmer"
    static let duration: CFTimeInterval = 1.2

    static func currentColors() -> (base: CGColor, highlight: CGColor) {
        let theme = UIColor.theme
        let base = theme.secondaryWeight
        let highlight = theme.tertiary
        return (base.cgColor, highlight.cgColor)
    }

    static func currentBaseUIColor() -> UIColor {
        UIColor.theme.secondaryWeight
    }
}

enum DefaultUserAvatar {
    private static let cache = NSCache<NSNumber, UIImage>()
    private static let discColor = UIColor(red: 96 / 255, green: 96 / 255, blue: 101 / 255, alpha: 1)
    private static let bodyColor = UIColor(red: 140 / 255, green: 140 / 255, blue: 144 / 255, alpha: 1)
    private static let bodyTop: CGFloat = 0.734
    private static let headCenterY: CGFloat = 0.498
    private static let headRadius: CGFloat = 0.235

    static func image(side: CGFloat) -> UIImage {
        let side = max(1, side.rounded(.up))
        let key = NSNumber(value: Double(side))
        if let cached = cache.object(forKey: key) { return cached }
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { context in
            discColor.setFill()
            context.fill(bounds)
            bodyColor.setFill()
            context.fill(CGRect(x: 0, y: side * bodyTop, width: side, height: side * (1 - bodyTop)))
            let radius = side * headRadius
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(
                x: side / 2 - radius,
                y: side * headCenterY - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

final class TextAvatarView: UIView {

    private var label: UILabel?
    private var initialsName: String?
    private var currentSize: CGFloat
    private var skeletonGradient: CAGradientLayer?

    init(size: CGFloat) {
        self.currentSize = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        layer.cornerRadius = size / 2
        clipsToBounds = true
        backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
    }

    convenience init(username: String, size: CGFloat, fontSize: CGFloat? = nil) {
        self.init(size: size)
        configure(username: username, fontSize: fontSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        skeletonGradient?.frame = bounds
    }

    func configure(username: String, fontSize: CGFloat? = nil) {
        stopSkeletonShimmer()
        layer.contents = nil
        initialsName = username
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? ""
        let resolvedFontSize = fontSize ?? (currentSize * 0.4)

        backgroundColor = UIColor.avatarColor(for: username)
        let label = initialsLabel()
        label.text = initial
        label.font = .systemFont(ofSize: resolvedFontSize, weight: .semibold)
        label.isHidden = false
    }

    func showImageMode() {
        stopSkeletonShimmer()
        layer.contents = nil
        backgroundColor = .clear
        label?.isHidden = true
    }

    func showPlaceholder() {
        stopSkeletonShimmer()
        if let initialsName {
            backgroundColor = UIColor.avatarColor(for: initialsName)
            label?.isHidden = false
        } else {
            backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
            layer.contents = DefaultUserAvatar.image(side: currentSize).cgImage
        }
    }

    func showSkeleton() {
        layer.contents = nil
        label?.isHidden = true
        startSkeletonShimmer()
    }

    private func initialsLabel() -> UILabel {
        if let existing = label { return existing }
        let created = UILabel()
        created.textAlignment = .center
        created.textColor = .white
        created.translatesAutoresizingMaskIntoConstraints = false
        addSubview(created)
        NSLayoutConstraint.activate([
            created.centerXAnchor.constraint(equalTo: centerXAnchor),
            created.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        label = created
        return created
    }

    private func startSkeletonShimmer() {
        let colors = AvatarSkeletonPalette.currentColors()
        backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
        let gradient = skeletonGradient ?? CAGradientLayer()
        gradient.frame = bounds
        gradient.colors = [colors.base, colors.highlight, colors.base]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1]
        if skeletonGradient == nil {
            layer.addSublayer(gradient)
            skeletonGradient = gradient
        }
        gradient.removeAnimation(forKey: AvatarSkeletonPalette.shimmerKey)
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue = [1.0, 1.5, 2.0]
        anim.duration = AvatarSkeletonPalette.duration
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: AvatarSkeletonPalette.shimmerKey)
    }

    private func stopSkeletonShimmer() {
        skeletonGradient?.removeAnimation(forKey: AvatarSkeletonPalette.shimmerKey)
        skeletonGradient?.removeFromSuperlayer()
        skeletonGradient = nil
    }
}

final class TextAvatarNode: ASDisplayNode {

    private var textNode: ASTextNode2?
    private var defaultUserNode: ASImageNode?
    private var initialsName: String?
    let avatarSize: CGFloat
    private var skeletonGradient: CAGradientLayer?

    init(size: CGFloat) {
        self.avatarSize = size
        super.init()
        automaticallyManagesSubnodes = true

        style.preferredSize = CGSize(width: size, height: size)
        cornerRadius = size / 2
        clipsToBounds = true
        backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
    }

    convenience init(username: String, size: CGFloat, fontSize: CGFloat? = nil) {
        self.init(size: size)
        configure(username: username, fontSize: fontSize)
    }

    func configure(username: String, fontSize: CGFloat? = nil) {
        stopSkeletonShimmer()
        initialsName = username
        if defaultUserNode != nil {
            defaultUserNode = nil
            setNeedsLayout()
        }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? ""
        let resolvedFontSize = fontSize ?? (avatarSize * 0.4)

        backgroundColor = UIColor.avatarColor(for: username)

        let para = NSMutableParagraphStyle()
        para.alignment = .center

        let textNode = initialsTextNode()
        textNode.attributedText = NSAttributedString(
            string: initial,
            attributes: [
                .font: UIFont.systemFont(ofSize: resolvedFontSize, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ]
        )
        textNode.isHidden = false
    }

    func showImageMode() {
        stopSkeletonShimmer()
        backgroundColor = .clear
        textNode?.isHidden = true
        defaultUserNode?.isHidden = true
    }

    func showPlaceholder() {
        stopSkeletonShimmer()
        if let initialsName {
            backgroundColor = UIColor.avatarColor(for: initialsName)
            textNode?.isHidden = false
        } else {
            backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
            defaultUserImageNode().isHidden = false
        }
    }

    func showSkeleton() {
        textNode?.isHidden = true
        defaultUserNode?.isHidden = true
        if Thread.isMainThread {
            startSkeletonShimmer()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startSkeletonShimmer()
            }
        }
    }

    private func initialsTextNode() -> ASTextNode2 {
        if let existing = textNode { return existing }
        let created = ASTextNode2()
        created.maximumNumberOfLines = 1
        textNode = created
        setNeedsLayout()
        return created
    }

    private func defaultUserImageNode() -> ASImageNode {
        if let existing = defaultUserNode { return existing }
        let created = ASImageNode()
        created.isLayerBacked = true
        created.displaysAsynchronously = false
        created.image = DefaultUserAvatar.image(side: avatarSize)
        created.style.preferredSize = CGSize(width: avatarSize, height: avatarSize)
        defaultUserNode = created
        setNeedsLayout()
        return created
    }

    private func startSkeletonShimmer() {
        let colors = AvatarSkeletonPalette.currentColors()
        backgroundColor = AvatarSkeletonPalette.currentBaseUIColor()
        let gradient = skeletonGradient ?? CAGradientLayer()
        gradient.frame = layer.bounds
        gradient.colors = [colors.base, colors.highlight, colors.base]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.locations = [0, 0.5, 1]
        if skeletonGradient == nil {
            layer.addSublayer(gradient)
            skeletonGradient = gradient
        }
        gradient.removeAnimation(forKey: AvatarSkeletonPalette.shimmerKey)
        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = [-1.0, -0.5, 0.0]
        anim.toValue = [1.0, 1.5, 2.0]
        anim.duration = AvatarSkeletonPalette.duration
        anim.repeatCount = .infinity
        gradient.add(anim, forKey: AvatarSkeletonPalette.shimmerKey)
    }

    private func stopSkeletonShimmer() {
        if Thread.isMainThread {
            skeletonGradient?.removeAnimation(forKey: AvatarSkeletonPalette.shimmerKey)
            skeletonGradient?.removeFromSuperlayer()
            skeletonGradient = nil
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.skeletonGradient?.removeAnimation(forKey: AvatarSkeletonPalette.shimmerKey)
                self?.skeletonGradient?.removeFromSuperlayer()
                self?.skeletonGradient = nil
            }
        }
    }

    override func layout() {
        super.layout()
        skeletonGradient?.frame = layer.bounds
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        if let defaultUserNode {
            return ASWrapperLayoutSpec(layoutElement: defaultUserNode)
        }
        guard let textNode else { return ASLayoutSpec() }
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: textNode)
    }
}
