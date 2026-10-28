import Foundation
import UIKit

/// Owned by the voice call and transferred with its SFU session through PiP.
@MainActor
final class VoiceBreakoutCoordinator {
    private let context: AccountContext
    private let accountEpoch: Int
    private weak var session: MezonSfuSession?
    private var channel: Mezon_Api_ChannelDescription?
    private var parent: Mezon_Api_ChannelDescription?
    private var knownParents = Set<Int64>()
    private var pending: VoiceBreakoutSignal?
    private var revision = UUID()
    private var acceptedChannelId: Int64?
    private var preparationId = UUID()
    private var isCommittingMove = false
    private var hasEnded = false
    private var socketDisposable: Disposable?
    private var presentationTask: Task<Void, Never>?
    private var moveTask: Task<Void, Never>?
    private weak var popup: VoiceBreakoutInviteController?
    private var presenter: (() -> UIViewController?)?
    private var move: ((Mezon_Api_ChannelDescription, Mezon_Api_GenerateMeetTokenResponse) -> Bool)?

    var isInBreakout: Bool { parent != nil }

    init(context: AccountContext) {
        self.context = context
        self.accountEpoch = context.sessionEpoch
        socketDisposable = (context.account.socket.events() |> deliverOnMainQueue).start(next: { [weak self] event in
            guard case .sfuBreakoutRoom(let event) = event else { return }
            self?.handle(event)
        })
    }

    func begin(channel: Mezon_Api_ChannelDescription) {
        guard !hasEnded, self.channel == nil, context.isStillCurrentSession(epoch: accountEpoch) else { return }
        self.channel = channel
    }

    deinit {
        socketDisposable?.dispose()
        presentationTask?.cancel()
        moveTask?.cancel()
    }

    func attach(channel: Mezon_Api_ChannelDescription, session: MezonSfuSession,
                presenter: @escaping () -> UIViewController?,
                move: @escaping (Mezon_Api_ChannelDescription, Mezon_Api_GenerateMeetTokenResponse) -> Bool) {
        guard !hasEnded, context.isStillCurrentSession(epoch: accountEpoch) else { endCall(); return }
        if self.session !== session, !isCommittingMove { pauseForReconnect() }
        self.channel = channel
        self.session = session
        self.presenter = presenter
        self.move = move
    }

    func cancelInvitation() {
        revision = UUID()
        pending = nil
        acceptedChannelId = nil
        cancelPreparation()
        presentationTask?.cancel()
        presentationTask = nil
        dismissPopup()
    }

    private func cancelPreparation() {
        preparationId = UUID()
        moveTask?.cancel()
        moveTask = nil
    }

    private func dismissPopup() {
        popup?.dismiss(animated: false)
        popup = nil
    }

    func endCall() {
        hasEnded = true
        cancelInvitation()
        session = nil
        channel = nil
        parent = nil
        knownParents.removeAll()
        presenter = nil
        move = nil
    }

    /// A transport failure ends the SFU session, but the user can still retry the
    /// same call. Keep both the latest invitation and an already accepted move.
    func pauseForReconnect() {
        guard !isCommittingMove else { return }
        cancelPreparation()
        dismissPopup()
    }

    func sessionDidLeave(_ session: MezonSfuSession) {
        // Native cleanup of an old room can finish after its replacement joined.
        guard self.session === session else { return }
        pauseForReconnect()
    }

    func returnToMain() {
        guard let parent, channel != nil else { return }
        cancelInvitation()
        pending = .returnToMain
        accept(channelId: parent.channelID, revision: revision)
        monitorInvitation()
    }

    private func handle(_ event: Mezon_Realtime_SfuBreakoutRoomEvent) {
        guard context.isStillCurrentSession(epoch: accountEpoch) else { endCall(); return }
        guard let channel, channel.clanID != 0 else { return }
        let parentId = parent?.channelID ?? channel.channelID
        guard let signal = VoiceBreakoutSignal.classify(
            channelId: event.channelID, hasToken: !event.token.isEmpty, selfSelectIds: event.selfSelectIds,
            currentChannelId: channel.channelID, parentChannelId: parentId, knownParents: knownParents
        ) else { return }
        if signal == .closed {
            cancelInvitation()
        } else if signal != pending {
            knownParents.insert(parentId)
            replaceInvitation(signal)
        }
    }

    private func replaceInvitation(_ signal: VoiceBreakoutSignal) {
        cancelInvitation()
        pending = signal
        monitorInvitation()
    }

    private func monitorInvitation() {
        guard presentationTask == nil else { return }
        // Keep an invitation received in the background or during a navigation
        // transition until the app can safely present it. New events cancel it.
        presentationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.updateInvitation() == true else { return }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func availablePresenter() -> UIViewController? {
        guard UIApplication.shared.applicationState == .active,
              let host = presenter?(), host.viewIfLoaded?.window != nil,
              !host.isBeingDismissed, !host.isBeingPresented,
              host.presentedViewController == nil, host.transitionCoordinator == nil else { return nil }
        return host
    }

    /// Continue observing while a popup is visible: UIKit can dismiss it during
    /// a PiP/navigation handoff without the user accepting or declining it.
    private func updateInvitation() -> Bool {
        guard context.isStillCurrentSession(epoch: accountEpoch) else { endCall(); return false }
        guard let pending, channel != nil else { return false }
        guard session?.isActiveForBreakout == true else {
            if moveTask != nil { cancelPreparation() }
            dismissPopup()
            return true
        }
        if let acceptedChannelId {
            if moveTask == nil, availablePresenter() != nil, context.account.socket.isConnected {
                prepareMove(channelId: acceptedChannelId, revision: revision)
            }
            return true
        }
        if let popup {
            if popup.isBeingPresented || popup.viewIfLoaded?.window != nil { return true }
            self.popup = nil
        }
        guard let host = availablePresenter() else { return true }
        let currentRevision = revision
        let mode: VoiceBreakoutInviteController.Mode
        let ids: [Int64]
        switch pending {
        case .assigned(let id): mode = .assigned; ids = [id]
        case .choose(let rooms): mode = .choose; ids = rooms
        case .returnToMain: mode = .returnToMain; ids = parent.map { [$0.channelID] } ?? []
        case .closed: return false
        }
        let invitation = VoiceBreakoutInviteController(
            mode: mode, rooms: ids.map { .init(channelId: $0, name: roomName($0)) },
            onJoin: { [weak self] id in
                guard let self, self.revision == currentRevision else { return }
                self.popup = nil
                self.accept(channelId: id, revision: currentRevision)
            }, onNotNow: { [weak self] in
                guard let self, self.revision == currentRevision else { return }
                self.cancelInvitation()
            })
        popup = invitation
        host.present(invitation, animated: true)
        return true
    }

    private func roomName(_ id: Int64) -> String {
        let name = context.account.postbox.resolvedChannelDescription(clanId: channel?.clanID ?? 0, channelId: id)?.channelLabel
        return name.flatMap { $0.isEmpty ? nil : $0 } ?? L("voiceChannel.breakout.room", String(id))
    }

    private func accept(channelId: Int64, revision expectedRevision: UUID) {
        guard revision == expectedRevision, acceptedChannelId == nil, let source = channel else { return }
        if channelId == source.channelID { cancelInvitation(); return }
        acceptedChannelId = channelId
    }

    private func prepareMove(channelId: Int64, revision expectedRevision: UUID) {
        guard let source = channel, let sourceSession = session, sourceSession.isActiveForBreakout else { return }
        let currentPreparation = UUID()
        preparationId = currentPreparation
        moveTask = Task { @MainActor [weak self, weak sourceSession] in
            guard let self, let sourceSession else { return }
            defer {
                if self.preparationId == currentPreparation { self.moveTask = nil }
            }
            let socket = self.context.account.socket
            let generation = socket.connectionGeneration
            do {
                guard let token = await self.context.getToken() else {
                    throw MezonError.socketError(L("voiceChannel.breakout.unavailable"))
                }
                try Task.checkCancellation()
                guard socket.isConnected, socket.connectionGeneration == generation else { return }
                try await socket.joinClanChatAwait(clanId: source.clanID)
                try Task.checkCancellation()
                let channels = try await self.context.account.network.listChannelDescs(clanId: source.clanID, token: token, force: true)
                try Task.checkCancellation()
                guard let target = channels.first(where: {
                    $0.channelID == channelId && $0.clanID == source.clanID && $0.type == MezonConstants.ChannelType.mezonVoice.rawValue
                }), !self.context.engine.channels.isAccessRevoked(channelId: channelId) else {
                    throw MezonError.socketError(L("voiceChannel.breakout.unavailable"))
                }
                // As on desktop, mint a fresh token on acceptance instead of
                // reusing the invitation token, which may already have expired.
                let meetToken = try await self.context.account.network.generateMeetTokenResponse(
                    channelId: channelId, roomName: String(channelId),
                    metadata: self.context.meetTokenMetadata(clanId: source.clanID), token: token)
                try Task.checkCancellation()
                guard !meetToken.token.isEmpty else { throw MezonError.invalidResponse }
                guard !Task.isCancelled, self.revision == expectedRevision,
                      self.preparationId == currentPreparation,
                      self.context.isStillCurrentSession(epoch: self.accountEpoch), self.session === sourceSession,
                      sourceSession.isActiveForBreakout else { return }
                guard !self.context.engine.channels.isAccessRevoked(channelId: channelId) else {
                    throw MezonError.socketError(L("voiceChannel.breakout.unavailable"))
                }
                // If connectivity or UI changed while minting the token, retain
                // the accepted move and prepare a fresh token when ready again.
                guard socket.isConnected, socket.connectionGeneration == generation,
                      self.availablePresenter() != nil else { return }
                let previousParent = self.parent
                self.parent = channelId == self.parent?.channelID ? nil : (self.parent ?? source)
                self.isCommittingMove = true
                let moved = self.move?(target, meetToken) == true
                self.isCommittingMove = false
                guard moved else {
                    self.parent = previousParent
                    throw MezonError.socketError(L("voiceChannel.breakout.unavailable"))
                }
                self.cancelInvitation()
            } catch {
                guard !Task.isCancelled, self.revision == expectedRevision,
                      self.preparationId == currentPreparation,
                      self.context.isStillCurrentSession(epoch: self.accountEpoch) else { return }
                // A realtime reconnect invalidates the request, not the invite.
                guard socket.isConnected, socket.connectionGeneration == generation else { return }
                self.acceptedChannelId = nil
                Toast.error(error.localizedDescription)
            }
        }
    }
}
