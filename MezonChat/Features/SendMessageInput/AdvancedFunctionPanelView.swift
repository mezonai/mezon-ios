import UIKit

struct AdvancedFunctionItem {
    let id: String
    let label: String
    let systemIcon: String
    let backgroundColor: UIColor
}

final class AdvancedFunctionPanelView: UIView, UIGestureRecognizerDelegate {

    var onRequestDismiss: (() -> Void)?
    var onActionTapped: ((AdvancedFunctionItem) -> Void)?
    var onHeightChanged: ((CGFloat) -> Void)?

    var collapsedHeight: CGFloat = 260
    var expandedHeight: CGFloat = 500

    private(set) var isExpanded = false

    private let grabberBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.mezonLabel.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let handleArea: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let gridScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let gridContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private static let handleHeight: CGFloat = 24
    private static let columnsCount: Int = 4
    private static let iconContainerSize: CGFloat = 42
    private static let itemSpacingV: CGFloat = 20
    private static let itemPaddingH: CGFloat = 8

    private var sheetPanGesture: UIPanGestureRecognizer!
    private var dragStartHeight: CGFloat = 0

    private var actionItems: [AdvancedFunctionItem] = []
    private var gridHeightConstraint: NSLayoutConstraint?

    static func defaultActionItems(anonymousOn: Bool, includeAnonymous: Bool) -> [AdvancedFunctionItem] {
        var items: [AdvancedFunctionItem] = [
            AdvancedFunctionItem(id: "location", label: "Location", systemIcon: "location.fill",
                                 backgroundColor: UIColor(red: 0.91, green: 0.60, blue: 0.58, alpha: 1)),
            AdvancedFunctionItem(id: "pickFiles", label: "Files", systemIcon: "doc.fill",
                                 backgroundColor: UIColor(red: 0.15, green: 0.27, blue: 0.88, alpha: 1)),
            AdvancedFunctionItem(id: "buzz", label: "Buzz", systemIcon: "megaphone.fill",
                                 backgroundColor: UIColor(red: 0.83, green: 0.40, blue: 0.48, alpha: 1)),
        ]
        if includeAnonymous {
            let anonLabel = anonymousOn ? "Anonymous\nOn" : "Anonymous"
            items.append(AdvancedFunctionItem(id: "anonymous", label: anonLabel, systemIcon: "Chat/AnonymousIcon",
                                              backgroundColor: UIColor(red: 0.32, green: 0.34, blue: 0.42, alpha: 1)))
        }
        items.append(contentsOf: [
            AdvancedFunctionItem(id: "transfer_funds", label: "Transfer\nfunds", systemIcon: "arrow.up.circle.fill",
                                 backgroundColor: UIColor(red: 0.36, green: 0.73, blue: 0.55, alpha: 1)),
            AdvancedFunctionItem(id: "share_contact", label: "Share This\nContact", systemIcon: "person.crop.circle.badge.plus",
                                 backgroundColor: UIColor(red: 0.42, green: 0.71, blue: 1.0, alpha: 1)),
        ])
        return items
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        actionItems = Self.defaultActionItems(anonymousOn: false, includeAnonymous: true)
        setupLayout()
        setupGrid()
        setupGestures()
    }

    func setActions(_ items: [AdvancedFunctionItem]) {
        actionItems = items
        gridContainerView.subviews.forEach { $0.removeFromSuperview() }
        if let gh = gridHeightConstraint {
            NSLayoutConstraint.deactivate([gh])
            gridHeightConstraint = nil
        }
        setupGrid()
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        backgroundColor = UIColor.theme.secondary
    }

    func resetToCollapsed() {
        isExpanded = false
        gridScrollView.setContentOffset(.zero, animated: false)
    }

    func applySnapCollapsed() {
        isExpanded = false
        gridScrollView.setContentOffset(.zero, animated: false)
        onHeightChanged?(collapsedHeight)
    }

    private func setupLayout() {
        addSubview(handleArea)
        handleArea.addSubview(grabberBar)
        addSubview(gridScrollView)
        gridScrollView.addSubview(gridContainerView)

        NSLayoutConstraint.activate([
            handleArea.topAnchor.constraint(equalTo: topAnchor),
            handleArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            handleArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            handleArea.heightAnchor.constraint(equalToConstant: Self.handleHeight),

            grabberBar.centerXAnchor.constraint(equalTo: handleArea.centerXAnchor),
            grabberBar.centerYAnchor.constraint(equalTo: handleArea.centerYAnchor),
            grabberBar.widthAnchor.constraint(equalToConstant: 36),
            grabberBar.heightAnchor.constraint(equalToConstant: 5),

            gridScrollView.topAnchor.constraint(equalTo: handleArea.bottomAnchor, constant: 8),
            gridScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gridScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gridScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            gridContainerView.topAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.topAnchor),
            gridContainerView.leadingAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.leadingAnchor),
            gridContainerView.trailingAnchor.constraint(equalTo: gridScrollView.contentLayoutGuide.trailingAnchor),
            gridContainerView.widthAnchor.constraint(equalTo: gridScrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    private func setupGrid() {
        let columns = Self.columnsCount
        let containerSize = Self.iconContainerSize
        let spacingV = Self.itemSpacingV
        let itemHeight: CGFloat = containerSize + 30

        var itemConstraints: [NSLayoutConstraint] = []

        for (index, action) in actionItems.enumerated() {
            let col = index % columns
            let row = index / columns

            let itemView = makeItemView(action: action)
            gridContainerView.addSubview(itemView)

            let topOffset = CGFloat(row) * (itemHeight + spacingV) + 8

            itemConstraints.append(contentsOf: [
                itemView.topAnchor.constraint(equalTo: gridContainerView.topAnchor, constant: topOffset),
                itemView.leadingAnchor.constraint(equalTo: gridContainerView.leadingAnchor,
                    constant: CGFloat(col) * (1.0 / CGFloat(columns)) * UIScreen.main.bounds.width),
                itemView.widthAnchor.constraint(equalTo: gridContainerView.widthAnchor, multiplier: 1.0 / CGFloat(columns)),
                itemView.heightAnchor.constraint(equalToConstant: itemHeight),
            ])
        }

        let rows = ceil(Double(actionItems.count) / Double(columns))
        let totalH = CGFloat(rows) * (itemHeight + spacingV) + 16
        let gh = gridContainerView.heightAnchor.constraint(equalToConstant: totalH)
        gridHeightConstraint = gh
        itemConstraints.append(gh)

        NSLayoutConstraint.activate(itemConstraints)
    }

    private func makeItemView(action: AdvancedFunctionItem) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconContainer = UIView()
        iconContainer.backgroundColor = action.backgroundColor
        iconContainer.layer.cornerRadius = Self.iconContainerSize / 2
        iconContainer.clipsToBounds = true
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let iconConfig = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let iconImage = UIImage(named: action.systemIcon)?.withRenderingMode(.alwaysTemplate)
            ?? UIImage(systemName: action.systemIcon, withConfiguration: iconConfig)
        let iconImageView = UIImageView(image: iconImage)
        iconImageView.tintColor = .white
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.addSubview(iconImageView)

        let label = UILabel()
        label.text = action.label
        label.font = .systemFont(ofSize: 11)
        label.textColor = UIColor.theme.textDisabled
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconContainer)
        container.addSubview(label)

        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(btn)
        btn.tag = actionItems.firstIndex(where: { $0.id == action.id }) ?? 0
        btn.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: container.topAnchor),
            iconContainer.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: Self.iconContainerSize),
            iconContainer.heightAnchor.constraint(equalToConstant: Self.iconContainerSize),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 22),
            iconImageView.heightAnchor.constraint(equalToConstant: 22),

            label.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 6),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.itemPaddingH),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.itemPaddingH),

            btn.topAnchor.constraint(equalTo: container.topAnchor),
            btn.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    @objc private func actionButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index >= 0, index < actionItems.count else { return }
        let item = actionItems[index]
        onActionTapped?(item)
    }

    private func setupGestures() {
        sheetPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        sheetPanGesture.delegate = self
        sheetPanGesture.cancelsTouchesInView = false
        addGestureRecognizer(sheetPanGesture)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer == sheetPanGesture else { return true }
        var v: UIView? = touch.view
        while let cur = v {
            if cur is UIControl { return false }
            if cur === self { break }
            v = cur.superview
        }
        return true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == sheetPanGesture else { return true }
        let velocity = sheetPanGesture.velocity(in: self)
        let isVertical = abs(velocity.y) > abs(velocity.x)
        guard isVertical else { return false }

        if !isExpanded {
            return true
        } else {
            let atTop = gridScrollView.contentOffset.y <= 0
            let draggingDown = velocity.y > 0
            return atTop && draggingDown
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStartHeight = bounds.height
        case .changed:
            let translation = gesture.translation(in: self)
            let raw = dragStartHeight - translation.y
            let newHeight = min(max(raw, collapsedHeight), expandedHeight)
            onHeightChanged?(newHeight)
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: self).y
            snapWithVelocity(velocity)
        default:
            break
        }
    }

    private func snapWithVelocity(_ velocityY: CGFloat) {
        let currentH = bounds.height
        let midPoint = (collapsedHeight + expandedHeight) / 2

        if velocityY < -500 {
            snapTo(expanded: true)
        } else if velocityY > 500 {
            snapTo(expanded: false)
        } else {
            snapTo(expanded: currentH > midPoint)
        }
    }

    private func snapTo(expanded: Bool) {
        let targetH = expanded ? expandedHeight : collapsedHeight
        isExpanded = expanded
        onHeightChanged?(targetH)

        if !expanded {
            gridScrollView.setContentOffset(.zero, animated: false)
        }
    }
}
