import UIKit

enum ScreenScale {

    static let baseWidth:  CGFloat = 375
    static let baseHeight: CGFloat = 812

    static let width:  CGFloat = {
        let raw = UIScreen.main.bounds.width / baseWidth
        return raw.clamped(to: 0.85...1.5)
    }()

    static let height: CGFloat = {
        let raw = UIScreen.main.bounds.height / baseHeight
        return raw.clamped(to: 0.85...1.5)
    }()

    static let square: CGFloat = min(width, height)
    static let font: CGFloat = width.clamped(to: 0.85...1.2)

    static func w(_ v: CGFloat)   -> CGFloat { v * width  }
    static func h(_ v: CGFloat)   -> CGFloat { v * height }
    static func wh(_ v: CGFloat)  -> CGFloat { v * square }
    static func f(_ v: CGFloat)   -> CGFloat { ceil(v * font) }
}

extension CGFloat {
    var sw: CGFloat  { ScreenScale.w(self)  }
    var sh: CGFloat  { ScreenScale.h(self)  }
    var swh: CGFloat { ScreenScale.wh(self) }
    var sf: CGFloat  { ScreenScale.f(self)  }

    fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound))
    }
}

extension Int {
    var sw: CGFloat  { CGFloat(self).sw  }
    var sh: CGFloat  { CGFloat(self).sh  }
    var swh: CGFloat { CGFloat(self).swh }
    var sf: CGFloat  { CGFloat(self).sf  }
}

extension Double {
    var sw: CGFloat  { CGFloat(self).sw  }
    var sh: CGFloat  { CGFloat(self).sh  }
    var swh: CGFloat { CGFloat(self).swh }
    var sf: CGFloat  { CGFloat(self).sf  }
}

extension CGSize {
    var scaled: CGSize { CGSize(width: width.swh, height: height.swh) }
}
