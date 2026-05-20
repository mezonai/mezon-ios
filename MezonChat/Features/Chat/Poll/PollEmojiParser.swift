import UIKit

enum PollEmojiParser {
    static func parse(_ text: String, font: UIFont, color: UIColor, emojiSize: CGFloat = 20, lineBreakMode: NSLineBreakMode = .byTruncatingTail) -> NSAttributedString {
        let pattern = "\\[e:([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        }
        
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        let result = NSMutableAttributedString()
        var lastOffset = 0
        
        let ps = NSMutableParagraphStyle()
        ps.lineBreakMode = lineBreakMode
        
        for match in matches {
            let matchRange = match.range
            if matchRange.location > lastOffset {
                let plainText = nsString.substring(with: NSRange(location: lastOffset, length: matchRange.location - lastOffset))
                result.append(NSAttributedString(string: plainText, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: ps
                ]))
            }
            
            if match.numberOfRanges > 1, let emojiId = nsString.substring(with: match.range(at: 1)) as String?, !emojiId.isEmpty {
                let attachment = EmojiTextAttachment(
                    emojiId: emojiId,
                    emojiSize: emojiSize,
                    baselineFont: font,
                    imgproxyFitSide: Int(emojiSize * 2)
                )
                let mas = NSMutableAttributedString(attachment: attachment)
                mas.addAttributes([
                    .font: font,
                    .paragraphStyle: ps
                ], range: NSRange(location: 0, length: mas.length))
                result.append(mas)
            }
            
            lastOffset = matchRange.location + matchRange.length
        }
        
        if lastOffset < nsString.length {
            let plainText = nsString.substring(from: lastOffset)
            result.append(NSAttributedString(string: plainText, attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: ps
            ]))
        }
        
        return result
    }
}
