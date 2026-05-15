import UIKit

extension UIColor {

    static var theme: ThemeAttributes { ThemeManager.shared.attributes }

    static var mezonPrimary:             UIColor { theme.primary }
    static var mezonSecondary:           UIColor { theme.secondary }
    static var mezonTertiary:            UIColor { theme.tertiary }
    static var mezonBackground:          UIColor { theme.primary }
    static var mezonSecondaryBackground: UIColor { theme.secondary }
    static var mezonTertiaryBackground:  UIColor { theme.tertiary }

    static var mezonSidebarBackground:   UIColor { theme.tertiary }
    static var mezonChannelBackground:   UIColor { theme.secondary }

    static var mezonTextPrimary:         UIColor { theme.text }
    static var mezonTextStrong:          UIColor { theme.textStrong }
    static var mezonTextSecondary:       UIColor { theme.textNormal }
    static var mezonTextMuted:           UIColor { theme.textDisabled }

    static var mezonIconPrimary:         UIColor { theme.iconPrimary }
    static var mezonIconSecondary:       UIColor { theme.iconSecondary }
    static var mezonIconTertiary:        UIColor { theme.iconTertiary }

    static var mezonLabel:               UIColor { theme.textStrong }
    static var mezonSecondaryLabel:      UIColor { theme.textNormal }

    static var mezonBorder:              UIColor { theme.border }
    static var mezonSeparator:           UIColor { theme.borderDim }

    static var mezonChannelSelected:     UIColor { theme.selectedOverlay }
    static var mezonChannelText:         UIColor { theme.channelNormal }
    static var mezonChannelTextActive:   UIColor { theme.channelUnread }

    static var outgoingBubble:           UIColor { theme.bgViolet }
    static var incomingBubble:           UIColor { theme.secondaryLight }

    static var mezonLink:                UIColor { theme.textLink }

    static var textRoleLink:             UIColor { theme.textRoleLink }
    static var mezonError:               UIColor { .systemRed }
    static var mezonSuccess:             UIColor { theme.textSuccess }
    static var mezonWarning:             UIColor { theme.textWarning }

    static var mezonUnreadBadge:         UIColor { UIColor(hex: 0xC61E1B) }
    static var mezonMention:             UIColor { theme.textWarning.withAlphaComponent(0.3) }

    static var loginGradientColors:      [UIColor] { theme.loginGradientColors }
    static var loginInputBg:             UIColor { theme.loginInputBg }
    static var loginInputBorder:         UIColor { theme.loginInputBorder }
    static var loginPlaceholder:         UIColor { theme.loginPlaceholder }
    static var loginButtonBg:            UIColor { theme.loginButtonBg }
    static var loginButtonBgDisabled:    UIColor { theme.loginButtonBgDisabled }
    static var loginAlternativeText:     UIColor { theme.loginAlternativeText }
    static var loginTitleColor:          UIColor { theme.loginTitleColor }
    static var loginSubtitleColor:       UIColor { theme.loginSubtitleColor }
    static var loginInputTextColor:      UIColor { theme.loginInputTextColor }

    private static let avatarColors: [UIColor] = [
        UIColor(red: 0xAD/255.0, green: 0xE6/255.0, blue: 0x03/255.0, alpha: 1), 
        UIColor(red: 0x00/255.0, green: 0xB2/255.0, blue: 0xCC/255.0, alpha: 1), 
        UIColor(red: 0xFD/255.0, green: 0xA6/255.0, blue: 0x3C/255.0, alpha: 1), 
        UIColor(red: 0xE1/255.0, green: 0x6D/255.0, blue: 0xCC/255.0, alpha: 1), 
        UIColor(red: 0xE8/255.0, green: 0x46/255.0, blue: 0x7B/255.0, alpha: 1), 
        UIColor(red: 0x9C/255.0, green: 0x7C/255.0, blue: 0xFD/255.0, alpha: 1), 
        UIColor(red: 0x22/255.0, green: 0xE2/255.0, blue: 0xB3/255.0, alpha: 1), 
    ]

    static func avatarColor(for username: String) -> UIColor {
        guard let firstChar = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased().unicodeScalars.first else {
            return avatarColors[0]
        }
        let index = Int(firstChar.value) % avatarColors.count
        return avatarColors[index]
    }
}
