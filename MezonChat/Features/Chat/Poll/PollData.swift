import Foundation

struct PollData {
    let id: Int64
    let question: String
    let answers: [PollAnswer]
    let answerCounts: [Int: Int]
    let totalVotes: Int
    let expireAt: TimeInterval
    let isClosed: Bool
    let type: PollType

    enum PollType: Int {
        case single = 0
        case multiple = 1
    }

    struct PollAnswer {
        let index: Int
        let label: String
    }

    static func parse(from data: Data) -> PollData? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parse(from: json)
    }

    static func parse(from json: [String: Any]) -> PollData? {
        guard let id = (json["id"] as? NSNumber)?.int64Value ?? Int64(json["id"] as? String ?? "") else {
            return nil
        }
        guard let question = json["question"] as? String,
              let answersArray = json["answers"] as? [[String: Any]] else {
            return nil
        }
        
        let totalVotes = (json["total_votes"] as? NSNumber)?.intValue ?? 0
        let expireAt = (json["expire_at"] as? NSNumber)?.doubleValue ?? 0
        let isClosed = json["is_closed"] as? Bool ?? false
        let typeRaw = (json["type"] as? NSNumber)?.intValue ?? 0
        let pollType = PollType(rawValue: typeRaw) ?? .single

        var answers: [PollAnswer] = []
        for answerJson in answersArray {
            let index = (answerJson["index"] as? NSNumber)?.intValue ?? 0
            let label = answerJson["label"] as? String ?? ""
            answers.append(PollAnswer(index: index, label: label))
        }

        var answerCounts: [Int: Int] = [:]
        if let countsArray = json["answer_counts"] as? [NSNumber] {
            for (i, count) in countsArray.enumerated() {
                answerCounts[i] = count.intValue
            }
        } else if let countsDict = json["answer_counts"] as? [String: Any] {
            for (key, value) in countsDict {
                if let idx = Int(key), let count = (value as? NSNumber)?.intValue {
                    answerCounts[idx] = count
                }
            }
        }

        return PollData(
            id: id,
            question: question,
            answers: answers,
            answerCounts: answerCounts,
            totalVotes: totalVotes,
            expireAt: expireAt,
            isClosed: isClosed,
            type: pollType
        )
    }
}

struct PollOptionDisplay {
    let index: Int
    let label: String
    let voteCount: Int
    let percentage: Int
    var isSelected: Bool
}

struct PollVoter {
    let id: String
    let displayName: String
    let username: String
    let avatar: String
}
