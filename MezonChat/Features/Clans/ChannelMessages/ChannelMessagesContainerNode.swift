import UIKit
import AsyncDisplayKit

struct ChannelMessagesInteraction {
    let onBackTapped: () -> Void
    let onSearchTapped: () -> Void
    let onHistoryTapped: () -> Void
    let onMenuTapped: () -> Void
    let onScrolledNearTop: () -> Void
    let onScrolledToBottom: (Bool) -> Void
}

final class ChannelMessagesContainerNode: ASDisplayNode {

    let tableView: UITableView
    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    let channelTitleLabel = UILabel()
    private let loadingIndicator = UIActivityIndicatorView(style: .medium)
    private let loadingMoreIndicator = UIActivityIndicatorView(style: .medium)
    let emptyLabel = UILabel()

    private(set) var state: ChannelMessagesState = .empty
    private let interaction: ChannelMessagesInteraction
    private let disposables = DisposableSet()

    init(signal: Signal<ChannelMessagesState, NoError>, interaction: ChannelMessagesInteraction) {
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
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !(!newState.isLoading && newState.messages.isEmpty)
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
        tableView.dataSource = self
        tableView.delegate = self

        var backCfg = UIButton.Configuration.plain()
        backCfg.image = UIImage(systemName: "chevron.left")
        backButton.configuration = backCfg
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        channelTitleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
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

        let headerH: CGFloat = 44.sh
        let headerFrame = CGRect(x: 0, y: safeTop, width: layout.size.width, height: headerH)
        transition.updateFrame(view: headerView, frame: headerFrame)

        let tvFrame = CGRect(x: 0, y: headerFrame.maxY, width: layout.size.width, height: layout.size.height - headerFrame.maxY - inputBarHeight - layout.intrinsicInsets.bottom)
        transition.updateFrame(view: tableView, frame: tvFrame)

        let liS: CGFloat = 24.swh
        transition.updateFrame(view: loadingIndicator, frame: CGRect(x: (layout.size.width - liS) / 2, y: (layout.size.height - liS) / 2, width: liS, height: liS))
        transition.updateFrame(view: loadingMoreIndicator, frame: CGRect(x: (layout.size.width - liS) / 2, y: headerFrame.maxY + 12.sh, width: liS, height: liS))
        transition.updateFrame(view: emptyLabel, frame: CGRect(x: 0, y: (layout.size.height - 44.sh) / 2, width: layout.size.width, height: 44.sh))

        let btnH: CGFloat = 44.swh
        transition.updateFrame(view: backButton, frame: CGRect(x: 12.sw, y: 0, width: btnH, height: headerH))
        transition.updateFrame(view: channelTitleLabel, frame: CGRect(x: 12.sw + btnH + 4.sw, y: 0, width: layout.size.width - 12.sw - btnH - 4.sw - 60.sw, height: headerH))
    }

    override func layout() {
        super.layout()
        applyLayout(transition: .immediate)
    }

    func applyTheme() {
        let t = UIColor.theme
        backgroundColor = t.primary
        headerView.backgroundColor = t.secondary
        backButton.tintColor = t.textStrong
        channelTitleLabel.textColor = t.textStrong
        loadingIndicator.color = t.textDisabled
        loadingMoreIndicator.color = t.textDisabled
        emptyLabel.textColor = t.textDisabled
        emptyLabel.text = L(L10n.ChannelMessages.emptyMessages)
    }

    @objc private func backTapped() { interaction.onBackTapped() }
}

extension ChannelMessagesContainerNode: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        state.messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MessageCell.reuseId, for: indexPath) as! MessageCell
        cell.configure(display: state.messages[indexPath.row])
        return cell
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < 80 { interaction.onScrolledNearTop() }
        let atBottom = scrollView.contentOffset.y + scrollView.bounds.height >= scrollView.contentSize.height - 100
        interaction.onScrolledToBottom(atBottom)
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

    func configure(display: ChannelMessageDisplay) {
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
                avatarImageNode.setArguments(args)
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

        let maxW: CGFloat = UIScreen.main.bounds.width - 150
        let maxH: CGFloat = UIScreen.main.bounds.height * 0.3

        if media.count == 1 {
            let att = media[0]
            var w = CGFloat(att.width ?? 300)
            var h = CGFloat(att.height ?? 200)
            let ratio = min(maxW / w, maxH / h, 1.0)
            w = max(floor(w * ratio), 100)
            h = max(floor(h * ratio), 80)

            if att.isVideo {
                let videoView = makeVideoView(url: att.url, width: w, height: h)
                imageStackView.addArrangedSubview(videoView)
            } else {
                let host = makeImageHostView(width: w, height: h)
                imageStackView.addArrangedSubview(host)
                imageHostViews.append(host)
                setImageSignal(url: att.url, host: host, width: w, height: h)
                addImageTapGesture(to: host, url: att.url)
            }
        } else {
            let gridRow = UIStackView()
            gridRow.axis = .horizontal
            gridRow.spacing = 4.sw
            gridRow.distribution = .fillEqually

            let halfH = floor(maxH / 2)
            gridRow.heightAnchor.constraint(equalToConstant: halfH).isActive = true

            for (i, att) in media.prefix(4).enumerated() {
                let mediaView: UIView
                if att.isVideo {
                    mediaView = makeVideoView(url: att.url, width: nil, height: halfH)
                } else {
                    let host = makeImageHostView(width: nil, height: halfH)
                    imageHostViews.append(host)
                    setImageSignal(url: att.url, host: host, width: nil, height: halfH)
                    addImageTapGesture(to: host, url: att.url)
                    mediaView = host
                }

                if i == 3 && media.count > 4 {
                    addOverlayCount(to: mediaView, count: media.count - 4)
                }

                if i < 2 {
                    gridRow.addArrangedSubview(mediaView)
                } else if i == 2 {
                    imageStackView.addArrangedSubview(gridRow)
                    let gridRow2 = UIStackView()
                    gridRow2.axis = .horizontal
                    gridRow2.spacing = 4.sw
                    gridRow2.distribution = .fillEqually
                    gridRow2.heightAnchor.constraint(equalToConstant: halfH).isActive = true
                    gridRow2.addArrangedSubview(mediaView)
                    gridRow2.tag = 999
                    imageStackView.addArrangedSubview(gridRow2)
                } else {
                    if let row2 = imageStackView.arrangedSubviews.last(where: { $0.tag == 999 }) as? UIStackView {
                        row2.addArrangedSubview(mediaView)
                    }
                }
            }
            if imageStackView.arrangedSubviews.isEmpty {
                imageStackView.addArrangedSubview(gridRow)
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

    private func setImageSignal(url: String, host: MessageCellImageHostView, width: CGFloat?, height: CGFloat) {
        let w = width ?? (UIScreen.main.bounds.width - 150) / 2
        let h = height
        let args = TransformImageArguments(
            corners: ImageCorners(radius: 8.swh),
            imageSize: CGSize(width: w, height: h),
            boundingSize: CGSize(width: w, height: h),
            intrinsicInsets: .zero
        )
        host.imageNode.setSignal(remoteImageSignal(url: url), attemptSynchronously: false)
        host.imageNode.setArguments(args)
    }

    private func makeVideoView(url: String, width: CGFloat?, height: CGFloat) -> UIView {
        let container = MessageVideoView(urlString: url)
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
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        overlay.layer.cornerRadius = 8.swh
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

    private func addImageTapGesture(to host: MessageCellImageHostView, url: String) {
        host.isUserInteractionEnabled = true
        host.accessibilityIdentifier = url
        let tap = UITapGestureRecognizer(target: self, action: #selector(imageTapped(_:)))
        host.addGestureRecognizer(tap)
    }

    @objc private func imageTapped(_ gesture: UITapGestureRecognizer) {
        guard let host = gesture.view as? MessageCellImageHostView, let image = host.imageNode.image else { return }
        let viewer = ImageDetailViewController(image: image, sourceView: host)
        if let vc = findViewController() {
            viewer.modalPresentationStyle = .overFullScreen
            viewer.modalTransitionStyle = .crossDissolve
            vc.present(viewer, animated: true)
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
    private let emojiLabel = UILabel()
    private let countLabel = UILabel()

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

        emojiLabel.text = reaction.emoji.isEmpty ? "?" : reaction.emoji
        emojiLabel.font = .systemFont(ofSize: 16)
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.text = "\(reaction.count)"
        countLabel.font = .systemFont(ofSize: 12.sf, weight: .semibold)
        countLabel.textColor = UIColor.theme.textStrong
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(emojiLabel)
        addSubview(countLabel)

        NSLayoutConstraint.activate([
            emojiLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6.sw),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: emojiLabel.trailingAnchor, constant: 4.sw),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6.sw),

            heightAnchor.constraint(equalToConstant: 28.sh),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

import AVFoundation

final class MessageVideoView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private let thumbnailImageView = UIImageView()
    private let playButton = UIImageView()

    init(urlString: String) {
        super.init(frame: .zero)

        thumbnailImageView.contentMode = .scaleAspectFill
        thumbnailImageView.clipsToBounds = true
        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailImageView)

        let playConfig = UIImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        playButton.image = UIImage(systemName: "play.circle.fill", withConfiguration: playConfig)
        playButton.tintColor = .white
        playButton.translatesAutoresizingMaskIntoConstraints = false
        playButton.layer.shadowColor = UIColor.black.cgColor
        playButton.layer.shadowOpacity = 0.5
        playButton.layer.shadowRadius = 4
        addSubview(playButton)

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            thumbnailImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 48),
            playButton.heightAnchor.constraint(equalToConstant: 48),
        ])

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        guard let url = URL(string: urlString) else { return }
        generateThumbnail(url: url)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func handleTap() {
        if let player, player.rate > 0 {
            player.pause()
            playButton.isHidden = false
            return
        }

        if let player {
            player.seek(to: .zero)
            player.play()
            playButton.isHidden = true
            return
        }

        guard let urlStr = thumbnailImageView.accessibilityIdentifier, let url = URL(string: urlStr) else { return }
        startPlayback(url: url)
    }

    private func startPlayback(url: URL) {
        let player = AVPlayer(url: url)
        self.player = player

        let layer = AVPlayerLayer(player: player)
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill
        self.layer.insertSublayer(layer, above: thumbnailImageView.layer)
        self.playerLayer = layer

        playButton.isHidden = true
        thumbnailImageView.isHidden = true
        player.play()

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.playButton.isHidden = false
            self?.player?.seek(to: .zero)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    private func generateThumbnail(url: URL) {
        thumbnailImageView.accessibilityIdentifier = url.absoluteString

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)

            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async {
                    self?.thumbnailImageView.image = image
                }
            }
        }
    }
}
