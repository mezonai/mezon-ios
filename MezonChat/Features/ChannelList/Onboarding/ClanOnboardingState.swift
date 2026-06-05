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
    @MainActor
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

    @MainActor
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

        let createChannelCompleted = topLevelChannelCount > 1
        let inviteCompleted = memberCount > 1
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

    @MainActor
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

        let hasUserMessageInPostbox = postbox.read { tx in
            ClanOnboardingChannelCache.welcomeChannelSendMessageComplete(
                transaction: tx,
                welcomeChannelId: welcomeChannelId
            )
        }
        if hasUserMessageInPostbox {
            ClanOnboardingChannelCache.markCreatorSentWelcomeMessage(postbox: postbox, clanId: clanId)
            return true
        }
        return false
    }
}

enum ClanOnboardingChannelCache {
    private static let creatorSentMessageValue = Data([1])
    private static let userDefaultsKeyPrefix = "mezon.onboardingCreatorSentMessage."

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

    /// Matches RN onboarding: step 3 is done once the latest welcome-channel message is not the bootstrap indicator (code 4).
    static func welcomeChannelSendMessageComplete(
        transaction tx: PostboxTransaction,
        welcomeChannelId: Int64
    ) -> Bool {
        guard welcomeChannelId != 0 else { return false }
        let channelId = String(welcomeChannelId)
        guard let lastMessage = tx.getRecentMessages(channelId: channelId, limit: 1).first,
              !lastMessage.isDeleted else {
            return false
        }
        return lastMessage.code != MezonConstants.MessageCode.firstMessage.rawValue
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
