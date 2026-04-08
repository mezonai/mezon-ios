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
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        checkCameraPermission()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if captureSession?.isRunning == false {
            captureSession?.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession?.isRunning == true {
            captureSession?.stopRunning()
        }
    }
    
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        scannerNode.updateLayout(size: layout.size, safeInsets: layout.safeInsets, intrinsicInsets: layout.intrinsicInsets, transition: transition)
        previewLayer?.frame = CGRect(origin: .zero, size: layout.size)
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async { self?.setupCamera() }
                }
            }
        case .denied, .restricted:
            showPermissionAlert()
        @unknown default:
            break
        }
    }
    
    private func showPermissionAlert() {
        let alert = UIAlertController(title: L(L10n.QRScanner.cameraPermissionTitle), message: L(L10n.QRScanner.cameraPermissionMessage), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel, handler: { [weak self] _ in
            self?.closeTapped()
        }))
        alert.addAction(UIAlertAction(title: L(L10n.Common.settings), style: .default, handler: { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }))
        present(alert, animated: true)
    }
    
    private func setupCamera() {
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
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
        if #available(iOS 14, *) {
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
        captureSession?.stopRunning()
        
        // 1. Check if it is a numeric ID (Login)
        if data.allSatisfy({ $0.isNumber }) && data.count >= 15 {
            showLoginConfirm(userId: data)
            return
        }
        
        // 2. Check if it is a mezon invite
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
            }
            return
        }
        
        // 3. Check if it is a mezon profile
        if data.contains("mezon.ai/chat/") {
            guard let url = URL(string: data),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value else {
                return
            }
            
            self.showUserProfile(dataParam: dataParam)
            return
        }
        
        // 4. Check if it is a JSON (Transfer)
        if let jsonData = data.data(using: .utf8), 
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let receiverId = json["receiver_id"] as? String {
            showTransferConfirm(receiverId: receiverId)
            return
        }
        
        showAlert(title: L(L10n.QRScanner.invalidQR), message: data) { [weak self] in
            self?.captureSession?.startRunning()
        }
    }
    
    private func showLoginConfirm(userId: String) {
        captureSession?.stopRunning()
        
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
            self.captureSession?.startRunning()
        }
    }
    
    private func showClanInvite(code: String) {
        captureSession?.stopRunning()
        
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
                        Task {
                            do {
                                let response = try await self.context.engine.clanData.joinClanWithInvite(code: code, token: token)
                                await MainActor.run {
                                    self.hideClanInvite()
                                    self.closeTapped()
                                    NotificationCenter.default.post(
                                        name: .mezonQRSelectClan,
                                        object: nil,
                                        userInfo: ["clanId": "\(response.clanID)"]
                                    )
                                }
                            } catch {
                                await MainActor.run {
                                    self.showAlert(message: error.localizedDescription)
                                }
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
                    self.showAlert(message: error.localizedDescription) {
                        self.captureSession?.startRunning()
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
            self.captureSession?.startRunning()
        }
    }
    
    private func showUserProfile(dataParam: String) {
        // dataParam is Base64 -> URL Encode -> JSON
        guard let data = Data(base64Encoded: dataParam),
              let urlEncodedString = String(data: data, encoding: .utf8),
              let decodedString = urlEncodedString.removingPercentEncoding,
              let jsonData = decodedString.data(using: .utf8) else {
            return
        }
        
        do {
            let profileData = try JSONDecoder().decode(QRUserProfileData.self, from: jsonData)
            
            captureSession?.stopRunning()
            
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
            
        } catch {
            print("Failed to decode profile data: \(error)")
        }
    }
    
    private func hideUserProfile() {
        guard let profileNode = userProfileNode else { return }
        UIView.animate(withDuration: 0.3, animations: {
            profileNode.alpha = 0
        }) { _ in
            profileNode.removeFromSupernode()
            self.userProfileNode = nil
            self.captureSession?.startRunning()
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
    
    private func showTransferConfirm(receiverId: String) {
        let alert = UIAlertController(title: L(L10n.Profile.transferFunds), 
                                      message: String(format: L(L10n.QRScanner.transferTo), receiverId), 
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel, handler: { [weak self] _ in
            self?.captureSession?.startRunning()
        }))
        alert.addAction(UIAlertAction(title: L(L10n.Common.confirm), style: .default, handler: { _ in
            // Handle transfer logic
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
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            handleScannedData(stringValue)
        }
    }
}

@available(iOS 14, *)
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
