import UIKit

struct FriendRequestState {
    var receivedRequests: [Mezon_Api_Friend]
    var sentRequests: [Mezon_Api_Friend]

    static let empty = FriendRequestState(receivedRequests: [], sentRequests: [])
}

final class FriendRequestViewController: ViewController {

    private let context: AccountContext

    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var receivedRequests: [Mezon_Api_Friend] = []
    private(set) var sentRequests: [Mezon_Api_Friend] = []
    private var refreshTask: Task<Void, Never>?
    private var inFlightActionUserIds: Set<Int64> = []

    private var friendRequestNode: FriendRequestContainerNode { displayNode as! FriendRequestContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = FriendRequestInteraction(
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onSearchTapped: { [weak self] in
                guard let self else { return }
                let vc = AddFriendByUsernameViewController(context: self.context)
                if let nav = self.navigationController as? NavigationController {
                    nav.pushViewController(vc, animated: false)
                } else {
                    self.push(vc)
                }
            },
            onAcceptFriend: { [weak self] friend in
                self?.acceptFriend(friend)
            },
            onRejectFriend: { [weak self] friend in
                self?.rejectFriend(friend)
            }
        )
        displayNode = FriendRequestContainerNode(signal: stateSignal(), interaction: interaction)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let layout = lastLayout {
            friendRequestNode.updateLayout(
                size: layout.size,
                safeTop: resolvedSafeTop(for: layout),
                bottomInset: layout.intrinsicInsets.bottom,
                transition: .immediate
            )
        }
        syncFromGlobalFriendState()
        refreshFromNetwork()
    }

    private var friendsUpdatedDisposable: Disposable?

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        
        friendsUpdatedDisposable = (context.engine.friendsData.friendsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                self?.syncFromGlobalFriendState()
            })
        syncFromGlobalFriendState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        friendsUpdatedDisposable?.dispose()
        refreshTask?.cancel()
    }

    @objc private func handleThemeChange() {
        guard isNodeLoaded else { return }
        friendRequestNode.applyTheme()
    }

    private var lastLayout: ContainerViewLayout?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout

        friendRequestNode.updateLayout(
            size: layout.size,
            safeTop: resolvedSafeTop(for: layout),
            bottomInset: layout.intrinsicInsets.bottom,
            transition: transition
        )
    }

    private func resolvedSafeTop(for layout: ContainerViewLayout) -> CGFloat {
        let viewSafeTop = isViewLoaded ? view.safeAreaInsets.top : 0
        return max(layout.safeInsets.top, layout.statusBarHeight ?? 0, viewSafeTop)
    }

    private func setRequests(received: [Mezon_Api_Friend], sent: [Mezon_Api_Friend]) {
        let nextReceived = received.filter { $0.state == EStateFriend.myPending.rawValue }
        let nextSent = sent.filter { $0.state == EStateFriend.otherPending.rawValue }
        guard friendListSignature(receivedRequests) != friendListSignature(nextReceived)
                || friendListSignature(sentRequests) != friendListSignature(nextSent) else { return }
        receivedRequests = nextReceived
        sentRequests = nextSent
        needsReloadPipe.putNext(())
    }

    private func removeRequestsLocally(userId: Int64) {
        setRequests(
            received: receivedRequests.filter { $0.user.id != userId },
            sent: sentRequests.filter { $0.user.id != userId }
        )
    }

    private func friendListSignature(_ friends: [Mezon_Api_Friend]) -> String {
        friends.map { friend in
            let user = friend.user
            return [
                "\(friend.state)",
                "\(user.id)",
                user.displayName,
                user.username,
                user.avatarURL
            ].joined(separator: "|")
        }.joined(separator: "||")
    }

    var currentState: FriendRequestState {
        FriendRequestState(receivedRequests: receivedRequests, sentRequests: sentRequests)
    }

    func stateSignal() -> Signal<FriendRequestState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    private func syncFromGlobalFriendState() {
        let friendsData = context.engine.friendsData
        setRequests(
            received: friendsData.pendingIncomingFriends(),
            sent: friendsData.pendingOutgoingFriends()
        )
    }

    private func refreshFromNetwork(force: Bool = false) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            await self.context.engine.friendsData.refreshFromNetwork(token: token, force: force)
        }
    }

    private func acceptFriend(_ friend: Mezon_Api_Friend) {
        guard friend.hasUser else { return }
        let userId = friend.user.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.inFlightActionUserIds.contains(userId) else { return }
            self.inFlightActionUserIds.insert(userId)
            defer { self.inFlightActionUserIds.remove(userId) }
            guard let token = await self.context.getToken() else { return }
            do {
                try await self.context.account.network.addFriends(ids: [userId], token: token)

                self.removeRequestsLocally(userId: userId)
                self.context.engine.friendsData.removePendingRequest(userId: userId)
                self.refreshFromNetwork(force: true)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func rejectFriend(_ friend: Mezon_Api_Friend) {
        guard friend.hasUser else { return }
        let userId = friend.user.id
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard !self.inFlightActionUserIds.contains(userId) else { return }
            self.inFlightActionUserIds.insert(userId)
            defer { self.inFlightActionUserIds.remove(userId) }
            guard let token = await self.context.getToken() else { return }
            do {
                try await self.context.account.network.deleteFriends(ids: [userId], token: token)

                self.removeRequestsLocally(userId: userId)
                self.context.engine.friendsData.removePendingRequest(userId: userId)
                self.refreshFromNetwork(force: true)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }
}
