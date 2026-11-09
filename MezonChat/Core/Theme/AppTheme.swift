import UIKit

struct ThemeGradient {
    let angle: CGFloat
    let stops: [(location: CGFloat, color: UIColor)]
    var viewportAnchored = false

    func apply(to layer: CAGradientLayer, in window: UIWindow? = nil) {
        layer.colors = stops.map { $0.color.cgColor }
        layer.locations = stops.map { NSNumber(value: Double($0.location)) }
        updateDirection(on: layer, in: window)
    }

    func updateDirection(on layer: CAGradientLayer, in window: UIWindow? = nil) {
        let bounds = layer.bounds
        let reference: CGRect
        if viewportAnchored, let window {
            reference = layer.convert(window.layer.bounds, from: window.layer)
        } else {
            reference = bounds
        }
        let size = reference.size
        guard bounds.width > 0, bounds.height > 0, size.width > 0, size.height > 0 else { return }

        let radians = (angle - 90) * .pi / 180
        let longestSide = max(size.width, size.height)
        let x = cos(radians) * size.width / longestSide
        let y = sin(radians) * size.height / longestSide
        let length = abs(x) > abs(y) ? size.width : size.height
        let halfAxis = length / (2 * hypot(x, y))
        let centerX = (reference.midX - bounds.minX) / bounds.width
        let centerY = (reference.midY - bounds.minY) / bounds.height
        let dx = x * halfAxis / bounds.width
        let dy = y * halfAxis / bounds.height
        layer.startPoint = CGPoint(x: centerX - dx, y: centerY - dy)
        layer.endPoint = CGPoint(x: centerX + dx, y: centerY + dy)
    }
}

final class ThemeFillView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }
    private var gradient: ThemeGradient?

    func apply(solid: UIColor, gradient: ThemeGradient?) {
        self.gradient = gradient
        backgroundColor = gradient == nil ? solid : .clear
        if let gradient {
            gradient.apply(to: gradientLayer)
        } else {
            gradientLayer.colors = nil
            gradientLayer.locations = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient?.updateDirection(on: gradientLayer)
    }
}

struct ThemeAttributes {
    private(set) var desktop: DesktopThemePalette
    // Keep the pre-sync iOS Dark colors without changing the desktop palettes.
    private(set) var usesLegacyDarkColors = false

    var themeSettingPrimary: UIColor { desktop[.themeSettingPrimary] }
    var themeSettingNav: UIColor { desktop[.themeSettingNav] }
    var borderPrimary: UIColor { desktop[.borderPrimary] }
    var textThemePrimary: UIColor { desktop[.textThemePrimary] }
    var textThemeMessage: UIColor { usesLegacyDarkColors ? textStrong : desktop[.textThemeMessage] }

    var primary: UIColor { usesLegacyDarkColors ? hex("#131318") : desktop[.bgSecondary] }
    var primaryGradient: UIColor { usesLegacyDarkColors ? hex("#131318") : desktop.conversationGradient?.stops.first?.color ?? primary }
    var secondary: UIColor { usesLegacyDarkColors ? hex("#1c1d23") : desktop[.bgThemeDirectMessage] }
    private(set) var secondaryWeight: UIColor
    private(set) var secondaryLight: UIColor
    var tertiary: UIColor { usesLegacyDarkColors ? hex("#383a43") : desktop[.bgPrimary] }
    var raisedSurface: UIColor { usesLegacyDarkColors ? tertiary : desktop[.bgSurface] }
    var border: UIColor { usesLegacyDarkColors ? hex("#2a2d31") : borderPrimary }
    let borderDim: UIColor
    let borderHighlight: UIColor
    let borderRadio: UIColor
    var text: UIColor { usesLegacyDarkColors ? hex("#CCCCCC") : desktop.semantic.textPrimary }
    var textStrong: UIColor { usesLegacyDarkColors ? hex("#dfe0e4") : desktop.semantic.textPrimary }
    var textDisabled: UIColor { usesLegacyDarkColors ? hex("#7b7b83") : desktop.semantic.textMuted }
    var textNormal: UIColor { usesLegacyDarkColors ? hex("#898993") : desktop.semantic.textSecondary }
    var iconPrimary: UIColor { usesLegacyDarkColors ? hex("#5a62f4") : desktop[.buttonThemePrimary] }
    let iconSecondary: UIColor
    let iconTertiary: UIColor
    let white: UIColor
    let black: UIColor
    var bgInputPrimary: UIColor { usesLegacyDarkColors ? hex("#2a2e31") : desktop[.bgThemeInputPrimary] }
    let charcoal: UIColor
    let jet: UIColor
    let channelUnread: UIColor
    let channelNormal: UIColor
    let midnightBlue: UIColor
    var textLink: UIColor { usesLegacyDarkColors ? hex("#3297ff") : desktop[.colorMentionHover] }
    let reactionBg: UIColor
    let reactionBorder: UIColor
    let selectedOverlay: UIColor
    let bgViolet: UIColor

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
    private(set) var loginGradientColors: [UIColor]
    let loginInputBg: UIColor
    let loginInputBorder: UIColor
    let loginPlaceholder: UIColor
    let loginButtonBg: UIColor
    let loginButtonBgDisabled: UIColor
    let loginAlternativeText: UIColor
    let loginTitleColor: UIColor
    let loginSubtitleColor: UIColor
    let loginInputTextColor: UIColor

    var statusOnline: UIColor { desktop.semantic.statusOnline }

    func shimmerHighlight(over base: UIColor) -> UIColor {
        usesLegacyDarkColors ? tertiary : base.mixedWith(textStrong, alpha: 0.08)
    }
}

enum AppTheme: String, CaseIterable {
    case dark
    case light
    case sunrise
    case redDark
    case purpleHaze
    case abyssDark
    case sunset
    case cisher
    case berrynade
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
        case .cisher:     return L(L10n.Theme.cisher)
        case .berrynade:  return L(L10n.Theme.berrynade)
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
        case .cisher:     return .cisher
        case .berrynade:  return .berrynade
        case .system:
            return effectiveInterfaceStyle == .dark ? .dark : .light
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light, .sunrise, .cisher:
            return .light
        case .dark, .redDark, .purpleHaze, .abyssDark, .sunset, .berrynade:
            return .dark
        case .system:
            return .unspecified
        }
    }

    var effectiveInterfaceStyle: UIUserInterfaceStyle {
        let style = interfaceStyle
        guard style == .unspecified else { return style }
        return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }

    var usesLightStatusBarContent: Bool {
        effectiveInterfaceStyle == .dark
    }
}

private extension ThemeAttributes {

    static let dark = ThemeAttributes(
        desktop: .dark,
        usesLegacyDarkColors: true,
        secondaryWeight:  hex("#212122"),
        secondaryLight:   hex("#26272f"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#dadada"),
        iconSecondary:    hex("#7b7b83"),
        iconTertiary:     hex("#949aa4"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .light,
        secondaryWeight:  hex("#F0F0F0"),
        secondaryLight:   hex("#ffffff"),
        borderDim:        hex("#dfdfdf"),
        borderHighlight:  hex("#e0e1e3"),
        borderRadio:      hex("#4d4d54"),
        iconSecondary:    hex("#606065"),
        iconTertiary:     hex("#6c7077"),
        white:            hex("#000000"),
        black:            hex("#FFFFFF"),
        charcoal:         hex("#f2f3f5"),
        jet:              hex("#ecedef"),
        channelUnread:    hex("#000000"),
        channelNormal:    hex("#6c7077"),
        midnightBlue:     hex("#d1e0ff"),
        reactionBg:       rgba(229, 231, 235, 0.6),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#FFFFFF96"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .sunrise,
        secondaryWeight:  hex("#ffe5ed"),
        secondaryLight:   hex("#f8ebee"),
        borderDim:        hex("#f4f4f4"),
        borderHighlight:  hex("#e0e1e3"),
        borderRadio:      hex("#4d4d54"),
        iconSecondary:    hex("#b13b3d"),
        iconTertiary:     hex("#e04c51"),
        white:            hex("#000000"),
        black:            hex("#FFFFFF"),
        charcoal:         hex("#f2f3f5"),
        jet:              hex("#ecedef"),
        channelUnread:    hex("#000000"),
        channelNormal:    hex("#6c7077"),
        midnightBlue:     hex("#d1e0ff"),
        reactionBg:       rgba(229, 231, 235, 0.6),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#FFFFFF96"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .redDark,
        secondaryWeight:  hex("#67171a"),
        secondaryLight:   hex("#70393c"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        iconSecondary:    hex("#d23331"),
        iconTertiary:     hex("#dd2f2f"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .purpleHaze,
        secondaryWeight:  hex("#1E1133"),
        secondaryLight:   hex("#1e143a"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        iconSecondary:    hex("#7d7582"),
        iconTertiary:     hex("#9ca3af"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        charcoal:         hex("#3b3b48"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#a9acb7"),
        midnightBlue:     hex("#3b426e"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .abyssDark,
        secondaryWeight:  hex("#0E0B20"),
        secondaryLight:   hex("#24204E"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        iconSecondary:    hex("#5331d2"),
        iconTertiary:     hex("#5331d2"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),

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
        desktop: .sunset,
        secondaryWeight:  hex("#2C1910"),
        secondaryLight:   hex("#4C2C1B"),
        borderDim:        hex("#2f2f37"),
        borderHighlight:  hex("#27272f"),
        borderRadio:      hex("#cacad2"),
        iconSecondary:    hex("#ff7e30"),
        iconTertiary:     hex("#dd3f2f"),
        white:            hex("#FFFFFF"),
        black:            hex("#000000"),
        charcoal:         hex("#2b2b2e"),
        jet:              hex("#29292b"),
        channelUnread:    hex("#ffffff"),
        channelNormal:    hex("#aeaeae"),
        midnightBlue:     hex("#3b426e"),
        reactionBg:       rgba(55, 58, 84, 0.5),
        reactionBorder:   hex("#2563eb"),
        selectedOverlay:  hex("#00000096"),
        bgViolet:         hex("#5a62f4"),

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

    static let cisher = light.adapting(to: .cisher)
    static let berrynade = dark.adapting(to: .berrynade)

    private func adapting(to palette: DesktopThemePalette) -> ThemeAttributes {
        var theme = self
        theme.desktop = palette
        theme.usesLegacyDarkColors = false
        theme.secondaryWeight = palette[.bgActiveFriendList]
        theme.secondaryLight = palette[.bgSurface]
        if let preview = palette.previewGradient {
            theme.loginGradientColors = preview.stops.map { $0.color }
        }
        return theme
    }
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
