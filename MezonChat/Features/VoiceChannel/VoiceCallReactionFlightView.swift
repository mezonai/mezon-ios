import UIKit
import AVFoundation

@MainActor
final class VoiceCallReactionFlightView: UIView {

    var onSoundReactionTilePlayingChanged: ((Int64, Bool) -> Void)?
    var onSoundReactionTileBadgesClearAll: (() -> Void)?
    var onRaiseHandStateChanged: ((Int64, Bool) -> Void)?
    var onRaiseHandDisplayReset: (() -> Void)?

    private static let raiseHandUpPrefix = "raising-up"
    private static let raiseHandDownPrefix = "raising-down"
    private static let senderNamePrefix = "sender-name:"
    private static let senderAvatarPrefix = "sender-avatar:"
    private static let soundPrefix = "sound:"
    private static let maxSlots = 10
    private static let flightDuration: TimeInterval = 4
    private static let emojiSize: CGFloat = 44

    private var reactionSlots = 0
    private var oneShotAudios: [OneShotAudioPlayback] = []
    private var soundReactionPlayCounts: [Int64: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handle(message: Mezon_Realtime_VoiceReactionSend, context: AccountContext, clanId: Int64) {
        let emojis = message.emojis
        guard let rawFirst = emojis.first, !rawFirst.isEmpty else { return }

        let senderIdNum = message.senderID

        if rawFirst.hasPrefix(Self.raiseHandDownPrefix) {
            onRaiseHandStateChanged?(senderIdNum, false)
            return
        }

        if rawFirst.hasPrefix(Self.raiseHandUpPrefix) {
            onRaiseHandStateChanged?(senderIdNum, true)
            return
        }

        if reactionSlots >= Self.maxSlots { return }

        if rawFirst.hasPrefix(Self.soundPrefix) {
            let path = String(rawFirst.dropFirst(Self.soundPrefix.count))
            if let url = URL(string: path), url.scheme != nil {
                bumpSoundReactionCount(for: senderIdNum, delta: 1)
                playSound(url: url, senderId: senderIdNum)
                reactionSlots += 1
            }
            return
        }

        let displayName = metaString(emojis, index: 1, prefix: Self.senderNamePrefix)
            .ifEmpty { voiceReactionDisplayName(context: context, clanId: clanId, userId: senderIdNum) }
        spawnFlyingEmoji(emojiId: rawFirst, displayName: displayName)
        reactionSlots += 1
    }

    func reset() {
        for v in subviews {
            v.removeFromSuperview()
        }
        reactionSlots = 0
        for o in oneShotAudios {
            o.stopPlaybackSilently()
        }
        oneShotAudios.removeAll()
        soundReactionPlayCounts.removeAll()
        onSoundReactionTileBadgesClearAll?()
        onRaiseHandDisplayReset?()
    }

    private func metaString(_ emojis: [String], index: Int, prefix: String) -> String {
        guard emojis.count > index else { return "" }
        let s = emojis[index]
        if s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func spawnFlyingEmoji(emojiId: String, displayName: String) {
        layoutIfNeeded()
        let w = bounds.width
        let h = bounds.height
        guard w > 1, h > 1 else { return }

        let horizontalJitter = CGFloat.random(in: -30...30)
        let verticalJitter = CGFloat.random(in: 0...30)
        let start = CGPoint(x: w / 2 + horizontalJitter * 0.2, y: h - 120 - verticalJitter)
        let endX = start.x + CGFloat.random(in: -75...75)
        let endY = start.y - h * CGFloat.random(in: 0.55...0.85)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.distribution = .fill
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Self.emojiSize),
            imageView.heightAnchor.constraint(equalToConstant: Self.emojiSize),
        ])
        stack.addArrangedSubview(imageView)

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            let pill = UIView()
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.backgroundColor = UIColor.theme.secondaryLight.withAlphaComponent(0.95)
            pill.layer.cornerRadius = 10
            pill.layer.masksToBounds = true

            let nl = UILabel()
            nl.translatesAutoresizingMaskIntoConstraints = false
            nl.font = .systemFont(ofSize: 10, weight: .semibold)
            nl.textColor = UIColor.theme.textStrong
            nl.textAlignment = .center
            nl.text = trimmedName
            nl.numberOfLines = 1
            nl.lineBreakMode = .byTruncatingTail
            nl.setContentHuggingPriority(.defaultLow, for: .horizontal)
            nl.setContentCompressionResistancePriority(.required, for: .vertical)

            pill.addSubview(nl)
            let maxPillW = min(w * 0.72, 200)
            NSLayoutConstraint.activate([
                nl.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
                nl.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
                nl.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
                nl.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
                pill.widthAnchor.constraint(lessThanOrEqualToConstant: maxPillW),
                pill.widthAnchor.constraint(greaterThanOrEqualToConstant: 52),
            ])
            stack.addArrangedSubview(pill)
        }

        let host = UIView()
        host.isUserInteractionEnabled = false
        host.alpha = 0
        host.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let maxHostW = min(w - 24, 220)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: maxHostW),
        ])
        addSubview(host)

        let fit = stack.systemLayoutSizeFitting(
            CGSize(width: maxHostW, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .fittingSizeLevel,
            verticalFittingPriority: .fittingSizeLevel
        )
        let hostW = max(fit.width, Self.emojiSize)
        let hostH = max(fit.height, Self.emojiSize)
        host.bounds = CGRect(x: 0, y: 0, width: hostW, height: hostH)
        host.center = start

        let proxiedURL = MezonConfig.emojiResourceURL(emojiId: emojiId, imgproxyFitSide: 32)
        let cachedImage: UIImage? = {
            guard let url = proxiedURL else { return nil }
            return ImageCache.shared.memoryImage(forKey: url.absoluteString)
        }()
        if let cachedImage {
            imageView.image = cachedImage
            startReactionFlight(host: host, endX: endX, endY: endY)
        } else {
            let gate = ReactionFlightStartGate()
            let beginFlight: () -> Void = { [weak self] in
                guard !gate.started else { return }
                gate.started = true
                self?.startReactionFlight(host: host, endX: endX, endY: endY)
            }
            ReactionEmojiImageLoader.load(emojiId: emojiId, imgproxyFitSide: 32) { [weak imageView] img in
                imageView?.image = img
                beginFlight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                beginFlight()
            }
        }
    }

    private func startReactionFlight(host: UIView, endX: CGFloat, endY: CGFloat) {
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut]) {
            host.alpha = 1
            host.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
        } completion: { _ in
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
                host.transform = .identity
            }
        }

        UIView.animate(withDuration: Self.flightDuration, delay: 0, options: [.curveEaseOut]) {
            host.center = CGPoint(x: endX, y: endY)
            host.alpha = 0
        } completion: { [weak self] _ in
            host.removeFromSuperview()
            self?.reactionSlots = max(0, (self?.reactionSlots ?? 1) - 1)
        }
    }

    func prewarmEmojiCache(emojiIds: [String]) {
        let capped = Array(emojiIds.prefix(120))
        for id in capped {
            guard !id.isEmpty,
                  let url = MezonConfig.emojiResourceURL(emojiId: id, imgproxyFitSide: 32) else { continue }
            if ImageCache.shared.memoryImage(forKey: url.absoluteString) != nil { continue }
            ReactionEmojiImageLoader.load(emojiId: id, imgproxyFitSide: 32) { _ in }
        }
    }

    private func playSound(url: URL, senderId: Int64) {
        let one = OneShotAudioPlayback()
        oneShotAudios.append(one)
        one.play(url: url) { [weak self] _ in
            guard let self else { return }
            self.oneShotAudios.removeAll { $0 === one }
            self.bumpSoundReactionCount(for: senderId, delta: -1)
            self.reactionSlots = max(0, self.reactionSlots - 1)
        }
    }

    private func bumpSoundReactionCount(for senderId: Int64, delta: Int) {
        let prev = soundReactionPlayCounts[senderId] ?? 0
        let next = max(0, prev + delta)
        if next == 0 {
            soundReactionPlayCounts.removeValue(forKey: senderId)
        } else {
            soundReactionPlayCounts[senderId] = next
        }
        if prev == 0, next == 1 {
            onSoundReactionTilePlayingChanged?(senderId, true)
        } else if prev == 1, next == 0 {
            onSoundReactionTilePlayingChanged?(senderId, false)
        }
    }
}

private extension String {
    func ifEmpty(_ alt: () -> String) -> String {
        isEmpty ? alt() : self
    }
}

@MainActor
private final class ReactionFlightStartGate {
    var started = false
}

@MainActor
private func voiceReactionDisplayName(context: AccountContext, clanId: Int64, userId: Int64) -> String {
    let key = String(userId)
    if let list = context.engine.clanData.getClanUsers(clanId: clanId) {
        for cu in list.clanUsers where cu.user.id == userId {
            if !cu.clanNick.isEmpty { return cu.clanNick }
            if !cu.user.displayName.isEmpty { return cu.user.displayName }
            if !cu.user.username.isEmpty { return cu.user.username }
        }
    }
    if let profile = context.account.postbox.read({ $0.getProfile(userId: key) }) {
        if let d = profile.displayName, !d.isEmpty { return d }
        if !profile.username.isEmpty { return profile.username }
    }
    return ""
}

@MainActor
private func voiceReactionAvatarURL(context: AccountContext, clanId: Int64, userId: Int64) -> String? {
    guard let list = context.engine.clanData.getClanUsers(clanId: clanId) else { return nil }
    for cu in list.clanUsers where cu.user.id == userId {
        if !cu.clanAvatar.isEmpty { return cu.clanAvatar }
        if !cu.user.avatarURL.isEmpty { return cu.user.avatarURL }
    }
    return nil
}

private final class OneShotAudioPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var finish: ((Bool) -> Void)?
    private var dataTask: URLSessionDataTask?
    private var isCancelled = false

    func play(url: URL, completion: @escaping (Bool) -> Void) {
        isCancelled = false
        finish = completion
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            if self.isCancelled { return }
            guard error == nil, let data, !data.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.complete(false)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isCancelled else { return }
                do {
                    self.player = try AVAudioPlayer(data: data)
                    self.player?.delegate = self
                    self.player?.prepareToPlay()
                    guard self.player?.play() == true else {
                        self.complete(false)
                        return
                    }
                } catch {
                    self.complete(false)
                }
            }
        }
        dataTask = task
        task.resume()
    }

    func stopPlaybackSilently() {
        isCancelled = true
        dataTask?.cancel()
        dataTask = nil
        player?.stop()
        player?.delegate = nil
        player = nil
        finish = nil
    }

    private func complete(_ flag: Bool) {
        guard !isCancelled else { return }
        let f = finish
        finish = nil
        player = nil
        f?(flag)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        complete(flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        complete(false)
    }
}
