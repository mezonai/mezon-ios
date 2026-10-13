import UIKit

enum ChannelListGhostRowProbe {

    struct RowSample {
        let indexPath: IndexPath
        let kind: String
        let rect: CGRect
    }

    struct RowResult {
        let indexPath: IndexPath
        let kind: String
        let contrast: Double
        let isDim: Bool
    }

    struct Result {
        let rows: [RowResult]
        let expectedRowContrast: Double
        let referenceContrast: Double
        let isTrusted: Bool

        var dimRows: [RowResult] { rows.filter { $0.isDim } }

        var summary: String {
            rows.map {
                "\($0.indexPath.section).\($0.indexPath.row)\($0.kind.prefix(1)):\(Int($0.contrast))\($0.isDim ? "!" : "")"
            }.joined(separator: " ")
        }
    }

    static let dimThresholdRatio: Double = 0.3
    static let minimumTrustedReferenceContrast: Double = 40
    static let maxDumpLength = 12_000

    static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return Double(0.299 * r + 0.587 * g + 0.114 * b) * 255
        }
        var w: CGFloat = 0
        if color.getWhite(&w, alpha: &a) {
            return Double(w) * 255
        }
        return 0
    }

    static func measure(
        container: UIView,
        rows: [RowSample],
        referenceRects: [CGRect],
        exclusionRects: [CGRect],
        backgroundColor: UIColor,
        rowTextColor: UIColor
    ) -> Result? {
        let bounds = container.bounds
        let width = Int(bounds.width.rounded(.down))
        let height = Int(bounds.height.rounded(.down))
        guard width > 0, height > 0 else { return nil }
        let frame = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: frame.size, format: format).image { _ in
            container.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        guard let cgImage = image.cgImage else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            ctx.draw(cgImage, in: frame)
            return true
        }
        guard drawn else { return nil }

        let backgroundLuminance = luminance(backgroundColor)
        let expectedRowContrast = abs(luminance(rowTextColor) - backgroundLuminance)
        guard expectedRowContrast > 0 else { return nil }

        func contrast(in rect: CGRect) -> Double {
            let r = rect.integral.intersection(frame)
            guard !r.isNull, r.width >= 1, r.height >= 1 else { return 0 }
            let x0 = Int(r.minX), x1 = Int(r.maxX), y0 = Int(r.minY), y1 = Int(r.maxY)
            var best = 0.0
            for y in y0..<y1 {
                var i = (y * width + x0) * 4
                for _ in x0..<x1 {
                    let l = 0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])
                    let d = abs(l - backgroundLuminance)
                    if d > best { best = d }
                    i += 4
                }
            }
            return best
        }

        var referenceContrast = 0.0
        for rect in referenceRects {
            referenceContrast = max(referenceContrast, contrast(in: rect))
        }

        let threshold = expectedRowContrast * dimThresholdRatio
        var results: [RowResult] = []
        for row in rows {
            guard frame.contains(row.rect) else { continue }
            guard !exclusionRects.contains(where: { $0.intersects(row.rect) }) else { continue }
            let c = contrast(in: row.rect)
            results.append(RowResult(indexPath: row.indexPath, kind: row.kind, contrast: c, isDim: c < threshold))
        }
        return Result(
            rows: results,
            expectedRowContrast: expectedRowContrast,
            referenceContrast: referenceContrast,
            isTrusted: referenceContrast >= minimumTrustedReferenceContrast
        )
    }

    static func dump(table: UITableView, cells: [(IndexPath, UITableViewCell)], maxCells: Int = 4) -> String {
        var lines: [String] = []
        var ancestor: UIView? = table
        var depth = 0
        while let v = ancestor, depth < 12 {
            lines.append("A\(depth) " + describe(v))
            ancestor = v.superview
            depth += 1
        }
        let visible = Set(table.visibleCells.map { ObjectIdentifier($0) })
        var inTree = 0
        var hiddenPool = 0
        var orphans = 0
        for sub in table.subviews {
            guard let cell = sub as? UITableViewCell else { continue }
            inTree += 1
            if visible.contains(ObjectIdentifier(cell)) { continue }
            if cell.isHidden {
                hiddenPool += 1
            } else if cell.frame.intersects(table.bounds) {
                orphans += 1
                lines.append("ORPHAN " + describe(cell))
            }
        }
        lines.append("cells inTree=\(inTree) visible=\(visible.count) hiddenPool=\(hiddenPool) orphans=\(orphans)")
        for (indexPath, cell) in cells.prefix(maxCells) {
            lines.append("CELL \(indexPath.section).\(indexPath.row)")
            dumpTree(view: cell, indent: 1, maxDepth: 5, into: &lines)
        }
        let joined = lines.joined(separator: "\n")
        return joined.count > maxDumpLength ? String(joined.prefix(maxDumpLength)) : joined
    }

    private static func dumpTree(view: UIView, indent: Int, maxDepth: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent * 2)
        lines.append(pad + describe(view))
        guard indent < maxDepth else { return }
        let subviewLayers = Set(view.subviews.map { ObjectIdentifier($0.layer) })
        for sublayer in view.layer.sublayers ?? [] where !subviewLayers.contains(ObjectIdentifier(sublayer)) {
            lines.append(pad + "  +L " + describe(sublayer))
        }
        for sub in view.subviews {
            dumpTree(view: sub, indent: indent + 1, maxDepth: maxDepth, into: &lines)
        }
    }

    private static func describe(_ view: UIView) -> String {
        var s = "\(type(of: view)) a=\(fmt(Double(view.alpha)))"
        if view.isHidden { s += " hidden" }
        if view.transform != .identity { s += " vtransform" }
        return s + " " + describe(view.layer)
    }

    private static func describe(_ layer: CALayer) -> String {
        let p = layer.presentation()
        var s = "\(type(of: layer)) f=\(fmt(layer.frame)) o=\(fmt(Double(layer.opacity)))"
        s += " po=" + (p.map { fmt(Double($0.opacity)) } ?? "-")
        if layer.isHidden { s += " lhidden" }
        if let p, p.isHidden { s += " phidden" }
        if let mask = layer.mask { s += " mask(\(type(of: mask)) o=\(fmt(Double(mask.opacity))))" }
        if let filters = layer.filters, !filters.isEmpty { s += " filters=\(filters.count)" }
        if layer.compositingFilter != nil { s += " compositingFilter" }
        if layer.speed != 1 || layer.timeOffset != 0 || layer.beginTime != 0 {
            s += " time(s=\(fmt(Double(layer.speed))) to=\(fmt(layer.timeOffset)) bt=\(fmt(layer.beginTime)))"
        }
        if !CATransform3DIsIdentity(layer.transform) { s += " transform" }
        if let p, !CATransform3DIsIdentity(p.transform) { s += " ptransform" }
        if let p, !p.frame.equalTo(layer.frame) { s += " pf=\(fmt(p.frame))" }
        if layer.zPosition != 0 { s += " z=\(fmt(Double(layer.zPosition)))" }
        if layer.contents != nil { s += " contents" }
        if let keys = layer.animationKeys(), !keys.isEmpty {
            let anims = keys.map { key -> String in
                guard let anim = layer.animation(forKey: key) else { return key }
                let path = (anim as? CAPropertyAnimation)?.keyPath ?? "-"
                return "\(key)/\(type(of: anim))/\(path)/s=\(fmt(Double(anim.speed)))/bt=\(fmt(anim.beginTime))/rm=\(anim.isRemovedOnCompletion)"
            }
            s += " anim=[" + anims.joined(separator: ",") + "]"
        }
        return s
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private static func fmt(_ rect: CGRect) -> String {
        String(format: "(%.0f,%.0f,%.0f,%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
