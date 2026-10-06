import Foundation
import WebRTC

struct SfuLossSample {
    let id: String
    let upload: Bool
    let packets: Double
    let lost: Double
}

final class SfuNetworkQuality {

    private static let lossRatio = 0.05
    private static let minPackets: Double = 50
    private static let clearSamples = 2

    private var previous: [String: SfuLossSample] = [:]
    private var isWeak = false
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
        let lossy = Self.isLossy(expected: receivedExpected, lost: receivedLost)
            || Self.isLossy(expected: sentExpected, lost: sentLost)
        cleanSamples = lossy ? 0 : cleanSamples + 1
        if lossy {
            isWeak = true
        } else if cleanSamples >= Self.clearSamples {
            isWeak = false
        }
        return isWeak
    }

    private static func isLossy(expected: Double, lost: Double) -> Bool {
        expected >= minPackets && lost / expected >= lossRatio
    }

    static func lossSamples(in report: RTCStatisticsReport) -> [SfuLossSample] {
        let stats = report.statistics
        var samples: [SfuLossSample] = []
        for (id, stat) in stats {
            let values = stat.values
            guard let lost = (values["packetsLost"] as? NSNumber)?.doubleValue else { continue }
            let upload = stat.type == "remote-inbound-rtp"
            let packets: NSNumber?
            if stat.type == "inbound-rtp" {
                packets = values["packetsReceived"] as? NSNumber
            } else if upload, let localId = values["localId"] as? String {
                packets = stats[localId]?.values["packetsSent"] as? NSNumber
            } else {
                packets = nil
            }
            guard let packets else { continue }
            samples.append(SfuLossSample(id: id, upload: upload, packets: packets.doubleValue, lost: lost))
        }
        return samples
    }
}
