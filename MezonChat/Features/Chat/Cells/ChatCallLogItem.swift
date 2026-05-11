import AsyncDisplayKit
import UIKit

final class MessageCallLogNode: ASDisplayNode {

    static let redStrong = UIColor(red: 198.0/255, green: 30.0/255, blue: 27.0/255, alpha: 1.0)

    private static let containerHorizontalInset: CGFloat = 4.sw
    private static let wrapperPadding: CGFloat = 10.sw
    private static let descriptionTopSpacing: CGFloat = 6.sh
    private static let descriptionGap: CGFloat = 4.sw
    private static let iconTopOffset: CGFloat = 2.sh
    private static let iconSize: CGFloat = 17.sf
    private static let dividerHeight: CGFloat = 1
    private static let callBackVerticalPadding: CGFloat = 8.sh
    private static let containerCornerRadius: CGFloat = 10
    private static let titleFontSize: CGFloat = 14.sf
    private static let descriptionFontSize: CGFloat = 12.sf
    private static let callBackFontSize: CGFloat = 12.sf

    private let containerNode = ASDisplayNode()
    private let titleNode = ASTextNode2()
    private let iconNode = ASImageNode()
    private let descriptionNode = ASTextNode2()
    private let dividerNode = ASDisplayNode()
    private let callBackButton = ASButtonNode()

    private var cachedTitleSize: CGSize = .zero
    private var cachedDescriptionSize: CGSize = .zero
    private var cachedCallBackSize: CGSize = .zero
    private var cachedTotalSize: CGSize = .zero
    private var showsCallBack: Bool = false
    private var hasTitle: Bool = false

    var onCallBackTapped: (() -> Void)?

    override init() {
        super.init()
        automaticallyManagesSubnodes = false

        addSubnode(containerNode)
        containerNode.addSubnode(titleNode)
        containerNode.addSubnode(iconNode)
        containerNode.addSubnode(descriptionNode)
        containerNode.addSubnode(dividerNode)
        containerNode.addSubnode(callBackButton)

        iconNode.contentMode = .scaleAspectFit
        callBackButton.addTarget(self, action: #selector(handleCallBackTapped), forControlEvents: .touchUpInside)
    }

    func configure(callLog: CallLogData, isMe: Bool, senderName: String, contentText: String, isGroupChat: Bool = false) {
        let t = UIColor.theme

        containerNode.backgroundColor = t.border
        containerNode.cornerRadius = Self.containerCornerRadius
        containerNode.clipsToBounds = true

        let title = Self.titleText(callLog: callLog, isMe: isMe, senderName: senderName, isGroupChat: isGroupChat)
        hasTitle = !title.isEmpty
        let isFailed = Self.isFailedTitle(callLog.callLogType)
        if hasTitle {
            titleNode.attributedText = NSAttributedString(
                string: title,
                attributes: [
                    .font: UIFont.systemFont(ofSize: Self.titleFontSize, weight: .bold),
                    .foregroundColor: isFailed ? Self.redStrong : t.text,
                ]
            )
            titleNode.maximumNumberOfLines = 0
            titleNode.isHidden = false
        } else {
            titleNode.attributedText = nil
            titleNode.isHidden = true
        }

        if let (imageName, color) = Self.iconInfo(callLog: callLog, isMe: isMe) {
            iconNode.image = UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate)
            iconNode.tintColor = color
            iconNode.isHidden = false
        } else {
            iconNode.image = nil
            iconNode.isHidden = true
        }

        let description = Self.descriptionText(callLog: callLog, contentText: contentText)
        descriptionNode.attributedText = NSAttributedString(
            string: description,
            attributes: [
                .font: UIFont.systemFont(ofSize: Self.descriptionFontSize),
                .foregroundColor: t.textDisabled,
            ]
        )
        descriptionNode.maximumNumberOfLines = 1

        showsCallBack = Self.shouldShowCallBack(callLogType: callLog.callLogType, isMe: isMe, isGroupChat: isGroupChat)
        if showsCallBack {
            dividerNode.backgroundColor = t.secondaryWeight
            dividerNode.isHidden = false
            callBackButton.isHidden = false
            callBackButton.setAttributedTitle(
                NSAttributedString(
                    string: L(L10n.CallLog.callBack).uppercased(),
                    attributes: [
                        .font: UIFont.systemFont(ofSize: Self.callBackFontSize, weight: .bold),
                        .foregroundColor: t.textLink,
                    ]
                ),
                for: .normal
            )
        } else {
            dividerNode.isHidden = true
            callBackButton.isHidden = true
        }
    }

    func measureSize(maxWidth: CGFloat) -> CGSize {
        let outerInset = Self.containerHorizontalInset
        let containerWidth = max(maxWidth - outerInset * 2, 1)
        let pad = Self.wrapperPadding
        let contentWidth = max(containerWidth - pad * 2, 1)

        if hasTitle {
            cachedTitleSize = titleNode.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        } else {
            cachedTitleSize = .zero
        }

        let descMaxWidth = max(contentWidth - Self.iconSize - Self.descriptionGap, 1)
        cachedDescriptionSize = descriptionNode.measure(CGSize(width: descMaxWidth, height: .greatestFiniteMagnitude))

        let descriptionRowHeight = max(cachedDescriptionSize.height, Self.iconSize + Self.iconTopOffset)
        var wrapperHeight = pad * 2 + descriptionRowHeight
        if hasTitle {
            wrapperHeight += cachedTitleSize.height + Self.descriptionTopSpacing
        }

        var totalHeight = wrapperHeight
        if showsCallBack {
            cachedCallBackSize = callBackButton.measure(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
            let callBackRowHeight = Self.callBackVerticalPadding * 2 + max(cachedCallBackSize.height, Self.callBackFontSize)
            totalHeight += Self.dividerHeight + callBackRowHeight
        } else {
            cachedCallBackSize = .zero
        }

        cachedTotalSize = CGSize(width: maxWidth, height: totalHeight)
        return cachedTotalSize
    }

    override func layout() {
        super.layout()
        let outerInset = Self.containerHorizontalInset
        let pad = Self.wrapperPadding
        let containerFrame = CGRect(
            x: outerInset,
            y: 0,
            width: max(bounds.width - outerInset * 2, 0),
            height: bounds.height
        )
        containerNode.frame = containerFrame

        var y = pad

        if hasTitle {
            titleNode.frame = CGRect(
                x: pad,
                y: y,
                width: containerFrame.width - pad * 2,
                height: cachedTitleSize.height
            )
            y += cachedTitleSize.height + Self.descriptionTopSpacing
        }

        let descriptionRowHeight = max(cachedDescriptionSize.height, Self.iconSize + Self.iconTopOffset)
        iconNode.frame = CGRect(
            x: pad,
            y: y + Self.iconTopOffset,
            width: Self.iconSize,
            height: Self.iconSize
        )
        descriptionNode.frame = CGRect(
            x: pad + Self.iconSize + Self.descriptionGap,
            y: y + (descriptionRowHeight - cachedDescriptionSize.height) / 2,
            width: max(containerFrame.width - pad * 2 - Self.iconSize - Self.descriptionGap, 0),
            height: cachedDescriptionSize.height
        )
        y += descriptionRowHeight + pad

        if showsCallBack {
            dividerNode.frame = CGRect(x: 0, y: y, width: containerFrame.width, height: Self.dividerHeight)
            y += Self.dividerHeight
            let callBackRowHeight = Self.callBackVerticalPadding * 2 + max(cachedCallBackSize.height, Self.callBackFontSize)
            callBackButton.frame = CGRect(
                x: 0,
                y: y,
                width: containerFrame.width,
                height: callBackRowHeight
            )
        } else {
            dividerNode.frame = .zero
            callBackButton.frame = .zero
        }
    }

    @objc private func handleCallBackTapped() {
        onCallBackTapped?()
    }

    private static func titleText(callLog: CallLogData, isMe: Bool, senderName: String, isGroupChat: Bool) -> String {
        switch callLog.callLogType {
        case .timeoutCall:
            return isMe ? L(L10n.CallLog.outGoingCall) : L(L10n.CallLog.missed)
        case .rejectCall:
            return isMe ? L(L10n.CallLog.receiverRejected) : L(L10n.CallLog.youRejected)
        case .cancelCall:
            return isMe ? L(L10n.CallLog.cancel) : L(L10n.CallLog.missed)
        case .finishCall:
            return isMe ? L(L10n.CallLog.outGoingCall) : L(L10n.CallLog.incomingCall)
        case .startCall:
            if isGroupChat {
                return L(L10n.CallLog.startGroupCall, senderName)
            }
            return callLog.isVideo
                ? L(L10n.CallLog.startVideoCall, senderName)
                : L(L10n.CallLog.startAudioCall, senderName)
        }
    }

    private static func descriptionText(callLog: CallLogData, contentText: String) -> String {
        if callLog.callLogType == .finishCall {
            return contentText
        }
        return callLog.isVideo ? L(L10n.CallLog.videoCall) : L(L10n.CallLog.audioCall)
    }

    private static func isFailedTitle(_ type: CallLogType) -> Bool {
        switch type {
        case .timeoutCall, .rejectCall, .cancelCall:
            return true
        case .startCall, .finishCall:
            return false
        }
    }

    private static func iconInfo(callLog: CallLogData, isMe: Bool) -> (name: String, color: UIColor)? {
        let t = UIColor.theme
        switch callLog.callLogType {
        case .timeoutCall:
            return isMe
                ? ("CallOutGoingIcon", t.textDisabled)
                : ("CallMissIcon", redStrong)
        case .rejectCall:
            return ("CallCancelIcon", redStrong)
        case .cancelCall:
            return isMe
                ? ("CallCancelIcon", redStrong)
                : ("CallMissIcon", redStrong)
        case .finishCall, .startCall:
            return isMe
                ? ("CallOutGoingIcon", t.textDisabled)
                : ("CallInComingIcon", t.textDisabled)
        }
    }

    private static func shouldShowCallBack(callLogType: CallLogType, isMe: Bool, isGroupChat: Bool) -> Bool {
        if isGroupChat { return false }
        switch callLogType {
        case .startCall:
            return false
        case .timeoutCall, .finishCall:
            return !isMe
        case .rejectCall, .cancelCall:
            return true
        }
    }
}
