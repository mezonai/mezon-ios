import UIKit

private enum _Scale {
    static let baseW: CGFloat = 375
    static let baseH: CGFloat = 812
    static var w: CGFloat { (UIScreen.main.bounds.width / baseW).clamped(0.85...1.5) }
    static var h: CGFloat { (UIScreen.main.bounds.height / baseH).clamped(0.85...1.5) }
    static var wh: CGFloat { Swift.min(w, h) }
    static var f: CGFloat { w.clamped(0.85...1.2) }
    static func sw(_ v: CGFloat) -> CGFloat { v * w }
    static func sh(_ v: CGFloat) -> CGFloat { v * h }
    static func swh(_ v: CGFloat) -> CGFloat { v * wh }
    static func sf(_ v: CGFloat) -> CGFloat { ceil(v * f) }
}

private extension CGFloat {
    func clamped(_ range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

enum Constants {

    enum Scale {
        static func sw(_ v: CGFloat) -> CGFloat { _Scale.sw(v) }
        static func sh(_ v: CGFloat) -> CGFloat { _Scale.sh(v) }
        static func swh(_ v: CGFloat) -> CGFloat { _Scale.swh(v) }
        static func sf(_ v: CGFloat) -> CGFloat { _Scale.sf(v) }
    }

    enum Layout {
        static let defaultPadding: CGFloat       = _Scale.sw(16)
        static let smallPadding: CGFloat         = _Scale.sw(8)
        static let largePadding: CGFloat         = _Scale.sw(24)
        static let cornerRadius: CGFloat        = _Scale.sw(12)
        static let avatarSize: CGFloat           = _Scale.swh(44)
        static let messageBubbleMaxWidth: CGFloat = UIScreen.main.bounds.width * 0.72
        static let inputBarHeight: CGFloat       = _Scale.sh(56)
        static let buttonHeight: CGFloat         = _Scale.sh(52)
        static let rowHeight: CGFloat            = _Scale.sh(44)
        static let sectionHeaderHeight: CGFloat = _Scale.sh(32)
        static let clanSidebarWidth: CGFloat     = _Scale.sw(64)
    }

    enum Animation {
        static let defaultDuration: Double  = 0.25
        static let springDamping: CGFloat   = 0.8
    }

    enum Pagination {
        static let messagesPageSize: Int    = 50
        static let channelsPageSize: Int   = 30
    }

    enum Font {
        static let tiny: CGFloat    = _Scale.sf(10)
        static let caption: CGFloat = _Scale.sf(11)
        static let small: CGFloat   = _Scale.sf(12)
        static let body: CGFloat    = _Scale.sf(13)
        static let callout: CGFloat = _Scale.sf(15)
        static let regular: CGFloat = _Scale.sf(16)
        static let subhead: CGFloat = _Scale.sf(17)
        static let title3: CGFloat  = _Scale.sf(18)
        static let title2: CGFloat  = _Scale.sf(20)
        static let title: CGFloat   = _Scale.sf(22)
        static let large: CGFloat   = _Scale.sf(28)
        static let hero: CGFloat   = _Scale.sf(32)
    }
}
