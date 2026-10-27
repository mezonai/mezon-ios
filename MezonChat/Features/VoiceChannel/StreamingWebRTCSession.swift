import AVFoundation
import Foundation
import UIKit
import MobileVLCKit
import WebRTC

enum StreamingQuality: String, CaseIterable {
    case auto, high, mid, low

    var title: String {
        switch self {
        case .auto: return NSLocalizedString("streamingRoom.qualityAuto", tableName: nil, bundle: .main, value: "Auto", comment: "")
        case .high: return NSLocalizedString("streamingRoom.qualityHigh", tableName: nil, bundle: .main, value: "High", comment: "")
        case .mid: return NSLocalizedString("streamingRoom.qualityMid", tableName: nil, bundle: .main, value: "Medium", comment: "")
        case .low: return NSLocalizedString("streamingRoom.qualityLow", tableName: nil, bundle: .main, value: "Low", comment: "")
        }
    }

    // AVPlayer keeps native HLS adaptation within the requested quality ceiling.
    var maximumResolution: CGSize {
        switch self {
        case .auto, .high: return .zero
        case .mid: return CGSize(width: 1280, height: 720)
        case .low: return CGSize(width: 640, height: 360)
        }
    }
}

/// Stream channels prefer LL-HLS from GetStreamPlayback, using WHEP when HLS is unavailable.
@MainActor
final class StreamingWebRTCSession: NSObject {
    static let shared = StreamingWebRTCSession()
    private static var sslInitialized = false

    private(set) var activeStreamChannelId: Int64?
    private(set) var isStreaming = false
    private(set) var isBuffering = false
    private(set) var hasVideoFrames = false
    private(set) var quality: StreamingQuality = .auto
    private(set) var volume: Float = 1
    private(set) var isMuted = false
    private static let defaultQualityKey = "mezon.stream.defaultQuality"
    var defaultQuality: StreamingQuality {
        StreamingQuality(rawValue: UserDefaults.standard.string(forKey: Self.defaultQualityKey) ?? "") ?? .auto
    }
    private(set) var remoteAudioTrack: RTCAudioTrack?
    private(set) var remoteVideoTrack: RTCVideoTrack?
    private var videoFrameObserver: StreamingFirstVideoFrameObserver?
    private(set) var player: AVPlayer?
    private(set) var vlcVideoView: UIView?
    private var vlcPlayer: VLCMediaPlayer?
    private var activeHlsURL: URL?
    private var prefersVlcHls = false
    // New streams start on speaker; nil respects an external route chosen through the system picker.
    private var preferredSpeakerOutput: Bool?
    var isSpeakerOutput: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }
    private var mediaProgressTask: Task<Void, Never>?
    private var lastMediaProgressUptime: TimeInterval = 0
    private var lastMediaPosition: Double?
    private var lastInboundBytes: Double = 0
    private var lastVlcTime: Int32 = -1
    var onStreamingStateChanged: (() -> Void)?

    private var context: AccountContext?
    private var clanId: Int64 = 0
    private var peerConnection: RTCPeerConnection?
    private var peerFactory: RTCPeerConnectionFactory?
    private var resourceURL: URL?
    private var connectionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var watchdogDeadline: TimeInterval?
    private var watchTask: Task<Void, Never>?
    private var watchRenewTask: Task<Void, Never>?
    private var socketObserver: NSObjectProtocol?
    private var presenceObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var audioRouteObserver: NSObjectProtocol?
    private var presenceRefreshTask: Task<Void, Never>?
    private var playerObservation: NSKeyValueObservation?
    private var playerStatusObservation: NSKeyValueObservation?
    private var playerFailureObserver: NSObjectProtocol?
    private var generation = 0
    private var transportGeneration = 0
    private var reconnectAttempt = 0
    private var hasActivatedAudioSession = false
    private var hasActivatedHlsAudioSession = false
    private var fallbackURL: URL?
    private var isConnectingWhep = false
    private var pendingJoinChannelId: Int64?
    private var joinRequestGeneration = 0
    private let httpSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    private override init() { super.init() }

    /// Fetch first: a failed or stale join must not stop the stream already playing.
    func join(
        channelId: Int64,
        clanId: Int64,
        context: AccountContext,
        canJoin: () -> Bool = { true }
    ) async -> Bool {
        guard channelId != 0 else { return false }
        if activeStreamChannelId == channelId {
            joinRequestGeneration &+= 1
            pendingJoinChannelId = nil
            return canJoin()
        }
        guard pendingJoinChannelId != channelId else { return false }
        joinRequestGeneration &+= 1
        let request = joinRequestGeneration
        pendingJoinChannelId = channelId
        defer {
            if request == joinRequestGeneration { pendingJoinChannelId = nil }
        }
        do {
            let playback = try await fetchPlayback(channelId: channelId, context: context)
            guard request == joinRequestGeneration, !Task.isCancelled, canJoin() else { return false }
            stopPlayback(sendUnwatch: true)
            activeStreamChannelId = channelId
            self.clanId = clanId
            self.context = context
            quality = defaultQuality
            preferredSpeakerOutput = true
            startPresence()
            startPlayback(playback)
            return true
        } catch {
            if request == joinRequestGeneration, !Task.isCancelled, canJoin() { showPlaybackError() }
            return false
        }
    }

    func leave() { disconnect() }

    func disconnect() {
        joinRequestGeneration &+= 1
        pendingJoinChannelId = nil
        stopPlayback(sendUnwatch: true)
    }

    private func stopPlayback(sendUnwatch: Bool) {
        let previousChannelId = activeStreamChannelId
        let wasWatching = watchTask != nil
        generation &+= 1
        reconnectTask?.cancel()
        reconnectTask = nil
        watchTask?.cancel()
        watchTask = nil
        watchRenewTask?.cancel()
        watchRenewTask = nil
        presenceRefreshTask?.cancel()
        presenceRefreshTask = nil
        for observer in [socketObserver, presenceObserver, foregroundObserver, audioRouteObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        socketObserver = nil
        presenceObserver = nil
        foregroundObserver = nil
        audioRouteObserver = nil
        closeTransport()
        activeStreamChannelId = nil
        context = nil
        clanId = 0
        reconnectAttempt = 0
        prefersVlcHls = false
        preferredSpeakerOutput = nil
        isStreaming = false
        isBuffering = false
        if wasWatching { UIApplication.shared.isIdleTimerDisabled = false }
        deactivateWebRTCAudio()
        onStreamingStateChanged?()
        if let previousChannelId, wasWatching, sendUnwatch {
            MezonSocket.shared.sendStreamingUnwatch(channelId: previousChannelId)
        }
        // Presence belongs to server events, including when the publisher watches their own stream.
    }

    func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        if volume > 0 { isMuted = false }
        applyAudioSettings()
        onStreamingStateChanged?()
    }

    func toggleMute() {
        if isMuted || volume == 0 {
            isMuted = false
            if volume == 0 { volume = 0.5 }
        } else { isMuted = true }
        applyAudioSettings()
        onStreamingStateChanged?()
    }

    func toggleSpeakerOutput() {
        guard activeStreamChannelId != nil else { return }
        let previous = preferredSpeakerOutput
        preferredSpeakerOutput = !isSpeakerOutput
        do {
            if hasActivatedAudioSession || hasActivatedHlsAudioSession || otherCallOwnsAudio {
                try applyPreferredAudioOutput()
            }
        } catch {
            preferredSpeakerOutput = previous
            logError("audio-route-failed", error)
            Toast.error(NSLocalizedString(
                "streamingRoom.audioRouteFailed", tableName: nil, bundle: .main,
                value: "Unable to switch audio output", comment: ""))
        }
        onStreamingStateChanged?()
    }

    func setDefaultQuality(_ value: StreamingQuality) {
        UserDefaults.standard.set(value.rawValue, forKey: Self.defaultQualityKey)
    }

    func setQuality(_ value: StreamingQuality) {
        quality = value
        player?.currentItem?.preferredMaximumResolution = value.maximumResolution
        if vlcPlayer != nil, let activeHlsURL {
            startVlcHls(url: activeHlsURL, transport: transportGeneration)
        }
        if let resourceURL { updateWhepLayer(resourceURL) }
        onStreamingStateChanged?()
    }

    func noteNativeVideoFrame(from player: AVPlayer) {
        guard self.player === player else { return }
        noteVideoFrame()
    }

    private func noteVideoFrame() {
        guard !hasVideoFrames else { return }
        hasVideoFrames = true
        onStreamingStateChanged?()
    }

    private func applyAudioSettings() {
        remoteAudioTrack?.source.volume = Double(isMuted ? 0 : volume)
        player?.volume = volume
        player?.isMuted = isMuted
        vlcPlayer?.audio?.volume = Int32((volume * 100).rounded())
        vlcPlayer?.audio?.isMuted = isMuted
    }

    private func updateWhepLayer(_ resource: URL) {
        guard var components = URLComponents(url: resource.appendingPathComponent("layer"), resolvingAgainstBaseURL: true) else { return }
        var query = components.queryItems ?? []
        query.removeAll { $0.name == "layer" }
        query.append(URLQueryItem(name: "layer", value: quality.rawValue))
        components.queryItems = query
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        httpSession.dataTask(with: request).resume()
    }

    private func fetchPlayback(channelId: Int64, context: AccountContext) async throws -> Mezon_Api_GetStreamPlaybackResponse {
        guard let token = await context.getToken() else { throw MezonError.invalidResponse }
        let response = try await context.account.network.getStreamPlayback(channelId: channelId, token: token)
        let playback = Self.resolvedPlayback(response, channelId: channelId)
        guard Self.httpURL(playback.hlsURL) != nil ||
              (Self.httpURL(playback.whepURL) != nil && !playback.token.isEmpty) else {
            throw MezonError.invalidResponse
        }
        log("playback-response", "channel=\(channelId) whep=\(!playback.whepURL.isEmpty) hls=\(!playback.hlsURL.isEmpty)")
        return playback
    }

    private func startPresence() {
        UIApplication.shared.isIdleTimerDisabled = true
        renewWatch()
        watchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard let self, self.activeStreamChannelId != nil else { return }
                self.renewWatch()
            }
        }
        socketObserver = NotificationCenter.default.addObserver(
            forName: .mezonSocketStatusChanged, object: nil, queue: .main
        ) { [weak self] notification in
            guard notification.userInfo?["isConnected"] as? Bool == true else { return }
            Task { @MainActor [weak self] in self?.resumePresence() }
        }
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.resumePresence() }
        }
        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue ?? 0
            Task { @MainActor [weak self] in self?.audioRouteChanged(reason: reason) }
        }
        // The session, rather than a particular screen/PiP view, observes publisher termination.
        presenceObserver = NotificationCenter.default.addObserver(
            forName: .mezonVoicePresenceChanged, object: nil, queue: .main
        ) { [weak self] notification in
            let updatedClanId = (notification.userInfo?["clanId"] as? NSNumber)?.int64Value
            Task { @MainActor [weak self] in
                guard let self, updatedClanId == self.clanId,
                      let channelId = self.activeStreamChannelId, let context = self.context,
                      let users = context.engine.clanData.getStreamUsers(clanId: self.clanId) else { return }
                let members = users.voiceChannelUsers.first { $0.channelID == channelId }?.userIds ?? []
                if members.isEmpty {
                    // Server events end local playback only; never echo watch/unwatch back to the server.
                    self.stopPlayback(sendUnwatch: false)
                }
            }
        }
    }

    private func resumePresence() {
        guard activeStreamChannelId != nil else { return }
        watchRenewTask?.cancel()
        watchRenewTask = nil
        renewWatch()
        guard presenceRefreshTask == nil, let context else { return }
        let currentGeneration = generation
        let currentClanId = clanId
        presenceRefreshTask = Task { @MainActor [weak self] in
            defer {
                if let self, currentGeneration == self.generation { self.presenceRefreshTask = nil }
            }
            guard let token = await context.getToken(), !Task.isCancelled,
                  let self, currentGeneration == self.generation else { return }
            await context.engine.clanData.refetchStreamChannelUsers(clanId: currentClanId, token: token)
        }
    }

    private func renewWatch() {
        guard let channelId = activeStreamChannelId, watchRenewTask == nil else { return }
        let currentGeneration = generation
        watchRenewTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, currentGeneration == self.generation,
                  self.activeStreamChannelId == channelId else { return }
            try? await MezonSocket.shared.writeStreamingWatch(channelId: channelId, watching: true)
            guard currentGeneration == self.generation, !Task.isCancelled else { return }
            self.watchRenewTask = nil
        }
    }

    private func startPlayback(_ playback: Mezon_Api_GetStreamPlaybackResponse) {
        closeTransport()
        isStreaming = false
        isBuffering = true
        fallbackURL = Self.httpURL(playback.hlsURL)
        let transport = transportGeneration
        if fallbackURL != nil {
            startHls(transport: transport)
            return
        }
        if let url = Self.httpURL(playback.whepURL), !playback.token.isEmpty {
            isConnectingWhep = true
            // Bound signaling too, including async SDK offer/description callbacks.
            armWatchdog(transport: transport, delay: 15_000_000_000)
            connectionTask = Task { @MainActor [weak self] in
                await self?.connectWhep(url: url, token: playback.token, transport: transport)
            }
        } else {
            startHls(transport: transport)
        }
        onStreamingStateChanged?()
    }

    private func connectWhep(url: URL, token: String, transport: Int) async {
        log("whep-start", "host=\(url.host ?? "unknown")")
        do {
            if !Self.sslInitialized {
                RTCInitializeSSL()
                Self.sslInitialized = true
            }
            guard configureWebRTCAudioForPlayback() else { throw MezonError.invalidResponse }
            let factory = RTCPeerConnectionFactory(
                encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
            peerFactory = factory
            let config = RTCConfiguration()
            config.sdpSemantics = .unifiedPlan
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
                throw MezonError.invalidResponse
            }
            peerConnection = pc
            startMediaProgressMonitoring(transport: transport)
            let receiveOnly = RTCRtpTransceiverInit()
            receiveOnly.direction = .recvOnly
            pc.addTransceiver(of: .audio, init: receiveOnly)
            pc.addTransceiver(of: .video, init: receiveOnly)
            let offer = try await Self.createOffer(on: pc)
            guard isCurrent(transport, pc: pc) else { return }
            try await Self.setLocalDescription(offer, on: pc)
            guard isCurrent(transport, pc: pc), let sdp = pc.localDescription?.sdp else { return }
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                throw MezonError.invalidResponse
            }
            var items = components.queryItems ?? []
            items.removeAll { $0.name == "layer" }
            items.append(URLQueryItem(name: "layer", value: quality.rawValue))
            components.queryItems = items
            guard let target = components.url else { throw MezonError.invalidResponse }
            var request = URLRequest(url: target)
            request.httpMethod = "POST"
            request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = Data(sdp.utf8)
            let (data, response) = try await httpData(request)
            guard let response = response as? HTTPURLResponse else { throw MezonError.invalidResponse }
            log("whep-response", "status=\(response.statusCode)")
            guard response.statusCode == 201 else { throw WhepError(status: response.statusCode) }
            guard let location = response.value(forHTTPHeaderField: "Location"), !location.isEmpty,
                  let resolvedResource = URL(string: location, relativeTo: response.url ?? url)?.absoluteURL,
                  let resource = Self.httpURL(resolvedResource.absoluteString) else { throw MezonError.invalidResponse }
            guard isCurrent(transport, pc: pc) else {
                deleteResource(resource)
                return
            }
            resourceURL = resource
            guard let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
                throw MezonError.invalidResponse
            }
            if answer.range(of: "^m=video 0 ", options: .regularExpression) != nil ||
                answer.contains("\nm=video 0 ") { throw WhepError(status: 406) }
            try await Self.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer), on: pc)
            guard isCurrent(transport, pc: pc) else { return }
            scanRemoteTracks(pc)
            // Honor a quality change made while the WHEP POST was in flight.
            updateWhepLayer(resource)
            // A connected callback can arrive before setRemoteDescription completes.
            if pc.connectionState == .connected {
                connected()
            } else if !isStreaming {
                armWatchdog(transport: transport, delay: 5_000_000_000)
            }
        } catch {
            guard transport == transportGeneration, activeStreamChannelId != nil else { return }
            logError("whep-failed", error)
            if let error = error as? WhepError, error.status == 404 { failPlayback(); return }
            startHls(transport: transport)
        }
    }

    private func startHls(transport: Int) {
        guard transport == transportGeneration, activeStreamChannelId != nil else { return }
        let url = fallbackURL
        if let url, prefersVlcHls {
            startVlcHls(url: url, transport: transport)
            return
        }
        closeTransport()
        deactivateWebRTCAudio()
        guard let url else { scheduleReconnect(); return }
        if !AppAudioSession.isHeldByLiveCall {
            AppAudioSession.activateForMediaPlayback(options: [.mixWithOthers])
            hasActivatedHlsAudioSession = true
            do { try applyPreferredAudioOutput() }
            catch { logError("audio-route-restore-failed", error) }
        }
        let currentTransport = transportGeneration
        activeHlsURL = url
        log("hls-native-start", "host=\(url.host ?? "unknown")")
        let item = AVPlayerItem(url: url)
        item.preferredMaximumResolution = quality.maximumResolution
        let player = AVPlayer(playerItem: item)
        self.player = player
        applyAudioSettings()
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self, weak player] _, _ in
            Task { @MainActor [weak self, weak player] in
                guard let self, let player, self.player === player, currentTransport == self.transportGeneration else { return }
                if player.timeControlStatus == .playing {
                    self.connected()
                } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self.isBuffering = true
                    self.onStreamingStateChanged?()
                    self.armWatchdog(transport: currentTransport, delay: 15_000_000_000)
                }
            }
        }
        playerStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, currentTransport == self.transportGeneration else { return }
                self.fallbackFromNativeHls(transport: currentTransport)
            }
        }
        playerFailureObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, currentTransport == self.transportGeneration else { return }
                self.fallbackFromNativeHls(transport: currentTransport)
            }
        }
        armWatchdog(transport: currentTransport, delay: 15_000_000_000)
        startMediaProgressMonitoring(transport: currentTransport)
        onStreamingStateChanged?()
        player.play()
    }

    private func fallbackFromNativeHls(transport: Int) {
        guard transport == transportGeneration, let url = activeHlsURL, player != nil else { return }
        if let error = player?.currentItem?.error { logError("hls-native-failed", error) }
        if let event = player?.currentItem?.errorLog()?.events.last {
            log("hls-native-error-log", "status=\(event.errorStatusCode)")
        }
        // The streaming node can serve Opus/fMP4. Native HLS rejects that on supported
        // older iOS versions; retrying the same manifest with AVPlayer cannot fix it.
        startVlcHls(url: url, transport: transport)
    }

    private func startVlcHls(url: URL, transport: Int) {
        guard transport == transportGeneration, activeStreamChannelId != nil else { return }
        closeTransport()
        deactivateWebRTCAudio()
        prefersVlcHls = true
        activeHlsURL = url
        isStreaming = false
        isBuffering = true
        log("hls-vlc-start", "host=\(url.host ?? "unknown")")
        if !AppAudioSession.isHeldByLiveCall {
            AppAudioSession.activateForMediaPlayback(options: [.mixWithOthers])
            hasActivatedHlsAudioSession = true
            do { try applyPreferredAudioOutput() }
            catch { logError("audio-route-restore-failed", error) }
        }
        let drawable = UIView()
        drawable.backgroundColor = .black
        vlcVideoView = drawable
        var options = ["--network-caching=1000", "--no-video-title-show"]
        switch quality {
        case .auto, .high: break
        case .mid: options.append("--adaptive-maxheight=720")
        case .low: options.append("--adaptive-maxheight=360")
        }
        let player = VLCMediaPlayer(options: options)
        player.delegate = self
        player.drawable = drawable
        player.media = VLCMedia(url: url)
        vlcPlayer = player
        lastVlcTime = -1
        applyAudioSettings()
        let currentTransport = transportGeneration
        armWatchdog(transport: currentTransport, delay: 15_000_000_000)
        startMediaProgressMonitoring(transport: currentTransport)
        onStreamingStateChanged?()
        player.play()
    }

    private func noteMediaProgress() {
        lastMediaProgressUptime = ProcessInfo.processInfo.systemUptime
        reconnectAttempt = 0
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogDeadline = nil
        if !isStreaming || isBuffering { connected() }
    }

    private func startMediaProgressMonitoring(transport: Int) {
        mediaProgressTask?.cancel()
        lastMediaProgressUptime = ProcessInfo.processInfo.systemUptime
        lastMediaPosition = nil
        lastInboundBytes = 0
        mediaProgressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self, transport == self.transportGeneration else { return }
                if let player = self.player {
                    let position = player.currentTime().seconds
                    if position.isFinite, position >= 0 {
                        if let previous = self.lastMediaPosition,
                           player.timeControlStatus == .playing, position > previous + 0.01 {
                            self.noteMediaProgress()
                        }
                        self.lastMediaPosition = position
                    }
                } else if let pc = self.peerConnection {
                    pc.statistics { [weak self, weak pc] report in
                        let bytes = report.statistics.values.reduce(0.0) { total, stat in
                            guard stat.type == "inbound-rtp" else { return total }
                            return total + ((stat.values["bytesReceived"] as? NSNumber)?.doubleValue ?? 0)
                        }
                        Task { @MainActor [weak self, weak pc] in
                            guard let self, let pc, self.peerConnection === pc,
                                  transport == self.transportGeneration else { return }
                            if bytes > self.lastInboundBytes {
                                self.lastInboundBytes = bytes
                                self.noteMediaProgress()
                            }
                        }
                    }
                }
                // VLC reports actual clock advances through mediaPlayerTimeChanged.
                let stalledFor = ProcessInfo.processInfo.systemUptime - self.lastMediaProgressUptime
                if stalledFor >= 15 {
                    self.log("media-stalled")
                    if self.player != nil { self.fallbackFromNativeHls(transport: transport) }
                    else if self.peerConnection != nil { self.startHls(transport: transport) }
                    else { self.scheduleReconnect() }
                    return
                }
                if stalledFor >= 3, !self.isBuffering {
                    self.isBuffering = true
                    self.onStreamingStateChanged?()
                }
            }
        }
    }

    private func connected() {
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogDeadline = nil
        if !isStreaming || isBuffering { log("media-playing", "engine=\(vlcPlayer != nil ? "vlc" : (player != nil ? "avplayer" : "whep"))") }
        isConnectingWhep = false
        isStreaming = true
        isBuffering = false
        onStreamingStateChanged?()
    }

    private func armWatchdog(transport: Int, delay: UInt64) {
        let deadline = ProcessInfo.processInfo.systemUptime + Double(delay) / 1_000_000_000
        // KVO can repeat "waiting"/"buffering" without any media progress. Those
        // notifications must not keep postponing the existing connection deadline.
        if let watchdogDeadline, watchdogDeadline <= deadline { return }
        watchdogTask?.cancel()
        watchdogDeadline = deadline
        watchdogTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, transport == self.transportGeneration else { return }
            self.watchdogTask = nil
            self.watchdogDeadline = nil
            self.log("playback-timeout")
            if self.isConnectingWhep { self.startHls(transport: transport) }
            else if self.player != nil { self.fallbackFromNativeHls(transport: transport) }
            else { self.scheduleReconnect() }
        }
    }

    private func scheduleReconnect() {
        guard activeStreamChannelId != nil, reconnectTask == nil else { return }
        closeTransport()
        isStreaming = false
        isBuffering = true
        onStreamingStateChanged?()
        guard reconnectAttempt < 3 else {
            failPlayback()
            return
        }
        let delay = UInt64(Double(1 << reconnectAttempt) * Double.random(in: 0.5...1) * 1_000_000_000)
        reconnectAttempt += 1
        log("reconnect", "attempt=\(reconnectAttempt)")
        let currentGeneration = generation
        reconnectTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, currentGeneration == self.generation,
                  let channelId = self.activeStreamChannelId, let context = self.context else { return }
            do {
                let playback = try await self.fetchPlayback(channelId: channelId, context: context)
                guard currentGeneration == self.generation, !Task.isCancelled else { return }
                self.reconnectTask = nil
                self.renewWatch()
                self.startPlayback(playback)
            } catch {
                guard currentGeneration == self.generation, !Task.isCancelled else { return }
                self.reconnectTask = nil
                self.scheduleReconnect()
            }
        }
    }

    private func closeTransport() {
        transportGeneration &+= 1
        connectionTask?.cancel()
        connectionTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogDeadline = nil
        mediaProgressTask?.cancel()
        mediaProgressTask = nil
        if let resourceURL { deleteResource(resourceURL) }
        resourceURL = nil
        let oldPeer = peerConnection
        peerConnection = nil
        oldPeer?.close()
        peerFactory = nil
        remoteAudioTrack = nil
        if let videoFrameObserver { remoteVideoTrack?.remove(videoFrameObserver) }
        videoFrameObserver = nil
        remoteVideoTrack = nil
        hasVideoFrames = false
        playerObservation = nil
        playerStatusObservation = nil
        if let playerFailureObserver { NotificationCenter.default.removeObserver(playerFailureObserver) }
        playerFailureObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        activeHlsURL = nil
        let oldVlcPlayer = vlcPlayer
        vlcPlayer = nil
        oldVlcPlayer?.delegate = nil
        oldVlcPlayer?.stop()
        oldVlcPlayer?.drawable = nil
        vlcVideoView = nil
        if hasActivatedHlsAudioSession {
            hasActivatedHlsAudioSession = false
            if !AppAudioSession.isHeldByLiveCall {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
        fallbackURL = nil
        isConnectingWhep = false
    }

    private func failPlayback() {
        stopPlayback(sendUnwatch: true)
        showPlaybackError()
    }

    private func log(_ event: String, _ details: String = "") {
        // Never log bearer tokens, SDP, full signed URLs or WHEP resource IDs.
        NSLog("[MezonStream] channel=%@ transport=%d %@ %@",
              activeStreamChannelId.map(String.init) ?? "none", transportGeneration, event, details)
    }

    private func logError(_ event: String, _ error: Error) {
        let error = error as NSError
        var details = "domain=\(error.domain) code=\(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            details += " underlying=\(underlying.domain):\(underlying.code)"
        }
        log(event, details)
    }

    private func showPlaybackError() {
        Toast.error(NSLocalizedString(
            "streamingRoom.noDisplay", tableName: nil, bundle: .main, value: "Stream is not available", comment: ""))
    }

    private func deleteResource(_ url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        httpSession.dataTask(with: request).resume()
    }

    private func httpData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        if #available(iOS 15.0, *) { return try await httpSession.data(for: request) }
        return try await withCheckedThrowingContinuation { continuation in
            httpSession.dataTask(with: request) { data, response, error in
                if let error { continuation.resume(throwing: error) }
                else if let response { continuation.resume(returning: (data ?? Data(), response)) }
                else { continuation.resume(throwing: MezonError.invalidResponse) }
            }.resume()
        }
    }

    private func isCurrent(_ transport: Int, pc: RTCPeerConnection) -> Bool {
        transport == transportGeneration && peerConnection === pc && activeStreamChannelId != nil
    }

    private static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private static func resolvedPlayback(_ playback: Mezon_Api_GetStreamPlaybackResponse, channelId: Int64) -> Mezon_Api_GetStreamPlaybackResponse {
        // An omitted WHEP URL can mean no edge has capacity: honor an API-provided HLS URL.
        guard channelId != 0, !playback.token.isEmpty,
              httpURL(playback.whepURL) == nil, httpURL(playback.hlsURL) == nil else { return playback }
        let baseURL = URL(string: "https://streaming.mezon.vn")!
        var resolved = playback
        resolved.whepURL = baseURL.appendingPathComponent("whep/\(channelId)").absoluteString
        // The streaming server uses the channel's 16-digit hexadecimal ID for HLS.
        let channelPath = String(format: "%016llx", UInt64(bitPattern: channelId))
        var hls = URLComponents(url: baseURL.appendingPathComponent("\(channelPath)/live/index.m3u8"), resolvingAgainstBaseURL: true)!
        hls.queryItems = [URLQueryItem(name: "token", value: playback.token)]
        resolved.hlsURL = hls.url!.absoluteString
        return resolved
    }

    private func scanRemoteTracks(_ pc: RTCPeerConnection) {
        for transceiver in pc.transceivers {
            if let audio = transceiver.receiver.track as? RTCAudioTrack {
                remoteAudioTrack = audio
                audio.isEnabled = true
            } else if let video = transceiver.receiver.track as? RTCVideoTrack {
                if remoteVideoTrack?.isEqual(video) != true {
                    if let videoFrameObserver { remoteVideoTrack?.remove(videoFrameObserver) }
                    hasVideoFrames = false
                    let transport = transportGeneration
                    let observer = StreamingFirstVideoFrameObserver { [weak self, weak pc] in
                        Task { @MainActor [weak self, weak pc] in
                            guard let self, let pc, self.isCurrent(transport, pc: pc) else { return }
                            self.noteVideoFrame()
                        }
                    }
                    remoteVideoTrack = video
                    videoFrameObserver = observer
                    video.add(observer)
                }
                video.isEnabled = true
            }
        }
        applyAudioSettings()
        onStreamingStateChanged?()
    }

    private func configureWebRTCAudioForPlayback() -> Bool {
        let rtc = RTCAudioSession.sharedInstance()
        rtc.useManualAudio = true
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        do {
            if !otherCallOwnsAudio {
                let configuration = RTCAudioSessionConfiguration.webRTC()
                configuration.category = AVAudioSession.Category.playAndRecord.rawValue
                configuration.mode = AVAudioSession.Mode.default.rawValue
                configuration.categoryOptions = playbackCategoryOptions
                RTCAudioSessionConfiguration.setWebRTC(configuration)
                try rtc.setConfiguration(configuration)
            }
            if !hasActivatedAudioSession {
                try rtc.setActive(true)
                hasActivatedAudioSession = true
            }
            rtc.isAudioEnabled = true
            try applyPreferredAudioPorts(on: rtc)
            return true
        } catch { return false }
    }

    private var playbackCategoryOptions: AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetooth, .allowAirPlay]
        if preferredSpeakerOutput != false {
            options.formUnion([.defaultToSpeaker, .allowBluetoothA2DP])
        }
        return options
    }

    private func applyPreferredAudioOutput() throws {
        guard preferredSpeakerOutput != nil else { return }
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        let audio = AVAudioSession.sharedInstance()
        if hasActivatedAudioSession || otherCallOwnsAudio {
            let configuration = RTCAudioSessionConfiguration.webRTC()
            configuration.category = AVAudioSession.Category.playAndRecord.rawValue
            configuration.mode = otherCallOwnsAudio ? audio.mode.rawValue : AVAudioSession.Mode.default.rawValue
            configuration.categoryOptions = playbackCategoryOptions
            RTCAudioSessionConfiguration.setWebRTC(configuration)
            try rtc.setConfiguration(configuration)
            try applyPreferredAudioPorts(on: rtc)
        } else {
            // Receiver output requires playAndRecord, including native/VLC HLS playback.
            try audio.setCategory(.playAndRecord, mode: .default, policy: .default,
                                  options: playbackCategoryOptions)
            if preferredSpeakerOutput == false {
                if let mic = audio.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                    try audio.setPreferredInput(mic)
                }
            } else { try audio.setPreferredInput(nil) }
            try audio.overrideOutputAudioPort(preferredSpeakerOutput == true ? .speaker : .none)
        }
    }

    private func applyPreferredAudioPorts(on rtc: RTCAudioSession) throws {
        guard let speaker = preferredSpeakerOutput else { return }
        if !speaker {
            if let mic = AVAudioSession.sharedInstance().availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try rtc.setPreferredInput(mic)
            }
        } else { try AVAudioSession.sharedInstance().setPreferredInput(nil) }
        try rtc.overrideOutputAudioPort(speaker ? .speaker : .none)
    }

    private func audioRouteChanged(reason: UInt) {
        guard activeStreamChannelId != nil else { return }
        let audio = AVAudioSession.sharedInstance()
        if reason != AVAudioSession.RouteChangeReason.categoryChange.rawValue,
           audio.currentRoute.outputs.contains(where: { $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver }) {
            // Respect a headset/Bluetooth/AirPlay route chosen through the system picker.
            preferredSpeakerOutput = nil
        }
        if reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue {
            restoreVlcAudioOutputIfNeeded()
        }
        onStreamingStateChanged?()
    }

    private func restoreVlcAudioOutputIfNeeded() {
        guard vlcPlayer != nil, preferredSpeakerOutput != nil, !otherCallOwnsAudio,
              AVAudioSession.sharedInstance().category != .playAndRecord else { return }
        // VLC resets the category on output startup/resume. Also check on media progress:
        // category notifications aren't guaranteed when the physical route stays unchanged.
        do { try applyPreferredAudioOutput() }
        catch { logError("audio-route-restore-failed", error) }
    }

    private func deactivateWebRTCAudio() {
        guard hasActivatedAudioSession else { return }
        hasActivatedAudioSession = false
        let rtc = RTCAudioSession.sharedInstance()
        rtc.lockForConfiguration()
        defer { rtc.unlockForConfiguration() }
        if !otherCallOwnsAudio { rtc.isAudioEnabled = false }
        // RTCAudioSession reference-counts activations; release our reference even during a call.
        try? rtc.setActive(false)
    }

    private var otherCallOwnsAudio: Bool {
        MezonSfuSession.hasLiveSession || WebRTCCallManager.shared.signalingSession != nil
    }

    private struct WhepError: Error { let status: Int }

    private static func createOffer(on pc: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.offer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: MezonError.invalidResponse) }
            }
        }
    }

    private static func setLocalDescription(_ sdp: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private static func setRemoteDescription(_ sdp: RTCSessionDescription, on pc: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

extension StreamingWebRTCSession: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCSignalingState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd _: RTCMediaStream) { updateTracks(pc) }
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_: RTCPeerConnection) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === pc else { return }
            switch state {
            case .connected:
                self.scanRemoteTracks(pc)
                self.connected()
            case .failed:
                if self.isConnectingWhep { self.startHls(transport: self.transportGeneration) }
                else { self.scheduleReconnect() }
            case .disconnected:
                self.isBuffering = true
                self.onStreamingStateChanged?()
                self.armWatchdog(transport: self.transportGeneration, delay: 5_000_000_000)
            default: break
            }
        }
    }
    nonisolated func peerConnection(_: RTCPeerConnection, didChange _: RTCIceGatheringState) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didGenerate _: RTCIceCandidate) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_: RTCPeerConnection, didOpen _: RTCDataChannel) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didAdd _: RTCRtpReceiver, streams _: [RTCMediaStream]) { updateTracks(pc) }
    nonisolated func peerConnection(_: RTCPeerConnection, didRemove _: RTCRtpReceiver) {}
    nonisolated func peerConnection(_ pc: RTCPeerConnection, didStartReceivingOn _: RTCRtpTransceiver) { updateTracks(pc) }

    private nonisolated func updateTracks(_ pc: RTCPeerConnection) {
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === pc else { return }
            self.scanRemoteTracks(pc)
        }
    }
}

extension StreamingWebRTCSession: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        Task { @MainActor [weak self] in
            guard let self, player === self.vlcPlayer else { return }
            switch player.state {
            case .error, .ended, .stopped:
                self.log("hls-vlc-ended", "state=\(player.state.rawValue)")
                self.scheduleReconnect()
            default:
                // VLC's buffering state may repeat even while its playback clock advances.
                // The clock/progress deadline below determines whether media actually stalls.
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        guard let player = notification.object as? VLCMediaPlayer else { return }
        Task { @MainActor [weak self] in
            guard let self, player === self.vlcPlayer else { return }
            let time = player.time.intValue
            guard time > 0 else { return }
            let progressed = self.lastVlcTime > 0 && time > self.lastVlcTime
            self.lastVlcTime = time
            if progressed { self.noteMediaProgress() }
            self.restoreVlcAudioOutputIfNeeded()
            if player.hasVideoOut, let media = player.media, media.statistics.displayedPictures > 0 {
                self.noteVideoFrame()
            }
        }
    }
}

private final class StreamingFirstVideoFrameObserver: NSObject, RTCVideoRenderer {
    private let lock = NSLock()
    private var receivedFrame = false
    private let onFirstFrame: @Sendable () -> Void

    init(onFirstFrame: @escaping @Sendable () -> Void) {
        self.onFirstFrame = onFirstFrame
        super.init()
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, frame.width > 0, frame.height > 0 else { return }
        lock.lock()
        let first = !receivedFrame
        receivedFrame = true
        lock.unlock()
        if first { onFirstFrame() }
    }
}

/// Each surface owns its renderer; the session and player survive fullscreen/PiP transitions.
@MainActor
final class StreamingPlaybackView: UIView {
    private let videoView = RTCMTLVideoView()
    private let playerLayer = AVPlayerLayer()
    private var track: RTCVideoTrack?
    private weak var attachedVlcView: UIView?
    private weak var session: StreamingWebRTCSession?
    private var readyObservation: NSKeyValueObservation?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .black
        videoView.videoContentMode = .scaleAspectFit
        videoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)
        layer.addSublayer(playerLayer)
        playerLayer.videoGravity = .resizeAspect
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay, let player = layer.player else { return }
            Task { @MainActor [weak self] in self?.session?.noteNativeVideoFrame(from: player) }
        }
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func update(session: StreamingWebRTCSession?) {
        self.session = session
        let nextTrack = session?.remoteVideoTrack
        let sameTrack = track == nil && nextTrack == nil || track?.isEqual(nextTrack) == true
        if !sameTrack {
            track?.remove(videoView)
            track = nextTrack
            track?.add(videoView)
        }
        if playerLayer.player !== session?.player { playerLayer.player = session?.player }
        let nextVlcView = session?.vlcVideoView
        if attachedVlcView !== nextVlcView {
            if attachedVlcView?.superview === self { attachedVlcView?.removeFromSuperview() }
            attachedVlcView = nextVlcView
            if let nextVlcView {
                nextVlcView.translatesAutoresizingMaskIntoConstraints = false
                addSubview(nextVlcView)
                NSLayoutConstraint.activate([
                    nextVlcView.leadingAnchor.constraint(equalTo: leadingAnchor),
                    nextVlcView.trailingAnchor.constraint(equalTo: trailingAnchor),
                    nextVlcView.topAnchor.constraint(equalTo: topAnchor),
                    nextVlcView.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
            }
        }
        videoView.isHidden = track == nil
        playerLayer.isHidden = playerLayer.player == nil
        isHidden = track == nil && playerLayer.player == nil && nextVlcView == nil
    }

    deinit { track?.remove(videoView) }
}
