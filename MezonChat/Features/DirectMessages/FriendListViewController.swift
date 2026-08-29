import UIKit

struct FriendAlphabetGroup {
    let character: String
    let friends: [Mezon_Api_Friend]
}

struct FriendListState {
    var groups: [FriendAlphabetGroup]
    var receivedRequestCount: Int
    var sentRequestCount: Int
    var totalFriendCount: Int
    var isSearching: Bool

    static let empty = FriendListState(groups: [], receivedRequestCount: 0, sentRequestCount: 0, totalFriendCount: 0, isSearching: false)
}

final class FriendListViewController: ViewController {

    private let context: AccountContext

    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var allFriends: [Mezon_Api_Friend] = []              
    private(set) var filteredFriends: [Mezon_Api_Friend] = []
    private(set) var groups: [FriendAlphabetGroup] = []
    private(set) var receivedRequestCount: Int = 0
    private(set) var sentRequestCount: Int = 0
    private(set) var searchText: String = ""
    private var refreshTask: CancelHandle?
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var friendsUpdatedDisposable: Disposable?
    private var lastStateSignature: String?

    private var friendListNode: FriendListContainerNode { displayNode as! FriendListContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        if #available(iOS 13.0, *) {
            syncFromGlobalFriendState()
        }

        let interaction = FriendListInteraction(
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
            onAddFriendTapped: { [weak self] in
                guard let self else { return }
                let vc = AddFriendByUsernameViewController(context: self.context)
                if let nav = self.navigationController as? NavigationController {
                    nav.pushViewController(vc, animated: false)
                } else {
                    self.push(vc)
                }
            },
            onFriendRequestTapped: { [weak self] in
                guard let self else { return }
                let vc = FriendRequestViewController(context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onCallFriend: { [weak self] friend in
                self?.handleCallFriend(friend)
            },
            onMessageFriend: { [weak self] friend in
                if #available(iOS 13.0, *) {
                    self?.handleMessageFriend(friend)
                }
            },
            onShowProfile: { [weak self] friend in
                self?.showMemberProfile(friend)
            }
        )
        let node = FriendListContainerNode(signal: stateSignal(), interaction: interaction)
        node.onSearchTextChanged = { [weak self] text in
            if #available(iOS 13.0, *) {
                self?.handleSearchTextChanged(text)
            }
        }
        displayNode = node
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let layout = lastLayout {
            friendListNode.updateLayout(
                size: layout.size,
                safeTop: resolvedSafeTop(for: layout),
                bottomInset: layout.intrinsicInsets.bottom,
                transition: .immediate
            )
        }
        if #available(iOS 13.0, *) {
            syncFromGlobalFriendState()
        }
        if #available(iOS 13.0, *) {
            refreshFromNetwork()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: ThemeManager.didChangeNotification, object: nil)

        friendsUpdatedDisposable = (context.engine.friendsData.friendsUpdated.signal()
            |> deliverOnMainQueue).start(next: { [weak self] _ in
                if #available(iOS 13.0, *) {
                    self?.syncFromGlobalFriendState()
                }
            })
        if #available(iOS 13.0, *) {
            syncFromGlobalFriendState()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        friendsUpdatedDisposable?.dispose()
        refreshTask?.cancel()
        searchDebounceWorkItem?.cancel()
    }

    @objc private func handleThemeChange() {
        guard isNodeLoaded else { return }
        friendListNode.applyTheme()
    }

    private var lastLayout: ContainerViewLayout?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout

        friendListNode.updateLayout(
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

    var currentState: FriendListState {
        FriendListState(
            groups: groups,
            receivedRequestCount: receivedRequestCount,
            sentRequestCount: sentRequestCount,
            totalFriendCount: allFriends.count,
            isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func stateSignal() -> Signal<FriendListState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }

    @available(iOS 13.0, *)
    private func syncFromGlobalFriendState() {
        let allFriendsRaw = context.engine.friendsData.allFriends()
        allFriends = allFriendsRaw.filter { $0.state == EStateFriend.friend.rawValue }
        receivedRequestCount = allFriendsRaw.filter { $0.state == EStateFriend.myPending.rawValue }.count
        sentRequestCount = allFriendsRaw.filter { $0.state == EStateFriend.otherPending.rawValue }.count
        applyFilter()
    }

    @available(iOS 13.0, *)
    private func applyFilter() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            filteredFriends = allFriends
        } else {
            let normalizedQuery = normalizeString(query)
            filteredFriends = allFriends.filter { friend in
                let displayName = friend.user.displayName
                let username = friend.user.username
                return normalizeString(displayName).contains(normalizedQuery)
                    || normalizeString(username).contains(normalizedQuery)
            }
        }
        groups = groupByAlphabet(filteredFriends)
        let signature = makeStateSignature()
        guard signature != lastStateSignature else { return }
        lastStateSignature = signature
        needsReloadPipe.putNext(())
    }

    private func normalizeString(_ str: String) -> String {
        str.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func groupByAlphabet(_ friends: [Mezon_Api_Friend]) -> [FriendAlphabetGroup] {
        guard !friends.isEmpty else { return [] }

        var dict: [String: [Mezon_Api_Friend]] = [:]
        for friend in friends {
            let priorityName = friend.user.displayName.isEmpty ? friend.user.username : friend.user.displayName
            let firstChar = priorityName.trimmingCharacters(in: .whitespacesAndNewlines)
            let character: String
            if let first = firstChar.first, first.isLetter {
                character = String(first).uppercased()
            } else {
                character = "#"
            }
            dict[character, default: []].append(friend)
        }

        return dict.map { FriendAlphabetGroup(character: $0.key, friends: $0.value) }
            .sorted { $0.character < $1.character }
    }

    @available(iOS 13.0, *)
    private func handleSearchTextChanged(_ text: String) {
        searchDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.searchText = text
            self.applyFilter()
        }
        searchDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    @available(iOS 13.0, *)
    private func refreshFromNetwork() {
        refreshTask?.cancel()
        let refreshTaskWork = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            await self.context.engine.friendsData.refreshFromNetwork(token: token)
        }
        refreshTask = CancelHandle { refreshTaskWork.cancel() }
    }

    @available(iOS 13.0, *)
    private func handleMessageFriend(_ friend: Mezon_Api_Friend) {
        guard friend.hasUser else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let token = await self.context.getToken() else { return }
            let targetUserId = friend.user.id

            let dmChannels = try? await self.context.account.network.listDirectMessageChannels(token: token)
            if let existing = dmChannels?.first(where: { ch in
                ch.type == MezonConstants.ChannelType.dm.rawValue
                && ch.userIds.count == 1
                && ch.userIds.contains(targetUserId)
            }) {
                let chatVC = ChatViewController(clanId: 0, channel: existing, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
                return
            }

            do {
                let channel = try await self.context.account.network.createDirectMessage(
                    userId: targetUserId,
                    token: token
                )
                let chatVC = ChatViewController(clanId: 0, channel: channel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            } catch {
                Toast.error(error.localizedDescription)
            }
        }
    }

    private func handleCallFriend(_ friend: Mezon_Api_Friend) {
    }

    @available(iOS 13.0, *)
    private func makeStateSignature() -> String {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        parts.reserveCapacity(groups.count + 3)
        parts.append("rq:\(receivedRequestCount)")
        parts.append("sq:\(sentRequestCount)")
        parts.append("q:\(normalizedSearch)")

        for group in groups {
            let ids = group.friends.map { friend -> String in
                let user = friend.user
                if user.id != 0 {
                    return "\(user.id)"
                }
                return user.username + "|" + user.displayName
            }.joined(separator: ",")
            parts.append("\(group.character):\(ids)")
        }

        return parts.joined(separator: ";")
    }

    private func showMemberProfile(_ friend: Mezon_Api_Friend) {
        guard friend.hasUser else { return }
        let user = friend.user
        let isCurrentUser = user.id == (Int64(context.currentUser?.id ?? "") ?? 0)

        view.endEditing(true)

        let sheet = MemberProfileSheetController(
            user: user,
            context: context,
            isCurrentUser: isCurrentUser,
            onSendMessage: { [weak self] dmChannel in
                guard let self else { return }
                let chatVC = ChatViewController(clanId: 0, channel: dmChannel, context: self.context, parentName: nil)
                self.navigationController?.pushViewController(chatVC, animated: true)
            },
            onTransferFunds: { [weak self] payload in
                guard let self else { return }
                let vc = WalletTransferViewController(context: self.context, payload: payload)
                self.navigationController?.pushViewController(vc, animated: true)
            }
        )
        self.presentInGlobalOverlay(sheet)
        sheet.animateIn()
    }
}
