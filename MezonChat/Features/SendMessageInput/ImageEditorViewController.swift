import UIKit

private enum ImageEditorTool: Int, Hashable {
    case draw
    case text
    case crop
    case rotate

    var canvasMode: ImageEditorCanvasView.Mode? {
        switch self {
        case .draw: .draw
        case .text: .text
        case .crop: .crop
        case .rotate: nil
        }
    }
}

final class ImageEditorViewController: UIViewController {
    var onSend: ((MediaPickerResult) -> Void)?
    var onSendStarted: (() -> Void)?
    var onCancel: (() -> Void)?

    private let sourceResult: MediaPickerResult
    private let canvas: ImageEditorCanvasView
    private var handedOffFile = false
    private var hasChanges = false
    private var selectedColor: UIColor = .systemRed
    private var editingTextIndex: Int?
    private var toolTopConstraint: NSLayoutConstraint?
    private var paletteBottomConstraint: NSLayoutConstraint?

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 17, weight: .bold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        button.layer.cornerRadius = 22
        button.accessibilityLabel = L(L10n.Common.close)
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    private lazy var undoButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(L(L10n.Common.reset), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.contentHorizontalAlignment = .left
        button.addTarget(self, action: #selector(undoTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()

    private lazy var sendButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(L(L10n.ImageEditor.send), for: .normal)
        button.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        button.backgroundColor = .white
        button.setTitleColor(.black, for: .normal)
        button.tintColor = .black
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 24, bottom: 8, right: 26)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        
        button.layer.cornerRadius = 20
        button.clipsToBounds = true
        
        button.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        return button
    }()

    private let toolRail = UIStackView()
    private var toolButtons: [ImageEditorTool: EditorToolButton] = [:]

    private let palette = UIStackView()
    private var colorButtons: [UIButton] = []
    private lazy var eraserButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = .white
        button.setImage(UIImage(systemName: "eraser.fill"), for: .normal)
        button.layer.cornerRadius = 20
        button.addTarget(self, action: #selector(eraserTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }()
    private let eraserDivider = UIView()
    private let brushSlider = VerticalBrushSizeView()

    private lazy var trashTarget: UIView = {
        let target = UIView()
        target.translatesAutoresizingMaskIntoConstraints = false
        target.backgroundColor = .white
        target.layer.cornerRadius = 26
        target.layer.shadowColor = UIColor.black.cgColor
        target.layer.shadowOpacity = 0.3
        target.layer.shadowRadius = 5
        target.isHidden = true
        let image = UIImageView(image: UIImage(systemName: "trash.fill"))
        image.translatesAutoresizingMaskIntoConstraints = false
        image.tintColor = .black
        target.addSubview(image)
        NSLayoutConstraint.activate([
            target.widthAnchor.constraint(equalToConstant: 52),
            target.heightAnchor.constraint(equalToConstant: 52),
            image.centerXAnchor.constraint(equalTo: target.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: target.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 22),
            image.heightAnchor.constraint(equalToConstant: 22)
        ])
        return target
    }()

    private lazy var textInputOverlay: UIView = makeTextInputOverlay()
    private let textView = UITextView()

    init(result: MediaPickerResult) {
        sourceResult = result
        canvas = ImageEditorCanvasView(image: result.image)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        guard !handedOffFile, let url = sourceResult.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCanvas()
        setupControls()
        updateModeUI()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.toolButtons.values.forEach { $0.setLabelVisible(false, animated: true) }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let landscape = view.bounds.width > view.bounds.height
        toolTopConstraint?.constant = landscape ? 10 : 72
        paletteBottomConstraint?.constant = landscape ? -18 : -80
        canvas.cropInsets = UIEdgeInsets(
            top: view.safeAreaInsets.top + (landscape ? 20 : 72),
            left: 18,
            bottom: view.safeAreaInsets.bottom + (landscape ? 20 : 76),
            right: landscape ? 96 : 18
        )
    }

    private func setupCanvas() {
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.onChanged = { [weak self] in
            guard let self, !self.hasChanges else { return }
            self.hasChanges = true
            self.undoButton.isHidden = false
        }
        canvas.onTextEdit = { [weak self] index, text, color in
            self?.showTextInput(index: index, text: text, color: color)
        }
        canvas.onTextSelected = { [weak self] color in
            self?.selectedColor = color
            self?.canvas.brushColor = color
            self?.refreshPalette()
        }
        canvas.onTextDrag = { [weak self] active, point in
            self?.updateTrash(active: active, point: point) ?? false
        }
        canvas.isMultipleTouchEnabled = true
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgeDismiss(_:)))
        edge.edges = .left
        view.addGestureRecognizer(edge)
    }

    private func setupControls() {
        view.addSubview(closeButton)

        undoButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(undoButton)

        toolRail.translatesAutoresizingMaskIntoConstraints = false
        toolRail.axis = .vertical
        toolRail.alignment = .trailing
        toolRail.spacing = 10
        view.addSubview(toolRail)

        addTool(.draw, title: L(L10n.ImageEditor.draw), systemImage: "scribble")
        addTool(.text, title: L(L10n.ImageEditor.text), textIcon: "Aa")
        addTool(.crop, title: L(L10n.ImageEditor.crop), systemImage: "crop")
        addTool(.rotate, title: L(L10n.ImageEditor.rotate), systemImage: "rotate.left")

        configurePalette()
        view.addSubview(palette)

        brushSlider.translatesAutoresizingMaskIntoConstraints = false
        brushSlider.isHidden = true
        brushSlider.onValueChanged = { [weak self] value in self?.canvas.brushWidth = value }
        view.addSubview(brushSlider)

        view.addSubview(sendButton)
        view.addSubview(trashTarget)
        view.addSubview(textInputOverlay)

        let toolTop = toolRail.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72)
        let paletteBottom = palette.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80)
        toolTopConstraint = toolTop
        paletteBottomConstraint = paletteBottom

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            undoButton.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 12),
            undoButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            undoButton.heightAnchor.constraint(equalToConstant: 44),
            undoButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            toolRail.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            toolTop,

            palette.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            paletteBottom,
            palette.heightAnchor.constraint(equalToConstant: 48),

            brushSlider.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            brushSlider.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            brushSlider.widthAnchor.constraint(equalToConstant: 44),
            brushSlider.heightAnchor.constraint(equalToConstant: 184),

            sendButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            sendButton.heightAnchor.constraint(equalToConstant: 52),

            trashTarget.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            trashTarget.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            textInputOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            textInputOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textInputOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textInputOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func addTool(
        _ tool: ImageEditorTool,
        title: String,
        systemImage: String? = nil,
        textIcon: String? = nil
    ) {
        let button = EditorToolButton(title: title, systemImage: systemImage, textIcon: textIcon)
        button.tag = tool.rawValue
        button.addTarget(self, action: #selector(toolTapped(_:)), for: .touchUpInside)
        toolButtons[tool] = button
        toolRail.addArrangedSubview(button)
    }

    private func configurePalette() {
        palette.translatesAutoresizingMaskIntoConstraints = false
        palette.axis = .horizontal
        palette.alignment = .center
        palette.spacing = 5
        palette.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        palette.layer.cornerRadius = 24
        palette.isLayoutMarginsRelativeArrangement = true
        palette.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        palette.isHidden = true

        let colors: [UIColor] = [.white, .black, .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .systemPurple]
        for color in colors {
            let button = UIButton(type: .custom)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.backgroundColor = color
            button.layer.cornerRadius = 13
            button.layer.borderColor = UIColor.gray.cgColor
            button.layer.borderWidth = 1
            button.accessibilityValue = color.description
            button.addTarget(self, action: #selector(colorTapped(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 26),
                button.heightAnchor.constraint(equalToConstant: 26)
            ])
            colorButtons.append(button)
            palette.addArrangedSubview(button)
        }

        eraserDivider.translatesAutoresizingMaskIntoConstraints = false
        eraserDivider.backgroundColor = UIColor.white.withAlphaComponent(0.2)
        eraserDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        eraserDivider.heightAnchor.constraint(equalToConstant: 26).isActive = true
        palette.addArrangedSubview(eraserDivider)
        palette.addArrangedSubview(eraserButton)
        refreshPalette()
    }

    private func selectTool(_ tool: ImageEditorTool) {
        switch tool {
        case .draw:
            canvas.mode = .draw
            canvas.isErasing = false
        case .text:
            canvas.mode = .text
            showTextInput(index: nil, text: "", color: selectedColor)
        case .crop:
            canvas.mode = .crop
        case .rotate:
            canvas.mode = .crop
            canvas.rotateLeft()
        }
        updateModeUI()
    }

    private func updateModeUI() {
        for (tool, button) in toolButtons {
            button.setActive(tool.canvasMode == canvas.mode)
        }
        let editing = canvas.mode == .draw || canvas.mode == .text
        palette.isHidden = !editing || !trashTarget.isHidden
        let drawing = canvas.mode == .draw
        eraserButton.isHidden = !drawing
        eraserDivider.isHidden = !drawing
        brushSlider.isHidden = !drawing
        eraserButton.backgroundColor = canvas.isErasing ? UIColor.systemBlue.withAlphaComponent(0.9) : .clear
    }

    private func refreshPalette() {
        colorButtons.forEach { button in
            let selected = button.backgroundColor?.rgbaApproximatelyEquals(selectedColor) == true
            button.layer.borderColor = (selected ? UIColor.white : UIColor.gray).cgColor
            button.layer.borderWidth = selected ? 3 : 1
        }
    }

    @objc private func eraserTapped() {
        canvas.isErasing.toggle()
        updateModeUI()
    }

    @objc private func toolTapped(_ sender: UIButton) {
        guard let tool = ImageEditorTool(rawValue: sender.tag) else { return }
        selectTool(tool)
    }

    @objc private func colorTapped(_ sender: UIButton) {
        guard let color = sender.backgroundColor else { return }
        self.selectedColor = color
        self.canvas.brushColor = color
        self.canvas.isErasing = false
        if self.canvas.mode == .text {
            self.canvas.setSelectedTextColor(color)
        }
        self.refreshPalette()
        self.updateModeUI()
    }

    @objc private func undoTapped() {
        canvas.resetAll()
        hasChanges = false
        undoButton.isHidden = true
        updateModeUI()
    }

    @objc private func sendTapped() {
        guard sendButton.isEnabled else { return }
        sendButton.isEnabled = false
        if !hasChanges {
            handedOffFile = true
            onSendStarted?()
            onSend?(sourceResult)
            return
        }
        guard let renderImage = canvas.makeRenderOperation(maxEdge: 2560) else {
            sendButton.isEnabled = true
            return
        }
        canvas.isUserInteractionEnabled = false
        let originalURL = sourceResult.fileURL
        let sendResult = onSend
        onSendStarted?()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = renderImage() else {
                DispatchQueue.main.async {
                    self?.sendButton.isEnabled = true
                    self?.canvas.isUserInteractionEnabled = true
                }
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("edited-\(UUID().uuidString).jpg")
            guard let data = image.jpegData(compressionQuality: 0.92),
                  (try? data.write(to: url, options: .atomic)) != nil else {
                DispatchQueue.main.async {
                    self?.sendButton.isEnabled = true
                    self?.canvas.isUserInteractionEnabled = true
                }
                return
            }
            if let originalURL { try? FileManager.default.removeItem(at: originalURL) }
            let result = MediaPickerResult(image: image, fileURL: url, isVideo: false)
            DispatchQueue.main.async { [weak self] in
                self?.handedOffFile = true
                sendResult?(result)
            }
        }
    }

    @objc private func closeTapped() {
        dismissEditor()
    }

    @objc private func edgeDismiss(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard sendButton.isEnabled,
              gesture.state == .ended,
              gesture.translation(in: view).x > 80 else { return }
        dismissEditor()
    }

    private func dismissEditor() {
        guard sendButton.isEnabled else { return }
        onCancel?()
        dismiss(animated: true)
    }

    private func makeTextInputOverlay() -> UIView {
        let overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.9)
        overlay.isHidden = true

        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.textColor = selectedColor
        textView.font = .boldSystemFont(ofSize: 32)
        textView.textAlignment = .center
        textView.tintColor = .white
        textView.returnKeyType = .default
        textView.delegate = self

        let cancel = UIButton(type: .system)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.setTitle(L(L10n.Common.cancel), for: .normal)
        cancel.setTitleColor(.white, for: .normal)
        cancel.titleLabel?.font = .systemFont(ofSize: 17)
        cancel.addTarget(self, action: #selector(cancelTextInput), for: .touchUpInside)

        let done = UIButton(type: .system)
        done.translatesAutoresizingMaskIntoConstraints = false
        done.setTitle(L(L10n.ImageEditor.done), for: .normal)
        done.setTitleColor(.white, for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        done.addTarget(self, action: #selector(doneTextInput), for: .touchUpInside)

        overlay.addSubview(textView)
        overlay.addSubview(cancel)
        overlay.addSubview(done)
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancel.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancel.heightAnchor.constraint(equalToConstant: 48),
            done.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            done.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 8),
            done.heightAnchor.constraint(equalToConstant: 48),
            textView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 24),
            textView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -24),
            textView.topAnchor.constraint(equalTo: cancel.bottomAnchor, constant: 8),
            textView.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -60)
        ])
        return overlay
    }

    private func showTextInput(index: Int?, text: String, color: UIColor) {
        editingTextIndex = index
        selectedColor = color
        textView.text = text
        textView.textColor = color
        textInputOverlay.isHidden = false
        view.bringSubviewToFront(textInputOverlay)
        textView.becomeFirstResponder()
        refreshPalette()
    }

    @objc private func cancelTextInput() {
        textView.resignFirstResponder()
        textInputOverlay.isHidden = true
        editingTextIndex = nil
        updateModeUI()
    }

    @objc private func doneTextInput() {
        let value = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = editingTextIndex {
            canvas.updateText(at: index, text: value, color: selectedColor)
        } else if !value.isEmpty {
            canvas.addText(value, color: selectedColor)
        }
        textView.resignFirstResponder()
        textInputOverlay.isHidden = true
        editingTextIndex = nil
        updateModeUI()
    }

    private func updateTrash(active: Bool, point: CGPoint) -> Bool {
        guard active else {
            let wasVisible = !trashTarget.isHidden
            trashTarget.isHidden = true
            trashTarget.transform = .identity
            trashTarget.backgroundColor = .white
            trashTarget.subviews.compactMap { $0 as? UIImageView }.first?.tintColor = .black
            if wasVisible { updateModeUI() }
            return false
        }
        let becameVisible = trashTarget.isHidden
        if becameVisible {
            trashTarget.isHidden = false
            trashTarget.transform = CGAffineTransform(scaleX: 0.82, y: 0.82)
            UIView.animate(withDuration: 0.14) { self.trashTarget.transform = .identity }
        }
        view.layoutIfNeeded()
        let hot = trashTarget.frame.insetBy(dx: -14, dy: -14).contains(point)
        trashTarget.backgroundColor = hot ? UIColor.systemRed : .white
        trashTarget.subviews.compactMap { $0 as? UIImageView }.first?.tintColor = hot ? .white : .black
        trashTarget.transform = hot ? CGAffineTransform(scaleX: 1.08, y: 1.08) : .identity
        if becameVisible { updateModeUI() }
        return hot
    }
}

extension ImageEditorViewController: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard let swiftRange = Range(range, in: textView.text) else { return false }
        let updated = textView.text.replacingCharacters(in: swiftRange, with: text)
        return updated.count <= 200 && updated.components(separatedBy: .newlines).count <= 6
    }
}

private final class EditorToolButton: UIButton {
    private let iconLabel = UILabel()
    private let caption = UILabel()

    init(title: String, systemImage: String?, textIcon: String?) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 48).isActive = true
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false

        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        iconLabel.text = textIcon
        iconLabel.textColor = .white
        iconLabel.font = .systemFont(ofSize: textIcon == nil ? 0 : 20, weight: .semibold)
        iconLabel.textAlignment = .center
        iconLabel.numberOfLines = 1
        iconLabel.lineBreakMode = .byClipping
        iconLabel.adjustsFontSizeToFitWidth = true
        iconLabel.minimumScaleFactor = 0.75
        if let systemImage {
            let attachment = NSTextAttachment()
            attachment.image = UIImage(systemName: systemImage)?.withTintColor(.white, renderingMode: .alwaysOriginal)
            iconLabel.attributedText = NSAttributedString(attachment: attachment)
        }
        caption.text = title
        caption.textColor = .white
        caption.font = .systemFont(ofSize: 15, weight: .semibold)
        stack.addArrangedSubview(iconLabel)
        stack.addArrangedSubview(caption)
        addSubview(stack)
        NSLayoutConstraint.activate([
            iconLabel.widthAnchor.constraint(equalToConstant: 28),
            iconLabel.heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        let captionWidth = caption.isHidden ? 0 : caption.intrinsicContentSize.width + 8
        return CGSize(width: 48 + captionWidth, height: 48)
    }

    func setActive(_ active: Bool) {
        backgroundColor = active ? UIColor.systemBlue.withAlphaComponent(0.9) : UIColor.black.withAlphaComponent(0.7)
        layer.borderColor = (active ? UIColor.systemBlue : UIColor.white.withAlphaComponent(0.15)).cgColor
    }

    func setLabelVisible(_ visible: Bool, animated: Bool) {
        let changes = {
            self.caption.isHidden = !visible
            self.invalidateIntrinsicContentSize()
            self.layoutIfNeeded()
        }
        animated ? UIView.animate(withDuration: 0.2, animations: changes) : changes()
    }
}

private final class VerticalBrushSizeView: UIControl {
    var onValueChanged: ((CGFloat) -> Void)?
    private var value: CGFloat = 6

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 0.86)
        layer.cornerRadius = 22
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        let top: CGFloat = 22
        let bottom = bounds.height - 22
        let center = bounds.midX
        let fraction = (value - 3) / 13
        let thumbY = bottom - fraction * (bottom - top)
        let topHalf: CGFloat = 9
        let bottomHalf: CGFloat = 1.5
        let thumbHalf = bottomHalf + (topHalf - bottomHalf) * fraction

        let track = UIBezierPath()
        track.move(to: CGPoint(x: center - topHalf, y: top))
        track.addLine(to: CGPoint(x: center + topHalf, y: top))
        track.addLine(to: CGPoint(x: center + bottomHalf, y: bottom))
        track.addLine(to: CGPoint(x: center - bottomHalf, y: bottom))
        track.close()
        UIColor.white.withAlphaComponent(0.35).setFill()
        track.fill()

        let active = UIBezierPath()
        active.move(to: CGPoint(x: center - bottomHalf, y: bottom))
        active.addLine(to: CGPoint(x: center + bottomHalf, y: bottom))
        active.addLine(to: CGPoint(x: center + thumbHalf, y: thumbY))
        active.addLine(to: CGPoint(x: center - thumbHalf, y: thumbY))
        active.close()
        UIColor.systemBlue.setFill()
        active.fill()
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: center - 9, y: thumbY - 9, width: 18, height: 18)).fill()
        UIColor.systemBlue.setFill()
        let radius = 2 + fraction * 4
        UIBezierPath(ovalIn: CGRect(x: center - radius, y: thumbY - radius, width: radius * 2, height: radius * 2)).fill()
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        update(touch.location(in: self).y)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        update(touch.location(in: self).y)
        return true
    }

    private func update(_ y: CGFloat) {
        let top: CGFloat = 22
        let bottom = bounds.height - 22
        let fraction = min(1, max(0, (bottom - y) / (bottom - top)))
        value = 3 + fraction * 13
        setNeedsDisplay()
        onValueChanged?(value)
    }
}

private extension UIColor {
    func rgbaApproximatelyEquals(_ other: UIColor) -> Bool {
        var lhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var rhs: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&lhs.0, green: &lhs.1, blue: &lhs.2, alpha: &lhs.3)
        other.getRed(&rhs.0, green: &rhs.1, blue: &rhs.2, alpha: &rhs.3)
        return abs(lhs.0 - rhs.0) < 0.01 && abs(lhs.1 - rhs.1) < 0.01 && abs(lhs.2 - rhs.2) < 0.01
    }
}

private final class CanvasTextContainerView: UIView {
    var texts: [ImageEditorCanvasView.TextOverlay] = []
    var cropRect: CGRect = .zero

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clip(to: cropRect)
        for overlay in texts {
            ImageEditorCanvasView.draw(text: overlay, cropRect: cropRect)
        }
    }
}

private final class ImageEditorCanvasView: UIView, UIGestureRecognizerDelegate {
    enum Mode: Hashable { case crop, draw, text }

    struct Stroke {
        var points: [CGPoint]
        let color: UIColor
        let width: CGFloat
    }

    struct TextOverlay {
        var text: String
        var color: UIColor
        var center: CGPoint
        let fontSize: CGFloat
    }

    enum CropTarget: Equatable {
        case topLeft, topRight, bottomLeft, bottomRight
        case left, top, right, bottom
        case moveCrop, panImage, none
    }

    var onChanged: (() -> Void)?
    var onTextEdit: ((Int, String, UIColor) -> Void)?
    var onTextSelected: ((UIColor) -> Void)?
    var onTextDrag: ((Bool, CGPoint) -> Bool)?

    var mode: Mode = .crop {
        didSet {
            currentStroke = nil
            textTouchIndex = nil
            isErasing = false
            updateActiveStrokeLayer()
            updateLayers()
        }
    }
    var brushColor: UIColor = .systemRed
    var brushWidth: CGFloat = 6
    var isErasing = false
    var cropInsets: UIEdgeInsets = .zero {
        didSet {
            if didInitialLayout { reflowForAllowedRectChange(from: lastAllowedCropRect, to: allowedCropRect) }
            else { setNeedsLayout() }
        }
    }

    private let image: UIImage
    private let displayImage: UIImage
    private var committedStrokesCache: UIImage?
    
    private let imageContainerView = UIView()
    private let imageView = UIImageView()
    private let strokesView = UIImageView()
    private let activeStrokeLayer = CAShapeLayer()
    private let cropMaskLayer = CAShapeLayer()
    private let cropFrameLayer = CAShapeLayer()
    private let cropCornersLayer = CAShapeLayer()
    private let textContainerView = CanvasTextContainerView()

    private var cropRect: CGRect = .zero
    private var initialCropRect: CGRect = .zero
    private var imageCenter: CGPoint = .zero
    private var imageScale: CGFloat = 1
    private var initialImageCenter: CGPoint = .zero
    private var initialImageScale: CGFloat = 1
    private var quarterTurns = 0
    private var rotationCropFitScale: CGFloat = 1
    private var didInitialLayout = false
    private var lastAllowedCropRect: CGRect = .zero

    private var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    private var texts: [TextOverlay] = []
    private var selectedTextIndex: Int?
    private var textTouchIndex: Int?
    private var textDragOffset = CGPoint.zero
    private var textDownPoint = CGPoint.zero
    private var textMoved = false
    private var cropTarget: CropTarget = .none
    private var lastTouch = CGPoint.zero
    private let touchSlop: CGFloat = 8
    private lazy var pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

    init(image: UIImage) {
        let normalized = image.normalizedForEditing()
        self.image = normalized
        self.displayImage = Self.createDisplayImage(normalized)
        super.init(frame: .zero)
        backgroundColor = .black
        isOpaque = true
        
        imageContainerView.bounds = CGRect(origin: .zero, size: normalized.size)
        imageContainerView.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        imageView.frame = imageContainerView.bounds
        imageView.contentMode = .scaleToFill
        imageView.image = displayImage
        imageContainerView.addSubview(imageView)
        
        strokesView.frame = imageContainerView.bounds
        strokesView.contentMode = .scaleToFill
        imageContainerView.addSubview(strokesView)
        
        activeStrokeLayer.frame = imageContainerView.bounds
        activeStrokeLayer.fillColor = nil
        activeStrokeLayer.lineCap = .round
        activeStrokeLayer.lineJoin = .round
        imageContainerView.layer.addSublayer(activeStrokeLayer)
        
        addSubview(imageContainerView)
        
        cropMaskLayer.fillRule = .evenOdd
        cropMaskLayer.fillColor = UIColor.black.withAlphaComponent(0.62).cgColor
        layer.addSublayer(cropMaskLayer)
        
        cropFrameLayer.fillColor = nil
        cropFrameLayer.strokeColor = UIColor.white.withAlphaComponent(0.75).cgColor
        cropFrameLayer.lineWidth = 1
        layer.addSublayer(cropFrameLayer)
        
        cropCornersLayer.fillColor = nil
        cropCornersLayer.strokeColor = UIColor.white.cgColor
        cropCornersLayer.lineWidth = 3.5
        cropCornersLayer.lineCap = .square
        layer.addSublayer(cropCornersLayer)
        
        textContainerView.isOpaque = false
        textContainerView.backgroundColor = .clear
        addSubview(textContainerView)
        
        pinch.delegate = self
        pinch.cancelsTouchesInView = false
        addGestureRecognizer(pinch)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func createDisplayImage(_ source: UIImage) -> UIImage {
        let maxEdge = max(UIScreen.main.nativeBounds.width, UIScreen.main.nativeBounds.height)
        let longest = max(source.size.width, source.size.height)
        guard longest > maxEdge else { return source }
        let factor = maxEdge / longest
        let newSize = CGSize(
            width: (source.size.width * factor).rounded(),
            height: (source.size.height * factor).rounded()
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    private func rebuildStrokesCache() {
        guard !strokes.isEmpty else {
            committedStrokesCache = nil
            strokesView.image = nil
            return
        }
        let cacheSize = displayImage.size
        let xScale = cacheSize.width / image.size.width
        let yScale = cacheSize.height / image.size.height
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        committedStrokesCache = UIGraphicsImageRenderer(size: cacheSize, format: format).image { ctx in
            ctx.cgContext.scaleBy(x: xScale, y: yScale)
            for stroke in self.strokes {
                Self.draw(stroke: stroke)
            }
        }
        strokesView.image = committedStrokesCache
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !didInitialLayout, bounds.width > 0, bounds.height > 0 else { return }
        didInitialLayout = true
        layoutInitialCrop()
    }

    private var allowedCropRect: CGRect {
        bounds.inset(by: cropInsets)
    }

    private func layoutInitialCrop() {
        let allowed = allowedCropRect
        guard allowed.width > 1, allowed.height > 1 else { return }
        lastAllowedCropRect = allowed
        let imageAspect = image.size.width / max(image.size.height, 1)
        var size = allowed.size
        if size.width / size.height > imageAspect {
            size.width = size.height * imageAspect
        } else {
            size.height = size.width / imageAspect
        }
        cropRect = CGRect(
            x: allowed.midX - size.width / 2,
            y: allowed.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        imageCenter = CGPoint(x: cropRect.midX, y: cropRect.midY)
        imageScale = max(cropRect.width / image.size.width, cropRect.height / image.size.height)
        initialCropRect = cropRect
        initialImageCenter = imageCenter
        initialImageScale = imageScale
        rotationCropFitScale = 1
        updateLayers()
    }

    private func reflowForAllowedRectChange(from old: CGRect, to new: CGRect) {
        guard old.width > 1, old.height > 1, new.width > 1, new.height > 1, old != new else {
            lastAllowedCropRect = new
            return
        }
        let factor = min(new.width / old.width, new.height / old.height)
        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: new.midX + (point.x - old.midX) * factor,
                y: new.midY + (point.y - old.midY) * factor
            )
        }
        let mappedOrigin = map(cropRect.origin)
        cropRect = CGRect(
            origin: mappedOrigin,
            size: CGSize(width: cropRect.width * factor, height: cropRect.height * factor)
        )
        imageCenter = map(imageCenter)
        imageScale *= factor
        initialCropRect = CGRect(
            origin: map(initialCropRect.origin),
            size: CGSize(width: initialCropRect.width * factor, height: initialCropRect.height * factor)
        )
        initialImageCenter = map(initialImageCenter)
        initialImageScale *= factor
        texts.indices.forEach { texts[$0].center = map(texts[$0].center) }
        lastAllowedCropRect = new

        if !new.contains(cropRect) {
            let fit = min(new.width / cropRect.width, new.height / cropRect.height, 1)
            cropRect.size.width *= fit
            cropRect.size.height *= fit
            cropRect.origin = CGPoint(x: new.midX - cropRect.width / 2, y: new.midY - cropRect.height / 2)
        }
        rotationCropFitScale = 1
        clampImageToCrop()
    }

    private var imageTransform: CGAffineTransform {
        CGAffineTransform(translationX: imageCenter.x, y: imageCenter.y)
            .rotated(by: CGFloat(quarterTurns) * -.pi / 2)
            .scaledBy(x: imageScale, y: imageScale)
            .translatedBy(x: -image.size.width / 2, y: -image.size.height / 2)
    }

    private var imageBounds: CGRect {
        let rotated = quarterTurns % 2 != 0
        let width = (rotated ? image.size.height : image.size.width) * imageScale
        let height = (rotated ? image.size.width : image.size.height) * imageScale
        return CGRect(x: imageCenter.x - width / 2, y: imageCenter.y - height / 2, width: width, height: height)
    }

    private func updateLayers() {
        imageContainerView.center = imageCenter
        imageContainerView.transform = CGAffineTransform(rotationAngle: CGFloat(quarterTurns) * -.pi / 2)
            .scaledBy(x: imageScale, y: imageScale)
        
        let boundsPath = UIBezierPath(rect: bounds)
        boundsPath.append(UIBezierPath(rect: cropRect))
        cropMaskLayer.path = boundsPath.cgPath

        cropFrameLayer.path = UIBezierPath(rect: cropRect).cgPath

        if mode == .crop {
            let length: CGFloat = 22
            let path = UIBezierPath()
            path.move(to: CGPoint(x: cropRect.minX + length, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.minY + length))
            path.move(to: CGPoint(x: cropRect.maxX - length, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + length))
            path.move(to: CGPoint(x: cropRect.minX + length, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.minX, y: cropRect.maxY - length))
            path.move(to: CGPoint(x: cropRect.maxX - length, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.maxY))
            path.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.maxY - length))
            cropCornersLayer.path = path.cgPath
            cropCornersLayer.isHidden = false
        } else {
            cropCornersLayer.isHidden = true
        }

        textContainerView.frame = bounds
        textContainerView.cropRect = cropRect
        textContainerView.texts = texts
        textContainerView.setNeedsDisplay()
    }
    
    private func updateActiveStrokeLayer() {
        guard let stroke = currentStroke, let first = stroke.points.first else {
            activeStrokeLayer.path = nil
            return
        }
        let path = UIBezierPath()
        path.move(to: first)
        if stroke.points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y + 0.01))
        } else {
            for index in 1..<stroke.points.count {
                let previous = stroke.points[index - 1]
                let point = stroke.points[index]
                let midpoint = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                path.addQuadCurve(to: midpoint, controlPoint: previous)
            }
            if let last = stroke.points.last { path.addLine(to: last) }
        }
        activeStrokeLayer.strokeColor = stroke.color.cgColor
        activeStrokeLayer.lineWidth = stroke.width
        activeStrokeLayer.path = path.cgPath
    }

    fileprivate static func draw(stroke: Stroke) {
        guard let first = stroke.points.first else { return }
        let path = UIBezierPath()
        path.move(to: first)
        if stroke.points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y + 0.01))
        } else {
            for index in 1..<stroke.points.count {
                let previous = stroke.points[index - 1]
                let point = stroke.points[index]
                let midpoint = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
                path.addQuadCurve(to: midpoint, controlPoint: previous)
            }
            if let last = stroke.points.last { path.addLine(to: last) }
        }
        path.lineWidth = stroke.width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        stroke.color.setStroke()
        path.stroke()
    }

    fileprivate static func draw(text overlay: TextOverlay, cropRect: CGRect) {
        let rect = textBounds(overlay, cropRect: cropRect)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = UIFont.boldSystemFont(ofSize: overlay.fontSize)
        let outline: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: overlay.color,
            .strokeColor: overlay.color == .black ? UIColor.white : UIColor.black,
            .strokeWidth: -2.5
        ]
        (overlay.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: outline, context: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, event?.allTouches?.count == 1, let point = touches.first?.location(in: self) else { return }
        lastTouch = point
        switch mode {
        case .draw:
            guard cropRect.contains(point) else { return }
            if isErasing { erase(at: point) }
            else if let imagePoint = viewToImage(point) {
                currentStroke = Stroke(points: [imagePoint], color: brushColor, width: brushWidth / imageScale)
            }
        case .text:
            textTouchIndex = findText(at: point)
            textDownPoint = point
            textMoved = false
            if let index = textTouchIndex {
                selectedTextIndex = index
                onTextSelected?(texts[index].color)
                textDragOffset = CGPoint(x: texts[index].center.x - point.x, y: texts[index].center.y - point.y)
            }
        case .crop:
            cropTarget = findCropTarget(at: point)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard event?.allTouches?.count == 1, !pinch.isEnabled || pinch.state != .changed,
              let point = touches.first?.location(in: self) else { return }
        let delta = CGPoint(x: point.x - lastTouch.x, y: point.y - lastTouch.y)
        switch mode {
        case .draw:
            if isErasing { erase(at: point) }
            else if cropRect.contains(point), let imagePoint = viewToImage(point), currentStroke != nil {
                currentStroke?.points.append(imagePoint)
                updateActiveStrokeLayer()
            }
        case .text:
            guard let index = textTouchIndex else { break }
            if !textMoved, hypot(point.x - textDownPoint.x, point.y - textDownPoint.y) > touchSlop { textMoved = true }
            if textMoved {
                let center = CGPoint(x: point.x + textDragOffset.x, y: point.y + textDragOffset.y)
                texts[index].center = clampTextCenter(center, overlay: texts[index])
                _ = onTextDrag?(true, point)
                updateLayers()
            }
        case .crop:
            applyCropDrag(delta)
        }
        lastTouch = point
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let point = touches.first?.location(in: self) ?? lastTouch
        switch mode {
        case .draw:
            if let stroke = currentStroke {
                strokes.append(stroke)
                currentStroke = nil
                rebuildStrokesCache()
                updateActiveStrokeLayer()
                onChanged?()
                updateLayers()
            }
        case .text:
            if let index = textTouchIndex {
                if textMoved {
                    let shouldDelete = onTextDrag?(true, point) == true
                    _ = onTextDrag?(false, point)
                    if shouldDelete {
                        removeText(at: index)
                    } else {
                        changed()
                    }
                } else {
                    let overlay = texts[index]
                    onTextEdit?(index, overlay.text, overlay.color)
                }
            }
            textTouchIndex = nil
        case .crop:
            cropTarget = .none
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
        textTouchIndex = nil
        cropTarget = .none
        _ = onTextDrag?(false, lastTouch)
        updateActiveStrokeLayer()
        updateLayers()
    }

    private func findCropTarget(at point: CGPoint) -> CropTarget {
        let radius: CGFloat = 28
        let left = abs(point.x - cropRect.minX) <= radius
        let right = abs(point.x - cropRect.maxX) <= radius
        let top = abs(point.y - cropRect.minY) <= radius
        let bottom = abs(point.y - cropRect.maxY) <= radius
        let expandedX = point.x >= cropRect.minX - radius && point.x <= cropRect.maxX + radius
        let expandedY = point.y >= cropRect.minY - radius && point.y <= cropRect.maxY + radius
        if left && top { return .topLeft }
        if right && top { return .topRight }
        if left && bottom { return .bottomLeft }
        if right && bottom { return .bottomRight }
        if left && expandedY { return .left }
        if right && expandedY { return .right }
        if top && expandedX { return .top }
        if bottom && expandedX { return .bottom }
        if cropRect.contains(point) { return .moveCrop }
        if canPanImage && imageBounds.contains(point) { return .panImage }
        return .none
    }

    private var canPanImage: Bool {
        imageBounds.width > cropRect.width + 1 || imageBounds.height > cropRect.height + 1
    }

    private func applyCropDrag(_ delta: CGPoint) {
        guard cropTarget != .none else { return }
        if cropTarget == .panImage {
            imageCenter.x += delta.x
            imageCenter.y += delta.y
            clampImageToCrop()
            changed()
            return
        }
        if cropTarget == .moveCrop {
            let bounds = allowedCropRect.intersection(imageBounds)
            let dx = min(max(delta.x, bounds.minX - cropRect.minX), bounds.maxX - cropRect.maxX)
            let dy = min(max(delta.y, bounds.minY - cropRect.minY), bounds.maxY - cropRect.maxY)
            cropRect = cropRect.offsetBy(dx: dx, dy: dy)
            changed()
            return
        }
        resizeCrop(by: delta)
    }

    private func resizeCrop(by delta: CGPoint) {
        let limits = allowedCropRect.intersection(imageBounds)
        guard !limits.isNull else { return }
        let minimum: CGFloat = 80
        var rect = cropRect
        switch cropTarget {
        case .topLeft:
            rect.origin.x = min(max(rect.minX + delta.x, limits.minX), rect.maxX - minimum)
            rect.origin.y = min(max(rect.minY + delta.y, limits.minY), rect.maxY - minimum)
            rect.size.width = cropRect.maxX - rect.minX
            rect.size.height = cropRect.maxY - rect.minY
        case .topRight:
            rect.size.width = min(max(rect.width + delta.x, minimum), limits.maxX - rect.minX)
            let oldMaxY = rect.maxY
            rect.origin.y = min(max(rect.minY + delta.y, limits.minY), oldMaxY - minimum)
            rect.size.height = oldMaxY - rect.minY
        case .bottomLeft:
            let oldMaxX = rect.maxX
            rect.origin.x = min(max(rect.minX + delta.x, limits.minX), oldMaxX - minimum)
            rect.size.width = oldMaxX - rect.minX
            rect.size.height = min(max(rect.height + delta.y, minimum), limits.maxY - rect.minY)
        case .bottomRight:
            rect.size.width = min(max(rect.width + delta.x, minimum), limits.maxX - rect.minX)
            rect.size.height = min(max(rect.height + delta.y, minimum), limits.maxY - rect.minY)
        case .left:
            let oldMaxX = rect.maxX
            rect.origin.x = min(max(rect.minX + delta.x, limits.minX), oldMaxX - minimum)
            rect.size.width = oldMaxX - rect.minX
        case .top:
            let oldMaxY = rect.maxY
            rect.origin.y = min(max(rect.minY + delta.y, limits.minY), oldMaxY - minimum)
            rect.size.height = oldMaxY - rect.minY
        case .right:
            rect.size.width = min(max(rect.width + delta.x, minimum), limits.maxX - rect.minX)
        case .bottom:
            rect.size.height = min(max(rect.height + delta.y, minimum), limits.maxY - rect.minY)
        default: return
        }
        cropRect = rect
        rotationCropFitScale = 1
        changed()
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else {
            if gesture.state == .ended { clampImageToCrop() }
            return
        }
        let focus = gesture.location(in: self)
        let factor = gesture.scale
        let newScale = min(max(imageScale * factor, minimumScaleToCoverCrop()), initialImageScale * 8)
        let actual = newScale / imageScale
        imageCenter = CGPoint(
            x: focus.x + (imageCenter.x - focus.x) * actual,
            y: focus.y + (imageCenter.y - focus.y) * actual
        )
        imageScale = newScale
        gesture.scale = 1
        clampImageToCrop()
        changed()
    }

    private func minimumScaleToCoverCrop() -> CGFloat {
        let rotated = quarterTurns % 2 != 0
        let width = rotated ? image.size.height : image.size.width
        let height = rotated ? image.size.width : image.size.height
        return max(cropRect.width / width, cropRect.height / height)
    }

    private func clampImageToCrop() {
        imageScale = max(imageScale, minimumScaleToCoverCrop())
        let halfW = imageBounds.width / 2
        let halfH = imageBounds.height / 2
        imageCenter.x = min(max(imageCenter.x, cropRect.maxX - halfW), cropRect.minX + halfW)
        imageCenter.y = min(max(imageCenter.y, cropRect.maxY - halfH), cropRect.minY + halfH)
        updateLayers()
    }

    func rotateLeft() {
        let oldCropCenter = CGPoint(x: cropRect.midX, y: cropRect.midY)
        let oldImageOffset = CGPoint(
            x: imageCenter.x - oldCropCenter.x,
            y: imageCenter.y - oldCropCenter.y
        )
        let allowed = allowedCropRect
        let currentFit = max(rotationCropFitScale, 0.0001)
        let unscaledRotatedSize = CGSize(
            width: cropRect.height / currentFit,
            height: cropRect.width / currentFit
        )
        let newFit = min(
            1,
            allowed.width / unscaledRotatedSize.width,
            allowed.height / unscaledRotatedSize.height
        )
        let scaleChange = newFit / currentFit
        let newSize = CGSize(
            width: unscaledRotatedSize.width * newFit,
            height: unscaledRotatedSize.height * newFit
        )
        let newCropCenter = CGPoint(
            x: min(max(oldCropCenter.x, allowed.minX + newSize.width / 2), allowed.maxX - newSize.width / 2),
            y: min(max(oldCropCenter.y, allowed.minY + newSize.height / 2), allowed.maxY - newSize.height / 2)
        )

        quarterTurns = (quarterTurns + 1) % 4
        imageScale *= scaleChange
        imageCenter = CGPoint(
            x: newCropCenter.x + oldImageOffset.y * scaleChange,
            y: newCropCenter.y - oldImageOffset.x * scaleChange
        )
        cropRect = CGRect(
            x: newCropCenter.x - newSize.width / 2,
            y: newCropCenter.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        for index in texts.indices {
            var overlay = texts[index]
            let oldTextOffset = CGPoint(
                x: overlay.center.x - oldCropCenter.x,
                y: overlay.center.y - oldCropCenter.y
            )
            let remappedCenter = CGPoint(
                x: newCropCenter.x + oldTextOffset.y * scaleChange,
                y: newCropCenter.y - oldTextOffset.x * scaleChange
            )
            overlay.center = clampTextCenter(remappedCenter, overlay: overlay)
            texts[index] = overlay
        }
        rotationCropFitScale = newFit
        clampImageToCrop()
        changed()
    }

    private func changed() {
        onChanged?()
        updateLayers()
    }

    func resetAll() {
        let activeMode = mode
        cropRect = initialCropRect
        imageCenter = initialImageCenter
        imageScale = initialImageScale
        quarterTurns = 0
        rotationCropFitScale = 1
        strokes.removeAll()
        committedStrokesCache = nil
        texts.removeAll()
        selectedTextIndex = nil
        textTouchIndex = nil
        mode = activeMode
    }

    func addText(_ text: String, color: UIColor) {
        guard !text.isEmpty else { return }
        texts.append(TextOverlay(text: text, color: color, center: CGPoint(x: cropRect.midX, y: cropRect.midY), fontSize: 32))
        selectedTextIndex = texts.indices.last
        changed()
    }

    func updateText(at index: Int, text: String, color: UIColor) {
        guard texts.indices.contains(index) else { return }
        if text.isEmpty {
            removeText(at: index)
            return
        } else {
            texts[index].text = text
            texts[index].color = color
            selectedTextIndex = index
        }
        changed()
    }

    func setSelectedTextColor(_ color: UIColor) {
        guard let index = selectedTextIndex, texts.indices.contains(index),
              !texts[index].color.rgbaApproximatelyEquals(color) else { return }
        texts[index].color = color
        changed()
    }

    private func removeText(at index: Int) {
        guard texts.indices.contains(index) else { return }
        texts.remove(at: index)
        if let selected = selectedTextIndex {
            if selected == index { selectedTextIndex = nil }
            else if selected > index { selectedTextIndex = selected - 1 }
        }
        textTouchIndex = nil
        changed()
    }

    private func findText(at point: CGPoint) -> Int? {
        for index in texts.indices.reversed() where textBounds(texts[index]).insetBy(dx: -12, dy: -12).contains(point) {
            return index
        }
        return nil
    }

    private func textBounds(_ overlay: TextOverlay) -> CGRect {
        Self.textBounds(overlay, cropRect: cropRect)
    }

    private static func textBounds(_ overlay: TextOverlay, cropRect: CGRect) -> CGRect {
        let maxWidth = max(80, cropRect.width - 24)
        let font = UIFont.boldSystemFont(ofSize: overlay.fontSize)
        var size = (overlay.text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).integral.size
        size.width = min(maxWidth, max(24, size.width + 4))
        size.height = max(overlay.fontSize + 4, size.height + 4)
        return CGRect(x: overlay.center.x - size.width / 2, y: overlay.center.y - size.height / 2, width: size.width, height: size.height)
    }

    private func clampTextCenter(_ center: CGPoint, overlay: TextOverlay) -> CGPoint {
        let rect = textBounds(overlay)
        return CGPoint(
            x: min(max(center.x, cropRect.minX + rect.width / 2), cropRect.maxX - rect.width / 2),
            y: min(max(center.y, cropRect.minY + rect.height / 2), cropRect.maxY - rect.height / 2)
        )
    }

    private func viewToImage(_ point: CGPoint) -> CGPoint? {
        let inverse = imageTransform.inverted()
        let mapped = point.applying(inverse)
        guard mapped.x >= 0, mapped.y >= 0, mapped.x <= image.size.width, mapped.y <= image.size.height else { return nil }
        return mapped
    }

    private func erase(at viewPoint: CGPoint) {
        guard let imagePoint = viewToImage(viewPoint) else { return }
        let radius = 14 / imageScale
        let oldCount = strokes.count
        strokes.removeAll { stroke in
            guard stroke.points.count > 1 else { return stroke.points.first.map { hypot($0.x - imagePoint.x, $0.y - imagePoint.y) <= radius } ?? false }
            for index in 1..<stroke.points.count {
                if distance(imagePoint, toSegmentFrom: stroke.points[index - 1], to: stroke.points[index]) <= radius + stroke.width / 2 { return true }
            }
            return false
        }
        if strokes.count != oldCount {
            rebuildStrokesCache()
            changed()
        }
    }

    private func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    func makeRenderOperation(maxEdge: CGFloat) -> (() -> UIImage?)? {
        guard cropRect.width > 0, cropRect.height > 0 else { return nil }
        let sourceScale = max(1, 1 / imageScale)
        var output = CGSize(width: cropRect.width * sourceScale, height: cropRect.height * sourceScale)
        if max(output.width, output.height) > maxEdge {
            let factor = maxEdge / max(output.width, output.height)
            output.width *= factor
            output.height *= factor
        }
        output.width = max(1, output.width.rounded())
        output.height = max(1, output.height.rounded())
        let sx = output.width / cropRect.width
        let sy = output.height / cropRect.height
        let sourceImage = image
        let sourceImageTransform = imageTransform
        let capturedCropRect = cropRect
        let capturedStrokes = strokes + (currentStroke.map { [$0] } ?? [])
        let capturedTexts = texts

        return {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: output, format: format)
            return renderer.image { context in
                UIColor.black.setFill()
                context.cgContext.fill(CGRect(origin: .zero, size: output))
                let transform = CGAffineTransform(scaleX: sx, y: sy)
                    .translatedBy(x: -capturedCropRect.minX, y: -capturedCropRect.minY)

                context.cgContext.saveGState()
                context.cgContext.concatenate(transform)
                context.cgContext.concatenate(sourceImageTransform)
                sourceImage.draw(in: CGRect(origin: .zero, size: sourceImage.size))
                for stroke in capturedStrokes { Self.draw(stroke: stroke) }
                context.cgContext.restoreGState()

                context.cgContext.saveGState()
                context.cgContext.concatenate(transform)
                context.cgContext.clip(to: capturedCropRect)
                for overlay in capturedTexts {
                    Self.draw(text: overlay, cropRect: capturedCropRect)
                }
                context.cgContext.restoreGState()
            }
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

private extension UIImage {
    func normalizedForEditing() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
