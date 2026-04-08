import AsyncDisplayKit
import UIKit

final class MessageSystemNode: ASDisplayNode {

    private let iconNode = ASImageNode()
    private let textNode = ASTextNode2()
    private let timeNode = ASTextNode2()

    private var cachedTextSize: CGSize = .zero
    private var cachedTimeSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    private static let iconSize: CGFloat = 20
    private static let hPadding: CGFloat = 12
    private static let vPadding: CGFloat = 3
    private static let iconTextGap: CGFloat = 8
    private static let timeGap: CGFloat = 3

    let display: ChatMessageDisplay
    private let interaction: ChatInteraction

    init(display: ChatMessageDisplay, interaction: ChatInteraction) {
        self.display = display
        self.interaction = interaction
        super.init()
        backgroundColor = .clear

        let t = UIColor.theme
        configureIcon(code: display.messageCode, theme: t)

        let parsed = display.parsedContent
        let messageText = parsed.text.trimmingCharacters(in: .whitespacesAndNewlines)

        if messageText.isEmpty {
            let fallback = systemDefaultText(code: display.messageCode)
            textNode.attributedText = NSAttributedString(
                string: fallback,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 13.sf),
                    .foregroundColor: t.text,
                ]
            )
        } else {
            let style = RichTextBuilder.Style(
                bodyFont: .systemFont(ofSize: 13.sf),
                bodyColor: t.text,
                mentionFont: .systemFont(ofSize: 13.sf, weight: .semibold),
                mentionColor: t.textLink,
                mentionBgColor: t.midnightBlue,
                roleMentionColor: t.textRoleLink,
                roleMentionBgColor: t.darkMossGreen,
                linkColor: t.textLink,
                codeBgColor: t.tertiary,
                codeFont: UIFont(name: "Menlo", size: 12.sf) ?? .monospacedSystemFont(ofSize: 12.sf, weight: .regular),
                boldFont: .systemFont(ofSize: 13.sf, weight: .bold),
                headingFonts: [],
                emojiSize: 16.sf,
                emojiImgproxyFitSide: 40
            )
            textNode.attributedText = RichTextBuilder.build(from: parsed, style: style)
        }

        textNode.maximumNumberOfLines = 0
        textNode.isUserInteractionEnabled = false

        let timeText = Self.formatDate(display.message.createdAt)
        timeNode.attributedText = NSAttributedString(
            string: timeText,
            attributes: [
                .font: UIFont.systemFont(ofSize: 11.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        timeNode.maximumNumberOfLines = 1

        addSubnode(iconNode)
        addSubnode(textNode)
        addSubnode(timeNode)
    }

    override func didLoad() {
        super.didLoad()
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        let localPoint = view.convert(point, to: textNode.view)

        guard let attrText = textNode.attributedText, attrText.length > 0 else { return }

        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: textNode.bounds.size)
        let textStorage = NSTextStorage(attributedString: attrText)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let charIndex = layoutManager.characterIndex(
            for: localPoint, in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        guard charIndex < attrText.length else { return }
        let attrs = attrText.attributes(at: charIndex, effectiveRange: nil)

        if let userId = attrs[.mezonMention] as? NSString {
            interaction.onMentionTapped("\(userId)")
        } else if let link = attrs[.mezonLink] as? NSString, let url = URL(string: "\(link)") {
            UIApplication.shared.open(url)
        } else if let channelId = attrs[.mezonHashtag] as? NSString {
            interaction.onHashtagTapped("\(channelId)")
        }
    }

    func measureSize(width: CGFloat) -> CGSize {
        let contentW = width - Self.hPadding * 2 - Self.iconSize - Self.iconTextGap
        cachedTextSize = textNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))
        cachedTimeSize = timeNode.measure(CGSize(width: contentW, height: 20))

        let textBlockH = cachedTextSize.height + Self.timeGap + cachedTimeSize.height
        let minH = max(textBlockH, Self.iconSize)
        let totalH = Self.vPadding + minH + Self.vPadding
        cachedTotalSize = CGSize(width: width, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let iconSz = Self.iconSize
        let iconX = Self.hPadding
        let textX = iconX + iconSz + Self.iconTextGap

        let textBlockH = cachedTextSize.height + Self.timeGap + cachedTimeSize.height
        let contentH = max(textBlockH, iconSz)
        let topY = Self.vPadding

        let iconY = topY + (contentH - iconSz) / 2
        iconNode.frame = CGRect(x: iconX, y: iconY, width: iconSz, height: iconSz)

        let textContentW = bounds.width - textX - Self.hPadding
        textNode.frame = CGRect(x: textX, y: topY, width: textContentW, height: cachedTextSize.height)
        timeNode.frame = CGRect(x: textX, y: topY + cachedTextSize.height + Self.timeGap, width: cachedTimeSize.width, height: cachedTimeSize.height)
    }

    private func configureIcon(code: Int32, theme: ThemeAttributes) {
        let mc = MezonConstants.MessageCode(rawValue: code)
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        let iconColor: UIColor
        let iconImage: UIImage?

        switch mc {
        case .welcome:
            iconImage = UIImage(systemName: "hand.wave.fill", withConfiguration: config)
            iconColor = theme.text
        case .createThread:
            iconImage = UIImage(systemName: "number", withConfiguration: config)
            iconColor = theme.text
        case .createPin:
            iconImage = UIImage(systemName: "pin.fill", withConfiguration: config)
            iconColor = theme.text
        case .auditLog:
            iconImage = UIImage(systemName: "doc.text.magnifyingglass", withConfiguration: config)
            iconColor = theme.text
        case .upcomingEvent:
            iconImage = UIImage(systemName: "calendar", withConfiguration: config)
            iconColor = theme.text
        default:
            iconImage = UIImage(systemName: "info.circle.fill", withConfiguration: config)
            iconColor = theme.text
        }

        iconNode.image = iconImage?.withRenderingMode(.alwaysTemplate)
        iconNode.tintColor = iconColor
        iconNode.contentMode = .scaleAspectFit
    }

    private func systemDefaultText(code: Int32) -> String {
        let mc = MezonConstants.MessageCode(rawValue: code)
        switch mc {
        case .welcome:       return "Welcome!"
        case .createThread:  return "A thread was created."
        case .createPin:     return "A message was pinned."
        case .auditLog:      return "Audit log entry."
        case .upcomingEvent: return "An upcoming event."
        default:             return "System message"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fullFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        return fullFormatter.string(from: date)
    }
}
