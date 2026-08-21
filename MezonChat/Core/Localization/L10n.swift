import Foundation

enum L10n {

    enum Tab {
        static let clans         = "tab.clans"
        static let messages      = "tab.messages"
        static let notifications = "tab.notifications"
        static let profile       = "tab.profile"
    }

    enum MediaPanel {
        static let emoji = "mediaPanel.emoji"
        static let gifs = "mediaPanel.gifs"
        static let stickers = "mediaPanel.stickers"
        static let search = "mediaPanel.search"
        static let findGif = "mediaPanel.findGif"
        static let findEmoji = "mediaPanel.findEmoji"
        static let findSticker = "mediaPanel.findSticker"
        static let findReaction = "mediaPanel.findReaction"
        static let trendingGifs = "mediaPanel.trendingGifs"
        static let emptyGifs = "mediaPanel.emptyGifs"
    }

    enum Profile {
        static let addStatus         = "profile.addStatus"
        static let editProfile       = "profile.editProfile"
        static let balance           = "profile.balance"
        static let transferFunds     = "profile.transferFunds"
        static let transferSend        = "profile.transferSend"
        static let transferAmount     = "profile.transferAmount"
        static let sendTokenHeading      = "profile.sendTokenHeading"
        static let sendTokenSendToken    = "profile.sendTokenSendToken"
        static let sendTokenDebitAccount = "profile.sendTokenDebitAccount"
        static let sendTokenSendTo       = "profile.sendTokenSendTo"
        static let sendTokenSendToAddress = "profile.sendTokenSendToAddress"
        static let sendTokenToken        = "profile.sendTokenToken"
        static let sendTokenNote         = "profile.sendTokenNote"
        static let sendTokenDefaultNote  = "profile.sendTokenDefaultNote"
        static let sendTokenSelectAccount = "profile.sendTokenSelectAccount"
        static let sendTokenCopyAddressSuccess = "profile.sendTokenCopyAddressSuccess"
        static let sendTokenConfirmTitle = "profile.sendTokenConfirmTitle"
        static let sendTokenConfirmMessage = "profile.sendTokenConfirmMessage"
        static let sendTokenConfirmAction  = "profile.sendTokenConfirmAction"
        static let sendTokenSuccessTitle = "profile.sendTokenSuccessTitle"
        static let sendTokenComplete     = "profile.sendTokenComplete"
        static let sendTokenSendNew      = "profile.sendTokenSendNew"
        static let sendTokenReceiver     = "profile.sendTokenReceiver"
        static let sendTokenDate         = "profile.sendTokenDate"
        static let sendTokenErrAmountZero = "profile.sendTokenErrAmountZero"
        static let sendTokenErrExceedWallet = "profile.sendTokenErrExceedWallet"
        static let sendTokenErrSelectUser = "profile.sendTokenErrSelectUser"
        static let sendTokenErrSendFailed = "profile.sendTokenErrSendFailed"
        static let sendTokenErrSessionExpired = "profile.sendTokenErrSessionExpired"
        static let sendTokenErrLoginAgain = "profile.sendTokenErrLoginAgain"
        static let sendTokenLogLinePrefix = "profile.sendTokenLogLinePrefix"
        static let mezonTransfer       = "profile.mezonTransfer"
        static let historyTransaction = "profile.historyTransaction"
        static let historyAll        = "profile.historyAll"
        static let historyIncoming   = "profile.historyIncoming"
        static let historyOutgoing   = "profile.historyOutgoing"
        static let historyReceived   = "profile.historyReceived"
        static let historySent       = "profile.historySent"
        static let historyTransactionId = "profile.historyTransactionId"
        static let historyDetailTitle = "profile.historyDetailTitle"
        static let historyStatus     = "profile.historyStatus"
        static let historyCompleted  = "profile.historyCompleted"
        static let historyFailed     = "profile.historyFailed"
        static let historyTime       = "profile.historyTime"
        static let historyFee        = "profile.historyFee"
        static let historyHash       = "profile.historyHash"
        static let historyFrom       = "profile.historyFrom"
        static let historyTo         = "profile.historyTo"
        static let historySenderName = "profile.historySenderName"
        static let historyReceiverName = "profile.historyReceiverName"
        static let historyUnknownUser = "profile.historyUnknownUser"
        static let historyTransactionIdCopied = "profile.historyTransactionIdCopied"
        static let historyValue      = "profile.historyValue"
        static let aboutMe           = "profile.aboutMe"
        static let mezonMemberSince   = "profile.mezonMemberSince"
        static let yourFriends       = "profile.yourFriends"
        static let copyUserId        = "profile.copyUserId"
        static let userIdCopied      = "profile.userIdCopied"
        static let currency          = "profile.currency"
        static let statusTitle              = "profile.statusTitle"
        static let statusDurationLabel      = "profile.statusDurationLabel"
        static let statusDurationToday      = "profile.statusDurationToday"
        static let statusDurationFourHours  = "profile.statusDurationFourHours"
        static let statusDurationOneHour    = "profile.statusDurationOneHour"
        static let statusDurationThirtyMinutes = "profile.statusDurationThirtyMinutes"
        static let statusDurationDontClear  = "profile.statusDurationDontClear"
        static let statusTooLong            = "profile.statusTooLong"
        static let statusUpdateFailed       = "profile.statusUpdateFailed"
        static let changeOnlineStatus       = "profile.changeOnlineStatus"
        static let onlineStatusSection      = "profile.onlineStatusSection"
        static let setCustomStatus          = "profile.setCustomStatus"
        static let userStatusOnline         = "profile.userStatusOnline"
        static let userStatusIdle           = "profile.userStatusIdle"
        static let userStatusDoNotDisturb   = "profile.userStatusDoNotDisturb"
        static let userStatusInvisible      = "profile.userStatusInvisible"
        static let presenceUpdateFailed     = "profile.presenceUpdateFailed"
    }

    enum ProfileSetting {
        static let title             = "profileSetting.title"
        static let userProfile       = "profileSetting.userProfile"
        static let clanProfiles      = "profileSetting.clanProfiles"
        static let save              = "profileSetting.save"
        static let displayName       = "profileSetting.displayName"
        static let aboutMe           = "profileSetting.aboutMe"
        static let clanNickname      = "profileSetting.clanNickname"
        static let selectAClan       = "profileSetting.selectAClan"
        static let updateSuccess     = "profileSetting.updateSuccess"
        static let updateError       = "profileSetting.updateError"
        static let clanUpdateSuccess = "profileSetting.clanUpdateSuccess"
        static let duplicateNickname = "profileSetting.duplicateNickname"
        static let noClanTitle       = "profileSetting.noClanTitle"
        static let noClanDesc        = "profileSetting.noClanDesc"
        static let noClanCreateClan  = "profileSetting.noClanCreateClan"
        static let noClanJoinClan    = "profileSetting.noClanJoinClan"
        static let directMessageIcon = "profileSetting.directMessageIcon"
    }

    enum Common {
        static let settings       = "common.settings"
        static let save           = "common.save"
        static let cancel         = "common.cancel"
        static let confirm        = "common.confirm"
        static let delete         = "common.delete"
        static let search         = "common.search"
        static let logOut         = "common.logOut"
        static let deleteAccount  = "common.deleteAccount"
        static let refresh        = "common.refresh"
        static let close          = "common.close"
        static let goBack         = "common.goBack"
        static let copy           = "common.copy"
        static let share          = "common.share"
        static let download       = "common.download"
        static let forward        = "common.forward"
        static let comingSoon     = "common.comingSoon"
        static let forwarded      = "common.forwarded"
        static let saveChanges    = "common.saveChanges"
        static let enable         = "common.enable"
        static let reset          = "common.reset"
        static let loading        = "common.loading"
        static let actions        = "common.actions"
        static let notifications  = "common.notifications"
        static let appearance     = "common.appearance"
        static let theme          = "common.theme"
        static let language       = "common.language"
        static let linkEmail      = "common.linkEmail"
        static let linkPhoneNumber = "common.linkPhoneNumber"
        static let detail         = "common.detail"
    }

    enum ImageEditor {
        static let send   = "imageEditor.send"
        static let draw   = "imageEditor.draw"
        static let text   = "imageEditor.text"
        static let crop   = "imageEditor.crop"
        static let rotate = "imageEditor.rotate"
        static let done   = "imageEditor.done"
    }

    enum MediaPicker {
        static let edit      = "mediaPicker.edit"
        static let doneCount = "mediaPicker.doneCount"
        static let sizeLimit = "mediaPicker.sizeLimit"
    }

    enum AccountSetting {
        static let accountInformation = "accountSetting.accountInformation"
        static let users              = "accountSetting.users"
        static let accountManagement  = "accountSetting.accountManagement"
        static let username           = "accountSetting.username"
        static let displayName        = "accountSetting.displayName"
        static let blockedUsers       = "accountSetting.blockedUsers"
        static let unblock            = "accountSetting.unblock"
        static let setPassword        = "accountSetting.setPassword"
        static let phoneSectionTitle  = "accountSetting.phoneNumberSetting.title"
        static let emailSectionTitle  = "accountSetting.emailSetting.title"
        static let deleteAccountAlertTitle = "accountSetting.deleteAccountAlert.title"
        static let deleteAccountAlertMessage = "accountSetting.deleteAccountAlert.description"
        static let deleteAccountConfirm = "accountSetting.deleteAccountAlert.yesConfirm"
        static let deleteAccountCancel = "accountSetting.deleteAccountAlert.noConfirm"
        static let deleteAccountSuccess = "accountSetting.toast.deleteAccount.success"
        static let deleteAccountError = "accountSetting.toast.deleteAccount.error"

        static let requireLinkEmailTitle = "accountSetting.requireLinkEmail.title"
        static let requireLinkEmailMessage = "accountSetting.requireLinkEmail.description"
        static let requireLinkEmailAction = "accountSetting.requireLinkEmail.action"       
        static let noBlockedUsers = "accountSetting.noBlockedUsers"
    }

    enum SetPassword {
        static let title                       = "setPassword.title"
        static let save                        = "setPassword.save"
        static let email                       = "setPassword.email"
        static let currentPassword             = "setPassword.currentPassword"
        static let currentPasswordPlaceholder  = "setPassword.currentPasswordPlaceholder"
        static let password                    = "setPassword.password"
        static let passwordPlaceholder         = "setPassword.passwordPlaceholder"
        static let confirmPassword             = "setPassword.confirmPassword"
        static let confirmPasswordPlaceholder  = "setPassword.confirmPasswordPlaceholder"
        static let description                 = "setPassword.description"
        static let errorCharacters             = "setPassword.error.characters"
        static let errorUppercase              = "setPassword.error.uppercase"
        static let errorLowercase              = "setPassword.error.lowercase"
        static let errorNumber                 = "setPassword.error.number"
        static let errorSymbol                 = "setPassword.error.symbol"
        static let errorSamePass               = "setPassword.error.samePass"
        static let errorNotEqual               = "setPassword.error.notEqual"
        static let errorIncorrectCurrent       = "setPassword.error.incorrectCurrent"
        static let errorUpdateFail             = "setPassword.error.updateFail"
        static let errorCreateFail             = "setPassword.error.createFail"
        static let toastSuccess                = "setPassword.toast.success"
        static let toastError                  = "setPassword.toast.error"
    }

    enum EmailSetting {
        static let updateEmailTitle = "emailSetting.updateEmailTitle"
        static let newEmail = "emailSetting.newEmail"
        static let nextButton = "emailSetting.nextButton"
        static let invalidEmail = "emailSetting.invalidEmail"
        static let emailAlreadyLinked = "emailSetting.emailAlreadyLinked"
        static let tooFast = "emailSetting.tooFast"
        static let updateFailed = "emailSetting.updateFailed"
        static let verifyEmailTitle = "emailSetting.verifyEmailTitle"
        static let verifyDescription = "emailSetting.verifyDescription"
        static let verifyButton = "emailSetting.verifyButton"
        static let verifySuccess = "emailSetting.verifySuccess"
    }

    enum PhoneSetting {
        static let updatePhoneTitle = "phoneSetting.updatePhoneTitle"
        static let newPhoneNumber = "phoneSetting.newPhoneNumber"
        static let phonePlaceholder = "phoneSetting.phonePlaceholder"
        static let nextButton = "phoneSetting.nextButton"
        static let invalidPhoneNumber = "phoneSetting.invalidPhoneNumber"
        static let phoneAlreadyLinked = "phoneSetting.phoneAlreadyLinked"
        static let tooFast = "phoneSetting.tooFast"
        static let updateFailed = "phoneSetting.updateFailed"
        static let verifyPhoneTitle = "phoneSetting.verifyPhoneTitle"
        static let verifyDescription = "phoneSetting.verifyDescription"
        static let verifyButton = "phoneSetting.verifyButton"
        static let verifySuccess = "phoneSetting.verifySuccess"
    }

    enum UpdateGate {
        static let outOfDateVersion  = "updateGate.outOfDateVersion"
        static let updateExperience  = "updateGate.updateExperience"
        static let updateNow         = "updateGate.updateNow"
        static let versionInfo       = "updateGate.versionInfo"
    }

    enum Settings {
        static let title             = "settings.title"
        static let language          = "settings.language"
        static let theme             = "settings.theme"
        static let notifications     = "settings.notifications"
        static let account           = "settings.account"
        static let privacy           = "settings.privacy"
        static let accountSettings   = "settings.accountSettings"
        static let appSettings       = "settings.appSettings"
        static let friendRequests    = "settings.friendRequests"
        static let myQRCode          = "settings.myQRCode"
        static let qrScan           = "settings.qrScan"
        static let devices           = "settings.devices"
        static let appVersion        = "settings.appVersion"
        static let appearance        = "settings.appearance"
        static let logout            = "settings.logout"
        static let noSearchResults   = "settings.noSearchResults"
    }

    enum QRScanner {
        static let title = "qrScanner.title"
        static let cameraPermissionTitle = "qrScanner.cameraPermissionTitle"
        static let cameraPermissionMessage = "qrScanner.cameraPermissionMessage"
        static let gallery = "qrScanner.gallery"
        static let invalidQR = "qrScanner.invalidQR"
        static let loginConfirm = "qrScanner.loginConfirm"
        static let joinGroup = "qrScanner.joinGroup"
        static let transferTo = "qrScanner.transferTo"
        static let processing = "qrScanner.processing"
        static let logInOnNewDevice = "qrScanner.logInOnNewDevice"
        static let neverScanLoginQR = "qrScanner.neverScanLoginQR"
        static let youAreIn = "qrScanner.youAreIn"
        static let youAreLoggedInDesktop = "qrScanner.youAreLoggedInDesktop"
        static let startTalking = "qrScanner.startTalking"
        static let inviteToJoinClan = "qrScanner.inviteToJoinClan"
        static let joinClan = "qrScanner.joinClan"
        static let goToClan = "qrScanner.goToClan"
        static let noThanks = "qrScanner.noThanks"
        static let userProfile = "qrScanner.userProfile"
        static let message = "qrScanner.message"
        static let myQRCode = "qrScanner.myQRCode"
        static let qrProfile = "qrScanner.qrProfile"
        static let qrTransfer = "qrScanner.qrTransfer"
        static let poweredBy = "qrScanner.poweredBy"
        static let shareWithOthers = "qrScanner.shareWithOthers"
        static let scanProfileHelp = "qrScanner.scanProfileHelp"
        static let scanTransferHelp = "qrScanner.scanTransferHelp"
        static let scanInstruction = "qrScanner.scanInstruction"
        static let chooseFromGallery = "qrScanner.chooseFromGallery"
        static let sharePersonalQR = "qrScanner.sharePersonalQR"
        static let luckyMoneyTitle = "qrScanner.luckyMoneyTitle"
        static let luckyMoneyPleaseWait = "qrScanner.luckyMoneyPleaseWait"
        static let luckyMoneyCongratulations = "qrScanner.luckyMoneyCongratulations"
        static let luckyMoneyClaimToWallet = "qrScanner.luckyMoneyClaimToWallet"
        static let luckyMoneyClaimSuccess = "qrScanner.luckyMoneyClaimSuccess"
        static let luckyMoneySuccessDone = "qrScanner.luckyMoneySuccessDone"
        static let luckyMoneyClaimFailed = "qrScanner.luckyMoneyClaimFailed"
        static let luckyMoneyWalletNotReady = "qrScanner.luckyMoneyWalletNotReady"
        static let luckyMoneyServiceNotConfigured = "qrScanner.luckyMoneyServiceNotConfigured"
        static let luckyMoneyInvalidPayload = "qrScanner.luckyMoneyInvalidPayload"
        static let scannedPayloadTitle = "qrScanner.scannedPayloadTitle"
        static let copyContent = "qrScanner.copyContent"
    }

    enum Language {
        static let title          = "language.title"
    }

    enum Theme {
        static let title          = "theme.title"
        static let conversation  = "theme.conversation"
        static let canChangeLater = "theme.canChangeLater"
        static let dark           = "theme.dark"
        static let light          = "theme.light"
        static let sunrise        = "theme.sunrise"
        static let redDark        = "theme.redDark"
        static let purpleHaze     = "theme.purpleHaze"
        static let abyssDark      = "theme.abyssDark"
        static let sunset        = "theme.sunset"
        static let system        = "theme.system"
    }

    enum Login {
        static let welcomeBack         = "login.welcomeBack"
        static let email               = "login.email"
        static let password            = "login.password"
        static let logIn               = "login.logIn"
        static let otp                 = "login.otp"
        static let sendOTP             = "login.sendOTP"
        static let resendOTP           = "login.resendOTP"
        static let loginFailed         = "login.loginFailed"
        static let phone               = "login.phone"
        static let enterEmail          = "login.enterEmail"
        static let enterPhone          = "login.enterPhone"
        static let chooseAnotherOption = "login.chooseAnotherOption"
        static let emailAddress        = "login.emailAddress"
        static let send                = "login.send"
        static let showPassword        = "login.showPassword"
        static let cannotAccessYourEmail  = "login.cannotAccessYourEmail"
        static let cannotAccessYourPhone  = "login.cannotAccessYourPhone"
        static let passwordNotSet      = "login.passwordNotSet"
        static let loginWithSMS        = "login.loginWithSMS"
        static let loginWithEmailOTP   = "login.loginWithEmailOTP"
        static let loginWithPassword   = "login.loginWithPassword"
        static let invalidPhoneNumber  = "login.invalidPhoneNumber"
        static let loginTooFast       = "login.loginTooFast"
        static let resendInSeconds    = "login.resendInSeconds"
        static let selectCountry      = "login.selectCountry"
    }

    enum Welcome {
        static let title = "welcome.title"
        static let subtitle = "welcome.subtitle"
        static let startNow = "welcome.startNow"
    }

    enum Notifications {
        static let title = "notifications.title"
        static let mentions = "notifications.mentions"
        static let messages = "notifications.messages"
        static let forYou = "notifications.forYou"
        static let topic = "notifications.topic"
        static let topicDiscussion = "notifications.topicDiscussion"
        static let emptyTitle = "notifications.empty.title"
        static let emptyDescription = "notifications.empty.description"
        static let repliedTo = "notifications.repliedTo"
        static let topicOriginalAttachment = "notifications.topicOriginalAttachment"
        static let topicOriginalContact = "notifications.topicOriginalContact"
        static let topicOriginalInteractiveMessage = "notifications.topicOriginalInteractiveMessage"
        static let sender = "notifications.sender"
        static let unreachableMessage = "notifications.unreachableMessage"
    }

    enum OTPVerify {
        static let loginToMezon   = "otpVerify.loginToMezon"
        static let enterCodeFrom  = "otpVerify.enterCodeFrom"
        static let verifyOTP      = "otpVerify.verifyOTP"
        static let resendOTP      = "otpVerify.resendOTP"
        static let otpNotMatch    = "otpVerify.otpNotMatch"
        static let didNotReceive  = "otpVerify.didNotReceiveCode"
        static let changeEmail    = "otpVerify.changeEmail"
        static let changePhone    = "otpVerify.changePhone"
        static let resendFailed   = "otpVerify.resendFailed"
        static let sendOtpError   = "otpVerify.sendOtpError"
    }

    enum UpdateUsername {
        static let enterUsername = "updateUsername.enterUsername"
        static let usernamePlaceholder = "updateUsername.usernamePlaceholder"
        static let yourName = "updateUsername.yourName"
        static let usernamePreview = "updateUsername.usernamePreview"
        static let update = "updateUsername.update"
        static let errorDuplicate = "updateUsername.errorDuplicate"
        static let errorGeneric = "updateUsername.errorGeneric"
        static let skipUpdateQuestion = "updateUsername.skipUpdateQuestion"
        static let skipUpdateBack = "updateUsername.skipUpdateBack"
    }

    enum Clan {
        static let createClan     = "clan.createClan"
        static let joinClanTitle   = "clan.joinClanTitle"
        static let inviteInputPlaceholder = "clan.inviteInputPlaceholder"
        static let newClanNamePlaceholder = "clan.newClanNamePlaceholder"
        static let joinAction        = "clan.joinAction"
        static let inviteInvalid    = "clan.inviteInvalid"
        static let nameRequired     = "clan.nameRequired"
        static let createClanBannerTitle = "clan.createClanBannerTitle"
        static let createClanLogoTitle = "clan.createClanLogoTitle"
        static let createClanAddBanner = "clan.createClanAddBanner"
        static let createClanAddIcon = "clan.createClanAddIcon"
        static let createClanNameSection = "clan.createClanNameSection"
        static let createYourClanTitle = "clan.createYourClanTitle"
        static let createClanIntroBody = "clan.createClanIntroBody"
        static let createMyOwnTitle = "clan.createMyOwnTitle"
        static let startFromTemplateSection = "clan.startFromTemplateSection"
        static let createTemplateGaming = "clan.createTemplateGaming"
        static let createTemplateFriends = "clan.createTemplateFriends"
        static let createTemplateStudyGroup = "clan.createTemplateStudyGroup"
        static let createTemplateSchoolClub = "clan.createTemplateSchoolClub"
        static let createTemplateLocalCommunity = "clan.createTemplateLocalCommunity"
        static let createTemplateArtists = "clan.createTemplateArtists"
        static let customizeClanTitle = "clan.customizeClanTitle"
        static let customizeClanSubtitle = "clan.customizeClanSubtitle"
        static let clanNameInvalidFormat = "clan.clanNameInvalidFormat"
        static let createClanAgreementPrefix = "clan.createClanAgreementPrefix"
        static let createClanAgreementLink = "clan.createClanAgreementLink"
        static let uploadWordmark = "clan.uploadWordmark"
        static let members        = "clan.members"
        static let settings       = "clan.settings"
        static let duplicateName  = "clan.duplicateName"
        static let invalidName    = "clan.invalidName"
        static let creationLimitReached = "clan.creationLimitReached"
    }

    enum Discover {
        static let communityOnMezon = "discover.communityOnMezon"
        static let exploreCommunities = "discover.exploreCommunities"
        static let membersLabel = "discover.membersLabel"
        static let verified = "discover.verified"
        static let joinClan = "discover.joinClan"
        static let noCommunities = "discover.noCommunities"
        static let noMatchingCommunities = "discover.noMatchingCommunities"
        static let loadFailed = "discover.loadFailed"
    }

    enum DiscoverDetail {
        static let howChatty = "discover.detail.howChatty"
        static let clanCreated = "discover.detail.clanCreated"
        static let feature = "discover.detail.feature"
        static let communityRow = "discover.detail.communityRow"
        static let about = "discover.detail.about"
        static let chattyBusy = "discover.detail.chattyBusy"
        static let chattyModerate = "discover.detail.chattyModerate"
        static let chattyQuiet = "discover.detail.chattyQuiet"
        static let featureFallback = "discover.detail.featureFallback"
        static let communityFallback = "discover.detail.communityFallback"
        static let communityVerified = "discover.detail.communityVerified"
        static let dateUnavailable = "discover.detail.dateUnavailable"
    }

    enum CategoryCreator {
        static let title            = "category.creator.title"
        static let create           = "category.creator.create"
        static let nameTitle        = "category.creator.nameTitle"
        static let namePlaceholder  = "category.creator.namePlaceholder"
        static let nameError        = "category.creator.nameError"
        static let duplicateName    = "category.creator.duplicateName"
    }

    enum ClanAction {
        static let invite               = "clan.action.invite"
        static let markAsRead           = "clan.action.markAsRead"
        static let createEvent          = "clan.action.createEvent"
        static let createCategory       = "clan.action.createCategory"
        static let editClanProfile      = "clan.action.editClanProfile"
        static let auditLog             = "clan.action.auditLog"
        static let leaveClan            = "clan.action.leaveClan"
        static let deleteClan           = "clan.action.deleteClan"
        static let showEmptyCategories  = "clan.action.showEmptyCategories"
        static let onlineCount          = "clan.action.onlineCount"
        static let memberCount          = "clan.action.memberCount"
        static let community            = "clan.action.community"
    }

    enum AuditLog {
        static let title = "auditLog.title"
        static let filterBtn = "auditLog.filterBtn"
        static let filterByUser = "auditLog.filterByUser"
        static let filterByAction = "auditLog.filterByAction"
        static let allUsers = "auditLog.allUsers"
        static let allActions = "auditLog.allActions"
        static let empty = "auditLog.empty"
        static let add = "auditLog.add"
        static let remove = "auditLog.remove"
        static let toChannel = "auditLog.toChannel"
        
        static let updateClan = "auditLog.updateClan"
        static let createChannel = "auditLog.createChannel"
        static let updateChannel = "auditLog.updateChannel"
        static let updateChannelPrivate = "auditLog.updateChannelPrivate"
        static let deleteChannel = "auditLog.deleteChannel"
        static let createChannelPermission = "auditLog.createChannelPermission"
        static let updateChannelPermission = "auditLog.updateChannelPermission"
        static let deleteChannelPermission = "auditLog.deleteChannelPermission"
        static let kickMember = "auditLog.kickMember"
        static let pruneMember = "auditLog.pruneMember"
        static let banMember = "auditLog.banMember"
        static let unbanMember = "auditLog.unbanMember"
        static let updateMember = "auditLog.updateMember"
        static let updateRolesMember = "auditLog.updateRolesMember"
        static let moveMember = "auditLog.moveMember"
        static let disconnectMember = "auditLog.disconnectMember"
        static let addBot = "auditLog.addBot"
        static let createThread = "auditLog.createThread"
        static let updateThread = "auditLog.updateThread"
        static let deleteThread = "auditLog.deleteThread"
        static let createRole = "auditLog.createRole"
        static let updateRole = "auditLog.updateRole"
        static let deleteRole = "auditLog.deleteRole"
        static let createWebhook = "auditLog.createWebhook"
        static let updateWebhook = "auditLog.updateWebhook"
        static let deleteWebhook = "auditLog.deleteWebhook"
        static let createEmoji = "auditLog.createEmoji"
        static let updateEmoji = "auditLog.updateEmoji"
        static let deleteEmoji = "auditLog.deleteEmoji"
        static let createSticker = "auditLog.createSticker"
        static let updateSticker = "auditLog.updateSticker"
        static let deleteSticker = "auditLog.deleteSticker"
        static let createEvent = "auditLog.createEvent"
        static let updateEvent = "auditLog.updateEvent"
        static let deleteEvent = "auditLog.deleteEvent"
        static let createCanvas = "auditLog.createCanvas"
        static let updateCanvas = "auditLog.updateCanvas"
        static let deleteCanvas = "auditLog.deleteCanvas"
        static let createCategory = "auditLog.createCategory"
        static let updateCategory = "auditLog.updateCategory"
        static let deleteCategory = "auditLog.deleteCategory"
        static let addMemberChannel = "auditLog.addMemberChannel"
        static let removeMemberChannel = "auditLog.removeMemberChannel"
        static let addRoleChannel = "auditLog.addRoleChannel"
        static let removeRoleChannel = "auditLog.removeRoleChannel"
        static let addMemberThread = "auditLog.addMemberThread"
        static let removeMemberThread = "auditLog.removeMemberThread"
        static let addRoleThread = "auditLog.addRoleThread"
        static let removeRoleThread = "auditLog.removeRoleThread"
    }

    enum DeleteClanModal {
        static let title                = "deleteClanModal.title"
        static let description          = "deleteClanModal.description"
        static let titleLeaveClan       = "deleteClanModal.titleLeaveClan"
        static let descriptionLeaveClan = "deleteClanModal.descriptionLeaveClan"
        static let confirm              = "deleteClanModal.confirm"
        static let error                = "deleteClanModal.error"
    }

    enum ClanSetting {
        static let overview             = "clan.setting.overview"
        static let auditLog             = "clan.setting.auditLog"
        static let integrations         = "clan.setting.integrations"
        static let emoji                = "clan.setting.emoji"
        static let sticker              = "clan.setting.sticker"
        static let soundEffect          = "clan.setting.soundEffect"
        static let enableCommunity      = "clan.setting.enableCommunity"
        static let userManagement       = "clan.setting.userManagement"
        static let roles                = "clan.setting.roles"
        static let invites              = "clan.setting.invites"

        enum Emojis {
            static let duplicateName = "clan.setting.emojis.duplicateName"
            static let updateSuccess = "clan.setting.emojis.updateSuccess"
            static let deleteConfirmTitle = "clan.setting.emojis.deleteConfirmTitle"
            static let deleteConfirmDesc = "clan.setting.emojis.deleteConfirmDesc"
            static let deleteSuccess = "clan.setting.emojis.deleteSuccess"
            static let createSuccess = "clan.setting.emojis.createSuccess"
            static let validateName = "clan.setting.emojis.validateName"
            static let errorUpdating = "clan.setting.emojis.errorUpdating"
            static let uploadLimit = "clan.setting.emojis.uploadLimit"
            static let uploadButton = "clan.setting.emojis.uploadButton"
            static let uploadDescription = "clan.setting.emojis.uploadDescription"
            static let uploadRequirementsTitle = "clan.setting.emojis.uploadRequirementsTitle"
            static let uploadRequirement1 = "clan.setting.emojis.uploadRequirement1"
            static let uploadRequirement2 = "clan.setting.emojis.uploadRequirement2"
            static let uploadRequirement3 = "clan.setting.emojis.uploadRequirement3"
            static let uploadRequirement4 = "clan.setting.emojis.uploadRequirement4"
            static let uploadFileTooLarge = "clan.setting.emojis.uploadFileTooLarge"
            static let previewTitle = "clan.setting.emojis.previewTitle"
            static let previewNameLabel = "clan.setting.emojis.previewNameLabel"
            static let previewForSale = "clan.setting.emojis.previewForSale"
            static let previewUpload = "clan.setting.emojis.previewUpload"
            static let previewLengthError = "clan.setting.emojis.previewLengthError"
            static let previewTypeEmoji = "clan.setting.emojis.previewTypeEmoji"
            static let empty = "clan.setting.emojis.empty"
        }

        enum Stickers {
            static let duplicateName = "clan.setting.stickers.duplicateName"
            static let updateSuccess = "clan.setting.stickers.updateSuccess"
            static let deleteConfirmTitle = "clan.setting.stickers.deleteConfirmTitle"
            static let deleteConfirmDesc = "clan.setting.stickers.deleteConfirmDesc"
            static let deleteSuccess = "clan.setting.stickers.deleteSuccess"
            static let empty = "clan.setting.stickers.empty"
            static let create = "clan.setting.stickers.create"
            static let createSuccess = "clan.setting.stickers.createSuccess"
            static let validateName = "clan.setting.stickers.validateName"
            static let errorUpdating = "clan.setting.stickers.errorUpdating"
            static let uploadLimit = "clan.setting.stickers.uploadLimit"
            static let uploadButton = "clan.setting.stickers.uploadButton"
            static let uploadRequirementsTitle = "clan.setting.stickers.uploadRequirementsTitle"
            static let uploadRequirement1 = "clan.setting.stickers.uploadRequirement1"
            static let uploadRequirement2 = "clan.setting.stickers.uploadRequirement2"
            static let uploadRequirement3 = "clan.setting.stickers.uploadRequirement3"
            static let uploadFileTooLarge = "clan.setting.stickers.uploadFileTooLarge"
            static let previewTitle = "clan.setting.stickers.previewTitle"
            static let previewNameLabel = "clan.setting.stickers.previewNameLabel"
            static let previewForSale = "clan.setting.stickers.previewForSale"
            static let previewUpload = "clan.setting.stickers.previewUpload"
            static let previewLengthError = "clan.setting.stickers.previewLengthError"
            static let previewTypeSticker = "clan.setting.stickers.previewTypeSticker"
        }

        enum Overview {
            static let title = "clan.setting.overview.title"
            static let save = "clan.setting.overview.save"
            static let clanName = "clan.setting.overview.clanName"
            static let chooseImage = "clan.setting.overview.chooseImage"
            static let systemMessageTitle = "clan.setting.overview.systemMessage.title"
            static let systemMessageChannel = "clan.setting.overview.systemMessage.channel"
        static let systemMessageNoChannel = "clan.setting.overview.systemMessage.noChannel"
            static let systemMessageWelcomeRandom = "clan.setting.overview.systemMessage.welcomeRandom"
            static let systemMessageWelcomeSticker = "clan.setting.overview.systemMessage.welcomeSticker"
            static let systemMessageHideAuditLog = "clan.setting.overview.systemMessage.hideAuditLog"
            static let systemMessageDescription = "clan.setting.overview.systemMessage.description"
            static let uploadFileTooLarge10MB = "clan.setting.overview.uploadFileTooLarge10MB"
            static let uploadFileTooLarge1MB = "clan.setting.overview.uploadFileTooLarge1MB"
            static let removeAvatarTitle = "clan.setting.overview.removeAvatarTitle"
            static let removeAvatarMessage = "clan.setting.overview.removeAvatarMessage"
            static let anonymousTitle = "clan.setting.overview.anonymous.title"
            static let anonymousDescription = "clan.setting.overview.anonymous.description"
            static let defaultNotificationTitle = "clan.setting.overview.defaultNotification.title"
            static let defaultNotificationAll = "clan.setting.overview.defaultNotification.all"
            static let defaultNotificationMention = "clan.setting.overview.defaultNotification.mention"
            static let defaultNotificationNone = "clan.setting.overview.defaultNotification.none"
            static let defaultNotificationDescription = "clan.setting.overview.defaultNotification.description"
            static let deleteClan = "clan.setting.overview.deleteClan"
            static let saveSuccess = "clan.setting.overview.toast.saveSuccess"
            static let saveError = "clan.setting.overview.toast.saveError"
            static let duplicateName = "clan.setting.overview.toast.duplicateName"
            static let permissionDenied = "clan.setting.overview.toast.permissionDenied"
            static let invalidName = "clan.setting.overview.toast.invalidName"
            static let deleteClanConfirmTitle = "clan.setting.overview.deleteClan.confirmTitle"
            static let deleteClanConfirmMessage = "clan.setting.overview.deleteClan.confirmMessage"
        }

        enum Members {
            static let title                 = "clan.setting.members.title"
            static let searchPlaceholder     = "clan.setting.members.searchPlaceholder"
            static let manageUserTitle       = "clan.setting.members.manageUserTitle"
            static let roles                 = "clan.setting.members.roles"
            static let editRoles             = "clan.setting.members.editRoles"
            static let transferOwnership     = "clan.setting.members.transferOwnership"
            static let kick                  = "clan.setting.members.kick"
            static let kickTitle             = "clan.setting.members.kickTitle"
            static let kickFromClan          = "clan.setting.members.kickFromClan"
            static let kickConfirmation      = "clan.setting.members.kickConfirmation"
            static let kickReason            = "clan.setting.members.kickReason"
            static let kickButton            = "clan.setting.members.kickButton"
            static let kickSuccess           = "clan.setting.members.kickSuccess"
            static let kickFailed            = "clan.setting.members.kickFailed"
            static let transferTitle         = "clan.setting.members.transferTitle"
            static let transferWarning       = "clan.setting.members.transferWarning"
            static let transferAcknowledgmentTitle = "clan.setting.members.transferAcknowledgmentTitle"
            static let transferAcknowledgment = "clan.setting.members.transferAcknowledgment"
            static let transferButton        = "clan.setting.members.transferButton"
            static let transferSuccess       = "clan.setting.members.transferSuccess"
            static let transferFailed        = "clan.setting.members.transferFailed"
        }
    }

    enum ClanRoles {
        static let title                  = "clanRoles.title"
        static let roleDescription        = "clanRoles.roleDescription"
        static let defaultRole            = "clanRoles.defaultRole"
        static let everyone               = "clanRoles.everyone"
        static let rolesCount             = "clanRoles.rolesCount"
        static let member                 = "clanRoles.member"
        static let members                = "clanRoles.members"
        static let allMembers             = "clanRoles.allMembers"
        static let noRole                 = "clanRoles.noRole"
        static let role                   = "clanRoles.role"
        static let save                   = "clanRoles.save"
        static let saved                  = "clanRoles.saved"
        static let failed                 = "clanRoles.failed"
        static let skipStep               = "clanRoles.skipStep"

        static let createTitle            = "clanRoles.create.title"
        static let createHeading          = "clanRoles.create.heading"
        static let createDescription      = "clanRoles.create.description"
        static let createRoleName         = "clanRoles.create.roleName"
        static let createNewRolePlaceholder = "clanRoles.create.placeholder"
        static let createButton           = "clanRoles.create.button"
        static let createSuccess          = "clanRoles.create.success"

        static let detailPermissions      = "clanRoles.detail.permissions"
        static let detailMembers          = "clanRoles.detail.members"
        static let detailRoleName         = "clanRoles.detail.roleName"
        static let detailDelete           = "clanRoles.detail.delete"
        static let detailConfirmSaveTitle = "clanRoles.detail.confirmSaveTitle"
        static let detailConfirmSaveContent = "clanRoles.detail.confirmSaveContent"
        static let detailConfirmSaveYes   = "clanRoles.detail.confirmSaveYes"
        static let detailConfirmSaveDiscard = "clanRoles.detail.confirmSaveDiscard"
        static let detailDeleteTitle      = "clanRoles.detail.deleteTitle"
        static let detailDeleteMessage    = "clanRoles.detail.deleteMessage"
        static let detailDeleteConfirm    = "clanRoles.detail.deleteConfirm"

        static let colorRow               = "clanRoles.color.row"
        static let colorPickerTitle       = "clanRoles.color.pickerTitle"
        static let colorReset             = "clanRoles.color.reset"

        static let iconRow                = "clanRoles.icon.row"
        static let iconUpload             = "clanRoles.icon.upload"
        static let iconRemove             = "clanRoles.icon.remove"
        static let iconFailed             = "clanRoles.icon.failed"

        static let permissionsTitle       = "clanRoles.permissions.title"
        static let permissionsHeading     = "clanRoles.permissions.heading"
        static let permissionsSearch      = "clanRoles.permissions.search"
        static let permissionsNext        = "clanRoles.permissions.next"
        static let permissionsNotFound    = "clanRoles.permissions.notFound"
        static let permissionNotAvailable = "clanRoles.permissions.notAvailable"

        static let membersTitle           = "clanRoles.members.title"
        static let membersAdd             = "clanRoles.members.add"
        static let membersAddDescription  = "clanRoles.members.description"
        static let membersSearch          = "clanRoles.members.search"
        static let membersNotFound        = "clanRoles.members.notFound"
        static let membersFinish          = "clanRoles.members.finish"
        static let membersAdded           = "clanRoles.members.added"

        // Permission slugs → titles + descriptions
        static let permissionTitleAdministrator = "clanRoles.permissionTitle.administrator"
        static let permissionTitleManageClan    = "clanRoles.permissionTitle.manage-clan"
        static let permissionTitleManageChannel = "clanRoles.permissionTitle.manage-channel"
        static let permissionTitleViewChannel   = "clanRoles.permissionTitle.view-channel"
        static let permissionTitleSendMessage   = "clanRoles.permissionTitle.send-message"
        static let permissionTitleManageThread  = "clanRoles.permissionTitle.manage-thread"
        static let permissionTitleDeleteMessage = "clanRoles.permissionTitle.delete-message"

        static let permissionDescAdministrator  = "clanRoles.permissionDescription.administrator"
        static let permissionDescManageClan     = "clanRoles.permissionDescription.manage-clan"
        static let permissionDescManageChannel  = "clanRoles.permissionDescription.manage-channel"
        static let permissionDescViewChannel    = "clanRoles.permissionDescription.view-channel"
        static let permissionDescSendMessage    = "clanRoles.permissionDescription.send-message"
        static let permissionDescManageThread   = "clanRoles.permissionDescription.manage-thread"
        static let permissionDescDeleteMessage  = "clanRoles.permissionDescription.delete-message"
    }

    enum Forward {
        static let screenTitle            = "forward.screenTitle"
        static let success                = "forward.success"
        static let attachmentsSingular    = "forward.attachmentsSingular"
        static let attachmentsPlural      = "forward.attachmentsPlural"
        static let filesSingular          = "forward.filesSingular"
        static let filesPlural            = "forward.filesPlural"
        static let audioSingular          = "forward.audioSingular"
        static let audioPlural            = "forward.audioPlural"
        static let moreBundledMessages    = "forward.moreBundledMessages"
        static let previewPlaceholder     = "forward.previewPlaceholder"
        static let commentTooLong        = "forward.commentTooLong"
        static let noResults             = "forward.noResults"
        static let blockedByYou          = "forward.blockedByYou"
        static let blockedYou            = "forward.blockedYou"
        static let cannotMessage         = "forward.cannotMessage"
        static let toastCannotForward    = "forward.toastCannotForward"
    }

    enum Sharing {
        static let title                 = "sharing.title"
        static let suggestionsSection    = "sharing.suggestionsSection"
        static let searchPlaceholderAll  = "sharing.searchPlaceholderAll"
        static let searchPlaceholderUsers = "sharing.searchPlaceholderUsers"
        static let searchPlaceholderChannels = "sharing.searchPlaceholderChannels"
        static let emptySuggestions      = "sharing.emptySuggestions"
        static let commentPlaceholder    = "sharing.commentPlaceholder"
        static let sending               = "sharing.sending"
        static let uploading             = "sharing.uploading"
        static let filterTitle           = "sharing.filterTitle"
        static let filterAll             = "sharing.filterAll"
        static let filterUsers           = "sharing.filterUsers"
        static let filterChannels        = "sharing.filterChannels"
        static let sessionExpired        = "sharing.sessionExpired"
        static let errorTitle            = "sharing.errorTitle"
        static let alertOK             = "sharing.alertOK"
        static let uploadFailed          = "sharing.uploadFailed"
        static let uploadCancelled       = "sharing.uploadCancelled"
        static let uploadNetworkError    = "sharing.uploadNetworkError"
        static let fileUnavailable       = "sharing.fileUnavailable"
    }

    enum ChannelApp {
        static let launchApp = "channelApp.launchApp"
        static let help = "channelApp.help"
        static let unavailable = "channelApp.unavailable"
    }

    enum ClanInviteSheet {
        static let title                = "clan.inviteSheet.title"
        static let share                = "clan.inviteSheet.share"
        static let copy                 = "clan.inviteSheet.copy"
        static let qrCode               = "clan.inviteSheet.qrCode"
        static let qrHint               = "clan.inviteSheet.qrHint"
        static let shareQR              = "clan.inviteSheet.shareQR"
        static let saveQR               = "clan.inviteSheet.saveQR"
        static let qrSaved              = "clan.inviteSheet.qrSaved"
        static let qrSaveFailed         = "clan.inviteSheet.qrSaveFailed"
        static let linkCopied           = "clan.inviteSheet.linkCopied"
        static let searchPlaceholder    = "clan.inviteSheet.searchPlaceholder"
        static let loadingInviteLink    = "clan.inviteSheet.loadingInviteLink"
        static let emptyTitle           = "clan.inviteSheet.emptyTitle"
        static let emptyDescription     = "clan.inviteSheet.emptyDescription"
        static let emptyAction          = "clan.inviteSheet.emptyAction"
        static let sessionNotFound      = "clan.inviteSheet.sessionNotFound"
        static let cannotCreateInvite   = "clan.inviteSheet.cannotCreateInvite"
        static let cannotSendInvite     = "clan.inviteSheet.cannotSendInvite"
        static let invite               = "clan.inviteSheet.invite"
        static let invited              = "clan.inviteSheet.invited"
        static let unknownClan          = "clan.inviteSheet.unknownClan"
    }

    enum EventMenu {
        static let title              = "eventMenu.dashboard.title"
        static let eventOne           = "eventMenu.dashboard.event_one"
        static let noEvent            = "eventMenu.dashboard.noEvent"
        static let noEventDescription = "eventMenu.dashboard.noEventDescription"
        static let createButton       = "eventMenu.dashboard.createButton"
        static let clanEvent          = "eventMenu.eventDetail.clanEvent"
        static let channelEvent       = "eventMenu.eventDetail.channelEvent"
        static let privateEvent       = "eventMenu.eventDetail.privateEvent"
        static let eventIsTaking      = "eventMenu.eventDetail.eventIsTaking"
        static let tenMinutesLeft     = "eventMenu.eventDetail.tenMinutesLeft"
        static let newEvent           = "eventMenu.eventDetail.newEvent"
        static let privateRoom        = "eventMenu.eventDetail.privateRoom"
        static let channelAudience    = "eventMenu.eventDetail.channelAudience"
        static let detailEventInfo    = "eventMenu.detail.eventInfo"
        static let detailInterested   = "eventMenu.detail.interested"
        static let detailNoOneInterested = "eventMenu.detail.noOneInterested"
        static let detailOnePersonInterested = "eventMenu.detail.onePersonInterested"
        static let detailPersonInterested = "eventMenu.detail.personInterested"
        static let detailCreatedBy    = "eventMenu.detail.createdBy"
        static let itemInterested     = "eventMenu.item.interested"
        static let itemUninterested   = "eventMenu.item.uninterested"
    }

    enum OnboardingClan {
        static let title              = "onboardingClan.title"
        static let description        = "onboardingClan.description"
        static let actionTitle        = "onboardingClan.action.title"
        static let actionDescription  = "onboardingClan.action.description"
        static let createChannel      = "onboardingClan.action.createChannel"
        static let invite             = "onboardingClan.action.invite"
        static let sendMessage        = "onboardingClan.action.sendMessage"
    }

    enum OnboardingMember {
        static let title              = "onboardingMember.title"
        static let description        = "onboardingMember.description"
        static let actionTitle        = "onboardingMember.action.title"
        static let actionDescription  = "onboardingMember.action.description"
        static let missionSendMessage = "onboardingMember.mission.sendMessage"
        static let missionVisit       = "onboardingMember.mission.visit"
        static let missionDoSomething = "onboardingMember.mission.doSomething"
    }

    enum ThreadList {
        static let searchPlaceholder = "threadList.searchPlaceholder"
        static let empty = "threadList.empty"
        static let emptyTitle = "threadList.emptyTitle"
        static let emptyDescription = "threadList.emptyDescription"
        static let joinedThread = "threadList.joinedThread"
        static let joinedThreads = "threadList.joinedThreads"
        static let otherActiveThread = "threadList.otherActiveThread"
        static let otherActiveThreads = "threadList.otherActiveThreads"
        static let olderThread = "threadList.olderThread"
        static let olderThreads = "threadList.olderThreads"
        static let searchThread = "threadList.searchThread"
        static let searchThreads = "threadList.searchThreads"
        static let createThreadSoon = "threadList.createThreadSoon"
        static let createThreadButton = "threadList.createThreadButton"
        static let createThreadTitle = "threadList.createThreadTitle"
        static let createThreadNameLabel = "threadList.createThreadNameLabel"
        static let createThreadNamePlaceholder = "threadList.createThreadNamePlaceholder"
        static let createThreadPrivateTitle = "threadList.createThreadPrivateTitle"
        static let createThreadPrivateSubtitle = "threadList.createThreadPrivateSubtitle"
        static let createThreadSubmit = "threadList.createThreadSubmit"
        static let createThreadCancel = "threadList.createThreadCancel"
        static let createThreadNameInvalid = "threadList.createThreadNameInvalid"
        static let createThreadFailed = "threadList.createThreadFailed"
        static let createThreadForbidden = "threadList.createThreadForbidden"
        static let createThreadSuccess = "threadList.createThreadSuccess"
        static let createThreadInChannel = "threadList.createThreadInChannel"
        static let createThreadPublicTitle = "threadList.createThreadPublicTitle"
        static let createThreadPublicSubtitle = "threadList.createThreadPublicSubtitle"
        static let createThreadBadgePublic = "threadList.createThreadBadgePublic"
        static let createThreadBadgePrivate = "threadList.createThreadBadgePrivate"
        static let createThreadFirstMessageSection = "threadList.createThreadFirstMessageSection"
        static let createThreadFirstMessagePlaceholder = "threadList.createThreadFirstMessagePlaceholder"
    }

    enum ChatSystem {
        static let pinMessageAnchor = "chat.system.pinMessageAnchor"
        static let allThreadsAnchor = "chat.system.allThreadsAnchor"
        static let startedThread = "chat.system.startedThread"
        static let deletedThread = "chat.system.deletedThread"
        static let seeAllThreads = "chat.system.seeAllThreads"
        static let waveWelcome = "chat.system.waveWelcome"
    }

    enum Channel {
        static let label          = "channel.label"
        static let thread         = "channel.thread"
        static let settings       = "channel.settings"
        static let threadSettings = "channel.threadSettings"
        static let name           = "channel.name"
        static let threadName     = "channel.threadName"
        static let topic          = "channel.topic"
        static let delete         = "channel.delete"
        static let deleteConfirm  = "channel.deleteConfirm"
        static let deleteThreadConfirm = "channel.deleteThreadConfirm"
    }

    enum ChannelAction {
        static let markAsRead           = "channel.action.markAsRead"
        static let markFavorite         = "channel.action.markFavorite"
        static let unmarkFavorite       = "channel.action.unmarkFavorite"
        static let copyLink             = "channel.action.copyLink"
        static let mute                 = "channel.action.mute"
        static let muteShort            = "channel.action.muteShort"
        static let muteThread           = "channel.action.muteThread"
        static let unmute               = "channel.action.unmute"
        static let unmuteShort          = "channel.action.unmuteShort"
        static let unmuteThread         = "channel.action.unmuteThread"
        static let notificationSettings = "channel.action.notificationSettings"
        static let editChannel          = "channel.action.editChannel"
        static let editThread           = "channel.action.editThread"
        static let leaveThread          = "channel.action.leaveThread"
        static let leaveThreadConfirm   = "channel.action.leaveThreadConfirm"
        static let deleteThread         = "channel.action.deleteThread"
    }

    enum MuteDuration {
        static let title              = "muteDuration.title"
        static let titleThread        = "muteDuration.titleThread"
        static let titleConversation  = "muteDuration.titleConversation"
        static let for15Minutes       = "muteDuration.for15Minutes"
        static let for1Hour           = "muteDuration.for1Hour"
        static let for3Hours          = "muteDuration.for3Hours"
        static let for8Hours          = "muteDuration.for8Hours"
        static let for24Hours         = "muteDuration.for24Hours"
        static let untilTurnedOff     = "muteDuration.untilTurnedOff"
        static let notificationSettings = "muteDuration.notificationSettings"
        static let description        = "muteDuration.description"
    }

    enum NotificationSettings {
        static let title            = "notifSettings.title"
        static let useDefault       = "notifSettings.useDefault"
        static let allMessages      = "notifSettings.allMessages"
        static let mentionsOnly     = "notifSettings.mentionsOnly"
        static let nothing          = "notifSettings.nothing"
    }

    enum ChannelSetting {
        static let changeCategory               = "channel.setting.changeCategory"
        static let changeCategoryMoveFrom       = "channel.setting.changeCategory.moveFrom"
        static let changeCategoryConfirmContent = "channel.setting.changeCategory.confirmContent"
        static let changeCategoryEmpty          = "channel.setting.changeCategory.empty"
        static let permissions          = "channel.setting.permissions"
        static let quickAction          = "channel.setting.quickAction"
        static let banList              = "channel.setting.banList"
        static let webhook              = "channel.setting.webhook"
        static let privacyFooter        = "channel.setting.privacyFooter"
        static let createChannel        = "channel.setting.createChannel"
        static let channelName          = "channel.setting.channelName"
        static let channelNamePlaceholder = "channel.setting.channelNamePlaceholder"
        static let channelNameError     = "channel.setting.channelNameError"
        static let channelNameDuplicate = "channel.setting.channelNameDuplicate"
        static let channelType          = "channel.setting.channelType"
        static let textChannel          = "channel.setting.textChannel"
        static let textChannelDesc      = "channel.setting.textChannelDesc"
        static let voiceChannel         = "channel.setting.voiceChannel"
        static let voiceChannelDesc     = "channel.setting.voiceChannelDesc"
        static let streamChannel        = "channel.setting.streamChannel"
        static let streamChannelDesc    = "channel.setting.streamChannelDesc"
        static let privateChannel       = "channel.setting.privateChannel"
        static let privateChannelDesc   = "channel.setting.privateChannelDesc"
        static let channelNameValidate  = "channel.setting.channelNameValidate"
        static let threadNameValidate   = "channel.setting.threadNameValidate"
    }

    enum ChannelPermission {
        static let title              = "channelPermission.title"
        static let basicView          = "channelPermission.basicView"
        static let advancedView       = "channelPermission.advancedView"
        static let edit               = "channelPermission.edit"
        static let done               = "channelPermission.done"
        static let save               = "channelPermission.save"
        static let privateChannel     = "channelPermission.privateChannel"
        static let basicViewDescription = "channelPermission.basicViewDescription"
        static let addMemberAndRoles  = "channelPermission.addMemberAndRoles"
        static let whoCanAccess       = "channelPermission.whoCanAccess"
        static let roles              = "channelPermission.roles"
        static let members            = "channelPermission.members"
        static let role               = "channelPermission.role"
        static let toastSuccess       = "channelPermission.toast.success"
        static let toastFailed        = "channelPermission.toast.failed"
        static let bsAddMembersOrRoles = "channelPermission.bottomSheet.addMembersOrRoles"
        static let bsAdd              = "channelPermission.bottomSheet.add"
        static let searchPlaceholder  = "channelPermission.bottomSheet.search"
        static let roleAndMemberEmpty = "channelPermission.roleAndMemberEmpty"
        static let permissionOverrides = "channelPermission.permissionOverrides"
        static let generalChannelPermission = "channelPermission.generalChannelPermission"
        static let warnTitle          = "channelPermission.warningChangeSettingModal.title"
        static let warnContent        = "channelPermission.warningChangeSettingModal.content"
        static let warnConfirm        = "channelPermission.warningChangeSettingModal.confirm"
        static let warnCancel         = "channelPermission.warningChangeSettingModal.cancel"
    }

    enum ChatWelcome {
        static let welcomeToChannel = "chatWelcome.welcomeToChannel"
        static let startOfChannel = "chatWelcome.startOfChannel"
        static let privateChannel = "chatWelcome.privateChannel"
        static let threadStartedBy = "chatWelcome.threadStartedBy"
        static let beginningOfDM = "chatWelcome.beginningOfDM"
        static let welcomeToGroup = "chatWelcome.welcomeToGroup"
    }

    enum ChannelMessages {
        static let emptyMessages  = "channelMessages.emptyMessages"
        static let todayAt        = "channelMessages.todayAt"
        static let yesterdayAt   = "channelMessages.yesterdayAt"
        static let writeMessage   = "channelMessages.writeMessage"
        static let noSendPermission = "channelMessages.noSendPermission"
        static let userIsTyping        = "channelMessages.userIsTyping"
        static let usersAreTyping      = "channelMessages.usersAreTyping"
        static let severalPeopleTyping = "channelMessages.severalPeopleTyping"
        static let voiceMessageA11y      = "channelMessages.voiceMessageA11y"
        static let yourLocation          = "channelMessages.yourLocation"
        static let locationOf            = "channelMessages.locationOf"
        static let clanInviteLoadFailed  = "channelMessages.clanInviteLoadFailed"
        static let pollUnsupported        = "channelMessages.pollUnsupported"
        static let pollComingSoon         = "channelMessages.pollComingSoon"
    }

    enum DirectMessage {
        static let you        = "directMessage.you"
        static let addFriend = "directMessage.addFriend"
        static let newGroup = "directMessage.newGroup"
        static let create = "directMessage.create"
        static let searchFriends = "directMessage.searchFriends"
        static let memberCount = "directMessage.memberCount"
        static let noFriends = "directMessage.noFriends"
        static let memberLimitReached = "directMessage.memberLimitReached"
        static let createFailed = "directMessage.createFailed"

        static let groupCreated   = "directMessage.groupCreated"
        static let previewAttachment = "directMessage.previewAttachment"
        static let previewLink    = "directMessage.previewLink"
        static let previewLocation = "directMessage.previewLocation"
        static let previewContact = "directMessage.previewContact"
        static let previewEmbed   = "directMessage.previewEmbed"
    }

    enum DmMenu {
        static let leaveGroup = "dmMenu.leaveGroup"
        static let deleteGroup = "dmMenu.deleteGroup"
        static let closeDm = "dmMenu.closeDm"
        static let closeDmConfirmTitle = "dmMenu.closeDmConfirmTitle"
        static let closeDmConfirmMessage = "dmMenu.closeDmConfirmMessage"
        static let markAsRead = "dmMenu.markAsRead"
        static let muteConversation = "dmMenu.muteConversation"
        static let unmuteConversation = "dmMenu.unmuteConversation"
        static let blockUser = "dmMenu.blockUser"
        static let unblockUser = "dmMenu.unblockUser"
        static let removeFriend = "dmMenu.removeFriend"
        static let addFriend = "dmMenu.addFriend"
        static let members = "dmMenu.members"
        static let leaveGroupConfirmTitle = "dmMenu.leaveGroupConfirmTitle"
        static let leaveGroupConfirmBody = "dmMenu.leaveGroupConfirmBody"
        static let deleteGroupConfirmTitle = "dmMenu.deleteGroupConfirmTitle"
        static let deleteGroupConfirmBody = "dmMenu.deleteGroupConfirmBody"
        static let blockUserSuccess = "dmMenu.blockUserSuccess"
        static let blockUserError = "dmMenu.blockUserError"
        static let unblockUserSuccess = "dmMenu.unblockUserSuccess"
        static let unblockUserError = "dmMenu.unblockUserError"
        static let unmuteError = "dmMenu.unmuteError"
    }

    enum ReportMessage {
        static let title = "reportMessage.title"
        static let subtitle = "reportMessage.subtitle"
        static let selectedMessage = "reportMessage.selectedMessage"
        static let spam = "reportMessage.spam"
        static let harassment = "reportMessage.harassment"
        static let violentContent = "reportMessage.violentContent"
        static let privateInfo = "reportMessage.private"
        static let summaryTitle = "reportMessage.reportSummary"
        static let reviewBeforeSubmit = "reportMessage.reviewYourReportBeforeSubmitting"
        static let categoryLabel = "reportMessage.reportCategory"
        static let submitDescription = "reportMessage.submitDescription"
        static let submitReport = "reportMessage.submitReport"
        static let cancel = "reportMessage.cancel"
        static let submitted = "reportMessage.reportSubmitted"
        static let failed = "reportMessage.failed"
    }

    enum Embed {
        static let onlyVisibleToRecipient = "embed.onlyVisibleToRecipient"
    }

    enum Gallery {
        static let imageSaved = "gallery.imageSaved"
        static let imageSaveFailed = "gallery.imageSaveFailed"
        static let videoSaved = "gallery.videoSaved"
        static let videoSaveFailed = "gallery.videoSaveFailed"
        static let videoDownloading = "gallery.videoDownloading"
        static let videoSaving = "gallery.videoSaving"
        static let imageLoadFailed = "gallery.imageLoadFailed"
        static let photoPermissionDenied = "gallery.photoPermissionDenied"
        static let photoPermissionTitle = "gallery.photoPermissionTitle"
        static let photoPermissionMessage = "gallery.photoPermissionMessage"
    }

    enum MessageAction {
        static let reply            = "messageAction.reply"
        static let copyText         = "messageAction.copyText"
        static let saveImage        = "messageAction.saveImage"
        static let saveVideo        = "messageAction.saveVideo"
        static let copyImage        = "messageAction.copyImage"
        static let editMessage      = "messageAction.editMessage"
        static let editingMessage   = "messageAction.editingMessage"
        static let editedSuffix     = "messageAction.editedSuffix"
        static let deleteMessage    = "messageAction.deleteMessage"
        static let deleteMessageConfirm = "messageAction.deleteMessageConfirm"
        static let deleteError      = "messageAction.deleteError"
        static let pinMessage       = "messageAction.pinMessage"
        static let unpinMessage     = "messageAction.unpinMessage"
        static let forward          = "messageAction.forward"
        static let copied           = "messageAction.copied"
        static let giveACoffee        = "messageAction.giveACoffee"
        static let giveCoffeeSuccess  = "messageAction.giveCoffeeSuccess"
        static let forwardMessage   = "messageAction.forwardMessage"
        static let forwardAll       = "messageAction.forwardAll"
        static let createThread     = "messageAction.createThread"
        static let markUnread       = "messageAction.markUnread"
        static let topicDiscussion  = "messageAction.topicDiscussion"
        static let markMessage      = "messageAction.markMessage"
        static let quickMenu        = "messageAction.quickMenu"
        static let report           = "messageAction.report"
        static let pinMessageConfirm = "messageAction.pinMessageConfirm"
        static let unpinMessageConfirm = "messageAction.unpinMessageConfirm"
        static let pinSuccess       = "messageAction.pinSuccess"
        static let pinError         = "messageAction.pinError"
        static let unpinSuccess     = "messageAction.unpinSuccess"
        static let unpinError       = "messageAction.unpinError"
        static let yes              = "messageAction.yes"
        static let no               = "messageAction.no"
    }

    enum Error {
        static let networkError           = "error.networkError"
        static let connectionFailed       = "error.connectionFailed"
        static let somethingWentWrong     = "error.somethingWentWrong"
        static let sessionExpiredTitle    = "error.sessionExpiredTitle"
        static let sessionExpiredOrNetwork = "error.sessionExpiredOrNetwork"
        static let sessionExpiredContent  = "error.sessionExpiredContent"
        static let sessionExpiredConfirm  = "error.sessionExpiredConfirm"
    }

    enum ClanSwitch {
        static let rapidTitle   = "clanSwitch.rapidTitle"
        static let rapidMessage = "clanSwitch.rapidMessage"
        static let rapidConfirm = "clanSwitch.rapidConfirm"
    }

    enum ChannelDetail {
        static let members = "channelDetail.members"
        static let media   = "channelDetail.media"
        static let images  = "channelDetail.images"
        static let videos  = "channelDetail.videos"
        static let files   = "channelDetail.files"
        static let docs    = "channelDetail.docs"
        static let audios  = "channelDetail.audios"
        static let pins    = "channelDetail.pins"
        static let canvas  = "channelDetail.canvas"
        static let online  = "channelDetail.online"
        static let offline = "channelDetail.offline"
        static let inviteMembers = "channelDetail.inviteMembers"
        static let newGroup = "channelDetail.newGroup"
        static let addMembers = "channelDetail.addMembers"
        static let untitledCanvas = "channelDetail.untitledCanvas"
        static let searchFilesPlaceholder = "channelDetail.searchFilesPlaceholder"
        static let fileSharedBy = "channelDetail.fileSharedBy"
        static let noFilesYet = "channelDetail.noFilesYet"
        static let noMediaYet = "channelDetail.noMediaYet"
        static let pinAttachmentPreview = "channelDetail.pinAttachmentPreview"
        static let pinContactPreview = "channelDetail.pinContactPreview"
        static let pinEmbedPreview = "channelDetail.pinEmbedPreview"
        static let noPinsYet = "channelDetail.noPinsYet"
        static let unpinError = "channelDetail.unpinError"
        static let unpinConfirmTitle = "channelDetail.unpinConfirmTitle"
        static let unpinConfirmBody = "channelDetail.unpinConfirmBody"
        static let unpinConfirmAction = "channelDetail.unpinConfirmAction"
        static let customizeGroup = "channelDetail.customizeGroup"
        static let leaveGroup = "channelDetail.leaveGroup"
        static let deleteGroup = "channelDetail.deleteGroup"
        static let leaveGroupConfirmTitle = "channelDetail.leaveGroupConfirmTitle"
        static let leaveGroupConfirmBody = "channelDetail.leaveGroupConfirmBody"
        static let deleteGroupConfirmTitle = "channelDetail.deleteGroupConfirmTitle"
        static let deleteGroupConfirmBody = "channelDetail.deleteGroupConfirmBody"
        static let groupName = "channelDetail.groupName"
        static let removeGroupLogo = "channelDetail.removeGroupLogo"
        static let groupNameRequired = "channelDetail.groupNameRequired"
        static let groupUpdated = "channelDetail.groupUpdated"
        static let groupLeft = "channelDetail.groupLeft"
        static let groupDeleted = "channelDetail.groupDeleted"
        static let updateGroupFailed = "channelDetail.updateGroupFailed"
        static let leaveGroupFailed = "channelDetail.leaveGroupFailed"
        static let removeFromGroup = "channelDetail.removeFromGroup"
        static let removeFromGroupConfirmTitle = "channelDetail.removeFromGroupConfirmTitle"
        static let removeFromGroupConfirmBody = "channelDetail.removeFromGroupConfirmBody"
        static let removeFromGroupConfirmAction = "channelDetail.removeFromGroupConfirmAction"
        static let removeFromGroupFailed = "channelDetail.removeFromGroupFailed"
        static let memberRemoved = "channelDetail.memberRemoved"
    }

    enum FriendRequest {
        static let title              = "friendRequest.title"
        static let received           = "friendRequest.received"
        static let sent               = "friendRequest.sent"
        static let emptyReceivedTitle = "friendRequest.emptyReceivedTitle"
        static let emptyReceivedDesc  = "friendRequest.emptyReceivedDesc"
        static let addByTitle         = "friendRequest.addByTitle"
        static let addByQuestion      = "friendRequest.addByQuestion"
        static let addByPlaceholder   = "friendRequest.addByPlaceholder"
        static let addByHintFormat    = "friendRequest.addByHintFormat"
        static let addBySending       = "friendRequest.addBySending"
        static let addBySubmit        = "friendRequest.addBySubmit"
        static let addByGenericError  = "friendRequest.addByGenericError"
        static let toastSelfAddError  = "friendRequest.toastSelfAddError"
        static let toastBlockedError  = "friendRequest.toastBlockedError"
        static let toastAlreadyFriend = "friendRequest.toastAlreadyFriend"
        static let toastWaitAccept    = "friendRequest.toastWaitAccept"
        static let toastIncomingReq   = "friendRequest.toastIncomingReq"
        static let toastSendSuccess   = "friendRequest.toastSendSuccess"
        static let toastAcceptSuccess = "friendRequest.toastAcceptSuccess"
    }

    enum FriendList {
        static let title              = "friendList.title"
        static let friendCount        = "friendList.friendCount"
        static let addFriend          = "friendList.addFriend"
        static let searchPlaceholder  = "friendList.searchPlaceholder"
        static let friendRequest      = "friendList.friendRequest"
        static let received           = "friendList.received"
        static let sent               = "friendList.sent"
        static let noResults          = "friendList.noResults"
    }

    enum Poll {
        static let selectOne          = "poll.selectOne"
        static let selectOneOrMore    = "poll.selectOneOrMore"
        static let voteButton         = "poll.voteButton"
        static let removeVote         = "poll.removeVote"
        static let showResults        = "poll.showResults"
        static let backToVote         = "poll.backToVote"
        static let vote               = "poll.vote"
        static let votes              = "poll.votes"
        static let ended              = "poll.ended"
        static let left               = "poll.left"
        static let days               = "poll.days"
        static let hours              = "poll.hours"
        static let minutes            = "poll.minutes"
        static let loadMore           = "poll.loadMore"
        static let loadMore1Option    = "poll.loadMore1Option"
        static let showLess           = "poll.showLess"
        static let noVotesYet         = "poll.noVotesYet"
    }

    enum CreatePoll {
        static let poll                  = "advanced.poll"
        static let title                 = "createPoll.title"
        static let questionLabel         = "createPoll.questionLabel"
        static let questionPlaceholder   = "createPoll.questionPlaceholder"
        static let answersLabel          = "createPoll.answersLabel"
        static let answerPlaceholder     = "createPoll.answerPlaceholder"
        static let addAnswerButton       = "createPoll.addAnswerButton"
        static let durationLabel         = "createPoll.durationLabel"
        static let multipleAnswersLabel  = "createPoll.multipleAnswersLabel"
        static let postButton            = "createPoll.postButton"
        static let selectDuration        = "createPoll.selectDuration"
        static let cancel                = "createPoll.cancel"
        static let hour1                 = "createPoll.hour1"
        static let hours4                = "createPoll.hours4"
        static let hours8                = "createPoll.hours8"
        static let hours24               = "createPoll.hours24"
        static let days3                 = "createPoll.days3"
        static let week1                 = "createPoll.week1"
    }

    enum CallLog {
        static let cancel             = "callLog.cancel"
        static let missed             = "callLog.missed"
        static let receiverRejected   = "callLog.receiverRejected"
        static let youRejected        = "callLog.youRejected"
        static let audioCall          = "callLog.audioCall"
        static let videoCall          = "callLog.videoCall"
        static let callBack           = "callLog.callBack"
        static let incomingCall       = "callLog.incomingCall"
        static let outGoingCall       = "callLog.outGoingCall"
        static let startGroupCall     = "callLog.startGroupCall"
        static let startAudioCall     = "callLog.startAudioCall"
        static let startVideoCall     = "callLog.startVideoCall"
        static let callDurationPrefix = "callLog.callDurationPrefix"
    }

    enum PeerCall {
        static let actionEnd                 = "peerCall.actionEnd"
        static let actionMic                 = "peerCall.actionMic"
        static let actionSpeaker             = "peerCall.actionSpeaker"
        static let actionCancel              = "peerCall.actionCancel"
        static let actionOK                  = "peerCall.actionOK"
        static let titleDefaultOutgoing      = "peerCall.titleDefaultOutgoing"
        static let titleDefaultIncoming      = "peerCall.titleDefaultIncoming"
        static let statusRinging             = "peerCall.statusRinging"
        static let statusIncoming            = "peerCall.statusIncoming"
        static let statusConnecting          = "peerCall.statusConnecting"
        static let statusConnected           = "peerCall.statusConnected"
        static let statusMissed              = "peerCall.statusMissed"
        static let statusNoAnswer            = "peerCall.statusNoAnswer"
        static let statusCouldNotConnect     = "peerCall.statusCouldNotConnect"
        static let statusUnlockForMicrophone = "peerCall.statusUnlockForMicrophone"
        static let errorMicrophoneDenied     = "peerCall.errorMicrophoneDenied"
        static let micPermissionTitle        = "peerCall.micPermissionTitle"
        static let micPermissionBody         = "peerCall.micPermissionBody"
        static let errorCameraDenied         = "peerCall.errorCameraDenied"
        static let errorCouldNotStartCall    = "peerCall.errorCouldNotStartCall"
        static let errorCouldNotAnswerCall   = "peerCall.errorCouldNotAnswerCall"
        static let alertEndCallTitle         = "peerCall.alertEndCallTitle"
        static let alertEndCallMessage       = "peerCall.alertEndCallMessage"
        static let bannerWeakNetwork         = "peerCall.bannerWeakNetwork"
        static let remoteMicOffBanner        = "peerCall.remoteMicOffBanner"
    }

    struct Integrations {
        static let title = "integrations.title"
        static let description = "integrations.description"
        static let learnMore = "integrations.learnMore"
        static let webhooks = "integrations.webhooks"
        static let clanWebhooks = "integrations.clanWebhooks"
        static let messagesUpdates = "integrations.messagesUpdates"
    }

    enum Webhook {
        static let title            = "webhook.title"
        static let description      = "webhook.description"
        static let clanDescription  = "webhook.clanDescription"
        static let clanDescriptionTip = "webhook.clanDescriptionTip"
        static let learnMore        = "webhook.learnMore"
        static let buildOne         = "webhook.buildOne"
        static let noWebhooks       = "webhook.noWebhooks"
        static let editTitle        = "webhook.editTitle"
        static let name             = "webhook.name"
        static let nameLengthError  = "webhook.nameLengthError"
        static let channel          = "webhook.channel"
        static let webhookURL       = "webhook.webhookURL"
        static let copy             = "webhook.copy"
        static let copied           = "webhook.copied"
        static let delete           = "webhook.delete"
        static let deleteTitle      = "webhook.deleteTitle"
        static let deleteConfirm    = "webhook.deleteConfirm"
        static let recommendImage   = "webhook.recommendImage"
        static let addSuccess       = "webhook.addSuccess"
        static let addError         = "webhook.addError"
        static let saveSuccess      = "webhook.saveSuccess"
        static let saveError        = "webhook.saveError"
        static let deleteSuccess    = "webhook.deleteSuccess"
        static let deleteError      = "webhook.deleteError"
        static let createdBy        = "webhook.createdBy"
        static let resetToken       = "webhook.resetToken"
        static let resetSuccess     = "webhook.resetSuccess"
    }
}

extension L10n {

    static let translations: [AppLanguage: [String: String]] = [
        .english: en,
        .vietnamese: vi
    ]

    private static let en: [String: String] = [
        "tab.clans":            "Clans",
        "tab.messages":         "Messages",
        "tab.notifications":    "Notifications",
        "tab.profile":          "Profile",

        "common.settings":      "Settings",
        "common.save":          "Save",
        "common.cancel":        "Cancel",
        "common.confirm":       "Confirm",
        "common.delete":        "Delete",
        "common.search":        "Search",
        "common.logOut":        "Log Out",
        "common.deleteAccount": "Delete Account",
        "common.refresh":       "Refresh",
        "common.close":         "Close",
        "common.goBack":        "Go Back",
        "common.copy":          "Copy",
        "common.share":         "Share",
        "common.download":      "Download",
        "common.forward":       "Forward",
        "common.comingSoon":     "Coming soon",
        "common.forwarded":     "Forwarded",
        "common.saveChanges":   "Save Changes",
        "common.enable":        "Enable",
        "common.reset":         "Reset",
        "common.loading":       "Loading...",
        "common.actions":       "Actions",
        "common.notifications": "Notifications",
        "common.appearance":    "Appearance",
        "common.theme":         "Theme",
        "common.language":      "Language",
        "common.linkEmail":     "Add email",
        "common.linkPhoneNumber": "Add phone number",
        "common.detail":        "Detail",

        "imageEditor.send":   "Send",
        "imageEditor.draw":   "Draw",
        "imageEditor.text":   "Text",
        "imageEditor.crop":   "Crop",
        "imageEditor.rotate": "Rotate",
        "imageEditor.done":   "Done",

        "mediaPicker.edit":      "Edit",
        "mediaPicker.doneCount": "Done (%d)",
        "mediaPicker.sizeLimit": "You can select up to %dGB in total.",

        "updateGate.outOfDateVersion": "New Version Ready",
        "updateGate.updateExperience": "A quick update is needed to continue using our latest family features.",
        "updateGate.updateNow": "Update now",
        "updateGate.versionInfo": "VERSION",

        "accountSetting.accountInformation": "Account Information",
        "accountSetting.users": "Users",
        "accountSetting.accountManagement": "Account Management",
        "accountSetting.username": "Username",
        "accountSetting.displayName": "Display Name",
        "accountSetting.blockedUsers": "Blocked Users",
        "accountSetting.unblock": "Unblock",
        "accountSetting.noBlockedUsers": "You don't have any blocked users.",
        "accountSetting.setPassword": "Set Password",
        "accountSetting.phoneNumberSetting.title": "Phone",
        "accountSetting.emailSetting.title": "Email",
        "accountSetting.deleteAccountAlert.title": "Delete Account",
        "accountSetting.deleteAccountAlert.description": "Please confirm if you would like to delete your account?",
        "accountSetting.deleteAccountAlert.yesConfirm": "Yes",
        "accountSetting.deleteAccountAlert.noConfirm": "No",
        "accountSetting.toast.deleteAccount.success": "Account deleted successfully",
        "accountSetting.toast.deleteAccount.error": "You are the owner of the clan",
        "accountSetting.requireLinkEmail.title": "Link Email Required",
        "accountSetting.requireLinkEmail.description": "You need to link an email before changing your password.",
        "accountSetting.requireLinkEmail.action": "Link Email",

        "setPassword.title": "Set Password",
        "setPassword.save": "Save",
        "setPassword.email": "Email",
        "setPassword.currentPassword": "Current Password",
        "setPassword.currentPasswordPlaceholder": "Enter your current password",
        "setPassword.password": "Password",
        "setPassword.passwordPlaceholder": "Enter your new password",
        "setPassword.confirmPassword": "Confirm Password",
        "setPassword.confirmPasswordPlaceholder": "Confirm your new password",
        "setPassword.description": "Your password must be at least 8 characters long and include at least one uppercase letter, one lowercase letter, one number, and one special character (e.g., !@#$%^&*).",
        "setPassword.error.characters": "Password must be at least 8 characters",
        "setPassword.error.uppercase": "Password must include an uppercase letter",
        "setPassword.error.lowercase": "Password must include a lowercase letter",
        "setPassword.error.number": "Password must include a number",
        "setPassword.error.symbol": "Password must include a special character",
        "setPassword.error.samePass": "New password must be different from current password",
        "setPassword.error.notEqual": "Passwords do not match",
        "setPassword.error.incorrectCurrent": "Current password is incorrect",
        "setPassword.error.updateFail": "Failed to update password",
        "setPassword.error.createFail": "Failed to set password",
        "setPassword.toast.success": "Password updated successfully",
        "setPassword.toast.error": "Something went wrong. Please try again.",

        "emailSetting.updateEmailTitle": "Update Email",
        "emailSetting.newEmail": "New Email",
        "emailSetting.nextButton": "Next",
        "emailSetting.invalidEmail": "Invalid email address",
        "emailSetting.emailAlreadyLinked": "This email is already linked",
        "emailSetting.tooFast": "Please wait %ds before requesting again",
        "emailSetting.updateFailed": "Failed to update email. Please try again.",
        "emailSetting.verifyEmailTitle": "Verify Email",
        "emailSetting.verifyDescription": "Enter the 6-digit code we sent to",
        "emailSetting.verifyButton": "Verify",
        "emailSetting.verifySuccess": "Email linked successfully",

        "phoneSetting.updatePhoneTitle": "Update Phone Number",
        "phoneSetting.newPhoneNumber": "New Phone Number",
        "phoneSetting.phonePlaceholder": "Phone number",
        "phoneSetting.nextButton": "Next",
        "phoneSetting.invalidPhoneNumber": "Invalid phone number",
        "phoneSetting.phoneAlreadyLinked": "This phone number is already linked",
        "phoneSetting.tooFast": "Please wait %ds before requesting again",
        "phoneSetting.updateFailed": "Failed to update phone number. Please try again.",
        "phoneSetting.verifyPhoneTitle": "Verify Phone Number",
        "phoneSetting.verifyDescription": "Enter the 6-digit code we sent to",
        "phoneSetting.verifyButton": "Verify",
        "phoneSetting.verifySuccess": "Phone number linked successfully",

        "settings.title":           "Settings",
        "settings.language":        "Language",
        "settings.theme":           "Theme",
        "settings.notifications":   "Notifications",
        "settings.account":         "Account",
        "settings.privacy":         "Privacy",
        "settings.accountSettings": "Account Settings",
        "settings.appSettings":     "App Settings",
        "settings.friendRequests":  "Friend Requests",
        "settings.myQRCode":        "My QR Code",
        "settings.qrScan":          "QR Scan",
        "settings.devices":         "Devices",
        "settings.appVersion":      "App Version",
        "settings.appearance":      "Appearance",
        "settings.logout":          "Logout",
        "settings.noSearchResults": "No search results found",

        "language.title":         "Language Settings",

        "theme.title":            "App Theme",
        "theme.conversation":     "Conversation",
        "theme.canChangeLater":   "You can always change this later!",
        "theme.dark":             "Dark",
        "theme.light":            "Light",
        "theme.sunrise":          "Sunrise",
        "theme.redDark":          "Red Dark",
        "theme.purpleHaze":       "Purple Haze",
        "theme.abyssDark":        "Abyss Dark",
        "theme.sunset":           "Sunset",
        "theme.system":           "System",

        "login.welcomeBack":    "WELCOME BACK",
        "login.email":          "Email",
        "login.password":       "Password",
        "login.logIn":          "Log In",
        "login.otp":            "One-Time Password (OTP)",
        "login.sendOTP":        "Send OTP",
        "login.resendOTP":      "Resend OTP",
        "login.loginFailed":    "Invalid email or password. Please try again.",
        "login.phone":          "Phone number",
        "login.enterEmail":     "Enter your email",
        "login.enterPhone":     "Enter your phone number",
        "login.chooseAnotherOption":   "Or choose another option",
        "login.emailAddress":   "Email address",
        "login.send":           "Send OTP",
        "login.showPassword":   "Show password",
        "login.cannotAccessYourEmail":  "Couldn't access your email inbox?",
        "login.cannotAccessYourPhone":  "Couldn't access your phone number?",
        "login.passwordNotSet": "Password hasn't been set yet?",
        "login.loginWithSMS":   "Login with SMS OTP",
        "login.loginWithEmailOTP": "Login with Email OTP",
        "login.loginWithPassword": "Login with Email & Password",
        "login.invalidPhoneNumber": "Invalid phone number",
        "login.loginTooFast":   "Please wait before trying again",
        "login.resendInSeconds": "Resend in %ds",
        "login.selectCountry":  "Select country code",

        "welcome.title":        "Welcome to Mezon",
        "welcome.subtitle":     "The Live, Work, and Play Platform\nCustomize your own space to talk, play and hang out.",
        "welcome.startNow":     "Get started",

        "notifications.title": "Notifications",
        "notifications.mentions": "Mentions",
        "notifications.messages": "Messages",
        "notifications.forYou": "For you",
        "notifications.topic": "Topic",
        "notifications.empty.title": "Nothing yet here",
        "notifications.empty.description": "Come back for notifications on events, stream and more",
        "notifications.topicDiscussion": "TOPIC DISCUSSION",
        "notifications.repliedTo": "Original message: ",
        "notifications.topicOriginalAttachment": "[Attachment]",
        "notifications.topicOriginalContact": "[Contact]",
        "notifications.topicOriginalInteractiveMessage": "[Interactive message]",
        "notifications.sender": "Sender: ",
        "notifications.unreachableMessage": "Unreachable message",

        "otpVerify.loginToMezon":      "Log in to Mezon account",
        "otpVerify.enterCodeFrom":     "Enter code from",
        "otpVerify.verifyOTP":         "Verify OTP",
        "otpVerify.resendOTP":         "Resend OTP",
        "otpVerify.otpNotMatch":       "OTP invalid",
        "otpVerify.didNotReceiveCode": "Didn't receive a code?",
        "otpVerify.changeEmail":       "Change Email",
        "otpVerify.changePhone":       "Change Phone",
        "otpVerify.resendFailed":      "Failed to resend OTP. Please try again.",
        "otpVerify.sendOtpError":      "Failed to receive OTP. Please try again.",

        "updateUsername.enterUsername": "Enter Mezon name",
        "updateUsername.usernamePlaceholder": "Please use your actual name to make it easier for people to identify you.",
        "updateUsername.yourName": "Your name...",
        "updateUsername.usernamePreview": "Username: %@",
        "updateUsername.update": "Update",
        "updateUsername.errorDuplicate": "There's an issue or the name already exists, please choose another one.",
        "updateUsername.errorGeneric": "Something went wrong. Please try again or enter another name.",
        "updateUsername.skipUpdateQuestion": "Want to sign in again with your phone number?",
        "updateUsername.skipUpdateBack": "Return to login with phone number",

        "clan.createClan":  "Create Clan",
        "clan.joinClanTitle": "Join a clan",
        "clan.inviteInputPlaceholder": "Invite link or code",
        "clan.newClanNamePlaceholder": "Clan name",
        "clan.joinAction": "Join",
        "clan.inviteInvalid": "Enter a valid invite link or code",
        "clan.nameRequired": "Enter a clan name",
        "clan.createClanBannerTitle": "Banner",
        "clan.createClanLogoTitle": "Clan icon",
        "clan.createClanAddBanner": "Add banner",
        "clan.createClanAddIcon": "Add icon",
        "clan.createClanNameSection": "Clan name",
        "clan.createYourClanTitle": "Create Your Clan",
        "clan.createClanIntroBody": "Create your own space to connect with friends. Build your clan and start chatting today.",
        "clan.createMyOwnTitle": "Create My Own",
        "clan.startFromTemplateSection": "START FROM A TEMPLATE",
        "clan.createTemplateGaming": "Gaming",
        "clan.createTemplateFriends": "Friends",
        "clan.createTemplateStudyGroup": "Study Group",
        "clan.createTemplateSchoolClub": "School Club",
        "clan.createTemplateLocalCommunity": "Local Community",
        "clan.createTemplateArtists": "Artists & Creators",
        "clan.customizeClanTitle": "Customize Your Clan",
        "clan.customizeClanSubtitle": "Give your new clan a personality with a name and an icon. You can always change it later.",
        "clan.clanNameInvalidFormat": "Please enter a valid clan name (max 64 characters, only words, numbers, _ or -).",
        "clan.createClanAgreementPrefix": "By creating a clan, you agree to ",
        "clan.createClanAgreementLink": "Mezon's Community Guidelines",
        "clan.uploadWordmark": "UPLOAD",
        "clan.members":     "Members",
        "clan.settings":    "Clan Settings",
        "clan.duplicateName": "The clan name already exists. Please enter another name.",
        "clan.invalidName": "Please enter a valid clan name (max 64 characters, only words, numbers, _ or -).",
        "clan.creationLimitReached": "You have reached the clan creation limit.",

        "discover.communityOnMezon": "Community on Mezon",
        "discover.exploreCommunities": "Explore communities",
        "discover.membersLabel": "%d members",
        "discover.verified": "Verified",
        "discover.joinClan": "Join Clan",
        "discover.noCommunities": "No communities to show.",
        "discover.noMatchingCommunities": "No matching communities.",
        "discover.loadFailed": "Could not load communities. Pull to try again.",
        "discover.detail.howChatty": "How chatty?",
        "discover.detail.clanCreated": "Clan created",
        "discover.detail.feature": "Feature",
        "discover.detail.communityRow": "Community",
        "discover.detail.about": "About",
        "discover.detail.chattyBusy": "Like a busy coffee shop",
        "discover.detail.chattyModerate": "Fairly active",
        "discover.detail.chattyQuiet": "Pretty quiet",
        "discover.detail.featureFallback": "Try out the official features of this clan!",
        "discover.detail.communityFallback": "Connect with members and explore channels.",
        "discover.detail.communityVerified": "Weekly events and updates.",
        "discover.detail.dateUnavailable": "—",

        "eventMenu.dashboard.title":              "Events",
        "eventMenu.dashboard.event_one":          "Event",
        "eventMenu.dashboard.noEvent":            "There are no upcoming events.",
        "eventMenu.dashboard.noEventDescription": "Feel free to invite other members to contribute their ideas for upcoming events.",
        "eventMenu.dashboard.createButton":     "Create",
        "eventMenu.eventDetail.clanEvent":        "Clan Event",
        "eventMenu.eventDetail.channelEvent":     "Channel Event",
        "eventMenu.eventDetail.privateEvent":     "External Event",
        "eventMenu.eventDetail.eventIsTaking":    "Event is taking place!",
        "eventMenu.eventDetail.tenMinutesLeft":   "%d minutes left. Join in!",
        "eventMenu.eventDetail.newEvent":         "New",
        "eventMenu.eventDetail.privateRoom":      "Private room",
        "eventMenu.eventDetail.channelAudience":  "The audience consists of members from channel: %@",
        "eventMenu.detail.eventInfo":             "Event Info",
        "eventMenu.detail.interested":            "Interested",
        "eventMenu.detail.noOneInterested":       "No one's interested in this event yet.",
        "eventMenu.detail.onePersonInterested":   "1 person is interested",
        "eventMenu.detail.personInterested":      "%d people are interested",
        "eventMenu.detail.createdBy":             "Created by ",
        "eventMenu.item.interested":              "Interested",
        "eventMenu.item.uninterested":            "Uninterested",

        "clan.action.invite":               "Invite",
        "clan.action.markAsRead":           "Mark as Read",
        "category.creator.title":           "Create Category",
        "category.creator.create":          "Create",
        "category.creator.nameTitle":       "Category Name",
        "category.creator.namePlaceholder": "New Category",
        "category.creator.nameError":       "Please enter a category name (max 64 characters, only letters, numbers, _ or -).",
        "category.creator.duplicateName":   "The category name already exists.",
        "clan.action.createEvent":          "Create Event",
        "clan.action.createCategory":       "Create Category",
        "clan.action.editClanProfile":      "Edit Clan Profile",
        "clan.action.auditLog" :            "Audit log",
        "clan.action.leaveClan":            "Leave Clan",
        "clan.action.deleteClan":           "Delete Clan",
        "deleteClanModal.title":            "Delete Clan",
        "deleteClanModal.description":      "Please confirm if you would like to delete %@? This action cannot be undone.",
        "deleteClanModal.titleLeaveClan":   "Leave clan",
        "deleteClanModal.descriptionLeaveClan": "Please confirm if you would like to leave %@? You won't be able to re-join this clan unless you are re-invited.",
        "deleteClanModal.confirm":          "Yes",
        "deleteClanModal.error":            "An error occurred while trying to delete/leave the clan",
        "clan.action.showEmptyCategories":  "Show Empty Categories",
        "clan.action.onlineCount":          "%d Online",
        "clan.action.memberCount":          "%d Members",
        "clan.action.community":            "Community",

        "clan.setting.overview":            "Overview",
        "clan.setting.auditLog":            "Audit Log",
        "clan.setting.integrations":        "Integrations",
        "clan.setting.emoji":               "Emoji",
        "clan.setting.sticker":             "Sticker",
        "clan.setting.soundEffect":         "Sound Effect",
        "clan.setting.enableCommunity":     "Enable Community",
        "clan.setting.userManagement":      "User Management",
        "clan.setting.roles":               "Roles",
        "clan.setting.invites":             "Invites",

        "clan.setting.overview.title": "Overview",
        "clan.setting.overview.save": "Save",
        "clan.setting.overview.clanName": "Clan Name",
        "clan.setting.overview.chooseImage": "Choose Clan Banner",
        "clan.setting.overview.systemMessage.title": "System Notification Settings",
        "clan.setting.overview.systemMessage.channel": "Channel",
        "clan.setting.overview.systemMessage.noChannel": "No system messages",
        "clan.setting.overview.systemMessage.welcomeRandom": "Send random welcome messages when someone joins this clan",
        "clan.setting.overview.systemMessage.welcomeSticker": "Send helpful tips for clan setup",
        "clan.setting.overview.systemMessage.hideAuditLog": "Send a log when an action is applied to the clan",
        "clan.setting.overview.systemMessage.description": "This is the channel we send system event notifications to. You can turn them off at any time.",
        "clan.setting.overview.uploadFileTooLarge10MB": "File size exceeds 10MB limit.",
        "clan.setting.overview.uploadFileTooLarge1MB": "File size exceeds 1MB limit.",
        "clan.setting.overview.removeAvatarTitle": "Remove Avatar",
        "clan.setting.overview.removeAvatarMessage": "Are you sure you want to remove the clan avatar?",
        "clan.setting.overview.anonymous.title": "Anonymous Mode",
        "clan.setting.overview.anonymous.description": "Prevent users from using anonymous mode",
        "clan.setting.overview.defaultNotification.title": "Default Notification Settings",
        "clan.setting.overview.defaultNotification.all": "All messages",
        "clan.setting.overview.defaultNotification.mention": "Only @mention",
        "clan.setting.overview.defaultNotification.none": "Nothing",
        "clan.setting.overview.defaultNotification.description": "This setting will determine whether members who have not set up their notification settings will receive notifications for all messages sent in this clan or not. We recommend that communities only set notifications for @mention.",
        "clan.setting.overview.deleteClan": "Delete Clan",
        "clan.setting.overview.toast.saveSuccess": "Settings saved successfully",
        "clan.setting.overview.toast.saveError": "Failed to save settings",
        "clan.setting.overview.toast.duplicateName": "Clan name already exists",
        "clan.setting.overview.toast.permissionDenied": "You don't have permission",
        "clan.setting.overview.toast.invalidName": "Invalid clan name",
        "clan.setting.overview.deleteClan.confirmTitle": "Delete Clan",
        "clan.setting.overview.deleteClan.confirmMessage": "Are you sure you want to delete this clan? This action cannot be undone.",

        "clan.setting.members.title": "Members",
        "clan.setting.members.searchPlaceholder": "Search Members",
        "clan.setting.members.manageUserTitle": "Edit Member",
        "clan.setting.members.roles": "Roles",
        "clan.setting.members.editRoles": "Edit Roles",
        "clan.setting.members.transferOwnership": "Transfer Ownership",
        "clan.setting.members.kick": "Kick",
        "clan.setting.members.kickTitle": "Kick Member",
        "clan.setting.members.kickFromClan": "Kick %@ from clan",
        "clan.setting.members.kickConfirmation": "Are you sure you want to kick %@ from the clan? They can rejoin with a new invitation.",
        "clan.setting.members.kickReason": "Kick Reason",
        "clan.setting.members.kickButton": "Kick",
        "clan.setting.members.kickSuccess": "Member kicked successfully",
        "clan.setting.members.kickFailed": "Failed to kick member",
        "clan.setting.members.transferTitle": "Transfer Ownership",
        "clan.setting.members.transferWarning": "This will transfer ownership of %@ to %@. This action cannot be undone!",
        "clan.setting.members.transferAcknowledgmentTitle": "Transfer Ownership",
        "clan.setting.members.transferAcknowledgment": "I acknowledge that by transferring ownership of this clan to %@, it will belong to them.",
        "clan.setting.members.transferButton": "Transfer",
        "clan.setting.members.transferSuccess": "Ownership transferred successfully",
        "clan.setting.members.transferFailed": "Failed to transfer ownership",

        "clan.setting.stickers.duplicateName": "Sticker name already exists",
        "clan.setting.stickers.updateSuccess": "Sticker updated successfully",
        "clan.setting.stickers.deleteConfirmTitle": "Delete Sticker",
        "clan.setting.stickers.deleteConfirmDesc": "Are you sure you want to delete this sticker?",
        "clan.setting.stickers.deleteSuccess": "Sticker deleted successfully",
        "clan.setting.stickers.empty": "No stickers available",
        "clan.setting.stickers.create": "Create Sticker",
        "clan.setting.stickers.createSuccess": "Sticker created successfully",
        "clan.setting.stickers.validateName": "Length must be %d - %d characters. Only letters, numbers, _ and - are allowed.",
        "clan.setting.stickers.errorUpdating": "Failed to update sticker. Please try again.",
        "clan.setting.stickers.uploadLimit": "Sticker upload limit reached",
        "clan.setting.stickers.uploadButton": "Upload Sticker",
        "clan.setting.stickers.uploadRequirementsTitle": "Upload Requirements",
        "clan.setting.stickers.uploadRequirement1": "Can be a static image (PNG) or an animated image (GIF).",
        "clan.setting.stickers.uploadRequirement2": "Must be exactly 320 x 320 pixels.",
        "clan.setting.stickers.uploadRequirement3": "Must not be larger than 512KB.",
        "clan.setting.stickers.uploadFileTooLarge": "Image must not be larger than 512KB.",
        "clan.setting.stickers.previewTitle": "Sticker Preview",
        "clan.setting.stickers.previewNameLabel": "Sticker Name",
        "clan.setting.stickers.previewForSale": "For Sale",
        "clan.setting.stickers.previewUpload": "Upload",
        "clan.setting.stickers.previewLengthError": "%@ name must be between %d and %d characters, only letters, numbers, _ and - are allowed.",
        "clan.setting.stickers.previewTypeSticker": "Sticker",
        "clan.setting.emojis.duplicateName": "Emoji name already exists",
        "clan.setting.emojis.updateSuccess": "Emoji updated successfully",
        "clan.setting.emojis.deleteConfirmTitle": "Delete Emoji",
        "clan.setting.emojis.deleteConfirmDesc": "Are you sure you want to delete this emoji?",
        "clan.setting.emojis.deleteSuccess": "Emoji deleted successfully",
        "clan.setting.emojis.createSuccess": "Emoji created successfully",
        "clan.setting.emojis.validateName": "Length must be %d - %d characters. Only letters, numbers, _ and - are allowed.",
        "clan.setting.emojis.errorUpdating": "Failed to update emoji. Please try again.",
        "clan.setting.emojis.uploadLimit": "Emoji upload limit reached",
        "clan.setting.emojis.uploadButton": "Upload Emoji",
        "clan.setting.emojis.uploadDescription": "Add custom emoji that anyone in this clan can use. All Mezon members can use animated GIF emoji.",
        "clan.setting.emojis.uploadRequirementsTitle": "Upload Requirements",
        "clan.setting.emojis.uploadRequirement1": "File type: JPEG, PNG, GIF.",
        "clan.setting.emojis.uploadRequirement2": "Recommended file size: 256 KB.",
        "clan.setting.emojis.uploadRequirement3": "Recommended dimensions: 128x128.",
        "clan.setting.emojis.uploadRequirement4": "Naming: Emoji name must be at least 3 characters and only contain letters, numbers, and underscores.",
        "clan.setting.emojis.uploadFileTooLarge": "Image must not be larger than 256 KB.",
        "clan.setting.emojis.previewTitle": "Emoji Preview",
        "clan.setting.emojis.previewNameLabel": "Emoji Name",
        "clan.setting.emojis.previewForSale": "For Sale",
        "clan.setting.emojis.previewUpload": "Upload",
        "clan.setting.emojis.previewLengthError": "%@ name must be between %d and %d characters, only letters, numbers, _ and - are allowed.",
        "clan.setting.emojis.previewTypeEmoji": "Emoji",
        "clan.setting.emojis.empty": "No emojis found",

        "clanRoles.title":                  "Roles",
        "clanRoles.roleDescription":        "Use roles to group your clan members and assign permissions.",
        "clanRoles.defaultRole":            "Default permissions for all clan members.",
        "clanRoles.everyone":               "@everyone",
        "clanRoles.rolesCount":             "Roles — %d",
        "clanRoles.member":                 "member",
        "clanRoles.members":                "members",
        "clanRoles.allMembers":             "All clan members",
        "clanRoles.noRole":                 "No role yet. Tap + to create one.",
        "clanRoles.role":                   "Role",
        "clanRoles.save":                   "Save",
        "clanRoles.saved":                  "Changes saved",
        "clanRoles.failed":                 "Something went wrong. Try again.",
        "clanRoles.skipStep":               "Skip this step",

        "clanRoles.create.title":           "Create a new role",
        "clanRoles.create.heading":         "Create a new role",
        "clanRoles.create.description":     "Roles represent a set of permissions assigned to a group of clan members.",
        "clanRoles.create.roleName":        "Role name",
        "clanRoles.create.placeholder":     "New role",
        "clanRoles.create.button":          "Create",
        "clanRoles.create.success":         "Role \"%@\" created",

        "clanRoles.detail.permissions":     "Permissions",
        "clanRoles.detail.members":         "Members",
        "clanRoles.detail.roleName":        "Role Name",
        "clanRoles.detail.delete":          "Delete Role",
        "clanRoles.detail.confirmSaveTitle":   "Save changes?",
        "clanRoles.detail.confirmSaveContent": "You have unsaved changes. Save before leaving?",
        "clanRoles.detail.confirmSaveYes":     "Save",
        "clanRoles.detail.confirmSaveDiscard": "Discard",
        "clanRoles.detail.deleteTitle":     "Delete this role?",
        "clanRoles.detail.deleteMessage":   "This action is permanent and cannot be undone.",
        "clanRoles.detail.deleteConfirm":   "Delete",

        "clanRoles.color.row":              "Role Color",
        "clanRoles.color.pickerTitle":      "Role Color",
        "clanRoles.color.reset":            "Reset color",

        "clanRoles.icon.row":               "Role Icon",
        "clanRoles.icon.upload":            "Upload",
        "clanRoles.icon.remove":            "Remove",
        "clanRoles.icon.failed":            "Could not upload icon",

        "clanRoles.permissions.title":      "Setup Permissions",
        "clanRoles.permissions.heading":    "Choose what members of this role can do.",
        "clanRoles.permissions.search":     "Search permission",
        "clanRoles.permissions.next":       "Next",
        "clanRoles.permissions.notFound":   "No permissions found.",
        "clanRoles.permissions.notAvailable": "No description available for this permission.",

        "clanRoles.members.title":          "Add Members",
        "clanRoles.members.add":            "Add member",
        "clanRoles.members.description":    "Pick members to add to this role.",
        "clanRoles.members.search":         "Search members",
        "clanRoles.members.notFound":       "No members found",
        "clanRoles.members.finish":         "Finish",
        "clanRoles.members.added":          "Members updated",

        "clanRoles.permissionTitle.administrator":   "Administrator",
        "clanRoles.permissionTitle.manage-clan":     "Manage Clan",
        "clanRoles.permissionTitle.manage-channel":  "Manage Channels",
        "clanRoles.permissionTitle.view-channel":    "View Channels",
        "clanRoles.permissionTitle.send-message":    "Send Messages",
        "clanRoles.permissionTitle.manage-thread":   "Manage Threads",
        "clanRoles.permissionTitle.delete-message":  "Delete Messages",

        "clanRoles.permissionDescription.administrator":  "Members with this permission have every permission and can bypass channel restrictions.",
        "clanRoles.permissionDescription.manage-clan":    "Allows changing the clan name, icon and other settings.",
        "clanRoles.permissionDescription.manage-channel": "Allows creating, editing or deleting channels.",
        "clanRoles.permissionDescription.view-channel":   "Allows members to view channels by default.",
        "clanRoles.permissionDescription.send-message":   "Allows members to send messages in text channels.",
        "clanRoles.permissionDescription.manage-thread":  "Allows creating, archiving and deleting threads.",
        "clanRoles.permissionDescription.delete-message": "Allows deleting messages from other members.",
        "forward.screenTitle": "Forward to",
        "forward.success": "Messages forwarded",
        "forward.attachmentsSingular": "attachment",
        "forward.attachmentsPlural": "attachments",
        "forward.filesSingular": "file",
        "forward.filesPlural": "files",
        "forward.audioSingular": "audio",
        "forward.audioPlural": "audio",
        "forward.moreBundledMessages": "more messages included",
        "forward.previewPlaceholder": "Message preview",
        "forward.commentTooLong": "Comment is too long",
        "forward.noResults": "No results found",
        "forward.blockedByYou": "You blocked this user",
        "forward.blockedYou": "This user blocked you",
        "forward.cannotMessage": "You can't message each other",
        "forward.toastCannotForward": "You can't forward messages to this conversation",

        "sharing.title":                    "Share",
        "sharing.suggestionsSection":       "Suggestions",
        "sharing.searchPlaceholderAll":     "Select a channel or user",
        "sharing.searchPlaceholderUsers":   "Select user",
        "sharing.searchPlaceholderChannels":"Select channel",
        "sharing.emptySuggestions":         "No channels or conversations yet. Open the app and browse your servers, then try again.",
        "sharing.commentPlaceholder":       "Add a comment (optional)",
        "sharing.sending":                  "Sending…",
        "sharing.uploading":                "Uploading",
        "sharing.filterTitle":              "Filter",
        "sharing.filterAll":                "All",
        "sharing.filterUsers":              "Users",
        "sharing.filterChannels":           "Channels",
        "sharing.sessionExpired":           "Session expired",
        "sharing.errorTitle": "Error",
        "sharing.alertOK": "OK",
        "sharing.uploadFailed":             "Could not send. Please try again.",
        "sharing.uploadCancelled":          "Upload was interrupted. Stay in Mezon and try again.",
        "sharing.uploadNetworkError":       "Network error while uploading. Check your connection and try again.",
        "sharing.fileUnavailable":          "The shared file is no longer available. Share it again from the other app.",

        "clan.inviteSheet.title":           "Invite a friend",
        "clan.inviteSheet.share":           "Share Invite",
        "clan.inviteSheet.copy":            "Copy Link",
        "clan.inviteSheet.qrCode":          "QR Code",
        "clan.inviteSheet.qrHint":          "Scan QR code to join this clan",
        "clan.inviteSheet.shareQR":         "Share QR",
        "clan.inviteSheet.saveQR":          "Save QR",
        "clan.inviteSheet.qrSaved":         "QR saved to gallery",
        "clan.inviteSheet.qrSaveFailed":    "Could not save QR code.",
        "clan.inviteSheet.linkCopied":      "Link Copied!",
        "clan.inviteSheet.searchPlaceholder":"Invite friend to clan",
        "clan.inviteSheet.loadingInviteLink":"Creating invite link...",
        "clan.inviteSheet.emptyTitle":      "No friends to invite",
        "clan.inviteSheet.emptyDescription":"Add friends to your friend list to invite them to this clan.",
        "clan.inviteSheet.emptyAction":     "Add some friends",
        "clan.inviteSheet.sessionNotFound": "Can't connect right now. Please try again.",
        "clan.inviteSheet.cannotCreateInvite":"Cannot create clan invite link.",
        "clan.inviteSheet.cannotSendInvite":"Cannot send invite to %@.",
        "clan.inviteSheet.invite":          "Invite",
        "clan.inviteSheet.invited":         "Invited",
        "clan.inviteSheet.unknownClan":     "Unknown Clan",

        "onboardingClan.title":                 "Complete the guide",
        "onboardingClan.description":           "Step %d of %d",
        "onboardingClan.action.title":          "Finish onboarding your clan",
        "onboardingClan.action.description":    "Completed %d of %d steps",
        "onboardingClan.action.createChannel":  "Create your channel",
        "onboardingClan.action.invite":         "Invite some friends",
        "onboardingClan.action.sendMessage":    "Send your first message",
        "onboardingMember.title":               "Get Started",
        "onboardingMember.description":         "Step %d of %d",
        "onboardingMember.action.title":        "Get Started",
        "onboardingMember.action.description":  "Completed %d of %d steps",
        "onboardingMember.mission.sendMessage": "Send a message in",
        "onboardingMember.mission.visit":       "Visit a channel",
        "onboardingMember.mission.doSomething": "Do anything you want",

        "threadList.searchPlaceholder": "Search Threads",
        "threadList.empty": "No threads yet",
        "threadList.emptyTitle": "There are no threads",
        "threadList.emptyDescription": "Stay focus on conversation with a thread\n- a temporary text channel.",
        "threadList.joinedThread": "joined thread",
        "threadList.joinedThreads": "joined threads",
        "threadList.otherActiveThread": "other active thread",
        "threadList.otherActiveThreads": "other active threads",
        "threadList.olderThread": "archived thread",
        "threadList.olderThreads": "archived threads",
        "threadList.searchThread": "search result",
        "threadList.searchThreads": "search results",
        "threadList.createThreadSoon": "Create thread is not available here yet.",
        "threadList.createThreadButton": "Create Thread",
        "threadList.createThreadTitle": "New thread",
        "threadList.createThreadNameLabel": "Thread name",
        "threadList.createThreadNamePlaceholder": "New thread",
        "threadList.createThreadPrivateTitle": "Private thread",
        "threadList.createThreadPrivateSubtitle": "Only people you invite can access this thread.",
        "threadList.createThreadSubmit": "Create",
        "threadList.createThreadCancel": "Cancel",
        "threadList.createThreadNameInvalid": "Enter a name from 4 to 64 characters.",
        "threadList.createThreadFailed": "Could not create thread.",
        "threadList.createThreadForbidden": "You do not have permission to create threads in this channel.",
        "threadList.createThreadSuccess": "Thread created.",
        "threadList.createThreadInChannel": "In #%@",
        "threadList.createThreadPublicTitle": "Public thread",
        "threadList.createThreadPublicSubtitle": "Anyone who can access this channel can find and join this thread.",
        "threadList.createThreadBadgePublic": "PUBLIC",
        "threadList.createThreadBadgePrivate": "PRIVATE",
        "threadList.createThreadFirstMessageSection": "First message",
        "threadList.createThreadFirstMessagePlaceholder": "Optional — use @ to mention someone",

        "channel.label":  "channel",
        "channel.thread": "Threads",
        "chat.system.pinMessageAnchor": "a message",
        "chat.system.allThreadsAnchor": "all threads",
        "chat.system.startedThread": "started a thread:",
        "chat.system.deletedThread": "deleted a thread:",
        "chat.system.seeAllThreads": "See",
        "chat.system.waveWelcome": "Wave to say hi!",
        "channel.settings": "Channel Settings",
        "channel.threadSettings": "Thread Settings",
        "channel.name":   "Channel Name",
        "channel.threadName": "Thread Name",
        "channel.topic":  "Channel Topic",
        "channel.delete": "Delete Channel",
        "channel.deleteConfirm": "Are you sure you want to delete this channel?",
        "channel.deleteThreadConfirm": "Are you sure you want to delete this thread?",

        "channel.action.markAsRead":           "Mark as Read",
        "channel.action.markFavorite":         "Mark Favorite",
        "channel.action.unmarkFavorite":       "Unmark Favorite",
        "channel.action.copyLink":             "Copy Link",
        "channel.action.mute":                 "Mute Channel",
        "channel.action.muteShort":            "Mute",
        "channel.action.muteThread":           "Mute Thread",
        "channel.action.unmute":               "Unmute Channel",
        "channel.action.unmuteShort":          "Unmute",
        "channel.action.unmuteThread":         "Unmute Thread",
        "channel.action.notificationSettings": "Notification Settings",
        "channel.action.editChannel":          "Edit Channel",
        "channel.action.editThread":           "Edit Thread",
        "channel.action.leaveThread":          "Leave Thread",
        "channel.action.leaveThreadConfirm":   "Are you sure you want to leave this thread?",
        "channel.action.deleteThread":         "Delete Thread",

        "emojiPicker.title":                   "Emojis",
        "muteDuration.title":              "Mute this channel",
        "muteDuration.titleThread":        "Mute this thread",
        "muteDuration.titleConversation":  "Mute this conversation",
        "muteDuration.for15Minutes":       "For 15 minutes",
        "muteDuration.for1Hour":           "For 1 hour",
        "muteDuration.for3Hours":          "For 3 hours",
        "muteDuration.for8Hours":          "For 8 hours",
        "muteDuration.for24Hours":         "For 24 hours",
        "muteDuration.untilTurnedOff":     "Until I turn it back on",
        "muteDuration.notificationSettings": "Notification Settings",
        "muteDuration.description":        "You are receiving notifications from all messages in this clan, but you can change settings here",
        "notifSettings.title":          "Notification Settings",
        "notifSettings.useDefault":     "Use default settings",
        "notifSettings.allMessages":    "All messages",
        "notifSettings.mentionsOnly":   "Only @mention",
        "notifSettings.nothing":        "Nothing",

        "channel.setting.changeCategory":       "Change Category",
        "channel.setting.changeCategory.moveFrom": "Move from %@ to",
        "channel.setting.changeCategory.confirmContent": "Are you sure you want to move %channel% to %category%?",
        "channel.setting.changeCategory.empty": "No other categories to move to",
        "channel.setting.permissions":          "Channel Permissions",
        "channel.setting.channelNameValidate":  "Please enter a channel name (max 64 characters, only words, numbers, _ or -).",
        "channel.setting.threadNameValidate":   "Please enter a valid thread name (max 65 characters, only words, numbers, _ or -).",
        "channel.setting.quickAction":          "Quick Action",
        "channel.setting.banList":              "Ban List",
        "channel.setting.webhook":              "Webhook",
        "channel.setting.privacyFooter":        "Change privacy settings and customize how members can interact with this channel.",
        "channel.setting.createChannel":        "Create Channel",
        "channel.setting.channelName":          "Channel Name",
        "channel.setting.channelNamePlaceholder": "Enter the channel's name",
        "channel.setting.channelNameError":       "Please enter a channel name (max 64 characters, only words, numbers, _ or -).",
        "channel.setting.channelNameDuplicate":   "The channel name already exists.",
        "channel.setting.channelType":          "Channel Type",
        "channel.setting.textChannel":          "Text",
        "channel.setting.textChannelDesc":      "Send messages, images, GIFs, emojis, opinions, and puns",
        "channel.setting.voiceChannel":         "Voice",
        "channel.setting.voiceChannelDesc":     "Hang out together with voice, video, and screen share",
        "channel.setting.streamChannel":        "Stream",
        "channel.setting.streamChannelDesc":    "Sharing hobby activities",
        "channel.setting.privateChannel":       "Private Channel",
        "channel.setting.privateChannelDesc":   "Only selected members and roles will be able to view this channel.",

        "webhook.title":            "Webhook",
        "integrations.title":           "Integrations",
        "integrations.description":     "Customize your clan with integrations. Manage webhooks, followed channels and apps, integrate external systems and automate notification workflows in Mezon.",
        "integrations.learnMore":       "Learn more about managing integrations",
        "integrations.webhooks":        "Webhooks",
        "integrations.clanWebhooks":    "Clan Webhooks",
        "integrations.messagesUpdates": "Messages and automated updates",
        "webhook.description":          "Webhooks are a simple way to post messages from other apps and websites into Mezon using internet magic.",
        "webhook.clanDescription":      "Clan Webhooks are a simple way to post messages from other apps and websites for each Mezon user using internet technology.",
        "webhook.clanDescriptionTip":   "\nTip: If you feel the token on your URL is compromised or outdated, reset it and copy the new URL",
        "webhook.learnMore":            "Learn more",
        "webhook.buildOne":         "build your own",
        "webhook.noWebhooks":       "No Webhooks",
        "webhook.editTitle":        "Edit Webhook",
        "webhook.name":             "Webhook name",
        "webhook.nameLengthError":  "Must be 64 characters or fewer in length.",
        "webhook.channel":          "Channel",
        "webhook.webhookURL":       "Webhook URL",
        "webhook.copy":             "Copy",
        "webhook.copied":           "Copied",
        "webhook.delete":           "Delete",
        "webhook.deleteTitle":      "Delete Webhook",
        "webhook.deleteConfirm":    "Are you sure you want to delete webhook %@?",
        "webhook.recommendImage":   "Recommended image size is at least 128x128 px",
        "webhook.addSuccess":       "Webhook added successfully",
        "webhook.addError":         "Failed to add webhook",
        "webhook.saveSuccess":      "Saved successfully",
        "webhook.saveError":        "Failed to save",
        "webhook.deleteSuccess":    "Webhook deleted successfully",
        "webhook.deleteError":      "Failed to delete webhook",
        "webhook.createdBy":        "Created on %@ by %@",
        "webhook.resetToken":       "Reset Token",
        "webhook.resetSuccess":     "Reset successfully",

        "channelPermission.title":              "Channel Permissions",
        "channelPermission.basicView":          "Basic View",
        "channelPermission.advancedView":       "Advanced View",
        "channelPermission.edit":               "Edit",
        "channelPermission.done":               "Done",
        "channelPermission.save":               "Save",
        "channelPermission.privateChannel":     "Private Channel",
        "channelPermission.basicViewDescription": "By making a channel private, only selected members and roles will be able to view this channel.",
        "channelPermission.addMemberAndRoles":  "Add members and roles",
        "channelPermission.whoCanAccess":       "Who can access this channel?",
        "channelPermission.roles":              "Roles",
        "channelPermission.members":            "Members",
        "channelPermission.role":               "Role",
        "channelPermission.toast.success":      "Update successfully",
        "channelPermission.toast.failed":       "Update failed",
        "channelPermission.bottomSheet.addMembersOrRoles": "Add members or roles",
        "channelPermission.bottomSheet.add":    "Add",
        "channelPermission.bottomSheet.search": "Search for a member or role",
        "channelPermission.roleAndMemberEmpty": "No roles or members. Add some from Basic View first.",
        "channelPermission.permissionOverrides": "Permission Overrides",
        "channelPermission.generalChannelPermission": "General Channel Permissions",
        "channelPermission.warningChangeSettingModal.title":   "Unsaved changes",
        "channelPermission.warningChangeSettingModal.content": "You have made changes. Are you sure you want to leave without saving?",
        "channelPermission.warningChangeSettingModal.confirm": "Save",
        "channelPermission.warningChangeSettingModal.cancel":  "Discard",

        "channelMessages.emptyMessages": "No messages yet",
        "channelMessages.todayAt": "Today at %@",
        "channelMessages.yesterdayAt": "Yesterday at %@",
        "channelMessages.writeMessage": "Write message...",
        "channelMessages.noSendPermission": "You do not have permission to send messages in this channel.",
        "channelMessages.userIsTyping": "%@ is typing…",
        "channelMessages.usersAreTyping": "%@ are typing…",
        "channelMessages.severalPeopleTyping": "Several people are typing…",
        "channelMessages.voiceMessageA11y": "Voice message. Tap to play or pause.",
        "channelMessages.yourLocation": "Your location",
        "channelMessages.locationOf": "%@'s location",
        "channelMessages.clanInviteLoadFailed": "Couldn't load this clan invite.",
        "channelMessages.pollUnsupported": "Polls aren't supported in the app yet.",
        "channelMessages.pollComingSoon": "Coming soon.",

        "channelApp.launchApp": "Launch App",
        "channelApp.help": "Help",
        "channelApp.unavailable": "App unavailable",

        "poll.selectOne": "Select one option",
        "poll.selectOneOrMore": "Select one or more options",
        "poll.voteButton": "Vote",
        "poll.removeVote": "Remove vote",
        "poll.showResults": "Show results",
        "poll.backToVote": "Back to vote",
        "poll.vote": "vote",
        "poll.votes": "votes",
        "poll.ended": "Ended",
        "poll.left": "left",
        "poll.days": "days",
        "poll.hours": "hours",
        "poll.minutes": "minutes",
        "poll.loadMore": "%d more options",
        "poll.loadMore1Option": "1 more option",
        "poll.showLess": "Show less",
        "poll.noVotesYet": "No votes yet",

        "advanced.poll": "Poll",
        "createPoll.title": "Create Poll",
        "createPoll.questionLabel": "Question",
        "createPoll.questionPlaceholder": "What question do you want to ask?",
        "createPoll.answersLabel": "Answers",
        "createPoll.answerPlaceholder": "Type your answer",
        "createPoll.addAnswerButton": "+ Add another answer",
        "createPoll.durationLabel": "Duration",
        "createPoll.multipleAnswersLabel": "Allow multiple answers",
        "createPoll.postButton": "Post",
        "createPoll.selectDuration": "Select Duration",
        "createPoll.cancel": "Cancel",
        "createPoll.hour1": "1 Hour",
        "createPoll.hours4": "4 Hours",
        "createPoll.hours8": "8 Hours",
        "createPoll.hours24": "24 Hours",
        "createPoll.days3": "3 Days",
        "createPoll.week1": "1 Week",

        "chatWelcome.welcomeToChannel": "Welcome to #%@",
        "chatWelcome.startOfChannel": "This is the start of the #%@ %@ channel",
        "chatWelcome.privateChannel": "private",
        "chatWelcome.threadStartedBy": "Started by %@",
        "chatWelcome.beginningOfDM": "This is the very beginning of your legendary conversation with %@",
        "chatWelcome.welcomeToGroup": "Welcome to the beginning of the %@ group.",

        "directMessage.addFriend": "Add Friend",
        "directMessage.you": "You",
        "directMessage.newGroup": "New Group",
        "directMessage.create": "Create",
        "directMessage.searchFriends": "Search friends",
        "directMessage.memberCount": "%d of %d members",
        "directMessage.noFriends": "No friends available",
        "directMessage.memberLimitReached": "Group chats can have up to 20 members.",
        "directMessage.createFailed": "Could not create group.",
        "directMessage.groupCreated": "Group created",
        "directMessage.previewAttachment": "Attachment",
        "directMessage.previewLink": "Link",
        "directMessage.previewLocation": "Location",
        "directMessage.previewContact": "Contact",
        "directMessage.previewEmbed": "embed",

        "friendRequest.title": "Add Friend",
        "friendRequest.received": "Received",
        "friendRequest.sent": "Sent",
        "friendRequest.emptyReceivedTitle": "No incoming friend requests",
        "friendRequest.emptyReceivedDesc": "Here you will see all the friend requests that people send to you.",
        "friendRequest.addByTitle": "Add by username or phone number",
        "friendRequest.addByQuestion": "Who would you like to add as a friend?",
        "friendRequest.addByPlaceholder": "Enter username or phone number",
        "friendRequest.addByHintFormat": "By the way, your username is %@",
        "friendRequest.addBySending": "Sending...",
        "friendRequest.addBySubmit": "Send Friend Request",
        "friendRequest.addByGenericError": "Couldn't send friend request. Please try again.",
        "friendRequest.toastSelfAddError": "Hmm, that didn't work. Double-check that the username is correct",
        "friendRequest.toastBlockedError": "You have blocked this user. Please unblock them before sending a friend request.",
        "friendRequest.toastAlreadyFriend": "You're already friends with that user!",
        "friendRequest.toastWaitAccept": "You have already sent a friend request to this user!",
        "friendRequest.toastIncomingReq": "This user already sent you a friend request",
        "friendRequest.toastSendSuccess": "Friend request sent successfully!",
        "friendRequest.toastAcceptSuccess": "%@ accepted your friend request",

        "friendList.title": "Friends",
        "friendList.friendCount": "Friends",
        "friendList.addFriend": "Add Friend",
        "friendList.searchPlaceholder": "Search",
        "friendList.friendRequest": "Friend requests",
        "friendList.received": "Received",
        "friendList.sent": "Sent",
        "friendList.noResults": "No friends results found",

        "gallery.imageSaved": "Image saved",
        "gallery.imageSaveFailed": "Could not save image",
        "gallery.videoSaved": "Video saved",
        "gallery.videoSaveFailed": "Could not save video",
        "gallery.videoDownloading": "Downloading video...",
        "gallery.videoSaving": "Saving video...",
        "gallery.imageLoadFailed": "Could not load image",
        "gallery.photoPermissionDenied": "Allow photo access to save images",
        "gallery.photoPermissionTitle": "Photo Access Needed",
        "gallery.photoPermissionMessage": "Photo access was denied. Enable Photos access in Settings to save images.",

        "messageAction.reply": "Reply",
        "messageAction.copyText": "Copy Text",
        "messageAction.saveImage": "Save Image",
        "messageAction.saveVideo": "Save Video",
        "messageAction.copyImage": "Copy Image",
        "messageAction.editMessage": "Edit Message",
        "messageAction.editingMessage": "Editing message",
        "messageAction.editedSuffix": "(edited)",
        "messageAction.deleteMessage": "Delete Message",
        "messageAction.deleteMessageConfirm": "Please confirm if you would like to delete this message?",
        "messageAction.pinMessage": "Pin Message",
        "messageAction.unpinMessage": "Unpin Message",
        "messageAction.forward": "Forward",
        "messageAction.copied": "Copied to clipboard",
        "messageAction.giveACoffee": "Give A Coffee",
        "messageAction.giveCoffeeSuccess": "Coffee sent",
        "messageAction.forwardMessage": "Forward Message",
        "messageAction.forwardAll": "Forward All Nearby",
        "messageAction.createThread": "Create Thread",
        "messageAction.markUnread": "Mark Unread",
        "messageAction.topicDiscussion": "Topic Discussion",
        "messageAction.markMessage": "Mark Message",
        "messageAction.quickMenu": "Quick Menu",
        "messageAction.report": "Report",
        "messageAction.pinMessageConfirm": "Please confirm if you would like to pin this message?",
        "messageAction.unpinMessageConfirm": "Remove this message from pinned messages?",
        "messageAction.deleteError": "Failed to delete message",
        "messageAction.pinSuccess": "Message pinned successfully",
        "messageAction.pinError": "Failed to pin message",
        "messageAction.unpinSuccess": "Message unpinned",
        "messageAction.unpinError": "Failed to unpin message",
        "messageAction.yes": "Yes",
        "messageAction.no": "No",

        "reportMessage.title": "Report message",
        "reportMessage.subtitle": "Tell us what went wrong. Your report is anonymous.",
        "reportMessage.selectedMessage": "Why are you reporting this message?",
        "reportMessage.spam": "Spam",
        "reportMessage.harassment": "Harassment or abuse",
        "reportMessage.violentContent": "Harmful misinformation or glorifying violence",
        "reportMessage.private": "Sharing private or identifying information",
        "reportMessage.reportSummary": "Report summary",
        "reportMessage.reviewYourReportBeforeSubmitting": "Review your report before submitting.",
        "reportMessage.reportCategory": "Report category",
        "reportMessage.submitDescription": "If we find this message violates our guidelines, we may remove it and take action on the account.",
        "reportMessage.submitReport": "Submit report",
        "reportMessage.cancel": "Cancel",
        "reportMessage.reportSubmitted": "Report submitted",
        "reportMessage.failed": "Could not submit report. Please try again.",

        "profile.addStatus": "Add Status",
        "profile.editProfile": "Edit Profile",
        "profile.balance": "Balance",
        "profile.transferFunds": "Transfer Funds",
        "profile.transferSend": "Send",
        "profile.transferAmount": "Amount",
        "profile.sendTokenHeading": "Transfer Funds",
        "profile.sendTokenSendToken": "Transfer Funds",
        "profile.sendTokenDebitAccount": "Debit Account",
        "profile.sendTokenSendTo": "Transfer to",
        "profile.sendTokenSendToAddress": "Transfer to address",
        "profile.sendTokenToken": "Amount",
        "profile.sendTokenNote": "Note",
        "profile.sendTokenDefaultNote": "Transfer funds",
        "profile.sendTokenSelectAccount": "Select an account",
        "profile.sendTokenCopyAddressSuccess": "Address copied",
        "profile.sendTokenConfirmTitle": "Confirm transfer",
        "profile.sendTokenConfirmMessage": "Transfer %1$@ %2$@ to %3$@?",
        "profile.sendTokenConfirmAction": "Transfer",
        "profile.sendTokenSuccessTitle": "Funds Transferred",
        "profile.sendTokenComplete": "Done",
        "profile.sendTokenSendNew": "New transfer",
        "profile.sendTokenReceiver": "Receiver",
        "profile.sendTokenDate": "Date",
        "profile.sendTokenErrAmountZero": "Amount must be greater than 0",
        "profile.sendTokenErrExceedWallet": "Amount exceeds your wallet balance",
        "profile.sendTokenErrSelectUser": "Please select a recipient",
        "profile.sendTokenErrSendFailed": "Transfer failed. Please try again.",
        "profile.sendTokenErrSessionExpired": "Your session has expired",
        "profile.sendTokenErrLoginAgain": "Please log in again to continue.",
        "profile.sendTokenLogLinePrefix": "Funds Transferred:",
        "profile.mezonTransfer": "Mezon Transfer",
        "profile.historyTransaction": "History Transaction",
        "profile.historyAll": "All",
        "profile.historyIncoming": "Incoming",
        "profile.historyOutgoing": "Outgoing",
        "profile.historyReceived": "Received",
        "profile.historySent": "Sent",
        "profile.historyTransactionId": "Transaction ID:",
        "profile.historyDetailTitle": "Transaction Details",
        "profile.historyStatus": "Status",
        "profile.historyCompleted": "Completed",
        "profile.historyFailed": "Failed",
        "profile.historyTime": "Time",
        "profile.historyFee": "Network Fee",
        "profile.historyHash": "Hash",
        "profile.historyFrom": "From",
        "profile.historyTo": "To",
        "profile.historySenderName": "Sender name",
        "profile.historyReceiverName": "Receiver name",
        "profile.historyUnknownUser": "Unknown",
        "profile.historyTransactionIdCopied": "Transaction ID copied",
        "profile.historyValue": "Value",
        "profile.aboutMe": "About Me",
        "profile.mezonMemberSince": "Mezon Member Since",
        "profile.yourFriends": "Your Friends",
        "profile.copyUserId": "Copy User ID",
        "profile.userIdCopied": "User ID copied",
        "profile.currency": "đồng",
        "profile.statusTitle": "Update Status",
        "profile.statusDurationLabel": "Status Duration",
        "profile.statusDurationToday": "Today",
        "profile.statusDurationFourHours": "4 hours",
        "profile.statusDurationOneHour": "1 hour",
        "profile.statusDurationThirtyMinutes": "30 minutes",
        "profile.statusDurationDontClear": "Don't clear",
        "profile.statusTooLong": "Status must be at most 128 characters.",
        "profile.statusUpdateFailed": "Could not update status. Please try again.",
        "profile.changeOnlineStatus": "Change Online Status",
        "profile.onlineStatusSection": "Online Status",
        "profile.setCustomStatus": "Set a custom status",
        "profile.userStatusOnline": "Online",
        "profile.userStatusIdle": "Idle",
        "profile.userStatusDoNotDisturb": "Do Not Disturb",
        "profile.userStatusInvisible": "Invisible",
        "profile.presenceUpdateFailed": "Could not change online status. Please try again.",

        "profileSetting.title": "Profile Settings",
        "profileSetting.userProfile": "User Profile",
        "profileSetting.clanProfiles": "Clan Profiles",
        "profileSetting.save": "Save",
        "profileSetting.displayName": "Display name",
        "profileSetting.aboutMe": "About me",
        "profileSetting.clanNickname": "Clan nickname",
        "profileSetting.selectAClan": "Select a Clan",
        "profileSetting.updateSuccess": "Profile updated successfully",
        "profileSetting.updateError": "Failed to update profile",
        "profileSetting.clanUpdateSuccess": "Clan profile updated successfully",
        "profileSetting.duplicateNickname": "This nickname already exists in the clan. Please choose another.",
        "profileSetting.noClanTitle": "You don't have any clan",
        "profileSetting.noClanDesc": "Create or join a clan to get started!",
        "profileSetting.noClanCreateClan": "Create a clan",
        "profileSetting.noClanJoinClan": "Join a clan",
        "profileSetting.directMessageIcon": "Direct Message Icon",

        "qrScanner.title": "Scan QR Code",
        "qrScanner.cameraPermissionTitle": "Camera Access Required",
        "qrScanner.cameraPermissionMessage":
            "Please allow camera access in Settings to scan QR codes.",
        "qrScanner.gallery": "Gallery",
        "qrScanner.invalidQR": "Invalid QR code",
        "qrScanner.loginConfirm": "Do you want to log in with %@?",
        "qrScanner.joinGroup": "Join Group",
        "qrScanner.transferTo": "Transfer to user: %@",
        "qrScanner.processing": "Processing...",
        "qrScanner.logInOnNewDevice": "Log in on a new device?",
        "qrScanner.neverScanLoginQR": "Never scan a login QR code from another user.",
        "qrScanner.youAreIn": "You are in",
        "qrScanner.youAreLoggedInDesktop": "You are now logged in on Desktop",
        "qrScanner.startTalking": "Start Talking",
        "qrScanner.inviteToJoinClan": "INVITE TO JOIN A CLAN",
        "qrScanner.joinClan": "Join",
        "qrScanner.goToClan": "Go to Clan",
        "qrScanner.noThanks": "No, Thanks",
        "qrScanner.message": "Message",
        "qrScanner.userProfile": "USER PROFILE",
        "qrScanner.myQRCode": "My QR Code",
        "qrScanner.qrProfile": "QR Profile",
        "qrScanner.qrTransfer": "QR Transfer",
        "qrScanner.poweredBy": "Powered by Mezon",
        "qrScanner.shareWithOthers": "Share with others",
        "qrScanner.scanProfileHelp": "Scan this QR code to chat with me or view my profile",
        "qrScanner.scanTransferHelp": "Scan this QR code to transfer funds",
        "qrScanner.scanInstruction": "Move camera to QR to scan or",
        "qrScanner.chooseFromGallery": "Choose from Photo Library",
        "qrScanner.sharePersonalQR": "Share personal QR code ˄",
        "qrScanner.luckyMoneyTitle": "Lucky money",
        "qrScanner.luckyMoneyPleaseWait": "Please wait a moment...",
        "qrScanner.luckyMoneyCongratulations": "You received lucky money!",
        "qrScanner.luckyMoneyClaimToWallet": "Claim to wallet",
        "qrScanner.luckyMoneyClaimSuccess": "Claimed successfully",
        "qrScanner.luckyMoneySuccessDone": "Done",
        "qrScanner.luckyMoneyClaimFailed": "Could not claim. Please try again.",
        "qrScanner.luckyMoneyWalletNotReady": "Wallet is not ready. Please try again later.",
        "qrScanner.luckyMoneyServiceNotConfigured": "Claim service is not configured.",
        "qrScanner.luckyMoneyInvalidPayload": "This QR code is not valid lucky money.",
        "qrScanner.scannedPayloadTitle": "Scanned content",
        "qrScanner.copyContent": "Copy",

        "error.networkError": "Network Error",
        "error.connectionFailed": "Connection failed. Please try again.",
        "error.somethingWentWrong": "Something went wrong",
        "error.sessionExpiredTitle": "Session Expired",
        "error.sessionExpiredOrNetwork": "Session Expired or Network Error",
        "error.sessionExpiredContent":  "Your session has expired. Please log in again to continue.",
        "error.sessionExpiredConfirm":  "Login Again",

        "clanSwitch.rapidTitle":   "Slow down a little",
        "clanSwitch.rapidMessage": "You're switching clans quite fast. Give the channel list a few seconds to load so nothing gets interrupted.",
        "clanSwitch.rapidConfirm": "Got it",

        "channelDetail.members": "Members",
        "channelDetail.media":   "Media",
        "channelDetail.images":  "Images",
        "channelDetail.videos":  "Videos",
        "channelDetail.files":   "Files",
        "channelDetail.docs":    "Docs",
        "channelDetail.audios":  "Audios",
        "channelDetail.pins":    "Pins",
        "channelDetail.canvas":  "Canvas",
        "channelDetail.online":  "Online",
        "channelDetail.offline": "Offline",
        "channelDetail.inviteMembers": "Invite Members",
        "channelDetail.newGroup": "New Group",
        "channelDetail.addMembers": "Add Members",
        "channelDetail.untitledCanvas": "Untitled Canvas",
        "channelDetail.searchFilesPlaceholder": "Search files",
        "channelDetail.fileSharedBy": "Shared by %@",
        "channelDetail.noFilesYet": "No files yet",
        "channelDetail.noMediaYet": "No photos or videos yet",
        "channelDetail.pinAttachmentPreview": "Attachment",
        "channelDetail.pinContactPreview": "Contact",
        "channelDetail.pinEmbedPreview": "Embed",
        "channelDetail.noPinsYet": "No pinned messages",
        "channelDetail.unpinError": "Couldn’t unpin message. Try again.",
        "channelDetail.unpinConfirmTitle": "Unpin this message?",
        "channelDetail.unpinConfirmBody": "It will be removed from pinned for everyone in this channel.",
        "channelDetail.unpinConfirmAction": "Unpin",
        "channelDetail.customizeGroup": "Customize Group",
        "channelDetail.leaveGroup": "Leave Group",
        "channelDetail.deleteGroup": "Delete Group",
        "channelDetail.leaveGroupConfirmTitle": "Leave this group?",
        "channelDetail.leaveGroupConfirmBody": "You will stop receiving messages from this group.",
        "channelDetail.deleteGroupConfirmTitle": "Delete this group?",
        "channelDetail.deleteGroupConfirmBody": "This group will be deleted for everyone.",
        "channelDetail.groupName": "Group Name",
        "channelDetail.removeGroupLogo": "Remove Group Logo",
        "channelDetail.groupNameRequired": "Group name is required.",
        "channelDetail.groupUpdated": "Group updated",
        "channelDetail.groupLeft": "You left the group",
        "channelDetail.groupDeleted": "Group deleted",
        "channelDetail.updateGroupFailed": "Could not update group.",
        "channelDetail.leaveGroupFailed": "Could not leave group.",
        "channelDetail.removeFromGroup": "Remove From Group",
        "channelDetail.removeFromGroupConfirmTitle": "Remove from group?",
        "channelDetail.removeFromGroupConfirmBody": "%@ will be removed from this group.",
        "channelDetail.removeFromGroupConfirmAction": "Remove",
        "channelDetail.removeFromGroupFailed": "Could not remove member.",
        "channelDetail.memberRemoved": "Member removed",

        "dmMenu.leaveGroup": "Leave Group",
        "dmMenu.deleteGroup": "Delete Group",
        "dmMenu.closeDm": "Close DM",
        "dmMenu.closeDmConfirmTitle": "Close %@",
        "dmMenu.closeDmConfirmMessage": "Are you sure you want to close this conversation with %@?",
        "dmMenu.markAsRead": "Mark as Read",
        "dmMenu.muteConversation": "Mute Conversation",
        "dmMenu.unmuteConversation": "Unmute Conversation",
        "dmMenu.blockUser": "Block User",
        "dmMenu.unblockUser": "Unblock User",
        "dmMenu.removeFriend": "Remove Friend",
        "dmMenu.addFriend": "Add Friend",
        "dmMenu.members": "%d members",
        "dmMenu.blockUserSuccess": "User blocked successfully",
        "dmMenu.blockUserError": "Failed to block user",
        "dmMenu.unblockUserSuccess": "User unblocked successfully",
        "dmMenu.unblockUserError": "Failed to unblock user",

        "embed.onlyVisibleToRecipient": "Only visible to recipient",

        "callLog.cancel":           "You canceled",
        "callLog.missed":           "You missed",
        "callLog.receiverRejected": "Receiver rejected",
        "callLog.youRejected":      "You rejected",
        "callLog.audioCall":        "Audio call",
        "callLog.videoCall":        "Video call",
        "callLog.callBack":         "Call back",
        "callLog.incomingCall":     "Incoming call",
        "callLog.outGoingCall":     "Outgoing call",
        "callLog.startGroupCall":   "%@ started a group call",
        "callLog.startAudioCall":   "%@ started an audio call",
        "callLog.startVideoCall":   "%@ started a video call",
        "callLog.callDurationPrefix": "Call duration: ",

        "peerCall.actionEnd":               "End",
        "peerCall.actionMic":               "Mic",
        "peerCall.actionSpeaker":           "Speaker",
        "peerCall.actionCancel":            "Cancel",
        "peerCall.actionOK":                "OK",
        "peerCall.titleDefaultOutgoing":    "Call",
        "peerCall.titleDefaultIncoming":    "Incoming call",
        "peerCall.statusRinging":           "Ringing…",
        "peerCall.statusIncoming":          "Incoming…",
        "peerCall.statusConnecting":        "Connecting…",
        "peerCall.statusConnected":         "Connected",
        "peerCall.statusMissed":            "Missed call",
        "peerCall.statusNoAnswer":          "No answer",
        "peerCall.statusCouldNotConnect":   "Could not connect",
        "peerCall.statusUnlockForMicrophone": "Unlock your phone to allow microphone access",
        "peerCall.errorMicrophoneDenied":   "Microphone access denied",
        "peerCall.micPermissionTitle":      "Microphone",
        "peerCall.micPermissionBody":       "Allow microphone access in Settings to join this call.",
        "peerCall.errorCameraDenied":       "Camera access denied",
        "peerCall.errorCouldNotStartCall":  "Could not start call",
        "peerCall.errorCouldNotAnswerCall": "Could not answer call",
        "peerCall.alertEndCallTitle":       "End Call",
        "peerCall.alertEndCallMessage":     "Please confirm if you would like to end the call?",
        "peerCall.bannerWeakNetwork":       "Weak network — reconnecting…",
        "peerCall.remoteMicOffBanner":      "%@ turned the microphone off",

        "auditLog.title": "Audit Log",
        "auditLog.filterBtn": "Filter",
        "auditLog.filterByUser": "Filter by User",
        "auditLog.filterByAction": "Filter by Action",
        "auditLog.allUsers": "All Users",
        "auditLog.allActions": "All Actions",
        "auditLog.empty": "No logs found.",
        "auditLog.add": "added",
        "auditLog.remove": "removed",
        "auditLog.toChannel": "to channel",
        "auditLog.updateClan": "Update Clan",
        "auditLog.createChannel": "Create Channel",
        "auditLog.updateChannel": "Update Channel",
        "auditLog.updateChannelPrivate": "Update Channel Private",
        "auditLog.deleteChannel": "Delete Channel",
        "auditLog.createChannelPermission": "Create Channel Permission",
        "auditLog.updateChannelPermission": "Update Channel Permission",
        "auditLog.deleteChannelPermission": "Delete Channel Permission",
        "auditLog.kickMember": "Kick Member",
        "auditLog.pruneMember": "Prune Member",
        "auditLog.banMember": "Ban Member",
        "auditLog.unbanMember": "Unban Member",
        "auditLog.updateMember": "Update Member",
        "auditLog.updateRolesMember": "Update Roles Member",
        "auditLog.moveMember": "Move Member",
        "auditLog.disconnectMember": "Disconnect Member",
        "auditLog.addBot": "Add Bot",
        "auditLog.createThread": "Create Thread",
        "auditLog.updateThread": "Update Thread",
        "auditLog.deleteThread": "Delete Thread",
        "auditLog.createRole": "Create Role",
        "auditLog.updateRole": "Update Role",
        "auditLog.deleteRole": "Delete Role",
        "auditLog.createWebhook": "Create Webhook",
        "auditLog.updateWebhook": "Update Webhook",
        "auditLog.deleteWebhook": "Delete Webhook",
        "auditLog.createEmoji": "Create Emoji",
        "auditLog.updateEmoji": "Update Emoji",
        "auditLog.deleteEmoji": "Delete Emoji",
        "auditLog.createSticker": "Create Sticker",
        "auditLog.updateSticker": "Update Sticker",
        "auditLog.deleteSticker": "Delete Sticker",
        "auditLog.createEvent": "Create Event",
        "auditLog.updateEvent": "Update Event",
        "auditLog.deleteEvent": "Delete Event",
        "auditLog.createCanvas": "Create Canvas",
        "auditLog.updateCanvas": "Update Canvas",
        "auditLog.deleteCanvas": "Delete Canvas",
        "auditLog.createCategory": "Create Category",
        "auditLog.updateCategory": "Update Category",
        "auditLog.deleteCategory": "Delete Category",
        "auditLog.addMemberChannel": "Add Member to Channel",
        "auditLog.removeMemberChannel": "Remove Member from Channel",
        "auditLog.addRoleChannel": "Add Role to Channel",
        "auditLog.removeRoleChannel": "Remove Role from Channel",
        "auditLog.addMemberThread": "Add Member to Thread",
        "auditLog.removeMemberThread": "Remove Member from Thread",
        "auditLog.addRoleThread": "Add Role to Thread",
        "auditLog.removeRoleThread": "Remove Role from Thread",
        
        "mediaPanel.emoji": "Emojis",
        "mediaPanel.gifs": "GIFs",
        "mediaPanel.stickers": "Stickers",
        "mediaPanel.search": "Search",
        "mediaPanel.findGif": "Find the perfect GIF",
        "mediaPanel.findEmoji": "Find the perfect emoji",
        "mediaPanel.findSticker": "Find the perfect sticker",
        "mediaPanel.findReaction": "Find the perfect reaction",
        "mediaPanel.trendingGifs": "Trending GIFs",
        "mediaPanel.emptyGifs": "GIFs will appear here",
    ]

    private static let vi: [String: String] = [
        "tab.clans":            "Kênh",
        "tab.messages":         "Tin nhắn",
        "tab.notifications":    "Thông báo",
        "tab.profile":          "Hồ sơ",

        "common.settings":      "Cài đặt",
        "common.save":          "Lưu",
        "common.cancel":        "Hủy",
        "common.confirm":       "Xác nhận",
        "common.delete":        "Xóa",
        "common.search":        "Tìm kiếm",
        "common.logOut":        "Đăng xuất",
        "common.deleteAccount": "Xóa tài khoản",
        "common.refresh":       "Làm mới",
        "common.close":         "Đóng",
        "common.goBack":        "Quay lại",
        "common.copy":          "Sao chép",
        "common.share":         "Chia sẻ",
        "common.download":      "Tải xuống",
        "common.forward":       "Chuyển tiếp",
        "common.comingSoon":    "Sắp ra mắt",
        "common.forwarded":     "Đã chuyển tiếp",
        "common.saveChanges":   "Lưu thay đổi",
        "common.enable":        "Bật",
        "common.reset":         "Đặt lại",
        "common.loading":       "Đang tải...",
        "common.actions":       "Hành động",
        "common.notifications": "Thông báo",
        "common.appearance":    "Giao diện",
        "common.theme":         "Chủ đề",
        "common.language":      "Ngôn ngữ",
        "common.linkEmail":     "Thêm email",
        "common.linkPhoneNumber": "Thêm số điện thoại",
        "common.detail":        "Chi tiết",

        "imageEditor.send":   "Gửi",
        "imageEditor.draw":   "Vẽ",
        "imageEditor.text":   "Văn bản",
        "imageEditor.crop":   "Cắt",
        "imageEditor.rotate": "Xoay",
        "imageEditor.done":   "Xong",

        "mediaPicker.edit":      "Chỉnh sửa",
        "mediaPicker.doneCount": "Xong (%d)",
        "mediaPicker.sizeLimit": "Bạn chỉ có thể chọn tối đa %dGB.",

        "updateGate.outOfDateVersion": "Phiên Bản Mới Đã Sẵn Sàng",
        "updateGate.updateExperience": "Cần cập nhật nhanh để tiếp tục sử dụng các tính năng gia đình mới nhất của chúng tôi.",
        "updateGate.updateNow": "Cập nhật ngay",
        "updateGate.versionInfo": "PHIÊN BẢN",

        "accountSetting.accountInformation": "Thông tin tài khoản",
        "accountSetting.users": "Người dùng",
        "accountSetting.accountManagement": "Quản lý tài khoản",
        "accountSetting.username": "Tên đăng nhập",
        "accountSetting.displayName": "Tên hiển thị",
        "accountSetting.blockedUsers": "Người dùng bị chặn",
        "accountSetting.unblock": "Bỏ chặn",
        "accountSetting.noBlockedUsers": "Bạn chưa chặn ai cả.",
        "accountSetting.setPassword": "Đặt mật khẩu",
        "accountSetting.phoneNumberSetting.title": "Số điện thoại",
        "accountSetting.emailSetting.title": "Email",
        "accountSetting.deleteAccountAlert.title": "Xóa tài khoản",
        "accountSetting.deleteAccountAlert.description": "Bạn có chắc muốn xóa tài khoản?",
        "accountSetting.deleteAccountAlert.yesConfirm": "Có",
        "accountSetting.deleteAccountAlert.noConfirm": "Không",
        "accountSetting.toast.deleteAccount.success": "Đã xóa tài khoản thành công",
        "accountSetting.toast.deleteAccount.error": "Bạn đang là chủ clan",
        "accountSetting.requireLinkEmail.title": "Yêu cầu liên kết Email",
        "accountSetting.requireLinkEmail.description": "Bạn cần liên kết email trước khi đặt mật khẩu.",
        "accountSetting.requireLinkEmail.action": "Liên kết Email",

        "setPassword.title": "Đặt mật khẩu",
        "setPassword.save": "Lưu",
        "setPassword.email": "Email",
        "setPassword.currentPassword": "Mật khẩu hiện tại",
        "setPassword.currentPasswordPlaceholder": "Nhập mật khẩu hiện tại",
        "setPassword.password": "Mật khẩu",
        "setPassword.passwordPlaceholder": "Nhập mật khẩu mới",
        "setPassword.confirmPassword": "Xác nhận mật khẩu",
        "setPassword.confirmPasswordPlaceholder": "Xác nhận mật khẩu mới",
        "setPassword.description": "Mật khẩu phải có ít nhất 8 ký tự và bao gồm ít nhất một chữ hoa, một chữ thường, một số và một ký tự đặc biệt (ví dụ: !@#$%^&*).",
        "setPassword.error.characters": "Mật khẩu phải có ít nhất 8 ký tự",
        "setPassword.error.uppercase": "Mật khẩu phải có ít nhất một chữ hoa",
        "setPassword.error.lowercase": "Mật khẩu phải có ít nhất một chữ thường",
        "setPassword.error.number": "Mật khẩu phải có ít nhất một số",
        "setPassword.error.symbol": "Mật khẩu phải có ít nhất một ký tự đặc biệt",
        "setPassword.error.samePass": "Mật khẩu mới phải khác mật khẩu hiện tại",
        "setPassword.error.notEqual": "Mật khẩu không khớp",
        "setPassword.error.incorrectCurrent": "Mật khẩu hiện tại không đúng",
        "setPassword.error.updateFail": "Không thể cập nhật mật khẩu",
        "setPassword.error.createFail": "Không thể đặt mật khẩu",
        "setPassword.toast.success": "Cập nhật mật khẩu thành công",
        "setPassword.toast.error": "Đã xảy ra lỗi. Vui lòng thử lại.",

        "emailSetting.updateEmailTitle": "Cập nhật Email",
        "emailSetting.newEmail": "Email mới",
        "emailSetting.nextButton": "Tiếp tục",
        "emailSetting.invalidEmail": "Địa chỉ email không hợp lệ",
        "emailSetting.emailAlreadyLinked": "Email này đã được liên kết",
        "emailSetting.tooFast": "Vui lòng đợi %ds trước khi gửi lại",
        "emailSetting.updateFailed": "Không thể cập nhật email. Vui lòng thử lại.",
        "emailSetting.verifyEmailTitle": "Xác thực Email",
        "emailSetting.verifyDescription": "Nhập mã gồm 6 chữ số chúng tôi đã gửi tới",
        "emailSetting.verifyButton": "Xác thực",
        "emailSetting.verifySuccess": "Liên kết email thành công",

        "phoneSetting.updatePhoneTitle": "Cập nhật số điện thoại",
        "phoneSetting.newPhoneNumber": "Số điện thoại mới",
        "phoneSetting.phonePlaceholder": "Số điện thoại",
        "phoneSetting.nextButton": "Tiếp tục",
        "phoneSetting.invalidPhoneNumber": "Số điện thoại không hợp lệ",
        "phoneSetting.phoneAlreadyLinked": "Số điện thoại này đã được liên kết",
        "phoneSetting.tooFast": "Vui lòng đợi %ds trước khi gửi lại",
        "phoneSetting.updateFailed": "Không thể cập nhật số điện thoại. Vui lòng thử lại.",
        "phoneSetting.verifyPhoneTitle": "Xác thực số điện thoại",
        "phoneSetting.verifyDescription": "Nhập mã gồm 6 chữ số chúng tôi đã gửi tới",
        "phoneSetting.verifyButton": "Xác thực",
        "phoneSetting.verifySuccess": "Liên kết số điện thoại thành công",

        "settings.title":           "Cài đặt",
        "settings.language":        "Ngôn ngữ",
        "settings.theme":           "Chủ đề",
        "settings.notifications":   "Thông báo",
        "settings.account":         "Tài khoản",
        "settings.privacy":         "Quyền riêng tư",
        "settings.accountSettings": "Cài đặt tài khoản",
        "settings.appSettings":     "Cài đặt ứng dụng",
        "settings.friendRequests":  "Lời mời kết bạn",
        "settings.myQRCode":        "Mã QR của tôi",
        "settings.qrScan":          "Quét mã QR",
        "settings.devices":         "Thiết bị",
        "settings.appVersion":      "Phiên bản ứng dụng",
        "settings.appearance":      "Giao diện",
        "settings.logout":          "Đăng xuất",
        "settings.noSearchResults": "Không tìm thấy kết quả",

        "language.title":         "Cài đặt ngôn ngữ",

        "theme.title":            "Chủ đề ứng dụng",
        "theme.conversation":     "Hội thoại",
        "theme.canChangeLater":   "Bạn có thể thay đổi bất cứ lúc nào!",
        "theme.dark":             "Tối",
        "theme.light":            "Sáng",
        "theme.sunrise":          "Bình minh",
        "theme.redDark":          "Đỏ đậm",
        "theme.purpleHaze":       "Tím mộng mơ",
        "theme.abyssDark":        "Vực thẳm tối",
        "theme.sunset":           "Hoàng hôn",
        "theme.system":           "Hệ thống",

        "login.welcomeBack":    "CHÀO MỪNG TRỞ LẠI",
        "login.email":          "Email",
        "login.password":       "Mật khẩu",
        "login.logIn":          "Đăng nhập",
        "login.otp":            "Mã xác thực (OTP)",
        "login.sendOTP":        "Gửi OTP",
        "login.resendOTP":      "Gửi lại OTP",
        "login.loginFailed":    "Email hoặc mật khẩu không hợp lệ. Vui lòng thử lại.",
        "login.phone":          "Số điện thoại",
        "login.enterEmail":     "Nhập email của bạn",
        "login.enterPhone":     "Nhập số điện thoại của bạn",
        "login.chooseAnotherOption":   "Hoặc chọn phương thức khác",
        "login.emailAddress":   "Địa chỉ email",
        "login.send":           "Gửi OTP",
        "login.showPassword":   "Hiển thị mật khẩu",
        "login.cannotAccessYourEmail":  "Không thể truy cập hộp thư?",
        "login.cannotAccessYourPhone":  "Không thể truy cập số điện thoại?",
        "login.passwordNotSet": "Chưa đặt mật khẩu?",
        "login.loginWithSMS":   "Đăng nhập bằng SMS OTP",
        "login.loginWithEmailOTP": "Đăng nhập bằng Email OTP",
        "login.loginWithPassword": "Đăng nhập bằng Email & Mật khẩu",
        "login.invalidPhoneNumber": "Số điện thoại không hợp lệ",
        "login.loginTooFast":   "Vui lòng đợi trước khi thử lại",
        "login.resendInSeconds": "Gửi lại sau %ds",
        "login.selectCountry":  "Chọn mã vùng",

        "welcome.title":        "Chào mừng đến với Mezon",
        "welcome.subtitle":     "Nền tảng Kết nối, Làm việc,\nvà Giải trí",
        "welcome.startNow":     "Bắt đầu nào",

        "notifications.title": "Thông báo",
        "notifications.mentions": "Nhắc đến",
        "notifications.messages": "Tin nhắn",
        "notifications.forYou": "Dành cho bạn",
        "notifications.topic": "Thảo luận ngắn",
        "notifications.empty.title": "Chưa có gì ở đây",
        "notifications.empty.description": "Quay lại để nhận thông báo về sự kiện và nhiều hơn thế nữa",
        "notifications.topicDiscussion": "THẢO LUẬN CHỦ ĐỀ",
        "notifications.repliedTo": "Tin nhắn gốc: ",
        "notifications.topicOriginalAttachment": "[Tệp đính kèm]",
        "notifications.topicOriginalContact": "[Liên hệ]",
        "notifications.topicOriginalInteractiveMessage": "[Tin nhắn tương tác]",
        "notifications.sender": "Người gửi: ",
        "notifications.unreachableMessage": "Tin nhắn không khả dụng",

        "otpVerify.loginToMezon":      "Đăng nhập tài khoản Mezon",
        "otpVerify.enterCodeFrom":     "Nhập mã từ",
        "otpVerify.verifyOTP":         "Xác thực OTP",
        "otpVerify.resendOTP":         "Gửi lại OTP",
        "otpVerify.otpNotMatch":       "Mã OTP không hợp lệ",
        "otpVerify.didNotReceiveCode": "Không nhận được mã?",
        "otpVerify.changeEmail":       "Đổi Email",
        "otpVerify.changePhone":       "Đổi số điện thoại",
        "otpVerify.resendFailed":      "Không thể gửi lại OTP. Vui lòng thử lại.",
        "otpVerify.sendOtpError":      "Không thể gửi mã OTP. Vui lòng thử lại.",

        "updateUsername.enterUsername": "Nhập tên Mezon",
        "updateUsername.usernamePlaceholder": "Hãy dùng tên thật để mọi người dễ nhận ra bạn",
        "updateUsername.yourName": "Tên của bạn...",
        "updateUsername.usernamePreview": "Tên người dùng: %@",
        "updateUsername.update": "Cập nhật",
        "updateUsername.errorDuplicate": "Có sự cố hoặc tên đã tồn tại, vui lòng chọn tên khác.",
        "updateUsername.errorGeneric": "Có lỗi xảy ra vui lòng thử lại hoặc nhập 1 cái tên khác",
        "updateUsername.skipUpdateQuestion": "Muốn đăng nhập lại với số điện thoại của bạn?",
        "updateUsername.skipUpdateBack": "Quay lại đăng nhập với số điện thoại",

        "clan.createClan":  "Tạo Clan",
        "clan.joinClanTitle": "Tham gia clan",
        "clan.inviteInputPlaceholder": "Liên kết hoặc mã mời",
        "clan.newClanNamePlaceholder": "Tên clan",
        "clan.joinAction": "Tham gia",
        "clan.inviteInvalid": "Nhập liên kết hoặc mã mời hợp lệ",
        "clan.nameRequired": "Nhập tên clan",
        "clan.createClanBannerTitle": "Ảnh bìa",
        "clan.createClanLogoTitle": "Biểu tượng clan",
        "clan.createClanAddBanner": "Thêm ảnh bìa",
        "clan.createClanAddIcon": "Thêm biểu tượng",
        "clan.createClanNameSection": "Tên clan",
        "clan.createYourClanTitle": "Tạo clan của bạn",
        "clan.createClanIntroBody": "Tạo không gian riêng để kết nối với bạn bè. Xây dựng clan và bắt đầu trò chuyện ngay hôm nay.",
        "clan.createMyOwnTitle": "Tự tạo",
        "clan.startFromTemplateSection": "BẮT ĐẦU TỪ MẪU",
        "clan.createTemplateGaming": "Gaming",
        "clan.createTemplateFriends": "Bạn bè",
        "clan.createTemplateStudyGroup": "Nhóm học",
        "clan.createTemplateSchoolClub": "Câu lạc bộ",
        "clan.createTemplateLocalCommunity": "Cộng đồng địa phương",
        "clan.createTemplateArtists": "Nghệ sĩ & sáng tạo",
        "clan.customizeClanTitle": "Tùy chỉnh clan",
        "clan.customizeClanSubtitle": "Đặt tên và biểu tượng cho clan mới. Bạn có thể thay đổi sau.",
        "clan.clanNameInvalidFormat": "Tên clan không hợp lệ (tối đa 64 ký tự, chỉ chữ, số, dấu cách, _ hoặc -).",
        "clan.createClanAgreementPrefix": "Khi tạo clan, bạn đồng ý với ",
        "clan.createClanAgreementLink": "Quy định cộng đồng của Mezon",
        "clan.uploadWordmark": "TẢI LÊN",
        "clan.members":     "Thành viên",
        "clan.settings":    "Cài đặt Clan",
        "clan.duplicateName": "Tên Clan đã tồn tại. Vui lòng nhập tên khác.",
        "clan.invalidName": "Vui lòng nhập tên clan hợp lệ (tối đa 64 ký tự, chỉ từ, số, _ hoặc -).",
        "clan.creationLimitReached": "Bạn đã đạt giới hạn tạo clan.",

        "discover.communityOnMezon": "Cộng đồng trên Mezon",
        "discover.exploreCommunities": "Khám phá cộng đồng",
        "discover.membersLabel": "%d thành viên",
        "discover.verified": "Đã xác minh",
        "discover.joinClan": "Tham gia Clan",
        "discover.noCommunities": "Không có cộng đồng để hiển thị.",
        "discover.noMatchingCommunities": "Không có cộng đồng trùng khớp.",
        "discover.loadFailed": "Không tải được danh sách. Kéo để thử lại.",
        "discover.detail.howChatty": "Độ sôi nổi?",
        "discover.detail.clanCreated": "Ngày tạo clan",
        "discover.detail.feature": "Tính năng",
        "discover.detail.communityRow": "Cộng đồng",
        "discover.detail.about": "Giới thiệu",
        "discover.detail.chattyBusy": "Như một quán cà phê đông đúc",
        "discover.detail.chattyModerate": "Khá hoạt động",
        "discover.detail.chattyQuiet": "Khá yên tĩnh",
        "discover.detail.featureFallback": "Trải nghiệm các tính năng chính thức của clan!",
        "discover.detail.communityFallback": "Kết nối với thành viên và khám phá kênh.",
        "discover.detail.communityVerified": "Sự kiện và cập nhật hàng tuần.",
        "discover.detail.dateUnavailable": "—",

        "eventMenu.dashboard.title":              "Sự kiện",
        "eventMenu.dashboard.event_one":          "Sự kiện",
        "eventMenu.dashboard.noEvent":            "Không có sự kiện nào",
        "eventMenu.dashboard.noEventDescription": "Hãy thoải mái mời các thành viên khác tham gia đóng góp ý tưởng cho các sự kiện sắp tới.",
        "eventMenu.dashboard.createButton":     "Tạo",
        "eventMenu.eventDetail.clanEvent":        "Sự kiện Clan",
        "eventMenu.eventDetail.channelEvent":     "Sự kiện kênh",
        "eventMenu.eventDetail.privateEvent":     "Sự kiện riêng",
        "eventMenu.eventDetail.eventIsTaking":    "Sự kiện đang diễn ra!",
        "eventMenu.eventDetail.tenMinutesLeft":   "Còn %d phút. Tham gia ngay!",
        "eventMenu.eventDetail.newEvent":         "Mới",
        "eventMenu.eventDetail.privateRoom":      "Phòng riêng",
        "eventMenu.eventDetail.channelAudience":  "Đối tượng là thành viên từ kênh: %@",
        "eventMenu.detail.eventInfo":             "Thông tin sự kiện",
        "eventMenu.detail.interested":            "Quan tâm",
        "eventMenu.detail.noOneInterested":       "Chưa có ai quan tâm sự kiện này.",
        "eventMenu.detail.onePersonInterested":   "1 người quan tâm",
        "eventMenu.detail.personInterested":      "%d người quan tâm",
        "eventMenu.detail.createdBy":             "Tạo bởi ",
        "eventMenu.item.interested":              "Quan tâm",
        "eventMenu.item.uninterested":            "Bỏ quan tâm",

        "clan.action.invite":               "Mời",
        "clan.action.markAsRead":           "Đánh dấu là đã đọc",
        "category.creator.title":           "Tạo danh mục",
        "category.creator.create":          "Tạo",
        "category.creator.nameTitle":       "Danh mục mới",
        "category.creator.namePlaceholder": "Tên danh mục",
        "category.creator.nameError":       "Vui lòng nhập tên danh mục hợp lệ (tối đa 64 ký tự, chỉ từ, số, _ hoặc -).",
        "category.creator.duplicateName":   "Tên danh mục đã tồn tại.",
        "clan.action.createEvent":          "Tạo sự kiện",
        "clan.action.createCategory":       "Tạo danh mục",
        "clan.action.editClanProfile":      "Chỉnh sửa hồ sơ Clan",
        "clan.action.auditLog" :            "Nhật kí kiểm tra",
        "clan.action.leaveClan":            "Rời Clan",
        "clan.action.deleteClan":           "Xóa Clan",
        "deleteClanModal.title":            "Xóa Clan",
        "deleteClanModal.description":      "Bạn có chắc chắn muốn xóa %@? Hành động này không thể hoàn tác.",
        "deleteClanModal.titleLeaveClan":   "Rời clan",
        "deleteClanModal.descriptionLeaveClan": "Bạn có chắc chắn muốn rời khỏi %@ không? Bạn sẽ không thể tham gia lại clan này trừ khi bạn được mời lại.",
        "deleteClanModal.confirm":          "Có",
        "deleteClanModal.error":            "Đã xảy ra lỗi khi cố gắng xóa/rời clan",
        "clan.action.showEmptyCategories":  "Hiển thị danh mục trống",
        "clan.action.onlineCount":          "%d Đang trực tuyến",
        "clan.action.memberCount":          "%d Thành viên",
        "clan.action.community":            "Cộng đồng",

        "clan.setting.overview":            "Tổng quan",
        "clan.setting.auditLog":            "Nhật ký hoạt động",
        "clan.setting.integrations":        "Tích hợp",
        "clan.setting.emoji":               "Biểu cảm",
        "clan.setting.sticker":             "Nhãn dán",
        "clan.setting.soundEffect":         "Hiệu ứng âm thanh",
        "clan.setting.enableCommunity":     "Bật cộng đồng",
        "clan.setting.userManagement":      "Quản lý người dùng",
        "clan.setting.roles":               "Vai trò",
        "clan.setting.invites":             "Lời mời",

        "clan.setting.overview.title": "Tổng quan",
        "clan.setting.overview.save": "Lưu",
        "clan.setting.overview.clanName": "Tên clan",
        "clan.setting.overview.chooseImage": "Đặt ảnh bìa clan",
        "clan.setting.overview.systemMessage.title": "Kênh tin nhắn hệ thống",
        "clan.setting.overview.systemMessage.channel": "Kênh",
        "clan.setting.overview.systemMessage.noChannel": "Không có kênh tin nhắn hệ thống",
        "clan.setting.overview.systemMessage.welcomeRandom": "Gửi tin nhắn chào mừng ngẫu nhiên khi ai đó tham gia vào clan này",
        "clan.setting.overview.systemMessage.welcomeSticker": "Gửi mẹo hữu ích cho thiết lập clan",
        "clan.setting.overview.systemMessage.hideAuditLog": "Gửi nhật ký khi một hành động được áp dụng cho clan",
        "clan.setting.overview.systemMessage.description": "Đây là kênh nhận thông báo về các sự kiện của hệ thống. Bạn có thể tắt chúng bất cứ lúc nào.",
        "clan.setting.overview.uploadFileTooLarge10MB": "Kích thước ảnh không được vượt quá 10MB.",
        "clan.setting.overview.uploadFileTooLarge1MB": "Kích thước ảnh không được vượt quá 1MB.",
        "clan.setting.overview.removeAvatarTitle": "Xóa ảnh đại diện",
        "clan.setting.overview.removeAvatarMessage": "Bạn có chắc chắn muốn xóa ảnh đại diện của clan không?",
        "clan.setting.overview.anonymous.title": "Chế độ ẩn danh",
        "clan.setting.overview.anonymous.description": "Chặn thành viên sử dụng chế độ ẩn danh",
        "clan.setting.overview.defaultNotification.title": "Cài đặt thông báo mặc định",
        "clan.setting.overview.defaultNotification.all": "Tất cả tin nhắn",
        "clan.setting.overview.defaultNotification.mention": "Chỉ @mention",
        "clan.setting.overview.defaultNotification.none": "Không có gì",
        "clan.setting.overview.defaultNotification.description": "Thiết lập này sẽ xác định liệu các thành viên chưa thiết lập rõ ràng cài đặt thông báo của họ có nhận thông báo cho mọi tin nhắn được gửi trong clan này hay không. Chúng tôi khuyến nghị cho các cộng đồng clan chỉ nên đặt thông báo cho @mention.",
        "clan.setting.overview.deleteClan": "Xóa clan",
        "clan.setting.overview.toast.saveSuccess": "Đã lưu cài đặt thành công",
        "clan.setting.overview.toast.saveError": "Không thể lưu cài đặt",
        "clan.setting.overview.toast.duplicateName": "Tên clan đã tồn tại",
        "clan.setting.overview.toast.permissionDenied": "Bạn không có quyền",
        "clan.setting.overview.toast.invalidName": "Tên clan không hợp lệ",
        "clan.setting.overview.deleteClan.confirmTitle": "Xóa clan",
        "clan.setting.overview.deleteClan.confirmMessage": "Bạn có chắc muốn xóa clan này? Hành động này không thể hoàn tác.",

        "clan.setting.members.title": "Thành viên",
        "clan.setting.members.searchPlaceholder": "Tìm kiếm thành viên",
        "clan.setting.members.manageUserTitle": "Chỉnh sửa thành viên",
        "clan.setting.members.roles": "Vai trò",
        "clan.setting.members.editRoles": "Chỉnh sửa vai trò",
        "clan.setting.members.transferOwnership": "Chuyển quyền sở hữu",
        "clan.setting.members.kick": "Khai trừ",
        "clan.setting.members.kickTitle": "Khai trừ thành viên",
        "clan.setting.members.kickFromClan": "Khai trừ %@ ra khỏi clan",
        "clan.setting.members.kickConfirmation": "Bạn có chắc chắn muốn khai trừ %@ ra khỏi clan? Họ có thể tham gia lại bằng lời mời mới.",
        "clan.setting.members.kickReason": "Lý do khai trừ",
        "clan.setting.members.kickButton": "Khai trừ",
        "clan.setting.members.kickSuccess": "Đã khai trừ thành viên",
        "clan.setting.members.kickFailed": "Khai trừ thành viên thất bại",
        "clan.setting.members.transferTitle": "Chuyển quyền sở hữu",
        "clan.setting.members.transferWarning": "Điều này sẽ chuyển quyền sở hữu của %@ cho %@. Hành động này không thể hoàn tác!",
        "clan.setting.members.transferAcknowledgmentTitle": "Chuyển quyền sở hữu",
        "clan.setting.members.transferAcknowledgment": "Tôi xác nhận rằng bằng cách chuyển quyền sở hữu của clan này cho %@, nó sẽ thuộc về họ.",
        "clan.setting.members.transferButton": "Chuyển",
        "clan.setting.members.transferSuccess": "Chuyển quyền sở hữu thành công",
        "clan.setting.members.transferFailed": "Chuyển quyền sở hữu thất bại",

        "clan.setting.stickers.duplicateName": "Tên nhãn dán đã tồn tại",
        "clan.setting.stickers.updateSuccess": "Cập nhật nhãn dán thành công",
        "clan.setting.stickers.deleteConfirmTitle": "Xoá nhãn dán",
        "clan.setting.stickers.deleteConfirmDesc": "Bạn có chắc muốn xoá nhãn dán này?",
        "clan.setting.stickers.deleteSuccess": "Đã xoá nhãn dán thành công",
        "clan.setting.stickers.empty": "Chưa có nhãn dán nào",
        "clan.setting.stickers.create": "Tạo nhãn dán",
        "clan.setting.stickers.createSuccess": "Tạo nhãn dán thành công",
        "clan.setting.stickers.validateName": "Độ dài phải từ %d - %d ký tự. Chỉ cho phép chữ, số, _ và -.",
        "clan.setting.stickers.errorUpdating": "Cập nhật nhãn dán thất bại. Vui lòng thử lại.",
        "clan.setting.stickers.uploadLimit": "Đã đạt giới hạn tải nhãn dán",
        "clan.setting.stickers.uploadButton": "Tải lên nhãn dán",
        "clan.setting.stickers.uploadRequirementsTitle": "Yêu cầu tải lên",
        "clan.setting.stickers.uploadRequirement1": "Có thể là ảnh tĩnh (PNG) hoặc ảnh động (GIF).",
        "clan.setting.stickers.uploadRequirement2": "Phải chính xác 320 x 320 pixel.",
        "clan.setting.stickers.uploadRequirement3": "Không lớn hơn 512KB.",
        "clan.setting.stickers.uploadFileTooLarge": "Ảnh không được lớn hơn 512KB.",
        "clan.setting.stickers.previewTitle": "Xem trước nhãn dán",
        "clan.setting.stickers.previewNameLabel": "Tên nhãn dán",
        "clan.setting.stickers.previewForSale": "Để bán",
        "clan.setting.stickers.previewUpload": "Tải lên",
        "clan.setting.stickers.previewLengthError": "Tên %@ phải từ %d đến %d kí tự, chỉ bao gồm chữ cái, chữ số, _ và -.",
        "clan.setting.stickers.previewTypeSticker": "nhãn dán",
        "clan.setting.emojis.duplicateName": "Tên biểu cảm đã tồn tại",
        "clan.setting.emojis.updateSuccess": "Cập nhật biểu cảm thành công",
        "clan.setting.emojis.deleteConfirmTitle": "Xoá biểu cảm",
        "clan.setting.emojis.deleteConfirmDesc": "Bạn có chắc muốn xoá biểu cảm này?",
        "clan.setting.emojis.deleteSuccess": "Xoá biểu cảm thành công",
        "clan.setting.emojis.createSuccess": "Tạo biểu cảm thành công",
        "clan.setting.emojis.validateName": "Độ dài phải từ %d - %d ký tự. Chỉ cho phép chữ, số, _ và -.",
        "clan.setting.emojis.errorUpdating": "Cập nhật biểu cảm thất bại. Vui lòng thử lại.",
        "clan.setting.emojis.uploadLimit": "Đã đạt giới hạn tải biểu cảm lên",
        "clan.setting.emojis.uploadButton": "Tải lên biểu cảm",
        "clan.setting.emojis.uploadDescription": "Thêm biểu cảm tùy chỉnh mà tất cả người dùng trong clan này đều có thể sử dụng. Mọi thành viên trong Mezon đều có thể sử dụng được các biểu cảm GIF động.",
        "clan.setting.emojis.uploadRequirementsTitle": "Yêu cầu tải lên",
        "clan.setting.emojis.uploadRequirement1": "Loại tệp: JPEG, PNG, GIF.",
        "clan.setting.emojis.uploadRequirement2": "Kích thước đề xuất: 256 KB.",
        "clan.setting.emojis.uploadRequirement3": "Kích cỡ ảnh đề nghị: 128x128.",
        "clan.setting.emojis.uploadRequirement4": "Đặt tên: Tên của biểu cảm phải có ít nhất 3 ký tự và chỉ được chứa ký tự chữ, ký tự số và dấu gạch dưới.",
        "clan.setting.emojis.uploadFileTooLarge": "Ảnh không được lớn hơn 256 KB.",
        "clan.setting.emojis.previewTitle": "Xem trước biểu cảm",
        "clan.setting.emojis.previewNameLabel": "Tên biểu cảm",
        "clan.setting.emojis.previewForSale": "Để bán",
        "clan.setting.emojis.previewUpload": "Tải lên",
        "clan.setting.emojis.previewLengthError": "Tên %@ phải từ %d đến %d ký tự, chỉ chữ, số, _ và -.",
        "clan.setting.emojis.previewTypeEmoji": "biểu cảm",
        "clan.setting.emojis.empty": "Không tìm thấy biểu cảm nào",

        "clanRoles.title":                  "Vai trò",
        "clanRoles.roleDescription":        "Dùng vai trò để nhóm thành viên và phân quyền trong clan.",
        "clanRoles.defaultRole":            "Quyền mặc định cho tất cả thành viên trong clan.",
        "clanRoles.everyone":               "@everyone",
        "clanRoles.rolesCount":             "Vai trò — %d",
        "clanRoles.member":                 "thành viên",
        "clanRoles.members":                "thành viên",
        "clanRoles.allMembers":             "Tất cả thành viên trong clan",
        "clanRoles.noRole":                 "Chưa có vai trò nào. Nhấn + để tạo mới.",
        "clanRoles.role":                   "Vai trò",
        "clanRoles.save":                   "Lưu",
        "clanRoles.saved":                  "Đã lưu thay đổi",
        "clanRoles.failed":                 "Có lỗi xảy ra. Vui lòng thử lại.",
        "clanRoles.skipStep":               "Bỏ qua bước này",

        "clanRoles.create.title":           "Tạo vai trò mới",
        "clanRoles.create.heading":         "Tạo vai trò mới",
        "clanRoles.create.description":     "Vai trò đại diện cho tập quyền được gán cho một nhóm thành viên.",
        "clanRoles.create.roleName":        "Tên vai trò",
        "clanRoles.create.placeholder":     "Vai trò mới",
        "clanRoles.create.button":          "Tạo",
        "clanRoles.create.success":         "Đã tạo vai trò \"%@\"",

        "clanRoles.detail.permissions":     "Quyền",
        "clanRoles.detail.members":         "Thành viên",
        "clanRoles.detail.roleName":        "Tên vai trò",
        "clanRoles.detail.delete":          "Xoá vai trò",
        "clanRoles.detail.confirmSaveTitle":   "Lưu thay đổi?",
        "clanRoles.detail.confirmSaveContent": "Bạn có thay đổi chưa lưu. Lưu trước khi rời?",
        "clanRoles.detail.confirmSaveYes":     "Lưu",
        "clanRoles.detail.confirmSaveDiscard": "Bỏ thay đổi",
        "clanRoles.detail.deleteTitle":     "Xoá vai trò này?",
        "clanRoles.detail.deleteMessage":   "Hành động này không thể hoàn tác.",
        "clanRoles.detail.deleteConfirm":   "Xoá",

        "clanRoles.color.row":              "Màu vai trò",
        "clanRoles.color.pickerTitle":      "Màu vai trò",
        "clanRoles.color.reset":            "Đặt lại màu",

        "clanRoles.icon.row":               "Biểu tượng",
        "clanRoles.icon.upload":            "Tải lên",
        "clanRoles.icon.remove":            "Xoá",
        "clanRoles.icon.failed":            "Không thể tải biểu tượng",

        "clanRoles.permissions.title":      "Cài đặt quyền",
        "clanRoles.permissions.heading":    "Chọn các quyền cho thành viên có vai trò này.",
        "clanRoles.permissions.search":     "Tìm quyền",
        "clanRoles.permissions.next":       "Tiếp theo",
        "clanRoles.permissions.notFound":   "Không tìm thấy quyền nào.",
        "clanRoles.permissions.notAvailable": "Chưa có mô tả cho quyền này.",

        "clanRoles.members.title":          "Thêm thành viên",
        "clanRoles.members.add":            "Thêm thành viên",
        "clanRoles.members.description":    "Chọn thành viên để thêm vào vai trò.",
        "clanRoles.members.search":         "Tìm thành viên",
        "clanRoles.members.notFound":       "Không tìm thấy thành viên",
        "clanRoles.members.finish":         "Hoàn tất",
        "clanRoles.members.added":          "Đã cập nhật thành viên",

        "clanRoles.permissionTitle.administrator":   "Quản trị viên",
        "clanRoles.permissionTitle.manage-clan":     "Quản lý Clan",
        "clanRoles.permissionTitle.manage-channel":  "Quản lý kênh",
        "clanRoles.permissionTitle.view-channel":    "Xem kênh",
        "clanRoles.permissionTitle.send-message":    "Gửi tin nhắn",
        "clanRoles.permissionTitle.manage-thread":   "Quản lý thread",
        "clanRoles.permissionTitle.delete-message":  "Xoá tin nhắn",

        "clanRoles.permissionDescription.administrator":  "Thành viên có quyền này sở hữu mọi quyền và bỏ qua hạn chế của kênh.",
        "clanRoles.permissionDescription.manage-clan":    "Cho phép đổi tên, ảnh đại diện và cài đặt khác của clan.",
        "clanRoles.permissionDescription.manage-channel": "Cho phép tạo, sửa, xoá kênh.",
        "clanRoles.permissionDescription.view-channel":   "Cho phép thành viên xem kênh theo mặc định.",
        "clanRoles.permissionDescription.send-message":   "Cho phép gửi tin nhắn trong các kênh chat.",
        "clanRoles.permissionDescription.manage-thread":  "Cho phép tạo, lưu trữ và xoá thread.",
        "clanRoles.permissionDescription.delete-message": "Cho phép xoá tin nhắn của thành viên khác.",

        "forward.screenTitle": "Chuyển tiếp tới",
        "forward.success": "Đã chuyển tiếp tin nhắn",
        "forward.attachmentsSingular": "đính kèm",
        "forward.attachmentsPlural": "đính kèm",
        "forward.filesSingular": "tệp",
        "forward.filesPlural": "tệp",
        "forward.audioSingular": "âm thanh",
        "forward.audioPlural": "âm thanh",
        "forward.moreBundledMessages": "tin nhắn khác được gộp",
        "forward.previewPlaceholder": "Xem trước tin nhắn",
        "forward.commentTooLong": "Nội dung nhập quá dài",
        "forward.noResults": "Không tìm thấy kết quả",
        "forward.blockedByYou": "Bạn đã chặn người dùng này",
        "forward.blockedYou": "Người dùng này đã chặn bạn",
        "forward.cannotMessage": "Không thể nhắn tin cho nhau",
        "forward.toastCannotForward": "Không thể chuyển tiếp tin nhắn tới cuộc trò chuyện này",

        "sharing.title":                    "Chia sẻ",
        "sharing.suggestionsSection":       "Gợi ý",
        "sharing.searchPlaceholderAll":     "Chọn kênh hoặc người dùng",
        "sharing.searchPlaceholderUsers":   "Chọn người dùng",
        "sharing.searchPlaceholderChannels":"Chọn kênh",
        "sharing.emptySuggestions":         "Chưa có kênh hoặc cuộc trò chuyện. Mở ứng dụng và vào máy chủ của bạn, rồi thử lại.",
        "sharing.commentPlaceholder":       "Thêm bình luận (tùy chọn)",
        "sharing.sending":                  "Đang gửi…",
        "sharing.uploading":                "Đang tải lên",
        "sharing.filterTitle":              "Lọc",
        "sharing.filterAll":                "Tất cả",
        "sharing.filterUsers":              "Người dùng",
        "sharing.filterChannels":           "Kênh",
        "sharing.sessionExpired":           "Phiên đăng nhập hết hạn",
        "sharing.errorTitle":               "Lỗi",
        "sharing.alertOK":                  "OK",
        "sharing.uploadFailed":             "Không gửi được. Vui lòng thử lại.",
        "sharing.uploadCancelled":          "Tải lên bị gián đoạn. Ở lại Mezon và thử lại.",
        "sharing.uploadNetworkError":       "Lỗi mạng khi tải lên. Kiểm tra kết nối và thử lại.",
        "sharing.fileUnavailable":          "Không còn file được chia sẻ. Hãy chia sẻ lại từ ứng dụng kia.",
        "clan.inviteSheet.title":           "Mời bạn bè",
        "clan.inviteSheet.share":           "Chia sẻ lời mời",
        "clan.inviteSheet.copy":            "Sao chép link",
        "clan.inviteSheet.qrCode":          "Mã QR",
        "clan.inviteSheet.qrHint":          "Quét mã QR để tham gia clan này",
        "clan.inviteSheet.shareQR":         "Chia sẻ QR",
        "clan.inviteSheet.saveQR":          "Lưu QR",
        "clan.inviteSheet.qrSaved":         "Đã lưu QR vào thư viện",
        "clan.inviteSheet.qrSaveFailed":    "Không thể lưu mã QR.",
        "clan.inviteSheet.linkCopied":      "Đã sao chép liên kết!",
        "clan.inviteSheet.searchPlaceholder":"Mời bạn bè vào clan",
        "clan.inviteSheet.loadingInviteLink":"Đang tạo link mời...",
        "clan.inviteSheet.emptyTitle":      "Không có bạn bè nào để mời",
        "clan.inviteSheet.emptyDescription":"Thêm bạn bè vào danh sách bạn bè của bạn để mời họ vào clan này.",
        "clan.inviteSheet.emptyAction":     "Thêm vài người bạn",
        "clan.inviteSheet.sessionNotFound": "Không tìm thấy phiên đăng nhập.",
        "clan.inviteSheet.cannotCreateInvite":"Không tạo được link mời clan.",
        "clan.inviteSheet.cannotSendInvite":"Không thể gửi lời mời cho %@.",
        "clan.inviteSheet.invite":          "Mời",
        "clan.inviteSheet.invited":         "Đã mời",
        "clan.inviteSheet.unknownClan":     "Clan không xác định",

        "onboardingClan.title":                 "Hoàn thành hướng dẫn",
        "onboardingClan.description":           "Bước %d trên %d",
        "onboardingClan.action.title":          "Hoàn thành hướng dẫn cho clan của bạn",
        "onboardingClan.action.description":    "Đã hoàn thành %d trên %d bước",
        "onboardingClan.action.createChannel":  "Tạo kênh của bạn",
        "onboardingClan.action.invite":         "Mời một vài người bạn",
        "onboardingClan.action.sendMessage":    "Gửi tin nhắn đầu tiên",
        "onboardingMember.title":               "Bắt đầu nào",
        "onboardingMember.description":         "Bước %d trên %d",
        "onboardingMember.action.title":        "Bắt đầu nào",
        "onboardingMember.action.description":  "Đã hoàn thành %d trên %d bước",
        "onboardingMember.mission.sendMessage": "Gửi tin nhắn trong",
        "onboardingMember.mission.visit":       "Truy cập kênh",
        "onboardingMember.mission.doSomething": "Làm bất cứ điều gì bạn muốn",

        "threadList.searchPlaceholder": "Tìm chủ đề",
        "threadList.empty": "Chưa có chủ đề",
        "threadList.emptyTitle": "Chưa có chủ đề",
        "threadList.emptyDescription": "Tập trung vào cuộc trò chuyện bằng một chủ đề\n- một kênh văn bản tạm thời.",
        "threadList.joinedThread": "chủ đề đã tham gia",
        "threadList.joinedThreads": "chủ đề đã tham gia",
        "threadList.otherActiveThread": "chủ đề hoạt động khác",
        "threadList.otherActiveThreads": "chủ đề hoạt động khác",
        "threadList.olderThread": "chủ đề cũ",
        "threadList.olderThreads": "chủ đề cũ",
        "threadList.searchThread": "kết quả",
        "threadList.searchThreads": "kết quả",
        "threadList.createThreadSoon": "Tạo chủ đề từ đây sẽ có trong bản cập nhật sau.",
        "threadList.createThreadButton": "Tạo chủ đề",
        "threadList.createThreadTitle": "Chủ đề mới",
        "threadList.createThreadNameLabel": "Tên chủ đề",
        "threadList.createThreadNamePlaceholder": "Chủ đề mới",
        "threadList.createThreadPrivateTitle": "Chủ đề riêng tư",
        "threadList.createThreadPrivateSubtitle": "Chỉ những người được mời mới vào được chủ đề này.",
        "threadList.createThreadSubmit": "Tạo",
        "threadList.createThreadCancel": "Hủy",
        "threadList.createThreadNameInvalid": "Nhập tên từ 4 đến 64 ký tự.",
        "threadList.createThreadFailed": "Không tạo được chủ đề.",
        "threadList.createThreadForbidden": "Bạn không có quyền tạo chủ đề trong kênh này.",
        "threadList.createThreadSuccess": "Đã tạo chủ đề.",
        "threadList.createThreadInChannel": "Trong #%@",
        "threadList.createThreadPublicTitle": "Chủ đề công khai",
        "threadList.createThreadPublicSubtitle": "Mọi người vào được kênh này đều có thể thấy và tham gia chủ đề.",
        "threadList.createThreadBadgePublic": "CÔNG KHAI",
        "threadList.createThreadBadgePrivate": "RIÊNG TƯ",
        "threadList.createThreadFirstMessageSection": "Tin nhắn đầu",
        "threadList.createThreadFirstMessagePlaceholder": "Tuỳ chọn — gõ @ để nhắc người khác",

        "channel.label":  "kênh",
        "channel.thread": "Chủ đề",
        "chat.system.pinMessageAnchor": "một tin nhắn",
        "chat.system.allThreadsAnchor": "tất cả chủ đề",
        "chat.system.startedThread": "đã tạo một chủ đề:",
        "chat.system.deletedThread": "đã xóa chủ đề:",
        "chat.system.seeAllThreads": "Xem",
        "chat.system.waveWelcome": "Vẫy tay để chào!",
        "channel.settings": "Cài đặt kênh",
        "channel.threadSettings": "Cài đặt chủ đề",
        "channel.name":   "Tên kênh",
        "channel.threadName": "Tên chủ đề",
        "channel.topic":  "Chủ đề kênh",
        "channel.delete": "Xóa kênh",
        "channel.deleteConfirm": "Bạn có chắc chắn muốn xóa kênh này không?",
        "channel.deleteThreadConfirm": "Bạn có chắc chắn muốn xóa chủ đề này không?",

        "channel.action.markAsRead":           "Đánh dấu là đã đọc",
        "channel.action.markFavorite":         "Thêm vào yêu thích",
        "channel.action.unmarkFavorite":       "Bỏ khỏi yêu thích",
        "channel.action.copyLink":             "Sao chép liên kết",
        "channel.action.mute":                 "Tắt thông báo kênh",
        "channel.action.muteShort":            "Tắt thông báo",
        "channel.action.muteThread":           "Tắt thông báo chủ đề",
        "channel.action.unmute":               "Bật thông báo kênh",
        "channel.action.unmuteShort":          "Bật thông báo",
        "channel.action.unmuteThread":         "Bật thông báo chủ đề",
        "channel.action.notificationSettings": "Cài đặt thông báo",
        "channel.action.editChannel":          "Chỉnh sửa kênh",
        "channel.action.editThread":           "Chỉnh sửa chủ đề",
        "channel.action.leaveThread":          "Rời khỏi chủ đề",
        "channel.action.leaveThreadConfirm":   "Bạn có chắc chắn muốn rời khỏi chủ đề này không?",
        "channel.action.deleteThread":         "Xóa chủ đề",

        "emojiPicker.title":                   "Cảm xúc",
        "muteDuration.title":              "Tắt thông báo kênh này",
        "muteDuration.titleThread":        "Tắt thông báo chủ đề này",
        "muteDuration.titleConversation":  "Tắt thông báo cuộc trò chuyện này",
        "muteDuration.for15Minutes":       "Trong 15 phút",
        "muteDuration.for1Hour":           "Trong 1 giờ",
        "muteDuration.for3Hours":          "Trong 3 giờ",
        "muteDuration.for8Hours":          "Trong 8 giờ",
        "muteDuration.for24Hours":         "Trong 24 giờ",
        "muteDuration.untilTurnedOff":     "Cho đến khi tôi bật lại",
        "muteDuration.notificationSettings": "Cài đặt thông báo",
        "muteDuration.description":        "Bạn đang nhận được thông báo từ tất cả tin nhắn trong clan này, nhưng bạn có thể thay đổi cài đặt tại đây",

        "notifSettings.title":          "Cài đặt thông báo",
        "notifSettings.useDefault":     "Sử dụng cài đặt mặc định",
        "notifSettings.allMessages":    "Tất cả",
        "notifSettings.mentionsOnly":   "Chỉ @mention",
        "notifSettings.nothing":        "Không có gì",

        "channel.setting.changeCategory":       "Thay đổi danh mục",
        "channel.setting.changeCategory.moveFrom": "Chuyển từ %@ tới",
        "channel.setting.changeCategory.confirmContent": "Bạn có chắc muốn chuyển %channel% sang %category% không?",
        "channel.setting.changeCategory.empty": "Không có danh mục nào khác để chuyển đến",
        "channel.setting.permissions":          "Quyền hạn kênh",
        "channel.setting.channelNameValidate":  "Vui lòng nhập tên kênh (tối đa 64 ký tự, chỉ từ, số, _ hoặc -).",
        "channel.setting.threadNameValidate":   "Vui lòng nhập tên chủ đề hợp lệ (tối đa 65 ký tự, chỉ chữ, số, _ hoặc -).",
        "channel.setting.quickAction":          "Hành động nhanh",
        "channel.setting.banList":              "Danh sách chặn",
        "channel.setting.webhook":              "Webhook",
        "channel.setting.privacyFooter":        "Thay đổi cài đặt quyền riêng tư và tùy chỉnh cách các thành viên có thể tương tác với kênh này.",
        "channel.setting.createChannel":        "Tạo kênh",
        "channel.setting.channelName":          "Tên kênh",
        "channel.setting.channelNamePlaceholder": "Nhập tên kênh",
        "channel.setting.channelNameError":       "Vui lòng nhập tên kênh (tối đa 64 ký tự, chỉ từ, số, _ hoặc -).",
        "channel.setting.channelNameDuplicate":   "Tên kênh đã tồn tại.",
        "channel.setting.channelType":          "Loại kênh",
        "channel.setting.textChannel":          "Văn bản",
        "channel.setting.textChannelDesc":      "Gửi tin nhắn, hình ảnh, GIF, biểu tượng cảm xúc, ý kiến và những câu chơi chữ",
        "channel.setting.voiceChannel":         "Thoại",
        "channel.setting.voiceChannelDesc":     "Trò chuyện cùng nhau bằng thoại, video và chia sẻ màn hình",
        "channel.setting.streamChannel":        "Phát trực tiếp",
        "channel.setting.streamChannelDesc":    "Phát sóng các hoạt động sở thích",
        "channel.setting.privateChannel":       "Kênh riêng tư",
        "channel.setting.privateChannelDesc":   "Chỉ những thành viên và vai trò được chọn mới có thể xem kênh này.",

        "webhook.title":            "Webhook",
        "integrations.title":           "Tích hợp",
        "integrations.description":     "Tùy chỉnh clan của bạn với các tính năng tích hợp. Quản lý webhook, các kênh và ứng dụng đã theo dõi, tích hợp các hệ thống bên ngoài và tự động hóa quy trình thông báo trong Mezon.",
        "integrations.learnMore":       "Tìm hiểu thêm về quản lý tích hợp",
        "integrations.webhooks":        "Webhooks",
        "integrations.clanWebhooks":    "Clan webhooks",
        "integrations.messagesUpdates": "Tin nhắn và cập nhật tự động",
        "webhook.description":          "Webhook là một cách đơn giản để gửi tin nhắn từ các ứng dụng và trang web khác vào Mezon bằng cách sử dụng công nghệ internet.",
        "webhook.clanDescription":      "Webhook Clan là một cách đơn giản để gửi tin nhắn từ các ứng dụng và trang web khác cho mỗi người dùng Mezon bằng cách sử dụng công nghệ internet.",
        "webhook.clanDescriptionTip":   "\nMẹo: Nếu bạn cảm thấy token trên URL của bạn bị xâm phạm hoặc lỗi thời, hãy đặt lại và sao chép URL mới",
        "webhook.learnMore":            "Tìm hiểu thêm",
        "webhook.buildOne":         "tạo một cái của riêng bạn",
        "webhook.noWebhooks":       "Không có webhook",
        "webhook.editTitle":        "Chỉnh sửa webhook",
        "webhook.name":             "Tên webhook",
        "webhook.nameLengthError":  "Độ dài phải từ 64 kí tự trở xuống.",
        "webhook.channel":          "Kênh",
        "webhook.webhookURL":       "Webhook URL",
        "webhook.copy":             "Sao chép",
        "webhook.copied":           "Đã sao chép",
        "webhook.delete":           "Xóa",
        "webhook.deleteTitle":      "Xóa Webhook",
        "webhook.deleteConfirm":    "Bạn có chắc chắn muốn xóa webhook %@?",
        "webhook.recommendImage":   "Khuyến nghị sử dụng hình ảnh có kích thước tối thiểu 128x128 px",
        "webhook.addSuccess":       "Thêm webhook thành công",
        "webhook.addError":         "Thêm webhook thất bại",
        "webhook.saveSuccess":      "Lưu thành công",
        "webhook.saveError":        "Lưu thất bại",
        "webhook.deleteSuccess":    "Xóa webhook thành công",
        "webhook.deleteError":      "Xóa webhook thất bại",
        "webhook.createdBy":        "Được tạo vào %@ bởi %@",
        "webhook.resetToken":       "Đặt lại token",
        "webhook.resetSuccess":     "Đặt lại thành công",

        "channelPermission.title":              "Quyền hạn kênh",
        "channelPermission.basicView":          "Cơ bản",
        "channelPermission.advancedView":       "Nâng cao",
        "channelPermission.edit":               "Sửa",
        "channelPermission.done":               "Xong",
        "channelPermission.save":               "Lưu",
        "channelPermission.privateChannel":     "Kênh riêng tư",
        "channelPermission.basicViewDescription": "Khi đặt kênh ở chế độ riêng tư, chỉ những thành viên và vai trò được chọn mới có thể xem kênh này.",
        "channelPermission.addMemberAndRoles":  "Thêm thành viên và vai trò",
        "channelPermission.whoCanAccess":       "Ai có thể truy cập kênh này?",
        "channelPermission.roles":              "Vai trò",
        "channelPermission.members":            "Thành viên",
        "channelPermission.role":               "Vai trò",
        "channelPermission.toast.success":      "Cập nhật thành công",
        "channelPermission.toast.failed":       "Cập nhật thất bại",
        "channelPermission.bottomSheet.addMembersOrRoles": "Thêm thành viên hoặc vai trò",
        "channelPermission.bottomSheet.add":    "Thêm",
        "channelPermission.bottomSheet.search": "Tìm thành viên hoặc vai trò",
        "channelPermission.roleAndMemberEmpty": "Chưa có vai trò hay thành viên nào. Hãy thêm ở mục Cơ bản trước.",
        "channelPermission.permissionOverrides": "Tuỳ chỉnh quyền",
        "channelPermission.generalChannelPermission": "Quyền kênh chung",
        "channelPermission.warningChangeSettingModal.title":   "Có thay đổi chưa lưu",
        "channelPermission.warningChangeSettingModal.content": "Bạn có thay đổi chưa lưu. Bạn có muốn lưu trước khi rời đi không?",
        "channelPermission.warningChangeSettingModal.confirm": "Lưu",
        "channelPermission.warningChangeSettingModal.cancel":  "Bỏ qua",

        "channelMessages.emptyMessages": "Chưa có tin nhắn",
        "channelMessages.todayAt": "Hôm nay lúc %@",
        "channelMessages.yesterdayAt": "Hôm qua lúc %@",
        "channelMessages.writeMessage": "Nhập tin nhắn...",
        "channelMessages.noSendPermission": "Bạn không có quyền gửi tin nhắn trong kênh này.",
        "channelMessages.userIsTyping": "%@ đang nhập…",
        "channelMessages.usersAreTyping": "%@ đang nhập…",
        "channelMessages.severalPeopleTyping": "Nhiều người đang nhập…",
        "channelMessages.voiceMessageA11y": "Tin nhắn thoại. Chạm để phát hoặc tạm dừng.",
        "channelMessages.yourLocation": "Vị trí của bạn",
        "channelMessages.locationOf": "Vị trí của %@",
        "channelMessages.clanInviteLoadFailed": "Không tải được lời mời clan.",
        "channelMessages.pollUnsupported": "Bình chọn chưa được hỗ trợ trên ứng dụng này.",
        "channelMessages.pollComingSoon": "Sắp có.",

        "channelApp.launchApp": "Mở app",
        "channelApp.help": "Trợ giúp",
        "channelApp.unavailable": "Không mở được app.",

        "poll.selectOne": "Chọn một tùy chọn",
        "poll.selectOneOrMore": "Chọn một hoặc nhiều tùy chọn",
        "poll.voteButton": "Bình chọn",
        "poll.removeVote": "Hủy bình chọn",
        "poll.showResults": "Xem kết quả",
        "poll.backToVote": "Quay lại",
        "poll.vote": "bình chọn",
        "poll.votes": "bình chọn",
        "poll.ended": "Đã kết thúc",
        "poll.left": "còn lại",
        "poll.days": "ngày",
        "poll.hours": "giờ",
        "poll.minutes": "phút",
        "poll.loadMore": "Thêm %d tùy chọn",
        "poll.loadMore1Option": "Thêm 1 tùy chọn",
        "poll.showLess": "Thu gọn",
        "poll.noVotesYet": "Chưa có bình chọn nào",

        "advanced.poll": "Bình chọn",
        "createPoll.title": "Tạo bình chọn",
        "createPoll.questionLabel": "Câu hỏi",
        "createPoll.questionPlaceholder": "Bạn muốn hỏi điều gì?",
        "createPoll.answersLabel": "Câu trả lời",
        "createPoll.answerPlaceholder": "Nhập câu trả lời",
        "createPoll.addAnswerButton": "+ Thêm câu trả lời",
        "createPoll.durationLabel": "Thời gian",
        "createPoll.multipleAnswersLabel": "Cho phép chọn nhiều đáp án",
        "createPoll.postButton": "Đăng",
        "createPoll.selectDuration": "Chọn thời gian",
        "createPoll.cancel": "Hủy",
        "createPoll.hour1": "1 Giờ",
        "createPoll.hours4": "4 Giờ",
        "createPoll.hours8": "8 Giờ",
        "createPoll.hours24": "24 Giờ",
        "createPoll.days3": "3 Ngày",
        "createPoll.week1": "1 Tuần",

        "chatWelcome.welcomeToChannel": "Chào mừng đến với #%@",
        "chatWelcome.startOfChannel": "Đây là nơi bắt đầu của kênh #%@ %@",
        "chatWelcome.privateChannel": "riêng tư",
        "chatWelcome.threadStartedBy": "Được tạo bởi %@",
        "chatWelcome.beginningOfDM": "Đây là nơi bắt đầu cuộc trò chuyện của bạn và %@",
        "chatWelcome.welcomeToGroup": "Chào mừng bạn đến với nhóm %@.",

        "directMessage.addFriend": "Thêm bạn",
        "directMessage.you": "Bạn",
        "directMessage.newGroup": "Nhóm mới",
        "directMessage.create": "Tạo",
        "directMessage.searchFriends": "Tìm bạn bè",
        "directMessage.memberCount": "%d trên %d thành viên",
        "directMessage.noFriends": "Chưa có bạn bè để chọn",
        "directMessage.memberLimitReached": "Nhóm chat chỉ có tối đa 20 thành viên.",
        "directMessage.createFailed": "Không thể tạo nhóm.",
        "directMessage.groupCreated": "Nhóm đã được tạo",
        "directMessage.previewAttachment": "Đính kèm",
        "directMessage.previewLink": "Liên kết",
        "directMessage.previewLocation": "Vị trí",
        "directMessage.previewContact": "Danh bạ",
        "directMessage.previewEmbed": "embed",

        "friendRequest.title": "Thêm bạn bè",
        "friendRequest.received": "Đã nhận",
        "friendRequest.sent": "Đã gửi",
        "friendRequest.emptyReceivedTitle": "Không có yêu cầu kết bạn đến",
        "friendRequest.emptyReceivedDesc": "Tại đây bạn sẽ thấy tất cả các yêu cầu kết bạn mà mọi người gửi cho bạn.",
        "friendRequest.addByTitle": "Thêm bằng tên người dùng hoặc số điện thoại",
        "friendRequest.addByQuestion": "Bạn muốn thêm ai làm bạn bè?",
        "friendRequest.addByPlaceholder": "Nhập tên người dùng hoặc số điện thoại",
        "friendRequest.addByHintFormat": "À nhân tiện, tên người dùng của bạn là %@",
        "friendRequest.addBySending": "Đang gửi...",
        "friendRequest.addBySubmit": "Gửi yêu cầu kết bạn",
        "friendRequest.addByGenericError": "Không thể gửi lời mời kết bạn. Vui lòng thử lại.",
        "friendRequest.toastSelfAddError": "Hmm, có lỗi xảy ra. Vui lòng kiểm tra lại tên người dùng có đúng không",
        "friendRequest.toastBlockedError": "Bạn đã chặn người dùng này. Vui lòng bỏ chặn để gửi lời mời kết bạn.",
        "friendRequest.toastAlreadyFriend": "Bạn đã là bạn bè với người dùng này!",
        "friendRequest.toastWaitAccept": "Bạn đã gửi yêu cầu kết bạn tới người dùng này rồi!",
        "friendRequest.toastIncomingReq": "Người này đã gửi yêu cầu kết bạn cho bạn",
        "friendRequest.toastSendSuccess": "Yêu cầu kết bạn đã được gửi thành công!",
        "friendRequest.toastAcceptSuccess": "%@ đã chấp nhận yêu cầu kết bạn của bạn",
        "profile.mezonTransfer": "Chuyển tiền qua Mezon",
        "profile.historyTransaction": "Lịch sử giao dịch",
        "profile.historyAll": "Tất cả",
        "profile.historyIncoming": "Tiền vào",
        "profile.historyOutgoing": "Tiền ra",
        "profile.historyReceived": "Nhận tiền",
        "profile.historySent": "Chuyển tiền",
        "profile.historyTransactionId": "Mã giao dịch:",
        "profile.historyDetailTitle": "Chi tiết giao dịch",
        "profile.historyStatus": "Trạng thái",
        "profile.historyCompleted": "Thành công",
        "profile.historyFailed": "Thất bại",
        "profile.historyTime": "Thời gian",
        "profile.historyFee": "Phí mạng",
        "profile.historyHash": "Mã giao dịch",
        "profile.historyFrom": "Từ",
        "profile.historyTo": "Đến",
        "profile.historySenderName": "Tên người gửi",
        "profile.historyReceiverName": "Tên người nhận",
        "profile.historyUnknownUser": "Không xác định",
        "profile.historyTransactionIdCopied": "Đã sao chép mã giao dịch",
        "profile.historyValue": "Số lượng",

        "friendList.title": "Bạn bè",
        "friendList.friendCount": "Bạn bè",
        "friendList.addFriend": "Thêm bạn bè",
        "friendList.searchPlaceholder": "Tìm kiếm",
        "friendList.friendRequest": "Yêu cầu kết bạn",
        "friendList.received": "Đã nhận",
        "friendList.sent": "Đã gửi",
        "friendList.noResults": "Không tìm thấy kết quả bạn bè",

        "gallery.imageSaved": "Đã lưu ảnh",
        "gallery.imageSaveFailed": "Không thể lưu ảnh",
        "gallery.videoSaved": "Đã lưu video",
        "gallery.videoSaveFailed": "Không thể lưu video",
        "gallery.videoDownloading": "Đang tải video...",
        "gallery.videoSaving": "Đang lưu video...",
        "gallery.imageLoadFailed": "Không thể tải ảnh",
        "gallery.photoPermissionDenied": "Vui lòng cấp quyền ảnh để lưu ảnh",
        "gallery.photoPermissionTitle": "Cần quyền truy cập ảnh",
        "gallery.photoPermissionMessage": "Quyền truy cập ảnh đã bị từ chối. Vui lòng bật quyền Ảnh trong Cài đặt để lưu ảnh.",

        "messageAction.reply": "Trả lời",
        "messageAction.copyText": "Sao chép văn bản",
        "messageAction.saveImage": "Lưu ảnh",
        "messageAction.saveVideo": "Lưu video",
        "messageAction.copyImage": "Sao chép ảnh",
        "messageAction.editMessage": "Chỉnh sửa tin nhắn",
        "messageAction.editingMessage": "Đang chỉnh sửa tin nhắn",
        "messageAction.editedSuffix": "(đã chỉnh sửa)",
        "messageAction.deleteMessage": "Xóa tin nhắn",
        "messageAction.deleteMessageConfirm": "Bạn có muốn xóa tin nhắn này không?",
        "messageAction.pinMessage": "Ghim tin nhắn",
        "messageAction.unpinMessage": "Bỏ ghim tin nhắn",
        "messageAction.forward": "Chuyển tiếp",
        "messageAction.copied": "Đã sao chép",
        "messageAction.giveACoffee": "Tặng cà phê",
        "messageAction.giveCoffeeSuccess": "Đã tặng cà phê",
        "messageAction.forwardMessage": "Chuyển tiếp tin nhắn",
        "messageAction.forwardAll": "Chuyển tiếp nhiều tin gần nhau",
        "messageAction.createThread": "Tạo chủ đề",
        "messageAction.markUnread": "Đánh dấu chưa đọc",
        "messageAction.topicDiscussion": "Thảo luận chủ đề",
        "messageAction.markMessage": "Đánh dấu tin nhắn",
        "messageAction.quickMenu": "Menu nhanh",
        "messageAction.report": "Báo cáo",
        "messageAction.pinMessageConfirm": "Bạn có muốn ghim tin nhắn này không?",
        "messageAction.unpinMessageConfirm": "Bỏ ghim tin nhắn này?",
        "messageAction.deleteError": "Xóa tin nhắn thất bại",
        "messageAction.pinSuccess": "Ghim tin nhắn thành công",
        "messageAction.pinError": "Ghim tin nhắn thất bại",
        "messageAction.unpinSuccess": "Đã bỏ ghim",
        "messageAction.unpinError": "Không thể bỏ ghim",
        "messageAction.yes": "Đồng ý",
        "messageAction.no": "Không",

        "reportMessage.title": "Báo cáo tin nhắn",
        "reportMessage.subtitle": "Cho chúng tôi biết vấn đề. Báo cáo của bạn được ẩn danh.",
        "reportMessage.selectedMessage": "Tại sao bạn báo cáo tin nhắn này?",
        "reportMessage.spam": "Spam",
        "reportMessage.harassment": "Quấy rối hoặc lạm dụng",
        "reportMessage.violentContent": "Thông tin sai lệch có hại hoặc ca ngợi bạo lực",
        "reportMessage.private": "Chia sẻ thông tin riêng tư hoặc định danh",
        "reportMessage.reportSummary": "Tóm tắt báo cáo",
        "reportMessage.reviewYourReportBeforeSubmitting": "Xem lại báo cáo trước khi gửi.",
        "reportMessage.reportCategory": "Danh mục báo cáo",
        "reportMessage.submitDescription": "Nếu tin nhắn vi phạm quy định, chúng tôi có thể gỡ và xử lý tài khoản.",
        "reportMessage.submitReport": "Gửi báo cáo",
        "reportMessage.cancel": "Hủy",
        "reportMessage.reportSubmitted": "Đã gửi báo cáo",
        "reportMessage.failed": "Không gửi được báo cáo. Vui lòng thử lại.",

        "profile.addStatus": "Thêm trạng thái",
        "profile.editProfile": "Chỉnh sửa hồ sơ",
        "profile.balance": "Số dư",
        "profile.transferFunds": "Chuyển khoản",
        "profile.transferSend": "Gửi",
        "profile.transferAmount": "Số tiền",
        "profile.sendTokenHeading": "Chuyển khoản",
        "profile.sendTokenSendToken": "Chuyển khoản",
        "profile.sendTokenDebitAccount": "Tài khoản nguồn",
        "profile.sendTokenSendTo": "Chuyển khoản đến",
        "profile.sendTokenSendToAddress": "Chuyển khoản đến địa chỉ",
        "profile.sendTokenToken": "Số lượng",
        "profile.sendTokenNote": "Ghi chú",
        "profile.sendTokenDefaultNote": "Chuyển khoản",
        "profile.sendTokenSelectAccount": "Chọn người dùng để chuyển khoản",
        "profile.sendTokenCopyAddressSuccess": "Đã sao chép địa chỉ",
        "profile.sendTokenConfirmTitle": "Xác nhận chuyển khoản",
        "profile.sendTokenConfirmMessage": "Chuyển khoản %1$@ %2$@ đến %3$@?",
        "profile.sendTokenConfirmAction": "Chuyển",
        "profile.sendTokenSuccessTitle": "Gửi thành công",
        "profile.sendTokenComplete": "Hoàn thành",
        "profile.sendTokenSendNew": "Tạo giao dịch mới",
        "profile.sendTokenReceiver": "Người nhận",
        "profile.sendTokenDate": "Thời gian",
        "profile.sendTokenErrAmountZero": "Số tiền giao dịch phải lớn hơn 0",
        "profile.sendTokenErrExceedWallet": "Tài khoản không đủ tiền",
        "profile.sendTokenErrSelectUser": "Bạn phải chọn một người dùng để nhận",
        "profile.sendTokenErrSendFailed": "Đã xảy ra lỗi, vui lòng thử lại",
        "profile.sendTokenErrSessionExpired": "Phiên đăng nhập đã hết hạn",
        "profile.sendTokenErrLoginAgain": "Vui lòng đăng nhập lại để tiếp tục",
        "profile.sendTokenLogLinePrefix": "Biến động số dư:",
        "profile.aboutMe": "Về tôi",
        "profile.mezonMemberSince": "Thành viên Mezon từ",
        "profile.yourFriends": "Bạn bè",
        "profile.copyUserId": "Sao chép User ID",
        "profile.userIdCopied": "Đã sao chép User ID",
        "profile.currency": "đồng",
        "profile.statusTitle": "Cập nhật trạng thái",
        "profile.statusDurationLabel": "Thời lượng trạng thái",
        "profile.statusDurationToday": "Hôm nay",
        "profile.statusDurationFourHours": "4 giờ",
        "profile.statusDurationOneHour": "1 giờ",
        "profile.statusDurationThirtyMinutes": "30 phút",
        "profile.statusDurationDontClear": "Không xóa",
        "profile.statusTooLong": "Trạng thái tối đa 128 ký tự.",
        "profile.statusUpdateFailed": "Không thể cập nhật trạng thái. Vui lòng thử lại.",
        "profile.changeOnlineStatus": "Thay đổi trạng thái trực tuyến",
        "profile.onlineStatusSection": "Trạng thái trực tuyến",
        "profile.setCustomStatus": "Đặt trạng thái tùy chỉnh",
        "profile.userStatusOnline": "Trực tuyến",
        "profile.userStatusIdle": "Tạm vắng",
        "profile.userStatusDoNotDisturb": "Không làm phiền",
        "profile.userStatusInvisible": "Ngoại tuyến (Ẩn)",
        "profile.presenceUpdateFailed": "Không thể đổi trạng thái trực tuyến. Vui lòng thử lại.",

        "profileSetting.title": "Cài đặt hồ sơ",
        "profileSetting.userProfile": "Cá nhân",
        "profileSetting.clanProfiles": "Clan",
        "profileSetting.save": "Lưu",
        "profileSetting.displayName": "Tên hiển thị",
        "profileSetting.aboutMe": "Về tôi",
        "profileSetting.clanNickname": "Biệt danh Clan",
        "profileSetting.selectAClan": "Chọn một Clan",
        "profileSetting.updateSuccess": "Cập nhật hồ sơ thành công",
        "profileSetting.updateError": "Cập nhật hồ sơ thất bại",
        "profileSetting.clanUpdateSuccess": "Cập nhật hồ sơ Clan thành công",
        "profileSetting.duplicateNickname": "Biệt danh này đã tồn tại trong Clan. Vui lòng chọn tên khác.",
        "profileSetting.noClanTitle": "Bạn chưa tham gia clan nào",
        "profileSetting.noClanDesc": "Tạo hoặc tham gia một clan để thiết lập hồ sơ clan của bạn.",
        "profileSetting.noClanCreateClan": "Tạo clan",
        "profileSetting.noClanJoinClan": "Tham gia clan",
        "profileSetting.directMessageIcon": "Biểu tượng tin nhắn riêng",

        "qrScanner.title": "Quét mã QR",
        "qrScanner.cameraPermissionTitle": "Yêu cầu quyền truy cập Camera",
        "qrScanner.cameraPermissionMessage":
            "Vui lòng cho phép truy cập camera trong Cài đặt để quét mã QR.",
        "qrScanner.gallery": "Thư viện",
        "qrScanner.invalidQR": "Mã QR không hợp lệ",
        "qrScanner.loginConfirm": "Bạn có muốn đăng nhập với %@?",
        "qrScanner.joinGroup": "Tham gia nhóm",
        "qrScanner.transferTo": "Chuyển khoản cho %@",
        "qrScanner.processing": "Đang xử lý...",
        "qrScanner.logInOnNewDevice": "Đăng nhập trên thiết bị mới?",
        "qrScanner.neverScanLoginQR": "Không bao giờ quét mã QR đăng nhập từ người dùng khác.",
        "qrScanner.youAreIn": "Bạn đã đăng nhập",
        "qrScanner.youAreLoggedInDesktop": "Bạn đã đăng nhập trên máy tính",
        "qrScanner.startTalking": "Bắt đầu trò chuyện",
        "qrScanner.inviteToJoinClan": "LỜI MỜI THAM GIA CLAN",
        "qrScanner.joinClan": "Tham gia",
        "qrScanner.goToClan": "Vào clan",
        "qrScanner.noThanks": "Không, cảm ơn",
        "qrScanner.message": "Nhắn tin",
        "qrScanner.userProfile": "THÔNG TIN NGƯỜI DÙNG",
        "qrScanner.myQRCode": "Mã QR của tôi",
        "qrScanner.qrProfile": "Mã QR Hồ sơ",
        "qrScanner.qrTransfer": "Mã QR chuyển khoản",
        "qrScanner.poweredBy": "Được cung cấp bởi Mezon",
        "qrScanner.shareWithOthers": "Chia sẻ với mọi người",
        "qrScanner.scanProfileHelp": "Quét mã QR này để trò chuyện với tôi hoặc xem hồ sơ của tôi",
        "qrScanner.scanTransferHelp": "Quét mã QR này để chuyển khoản",
        "qrScanner.scanInstruction": "Di chuyển camera đến mã QR để quét hoặc",
        "qrScanner.chooseFromGallery": "Chọn từ Thư viện ảnh",
        "qrScanner.sharePersonalQR": "Chia sẻ mã QR cá nhân ˄",
        "qrScanner.luckyMoneyTitle": "Lì xì",
        "qrScanner.luckyMoneyPleaseWait": "Vui lòng chờ trong giây lát...",
        "qrScanner.luckyMoneyCongratulations": "Bạn đã nhận được lì xì!",
        "qrScanner.luckyMoneyClaimToWallet": "Nhận vào ví",
        "qrScanner.luckyMoneyClaimSuccess": "Nhận thành công",
        "qrScanner.luckyMoneySuccessDone": "Xong",
        "qrScanner.luckyMoneyClaimFailed": "Không nhận được. Vui lòng thử lại.",
        "qrScanner.luckyMoneyWalletNotReady": "Ví chưa sẵn sàng. Vui lòng thử lại sau.",
        "qrScanner.luckyMoneyServiceNotConfigured": "Dịch vụ nhận lì xì chưa được cấu hình.",
        "qrScanner.luckyMoneyInvalidPayload": "Mã QR không phải lì xì hợp lệ.",
        "qrScanner.scannedPayloadTitle": "Nội dung quét được",
        "qrScanner.copyContent": "Sao chép",

        "error.networkError": "Lỗi kết nối mạng",
        "error.connectionFailed": "Kết nối thất bại. Vui lòng thử lại.",
        "error.somethingWentWrong": "Đã xảy ra lỗi",
        "error.sessionExpiredTitle": "Phiên đăng nhập hết hạn",
        "error.sessionExpiredOrNetwork": "Phiên hết hạn hoặc lỗi mạng",
        "error.sessionExpiredContent":
            "Phiên đăng nhập của bạn đã hết hạn. Vui lòng đăng nhập lại.",
        "error.sessionExpiredConfirm": "Đăng nhập lại",

        "clanSwitch.rapidTitle":   "Chậm lại một chút nhé",
        "clanSwitch.rapidMessage": "Bạn đang chuyển clan khá nhanh. Đợi vài giây cho danh sách kênh tải xong để tránh bị gián đoạn nha!",
        "clanSwitch.rapidConfirm": "Đã hiểu",

        "channelDetail.members": "Thành viên",
        "channelDetail.media":   "Phương tiện",
        "channelDetail.images":  "Hình ảnh",
        "channelDetail.videos":  "Video",
        "channelDetail.files":   "Tệp",
        "channelDetail.docs":    "Tài liệu",
        "channelDetail.audios":  "Âm thanh",
        "channelDetail.pins":    "Ghim",
        "channelDetail.canvas":  "Canvas",
        "channelDetail.online":  "Trực tuyến",
        "channelDetail.offline": "Ngoại tuyến",
        "channelDetail.inviteMembers": "Mời thành viên",
        "channelDetail.newGroup": "Nhóm mới",
        "channelDetail.addMembers": "Thêm thành viên",
        "channelDetail.untitledCanvas": "Bản vẽ chưa đặt tên",
        "channelDetail.searchFilesPlaceholder": "Tìm tệp",
        "channelDetail.fileSharedBy": "Chia sẻ bởi %@",
        "channelDetail.noFilesYet": "Chưa có tệp",
        "channelDetail.noMediaYet": "Chưa có ảnh hay video",
        "channelDetail.pinAttachmentPreview": "Tệp đính kèm",
        "channelDetail.pinContactPreview": "Danh bạ",
        "channelDetail.pinEmbedPreview": "Nội dung nhúng",
        "channelDetail.noPinsYet": "Chưa có tin nhắn ghim",
        "channelDetail.unpinError": "Không thể bỏ ghim. Thử lại sau.",
        "channelDetail.unpinConfirmTitle": "Bỏ ghim tin nhắn này?",
        "channelDetail.unpinConfirmBody": "Tin sẽ được gỡ khỏi mục ghim với mọi người trong kênh.",
        "channelDetail.unpinConfirmAction": "Bỏ ghim",
        "channelDetail.customizeGroup": "Tùy chỉnh nhóm",
        "channelDetail.leaveGroup": "Rời nhóm",
        "channelDetail.deleteGroup": "Xóa nhóm",
        "channelDetail.leaveGroupConfirmTitle": "Rời nhóm này?",
        "channelDetail.leaveGroupConfirmBody": "Bạn sẽ không nhận tin nhắn từ nhóm này nữa.",
        "channelDetail.deleteGroupConfirmTitle": "Xóa nhóm này?",
        "channelDetail.deleteGroupConfirmBody": "Nhóm này sẽ bị xóa với mọi người.",
        "channelDetail.groupName": "Tên nhóm",
        "channelDetail.removeGroupLogo": "Xóa logo nhóm",
        "channelDetail.groupNameRequired": "Vui lòng nhập tên nhóm.",
        "channelDetail.groupUpdated": "Đã cập nhật nhóm",
        "channelDetail.groupLeft": "Bạn đã rời nhóm",
        "channelDetail.groupDeleted": "Đã xóa nhóm",
        "channelDetail.updateGroupFailed": "Không thể cập nhật nhóm.",
        "channelDetail.leaveGroupFailed": "Không thể rời nhóm.",
        "channelDetail.removeFromGroup": "Xóa khỏi nhóm",
        "channelDetail.removeFromGroupConfirmTitle": "Xóa khỏi nhóm?",
        "channelDetail.removeFromGroupConfirmBody": "%@ sẽ bị xóa khỏi nhóm này.",
        "channelDetail.removeFromGroupConfirmAction": "Xóa",
        "channelDetail.removeFromGroupFailed": "Không thể xóa thành viên.",
        "channelDetail.memberRemoved": "Đã xóa thành viên",

        "dmMenu.leaveGroup": "Rời nhóm",
        "dmMenu.deleteGroup": "Xóa nhóm",
        "dmMenu.closeDm": "Đóng tin nhắn",
        "dmMenu.closeDmConfirmTitle": "Đóng %@",
        "dmMenu.closeDmConfirmMessage": "Bạn có chắc chắn muốn đóng cuộc trò chuyện với %@ không?",
        "dmMenu.markAsRead": "Đánh dấu là đã đọc",
        "dmMenu.muteConversation": "Tắt thông báo",
        "dmMenu.unmuteConversation": "Bật thông báo",
        "dmMenu.blockUser": "Chặn người dùng",
        "dmMenu.unblockUser": "Bỏ chặn người dùng",
        "dmMenu.removeFriend": "Xóa bạn",
        "dmMenu.addFriend": "Thêm bạn",
        "dmMenu.members": "%d thành viên",
        "dmMenu.blockUserSuccess": "Chặn người dùng thành công",
        "dmMenu.blockUserError": "Không thể chặn người dùng",
        "dmMenu.unblockUserSuccess": "Bỏ chặn người dùng thành công",
        "dmMenu.unblockUserError": "Không thể bỏ chặn người dùng",

        "embed.onlyVisibleToRecipient": "Chỉ người nhận mới thấy được",

        "callLog.cancel":           "Bạn đã từ chối",
        "callLog.missed":           "Bạn bị nhỡ",
        "callLog.receiverRejected": "Người nhận từ chối",
        "callLog.youRejected":      "Bạn đã từ chối",
        "callLog.audioCall":        "Cuộc gọi thoại",
        "callLog.videoCall":        "Cuộc gọi video",
        "callLog.callBack":         "Gọi lại",
        "callLog.incomingCall":     "Cuộc gọi đến",
        "callLog.outGoingCall":     "Cuộc gọi đi",
        "callLog.startGroupCall":   "%@ đã bắt đầu 1 cuộc gọi nhóm",
        "callLog.startAudioCall":   "%@ đã bắt đầu 1 cuộc gọi thoại",
        "callLog.startVideoCall":   "%@ đã bắt đầu 1 cuộc gọi video",
        "callLog.callDurationPrefix": "Thời lượng cuộc gọi: ",

        "peerCall.actionEnd":               "Kết thúc",
        "peerCall.actionMic":               "Mic",
        "peerCall.actionSpeaker":           "Loa",
        "peerCall.actionCancel":            "Huỷ",
        "peerCall.actionOK":                "OK",
        "peerCall.titleDefaultOutgoing":    "Cuộc gọi",
        "peerCall.titleDefaultIncoming":    "Cuộc gọi đến",
        "peerCall.statusRinging":           "Đang đổ chuông…",
        "peerCall.statusIncoming":          "Đang gọi đến…",
        "peerCall.statusConnecting":        "Đang kết nối…",
        "peerCall.statusConnected":         "Đã kết nối",
        "peerCall.statusMissed":            "Cuộc gọi nhỡ",
        "peerCall.statusNoAnswer":          "Không có người nghe",
        "peerCall.statusCouldNotConnect":   "Không kết nối được",
        "peerCall.statusUnlockForMicrophone": "Mở khóa điện thoại để cấp quyền micro",
        "peerCall.errorMicrophoneDenied":   "Quyền truy cập micro bị từ chối",
        "peerCall.micPermissionTitle":      "Micro",
        "peerCall.micPermissionBody":       "Cho phép truy cập micro trong Cài đặt để tham gia cuộc gọi.",
        "peerCall.errorCameraDenied":       "Quyền truy cập camera bị từ chối",
        "peerCall.errorCouldNotStartCall":  "Không thể bắt đầu cuộc gọi",
        "peerCall.errorCouldNotAnswerCall": "Không thể trả lời cuộc gọi",
        "peerCall.alertEndCallTitle":       "Kết thúc cuộc gọi",
        "peerCall.alertEndCallMessage":     "Bạn có chắc chắn muốn kết thúc cuộc gọi không?",
        "peerCall.bannerWeakNetwork":       "Mạng yếu — đang kết nối lại…",
        "peerCall.remoteMicOffBanner":      "%@ đã tắt micro",

        "auditLog.title": "Nhật ký hoạt động",
        "auditLog.filterBtn": "Lọc",
        "auditLog.filterByUser": "Lọc theo người dùng",
        "auditLog.filterByAction": "Lọc theo hành động",
        "auditLog.allUsers": "Tất cả người dùng",
        "auditLog.allActions": "Tất cả hành động",
        "auditLog.empty": "Không tìm thấy nhật ký.",
        "auditLog.add": "thêm",
        "auditLog.remove": "xoá",
        "auditLog.toChannel": "vào kênh",
        "auditLog.updateClan": "Cập nhật clan",
        "auditLog.createChannel": "Tạo kênh",
        "auditLog.updateChannel": "Cập nhật kênh",
        "auditLog.updateChannelPrivate": "Cập nhật kênh riêng tư",
        "auditLog.deleteChannel": "Xóa kênh",
        "auditLog.createChannelPermission": "Tạo quyền kênh",
        "auditLog.updateChannelPermission": "Cập nhật quyền kênh",
        "auditLog.deleteChannelPermission": "Xóa quyền kênh",
        "auditLog.kickMember": "Đuổi thành viên",
        "auditLog.pruneMember": "Lọc thành viên",
        "auditLog.banMember": "Cấm thành viên",
        "auditLog.unbanMember": "Bỏ cấm thành viên",
        "auditLog.updateMember": "Cập nhật thành viên",
        "auditLog.updateRolesMember": "Cập nhật quyền thành viên",
        "auditLog.moveMember": "Di chuyển thành viên",
        "auditLog.disconnectMember": "Ngắt kết nối thành viên",
        "auditLog.addBot": "Thêm bot",
        "auditLog.createThread": "Tạo chủ đề",
        "auditLog.updateThread": "Cập nhật chủ đề",
        "auditLog.deleteThread": "Xóa chủ đề",
        "auditLog.createRole": "Tạo vai trò",
        "auditLog.updateRole": "Cập nhật vai trò",
        "auditLog.deleteRole": "Xóa vai trò",
        "auditLog.createWebhook": "Tạo webhook",
        "auditLog.updateWebhook": "Cập nhật webhook",
        "auditLog.deleteWebhook": "Xóa webhook",
        "auditLog.createEmoji": "Tạo biểu cảm",
        "auditLog.updateEmoji": "Cập nhật biểu cảm",
        "auditLog.deleteEmoji": "Xóa biểu cảm",
        "auditLog.createSticker": "Tạo nhãn dán",
        "auditLog.updateSticker": "Cập nhật nhãn dán",
        "auditLog.deleteSticker": "Xóa nhãn dán",
        "auditLog.createEvent": "Tạo sự kiện",
        "auditLog.updateEvent": "Cập nhật sự kiện",
        "auditLog.deleteEvent": "Xóa sự kiện",
        "auditLog.createCanvas": "Tạo canvas",
        "auditLog.updateCanvas": "Cập nhật canvas",
        "auditLog.deleteCanvas": "Xóa canvas",
        "auditLog.createCategory": "Tạo danh mục",
        "auditLog.updateCategory": "Cập nhật danh mục",
        "auditLog.deleteCategory": "Xóa danh mục",
        "auditLog.addMemberChannel": "Thêm thành viên vào kênh",
        "auditLog.removeMemberChannel": "Xóa thành viên khỏi kênh",
        "auditLog.addRoleChannel": "Thêm vai trò vào kênh",
        "auditLog.removeRoleChannel": "Xóa vai trò khỏi kênh",
        "auditLog.addMemberThread": "Thêm thành viên vào chủ đề",
        "auditLog.removeMemberThread": "Xóa thành viên khỏi chủ đề",
        "auditLog.addRoleThread": "Thêm vai trò vào chủ đề",
        "auditLog.removeRoleThread": "Xóa vai trò khỏi chủ đề",
        
        "mediaPanel.emoji": "Biểu cảm",
        "mediaPanel.gifs": "GIFs",
        "mediaPanel.stickers": "Nhãn dán",
        "mediaPanel.search": "Tìm kiếm",
        "mediaPanel.findGif": "Tìm kiếm GIF",
        "mediaPanel.findEmoji": "Tìm kiếm biểu cảm",
        "mediaPanel.findSticker": "Tìm kiếm nhãn dán",
        "mediaPanel.findReaction": "Tìm kiếm biểu cảm",
        "mediaPanel.trendingGifs": "Thịnh hành",
        "mediaPanel.emptyGifs": "GIF sẽ xuất hiện ở đây",
    ]
}
