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

    var swatchColor: UIColor { primary }
}


enum AppTheme: String, CaseIterable {
    case dark
    case light
    case sunrise
    case redDark
    case purpleHaze
    case abyssDark

    var displayName: String {
        switch self {
        case .dark:       return "Dark"
        case .light:      return "Light"
        case .sunrise:    return "Sunrise"
        case .redDark:    return "Red Dark"
        case .purpleHaze: return "Purple Haze"
        case .abyssDark:  return "Abyss Dark"
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
        }
    }
}


private extension ThemeAttributes {

    static let dark = ThemeAttributes(
        primary:          hex("#1c1d22"),
        primaryGradient:  hex("#1c1d22"),
        secondary:        hex("#242427"),
        secondaryWeight:  hex("#212122"),
        secondaryLight:   hex("#2A2D31"),
        tertiary:         hex("#141319"),
        border:           hex("#2e2f34"),
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
        textSuccess:      hex("#00d4aa")
    )

    static let light = ThemeAttributes(
        primary:          hex("#f2f3f5"),
        primaryGradient:  hex("#f2f3f5"),
        secondary:        hex("#ffffff"),
        secondaryWeight:  hex("#F0F0F0"),
        secondaryLight:   hex("#ffffff"),
        tertiary:         hex("#e1e1e1"),
        border:           hex("#9e9eaa"),
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
        textSuccess:      hex("#00d4aa")
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
        textSuccess:      hex("#00d4aa")
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
        textSuccess:      hex("#00d4aa")
    )

    static let purpleHaze = ThemeAttributes(
        primary:          hex("#2f2147"),
        primaryGradient:  hex("#42294e"),
        secondary:        hex("#543e9f"),
        secondaryWeight:  hex("#1E1133"),
        secondaryLight:   hex("#48256e"),
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
        textSuccess:      hex("#00d4aa")
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
        textSuccess:      hex("#00d4aa")
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
