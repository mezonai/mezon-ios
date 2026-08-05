import UIKit
import AVFoundation
import PhotosUI
import AsyncDisplayKit

final class QRScannerViewController: ViewController {
    
    private let context: AccountContext
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var loginConfirmNode: QRLoginConfirmNode?
    private var clanInviteNode: QRClanInviteNode?
    private var userProfileNode: QRUserProfileNode?
    private var externalLinkSheetController: QRExternalLinkSheetController?
    private var scannedTextPayloadSheetController: QRScannedTextPayloadSheetController?
    private let captureSessionQueue = DispatchQueue(label: "mezon.qrScanner.captureSession")
    private var shouldResumeCaptureWhenApplicationBecomesActive = false
    private var exclusiveScanHandlingActive = false
    
    private var isFlashOn = false
    
    private var scannerNode: QRScannerContainerNode {
        return self.displayNode as! QRScannerContainerNode
    }
    
    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
        self.displayNavigationBar = false
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    override func loadDisplayNode() {
        self.displayNode = QRScannerContainerNode()
        
        scannerNode.onCloseTapped = { [weak self] in
            self?.closeTapped()
        }
        
        scannerNode.onFlashTapped = { [weak self] in
            self?.toggleFlash()
        }
        
        scannerNode.onGalleryTapped = { [weak self] in
            self?.openGallery()
        }
        
        scannerNode.onMyQRCodeTapped = { [weak self] in
            self?.navigateToMyQRCode()
        }

        scannerNode.onCameraPermissionSettingsTapped = { [weak self] in
            self?.openAppSettingsForCamera()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        checkCameraPermission()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if shouldOfferExclusiveScanHandlingResetAfterAppear() {
            endExclusiveScanHandling()
        }
        resumeCameraIfAuthorizedAfterSettings()
        startCaptureSessionIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopCaptureSessionIfNeeded()
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        scannerNode.updateLayout(size: layout.size, safeInsets: layout.safeInsets, intrinsicInsets: layout.intrinsicInsets, transition: transition)
        previewLayer?.frame = CGRect(origin: .zero, size: layout.size)
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            applyCameraPermissionGateVisible(false)
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.applyCameraPermissionGateVisible(false)
                        self.setupCamera()
                    } else {
                        self.applyCameraPermissionGateVisible(true)
                    }
                }
            }
        case .denied, .restricted:
            applyCameraPermissionGateVisible(true)
        @unknown default:
            break
        }
    }

    private func resumeCameraIfAuthorizedAfterSettings() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard captureSession == nil else { return }
        setupCamera()
    }

    @objc private func applicationDidBecomeActive() {
        guard shouldResumeCaptureWhenApplicationBecomesActive else { return }
        shouldResumeCaptureWhenApplicationBecomesActive = false
        endExclusiveScanHandling()
        startCaptureSessionIfNeeded()
    }

    private func openAppSettingsForCamera() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func applyCameraPermissionGateVisible(_ visible: Bool) {
        scannerNode.setCameraPermissionGateVisible(visible)
        refreshScannerLayoutForPermissionGate()
    }

    private func refreshScannerLayoutForPermissionGate() {
        guard let layout = currentlyAppliedLayout else { return }
        scannerNode.updateLayout(
            size: layout.size,
            safeInsets: layout.safeInsets,
            intrinsicInsets: layout.intrinsicInsets,
            transition: .immediate
        )
    }
    
    private func setupCamera() {
        guard captureSession == nil else { return }
        applyCameraPermissionGateVisible(false)
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            output.metadataObjectTypes = [.qr]
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = self.scannerNode.bounds
        self.scannerNode.layer.insertSublayer(preview, at: 0)
        
        self.captureSession = session
        self.previewLayer = preview

        startCaptureSessionIfNeeded()
    }

    private func startCaptureSessionIfNeeded() {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        guard let session = captureSession else { return }
        captureSessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func beginExclusiveScanHandling() -> Bool {
        if exclusiveScanHandlingActive { return false }
        exclusiveScanHandlingActive = true
        return true
    }

    private func endExclusiveScanHandling() {
        exclusiveScanHandlingActive = false
    }

    private func shouldOfferExclusiveScanHandlingResetAfterAppear() -> Bool {
        guard navigationController?.topViewController === self else { return false }
        guard loginConfirmNode == nil, clanInviteNode == nil, userProfileNode == nil else { return false }
        guard externalLinkSheetController == nil, scannedTextPayloadSheetController == nil else { return false }
        return true
    }

    private func stopCaptureSessionIfNeeded() {
        guard let session = captureSession else { return }
        captureSessionQueue.async {
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
    
    @objc private func closeTapped() {
        if let nav = navigationController {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    @objc private func toggleFlash() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        isFlashOn.toggle()
        device.torchMode = isFlashOn ? .on : .off
        device.unlockForConfiguration()
        scannerNode.updateFlashButton(isOn: isFlashOn)
    }
    
    @objc private func openGallery() {
        if #available(iOS 14.0, *) {
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.delegate = self
            present(picker, animated: true)
        }
    }
    
    private func navigateToMyQRCode() {
        let vc = MyQRCodeViewController(context: self.context)
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    private func handleScannedData(_ data: String) {
        guard externalLinkSheetController == nil, scannedTextPayloadSheetController == nil else { return }

        if data.allSatisfy({ $0.isNumber }) && data.count >= 15 {
            showLoginConfirm(userId: data)
            return
        }
        
        if data.hasPrefix("mezon://invite/") || data.contains("mezon.ai/invite/") {
            let code: String
            if data.hasPrefix("mezon://invite/") {
                code = String(data.dropFirst("mezon://invite/".count))
            } else if let range = data.range(of: "mezon.ai/invite/") {
                var extracted = String(data[range.upperBound...])
                if extracted.hasSuffix("/") {
                    extracted = String(extracted.dropLast())
                }
                code = extracted
            } else {
                code = ""
            }
            
            if !code.isEmpty {
                self.showClanInvite(code: code)
            } else {
                showAlert(message: L(L10n.QRScanner.invalidQR)) { [weak self] in
                    self?.startCaptureSessionIfNeeded()
                }
            }
            return
        }
        
        if data.contains("mezon.ai/chat/") {
            guard let dataParam = extractProfileDataParam(from: data) else {
                showAlert(message: L(L10n.QRScanner.invalidQR)) { [weak self] in
                    self?.startCaptureSessionIfNeeded()
                }
                return
            }
            guard let profile = decodeProfileQRDataParam(dataParam) else {
                showAlert(message: L(L10n.QRScanner.invalidQR)) { [weak self] in
                    self?.startCaptureSessionIfNeeded()
                }
                return
            }
            guard beginExclusiveScanHandling() else { return }
            stopCaptureSessionIfNeeded()
            presentUserProfile(profileData: profile)
            return
        }

        if let luckyMoneyId = LuckyMoneyQRParse.luckyMoneyId(from: data) {
            guard beginExclusiveScanHandling() else { return }
            stopCaptureSessionIfNeeded()
            let vc = ClaimLuckyMoneyViewController(context: context, luckyMoneyId: luckyMoneyId)
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        
        if let payload = MmnTransferParse.fromQRString(data) {
            guard beginExclusiveScanHandling() else { return }
            stopCaptureSessionIfNeeded()
            let vc = WalletTransferViewController(context: context, payload: payload)
            navigationController?.pushViewController(vc, animated: true)
            return
        }

        if let url = Self.externalLinkURL(from: data) {
            guard beginExclusiveScanHandling() else { return }
            stopCaptureSessionIfNeeded()
            presentExternalLinkSheet(url: url)
            return
        }

        presentScannedTextPayloadSheet(with: data)
    }

    private static func externalLinkURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           url.host != nil {
            return url
        }

        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.contains("."),
              let url = URL(string: "https://\(trimmed)"),
              url.host != nil else {
            return nil
        }
        return url
    }

    private func presentExternalLinkSheet(url: URL) {
        let sheet = QRExternalLinkSheetController(url: url)
        sheet.onDismiss = { [weak self, weak sheet] didOpen in
            guard let self else { return }
            if self.externalLinkSheetController === sheet {
                self.externalLinkSheetController = nil
            }
            if didOpen {
                self.shouldResumeCaptureWhenApplicationBecomesActive = true
                UIApplication.shared.open(url, options: [:]) { [weak self] success in
                    if !success {
                        self?.shouldResumeCaptureWhenApplicationBecomesActive = false
                        self?.endExclusiveScanHandling()
                        self?.startCaptureSessionIfNeeded()
                    }
                }
            } else {
                self.endExclusiveScanHandling()
                self.startCaptureSessionIfNeeded()
            }
        }
        externalLinkSheetController = sheet
        present(sheet, animated: false)
    }

    private func presentScannedTextPayloadSheet(with payload: String) {
        guard beginExclusiveScanHandling() else { return }
        stopCaptureSessionIfNeeded()
        let sheet = QRScannedTextPayloadSheetController(payload: payload)
        sheet.onDismiss = { [weak self, weak sheet] in
            guard let self else { return }
            if self.scannedTextPayloadSheetController === sheet {
                self.scannedTextPayloadSheetController = nil
            }
            self.endExclusiveScanHandling()
            self.startCaptureSessionIfNeeded()
        }
        scannedTextPayloadSheetController = sheet
        present(sheet, animated: false)
    }

    private func extractProfileDataParam(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = c.queryItems?.first(where: { $0.name == "data" })?.value,
           !v.isEmpty {
            return v
        }
        guard let range = trimmed.range(of: "data=") else { return nil }
        var rest = String(trimmed[range.upperBound...])
        if let a = rest.firstIndex(of: "&") {
            rest = String(rest[..<a])
        }
        if let p = rest.removingPercentEncoding, !p.isEmpty { return p }
        return rest.isEmpty ? nil : rest
    }

    private func decodeProfileQRDataParam(_ dataParam: String) -> QRUserProfileData? {
        let s = dataParam.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
        guard !s.isEmpty else { return nil }
        if let raw = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           let p = try? JSONDecoder().decode(QRUserProfileData.self, from: raw) {
            return p
        }
        if let raw = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           let str = String(data: raw, encoding: .utf8),
           let json = str.removingPercentEncoding,
           let j = json.data(using: .utf8),
           let p = try? JSONDecoder().decode(QRUserProfileData.self, from: j) {
            return p
        }
        return nil
    }
    
    private func showLoginConfirm(userId: String) {
        guard beginExclusiveScanHandling() else { return }
        stopCaptureSessionIfNeeded()
        
        let theme = context.sharedContext.currentPresentationTheme.attributes
        let confirmNode = QRLoginConfirmNode(theme: theme)
        confirmNode.frame = self.displayNode.bounds
        
        confirmNode.onLogin = { [weak self, weak confirmNode] in
            guard let self = self else { return }
            Task {
                do {
                    let token = self.context.session?.token ?? ""
                    _ = try await self.context.engine.auth.confirmLogin(loginId: userId, token: token)
                    await MainActor.run {
                        confirmNode?.setSuccess(true)
                    }
                } catch {
                    await MainActor.run {
                        self.showAlert(message: error.localizedDescription) {
                            self.hideLoginConfirm()
                        }
                    }
                }
            }
        }
        
        confirmNode.onCancel = { [weak self] in
            self?.hideLoginConfirm()
        }
        
        confirmNode.onStartTalking = { [weak self] in
            self?.closeTapped()
        }
        
        self.loginConfirmNode = confirmNode
        self.displayNode.addSubnode(confirmNode)
        
        confirmNode.alpha = 0
        UIView.animate(withDuration: 0.3) {
            confirmNode.alpha = 1
        }
    }
    
    private func hideLoginConfirm() {
        guard let confirmNode = loginConfirmNode else { return }
        UIView.animate(withDuration: 0.3, animations: {
            confirmNode.alpha = 0
        }) { _ in
            confirmNode.removeFromSupernode()
            self.loginConfirmNode = nil
            self.endExclusiveScanHandling()
            self.startCaptureSessionIfNeeded()
        }
    }
    
    private func showClanInvite(code: String) {
        guard beginExclusiveScanHandling() else { return }
        stopCaptureSessionIfNeeded()
        
        let theme = context.sharedContext.currentPresentationTheme.attributes
        let token = context.session?.token ?? ""
        
        Task {
            do {
                let inviteInfo = try await context.engine.clanData.getInviteInfo(code: code, token: token)
                
                await MainActor.run {
                    let inviteNode = QRClanInviteNode(theme: theme, inviteInfo: inviteInfo)
                    inviteNode.frame = self.displayNode.bounds
                    
                    inviteNode.onJoin = { [weak self, weak inviteNode] in
                        guard let self = self else { return }
                        inviteNode?.setJoining(true)
                        Task {
                            let clanId = await ClanInviteJoiner.join(context: self.context, code: code, clanId: inviteInfo.clan_id.flatMap(Int64.init))
                            await MainActor.run {
                                guard let clanId else {
                                    self.hideClanInvite()
                                    return
                                }
                                self.hideClanInvite()
                                self.closeTapped()
                                NotificationCenter.default.post(
                                    name: .mezonQRSelectClan,
                                    object: nil,
                                    userInfo: ["clanId": "\(clanId)"]
                                )
                            }
                        }
                    }
                    
                    inviteNode.onCancel = { [weak self] in
                        self?.hideClanInvite()
                    }
                    
                    self.clanInviteNode = inviteNode
                    self.displayNode.addSubnode(inviteNode)
                    
                    inviteNode.alpha = 0
                    UIView.animate(withDuration: 0.3) {
                        inviteNode.alpha = 1
                    }
                }
            } catch {
                await MainActor.run {
                    self.endExclusiveScanHandling()
                    self.showAlert(message: error.localizedDescription) {
                        self.startCaptureSessionIfNeeded()
                    }
                }
            }
        }
    }
    
    private func hideClanInvite() {
        guard let inviteNode = clanInviteNode else { return }
        UIView.animate(withDuration: 0.3, animations: {
            inviteNode.alpha = 0
        }) { _ in
            inviteNode.removeFromSupernode()
            self.clanInviteNode = nil
            self.endExclusiveScanHandling()
            self.startCaptureSessionIfNeeded()
        }
    }
    
    private func presentUserProfile(profileData: QRUserProfileData) {
        let theme = context.sharedContext.currentPresentationTheme.attributes
        let profileNode = QRUserProfileNode(profile: profileData, theme: theme)
        profileNode.frame = self.displayNode.bounds
        
        profileNode.onMessage = { [weak self] in
            guard let self = self else { return }
            Task {
                do {
                    let token = await self.context.getToken() ?? ""
                    if let userId = Int64(profileData.id) {
                        let channel = try await self.context.account.network.createDirectMessage(userId: userId, token: token)
                        await MainActor.run {
                            self.hideUserProfile()
                            self.closeTapped()
                            NotificationCenter.default.post(
                                name: .mezonQRNavigateToDM,
                                object: nil,
                                userInfo: ["channelId": "\(channel.channelID)", "title": profileData.name]
                            )
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.showAlert(message: error.localizedDescription)
                    }
                }
            }
        }
        
        profileNode.onClose = { [weak self] in
            self?.hideUserProfile()
        }
        
        self.userProfileNode = profileNode
        self.displayNode.addSubnode(profileNode)
        
        profileNode.alpha = 0
        UIView.animate(withDuration: 0.3) {
            profileNode.alpha = 1
        }
    }
    
    private func hideUserProfile() {
        guard let profileNode = userProfileNode else { return }
        UIView.animate(withDuration: 0.3, animations: {
            profileNode.alpha = 0
        }) { _ in
            profileNode.removeFromSupernode()
            self.userProfileNode = nil
            self.endExclusiveScanHandling()
            self.startCaptureSessionIfNeeded()
        }
    }
    
    private func showJoinGroup(code: String) {
        let alert = UIAlertController(title: L(L10n.QRScanner.joinGroup), 
                                      message: "Joining group with code: \(code)", 
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak self] _ in
            self?.closeTapped()
        }))
        present(alert, animated: true)
    }
    
    private func showAlert(title: String? = nil, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            completion?()
        }))
        present(alert, animated: true)
    }
}

extension QRScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !exclusiveScanHandlingActive else { return }
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            handleScannedData(stringValue)
        }
    }
}

@available(iOS 14.0, *)
extension QRScannerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        
        provider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
            guard let image = image as? UIImage else { return }
            self?.processQRFromImage(image)
        }
    }
}

extension QRScannerViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        processQRFromImage(image)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    private func processQRFromImage(_ image: UIImage) {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let ciImage = CIImage(image: image)
        let features = detector?.features(in: ciImage!) as? [CIQRCodeFeature]

        DispatchQueue.main.async { [weak self] in
            if let firstFeature = features?.first, let data = firstFeature.messageString {
                self?.handleScannedData(data)
            } else {
                self?.showAlert(message: L(L10n.QRScanner.invalidQR))
            }
        }
    }
}

private final class QRExternalLinkSheetController: UIViewController {
    private let url: URL
    var onDismiss: ((Bool) -> Void)?

    private let dimView = UIView()
    private let contentView = UIView()
    private let handleView = UIView()
    private let iconContainer = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let openButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)

    private var didAnimateIn = false
    private var isDismissing = false

    init(url: URL) {
        self.url = url
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        view.addSubview(dimView)

        contentView.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1.0)
        contentView.layer.cornerRadius = 14
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.clipsToBounds = true
        view.addSubview(contentView)

        handleView.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        handleView.layer.cornerRadius = 2.5
        contentView.addSubview(handleView)

        iconContainer.backgroundColor = UIColor(red: 0.26, green: 0.29, blue: 0.32, alpha: 1.0)
        iconContainer.layer.cornerRadius = 4
        iconContainer.clipsToBounds = true
        contentView.addSubview(iconContainer)

        iconImageView.image = UIImage(systemName: "link")
        iconImageView.tintColor = UIColor.white.withAlphaComponent(0.14)
        iconImageView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconImageView)

        titleLabel.text = url.absoluteString
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        contentView.addSubview(titleLabel)

        hostLabel.text = hostDisplayText(for: url)
        hostLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hostLabel.textColor = UIColor(red: 0.37, green: 0.62, blue: 1.0, alpha: 1.0)
        contentView.addSubview(hostLabel)

        openButton.backgroundColor = UIColor(red: 0.02, green: 0.43, blue: 1.0, alpha: 1.0)
        openButton.layer.cornerRadius = 22
        openButton.tintColor = .white
        openButton.setTitle(Self.openLinkTitle, for: .normal)
        openButton.setTitleColor(.white, for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        openButton.setImage(UIImage(systemName: "globe"), for: .normal)
        openButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        openButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6)
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)
        contentView.addSubview(openButton)

        moreButton.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        moreButton.layer.cornerRadius = 22
        moreButton.tintColor = .white
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        contentView.addSubview(moreButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        dimView.frame = view.bounds

        let safeBottom = view.safeAreaInsets.bottom
        let width = view.bounds.width
        let horizontal: CGFloat = 16
        let iconSize: CGFloat = 68
        let textX = horizontal + iconSize + 18
        let textWidth = max(0, width - textX - horizontal)
        let titleHeight = min(44, titleLabel.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height)
        let headerY: CGFloat = 42
        let hostY = headerY + titleHeight + 3
        let headerBottom = max(headerY + iconSize, hostY + 18)
        let buttonY = headerBottom + 26
        let sheetHeight = buttonY + 44 + 18 + safeBottom

        contentView.frame = CGRect(x: 0, y: view.bounds.height - sheetHeight, width: width, height: sheetHeight)
        handleView.frame = CGRect(x: (width - 56) / 2, y: 10, width: 56, height: 5)
        iconContainer.frame = CGRect(x: horizontal, y: headerY, width: iconSize, height: iconSize)
        iconImageView.frame = iconContainer.bounds.insetBy(dx: 17, dy: 17)
        titleLabel.frame = CGRect(x: textX, y: headerY + 2, width: textWidth, height: titleHeight)
        hostLabel.frame = CGRect(x: textX, y: hostY, width: textWidth, height: 18)

        let moreSize: CGFloat = 44
        moreButton.frame = CGRect(x: width - horizontal - moreSize, y: buttonY, width: moreSize, height: moreSize)
        openButton.frame = CGRect(
            x: horizontal,
            y: buttonY,
            width: max(0, width - horizontal * 3 - moreSize),
            height: 44
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        contentView.transform = CGAffineTransform(translationX: 0, y: contentView.bounds.height)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    private static var openLinkTitle: String {
        let language = Locale.current.languageCode ?? ""
        return language == "vi" ? "Mở link" : "Open link"
    }

    private static var copyLinkTitle: String {
        let language = Locale.current.languageCode ?? ""
        return language == "vi" ? "Sao chép link" : "Copy link"
    }

    private static var cancelTitle: String {
        let language = Locale.current.languageCode ?? ""
        return language == "vi" ? "Huỷ" : "Cancel"
    }

    private func hostDisplayText(for url: URL) -> String {
        guard let host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        return host
    }

    @objc private func dimTapped() {
        dismissSheet(didOpen: false)
    }

    @objc private func openTapped() {
        dismissSheet(didOpen: true)
    }

    @objc private func moreTapped() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: Self.copyLinkTitle, style: .default) { [weak self] _ in
            guard let self else { return }
            UIPasteboard.general.string = self.url.absoluteString
        })
        sheet.addAction(UIAlertAction(title: Self.cancelTitle, style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = moreButton
            popover.sourceRect = moreButton.bounds
        }
        present(sheet, animated: true)
    }

    private func dismissSheet(didOpen: Bool) {
        guard !isDismissing else { return }
        isDismissing = true
        let height = contentView.bounds.height
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            self.contentView.transform = CGAffineTransform(translationX: 0, y: height)
        } completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss?(didOpen)
            }
        }
    }
}

private final class QRScannedTextPayloadSheetController: UIViewController {
    private let payload: String
    var onDismiss: (() -> Void)?

    private let dimView = UIView()
    private let contentView = UIView()
    private let handleView = UIView()
    private let titleLabel = UILabel()
    private let textView = UITextView()
    private let copyButton = UIButton(type: .system)

    private var didAnimateIn = false
    private var isDismissing = false

    init(payload: String) {
        self.payload = payload
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.32)
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        view.addSubview(dimView)

        contentView.backgroundColor = UIColor(red: 0.10, green: 0.11, blue: 0.12, alpha: 1.0)
        contentView.layer.cornerRadius = 14
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.clipsToBounds = true
        view.addSubview(contentView)

        handleView.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        handleView.layer.cornerRadius = 2.5
        contentView.addSubview(handleView)

        titleLabel.text = L(L10n.QRScanner.scannedPayloadTitle)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1
        contentView.addSubview(titleLabel)

        textView.text = payload
        textView.font = .systemFont(ofSize: 15, weight: .regular)
        textView.textColor = .white
        textView.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        textView.layer.cornerRadius = 10
        textView.clipsToBounds = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.indicatorStyle = .white
        contentView.addSubview(textView)

        copyButton.backgroundColor = UIColor(red: 0.02, green: 0.43, blue: 1.0, alpha: 1.0)
        copyButton.layer.cornerRadius = 22
        copyButton.tintColor = .white
        copyButton.setTitle(L(L10n.QRScanner.copyContent), for: .normal)
        copyButton.setTitleColor(.white, for: .normal)
        copyButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        copyButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
        copyButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6)
        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        contentView.addSubview(copyButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        dimView.frame = view.bounds
        let safeBottom = view.safeAreaInsets.bottom
        let width = view.bounds.width
        let horizontal: CGFloat = 16
        let insetH = textView.textContainerInset.left + textView.textContainerInset.right
        let innerTextWidth = max(1, width - horizontal * 2 - insetH)

        let bodyFont = textView.font ?? UIFont.systemFont(ofSize: 15)
        let bounded = (payload as NSString).boundingRect(
            with: CGSize(width: innerTextWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: bodyFont],
            context: nil)
        let intrinsicText = ceil(bounded.height) + textView.textContainerInset.top + textView.textContainerInset.bottom
        let textBlockH = min(320, max(120, intrinsicText))

        let titleY: CGFloat = 38
        titleLabel.frame = CGRect(x: horizontal, y: titleY, width: width - horizontal * 2, height: 24)

        let textY = titleY + 24 + 12
        textView.frame = CGRect(x: horizontal, y: textY, width: width - horizontal * 2, height: textBlockH)

        let buttonY = textY + textBlockH + 20
        copyButton.frame = CGRect(x: horizontal, y: buttonY, width: width - horizontal * 2, height: 44)

        let sheetHeight = buttonY + 44 + 18 + safeBottom
        contentView.frame = CGRect(x: 0, y: view.bounds.height - sheetHeight, width: width, height: sheetHeight)
        handleView.frame = CGRect(x: (width - 56) / 2, y: 10, width: 56, height: 5)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didAnimateIn else { return }
        didAnimateIn = true
        contentView.transform = CGAffineTransform(translationX: 0, y: contentView.bounds.height)
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    @objc private func dimTapped() {
        dismissSheet()
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = payload
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func dismissSheet() {
        guard !isDismissing else { return }
        isDismissing = true
        let height = contentView.bounds.height
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.dimView.alpha = 0
            self.contentView.transform = CGAffineTransform(translationX: 0, y: height)
        } completion: { _ in
            self.dismiss(animated: false) {
                self.onDismiss?()
            }
        }
    }
}
