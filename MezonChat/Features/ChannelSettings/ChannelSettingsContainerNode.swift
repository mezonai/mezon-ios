import UIKit
import AsyncDisplayKit

final class ChannelSettingsContainerNode: ASDisplayNode {

    private let onClose: () -> Void
    private let onSave: (String, String) -> Void

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let nameField = UITextField()
    private let topicView = UITextView()
    private var saveBtn: UIButton!
    private let initialName: String

    init(channelName: String, channelTopic: String, onClose: @escaping () -> Void, onSave: @escaping (String, String) -> Void) {
        self.initialName = channelName
        self.onClose = onClose
        self.onSave = onSave
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

        // Header
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

        // Content
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

        // Inputs
        stackView.addArrangedSubview(createInputSection(title: L(L10n.Channel.name), input: nameField))
        stackView.addArrangedSubview(createInputSection(title: L(L10n.Channel.topic), input: topicView, isTextArea: true))

        // Actions Group 1
        let group1 = createGroup(actions: [
            .init(title: L(L10n.ChannelSetting.changeCategory), icon: "ClanSetting/AuditLog"),
            .init(title: L(L10n.ChannelSetting.permissions), icon: "ChannelSetting/ChannelPermission"),
            .init(title: L(L10n.ChannelSetting.quickAction), icon: "ChannelSetting/QuickActionIcon"),
            .init(title: L(L10n.ChannelSetting.banList), icon: "ChannelSetting/BanIcon"),
        ])
        stackView.addArrangedSubview(group1)

        let footerLabel = UILabel()
        footerLabel.text = L(L10n.ChannelSetting.privacyFooter)
        footerLabel.font = .systemFont(ofSize: 12.sf)
        footerLabel.textColor = t.textDisabled
        footerLabel.numberOfLines = 0
        stackView.addArrangedSubview(footerLabel)

        // Actions Group 2
        let group2 = createGroup(actions: [
            .init(title: L(L10n.ChannelSetting.webhook), icon: "ChannelSetting/WebhookIcon"),
        ])
        stackView.addArrangedSubview(group2)

        // Delete Row
        let deleteBtn = createActionRow(title: L(L10n.Channel.delete), icon: "ChannelSetting/DeleteIcon", isDestructive: true)
        deleteBtn.backgroundColor = .mezonBorder
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
        }

        return v
    }

    @objc private func handleNameChange() {
        let isChanged = nameField.text != initialName && !(nameField.text?.isEmpty ?? true)
        saveBtn.isEnabled = isChanged
        saveBtn.tintColor = isChanged ? .mezonLink : UIColor.theme.textDisabled
    }

    private func createGroup(actions: [SettingAction]) -> UIView {
        let v = UIView()
        v.backgroundColor = .mezonBorder
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
            let row = createActionRow(title: action.title, icon: action.icon)
            stack.addArrangedSubview(row)
            if idx < actions.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.tertiary
                stack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
            }
        }
        return v
    }

    private func createActionRow(title: String, icon: String, isDestructive: Bool = false) -> UIView {
        let v = UIButton(type: .system)
        v.backgroundColor = .clear

        let iconView = UIImageView()
        iconView.image = UIImage(named: icon)?.withRenderingMode(isDestructive ? .alwaysTemplate : .alwaysOriginal)
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = isDestructive ? .mezonError : UIColor.theme.textStrong
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
            let arrow = UIImageView(image: UIImage(named: "Channel/ChevronRight"))
            arrow.tintColor = UIColor.theme.textDisabled
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
    }
}
