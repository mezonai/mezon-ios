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

    static var mezonBorder:              UIColor { theme.border }
    static var mezonSeparator:           UIColor { theme.borderDim }

    static var mezonChannelSelected:     UIColor { theme.selectedOverlay }
    static var mezonChannelText:         UIColor { theme.channelNormal }
    static var mezonChannelTextActive:   UIColor { theme.channelUnread }

    static var outgoingBubble:           UIColor { theme.bgViolet }
    static var incomingBubble:           UIColor { theme.secondaryLight }

    static var mezonLink:                UIColor { theme.textLink }
    static var colorAvatarDefault:       UIColor { theme.colorAvatarDefault }
    static var textRoleLink:             UIColor { theme.textRoleLink }
    static var mezonError:               UIColor { .systemRed }
    static var mezonSuccess:             UIColor { theme.textSuccess }
    static var mezonWarning:             UIColor { theme.textWarning }

    static var mezonUnreadBadge:         UIColor { .systemRed }
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
}
