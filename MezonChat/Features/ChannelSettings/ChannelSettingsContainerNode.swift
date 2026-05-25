import UIKit
import AsyncDisplayKit

final class ChannelSettingsContainerNode: ASDisplayNode {

    private let onClose: () -> Void
    private let onSave: (String, String) -> Void
    private let onPermissionsTap: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let nameField = UITextField()
    private let nameErrorLabel = UILabel()
    private let topicView = UITextView()
    private var saveBtn: UIButton!
    private let initialName: String

    init(
        channelName: String,
        channelTopic: String,
        onClose: @escaping () -> Void,
        onSave: @escaping (String, String) -> Void,
        onPermissionsTap: (() -> Void)? = nil
    ) {
        self.initialName = channelName
        self.onClose = onClose
        self.onSave = onSave
        self.onPermissionsTap = onPermissionsTap
        super.init()
        backgroundColor = UIColor.theme.primary

        nameField.text = channelName
        topicView.text = channelTopic
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
        closeBtn.setImage(UIImage(systemName: "xmark")?.withRenderingMode(.alwaysTemplate), for: .normal)
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
        titleLabel.text = L(L10n.Channel.settings)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        saveBtn = UIButton(type: .system)
        saveBtn.setTitle("Save", for: .normal)
        saveBtn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .medium)
        saveBtn.addTarget(self, action: #selector(handleSave), for: .touchUpInside)
        saveBtn.isEnabled = false
        saveBtn.tintColor = t.textDisabled
        header.addSubview(saveBtn)
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            saveBtn.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16.sw),
            saveBtn.centerYAnchor.constraint(equalTo: header.centerYAnchor),
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


        stackView.addArrangedSubview(createInputSection(title: L(L10n.Channel.name), input: nameField))
        stackView.addArrangedSubview(createInputSection(title: L(L10n.Channel.topic), input: topicView, isTextArea: true))


        let group1 = createGroup(actions: [
            .init(title: L(L10n.ChannelSetting.changeCategory), icon: "ClanSetting/AuditLog", action: nil),
            .init(title: L(L10n.ChannelSetting.permissions), icon: "ChannelSetting/ChannelPermission", action: { [weak self] in
                self?.onPermissionsTap?()
            }),
            .init(title: L(L10n.ChannelSetting.quickAction), icon: "ChannelSetting/QuickActionIcon", action: nil),
            .init(title: L(L10n.ChannelSetting.banList), icon: "ChannelSetting/BanIcon", action: nil),
        ])
        stackView.addArrangedSubview(group1)

        let footerLabel = UILabel()
        footerLabel.text = L(L10n.ChannelSetting.privacyFooter)
        footerLabel.font = .systemFont(ofSize: 12.sf)
        footerLabel.textColor = t.textDisabled
        footerLabel.numberOfLines = 0
        stackView.addArrangedSubview(footerLabel)


        let group2 = createGroup(actions: [
            .init(title: L(L10n.ChannelSetting.webhook), icon: "ChannelSetting/WebhookIcon", action: nil),
        ])
        stackView.addArrangedSubview(group2)


        let deleteBtn = createActionRow(title: L(L10n.Channel.delete), icon: "ChannelSetting/DeleteIcon", isDestructive: true)
        deleteBtn.backgroundColor = UIColor.theme.secondary
        deleteBtn.layer.cornerRadius = 12
        stackView.addArrangedSubview(deleteBtn)
    }

    private func createInputSection(title: String, input: UIView, isTextArea: Bool = false) -> UIView {
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
            tf.font = .systemFont(ofSize: 16.sf)
            tf.heightAnchor.constraint(equalToConstant: 48.sh).isActive = true
        } else if let tv = input as? UITextView {
            tv.textContainerInset = UIEdgeInsets(top: 12.sh, left: 12.sw, bottom: 12.sh, right: 12.sw)
            tv.textColor = UIColor.theme.textStrong
            tv.font = .systemFont(ofSize: 16.sf)
            tv.heightAnchor.constraint(equalToConstant: 150.sh).isActive = true
            tv.isScrollEnabled = false
        }
        v.addArrangedSubview(input)

        if input === nameField {
            nameField.addTarget(self, action: #selector(handleNameChange), for: .editingChanged)
            
            nameErrorLabel.text = L(L10n.ChannelSetting.channelNameError)
            nameErrorLabel.font = .systemFont(ofSize: 12.sf)
            nameErrorLabel.textColor = .mezonError
            nameErrorLabel.numberOfLines = 0
            nameErrorLabel.isHidden = true
            v.addArrangedSubview(nameErrorLabel)
        }

        return v
    }

    private func isValidChannelName(_ name: String) -> Bool {
        if name.isEmpty { return false }
        if name.count > 64 { return false }
        let regex = "^(?![_\\-\\s])(?:(?!')[a-zA-Z0-9\\p{L}\\p{N}\\p{So}_\\-\\s]){1,64}$"
        return name.range(of: regex, options: .regularExpression) != nil
    }

    @objc private func handleNameChange() {
        let text = nameField.text ?? ""
        let isValid = isValidChannelName(text)
        let isPristine = text.isEmpty
        let isChanged = text != initialName && !isPristine
        
        saveBtn.isEnabled = isChanged && isValid
        saveBtn.tintColor = (isChanged && isValid) ? .mezonLink : UIColor.theme.textDisabled
        nameErrorLabel.isHidden = isValid || isPristine
    }

    private func createGroup(actions: [SettingAction]) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.theme.secondary
        v.layer.cornerRadius = 12
        v.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        v.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: v.topAnchor),
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])

        for (idx, action) in actions.enumerated() {
            let row = createActionRow(title: action.title, icon: action.icon, tapHandler: action.action)
            stack.addArrangedSubview(row)
            if idx < actions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.border
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }
        return v
    }

    private func createActionRow(title: String, icon: String, isDestructive: Bool = false, tapHandler: (() -> Void)? = nil) -> UIView {
        let v = ActionRowButton(type: .system)
        v.backgroundColor = .clear
        v.tapHandler = tapHandler
        v.addTarget(v, action: #selector(ActionRowButton.handleTap), for: .touchUpInside)

        let iconView = UIImageView()
        iconView.image = UIImage(named: icon)?.withRenderingMode(.alwaysTemplate)
        iconView.contentMode = .scaleAspectFit
        if isDestructive {
            iconView.tintColor = .mezonError
        } else {
            iconView.tintColor = .mezonTextPrimary
        }
        v.addSubview(iconView)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 16.sw),
            iconView.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24.swh),
            iconView.heightAnchor.constraint(equalToConstant: 24.swh),
        ])

        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 14.sf, weight: .medium)
        l.textColor = isDestructive ? .mezonError : UIColor.theme.textStrong
        v.addSubview(l)
        l.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12.sw),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])

        if !isDestructive {
            let arrowImage =
                UIImage(named: "Channel/ChevronRight")?.withRenderingMode(.alwaysTemplate)
                ?? UIImage(systemName: "chevron.right")?.withRenderingMode(.alwaysTemplate)
            let arrow = UIImageView(image: arrowImage)
            arrow.tintColor = UIColor.theme.textStrong
            v.addSubview(arrow)
            arrow.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                arrow.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -16.sw),
                arrow.centerYAnchor.constraint(equalTo: v.centerYAnchor),
                arrow.widthAnchor.constraint(equalToConstant: 16.swh),
                arrow.heightAnchor.constraint(equalToConstant: 16.swh),
            ])
        }

        v.heightAnchor.constraint(equalToConstant: 60.sh).isActive = true
        return v
    }

    @objc private func handleClose() { onClose() }
    @objc private func handleSave() { onSave(nameField.text ?? "", topicView.text ?? "") }

    func applyTheme() {
        backgroundColor = UIColor.theme.primary
    }

    private struct SettingAction {
        let title: String
        let icon: String
        let action: (() -> Void)?
    }
}

private final class ActionRowButton: UIButton {
    var tapHandler: (() -> Void)?
    @objc func handleTap() { tapHandler?() }
}
