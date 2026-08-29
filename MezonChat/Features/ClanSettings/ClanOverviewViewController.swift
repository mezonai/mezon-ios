import UIKit
import AsyncDisplayKit
import SwiftProtobuf

final class ClanOverviewViewController: BaseViewController {

    private let context: AccountContext
    private let clanId: Int64

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    private let headerView = UIView()
    private let backButton = UIButton(type: .system)
    private let headerTitleLabel = UILabel()
    private let saveButton = UIButton(type: .system)

    private let clanNameTextField = UITextField()
    private let nameErrorLabel = UILabel()
    private let avatarImageView = UIImageView()
    private let pickAvatarButton = UIButton(type: .system)
    private let cameraIcon = UIImageView(image: UIImage.mezonSystemImage("camera.fill"))
    private let changeAvatarLabel = UILabel()

    private let sysMsgChannelButton = UIButton(type: .system)
    private let sysMsgRandomWelcomeSwitch = UISwitch()
    private let sysMsgWelcomeStickerSwitch = UISwitch()
    private let sysMsgAuditLogSwitch = UISwitch()

    private let anonymousSwitch = UISwitch()

    private var selectedNotificationType: Int32 = 0
    private let notifAllButton = UIButton(type: .custom)
    private let notifMentionButton = UIButton(type: .custom)
    private let notifNoneButton = UIButton(type: .custom)

    private let deleteButton = UIButton(type: .system)

    private var isSaving = false
    private var selectedAvatarImage: UIImage?
    private var selectedAvatarData: Data? = nil {
        didSet { updateSaveButtonState() }
    }

    private var initialClanName: String = ""
    private var initialAnonymous: Bool = false
    private var initialSysMsg: Mezon_Api_SystemMessage?
    private var selectedSysMsgChannelId: Int64?
    private var initialNotificationType: Int32 = 0

    init(context: AccountContext, clanId: Int64) {
        self.context = context
        self.clanId = clanId
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = .mezonSecondary
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            loadClanData()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(clanDescDidUpdate(_:)), name: Notification.Name("MezonClanDescUpdated"), object: nil)
    }



    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func clanDescDidUpdate(_ notification: Notification) {
        if #available(iOS 13.0, *) {
            guard let userInfo = notification.userInfo,
                  let id = userInfo["clanId"] as? Int64,
                  id == self.clanId else { return }
        
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let clan = self.context.account.postbox.read({ tx in tx.getClan(id: self.clanId) }) else { return }
            
                let currentName = self.clanNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if currentName == self.initialClanName || currentName == clan.name {
                    self.clanNameTextField.text = clan.name
                    self.initialClanName = clan.name
                }
            
                if self.anonymousSwitch.isOn == self.initialAnonymous || self.anonymousSwitch.isOn == clan.preventsAnonymousMessages {
                    self.anonymousSwitch.isOn = clan.preventsAnonymousMessages
                    self.initialAnonymous = clan.preventsAnonymousMessages
                }
            
                if let d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                    if !d.banner.isEmpty, let url = URL(string: d.banner) {
                        if self.selectedAvatarData == nil {
                            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                                guard let data = data, let image = UIImage(data: data) else { return }
                                DispatchQueue.main.async {
                                    self?.avatarImageView.image = image
                                    self?.updateAvatarOverlay()
                                }
                            }.resume()
                        }
                    } else if self.selectedAvatarData == nil {
                        self.avatarImageView.image = nil
                        self.updateAvatarOverlay()
                    }
                }
            
                self.updateSaveButtonState()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func setupUI() {
        view.backgroundColor = .mezonSecondary
        
        setupHeader()
        
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        contentStack.axis = .vertical
        contentStack.spacing = 20.sh
        contentStack.alignment = .fill
        scrollView.addSubview(contentStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16.sh),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16.sw),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16.sw),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -40.sh),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32.sw),
        ])

        buildForm()
        updateNotificationUI()
        updateSaveButtonState()
    }

    private func setupHeader() {
        headerView.backgroundColor = .mezonSecondary
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        backButton.setImage(UIImage.mezonSystemImage("chevron.left")?.withRenderingMode(.alwaysTemplate), for: .normal)
        backButton.tintColor = UIColor.theme.textStrong
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        
        headerTitleLabel.text = L(L10n.ClanSetting.Overview.title)
        headerTitleLabel.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        headerTitleLabel.textColor = UIColor.theme.textStrong
        headerTitleLabel.textAlignment = .center

        saveButton.setTitle(L(L10n.ClanSetting.Overview.save), for: .normal)
        saveButton.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .bold)
        saveButton.setTitleColor(UIColor.theme.bgViolet, for: .normal)
        saveButton.setTitleColor(UIColor.theme.textDisabled, for: .disabled)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        [backButton, headerTitleLabel, saveButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            headerView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 50.sh),

            backButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8.sw),
            backButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44.swh),
            backButton.heightAnchor.constraint(equalToConstant: 44.swh),

            headerTitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            headerTitleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor)
        ])
    }

    private func buildForm() {
        let logoNameSection = buildLogoNameSection()
        contentStack.addArrangedSubview(logoNameSection)
        
        nameErrorLabel.text = L(L10n.Clan.invalidName)
        nameErrorLabel.font = .systemFont(ofSize: 12.sf)
        nameErrorLabel.textColor = .systemRed
        nameErrorLabel.numberOfLines = 0
        nameErrorLabel.isHidden = true
        contentStack.addArrangedSubview(nameErrorLabel)
        
        contentStack.setCustomSpacing(12.sh, after: logoNameSection)
        contentStack.setCustomSpacing(12.sh, after: nameErrorLabel)

        let sysMsgSection = buildSystemMessageSection()
        contentStack.addArrangedSubview(sysMsgSection)

        let anonSection = buildAnonymousSection()
        contentStack.addArrangedSubview(anonSection)

        let notifSection = buildNotificationSection()
        contentStack.addArrangedSubview(notifSection)

        let deleteSection = buildDeleteSection()
        contentStack.addArrangedSubview(deleteSection)
    }

    private func buildLogoNameSection() -> UIView {
        let container = UIView()
        
        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true
        avatarImageView.layer.cornerRadius = 12.swh
        avatarImageView.backgroundColor = UIColor.theme.primary
        
        cameraIcon.tintColor = UIColor.theme.textDisabled
        
        changeAvatarLabel.text = L(L10n.ClanSetting.Overview.chooseImage)
        changeAvatarLabel.font = .systemFont(ofSize: 13.sf)
        changeAvatarLabel.textColor = UIColor.theme.textDisabled
        
        pickAvatarButton.addTarget(self, action: #selector(pickAvatarTapped), for: .touchUpInside)
        
        let label = UILabel()
        label.text = L(L10n.ClanSetting.Overview.clanName)
        label.font = .systemFont(ofSize: 14.sf, weight: .bold)
        label.textColor = UIColor.theme.textStrong
        
        let inputContainer = UIView()
        inputContainer.backgroundColor = UIColor.theme.primary
        inputContainer.layer.cornerRadius = 12.swh
        
        clanNameTextField.font = .systemFont(ofSize: 15.sf)
        clanNameTextField.textColor = UIColor.theme.textStrong
        clanNameTextField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        
        [avatarImageView, cameraIcon, changeAvatarLabel, pickAvatarButton, label, inputContainer, clanNameTextField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            avatarImageView.topAnchor.constraint(equalTo: container.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            avatarImageView.heightAnchor.constraint(equalTo: avatarImageView.widthAnchor, multiplier: 9.0 / 16.0),
            
            cameraIcon.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            cameraIcon.centerYAnchor.constraint(equalTo: avatarImageView.centerYAnchor, constant: -12.sh),
            cameraIcon.widthAnchor.constraint(equalToConstant: 32.swh),
            cameraIcon.heightAnchor.constraint(equalToConstant: 32.swh),
            
            changeAvatarLabel.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            changeAvatarLabel.topAnchor.constraint(equalTo: cameraIcon.bottomAnchor, constant: 8.sh),
            
            pickAvatarButton.topAnchor.constraint(equalTo: avatarImageView.topAnchor),
            pickAvatarButton.leadingAnchor.constraint(equalTo: avatarImageView.leadingAnchor),
            pickAvatarButton.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor),
            pickAvatarButton.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor),
            
            label.topAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 24.sh),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            inputContainer.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8.sh),
            inputContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inputContainer.heightAnchor.constraint(equalToConstant: 48.sh),
            inputContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            clanNameTextField.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 16.sw),
            clanNameTextField.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -16.sw),
            clanNameTextField.centerYAnchor.constraint(equalTo: inputContainer.centerYAnchor)
        ])
        
        return container
    }

    private func buildSystemMessageSection() -> UIView {
        let container = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSetting.Overview.systemMessageTitle)
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        
        let bgView = UIView()
        bgView.backgroundColor = UIColor.theme.primary
        bgView.layer.cornerRadius = 12.swh
        
        let stack = UIStackView()
        stack.axis = .vertical
        
        let channelRow = createButtonRow(title: L(L10n.ClanSetting.Overview.systemMessageChannel), button: sysMsgChannelButton, showChevron: true)
        sysMsgChannelButton.addTarget(self, action: #selector(channelPickerTapped), for: .touchUpInside)
        
        let r1 = createSwitchRow(title: L(L10n.ClanSetting.Overview.systemMessageWelcomeRandom), toggle: sysMsgRandomWelcomeSwitch)
        let r2 = createSwitchRow(title: L(L10n.ClanSetting.Overview.systemMessageWelcomeSticker), toggle: sysMsgWelcomeStickerSwitch)
        let r3 = createSwitchRow(title: L(L10n.ClanSetting.Overview.systemMessageHideAuditLog), toggle: sysMsgAuditLogSwitch)
        
        sysMsgRandomWelcomeSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        sysMsgWelcomeStickerSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        sysMsgAuditLogSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        
        stack.addArrangedSubview(channelRow)
        stack.addArrangedSubview(createSeparator())
        stack.addArrangedSubview(r1)
        stack.addArrangedSubview(createSeparator())
        stack.addArrangedSubview(r2)
        stack.addArrangedSubview(createSeparator())
        stack.addArrangedSubview(r3)
        
        let descLabel = UILabel()
        descLabel.text = L(L10n.ClanSetting.Overview.systemMessageDescription)
        descLabel.font = .systemFont(ofSize: 13.sf)
        descLabel.textColor = UIColor.theme.textDisabled
        descLabel.numberOfLines = 0
        
        [titleLabel, bgView, stack, descLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            bgView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            bgView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            stack.topAnchor.constraint(equalTo: bgView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bgView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bgView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bgView.bottomAnchor),
            
            descLabel.topAnchor.constraint(equalTo: bgView.bottomAnchor, constant: 8.sh),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8.sw),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8.sw),
            descLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }

    private func buildAnonymousSection() -> UIView {
        let container = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSetting.Overview.anonymousTitle)
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        
        let bgView = UIView()
        bgView.backgroundColor = UIColor.theme.primary
        bgView.layer.cornerRadius = 12.swh
        
        let row = createSwitchRow(title: L(L10n.ClanSetting.Overview.anonymousDescription), toggle: anonymousSwitch)
        anonymousSwitch.addTarget(self, action: #selector(switchChanged), for: .valueChanged)
        
        [titleLabel, bgView, row].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            bgView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            bgView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bgView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            
            row.topAnchor.constraint(equalTo: bgView.topAnchor),
            row.leadingAnchor.constraint(equalTo: bgView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bgView.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bgView.bottomAnchor)
        ])
        
        return container
    }

    private func buildNotificationSection() -> UIView {
        let container = UIView()
        
        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSetting.Overview.defaultNotificationTitle)
        titleLabel.font = .systemFont(ofSize: 14.sf, weight: .bold)
        titleLabel.textColor = UIColor.theme.textStrong
        
        let bgView = UIView()
        bgView.backgroundColor = UIColor.theme.primary
        bgView.layer.cornerRadius = 12.swh
        
        let stack = UIStackView()
        stack.axis = .vertical
        
        let r1 = createCheckRow(title: L(L10n.ClanSetting.Overview.defaultNotificationAll), button: notifAllButton, tag: 1)
        let r2 = createCheckRow(title: L(L10n.ClanSetting.Overview.defaultNotificationMention), button: notifMentionButton, tag: 2)
        let r3 = createCheckRow(title: L(L10n.ClanSetting.Overview.defaultNotificationNone), button: notifNoneButton, tag: 3)
        
        stack.addArrangedSubview(r1)
        stack.addArrangedSubview(createSeparator())
        stack.addArrangedSubview(r2)
        stack.addArrangedSubview(createSeparator())
        stack.addArrangedSubview(r3)
        
        let descLabel = UILabel()
        descLabel.text = L(L10n.ClanSetting.Overview.defaultNotificationDescription)
        descLabel.font = .systemFont(ofSize: 13.sf)
        descLabel.textColor = UIColor.theme.textDisabled
        descLabel.numberOfLines = 0
        
        [titleLabel, bgView, stack, descLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            
            bgView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8.sh),
            bgView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bgView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            stack.topAnchor.constraint(equalTo: bgView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: bgView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bgView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bgView.bottomAnchor),
            
            descLabel.topAnchor.constraint(equalTo: bgView.bottomAnchor, constant: 8.sh),
            descLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8.sw),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8.sw),
            descLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }

    private func buildDeleteSection() -> UIView {
        let container = UIView()
        
        deleteButton.setTitle(L(L10n.ClanSetting.Overview.deleteClan), for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 15.sf, weight: .bold)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = .mezonError
        deleteButton.layer.cornerRadius = 12.swh
        deleteButton.addTarget(self, action: #selector(deleteClanTapped), for: .touchUpInside)
        
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            deleteButton.topAnchor.constraint(equalTo: container.topAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            deleteButton.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            deleteButton.heightAnchor.constraint(equalToConstant: 48.sh)
        ])
        
        return container
    }

    private func createSwitchRow(title: String, toggle: UISwitch) -> UIView {
        let row = UIView()
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52.sh).isActive = true
        
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15.sf)
        label.textColor = UIColor.theme.textStrong
        label.numberOfLines = 0
        
        toggle.onTintColor = UIColor.theme.bgViolet
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        [label, toggle].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            toggle.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16.sw),
            toggle.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16.sw),
            label.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -16.sw),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 12.sh),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12.sh)
        ])
        
        return row
    }
    
    private final class ButtonRowContainer: UIView {
        weak var targetButton: UIButton?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(tap)
        }
        
        required init?(coder: NSCoder) { fatalError() }
        
        @objc private func handleTap() {
            guard let button = targetButton, button.isEnabled else { return }
            button.sendActions(for: .touchUpInside)
        }
    }

    private func createButtonRow(title: String, button: UIButton, showChevron: Bool) -> UIView {
        let row = ButtonRowContainer()
        row.targetButton = button
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 52.sh).isActive = true
        
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15.sf)
        label.textColor = UIColor.theme.textStrong
        
        button.titleLabel?.font = .systemFont(ofSize: 15.sf)
        button.setTitleColor(UIColor.theme.textDisabled, for: .normal)
        button.contentHorizontalAlignment = .right
        button.isUserInteractionEnabled = false
        
        [label, button].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16.sw),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            
            button.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 16.sw),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: showChevron ? -32.sw : -16.sw),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.heightAnchor.constraint(equalTo: row.heightAnchor)
        ])
        
        if showChevron {
            let chevron = UIImageView(image: UIImage.mezonSystemImage("chevron.right")?.withRenderingMode(.alwaysTemplate))
            chevron.tintColor = UIColor.theme.textDisabled
            chevron.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16.sw),
                chevron.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                chevron.widthAnchor.constraint(equalToConstant: 12.swh),
                chevron.heightAnchor.constraint(equalToConstant: 16.swh)
            ])
        }
        
        return row
    }

    private func createCheckRow(title: String, button: UIButton, tag: Int) -> UIView {
        let row = UIView()
        row.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15.sf)
        label.textColor = UIColor.theme.textStrong
        
        button.tag = tag
        let symbolConfig = MezonSymbolConfiguration(pointSize: 22.swh, weight: .regular)
        button.setImage(UIImage.mezonSystemImage("circle", withConfiguration: symbolConfig)?.withRenderingMode(.alwaysTemplate), for: .normal)
        if #available(iOS 15.0, *) {
            let palette = UIImage.SymbolConfiguration(paletteColors: [.white, UIColor.theme.bgViolet])
            button.setImage(UIImage(systemName: "checkmark.circle.fill", withConfiguration: palette.applying(symbolConfig.uiKitConfiguration))?.withRenderingMode(.alwaysOriginal), for: .selected)
        } else {
            button.setImage(UIImage.mezonSystemImage("checkmark.circle.fill", withConfiguration: symbolConfig)?.withRenderingMode(.alwaysTemplate), for: .selected)
        }
        button.tintColor = UIColor.theme.textDisabled
        button.addTarget(self, action: #selector(notifTypeChanged(_:)), for: .touchUpInside)
        
        let tapBtn = UIButton(type: .custom)
        tapBtn.tag = tag
        tapBtn.addTarget(self, action: #selector(notifTypeChanged(_:)), for: .touchUpInside)
        
        [label, button, tapBtn].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview($0)
        }
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16.sw),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16.sw),
            button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 24.swh),
            button.heightAnchor.constraint(equalToConstant: 24.swh),
            
            tapBtn.topAnchor.constraint(equalTo: row.topAnchor),
            tapBtn.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            tapBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            tapBtn.bottomAnchor.constraint(equalTo: row.bottomAnchor)
        ])
        
        return row
    }

    private func createSeparator() -> UIView {
        let sep = UIView()
        sep.backgroundColor = UIColor.theme.borderDim
        sep.translatesAutoresizingMaskIntoConstraints = false
        
        let wrap = UIView()
        wrap.addSubview(sep)
        
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            sep.topAnchor.constraint(equalTo: wrap.topAnchor),
            sep.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
        return wrap
    }

    @available(iOS 13.0, *)
    private func loadClanData() {
        guard let clan = context.account.postbox.read({ tx in tx.getClan(id: clanId) }) else { return }
        self.initialClanName = clan.name
        self.initialAnonymous = clan.preventsAnonymousMessages
        
        clanNameTextField.text = clan.name
        anonymousSwitch.isOn = clan.preventsAnonymousMessages
        
        if let d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
            if !d.banner.isEmpty, let url = URL(string: d.banner) {
                URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                    guard let data = data, let image = UIImage(data: data) else { return }
                    DispatchQueue.main.async {
                        self?.avatarImageView.image = image
                        self?.updateAvatarOverlay()
                    }
                }.resume()
            } else {
                self.avatarImageView.image = nil
                self.updateAvatarOverlay()
            }
        }

        Task { [weak self] in
            guard let self, let token = await self.context.getToken() else { return }
            
            do {
                let msg = try await self.context.account.network.getSystemMessageByClanId(clanId: self.clanId, token: token)
                
                let notifRes = try? await self.context.account.network.getNotificationClan(clanId: self.clanId, token: token)
                let localNotifType = self.context.account.postbox.read({ tx in tx.getNotificationSetting(entityId: self.clanId)?.notificationSettingType })
                let notifTypeFetched = notifRes?.notificationSettingType ?? localNotifType ?? 1
                let notifType = notifTypeFetched == 0 ? 1 : notifTypeFetched
                
                await MainActor.run {
                    self.initialNotificationType = notifType
                    self.selectedNotificationType = notifType
                    self.updateNotificationUI()
                    self.initialSysMsg = msg
                    self.selectedSysMsgChannelId = msg.channelID
                    self.sysMsgRandomWelcomeSwitch.isOn = msg.welcomeRandom == "1"
                    self.sysMsgWelcomeStickerSwitch.isOn = msg.setupTips == "1"
                    self.sysMsgAuditLogSwitch.isOn = !msg.hideAuditLog
                    self.updateSysMsgChannelUI()
                    self.updateSaveButtonState()
                }
            } catch {
            }
        }
    }

    private func updateSaveButtonState() {
        let name = clanNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isInvalidFormat = !ClanCreationNameRules.isValid(name)
        
        if isSaving || isInvalidFormat {
            saveButton.isEnabled = false
            saveButton.alpha = 0.5
        } else {
            saveButton.isEnabled = true
            saveButton.alpha = 1.0
        }
    }

    private func updateAvatarOverlay() {
        let hasImage = avatarImageView.image != nil
        cameraIcon.isHidden = hasImage
        changeAvatarLabel.isHidden = hasImage
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func textFieldDidChange() {
        let name = (clanNameTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ClanCreationNameRules.isValid(name) {
            nameErrorLabel.isHidden = false
        } else {
            nameErrorLabel.isHidden = true
        }
        updateSaveButtonState()
    }
    
    @objc private func switchChanged() {
        updateSaveButtonState()
    }

    @objc private func notifTypeChanged(_ sender: UIButton) {
        selectedNotificationType = Int32(sender.tag)
        updateNotificationUI()
        updateSaveButtonState()
    }

    private func updateNotificationUI() {
        notifAllButton.isSelected = selectedNotificationType == 1
        notifMentionButton.isSelected = selectedNotificationType == 2
        notifNoneButton.isSelected = selectedNotificationType == 3
        notifAllButton.tintColor = notifAllButton.isSelected ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        notifMentionButton.tintColor = notifMentionButton.isSelected ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
        notifNoneButton.tintColor = notifNoneButton.isSelected ? UIColor.theme.bgViolet : UIColor.theme.textDisabled
    }

    @objc private func pickAvatarTapped() {
        if #available(iOS 13.0, *) {
            guard pickAvatarButton.isUserInteractionEnabled else { return }
            pickAvatarButton.isUserInteractionEnabled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.pickAvatarButton.isUserInteractionEnabled = true
            }
        
            guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return }
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.allowsEditing = true
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    private func updateSysMsgChannelUI() {
        guard let channelId = selectedSysMsgChannelId, channelId != 0 else {
            sysMsgChannelButton.setTitle(L(L10n.ClanSetting.Overview.systemMessageChannel), for: .normal)
            return
        }
        
        var channelName: String?
        var isPrivate = false
        
        let channelListKey = PreferencesKeys.channelList(clanId: clanId)
        if let data = context.account.postbox.getPreferenceData(key: channelListKey) {
            let allChannels = ChannelPreferenceListCodec.decode(data)
            if let ch = allChannels.first(where: { $0.channelID == channelId }) {
                channelName = ch.channelLabel
                isPrivate = ch.channelPrivate == 1
            }
        }
        
        if (channelName == nil || channelName?.isEmpty == true), let channel = context.account.postbox.read({ tx in tx.getChannelMeta(channelId: channelId) }) {
            channelName = channel.label
            isPrivate = channel.toProto().channelPrivate == 1
        }
        
        if let name = channelName, !name.isEmpty {
            let prefix = isPrivate ? "🔒 " : ""
            sysMsgChannelButton.setTitle("\(prefix)# \(name)", for: .normal)
        } else {
            sysMsgChannelButton.setTitle(L(L10n.ClanSetting.Overview.systemMessageChannel), for: .normal)
        }
    }

    @objc private func channelPickerTapped() {
        let vc = SysMsgSelectChannelViewController(
            context: context,
            clanId: clanId,
            currentChannelId: selectedSysMsgChannelId ?? 0
        ) { [weak self] selectedChannel in
            self?.selectedSysMsgChannelId = selectedChannel.channelID
            self?.updateSysMsgChannelUI()
            self?.updateSaveButtonState()
        }
        
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            vc.sheetPresentationController?.detents = [.medium(), .large()]
        }
        
        self.present(vc, animated: true)
    }

    @objc private func saveTapped() {
        if #available(iOS 13.0, *) {
            guard !isSaving else { return }
            isSaving = true
            updateSaveButtonState()

            let name = clanNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !ClanCreationNameRules.isValid(name) {
                Toast.error(L(L10n.Clan.invalidName))
                isSaving = false
                updateSaveButtonState()
                return
            }
        
            let isDuplicate = context.account.postbox.read({ tx -> Bool in
                let clans = tx.getClans()
                return clans.contains(where: { $0.id != self.clanId && $0.name.lowercased() == name.lowercased() })
            })
        
            if isDuplicate {
                Toast.error(L(L10n.Clan.duplicateName))
                isSaving = false
                updateSaveButtonState()
                return
            }

            Task { [weak self] in
                guard let self else { return }
                defer {
                    self.isSaving = false
                    self.updateSaveButtonState()
                }
                guard let token = await self.context.getToken() else { return }

                guard let clan = self.context.account.postbox.read({ tx in tx.getClan(id: self.clanId) }) else { return }
            
                let currentName = self.clanNameTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let isNameChanged = currentName != clan.name
                let isAvatarChanged = self.selectedAvatarData != nil
                let isAnonymousChanged = self.anonymousSwitch.isOn != clan.preventsAnonymousMessages
                let isNotifChanged = self.selectedNotificationType != self.initialNotificationType
            
                var isSysMsgChanged = false
                if let msg = self.initialSysMsg {
                    isSysMsgChanged = (self.sysMsgRandomWelcomeSwitch.isOn ? "1" : "0") != msg.welcomeRandom ||
                                      (self.sysMsgWelcomeStickerSwitch.isOn ? "1" : "0") != msg.setupTips ||
                                      (!self.sysMsgAuditLogSwitch.isOn) != msg.hideAuditLog ||
                                      (self.selectedSysMsgChannelId ?? 0) != msg.channelID
                } else {
                    isSysMsgChanged = self.sysMsgRandomWelcomeSwitch.isOn || self.sysMsgWelcomeStickerSwitch.isOn || self.sysMsgAuditLogSwitch.isOn || (self.selectedSysMsgChannelId ?? 0) != 0
                }
            
                if isNameChanged || isAvatarChanged || isAnonymousChanged {
                    var req = Mezon_Api_UpdateClanDescRequest()
                    req.clanID = self.clanId
                    req.clanName = name
                    req.preventAnonymous = self.anonymousSwitch.isOn
                    req.logo = SwiftProtobuf.Google_Protobuf_StringValue(clan.icon ?? "")
                
                    if let d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                        req.banner = SwiftProtobuf.Google_Protobuf_StringValue(d.banner)
                        req.status = d.status
                        req.isOnboarding = SwiftProtobuf.Google_Protobuf_BoolValue(d.isOnboarding)
                        req.welcomeChannelID = d.welcomeChannelID
                        req.onboardingBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.onboardingBanner)
                        req.isCommunity = SwiftProtobuf.Google_Protobuf_BoolValue(d.isCommunity)
                        req.communityBanner = SwiftProtobuf.Google_Protobuf_StringValue(d.communityBanner)
                    }
                
                    var bannerUrlToSave: String? = nil
                    if let data = self.selectedAvatarData {
                        let uploadInfo = try await self.context.account.network.uploadAttachmentFile(
                            filename: "banner.jpg",
                            filetype: "image/jpeg",
                            size: data.count,
                            width: Int(self.selectedAvatarImage?.size.width ?? 0),
                            height: Int(self.selectedAvatarImage?.size.height ?? 0),
                            token: token
                        )
                        try await self.context.account.network.uploadToMinIO(
                            url: uploadInfo.url,
                            data: data,
                            contentType: "image/jpeg"
                        )
                        bannerUrlToSave = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                    }
                    if let b = bannerUrlToSave {
                        req.banner = SwiftProtobuf.Google_Protobuf_StringValue(b)
                    }
                
                    do {
                        try await self.context.account.network.updateClanDesc(request: req, token: token)
                    
                        if var d = try? Mezon_Api_ClanDesc(serializedBytes: clan.data) {
                            d.clanName = req.clanName
                            d.preventAnonymous = req.preventAnonymous
                            if !req.logo.value.isEmpty {
                                d.logo = req.logo.value
                            }
                            if let b = bannerUrlToSave {
                                d.banner = b
                            }
                            let updatedClan = ClanRecord(
                                id: clan.id,
                                name: req.clanName,
                                icon: clan.icon,
                                ownerId: clan.ownerId,
                                data: try d.serializedData()
                            )
                            self.context.account.postbox.writeSync { tx in
                                tx.updateClans([updatedClan])
                            }
                        }
                    } catch {
                        await MainActor.run { Toast.error("ClanDesc error: \(error.localizedDescription)") }
                        return
                    }
                }
                
                if isSysMsgChanged {
                    var sysReq = Mezon_Api_SystemMessageRequest()
                    sysReq.clanID = self.clanId
                    sysReq.welcomeRandom = self.sysMsgRandomWelcomeSwitch.isOn ? "1" : "0"
                    sysReq.setupTips = self.sysMsgWelcomeStickerSwitch.isOn ? "1" : "0"
                    sysReq.welcomeSticker = self.initialSysMsg?.welcomeSticker ?? ""
                    sysReq.hideAuditLog = !self.sysMsgAuditLogSwitch.isOn
                    sysReq.channelID = self.selectedSysMsgChannelId ?? 0
                    sysReq.boostMessage = self.initialSysMsg?.boostMessage ?? ""
                
                    do {
                        try await self.context.account.network.updateSystemMessage(request: sysReq, token: token)
                    } catch {
                        await MainActor.run { Toast.error("SysMsg error: \(error.localizedDescription)") }
                        return
                    }
                }
            
                if isNotifChanged {
                    do {
                        try await self.context.account.network.setDefaultNotificationClan(clanId: self.clanId, notificationType: self.selectedNotificationType, token: token)
                        self.context.account.postbox.writeSync { tx in
                            let existing = tx.getNotificationSetting(entityId: self.clanId)
                            let newSetting = NotificationSettingRecord(
                                id: existing?.id ?? self.clanId,
                                entityId: self.clanId,
                                scope: .clan,
                                notificationSettingType: self.selectedNotificationType,
                                timeMuteSeconds: existing?.timeMuteSeconds ?? 0,
                                active: existing?.active ?? 1
                            )
                            tx.updateNotificationSetting(newSetting)
                        }
                    } catch {
                        await MainActor.run { Toast.error("Notif error: \(error.localizedDescription)") }
                        return
                    }
                }
            
                await MainActor.run {
                    Toast.success(L(L10n.ClanSetting.Overview.saveSuccess))
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }

    @objc private func deleteClanTapped() {
        if #available(iOS 13.0, *) {
            MezonConfirm.present(
                from: self,
                title: L(L10n.ClanSetting.Overview.deleteClanConfirmTitle),
                content: L(L10n.ClanSetting.Overview.deleteClanConfirmMessage),
                confirmTitle: L(L10n.Common.delete),
                isDanger: true,
                onConfirm: { [weak self] in
                    guard let self else { return }
                    Task {
                        guard let token = await self.context.getToken() else { return }
                        do {
                            try await self.context.account.network.deleteClanDesc(clanId: self.clanId, token: token)
                        
                            await MainActor.run {
                                if let root = self.navigationController as? MezonRootController {
                                    root.homeController?.clanListVC.removeClanAndSelectNext(removedClanId: self.clanId)
                                }
                            
                                let nextClanId = self.context.currentClanId
                                if nextClanId != 0 {
                                    NotificationCenter.default.post(
                                        name: .mezonQRSelectClan,
                                        object: nil,
                                        userInfo: ["clanId": "\(nextClanId)"]
                                    )
                                } else {
                                    self.navigationController?.popToRootViewController(animated: true)
                                }
                            }
                        } catch {
                            await MainActor.run {
                                Toast.error(L(L10n.ClanSetting.Overview.saveError))
                            }
                        }
                    }
                }
            )
        }
    }
}

extension ClanOverviewViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image else { return }
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            
            let maxSize = 10 * 1024 * 1024 
            if data.count > maxSize {
                Toast.error(L(L10n.ClanSetting.Overview.uploadFileTooLarge10MB))
                return
            }

            self.selectedAvatarImage = image
            self.selectedAvatarData = data
            self.avatarImageView.image = image
            self.updateAvatarOverlay()
            self.updateSaveButtonState()
        }
    }
}
final class SysMsgSelectChannelViewController: BaseViewController {
    private let context: AccountContext
    private let clanId: Int64
    private let currentChannelId: Int64
    private let onSelect: (Mezon_Api_ChannelDescription) -> Void
    private var channels: [Mezon_Api_ChannelDescription] = []

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(context: AccountContext, clanId: Int64, currentChannelId: Int64, onSelect: @escaping (Mezon_Api_ChannelDescription) -> Void) {
        self.context = context
        self.clanId = clanId
        self.currentChannelId = currentChannelId
        self.onSelect = onSelect
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder: NSCoder) { fatalError() }

    override func setupUI() {
        displayNode.backgroundColor = UIColor.theme.secondary
        let t = UIColor.theme
        
        let grabber = UIView()
        grabber.backgroundColor = t.textDisabled
        grabber.layer.cornerRadius = 2.5
        grabber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.topAnchor.constraint(equalTo: view.topAnchor, constant: 8.sh),
            grabber.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grabber.widthAnchor.constraint(equalToConstant: 36.sw),
            grabber.heightAnchor.constraint(equalToConstant: 5.sh)
        ])

        let header = UIView()
        view.addSubview(header)
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16.sh),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 44.sh),
        ])

        let titleLabel = UILabel()
        titleLabel.text = L(L10n.ClanSetting.Overview.systemMessageChannel)
        titleLabel.font = .systemFont(ofSize: 17.sf, weight: .bold)
        titleLabel.textColor = t.textStrong
        header.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
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
        stackView.spacing = 0
        scrollView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 16.sh),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16.sw),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16.sw),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -16.sh),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -32.sw),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(handleGlobalNavigation), name: .mezonNavigateToChannel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGlobalNavigation), name: .mezonQRSelectClan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGlobalNavigation), name: .mezonQRNavigateToDM, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleGlobalNavigation), name: .mezonIncomingPeerCall, object: nil)

        loadChannels()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleGlobalNavigation() {
        dismiss(animated: false)
    }

    private func loadChannels() {
        let postbox = context.account.postbox
        let channelListKey = PreferencesKeys.channelList(clanId: clanId)
        if let data = postbox.getPreferenceData(key: channelListKey) {
            let allChannels = ChannelPreferenceListCodec.decode(data)
            channels = allChannels.filter { ($0.type == 1 || $0.type == 9) && $0.channelPrivate != 1 }
        }

        buildChannelRows()
    }

    private func buildChannelRows() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if channels.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "Danh sách rỗng"
            emptyLabel.font = .systemFont(ofSize: 15.sf)
            emptyLabel.textColor = UIColor.theme.textDisabled
            emptyLabel.textAlignment = .center
            stackView.addArrangedSubview(emptyLabel)
            emptyLabel.translatesAutoresizingMaskIntoConstraints = false
            emptyLabel.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
            return
        }

        let container = UIView()
        container.backgroundColor = UIColor.theme.primary
        container.layer.cornerRadius = 12
        container.clipsToBounds = true

        let innerStack = UIStackView()
        innerStack.axis = .vertical
        innerStack.spacing = 0
        container.addSubview(innerStack)
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            innerStack.topAnchor.constraint(equalTo: container.topAnchor),
            innerStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            innerStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            innerStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        for (idx, channel) in channels.enumerated() {
            let row = createChannelRow(channel: channel)
            innerStack.addArrangedSubview(row)
            if idx < channels.count - 1 {
                let sep = UIView()
                sep.backgroundColor = UIColor.theme.borderDim
                innerStack.addArrangedSubview(sep)
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            }
        }

        stackView.addArrangedSubview(container)
    }

    private func createChannelRow(channel: Mezon_Api_ChannelDescription) -> UIView {
        let button = ChannelRowButton(type: .system)
        button.backgroundColor = .clear
        button.channel = channel
        button.addTarget(self, action: #selector(handleChannelTap(_:)), for: .touchUpInside)

        let iconName = channel.channelListIconAssetName()
        let hashIcon = UIImageView(image: (UIImage(named: iconName) ?? UIImage.mezonSystemImage(iconName))?.withRenderingMode(.alwaysTemplate))
        hashIcon.tintColor = UIColor.theme.textDisabled
        hashIcon.contentMode = .scaleAspectFit
        button.addSubview(hashIcon)
        hashIcon.translatesAutoresizingMaskIntoConstraints = false
        
        let label = UILabel()
        label.text = channel.channelLabel
        label.font = .systemFont(ofSize: 15.sf, weight: .medium)
        label.textColor = UIColor.theme.textStrong
        label.isUserInteractionEnabled = false
        button.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            hashIcon.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 16.sw),
            hashIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hashIcon.widthAnchor.constraint(equalToConstant: 18.swh),
            hashIcon.heightAnchor.constraint(equalToConstant: 18.swh),
            
            label.leadingAnchor.constraint(equalTo: hashIcon.trailingAnchor, constant: 8.sw),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -40.sw),
        ])
        
        if channel.channelID == currentChannelId {
            let checkIcon = UIImageView(image: UIImage.mezonSystemImage("checkmark")?.withRenderingMode(.alwaysTemplate))
            checkIcon.tintColor = UIColor.theme.bgViolet
            button.addSubview(checkIcon)
            checkIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                checkIcon.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -16.sw),
                checkIcon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                checkIcon.widthAnchor.constraint(equalToConstant: 20.swh),
                checkIcon.heightAnchor.constraint(equalToConstant: 20.swh),
            ])
        }

        button.heightAnchor.constraint(equalToConstant: 52.sh).isActive = true
        return button
    }

    @objc private func handleChannelTap(_ sender: ChannelRowButton) {
        guard let channel = sender.channel else { return }
        onSelect(channel)
        dismiss(animated: true)
    }
}

private final class ChannelRowButton: UIButton {
    var channel: Mezon_Api_ChannelDescription?
}
