import Foundation


enum L10n {


    enum Tab {
        static let clans         = "tab.clans"
        static let messages      = "tab.messages"
        static let notifications = "tab.notifications"
        static let profile       = "tab.profile"
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
        static let welcomeBack    = "login.welcomeBack"
        static let email          = "login.email"
        static let password       = "login.password"
        static let logIn          = "login.logIn"
        static let otp            = "login.otp"
        static let sendOTP        = "login.sendOTP"
        static let resendOTP      = "login.resendOTP"
        static let loginFailed    = "login.loginFailed"
        static let phone          = "login.phone"
        static let enterEmail     = "login.enterEmail"
        static let enterPhone     = "login.enterPhone"
    }


    enum OTPVerify {
        static let title          = "otpVerify.loginToMezon"
        static let verifyOTP      = "otpVerify.verifyOTP"
        static let resendOTP      = "otpVerify.resendOTP"
        static let otpNotMatch    = "otpVerify.otpNotMatch"
        static let didNotReceive  = "otpVerify.didNotReceiveCode"
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


    enum Error {
        static let networkError       = "error.networkError"
        static let connectionFailed   = "error.connectionFailed"
        static let somethingWentWrong = "error.somethingWentWrong"
        static let sessionExpiredTitle  = "error.sessionExpiredTitle"
        static let sessionExpiredContent = "error.sessionExpiredContent"
        static let sessionExpiredConfirm = "error.sessionExpiredConfirm"
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

        "otpVerify.loginToMezon":      "Log in to Mezon",
        "otpVerify.verifyOTP":         "Verify OTP",
        "otpVerify.resendOTP":         "Resend OTP",
        "otpVerify.otpNotMatch":       "OTP invalid",
        "otpVerify.didNotReceiveCode": "Didn't receive a code?",

        "clan.createClan":  "Create Clan",
        "clan.members":     "Members",
        "clan.settings":    "Clan Settings",

        "channel.label":  "channel",
        "channel.thread": "Threads",

        "error.networkError":           "Network Error",
        "error.connectionFailed":       "Connection failed. Please try again.",
        "error.somethingWentWrong":     "Something went wrong",
        "error.sessionExpiredTitle":    "Session Expired",
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

        "otpVerify.loginToMezon":      "Đăng nhập tài khoản Mezon",
        "otpVerify.verifyOTP":         "Xác thực OTP",
        "otpVerify.resendOTP":         "Gửi lại OTP",
        "otpVerify.otpNotMatch":       "Mã OTP không hợp lệ",
        "otpVerify.didNotReceiveCode": "Không nhận được mã?",

        "clan.createClan":  "Tạo Clan",
        "clan.members":     "Thành viên",
        "clan.settings":    "Cài đặt Clan",

        "channel.label":  "kênh",
        "channel.thread": "Chủ đề",

        "error.networkError":           "Lỗi kết nối mạng",
        "error.connectionFailed":       "Kết nối thất bại. Vui lòng thử lại.",
        "error.somethingWentWrong":     "Đã xảy ra lỗi",
        "error.sessionExpiredTitle":    "Phiên đăng nhập hết hạn",
        "error.sessionExpiredContent":  "Phiên đăng nhập của bạn đã hết hạn. Vui lòng đăng nhập lại.",
        "error.sessionExpiredConfirm":  "Đăng nhập lại",
    ]
}
