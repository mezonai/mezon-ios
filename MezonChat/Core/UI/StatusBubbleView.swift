import UIKit

final class StatusBubbleView: UIView {

    private let tailWidth: CGFloat = 12
    private let tailHeight: CGFloat = 14
    private let cornerRadius: CGFloat = 12

    private let bubbleLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        bubbleLayer.fillColor = UIColor.mezonSecondaryBackground.cgColor
        bubbleLayer.strokeColor = nil
        layer.addSublayer(bubbleLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.5).cgColor
        borderLayer.lineWidth = 1.5
        borderLayer.lineJoin = .round
        borderLayer.lineCap = .round
        layer.addSublayer(borderLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updatePath()
    }

    private func updatePath() {
        let b = bounds
        guard b.width > 0, b.height > 0 else { return }

        let w = b.width
        let h = b.height
        let bodyBottom = h - tailHeight
        let r = min(cornerRadius, min(w, bodyBottom) / 2)
        let tailTip = CGPoint(x: 0, y: h)

        let path = UIBezierPath()

        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        path.addArc(withCenter: CGPoint(x: w - r, y: r),
                    radius: r,
                    startAngle: -.pi / 2,
                    endAngle: 0,
                    clockwise: true)
        path.addLine(to: CGPoint(x: w, y: bodyBottom - r))
        path.addArc(withCenter: CGPoint(x: w - r, y: bodyBottom - r),
                    radius: r,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: true)
        path.addLine(to: CGPoint(x: tailWidth, y: bodyBottom))
        path.addLine(to: tailTip)
        path.addLine(to: CGPoint(x: 0, y: bodyBottom - tailHeight))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addArc(withCenter: CGPoint(x: r, y: r),
                    radius: r,
                    startAngle: .pi,
                    endAngle: -.pi / 2,
                    clockwise: true)
        path.close()

        bubbleLayer.path = path.cgPath
        borderLayer.path = path.cgPath
    }

    func setFillColor(_ color: UIColor) {
        bubbleLayer.fillColor = color.cgColor
    }

    func setBorderColor(_ color: UIColor) {
        borderLayer.strokeColor = color.cgColor
    }
}
