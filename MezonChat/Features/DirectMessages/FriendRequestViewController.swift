import UIKit

enum EStateFriend: Int32 {
    case friend = 0
    case otherPending = 1
    case myPending = 2
    case block = 3
}

struct FriendRequestState {
    var receivedRequests: [Mezon_Api_Friend]

    static let empty = FriendRequestState(receivedRequests: [])
}

final class FriendRequestViewController: ViewController {

    private let context: AccountContext

    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var receivedRequests: [Mezon_Api_Friend] = []
    private var fetchTask: Task<Void, Never>?
    private var socketDebounceTask: Task<Void, Never>?
    private var latestFetchRequestId: Int = 0
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
            let safeTop = max(layout.safeInsets.top, 54)
            friendRequestNode.updateLayout(
                size: layout.size,
                safeTop: safeTop,
                bottomInset: layout.intrinsicInsets.bottom,
                transition: .immediate
            )
        }
        fetchFriendRequests()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        socketDebounceTask?.cancel()
    }

    private var socketDisposable: Disposable?

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)
        
        socketDisposable = (MezonSocket.shared.events()
            |> deliverOnMainQueue).start(next: { [weak self] event in
                switch event {
                case .addFriend, .removeFriend, .blockFriend:
                    self?.scheduleSocketRefresh()
                default:
                    break
                }
            })
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        socketDisposable?.dispose()
        fetchTask?.cancel()
        socketDebounceTask?.cancel()
    }

    @objc private func handleThemeChange() {
        guard isNodeLoaded else { return }
        friendRequestNode.applyTheme()
    }

    private var lastLayout: ContainerViewLayout?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout

        let safeTop = max(layout.safeInsets.top, 54)
        friendRequestNode.updateLayout(
            size: layout.size,
            safeTop: safeTop,
            bottomInset: layout.intrinsicInsets.bottom,
            transition: transition
        )
    }

    private func setReceivedRequests(_ v: [Mezon_Api_Friend]) {
        let next = filteredMyPendingRequests(v)
        guard friendListSignature(receivedRequests) != friendListSignature(next) else { return }
        receivedRequests = next
        needsReloadPipe.putNext(())
    }

    private func filteredMyPendingRequests(_ friends: [Mezon_Api_Friend]) -> [Mezon_Api_Friend] {
        friends.filter { $0.state == EStateFriend.myPending.rawValue }
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
        FriendRequestState(receivedRequests: receivedRequests)
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

    private func fetchFriendRequests() {
        fetchTask?.cancel()
        latestFetchRequestId += 1
        let requestId = latestFetchRequestId
        fetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            do {
                let listFriends = try await self.context.account.network.listFriends(
                    token: token,
                    limit: 1000,
                    state: EStateFriend.myPending.rawValue
                )
                guard !Task.isCancelled, self.latestFetchRequestId == requestId else { return }
                self.setReceivedRequests(listFriends.friends)
            } catch is CancellationError {
                return
            } catch {
                guard self.latestFetchRequestId == requestId else { return }
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func scheduleSocketRefresh() {
        socketDebounceTask?.cancel()
        socketDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.isViewLoaded, self.view.window != nil else { return }
            self.fetchFriendRequests()
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

                if let idx = self.receivedRequests.firstIndex(where: { $0.user.id == userId }) {
                    var updatedList = self.receivedRequests
                    updatedList.remove(at: idx)
                    self.setReceivedRequests(updatedList)
                }
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

                if let idx = self.receivedRequests.firstIndex(where: { $0.user.id == userId }) {
                    var updatedList = self.receivedRequests
                    updatedList.remove(at: idx)
                    self.setReceivedRequests(updatedList)
                }
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }
}
