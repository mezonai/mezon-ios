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
