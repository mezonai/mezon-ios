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

    enum MessageAction {
        static let reply            = "messageAction.reply"
        static let copyText         = "messageAction.copyText"
        static let editMessage      = "messageAction.editMessage"
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

        "messageAction.reply": "Reply",
        "messageAction.copyText": "Copy Text",
        "messageAction.editMessage": "Edit Message",
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

        "messageAction.reply": "Trả lời",
        "messageAction.copyText": "Sao chép văn bản",
        "messageAction.editMessage": "Chỉnh sửa tin nhắn",
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
