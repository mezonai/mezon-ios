import AsyncDisplayKit
import Foundation
import UIKit

struct QRUserProfileData: Codable {
    let id: String
    let avatar: String?
    let name: String

    private enum CodingKeys: String, CodingKey {
        case id, avatar, name
    }
}

extension QRUserProfileData {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try container.decode(Int64.self, forKey: .id))
        }
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        name = try container.decode(String.self, forKey: .name)
    }
}

final class QRUserProfileNode: ASDisplayNode {
    private let profile: QRUserProfileData
    private let theme: ThemeAttributes
    private var showsAddFriend: Bool

    private let containerNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode()
    private let usernameNode = ASTextNode()
    private let messageButton = ASButtonNode()
    private let callButton = ASButtonNode()
    private let addFriendButton = ASButtonNode()
    private let closeButton = ASButtonNode()

    var onMessage: (() -> Void)?
    var onCall: (() -> Void)?
    var onAddFriend: (() -> Void)?
    var onClose: (() -> Void)?

    init(profile: QRUserProfileData, username: String?, showAddFriend: Bool, theme: ThemeAttributes) {
        self.profile = profile
        self.theme = theme
        self.showsAddFriend = showAddFriend
        super.init()

        backgroundColor = theme.primary
        accessibilityViewIsModal = true

        containerNode.backgroundColor = theme.secondaryLight
        containerNode.cornerRadius = 24
        containerNode.clipsToBounds = true
        addSubnode(containerNode)

        avatarNode.style.preferredSize = CGSize(width: 72, height: 72)
        avatarNode.cornerRadius = 36
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = theme.bgInfor
        avatarNode.contentMode = .scaleAspectFill
        avatarNode.isAccessibilityElement = false
        if let avatar = profile.avatar, let url = URL(string: ImgproxyURL.iconURL(from: avatar)) {
            avatarNode.url = url
        }
        containerNode.addSubnode(avatarNode)

        nameNode.attributedText = NSAttributedString(
            string: profile.name.isEmpty ? (username ?? profile.id) : profile.name,
            attributes: [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: theme.textStrong,
                .paragraphStyle: centeredParagraphStyle(),
            ])
        containerNode.addSubnode(nameNode)

        if let username, !username.isEmpty {
            usernameNode.attributedText = NSAttributedString(
                string: username.hasPrefix("@") ? username : "@\(username)",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 14),
                    .foregroundColor: theme.channelNormal,
                    .paragraphStyle: centeredParagraphStyle(),
                ])
        }
        containerNode.addSubnode(usernameNode)

        setupButton(messageButton, title: L(L10n.QRScanner.message), assetName: "Chat/ChatBubbleIcon", primary: true)
        messageButton.addTarget(
            self, action: #selector(messageTapped), forControlEvents: .touchUpInside)
        containerNode.addSubnode(messageButton)

        setupButton(callButton, title: L(L10n.QRScanner.call), assetName: "Chat/PhoneCallIcon", primary: true)
        callButton.addTarget(self, action: #selector(callTapped), forControlEvents: .touchUpInside)
        containerNode.addSubnode(callButton)

        setupButton(addFriendButton, title: L(L10n.FriendList.addFriend), assetName: "Chat/UserPlusIcon", primary: false)
        addFriendButton.addTarget(self, action: #selector(addFriendTapped), forControlEvents: .touchUpInside)
        addFriendButton.isHidden = !showAddFriend
        containerNode.addSubnode(addFriendButton)

        let closeImage = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        closeButton.setImage(closeImage?.withTintColor(theme.channelNormal, renderingMode: .alwaysOriginal), for: .normal)
        closeButton.style.preferredSize = CGSize(width: 44, height: 44)
        closeButton.accessibilityLabel = L(L10n.Common.close)
        closeButton.addTarget(
            self, action: #selector(closeTapped), forControlEvents: .touchUpInside)
        containerNode.addSubnode(closeButton)
    }

    private func setupButton(
        _ button: ASButtonNode, title: String, assetName: String, primary: Bool
    ) {
        let textColor: UIColor = primary ? .white : theme.textStrong
        button.setAttributedTitle(
            NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: textColor,
                ]), for: .normal)
        button.setImage(UIImage(named: assetName)?.withTintColor(textColor, renderingMode: .alwaysOriginal), for: .normal)
        button.imageNode.contentMode = .scaleAspectFit
        button.imageNode.style.preferredSize = CGSize(width: 20, height: 20)
        button.imageAlignment = .beginning
        button.laysOutHorizontally = true
        button.contentSpacing = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        button.backgroundColor = primary ? theme.bgViolet : theme.secondary
        button.cornerRadius = 16
        button.style.minHeight = ASDimensionMake(48)
        button.accessibilityLabel = title
    }

    override func didLoad() {
        super.didLoad()
        let tap = UITapGestureRecognizer(target: self, action: #selector(backdropTapped(_:)))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    func setActionsEnabled(_ enabled: Bool) {
        for button in [messageButton, callButton, addFriendButton] {
            button.isEnabled = enabled
            button.alpha = enabled ? 1 : 0.5
        }
    }

    func hideAddFriend() {
        showsAddFriend = false
        addFriendButton.isHidden = true
        containerNode.setNeedsLayout()
        setNeedsLayout()
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }

    @objc private func messageTapped() {
        onMessage?()
    }

    @objc private func callTapped() { onCall?() }

    @objc private func addFriendTapped() { onAddFriend?() }

    @objc private func backdropTapped(_ recognizer: UITapGestureRecognizer) { onClose?() }

    @objc private func closeTapped() {
        onClose?()
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        avatarNode.style.alignSelf = .center
        nameNode.style.alignSelf = .center
        usernameNode.style.alignSelf = .center

        let cardWidth = min(420, max(0, constrainedSize.max.width - 32))
        let buttonWidth = max(0, (cardWidth - 48 - 12) / 2)
        messageButton.style.width = ASDimensionMake(buttonWidth)
        callButton.style.width = ASDimensionMake(buttonWidth)
        closeButton.style.layoutPosition = CGPoint(x: cardWidth - 50, y: 6)

        let identity = ASStackLayoutSpec.vertical()
        identity.spacing = 4
        identity.alignItems = .stretch
        identity.children = usernameNode.attributedText == nil ? [nameNode] : [nameNode, usernameNode]

        let buttons = ASStackLayoutSpec.horizontal()
        buttons.spacing = 12
        buttons.alignItems = .stretch
        buttons.children = [messageButton, callButton]

        let actions = ASStackLayoutSpec.vertical()
        actions.spacing = 12
        actions.alignItems = .stretch
        actions.children = showsAddFriend ? [buttons, addFriendButton] : [buttons]

        let content = ASStackLayoutSpec.vertical()
        content.alignItems = .stretch
        let avatar = ASCenterLayoutSpec(centeringOptions: .X, sizingOptions: .minimumY, child: avatarNode)
        content.children = [
            avatar,
            ASInsetLayoutSpec(insets: UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0), child: identity),
            ASInsetLayoutSpec(insets: UIEdgeInsets(top: 24, left: 0, bottom: 0, right: 0), child: actions),
        ]
        let padded = ASInsetLayoutSpec(insets: UIEdgeInsets(top: 32, left: 24, bottom: 24, right: 24), child: content)
        let card = ASOverlayLayoutSpec(child: padded, overlay: ASAbsoluteLayoutSpec(children: [closeButton]))
        containerNode.style.width = ASDimensionMake(cardWidth)
        containerNode.layoutSpecBlock = { _, _ in card }

        return ASCenterLayoutSpec(
            centeringOptions: .XY, sizingOptions: .minimumXY, child: containerNode)
    }
}

extension QRUserProfileNode: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !containerNode.view.bounds.contains(touch.location(in: containerNode.view))
    }
}

enum QRProfileCall {
    @MainActor
    static func canStart(context: AccountContext, userId: Int64) -> Bool {
        if userId == Int64(context.currentUser?.id ?? "") {
            Toast.error(L(L10n.QRScanner.cannotCallYourself))
            return false
        }
        if context.engine.friendsData.blockedUserIds().contains(userId) {
            Toast.error(L(L10n.FriendRequest.toastBlockedError))
            return false
        }
        if WebRTCCallManager.shared.signalingSession != nil
            || WebRTCCallManager.shared.isPeerCallDetailScreenActive
            || CallKitManager.shared.hasTrackedActiveCall {
            Toast.error(L(L10n.QRScanner.callInProgress))
            return false
        }
        return true
    }
}
