import AVFoundation
import CallKit
import Darwin
import Foundation
import WebRTC
import PushKit
import UIKit

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

    private func wasAnsweredLocallyForVoIPCallKit() -> Bool {
        let hasUUID = hasStoredActiveVoIPCallUUID()
        let hasPayload = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) != nil
        return hasUUID && !hasPayload
    }

    func currentRingingOfferSentAtMs() -> Int64? {
        guard hasStoredActiveVoIPCallUUID(), !wasAnsweredLocallyForVoIPCallKit() else { return nil }
        guard let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) else { return nil }
        return IncomingPeerCallPayloadParser.offerCreatedAtMs(pushJsonData: info["pushJsonData"] as? String)
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
        let originalCancelChannelId = int64(inner["channelId"]) ?? 0
        let originalCancelCallerId = int64(inner["callerId"]) ?? 0
        var cancelChannelId = originalCancelChannelId
        var cancelCallerId = originalCancelCallerId
        if offerStr == "CANCEL_CALL" {
            if cancelChannelId == 0 || cancelCallerId == 0 {
                if let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) {
                    if cancelChannelId == 0 { cancelChannelId = int64(info["channelId"]) ?? 0 }
                    if cancelCallerId == 0 { cancelCallerId = int64(info["callerId"]) ?? 0 }
                } else if let snap = Self.readVoipQuitSnapshot() {
                    if cancelChannelId == 0 { cancelChannelId = snap.channelId }
                    if cancelCallerId == 0 { cancelCallerId = snap.callerId }
                }
            }
            if (cancelChannelId == 0 || cancelCallerId == 0), let last = recentlyRingedCallIds() {
                if cancelChannelId == 0 { cancelChannelId = last.channelId }
                if cancelCallerId == 0 { cancelCallerId = last.callerId }
            }
            let cancelHadOriginalIds = (originalCancelChannelId != 0 && originalCancelCallerId != 0)
            let isSelfEcho = (myId != 0 && cancelCallerId == myId)
            let hadStoredUUID = hasStoredActiveVoIPCallUUID()
            let alreadyEndedRecently = wasRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
            let anyRecentEnd = wasAnyCallRecentlyEnded(within: recentlyEndedRetention)
            let remoteIsConnected = (inner["isConnected"] as? Bool)
                ?? ((inner["isConnected"] as? NSNumber)?.boolValue ?? false)
            let answeredLocally = wasAnsweredLocallyForVoIPCallKit()
            let cancelSentAtMs = IncomingPeerCallPayloadParser.sentAtMs(fromInnerDict: inner)
            let cancelPredatesCurrentRing: Bool = {
                guard let c = cancelSentAtMs, let r = currentRingingOfferSentAtMs() else { return false }
                return c < r
            }()

            if remoteIsConnected && answeredLocally {
            } else if remoteIsConnected && hadStoredUUID && !alreadyEndedRecently && !cancelPredatesCurrentRing {
                endStoredActiveCallViaProvider(reason: .answeredElsewhere)
                requestEndActiveVoIPCallIfNeeded()
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
            } else if hadStoredUUID && !alreadyEndedRecently && !cancelPredatesCurrentRing {
                endStoredActiveCallViaProvider(reason: .remoteEnded)
                requestEndActiveVoIPCallIfNeeded()
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
            } else if !hadStoredUUID {
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
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

        let callerName = inner["callerName"] as? String ?? "Unknown"
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
        if isDuplicateOfferPush {
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
            callerName: callerName,
            offerStr: offerStr,
            pushJsonData: pushJsonData,
            completion: completion
        )
    }

    private func presentIncomingCallRing(
        channelId: Int64,
        callerId: Int64,
        receiverId: Int64,
        callerName: String,
        offerStr: String,
        pushJsonData: String,
        completion: (() -> Void)?
    ) {
        let userInfo: [AnyHashable: Any] = [
            "channelId": NSNumber(value: channelId),
            "callerId": NSNumber(value: callerId),
            "receiverId": NSNumber(value: receiverId),
            "compressedOfferFromPush": offerStr,
            "pushJsonData": pushJsonData,
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

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId != 0 ? "\(callerId)" : callerName)
        update.localizedCallerName = callerName
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        let gate = VoIPPushCompletionGate(completion ?? {})
        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            if let error {
                Self.clearStoredIncomingPayload()
            } else {
                self?.scheduleUnansweredRingFailsafe(callUUID: callUUID, channelId: channelId, callerId: callerId)
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
        guard !offerWasSeenRecently(offerStr) else { return }
        let display = IncomingPeerCallPayloadParser.callerDisplayFromCompressedOffer(offerStr)
        let callerName: String = {
            if let n = display.name, !n.isEmpty { return n }
            return "Incoming call"
        }()
        presentIncomingCallRing(
            channelId: channelId,
            callerId: callerId,
            receiverId: receiverId,
            callerName: callerName,
            offerStr: offerStr,
            pushJsonData: "",
            completion: nil
        )
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
