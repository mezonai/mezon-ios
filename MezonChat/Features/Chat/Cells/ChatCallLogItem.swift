import AsyncDisplayKit
import UIKit

final class MessageCallLogNode: ASDisplayNode {

    private let containerNode = ASDisplayNode()
    private let iconNode = ASImageNode()
    private let titleNode = ASTextNode2()
    private let descriptionNode = ASTextNode2()

    private var cachedTitleSize: CGSize = .zero
    private var cachedDescSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero

    private static let iconSize: CGFloat = 16
    private static let containerPadding: CGFloat = 10
    private static let spacing: CGFloat = 4

    func configure(callLog: CallLogData, isMe: Bool, senderName: String, contentText: String) {
        let t = UIColor.theme

        containerNode.backgroundColor = t.tertiary
        containerNode.cornerRadius = 10
        containerNode.clipsToBounds = true


        let title = Self.titleText(callLog: callLog, isMe: isMe, senderName: senderName)
        let isFailed = Self.isFailedCall(callLog.callLogType, isMe: isMe)
        titleNode.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 14.sf, weight: .semibold),
                .foregroundColor: isFailed ? UIColor.systemRed : t.textStrong,
            ]
        )
        titleNode.maximumNumberOfLines = 2


        let (iconName, iconColor) = Self.iconInfo(callLog: callLog, isMe: isMe)
        iconNode.image = UIImage(systemName: iconName)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        )
        iconNode.tintColor = iconColor
        iconNode.contentMode = .scaleAspectFit


        let desc: String
        if callLog.callLogType == .finishCall && !contentText.isEmpty {
            desc = contentText
        } else {
            desc = callLog.isVideo ? "Video Call" : "Audio Call"
        }
        descriptionNode.attributedText = NSAttributedString(
            string: desc,
            attributes: [
                .font: UIFont.systemFont(ofSize: 12.sf),
                .foregroundColor: t.textDisabled,
            ]
        )
        descriptionNode.maximumNumberOfLines = 1

        addSubnode(containerNode)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(iconNode)
        containerNode.addSubnode(descriptionNode)
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let pad = Self.containerPadding
        let iconSz = Self.iconSize
        let contentW = maxWidth - pad * 2

        cachedTitleSize = titleNode.measure(CGSize(width: contentW, height: .greatestFiniteMagnitude))

        let descContentW = contentW - iconSz - 6
        cachedDescSize = descriptionNode.measure(CGSize(width: descContentW, height: .greatestFiniteMagnitude))

        let innerH = cachedTitleSize.height + Self.spacing + max(cachedDescSize.height, iconSz)
        let totalH = innerH + pad * 2
        cachedTotalSize = CGSize(width: maxWidth, height: totalH)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let pad = Self.containerPadding
        let iconSz = Self.iconSize

        containerNode.frame = bounds

        var y = pad
        titleNode.frame = CGRect(x: pad, y: y, width: cachedTitleSize.width, height: cachedTitleSize.height)
        y += cachedTitleSize.height + Self.spacing

        let descRowH = max(cachedDescSize.height, iconSz)
        iconNode.frame = CGRect(x: pad, y: y + (descRowH - iconSz) / 2, width: iconSz, height: iconSz)
        descriptionNode.frame = CGRect(x: pad + iconSz + 6, y: y + (descRowH - cachedDescSize.height) / 2, width: cachedDescSize.width, height: cachedDescSize.height)
    }


    private static func titleText(callLog: CallLogData, isMe: Bool, senderName: String) -> String {
        switch callLog.callLogType {
        case .startCall:
            let callType = callLog.isVideo ? "Video Call" : "Audio Call"
            return "Started \(callType) with \(senderName)"
        case .finishCall:
            return isMe ? "Outgoing Call" : "Incoming Call"
        case .timeoutCall:
            return isMe ? "Outgoing Call" : "Missed Call"
        case .rejectCall:
            return isMe ? "Receiver Rejected" : "You Rejected"
        case .cancelCall:
            return isMe ? "Cancelled Call" : "Missed Call"
        }
    }

    private static func isFailedCall(_ type: CallLogType, isMe: Bool) -> Bool {
        switch type {
        case .timeoutCall: return !isMe
        case .rejectCall: return true
        case .cancelCall: return true
        case .finishCall, .startCall: return false
        }
    }

    private static func iconInfo(callLog: CallLogData, isMe: Bool) -> (name: String, color: UIColor) {
        switch callLog.callLogType {
        case .timeoutCall:
            return isMe
                ? ("phone.arrow.up.right", UIColor.theme.textDisabled)
                : ("phone.arrow.down.left", .systemRed)
        case .rejectCall:
            return ("phone.down.fill", .systemRed)
        case .cancelCall:
            return isMe
                ? ("phone.down.fill", .systemRed)
                : ("phone.arrow.down.left", .systemRed)
        case .finishCall, .startCall:
            return isMe
                ? ("phone.arrow.up.right", UIColor.theme.textDisabled)
                : ("phone.arrow.down.left", UIColor.theme.textDisabled)
        }
    }
}
