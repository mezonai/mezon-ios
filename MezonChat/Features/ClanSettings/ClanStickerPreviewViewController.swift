import UIKit
import AVFoundation

final class ClanStickerPreviewViewController: UIViewController, AVAudioPlayerDelegate {

    var onConfirm: ((String, Bool) -> Void)?

    private let previewImage: UIImage
    private let soundData: Data?
    private var audioPlayer: AVAudioPlayer?

    private var isSoundSticker: Bool {
        soundData != nil
    }

    private lazy var backdropView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleDismiss))
        view.addGestureRecognizer(tap)
        return view
    }()

    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 10
        view.clipsToBounds = true
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15.sf, weight: .bold)
        label.text = isSoundSticker
            ? L(L10n.ClanSetting.SoundStickers.previewTitle)
            : L(L10n.ClanSetting.Stickers.previewTitle)
        return label
    }()

    private lazy var imagePreviewView: UIImageView = {
        let view = UIImageView(image: previewImage)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        if isSoundSticker {
            view.image = UIImage(systemName: "play.fill")
            view.isUserInteractionEnabled = true
            view.layer.cornerRadius = 20.swh
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handlePlayTapped)))
        }
        return view
    }()

    private lazy var nameTitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15.sf, weight: .bold)
        label.text = isSoundSticker
            ? L(L10n.ClanSetting.SoundStickers.previewNameLabel)
            : L(L10n.ClanSetting.Stickers.previewNameLabel)
        return label
    }()

    private lazy var nameTextField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.font = .systemFont(ofSize: 15.sf)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.layer.cornerRadius = 6
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
        field.leftViewMode = .always
        field.addTarget(self, action: #selector(nameTextChanged), for: .editingChanged)
        return field
    }()

    private lazy var errorLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12.sf)
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    private lazy var forSaleSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.isOn = false
        return toggle
    }()

    private lazy var forSaleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15.sf, weight: .bold)
        label.text = L(L10n.ClanSetting.Stickers.previewForSale)
        return label
    }()

    private lazy var uploadButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(
            isSoundSticker
                ? L(L10n.ClanSetting.SoundStickers.previewUpload)
                : L(L10n.ClanSetting.Stickers.previewUpload),
            for: .normal
        )
        button.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 30.sh
        button.clipsToBounds = true
        button.addTarget(self, action: #selector(handleUploadTapped), for: .touchUpInside)
        return button
    }()

    init(image: UIImage) {
        self.previewImage = image
        self.soundData = nil
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    init(soundData: Data) {
        self.previewImage = UIImage(systemName: "play.fill") ?? UIImage()
        self.soundData = soundData
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        let prefix = isSoundSticker ? "sound" : "sticker"
        nameTextField.text = "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000))"
        setupLayout()
        applyTheme()
    }

    private func setupLayout() {
        view.addSubview(backdropView)
        view.addSubview(containerView)

        let forSaleRow = UIStackView(arrangedSubviews: [forSaleSwitch, forSaleLabel])
        forSaleRow.translatesAutoresizingMaskIntoConstraints = false
        forSaleRow.axis = .horizontal
        forSaleRow.alignment = .center
        forSaleRow.spacing = 10.sw

        var contentViews: [UIView] = [titleLabel, imagePreviewView, nameTitleLabel, nameTextField, errorLabel]
        if !isSoundSticker {
            contentViews.append(forSaleRow)
        }
        contentViews.append(uploadButton)
        contentViews.forEach {
            containerView.addSubview($0)
        }

        var constraints = [
            backdropView.topAnchor.constraint(equalTo: view.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20.sh),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20.sw),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20.sw),

            imagePreviewView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14.sh),
            imagePreviewView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20.sw),
            imagePreviewView.widthAnchor.constraint(equalToConstant: 40.swh),
            imagePreviewView.heightAnchor.constraint(equalToConstant: 40.swh),

            nameTitleLabel.topAnchor.constraint(equalTo: imagePreviewView.bottomAnchor, constant: 14.sh),
            nameTitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameTitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            nameTextField.topAnchor.constraint(equalTo: nameTitleLabel.bottomAnchor, constant: 12.sh),
            nameTextField.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameTextField.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            nameTextField.heightAnchor.constraint(equalToConstant: 40.sh),

            errorLabel.topAnchor.constraint(equalTo: nameTextField.bottomAnchor, constant: 6.sh),
            errorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: 4.sw),
            errorLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            uploadButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 20.sw),
            uploadButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -20.sw),
            uploadButton.heightAnchor.constraint(equalToConstant: 44.sh),
            uploadButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -20.sh)
        ]
        if isSoundSticker {
            constraints.append(uploadButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16.sh))
        } else {
            constraints.append(contentsOf: [
                forSaleRow.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 14.sh),
                forSaleRow.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                uploadButton.topAnchor.constraint(equalTo: forSaleRow.bottomAnchor, constant: 16.sh)
            ])
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func applyTheme() {
        let theme = UIColor.theme
        containerView.backgroundColor = theme.secondary
        titleLabel.textColor = theme.textStrong
        nameTitleLabel.textColor = theme.textStrong
        forSaleLabel.textColor = theme.textStrong
        nameTextField.backgroundColor = theme.primary
        nameTextField.textColor = theme.text
        errorLabel.textColor = .systemRed
        uploadButton.backgroundColor = theme.bgViolet
        forSaleSwitch.onTintColor = theme.bgViolet
        if isSoundSticker {
            imagePreviewView.tintColor = theme.bgViolet
            imagePreviewView.backgroundColor = theme.primary
        }
    }

    @objc private func handleDismiss() {
        audioPlayer?.stop()
        dismiss(animated: true)
    }

    @objc private func handlePlayTapped() {
        guard let soundData else { return }
        if audioPlayer?.isPlaying == true {
            audioPlayer?.pause()
            updateSoundPreviewIcon(isPlaying: false)
            return
        }
        do {
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(data: soundData)
                audioPlayer?.delegate = self
            }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            audioPlayer?.play()
            updateSoundPreviewIcon(isPlaying: true)
        } catch {
            updateSoundPreviewIcon(isPlaying: false)
        }
    }

    private func updateSoundPreviewIcon(isPlaying: Bool) {
        imagePreviewView.image = UIImage(systemName: isPlaying ? "pause.fill" : "play.fill")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        updateSoundPreviewIcon(isPlaying: false)
    }

    @objc private func nameTextChanged() {
        errorLabel.isHidden = true
    }

    @objc private func handleUploadTapped() {
        let name = ClanStickerNameValidator.normalized(nameTextField.text ?? "")
        guard ClanStickerNameValidator.isValidForPreview(name) else {
            errorLabel.text = String(
                format: L(
                    isSoundSticker
                        ? L10n.ClanSetting.SoundStickers.previewLengthError
                        : L10n.ClanSetting.Stickers.previewLengthError
                ),
                L(
                    isSoundSticker
                        ? L10n.ClanSetting.SoundStickers.previewTypeSound
                        : L10n.ClanSetting.Stickers.previewTypeSticker
                ),
                ClanStickerNameValidator.minLength,
                ClanStickerNameValidator.previewMaxLength
            )
            errorLabel.isHidden = false
            return
        }
        errorLabel.isHidden = true
        if isSoundSticker {
            audioPlayer?.stop()
            updateSoundPreviewIcon(isPlaying: false)
        }
        onConfirm?(name, !isSoundSticker && forSaleSwitch.isOn)
    }
}
