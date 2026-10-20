import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private var sender: ScreenShareFrameSender?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let sender = ScreenShareFrameSender()
        sender.onEnded = { [weak self] reason in
            DispatchQueue.main.async { self?.finish(reason) }
        }
        self.sender = sender
        sender.start()
    }

    override func broadcastFinished() {
        sender?.stop()
        sender = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        sender?.send(sampleBuffer)
    }

    private func finish(_ reason: ScreenShareFrameSender.EndReason) {
        let message: String
        switch reason {
        case .appUnavailable:
            message = NSLocalizedString(
                "screenShare.joinVoiceFirst", tableName: nil, bundle: .main,
                value: "Join a voice channel in Mezon to share your screen.", comment: "")
        case .stoppedByApp:
            message = NSLocalizedString(
                "screenShare.stopped", tableName: nil, bundle: .main,
                value: "Screen sharing has stopped.", comment: "")
        }
        sender?.stop()
        sender = nil
        finishBroadcastWithError(NSError(
            domain: ScreenShareBroadcastChannel.extensionBundleIdentifier,
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        ))
    }
}
