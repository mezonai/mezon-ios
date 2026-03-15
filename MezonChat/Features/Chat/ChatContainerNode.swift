import UIKit
import AsyncDisplayKit

struct ChatInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledToBottom: (Bool) -> Void
    var onMessagesReloaded: (() -> Void)?
}

final class ChatContainerNode: ASDisplayNode {

    let tableView: UITableView
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    let channelTitleLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingMoreIndicator = UIActivityIndicatorView(style: .medium)
    let emptyLabel = UILabel()

    private(set) var state: ChatState = .empty
    private let interaction: ChatInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ChatState, NoError>, interaction: ChatInteraction) {
        tableView = UITableView(frame: .zero, style: .plain)
        self.interaction = interaction
        super.init()

        disposables.add(
            (signal |> deliverOnMainQueue).start(next: { [weak self] newState in
                guard let self else { return }
                self.state = newState
                let labelText = newState.channelLabel
                let prefix = labelText.hasPrefix("#") ? "" : "#"
                self.channelTitleLabel.text = "\(prefix)\(labelText)"
                if newState.isLoading { self.loadingIndicator.startAnimating() }
                else { self.loadingIndicator.stopAnimating() }
                if newState.isLoadingMore { self.loadingMoreIndicator.startAnimating() }
                else { self.loadingMoreIndicator.stopAnimating() }
                if let msg = newState.errorMessage { Toast.error(msg) }
                let hasMessagesNow = !newState.messages.isEmpty
                if hasMessagesNow {
                    self.tableView.isHidden = true
                }
                self.tableView.reloadData()
                if hasMessagesNow {
                    self.tableView.layoutIfNeeded()
                    let tv = self.tableView
                    let y = max(-tv.contentInset.top, tv.contentSize.height - tv.bounds.height + tv.contentInset.bottom)
                    tv.contentOffset = CGPoint(x: 0, y: y)
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.tableView.isHidden = false
                    CATransaction.commit()
                }
                self.emptyLabel.isHidden = !(!newState.isLoading && newState.messages.isEmpty)
                if hasMessagesNow {
                    self.interaction.onMessagesReloaded?()
                }
            })
        )
    }

    deinit { disposables.dispose() }

    override func didLoad() {
        super.didLoad()

        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 200.sh
        tableView.register(MessageCell.self, forCellReuseIdentifier: MessageCell.reuseId)
        tableView.register(WelcomeCell.self, forCellReuseIdentifier: WelcomeCell.reuseId)
        tableView.dataSource = self
        tableView.delegate = self

        var backCfg = UIButton.Configuration.plain()
        backCfg.image = UIImage(systemName: "chevron.left")
        backButton.configuration = backCfg
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        channelTitleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        channelTitleLabel.lineBreakMode = .byTruncatingTail

        loadingIndicator.hidesWhenStopped = true
        loadingMoreIndicator.hidesWhenStopped = true
        emptyLabel.font = .systemFont(ofSize: 15.sf)
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true

        for v in [headerView, tableView, loadingIndicator, loadingMoreIndicator, emptyLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        for v in [backButton, channelTitleLabel] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview(v)
        }

        let btnH: CGFloat = 44
        let leftMargin: CGFloat = 12
        let rightMargin: CGFloat = 4
        let gap: CGFloat = 4

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: leftMargin),
            backButton.topAnchor.constraint(equalTo: headerView.topAnchor),
            backButton.widthAnchor.constraint(equalToConstant: btnH),
            backButton.heightAnchor.constraint(equalToConstant: btnH),

            channelTitleLabel.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: gap),
            channelTitleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            channelTitleLabel.heightAnchor.constraint(equalToConstant: btnH),
            channelTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -rightMargin),
        ])
    }

    private var lastLayout: ContainerViewLayout?
    private var lastInputBarHeight: CGFloat = 0

    func updateLayout(layout: ContainerViewLayout, inputBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        lastLayout = layout
        lastInputBarHeight = inputBarHeight
        applyLayout(transition: transition)
    }

    private func applyLayout(transition: ContainedViewLayoutTransition) {
        guard let layout = lastLayout else { return }
        let inputBarHeight = lastInputBarHeight
        let realSafeTop = view.safeAreaInsets.top
        let safeTop = realSafeTop > 20 ? realSafeTop : max(layout.safeInsets.top, 54)

        let fullWidth = view.bounds.width > 0 ? view.bounds.width : layout.size.width
        let headerH: CGFloat = 44
        let headerFrame = CGRect(x: 0, y: safeTop, width: fullWidth, height: headerH)
        transition.updateFrame(view: headerView, frame: headerFrame)

        let tvFrame = CGRect(x: 0, y: headerFrame.maxY, width: fullWidth, height: layout.size.height - headerFrame.maxY - inputBarHeight - layout.intrinsicInsets.bottom)
        transition.updateFrame(view: tableView, frame: tvFrame)

        let liS: CGFloat = 24
        transition.updateFrame(view: loadingIndicator, frame: CGRect(x: (fullWidth - liS) / 2, y: (layout.size.height - liS) / 2, width: liS, height: liS))
        transition.updateFrame(view: loadingMoreIndicator, frame: CGRect(x: (fullWidth - liS) / 2, y: headerFrame.maxY + 12, width: liS, height: liS))
        transition.updateFrame(view: emptyLabel, frame: CGRect(x: 0, y: (layout.size.height - 44) / 2, width: fullWidth, height: 44))
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        headerView.backgroundColor = t.primary
        backButton.tintColor = t.textStrong
        channelTitleLabel.textColor = t.textStrong
        loadingIndicator.color = t.textDisabled
        loadingMoreIndicator.color = t.textDisabled
        emptyLabel.textColor = t.textDisabled
        emptyLabel.text = L(L10n.ChannelMessages.emptyMessages)
    }

    @objc private func backTapped() { interaction.onBackTapped() }
}

extension ChatContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let welcomeRows = state.showWelcome ? 1 : 0
        return welcomeRows + state.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if state.showWelcome, indexPath.row == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: WelcomeCell.reuseId, for: indexPath) as! WelcomeCell
            cell.configure(channelLabel: state.channelLabel)
            return cell
        }
        let messageIndex = state.showWelcome ? indexPath.row - 1 : indexPath.row
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
        cell.configure(display: state.messages[messageIndex])
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 80 { interaction.onScrolledNearTop() }
        let atBottom = scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 100
        interaction.onScrolledToBottom(atBottom)
    }
}

final class WelcomeCell: UITableViewCell {

    static let reuseId = "WelcomeCell"
    private static let iconSize: CGFloat = 70
    private static let verticalPadding: CGFloat = 30
    private static let horizontalPadding: CGFloat = 10

    private let iconContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.theme.secondaryLight
        v.layer.cornerRadius = WelcomeCell.iconSize / 2
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = UIColor.theme.textStrong
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 22.sf, weight: .semibold)
        l.textColor = UIColor.theme.textStrong
        l.textAlignment = .left
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.textColor = UIColor.theme.text
        l.textAlignment = .left
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        iconImageView.image = UIImage(systemName: "number")
        contentView.addSubview(iconContainer)
        iconContainer.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalPadding),
            iconContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.verticalPadding),
            iconContainer.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconSize),
            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 36),
            iconImageView.heightAnchor.constraint(equalToConstant: 36),
            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 10.sh),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalPadding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.horizontalPadding),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10.sh),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.horizontalPadding),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.horizontalPadding),
            subtitleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.verticalPadding),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(channelLabel: String) {
        let name = channelLabel.hasPrefix("#") ? channelLabel : "#\(channelLabel)"
        titleLabel.text = "Welcome to \(name)"
        subtitleLabel.text = "This is the start of the \(name) channel"
    }
}

private final class MessageCellImageHostView: UIView {
    let imageNode = TransformImageNode()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.theme.tertiary
        layer.cornerRadius = 8.swh
        clipsToBounds = true
        imageNode.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageNode.view)
        NSLayoutConstraint.activate([
            imageNode.view.topAnchor.constraint(equalTo: topAnchor),
            imageNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageNode.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageNode.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class MessageCell: UITableViewCell {

    static let reuseId = "MessageCell"
    private static let avatarSize: CGFloat = 40.swh
    private static let contentLeading: CGFloat = 40.swh + 12.sw

    private let avatarContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = .colorAvatarDefault
        v.layer.cornerRadius = 20.swh
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let avatarImageNode = TransformImageNode()

    private let avatarPlaceholder: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        l.textAlignment = .center
        l.textColor = .white
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let nameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let timeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let contentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let imageStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 4.sh
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let reactionsView: ReactionsFlowView = {
        let v = ReactionsFlowView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private var imageHostViews: [MessageCellImageHostView] = []
    private var currentDisplay: ChatMessageDisplay?

    private var nameTopConstraint: NSLayoutConstraint?
    private var contentTopToName: NSLayoutConstraint?
    private var contentTopToCell: NSLayoutConstraint?
    private var imageTopToContent: NSLayoutConstraint?
    private var reactionsTopToImages: NSLayoutConstraint?
    private var reactionsTopToContent: NSLayoutConstraint?
    private var reactionsBottom: NSLayoutConstraint?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatarImageNode.reset()
        imageHostViews.forEach { $0.imageNode.reset() }
        imageHostViews.removeAll()
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reactionsView.clear()
    }

    private func setupLayout() {
        let avatarSize = Self.avatarSize
        let leading = Self.contentLeading

        avatarImageNode.view.translatesAutoresizingMaskIntoConstraints = false
        avatarContainerView.addSubview(avatarImageNode.view)
        avatarContainerView.addSubview(avatarPlaceholder)
        NSLayoutConstraint.activate([
            avatarImageNode.view.topAnchor.constraint(equalTo: avatarContainerView.topAnchor),
            avatarImageNode.view.leadingAnchor.constraint(equalTo: avatarContainerView.leadingAnchor),
            avatarImageNode.view.trailingAnchor.constraint(equalTo: avatarContainerView.trailingAnchor),
            avatarImageNode.view.bottomAnchor.constraint(equalTo: avatarContainerView.bottomAnchor),
        ])
        contentView.addSubview(avatarContainerView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(contentLabel)
        contentView.addSubview(imageStackView)
        contentView.addSubview(reactionsView)

        nameTopConstraint = nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh)
        contentTopToName = contentLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2.sh)
        contentTopToCell = contentLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2.sh)
        imageTopToContent = imageStackView.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6.sh)
        reactionsTopToImages = reactionsView.topAnchor.constraint(equalTo: imageStackView.bottomAnchor, constant: 6.sh)
        reactionsTopToContent = reactionsView.topAnchor.constraint(equalTo: contentLabel.bottomAnchor, constant: 6.sh)
        reactionsBottom = reactionsView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6.sh)

        NSLayoutConstraint.activate([
            avatarContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 6.sw),
            avatarContainerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10.sh),
            avatarContainerView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarContainerView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarPlaceholder.centerXAnchor.constraint(equalTo: avatarContainerView.centerXAnchor),
            avatarPlaceholder.centerYAnchor.constraint(equalTo: avatarContainerView.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -4.sw),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12.sw),
            timeLabel.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor),

            contentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
            contentLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28.sw),

            imageStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
            imageStackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -28.sw),

            reactionsView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: leading),
            reactionsView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12.sw),
        ])

        nameTopConstraint?.isActive = true
        contentTopToName?.isActive = true
        imageTopToContent?.isActive = true
        reactionsTopToImages?.isActive = true
        reactionsBottom?.isActive = true
    }

    func configure(display: ChatMessageDisplay) {
        self.currentDisplay = display
        let t = UIColor.theme
        let isCombine = display.isCombine

        nameLabel.text = display.senderDisplayName
        nameLabel.textColor = t.textRoleLink
        timeLabel.text = formatDate(display.message.createdAt)
        timeLabel.textColor = t.textDisabled

        let textContent = display.message.textContent ?? ""
        contentLabel.text = textContent.isEmpty ? nil : textContent
        contentLabel.textColor = t.textStrong
        contentLabel.isHidden = textContent.isEmpty

        avatarContainerView.isHidden = isCombine
        nameLabel.isHidden = isCombine
        timeLabel.isHidden = isCombine

        contentTopToName?.isActive = false
        contentTopToCell?.isActive = false
        nameTopConstraint?.constant = isCombine ? 0 : 10.sh
        if isCombine {
            contentTopToCell?.isActive = true
        } else {
            contentTopToName?.isActive = true
        }

        if !isCombine {
            if let urlString = display.avatarURL, !urlString.isEmpty {
                avatarPlaceholder.isHidden = true
                let size = Self.avatarSize
                let args = TransformImageArguments(
                    corners: ImageCorners(radius: size / 2),
                    imageSize: CGSize(width: size, height: size),
                    boundingSize: CGSize(width: size, height: size),
                    intrinsicInsets: .zero
                )
                avatarImageNode.setSignal(remoteImageSignal(url: urlString), attemptSynchronously: false)
                let avatarLayout = avatarImageNode.asyncLayout()
                let apply = avatarLayout(args)
                apply()
            } else {
                avatarImageNode.reset()
                avatarPlaceholder.isHidden = false
                avatarPlaceholder.text = String(display.senderDisplayName.prefix(1)).uppercased()
            }
        }

        configureMedia(display.attachments.filter { $0.isMedia })
        configureReactions(display.reactions)

        let hasImages = !imageStackView.arrangedSubviews.isEmpty
        let hasReactions = !display.reactions.isEmpty

        reactionsTopToImages?.isActive = false
        reactionsTopToContent?.isActive = false
        if hasImages {
            reactionsTopToImages?.isActive = true
        } else {
            reactionsTopToContent?.isActive = true
        }
        reactionsView.isHidden = !hasReactions
        reactionsBottom?.constant = hasReactions ? -6.sh : -4.sh
    }

    private func configureMedia(_ media: [ParsedAttachment]) {
        imageStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        imageHostViews.forEach { $0.imageNode.reset() }
        imageHostViews.removeAll()
        guard !media.isEmpty else { return }

        let maxW: CGFloat = UIScreen.main.bounds.width - 80
        let maxH: CGFloat = UIScreen.main.bounds.height * 0.5

        if media.count == 1 {
            let att = media[0]
            var w = CGFloat(att.width ?? 300)
            var h = CGFloat(att.height ?? 200)
            let ratio = min(maxW / w, maxH / h, 1.0)
            w = max(floor(w * ratio), 100)
            h = max(floor(h * ratio), 80)

            if att.isVideo {
                let videoView = makeVideoView(url: att.url, width: w, height: h, display: currentDisplay)
                imageStackView.addArrangedSubview(videoView)
            } else {
                let host = makeImageHostView(width: w, height: h)
                imageStackView.addArrangedSubview(host)
                imageHostViews.append(host)
                setImageSignal(url: att.url, host: host, width: w, height: h)
                addImageTapGesture(to: host, url: att.url, index: 0)
            }
        } else {
            let thumbH: CGFloat = 120.sh
            let mediaItems = Array(media.prefix(4))

            // Row 1: items 0-1
            let row1 = UIStackView()
            row1.axis = .horizontal
            row1.spacing = 4.sw
            row1.distribution = .fillEqually
            row1.translatesAutoresizingMaskIntoConstraints = false
            row1.heightAnchor.constraint(equalToConstant: thumbH).isActive = true
            row1.widthAnchor.constraint(equalToConstant: maxW).isActive = true

            // Row 2: items 2-3 (if any)
            var row2: UIStackView?

            for (i, att) in mediaItems.enumerated() {
                let mediaView: UIView
                if att.isVideo {
                    mediaView = makeVideoView(url: att.url, width: nil, height: thumbH, display: currentDisplay)
                } else {
                    let host = makeImageHostView(width: nil, height: thumbH)
                    imageHostViews.append(host)
                    setImageSignal(url: att.url, host: host, width: nil, height: thumbH, isMultiple: true)
                    addImageTapGesture(to: host, url: att.url, index: i)
                    mediaView = host
                }

                if i == mediaItems.count - 1 && media.count > 4 {
                    addOverlayCount(to: mediaView, count: media.count - 4)
                }

                if i < 2 {
                    row1.addArrangedSubview(mediaView)
                } else {
                    if row2 == nil {
                        let r2 = UIStackView()
                        r2.axis = .horizontal
                        r2.spacing = 4.sw
                        r2.distribution = .fillEqually
                        r2.translatesAutoresizingMaskIntoConstraints = false
                        r2.heightAnchor.constraint(equalToConstant: thumbH).isActive = true
                        r2.widthAnchor.constraint(equalToConstant: maxW).isActive = true
                        row2 = r2
                    }
                    row2?.addArrangedSubview(mediaView)
                }
            }

            imageStackView.addArrangedSubview(row1)
            if let row2 {
                imageStackView.addArrangedSubview(row2)
            }
        }
    }

    private func makeImageHostView(width: CGFloat?, height: CGFloat) -> MessageCellImageHostView {
        let host = MessageCellImageHostView()
        host.translatesAutoresizingMaskIntoConstraints = false
        if let w = width {
            host.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        host.heightAnchor.constraint(equalToConstant: height).isActive = true
        return host
    }

    private func setImageSignal(url: String, host: MessageCellImageHostView, width: CGFloat?, height: CGFloat, isMultiple: Bool = false) {
        let w = width ?? (UIScreen.main.bounds.width - 80) / 2
        let h = height
        let args = TransformImageArguments(
            corners: ImageCorners(radius: 8.swh),
            imageSize: CGSize(width: w, height: h),
            boundingSize: CGSize(width: w, height: h),
            intrinsicInsets: .zero
        )
        let resizeMode: ImageResizeMode = isMultiple ? .fill : .fit
        host.imageNode.setSignal(remoteImageSignal(url: url, resizeMode: resizeMode), attemptSynchronously: false)
        let imageLayout = host.imageNode.asyncLayout()
        let apply = imageLayout(args)
        apply()
    }

    private func makeVideoView(url: String, width: CGFloat?, height: CGFloat, display: ChatMessageDisplay?) -> UIView {
        let container = MessageVideoView(
            urlString: url,
            senderName: display?.senderDisplayName ?? "",
            senderAvatarURL: display?.avatarURL,
            timestamp: display?.message.createdAt
        )
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 8.swh
        container.clipsToBounds = true
        container.backgroundColor = UIColor.theme.tertiary
        if let w = width {
            container.widthAnchor.constraint(equalToConstant: w).isActive = true
        }
        container.heightAnchor.constraint(equalToConstant: height).isActive = true
        return container
    }

    private func addOverlayCount(to view: UIView, count: Int) {
        view.clipsToBounds = true
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "+\(count)"
        label.font = .systemFont(ofSize: 20.sf, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        overlay.addSubview(label)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            label.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
    }

    private func addImageTapGesture(to host: MessageCellImageHostView, url: String, index: Int) {
        host.isUserInteractionEnabled = true
        host.accessibilityIdentifier = url
        host.tag = index
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
        host.addGestureRecognizer(tap)
    }

    @objc private func imageTapped(_ gesture: UITapGestureRecognizer) {
        guard let host = gesture.view as? MessageCellImageHostView else { return }
        let tappedIndex = host.tag

        // Build gallery items from ALL media attachments (images + videos)
        guard let display = currentDisplay else { return }
        let mediaAttachments = display.attachments.filter { $0.isImage || $0.isVideo }
        guard !mediaAttachments.isEmpty else { return }

        let galleryItems: [GalleryItemInfo] = mediaAttachments.enumerated().map { (i, att) in
            let cachedImage: UIImage? = att.isImage && i < imageHostViews.count ? imageHostViews[i].imageNode.image : nil
            return GalleryItemInfo(
                url: att.url,
                image: cachedImage,
                senderName: display.senderDisplayName,
                senderAvatarURL: display.avatarURL,
                timestamp: display.message.createdAt,
                isVideo: att.isVideo
            )
        }

        let gallery = GalleryController(items: galleryItems, initialIndex: tappedIndex)
        if let vc = findViewController() {
            vc.present(gallery, animated: true)
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }

    private func configureReactions(_ reactions: [ParsedReaction]) {
        reactionsView.configure(reactions: reactions)
    }

    private func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        let timeF = DateFormatter()
        timeF.dateFormat = "HH:mm"
        let timeStr = timeF.string(from: date)
        if cal.isDateInToday(date) {
            return String(format: L(L10n.ChannelMessages.todayAt), timeStr)
        }
        if cal.isDateInYesterday(date) {
            return String(format: L(L10n.ChannelMessages.yesterdayAt), timeStr)
        }
        let fullF = DateFormatter()
        fullF.dateFormat = "dd/MM/yyyy, HH:mm"
        return fullF.string(from: date)
    }
}

final class ReactionsFlowView: UIView {
    private var pillViews: [UIView] = []

    func clear() {
        pillViews.forEach { $0.removeFromSuperview() }
        pillViews.removeAll()
    }

    func configure(reactions: [ParsedReaction]) {
        clear()
        guard !reactions.isEmpty else {
            isHidden = true
            return
        }
        isHidden = false

        for reaction in reactions {
            let pill = ReactionPillView(reaction: reaction)
            pill.translatesAutoresizingMaskIntoConstraints = false
            addSubview(pill)
            pillViews.append(pill)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let spacing: CGFloat = 6.sw
        let maxWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 80
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for pill in pillViews {
            pill.sizeToFit()
            let pillSize = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if x + pillSize.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            pill.frame = CGRect(x: x, y: y, width: pillSize.width, height: pillSize.height)
            x += pillSize.width + spacing
            rowHeight = max(rowHeight, pillSize.height)
        }

        let totalHeight = y + rowHeight
        if abs(bounds.height - totalHeight) > 1 {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: CGSize {
        let spacing: CGFloat = 6.sw
        let maxWidth = superview?.bounds.width ?? UIScreen.main.bounds.width - 80
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for pill in pillViews {
            let s = pill.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
            if x + s.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }
}

private final class ReactionPillView: UIView {
    private static let emojiSize: CGFloat = 20
    private let emojiImageView = UIImageView()
    private let emojiFallbackLabel = UILabel()
    private let countLabel = UILabel()
    private var imageTask: URLSessionDataTask?

    init(reaction: ParsedReaction) {
        super.init(frame: .zero)

        layer.cornerRadius = 5.swh
        clipsToBounds = true

        if reaction.isMe {
            backgroundColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.2)
            layer.borderWidth = 1
            layer.borderColor = UIColor(red: 0.35, green: 0.45, blue: 0.95, alpha: 0.6).cgColor
        } else {
            backgroundColor = UIColor.theme.secondary
        }

        emojiImageView.contentMode = .scaleAspectFit
        emojiImageView.clipsToBounds = true
        emojiImageView.translatesAutoresizingMaskIntoConstraints = false

        emojiFallbackLabel.font = .systemFont(ofSize: 16.sf, weight: .regular)
        emojiFallbackLabel.textAlignment = .center
        emojiFallbackLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.text = "\(reaction.count)"
        countLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        countLabel.textColor = UIColor.theme.textStrong
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(emojiImageView)
        addSubview(emojiFallbackLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            emojiImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6.sw),
            emojiImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            emojiImageView.widthAnchor.constraint(equalToConstant: Self.emojiSize),
            emojiImageView.heightAnchor.constraint(equalToConstant: Self.emojiSize),

            emojiFallbackLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6.sw),
            emojiFallbackLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emojiFallbackLabel.widthAnchor.constraint(equalToConstant: Self.emojiSize),
            emojiFallbackLabel.heightAnchor.constraint(equalToConstant: Self.emojiSize),

            countLabel.leadingAnchor.constraint(equalTo: emojiImageView.trailingAnchor, constant: 4.sw),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6.sw),

            heightAnchor.constraint(equalToConstant: 28.sh),
        ])

        let fallbackText = !reaction.emoji.isEmpty ? reaction.emoji : "?"
        emojiFallbackLabel.text = fallbackText
        let url = MezonConfig.emojiImageURL(emojiId: reaction.emojiId)
        if let url = url {
            emojiFallbackLabel.isHidden = true
            loadEmojiImage(url: url) { [weak self] success in
                DispatchQueue.main.async {
                    self?.emojiFallbackLabel.isHidden = success
                }
            }
        } else {
            emojiImageView.isHidden = true
            emojiFallbackLabel.isHidden = false
        }
    }

    private func loadEmojiImage(url: URL, onDone: @escaping (Bool) -> Void) {
        imageTask = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let img = data.flatMap { UIImage.decodeImage(from: $0) }
            DispatchQueue.main.async {
                self?.emojiImageView.image = img
                onDone(img != nil)
            }
        }
        imageTask?.resume()
    }

    deinit {
        imageTask?.cancel()
    }

    required init?(coder: NSCoder) { fatalError() }
}

import AVFoundation

final class MessageVideoView: UIView {
    private let thumbnailNode = TransformImageNode()
    private let playButton = UIImageView()
    private let urlString: String
    private let senderName: String
    private let senderAvatarURL: String?
    private let timestamp: Date?

    init(urlString: String, senderName: String = "", senderAvatarURL: String? = nil, timestamp: Date? = nil) {
        self.urlString = urlString
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.timestamp = timestamp
        super.init(frame: .zero)

        // Thumbnail via TransformImageNode (async, cached)
        thumbnailNode.contentAnimations = [.firstUpdate]
        thumbnailNode.view.translatesAutoresizingMaskIntoConstraints = false
        thumbnailNode.view.contentMode = .scaleAspectFill
        thumbnailNode.view.clipsToBounds = true
        addSubview(thumbnailNode.view)

        // Play button overlay
        let playBg = UIView()
        playBg.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        playBg.layer.cornerRadius = 24
        playBg.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playBg)

        let playConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        playButton.image = UIImage(systemName: "play.fill", withConfiguration: playConfig)
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playBg.addSubview(playButton)

        NSLayoutConstraint.activate([
            thumbnailNode.view.topAnchor.constraint(equalTo: topAnchor),
            thumbnailNode.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailNode.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailNode.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            playBg.centerXAnchor.constraint(equalTo: centerXAnchor),
            playBg.centerYAnchor.constraint(equalTo: centerYAnchor),
            playBg.widthAnchor.constraint(equalToConstant: 48),
            playBg.heightAnchor.constraint(equalToConstant: 48),
            playButton.centerXAnchor.constraint(equalTo: playBg.centerXAnchor, constant: 2),
            playButton.centerYAnchor.constraint(equalTo: playBg.centerYAnchor),
        ])

        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        // Load thumbnail via signal pipeline
        thumbnailNode.setSignal(videoThumbnailSignal(url: urlString, resizeMode: .fill))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let args = TransformImageArguments(
            corners: ImageCorners(radius: 8),
            imageSize: bounds.size,
            boundingSize: bounds.size,
            intrinsicInsets: .zero
        )
        let layout = thumbnailNode.asyncLayout()
        let apply = layout(args)
        apply()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        guard let url = URL(string: urlString) else { return }
        guard let vc = findViewController() else { return }
        let galleryItem = GalleryItemInfo(
            url: urlString,
            senderName: senderName,
            senderAvatarURL: senderAvatarURL,
            timestamp: timestamp,
            isVideo: true
        )
        let gallery = GalleryController(items: [galleryItem], initialIndex: 0)
        vc.present(gallery, animated: true)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }
}

