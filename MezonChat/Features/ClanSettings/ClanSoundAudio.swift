import AVFoundation

enum ClanSoundAudio {
    static let maxFileBytes = 1024 * 1024
    static let minDuration: TimeInterval = 1
    static let maxDuration: TimeInterval = 10

    struct Source {
        let url: URL
        let duration: TimeInterval
        let fileExtension: String
    }

    enum Failure: LocalizedError {
        case invalidFile, tooLarge, invalidDuration

        var errorDescription: String? {
            switch self {
            case .invalidFile: return L(L10n.ClanSetting.Sounds.invalidFile)
            case .tooLarge: return L(L10n.ClanSetting.Sounds.fileTooLarge)
            case .invalidDuration: return L(L10n.ClanSetting.Sounds.durationRequirement)
            }
        }
    }

    static func importFile(_ url: URL) throws -> Source {
        let ext = url.pathExtension.lowercased()
        guard ["mp3", "mpeg", "wav"].contains(ext) else { throw Failure.invalidFile }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw Failure.invalidFile }
        guard size <= maxFileBytes else { throw Failure.tooLarge }
        let audio: AVAudioFile
        do { audio = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch { throw Failure.invalidFile }
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw Failure.invalidFile }
        guard duration >= minDuration else { throw Failure.invalidDuration }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try FileManager.default.copyItem(at: url, to: copy)
        return Source(url: copy, duration: duration, fileExtension: ext)
    }

    static func uploadData(source: Source, start: TimeInterval, end: TimeInterval, volume: Float) throws -> (data: Data, fileExtension: String) {
        guard start >= 0, end <= source.duration, end >= start + minDuration,
              end - start <= maxDuration else { throw Failure.invalidDuration }
        if start == 0, end == source.duration, volume == 1 {
            return (try Data(contentsOf: source.url), source.fileExtension)
        }
        let input = try AVAudioFile(forReading: source.url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = input.processingFormat
        let firstFrame = AVAudioFramePosition(start * format.sampleRate)
        let frameCount = AVAudioFrameCount((end - start) * format.sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: format, to: outputFormat) else { throw Failure.invalidFile }
        input.framePosition = firstFrame
        try input.read(into: buffer, frameCount: frameCount)
        let outputCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 44100 / format.sampleRate)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw Failure.invalidFile
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, state in
            if supplied {
                state.pointee = .endOfStream
                return nil
            }
            supplied = true
            state.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.floatChannelData?[0] else {
            throw conversionError ?? Failure.invalidFile as NSError
        }
        for index in 0..<Int(output.frameLength) {
            samples[index] *= volume
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: destination) }
       
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
        ]
        do {
            let file = try AVAudioFile(forWriting: destination, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: output)
        }
        let data = try Data(contentsOf: destination)
        guard data.count <= maxFileBytes else { throw Failure.tooLarge }
        return (data, "wav")
    }

    static func waveformPeaks(source: Source, barCount: Int = 144) throws -> [Float] {
        guard barCount > 0 else { return [] }
        let file = try AVAudioFile(forReading: source.url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
            throw Failure.invalidFile
        }
        var peaks = [Float](repeating: 0, count: barCount)
        var offset: AVAudioFramePosition = 0
        while offset < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let bar = min(barCount - 1, Int(Double(offset + AVAudioFramePosition(frame)) / Double(file.length) * Double(barCount)))
                for channel in 0..<Int(format.channelCount) {
                    peaks[bar] = max(peaks[bar], abs(channels[channel][frame]))
                }
            }
            offset += AVAudioFramePosition(buffer.frameLength)
        }
        // Match desktop: retain source amplitude rather than normalizing quiet audio to full height.
        return peaks.map { min(1, max(0.08, $0)) }
    }

    static func timeLabel(_ seconds: TimeInterval) -> String {
        let value = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
