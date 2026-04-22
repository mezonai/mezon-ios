import Foundation

enum L10n {

    enum Tab {
        static let clans         = "tab.clans"
        static let messages      = "tab.messages"
        static let notifications = "tab.notifications"
        static let profile       = "tab.profile"
    }

    enum Profile {
        static let addStatus         = "profile.addStatus"
        static let editProfile       = "profile.editProfile"
        static let balance           = "profile.balance"
        static let transferFunds     = "profile.transferFunds"
        static let historyTransaction = "profile.historyTransaction"
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
        static let forwarded      = "common.forwarded"
        static let saveChanges    = "common.saveChanges"
        static let enable         = "common.enable"
        static let reset          = "common.reset"
        static let actions        = "common.actions"
        static let notifications  = "common.notifications"
        static let appearance     = "common.appearance"
        static let theme          = "common.theme"
        static let language       = "common.language"
        static let linkEmail      = "common.linkEmail"
        static let linkPhoneNumber = "common.linkPhoneNumber"
    }

    enum AccountSetting {
        static let accountInformation = "accountSetting.accountInformation"
        static let users              = "accountSetting.users"
        static let accountManagement  = "accountSetting.accountManagement"
        static let username           = "accountSetting.username"
        static let displayName        = "accountSetting.displayName"
        static let blockedUsers       = "accountSetting.blockedUsers"
        static let setPassword        = "accountSetting.setPassword"
        static let phoneSectionTitle  = "accountSetting.phoneNumberSetting.title"
        static let emailSectionTitle  = "accountSetting.emailSetting.title"
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
        static let emptyTitle = "notifications.empty.title"
        static let emptyDescription = "notifications.empty.description"
        static let repliedTo = "notifications.repliedTo"
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
    }

    enum Discover {
        static let communityOnMezon = "discover.communityOnMezon"
        static let exploreCommunities = "discover.exploreCommunities"
        static let membersLabel = "discover.membersLabel"
        static let verified = "discover.verified"
        static let joinClan = "discover.joinClan"
        static let noCommunities = "discover.noCommunities"
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
        static let filterTitle           = "sharing.filterTitle"
        static let filterAll             = "sharing.filterAll"
        static let filterUsers           = "sharing.filterUsers"
        static let filterChannels        = "sharing.filterChannels"
        static let sessionExpired        = "sharing.sessionExpired"
        static let errorTitle            = "sharing.errorTitle"
        static let alertOK             = "sharing.alertOK"
    }

    enum ClanInviteSheet {
        static let title                = "clan.inviteSheet.title"
        static let share                = "clan.inviteSheet.share"
        static let copy                 = "clan.inviteSheet.copy"
        static let qrCode               = "clan.inviteSheet.qrCode"
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

    enum ThreadList {
        static let searchPlaceholder = "threadList.searchPlaceholder"
        static let empty = "threadList.empty"
        static let joinedThread = "threadList.joinedThread"
        static let joinedThreads = "threadList.joinedThreads"
        static let otherActiveThread = "threadList.otherActiveThread"
        static let otherActiveThreads = "threadList.otherActiveThreads"
        static let olderThread = "threadList.olderThread"
        static let olderThreads = "threadList.olderThreads"
        static let searchThread = "threadList.searchThread"
        static let searchThreads = "threadList.searchThreads"
        static let createThreadSoon = "threadList.createThreadSoon"
    }

    enum Channel {
        static let label          = "channel.label"
        static let thread         = "channel.thread"
        static let settings       = "channel.settings"
        static let name           = "channel.name"
        static let topic          = "channel.topic"
        static let delete         = "channel.delete"
        static let deleteConfirm  = "channel.deleteConfirm"
    }

    enum ChannelAction {
        static let markAsRead           = "channel.action.markAsRead"
        static let markFavorite         = "channel.action.markFavorite"
        static let unmarkFavorite       = "channel.action.unmarkFavorite"
        static let copyLink             = "channel.action.copyLink"
        static let mute                 = "channel.action.mute"
        static let unmute               = "channel.action.unmute"
        static let notificationSettings = "channel.action.notificationSettings"
        static let editChannel          = "channel.action.editChannel"
    }

    enum ChannelSetting {
        static let changeCategory       = "channel.setting.changeCategory"
        static let permissions          = "channel.setting.permissions"
        static let quickAction          = "channel.setting.quickAction"
        static let banList              = "channel.setting.banList"
        static let webhook              = "channel.setting.webhook"
        static let privacyFooter        = "channel.setting.privacyFooter"
    }

    enum ChannelMessages {
        static let emptyMessages  = "channelMessages.emptyMessages"
        static let todayAt        = "channelMessages.todayAt"
        static let yesterdayAt   = "channelMessages.yesterdayAt"
        static let writeMessage   = "channelMessages.writeMessage"
        static let userIsTyping        = "channelMessages.userIsTyping"
        static let usersAreTyping      = "channelMessages.usersAreTyping"
        static let severalPeopleTyping = "channelMessages.severalPeopleTyping"
        static let voiceMessageA11y      = "channelMessages.voiceMessageA11y"
        static let yourLocation          = "channelMessages.yourLocation"
        static let locationOf            = "channelMessages.locationOf"
        static let clanInviteLoadFailed  = "channelMessages.clanInviteLoadFailed"
    }

    enum DirectMessage {
        static let you        = "directMessage.you"
        static let addFriend = "directMessage.addFriend"

        static let groupCreated   = "directMessage.groupCreated"
        static let previewFile    = "directMessage.previewFile"
        static let previewLink    = "directMessage.previewLink"
        static let previewLocation = "directMessage.previewLocation"
        static let previewContact = "directMessage.previewContact"
    }

    enum MessageAction {
        static let reply            = "messageAction.reply"
        static let copyText         = "messageAction.copyText"
        static let editMessage      = "messageAction.editMessage"
        static let editingMessage   = "messageAction.editingMessage"
        static let editedSuffix     = "messageAction.editedSuffix"
        static let deleteMessage    = "messageAction.deleteMessage"
        static let pinMessage       = "messageAction.pinMessage"
        static let forward          = "messageAction.forward"
        static let copied           = "messageAction.copied"
        static let giveACoffee      = "messageAction.giveACoffee"
        static let forwardMessage   = "messageAction.forwardMessage"
        static let createThread     = "messageAction.createThread"
        static let markUnread       = "messageAction.markUnread"
        static let topicDiscussion  = "messageAction.topicDiscussion"
        static let markMessage      = "messageAction.markMessage"
        static let quickMenu        = "messageAction.quickMenu"
        static let report           = "messageAction.report"
        static let pinMessageConfirm = "messageAction.pinMessageConfirm"
        static let pinSuccess       = "messageAction.pinSuccess"
        static let pinError         = "messageAction.pinError"
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

    enum ChannelDetail {
        static let members = "channelDetail.members"
        static let media   = "channelDetail.media"
        static let files   = "channelDetail.files"
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
        static let pinEmbedPreview = "channelDetail.pinEmbedPreview"
        static let noPinsYet = "channelDetail.noPinsYet"
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
        static let toastSelfAddError  = "friendRequest.toastSelfAddError"
        static let toastBlockedError  = "friendRequest.toastBlockedError"
        static let toastAlreadyFriend = "friendRequest.toastAlreadyFriend"
        static let toastWaitAccept    = "friendRequest.toastWaitAccept"
        static let toastIncomingReq   = "friendRequest.toastIncomingReq"
        static let toastSendSuccess   = "friendRequest.toastSendSuccess"
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
        "common.forwarded":     "Forwarded",
        "common.saveChanges":   "Save Changes",
        "common.enable":        "Enable",
        "common.reset":         "Reset",
        "common.actions":       "Actions",
        "common.notifications": "Notifications",
        "common.appearance":    "Appearance",
        "common.theme":         "Theme",
        "common.language":      "Language",
        "common.linkEmail":     "Add email",
        "common.linkPhoneNumber": "Add phone number",

        "accountSetting.accountInformation": "Account Information",
        "accountSetting.users": "Users",
        "accountSetting.accountManagement": "Account Management",
        "accountSetting.username": "Username",
        "accountSetting.displayName": "Display Name",
        "accountSetting.blockedUsers": "Blocked Users",
        "accountSetting.setPassword": "Set Password",
        "accountSetting.phoneNumberSetting.title": "Phone",
        "accountSetting.emailSetting.title": "Email",

        "emailSetting.updateEmailTitle": "Update Email",
        "emailSetting.newEmail": "New Email",
        "emailSetting.nextButton": "Next",
        "emailSetting.invalidEmail": "Invalid email address",
        "emailSetting.emailAlreadyLinked": "This email is already linked",
        "emailSetting.tooFast": "Please wait %ds before requesting again",
        "emailSetting.updateFailed": "Failed to update email. Please try again.",
        "emailSetting.verifyEmailTitle": "Verify Email",
        "emailSetting.verifyDescription": "Enter the 6-digit code we sent to",
        "emailSetting.verifyButton": "Verify Code",
        "emailSetting.verifySuccess": "Email linked successfully",

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
        "login.enterPhone":     "Enter your phone",
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
        "notifications.empty.title": "Notthing here yet",
        "notifications.empty.description": "Come back for notifications on events, stream and more",
        "notifications.repliedTo": "Replied to: ",
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

        "discover.communityOnMezon": "Community on Mezon",
        "discover.exploreCommunities": "Explore communities",
        "discover.membersLabel": "%d members",
        "discover.verified": "Verified",
        "discover.joinClan": "Join Clan",
        "discover.noCommunities": "No communities to show.",
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

        "clan.action.invite":               "Invite",
        "clan.action.markAsRead":           "Mark as Read",
        "clan.action.createEvent":          "Create Event",
        "clan.action.createCategory":       "Create Category",
        "clan.action.editClanProfile":      "Edit Clan Profile",
        "clan.action.auditLog" :            "Audit log",
        "clan.action.leaveClan":            "Leave Clan",
        "clan.action.deleteClan":           "Delete Clan",
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
        "sharing.title":                    "Share",
        "sharing.suggestionsSection":       "Suggestions",
        "sharing.searchPlaceholderAll":     "Select a channel or user",
        "sharing.searchPlaceholderUsers":   "Select user",
        "sharing.searchPlaceholderChannels":"Select channel",
        "sharing.emptySuggestions":         "No channels or conversations yet. Open the app and browse your servers, then try again.",
        "sharing.commentPlaceholder":       "Add a comment (optional)",
        "sharing.sending":                  "Sending…",
        "sharing.filterTitle":              "Filter",
        "sharing.filterAll":                "All",
        "sharing.filterUsers":              "Users",
        "sharing.filterChannels":           "Channels",
        "sharing.sessionExpired":           "Session expired",
        "sharing.errorTitle": "Error",
        "sharing.alertOK": "OK",

        "clan.inviteSheet.title":           "Invite a friend",
        "clan.inviteSheet.share":           "Share Invite",
        "clan.inviteSheet.copy":            "Copy Link",
        "clan.inviteSheet.qrCode":          "QR Code",
        "clan.inviteSheet.linkCopied":      "Link Copied!",
        "clan.inviteSheet.searchPlaceholder":"Invite friend to clan",
        "clan.inviteSheet.loadingInviteLink":"Creating invite link...",
        "clan.inviteSheet.emptyTitle":      "No friends to invite",
        "clan.inviteSheet.emptyDescription":"Add friends to your friend list to invite them to this clan.",
        "clan.inviteSheet.emptyAction":     "Add some friends",
        "clan.inviteSheet.sessionNotFound": "Session not found.",
        "clan.inviteSheet.cannotCreateInvite":"Cannot create clan invite link.",
        "clan.inviteSheet.cannotSendInvite":"Cannot send invite to %@.",
        "clan.inviteSheet.invite":          "Invite",
        "clan.inviteSheet.invited":         "Invited",
        "clan.inviteSheet.unknownClan":     "Unknown Clan",

        "threadList.searchPlaceholder": "Search for Thread Name",
        "threadList.empty": "No threads yet",
        "threadList.joinedThread": "joined thread",
        "threadList.joinedThreads": "joined threads",
        "threadList.otherActiveThread": "other active thread",
        "threadList.otherActiveThreads": "other active threads",
        "threadList.olderThread": "older thread",
        "threadList.olderThreads": "older threads",
        "threadList.searchThread": "search result",
        "threadList.searchThreads": "search results",
        "threadList.createThreadSoon": "Create thread is not available here yet.",

        "channel.label":  "channel",
        "channel.thread": "Threads",
        "channel.settings": "Channel Settings",
        "channel.name":   "Channel Name",
        "channel.topic":  "Channel Topic",
        "channel.delete": "Delete Channel",
        "channel.deleteConfirm": "Are you sure you want to delete this channel?",

        "channel.action.markAsRead":           "Mark as Read",
        "channel.action.markFavorite":         "Mark Favorite",
        "channel.action.unmarkFavorite":       "Unmark Favorite",
        "channel.action.copyLink":             "Copy Link",
        "channel.action.mute":                 "Mute Channel",
        "channel.action.unmute":               "Unmute Channel",
        "channel.action.notificationSettings": "Notification Settings",
        "channel.action.editChannel":          "Edit Channel",

        "channel.setting.changeCategory":       "Change Category",
        "channel.setting.permissions":          "Channel Permissions",
        "channel.setting.quickAction":          "Quick Action",
        "channel.setting.banList":              "Ban List",
        "channel.setting.webhook":              "Webhook",
        "channel.setting.privacyFooter":        "Change privacy settings and customize how members can interact with this channel.",

        "channelMessages.emptyMessages": "No messages yet",
        "channelMessages.todayAt": "Today at %@",
        "channelMessages.yesterdayAt": "Yesterday at %@",
        "channelMessages.writeMessage": "Write message...",
        "channelMessages.userIsTyping": "%@ is typing…",
        "channelMessages.usersAreTyping": "%@ are typing…",
        "channelMessages.severalPeopleTyping": "Several people are typing…",
        "channelMessages.voiceMessageA11y": "Voice message. Tap to play or pause.",
        "channelMessages.yourLocation": "Your location",
        "channelMessages.locationOf": "%@'s location",
        "channelMessages.clanInviteLoadFailed": "Couldn't load this clan invite.",

        "directMessage.addFriend": "Add Friend",
        "directMessage.you": "You",
        "directMessage.groupCreated": "Group created",
        "directMessage.previewFile": "File",
        "directMessage.previewLink": "Link",
        "directMessage.previewLocation": "Location",
        "directMessage.previewContact": "Contact",

        "friendRequest.title": "Add Friend",
        "friendRequest.received": "Received",
        "friendRequest.sent": "Sent",
        "friendRequest.emptyReceivedTitle": "No friend requests",
        "friendRequest.emptyReceivedDesc": "Here you will see all the friend requests that people send to you.",
        "friendRequest.addByTitle": "Add by username or phone number",
        "friendRequest.addByQuestion": "Who would you like to add as a friend?",
        "friendRequest.addByPlaceholder": "Enter username or phone number",
        "friendRequest.addByHintFormat": "By the way, your username is %@",
        "friendRequest.addBySending": "Sending...",
        "friendRequest.addBySubmit": "Send Friend Request",
        "friendRequest.toastSelfAddError": "Hmm, that didn't work. Double-check that the username is correct",
        "friendRequest.toastBlockedError": "You have blocked this user. Please unblock them before sending a friend request.",
        "friendRequest.toastAlreadyFriend": "You're already friends with that user!",
        "friendRequest.toastWaitAccept": "You have already sent a friend request to this user!",
        "friendRequest.toastIncomingReq": "This user already sent you a friend request",
        "friendRequest.toastSendSuccess": "Friend request sent successfully!",

        "messageAction.reply": "Reply",
        "messageAction.copyText": "Copy Text",
        "messageAction.editMessage": "Edit Message",
        "messageAction.editingMessage": "Editing message",
        "messageAction.editedSuffix": "(edited)",
        "messageAction.deleteMessage": "Delete Message",
        "messageAction.pinMessage": "Pin Message",
        "messageAction.forward": "Forward",
        "messageAction.copied": "Copied to clipboard",
        "messageAction.giveACoffee": "Give A Coffee",
        "messageAction.forwardMessage": "Forward Message",
        "messageAction.createThread": "Create Thread",
        "messageAction.markUnread": "Mark Unread",
        "messageAction.topicDiscussion": "Topic Discussion",
        "messageAction.markMessage": "Mark Message",
        "messageAction.quickMenu": "Quick Menu",
        "messageAction.report": "Report",
        "messageAction.pinMessageConfirm": "Please confirm if you would like to pin this message?",
        "messageAction.pinSuccess": "Message pinned successfully",
        "messageAction.pinError": "Failed to pin message",
        "messageAction.yes": "Yes",
        "messageAction.no": "No",

        "profile.addStatus": "Add Status",
        "profile.editProfile": "Edit Profile",
        "profile.balance": "Balance",
        "profile.transferFunds": "Transfer Funds",
        "profile.historyTransaction": "History Transaction",
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
        "profileSetting.noClanTitle": "No Clans Yet",
        "profileSetting.noClanDesc": "You haven't joined any clans yet.",
        "profileSetting.directMessageIcon": "Direct Message Icon",

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

        "error.networkError": "Network Error",
        "error.connectionFailed": "Connection failed. Please try again.",
        "error.somethingWentWrong": "Something went wrong",
        "error.sessionExpiredTitle": "Session Expired",
        "error.sessionExpiredOrNetwork": "Session Expired or Network Error",
        "error.sessionExpiredContent":  "Your session has expired. Please log in again to continue.",
        "error.sessionExpiredConfirm":  "Login Again",

        "channelDetail.members": "Members",
        "channelDetail.media":   "Media",
        "channelDetail.files":   "Files",
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
        "channelDetail.pinEmbedPreview": "Embed",
        "channelDetail.noPinsYet": "No pinned messages",
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
        "common.forwarded":     "Đã chuyển tiếp",
        "common.saveChanges":   "Lưu thay đổi",
        "common.enable":        "Bật",
        "common.reset":         "Đặt lại",
        "common.actions":       "Hành động",
        "common.notifications": "Thông báo",
        "common.appearance":    "Giao diện",
        "common.theme":         "Chủ đề",
        "common.language":      "Ngôn ngữ",
        "common.linkEmail":     "Thêm email",
        "common.linkPhoneNumber": "Thêm số điện thoại",

        "accountSetting.accountInformation": "Thông tin tài khoản",
        "accountSetting.users": "Người dùng",
        "accountSetting.accountManagement": "Quản lý tài khoản",
        "accountSetting.username": "Tên đăng nhập",
        "accountSetting.displayName": "Tên hiển thị",
        "accountSetting.blockedUsers": "Người dùng bị chặn",
        "accountSetting.setPassword": "Đặt mật khẩu",
        "accountSetting.phoneNumberSetting.title": "Số điện thoại",
        "accountSetting.emailSetting.title": "Email",

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
        "notifiactions.repliedTo": "Trả lời: ",
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

        "discover.communityOnMezon": "Cộng đồng trên Mezon",
        "discover.exploreCommunities": "Khám phá cộng đồng",
        "discover.membersLabel": "%d thành viên",
        "discover.verified": "Đã xác minh",
        "discover.joinClan": "Tham gia Clan",
        "discover.noCommunities": "Không có cộng đồng để hiển thị.",
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

        "clan.action.invite":               "Mời",
        "clan.action.markAsRead":           "Đánh dấu đã đọc",
        "clan.action.createEvent":          "Tạo sự kiện",
        "clan.action.createCategory":       "Tạo danh mục",
        "clan.action.editClanProfile":      "Chỉnh sửa hồ sơ Clan",
        "clan.action.auditLog" :            "Nhật kí kiểm tra",
        "clan.action.leaveClan":            "Rời Clan",
        "clan.action.deleteClan":           "Xóa Clan",
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
        "sharing.title":                    "Chia sẻ",
        "sharing.suggestionsSection":       "Gợi ý",
        "sharing.searchPlaceholderAll":     "Chọn kênh hoặc người dùng",
        "sharing.searchPlaceholderUsers":   "Chọn người dùng",
        "sharing.searchPlaceholderChannels":"Chọn kênh",
        "sharing.emptySuggestions":         "Chưa có kênh hoặc cuộc trò chuyện. Mở ứng dụng và vào máy chủ của bạn, rồi thử lại.",
        "sharing.commentPlaceholder":       "Thêm bình luận (tùy chọn)",
        "sharing.sending":                  "Đang gửi…",
        "sharing.filterTitle":              "Lọc",
        "sharing.filterAll":                "Tất cả",
        "sharing.filterUsers":              "Người dùng",
        "sharing.filterChannels":           "Kênh",
        "sharing.sessionExpired":           "Phiên đăng nhập hết hạn",
        "sharing.errorTitle":               "Lỗi",
        "sharing.alertOK":                  "OK",
        "clan.inviteSheet.title":           "Mời bạn bè",
        "clan.inviteSheet.share":           "Chia sẻ",
        "clan.inviteSheet.copy":            "Sao chép",
        "clan.inviteSheet.qrCode":          "Mã QR",
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

        "threadList.searchPlaceholder": "Tìm theo tên chủ đề",
        "threadList.empty": "Chưa có chủ đề",
        "threadList.joinedThread": "chủ đề đã tham gia",
        "threadList.joinedThreads": "chủ đề đã tham gia",
        "threadList.otherActiveThread": "chủ đề hoạt động khác",
        "threadList.otherActiveThreads": "chủ đề hoạt động khác",
        "threadList.olderThread": "chủ đề cũ",
        "threadList.olderThreads": "chủ đề cũ",
        "threadList.searchThread": "kết quả",
        "threadList.searchThreads": "kết quả",
        "threadList.createThreadSoon": "Tạo chủ đề từ đây sẽ có trong bản cập nhật sau.",

        "channel.label":  "kênh",
        "channel.thread": "Chủ đề",
        "channel.settings": "Cài đặt kênh",
        "channel.name":   "Tên kênh",
        "channel.topic":  "Chủ đề kênh",
        "channel.delete": "Xóa kênh",
        "channel.deleteConfirm": "Bạn có chắc chắn muốn xóa kênh này không?",

        "channel.action.markAsRead":           "Đánh dấu đã đọc",
        "channel.action.markFavorite":         "Yêu thích",
        "channel.action.unmarkFavorite":       "Bỏ yêu thích",
        "channel.action.copyLink":             "Sao chép liên kết",
        "channel.action.mute":                 "Tắt thông báo kênh",
        "channel.action.unmute":               "Bật thông báo kênh",
        "channel.action.notificationSettings": "Cài đặt thông báo",
        "channel.action.editChannel":          "Chỉnh sửa kênh",

        "channel.setting.changeCategory":       "Thay đổi danh mục",
        "channel.setting.permissions":          "Quyền hạn kênh",
        "channel.setting.quickAction":          "Hành động nhanh",
        "channel.setting.banList":              "Danh sách chặn",
        "channel.setting.webhook":              "Webhook",
        "channel.setting.privacyFooter":        "Thay đổi cài đặt quyền riêng tư và tùy chỉnh cách các thành viên có thể tương tác với kênh này.",

        "channelMessages.emptyMessages": "Chưa có tin nhắn",
        "channelMessages.todayAt": "Hôm nay lúc %@",
        "channelMessages.yesterdayAt": "Hôm qua lúc %@",
        "channelMessages.writeMessage": "Nhập tin nhắn...",
        "channelMessages.userIsTyping": "%@ đang nhập…",
        "channelMessages.usersAreTyping": "%@ đang nhập…",
        "channelMessages.severalPeopleTyping": "Nhiều người đang nhập…",
        "channelMessages.voiceMessageA11y": "Tin nhắn thoại. Chạm để phát hoặc tạm dừng.",
        "channelMessages.yourLocation": "Vị trí của bạn",
        "channelMessages.locationOf": "Vị trí của %@",
        "channelMessages.clanInviteLoadFailed": "Không tải được lời mời clan.",

        "directMessage.addFriend": "Thêm bạn",
        "directMessage.you": "Bạn",
        "directMessage.groupCreated": "Nhóm đã được tạo",
        "directMessage.previewFile": "Tệp",
        "directMessage.previewLink": "Liên kết",
        "directMessage.previewLocation": "Vị trí",
        "directMessage.previewContact": "Danh bạ",

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
        "friendRequest.toastSelfAddError": "Hmm, có lỗi xảy ra. Vui lòng kiểm tra lại tên người dùng có đúng không",
        "friendRequest.toastBlockedError": "Bạn đã chặn người dùng này. Vui lòng bỏ chặn để gửi lời mời kết bạn.",
        "friendRequest.toastAlreadyFriend": "Bạn đã là bạn bè với người dùng này!",
        "friendRequest.toastWaitAccept": "Bạn đã gửi yêu cầu kết bạn tới người dùng này rồi!",
        "friendRequest.toastIncomingReq": "Người này đã gửi yêu cầu kết bạn cho bạn",
        "friendRequest.toastSendSuccess": "Yêu cầu kết bạn đã được gửi thành công!",

        "messageAction.reply": "Trả lời",
        "messageAction.copyText": "Sao chép văn bản",
        "messageAction.editMessage": "Chỉnh sửa tin nhắn",
        "messageAction.editingMessage": "Đang chỉnh sửa tin nhắn",
        "messageAction.editedSuffix": "(đã chỉnh sửa)",
        "messageAction.deleteMessage": "Xóa tin nhắn",
        "messageAction.pinMessage": "Ghim tin nhắn",
        "messageAction.forward": "Chuyển tiếp",
        "messageAction.copied": "Đã sao chép",
        "messageAction.giveACoffee": "Tặng cà phê",
        "messageAction.forwardMessage": "Chuyển tiếp tin nhắn",
        "messageAction.createThread": "Tạo chủ đề",
        "messageAction.markUnread": "Đánh dấu chưa đọc",
        "messageAction.topicDiscussion": "Thảo luận chủ đề",
        "messageAction.markMessage": "Đánh dấu tin nhắn",
        "messageAction.quickMenu": "Menu nhanh",
        "messageAction.report": "Báo cáo",
        "messageAction.pinMessageConfirm": "Bạn có muốn ghim tin nhắn này không?",
        "messageAction.pinSuccess": "Ghim tin nhắn thành công",
        "messageAction.pinError": "Ghim tin nhắn thất bại",
        "messageAction.yes": "Đồng ý",
        "messageAction.no": "Không",

        "profile.addStatus": "Thêm trạng thái",
        "profile.editProfile": "Chỉnh sửa hồ sơ",
        "profile.balance": "Số dư",
        "profile.transferFunds": "Chuyển tiền",
        "profile.historyTransaction": "Lịch sử giao dịch",
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
        "profileSetting.noClanTitle": "Chưa có Clan",
        "profileSetting.noClanDesc": "Bạn chưa tham gia Clan nào.",
        "profileSetting.directMessageIcon": "Biểu tượng tin nhắn riêng",

        "qrScanner.title": "Quét mã QR",
        "qrScanner.cameraPermissionTitle": "Yêu cầu quyền truy cập Camera",
        "qrScanner.cameraPermissionMessage":
            "Vui lòng cho phép truy cập camera trong Cài đặt để quét mã QR.",
        "qrScanner.gallery": "Thư viện",
        "qrScanner.invalidQR": "Mã QR không hợp lệ",
        "qrScanner.loginConfirm": "Bạn có muốn đăng nhập với %@?",
        "qrScanner.joinGroup": "Tham gia nhóm",
        "qrScanner.transferTo": "Chuyển tiền cho %@",
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
        "qrScanner.qrTransfer": "Mã QR Chuyển tiền",
        "qrScanner.poweredBy": "Được cung cấp bởi Mezon",
        "qrScanner.shareWithOthers": "Chia sẻ với mọi người",
        "qrScanner.scanProfileHelp": "Quét mã QR này để trò chuyện với tôi hoặc xem hồ sơ của tôi",
        "qrScanner.scanTransferHelp": "Quét mã QR này để chuyển khoản",
        "qrScanner.scanInstruction": "Di chuyển camera đến mã QR để quét hoặc",
        "qrScanner.chooseFromGallery": "Chọn từ Thư viện ảnh",
        "qrScanner.sharePersonalQR": "Chia sẻ mã QR cá nhân ˄",

        "error.networkError": "Lỗi kết nối mạng",
        "error.connectionFailed": "Kết nối thất bại. Vui lòng thử lại.",
        "error.somethingWentWrong": "Đã xảy ra lỗi",
        "error.sessionExpiredTitle": "Phiên đăng nhập hết hạn",
        "error.sessionExpiredOrNetwork": "Phiên hết hạn hoặc lỗi mạng",
        "error.sessionExpiredContent":
            "Phiên đăng nhập của bạn đã hết hạn. Vui lòng đăng nhập lại.",
        "error.sessionExpiredConfirm": "Đăng nhập lại",

        "channelDetail.members": "Thành viên",
        "channelDetail.media":   "Phương tiện",
        "channelDetail.files":   "Tệp",
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
        "channelDetail.pinEmbedPreview": "Nội dung nhúng",
        "channelDetail.noPinsYet": "Chưa có tin nhắn ghim",
    ]
}
