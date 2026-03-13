import UIKit
import AsyncDisplayKit

final class ProfileContentComponent: CombinedComponent {
    let displayName: String
    let username: String
    let avatarURL: URL?
    let isOnline: Bool
    let onBack: () -> Void
    let onCopyUserId: () -> Void

    init(displayName: String, username: String, avatarURL: URL?, isOnline: Bool, onBack: @escaping () -> Void, onCopyUserId: @escaping () -> Void) {
        self.displayName = displayName
        self.username = username
        self.avatarURL = avatarURL
        self.isOnline = isOnline
        self.onBack = onBack
        self.onCopyUserId = onCopyUserId
    }

    static func == (lhs: ProfileContentComponent, rhs: ProfileContentComponent) -> Bool {
        return lhs.displayName == rhs.displayName && lhs.username == rhs.username && lhs.avatarURL == rhs.avatarURL && lhs.isOnline == rhs.isOnline
    }

    static var body: Body {
        let header = Child(ProfileHeaderComponent.self)
        let nameText = Child(Text.self)
        let usernameText = Child(Text.self)
        let balanceCard = Child(CardComponent.self)
        let editButton = Child(ProfileActionButtonComponent.self)
        let memberCard = Child(CardComponent.self)
        let friendsCard = Child(CardComponent.self)
        let copyCard = Child(CardComponent.self)

        return { context in
            let component = context.component
            let sideInset: CGFloat = 20
            let contentWidth = context.availableSize.width - sideInset * 2

            var nextY: CGFloat = 0

            let headerChild = header.update(
                component: ProfileHeaderComponent(avatarURL: component.avatarURL, isOnline: component.isOnline, onBack: component.onBack),
                availableSize: CGSize(width: context.availableSize.width, height: 140),
                transition: context.transition
            )
            context.add(headerChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + headerChild.size.height / 2)))
            nextY += headerChild.size.height + 16

            let nameChild = nameText.update(
                component: Text(text: component.displayName, font: .systemFont(ofSize: 22, weight: .bold), color: .mezonTextPrimary),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(nameChild.position(CGPoint(x: sideInset + nameChild.size.width / 2, y: nextY + nameChild.size.height / 2)))
            nextY += nameChild.size.height + 4

            let usernameChild = usernameText.update(
                component: Text(text: component.username, font: .systemFont(ofSize: 15), color: .mezonTextSecondary),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(usernameChild.position(CGPoint(x: sideInset + usernameChild.size.width / 2, y: nextY + usernameChild.size.height / 2)))
            nextY += usernameChild.size.height + 20

            let balanceContent = AnyComponent<Empty>(VStack<Empty>([
                AnyComponentWithIdentity(id: "balance", component: AnyComponent(IconRowComponent(icon: "checkmark.circle.fill", title: "\(L(L10n.Profile.balance)): 0 \(L(L10n.Profile.currency))"))),
                AnyComponentWithIdentity(id: "transfer", component: AnyComponent(IconRowComponent(icon: "arrow.up.square", title: L(L10n.Profile.transferFunds)))),
                AnyComponentWithIdentity(id: "history", component: AnyComponent(IconRowComponent(icon: "folder", title: L(L10n.Profile.historyTransaction)))),
            ], alignment: .left, spacing: 16))

            let balanceChild = balanceCard.update(
                component: CardComponent(content: balanceContent),
                availableSize: CGSize(width: context.availableSize.width, height: 10000),
                transition: context.transition
            )
            context.add(balanceChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + balanceChild.size.height / 2)))
            nextY += balanceChild.size.height + 16

            let editChild = editButton.update(
                component: ProfileActionButtonComponent(title: L(L10n.Profile.editProfile), icon: "pencil"),
                availableSize: CGSize(width: context.availableSize.width, height: 50),
                transition: context.transition
            )
            context.add(editChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + editChild.size.height / 2)))
            nextY += editChild.size.height + 16

            let memberContent = AnyComponent<Empty>(Text(text: L(L10n.Profile.mezonMemberSince), font: .systemFont(ofSize: 15), color: .mezonTextPrimary))
            let memberChild = memberCard.update(
                component: CardComponent(content: memberContent),
                availableSize: CGSize(width: context.availableSize.width, height: 10000),
                transition: context.transition
            )
            context.add(memberChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + memberChild.size.height / 2)))
            nextY += memberChild.size.height + 16

            let friendsContent = AnyComponent<Empty>(IconRowComponent(icon: "person.2.fill", title: L(L10n.Profile.yourFriends), trailingIcon: "chevron.right"))
            let friendsChild = friendsCard.update(
                component: CardComponent(content: friendsContent),
                availableSize: CGSize(width: context.availableSize.width, height: 10000),
                transition: context.transition
            )
            context.add(friendsChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + friendsChild.size.height / 2)))
            nextY += friendsChild.size.height + 16

            let copyContent = AnyComponent<Empty>(IconRowComponent(icon: "doc.on.doc", title: L(L10n.Profile.copyUserId)))
            let copyChild = copyCard.update(
                component: CardComponent(content: copyContent),
                availableSize: CGSize(width: context.availableSize.width, height: 10000),
                transition: context.transition
            )
            let copyUpdated = copyChild.position(CGPoint(x: context.availableSize.width / 2, y: nextY + copyChild.size.height / 2))
                .gesture(Gesture.tap { component.onCopyUserId() })
            context.add(copyUpdated)
            nextY += copyChild.size.height + 24

            return CGSize(width: context.availableSize.width, height: nextY)
        }
    }
}

final class ProfileHeaderComponent: Component {
    let avatarURL: URL?
    let isOnline: Bool
    let onBack: () -> Void

    init(avatarURL: URL?, isOnline: Bool, onBack: @escaping () -> Void) {
        self.avatarURL = avatarURL
        self.isOnline = isOnline
        self.onBack = onBack
    }

    static func == (lhs: ProfileHeaderComponent, rhs: ProfileHeaderComponent) -> Bool {
        return lhs.avatarURL == rhs.avatarURL && lhs.isOnline == rhs.isOnline
    }

    final class View: UIView {
        private let banner = UIView()
        private let backButton = UIButton(type: .system)
        private let avatarImageView = UIImageView()
        private let onlineIndicator = UIView()
        private let statusButton = UIButton(type: .system)
        private var onBack: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            banner.backgroundColor = UIColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
            addSubview(banner)

            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: "chevron.left")
            cfg.baseForegroundColor = .white
            backButton.configuration = cfg
            backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
            banner.addSubview(backButton)

            avatarImageView.contentMode = .scaleAspectFill
            avatarImageView.clipsToBounds = true
            avatarImageView.layer.cornerRadius = 40
            avatarImageView.backgroundColor = .mezonSecondaryBackground
            avatarImageView.layer.borderWidth = 3
            avatarImageView.layer.borderColor = UIColor.white.cgColor
            banner.addSubview(avatarImageView)

            onlineIndicator.backgroundColor = .mezonSuccess
            onlineIndicator.layer.cornerRadius = 7
            onlineIndicator.layer.borderWidth = 2
            onlineIndicator.layer.borderColor = UIColor.mezonBackground.cgColor
            avatarImageView.addSubview(onlineIndicator)

            var statusCfg = UIButton.Configuration.plain()
            statusCfg.image = UIImage(systemName: "plus.circle.fill")
            statusCfg.title = " \(L(L10n.Profile.addStatus))"
            statusCfg.baseForegroundColor = .white
            statusCfg.imagePadding = 4
            statusButton.configuration = statusCfg
            banner.addSubview(statusButton)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: ProfileHeaderComponent, availableSize: CGSize) -> CGSize {
            let size = CGSize(width: availableSize.width, height: 140)
            banner.frame = CGRect(origin: .zero, size: size)
            backButton.frame = CGRect(x: 4, y: 8, width: 44, height: 44)
            avatarImageView.frame = CGRect(x: 20, y: (size.height - 80) / 2, width: 80, height: 80)
            onlineIndicator.frame = CGRect(x: 66, y: 66, width: 14, height: 14)
            statusButton.frame = CGRect(x: 116, y: (size.height - 44) / 2, width: 200, height: 44)
            onlineIndicator.isHidden = !component.isOnline
            self.onBack = component.onBack

            if let url = component.avatarURL {
                Task {
                    if let data = try? await URLSession.shared.data(from: url).0, let img = UIImage.decodeImage(from: data) {
                        await MainActor.run { self.avatarImageView.image = img }
                    }
                }
            }

            return size
        }

        @objc private func backTapped() { onBack?() }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}

final class ProfileActionButtonComponent: Component {
    let title: String
    let icon: String

    init(title: String, icon: String) {
        self.title = title
        self.icon = icon
    }

    static func == (lhs: ProfileActionButtonComponent, rhs: ProfileActionButtonComponent) -> Bool {
        return lhs.title == rhs.title && lhs.icon == rhs.icon
    }

    final class View: UIView {
        private let button = UIButton(type: .system)

        override init(frame: CGRect) {
            super.init(frame: frame)
            var cfg = UIButton.Configuration.filled()
            cfg.baseForegroundColor = .white
            cfg.baseBackgroundColor = .mezonPrimary
            cfg.cornerStyle = .medium
            cfg.imagePadding = 8
            button.configuration = cfg
            addSubview(button)
        }

        required init?(coder: NSCoder) { fatalError() }

        func update(component: ProfileActionButtonComponent, availableSize: CGSize) -> CGSize {
            button.configuration?.title = component.title
            button.configuration?.image = UIImage(systemName: component.icon)
            let size = CGSize(width: availableSize.width, height: 50)
            button.frame = CGRect(origin: .zero, size: size)
            return size
        }
    }

    func makeView() -> View { View(frame: .zero) }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        view.update(component: self, availableSize: availableSize)
    }
}

@MainActor
final class ProfileContainerNode: ASDisplayNode {
    private let componentHostView = ComponentHostView<Empty>()
    private let scrollView = UIScrollView()
    private let context: AccountContext

    var onBackTapped: (() -> Void)?

    init(context: AccountContext) {
        self.context = context
        super.init()
    }

    override func didLoad() {
        super.didLoad()
        view.backgroundColor = .mezonBackground
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(componentHostView)
        updateContent()
    }

    func updateLayout(layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        scrollView.frame = CGRect(origin: .zero, size: layout.size)
        updateContent()
    }

    private func updateContent() {
        let user = context.currentUser
        let component = ProfileContentComponent(
            displayName: user?.displayName ?? "—",
            username: user?.username.isEmpty == false ? "@\(user!.username)" : "—",
            avatarURL: user?.avatarURL,
            isOnline: user?.status == .online,
            onBack: { [weak self] in self?.onBackTapped?() },
            onCopyUserId: { [weak self] in
                guard let userId = self?.context.currentUser?.id else { return }
                UIPasteboard.general.string = userId
                Toast.info(L(L10n.Profile.userIdCopied))
            }
        )

        let size = componentHostView.update(
            transition: .immediate,
            component: AnyComponent(component),
            environment: {},
            containerSize: CGSize(width: scrollView.bounds.width > 0 ? scrollView.bounds.width : UIScreen.main.bounds.width, height: .greatestFiniteMagnitude)
        )
        componentHostView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
    }
}
