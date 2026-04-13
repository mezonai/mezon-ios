import UIKit
import AVFoundation

@MainActor
final class VoiceCallReactionFlightView: UIView {

    var onSoundReactionTilePlayingChanged: ((Int64, Bool) -> Void)?
    var onSoundReactionTileBadgesClearAll: (() -> Void)?

    private static let raiseHandUpPrefix = "raising-up"
    private static let raiseHandDownPrefix = "raising-down"
    private static let senderNamePrefix = "sender-name:"
    private static let senderAvatarPrefix = "sender-avatar:"
    private static let soundPrefix = "sound:"
    private static let raiseHandDisplaySeconds: TimeInterval = 10
    private static let maxSlots = 10
    private static let flightDuration: TimeInterval = 4
    private static let emojiSize: CGFloat = 44

    private let raiseHandStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .center
        s.spacing = 10
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private var raiseHandWorkItems: [String: DispatchWorkItem] = [:]
    private var raiseHandRows: [String: UIView] = [:]
    private var reactionSlots = 0
    private var oneShotAudios: [OneShotAudioPlayback] = []
    private var soundReactionPlayCounts: [Int64: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(raiseHandStack)
        NSLayoutConstraint.activate([
            raiseHandStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            raiseHandStack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -200),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func handle(message: Mezon_Realtime_VoiceReactionSend, context: AccountContext, clanId: Int64) {
        let emojis = message.emojis
        guard let rawFirst = emojis.first, !rawFirst.isEmpty else { return }
        if reactionSlots >= Self.maxSlots { return }

        let senderIdNum = message.senderID
        let senderId = String(senderIdNum)

        if rawFirst.hasPrefix(Self.raiseHandDownPrefix) {
            removeRaiseHand(senderId: senderId)
            return
        }

        if rawFirst.hasPrefix(Self.raiseHandUpPrefix) {
            let name = metaString(emojis, index: 1, prefix: Self.senderNamePrefix)
                .ifEmpty { voiceReactionDisplayName(context: context, clanId: clanId, userId: senderIdNum) }
            let avatar = metaString(emojis, index: 2, prefix: Self.senderAvatarPrefix)
                .ifEmpty { voiceReactionAvatarURL(context: context, clanId: clanId, userId: senderIdNum) ?? "" }
            let wasNew = raiseHandRows[senderId] == nil
            addOrRefreshRaiseHand(senderId: senderId, displayName: name, avatarURLString: avatar)
            if wasNew { reactionSlots += 1 }
            return
        }

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
        raiseHandWorkItems.values.forEach { $0.cancel() }
        raiseHandWorkItems.removeAll()
        raiseHandRows.values.forEach { $0.removeFromSuperview() }
        raiseHandRows.removeAll()
        subviews.filter { $0 != raiseHandStack }.forEach { $0.removeFromSuperview() }
        reactionSlots = 0
        oneShotAudios.removeAll()
        soundReactionPlayCounts.removeAll()
        onSoundReactionTileBadgesClearAll?()
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

        ReactionEmojiImageLoader.load(emojiId: emojiId, imgproxyFitSide: 72) { [weak imageView] img in
            imageView?.image = img
        }

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

    private func addOrRefreshRaiseHand(senderId: String, displayName: String, avatarURLString: String) {
        raiseHandWorkItems[senderId]?.cancel()
        if let existing = raiseHandRows[senderId] {
            existing.removeFromSuperview()
            raiseHandRows.removeValue(forKey: senderId)
        }

        let row = makeRaiseHandRow(displayName: displayName, avatarURLString: avatarURLString)
        raiseHandStack.addArrangedSubview(row)
        raiseHandRows[senderId] = row

        let work = DispatchWorkItem { [weak self] in
            self?.removeRaiseHand(senderId: senderId)
        }
        raiseHandWorkItems[senderId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.raiseHandDisplaySeconds, execute: work)
    }

    private func removeRaiseHand(senderId: String) {
        raiseHandWorkItems[senderId]?.cancel()
        raiseHandWorkItems.removeValue(forKey: senderId)
        guard raiseHandRows[senderId] != nil else { return }
        raiseHandRows[senderId]?.removeFromSuperview()
        raiseHandRows.removeValue(forKey: senderId)
        reactionSlots = max(0, reactionSlots - 1)
    }

    private func makeRaiseHandRow(displayName: String, avatarURLString: String) -> UIView {
        let wrap = UIView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        wrap.layer.cornerRadius = 12

        let avatar = UIImageView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = 20
        avatar.backgroundColor = UIColor.theme.tertiary

        if let u = URL(string: avatarURLString), u.scheme != nil {
            URLSession.shared.dataTask(with: u) { data, _, _ in
                guard let data, let img = UIImage(data: data) else { return }
                DispatchQueue.main.async { avatar.image = img }
            }.resume()
        }

        let name = UILabel()
        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.textColor = UIColor.theme.textStrong
        name.text = displayName
        name.numberOfLines = 1

        let hand = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
        hand.translatesAutoresizingMaskIntoConstraints = false
        hand.tintColor = UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1)
        hand.contentMode = .scaleAspectFit

        wrap.addSubview(avatar)
        wrap.addSubview(name)
        wrap.addSubview(hand)

        NSLayoutConstraint.activate([
            wrap.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            avatar.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8),
            avatar.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 40),
            avatar.heightAnchor.constraint(equalToConstant: 40),

            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 160),

            hand.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 8),
            hand.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -10),
            hand.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            hand.widthAnchor.constraint(equalToConstant: 28),
            hand.heightAnchor.constraint(equalToConstant: 28),
        ])
        return wrap
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

    func play(url: URL, completion: @escaping (Bool) -> Void) {
        finish = completion
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self else { return }
            guard error == nil, let data, !data.isEmpty else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            DispatchQueue.main.async {
                do {
                    self.player = try AVAudioPlayer(data: data)
                    self.player?.delegate = self
                    self.player?.prepareToPlay()
                    guard self.player?.play() == true else {
                        completion(false)
                        return
                    }
                } catch {
                    completion(false)
                }
            }
        }
        task.resume()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let f = finish
        finish = nil
        self.player = nil
        DispatchQueue.main.async { f?(flag) }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let f = finish
        finish = nil
        self.player = nil
        DispatchQueue.main.async { f?(false) }
    }
}
