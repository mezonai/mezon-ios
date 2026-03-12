import Foundation
import UIKit

final class CardComponent: CombinedComponent {
    let content: AnyComponent<Empty>
    let backgroundColor: UIColor
    let cornerRadius: CGFloat
    let insets: UIEdgeInsets

    init(
        content: AnyComponent<Empty>,
        backgroundColor: UIColor = .mezonSecondaryBackground,
        cornerRadius: CGFloat = 12,
        insets: UIEdgeInsets = UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
    ) {
        self.content = content
        self.backgroundColor = backgroundColor
        self.cornerRadius = cornerRadius
        self.insets = insets
    }

    static func == (lhs: CardComponent, rhs: CardComponent) -> Bool {
        if lhs.content != rhs.content { return false }
        if lhs.backgroundColor != rhs.backgroundColor { return false }
        if lhs.cornerRadius != rhs.cornerRadius { return false }
        if lhs.insets != rhs.insets { return false }
        return true
    }

    static var body: Body {
        let background = Child(RoundedRectangle.self)
        let content = Child(environment: Empty.self)

        return { context in
            let component = context.component

            let contentChild = content.update(
                component: component.content,
                availableSize: CGSize(
                    width: context.availableSize.width - component.insets.left - component.insets.right,
                    height: context.availableSize.height - component.insets.top - component.insets.bottom
                ),
                transition: context.transition
            )

            let totalSize = CGSize(
                width: context.availableSize.width,
                height: contentChild.size.height + component.insets.top + component.insets.bottom
            )

            let bg = background.update(
                component: RoundedRectangle(color: component.backgroundColor, cornerRadius: component.cornerRadius),
                availableSize: totalSize,
                transition: context.transition
            )
            context.add(bg.position(CGPoint(x: totalSize.width / 2.0, y: totalSize.height / 2.0)))

            context.add(contentChild.position(CGPoint(
                x: component.insets.left + contentChild.size.width / 2.0,
                y: component.insets.top + contentChild.size.height / 2.0
            )))

            return totalSize
        }
    }
}

final class IconRowComponent: Component {
    let icon: String
    let title: String
    let iconColor: UIColor
    let textColor: UIColor
    let font: UIFont
    let trailingIcon: String?
    let trailingIconColor: UIColor?

    init(
        icon: String,
        title: String,
        iconColor: UIColor = .mezonTextSecondary,
        textColor: UIColor = .mezonTextPrimary,
        font: UIFont = .systemFont(ofSize: 15),
        trailingIcon: String? = nil,
        trailingIconColor: UIColor? = nil
    ) {
        self.icon = icon
        self.title = title
        self.iconColor = iconColor
        self.textColor = textColor
        self.font = font
        self.trailingIcon = trailingIcon
        self.trailingIconColor = trailingIconColor
    }

    static func == (lhs: IconRowComponent, rhs: IconRowComponent) -> Bool {
        return lhs.icon == rhs.icon && lhs.title == rhs.title && lhs.iconColor == rhs.iconColor && lhs.textColor == rhs.textColor && lhs.font == rhs.font && lhs.trailingIcon == rhs.trailingIcon
    }

    final class View: UIView {
        private let iconView = UIImageView()
        private let label = UILabel()
        private let trailingView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            iconView.contentMode = .scaleAspectFit
            addSubview(iconView)
            addSubview(label)
            addSubview(trailingView)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: IconRowComponent, availableSize: CGSize) -> CGSize {
            iconView.image = UIImage(systemName: component.icon)
            iconView.tintColor = component.iconColor
            label.text = component.title
            label.textColor = component.textColor
            label.font = component.font

            let iconSize: CGFloat = 20
            let spacing: CGFloat = 12
            let height: CGFloat = max(iconSize, label.intrinsicContentSize.height)

            iconView.frame = CGRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize)

            if let trailing = component.trailingIcon {
                trailingView.image = UIImage(systemName: trailing)
                trailingView.tintColor = component.trailingIconColor ?? component.iconColor
                trailingView.isHidden = false
                let trailSize: CGFloat = 16
                trailingView.frame = CGRect(x: availableSize.width - trailSize, y: (height - trailSize) / 2, width: trailSize, height: trailSize)
                label.frame = CGRect(x: iconSize + spacing, y: 0, width: availableSize.width - iconSize - spacing - trailSize - 8, height: height)
            } else {
                trailingView.isHidden = true
                label.frame = CGRect(x: iconSize + spacing, y: 0, width: availableSize.width - iconSize - spacing, height: height)
            }

            return CGSize(width: availableSize.width, height: height)
        }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}
