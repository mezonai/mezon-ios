import AsyncDisplayKit
import UIKit

final class WelcomeCellNode: ASDisplayNode {

    private enum Mode {
        case clan(channelType: Int32, isPrivate: Bool, isAgeRestricted: Bool, isMediaChannel: Bool, threadCreatorName: String)
        case dmOneToOne(label: String, username: String, priorityName: String, avatarURL: String, placeholderLetter: String)
        case dmGroup(label: String, groupAvatarURL: String?)
    }

    private let mode: Mode

    private let iconContainerNode = ASDisplayNode()
    private let iconImageNode = ASImageNode()

    private let dmAvatarBgNode = ASDisplayNode()
    private let dmAvatarImageNode = TransformImageNode()
    private let dmAvatarPlaceholderNode = ASTextNode2()

    private let groupDmOuterNode = ASDisplayNode()
    private let groupDmImageNode = TransformImageNode()
    private let groupDmIconNode = ASImageNode()

    private let titleNode = ASTextNode2()
    private let usernameNode = ASTextNode2()
    private let subtitleNode = ASTextNode2()

    private static let clanIconSize: CGFloat = 70
    private static let clanIconImageSize: CGFloat = 36
    private static let dmAvatarSize: CGFloat = 64
    private static let groupDmSize: CGFloat = 50
    private static let groupDmIconInner: CGFloat = 22

    private var cachedTitleSize: CGSize = .zero
    private var cachedUsernameSize: CGSize = .zero
    private var cachedSubtitleSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    private let showsUsernameRow: Bool

    init(
        channelLabel: String,
        channelType: Int32,
        isPrivate: Bool,
        isAgeRestricted: Bool,
        isDM: Bool,
        dmPeerUsername: String,
        dmPeerDisplayName: String,
        dmAvatarURL: String,
        dmGroupAvatarURL: String,
        threadCreatorName: String
    ) {
        let isGroupDM = channelType == MezonConstants.ChannelType.group.rawValue
        let isMediaChannel: Bool = {
            switch channelType {
            case MezonConstants.ChannelType.streaming.rawValue,
                 MezonConstants.ChannelType.mezonVoice.rawValue,
                 MezonConstants.ChannelType.app.rawValue:
                return true
            default:
                return false
            }
        }()

        let resolvedMode: Mode
        if isDM && isGroupDM {
            let trimmed = dmGroupAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = !trimmed.isEmpty && !trimmed.contains("avatar-group.png") ? trimmed : nil
            resolvedMode = .dmGroup(label: channelLabel, groupAvatarURL: url)
            showsUsernameRow = false
        } else if isDM {
            let letterSource = dmPeerUsername.isEmpty ? channelLabel : dmPeerUsername
            let letter = String(letterSource.prefix(1)).uppercased()
            let priorityNameRaw = dmPeerDisplayName.isEmpty ? dmPeerUsername : dmPeerDisplayName
            let priorityName = priorityNameRaw.isEmpty ? channelLabel : priorityNameRaw
            resolvedMode = .dmOneToOne(
                label: channelLabel,
                username: dmPeerUsername,
                priorityName: priorityName,
                avatarURL: dmAvatarURL.trimmingCharacters(in: .whitespacesAndNewlines),
                placeholderLetter: letter.isEmpty ? "" : letter
            )
            showsUsernameRow = !dmPeerUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            resolvedMode = .clan(
                channelType: channelType,
                isPrivate: isPrivate,
                isAgeRestricted: isAgeRestricted,
                isMediaChannel: isMediaChannel,
                threadCreatorName: threadCreatorName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            showsUsernameRow = false
        }

        self.mode = resolvedMode

        super.init()

        backgroundColor = .clear

        let t = UIColor.theme
        let name = channelLabel

        switch resolvedMode {
        case let .clan(channelType, isPrivate, isAgeRestricted, isMediaChannel, threadCreatorName):
            iconContainerNode.backgroundColor = t.secondaryLight
            iconContainerNode.cornerRadius = Self.clanIconSize / 2
            iconContainerNode.clipsToBounds = true
            addSubnode(iconContainerNode)

            let iconName: String
            switch channelType {
            case 10: iconName = "Chat/SpeakerIcon"
            case 4: iconName = "Channel/ChevronRight"
            case 6: iconName = "Channel/channelStream"
            case 8: iconName = "Channel/channelApp"
            case 7:
                if isPrivate {
                    iconName = "Channel/channelThreadPrivate"
                } else {
                    iconName = "Channel/channelThread"
                }
            case 1:
                if isPrivate {
                    iconName = "Channel/channelPrivate"
                } else if isAgeRestricted {
                    iconName = "Channel/channelWarning"
                } else {
                    iconName = "Channel/channel"
                }
            default: iconName = "Channel/channel"
            }
            let isThread = channelType == MezonConstants.ChannelType.thread.rawValue
            let image = UIImage(named: iconName) ?? UIImage(systemName: iconName)
            iconImageNode.image = image?.withRenderingMode(.alwaysTemplate)
            iconImageNode.tintColor = t.textStrong
            iconImageNode.contentMode = .scaleAspectFit
            iconContainerNode.addSubnode(iconImageNode)

            let privateWord = (isPrivate && !isMediaChannel) ? L(L10n.ChatWelcome.privateChannel) : ""
            titleNode.attributedText = NSAttributedString(
                string: isThread ? name : String(format: L(L10n.ChatWelcome.welcomeToChannel), name),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 22.sf, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            )
            let subtitle: String = {
                if isThread {
                    return threadCreatorName.isEmpty
                        ? ""
                        : String(format: L(L10n.ChatWelcome.threadStartedBy), threadCreatorName)
                }
                return String(format: L(L10n.ChatWelcome.startOfChannel), name, privateWord)
            }()
            subtitleNode.attributedText = NSAttributedString(
                string: subtitle,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.text,
                ]
            )

        case let .dmOneToOne(label, username, priorityName, avatarURL, placeholderLetter):
            dmAvatarBgNode.backgroundColor = UIColor.avatarColor(for: username)
            dmAvatarBgNode.cornerRadius = Self.dmAvatarSize / 2
            dmAvatarBgNode.clipsToBounds = true
            addSubnode(dmAvatarBgNode)

            dmAvatarBgNode.addSubnode(dmAvatarImageNode)
            dmAvatarPlaceholderNode.maximumNumberOfLines = 1
            dmAvatarBgNode.addSubnode(dmAvatarPlaceholderNode)

            Self.applyRoundAvatar(
                imageNode: dmAvatarImageNode,
                placeholderNode: dmAvatarPlaceholderNode,
                urlString: avatarURL.isEmpty ? nil : avatarURL,
                placeholderLetter: placeholderLetter,
                size: Self.dmAvatarSize,
                placeholderFontSize: 22.sf,
                containerNode: dmAvatarBgNode
            )

            titleNode.attributedText = NSAttributedString(
                string: label,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 22.sf, weight: .semibold),
                    .foregroundColor: t.textStrong,
                ]
            )

            if showsUsernameRow {
                usernameNode.attributedText = NSAttributedString(
                    string: username,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 18.sf),
                        .foregroundColor: t.text,
                    ]
                )
            }

            subtitleNode.attributedText = NSAttributedString(
                string: String(format: L(L10n.ChatWelcome.beginningOfDM), priorityName),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.text,
                ]
            )

        case let .dmGroup(label, groupAvatarURL):
            groupDmOuterNode.cornerRadius = Self.groupDmSize / 2
            groupDmOuterNode.clipsToBounds = true
            groupDmOuterNode.backgroundColor = .groupDMDefaultAvatar
            addSubnode(groupDmOuterNode)

            groupDmOuterNode.addSubnode(groupDmImageNode)

            groupDmIconNode.image = UIImage(systemName: "person.2.fill")?.withRenderingMode(.alwaysTemplate)
            groupDmIconNode.tintColor = .white
            groupDmIconNode.contentMode = .scaleAspectFit
            groupDmOuterNode.addSubnode(groupDmIconNode)

            if let groupAvatarURL {
                groupDmIconNode.isHidden = true
                Self.applyRoundAvatar(
                    imageNode: groupDmImageNode,
                    placeholderNode: nil,
                    urlString: groupAvatarURL,
                    placeholderLetter: "",
                    size: Self.groupDmSize,
                    placeholderFontSize: 12,
                    containerNode: groupDmOuterNode
                )
            } else {
                groupDmImageNode.isHidden = true
                groupDmIconNode.isHidden = false
            }

            let titleParagraph = NSMutableParagraphStyle()
            titleParagraph.alignment = .center
            titleNode.attributedText = NSAttributedString(
                string: label,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 22.sf, weight: .semibold),
                    .foregroundColor: t.textStrong,
                    .paragraphStyle: titleParagraph,
                ]
            )

            let subParagraph = NSMutableParagraphStyle()
            subParagraph.alignment = .center
            subtitleNode.attributedText = NSAttributedString(
                string: String(format: L(L10n.ChatWelcome.welcomeToGroup), label),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12.sf),
                    .foregroundColor: t.text,
                    .paragraphStyle: subParagraph,
                ]
            )
        }

        titleNode.maximumNumberOfLines = 0
        subtitleNode.maximumNumberOfLines = 0
        addSubnode(titleNode)
        addSubnode(subtitleNode)
        if showsUsernameRow {
            usernameNode.maximumNumberOfLines = 0
            addSubnode(usernameNode)
        }
    }

    private static func applyRoundAvatar(
        imageNode: TransformImageNode,
        placeholderNode: ASTextNode2?,
        urlString: String?,
        placeholderLetter: String,
        size: CGFloat,
        placeholderFontSize: CGFloat,
        containerNode: ASDisplayNode? = nil
    ) {
        let args = TransformImageArguments(
            corners: ImageCorners(radius: size / 2),
            imageSize: CGSize(width: size, height: size),
            boundingSize: CGSize(width: size, height: size),
            intrinsicInsets: .zero
        )
        if let urlString, !urlString.isEmpty {
            placeholderNode?.isHidden = true
            containerNode?.backgroundColor = .clear
            let proxyURL = ImgproxyURL.create(from: urlString, width: 200, height: 200)
            let hasMem = ImageCache.shared.memoryImage(forKey: proxyURL) != nil
                || ImageCache.shared.memoryImage(forKey: urlString) != nil
            imageNode.reset()
            imageNode.setSignal(remoteAvatarSignal(proxiedURL: proxyURL, originalURL: urlString), attemptSynchronously: hasMem)
            let avatarLayout = imageNode.asyncLayout()
            let apply = avatarLayout(args)
            apply()
            imageNode.isHidden = false
        } else {
            imageNode.reset()
            imageNode.isHidden = true
            guard let placeholderNode else { return }
            placeholderNode.isHidden = false
            placeholderNode.attributedText = NSAttributedString(
                string: placeholderLetter,
                attributes: [
                    .font: UIFont.systemFont(ofSize: placeholderFontSize, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
            )
        }
    }

    func measureSize(width: CGFloat) -> CGSize {
        let insetH: CGFloat = 10.sw
        let insetV: CGFloat = 30.sh
        let spacing: CGFloat = 10.sh
        let contentW = width - insetH * 2

        let totalH: CGFloat
        switch mode {
        case .clan:
            cachedTitleSize = titleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            cachedSubtitleSize = subtitleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            cachedUsernameSize = .zero
            totalH = insetV + Self.clanIconSize + spacing + cachedTitleSize.height + spacing + cachedSubtitleSize.height + insetV

        case .dmOneToOne:
            cachedTitleSize = titleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            cachedUsernameSize = showsUsernameRow
                ? usernameNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
                : .zero
            cachedSubtitleSize = subtitleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            let userExtra = showsUsernameRow ? spacing + cachedUsernameSize.height : 0
            totalH = insetV + Self.dmAvatarSize + spacing + cachedTitleSize.height + userExtra + spacing + cachedSubtitleSize.height + insetV

        case .dmGroup:
            cachedTitleSize = titleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            cachedSubtitleSize = subtitleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
            cachedUsernameSize = .zero
            totalH = insetV + Self.groupDmSize + spacing + cachedTitleSize.height + spacing + cachedSubtitleSize.height + insetV
        }

        cachedTotalSize = CGSize(width: width, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let insetH: CGFloat = 10.sw
        let insetV: CGFloat = 30.sh
        let spacing: CGFloat = 10.sh
        let contentW = bounds.width - insetH * 2
        var y = insetV

        switch mode {
        case .clan:
            let iconSz = Self.clanIconSize
            let imgSz = Self.clanIconImageSize
            iconContainerNode.frame = CGRect(x: insetH, y: y, width: iconSz, height: iconSz)
            iconImageNode.frame = CGRect(
                x: (iconSz - imgSz) / 2,
                y: (iconSz - imgSz) / 2,
                width: imgSz,
                height: imgSz
            )
            y += iconSz + spacing

            titleNode.frame = CGRect(x: insetH, y: y, width: min(cachedTitleSize.width, contentW), height: cachedTitleSize.height)
            y += cachedTitleSize.height + spacing
            subtitleNode.frame = CGRect(x: insetH, y: y, width: min(cachedSubtitleSize.width, contentW), height: cachedSubtitleSize.height)

        case .dmOneToOne:
            dmAvatarBgNode.frame = CGRect(x: insetH, y: y, width: Self.dmAvatarSize, height: Self.dmAvatarSize)
            dmAvatarImageNode.frame = dmAvatarBgNode.bounds
            let phSize = dmAvatarPlaceholderNode.measure(dmAvatarBgNode.bounds.size)
            dmAvatarPlaceholderNode.frame = CGRect(
                x: (Self.dmAvatarSize - phSize.width) / 2,
                y: (Self.dmAvatarSize - phSize.height) / 2,
                width: phSize.width,
                height: phSize.height
            )
            y += Self.dmAvatarSize + spacing

            titleNode.frame = CGRect(x: insetH, y: y, width: min(cachedTitleSize.width, contentW), height: cachedTitleSize.height)
            y += cachedTitleSize.height + spacing
            if showsUsernameRow {
                usernameNode.frame = CGRect(x: insetH, y: y, width: min(cachedUsernameSize.width, contentW), height: cachedUsernameSize.height)
                y += cachedUsernameSize.height + spacing
            }
            subtitleNode.frame = CGRect(x: insetH, y: y, width: min(cachedSubtitleSize.width, contentW), height: cachedSubtitleSize.height)

        case .dmGroup:
            let gsz = Self.groupDmSize
            let iconX = insetH + (contentW - gsz) / 2
            groupDmOuterNode.frame = CGRect(x: iconX, y: y, width: gsz, height: gsz)
            groupDmImageNode.frame = groupDmOuterNode.bounds
            let inner = Self.groupDmIconInner
            groupDmIconNode.frame = CGRect(x: (gsz - inner) / 2, y: (gsz - inner) / 2, width: inner, height: inner)
            y += gsz + spacing

            titleNode.frame = CGRect(x: insetH, y: y, width: contentW, height: cachedTitleSize.height)
            y += cachedTitleSize.height + spacing
            subtitleNode.frame = CGRect(x: insetH, y: y, width: contentW, height: cachedSubtitleSize.height)
        }
    }
}
