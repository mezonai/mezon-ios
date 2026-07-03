import UIKit

enum ScreenScale {

    static let baseWidth:  CGFloat = 390
    static let baseHeight: CGFloat = 844

    static let width: CGFloat = {
        let size = UIScreen.main.bounds.size
        return (min(size.width, size.height) / baseWidth).clamped(to: 0.85...1.25)
    }()

    static let height: CGFloat = {
        let size = UIScreen.main.bounds.size
        return (max(size.width, size.height) / baseHeight).clamped(to: 0.82...1.25)
    }()

    static let square: CGFloat = min(width, height)

    static let font: CGFloat = width.clamped(to: 0.88...1.12)

    static func w(_ v: CGFloat)  -> CGFloat { floorToScreenPixels(v * width)  }
    static func h(_ v: CGFloat)  -> CGFloat { floorToScreenPixels(v * height) }
    static func wh(_ v: CGFloat) -> CGFloat { floorToScreenPixels(v * square) }
    static func f(_ v: CGFloat)  -> CGFloat { ceil(v * font) }
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
