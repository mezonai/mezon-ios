import UIKit
import AVFoundation

final class SoundItemCell: UITableViewCell, ChatAudioPlaybackProgressSink {
    static let reuseId = "SoundItemCell"

    private static let deleteActionWidthRatio: CGFloat = 0.22

    var onDelete: (() -> Void)?
    var onSwipeOpened: (() -> Void)?
    var onSwipeClosed: (() -> Void)?
    var onSwipeInteractionChanged: ((Bool) -> Void)?
    var onDurationLoaded: ((TimeInterval) -> Void)?

    private let mainContentView = UIView()
    private let deleteActionView = UIView()
    private let deleteButton = UIButton(type: .system)
    private let soundContainer = UIView()
    private let creatorContainer = UIStackView()
    private let playButton = UIButton(type: .system)
    private let nameLabel = UILabel()
    private let timeLabel = UILabel()
    private let creatorNameLabel = UILabel()
    private let creatorAvatar = TextAvatarView(size: 28.swh)
    private let avatarImageView = UIImageView()
    private var avatarURL: String?
    private var sound: CachedClanStickerRecord?
    private var durationAsset: AVURLAsset?
    private var durationTask: Task<Void, Never>?
    private var duration: TimeInterval = 0
    private var playbackId: String? { sound.map { "clan-sound-\($0.clanID)-\($0.id)" } }
    private var isSwipeDeletable = false
    private var swipeStartOffset: CGFloat = 0
    private var currentSwipeOffset: CGFloat = 0
    private lazy var swipePanDelegate = SoundSwipePanGestureDelegate(owner: self)
    private lazy var panGesture: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = swipePanDelegate
        return pan
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.clipsToBounds = true
        deleteActionView.backgroundColor = .systemRed
        deleteActionView.isHidden = true
        deleteButton.setTitle(L(L10n.Common.delete), for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        deleteButton.titleLabel?.numberOfLines = 2
        deleteButton.titleLabel?.textAlignment = .center
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        [deleteActionView, mainContentView].forEach { contentView.addSubview($0) }
        deleteActionView.addSubview(deleteButton)
        contentView.addGestureRecognizer(panGesture)
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        playButton.layer.cornerRadius = 18.swh
        nameLabel.font = .systemFont(ofSize: 14.sf, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11.sf, weight: .regular)
        creatorNameLabel.font = .systemFont(ofSize: 12.sf)
        creatorNameLabel.lineBreakMode = .byTruncatingTail
        creatorNameLabel.textAlignment = .right
        avatarImageView.contentMode = .scaleAspectFill
        creatorContainer.axis = .horizontal
        creatorContainer.alignment = .center
        creatorContainer.spacing = 6.sw
        creatorContainer.addArrangedSubview(creatorNameLabel)
        creatorContainer.addArrangedSubview(creatorAvatar)
        creatorAvatar.addSubview(avatarImageView)
        let labels = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        labels.axis = .vertical
        labels.spacing = 2.sh
        [soundContainer, creatorContainer].forEach { mainContentView.addSubview($0) }
        [playButton, labels].forEach { soundContainer.addSubview($0) }
        [mainContentView, deleteActionView, deleteButton, soundContainer, creatorContainer, playButton, labels, avatarImageView, creatorAvatar].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            mainContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainContentView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            deleteActionView.topAnchor.constraint(equalTo: contentView.topAnchor),
            deleteActionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            deleteActionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            deleteActionView.widthAnchor.constraint(equalTo: contentView.widthAnchor, multiplier: Self.deleteActionWidthRatio),
            deleteButton.leadingAnchor.constraint(equalTo: deleteActionView.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: deleteActionView.trailingAnchor),
            deleteButton.topAnchor.constraint(equalTo: deleteActionView.topAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: deleteActionView.bottomAnchor),
            soundContainer.leadingAnchor.constraint(equalTo: mainContentView.leadingAnchor, constant: 10.sw),
            soundContainer.topAnchor.constraint(equalTo: mainContentView.topAnchor, constant: 6.sh),
            soundContainer.bottomAnchor.constraint(equalTo: mainContentView.bottomAnchor, constant: -6.sh),
            soundContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 48.sh),
            soundContainer.widthAnchor.constraint(equalTo: mainContentView.widthAnchor, multiplier: 0.59),
            playButton.leadingAnchor.constraint(equalTo: soundContainer.leadingAnchor, constant: 6.sw),
            playButton.centerYAnchor.constraint(equalTo: soundContainer.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 36.swh),
            playButton.heightAnchor.constraint(equalTo: playButton.widthAnchor),
            labels.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 8.sw),
            labels.trailingAnchor.constraint(equalTo: soundContainer.trailingAnchor, constant: -6.sw),
            labels.centerYAnchor.constraint(equalTo: soundContainer.centerYAnchor),
            labels.topAnchor.constraint(greaterThanOrEqualTo: soundContainer.topAnchor, constant: 6.sh),
            creatorContainer.leadingAnchor.constraint(equalTo: soundContainer.trailingAnchor, constant: 10.sw),
            creatorContainer.trailingAnchor.constraint(equalTo: mainContentView.trailingAnchor, constant: -10.sw),
            creatorContainer.centerYAnchor.constraint(equalTo: mainContentView.centerYAnchor),
            creatorAvatar.widthAnchor.constraint(equalToConstant: 28.swh),
            creatorAvatar.heightAnchor.constraint(equalTo: creatorAvatar.widthAnchor),
            avatarImageView.topAnchor.constraint(equalTo: creatorAvatar.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: creatorAvatar.bottomAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: creatorAvatar.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: creatorAvatar.trailingAnchor)
        ])
        creatorAvatar.setContentCompressionResistancePriority(.required, for: .horizontal)
        playbackDidReset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(sound: CachedClanStickerRecord, creatorName: String, creatorAvatarURL: String?, canDelete: Bool, knownDuration: TimeInterval?) {
        closeSwipe(animated: false)
        isSwipeDeletable = canDelete
        accessibilityCustomActions = canDelete
            ? [UIAccessibilityCustomAction(name: L(L10n.Common.delete), target: self, selector: #selector(accessibilityDelete))]
            : nil
        mainContentView.backgroundColor = UIColor.theme.secondary
        self.sound = sound
        loadDuration(source: sound.source, knownDuration: knownDuration)
        nameLabel.text = sound.shortname
        creatorNameLabel.text = creatorName
        nameLabel.textColor = UIColor.theme.textStrong
        timeLabel.textColor = UIColor.theme.textDisabled
        creatorNameLabel.textColor = UIColor.theme.textStrong
        playButton.backgroundColor = UIColor.theme.secondary
        playButton.tintColor = UIColor.theme.bgViolet
        avatarImageView.image = nil
        creatorAvatar.showPlaceholder()
        avatarURL = creatorAvatarURL
        guard let creatorAvatarURL, !creatorAvatarURL.isEmpty else { return }
        let resolved = ImgproxyURL.absoluteResourceURL(from: creatorAvatarURL)
        let proxy = ImgproxyURL.avatarProxyURL(from: resolved, width: 100, height: 100)
        ImageCache.shared.loadAvatar(urlString: proxy.isEmpty ? resolved : proxy) { [weak self] image in
            guard let self, self.avatarURL == creatorAvatarURL else { return }
            self.avatarImageView.image = image
            if image != nil { self.creatorAvatar.showImageMode() }
            else { self.creatorAvatar.showPlaceholder() }
        }
    }

    @objc private func togglePlayback() {
        closeSwipe(animated: true)
        guard let sound, let playbackId else { return }
        ChatAudioPlaybackCoordinator.shared.toggle(
            urlString: ImgproxyURL.absoluteResourceURL(from: sound.source), playbackId: playbackId, sink: self
        )
    }

    func stopPlayback() {
        guard let playbackId else { return }
        ChatAudioPlaybackCoordinator.shared.cancelIfCurrent(playbackId: playbackId)
    }

    func playbackDidReset() {
        playbackProgress(0, playing: false, duration: 0)
    }

    func playbackProgress(_ fraction: CGFloat, playing: Bool, duration: TimeInterval) {
        if duration.isFinite, duration > 0, duration != self.duration {
            self.duration = duration
            onDurationLoaded?(duration)
        }
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        playButton.accessibilityLabel = L(playing ? L10n.ClanSetting.Sounds.pause : L10n.ClanSetting.Sounds.play)
        let end = self.duration > 0 ? ClanSoundAudio.timeLabel(self.duration) : "–:––"
        timeLabel.text = "\(ClanSoundAudio.timeLabel(Double(fraction) * self.duration)) / \(end)"
    }

    private func loadDuration(source: String, knownDuration: TimeInterval?) {
        durationTask?.cancel()
        durationTask = nil
        durationAsset?.cancelLoading()
        durationAsset = nil
        duration = knownDuration ?? 0
        playbackDidReset()
        guard knownDuration == nil else { return }
        guard let url = URL(string: ImgproxyURL.absoluteResourceURL(from: source)) else { return }
        durationTask = Task { [weak self] in
            let request = await CDNSigner.shared.requestURL(for: url)
            guard !Task.isCancelled, let self else { return }
            let asset = AVURLAsset(url: request.url)
            self.durationAsset = asset
            asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self, weak asset] in
                DispatchQueue.main.async {
                    guard let self, let asset, self.durationAsset === asset,
                          asset.statusOfValue(forKey: "duration", error: nil) == .loaded else { return }
                    let seconds = asset.duration.seconds
                    guard seconds.isFinite, seconds > 0 else { return }
                    self.duration = seconds
                    self.onDurationLoaded?(seconds)
                    if ChatAudioPlaybackCoordinator.shared.currentPlaybackId != self.playbackId {
                        self.playbackDidReset()
                    }
                }
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        closeSwipe(animated: false)
        isSwipeDeletable = false
        accessibilityCustomActions = nil
        onDelete = nil
        onSwipeOpened = nil
        onSwipeClosed = nil
        onSwipeInteractionChanged = nil
        onDurationLoaded = nil
        stopPlayback()
        durationTask?.cancel()
        durationTask = nil
        durationAsset?.cancelLoading()
        durationAsset = nil
        duration = 0
        sound = nil
        avatarURL = nil
        avatarImageView.image = nil
        playbackDidReset()
    }

    func closeSwipe(animated: Bool) {
        let wasOpen = currentSwipeOffset < 0
        applySwipeOffset(0, animated: animated)
        onSwipeInteractionChanged?(false)
        if wasOpen { onSwipeClosed?() }
    }

    private func applySwipeOffset(_ offset: CGFloat, animated: Bool) {
        currentSwipeOffset = offset
        let updates = {
            self.mainContentView.transform = CGAffineTransform(translationX: offset, y: 0)
            self.deleteActionView.isHidden = !self.isSwipeDeletable || offset == 0
        }
        if animated {
            UIView.animate(
                withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState],
                animations: updates
            )
        } else {
            updates()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isSwipeDeletable else { return }
        let maxOffset = contentView.bounds.width * Self.deleteActionWidthRatio
        guard maxOffset > 0 else { return }
        switch gesture.state {
        case .began:
            swipeStartOffset = currentSwipeOffset
            onSwipeInteractionChanged?(true)
        case .changed:
            let offset = min(0, max(-maxOffset, swipeStartOffset + gesture.translation(in: contentView).x))
            applySwipeOffset(offset, animated: false)
        case .ended, .cancelled:
            let offset = min(0, max(-maxOffset, swipeStartOffset + gesture.translation(in: contentView).x))
            let velocity = gesture.velocity(in: contentView).x
            let shouldClose = swipeStartOffset < 0 && (velocity > 500 || offset > -maxOffset * 0.5)
            let shouldOpen = !shouldClose && (offset < -maxOffset * 0.5 || velocity < -500)
            if shouldOpen { onSwipeOpened?() }
            else if currentSwipeOffset < 0 { onSwipeClosed?() }
            onSwipeInteractionChanged?(false)
            applySwipeOffset(shouldOpen ? -maxOffset : 0, animated: true)
        default:
            break
        }
    }

    @objc private func deleteTapped() {
        guard isSwipeDeletable else { return }
        closeSwipe(animated: true)
        onDelete?()
    }

    @objc private func accessibilityDelete() -> Bool {
        guard isSwipeDeletable else { return false }
        deleteTapped()
        return true
    }

    fileprivate func shouldBeginSwipePan(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === panGesture, isSwipeDeletable else { return false }
        let velocity = panGesture.velocity(in: contentView)
        return abs(velocity.x) > abs(velocity.y) && (currentSwipeOffset < 0 || velocity.x < 0)
    }
}

private final class SoundSwipePanGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private weak var owner: SoundItemCell?

    init(owner: SoundItemCell) { self.owner = owner }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        owner?.shouldBeginSwipePan(gestureRecognizer) ?? false
    }
}
