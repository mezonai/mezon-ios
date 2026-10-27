#!/usr/bin/env python3
"""Run focused stream join/control checks without building the iOS app.

The harness compiles the production Swift methods verbatim, substituting a
controlled playback provider and transport so join races are deterministic.
Run from any directory: python3 scripts/check_streaming_join.py
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'MezonChat/Features/VoiceChannel/StreamingWebRTCSession.swift').read_text()


def declaration(pattern):
    start = re.search(pattern, source, re.MULTILINE)
    if start is None:
        raise RuntimeError(f'Production declaration not found: {pattern}')
    end = re.search(r'^    }$', source[start.start():], re.MULTILINE)
    if end is None:
        raise RuntimeError('Production declaration has no closing brace')
    return source[start.start():start.start() + end.end()]


def method(name):
    return declaration(r'^    (?:private )?func ' + name + r'\b').replace('    private func ', '    func ', 1)


enum_start = source.index('enum StreamingQuality:')
enum_end = source.index('\n}', enum_start) + 2
quality_enum = source[enum_start:enum_end]
methods = '\n'.join(method(name) for name in [
    'join', 'disconnect', 'setVolume', 'toggleMute', 'setDefaultQuality', 'armWatchdog', 'connected',
])
default_quality = declaration(r'^    var defaultQuality:')

harness = '''
import Foundation
import CoreGraphics

enum UserDefaults {
    static let suite = "mezon-stream-check-" + UUID().uuidString
    static let standard = Foundation.UserDefaults(suiteName: suite)!
}
struct Playback {}
enum TestError: Error { case unavailable }
@MainActor final class AccountContext {
    var pending: [Int64: CheckedContinuation<Playback, Error>] = [:]
    var requests: [Int64: Int] = [:]
    func playback(_ channelId: Int64) async throws -> Playback {
        requests[channelId, default: 0] += 1
        return try await withCheckedThrowingContinuation { pending[channelId] = $0 }
    }
    func resolve(_ channelId: Int64, _ result: Result<Playback, Error> = .success(Playback())) {
        pending.removeValue(forKey: channelId)!.resume(with: result)
    }
    func waitFor(_ channelId: Int64) async {
        for _ in 0..<10_000 {
            if pending[channelId] != nil { return }
            await Task.yield()
        }
        preconditionFailure("Join did not request playback")
    }
}
@MainActor final class JoinHarness {
    var activeStreamChannelId: Int64?
    var pendingJoinChannelId: Int64?
    var joinRequestGeneration = 0
    var generation = 0
    var transportGeneration = 0
    var watchdogTask: Task<Void, Never>?
    var watchdogDeadline: TimeInterval?
    var isConnectingWhep = false
    var player: Int?
    var vlcPlayer: Int?
    var reconnectAttempt = 0
    var isStreaming = false
    var isBuffering = false
    var timeoutAction: String?
    func log(_ event: String, _ details: String = "") {}
    func startHls(transport: Int) { timeoutAction = "hls" }
    func fallbackFromNativeHls(transport: Int) { timeoutAction = "vlc" }
    func scheduleReconnect() { timeoutAction = "reconnect" }
    var context: AccountContext?
    var clanId: Int64 = 0
    var quality: StreamingQuality = .auto
    var preferredSpeakerOutput: Bool?
    var volume: Float = 1
    var isMuted = false
    var onStreamingStateChanged: (() -> Void)?
    static let defaultQualityKey = "mezon.stream.defaultQuality"
    var stopped: [Int64] = []
    var watched: [Int64] = []
    var errors = 0
    var appliedVolume: Float = 1
    func fetchPlayback(channelId: Int64, context: AccountContext) async throws -> Playback {
        try await context.playback(channelId)
    }
    func stopPlayback(sendUnwatch: Bool) {
        if let id = activeStreamChannelId { stopped.append(id) }
        activeStreamChannelId = nil
        generation += 1
    }
    func startPresence() { watched.append(activeStreamChannelId!) }
    func startPlayback(_ playback: Playback) {}
    func showPlaybackError() { errors += 1 }
    func applyAudioSettings() { appliedVolume = isMuted ? 0 : volume }
'''
checks = '''
}
@main struct JoinChecks {
    @MainActor static func main() async {
        defer { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suite) }
        let context = AccountContext()
        let subject = JoinHarness()
        let first = Task { await subject.join(channelId: 1, clanId: 11, context: context) }
        await context.waitFor(1)
        precondition(subject.activeStreamChannelId == nil)
        context.resolve(1)
        let firstJoined = await first.value
        precondition(firstJoined && subject.activeStreamChannelId == 1 && subject.clanId == 11)

        precondition(subject.preferredSpeakerOutput == true, "new streams must start on speaker")
        subject.preferredSpeakerOutput = false

        let failed = Task { await subject.join(channelId: 2, clanId: 22, context: context) }
        await context.waitFor(2)
        precondition(subject.activeStreamChannelId == 1 && subject.stopped.isEmpty)
        context.resolve(2, .failure(TestError.unavailable))
        let failedJoined = await failed.value
        precondition(!failedJoined && subject.activeStreamChannelId == 1 && subject.errors == 1)
        precondition(subject.preferredSpeakerOutput == false, "failed joins must preserve the current route")

        var stillVisible = true
        let stale = Task { await subject.join(channelId: 3, clanId: 33, context: context, canJoin: { stillVisible }) }
        await context.waitFor(3)
        stillVisible = false
        context.resolve(3)
        let staleJoined = await stale.value
        precondition(!staleJoined && subject.activeStreamChannelId == 1 && subject.stopped.isEmpty)

        let duplicate = Task { await subject.join(channelId: 4, clanId: 44, context: context) }
        await context.waitFor(4)
        let duplicateJoined = await subject.join(channelId: 4, clanId: 44, context: context)
        precondition(!duplicateJoined && context.requests[4] == 1)
        context.resolve(4)
        let fourthJoined = await duplicate.value
        precondition(fourthJoined && subject.stopped == [1] && subject.watched == [1, 4])
        precondition(subject.preferredSpeakerOutput == true, "switching streams resets to speaker")

        let older = Task { await subject.join(channelId: 5, clanId: 55, context: context) }
        await context.waitFor(5)
        let newer = Task { await subject.join(channelId: 6, clanId: 66, context: context) }
        await context.waitFor(6)
        context.resolve(5)
        let olderJoined = await older.value
        precondition(!olderJoined && subject.activeStreamChannelId == 4)
        context.resolve(6)
        let newerJoined = await newer.value
        precondition(newerJoined && subject.activeStreamChannelId == 6 && subject.clanId == 66)

        let leaving = Task { await subject.join(channelId: 7, clanId: 77, context: context) }
        await context.waitFor(7)
        subject.disconnect()
        context.resolve(7)
        let joinedAfterLeave = await leaving.value
        precondition(!joinedAfterLeave && subject.activeStreamChannelId == nil)

        let canceled = Task { await subject.join(channelId: 8, clanId: 88, context: context) }
        await context.waitFor(8)
        canceled.cancel()
        context.resolve(8)
        let canceledJoined = await canceled.value
        precondition(!canceledJoined && subject.activeStreamChannelId == nil)

        subject.setDefaultQuality(.low)
        let defaultJoin = Task { await subject.join(channelId: 9, clanId: 99, context: context) }
        await context.waitFor(9)
        context.resolve(9)
        let defaultJoined = await defaultJoin.value
        precondition(defaultJoined && subject.quality == .low && subject.defaultQuality == .low)
        let pendingSwitch = Task { await subject.join(channelId: 10, clanId: 100, context: context) }
        await context.waitFor(10)
        subject.preferredSpeakerOutput = false
        let returnedToCurrent = await subject.join(channelId: 9, clanId: 99, context: context)
        precondition(returnedToCurrent)
        precondition(subject.preferredSpeakerOutput == false, "restoring the same stream must preserve the selected route")
        context.resolve(10)
        let switchedAfterReturn = await pendingSwitch.value
        precondition(!switchedAfterReturn && subject.activeStreamChannelId == 9)

        subject.setVolume(0)
        subject.toggleMute()
        precondition(subject.volume == 0.5 && !subject.isMuted && subject.appliedVolume == 0.5)
        subject.toggleMute()
        precondition(subject.isMuted && subject.appliedVolume == 0)
        subject.setVolume(0.7)
        precondition(!subject.isMuted && subject.appliedVolume == 0.7)
        subject.setVolume(.nan)
        precondition(subject.volume == 0.7)
        subject.setVolume(2)
        precondition(subject.volume == 1)
        subject.setVolume(-1)
        precondition(subject.volume == 0)
        precondition(StreamingQuality.low.maximumResolution == CGSize(width: 640, height: 360))
        precondition(StreamingQuality.mid.maximumResolution == CGSize(width: 1280, height: 720))
        precondition(StreamingQuality.auto.maximumResolution == .zero)
        let deadlineSubject = JoinHarness()
        deadlineSubject.armWatchdog(transport: 0, delay: 200_000_000)
        let firstDeadline = deadlineSubject.watchdogDeadline!
        try? await Task.sleep(nanoseconds: 10_000_000)
        deadlineSubject.armWatchdog(transport: 0, delay: 200_000_000)
        precondition(deadlineSubject.watchdogDeadline == firstDeadline, "buffering must not postpone a deadline")
        deadlineSubject.armWatchdog(transport: 0, delay: 30_000_000)
        precondition(deadlineSubject.watchdogDeadline! < firstDeadline, "a shorter connection timeout must take effect")
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(deadlineSubject.timeoutAction == "reconnect" && deadlineSubject.watchdogDeadline == nil)

        deadlineSubject.timeoutAction = nil
        deadlineSubject.player = 1
        deadlineSubject.armWatchdog(transport: 0, delay: 20_000_000)
        try? await Task.sleep(nanoseconds: 60_000_000)
        precondition(deadlineSubject.timeoutAction == "vlc", "native HLS timeout must try the compatible decoder")

        deadlineSubject.timeoutAction = nil
        deadlineSubject.player = nil
        deadlineSubject.isConnectingWhep = true
        deadlineSubject.armWatchdog(transport: 0, delay: 20_000_000)
        try? await Task.sleep(nanoseconds: 60_000_000)
        precondition(deadlineSubject.timeoutAction == "hls", "WHEP timeout must fall back to HLS")

        deadlineSubject.timeoutAction = nil
        deadlineSubject.armWatchdog(transport: 0, delay: 20_000_000)
        deadlineSubject.connected()
        try? await Task.sleep(nanoseconds: 60_000_000)
        precondition(deadlineSubject.timeoutAction == nil && deadlineSubject.watchdogDeadline == nil)
        precondition(deadlineSubject.isStreaming && !deadlineSubject.isBuffering)
        print("PASS: join races, quality/audio controls, fixed buffering deadlines, HLS/VLC fallback and progress cancellation")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='mezon-stream-join-') as folder:
    swift_file = Path(folder) / 'JoinChecks.swift'
    executable = Path(folder) / 'join-checks'
    swift_file.write_text(quality_enum + harness + default_quality + '\n' + methods + checks)
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(swift_file), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
