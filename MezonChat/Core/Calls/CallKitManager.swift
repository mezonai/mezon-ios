import AVFoundation
import CallKit
import Darwin
import Foundation
import Intents
import WebRTC
import PushKit
import UIKit
import UserNotifications

private final class VoIPPushCompletionGate {
    private var consumed = false
    private let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    func consume() {
        guard !consumed else { return }
        consumed = true
        body()
    }
}

enum IncomingPeerCallDisposition: String, Codable {
    case ringing, answered, rejected, answeredElsewhere, missed, discarded
}

struct IncomingPeerCallNotificationRecord: Codable {
    let id: String
    let channelId: Int64
    let callerId: Int64
    let receiverId: Int64
    let startedAt: TimeInterval
    let deadline: TimeInterval
    var name: String
    var body: String
    var avatarURL: String? = nil
    var disposition: IncomingPeerCallDisposition = .ringing

    var notificationId: String { "mezon.missed-call.\(id)" }
    var shouldNotify: Bool { disposition == .ringing || disposition == .missed }

    mutating func finish(_ next: IncomingPeerCallDisposition) -> Bool {
        guard next != .ringing,
              disposition == .ringing || (disposition == .missed && next == .discarded) else { return false }
        disposition = next
        return true
    }

    var userInfo: [AnyHashable: Any] {
        ["channel": String(channelId), "clan": "0", "is_dm": true,
         "sender": String(callerId), "recipient": String(receiverId),
         "callUUID": id, "notification_type": "missed_call"]
    }
}

enum PeerCallStartNotificationMatcher {
    static func matches(_ notification: UNNotification, record: IncomingPeerCallNotificationRecord) -> Bool {
        notification.date.timeIntervalSince1970 >= record.startedAt - 30
            && notification.date.timeIntervalSince1970 <= record.deadline + 120
            && CallStartNotificationPolicy.matchesSource(notification.request.content, channelId: record.channelId,
                                                         callerId: record.callerId, receiverId: record.receiverId)
            && CallStartNotificationPolicy.isCallStart(notification.request)
    }
}

final class PeerCallNotifications {
    private struct PreparedContent {
        let name: String
        let avatarURL: String?
        let content: UNNotificationContent
    }

    static let shared = PeerCallNotifications()
    static let missedCallCategory = CallStartNotificationPolicy.missedCallCategory
    private static let recordsKey = "mezon.call.notificationRecords"
    private let queue = DispatchQueue(label: "mezon.call.notifications")
    private let center = UNUserNotificationCenter.current()
    private var records: [String: IncomingPeerCallNotificationRecord]
    private var preparationIds: [String: UUID] = [:]
    private var preparedContents: [String: PreparedContent] = [:]
    private var queuedRequests: [String: UNNotificationRequest] = [:]
    private var addingRecordIds: Set<String> = []
    private var logoutObserver: NSObjectProtocol?

    private init() {
        records = UserDefaults.standard.data(forKey: Self.recordsKey)
            .flatMap { try? JSONDecoder().decode([String: IncomingPeerCallNotificationRecord].self, from: $0) } ?? [:]
        logoutObserver = NotificationCenter.default.addObserver(forName: .mezonAccountDidLogout, object: nil, queue: nil) { [weak self] _ in
            self?.clear()
        }
    }

    func begin(callUUID: UUID, channelId: Int64, callerId: Int64, receiverId: Int64, name: String, avatarURL: String? = nil, timeout: TimeInterval) {
        let now = Date().timeIntervalSince1970
        let record = IncomingPeerCallNotificationRecord(
            id: callUUID.uuidString, channelId: channelId, callerId: callerId, receiverId: receiverId,
            startedAt: now, deadline: now + timeout, name: name, body: L(L10n.PeerCall.missedCallNotification),
            avatarURL: avatarURL
        )
        queue.async { [self] in
            guard records[record.id] == nil else { return }
            records[record.id] = record
            persist()
            schedule(record)
            cleanupDeliveredStartNotifications()
            // Bounded retries catch FCM arriving after VoIP while the app still has execution time.
            for delay in [0.5, 2.0, 5.0, 10.0] {
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in self?.cleanupDeliveredStartNotifications() }
            }
        }
    }

    func shouldSuppressStartNotification(_ notification: UNNotification) -> Bool {
        queue.sync { records.values.contains { PeerCallStartNotificationMatcher.matches(notification, record: $0) } }
    }

    func cleanupDeliveredStartNotifications() {
        queue.async { [self] in
            guard !records.isEmpty else { return }
            center.getDeliveredNotifications { [weak self] notifications in
                guard let self else { return }
                self.queue.async {
                    let ids = notifications.filter { notification in
                        self.records.values.contains { PeerCallStartNotificationMatcher.matches(notification, record: $0) }
                    }.map { $0.request.identifier }
                    if !ids.isEmpty { self.center.removeDeliveredNotifications(withIdentifiers: ids) }
                }
            }
        }
    }

    func updateIdentity(callUUID: UUID, name: String, avatarURL: String?) {
        queue.async { [self] in
            guard var record = records[callUUID.uuidString], record.disposition == .ringing,
                  record.deadline > Date().timeIntervalSince1970 + 1,
                  record.name != name || record.avatarURL != avatarURL else { return }
            record.name = name
            record.avatarURL = avatarURL
            records[record.id] = record
            persist()
            schedule(record)
        }
    }

    func finish(callUUID: UUID, channelId: Int64? = nil, callerId: Int64? = nil, disposition: IncomingPeerCallDisposition) {
        queue.async { [self] in
            guard var record = records[callUUID.uuidString],
                  channelId == nil || record.channelId == channelId,
                  callerId == nil || record.callerId == callerId,
                  record.finish(disposition) else { return }
            records[record.id] = record
            persist()
            if record.disposition == .missed {
                // Near/after the deadline, the existing system-scheduled notification delivers it.
                // Reposting here could alert twice when the timeout callback and delivery coincide.
                if record.deadline > Date().timeIntervalSince1970 + 1 { schedule(record) }
            } else {
                preparationIds.removeValue(forKey: record.id)
                preparedContents.removeValue(forKey: record.id)
                queuedRequests.removeValue(forKey: record.id)
                remove(record.notificationId)
            }
            cleanupDeliveredStartNotifications()
        }
    }

    private func schedule(_ record: IncomingPeerCallNotificationRecord) {
        if let prepared = preparedContents[record.id],
           prepared.name == record.name, prepared.avatarURL == record.avatarURL {
            enqueue(prepared.content, for: record)
            return
        }
        preparedContents.removeValue(forKey: record.id)
        let content = UNMutableNotificationContent()
        content.title = record.name
        content.body = record.body
        content.sound = .default
        content.categoryIdentifier = Self.missedCallCategory
        content.threadIdentifier = "mezon.dm.\(record.channelId)"
        content.userInfo = record.userInfo
        // Always register the system fallback before doing image/intent work; the app may be suspended.
        if record.disposition == .ringing { enqueue(content, for: record) }
        let preparationId = UUID()
        preparationIds[record.id] = preparationId
        let submit: (UNNotificationContent, Bool) -> Void = { [weak self] prepared, enriched in
            guard let self else { return }
            self.queue.async {
                guard self.preparationIds[record.id] == preparationId,
                      let current = self.records[record.id], current.shouldNotify,
                      current.disposition == record.disposition,
                      current.name == record.name, current.avatarURL == record.avatarURL else { return }
                self.preparationIds.removeValue(forKey: record.id)
                if enriched {
                    self.preparedContents[record.id] = PreparedContent(
                        name: current.name, avatarURL: current.avatarURL, content: prepared
                    )
                }
                // Never replace a fallback that may already be delivering at the deadline.
                guard current.deadline > Date().timeIntervalSince1970 + 1 else { return }
                self.enqueue(prepared, for: current)
            }
        }
        PeerCallCommunicationIdentity.prepareMissedCallContent(
            content, callerId: record.callerId, name: record.name, avatarURL: record.avatarURL,
            callId: record.id, completion: { submit($0, true) }
        )
        if record.disposition == .missed {
            // A quick remote cancel can precede image download. Bound the delay and alert only once.
            queue.asyncAfter(deadline: .now() + 1) { submit(content, false) }
        }
    }

    private func enqueue(_ content: UNNotificationContent, for record: IncomingPeerCallNotificationRecord) {
        let trigger: UNNotificationTrigger? = record.disposition == .ringing
            ? UNTimeIntervalNotificationTrigger(timeInterval: max(1, record.deadline - Date().timeIntervalSince1970), repeats: false)
            : nil
        let request = UNNotificationRequest(identifier: record.notificationId, content: content, trigger: trigger)
        queuedRequests[record.id] = request
        addNextRequest(recordId: record.id)
    }

    private func addNextRequest(recordId: String) {
        guard !addingRecordIds.contains(recordId),
              let request = queuedRequests.removeValue(forKey: recordId) else { return }
        addingRecordIds.insert(recordId)
        center.add(request) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.addingRecordIds.remove(recordId)
                // Answer/reject can race with the notification service accepting an earlier add request.
                guard let current = self.records[recordId], current.shouldNotify else {
                    self.queuedRequests.removeValue(forKey: recordId)
                    self.remove(request.identifier)
                    return
                }
                if let error { NSLog("[CallKit] Missed call notification failed: %@", error.localizedDescription) }
                self.addNextRequest(recordId: recordId)
            }
        }
    }

    private func remove(_ id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    private func persist() {
        if records.count > 32 {
            let newest = records.values.sorted { $0.startedAt > $1.startedAt }.prefix(32)
            records = Dictionary(uniqueKeysWithValues: newest.map { ($0.id, $0) })
            preparedContents = preparedContents.filter { records[$0.key] != nil }
        }
        if let data = try? JSONEncoder().encode(records) { UserDefaults.standard.set(data, forKey: Self.recordsKey) }
    }

    private func clear() {
        queue.async { [self] in
            for record in records.values { remove(record.notificationId) }
            records.removeAll()
            preparationIds.removeAll()
            preparedContents.removeAll()
            queuedRequests.removeAll()
            UserDefaults.standard.removeObject(forKey: Self.recordsKey)
        }
    }
}

final class CallKitManager: NSObject {

    static let shared = CallKitManager()

    var hasTrackedActiveCall: Bool {
        guard let s = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) else { return false }
        return UUID(uuidString: s) != nil
    }

    private enum DefaultsKeys {
        static let notificationPayload = "mezon.voip.notificationPayload"
        static let activeCallUUID = "mezon.voip.activeCallUUID"
        static let notificationTimestamp = "mezon.voip.notificationTimestamp"
        static let quitSnapshotChannelId = "mezon.voip.quitSnapshot.channelId"
        static let quitSnapshotCallerId = "mezon.voip.quitSnapshot.callerId"
        static let quitSnapshotReceiverId = "mezon.voip.quitSnapshot.receiverId"
    }

    private let pushRegistry = PKPushRegistry(queue: .main)
    private var provider: CXProvider?
    private var complianceCallUUIDs: Set<UUID> = []
    private let complianceCallUUIDsLock = NSLock()
    private var transientComplianceProviders: [CXProvider] = []
    private var mainProviderNeedsReassert = false
    private let callController = CXCallController()
    private let payloadValiditySeconds: TimeInterval = 120
    private let recentlyEndedRetention: TimeInterval = 45
    private var callerIdentityTask: Task<Void, Never>?
    private var reportedIncomingCallUUID: UUID?
    private var reportedIncomingPayload: IncomingPeerCallPayload?
    private var callerIdentityCallUUID: UUID?
    private var callerIdentityPeer: (channelId: Int64, callerId: Int64)?
    private var appliedCallerIdentity: PeerCallCallerIdentity?

    private static let callKitComplianceDisplayLabel = "Mezon cancel call"

    private struct RecentlyEndedKey: Hashable {
        let channelId: Int64
        let callerId: Int64
    }
    private var recentlyEndedAt: [RecentlyEndedKey: Date] = [:]
    private let recentlyEndedLock = NSLock()

    private struct LastRingedCall {
        let channelId: Int64
        let callerId: Int64
        let at: Date
    }
    private var lastRingedCall: LastRingedCall?
    private let lastRingedCallLock = NSLock()
    private let lastRingedCallFallbackWindow: TimeInterval = 60

    private struct PushDedupKey: Hashable {
        let kind: String
        let channelId: Int64
        let callerId: Int64
    }
    private var recentPushDedup: [PushDedupKey: Date] = [:]
    private let recentPushDedupLock = NSLock()
    private let pushDedupWindow: TimeInterval = 6

    private var recentOfferDigests: [String: Date] = [:]
    private let recentOfferDigestsLock = NSLock()
    private let offerDedupWindow: TimeInterval = 30

    private(set) var voipToken: String?

    private override init() {
        super.init()
    }

    func configure() {
        _ = PeerCallNotifications.shared
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.isAudioEnabled = false

        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        ensureProviderConfigured()
    }

    private static func makeProviderConfiguration(forCompliance: Bool) -> CXProviderConfiguration {
        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = forCompliance ? "mezon_callkit_silent.caf" : nil
        config.includesCallsInRecents = false
        return config
    }

    private func ensureProviderConfigured() {
        guard provider == nil else { return }
        let prov = CXProvider(configuration: Self.makeProviderConfiguration(forCompliance: false))
        prov.setDelegate(self, queue: nil)
        provider = prov
    }

    private func makeTransientSilentComplianceProvider() -> CXProvider {
        let prov = CXProvider(configuration: Self.makeProviderConfiguration(forCompliance: true))
        prov.setDelegate(self, queue: nil)
        transientComplianceProviders.append(prov)
        mainProviderNeedsReassert = true
        return prov
    }

    private func scheduleComplianceProviderInvalidation(_ prov: CXProvider) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            prov.invalidate()
            self?.transientComplianceProviders.removeAll { $0 === prov }
        }
    }

    private func reassertMainProviderIfNeeded() {
        ensureProviderConfigured()
        guard mainProviderNeedsReassert else { return }
        mainProviderNeedsReassert = false
        let old = provider
        provider = nil
        ensureProviderConfigured()
        old?.invalidate()
    }

    private func markComplianceCall(_ uuid: UUID) {
        complianceCallUUIDsLock.lock()
        complianceCallUUIDs.insert(uuid)
        complianceCallUUIDsLock.unlock()
    }

    private func unmarkComplianceCall(_ uuid: UUID) {
        complianceCallUUIDsLock.lock()
        complianceCallUUIDs.remove(uuid)
        complianceCallUUIDsLock.unlock()
    }

    private func isComplianceCall(_ uuid: UUID) -> Bool {
        complianceCallUUIDsLock.lock()
        defer { complianceCallUUIDsLock.unlock() }
        return complianceCallUUIDs.contains(uuid)
    }

    private func clearComplianceCalls() {
        complianceCallUUIDsLock.lock()
        complianceCallUUIDs.removeAll()
        complianceCallUUIDsLock.unlock()
    }

    func requestEndActiveVoIPCallIfNeeded() {
        markRecentlyEndedFromStoredPayloadIfPossible()
        markRecentlyEndedFromQuitSnapshotIfPossible()
        guard let uuidString = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: uuidString)
        else {
            return
        }
        PeerCallNotifications.shared.finish(callUUID: uuid, disposition: .missed)
        if let provider {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        }
        let action = CXEndCallAction(call: uuid)
        let tx = CXTransaction(action: action)
        callController.request(tx) { _ in
            Self.clearStoredIncomingPayload()
        }
    }

    @discardableResult
    private func endStoredActiveCallViaProvider(reason: CXCallEndedReason) -> Bool {
        guard let provider else {
            return false
        }
        guard let uuidString = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: uuidString)
        else {
            return false
        }
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        return true
    }

    private func hasStoredActiveVoIPCallUUID() -> Bool {
        guard let s = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) else { return false }
        return UUID(uuidString: s) != nil
    }

    func noteIncomingCallDisposition(_ disposition: IncomingPeerCallDisposition, channelId: Int64? = nil, callerId: Int64? = nil) {
        guard let value = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: value) else { return }
        PeerCallNotifications.shared.finish(callUUID: uuid, channelId: channelId, callerId: callerId, disposition: disposition)
    }

    @MainActor
    func prepareToOpenMissedCallNotification(_ userInfo: [AnyHashable: Any]) {
        guard let value = userInfo["callUUID"] as? String,
              value == UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: value), !wasAnsweredLocallyForVoIPCallKit(),
              let payload = IncomingPeerCallPayload(userInfo: storedUserInfoIfFresh()) else { return }
        PeerCallNotifications.shared.finish(callUUID: uuid, disposition: .missed)
        endStoredActiveCallViaProvider(reason: .unanswered)
        Self.clearStoredIncomingPayload()
        WebRTCCallManager.shared.dismissUnansweredIncomingRing(channelId: payload.channelId, callerId: payload.callerId)
        WebRTCCallManager.shared.abandonIncomingPresentation()
    }

    func wasAnsweredLocallyForVoIPCallKit() -> Bool {
        let hasUUID = hasStoredActiveVoIPCallUUID()
        let hasPayload = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) != nil
        return hasUUID && !hasPayload
    }

    func currentRingingOfferSentAtMs() -> Int64? {
        guard hasStoredActiveVoIPCallUUID(), !wasAnsweredLocallyForVoIPCallKit() else { return nil }
        guard let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) else { return nil }
        return IncomingPeerCallPayloadParser.offerCreatedAtMs(pushJsonData: info["pushJsonData"] as? String)
    }

    func currentRingingOfferSessionId() -> String? {
        guard hasStoredActiveVoIPCallUUID(), !wasAnsweredLocallyForVoIPCallKit(),
              let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload),
              let payload = IncomingPeerCallPayload(userInfo: info),
              let offer = payload.resolvedCompressedOffer(),
              let json = try? PeerWebRTCStringCompression.decompressSignalingJson(offer),
              let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return IncomingPeerCallPayloadParser.sdpSessionId(value["sdp"] as? String)
    }

    private func markRecentlyEnded(channelId: Int64, callerId: Int64) {
        guard channelId != 0 || callerId != 0 else { return }
        let key = RecentlyEndedKey(channelId: channelId, callerId: callerId)
        let now = Date()
        recentlyEndedLock.lock()
        recentlyEndedAt[key] = now
        let cutoff = now.addingTimeInterval(-recentlyEndedRetention)
        recentlyEndedAt = recentlyEndedAt.filter { $0.value >= cutoff }
        recentlyEndedLock.unlock()
    }

    private func wasRecentlyEnded(channelId: Int64, callerId: Int64) -> Bool {
        let key = RecentlyEndedKey(channelId: channelId, callerId: callerId)
        let cutoff = Date().addingTimeInterval(-recentlyEndedRetention)
        recentlyEndedLock.lock()
        defer { recentlyEndedLock.unlock() }
        guard let ts = recentlyEndedAt[key] else { return false }
        return ts >= cutoff
    }

    private func wasAnyCallRecentlyEnded(within seconds: TimeInterval) -> Bool {
        let cutoff = Date().addingTimeInterval(-seconds)
        recentlyEndedLock.lock()
        defer { recentlyEndedLock.unlock() }
        for ts in recentlyEndedAt.values where ts >= cutoff {
            return true
        }
        return false
    }

    private func setLastRingedCall(channelId: Int64, callerId: Int64) {
        guard channelId != 0, callerId != 0 else { return }
        lastRingedCallLock.lock()
        lastRingedCall = LastRingedCall(channelId: channelId, callerId: callerId, at: Date())
        lastRingedCallLock.unlock()
        clearPushDedupFor(channelId: channelId, callerId: callerId)
        clearRecentlyEndedFor(channelId: channelId, callerId: callerId)
    }

    private func clearRecentlyEndedFor(channelId: Int64, callerId: Int64) {
        let key = RecentlyEndedKey(channelId: channelId, callerId: callerId)
        recentlyEndedLock.lock()
        recentlyEndedAt.removeValue(forKey: key)
        recentlyEndedLock.unlock()
    }

    private func clearPushDedupFor(channelId: Int64, callerId: Int64) {
        recentPushDedupLock.lock()
        recentPushDedup = recentPushDedup.filter { !($0.key.channelId == channelId && $0.key.callerId == callerId) }
        recentPushDedupLock.unlock()
    }

    private func recentlyRingedCallIds() -> (channelId: Int64, callerId: Int64)? {
        lastRingedCallLock.lock()
        defer { lastRingedCallLock.unlock() }
        guard let last = lastRingedCall else { return nil }
        guard Date().timeIntervalSince(last.at) <= lastRingedCallFallbackWindow else { return nil }
        return (last.channelId, last.callerId)
    }

    private func dedupHitAndStamp(kind: String, channelId: Int64, callerId: Int64) -> Bool {
        let key = PushDedupKey(kind: kind, channelId: channelId, callerId: callerId)
        let now = Date()
        let cutoff = now.addingTimeInterval(-pushDedupWindow)
        recentPushDedupLock.lock()
        defer { recentPushDedupLock.unlock() }
        recentPushDedup = recentPushDedup.filter { $0.value >= cutoff }
        if let prev = recentPushDedup[key], prev >= cutoff {
            recentPushDedup[key] = now
            return true
        }
        recentPushDedup[key] = now
        return false
    }

    private func offerDedupDigest(_ offerStr: String) -> String {
        if offerStr.count <= 96 { return offerStr }
        let head = offerStr.prefix(64)
        let tail = offerStr.suffix(32)
        return "\(head)|\(offerStr.count)|\(tail)"
    }

    private func offerWasSeenRecently(_ offerStr: String) -> Bool {
        let digest = offerDedupDigest(offerStr)
        let now = Date()
        let cutoff = now.addingTimeInterval(-offerDedupWindow)
        recentOfferDigestsLock.lock()
        defer { recentOfferDigestsLock.unlock() }
        recentOfferDigests = recentOfferDigests.filter { $0.value >= cutoff }
        if let prev = recentOfferDigests[digest], prev >= cutoff {
            recentOfferDigests[digest] = now
            return true
        }
        recentOfferDigests[digest] = now
        return false
    }

    private func markRecentlyEndedFromStoredPayloadIfPossible() {
        guard let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) else { return }
        let channelId = int64(info["channelId"]) ?? 0
        let callerId = int64(info["callerId"]) ?? 0
        markRecentlyEnded(channelId: channelId, callerId: callerId)
    }

    private func markRecentlyEndedFromQuitSnapshotIfPossible() {
        guard let snap = Self.readVoipQuitSnapshot() else { return }
        markRecentlyEnded(channelId: snap.channelId, callerId: snap.callerId)
    }

    func clearVoipQuitSnapshot() {
        Self.clearVoipQuitSnapshotStorage()
    }

    @MainActor
    func endRingingCallIfMatching(channelId: Int64, callerId: Int64, remoteIsConnected: Bool = false, cancelSentAtMs: Int64? = nil) {
        guard channelId != 0 else {
            return
        }
        if let c = cancelSentAtMs, let r = currentRingingOfferSentAtMs(), c < r {
            return
        }
        let storedChannelId: Int64
        let storedCallerId: Int64
        let source: String
        if let info = storedUserInfoIfFresh() {
            storedChannelId = int64(info["channelId"]) ?? 0
            storedCallerId = int64(info["callerId"]) ?? 0
            source = "storedPayload"
        } else if let snap = Self.readVoipQuitSnapshot() {
            storedChannelId = snap.channelId
            storedCallerId = snap.callerId
            source = "quitSnapshot"
        } else {
            return
        }
        let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: 0) ?? 0
        let channelMatches = storedChannelId == channelId
        let callerMatches = (callerId == 0) || (storedCallerId == callerId) || (myId != 0 && callerId == myId)
        guard channelMatches, callerMatches else {
            return
        }
        if remoteIsConnected && wasAnsweredLocallyForVoIPCallKit() {
            return
        }
        noteIncomingCallDisposition(remoteIsConnected ? .answeredElsewhere : .missed,
                                    channelId: storedChannelId, callerId: storedCallerId)
        markRecentlyEnded(channelId: storedChannelId, callerId: storedCallerId)
        let reason: CXCallEndedReason = remoteIsConnected ? .answeredElsewhere : .remoteEnded
        endStoredActiveCallViaProvider(reason: reason)
        requestEndActiveVoIPCallIfNeeded()
        Self.clearStoredIncomingPayload()
    }

    private static func clearVoipQuitSnapshotStorage() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotChannelId)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotCallerId)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.quitSnapshotReceiverId)
        UserDefaults.standard.synchronize()
    }

    private static func storeVoipQuitSnapshot(channelId: Int64, callerId: Int64, receiverId: Int64) {
        UserDefaults.standard.set(NSNumber(value: channelId), forKey: DefaultsKeys.quitSnapshotChannelId)
        UserDefaults.standard.set(NSNumber(value: callerId), forKey: DefaultsKeys.quitSnapshotCallerId)
        UserDefaults.standard.set(NSNumber(value: receiverId), forKey: DefaultsKeys.quitSnapshotReceiverId)
        UserDefaults.standard.synchronize()
    }

    private static func readVoipQuitSnapshot() -> (channelId: Int64, callerId: Int64, receiverId: Int64)? {
        guard let ch = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotChannelId) as? NSNumber,
              let ca = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotCallerId) as? NSNumber
        else { return nil }
        let rec = UserDefaults.standard.object(forKey: DefaultsKeys.quitSnapshotReceiverId) as? NSNumber
        let channelId = ch.int64Value
        let callerId = ca.int64Value
        let receiverId = rec?.int64Value ?? 0
        guard channelId != 0, callerId != 0 else { return nil }
        return (channelId, callerId, receiverId)
    }

    private func persistVoipQuitSnapshotFromIncomingPayload(_ info: [AnyHashable: Any]) {
        guard let channelId = int64(info["channelId"]), channelId != 0,
              let callerId = int64(info["callerId"]), callerId != 0 else { return }
        let receiverId = int64(info["receiverId"]) ?? 0
        Self.storeVoipQuitSnapshot(channelId: channelId, callerId: callerId, receiverId: receiverId)
    }

    func invalidateStoredVoIPPayloadOnly() {
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
    }

    private func forwardQuitToCallerFromStoredVoIPIfNeeded() {
        let channelId: Int64
        let callerId: Int64
        let receiverId: Int64
        if let info = storedUserInfoIfFresh(),
           let payload = IncomingPeerCallPayload(userInfo: info) {
            channelId = payload.channelId
            callerId = payload.callerId
            receiverId = payload.receiverId
        } else if let snap = Self.readVoipQuitSnapshot() {
            channelId = snap.channelId
            callerId = snap.callerId
            receiverId = snap.receiverId
        } else {
            return
        }
        let fallback = receiverId
        guard let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: fallback) else { return }
        guard receiverId == myId || receiverId == 0 else { return }
        Self.clearVoipQuitSnapshotStorage()
        Task { @MainActor in
            MezonSocket.shared.forwardWebrtcSignaling(
                receiverId: callerId,
                dataType: WebRTCSignalingDataType.sdpQuit,
                jsonData: "",
                channelId: channelId,
                callerId: myId
            )
        }
    }

    private static func clearStoredIncomingPayload() {
        VoIPMinimalCallBootstrap.clearMinimalChromeFlagOnly()
        clearVoipQuitSnapshotStorage()
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.activeCallUUID)
        UserDefaults.standard.removeObject(forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
    }

    private func storeIncomingUserInfo(_ info: [AnyHashable: Any], callUUID: UUID) {
        var dict: [String: Any] = [:]
        for (k, v) in info {
            if let ks = k as? String {
                dict[ks] = v
            }
        }
        UserDefaults.standard.set(dict, forKey: DefaultsKeys.notificationPayload)
        UserDefaults.standard.set(callUUID.uuidString, forKey: DefaultsKeys.activeCallUUID)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: DefaultsKeys.notificationTimestamp)
        UserDefaults.standard.synchronize()
        let wantsMinimalChrome = UIApplication.shared.applicationState != .active
        VoIPMinimalCallBootstrap.activateForIncomingVoIPStoredPayload(wantsMinimalChrome: wantsMinimalChrome)
        if wantsMinimalChrome {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .mezonVoIPMinimalCallChromeActivated, object: nil)
            }
        }
    }

    private func storedUserInfoIfFresh() -> [AnyHashable: Any]? {
        if let ts = UserDefaults.standard.object(forKey: DefaultsKeys.notificationTimestamp) as? Double {
            if Date().timeIntervalSince1970 - ts > payloadValiditySeconds {
                Self.clearStoredIncomingPayload()
                return nil
            }
        }
        return UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload)
    }

    @MainActor
    func handleCallCancelRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let offerValue = userInfo["offer"],
              let inner = parseOfferInner(offerValue),
              (inner["offer"] as? String) == "CANCEL_CALL"
        else { return false }
        let (channelId, callerId) = resolveCancelCallIds(inner)
        guard channelId != 0, callerId != 0,
              let data = try? JSONSerialization.data(withJSONObject: inner),
              let jsonData = String(data: data, encoding: .utf8)
        else { return true }
        let receiverId = int64(inner["receiverId"]) ?? 0
        var push = Mezon_Realtime_IncomingCallPush()
        push.receiverID = receiverId
        push.jsonData = jsonData
        push.channelID = channelId
        push.callerID = callerId
        let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId) ?? 0
        WebRTCCallManager.shared.handleIncomingCallPush(push, currentUserId: myId)
        return true
    }

    private func resolveCancelCallIds(_ inner: [String: Any]) -> (channelId: Int64, callerId: Int64) {
        var channelId = int64(inner["channelId"]) ?? 0
        var callerId = int64(inner["callerId"]) ?? 0
        if channelId == 0 || callerId == 0 {
            if let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) {
                if channelId == 0 { channelId = int64(info["channelId"]) ?? 0 }
                if callerId == 0 { callerId = int64(info["callerId"]) ?? 0 }
            } else if let snap = Self.readVoipQuitSnapshot() {
                if channelId == 0 { channelId = snap.channelId }
                if callerId == 0 { callerId = snap.callerId }
            }
        }
        if (channelId == 0 || callerId == 0), let last = recentlyRingedCallIds() {
            if channelId == 0 { channelId = last.channelId }
            if callerId == 0 { callerId = last.callerId }
        }
        return (channelId, callerId)
    }

    private func handleVoIPDictionary(_ payloadDict: [AnyHashable: Any], completion: @escaping () -> Void) {
        let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: 0) ?? 0
        guard let offerValue = payloadDict["offer"] else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }

        guard let inner = parseOfferInner(offerValue) else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }
        let offerStr = inner["offer"] as? String ?? ""
        if offerStr == "CANCEL_CALL" {
            let (cancelChannelId, cancelCallerId) = resolveCancelCallIds(inner)
            let isSelfEcho = (myId != 0 && cancelCallerId == myId)
            let hadStoredUUID = hasStoredActiveVoIPCallUUID()
            let alreadyEndedRecently = wasRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
            let anyRecentEnd = wasAnyCallRecentlyEnded(within: recentlyEndedRetention)
            let remoteIsConnected = (inner["isConnected"] as? Bool)
                ?? ((inner["isConnected"] as? NSNumber)?.boolValue ?? false)
            let answeredLocally = wasAnsweredLocallyForVoIPCallKit()
            let cancelMatchesCurrentRing: Bool = {
                guard let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) else { return false }
                let storedChannelId = int64(info["channelId"]) ?? 0
                let storedCallerId = int64(info["callerId"]) ?? 0
                return cancelChannelId == storedChannelId
                    && (cancelCallerId == storedCallerId || (myId != 0 && cancelCallerId == myId))
            }()
            let cancelSentAtMs = IncomingPeerCallPayloadParser.sentAtMs(fromInnerDict: inner)
            let cancelPredatesCurrentRing: Bool = {
                if let cancelId = inner["callSessionId"] as? String,
                   let ringId = currentRingingOfferSessionId(), cancelId != ringId {
                    return true
                }
                guard let c = cancelSentAtMs, let r = currentRingingOfferSentAtMs() else { return false }
                return c < r
            }()

            if answeredLocally {
            } else if remoteIsConnected && hadStoredUUID && cancelMatchesCurrentRing && !alreadyEndedRecently && !cancelPredatesCurrentRing {
                noteIncomingCallDisposition(.answeredElsewhere, channelId: cancelChannelId, callerId: cancelCallerId)
                endStoredActiveCallViaProvider(reason: .answeredElsewhere)
                requestEndActiveVoIPCallIfNeeded()
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
            } else if hadStoredUUID && cancelMatchesCurrentRing && !alreadyEndedRecently && !cancelPredatesCurrentRing {
                noteIncomingCallDisposition(.missed, channelId: cancelChannelId, callerId: cancelCallerId)
                endStoredActiveCallViaProvider(reason: .remoteEnded)
                requestEndActiveVoIPCallIfNeeded()
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
            } else if !hadStoredUUID {
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
            }

            if !answeredLocally && !cancelPredatesCurrentRing {
                Task { @MainActor in
                    WebRTCCallManager.shared.dismissUnansweredIncomingRing(
                        channelId: cancelChannelId,
                        callerId: cancelCallerId
                    )
                }
            }

            if remoteIsConnected {
                reportImmediateEndedIncomingForVoIPCompliance(
                    localizedCallerName: Self.callKitComplianceDisplayLabel,
                    remoteHandleValue: Self.callKitComplianceDisplayLabel,
                    requiresVideoUpdate: false,
                    pushCompletion: completion
                )
                return
            }

            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: Self.callKitComplianceDisplayLabel,
                remoteHandleValue: Self.callKitComplianceDisplayLabel,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }

        guard !offerStr.isEmpty else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }

        let payloadCallerName = PeerCallCallerIdentity.nonEmpty(inner["callerName"] as? String)
        let callerName = payloadCallerName ?? "Incoming call"
        let callerAvatar = PeerCallCallerIdentity.nonEmpty(inner["callerAvatar"] as? String)
        let callerId = int64(inner["callerId"]) ?? 0
        let channelId = int64(inner["channelId"]) ?? 0
        let receiverId = int64(inner["receiverId"]) ?? 0

        guard channelId != 0, callerId != 0 else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }

        let innerJsonForFreshness: String? = {
            if let data = try? JSONSerialization.data(withJSONObject: inner, options: []),
                let s = String(data: data, encoding: .utf8)
            { return s }
            return nil
        }()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sentAtMsOpt = IncomingPeerCallPayloadParser.offerCreatedAtMs(pushJsonData: innerJsonForFreshness)
        let staleReason: String? = {
            guard let sentAtMs = sentAtMsOpt else { return nil }
            let ageMs = nowMs - sentAtMs
            if ageMs > PeerCallIncomingFreshness.maxOfferAgeMs {
                return "ageMs=\(ageMs) > windowMs=\(PeerCallIncomingFreshness.maxOfferAgeMs) (sentAt=\(sentAtMs) now=\(nowMs))"
            }
            return nil
        }()
        if let staleReason {
            markRecentlyEnded(channelId: channelId, callerId: callerId)
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }
        let isSelfEcho = (myId != 0 && callerId == myId)
        let isDuplicateOfferPush = offerWasSeenRecently(offerStr)
        _ = storedUserInfoIfFresh()
        let hadStoredUUID = hasStoredActiveVoIPCallUUID()
        if isSelfEcho {
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }
        if isDuplicateOfferPush
            || PeerCallKnownSessions.shared.contains(peerUserId: callerId, compressedSignal: offerStr) {
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }
        if hadStoredUUID {
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }

        let pushJsonData: String = {
            if let data = try? JSONSerialization.data(withJSONObject: inner, options: []),
               let s = String(data: data, encoding: .utf8) {
                return s
            }
            return ""
        }()

        presentIncomingCallRing(
            channelId: channelId,
            callerId: callerId,
            receiverId: receiverId,
            callerName: payloadCallerName,
            callerAvatar: callerAvatar,
            offerStr: offerStr,
            pushJsonData: pushJsonData,
            completion: completion
        )
    }

    private func presentIncomingCallRing(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        callerName: String?,
        callerAvatar: String?,
        offerStr: String,
        pushJsonData: String,
        completion: (() -> Void)?
    ) {
        PeerCallKnownSessions.shared.remember(peerUserId: callerId, compressedSignal: offerStr)
        var metadata = pushJsonData.data(using: .utf8).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        } ?? [:]
        metadata["callerName"] = callerName
        metadata["callerAvatar"] = callerAvatar ?? ""
        let displayJsonData = (try? JSONSerialization.data(withJSONObject: metadata))
            .flatMap { String(data: $0, encoding: .utf8) } ?? pushJsonData
        let userInfo: [AnyHashable: Any] = [
            "channelId": NSNumber(value: channelId),
            "callerId": NSNumber(value: callerId),
            "receiverId": NSNumber(value: receiverId),
            "compressedOfferFromPush": offerStr,
            "pushJsonData": displayJsonData,
        ]

        reassertMainProviderIfNeeded()
        guard let provider else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            if let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId) {
                Task { @MainActor in
                    WebRTCCallManager.shared.armIncomingSignalingBufferIfDetached(channelId: channelId, calleeUserId: myId)
                    WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(userInfo, currentUserId: myId)
                }
            }
            return
        }

        if let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId) {
            Task { @MainActor in
                WebRTCCallManager.shared.armIncomingSignalingBufferIfDetached(channelId: channelId, calleeUserId: myId)
                Self.startConnectivityPreWarm()
                WebRTCCallManager.shared.preWarmIncomingPeerCallIfNeeded(
                    channelId: channelId,
                    callerId: callerId,
                    receiverId: receiverId,
                    currentUserId: myId,
                    compressedOffer: offerStr
                )
            }
        }

        let callUUID = UUID()
        setLastRingedCall(channelId: channelId, callerId: callerId)
        storeIncomingUserInfo(userInfo, callUUID: callUUID)
        PeerCallNotifications.shared.begin(
            callUUID: callUUID, channelId: channelId, callerId: callerId, receiverId: receiverId,
            name: callerName ?? "Incoming call", avatarURL: callerAvatar, timeout: 75
        )

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId != 0 ? "\(callerId)" : (callerName ?? "Incoming call"))
        update.localizedCallerName = callerName ?? "Incoming call"
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        let gate = VoIPPushCompletionGate(completion ?? {})
        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            if let error {
                PeerCallNotifications.shared.finish(callUUID: callUUID, disposition: .discarded)
                Self.clearStoredIncomingPayload()
            } else {
                self?.scheduleUnansweredRingFailsafe(callUUID: callUUID, channelId: channelId, callerId: callerId)
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentIncomingCall(callUUID) else { return }
                    self.reportedIncomingCallUUID = callUUID
                    self.reportedIncomingPayload = IncomingPeerCallPayload(userInfo: userInfo)
                    if let payload = self.reportedIncomingPayload {
                        self.applyIncomingCallerIdentity(
                            PeerCallCallerIdentity(fallbackName: callerName, avatar: callerAvatar),
                            callUUID: callUUID, payload: payload
                        )
                    }
                    self.refreshIncomingCallerIdentityIfNeeded()
                }
            }
            gate.consume()
        }
    }

    @MainActor
    func ringIncomingFromSocketOfferIfNeeded(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        compressedOffer: String
    ) {
        let offerStr = compressedOffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard channelId != 0, callerId != 0, !offerStr.isEmpty else { return }
        guard let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: receiverId), callerId != myId else { return }
        guard receiverId == myId || receiverId == 0 else { return }
        guard WebRTCCallManager.shared.signalingSession == nil else { return }
        guard WebRTCCallManager.shared.hasPendingIncomingSocketOffer(channelId: channelId, callerId: callerId) else { return }
        _ = storedUserInfoIfFresh()
        guard !hasStoredActiveVoIPCallUUID() else { return }
        guard !PeerCallKnownSessions.shared.contains(peerUserId: callerId, compressedSignal: offerStr) else { return }
        guard !offerWasSeenRecently(offerStr) else { return }
        let display = IncomingPeerCallPayloadParser.callerDisplayFromCompressedOffer(offerStr)
        presentIncomingCallRing(
            channelId: channelId,
            callerId: callerId,
            receiverId: receiverId,
            callerName: display.name,
            callerAvatar: display.avatar,
            offerStr: offerStr,
            pushJsonData: "",
            completion: nil
        )
    }

    @MainActor
    func refreshIncomingCallerIdentityIfNeeded() {
        guard let rawUUID = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let callUUID = UUID(uuidString: rawUUID), callUUID == reportedIncomingCallUUID,
              callerIdentityCallUUID != callUUID,
              let payload = IncomingPeerCallPayload(userInfo: storedUserInfoIfFresh()) ?? reportedIncomingPayload,
              let context = VoIPAnswerAccountBridge.context,
              let localUserId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: payload.receiverId),
              Int64(context.currentUser?.id ?? context.session?.userId ?? "") == localUserId,
              payload.receiverId == 0 || payload.receiverId == localUserId else { return }

        callerIdentityTask?.cancel()
        callerIdentityCallUUID = callUUID
        callerIdentityPeer = (payload.channelId, payload.callerId)
        appliedCallerIdentity = nil
        let epoch = context.sessionEpoch
        let display = IncomingPeerCallPayloadParser.callerDisplay(for: payload, skipDecompressOffer: false, context: context)
        let cachedIdentity = PeerCallCallerIdentity(fallbackName: display.name, avatar: display.avatar)
        applyIncomingCallerIdentity(cachedIdentity, callUUID: callUUID, payload: payload)

        // The PushKit call is already reported. Profile/image work must never delay reporting or completion.
        callerIdentityTask = Task { @MainActor [weak self, weak context] in
            guard let self, let context,
                  self.isCurrentIncomingCall(callUUID), VoIPAnswerAccountBridge.context === context,
                  context.isStillCurrentSession(epoch: epoch), !Task.isCancelled,
                  let token = await context.getTokenPreferringCachedSkipSessionReadyWait(),
                  self.isCurrentIncomingCall(callUUID), VoIPAnswerAccountBridge.context === context,
                  context.isStillCurrentSession(epoch: epoch),
                  !Task.isCancelled else { return }
            guard let channels = try? await context.account.network.listDirectMessageChannels(token: token),
                  self.isCurrentIncomingCall(callUUID), VoIPAnswerAccountBridge.context === context,
                  context.isStillCurrentSession(epoch: epoch),
                  !Task.isCancelled,
                  channels.contains(where: { $0.channelID == payload.channelId && $0.userIds.contains(payload.callerId) })
            else { return }
            let fresh = PeerCallCallerIdentityResolver.resolve(
                context: context, callerId: payload.callerId, channelId: payload.channelId,
                fallbackName: display.name, fallbackAvatar: display.avatar, channels: channels
            )
            self.applyIncomingCallerIdentity(fresh, callUUID: callUUID, payload: payload)
        }
    }

    private func isCurrentIncomingCall(_ callUUID: UUID) -> Bool {
        UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) == callUUID.uuidString
    }

    @MainActor
    func incomingCallerIdentity(callerId: Int64, channelId: Int64) -> PeerCallCallerIdentity? {
        guard let callUUID = callerIdentityCallUUID, isCurrentIncomingCall(callUUID),
              let peer = callerIdentityPeer, peer.callerId == callerId, peer.channelId == channelId else { return nil }
        return appliedCallerIdentity
    }

    @MainActor
    private func applyIncomingCallerIdentity(_ identity: PeerCallCallerIdentity, callUUID: UUID, payload: IncomingPeerCallPayload) {
        guard isCurrentIncomingCall(callUUID), appliedCallerIdentity != identity else { return }
        appliedCallerIdentity = identity
        PeerCallNotifications.shared.updateIdentity(callUUID: callUUID, name: identity.name, avatarURL: identity.avatar)
        let update = CXCallUpdate()
        update.localizedCallerName = identity.name
        provider?.reportCall(with: callUUID, updated: update)

        // Keep the metadata used after answering consistent with the system call name.
        if var info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) {
            var metadata = (info["pushJsonData"] as? String)?.data(using: .utf8).flatMap {
                (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
            } ?? [:]
            metadata["callerName"] = identity.name
            metadata["callerAvatar"] = identity.avatar ?? ""
            if let data = try? JSONSerialization.data(withJSONObject: metadata),
               let json = String(data: data, encoding: .utf8) {
                info["pushJsonData"] = json
                UserDefaults.standard.set(info, forKey: DefaultsKeys.notificationPayload)
            }
        }
        NotificationCenter.default.post(name: .mezonPeerCallCallerIdentityDidUpdate, object: nil, userInfo: [
            "channelId": payload.channelId, "callerId": payload.callerId,
            "callerName": identity.name, "callerAvatar": identity.avatar ?? "",
        ])
        donateIncomingCallIdentity(identity, callUUID: callUUID, callerId: payload.callerId)
    }

    @MainActor
    private func donateIncomingCallIdentity(_ identity: PeerCallCallerIdentity, callUUID: UUID, callerId: Int64) {
        guard #available(iOS 14.0, *) else { return }
        let context = VoIPAnswerAccountBridge.context
        let epoch = context?.sessionEpoch
        let donate: @MainActor (Data?) -> Void = { [weak self, weak context] avatarData in
            guard let self,
                  self.isCurrentIncomingCall(callUUID), self.appliedCallerIdentity == identity else { return }
            if let epoch {
                guard let context, VoIPAnswerAccountBridge.context === context,
                      context.isStillCurrentSession(epoch: epoch) else { return }
            }
            // Public communication-intent metadata; CXCallUpdate has no public caller-image property.
            // Rendering this avatar in the system CallKit banner remains controlled by iOS.
            let intent = PeerCallCommunicationIdentity.callIntent(callerId: callerId, name: identity.name, avatarData: avatarData)
            let interaction = INInteraction(intent: intent, response: nil)
            interaction.identifier = callUUID.uuidString
            interaction.direction = .incoming
            interaction.donate { error in
                if let error {
                    NSLog("[CallKit] Incoming caller intent donation failed: %@", error.localizedDescription)
                }
            }
        }
        PeerCallCommunicationIdentity.loadAvatarData(url: identity.avatar) { data in
            Task { @MainActor in donate(data) }
        }
    }

    private func scheduleUnansweredRingFailsafe(callUUID: UUID, channelId: Int64, callerId: Int64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 75) { [weak self] in
            self?.endRingIfStillUnanswered(callUUID: callUUID, channelId: channelId, callerId: callerId)
        }
    }

    private func endRingIfStillUnanswered(callUUID: UUID, channelId: Int64, callerId: Int64) {
        guard let stored = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              stored == callUUID.uuidString,
              !wasAnsweredLocallyForVoIPCallKit()
        else { return }
        markRecentlyEnded(channelId: channelId, callerId: callerId)
        PeerCallNotifications.shared.finish(callUUID: callUUID, disposition: .missed)
        provider?.reportCall(with: callUUID, endedAt: Date(), reason: .unanswered)
        Self.clearStoredIncomingPayload()
        Task { @MainActor in
            WebRTCCallManager.shared.abandonIncomingPresentation()
        }
    }

    @MainActor
    private static func startConnectivityPreWarm() {
        if let ctx = VoIPAnswerAccountBridge.context {
            Task { @MainActor in
                _ = await ctx.prepareForVoIPAnswerConnectivity()
            }
        } else if let tok = SessionStore.load()?.token, !MezonSocket.shared.isConnected {
            MezonSocket.shared.connect(token: tok, wsHostOverride: nil)
        }
    }

    private func parseOfferInner(_ offerValue: Any) -> [String: Any]? {
        if let s = offerValue as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "CANCEL_CALL" {
                return ["offer": "CANCEL_CALL"]
            }
            if let data = trimmed.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return obj
            }
            return nil
        }
        if let obj = offerValue as? [String: Any] {
            return obj
        }
        return nil
    }

    private func int64(_ any: Any?) -> Int64? {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? NSNumber { return v.int64Value }
        if let v = any as? String { return Int64(v) }
        return nil
    }

    private static func resolveLocalUserIdForVoIP(fallbackReceiverId: Int64) -> Int64? {
        if let uidStr = SessionStore.load()?.userId, let v = Int64(uidStr), v != 0 {
            return v
        }
        if fallbackReceiverId != 0 {
            return fallbackReceiverId
        }
        return nil
    }

    private func reportImmediateEndedIncomingForVoIPCompliance(
        localizedCallerName: String,
        remoteHandleValue: String,
        requiresVideoUpdate: Bool,
        pushCompletion: @escaping () -> Void
    ) {
        let rp = makeTransientSilentComplianceProvider()
        let ephemeralUUID = UUID()
        markComplianceCall(ephemeralUUID)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remoteHandleValue)
        update.localizedCallerName = localizedCallerName
        update.hasVideo = requiresVideoUpdate
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        rp.reportNewIncomingCall(with: ephemeralUUID, update: update) { [weak self] error in
            if error == nil {
                rp.reportCall(with: ephemeralUUID, endedAt: Date(), reason: .failed)
            }
            self?.unmarkComplianceCall(ephemeralUUID)
            DispatchQueue.main.async {
                self?.scheduleComplianceProviderInvalidation(rp)
            }
            pushCompletion()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            rp.reportCall(with: ephemeralUUID, endedAt: Date(), reason: .failed)
        }
    }

    private func reportAndEndPlaceholderCall(reason: CXCallEndedReason, pushCompletion: (() -> Void)? = nil) {
        let rp = makeTransientSilentComplianceProvider()
        let placeholderUUID = UUID()
        markComplianceCall(placeholderUUID)
        let alreadyEndedAt = Date(timeIntervalSinceNow: -2)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: Self.callKitComplianceDisplayLabel)
        update.localizedCallerName = Self.callKitComplianceDisplayLabel
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        rp.reportNewIncomingCall(with: placeholderUUID, update: update) { [weak self] error in
            if error == nil {
                rp.reportCall(with: placeholderUUID, endedAt: alreadyEndedAt, reason: reason)
            }
            self?.unmarkComplianceCall(placeholderUUID)
            DispatchQueue.main.async {
                self?.scheduleComplianceProviderInvalidation(rp)
            }
            pushCompletion?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            rp.reportCall(with: placeholderUUID, endedAt: alreadyEndedAt, reason: reason)
        }
    }
}

extension CallKitManager: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        voipToken = token
        NotificationCenter.default.post(name: .mezonVoIPTokenDidUpdate, object: nil, userInfo: ["token": token])
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        voipToken = nil
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }
        ensureProviderConfigured()
        handleVoIPDictionary(payload.dictionaryPayload, completion: completion)
    }
}

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ resetProvider: CXProvider) {
        guard resetProvider === provider else { return }
        noteIncomingCallDisposition(.missed)
        clearComplianceCalls()
        Task { @MainActor in
            WebRTCCallManager.shared.endActivePeerCallFromCallKitAction()
        }
        Self.clearStoredIncomingPayload()
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if isComplianceCall(action.callUUID) {
            action.fulfill()
            return
        }
        PeerCallNotifications.shared.finish(callUUID: action.callUUID, disposition: .answered)
        guard let info = storedUserInfoIfFresh() else {
            Task { @MainActor in
                WebRTCCallManager.shared.abandonIncomingPresentation()
                action.fulfill()
            }
            return
        }
        let fallback = int64(info["receiverId"]) ?? 0
        guard let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: fallback) else {
            action.fulfill()
            return
        }
        let payload = info
        persistVoipQuitSnapshotFromIncomingPayload(payload)
        invalidateStoredVoIPPayloadOnly()
        preconfigureAudioSessionForIncomingAnswer()
        action.fulfill(withDateConnected: Date())
        Task { @MainActor in
            var bgId = UIBackgroundTaskIdentifier.invalid
            bgId = UIApplication.shared.beginBackgroundTask(withName: "mezon.voip.answer") {
                UIApplication.shared.endBackgroundTask(bgId)
                bgId = .invalid
            }
            defer {
                if bgId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgId)
                    bgId = .invalid
                }
            }
            WebRTCCallManager.shared.prepareIncomingCallFromVoIPUserInfo(payload, currentUserId: myId)
            var prepared = false
            if let ctx = VoIPAnswerAccountBridge.context {
                prepared = await ctx.prepareForVoIPAnswerConnectivity()
            }
            if !prepared, let tok = SessionStore.load()?.token, !MezonSocket.shared.isConnected {
                MezonSocket.shared.connect(token: tok, wsHostOverride: nil)
            }
        }
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        if isComplianceCall(action.callUUID) {
            action.fulfill()
            return
        }
        PeerCallNotifications.shared.finish(callUUID: action.callUUID, disposition: .rejected)
        markRecentlyEndedFromStoredPayloadIfPossible()
        markRecentlyEndedFromQuitSnapshotIfPossible()
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Task { @MainActor in
            WebRTCCallManager.shared.endActivePeerCallFromCallKitAction()
            WebRTCCallManager.shared.abandonIncomingPresentation()
            Self.clearStoredIncomingPayload()
        }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        if let callAction = action as? CXCallAction, isComplianceCall(callAction.callUUID) {
            return
        }
        noteIncomingCallDisposition(.missed)
        markRecentlyEndedFromStoredPayloadIfPossible()
        markRecentlyEndedFromQuitSnapshotIfPossible()
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Task { @MainActor in
            WebRTCCallManager.shared.endActivePeerCallFromCallKitAction()
            WebRTCCallManager.shared.abandonIncomingPresentation()
            Self.clearStoredIncomingPayload()
        }
    }

    private func preconfigureAudioSessionForIncomingAnswer() {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let cfg = RTCAudioSessionConfiguration.webRTC()
        cfg.category = AVAudioSession.Category.playAndRecord.rawValue
        cfg.mode = AVAudioSession.Mode.voiceChat.rawValue
        cfg.categoryOptions = [.allowBluetoothHFP, .allowBluetoothA2DP]
        try? rtc.setConfiguration(cfg)
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(audioSession)
        rtc.isAudioEnabled = true
        NotificationCenter.default.post(name: .mezonCallKitAudioActivated, object: nil)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.isAudioEnabled = false
        rtc.audioSessionDidDeactivate(audioSession)
        NotificationCenter.default.post(name: .mezonCallKitAudioReleased, object: nil)
    }
}
