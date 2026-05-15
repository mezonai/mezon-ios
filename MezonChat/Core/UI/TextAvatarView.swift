import UIKit
import AsyncDisplayKit

final class TextAvatarView: UIView {

    private let label = UILabel()
    private(set) var currentUsername: String = ""
    private var currentSize: CGFloat

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

    func configure(username: String, fontSize: CGFloat? = nil) {
        currentUsername = username
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? "?"
        let resolvedFontSize = fontSize ?? (currentSize * 0.4)

        backgroundColor = UIColor.avatarColor(for: username)
        label.text = initial
        label.font = .systemFont(ofSize: resolvedFontSize, weight: .semibold)
        label.isHidden = false
    }

    func showImageMode() {
        backgroundColor = .clear
        label.isHidden = true
    }

    func showPlaceholder() {
        backgroundColor = UIColor.avatarColor(for: currentUsername)
        label.isHidden = false
    }
}

final class TextAvatarNode: ASDisplayNode {

    let textNode = ASTextNode2()
    private(set) var currentUsername: String = ""
    let avatarSize: CGFloat

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
        currentUsername = username
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { String($0).uppercased() } ?? "?"
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
        backgroundColor = .clear
        textNode.isHidden = true
    }

    func showPlaceholder() {
        backgroundColor = UIColor.avatarColor(for: currentUsername)
        textNode.isHidden = false
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: textNode)
    }
}
