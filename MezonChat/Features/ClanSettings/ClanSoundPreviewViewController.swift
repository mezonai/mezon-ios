import UIKit
import AVFoundation

final class ClanSoundPreviewViewController: UIViewController, AVAudioPlayerDelegate {
    var onUpload: ((Data, String, String) async throws -> Void)?

    private let source: ClanSoundAudio.Source
    private let player: AVAudioPlayer
    private let nameField = UITextField()
    private let waveformView: ClanSoundWaveformView
    private let volumeSlider = UISlider()
    private let volumeLabel = UILabel()
    private let timeLabel = UILabel()
    private let errorLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var timer: Foundation.Timer?
    private var waveformTask: Task<Void, Never>?
    private var submitting = false

    init(source: ClanSoundAudio.Source) throws {
        self.source = source
        waveformView = ClanSoundWaveformView(duration: source.duration)
        do { player = try AVAudioPlayer(contentsOf: source.url) }
        catch {
            try? FileManager.default.removeItem(at: source.url)
            throw ClanSoundAudio.Failure.invalidFile
        }
        super.init(nibName: nil, bundle: nil)
        player.delegate = self
        player.volume = 0.8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        timer?.invalidate()
        waveformTask?.cancel()
        player.stop()
        try? FileManager.default.removeItem(at: source.url)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.theme.primary
        let scroll = UIScrollView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16.sh
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24.sh),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24.sh),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24.sw),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24.sw),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48.sw)
        ])
        let title = makeLabel(L(L10n.ClanSetting.Sounds.upload), bold: true)
        stack.addArrangedSubview(title)
        let previewHeading = makeSectionHeading(L(L10n.ClanSetting.Sounds.preview))
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12.sf, weight: .regular)
        timeLabel.textColor = UIColor.theme.textDisabled
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        let previewHeader = UIStackView(arrangedSubviews: [previewHeading, timeLabel])
        previewHeader.axis = .horizontal
        previewHeader.alignment = .center
        stack.addArrangedSubview(previewHeader)
        stack.setCustomSpacing(10.sh, after: previewHeader)

        let previewCard = UIView()
        previewCard.backgroundColor = UIColor.theme.secondaryWeight
        previewCard.layer.cornerRadius = 14.swh
        previewCard.layer.borderWidth = 1 / UIScreen.main.scale
        previewCard.layer.borderColor = UIColor.theme.borderDim.cgColor
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.backgroundColor = UIColor.theme.bgViolet
        playButton.layer.cornerRadius = 22.swh
        playButton.addTarget(self, action: #selector(togglePreview), for: .touchUpInside)
        waveformView.addTarget(self, action: #selector(trimChanged), for: [.editingDidBegin, .valueChanged])
        [playButton, waveformView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            previewCard.addSubview($0)
        }
        NSLayoutConstraint.activate([
            playButton.leadingAnchor.constraint(equalTo: previewCard.leadingAnchor, constant: 12.sw),
            playButton.centerYAnchor.constraint(equalTo: waveformView.centerYAnchor, constant: -10.sh),
            playButton.widthAnchor.constraint(equalToConstant: 44.swh),
            playButton.heightAnchor.constraint(equalTo: playButton.widthAnchor),
            waveformView.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 10.sw),
            waveformView.trailingAnchor.constraint(equalTo: previewCard.trailingAnchor, constant: -12.sw),
            waveformView.topAnchor.constraint(equalTo: previewCard.topAnchor, constant: 12.sh),
            waveformView.bottomAnchor.constraint(equalTo: previewCard.bottomAnchor, constant: -12.sh),
            waveformView.heightAnchor.constraint(equalToConstant: 96.sh)
        ])
        stack.addArrangedSubview(previewCard)

        let volumeHeading = makeSectionHeading(L(L10n.ClanSetting.Sounds.volume))
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 13.sf, weight: .regular)
        volumeLabel.textColor = UIColor.theme.textDisabled
        volumeLabel.setContentHuggingPriority(.required, for: .horizontal)
        let volumeHeader = UIStackView(arrangedSubviews: [volumeHeading, volumeLabel])
        volumeHeader.axis = .horizontal
        volumeHeader.alignment = .center
        stack.addArrangedSubview(volumeHeader)
        stack.setCustomSpacing(4.sh, after: volumeHeader)
        volumeSlider.minimumValue = 0
        volumeSlider.maximumValue = 1
        volumeSlider.value = 0.8
        volumeSlider.minimumTrackTintColor = UIColor.theme.bgViolet
        volumeSlider.accessibilityLabel = L(L10n.ClanSetting.Sounds.volume)
        volumeSlider.addTarget(self, action: #selector(volumeChanged), for: .valueChanged)
        stack.addArrangedSubview(volumeSlider)

        stack.addArrangedSubview(makeSectionHeading(L(L10n.ClanSetting.Sounds.name)))
        nameField.text = "voice_\(Int64(Date().timeIntervalSince1970 * 1000))"
        nameField.font = .systemFont(ofSize: 15.sf)
        nameField.textColor = UIColor.theme.textStrong
        nameField.backgroundColor = UIColor.theme.secondary
        nameField.borderStyle = .roundedRect
        nameField.autocapitalizationType = .none
        nameField.autocorrectionType = .no
        nameField.spellCheckingType = .no
        nameField.accessibilityLabel = L(L10n.ClanSetting.Sounds.name)
        nameField.addTarget(self, action: #selector(updateControls), for: .editingChanged)
        stack.addArrangedSubview(nameField)
        errorLabel.font = .systemFont(ofSize: 13.sf)
        errorLabel.numberOfLines = 0
        let instructions = makeLabel(L(L10n.ClanSetting.Sounds.nameRequirement) + "\n" + L(L10n.ClanSetting.Sounds.durationRequirement))
        stack.addArrangedSubview(instructions)
        errorLabel.textColor = .systemRed
        stack.addArrangedSubview(errorLabel)
        cancelButton.setTitle(L(L10n.Common.cancel), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        saveButton.setTitle(L(L10n.ClanSetting.Sounds.upload), for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.backgroundColor = UIColor.theme.bgViolet
        saveButton.layer.cornerRadius = 22.sh
        saveButton.addTarget(self, action: #selector(uploadTapped), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [cancelButton, saveButton])
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 12.sw
        actions.heightAnchor.constraint(equalToConstant: 44.sh).isActive = true
        stack.addArrangedSubview(actions)
        playButton.accessibilityLabel = L(L10n.ClanSetting.Sounds.play)
        updateControls()
        loadWaveform()
    }

    private func makeLabel(_ text: String, bold: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: bold ? 17.sf : 13.sf, weight: bold ? .bold : .regular)
        label.textColor = UIColor.theme.textStrong
        label.numberOfLines = 0
        return label
    }

    private func makeSectionHeading(_ text: String) -> UILabel {
        let label = makeLabel(text.uppercased())
        label.font = .systemFont(ofSize: 13.sf, weight: .bold)
        return label
    }

    private func loadWaveform() {
        let source = self.source
        waveformTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let peaks = try ClanSoundAudio.waveformPeaks(source: source)
                try Task.checkCancellation()
                await self?.displayWaveform(peaks)
            } catch { /* The audio preview remains usable if waveform extraction fails. */ }
        }
    }

    private func displayWaveform(_ peaks: [Float]) {
        waveformView.peaks = peaks
    }

    private var start: TimeInterval { waveformView.selectedStart }
    private var end: TimeInterval { waveformView.selectedEnd }

    @objc private func trimChanged() {
        stopPreview()
        updateControls()
    }

    @objc private func volumeChanged() {
        player.volume = volumeSlider.value
        updateControls()
    }

    @objc private func updateControls() {
        volumeLabel.text = "\(Int((volumeSlider.value * 100).rounded()))%"
        let validDuration = end >= start + ClanSoundAudio.minDuration && end - start <= ClanSoundAudio.maxDuration
        let name = ClanStickerNameValidator.normalized(nameField.text ?? "")
        saveButton.isEnabled = !submitting && validDuration && ClanStickerNameValidator.isValid(name)
        saveButton.alpha = saveButton.isEnabled ? 1 : 0.5
        if !submitting { errorLabel.text = validDuration ? nil : L(L10n.ClanSetting.Sounds.durationRequirement) }
        updateTime()
    }

    @objc private func togglePreview() {
        if player.isPlaying { stopPreview(); return }
        AppAudioSession.activateForMediaPlayback(options: [.mixWithOthers])
        player.currentTime = start
        player.play()
        playButton.setImage(UIImage(systemName: "pause.fill"), for: .normal)
        playButton.accessibilityLabel = L(L10n.ClanSetting.Sounds.pause)
        timer = Foundation.Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.player.currentTime >= self.end || !self.player.isPlaying { self.stopPreview() }
            self.updateTime()
        }
    }

    private func updateTime() {
        let current = player.isPlaying ? max(0, player.currentTime - start) : 0
        waveformView.playbackTime = player.isPlaying ? player.currentTime : nil
        timeLabel.text = "\(ClanSoundAudio.timeLabel(current)) / \(ClanSoundAudio.timeLabel(end - start))"
    }

    private func stopPreview() {
        player.pause()
        timer?.invalidate()
        timer = nil
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.accessibilityLabel = L(L10n.ClanSetting.Sounds.play)
        updateTime()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { stopPreview() }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopPreview()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func uploadTapped() {
        guard saveButton.isEnabled, let onUpload else { return }
        stopPreview()
        view.endEditing(true)
        submitting = true
        isModalInPresentation = true
        ([nameField, waveformView, volumeSlider, playButton, cancelButton] as [UIControl]).forEach { $0.isEnabled = false }
        let source = self.source
        let start = self.start
        let end = self.end
        let volume = volumeSlider.value
        let name = ClanStickerNameValidator.normalized(nameField.text ?? "")
        updateControls()
        Task {
            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try ClanSoundAudio.uploadData(source: source, start: start, end: end, volume: volume)
                }.value
                try await onUpload(payload.data, payload.fileExtension, name)
                Toast.success(L(L10n.ClanSetting.Sounds.saved))
                dismiss(animated: true)
            } catch {
                submitting = false
                isModalInPresentation = false
                ([nameField, waveformView, volumeSlider, playButton, cancelButton] as [UIControl]).forEach { $0.isEnabled = true }
                updateControls()
                errorLabel.text = error.localizedDescription
            }
        }
    }
}

private final class ClanSoundWaveformView: UIControl {
    private enum Handle { case start, end }

    private let duration: TimeInterval
    private(set) var selectedStart: TimeInterval = 0
    private(set) var selectedEnd: TimeInterval
    private let startLabel = UILabel()
    private let endLabel = UILabel()
    private var activeHandle: Handle?
    private lazy var startElement = TrimHandleElement(owner: self, isStart: true)
    private lazy var endElement = TrimHandleElement(owner: self, isStart: false)

    var peaks: [Float] = [] { didSet { setNeedsDisplay() } }
    var playbackTime: TimeInterval? { didSet { setNeedsDisplay() } }

    override var isEnabled: Bool {
        didSet {
            alpha = isEnabled ? 1 : 0.5
            [startElement, endElement].forEach {
                $0.accessibilityTraits = isEnabled ? [.adjustable] : [.adjustable, .notEnabled]
            }
        }
    }

    init(duration: TimeInterval) {
        self.duration = duration
        selectedEnd = min(duration, ClanSoundAudio.maxDuration)
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = false
        accessibilityElements = [startElement, endElement]
        [startLabel, endLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 12.sf, weight: .regular)
            $0.textColor = UIColor.theme.textDisabled
            $0.isAccessibilityElement = false
            addSubview($0)
        }
        endLabel.textAlignment = .right
        updateLabels()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var trackRect: CGRect {
        CGRect(x: 12.sw, y: 8.sh, width: max(0, bounds.width - 24.sw), height: max(0, bounds.height - 34.sh))
    }

    private func position(for time: TimeInterval) -> CGFloat {
        trackRect.minX + CGFloat(time / duration) * trackRect.width
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelTop = trackRect.maxY + 6.sh
        startLabel.frame = CGRect(x: trackRect.minX, y: labelTop, width: trackRect.width / 2, height: 18.sh)
        endLabel.frame = CGRect(x: trackRect.midX, y: labelTop, width: trackRect.width / 2, height: 18.sh)
        startElement.accessibilityFrameInContainerSpace = CGRect(x: position(for: selectedStart) - 22, y: trackRect.minY, width: 44, height: trackRect.height)
        endElement.accessibilityFrameInContainerSpace = CGRect(x: position(for: selectedEnd) - 22, y: trackRect.minY, width: 44, height: trackRect.height)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let track = trackRect
        guard track.width > 0, track.height > 0 else { return }
        let startX = position(for: selectedStart)
        let endX = position(for: selectedEnd)
        let barCount = max(1, min(peaks.isEmpty ? 144 : peaks.count, Int(track.width)))
        let step = track.width / CGFloat(barCount)
        let barWidth = max(0.25, step - 0.75)
        let selectedBars = UIBezierPath()
        let unselectedBars = UIBezierPath()
        for index in 0..<barCount {
            let lower = index * peaks.count / barCount
            let upper = (index + 1) * peaks.count / barCount
            let peak = peaks.isEmpty ? 0.08 : peaks[lower..<max(lower + 1, upper)].max() ?? 0.08
            let height = min(track.height, 3.sh + CGFloat(peak) * 47.sh)
            let x = track.minX + (CGFloat(index) + 0.5) * step
            let bar = UIBezierPath(roundedRect: CGRect(x: x - barWidth / 2, y: track.midY - height / 2, width: barWidth, height: height), cornerRadius: barWidth / 2)
            if x >= startX, x <= endX { selectedBars.append(bar) }
            else { unselectedBars.append(bar) }
        }
        UIColor.theme.textStrong.withAlphaComponent(0.38).setFill()
        unselectedBars.fill()
        UIColor.theme.textStrong.setFill()
        selectedBars.fill()

        UIColor.theme.textStrong.setFill()
        for x in [startX, endX] {
            let handle = CGRect(x: x - 2.swh, y: track.minY, width: 4.swh, height: track.height)
            UIBezierPath(roundedRect: handle, cornerRadius: 2.swh).fill()
        }
        if let playbackTime {
            let x = position(for: min(selectedEnd, max(selectedStart, playbackTime)))
            UIColor.theme.bgViolet.setFill()
            UIBezierPath(rect: CGRect(x: x - 1, y: track.minY + 4.sh, width: 2, height: track.height - 8.sh)).fill()
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled, trackRect.width > 0 else { return false }
        let x = touch.location(in: self).x
        activeHandle = abs(x - position(for: selectedStart)) < abs(x - position(for: selectedEnd)) ? .start : .end
        sendActions(for: .editingDidBegin)
        moveHandle(to: time(at: x))
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        moveHandle(to: time(at: touch.location(in: self).x))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        activeHandle = nil
    }

    override func cancelTracking(with event: UIEvent?) {
        activeHandle = nil
    }

    private func time(at x: CGFloat) -> TimeInterval {
        Double(min(1, max(0, (x - trackRect.minX) / trackRect.width))) * duration
    }

    private func moveHandle(to time: TimeInterval) {
        let minimumLength = ClanSoundAudio.minDuration
        switch activeHandle {
        case .start: selectedStart = min(max(0, time), selectedEnd - minimumLength)
        case .end: selectedEnd = max(min(duration, time), selectedStart + minimumLength)
        case nil: return
        }
        updateLabels()
        setNeedsLayout()
        setNeedsDisplay()
        sendActions(for: .valueChanged)
    }

    private func updateLabels() {
        startLabel.text = ClanSoundAudio.timeLabel(selectedStart)
        endLabel.text = ClanSoundAudio.timeLabel(selectedEnd)
        startElement.accessibilityValue = startLabel.text
        endElement.accessibilityValue = endLabel.text
    }

    fileprivate func adjustHandle(isStart: Bool, forward: Bool) {
        guard isEnabled else { return }
        activeHandle = isStart ? .start : .end
        sendActions(for: .editingDidBegin)
        let time = isStart ? selectedStart : selectedEnd
        moveHandle(to: time + (forward ? 1 : -1))
        activeHandle = nil
    }
}

private final class TrimHandleElement: UIAccessibilityElement {
    private weak var owner: ClanSoundWaveformView?
    private let isStart: Bool

    init(owner: ClanSoundWaveformView, isStart: Bool) {
        self.owner = owner
        self.isStart = isStart
        super.init(accessibilityContainer: owner)
        accessibilityLabel = L(isStart ? L10n.ClanSetting.Sounds.start : L10n.ClanSetting.Sounds.end)
        accessibilityTraits = [.adjustable]
    }

    override func accessibilityIncrement() { owner?.adjustHandle(isStart: isStart, forward: true) }
    override func accessibilityDecrement() { owner?.adjustHandle(isStart: isStart, forward: false) }
}
