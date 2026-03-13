import Foundation
import UIKit

public final class ScrollChildEnvironment: Equatable {
    public let insets: UIEdgeInsets
    public let contentSize: CGSize

    public init(insets: UIEdgeInsets = .zero, contentSize: CGSize = .zero) {
        self.insets = insets
        self.contentSize = contentSize
    }

    public static func == (lhs: ScrollChildEnvironment, rhs: ScrollChildEnvironment) -> Bool {
        return lhs.insets == rhs.insets && lhs.contentSize == rhs.contentSize
    }
}

public final class ScrollComponent<ChildEnvironmentType: Equatable>: Component {
    public typealias EnvironmentType = ChildEnvironmentType

    public let content: AnyComponent<(ChildEnvironmentType, ScrollChildEnvironment)>
    public let contentInsets: UIEdgeInsets
    public let contentOffsetUpdated: (CGFloat) -> Void
    public let bounces: Bool
    public let clipsToBounds: Bool

    public init(
        content: AnyComponent<(ChildEnvironmentType, ScrollChildEnvironment)>,
        contentInsets: UIEdgeInsets = .zero,
        contentOffsetUpdated: @escaping (CGFloat) -> Void = { _ in },
        bounces: Bool = true,
        clipsToBounds: Bool = true
    ) {
        self.content = content
        self.contentInsets = contentInsets
        self.contentOffsetUpdated = contentOffsetUpdated
        self.bounces = bounces
        self.clipsToBounds = clipsToBounds
    }

    public static func == (lhs: ScrollComponent, rhs: ScrollComponent) -> Bool {
        if lhs.content != rhs.content { return false }
        if lhs.contentInsets != rhs.contentInsets { return false }
        if lhs.bounces != rhs.bounces { return false }
        if lhs.clipsToBounds != rhs.clipsToBounds { return false }
        return true
    }

    public final class View: UIScrollView, UIScrollViewDelegate {
        private let contentHostView = ComponentHostView<(ChildEnvironmentType, ScrollChildEnvironment)>()
        private var component: ScrollComponent?

        override init(frame: CGRect) {
            super.init(frame: frame)
            delegate = self
            showsVerticalScrollIndicator = true
            showsHorizontalScrollIndicator = false
            alwaysBounceVertical = true
            addSubview(contentHostView)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: ScrollComponent, availableSize: CGSize, environment: Environment<ChildEnvironmentType>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.bounces = component.bounces
            self.clipsToBounds = component.clipsToBounds

            let scrollEnv = ScrollChildEnvironment(insets: component.contentInsets, contentSize: availableSize)

            let contentSize = contentHostView.update(
                transition: transition,
                component: component.content,
                environment: {
                    environment[ChildEnvironmentType.self]
                    scrollEnv
                },
                containerSize: CGSize(width: availableSize.width - component.contentInsets.left - component.contentInsets.right, height: .greatestFiniteMagnitude)
            )

            contentHostView.frame = CGRect(origin: CGPoint(x: component.contentInsets.left, y: component.contentInsets.top), size: contentSize)

            let totalContentSize = CGSize(
                width: contentSize.width + component.contentInsets.left + component.contentInsets.right,
                height: contentSize.height + component.contentInsets.top + component.contentInsets.bottom
            )
            if self.contentSize != totalContentSize {
                self.contentSize = totalContentSize
            }

            self.contentInset = .zero
            self.scrollIndicatorInsets = .zero

            return availableSize
        }

        public func scrollViewDidScroll(_ scrollView: UIScrollView) {
            component?.contentOffsetUpdated(scrollView.contentOffset.y)
        }
    }

    public func makeView() -> View {
        return View(frame: .zero)
    }

    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ChildEnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, environment: environment, transition: transition)
    }
}
