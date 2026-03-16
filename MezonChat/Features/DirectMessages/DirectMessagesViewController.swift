import UIKit
import SwiftProtobuf

struct DirectMessagesState {
    var directMessages: [Mezon_Api_ChannelDescription]
    var isEmpty: Bool
    var isLoading: Bool
    var errorMessage: String?

    static let empty = DirectMessagesState(directMessages: [], isEmpty: true, isLoading: false, errorMessage: nil)
}

final class DirectMessagesViewController: ViewController {

    private let context: AccountContext

    private let directMessagesPipe = ValuePipe<[Mezon_Api_ChannelDescription]>()
    private let isEmptyPipe = ValuePipe<Bool>()
    private let isLoadingPipe = ValuePipe<Bool>()
    private let errorMessagePipe = ValuePipe<String?>()
    private let needsReloadPipe = ValuePipe<Void>()

    private(set) var directMessages: [Mezon_Api_ChannelDescription] = []
    private(set) var isEmpty: Bool = true
    private(set) var isLoading: Bool = false
    private(set) var errorMessage: String?

    private var directMessagesNode: DirectMessagesContainerNode { displayNode as! DirectMessagesContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = DirectMessagesInteraction(
            onSelectDirectMessage: { [weak self] ch in
                guard let self else { return }
                let vc = ChatViewController(clanId: 0, channel: ch, context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onAddFriendTapped: {},
            onSearchTapped: {},
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        displayNode = DirectMessagesContainerNode(signal: stateSignal(), interaction: interaction, context: context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await fetchDirectMessages() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(handleChannelMarkedAsRead(_:)), name: Notification.Name("MezonChannelMarkedAsRead"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleNewMessageReceived(_:)), name: Notification.Name("MezonNewMessageReceived"), object: nil)
    }

    /// Mirrors RN: badgeService.incrementDm(channelId, 1, false) for incoming DM/group messages
    @objc private func handleNewMessageReceived(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64,
              let clanId = notification.userInfo?["clanId"] as? Int64 else { return }

        let senderId: String
        if let s = notification.userInfo?["senderId"] as? String { senderId = s }
        else if let n = notification.userInfo?["senderId"] as? Int64 { senderId = String(n) }
        else { return }

        let ts: UInt32
        if let t = notification.userInfo?["timestampSeconds"] as? UInt32 { ts = t }
        else if let t = notification.userInfo?["timestampSeconds"] as? Int { ts = UInt32(t) }
        else { ts = UInt32(Date().timeIntervalSince1970) }

        guard clanId == 0 else { return }
        guard senderId != context.currentUser?.id else { return }

        var updated = false
        for i in 0..<directMessages.count {
            if directMessages[i].channelID == channelId {
                directMessages[i].countMessUnread += 1
                var header = directMessages[i].lastSentMessage
                header.timestampSeconds = ts
                directMessages[i].lastSentMessage = header
                updated = true
            }
        }
        if updated {
            directMessages.sort { ch1, ch2 in
                let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
                let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
                return t1 > t2
            }
            directMessagesPipe.putNext(directMessages)
            needsReloadPipe.putNext(())
        }
    }

    @objc private func handleChannelMarkedAsRead(_ notification: Notification) {
        guard let channelId = notification.userInfo?["channelId"] as? Int64 else { return }

        let mode = notification.userInfo?["mode"] as? Int32 ?? 0
        let isDMOrGroup = mode == MezonConstants.ChannelStreamMode.dm.rawValue
            || mode == MezonConstants.ChannelStreamMode.group.rawValue
        guard isDMOrGroup else { return }

        let now = notification.userInfo?["timestampSeconds"] as? UInt32 ?? UInt32(Date().timeIntervalSince1970)
        var updated = false
        for i in 0..<directMessages.count {
            if directMessages[i].channelID == channelId {
                directMessages[i].countMessUnread = 0
                directMessages[i].lastSeenMessage.timestampSeconds = now
                updated = true
            }
        }
        if updated {
            directMessagesPipe.putNext(directMessages)
            needsReloadPipe.putNext(())
        }
    }

    private var lastLayout: ContainerViewLayout?

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        lastLayout = layout
        directMessagesNode.updateLayout(layout: layout, transition: transition)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let layout = lastLayout {
            directMessagesNode.updateLayout(layout: layout, transition: .immediate)
        }
    }

    private func setDirectMessages(_ v: [Mezon_Api_ChannelDescription]) { directMessages = v; directMessagesPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsEmpty(_ v: Bool) { isEmpty = v; isEmptyPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setIsLoading(_ v: Bool) { isLoading = v; isLoadingPipe.putNext(v); needsReloadPipe.putNext(()) }
    private func setErrorMessage(_ v: String?) { errorMessage = v; errorMessagePipe.putNext(v); needsReloadPipe.putNext(()) }

    func fetchDirectMessages() async {
        guard let token = context.session?.token else { return }
        setIsLoading(true)
        setErrorMessage(nil)
        defer { setIsLoading(false) }

        do {
            let channels = try await self.context.account.network.listDirectMessageChannels(token: token)
            let sorted = channels.sorted { ch1, ch2 in
                let t1 = ch1.hasLastSentMessage ? ch1.lastSentMessage.timestampSeconds : 0
                let t2 = ch2.hasLastSentMessage ? ch2.lastSentMessage.timestampSeconds : 0
                return t1 > t2
            }
            setDirectMessages(sorted)
            setIsEmpty(sorted.isEmpty)
        } catch {
            setErrorMessage(error.localizedDescription)
            AppLogger.network.error("fetchDirectMessages: \(error)")
        }
    }

    var currentState: DirectMessagesState {
        DirectMessagesState(directMessages: directMessages, isEmpty: isEmpty, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<DirectMessagesState, NoError> {
        Signal { [weak self] subscriber in
            guard let self else { return EmptyDisposable }
            subscriber.putNext(self.currentState)
            return (self.needsReloadPipe.signal()
                |> map { [weak self] _ in self?.currentState ?? .empty }
                |> deliverOnMainQueue
            ).start(next: { subscriber.putNext($0) })
        }
    }
}
