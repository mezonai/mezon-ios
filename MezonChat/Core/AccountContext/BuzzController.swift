import AVFoundation
import UIKit

extension Notification.Name {
    static let mezonBuzzStateChanged = Notification.Name("mezon.buzz.stateChanged")
}

final class BuzzController {
    let state = BuzzState()
    private let postbox: Postbox
    private var observers: [NSObjectProtocol] = []
    private var viewing: (owner: ObjectIdentifier, channelId: Int64, topicId: Int64)?
    private var players: [AVAudioPlayer] = []

    init(postbox: Postbox) {
        self.postbox = postbox
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("MezonChannelMarkedAsRead"), object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let info = notification.userInfo, info["fromSelf"] as? Bool != true,
                  let channelId = info["channelId"] as? Int64 else { return }
            let topicId = info["topicId"] as? Int64 ?? 0
            let targetId = topicId != 0 ? topicId : channelId
            if let rawId = info["messageId"] as? String, let messageId = Int64(rawId), messageId != 0 {
                self.clearSeen(targetId: targetId, messageId: messageId)
            } else {
                self.markAsRead(clanId: info["clanId"] as? Int64 ?? 0, channelId: channelId)
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .mezonChannelDeletedLocally, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, let channelId = notification.userInfo?["channelId"] as? Int64 else { return }
            let channelIds = Set(notification.userInfo?["channelIds"] as? [Int64] ?? [channelId])
            self.notifyChanged(self.state.clearRows(targetIds: channelIds) { _, rowId in channelIds.contains(rowId) })
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func receive(_ message: Mezon_Api_ChannelMessage, currentUserId: Int64) {
        guard message.code == MezonConstants.MessageCode.buzz.rawValue,
              message.senderID != currentUserId,
              message.channelID != 0 else { return }
        let channelId = message.channelID
        let isViewing = UIApplication.shared.applicationState == .active
            && viewing?.channelId == channelId && viewing?.topicId == message.topicID
        let reception = state.receive(clanId: message.clanID, channelId: channelId,
                                      topicId: message.topicID, messageId: message.messageID, isViewing: isViewing)
        guard reception != .duplicate else { return }
        if reception == .badgeAdded { notifyChanged([channelId]) }
        playSound()
    }

    func setViewing(owner: AnyObject, channelId: Int64, topicId: Int64) {
        viewing = (ObjectIdentifier(owner), channelId, topicId)
        notifyChanged(state.clearTarget(topicId != 0 ? topicId : channelId))
    }

    func stopViewing(owner: AnyObject) {
        if viewing?.owner == ObjectIdentifier(owner) { viewing = nil }
    }

    func clearSeen(targetId: Int64, messageId: Int64) {
        notifyChanged(state.clearTarget(targetId, seenMessageId: messageId))
    }

    func markAsRead(clanId: Int64, channelId: Int64 = 0, categoryId: Int64 = 0) {
        let targets: Set<Int64> = channelId != 0 ? [channelId] : []
        notifyChanged(state.clearRows(targetIds: targets) { markedClanId, rowId in
            let channel = self.postbox.getChannelDescription(channelId: rowId)?.channel
            if channelId != 0 { return rowId == channelId || channel?.parentID == channelId }
            guard clanId != 0, markedClanId == clanId else { return false }
            if categoryId == 0 { return true }
            let category: Int64?
            if let channel, channel.parentID != 0 {
                category = self.postbox.getChannelDescription(channelId: channel.parentID)?.channel.categoryID
            } else {
                category = channel?.categoryID
            }
            return category == categoryId
        })
    }

    func removeChannel(_ channelId: Int64) {
        notifyChanged(state.clearRows(targetIds: [channelId]) { _, rowId in
            rowId == channelId || self.postbox.getChannelDescription(channelId: rowId)?.channel.parentID == channelId
        })
    }

    func removeClan(_ clanId: Int64) {
        notifyChanged(state.clearRows { markedClanId, _ in markedClanId == clanId })
    }

    func reset() {
        state.reset()
        viewing = nil
        players.forEach { $0.stop() }
        players.removeAll()
        NotificationCenter.default.post(name: .mezonBuzzStateChanged, object: self)
    }

    func playSound() {
        guard let url = Bundle.main.url(forResource: "buzz", withExtension: "mp3", subdirectory: "Sounds")
                ?? Bundle.main.url(forResource: "buzz", withExtension: "mp3") else { return }
        // Keep live call/recording routing; mix Buzz with other media like Android's SoundPool.
        if AVAudioSession.sharedInstance().category != .playAndRecord {
            AppAudioSession.activateForMediaPlayback(options: [.mixWithOthers])
        }
        players.removeAll { !$0.isPlaying }
        if players.count >= 4 { players.removeFirst().stop() }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            players.append(player)
            player.play()
        } catch {
            SentryLogger.capture(error, extras: ["where": "BuzzController.playSound"])
        }
    }

    private func notifyChanged(_ channelIds: Set<Int64>) {
        guard !channelIds.isEmpty else { return }
        NotificationCenter.default.post(name: .mezonBuzzStateChanged, object: self,
                                        userInfo: ["channelIds": channelIds])
    }
}
