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
        static let saveChanges    = "common.saveChanges"
        static let enable         = "common.enable"
        static let reset          = "common.reset"
        static let actions        = "common.actions"
        static let notifications  = "common.notifications"
        static let appearance     = "common.appearance"
        static let theme          = "common.theme"
        static let language       = "common.language"
    }

    enum Settings {
        static let title          = "settings.title"
        static let language       = "settings.language"
        static let theme          = "settings.theme"
        static let notifications  = "settings.notifications"
        static let account        = "settings.account"
        static let privacy        = "settings.privacy"
    }

    enum Language {
        static let title          = "language.title"
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
        static let members        = "clan.members"
        static let settings       = "clan.settings"
    }

    enum Channel {
        static let label          = "channel.label"
        static let thread         = "channel.thread"
    }

    enum ChannelMessages {
        static let emptyMessages  = "channelMessages.emptyMessages"
        static let todayAt        = "channelMessages.todayAt"
        static let yesterdayAt   = "channelMessages.yesterdayAt"
        static let writeMessage   = "channelMessages.writeMessage"
    }

    enum DirectMessage {
        static let you        = "directMessage.you"
        static let addFriend = "directMessage.addFriend"
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
        "common.saveChanges":   "Save Changes",
        "common.enable":        "Enable",
        "common.reset":         "Reset",
        "common.actions":       "Actions",
        "common.notifications": "Notifications",
        "common.appearance":    "Appearance",
        "common.theme":         "Theme",
        "common.language":      "Language",

        "settings.title":         "Settings",
        "settings.language":      "Language",
        "settings.theme":         "Theme",
        "settings.notifications": "Notifications",
        "settings.account":       "Account",
        "settings.privacy":       "Privacy",

        "language.title":         "Language Settings",

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
        "clan.members":     "Members",
        "clan.settings":    "Clan Settings",

        "channel.label":  "channel",
        "channel.thread": "Threads",

        "channelMessages.emptyMessages": "No messages yet",
        "channelMessages.todayAt": "Today at %@",
        "channelMessages.yesterdayAt": "Yesterday at %@",
        "channelMessages.writeMessage": "Write message...",

        "directMessage.addFriend": "Add Friend",
        "directMessage.you": "You",

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

        "error.networkError":           "Network Error",
        "error.connectionFailed":       "Connection failed. Please try again.",
        "error.somethingWentWrong":     "Something went wrong",
        "error.sessionExpiredTitle":    "Session Expired",
        "error.sessionExpiredOrNetwork": "Session Expired or Network Error",
        "error.sessionExpiredContent":  "Your session has expired. Please log in again to continue.",
        "error.sessionExpiredConfirm":  "Login Again",
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
        "common.saveChanges":   "Lưu thay đổi",
        "common.enable":        "Bật",
        "common.reset":         "Đặt lại",
        "common.actions":       "Hành động",
        "common.notifications": "Thông báo",
        "common.appearance":    "Giao diện",
        "common.theme":         "Chủ đề",
        "common.language":      "Ngôn ngữ",

        "settings.title":         "Cài đặt",
        "settings.language":      "Ngôn ngữ",
        "settings.theme":         "Chủ đề",
        "settings.notifications": "Thông báo",
        "settings.account":       "Tài khoản",
        "settings.privacy":       "Quyền riêng tư",

        "language.title":         "Cài đặt ngôn ngữ",

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
        "clan.members":     "Thành viên",
        "clan.settings":    "Cài đặt Clan",

        "channel.label":  "kênh",
        "channel.thread": "Chủ đề",

        "channelMessages.emptyMessages": "Chưa có tin nhắn",
        "channelMessages.todayAt": "Hôm nay lúc %@",
        "channelMessages.yesterdayAt": "Hôm qua lúc %@",
        "channelMessages.writeMessage": "Nhập tin nhắn...",

        "directMessage.addFriend": "Thêm bạn",
        "directMessage.you": "Bạn",

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

        "error.networkError":           "Lỗi kết nối mạng",
        "error.connectionFailed":       "Kết nối thất bại. Vui lòng thử lại.",
        "error.somethingWentWrong":     "Đã xảy ra lỗi",
        "error.sessionExpiredTitle":    "Phiên đăng nhập hết hạn",
        "error.sessionExpiredOrNetwork": "Phiên hết hạn hoặc lỗi mạng",
        "error.sessionExpiredContent":  "Phiên đăng nhập của bạn đã hết hạn. Vui lòng đăng nhập lại.",
        "error.sessionExpiredConfirm":  "Đăng nhập lại",
    ]
}
