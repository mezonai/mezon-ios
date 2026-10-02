// Targeted simulator check: compile together with PeerCallVideoRenderView.swift
// and link the app's WebRTC.framework; run the executable using simctl spawn.
// No signaling server, audio capture or live call is required.
import Foundation
import UIKit
import WebRTC

@main
struct ScreenFrameIdentityCheck {
    @MainActor static func main() {
        let factory = RTCPeerConnectionFactory()
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let pc = factory.peerConnection(with: config, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: nil)!
        let receiver = pc.addTransceiver(of: .video)!.receiver
        let first = receiver.track as! RTCVideoTrack
        let second = receiver.track as! RTCVideoTrack
        precondition(first !== second && first.isEqual(second), "SDK must return equal native tracks in different wrappers")
        let keeper = VideoTrackLastFrameStore.observe(first)
        var pixels: CVPixelBuffer?
        precondition(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess)
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels!), rotation: ._0, timeStampNs: 100)
        keeper.renderFrame(frame)
        let frameTime = keeper.lastFrameUptime
        precondition(VideoTrackLastFrameStore.observe(second) === keeper, "wrapper changes must keep the observer")
        precondition(VideoTrackLastFrameStore.cachedFrame(of: second) === frame, "wrapper changes must preserve static frames")
        precondition(VideoTrackLastFrameStore.cachedFrameUptime(of: second) == frameTime, "reusing a wrapper must not fake freshness")
        precondition(VideoTrackLastFrameStore.canonicalTrack(second) === first, "recovery must retain stable wrapper identity")
        let replacement = factory.videoTrack(with: factory.videoSource(), trackId: first.trackId)
        precondition(!replacement.isEqual(first))
        let replacementKeeper = VideoTrackLastFrameStore.observe(replacement)
        precondition(replacementKeeper !== keeper && replacementKeeper.lastFrame == nil, "same ID on a new native track must not reuse old pixels")
        replacementKeeper.renderFrame(frame)
        _ = VideoTrackLastFrameStore.observe(first)
        precondition(VideoTrackLastFrameStore.cachedFrame(of: replacement) === frame, "an old detail view must not clear the new source cache")
        VideoTrackLastFrameStore.clearFrame(of: second)
        precondition(VideoTrackLastFrameStore.cachedFrame(of: first) == nil, "restarted share must invalidate cached pixels")
        precondition(VideoTrackLastFrameStore.cachedFrame(of: replacement) === frame, "invalidation must be isolated by native track")
        print("PASS: real WebRTC wrapper equality, frame retention, stable recovery identity, replacement isolation, share restart invalidation")
        pc.close()
    }
}
