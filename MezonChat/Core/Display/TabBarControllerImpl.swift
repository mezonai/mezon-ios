import Foundation
import UIKit
import AsyncDisplayKit

open class TabBarControllerImpl: ViewController, TabBarController {
    private var validLayout: ContainerViewLayout?

    private var tabBarControllerNode: TabBarControllerNode {
        return super.displayNode as! TabBarControllerNode
    }

    public private(set) var controllers: [ViewController] = []

    private let _ready = Promise<Bool>()
    override open var ready: Promise<Bool> {
        return self._ready
    }

    private var _selectedIndex: Int?
    public var selectedIndex: Int {
        get {
            return _selectedIndex ?? 0
        }
        set {
            let index = max(0, min(controllers.count - 1, newValue))
            if _selectedIndex != index {
                _selectedIndex = index
                updateSelectedIndex(animated: true)
            }
        }
    }

    public var currentController: ViewController?

    override public var transitionNavigationBar: NavigationBar? {
        return self.currentController?.navigationBar
    }

    private let pendingControllerDisposable = MetaDisposable()

    public override init(navigationBarPresentationData: NavigationBarPresentationData?) {
        super.init(navigationBarPresentationData: nil)

        self.scrollToTop = { [weak self] in
            self?.currentController?.scrollToTop?()
        }
    }

    required public init(coder aDecoder: NSCoder) { fatalError() }

    override open var shouldAutomaticallyForwardAppearanceMethods: Bool {
        false
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: ThemeManager.didChangeNotification, object: nil)
        pendingControllerDisposable.dispose()
    }

    override open func loadDisplayNode() {
        self.displayNode = TabBarControllerNode(itemSelected: { [weak self] index, longTap in
            guard let self else { return }

            if let validLayout {
                var updatedLayout = validLayout
                let bottomInset = validLayout.safeInsets.bottom
                let tabBarHeight = TabBarNode.barHeight + bottomInset
                updatedLayout.intrinsicInsets.bottom = tabBarHeight
                self.controllers[index].containerLayoutUpdated(updatedLayout, transition: .immediate)
            }

            self.pendingControllerDisposable.set(
                (self.controllers[index].ready.get()
                    |> deliverOnMainQueue).start(next: { [weak self] _ in
                        guard let self else { return }
                        if self.selectedIndex == index {
                            if let controller = self.currentController {
                                if longTap {
                                    controller.longTapWithTabBar?()
                                } else {
                                    controller.scrollToTopWithTabBar?()
                                }
                            }
                        } else {
                            self.selectedIndex = index
                        }
                    })
            )
        })

        updateSelectedIndex()
        displayNodeDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppThemeDidChange),
            name: ThemeManager.didChangeNotification, object: nil)
    }

    @objc private func handleAppThemeDidChange() {
        guard let layout = validLayout else { return }
        tabBarControllerNode.tabBarNode.refreshItemAppearanceForThemeChange()
        containerLayoutUpdated(layout, transition: .immediate)
    }

    public func frameForControllerTab(controller: ViewController) -> CGRect? {
        if let index = controllers.firstIndex(of: controller) {
            return tabBarControllerNode.frameForControllerTab(at: index)
        }
        return nil
    }

    public func isPointInsideContentArea(point: CGPoint) -> Bool {
        return tabBarControllerNode.isPointInsideContentArea(point: point)
    }

    public func updateIsTabBarEnabled(_ value: Bool, transition: ContainedViewLayoutTransition) {
        tabBarControllerNode.updateIsTabBarEnabled(value, transition: transition)
    }

    public func updateIsTabBarHidden(_ value: Bool, transition: ContainedViewLayoutTransition) {
        tabBarControllerNode.tabBarHidden = value
        if let layout = validLayout {
            containerLayoutUpdated(layout, transition: .animated(duration: 0.4, curve: .slide))
        }
    }

    public func updateBackgroundAlpha(_ alpha: CGFloat, transition: ContainedViewLayoutTransition) {}

    private func updateSelectedIndex(animated: Bool = false) {
        guard isNodeLoaded else { return }

        let tabBarSelectedIndex = selectedIndex
        tabBarControllerNode.updateSelectedIndex(index: tabBarSelectedIndex)

        var transitionScale: CGFloat = 0.998
        if let currentView = currentController?.view {
            transitionScale = (currentView.frame.height - 3.0) / currentView.frame.height
        }

        if let currentController = self.currentController {
            currentController.willMove(toParent: nil)

            if animated {
                currentController.view.layer.animateScale(
                    from: 1.0, to: transitionScale, duration: 0.12,
                    timingFunction: kCAMediaTimingFunctionSpring,
                    removeOnCompletion: false
                ) { completed in
                    if completed {
                        currentController.view.layer.removeAllAnimations()
                    }
                }
            }
            currentController.removeFromParent()
            currentController.didMove(toParent: nil)
            self.currentController = nil
        }

        if let _selectedIndex, _selectedIndex < controllers.count {
            self.currentController = controllers[_selectedIndex]
        }

        if let currentController = self.currentController {
            currentController.willMove(toParent: self)
            addChild(currentController)

            let commit = tabBarControllerNode.setCurrentController(currentController)
            if animated {
                currentController.view.layer.animateScale(
                    from: transitionScale, to: 1.0, duration: 0.15, delay: 0.1,
                    timingFunction: kCAMediaTimingFunctionSpring
                )
                currentController.view.layer.allowsGroupOpacity = true
                currentController.view.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.1) { completed in
                    if completed {
                        currentController.view.layer.allowsGroupOpacity = false
                    }
                    commit()
                }
            } else {
                commit()
            }
            currentController.didMove(toParent: self)
            currentController.displayNode.recursivelyEnsureDisplaySynchronously(true)
            statusBar.statusBarStyle = currentController.statusBar.statusBarStyle
        }

        if let layout = validLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }

    public func updateLayout(transition: ContainedViewLayoutTransition = .immediate) {
        if let layout = validLayout {
            containerLayoutUpdated(layout, transition: transition)
        }
    }

    override open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        validLayout = layout

        let bottomInset = tabBarControllerNode.containerLayoutUpdated(layout, toolbar: currentController?.toolbar, transition: transition)

        if let currentController {
            currentController.view.frame = CGRect(origin: .zero, size: layout.size)
            var updatedLayout = layout
            if !tabBarControllerNode.tabBarHidden {
                updatedLayout.intrinsicInsets.bottom = bottomInset
            }
            currentController.containerLayoutUpdated(updatedLayout, transition: transition)
        }
    }

    public func updateControllerLayout(controller: ViewController) {
        guard let layout = validLayout,
              controllers.contains(where: { $0 === controller }) else { return }
        controller.view.frame = CGRect(origin: .zero, size: layout.size)
        var updatedLayout = layout
        let bottomInset = layout.safeInsets.bottom
        let tabBarHeight = TabBarNode.barHeight + bottomInset
        if !tabBarControllerNode.tabBarHidden {
            updatedLayout.intrinsicInsets.bottom = tabBarHeight
        }
        controller.containerLayoutUpdated(updatedLayout, transition: .immediate)
    }

    public func setControllers(_ controllers: [ViewController], selectedIndex: Int?) {
        var updatedSelectedIndex = selectedIndex
        if updatedSelectedIndex == nil, let si = _selectedIndex, si < self.controllers.count {
            if let index = controllers.firstIndex(where: { $0 === self.controllers[si] }) {
                updatedSelectedIndex = index
            } else {
                updatedSelectedIndex = 0
            }
        }
        self.controllers = controllers

        let tabBarItems = controllers.map { TabBarNodeItem(item: $0.tabBarItem) }
        tabBarControllerNode.updateTabBarItems(items: tabBarItems)

        self._ready.set(.single(true))

        if let updatedSelectedIndex {
            self.selectedIndex = updatedSelectedIndex
            updateSelectedIndex()
        }
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        currentController?.beginAppearanceTransition(true, animated: animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        currentController?.endAppearanceTransition()
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        currentController?.beginAppearanceTransition(false, animated: animated)
    }

    override open func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        currentController?.endAppearanceTransition()
    }
}
