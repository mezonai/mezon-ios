import Foundation
import WebRTC

struct SfuLossSample {
    let id: String
    let upload: Bool
    let packets: Double
    let lost: Double
}

final class SfuNetworkQuality {

    private static let warningLossRatio = 0.10
    private static let severeLossRatio = 0.20
    private static let recoveryLossRatio = 0.05
    private static let minPackets: Double = 50
    private static let warningSamples = 2
    private static let clearSamples = 2

    private var previous: [String: SfuLossSample] = [:]
    private var isWeak = false
    private var badSamples = 0
    private var cleanSamples = 0

    func update(_ samples: [SfuLossSample]) -> Bool {
        var receivedExpected: Double = 0
        var receivedLost: Double = 0
        var sentExpected: Double = 0
        var sentLost: Double = 0
        for sample in samples {
            guard let before = previous[sample.id] else { continue }
            let lostDelta = max(0, sample.lost - before.lost)
            let packetsDelta = max(0, sample.packets - before.packets)
            if sample.upload {
                sentLost += lostDelta
                sentExpected += packetsDelta
            } else {
                receivedLost += lostDelta
                receivedExpected += packetsDelta + lostDelta
            }
        }
        previous = Dictionary(samples.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        let ratios = [
            Self.lossRatio(expected: receivedExpected, lost: receivedLost),
            Self.lossRatio(expected: sentExpected, lost: sentLost)
        ].compactMap { $0 }
        guard let ratio = ratios.max() else {
            // Silence or a new stream is not evidence that the network recovered.
            badSamples = 0
            cleanSamples = 0
            return isWeak
        }
        badSamples = ratio >= Self.warningLossRatio ? min(badSamples + 1, Self.warningSamples) : 0
        cleanSamples = ratio < Self.recoveryLossRatio ? min(cleanSamples + 1, Self.clearSamples) : 0
        if ratio >= Self.severeLossRatio || badSamples >= Self.warningSamples {
            isWeak = true
        } else if cleanSamples >= Self.clearSamples {
            isWeak = false
        }
        return isWeak
    }

    private static func lossRatio(expected: Double, lost: Double) -> Double? {
        expected >= minPackets ? lost / expected : nil
    }

    static func lossSamples(in report: RTCStatisticsReport) -> [SfuLossSample] {
        let stats = report.statistics
        var samples: [SfuLossSample] = []
        for (id, stat) in stats {
            guard stat.type == "inbound-rtp" || stat.type == "remote-inbound-rtp" else { continue }
            let values = stat.values
            guard let lost = (values["packetsLost"] as? NSNumber)?.doubleValue else { continue }
            let upload = stat.type == "remote-inbound-rtp"
            let media = upload ? (values["localId"] as? String).flatMap { stats[$0] } : stat
            guard let media else { continue }
            let kind = (media.values["kind"] as? String) ?? (media.values["mediaType"] as? String)
            guard kind == "audio",
                  let packets = media.values[upload ? "packetsSent" : "packetsReceived"] as? NSNumber else { continue }
            samples.append(SfuLossSample(id: id, upload: upload, packets: packets.doubleValue, lost: lost))
        }
        return samples
    }
}

struct SfuCameraUplinkSample {
    let framesEncoded: Double
    let targetBitrate: Double
    let bandwidthLimited: Bool
}

final class SfuCameraUplinkQuality {

    private static let targetRatio = 0.8
    private static let limitedSamplesToLower = 2
    private static let baseRecoverySamples = 6
    private static let maxRecoverySamples = 24
    private static let relapseSamples = 12

    private var isLimited = false
    private var limitedSamples = 0
    private var cleanSamples = 0
    private var recoverySamples = SfuCameraUplinkQuality.baseRecoverySamples
    private var samplesSinceRecovery = Int.max
    private var framesEncoded: Double?

    func update(_ sample: SfuCameraUplinkSample?, maxBitrateBps: Int) -> Bool {
        let previousFrames = framesEncoded
        framesEncoded = sample?.framesEncoded
        guard let sample, let previousFrames, sample.framesEncoded > previousFrames else {
            isLimited = false
            limitedSamples = 0
            cleanSamples = 0
            return false
        }
        let sampleLimited = sample.bandwidthLimited
            && sample.targetBitrate < Double(maxBitrateBps) * Self.targetRatio
        if sampleLimited {
            limitedSamples += 1
            cleanSamples = 0
        } else {
            limitedSamples = 0
            cleanSamples += 1
        }
        if isLimited {
            if cleanSamples >= recoverySamples {
                isLimited = false
                samplesSinceRecovery = 0
            }
            return isLimited
        }
        if samplesSinceRecovery < Int.max {
            samplesSinceRecovery += 1
        }
        if limitedSamples >= Self.limitedSamplesToLower {
            isLimited = true
            recoverySamples = samplesSinceRecovery <= Self.relapseSamples
                ? min(recoverySamples * 2, Self.maxRecoverySamples)
                : Self.baseRecoverySamples
        }
        return isLimited
    }

    static func sample(in report: RTCStatisticsReport, mid: String) -> SfuCameraUplinkSample? {
        var best: SfuCameraUplinkSample?
        for stat in report.statistics.values {
            guard stat.type == "outbound-rtp" else { continue }
            let values = stat.values
            let kind = (values["kind"] as? String) ?? (values["mediaType"] as? String)
            guard kind == "video",
                  (values["mid"] as? String) == mid,
                  let frames = (values["framesEncoded"] as? NSNumber)?.doubleValue,
                  let target = (values["targetBitrate"] as? NSNumber)?.doubleValue,
                  let reason = values["qualityLimitationReason"] as? String else { continue }
            if let best, best.framesEncoded >= frames { continue }
            best = SfuCameraUplinkSample(
                framesEncoded: frames,
                targetBitrate: target,
                bandwidthLimited: reason == "bandwidth"
            )
        }
        return best
    }
}
