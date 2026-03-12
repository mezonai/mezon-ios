import UIKit
import SwiftProtobuf

struct MessagesState {
    var directMessages: [Mezon_Api_ChannelDescription]
    var isEmpty: Bool
    var isLoading: Bool
    var errorMessage: String?

    static let empty = MessagesState(directMessages: [], isEmpty: true, isLoading: false, errorMessage: nil)
}

final class MessagesViewController: ViewController {

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

    private var messagesNode: MessagesContainerNode { displayNode as! MessagesContainerNode }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: nil)
    }

    required init(coder aDecoder: NSCoder) { fatalError() }

    override func loadDisplayNode() {
        let interaction = MessagesInteraction(
            onSelectDirectMessage: { [weak self] ch in
                guard let self else { return }
                let vc = ChannelMessagesViewController(clanId: 0, channel: ch, context: self.context)
                self.navigationController?.pushViewController(vc, animated: true)
            },
            onAddFriendTapped: {},
            onSearchTapped: {},
            onBackTapped: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        )
        displayNode = MessagesContainerNode(signal: stateSignal(), interaction: interaction, context: context)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await fetchDirectMessages() }
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        messagesNode.updateLayout(layout: layout, transition: transition)
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

    var currentState: MessagesState {
        MessagesState(directMessages: directMessages, isEmpty: isEmpty, isLoading: isLoading, errorMessage: errorMessage)
    }

    func stateSignal() -> Signal<MessagesState, NoError> {
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
