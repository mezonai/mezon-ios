import AsyncDisplayKit
import UIKit

final class QRScannerContainerNode: ASDisplayNode {

    private let scannerOverlay = ASDisplayNode()
    private let cornerLayer = CAShapeLayer()
    
    private let closeButton = ASButtonNode()
    private let flashButton = ASButtonNode()
    
    private let mezonLogoIcon = ASImageNode()
    private let titleLabel = ASTextNode()
    
    private let scanInstructionNode = ASTextNode()
    private let galleryButton = ASButtonNode()
    private let myQRShareTextNode = ASTextNode()
    
    private let myQRCodeCardNode = ASButtonNode()
    private let fakeQRImageNode = ASImageNode()

    private let cameraPermissionGateContainer = ASDisplayNode()
    private let cameraPermissionIconNode = ASImageNode()
    private let cameraPermissionTitleNode = ASTextNode()
    private let cameraPermissionMessageNode = ASTextNode()
    private let cameraPermissionSettingsButton = ASButtonNode()
    private var showsCameraPermissionGate = false

    var onCloseTapped: (() -> Void)?
    var onFlashTapped: (() -> Void)?
    var onGalleryTapped: (() -> Void)?
    var onMyQRCodeTapped: (() -> Void)?
    var onCameraPermissionSettingsTapped: (() -> Void)?

    override init() {
        super.init()
        self.backgroundColor = .clear

        scannerOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        scannerOverlay.isLayerBacked = true
        scannerOverlay.isUserInteractionEnabled = false

        let arrowConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        closeButton.setImage(UIImage(systemName: "arrow.left", withConfiguration: arrowConfig)?.withTintColor(.white, renderingMode: .alwaysTemplate), for: .normal)
        closeButton.tintColor = .white

        flashButton.setImage(UIImage(systemName: "flashlight.off.fill")?.withTintColor(.white, renderingMode: .alwaysTemplate), for: .normal)
        flashButton.tintColor = .white

        mezonLogoIcon.image = UIImage(named: "Setting/LogoMezon")?.withTintColor(.white, renderingMode: .alwaysTemplate)
        mezonLogoIcon.contentMode = .scaleAspectFit
        
        titleLabel.attributedText = NSAttributedString(
            string: "Mezon",
            attributes: [
                .font: UIFont.systemFont(ofSize: 20, weight: .heavy),
                .foregroundColor: UIColor.white,
            ])
            
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        scanInstructionNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.scanInstruction),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ])

        let photoConfig = UIImage.SymbolConfiguration(pointSize: 16)
        galleryButton.setImage(UIImage(systemName: "photo.on.rectangle", withConfiguration: photoConfig)?.withTintColor(.white, renderingMode: .alwaysTemplate), for: .normal)
        galleryButton.setTitle(L(L10n.QRScanner.chooseFromGallery), with: .systemFont(ofSize: 14, weight: .regular), with: .white, for: .normal)
        galleryButton.imageAlignment = .beginning
        galleryButton.contentMode = .center
        galleryButton.tintColor = .white

        myQRShareTextNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.sharePersonalQR),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ])
            
        myQRCodeCardNode.backgroundColor = .white
        myQRCodeCardNode.cornerRadius = 24
        myQRCodeCardNode.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        fakeQRImageNode.contentMode = .scaleAspectFit
        
        myQRCodeCardNode.addSubnode(fakeQRImageNode)

        cameraPermissionGateContainer.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        cameraPermissionIconNode.image = UIImage(systemName: "camera.slash.fill")?.withTintColor(.white, renderingMode: .alwaysTemplate)
        cameraPermissionIconNode.contentMode = .scaleAspectFit

        let gateTitlePara = NSMutableParagraphStyle()
        gateTitlePara.alignment = .center
        cameraPermissionTitleNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.cameraPermissionTitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: gateTitlePara,
            ])

        let gateMsgPara = NSMutableParagraphStyle()
        gateMsgPara.alignment = .center
        cameraPermissionMessageNode.attributedText = NSAttributedString(
            string: L(L10n.QRScanner.cameraPermissionMessage),
            attributes: [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9),
                .paragraphStyle: gateMsgPara,
            ])

        cameraPermissionSettingsButton.setTitle(
            L(L10n.Common.settings),
            with: .systemFont(ofSize: 16, weight: .semibold),
            with: .black,
            for: .normal
        )
        cameraPermissionSettingsButton.backgroundColor = .white
        cameraPermissionSettingsButton.cornerRadius = 12
        cameraPermissionSettingsButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

        cameraPermissionGateContainer.addSubnode(cameraPermissionIconNode)
        cameraPermissionGateContainer.addSubnode(cameraPermissionTitleNode)
        cameraPermissionGateContainer.addSubnode(cameraPermissionMessageNode)
        cameraPermissionGateContainer.addSubnode(cameraPermissionSettingsButton)
        cameraPermissionGateContainer.isHidden = true
        
        self.addSubnode(scannerOverlay)
        self.addSubnode(cameraPermissionGateContainer)
        self.addSubnode(closeButton)
        self.addSubnode(flashButton)
        self.addSubnode(mezonLogoIcon)
        self.addSubnode(titleLabel)
        self.addSubnode(scanInstructionNode)
        self.addSubnode(galleryButton)
        self.addSubnode(myQRShareTextNode)
        self.addSubnode(myQRCodeCardNode)
        
        generateFakeQR()
    }

    override func didLoad() {
        super.didLoad()
        scannerOverlay.layer.addSublayer(cornerLayer)

        closeButton.addTarget(self, action: #selector(closeTapped), forControlEvents: .touchUpInside)
        flashButton.addTarget(self, action: #selector(toggleFlash), forControlEvents: .touchUpInside)
        galleryButton.addTarget(self, action: #selector(openGallery), forControlEvents: .touchUpInside)
        myQRCodeCardNode.addTarget(self, action: #selector(myQRCodeTapped), forControlEvents: .touchUpInside)
        cameraPermissionSettingsButton.addTarget(self, action: #selector(cameraPermissionSettingsTapped), forControlEvents: .touchUpInside)
    }

    func setCameraPermissionGateVisible(_ visible: Bool) {
        guard showsCameraPermissionGate != visible else { return }
        showsCameraPermissionGate = visible
        cameraPermissionGateContainer.isHidden = !visible
        flashButton.isHidden = visible
    }

    func updateFlashButton(isOn: Bool) {
        let color: UIColor = isOn ? .mezonPrimary : .white
        flashButton.setImage(UIImage(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill")?.withTintColor(color, renderingMode: .alwaysTemplate), for: .normal)
        flashButton.tintColor = color
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        return ASLayoutSpec()
    }

    func updateLayout(
        size: CGSize, safeInsets: UIEdgeInsets, intrinsicInsets: UIEdgeInsets,
        transition: ContainedViewLayoutTransition
    ) {
        _ = max(safeInsets.top, 20) + 16
        transition.updateFrame(node: scannerOverlay, frame: CGRect(origin: .zero, size: size))

        let closeSize = CGSize(width: 44, height: 44)
        let flashSize = CGSize(width: 44, height: 44)
        let logoSize = CGSize(width: 24, height: 24)
        let titleSize = titleLabel.calculateSizeThatFits(size)
        let headerSpacing: CGFloat = 8
        let totalHeaderWidth = logoSize.width + headerSpacing + titleSize.width
        let headerStartX = (size.width - totalHeaderWidth) / 2

        let headerY = max(safeInsets.top, 20) + 40
        let headerCenterY = headerY + logoSize.height / 2
        
        transition.updateFrame(node: closeButton, frame: CGRect(x: 8, y: headerCenterY - closeSize.height / 2, width: closeSize.width, height: closeSize.height))
        transition.updateFrame(node: flashButton, frame: CGRect(x: size.width - 52, y: headerCenterY - flashSize.height / 2, width: flashSize.width, height: flashSize.height))

        transition.updateFrame(node: mezonLogoIcon, frame: CGRect(x: headerStartX, y: headerY, width: logoSize.width, height: logoSize.height))
        transition.updateFrame(node: titleLabel, frame: CGRect(x: headerStartX + logoSize.width + headerSpacing, y: headerY + (logoSize.height - titleSize.height)/2, width: titleSize.width, height: titleSize.height))

        let scanSize = min(size.width, size.height) * 0.7
        let scanRect = CGRect(x: (size.width - scanSize) / 2, y: (size.height - scanSize) / 2 - 40, width: scanSize, height: scanSize)
        
        let instSize = scanInstructionNode.calculateSizeThatFits(CGSize(width: size.width - 32, height: .greatestFiniteMagnitude))
        transition.updateFrame(node: scanInstructionNode, frame: CGRect(x: 16, y: scanRect.maxY + 24, width: size.width - 32, height: instSize.height))
        
        transition.updateFrame(node: galleryButton, frame: CGRect(x: 16, y: scanRect.maxY + 32 + instSize.height, width: size.width - 32, height: 44))

        let shareTextSize = myQRShareTextNode.calculateSizeThatFits(size)
        let cardHeight: CGFloat = 80
        let cardY = size.height - cardHeight
        
        transition.updateFrame(node: myQRShareTextNode, frame: CGRect(x: (size.width - shareTextSize.width) / 2, y: cardY - shareTextSize.height - 16, width: shareTextSize.width, height: shareTextSize.height))
        
        let cardWidth = scanSize
        let cardX = (size.width - cardWidth) / 2
        transition.updateFrame(node: myQRCodeCardNode, frame: CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight + intrinsicInsets.bottom)) 
        
        let qrWidth = cardWidth - 32
        let qrHeight = qrWidth
        let dummyQRX: CGFloat = 16
        transition.updateFrame(node: fakeQRImageNode, frame: CGRect(x: dummyQRX, y: 16, width: qrWidth, height: qrHeight))

        if showsCameraPermissionGate {
            transition.updateFrame(node: cameraPermissionGateContainer, frame: CGRect(origin: .zero, size: size))
            let maxTextWidth = size.width - 48
            let iconSide: CGFloat = 56
            let iconY = size.height * 0.32
            transition.updateFrame(
                node: cameraPermissionIconNode,
                frame: CGRect(x: (size.width - iconSide) / 2, y: iconY, width: iconSide, height: iconSide))

            let titleSize = cameraPermissionTitleNode.calculateSizeThatFits(
                CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
            let titleY = iconY + iconSide + 20
            transition.updateFrame(
                node: cameraPermissionTitleNode,
                frame: CGRect(x: 24, y: titleY, width: size.width - 48, height: titleSize.height))

            let msgSize = cameraPermissionMessageNode.calculateSizeThatFits(
                CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
            let msgY = titleY + titleSize.height + 12
            transition.updateFrame(
                node: cameraPermissionMessageNode,
                frame: CGRect(x: 24, y: msgY, width: size.width - 48, height: msgSize.height))

            let btnW = min(maxTextWidth, 280)
            let btnH: CGFloat = 48
            let btnY = msgY + msgSize.height + 28
            transition.updateFrame(
                node: cameraPermissionSettingsButton,
                frame: CGRect(x: (size.width - btnW) / 2, y: btnY, width: btnW, height: btnH))
        }

        updateScannerMask(size: size, scanRect: scanRect)
    }

    private func updateScannerMask(size: CGSize, scanRect: CGRect) {
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let innerPath = UIBezierPath(rect: scanRect)
        path.append(innerPath)
        path.usesEvenOddFillRule = true

        let mask = CAShapeLayer()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        scannerOverlay.layer.mask = mask
        
        let cornerLength: CGFloat = 24
        let rect = scanRect.insetBy(dx: 0, dy: 0)
        let cornersPath = UIBezierPath()
        
        cornersPath.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerLength))
        cornersPath.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        cornersPath.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.minY))
        cornersPath.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.minY))
        cornersPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        cornersPath.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cornerLength))
        cornersPath.move(to: CGPoint(x: rect.minX, y: rect.maxY - cornerLength))
        cornersPath.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        cornersPath.addLine(to: CGPoint(x: rect.minX + cornerLength, y: rect.maxY))
        cornersPath.move(to: CGPoint(x: rect.maxX - cornerLength, y: rect.maxY))
        cornersPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        cornersPath.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerLength))
        
        cornerLayer.path = cornersPath.cgPath
        cornerLayer.strokeColor = UIColor.white.cgColor
        cornerLayer.lineWidth = 4
        cornerLayer.lineCap = .square
        cornerLayer.lineJoin = .miter
        cornerLayer.fillColor = UIColor.clear.cgColor
    }
    
    private func generateFakeQR() {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return }
        filter.setValue("https://mezon.ai".data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return }
        let scaleX = 400 / outputImage.extent.size.width
        let scaleY = 400 / outputImage.extent.size.height
        let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        let context = CIContext()
        if let cgImage = context.createCGImage(transformedImage, from: transformedImage.extent) {
            fakeQRImageNode.image = UIImage(cgImage: cgImage)
        }
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

    @objc private func myQRCodeTapped() {
        onMyQRCodeTapped?()
    }

    @objc private func cameraPermissionSettingsTapped() {
        onCameraPermissionSettingsTapped?()
    }
}

