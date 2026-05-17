import AVFoundation
import CallKit
import Darwin
import Foundation
import LiveKitWebRTC
import PushKit
import UIKit
import os

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
    private var silentReportProvider: CXProvider?
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

    private static let unifiedCallKitOSLog = OSLog(subsystem: "chat.mezon.voip", category: "CallKit")

    private static let unifiedCallKitMirrorOSLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "MezonChat",
        category: "VoIPCallKit"
    )

    private static let voipInstantSubsystemOSLog = OSLog(subsystem: "chat.mezon.voip", category: "Instant")

    private static let voipInstantMirrorOSLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "MezonChat",
        category: "VoIPInstant"
    )

    private static func emitCallKitUnifiedDebug(_ message: String) {
        print("[CallKitDebug] \(message)")
        NSLog("[CallKitDebug][chat.mezon.voip] %@", message)
        os_log("%{public}@", log: unifiedCallKitOSLog, type: .default, message as NSString as CVarArg)
        os_log("%{public}@", log: unifiedCallKitMirrorOSLog, type: .default, message as NSString as CVarArg)
    }

    private static let voipInstantDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func voipInstantFlushPrint(_ message: String) {
        let stamp = voipInstantDateFormatter.string(from: Date())
        let line = "[VoIP-INSTANT \(stamp)] \(message)"
        print(line)
        NSLog("%@", line)
        os_log("%{public}@", log: voipInstantSubsystemOSLog, type: .default, line as NSString as CVarArg)
        os_log("%{public}@", log: voipInstantMirrorOSLog, type: .default, line as NSString as CVarArg)
        if let data = (line + "\n").data(using: .utf8) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardError.write(data)
        }
        fflush(__stdoutp)
        fflush(__stderrp)
    }

    private static func voipInstantPrintPayload(_ dictionaryPayload: [AnyHashable: Any]) {
        let jsonObj = NSDictionary(dictionary: dictionaryPayload)
        if JSONSerialization.isValidJSONObject(jsonObj),
           let data = try? JSONSerialization.data(withJSONObject: jsonObj, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            voipInstantFlushPrint("payload JSON \(s)")
        } else {
            voipInstantFlushPrint("payload non-json-safe \(dictionaryPayload)")
        }
    }

    private func callKitUnifiedDebug(_ message: String) {
        Self.emitCallKitUnifiedDebug(message)
    }

    private override init() {
        super.init()
    }

    func configure() {
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.isAudioEnabled = false

        pushRegistry.delegate = self
        pushRegistry.desiredPushTypes = [.voIP]

        ensureProviderConfigured()
        Self.emitCallKitUnifiedDebug(
            "CallKitManager.configure() unifiedSubsystem=chat.mezon.voip mirrorSubsystem=\(Bundle.main.bundleIdentifier ?? "nil") categoryMirror=VoIPCallKit"
        )
    }

    private func ensureProviderConfigured() {
        guard provider == nil else { return }
        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = nil
        config.includesCallsInRecents = false

        let prov = CXProvider(configuration: config)
        prov.setDelegate(self, queue: nil)
        provider = prov
    }

    private func ensureSilentReportProviderConfigured() {
        guard silentReportProvider == nil else { return }
        let config = CXProviderConfiguration(localizedName: "Mezon")
        config.supportsVideo = true
        config.maximumCallsPerCallGroup = 1
        config.maximumCallGroups = 1
        config.supportedHandleTypes = [.generic]
        config.ringtoneSound = "mezon_callkit_silent.caf"
        config.includesCallsInRecents = false
        let prov = CXProvider(configuration: config)
        prov.setDelegate(self, queue: nil)
        silentReportProvider = prov
    }

    func requestEndActiveVoIPCallIfNeeded() {
        markRecentlyEndedFromStoredPayloadIfPossible()
        markRecentlyEndedFromQuitSnapshotIfPossible()
        guard let uuidString = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: uuidString)
        else {
            callKitUnifiedDebug("requestEndActiveVoIPCallIfNeeded -> no activeCallUUID, skipping CXEndCallAction (raw=\(UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) ?? "nil"))")
            return
        }
        callKitUnifiedDebug("requestEndActiveVoIPCallIfNeeded -> force provider.reportCall + submitting CXEndCallAction uuid=\(uuid.uuidString)")
        if let provider {
            provider.reportCall(with: uuid, endedAt: Date(), reason: .remoteEnded)
        } else {
            callKitUnifiedDebug("requestEndActiveVoIPCallIfNeeded -> provider is NIL, skipping force reportCall")
        }
        let action = CXEndCallAction(call: uuid)
        let tx = CXTransaction(action: action)
        callController.request(tx) { [weak self] error in
            if let error {
                self?.callKitUnifiedDebug("CXEndCallAction request callback ERROR uuid=\(uuid.uuidString) error=\(error.localizedDescription) ns=\((error as NSError).domain)/\((error as NSError).code)")
            } else {
                self?.callKitUnifiedDebug("CXEndCallAction request callback SUCCESS uuid=\(uuid.uuidString) (provider delegate may follow)")
            }
            Self.clearStoredIncomingPayload()
        }
    }

    @discardableResult
    private func endStoredActiveCallViaProvider(reason: CXCallEndedReason) -> Bool {
        guard let provider else {
            callKitUnifiedDebug("endStoredActiveCallViaProvider -> provider is NIL, cannot reportCall")
            return false
        }
        guard let uuidString = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID),
              let uuid = UUID(uuidString: uuidString)
        else {
            callKitUnifiedDebug("endStoredActiveCallViaProvider -> no activeCallUUID in UserDefaults (raw=\(UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) ?? "nil"))")
            return false
        }
        callKitUnifiedDebug("endStoredActiveCallViaProvider -> provider.reportCall uuid=\(uuid.uuidString) reason=\(reasonDescription(reason))")
        provider.reportCall(with: uuid, endedAt: Date(), reason: reason)
        callKitUnifiedDebug("endStoredActiveCallViaProvider -> provider.reportCall returned (sync void), assuming dispatched OK")
        return true
    }

    private func reasonDescription(_ reason: CXCallEndedReason) -> String {
        switch reason {
        case .failed: return "failed"
        case .remoteEnded: return "remoteEnded"
        case .unanswered: return "unanswered"
        case .answeredElsewhere: return "answeredElsewhere"
        case .declinedElsewhere: return "declinedElsewhere"
        @unknown default: return "unknown(\(reason.rawValue))"
        }
    }

    private func dumpVoIPState(tag: String) {
        let providerOK = provider != nil
        let activeUUID = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) ?? "nil"
        let payloadKeys: String
        if let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) {
            payloadKeys = info.map { "\($0.key)=\(describeValue($0.value))" }.sorted().joined(separator: ", ")
        } else {
            payloadKeys = "nil"
        }
        let lastRinged: String
        lastRingedCallLock.lock()
        if let last = lastRingedCall {
            lastRinged = "(channelId=\(last.channelId), callerId=\(last.callerId), ageSec=\(String(format: "%.2f", Date().timeIntervalSince(last.at))))"
        } else {
            lastRinged = "nil"
        }
        lastRingedCallLock.unlock()
        let recentlyEnded: String
        recentlyEndedLock.lock()
        recentlyEnded = recentlyEndedAt.map { "(ch=\($0.key.channelId), caller=\($0.key.callerId), ageSec=\(String(format: "%.2f", Date().timeIntervalSince($0.value))))" }.sorted().joined(separator: " | ")
        recentlyEndedLock.unlock()
        callKitUnifiedDebug("STATE@\(tag) providerOK=\(providerOK) activeCallUUID=\(activeUUID) storedPayload={\(payloadKeys)} lastRingedCall=\(lastRinged) recentlyEnded=[\(recentlyEnded.isEmpty ? "empty" : recentlyEnded)]")
    }

    private func describeValue(_ any: Any) -> String {
        if let s = any as? String {
            if s.count > 80 { return "\"\(s.prefix(60))...[+\(s.count - 60)more]\"" }
            return "\"\(s)\""
        }
        if let n = any as? NSNumber { return n.stringValue }
        return "\(any)"
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
    func endRingingCallIfMatching(channelId: Int64, callerId: Int64, remoteIsConnected: Bool = false) {
        guard channelId != 0 else {
            callKitUnifiedDebug("endRingingCallIfMatching ignored zero channelId=\(channelId) callerId=\(callerId) remoteIsConnected=\(remoteIsConnected)")
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
            callKitUnifiedDebug("endRingingCallIfMatching no stored payload/snapshot for channelId=\(channelId) callerId=\(callerId) remoteIsConnected=\(remoteIsConnected) -> noop")
            return
        }
        let myId = Self.resolveLocalUserIdForVoIP(fallbackReceiverId: 0) ?? 0
        let channelMatches = storedChannelId == channelId
        let callerMatches = (callerId == 0) || (storedCallerId == callerId) || (myId != 0 && callerId == myId)
        guard channelMatches, callerMatches else {
            callKitUnifiedDebug("endRingingCallIfMatching mismatch source=\(source) stored=(\(storedChannelId),\(storedCallerId)) incoming=(\(channelId),\(callerId)) myId=\(myId) remoteIsConnected=\(remoteIsConnected) -> noop")
            return
        }
        if remoteIsConnected && wasAnsweredLocallyForVoIPCallKit() {
            callKitUnifiedDebug("endRingingCallIfMatching skip source=\(source) (remoteIsConnected=true && answeredLocally) -> leaving active call alone")
            return
        }
        callKitUnifiedDebug("endRingingCallIfMatching matched source=\(source) channelId=\(channelId) callerId=\(callerId) storedCallerId=\(storedCallerId) remoteIsConnected=\(remoteIsConnected)")
        dumpVoIPState(tag: "endRingingCallIfMatching.entry")
        markRecentlyEnded(channelId: storedChannelId, callerId: storedCallerId)
        let reason: CXCallEndedReason = remoteIsConnected ? .answeredElsewhere : .remoteEnded
        let endedExisting = endStoredActiveCallViaProvider(reason: reason)
        requestEndActiveVoIPCallIfNeeded()
        if !endedExisting {
            callKitUnifiedDebug("endRingingCallIfMatching endStoredActiveCallViaProvider returned false -> relying on CXCallController fallback")
        }
        Self.clearStoredIncomingPayload()
        dumpVoIPState(tag: "endRingingCallIfMatching.exit")
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
        let priorUUID = UserDefaults.standard.string(forKey: DefaultsKeys.activeCallUUID) ?? "nil"
        let hadPayload = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) != nil
        Self.emitCallKitUnifiedDebug("clearStoredIncomingPayload priorActiveCallUUID=\(priorUUID) hadPayload=\(hadPayload)")
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
        callKitUnifiedDebug("storeIncomingUserInfo stored activeCallUUID=\(callUUID.uuidString) infoKeys=\(dict.keys.sorted())")
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
        callKitUnifiedDebug("handleVoIPDictionary START myId=\(myId) payload.keys=\(payloadDict.keys)")
        guard let offerValue = payloadDict["offer"] else {
            callKitUnifiedDebug("handleVoIPDictionary MISSING 'offer' key -> reportAndEndPlaceholderCall(.failed). full payload=\(payloadDict)")
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }
        callKitUnifiedDebug("handleVoIPDictionary 'offer' value type=\(type(of: offerValue))")

        guard let inner = parseOfferInner(offerValue) else {
            callKitUnifiedDebug("handleVoIPDictionary cannot parse 'offer' value -> reportAndEndPlaceholderCall(.failed). rawOfferValue=\(describeValue(offerValue))")
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }
        callKitUnifiedDebug("handleVoIPDictionary parsed inner.keys=\(inner.keys.sorted())")
        for (k, v) in inner.sorted(by: { $0.key < $1.key }) {
            callKitUnifiedDebug("  inner[\(k)] = \(describeValue(v))")
        }

        let offerStr = inner["offer"] as? String ?? ""
        let originalCancelChannelId = int64(inner["channelId"]) ?? 0
        let originalCancelCallerId = int64(inner["callerId"]) ?? 0
        callKitUnifiedDebug("handleVoIPDictionary offer=\"\(offerStr.count > 60 ? String(offerStr.prefix(60)) + "...[+\(offerStr.count-60)]" : offerStr)\" channelId=\(originalCancelChannelId) callerId=\(originalCancelCallerId)")
        var cancelChannelId = originalCancelChannelId
        var cancelCallerId = originalCancelCallerId
        if offerStr == "CANCEL_CALL" {
            if cancelChannelId == 0 || cancelCallerId == 0 {
                if let info = UserDefaults.standard.dictionary(forKey: DefaultsKeys.notificationPayload) {
                    if cancelChannelId == 0 { cancelChannelId = int64(info["channelId"]) ?? 0 }
                    if cancelCallerId == 0 { cancelCallerId = int64(info["callerId"]) ?? 0 }
                    callKitUnifiedDebug("CANCEL_CALL fallback IDs from storedPayload channelId=\(cancelChannelId) callerId=\(cancelCallerId)")
                } else if let snap = Self.readVoipQuitSnapshot() {
                    if cancelChannelId == 0 { cancelChannelId = snap.channelId }
                    if cancelCallerId == 0 { cancelCallerId = snap.callerId }
                    callKitUnifiedDebug("CANCEL_CALL fallback IDs from quitSnapshot channelId=\(cancelChannelId) callerId=\(cancelCallerId)")
                }
            }
            if (cancelChannelId == 0 || cancelCallerId == 0), let last = recentlyRingedCallIds() {
                if cancelChannelId == 0 { cancelChannelId = last.channelId }
                if cancelCallerId == 0 { cancelCallerId = last.callerId }
                callKitUnifiedDebug("CANCEL_CALL fallback IDs from lastRingedCall channelId=\(cancelChannelId) callerId=\(cancelCallerId)")
            }
            let cancelHadOriginalIds = (originalCancelChannelId != 0 && originalCancelCallerId != 0)
            let isSelfEcho = (myId != 0 && cancelCallerId == myId)
            let hadStoredUUID = hasStoredActiveVoIPCallUUID()
            let alreadyEndedRecently = wasRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
            let anyRecentEnd = wasAnyCallRecentlyEnded(within: recentlyEndedRetention)
            let remoteIsConnected = (inner["isConnected"] as? Bool)
                ?? ((inner["isConnected"] as? NSNumber)?.boolValue ?? false)
            let answeredLocally = wasAnsweredLocallyForVoIPCallKit()
            callKitUnifiedDebug("CANCEL_CALL evaluating channelId=\(cancelChannelId) callerId=\(cancelCallerId) cancelHadOriginalIds=\(cancelHadOriginalIds) isSelfEcho=\(isSelfEcho) hadStoredUUID=\(hadStoredUUID) alreadyEndedRecently=\(alreadyEndedRecently) anyRecentEnd=\(anyRecentEnd) remoteIsConnected=\(remoteIsConnected) answeredLocally=\(answeredLocally)")

            dumpVoIPState(tag: "CANCEL_CALL.beforeAction")

            if remoteIsConnected && answeredLocally {
                callKitUnifiedDebug("CANCEL_CALL action=NOOP_ANSWERED_HERE (remoteIsConnected=true && answeredLocally) -> leaving active call alone")
            } else if remoteIsConnected && hadStoredUUID && !alreadyEndedRecently {
                callKitUnifiedDebug("CANCEL_CALL action=END_RINGING_ANSWERED_ELSEWHERE (remoteIsConnected=true, still ringing locally)")
                let endedExisting = endStoredActiveCallViaProvider(reason: .answeredElsewhere)
                requestEndActiveVoIPCallIfNeeded()
                if endedExisting {
                    callKitUnifiedDebug("CANCEL_CALL endedExisting=true via provider + CXCallController -> ended ringing CallKit (.answeredElsewhere)")
                } else {
                    callKitUnifiedDebug("CANCEL_CALL endStoredActiveCallViaProvider returned false -> relying on CXCallController fallback")
                }
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
                dumpVoIPState(tag: "CANCEL_CALL.afterEnd")
            } else if hadStoredUUID && !alreadyEndedRecently {
                callKitUnifiedDebug("CANCEL_CALL action=END_ACTIVE_RINGING (hadStoredUUID && !alreadyEndedRecently, remoteIsConnected=\(remoteIsConnected))")
                let endedExisting = endStoredActiveCallViaProvider(reason: .remoteEnded)
                requestEndActiveVoIPCallIfNeeded()
                if endedExisting {
                    callKitUnifiedDebug("CANCEL_CALL endedExisting=true via provider + CXCallController -> ended ringing CallKit ✓ (isSelfEcho=\(isSelfEcho))")
                } else {
                    callKitUnifiedDebug("CANCEL_CALL endStoredActiveCallViaProvider returned false -> relying on CXCallController fallback")
                }
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
                Self.clearStoredIncomingPayload()
                dumpVoIPState(tag: "CANCEL_CALL.afterEnd")
            } else if !hadStoredUUID {
                callKitUnifiedDebug("CANCEL_CALL action=NOOP_NO_STORED_UUID -> immediate-ended VoIP compliance only")
                markRecentlyEnded(channelId: cancelChannelId, callerId: cancelCallerId)
            } else {
                callKitUnifiedDebug("CANCEL_CALL action=NOOP_ALREADY_ENDED -> immediate-ended VoIP compliance only")
            }

            if remoteIsConnected {
                callKitUnifiedDebug("CANCEL_CALL remoteIsConnected -> skip VoIPCompliance reportNewIncomingCall, completion only")
                completion()
                return
            }

            callKitUnifiedDebug("CANCEL_CALL -> reportImmediateEndedIncomingForVoIPCompliance(PushKit compliance)")
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: Self.callKitComplianceDisplayLabel,
                remoteHandleValue: Self.callKitComplianceDisplayLabel,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }

        guard !offerStr.isEmpty else {
            callKitUnifiedDebug("handleVoIPDictionary EMPTY offerStr after parse -> reportAndEndPlaceholderCall(.failed)")
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }

        let callerName = inner["callerName"] as? String ?? "Unknown"
        let callerId = int64(inner["callerId"]) ?? 0
        let channelId = int64(inner["channelId"]) ?? 0
        let receiverId = int64(inner["receiverId"]) ?? 0

        guard channelId != 0, callerId != 0 else {
            callKitUnifiedDebug("handleVoIPDictionary OFFER branch reject zero ids channelId=\(channelId) callerId=\(callerId) receiverId=\(receiverId) inner.keys=\(inner.keys.sorted()) -> reportAndEndPlaceholderCall(.failed)")
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
            guard let sentAtMs = sentAtMsOpt else {
                return "missing sentAt/createAt"
            }
            let ageMs = nowMs - sentAtMs
            if ageMs > PeerCallIncomingFreshness.maxOfferAgeMs {
                return "ageMs=\(ageMs) > windowMs=\(PeerCallIncomingFreshness.maxOfferAgeMs) (sentAt=\(sentAtMs) now=\(nowMs))"
            }
            return nil
        }()
        if let staleReason {
            callKitUnifiedDebug(
                "OFFER push STALE \(staleReason) -> early return, no CallKit report at all"
            )
            markRecentlyEnded(channelId: channelId, callerId: callerId)
            completion()
            return
        }
        if let sentAtMs = sentAtMsOpt {
            callKitUnifiedDebug("OFFER push fresh ageMs=\(nowMs - sentAtMs) (within \(PeerCallIncomingFreshness.maxOfferAgeMs)ms window)")
        }

        let isSelfEcho = (myId != 0 && callerId == myId)
        let isDuplicateOfferPush = offerWasSeenRecently(offerStr)
        let hadStoredUUID = hasStoredActiveVoIPCallUUID()
        callKitUnifiedDebug("OFFER push evaluating channelId=\(channelId) callerId=\(callerId) isSelfEcho=\(isSelfEcho) isDuplicateOfferPush=\(isDuplicateOfferPush) hadStoredUUID=\(hadStoredUUID)")
        if isSelfEcho {
            callKitUnifiedDebug("OFFER push isSelfEcho -> reportImmediateEndedCompliance (PushKit)")
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }
        if isDuplicateOfferPush {
            callKitUnifiedDebug("OFFER push duplicate offer SDP within \(offerDedupWindow)s -> immediate-ended compliance ring already shown")
            reportImmediateEndedIncomingForVoIPCompliance(
                localizedCallerName: callerName,
                remoteHandleValue: callerId != 0 ? "\(callerId)" : callerName,
                requiresVideoUpdate: false,
                pushCompletion: completion
            )
            return
        }
        if hadStoredUUID {
            callKitUnifiedDebug("OFFER push but CallKit already active -> immediate-ended compliance (no second ring UI churn)")
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

        let userInfo: [AnyHashable: Any] = [
            "channelId": NSNumber(value: channelId),
            "callerId": NSNumber(value: callerId),
            "receiverId": NSNumber(value: receiverId),
            "compressedOfferFromPush": offerStr,
            "pushJsonData": pushJsonData,
        ]

        let hasVideo = false

        if provider == nil {
            ensureProviderConfigured()
        }
        guard let provider else {
            callKitUnifiedDebug("handleVoIPDictionary provider nil after ensureProviderConfigured -> placeholder failed + prepareIncomingCallFromVoIPUserInfo if myId")
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
        callKitUnifiedDebug("reportNewIncomingCall (ringing) channelId=\(channelId) callerId=\(callerId) uuid=\(callUUID.uuidString) name=\"\(callerName)\"")
        setLastRingedCall(channelId: channelId, callerId: callerId)
        storeIncomingUserInfo(userInfo, callUUID: callUUID)

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: callerId != 0 ? "\(callerId)" : callerName)
        update.localizedCallerName = callerName
        update.hasVideo = hasVideo
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false

        let gate = VoIPPushCompletionGate(completion)
        provider.reportNewIncomingCall(with: callUUID, update: update) { [weak self] error in
            if let error {
                self?.callKitUnifiedDebug("reportNewIncomingCall (ringing) ERROR uuid=\(callUUID.uuidString) error=\(error.localizedDescription) ns=\((error as NSError).domain)/\((error as NSError).code) -> clearStored")
                Self.clearStoredIncomingPayload()
            } else {
                self?.callKitUnifiedDebug("reportNewIncomingCall (ringing) OK uuid=\(callUUID.uuidString) -> CallKit UI should now ring")
            }
            gate.consume()
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
        ensureSilentReportProviderConfigured()
        guard let rp = silentReportProvider else {
            callKitUnifiedDebug("reportImmediateEndedIncomingForVoIPCompliance NO_SILENT_PROVIDER -> pushCompletion only")
            pushCompletion()
            return
        }
        let ephemeralUUID = UUID()
        callKitUnifiedDebug("reportImmediateEndedIncomingForVoIPCompliance ephemeralUUID=\(ephemeralUUID.uuidString) name=\"\(localizedCallerName)\" handle=\"\(remoteHandleValue)\"")
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: remoteHandleValue)
        update.localizedCallerName = localizedCallerName
        update.hasVideo = requiresVideoUpdate
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        rp.reportNewIncomingCall(with: ephemeralUUID, update: update) { [weak self] error in
            if let error {
                self?.callKitUnifiedDebug("reportImmediateEndedIncomingForVoIPCompliance reportNewIncomingCall ERROR uuid=\(ephemeralUUID.uuidString) error=\(error.localizedDescription) ns=\((error as NSError).domain)/\((error as NSError).code)")
            } else {
                self?.callKitUnifiedDebug("reportImmediateEndedIncomingForVoIPCompliance reportNewIncomingCall OK uuid=\(ephemeralUUID.uuidString) -> reportCall(.failed)")
                rp.reportCall(with: ephemeralUUID, endedAt: Date(), reason: .failed)
            }
            pushCompletion()
        }
    }

    private func reportAndEndPlaceholderCall(reason: CXCallEndedReason, pushCompletion: (() -> Void)? = nil) {
        callKitUnifiedDebug("reportAndEndPlaceholderCall reason=\(reasonDescription(reason)) (placeholder CallKit will flash briefly)")
        ensureSilentReportProviderConfigured()
        guard let rp = silentReportProvider else {
            callKitUnifiedDebug("reportAndEndPlaceholderCall NO_SILENT_PROVIDER -> pushCompletion only")
            pushCompletion?()
            return
        }
        let placeholderUUID = UUID()
        callKitUnifiedDebug("reportAndEndPlaceholderCall placeholderUUID=\(placeholderUUID.uuidString)")
        let alreadyEndedAt = Date(timeIntervalSinceNow: -2)
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: Self.callKitComplianceDisplayLabel)
        update.localizedCallerName = Self.callKitComplianceDisplayLabel
        update.hasVideo = false
        update.supportsHolding = false
        update.supportsDTMF = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        let reasonLabel = reasonDescription(reason)
        rp.reportNewIncomingCall(with: placeholderUUID, update: update) { [weak self] error in
            if let error {
                self?.callKitUnifiedDebug("reportAndEndPlaceholderCall reportNewIncomingCall ERROR uuid=\(placeholderUUID.uuidString) error=\(error.localizedDescription) ns=\((error as NSError).domain)/\((error as NSError).code)")
            } else {
                self?.callKitUnifiedDebug("reportAndEndPlaceholderCall reportNewIncomingCall OK uuid=\(placeholderUUID.uuidString) -> reportCall(reason=\(reasonLabel))")
                rp.reportCall(with: placeholderUUID, endedAt: alreadyEndedAt, reason: reason)
            }
            pushCompletion?()
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
        Self.voipInstantFlushPrint("didReceiveIncomingPush ENTRY type=\(type.rawValue)")
        Self.voipInstantPrintPayload(payload.dictionaryPayload)
        let appState: String = {
            switch UIApplication.shared.applicationState {
            case .active: return "active"
            case .inactive: return "inactive"
            case .background: return "background"
            @unknown default: return "unknown"
            }
        }()
        callKitUnifiedDebug("=====================================================")
        callKitUnifiedDebug("pushRegistry didReceiveIncomingPush type=\(type.rawValue) appState=\(appState)")
        callKitUnifiedDebug("RAW payload.dictionaryPayload keys=\(payload.dictionaryPayload.keys)")
        for (k, v) in payload.dictionaryPayload {
            callKitUnifiedDebug("  payload[\(k)] = \(describeValue(v))")
        }
        dumpVoIPState(tag: "pushReceived")
        guard type == .voIP else {
            callKitUnifiedDebug("pushRegistry type != .voIP -> placeholder failed")
            reportAndEndPlaceholderCall(reason: .failed, pushCompletion: completion)
            return
        }
        ensureProviderConfigured()
        callKitUnifiedDebug("pushRegistry providerConfigured=\(provider != nil), handing off to handleVoIPDictionary")
        handleVoIPDictionary(payload.dictionaryPayload, completion: completion)
    }
}

extension CallKitManager: CXProviderDelegate {

    func providerDidReset(_ resetProvider: CXProvider) {
        if resetProvider === provider {
            callKitUnifiedDebug("providerDidReset MAIN -> clearStoredIncomingPayload")
            Task { @MainActor in
                WebRTCCallManager.shared.endActivePeerCallFromCallKitAction()
            }
            Self.clearStoredIncomingPayload()
        } else if resetProvider === silentReportProvider {
            callKitUnifiedDebug("providerDidReset SILENT_REPORT provider cleared")
            silentReportProvider = nil
        }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        callKitUnifiedDebug("CXAnswerCallAction received uuid=\(action.callUUID.uuidString)")
        if provider === silentReportProvider {
            callKitUnifiedDebug("CXAnswerCallAction silentReportProvider -> fulfill only")
            action.fulfill()
            return
        }
        guard let info = storedUserInfoIfFresh() else {
            callKitUnifiedDebug("CXAnswerCallAction no stored payload -> abandonIncomingPresentation + fulfill")
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
        callKitUnifiedDebug("CXEndCallAction received uuid=\(action.callUUID.uuidString) (CallKit invoked our end-action delegate)")
        if provider === silentReportProvider {
            action.fulfill()
            callKitUnifiedDebug("CXEndCallAction silentReportProvider -> fulfill only")
            return
        }
        dumpVoIPState(tag: "CXEndCallAction.entry")
        markRecentlyEndedFromStoredPayloadIfPossible()
        markRecentlyEndedFromQuitSnapshotIfPossible()
        forwardQuitToCallerFromStoredVoIPIfNeeded()
        Task { @MainActor in
            WebRTCCallManager.shared.endActivePeerCallFromCallKitAction()
            WebRTCCallManager.shared.abandonIncomingPresentation()
            Self.clearStoredIncomingPayload()
        }
        action.fulfill()
        callKitUnifiedDebug("CXEndCallAction fulfilled uuid=\(action.callUUID.uuidString)")
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
        callKitUnifiedDebug("CXProvider timedOutPerforming action=\(type(of: action))")
        if provider === silentReportProvider {
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

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        callKitUnifiedDebug("CXProvider didActivate audioSession")
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.audioSessionDidActivate(audioSession)
        rtc.isAudioEnabled = true
        NotificationCenter.default.post(name: .mezonCallKitAudioActivated, object: nil)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        callKitUnifiedDebug("CXProvider didDeactivate audioSession")
        let rtc = LKRTCAudioSession.sharedInstance()
        rtc.isAudioEnabled = false
        rtc.audioSessionDidDeactivate(audioSession)
    }
}
