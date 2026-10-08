import AsyncDisplayKit
import UIKit

final class BotCommandStatusNode: ASDisplayNode {

    private static let glyphWidth: CGFloat = 14.sf
    private static let itemGap: CGFloat = 6.sw
    private static let dismissSide: CGFloat = 24.sf
    private static let rowGap: CGFloat = 6.sh
    private static let waitingColor = UIColor(rgb: 0xa78bfa)

    var onAction: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let glyphNode = ASTextNode2()
    private let labelNode = ASTextNode2()
    private let actionButton = ASButtonNode()
    private let dismissButton = ASButtonNode()

    private var hasAction = false
    private var actionOnNewLine = false
    private var cachedGlyphSize: CGSize = .zero
    private var cachedLabelSize: CGSize = .zero
    private var cachedActionSize: CGSize = .zero
    private var cachedSize: CGSize = .zero

    override init() {
        super.init()
        automaticallyManagesSubnodes = false

        labelNode.maximumNumberOfLines = 0
        actionButton.contentEdgeInsets = UIEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        actionButton.cornerRadius = 4
        actionButton.borderWidth = 1
        actionButton.addTarget(self, action: #selector(actionTapped), forControlEvents: .touchUpInside)
        dismissButton.addTarget(self, action: #selector(dismissTapped), forControlEvents: .touchUpInside)
        dismissButton.hitTestSlop = UIEdgeInsets(top: -8, left: -8, bottom: -8, right: -8)

        addSubnode(glyphNode)
        addSubnode(labelNode)
        addSubnode(actionButton)
        addSubnode(dismissButton)
    }

    func configure(_ command: BotCommandDisplay) {
        let t = UIColor.theme
        let usesFallbackName = command.botName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let botName = usesFallbackName ? L(L10n.BotCommand.theBot) : command.botName

        func statusText(_ key: String) -> String {
            let text = key == L10n.BotCommand.failed ? L(key) : L(key, botName)
            guard usesFallbackName, let first = text.first else { return text }
            return first.uppercased() + text.dropFirst()
        }

        let glyph: String
        let glyphColor: UIColor
        let label: String
        let actionTitle: String?
        switch command.status {
        case .waiting:
            glyph = "…"
            glyphColor = Self.waitingColor
            label = statusText(L10n.BotCommand.waiting)
            actionTitle = nil
        case .answered:
            glyph = "✓"
            glyphColor = t.textSuccess
            label = statusText(L10n.BotCommand.answered)
            actionTitle = L(L10n.BotCommand.viewReply)
        case .noResponse:
            glyph = "!"
            glyphColor = t.textWarning
            label = statusText(L10n.BotCommand.noResponse)
            actionTitle = command.resendable ? L(L10n.BotCommand.resend) : nil
        case .failed:
            glyph = "✕"
            glyphColor = .mezonError
            label = statusText(L10n.BotCommand.failed)
            actionTitle = command.resendable ? L(L10n.BotCommand.retry) : nil
        }

        glyphNode.attributedText = NSAttributedString(
            string: glyph,
            attributes: [
                .font: UIFont.systemFont(ofSize: 13.sf, weight: .bold),
                .foregroundColor: glyphColor
            ]
        )
        let isWaiting = command.status == .waiting
        labelNode.attributedText = NSAttributedString(
            string: label,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 12.sf, weight: .regular),
                .foregroundColor: isWaiting ? t.textDisabled : t.text
            ]
        )

        hasAction = actionTitle != nil
        actionButton.isHidden = !hasAction
        if let actionTitle {
            actionButton.setAttributedTitle(
                NSAttributedString(
                    string: actionTitle,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: 12.sf, weight: .medium),
                        .foregroundColor: t.text
                    ]
                ),
                for: .normal
            )
            actionButton.borderColor = t.border.cgColor
        }

        let dismissIcon = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10.sf, weight: .semibold)
        )?.withTintColor(t.textDisabled, renderingMode: .alwaysOriginal)
        dismissButton.setImage(dismissIcon, for: .normal)
        setNeedsLayout()
    }

    func measure(maxWidth: CGFloat) -> CGSize {
        let labelMaxWidth = max(1, maxWidth - Self.glyphWidth - Self.itemGap * 2 - Self.dismissSide)
        cachedGlyphSize = glyphNode.measure(CGSize(width: Self.glyphWidth, height: .greatestFiniteMagnitude))
        let singleLineLabel = labelNode.measure(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        cachedActionSize = hasAction
            ? actionButton.measure(CGSize(width: labelMaxWidth, height: .greatestFiniteMagnitude))
            : .zero

        actionOnNewLine = hasAction && singleLineLabel.width + Self.itemGap + cachedActionSize.width > labelMaxWidth
        let labelWidthBudget = hasAction && !actionOnNewLine
            ? labelMaxWidth - Self.itemGap - cachedActionSize.width
            : labelMaxWidth
        cachedLabelSize = labelNode.measure(CGSize(width: max(1, labelWidthBudget), height: .greatestFiniteMagnitude))

        var firstRowHeight = max(cachedLabelSize.height, cachedGlyphSize.height, Self.dismissSide)
        if hasAction && !actionOnNewLine {
            firstRowHeight = max(firstRowHeight, cachedActionSize.height)
        }
        var height = firstRowHeight
        if actionOnNewLine {
            height += Self.rowGap + cachedActionSize.height
        }
        cachedSize = CGSize(width: maxWidth, height: ceil(height))
        return cachedSize
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let firstRowHeight: CGFloat = {
            var h = max(cachedLabelSize.height, cachedGlyphSize.height, Self.dismissSide)
            if hasAction && !actionOnNewLine {
                h = max(h, cachedActionSize.height)
            }
            return h
        }()

        glyphNode.frame = CGRect(
            x: (Self.glyphWidth - cachedGlyphSize.width) / 2,
            y: (firstRowHeight - cachedGlyphSize.height) / 2,
            width: cachedGlyphSize.width,
            height: cachedGlyphSize.height
        )
        let labelX = Self.glyphWidth + Self.itemGap
        labelNode.frame = CGRect(
            x: labelX,
            y: (firstRowHeight - cachedLabelSize.height) / 2,
            width: cachedLabelSize.width,
            height: cachedLabelSize.height
        )
        if hasAction {
            if actionOnNewLine {
                actionButton.frame = CGRect(
                    x: labelX,
                    y: firstRowHeight + Self.rowGap,
                    width: cachedActionSize.width,
                    height: cachedActionSize.height
                )
            } else {
                actionButton.frame = CGRect(
                    x: labelX + cachedLabelSize.width + Self.itemGap,
                    y: (firstRowHeight - cachedActionSize.height) / 2,
                    width: cachedActionSize.width,
                    height: cachedActionSize.height
                )
            }
        } else {
            actionButton.frame = .zero
        }
        dismissButton.frame = CGRect(
            x: width - Self.dismissSide,
            y: (firstRowHeight - Self.dismissSide) / 2,
            width: Self.dismissSide,
            height: Self.dismissSide
        )
    }

    @objc private func actionTapped() {
        onAction?()
    }

    @objc private func dismissTapped() {
        onDismiss?()
    }
}
