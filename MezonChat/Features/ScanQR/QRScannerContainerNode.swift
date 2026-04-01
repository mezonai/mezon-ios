import AsyncDisplayKit
import UIKit

final class QRScannerContainerNode: ASDisplayNode {

    private let scannerOverlay = ASDisplayNode()
    private let closeButton = ASButtonNode()
    private let flashButton = ASButtonNode()
    private let galleryButton = ASButtonNode()
    private let titleLabel = ASTextNode()

    var onCloseTapped: (() -> Void)?
    var onFlashTapped: (() -> Void)?
    var onGalleryTapped: (() -> Void)?

    override init() {
        super.init()
        self.backgroundColor = .clear

        scannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        scannerOverlay.isLayerBacked = true
        scannerOverlay.isUserInteractionEnabled = false

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white

        flashButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        flashButton.tintColor = .white

        galleryButton.setTitle(
            L(L10n.QRScanner.gallery), with: .systemFont(ofSize: 16, weight: .medium), with: .white,
            for: .normal)
        galleryButton.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        galleryButton.cornerRadius = 20

        titleLabel.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white,
            ])

        self.addSubnode(scannerOverlay)
        self.addSubnode(closeButton)
        self.addSubnode(flashButton)
        self.addSubnode(galleryButton)
        self.addSubnode(titleLabel)
    }

    override func didLoad() {
        super.didLoad()

        closeButton.addTarget(
            self, action: #selector(closeTapped), forControlEvents: .touchUpInside)
        flashButton.addTarget(
            self, action: #selector(toggleFlash), forControlEvents: .touchUpInside)
        galleryButton.addTarget(
            self, action: #selector(openGallery), forControlEvents: .touchUpInside)
    }

    func updateFlashButton(isOn: Bool) {
        flashButton.setImage(
            UIImage(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill"), for: .normal)
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        // We use manual layout in containerLayoutUpdated for precise control over camera overlay and safe areas
        return ASLayoutSpec()
    }

    func updateLayout(
        size: CGSize, safeInsets: UIEdgeInsets, intrinsicInsets: UIEdgeInsets,
        transition: ContainedViewLayoutTransition
    ) {
        transition.updateFrame(node: scannerOverlay, frame: CGRect(origin: .zero, size: size))

        let closeSize = CGSize(width: 44, height: 44)
        transition.updateFrame(
            node: closeButton,
            frame: CGRect(
                x: 16, y: safeInsets.top + 8, width: closeSize.width, height: closeSize.height))

        let flashSize = CGSize(width: 44, height: 44)
        transition.updateFrame(
            node: flashButton,
            frame: CGRect(
                x: size.width - 60, y: safeInsets.top + 8, width: flashSize.width,
                height: flashSize.height))

        let titleSize = titleLabel.calculateSizeThatFits(size)
        transition.updateFrame(
            node: titleLabel,
            frame: CGRect(
                x: (size.width - titleSize.width) / 2, y: safeInsets.top + 20,
                width: titleSize.width, height: titleSize.height))

        let galleryW: CGFloat = 120
        let galleryH: CGFloat = 40
        transition.updateFrame(
            node: galleryButton,
            frame: CGRect(
                x: (size.width - galleryW) / 2, y: size.height - intrinsicInsets.bottom - 80,
                width: galleryW, height: galleryH))

        updateScannerMask(size: size)
    }

    private func updateScannerMask(size: CGSize) {
        let scanSize = min(size.width, size.height) * 0.7
        let scanRect = CGRect(
            x: (size.width - scanSize) / 2, y: (size.height - scanSize) / 2, width: scanSize,
            height: scanSize)

        let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(roundedRect: scanRect, cornerRadius: 20)
        path.append(innerPath)
        path.usesEvenOddFillRule = true

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        scannerOverlay.layer.mask = mask
    }

    @objc private func closeTapped() {
        onCloseTapped?()
    }

    @objc private func toggleFlash() {
        onFlashTapped?()
    }

    @objc private func openGallery() {
        onGalleryTapped?()
    }
}

