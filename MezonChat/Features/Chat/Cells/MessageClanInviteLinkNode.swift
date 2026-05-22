import AsyncDisplayKit
import UIKit

final class MessageClanInviteLinkNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let loadingNode = ASDisplayNode()
    private let avatarContainerNode = ASDisplayNode()
    private let avatarImageNode = ASNetworkImageNode()
    private let avatarPlaceholderNode = ASTextNode2()
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
    private static let verticalInset: CGFloat = 10
    private static let avatarSide: CGFloat = 48
    private static let memberDotSize: CGFloat = 8
    private static let buttonHeight: CGFloat = 36
    private static let maxCardWidth: CGFloat = 264
    private static let primaryButtonColor = UIColor(hex: 0x5e65de)

    static let preferredHeight: CGFloat = 186

    private static func clanLogoURL(_ raw: String) -> URL? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.hasPrefix("//"), let u = URL(string: "https:\(t)") { return u }
        if let u = URL(string: t), u.scheme != nil { return u }
        if !t.contains("://"), let u = URL(string: "https://\(t)") { return u }
        return URLComponents(string: t)?.url
    }

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

        avatarContainerNode.cornerRadius = 10
        avatarContainerNode.clipsToBounds = true
        avatarContainerNode.borderWidth = 1
        avatarContainerNode.borderColor = t.border.withAlphaComponent(0.35).cgColor

        avatarImageNode.cornerRadius = 10
        avatarImageNode.clipsToBounds = true
        avatarImageNode.contentMode = .scaleAspectFill
        avatarImageNode.backgroundColor = .clear

        avatarPlaceholderNode.maximumNumberOfLines = 1

        nameNode.maximumNumberOfLines = 1
        memberNode.maximumNumberOfLines = 1

        memberDotNode.backgroundColor = UIColor(hex: 0x34C759)
        memberDotNode.cornerRadius = Self.memberDotSize / 2

        actionButton.cornerRadius = Self.buttonHeight / 2
        actionButton.addTarget(self, action: #selector(actionTapped), forControlEvents: .touchUpInside)

        errorNode.maximumNumberOfLines = 3
        errorNode.isHidden = true

        addSubnode(containerNode)
        containerNode.addSubnode(loadingNode)
        containerNode.addSubnode(avatarContainerNode)
        avatarContainerNode.addSubnode(avatarImageNode)
        avatarContainerNode.addSubnode(avatarPlaceholderNode)
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
        avatarContainerNode.isHidden = true
        nameNode.isHidden = true
        memberDotNode.isHidden = true
        memberNode.isHidden = true
        errorNode.isHidden = true
        actionButton.isHidden = true
    }

    private func applyLoadedUI(_ info: ClanInviteInfo) {
        loadingNode.isHidden = true
        avatarContainerNode.isHidden = false
        nameNode.isHidden = false
        memberDotNode.isHidden = false
        memberNode.isHidden = false
        errorNode.isHidden = true
        actionButton.isHidden = false

        let t = UIColor.theme
        let clanName = (info.clan_name?.isEmpty == false) ? (info.clan_name ?? "") : "Clan"
        let initialSource = clanName.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = initialSource.isEmpty ? "" : String(initialSource.prefix(1)).uppercased()
        avatarPlaceholderNode.attributedText = NSAttributedString(
            string: initial,
            attributes: [
                .font: UIFont.systemFont(ofSize: 18.sf, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
        )
        if let logo = info.clan_logo?.trimmingCharacters(in: .whitespacesAndNewlines), !logo.isEmpty,
           let url = Self.clanLogoURL(logo) {
            avatarImageNode.url = url
            avatarImageNode.isHidden = false
            avatarPlaceholderNode.isHidden = true
            avatarContainerNode.backgroundColor = UIColor.theme.primary
        } else {
            avatarImageNode.url = nil
            avatarImageNode.isHidden = true
            avatarPlaceholderNode.isHidden = false
            avatarContainerNode.backgroundColor = UIColor.avatarColor(for: clanName)
        }

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
        actionButton.backgroundColor = Self.primaryButtonColor
        actionButton.setTitle(
            title,
            with: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
            with: .white,
            for: .normal
        )
        actionButton.isEnabled = true
    }

    private func applyFailedUI() {
        loadingNode.isHidden = true
        avatarContainerNode.isHidden = true
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
        actionButton.backgroundColor = Self.primaryButtonColor
        actionButton.setTitle(
            L(L10n.Common.refresh),
            with: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
            with: .white,
            for: .normal
        )
        actionButton.isEnabled = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let cardW = min(Self.maxCardWidth, max(w, 1))
        containerNode.frame = CGRect(x: 0, y: 0, width: cardW, height: h)
        let inset = Self.horizontalInset
        let innerW = max(cardW - inset * 2, 1)
        let btnH = Self.buttonHeight

        if !loadingNode.isHidden && loadedInfo == nil && !loadFailed {
            let spinS: CGFloat = 32
            loadingNode.frame = CGRect(x: (cardW - spinS) / 2, y: (h - spinS) / 2, width: spinS, height: spinS)
            return
        }

        if loadFailed {
            let errH = errorNode.measure(CGSize(width: innerW, height: .greatestFiniteMagnitude)).height
            let topY = inset + 6
            errorNode.frame = CGRect(x: inset, y: topY, width: innerW, height: errH)
            actionButton.frame = CGRect(x: inset, y: h - inset - btnH, width: innerW, height: btnH)
            return
        }

        guard loadedInfo != nil else { return }

        var y = inset
        avatarContainerNode.frame = CGRect(x: inset, y: y, width: Self.avatarSide, height: Self.avatarSide)
        avatarImageNode.frame = CGRect(x: 0, y: 0, width: Self.avatarSide, height: Self.avatarSide)
        let phSize = avatarPlaceholderNode.measure(CGSize(width: Self.avatarSide, height: Self.avatarSide))
        avatarPlaceholderNode.frame = CGRect(
            x: (Self.avatarSide - phSize.width) / 2,
            y: (Self.avatarSide - phSize.height) / 2,
            width: phSize.width,
            height: phSize.height
        )
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
