import AsyncDisplayKit
import UIKit

final class MessageClanInviteLinkNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let loadingNode = ASDisplayNode()
    private let avatarNode = ASNetworkImageNode()
    private let nameNode = ASTextNode2()
    private let memberDotNode = ASDisplayNode()
    private let memberNode = ASTextNode2()
    private let actionButton = ASButtonNode()
    private let errorNode = ASTextNode2()

    private let inviteCode: String
    private let interaction: ChatInteraction
    private var loadedInfo: ClanInviteInfo?
    private var loadFailed = false

    private static let horizontalInset: CGFloat = 12
    private static let verticalInset: CGFloat = 12
    private static let avatarSide: CGFloat = 48
    private static let memberDotSize: CGFloat = 8
    private static let buttonHeight: CGFloat = 44

    static let preferredHeight: CGFloat = 200

    init(inviteCode: String, interaction: ChatInteraction) {
        self.inviteCode = inviteCode
        self.interaction = interaction
        super.init()
        automaticallyManagesSubnodes = false
        backgroundColor = .clear

        let t = UIColor.theme
        containerNode.backgroundColor = t.secondary
        containerNode.cornerRadius = 12
        containerNode.borderWidth = 1
        containerNode.borderColor = t.border.cgColor

        loadingNode.setViewBlock {
            let v = UIActivityIndicatorView(style: .medium)
            v.startAnimating()
            v.color = t.textDisabled
            return v
        }

        avatarNode.cornerRadius = 10
        avatarNode.clipsToBounds = true
        avatarNode.backgroundColor = t.bgInfor

        nameNode.maximumNumberOfLines = 1
        memberNode.maximumNumberOfLines = 1

        memberDotNode.backgroundColor = UIColor.mezonSuccess
        memberDotNode.cornerRadius = Self.memberDotSize / 2

        actionButton.cornerRadius = 22
        actionButton.addTarget(self, action: #selector(actionTapped), forControlEvents: .touchUpInside)

        errorNode.maximumNumberOfLines = 3
        errorNode.isHidden = true

        addSubnode(containerNode)
        containerNode.addSubnode(loadingNode)
        containerNode.addSubnode(avatarNode)
        containerNode.addSubnode(nameNode)
        containerNode.addSubnode(memberDotNode)
        containerNode.addSubnode(memberNode)
        containerNode.addSubnode(actionButton)
        containerNode.addSubnode(errorNode)

        applyLoadingUI()
    }

    override func didLoad() {
        super.didLoad()
        fetchInvite()
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        CGSize(width: maxWidth, height: Self.preferredHeight)
    }

    private func fetchInvite() {
        loadFailed = false
        loadedInfo = nil
        applyLoadingUI()
        interaction.loadClanInviteInfo(inviteCode) { [weak self] info in
            guard let self else { return }
            if let info {
                self.loadedInfo = info
                self.loadFailed = false
                self.applyLoadedUI(info)
            } else {
                self.loadedInfo = nil
                self.loadFailed = true
                self.applyFailedUI()
            }
            self.setNeedsLayout()
        }
    }

    private func applyLoadingUI() {
        loadingNode.isHidden = false
        avatarNode.isHidden = true
        nameNode.isHidden = true
        memberDotNode.isHidden = true
        memberNode.isHidden = true
        errorNode.isHidden = true
        actionButton.isHidden = true
    }

    private func applyLoadedUI(_ info: ClanInviteInfo) {
        loadingNode.isHidden = true
        avatarNode.isHidden = false
        nameNode.isHidden = false
        memberDotNode.isHidden = false
        memberNode.isHidden = false
        errorNode.isHidden = true
        actionButton.isHidden = false

        let t = UIColor.theme
        if let logo = info.clan_logo, !logo.isEmpty {
            avatarNode.url = URL(string: ImgproxyURL.create(from: logo, width: 96, height: 96))
        } else {
            avatarNode.url = nil
        }

        let clanName = (info.clan_name?.isEmpty == false) ? (info.clan_name ?? "") : "Clan"
        nameNode.attributedText = NSAttributedString(string: clanName, attributes: [
            .font: UIFont.systemFont(ofSize: 16.sf, weight: .bold),
            .foregroundColor: t.textStrong,
        ])

        let count = info.member_count ?? 0
        let memberText = String(format: L(L10n.ClanAction.memberCount), count)
        memberNode.attributedText = NSAttributedString(string: memberText, attributes: [
            .font: UIFont.systemFont(ofSize: 13.sf),
            .foregroundColor: t.textDisabled,
        ])

        let isJoined = info.user_joined == true
        let title = isJoined ? L(L10n.QRScanner.goToClan) : L(L10n.QRScanner.joinClan)
        actionButton.backgroundColor = UIColor.mezonSuccess
        actionButton.setTitle(
            title,
            with: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
            with: .white,
            for: .normal
        )
        actionButton.isEnabled = true
    }

    private func applyFailedUI() {
        loadingNode.isHidden = true
        avatarNode.isHidden = true
        nameNode.isHidden = true
        memberDotNode.isHidden = true
        memberNode.isHidden = true
        errorNode.isHidden = false
        actionButton.isHidden = false

        let t = UIColor.theme
        errorNode.attributedText = NSAttributedString(
            string: L(L10n.ChannelMessages.clanInviteLoadFailed),
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        actionButton.backgroundColor = UIColor.mezonSuccess
        actionButton.setTitle(
            L(L10n.Common.refresh),
            with: UIFont.systemFont(ofSize: 15.sf, weight: .semibold),
            with: .white,
            for: .normal
        )
        actionButton.isEnabled = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        containerNode.frame = bounds
        let inset = Self.horizontalInset
        let innerW = max(w - inset * 2, 1)
        let btnH = Self.buttonHeight

        if !loadingNode.isHidden && loadedInfo == nil && !loadFailed {
            let spinS: CGFloat = 32
            loadingNode.frame = CGRect(x: (w - spinS) / 2, y: (h - spinS) / 2, width: spinS, height: spinS)
            return
        }

        if loadFailed {
            let errH = errorNode.measure(CGSize(width: innerW, height: .greatestFiniteMagnitude)).height
            let topY = inset + 8
            errorNode.frame = CGRect(x: inset, y: topY, width: innerW, height: errH)
            actionButton.frame = CGRect(x: inset, y: h - inset - btnH, width: innerW, height: btnH)
            return
        }

        guard loadedInfo != nil else { return }

        var y = inset
        avatarNode.frame = CGRect(x: inset, y: y, width: Self.avatarSide, height: Self.avatarSide)
        y += Self.avatarSide + 8

        let nameH = nameNode.measure(CGSize(width: innerW, height: 30)).height
        nameNode.frame = CGRect(x: inset, y: y, width: innerW, height: nameH)
        y += nameH + 4

        let memberTextH = memberNode.measure(CGSize(width: innerW - Self.memberDotSize - 6, height: 30)).height
        let rowH = max(Self.memberDotSize, memberTextH)
        let dotY = y + (rowH - Self.memberDotSize) / 2
        memberDotNode.frame = CGRect(x: inset, y: dotY, width: Self.memberDotSize, height: Self.memberDotSize)
        memberNode.frame = CGRect(
            x: inset + Self.memberDotSize + 6,
            y: y + (rowH - memberTextH) / 2,
            width: innerW - Self.memberDotSize - 6,
            height: memberTextH
        )
        y += rowH

        actionButton.frame = CGRect(x: inset, y: h - inset - btnH, width: innerW, height: btnH)
    }

    @objc private func actionTapped() {
        if loadFailed {
            fetchInvite()
            return
        }
        guard let info = loadedInfo else { return }
        interaction.onClanInvitePrimaryAction(inviteCode, info)
    }
}
