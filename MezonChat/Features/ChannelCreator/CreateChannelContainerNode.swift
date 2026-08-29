import UIKit
import AsyncDisplayKit

final class CreateChannelContainerNode: ASDisplayNode {

    private let onClose: () -> Void
    private let onCreate: (String, Int32, Bool) -> Void

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let nameField = UITextField()
    private let nameErrorLabel = UILabel()
    private var createBtn: UIButton!
    private let activityIndicator = UIActivityIndicatorView.mezonMedium()
    
    private let textTypeBtn = RadioButtonView()
    private let voiceTypeBtn = RadioButtonView()
    private let streamTypeBtn = RadioButtonView()
    private var selectedType: Int32 = MezonConstants.ChannelType.channel.rawValue
    
    private let privateSwitch = UISwitch()
    private let privateSection = UIView()

    init(
        onClose: @escaping () -> Void,
        onCreate: @escaping (String, Int32, Bool) -> Void
    ) {
        self.onClose = onClose
        self.onCreate = onCreate
        super.init()
        backgroundColor = UIColor.theme.primary
    }

    override func didLoad() {
        super.didLoad()
        setupUI()
    }

    private func setupUI() {
        let t = UIColor.theme

        let header = UIView()
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.sh),
        ])

        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage.mezonSystemImage("xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
        closeBtn.tintColor = t.textStrong
        closeBtn.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        header.addSubview(closeBtn)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            closeBtn.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16.sw),
            closeBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            closeBtn.widthAnchor.constraint(equalToConstant: 24.swh),
            closeBtn.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ChannelSetting.createChannel)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        createBtn = UIButton(type: .system)
        createBtn.setTitle(L(L10n.DirectMessage.create), for: .normal)
        createBtn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .medium)
        createBtn.addTarget(self, action: #selector(handleCreate), for: .touchUpInside)
        createBtn.isEnabled = false
        createBtn.tintColor = t.textDisabled
        header.addSubview(createBtn)
        createBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            createBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16.sw),
            createBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        header.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: createBtn.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: createBtn.centerYAnchor),
        ])

        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        stackView.axis = .vertical
        stackView.spacing = 20.sh
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw),
        ])

        let nameSection = createInputSection(title: L(L10n.ChannelSetting.channelName), input: nameField)
        nameField.attributedPlaceholder = NSAttributedString(
            string: L(L10n.ChannelSetting.channelNamePlaceholder),
            attributes: [
                .foregroundColor: UIColor.theme.textDisabled,
                .font: UIFont.systemFont(ofSize: 14.sf)
            ]
        )
        stackView.addArrangedSubview(nameSection)

        let typeSection = UIStackView()
        typeSection.axis = .vertical
        typeSection.spacing = 8.sh
        let typeLabel = UILabel()
        typeLabel.text = L(L10n.ChannelSetting.channelType)
        typeLabel.font = .systemFont(ofSize: 14.sf, weight: .bold)
        typeLabel.textColor = UIColor.theme.textStrong
        typeSection.addArrangedSubview(typeLabel)

        let typeGroup = UIView()
        typeGroup.backgroundColor = UIColor.theme.secondary
        typeGroup.layer.cornerRadius = 12
        typeGroup.clipsToBounds = true
        let typeStack = UIStackView()
        typeStack.axis = .vertical
        typeStack.spacing = 0
        typeGroup.addSubview(typeStack)
        typeStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            typeStack.topAnchor.constraint(equalTo: typeGroup.topAnchor),
            typeStack.leadingAnchor.constraint(equalTo: typeGroup.leadingAnchor),
            typeStack.trailingAnchor.constraint(equalTo: typeGroup.trailingAnchor),
            typeStack.bottomAnchor.constraint(equalTo: typeGroup.bottomAnchor)
        ])

        typeStack.addArrangedSubview(createTypeRow(
            btn: textTypeBtn,
            title: L(L10n.ChannelSetting.textChannel),
            desc: L(L10n.ChannelSetting.textChannelDesc),
            icon: "Channel/channel",
            type: MezonConstants.ChannelType.channel.rawValue
        ))
        let sep1 = UIView()
        sep1.backgroundColor = UIColor.theme.border
        sep1.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        typeStack.addArrangedSubview(sep1)
        typeStack.addArrangedSubview(createTypeRow(
            btn: voiceTypeBtn,
            title: L(L10n.ChannelSetting.voiceChannel),
            desc: L(L10n.ChannelSetting.voiceChannelDesc),
            icon: "Chat/SpeakerIcon",
            type: MezonConstants.ChannelType.mezonVoice.rawValue
        ))
        let sep2 = UIView()
        sep2.backgroundColor = UIColor.theme.border
        sep2.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        typeStack.addArrangedSubview(sep2)
        typeStack.addArrangedSubview(createTypeRow(
            btn: streamTypeBtn,
            title: L(L10n.ChannelSetting.streamChannel),
            desc: L(L10n.ChannelSetting.streamChannelDesc),
            icon: "Channel/channelStream",
            type: MezonConstants.ChannelType.streaming.rawValue
        ))
        
        typeSection.addArrangedSubview(typeGroup)
        stackView.addArrangedSubview(typeSection)

        privateSection.backgroundColor = UIColor.theme.secondary
        privateSection.layer.cornerRadius = 12
        
        let privateTitle = UILabel()
        privateTitle.text = L(L10n.ChannelSetting.privateChannel)
        privateTitle.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        privateTitle.textColor = UIColor.theme.textStrong
        
        let privateIcon = UIImageView(image: UIImage(named: "Channel/LockIcon")?.withRenderingMode(.alwaysTemplate))
        privateIcon.tintColor = UIColor.theme.textStrong
        privateIcon.contentMode = .scaleAspectFit
        
        privateSection.addSubview(privateIcon)
        privateSection.addSubview(privateTitle)
        privateSection.addSubview(privateSwitch)
        
        privateIcon.translatesAutoresizingMaskIntoConstraints = false
        privateTitle.translatesAutoresizingMaskIntoConstraints = false
        privateSwitch.translatesAutoresizingMaskIntoConstraints = false
        privateSwitch.onTintColor = .mezonLink
        
        NSLayoutConstraint.activate([
            privateSection.heightAnchor.constraint(equalToConstant: 60.sh),
            privateIcon.leadingAnchor.constraint(equalTo: privateSection.leadingAnchor, constant: 16.sw),
            privateIcon.centerYAnchor.constraint(equalTo: privateSection.centerYAnchor),
            privateIcon.widthAnchor.constraint(equalToConstant: 24.swh),
            privateIcon.heightAnchor.constraint(equalToConstant: 24.swh),
            privateTitle.leadingAnchor.constraint(equalTo: privateIcon.trailingAnchor, constant: 12.sw),
            privateTitle.centerYAnchor.constraint(equalTo: privateSection.centerYAnchor),
            privateSwitch.trailingAnchor.constraint(equalTo: privateSection.trailingAnchor, constant: -16.sw),
            privateSwitch.centerYAnchor.constraint(equalTo: privateSection.centerYAnchor)
        ])
        
        let privateContainer = UIStackView()
        privateContainer.axis = .vertical
        privateContainer.spacing = 8.sh
        privateContainer.addArrangedSubview(privateSection)
        
        let privateDesc = UILabel()
        privateDesc.text = L(L10n.ChannelSetting.privateChannelDesc)
        privateDesc.font = .systemFont(ofSize: 12.sf)
        privateDesc.textColor = UIColor.theme.textDisabled
        privateDesc.numberOfLines = 0
        privateContainer.addArrangedSubview(privateDesc)
        
        stackView.addArrangedSubview(privateContainer)

        updateTypeSelection()
    }

    private func createInputSection(title: String, input: UIView) -> UIView {
        let v = UIStackView()
        v.axis = .vertical
        v.spacing = 8.sh

        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 14.sf, weight: .bold)
        label.textColor = UIColor.theme.textStrong
        v.addArrangedSubview(label)

        input.backgroundColor = UIColor.theme.secondary
        input.layer.cornerRadius = 12
        if let tf = input as? UITextField {
            tf.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
            tf.leftViewMode = .always
            tf.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12.sw, height: 1))
            tf.rightViewMode = .always
            tf.textColor = UIColor.theme.textStrong
            tf.font = .systemFont(ofSize: 14.sf)
            tf.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
            tf.addTarget(self, action: #selector(handleNameChange), for: .editingChanged)
        }
        v.addArrangedSubview(input)

        nameErrorLabel.text = L(L10n.ChannelSetting.channelNameError)
        nameErrorLabel.font = .systemFont(ofSize: 12.sf)
        nameErrorLabel.textColor = .mezonError
        nameErrorLabel.numberOfLines = 0
        nameErrorLabel.isHidden = true
        v.addArrangedSubview(nameErrorLabel)

        return v
    }

    private func createTypeRow(btn: RadioButtonView, title: String, desc: String, icon: String, type: Int32) -> UIView {
        let container = UIView()
        container.heightAnchor.constraint(greaterThanOrEqualToConstant: 68.sh).isActive = true
        
        let iconView = UIImageView(image: UIImage(named: icon)?.withRenderingMode(.alwaysTemplate))
        iconView.tintColor = UIColor.theme.textStrong
        iconView.contentMode = .scaleAspectFit
        
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.spacing = 2
        let tLabel = UILabel()
        tLabel.text = title
        tLabel.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        tLabel.textColor = UIColor.theme.textStrong
        let dLabel = UILabel()
        dLabel.text = desc
        dLabel.font = .systemFont(ofSize: 12.sf)
        dLabel.textColor = UIColor.theme.textDisabled
        dLabel.numberOfLines = 0
        vStack.addArrangedSubview(tLabel)
        vStack.addArrangedSubview(dLabel)
        
        container.addSubview(iconView)
        container.addSubview(vStack)
        container.addSubview(btn)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        vStack.translatesAutoresizingMaskIntoConstraints = false
        btn.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16.sw),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.swh),
            iconView.heightAnchor.constraint(equalToConstant: 24.swh),
            
            vStack.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            vStack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            vStack.trailingAnchor.constraint(equalTo: btn.leadingAnchor, constant: -12.sw),
            
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16.sw),
            btn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            btn.widthAnchor.constraint(equalToConstant: 24.swh),
            btn.heightAnchor.constraint(equalToConstant: 24.swh)
        ])
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTypeSelect(_:)))
        container.addGestureRecognizer(tap)
        container.tag = Int(type)
        container.isUserInteractionEnabled = true
        
        return container
    }
    
    @objc private func handleTypeSelect(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view else { return }
        selectedType = Int32(view.tag)
        updateTypeSelection()
    }
    
    private func updateTypeSelection() {
        textTypeBtn.setSelected(selectedType == MezonConstants.ChannelType.channel.rawValue)
        voiceTypeBtn.setSelected(selectedType == MezonConstants.ChannelType.mezonVoice.rawValue)
        streamTypeBtn.setSelected(selectedType == MezonConstants.ChannelType.streaming.rawValue)
        
        if selectedType == MezonConstants.ChannelType.channel.rawValue {
            privateSection.superview?.isHidden = false
        } else {
            privateSection.superview?.isHidden = true
        }
    }

    private func isValidChannelName(_ name: String) -> Bool {
        if name.isEmpty { return false }
        if name.count > 64 { return false }
        let regex = "^(?![_\\-\\s])(?:(?!')[a-zA-Z0-9\\p{L}\\p{N}\\p{So}_\\-\\s]){1,64}$"
        return name.range(of: regex, options: .regularExpression) != nil
    }

    @objc private func handleNameChange() {
        let name = nameField.text ?? ""
        let isValid = isValidChannelName(name)
        let isPristine = name.isEmpty

        createBtn.isEnabled = isValid
        createBtn.tintColor = isValid ? .mezonLink : UIColor.theme.textDisabled
        
        nameErrorLabel.isHidden = isValid || isPristine
    }

    @objc private func handleClose() { onClose() }
    
    @objc private func handleCreate() { 
        let name = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !isValidChannelName(name) { return }
        onCreate(name, selectedType, privateSwitch.isOn) 
    }

    func applyTheme() {
        backgroundColor = UIColor.theme.primary
        activityIndicator.color = UIColor.theme.textStrong
    }

    func setLoading(_ isLoading: Bool) {
        if isLoading {
            createBtn.setTitle("", for: .normal)
            activityIndicator.startAnimating()
            createBtn.isEnabled = false
            view.isUserInteractionEnabled = false
        } else {
            createBtn.setTitle(L(L10n.DirectMessage.create), for: .normal)
            activityIndicator.stopAnimating()
            view.isUserInteractionEnabled = true
            handleNameChange()
        }
    }
}

private class RadioButtonView: UIView {
    private let inner = UIView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 12
        layer.borderWidth = 2
        
        inner.layer.cornerRadius = 7
        addSubview(inner)
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        inner.frame = CGRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
    }
    
    func setSelected(_ isSelected: Bool) {
        let accentColor = UIColor.mezonLink
        if isSelected {
            layer.borderColor = accentColor.cgColor
            backgroundColor = accentColor
            inner.backgroundColor = .white
            inner.isHidden = false
        } else {
            layer.borderColor = UIColor.theme.textStrong.withAlphaComponent(0.3).cgColor
            backgroundColor = .clear
            inner.isHidden = true
        }
    }
}
