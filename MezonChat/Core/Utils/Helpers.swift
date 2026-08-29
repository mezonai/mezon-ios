


import Foundation
import UIKit

func safeJsonDecode<T: Decodable>(
    _ jsonString: String,
    to type: T.Type,
    fallback: T? = nil
) -> T? {
    guard !jsonString.isEmpty,
          jsonString != "null",
          let data = jsonString.data(using: .utf8) else {
        return fallback
    }

    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        return fallback
    }
}


/// Erased cancellation token for work that must be stored by a type available on
/// iOS 12: Swift forbids `@available` on stored properties, so a `Task` handle
/// cannot be held directly by such a type.
final class CancelHandle {
    private var cancelAction: (() -> Void)?
    private(set) var isCancelled = false

    init(_ cancelAction: @escaping () -> Void) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        let action = cancelAction
        cancelAction = nil
        action?()
    }
}

extension UIImage {
    /// SF Symbols are iOS 13+; iOS 12 has no system-provided glyph for these names.
    static func mezonSystemImage(_ name: String) -> UIImage? {
        if #available(iOS 13.0, *) {
            return UIImage(systemName: name)
        }
        return nil
    }

    /// `UIImage.SymbolConfiguration` is itself iOS 13+, so callers pass plain
    /// point size / `UIFont.Weight` and the configuration is built behind the check.
    static func mezonSystemImage(
        _ name: String,
        pointSize: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIImage? {
        if #available(iOS 13.0, *) {
            return UIImage(
                systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: pointSize, weight: mezonSymbolWeight(weight)
                )
            )
        }
        return nil
    }

    @available(iOS 13.0, *)
    fileprivate static func mezonSymbolWeight(_ weight: UIFont.Weight) -> UIImage.SymbolWeight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}

extension UIActivityIndicatorView {
    /// `.medium` / `.large` are iOS 13+; `.gray` / `.whiteLarge` are the iOS 12 equivalents.
    static func mezonMedium() -> UIActivityIndicatorView {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .medium)
        }
        return UIActivityIndicatorView(style: .gray)
    }

    static func mezonLarge() -> UIActivityIndicatorView {
        if #available(iOS 13.0, *) {
            return UIActivityIndicatorView(style: .large)
        }
        return UIActivityIndicatorView(style: .whiteLarge)
    }
}

extension CALayer {
    /// `cornerCurve` is iOS 13+; on iOS 12 the corner is always circular.
    func setMezonCornerCurveContinuous() {
        if #available(iOS 13.0, *) {
            cornerCurve = .continuous
        }
    }

    func setMezonCornerCurveCircular() {
        if #available(iOS 13.0, *) {
            cornerCurve = .circular
        }
    }
}

/// iOS-12-safe stand-in for `UIImage.SymbolConfiguration`, which is itself iOS 13+.
struct MezonSymbolConfiguration {
    let pointSize: CGFloat
    let weight: UIFont.Weight

    init(pointSize: CGFloat, weight: UIFont.Weight = .regular) {
        self.pointSize = pointSize
        self.weight = weight
    }

    @available(iOS 13.0, *)
    var uiKitConfiguration: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: pointSize, weight: UIImage.mezonSymbolWeight(weight))
    }
}

extension UIImage {
    static func mezonSystemImage(
        _ name: String,
        withConfiguration configuration: MezonSymbolConfiguration
    ) -> UIImage? {
        mezonSystemImage(name, pointSize: configuration.pointSize, weight: configuration.weight)
    }

    func mezonWithConfiguration(_ configuration: MezonSymbolConfiguration) -> UIImage? {
        if #available(iOS 13.0, *) {
            return withConfiguration(
                UIImage.SymbolConfiguration(
                    pointSize: configuration.pointSize,
                    weight: UIImage.mezonSymbolWeight(configuration.weight)
                )
            )
        }
        return self
    }
}

/// `UITraitCollection.current` is iOS 13+; iOS 12 has no system-wide dark mode.
func mezonSystemPrefersDarkMode() -> Bool {
    if #available(iOS 13.0, *) {
        return UITraitCollection.current.userInterfaceStyle == .dark
    }
    return false
}

extension UIView {
    /// `overrideUserInterfaceStyle` is iOS 13+; a no-op on iOS 12.
    func setMezonOverrideUserInterfaceStyle(_ style: UIUserInterfaceStyle) {
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = style
        }
    }
}

extension UISearchBar {
    /// `searchTextField` is iOS 13+; on iOS 12 the same view is reachable by its KVC name.
    var mezonSearchTextField: UITextField? {
        if #available(iOS 13.0, *) {
            return searchTextField
        }
        return value(forKey: "searchField") as? UITextField
    }
}

extension UIColor {
    /// Semantic system colours are iOS 13+; the fallbacks match their light-mode values.
    static var mezonCompatLabel: UIColor {
        if #available(iOS 13.0, *) { return .label }
        return .black
    }

    static var mezonCompatSecondaryLabel: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return UIColor(white: 0.24, alpha: 0.6)
    }

    static var mezonCompatPlaceholderText: UIColor {
        if #available(iOS 13.0, *) { return .placeholderText }
        return UIColor(white: 0.24, alpha: 0.3)
    }

    static var mezonCompatSystemIndigo: UIColor {
        if #available(iOS 13.0, *) { return .systemIndigo }
        return UIColor(red: 88.0 / 255.0, green: 86.0 / 255.0, blue: 214.0 / 255.0, alpha: 1)
    }

    static var mezonCompatSystemGray5: UIColor {
        if #available(iOS 13.0, *) { return .systemGray5 }
        return UIColor(red: 229.0 / 255.0, green: 229.0 / 255.0, blue: 234.0 / 255.0, alpha: 1)
    }
}

/// `UIWindowScene` is iOS 13+; on iOS 12 the application's windows are read directly.
func mezonApplicationWindows() -> [UIWindow] {
    if #available(iOS 13.0, *) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return [] }
        return scene.windows
    }
    return UIApplication.shared.windows
}

func mezonKeyWindow() -> UIWindow? {
    mezonApplicationWindows().first(where: { $0.isKeyWindow }) ?? mezonApplicationWindows().first
}

extension UIImage {
    /// `withTintColor(_:renderingMode:)` is iOS 13+; iOS 12 falls back to a template image.
    func mezonTinted(_ color: UIColor, renderingMode: UIImage.RenderingMode = .automatic) -> UIImage {
        if #available(iOS 13.0, *) {
            return withTintColor(color, renderingMode: renderingMode)
        }
        return withRenderingMode(.alwaysTemplate)
    }
}

extension UIFont {
    /// `monospacedSystemFont(ofSize:weight:)` is iOS 13+.
    static func mezonMonospacedSystemFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        if #available(iOS 13.0, *) {
            return .monospacedSystemFont(ofSize: size, weight: weight)
        }
        return UIFont(name: "Menlo", size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
}

extension UITableView {
    /// `.insetGrouped` is iOS 13+; `.grouped` is the closest iOS 12 equivalent.
    static func mezonInsetGrouped() -> UITableView {
        if #available(iOS 13.0, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        }
        return UITableView(frame: .zero, style: .grouped)
    }
}
