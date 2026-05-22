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

final class TextAvatarView: UIView {

    private let label = UILabel()
    private(set) var currentUsername: String = ""
    private var currentSize: CGFloat
    private var skeletonGradient: CAGradientLayer?

    init(username: String, size: CGFloat, fontSize: CGFloat? = nil) {
        self.currentSize = size
        super.init(frame: CGRect(x: 0, y: 0, width: size, height: size))
        setupView(size: size)
        configure(username: username, fontSize: fontSize)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupView(size: CGFloat) {
        layer.cornerRadius = size / 2
        clipsToBounds = true

        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        skeletonGradient?.frame = bounds
    }

    func configure(username: String, fontSize: CGFloat? = nil) {
        stopSkeletonShimmer()
        currentUsername = username
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? ""
        let resolvedFontSize = fontSize ?? (currentSize * 0.4)

        backgroundColor = UIColor.avatarColor(for: username)
        label.text = initial
        label.font = .systemFont(ofSize: resolvedFontSize, weight: .semibold)
        label.isHidden = false
    }

    func showImageMode() {
        stopSkeletonShimmer()
        backgroundColor = .clear
        label.isHidden = true
    }

    func showPlaceholder() {
        stopSkeletonShimmer()
        backgroundColor = UIColor.avatarColor(for: currentUsername)
        label.isHidden = false
    }

    func showSkeleton() {
        label.isHidden = true
        startSkeletonShimmer()
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

    let textNode = ASTextNode2()
    private(set) var currentUsername: String = ""
    let avatarSize: CGFloat
    private var skeletonGradient: CAGradientLayer?

    init(username: String, size: CGFloat, fontSize: CGFloat? = nil) {
        self.avatarSize = size
        super.init()
        automaticallyManagesSubnodes = true

        style.preferredSize = CGSize(width: size, height: size)
        cornerRadius = size / 2
        clipsToBounds = true

        textNode.maximumNumberOfLines = 1

        configure(username: username, fontSize: fontSize)
    }

    func configure(username: String, fontSize: CGFloat? = nil) {
        stopSkeletonShimmer()
        currentUsername = username
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? ""
        let resolvedFontSize = fontSize ?? (avatarSize * 0.4)

        backgroundColor = UIColor.avatarColor(for: username)

        let para = NSMutableParagraphStyle()
        para.alignment = .center

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
        textNode.isHidden = true
    }

    func showPlaceholder() {
        stopSkeletonShimmer()
        backgroundColor = UIColor.avatarColor(for: currentUsername)
        textNode.isHidden = false
    }

    func showSkeleton() {
        textNode.isHidden = true
        if Thread.isMainThread {
            startSkeletonShimmer()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.startSkeletonShimmer()
            }
        }
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
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: textNode)
    }
}
