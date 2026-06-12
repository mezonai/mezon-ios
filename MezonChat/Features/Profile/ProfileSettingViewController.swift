import UIKit
import PhotosUI
import SwiftProtobuf

enum ProfileSettingTab: Int {
    case userProfile = 0
    case clanProfile = 1
}

private let kMaxAvatarBytes = 10 * 1024 * 1024
private let kMaxDMIconBytes  = 1 * 1024 * 1024
private let kAboutMeMaxChars = 128
private let kDisplayNameMaxChars = 32
private let kMezonLogoURL = "https://cdn.mezon.ai/images/mezon_logo.png"

final class ProfileSettingViewController: BaseViewController {

    private let context: AccountContext
    private let initialTab: ProfileSettingTab

    private var currentTab: ProfileSettingTab = .userProfile

    private var userDisplayName: String = ""
    private var userAvatarUrl: String = ""
    private var userAboutMe: String = ""
    private var userName: String = ""
    private var userDmLogoUrl: String = ""
    private var initialUserDisplayName: String = ""
    private var initialUserAvatarUrl: String = ""
    private var initialUserAboutMe: String = ""
    private var initialUserDmLogoUrl: String = ""

    private var clanNickname: String = ""
    private var clanAvatarUrl: String = ""
    private var clanUserName: String = ""
    private var isDuplicateNickname: Bool = false

    private var clans: [Mezon_Api_ClanDesc] = []
    private var selectedClan: Mezon_Api_ClanDesc?
    private var clanProfile: Mezon_Api_ClanProfile?

    private var isSaving = false
    private var isUploading = false {
        didSet { updateSaveButtonState() }
    }

    private enum AvatarTarget { case userAvatar, clanAvatar, dmIcon }
    private var pendingAvatarTarget: AvatarTarget = .userAvatar

    private let headerView = UIView()

    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        btn.setImage(img, for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let saveButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 16.sf, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let tabContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 22.swh
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let userTabButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let clanTabButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.titleLabel?.font = .systemFont(ofSize: 14.sf, weight: .semibold)
        btn.layer.cornerRadius = 20.swh
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    private let contentStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 0
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let bannerView = UIView()
    private let bannerColorView: UIView = {
        let v = UIView()
        v.backgroundColor = .outgoingBubble
        return v
    }()

    private let avatarSize: CGFloat = 90.swh

    private let avatarContainerView: UIView = {
        let v = UIView()
        v.clipsToBounds = true
        return v
    }()
    private let avatarImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        return iv
    }()
    private let avatarPlaceholderLabel: UILabel = {
        let l = UILabel()
        l.textAlignment = .center
        l.textColor = .white
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.5
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let avatarSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    private let detailCard = UIView()
    private let detailContentStack: UIStackView = {
        let s = UIStackView()
        s.axis = .vertical
        s.alignment = .fill
        s.distribution = .fill
        s.spacing = 0
        s.isLayoutMarginsRelativeArrangement = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()
    private let detailNameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18.sf, weight: .bold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let detailUsernameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let displayNameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let displayNameField: UITextField = {
        let tf = UITextField()
        tf.font = .systemFont(ofSize: 15.sf)
        tf.borderStyle = .none
        tf.translatesAutoresizingMaskIntoConstraints = false
        return tf
    }()
    private let displayNameFieldContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12.swh
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let displayNameClearButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16))
        btn.setImage(img, for: .normal)
        btn.tintColor = .mezonTextPrimary
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let aboutMeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let aboutMeTextView: UITextView = {
        let tv = UITextView()
        tv.font = .systemFont(ofSize: 15.sf)
        tv.isScrollEnabled = false
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 24, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    private let aboutMeContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 12.swh
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let aboutMeCountLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11.sf)
        l.textAlignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let clanSelectorView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let clanSelectorAvatar: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 14.swh
        iv.backgroundColor = .outgoingBubble
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let clanSelectorNameLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16.sf, weight: .medium)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let clanSelectorChevron: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    
    private let noClanStateView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()
    private let noClanImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let noClanTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 22.sf, weight: .bold)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let noClanDescLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15.sf)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let createClanButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 12.swh
        btn.clipsToBounds = true
        btn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let joinClanButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.layer.cornerRadius = 12.swh
        btn.clipsToBounds = true
        btn.titleLabel?.font = .systemFont(ofSize: 17.sf, weight: .semibold)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()

    private let nicknameErrorLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 12.sf)
        l.textColor = .systemRed
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        return l
    }()

    private let dmIconSection: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let dmIconLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13.sf, weight: .semibold)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let dmIconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 25.swh
        iv.isUserInteractionEnabled = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()
    private let dmIconSpinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.hidesWhenStopped = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()
    private let dmIconRemoveButton: UIButton = {
        let btn = UIButton(type: .system)
        let img = UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .bold))
        btn.setImage(img, for: .normal)
        btn.tintColor = .systemRed
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 10
        btn.clipsToBounds = true
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        return btn
    }()

    private let loadingOverlay: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        v.isHidden = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(context: AccountContext, initialTab: ProfileSettingTab = .userProfile) {
        self.context = context
        self.initialTab = initialTab
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setupUI() {
        view.addSubview(headerView)
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(closeButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(saveButton)

        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)

        view.addSubview(tabContainer)
        tabContainer.addSubview(userTabButton)
        tabContainer.addSubview(clanTabButton)
        userTabButton.addTarget(self, action: #selector(userTabTapped), for: .touchUpInside)
        clanTabButton.addTarget(self, action: #selector(clanTabTapped), for: .touchUpInside)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        setupBanner()
        setupDetailCard()
        setupDMIconSection()
        setupNoClanState()

        view.addSubview(loadingOverlay)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(spinner)

        let headerHeight: CGFloat = 96
        let tabHeight: CGFloat = 48.sh

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: headerHeight),

            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16.sw),
            closeButton.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8.sh),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            saveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16.sw),
            saveButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),

            tabContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4.sh),
            tabContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16.sw),
            tabContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16.sw),
            tabContainer.heightAnchor.constraint(equalToConstant: tabHeight),

            userTabButton.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 4),
            userTabButton.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -4),
            userTabButton.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 4),
            userTabButton.trailingAnchor.constraint(equalTo: tabContainer.centerXAnchor, constant: -2),

            clanTabButton.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 4),
            clanTabButton.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -4),
            clanTabButton.leadingAnchor.constraint(equalTo: tabContainer.centerXAnchor, constant: 2),
            clanTabButton.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -4),

            scrollView.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 4.sh),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            loadingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
        ])

        displayNameField.delegate = self
        displayNameField.addTarget(self, action: #selector(displayNameFieldChanged), for: .editingChanged)
        displayNameClearButton.addTarget(self, action: #selector(clearDisplayName), for: .touchUpInside)

        currentTab = initialTab
        loadInitialData()
    }

    override func applyTheme() {
        view.backgroundColor = .mezonSecondaryBackground
        headerView.backgroundColor = .mezonSecondaryBackground
        scrollView.backgroundColor = .mezonSecondaryBackground
        closeButton.tintColor = .mezonTextPrimary
        titleLabel.textColor = .mezonTextStrong
        saveButton.setTitleColor(.outgoingBubble, for: .normal)

        tabContainer.backgroundColor = .mezonPrimary
        updateTabAppearance()

        applyBannerTintForCurrentAvatarState()
        avatarContainerView.layer.borderColor = UIColor.mezonSecondaryBackground.cgColor

        detailCard.backgroundColor = .mezonPrimary
        detailCard.layer.borderColor = UIColor.mezonBorder.cgColor
        detailNameLabel.textColor = .mezonTextStrong
        detailUsernameLabel.textColor = .mezonTextPrimary
        avatarPlaceholderLabel.font = .systemFont(ofSize: avatarSize * 0.36, weight: .semibold)
        avatarPlaceholderLabel.textColor = .white

        displayNameLabel.textColor = .mezonTextPrimary
        displayNameFieldContainer.backgroundColor = .mezonSecondaryBackground
        displayNameField.textColor = .mezonTextStrong

        aboutMeLabel.textColor = .mezonTextPrimary
        aboutMeContainer.backgroundColor = .mezonSecondaryBackground
        aboutMeTextView.backgroundColor = .clear
        aboutMeTextView.textColor = .mezonTextStrong
        aboutMeCountLabel.textColor = .mezonTextPrimary
        displayNameClearButton.tintColor = .mezonTextPrimary

        clanSelectorView.backgroundColor = .clear
        clanSelectorNameLabel.textColor = .mezonTextStrong
        clanSelectorChevron.tintColor = .mezonTextSecondary

        dmIconSection.backgroundColor = .mezonPrimary
        dmIconLabel.textColor = .mezonTextStrong

        titleLabel.text = L(L10n.ProfileSetting.title)
        saveButton.setTitle(L(L10n.ProfileSetting.save), for: .normal)
        userTabButton.setTitle(L(L10n.ProfileSetting.userProfile), for: .normal)
        clanTabButton.setTitle(L(L10n.ProfileSetting.clanProfiles), for: .normal)
        if currentTab == .userProfile {
            displayNameLabel.text = L(L10n.ProfileSetting.displayName)
            aboutMeLabel.text = L(L10n.ProfileSetting.aboutMe)
        } else {
            displayNameLabel.text = L(L10n.ProfileSetting.clanNickname)
        }
        dmIconLabel.text = L(L10n.ProfileSetting.directMessageIcon)
        noClanTitleLabel.text = L(L10n.ProfileSetting.noClanTitle)
        noClanDescLabel.text = L(L10n.ProfileSetting.noClanDesc)
        createClanButton.setTitle(L(L10n.ProfileSetting.noClanCreateClan), for: .normal)
        joinClanButton.setTitle(L(L10n.ProfileSetting.noClanJoinClan), for: .normal)
        noClanImageView.image = UIImage(named: "Profile/EmptyClanIcon")

        noClanStateView.backgroundColor = .clear
        noClanTitleLabel.textColor = .mezonTextStrong
        noClanDescLabel.textColor = .mezonTextPrimary
        createClanButton.backgroundColor = .outgoingBubble
        createClanButton.setTitleColor(.white, for: .normal)
        joinClanButton.backgroundColor = .darkGray
        joinClanButton.setTitleColor(.white, for: .normal)
        updateClanNicknamePlaceholderAppearance()
    }

    private func setupBanner() {
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(bannerView)

        bannerColorView.translatesAutoresizingMaskIntoConstraints = false
        bannerView.addSubview(bannerColorView)

        avatarContainerView.layer.cornerRadius = avatarSize / 2
        avatarContainerView.layer.borderWidth = 3
        avatarContainerView.translatesAutoresizingMaskIntoConstraints = false
        avatarContainerView.isUserInteractionEnabled = true
        bannerView.addSubview(avatarContainerView)

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.layer.cornerRadius = avatarSize / 2
        avatarContainerView.addSubview(avatarImageView)
        avatarContainerView.addSubview(avatarPlaceholderLabel)
        avatarContainerView.addSubview(avatarSpinner)

        let avatarTap = UITapGestureRecognizer(target: self, action: #selector(avatarTapped))
        avatarContainerView.addGestureRecognizer(avatarTap)

        let bannerHeight = avatarSize * 2
        NSLayoutConstraint.activate([
            bannerView.heightAnchor.constraint(equalToConstant: bannerHeight),

            bannerColorView.topAnchor.constraint(equalTo: bannerView.topAnchor),
            bannerColorView.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor),
            bannerColorView.trailingAnchor.constraint(equalTo: bannerView.trailingAnchor),
            bannerColorView.bottomAnchor.constraint(equalTo: avatarContainerView.centerYAnchor),

            avatarContainerView.leadingAnchor.constraint(equalTo: bannerView.leadingAnchor, constant: 16.sw),
            avatarContainerView.bottomAnchor.constraint(equalTo: bannerView.bottomAnchor),
            avatarContainerView.widthAnchor.constraint(equalToConstant: avatarSize),
            avatarContainerView.heightAnchor.constraint(equalToConstant: avatarSize),

            avatarImageView.topAnchor.constraint(equalTo: avatarContainerView.topAnchor),
            avatarImageView.leadingAnchor.constraint(equalTo: avatarContainerView.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: avatarContainerView.trailingAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: avatarContainerView.bottomAnchor),

            avatarPlaceholderLabel.topAnchor.constraint(equalTo: avatarContainerView.topAnchor),
            avatarPlaceholderLabel.leadingAnchor.constraint(equalTo: avatarContainerView.leadingAnchor),
            avatarPlaceholderLabel.trailingAnchor.constraint(equalTo: avatarContainerView.trailingAnchor),
            avatarPlaceholderLabel.bottomAnchor.constraint(equalTo: avatarContainerView.bottomAnchor),

            avatarSpinner.centerXAnchor.constraint(equalTo: avatarContainerView.centerXAnchor),
            avatarSpinner.centerYAnchor.constraint(equalTo: avatarContainerView.centerYAnchor),
        ])
    }

    private func setupDetailCard() {
        detailCard.layer.cornerRadius = 14.swh
        detailCard.layer.borderWidth = 1
        detailCard.clipsToBounds = true
        detailCard.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(detailCard)

        let inset = UIEdgeInsets(top: 16.sh, left: 16.sw, bottom: 16.sh, right: 16.sw)
        detailContentStack.layoutMargins = inset
        detailCard.addSubview(detailContentStack)

        detailContentStack.addArrangedSubview(detailNameLabel)
        detailContentStack.addArrangedSubview(detailUsernameLabel)
        detailContentStack.addArrangedSubview(displayNameLabel)
        detailContentStack.addArrangedSubview(displayNameFieldContainer)
        detailContentStack.addArrangedSubview(nicknameErrorLabel)
        detailContentStack.addArrangedSubview(aboutMeLabel)
        detailContentStack.addArrangedSubview(aboutMeContainer)

        displayNameFieldContainer.addSubview(displayNameField)
        displayNameFieldContainer.addSubview(displayNameClearButton)
        aboutMeContainer.addSubview(aboutMeTextView)
        aboutMeContainer.addSubview(aboutMeCountLabel)

        contentStack.setCustomSpacing(16.sh, after: bannerView)

        NSLayoutConstraint.activate([
            detailCard.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 16.sw),
            detailCard.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -16.sw),

            detailContentStack.topAnchor.constraint(equalTo: detailCard.topAnchor),
            detailContentStack.leadingAnchor.constraint(equalTo: detailCard.leadingAnchor),
            detailContentStack.trailingAnchor.constraint(equalTo: detailCard.trailingAnchor),
            detailContentStack.bottomAnchor.constraint(equalTo: detailCard.bottomAnchor),

            displayNameFieldContainer.heightAnchor.constraint(equalToConstant: 48.sh),

            displayNameField.topAnchor.constraint(equalTo: displayNameFieldContainer.topAnchor),
            displayNameField.leadingAnchor.constraint(equalTo: displayNameFieldContainer.leadingAnchor, constant: 12.sw),
            displayNameField.trailingAnchor.constraint(equalTo: displayNameClearButton.leadingAnchor, constant: -4),
            displayNameField.bottomAnchor.constraint(equalTo: displayNameFieldContainer.bottomAnchor),

            displayNameClearButton.trailingAnchor.constraint(equalTo: displayNameFieldContainer.trailingAnchor, constant: -8),
            displayNameClearButton.centerYAnchor.constraint(equalTo: displayNameFieldContainer.centerYAnchor),
            displayNameClearButton.widthAnchor.constraint(equalToConstant: 30),
            displayNameClearButton.heightAnchor.constraint(equalToConstant: 30),

            aboutMeTextView.topAnchor.constraint(equalTo: aboutMeContainer.topAnchor),
            aboutMeTextView.leadingAnchor.constraint(equalTo: aboutMeContainer.leadingAnchor),
            aboutMeTextView.trailingAnchor.constraint(equalTo: aboutMeContainer.trailingAnchor),
            aboutMeTextView.bottomAnchor.constraint(equalTo: aboutMeContainer.bottomAnchor),
            aboutMeTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100.sh),

            aboutMeCountLabel.trailingAnchor.constraint(equalTo: aboutMeContainer.trailingAnchor, constant: -12),
            aboutMeCountLabel.bottomAnchor.constraint(equalTo: aboutMeContainer.bottomAnchor, constant: -6),
        ])

        detailContentStack.setCustomSpacing(2.sh, after: detailNameLabel)
        detailContentStack.setCustomSpacing(16.sh, after: detailUsernameLabel)
        detailContentStack.setCustomSpacing(8.sh, after: displayNameLabel)
        detailContentStack.setCustomSpacing(8.sh, after: aboutMeLabel)

        aboutMeTextView.delegate = self
    }

    private func setupDMIconSection() {
        dmIconSection.layer.cornerRadius = 14.swh
        dmIconSection.layer.borderWidth = 1
        dmIconSection.layer.borderColor = UIColor.mezonBorder.cgColor
        dmIconSection.clipsToBounds = true

        contentStack.addArrangedSubview(dmIconSection)
        contentStack.setCustomSpacing(16.sh, after: detailCard)

        dmIconSection.addSubview(dmIconLabel)
        dmIconSection.addSubview(dmIconImageView)
        dmIconSection.addSubview(dmIconRemoveButton)
        dmIconImageView.addSubview(dmIconSpinner)

        let dmTap = UITapGestureRecognizer(target: self, action: #selector(dmIconTapped))
        dmIconImageView.addGestureRecognizer(dmTap)
        dmIconRemoveButton.addTarget(self, action: #selector(removeDMIconTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            dmIconSection.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor, constant: 16.sw),
            dmIconSection.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor, constant: -16.sw),
            dmIconSection.heightAnchor.constraint(equalToConstant: 72.sh),

            dmIconLabel.leadingAnchor.constraint(equalTo: dmIconSection.leadingAnchor, constant: 16.sw),
            dmIconLabel.centerYAnchor.constraint(equalTo: dmIconSection.centerYAnchor),

            dmIconImageView.trailingAnchor.constraint(equalTo: dmIconSection.trailingAnchor, constant: -16.sw),
            dmIconImageView.centerYAnchor.constraint(equalTo: dmIconSection.centerYAnchor),
            dmIconImageView.widthAnchor.constraint(equalToConstant: 50.swh),
            dmIconImageView.heightAnchor.constraint(equalToConstant: 50.swh),

            dmIconSpinner.centerXAnchor.constraint(equalTo: dmIconImageView.centerXAnchor),
            dmIconSpinner.centerYAnchor.constraint(equalTo: dmIconImageView.centerYAnchor),

            dmIconRemoveButton.topAnchor.constraint(equalTo: dmIconImageView.topAnchor, constant: -6),
            dmIconRemoveButton.trailingAnchor.constraint(equalTo: dmIconImageView.trailingAnchor, constant: 6),
            dmIconRemoveButton.widthAnchor.constraint(equalToConstant: 20),
            dmIconRemoveButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(spacer)
        spacer.heightAnchor.constraint(equalToConstant: 40.sh).isActive = true

        setupClanSelector()
    }

    private func setupClanSelector() {
        clanSelectorView.isHidden = true
        contentStack.insertArrangedSubview(clanSelectorView, at: 0)

        clanSelectorView.addSubview(clanSelectorAvatar)
        clanSelectorView.addSubview(clanSelectorNameLabel)
        clanSelectorView.addSubview(clanSelectorChevron)

        let tap = UITapGestureRecognizer(target: self, action: #selector(clanSelectorTapped))
        clanSelectorView.addGestureRecognizer(tap)

        NSLayoutConstraint.activate([
            clanSelectorView.heightAnchor.constraint(equalToConstant: 56.sh),
            clanSelectorAvatar.leadingAnchor.constraint(equalTo: clanSelectorView.leadingAnchor, constant: 16.sw),
            clanSelectorAvatar.centerYAnchor.constraint(equalTo: clanSelectorView.centerYAnchor),
            clanSelectorAvatar.widthAnchor.constraint(equalToConstant: 28.swh),
            clanSelectorAvatar.heightAnchor.constraint(equalToConstant: 28.swh),
            clanSelectorNameLabel.leadingAnchor.constraint(equalTo: clanSelectorAvatar.trailingAnchor, constant: 12.sw),
            clanSelectorNameLabel.centerYAnchor.constraint(equalTo: clanSelectorView.centerYAnchor),
            clanSelectorChevron.trailingAnchor.constraint(equalTo: clanSelectorView.trailingAnchor, constant: -16.sw),
            clanSelectorChevron.centerYAnchor.constraint(equalTo: clanSelectorView.centerYAnchor),
            clanSelectorChevron.widthAnchor.constraint(equalToConstant: 14),
            clanSelectorChevron.heightAnchor.constraint(equalToConstant: 14),
        ])
    }
    
    private func setupNoClanState() {
        contentStack.addArrangedSubview(noClanStateView)
        contentStack.setCustomSpacing(16.sh, after: noClanStateView)
        
        noClanStateView.addSubview(noClanImageView)
        noClanStateView.addSubview(noClanTitleLabel)
        noClanStateView.addSubview(noClanDescLabel)
        noClanStateView.addSubview(createClanButton)
        noClanStateView.addSubview(joinClanButton)
        
        createClanButton.addTarget(self, action: #selector(createClanTapped), for: .touchUpInside)
        joinClanButton.addTarget(self, action: #selector(joinClanTapped), for: .touchUpInside)
        
        NSLayoutConstraint.activate([
            noClanStateView.leadingAnchor.constraint(equalTo: contentStack.leadingAnchor),
            noClanStateView.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            
            noClanImageView.topAnchor.constraint(equalTo: noClanStateView.topAnchor, constant: 40.sh),
            noClanImageView.centerXAnchor.constraint(equalTo: noClanStateView.centerXAnchor),
            noClanImageView.widthAnchor.constraint(equalToConstant: 120.swh),
            noClanImageView.heightAnchor.constraint(equalToConstant: 120.swh),
            
            noClanTitleLabel.topAnchor.constraint(equalTo: noClanImageView.bottomAnchor, constant: 24.sh),
            noClanTitleLabel.leadingAnchor.constraint(equalTo: noClanStateView.leadingAnchor, constant: 16.sw),
            noClanTitleLabel.trailingAnchor.constraint(equalTo: noClanStateView.trailingAnchor, constant: -16.sw),
            
            noClanDescLabel.topAnchor.constraint(equalTo: noClanTitleLabel.bottomAnchor, constant: 8.sh),
            noClanDescLabel.leadingAnchor.constraint(equalTo: noClanStateView.leadingAnchor, constant: 24.sw),
            noClanDescLabel.trailingAnchor.constraint(equalTo: noClanStateView.trailingAnchor, constant: -24.sw),
            
            createClanButton.topAnchor.constraint(equalTo: noClanDescLabel.bottomAnchor, constant: 28.sh),
            createClanButton.leadingAnchor.constraint(equalTo: noClanStateView.leadingAnchor, constant: 16.sw),
            createClanButton.trailingAnchor.constraint(equalTo: noClanStateView.trailingAnchor, constant: -16.sw),
            createClanButton.heightAnchor.constraint(equalToConstant: 44.sh),
            
            joinClanButton.topAnchor.constraint(equalTo: createClanButton.bottomAnchor, constant: 12.sh),
            joinClanButton.leadingAnchor.constraint(equalTo: noClanStateView.leadingAnchor, constant: 16.sw),
            joinClanButton.trailingAnchor.constraint(equalTo: noClanStateView.trailingAnchor, constant: -16.sw),
            joinClanButton.heightAnchor.constraint(equalToConstant: 44.sh),
            joinClanButton.bottomAnchor.constraint(equalTo: noClanStateView.bottomAnchor, constant: -24.sh),
        ])
    }

    private func loadInitialData() {
        guard let user = context.currentUser else { return }
        userName = user.username
        let rawDisplayName = user.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawUsername = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        userDisplayName = (rawDisplayName.isEmpty || rawDisplayName == rawUsername) ? "" : user.displayName
        userAvatarUrl = user.avatarURL?.absoluteString ?? ""
        userAboutMe = user.bio ?? ""
        initialUserDisplayName = userDisplayName
        initialUserAvatarUrl = userAvatarUrl
        initialUserAboutMe = userAboutMe
        initialUserDmLogoUrl = userDmLogoUrl

        loadDmLogo()
        loadClans()
        switchToTab(currentTab, animated: false)
    }

    private func loadDmLogo() {
        if let cachedData = context.account.postbox.getPreferenceData(key: PreferencesKeys.account),
           let cachedAccount = try? Mezon_Api_Account(serializedData: cachedData),
           !cachedAccount.logo.isEmpty {
            userDmLogoUrl = cachedAccount.logo
            initialUserDmLogoUrl = userDmLogoUrl
            refreshDMIcon()
            return
        }
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let apiAccount = try await context.account.network.getAccount(token: token)
                userDmLogoUrl = apiAccount.logo
                initialUserDmLogoUrl = userDmLogoUrl
                refreshDMIcon()
            } catch {}
        }
    }

    private func loadClans() {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            do {
                let fetchedClans = try await context.account.network.listClanDescs(token: token)
                self.clans = fetchedClans
                if self.selectedClan == nil, !fetchedClans.isEmpty {
                    let currentId = context.currentClanId
                    self.selectedClan = fetchedClans.first(where: { $0.clanID == currentId }) ?? fetchedClans.first
                    await loadClanProfile()
                }
                if currentTab == .clanProfile { refreshContent() }
            } catch {
            }
        }
    }

    private func loadClanProfile() async {
        guard let clan = selectedClan,
              let token = await context.getToken() else { return }
        do {
            let profile = try await context.account.network.getUserProfileOnClan(clanId: clan.clanID, token: token)
            self.clanProfile = profile
            self.clanNickname = profile.nickName
            self.clanAvatarUrl = profile.avatar.isEmpty ? userAvatarUrl : profile.avatar
            self.clanUserName = userName
            refreshContent()
        } catch {
        }
    }

    private func switchToTab(_ tab: ProfileSettingTab, animated: Bool = true) {
        currentTab = tab
        updateTabAppearance()
        refreshContent()
    }

    private func updateTabAppearance() {
        let selectedBg = UIColor.outgoingBubble
        let normalBg = UIColor.clear
        if currentTab == .userProfile {
            userTabButton.backgroundColor = selectedBg
            userTabButton.setTitleColor(.white, for: .normal)
            clanTabButton.backgroundColor = normalBg
            clanTabButton.setTitleColor(.mezonTextPrimary, for: .normal)
        } else {
            userTabButton.backgroundColor = normalBg
            userTabButton.setTitleColor(.mezonTextPrimary, for: .normal)
            clanTabButton.backgroundColor = selectedBg
            clanTabButton.setTitleColor(.white, for: .normal)
        }
    }

    private func refreshContent() {
        let isUser = currentTab == .userProfile
        let showNoClanState = !isUser && clans.isEmpty
        
        noClanStateView.isHidden = !showNoClanState
        bannerView.isHidden = showNoClanState
        detailCard.isHidden = showNoClanState
        dmIconSection.isHidden = showNoClanState

        clanSelectorView.isHidden = isUser
        aboutMeLabel.isHidden = !isUser
        aboutMeContainer.isHidden = !isUser
        dmIconSection.isHidden = !isUser
        nicknameErrorLabel.isHidden = isUser || !isDuplicateNickname

        if showNoClanState {
            clanSelectorView.isHidden = true
            return
        }

        if isUser {
            displayNameLabel.text = L(L10n.ProfileSetting.displayName)
            detailNameLabel.text = userDisplayName.isEmpty ? userName : userDisplayName
            detailUsernameLabel.text = userName
            displayNameField.text = userDisplayName
            aboutMeTextView.text = userAboutMe
            updateAboutMeCount()
            loadAvatarImage(urlString: userAvatarUrl)
            refreshDMIcon()
        } else {
            displayNameLabel.text = L(L10n.ProfileSetting.clanNickname)
            let displayText = clanNickname
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? clanNicknamePreviewWhenEmpty() : clanNickname
            detailNameLabel.text = displayText
            detailUsernameLabel.text = clanUserName
            displayNameField.text = clanNickname
            nicknameErrorLabel.text = L(L10n.ProfileSetting.duplicateNickname)
            nicknameErrorLabel.isHidden = !isDuplicateNickname

            if let clan = selectedClan {
                clanSelectorNameLabel.text = clan.clanName
                loadClanSelectorAvatar(urlString: clan.logo)
            }
            let avatarToShow = clanAvatarUrl.isEmpty ? userAvatarUrl : clanAvatarUrl
            loadAvatarImage(urlString: avatarToShow)
        }
        updateDisplayNameClearButtonVisibility()
        updateClanNicknamePlaceholderAppearance()
        updateDetailStackSpacing()
    }

    private func updateDetailStackSpacing() {
        let isUser = currentTab == .userProfile
        if isUser {
            detailContentStack.setCustomSpacing(16.sh, after: displayNameFieldContainer)
        } else if isDuplicateNickname {
            detailContentStack.setCustomSpacing(4.sh, after: displayNameFieldContainer)
            detailContentStack.setCustomSpacing(12.sh, after: nicknameErrorLabel)
        } else {
            detailContentStack.setCustomSpacing(4.sh, after: displayNameFieldContainer)
        }
    }

    private func refreshDMIcon() {
        let isDefaultLogo = userDmLogoUrl.isEmpty || userDmLogoUrl == kMezonLogoURL
        if isDefaultLogo {
            dmIconImageView.image = UIImage(named: "NewMezonLogo")
            dmIconRemoveButton.isHidden = true
        } else {
            loadRemoteImage(urlString: userDmLogoUrl, into: dmIconImageView)
            dmIconRemoveButton.isHidden = false
        }
    }

    private func updateAboutMeCount() {
        let count = userAboutMe.count
        aboutMeCountLabel.text = "\(count)/\(kAboutMeMaxChars)"
    }

    private func updateDisplayNameClearButtonVisibility() {
        let text = displayNameField.text ?? ""
        displayNameClearButton.isHidden = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func clanNicknamePreviewWhenEmpty() -> String {
        let d = (context.currentUser?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty { return d }
        return userName
    }

    private func normalizedClanNickname(_ s: String) -> String {
        String(s.prefix(kDisplayNameMaxChars))
    }

    private func resolvedClanNicknameForSave() -> String {
        let t = clanNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return normalizedClanNickname(t) }
        return normalizedClanNickname(clanNicknamePreviewWhenEmpty())
    }

    private func updateClanNicknamePlaceholderAppearance() {
        guard currentTab == .clanProfile else {
            displayNameField.placeholder = nil
            displayNameField.attributedPlaceholder = nil
            return
        }
        let trimmed = clanNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            displayNameField.placeholder = nil
            displayNameField.attributedPlaceholder = nil
            return
        }
        let text = clanNicknamePreviewWhenEmpty()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15.sf),
            .foregroundColor: UIColor.mezonTextSecondary,
        ]
        displayNameField.attributedPlaceholder = NSAttributedString(string: text, attributes: attrs)
    }

    private func applyBannerTintForCurrentAvatarState() {
        let url: String
        if currentTab == .userProfile {
            url = userAvatarUrl
        } else {
            url = clanAvatarUrl.isEmpty ? userAvatarUrl : clanAvatarUrl
        }
        if url.isEmpty {
            bannerColorView.backgroundColor = .outgoingBubble
        }
    }

    private func avatarInitialText() -> String {
        let trimmed = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first.map { String($0).uppercased() } ?? ""
    }

    private func showAvatarPlaceholder() {
        avatarPlaceholderLabel.text = avatarInitialText()
        avatarPlaceholderLabel.isHidden = false
        avatarImageView.image = nil
        avatarContainerView.backgroundColor = UIColor.avatarColor(for: userName)
        bannerColorView.backgroundColor = .outgoingBubble
    }

    private func loadAvatarImage(urlString: String) {
        guard !urlString.isEmpty else {
            showAvatarPlaceholder()
            return
        }
        
        avatarPlaceholderLabel.isHidden = true
        avatarContainerView.backgroundColor = UIColor.avatarColor(for: userName)

        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            avatarImageView.image = cached
            avatarContainerView.backgroundColor = .clear
            bannerColorView.backgroundColor = cached.dominantColor() ?? .mezonBackground
            return
        }
        ImageCache.shared.loadImage(urlString: urlString) { [weak self] img in
            guard let self, let img else {
                DispatchQueue.main.async {
                    self?.showAvatarPlaceholder()
                }
                return
            }
            DispatchQueue.main.async {
                self.avatarImageView.image = img
                self.avatarPlaceholderLabel.isHidden = true
                self.avatarContainerView.backgroundColor = .clear
                self.bannerColorView.backgroundColor = img.dominantColor() ?? .mezonBackground
            }
        }
    }

    private func loadRemoteImage(urlString: String, into imageView: UIImageView) {
        guard !urlString.isEmpty else { return }
        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            imageView.image = cached
            return
        }
        ImageCache.shared.loadImage(urlString: urlString) { img in
            DispatchQueue.main.async { imageView.image = img }
        }
    }

    private func loadClanSelectorAvatar(urlString: String) {
        guard !urlString.isEmpty else {
            clanSelectorAvatar.image = nil
            return
        }
        if let cached = ImageCache.shared.memoryImage(forKey: urlString) {
            clanSelectorAvatar.image = cached
            return
        }
        ImageCache.shared.loadImage(urlString: urlString) { [weak self] img in
            DispatchQueue.main.async { self?.clanSelectorAvatar.image = img }
        }
    }

    private func updateSaveButtonState() {
        let blocked = isUploading || isSaving
        saveButton.isEnabled = !blocked
        saveButton.alpha = blocked ? 0.6 : 1.0
    }

    private func setLoading(_ loading: Bool) {
        isSaving = loading
        loadingOverlay.isHidden = !loading
        if loading { spinner.startAnimating() } else { spinner.stopAnimating() }
        updateSaveButtonState()
    }

    @objc private func saveTapped() {
        guard !isUploading else { return }
        view.endEditing(true)
        if currentTab == .userProfile {
            saveUserProfile()
        } else {
            saveClanProfile()
        }
    }

    private func saveUserProfile() {
        Task { @MainActor in
            guard let token = await context.getToken() else { return }
            let displayNameForSave = userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let aboutMeForSave = userAboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialDisplayName = initialUserDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialAboutMe = initialUserAboutMe.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasChanges =
                displayNameForSave != initialDisplayName ||
                aboutMeForSave != initialAboutMe ||
                userAvatarUrl != initialUserAvatarUrl ||
                userDmLogoUrl != initialUserDmLogoUrl
            guard hasChanges else {
                Toast.success(L(L10n.ProfileSetting.updateSuccess))
                navigationController?.popViewController(animated: true)
                return
            }
            setLoading(true)
            do {
                _ = try await context.account.network.updateAccount(
                    displayName: displayNameForSave,
                    avatarUrl: userAvatarUrl,
                    aboutMe: aboutMeForSave,
                    logo: userDmLogoUrl,
                    token: token
                )
                await context.refreshUserProfile()
                applyLocalUserProfileChange(displayName: displayNameForSave, avatarUrl: userAvatarUrl)
                setLoading(false)
                Toast.success(L(L10n.ProfileSetting.updateSuccess))
                navigationController?.popViewController(animated: true)
            } catch {
                setLoading(false)
                Toast.error(L(L10n.ProfileSetting.updateError))
            }
        }
    }

    private static let kTypeNickname: Int32 = 4

    private func saveClanProfile() {
        Task { @MainActor in
            guard let clan = selectedClan,
                  let token = await context.getToken() else { return }

            let nicknameForSave = resolvedClanNicknameForSave()
            let currentNick = clanProfile?.nickName ?? ""
            let currentAvatar = clanProfile?.avatar ?? ""
            let nickChanged = nicknameForSave != currentNick
            let avatarChanged = !clanAvatarUrl.isEmpty && clanAvatarUrl != currentAvatar

            guard nickChanged || avatarChanged else {
                Toast.success(L(L10n.ProfileSetting.clanUpdateSuccess))
                navigationController?.popViewController(animated: true)
                return
            }

            do {
                let isDuplicate = try await context.account.network.checkDuplicateName(
                    name: nicknameForSave, type: Self.kTypeNickname, conditionId: clan.clanID, token: token
                )
                if isDuplicate {
                    isDuplicateNickname = true
                    nicknameErrorLabel.isHidden = false
                    updateDetailStackSpacing()
                    return
                }
            } catch {
                Toast.error(L(L10n.ProfileSetting.updateError))
                return
            }

            setLoading(true)
            do {
                _ = try await context.account.network.updateClanProfile(
                    clanId: clan.clanID,
                    nickName: nicknameForSave,
                    avatar: avatarChanged ? clanAvatarUrl : nil,
                    token: token
                )
                await context.refreshUserProfile()
                applyLocalClanProfileChange(
                    clanId: clan.clanID,
                    nickName: nicknameForSave,
                    clanAvatar: avatarChanged ? clanAvatarUrl : nil
                )
                setLoading(false)
                Toast.success(L(L10n.ProfileSetting.clanUpdateSuccess))
                navigationController?.popViewController(animated: true)
            } catch {
                setLoading(false)
                Toast.error(L(L10n.ProfileSetting.updateError))
            }
        }
    }

    private func applyLocalUserProfileChange(displayName: String, avatarUrl: String) {
        guard let userIdStr = context.currentUser?.id, let userId = Int64(userIdStr) else { return }
        let trimmedAvatar = avatarUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        context.account.postbox.write { tx in
            let clans = tx.getClans()
            for clan in clans {
                let members = tx.getClanMembers(clanId: clan.id)
                guard let idx = members.firstIndex(where: { $0.userId == userId }) else { continue }
                let old = members[idx]
                let updated = ClanMemberRecord(
                    userId: old.userId,
                    roleIds: old.roleIds,
                    clanNick: old.clanNick,
                    clanAvatar: old.clanAvatar,
                    userAvatarURL: trimmedAvatar.isEmpty ? old.userAvatarURL : trimmedAvatar,
                    clanId: old.clanId,
                    isOnline: old.isOnline,
                    displayName: displayName,
                    username: old.username
                )
                var newMembers = members
                newMembers[idx] = updated
                tx.updateClanMembers(newMembers, clanId: clan.id)
            }
        }
        for clan in (context.account.postbox.read { tx in tx.getClans() }) {
            refreshClanUsersPreferenceCache(clanId: clan.id)
        }
    }

    private func applyLocalClanProfileChange(clanId: Int64, nickName: String, clanAvatar: String?) {
        guard clanId != 0, let userIdStr = context.currentUser?.id, let userId = Int64(userIdStr) else { return }
        let avatarToWrite: String? = clanAvatar.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        context.account.postbox.write { tx in
            let members = tx.getClanMembers(clanId: clanId)
            guard let idx = members.firstIndex(where: { $0.userId == userId }) else { return }
            let old = members[idx]
            let updated = ClanMemberRecord(
                userId: old.userId,
                roleIds: old.roleIds,
                clanNick: nickName,
                clanAvatar: avatarToWrite ?? old.clanAvatar,
                userAvatarURL: old.userAvatarURL,
                clanId: old.clanId,
                isOnline: old.isOnline,
                displayName: old.displayName,
                username: old.username
            )
            var newMembers = members
            newMembers[idx] = updated
            tx.updateClanMembers(newMembers, clanId: clanId)
        }
        refreshClanUsersPreferenceCache(clanId: clanId)
    }

    private func refreshClanUsersPreferenceCache(clanId: Int64) {
        let members = context.account.postbox.read { tx in tx.getClanMembers(clanId: clanId) }
        guard !members.isEmpty else { return }
        var list = Mezon_Api_ClanUserList()
        list.clanID = clanId
        list.clanUsers = members.map { $0.toClanUserListClanUser() }
        if let data = try? list.serializedData() {
            context.account.postbox.setPreferenceData(key: PreferencesKeys.clanUsers(clanId: clanId), value: data)
        }
    }

    @objc private func avatarTapped() {
        pendingAvatarTarget = currentTab == .userProfile ? .userAvatar : .clanAvatar
        showAvatarOptions()
    }

    @objc private func dmIconTapped() {
        pendingAvatarTarget = .dmIcon
        presentImagePicker()
    }

    @objc private func removeDMIconTapped() {
        pendingAvatarTarget = .dmIcon
        removeCurrentAvatar()
    }

    private func showAvatarOptions() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Change Avatar", style: .default) { [weak self] _ in
            self?.presentImagePicker()
        })
        sheet.addAction(UIAlertAction(title: "Remove Avatar", style: .destructive) { [weak self] _ in
            self?.removeCurrentAvatar()
        })
        sheet.addAction(UIAlertAction(title: L(L10n.Common.cancel), style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = avatarContainerView
            popover.sourceRect = avatarContainerView.bounds
        }
        present(sheet, animated: true)
    }

    private func removeCurrentAvatar() {
        let logo = UIImage(named: "MezonLogo")
        let bannerTint = logo?.dominantColor() ?? .outgoingBubble
        switch pendingAvatarTarget {
        case .userAvatar:
            userAvatarUrl = kMezonLogoURL
            avatarImageView.image = logo
            avatarPlaceholderLabel.isHidden = true
            avatarContainerView.backgroundColor = .clear
            bannerColorView.backgroundColor = bannerTint
        case .clanAvatar:
            clanAvatarUrl = kMezonLogoURL
            avatarImageView.image = logo
            avatarPlaceholderLabel.isHidden = true
            avatarContainerView.backgroundColor = .clear
            bannerColorView.backgroundColor = bannerTint
        case .dmIcon:
            userDmLogoUrl = ""
            dmIconImageView.image = UIImage(named: "NewMezonLogo")
            dmIconRemoveButton.isHidden = true
        }
    }

    private func presentImagePicker() {
        if #available(iOS 14.0, *) {
            var config = PHPickerConfiguration()
            config.selectionLimit = 1
            config.filter = .images
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
        } else {
            let picker = UIImagePickerController()
            picker.sourceType = .photoLibrary
            picker.mediaTypes = ["public.image"]
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    private func handlePickedImage(_ image: UIImage, data: Data) {
        let maxBytes: Int
        switch pendingAvatarTarget {
        case .userAvatar, .clanAvatar:
            maxBytes = kMaxAvatarBytes
        case .dmIcon:
            maxBytes = kMaxDMIconBytes
        }

        if data.count > maxBytes {
            let limitMB = maxBytes / (1024 * 1024)
            Toast.error("File size exceeds \(limitMB)MB limit")
            return
        }

        uploadImage(image: image, data: data, target: pendingAvatarTarget)
    }

    private func uploadImage(image: UIImage, data: Data, target: AvatarTarget) {
        isUploading = true

        let targetSpinner: UIActivityIndicatorView
        let targetImageView: UIImageView
        switch target {
        case .userAvatar, .clanAvatar:
            targetSpinner = avatarSpinner
            targetImageView = avatarImageView
        case .dmIcon:
            targetSpinner = dmIconSpinner
            targetImageView = dmIconImageView
        }
        targetSpinner.startAnimating()

        Task { @MainActor in
            defer {
                isUploading = false
                targetSpinner.stopAnimating()
            }
            guard let token = await context.getToken() else { return }
            do {
                let filename = "avatar_\(Int(Date().timeIntervalSince1970)).jpg"
                let filetype = "image/jpeg"

                let uploadInfo = try await context.account.network.uploadAttachmentFile(
                    filename: filename, filetype: filetype, size: data.count,
                    width: Int(image.size.width), height: Int(image.size.height), token: token
                )
                try await context.account.network.uploadToMinIO(
                    url: uploadInfo.url, data: data, contentType: filetype
                )

                let cdnURL = "\(MezonConfig.baseImgURL)/\(uploadInfo.filename)"
                ImageCache.shared.setImage(image, data: data, forKey: cdnURL)

                switch target {
                case .userAvatar:
                    userAvatarUrl = cdnURL
                    targetImageView.image = image
                    avatarPlaceholderLabel.isHidden = true
                    avatarContainerView.backgroundColor = .clear
                    bannerColorView.backgroundColor = image.dominantColor() ?? .outgoingBubble
                case .clanAvatar:
                    clanAvatarUrl = cdnURL
                    targetImageView.image = image
                    avatarPlaceholderLabel.isHidden = true
                    avatarContainerView.backgroundColor = .clear
                    bannerColorView.backgroundColor = image.dominantColor() ?? .outgoingBubble
                case .dmIcon:
                    userDmLogoUrl = cdnURL
                    targetImageView.image = image
                    dmIconRemoveButton.isHidden = false
                }
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "ProfileSetting.uploadImage",
                    "target": "\(target)",
                    "size": data.count,
                ])
                Toast.error(L(L10n.ProfileSetting.updateError))
            }
        }
    }

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func userTabTapped() {
        switchToTab(.userProfile)
    }

    @objc private func clanTabTapped() {
        switchToTab(.clanProfile)
    }

    @objc private func displayNameFieldChanged() {
        let text = displayNameField.text ?? ""
        updateDisplayNameClearButtonVisibility()
        if currentTab == .userProfile {
            if text.count <= kDisplayNameMaxChars {
                userDisplayName = text
            } else {
                let trimmed = String(text.prefix(kDisplayNameMaxChars))
                displayNameField.text = trimmed
                userDisplayName = trimmed
            }
            detailNameLabel.text = userDisplayName.isEmpty ? userName : userDisplayName
        } else {
            if text.count <= kDisplayNameMaxChars {
                clanNickname = text
            } else {
                let trimmed = String(text.prefix(kDisplayNameMaxChars))
                displayNameField.text = trimmed
                clanNickname = trimmed
            }
            isDuplicateNickname = false
            nicknameErrorLabel.isHidden = true
            updateDetailStackSpacing()
            detailNameLabel.text = clanNickname
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ? clanNicknamePreviewWhenEmpty() : clanNickname
            updateClanNicknamePlaceholderAppearance()
        }
    }

    @objc private func clearDisplayName() {
        displayNameField.text = ""
        displayNameFieldChanged()
    }

    @objc private func clanSelectorTapped() {
        showClanPicker()
    }
    
    @objc private func createClanTapped() {
        let vc = CreateClanEntryViewController(context: context)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc private func joinClanTapped() {
        let vc = JoinClanSheetViewController(context: context)
        present(vc, animated: true)
    }

    private func showClanPicker() {
        guard !clans.isEmpty else { return }
        let sheet = ClanPickerSheetViewController(
            clans: clans,
            selectedClanId: selectedClan?.clanID,
            title: L(L10n.ProfileSetting.selectAClan)
        ) { [weak self] clan in
            self?.didSelectClan(clan)
        }
        present(sheet, animated: true)
    }

    private func didSelectClan(_ clan: Mezon_Api_ClanDesc) {
        selectedClan = clan
        isDuplicateNickname = false
        nicknameErrorLabel.isHidden = true
        Task { @MainActor in await loadClanProfile() }
    }
}

extension ProfileSettingViewController: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let current = textField.text ?? ""
        guard let range = Range(range, in: current) else { return true }
        let newText = current.replacingCharacters(in: range, with: string)
        return newText.count <= kDisplayNameMaxChars
    }
}

extension ProfileSettingViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        let current = textView.text ?? ""
        guard let range = Range(range, in: current) else { return true }
        let newText = current.replacingCharacters(in: range, with: text)
        return newText.count <= kAboutMeMaxChars
    }

    func textViewDidChange(_ textView: UITextView) {
        userAboutMe = textView.text ?? ""
        updateAboutMeCount()
    }
}

@available(iOS 14.0, *)
extension ProfileSettingViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }

        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self, let image = object as? UIImage else { return }
            let jpegData = image.jpegData(compressionQuality: 0.9) ?? Data()
            DispatchQueue.main.async {
                self.handlePickedImage(image, data: jpegData)
            }
        }
    }
}

extension ProfileSettingViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        let jpegData = image.jpegData(compressionQuality: 0.9) ?? Data()
        handlePickedImage(image, data: jpegData)
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}
