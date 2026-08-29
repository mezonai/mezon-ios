import Foundation

struct ClanOnboardingViewState: Equatable {
    static let totalSteps = 3
    static let hidden = ClanOnboardingViewState()

    var isVisible: Bool = false
    var completedSteps: Int = 0
    var createChannelCompleted: Bool = false
    var inviteCompleted: Bool = false
    var sendMessageCompleted: Bool = false
    var welcomeChannelId: Int64 = 0
    var welcomeChannelCategoryId: Int64 = 0

    var currentDisplayStep: Int {
        min(completedSteps + 1, Self.totalSteps)
    }
}

enum ClanOnboardingProgress {
    static func isEligible(context: AccountContext, clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        let currentUserId = Int64(context.account.id) ?? 0
        guard currentUserId != 0 else { return false }
        let creatorId: Int64 = context.account.postbox.read { tx -> Int64 in
            guard let record = tx.getClan(id: clanId),
                  !record.data.isEmpty,
                  let desc = try? Mezon_Api_ClanDesc(serializedBytes: record.data) else {
                return 0
            }
            return desc.creatorID
        }
        guard creatorId != 0, currentUserId == creatorId else { return false }
        return context.rolePermissions.isClanOwner(clanId: clanId)
    }

    static func compute(
        context: AccountContext,
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        memberCount: Int
    ) -> ClanOnboardingViewState {
        guard clanId != 0 else { return .hidden }

        let topLevelChannelCount = channels.filter { $0.parentID == 0 }.count

        let clanInfo = context.account.postbox.read { tx -> (creatorId: Int64, welcomeChannelId: Int64)? in
            guard let record = tx.getClan(id: clanId),
                  !record.data.isEmpty,
                  let desc = try? Mezon_Api_ClanDesc(serializedBytes: record.data) else {
                return nil
            }
            return (desc.creatorID, desc.welcomeChannelID)
        }

        guard let clanInfo else { return .hidden }

        let currentUserId = Int64(context.account.id) ?? 0
        guard currentUserId != 0,
              currentUserId == clanInfo.creatorId,
              context.rolePermissions.isClanOwner(clanId: clanId) else {
            return .hidden
        }

        guard !channels.isEmpty else { return .hidden }

        let createChannelLive = topLevelChannelCount > 1
        let inviteLive = memberCount > 1
        if createChannelLive { markStepCompleted(.createChannel, clanId: clanId) }
        if inviteLive { markStepCompleted(.invite, clanId: clanId) }
        let createChannelCompleted = createChannelLive || isStepCompleted(.createChannel, clanId: clanId)
        let inviteCompleted = inviteLive || isStepCompleted(.invite, clanId: clanId)
        let sendMessageCompleted = sendMessageStepStatus(
            context: context,
            clanId: clanId,
            welcomeChannelId: clanInfo.welcomeChannelId,
            currentUserId: currentUserId
        )

        let completedSteps = [createChannelCompleted, inviteCompleted, sendMessageCompleted].filter { $0 }.count
        guard completedSteps < ClanOnboardingViewState.totalSteps else { return .hidden }

        let welcomeCategoryId = channels.first(where: { $0.channelID == clanInfo.welcomeChannelId })?.categoryID ?? 0

        return ClanOnboardingViewState(
            isVisible: true,
            completedSteps: completedSteps,
            createChannelCompleted: createChannelCompleted,
            inviteCompleted: inviteCompleted,
            sendMessageCompleted: sendMessageCompleted,
            welcomeChannelId: clanInfo.welcomeChannelId,
            welcomeChannelCategoryId: welcomeCategoryId
        )
    }

    enum Step: String {
        case createChannel
        case invite
    }

    private static func stepFlagKey(_ step: Step, clanId: Int64) -> String {
        "mezon.clanOnboardingStep.\(step.rawValue).\(clanId)"
    }

    static func markStepCompleted(_ step: Step, clanId: Int64) {
        guard clanId != 0 else { return }
        UserDefaults.standard.set(true, forKey: stepFlagKey(step, clanId: clanId))
    }

    static func isStepCompleted(_ step: Step, clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        return UserDefaults.standard.bool(forKey: stepFlagKey(step, clanId: clanId))
    }

    private static func sendMessageStepStatus(
        context: AccountContext,
        clanId: Int64,
        welcomeChannelId: Int64,
        currentUserId: Int64
    ) -> Bool {
        guard welcomeChannelId != 0, currentUserId != 0 else { return false }

        let postbox = context.account.postbox
        if ClanOnboardingChannelCache.hasCreatorSentWelcomeMessage(postbox: postbox, clanId: clanId) {
            return true
        }

        let hasCreatorMessageInPostbox = postbox.read { tx in
            ClanOnboardingChannelCache.welcomeChannelHasCreatorChatMessage(
                transaction: tx,
                welcomeChannelId: welcomeChannelId,
                creatorId: currentUserId
            )
        }
        if hasCreatorMessageInPostbox {
            ClanOnboardingChannelCache.markCreatorSentWelcomeMessage(postbox: postbox, clanId: clanId)
            return true
        }
        return false
    }
}

enum ClanOnboardingChannelCache {
    private static let creatorSentMessageValue = Data([1])
    private static let userDefaultsKeyPrefix = "mezon.onboardingCreatorSentMessage."

    static func isEphemeralMessageCode(_ code: Int32) -> Bool {
        switch code {
        case MezonConstants.MessageCode.ephemeral.rawValue,
             MezonConstants.MessageCode.updateEphemeral.rawValue,
             MezonConstants.MessageCode.deleteEphemeral.rawValue:
            return true
        default:
            return false
        }
    }

    @available(iOS 13.0, *)
    static func markSendMessageOnboardingProgressIfNeeded(
        context: AccountContext,
        postbox: Postbox,
        clanId: Int64,
        channelId: Int64,
        messageId: Int64,
        messageCode: Int32,
        anonymous: Bool
    ) {
        guard !anonymous else { return }
        guard !isEphemeralMessageCode(messageCode) else { return }
        guard messageId != 0 else { return }
        markCreatorSentWelcomeMessageIfNeeded(
            postbox: postbox,
            clanId: clanId,
            channelId: channelId,
            messageId: messageId
        )
        MemberOnboardingProgress.completeSendMessageMissionIfNeeded(
            context: context,
            clanId: clanId,
            channelId: channelId
        )
    }

    private static func userDefaultsKey(clanId: Int64) -> String {
        "\(userDefaultsKeyPrefix)\(clanId)"
    }

    private static func setUserDefaultsCreatorSentWelcomeMessage(clanId: Int64) {
        guard clanId != 0 else { return }
        UserDefaults.standard.set(true, forKey: userDefaultsKey(clanId: clanId))
    }

    static func hasCreatorSentWelcomeMessage(postbox: Postbox, clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        if UserDefaults.standard.bool(forKey: userDefaultsKey(clanId: clanId)) {
            return true
        }
        guard let data = postbox.getPreferenceData(key: PreferencesKeys.onboardingCreatorSentMessage(clanId: clanId)),
              let first = data.first,
              first == 1 else {
            return false
        }
        setUserDefaultsCreatorSentWelcomeMessage(clanId: clanId)
        return true
    }

    static func markCreatorSentWelcomeMessage(postbox: Postbox, clanId: Int64) {
        guard clanId != 0 else { return }
        if hasCreatorSentWelcomeMessage(postbox: postbox, clanId: clanId) { return }
        setUserDefaultsCreatorSentWelcomeMessage(clanId: clanId)
        postbox.setPreferenceDataSync(
            key: PreferencesKeys.onboardingCreatorSentMessage(clanId: clanId),
            value: creatorSentMessageValue
        )
    }

    static func markCreatorSentWelcomeMessage(transaction tx: PostboxTransaction, clanId: Int64) {
        guard clanId != 0 else { return }
        let key = PreferencesKeys.onboardingCreatorSentMessage(clanId: clanId)
        if UserDefaults.standard.bool(forKey: userDefaultsKey(clanId: clanId))
            || tx.getSetting(key: key)?.first == 1 {
            return
        }
        setUserDefaultsCreatorSentWelcomeMessage(clanId: clanId)
        tx.setSetting(key: key, value: creatorSentMessageValue)
    }

    static func markCreatorSentWelcomeMessageIfNeeded(
        postbox: Postbox,
        clanId: Int64,
        channelId: Int64,
        messageId: Int64
    ) {
        guard clanId != 0, channelId != 0, messageId != 0 else { return }
        let welcomeChannelId = welcomeChannelId(postbox: postbox, clanId: clanId)
        guard welcomeChannelId != 0, channelId == welcomeChannelId else { return }
        markCreatorSentWelcomeMessage(postbox: postbox, clanId: clanId)
        NotificationCenter.default.post(
            name: .mezonChannelDescriptionDidUpdate,
            object: nil,
            userInfo: [
                "clanId": clanId,
                "channelId": channelId,
            ]
        )
    }

    static func markCreatorSentWelcomeMessageIfNeeded(
        transaction tx: PostboxTransaction,
        clanId: Int64,
        channelId: Int64
    ) {
        guard clanId != 0, channelId != 0 else { return }
        let welcomeChannelId = welcomeChannelId(transaction: tx, clanId: clanId)
        guard welcomeChannelId != 0, channelId == welcomeChannelId else { return }
        markCreatorSentWelcomeMessage(transaction: tx, clanId: clanId)
    }

    static func welcomeChannelHasCreatorChatMessage(
        transaction tx: PostboxTransaction,
        welcomeChannelId: Int64,
        creatorId: Int64
    ) -> Bool {
        guard welcomeChannelId != 0, creatorId != 0 else { return false }
        let channelId = String(welcomeChannelId)
        let creatorSenderId = "\(creatorId)"
        return tx.getRecentMessages(channelId: channelId, limit: 50).contains { message in
            !message.isDeleted
                && message.senderId == creatorSenderId
                && !isEphemeralMessageCode(message.code)
        }
    }

    static func welcomeChannelId(postbox: Postbox, clanId: Int64) -> Int64 {
        postbox.read { tx in
            welcomeChannelId(transaction: tx, clanId: clanId)
        }
    }

    static func welcomeChannelId(transaction tx: PostboxTransaction, clanId: Int64) -> Int64 {
        guard let record = tx.getClan(id: clanId),
              !record.data.isEmpty,
              let desc = try? Mezon_Api_ClanDesc(serializedBytes: record.data) else {
            return 0
        }
        return desc.welcomeChannelID
    }
}
