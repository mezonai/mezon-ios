import AsyncDisplayKit
import UIKit

final class QRClanInviteNode: ASDisplayNode {
    
    private let containerNode = ASDisplayNode()
    private let titleNode = ASTextNode()
    private let avatarNode = ASNetworkImageNode()
    private let clanNameNode = ASTextNode()
    private let channelNode = ASTextNode()
    private let joinButton = ASButtonNode()
    private let noThanksButton = ASButtonNode()
    private let joinSpinnerNode = ASDisplayNode()
    
    var onJoin: (() -> Void)?
    var onCancel: (() -> Void)?
    
    private let theme: ThemeAttributes
    private let inviteInfo: ClanInviteInfo
    
    init(theme: ThemeAttributes, inviteInfo: ClanInviteInfo) {
        self.theme = theme
        self.inviteInfo = inviteInfo
        super.init()
        self.backgroundColor = UIColor.mezonPrimary
        setupNodes()
    }
    
    private func setupNodes() {
        containerNode.backgroundColor = theme.secondary
        containerNode.cornerRadius = 24
        containerNode.clipsToBounds = true
        
        titleNode.attributedText = NSAttributedString(string: L(L10n.QRScanner.inviteToJoinClan), attributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .bold),
            .foregroundColor: theme.textDisabled,
            .paragraphStyle: centeredParagraphStyle()
        ])
        
        avatarNode.style.preferredSize = CGSize(width: 80, height: 80)
        avatarNode.cornerRadius = 40
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = theme.bgInfor
        if let logo = inviteInfo.clan_logo, let url = URL(string: logo) {
            avatarNode.url = url
        }
        
        let clanName = inviteInfo.clan_name ?? "Clan"
        let clanAttr = NSMutableAttributedString(string: clanName + " ", attributes: [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: theme.white,
            .paragraphStyle: centeredParagraphStyle()
        ])
        if inviteInfo.is_community == true {
             let attachment = NSTextAttachment()
             if #available(iOS 13.0, *) {
                 attachment.image = UIImage(systemName: "checkmark.seal.fill")?.withTintColor(.white)
             }
             attachment.bounds = CGRect(x: 0, y: -2, width: 18, height: 18)
             clanAttr.append(NSAttributedString(attachment: attachment))
        }
        clanNameNode.attributedText = clanAttr
        
        if let channel = inviteInfo.channel_label {
            channelNode.attributedText = NSAttributedString(string: "# \(channel)", attributes: [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: theme.textDisabled,
                .paragraphStyle: centeredParagraphStyle()
            ])
        }
        
        joinButton.backgroundColor = UIColor(hex: 0x5e65de)
        joinButton.setTitle(L(L10n.QRScanner.joinClan), with: .systemFont(ofSize: 16, weight: .bold), with: .white, for: .normal)
        joinButton.cornerRadius = 24
        joinButton.style.height = ASDimensionMake(48)
        joinButton.addTarget(self, action: #selector(joinTapped), forControlEvents: .touchUpInside)

        joinSpinnerNode.style.preferredSize = CGSize(width: 24, height: 24)
        joinSpinnerNode.isHidden = true
        joinSpinnerNode.setViewBlock {
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.color = .white
            indicator.startAnimating()
            return indicator
        }
        
        noThanksButton.backgroundColor = .mezonPrimary
        noThanksButton.cornerRadius = 24
        noThanksButton.setTitle(L(L10n.QRScanner.noThanks), with: .systemFont(ofSize: 16, weight: .bold), with: theme.textStrong, for: .normal)
        noThanksButton.style.height = ASDimensionMake(48)
        noThanksButton.addTarget(self, action: #selector(cancelTapped), forControlEvents: .touchUpInside)
        
        self.addSubnode(containerNode)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(avatarNode)
        containerNode.addSubnode(clanNameNode)
        containerNode.addSubnode(channelNode)
        containerNode.addSubnode(joinButton)
        containerNode.addSubnode(joinSpinnerNode)
        containerNode.addSubnode(noThanksButton)
    }
    
    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        titleNode.style.alignSelf = .center
        avatarNode.style.alignSelf = .center
        clanNameNode.style.alignSelf = .center
        channelNode.style.alignSelf = .center
        
        joinButton.style.width = ASDimensionMakeWithFraction(1.0)
        noThanksButton.style.width = ASDimensionMakeWithFraction(1.0)

        let joinOverlay = ASOverlayLayoutSpec(
            child: joinButton,
            overlay: ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: [], child: joinSpinnerNode)
        )

        let contentStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 24,
            justifyContent: .center,
            alignItems: .stretch,
            children: [titleNode, avatarNode, clanNameNode, channelNode, joinOverlay, noThanksButton]
        )
        
        let containerInsetEnabled = ASInsetLayoutSpec(insets: UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24), child: contentStack)
        containerNode.style.width = ASDimensionMakeWithPoints(constrainedSize.max.width - 40)
        
        containerNode.layoutSpecBlock = { _, _ in return containerInsetEnabled }
        
        return ASCenterLayoutSpec(centeringOptions: .XY, sizingOptions: .minimumXY, child: containerNode)
    }
    
    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }
    
    @objc private func joinTapped() {
        onJoin?()
    }
    
    @objc private func cancelTapped() {
        onCancel?()
    }

    func setJoining(_ joining: Bool) {
        joinSpinnerNode.isHidden = !joining
        joinButton.isEnabled = !joining
        noThanksButton.isEnabled = !joining
        let title = joining ? "" : L(L10n.QRScanner.joinClan)
        joinButton.setTitle(title, with: .systemFont(ofSize: 16, weight: .bold), with: .white, for: .normal)
    }
}
