import UIKit

struct ThemeAttributes {
    let primary: UIColor
    let primaryGradient: UIColor
    let secondary: UIColor
    let secondaryWeight: UIColor
    let secondaryLight: UIColor
    let tertiary: UIColor
    let border: UIColor
    let borderDim: UIColor
    let borderHighlight: UIColor
    let borderRadio: UIColor
    let text: UIColor
    let textStrong: UIColor
    let textDisabled: UIColor
    let textNormal: UIColor
    let white: UIColor
    let black: UIColor
    let bgInputPrimary: UIColor
    let charcoal: UIColor
    let jet: UIColor
    let channelUnread: UIColor
    let channelNormal: UIColor
    let midnightBlue: UIColor
    let textLink: UIColor
    let reactionBg: UIColor
    let reactionBorder: UIColor
    let selectedOverlay: UIColor
    let bgViolet: UIColor
    let colorAvatarDefault: UIColor
    let colorActiveClan: UIColor
    let textRoleLink: UIColor
    let darkMossGreen: UIColor
    let badgeHighlight: UIColor
    let textWarning: UIColor
    let borderWarning: UIColor
    let darkJade: UIColor
    let bgInfor: UIColor
    let borderInfor: UIColor
    let headerInfor: UIColor
    let descInfor: UIColor
    let textSuccess: UIColor
    let loginGradientColors: [UIColor]
    let loginInputBg: UIColor
    let loginInputBorder: UIColor
    let loginPlaceholder: UIColor
    let loginButtonBg: UIColor
    let loginButtonBgDisabled: UIColor
    let loginAlternativeText: UIColor
    let loginTitleColor: UIColor
    let loginSubtitleColor: UIColor
    let loginInputTextColor: UIColor

    var swatchColor: UIColor { primary }
}

enum AppTheme: String, CaseIterable {
    case dark
    case light
    case sunrise
    case redDark
    case purpleHaze
    case abyssDark
    case sunset
    case system = "system"

    var localizedDisplayName: String {
        switch self {
        case .dark:       return L(L10n.Theme.dark)
        case .light:      return L(L10n.Theme.light)
        case .sunrise:    return L(L10n.Theme.sunrise)
        case .redDark:    return L(L10n.Theme.redDark)
        case .purpleHaze: return L(L10n.Theme.purpleHaze)
        case .abyssDark:  return L(L10n.Theme.abyssDark)
        case .sunset:     return L(L10n.Theme.sunset)
        case .system:     return L(L10n.Theme.system)
        }
    }

    var attributes: ThemeAttributes {
        switch self {
        case .dark:       return .dark
        case .light:      return .light
        case .sunrise:    return .sunrise
        case .redDark:    return .redDark
        case .purpleHaze: return .purpleHaze
        case .abyssDark:  return .abyssDark
        case .sunset:     return .sunset
        case .system:
            if #available(iOS 13.0, *), UIScreen.main.traitCollection.userInterfaceStyle == .dark {
                return .dark
            }
            return .light
        }
    }
}

private extension ThemeAttributes {

    static let dark = ThemeAttributes(
        primary:          hex("#121218"),
        primaryGradient:  hex("#121218"),
        secondary:        hex("#1c1d23"),
        secondaryWeight:  hex("#212122"),
        secondaryLight:   hex("#26272f"),
        tertiary:         hex("#383a43"),
        border:           hex("#2a2d31"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#dadada"),
        text:             hex("#CCCCCC"),
        textStrong:       hex("#dfe0e4"),
        textDisabled:     hex("#7b7b83"),
        textNormal:       hex("#898993"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        bgInputPrimary:   hex("#2a2e31"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#334155"),
        colorActiveClan:  hex("#141c2a"),
        textRoleLink:     hex("#009c67"),
        darkMossGreen:    hex("#3c4c43"),
        badgeHighlight:   hex("#2e2f34"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#174033"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#1c1d22"), hex("#2a2d31"), hex("#1c1d22")],
        loginInputBg:     hex("#2a2e31"),
        loginInputBorder: hex("#3e4045"),
        loginPlaceholder: hex("#7b7b83"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#4a4d51"),
        loginAlternativeText: hex("#7b7b83"),
        loginTitleColor:  hex("#ffffff"),
        loginSubtitleColor: hex("#b0b0b0"),
        loginInputTextColor: hex("#ffffff")
    )

    static let light = ThemeAttributes(
        primary:          hex("#f4f4f8"),
        primaryGradient:  hex("#ffffff"),
        secondary:        hex("#ffffff"),
        secondaryWeight:  hex("#F0F0F0"),
        secondaryLight:   hex("#fefdfe"),
        tertiary:         hex("#f2f3f6"),
        border:           hex("#ededf1"),
        borderDim:        hex("#dfdfdf"),
        borderHighlight:  hex("#e0e1e3"),
        borderRadio:      hex("#4d4d54"),
        text:             hex("#29292b"),
        textStrong:       hex("#070709"),
        textDisabled:     hex("#606065"),
        textNormal:       hex("#e0e1e3"),
        white:            hex("#000000"),
        black:            hex("#FFFFFF"),
        bgInputPrimary:   hex("#a0a1a6"),
        charcoal:         hex("#f2f3f5"),
        jet:              hex("#ecedef"),
        channelUnread:    hex("#000000"),
        channelNormal:    hex("#6c7077"),
        midnightBlue:     hex("#d1e0ff"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(229, 231, 235, 0.6),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#FFFFFF96"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#8a97a5"),
        colorActiveClan:  hex("#d8e2f0"),
        textRoleLink:     hex("#00b098"),
        darkMossGreen:    hex("#e2f1e5"),
        badgeHighlight:   hex("#ffffff"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#50f5c0"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#f0edfd"), hex("#beb5f8"), hex("#9774fa")],
        loginInputBg:     hex("#ffffff"),
        loginInputBorder: hex("#cccccc"),
        loginPlaceholder: hex("#a8a8a8"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#88888c"),
        loginAlternativeText: hex("#5e5e5e"),
        loginTitleColor:  hex("#191919"),
        loginSubtitleColor: hex("#505050"),
        loginInputTextColor: hex("#191919")
    )

    static let sunrise = ThemeAttributes(
        primary:          hex("#ead9e0"),
        primaryGradient:  hex("#fbdbe3"),
        secondary:        hex("#fae9ef"),
        secondaryWeight:  hex("#ffe5ed"),
        secondaryLight:   hex("#f8ebee"),
        tertiary:         hex("#faf2f2"),
        border:           hex("#9e9eaa"),
        borderDim:        hex("#f4f4f4"),
        borderHighlight:  hex("#e0e1e3"),
        borderRadio:      hex("#4d4d54"),
        text:             hex("#181819"),
        textStrong:       hex("#070709"),
        textDisabled:     hex("#606065"),
        textNormal:       hex("#e0e1e3"),
        white:            hex("#000000"),
        black:            hex("#FFFFFF"),
        bgInputPrimary:   hex("#707075"),
        charcoal:         hex("#f2f3f5"),
        jet:              hex("#ecedef"),
        channelUnread:    hex("#000000"),
        channelNormal:    hex("#6c7077"),
        midnightBlue:     hex("#d1e0ff"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(229, 231, 235, 0.6),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#FFFFFF96"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#8a97a5"),
        colorActiveClan:  hex("#d8e2f0"),
        textRoleLink:     hex("#00b098"),
        darkMossGreen:    hex("#e2f1e5"),
        badgeHighlight:   hex("#ffffff"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#50f5c0"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#ead9e0"), hex("#f5d0da"), hex("#e8b8c5")],
        loginInputBg:     hex("#ffffff"),
        loginInputBorder: hex("#cccccc"),
        loginPlaceholder: hex("#a8a8a8"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#88888c"),
        loginAlternativeText: hex("#5e5e5e"),
        loginTitleColor:  hex("#191919"),
        loginSubtitleColor: hex("#505050"),
        loginInputTextColor: hex("#191919")
    )

    static let redDark = ThemeAttributes(
        primary:          hex("#610101"),
        primaryGradient:  hex("#700303"),
        secondary:        hex("#2B1011"),
        secondaryWeight:  hex("#67171a"),
        secondaryLight:   hex("#70393c"),
        tertiary:         hex("#141319"),
        border:           hex("#2e2f34"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        text:             hex("#CCCCCC"),
        textStrong:       hex("#dfe0e4"),
        textDisabled:     hex("#7b7b83"),
        textNormal:       hex("#898993"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        bgInputPrimary:   hex("#2a2e31"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#334155"),
        colorActiveClan:  hex("#141c2a"),
        textRoleLink:     hex("#009c67"),
        darkMossGreen:    hex("#3c4c43"),
        badgeHighlight:   hex("#2e2f34"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#174033"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#1a0d2e"), hex("#3d2563"), hex("#610101")],
        loginInputBg:     hex("#2a2e31"),
        loginInputBorder: hex("#3e4045"),
        loginPlaceholder: hex("#7b7b83"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#4a4d51"),
        loginAlternativeText: hex("#aeaeae"),
        loginTitleColor:  hex("#ffffff"),
        loginSubtitleColor: hex("#b0b0b0"),
        loginInputTextColor: hex("#ffffff")
    )

    static let purpleHaze = ThemeAttributes(
        primary:          hex("#0e032c"),
        primaryGradient:  hex("#111a35"),
        secondary:        hex("#23052f"),
        secondaryWeight:  hex("#1E1133"),
        secondaryLight:   hex("#1e143a"),
        tertiary:         hex("#0e032c"),
        border:           hex("#23193d"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        text:             hex("#CCCCCC"),
        textStrong:       hex("#dfe0e4"),
        textDisabled:     hex("#7d7582"),
        textNormal:       hex("#858593"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        bgInputPrimary:   hex("#2a2e31"),
        charcoal:         hex("#3b3b48"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#a9acb7"),
        midnightBlue:     hex("#3b426e"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#334155"),
        colorActiveClan:  hex("#141c2a"),
        textRoleLink:     hex("#009c67"),
        darkMossGreen:    hex("#3c4c43"),
        badgeHighlight:   hex("#2e2f34"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#174033"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#f0edfd"), hex("#beb5f8"), hex("#9774fa")],
        loginInputBg:     hex("#ffffff"),
        loginInputBorder: hex("#cccccc"),
        loginPlaceholder: hex("#a8a8a8"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#88888c"),
        loginAlternativeText: hex("#5e5e5e"),
        loginTitleColor:  hex("#191919"),
        loginSubtitleColor: hex("#505050"),
        loginInputTextColor: hex("#191919")
    )

    static let abyssDark = ThemeAttributes(
        primary:          hex("#110B33"),
        primaryGradient:  hex("#21165c"),
        secondary:        hex("#19153C"),
        secondaryWeight:  hex("#0E0B20"),
        secondaryLight:   hex("#24204E"),
        tertiary:         hex("#141319"),
        border:           hex("#2e2f34"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        text:             hex("#CCCCCC"),
        textStrong:       hex("#dfe0e4"),
        textDisabled:     hex("#7b7b83"),
        textNormal:       hex("#898993"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        bgInputPrimary:   hex("#2a2e31"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#334155"),
        colorActiveClan:  hex("#141c2a"),
        textRoleLink:     hex("#009c67"),
        darkMossGreen:    hex("#3c4c43"),
        badgeHighlight:   hex("#2e2f34"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#174033"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#110B33"), hex("#21165c"), hex("#19153C")],
        loginInputBg:     hex("#2a2e31"),
        loginInputBorder: hex("#3e4045"),
        loginPlaceholder: hex("#7b7b83"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#4a4d51"),
        loginAlternativeText: hex("#7b7b83"),
        loginTitleColor:  hex("#ffffff"),
        loginSubtitleColor: hex("#b0b0b0"),
        loginInputTextColor: hex("#ffffff")
    )

    static let sunset = ThemeAttributes(
        primary:          hex("#372013"),
        primaryGradient:  hex("#57321e"),
        secondary:        hex("#563928"),
        secondaryWeight:  hex("#2C1910"),
        secondaryLight:   hex("#4C2C1B"),
        tertiary:         hex("#141319"),
        border:           hex("#2e2f34"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        text:             hex("#CCCCCC"),
        textStrong:       hex("#dfe0e4"),
        textDisabled:     hex("#7b7b83"),
        textNormal:       hex("#898993"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        bgInputPrimary:   hex("#2a2e31"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        textLink:         hex("#3297ff"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),
        colorAvatarDefault: hex("#334155"),
        colorActiveClan:  hex("#141c2a"),
        textRoleLink:     hex("#009c67"),
        darkMossGreen:    hex("#3c4c43"),
        badgeHighlight:   hex("#2e2f34"),
        textWarning:      hex("#FEF08A"),
        borderWarning:    hex("#EAB308"),
        darkJade:         hex("#174033"),
        bgInfor:          hex("#3b82f6", alpha: 0.10),
        borderInfor:      hex("#3b82f6", alpha: 0.50),
        headerInfor:      hex("#60a5fa"),
        descInfor:        hex("#93c5fd", alpha: 0.80),
        textSuccess:      hex("#00d4aa"),
        loginGradientColors: [hex("#372013"), hex("#57321e"), hex("#563928")],
        loginInputBg:     hex("#2a2e31"),
        loginInputBorder: hex("#3e4045"),
        loginPlaceholder: hex("#7b7b83"),
        loginButtonBg:    hex("#2563eb"),
        loginButtonBgDisabled: hex("#4a4d51"),
        loginAlternativeText: hex("#7b7b83"),
        loginTitleColor:  hex("#ffffff"),
        loginSubtitleColor: hex("#b0b0b0"),
        loginInputTextColor: hex("#ffffff")
    )
}

private func hex(_ value: String, alpha: CGFloat = 1) -> UIColor {
    var str = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if str.hasPrefix("#") { str = String(str.dropFirst()) }
    if str.count == 8 {
        let r = CGFloat(UInt8(str[str.index(str.startIndex, offsetBy: 0)..<str.index(str.startIndex, offsetBy: 2)], radix: 16) ?? 0) / 255
        let g = CGFloat(UInt8(str[str.index(str.startIndex, offsetBy: 2)..<str.index(str.startIndex, offsetBy: 4)], radix: 16) ?? 0) / 255
        let b = CGFloat(UInt8(str[str.index(str.startIndex, offsetBy: 4)..<str.index(str.startIndex, offsetBy: 6)], radix: 16) ?? 0) / 255
        let a = CGFloat(UInt8(str[str.index(str.startIndex, offsetBy: 6)..<str.index(str.startIndex, offsetBy: 8)], radix: 16) ?? 255) / 255
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
    let scanner = Scanner(string: str)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return UIColor(
        red:   CGFloat((rgb >> 16) & 0xFF) / 255,
        green: CGFloat((rgb >>  8) & 0xFF) / 255,
        blue:  CGFloat( rgb        & 0xFF) / 255,
        alpha: alpha
    )
}

private func rgba(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat) -> UIColor {
    UIColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}
