import Foundation

enum MemberOnboardingMissionType: Int32 {
    case sendMessage = 1
    case visit = 2
    case doSomething = 3
}

struct MemberOnboardingMission: Equatable {
    let id: Int64
    let channelId: Int64
    let taskType: MemberOnboardingMissionType
    let title: String
}

struct MemberOnboardingViewState: Equatable {
    static let hidden = MemberOnboardingViewState()

    var isVisible: Bool = false
    var completedSteps: Int = 0
    var missions: [MemberOnboardingMission] = []

    var currentDisplayStep: Int {
        min(completedSteps + 1, max(missions.count, 1))
    }
}

enum MemberOnboardingProgress {
    private static let doneMissionKeyPrefix = "mezon.memberOnboarding.doneMission."
    private static let fullyDoneKeyPrefix = "mezon.memberOnboarding.fullyDone."

    @MainActor
    private static var missionsByClanId: [Int64: [MemberOnboardingMission]] = [:]

    @MainActor
    static func clearClanData(clanId: Int64) {
        missionsByClanId[clanId] = nil
    }

    @MainActor
    static func isEligible(context: AccountContext, clanId: Int64) -> Bool {
        guard clanId != 0 else { return false }
        if ClanOnboardingProgress.isEligible(context: context, clanId: clanId) { return false }
        guard clanIsOnboardingEnabled(context: context, clanId: clanId) else { return false }

        let userId = resolvedUserId(context: context)
        guard userId != 0 else { return false }
        if isFullyDone(clanId: clanId, userId: userId) { return false }
        return true
    }

    @MainActor
    static func compute(context: AccountContext, clanId: Int64) -> MemberOnboardingViewState {
        guard isEligible(context: context, clanId: clanId) else { return .hidden }

        let missions = missionsByClanId[clanId] ?? []
        guard !missions.isEmpty else { return .hidden }

        let userId = resolvedUserId(context: context)
        guard userId != 0 else { return .hidden }

        let completedSteps = doneMissionCount(userId: userId, clanId: clanId)
        guard completedSteps < missions.count else { return .hidden }

        return MemberOnboardingViewState(
            isVisible: true,
            completedSteps: completedSteps,
            missions: missions
        )
    }

    @MainActor
    static func fetchData(context: AccountContext, clanId: Int64) async {
        guard clanId != 0 else { return }
        guard clanIsOnboardingEnabled(context: context, clanId: clanId) else {
            clearClanData(clanId: clanId)
            return
        }
        guard let token = await context.getToken() else {
            Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
            return
        }

        do {
            async let onboardingItemsTask = MezonHTTPClient.shared.listOnboarding(clanId: clanId, token: token)
            async let onboardingStepsTask = MezonHTTPClient.shared.listOnboardingStep(clanId: clanId, token: token)

            let onboardingItems = try await onboardingItemsTask
            let missions = parseMissions(from: onboardingItems)
            missionsByClanId[clanId] = missions

            let userId = await awaitResolvedUserId(context: context)
            let steps = (try? await onboardingStepsTask) ?? []
            if userId != 0 {
                let serverStep = resolvedServerOnboardingStep(
                    steps: steps,
                    userId: userId,
                    clanId: clanId
                )
                applyServerProgress(
                    userId: userId,
                    clanId: clanId,
                    serverStep: serverStep,
                    missionCount: missions.count
                )
                await reconcileLocalProgressToServerIfNeeded(
                    context: context,
                    clanId: clanId,
                    serverStep: serverStep,
                    missionCount: missions.count,
                    userId: userId
                )
            }

            NotificationCenter.default.post(
                name: .mezonMemberOnboardingDidUpdate,
                object: nil,
                userInfo: ["clanId": clanId]
            )
        } catch {
            SentryLogger.capture(error, extras: [
                "where": "MemberOnboardingProgress.fetchData",
                "clanId": clanId,
            ])
        }
    }

    @MainActor
    static func currentMission(context: AccountContext, clanId: Int64) -> MemberOnboardingMission? {
        let state = compute(context: context, clanId: clanId)
        guard state.isVisible, state.completedSteps < state.missions.count else { return nil }
        return state.missions[state.completedSteps]
    }

    @MainActor
    static func resolveChannelLabel(
        channelId: Int64,
        context: AccountContext,
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription] = []
    ) -> String? {
        guard channelId != 0 else { return nil }
        if let label = channels.first(where: { $0.channelID == channelId })?.channelLabel,
           !label.isEmpty {
            return label
        }
        if let label = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId)?.channelLabel,
           !label.isEmpty {
            return label
        }
        return nil
    }

    static func missionActionSubtitle(
        taskType: MemberOnboardingMissionType,
        channelLabel: String?
    ) -> String {
        let actionKey: String = {
            switch taskType {
            case .sendMessage: return L10n.OnboardingMember.missionSendMessage
            case .visit: return L10n.OnboardingMember.missionVisit
            case .doSomething: return L10n.OnboardingMember.missionDoSomething
            }
        }()
        let action = L(actionKey)
        guard let channelLabel, !channelLabel.isEmpty else { return action }
        return "\(action) #\(channelLabel)"
    }

    @MainActor
    static func performMission(
        _ mission: MemberOnboardingMission,
        at index: Int,
        completedSteps: Int,
        context: AccountContext,
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        navigation: MemberOnboardingChannelNavigation
    ) {
        guard index == completedSteps else { return }
        switch mission.taskType {
        case .visit:
            MemberOnboardingChannelRouting.openChannel(
                channelId: mission.channelId,
                completeVisit: true,
                context: context,
                clanId: clanId,
                channels: channels,
                navigation: navigation
            )
        case .sendMessage:
            MemberOnboardingChannelRouting.openChannel(
                channelId: mission.channelId,
                completeVisit: false,
                context: context,
                clanId: clanId,
                channels: channels,
                navigation: navigation
            )
        case .doSomething:
            completeDoSomethingMissionIfNeeded(context: context, clanId: clanId)
        }
    }

    @MainActor
    static func completeVisitMissionIfNeeded(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64
    ) {
        completeMissionIfNeeded(
            context: context,
            clanId: clanId,
            matching: { $0.taskType == .visit && $0.channelId == channelId }
        )
    }

    @MainActor
    static func completeSendMessageMissionIfNeeded(
        context: AccountContext,
        clanId: Int64,
        channelId: Int64
    ) {
        completeMissionIfNeeded(
            context: context,
            clanId: clanId,
            matching: { $0.taskType == .sendMessage && $0.channelId == channelId }
        )
    }

    @MainActor
    static func completeDoSomethingMissionIfNeeded(context: AccountContext, clanId: Int64) {
        completeMissionIfNeeded(
            context: context,
            clanId: clanId,
            matching: { $0.taskType == .doSomething }
        )
    }

    @MainActor
    private static func completeMissionIfNeeded(
        context: AccountContext,
        clanId: Int64,
        matching predicate: (MemberOnboardingMission) -> Bool
    ) {
        guard isEligible(context: context, clanId: clanId) else { return }
        let missions = missionsByClanId[clanId] ?? []
        guard !missions.isEmpty else { return }

        let userId = resolvedUserId(context: context)
        guard userId != 0 else { return }

        let doneCount = doneMissionCount(userId: userId, clanId: clanId)
        guard doneCount < missions.count else { return }

        let currentMission = missions[doneCount]
        guard predicate(currentMission) else { return }

        let newCompleted = doneCount + 1
        setDoneMissionCount(userId: userId, clanId: clanId, count: newCompleted)

        let isFullyComplete = newCompleted >= missions.count
        if isFullyComplete {
            markFullyDone(clanId: clanId, userId: userId)
        }

        syncOnboardingStepToServer(
            context: context,
            clanId: clanId,
            onboardingStep: Int32(newCompleted)
        )

        NotificationCenter.default.post(
            name: .mezonMemberOnboardingDidUpdate,
            object: nil,
            userInfo: ["clanId": clanId]
        )
    }

    @MainActor
    private static func resolvedServerOnboardingStep(
        steps: [Mezon_Api_OnboardingSteps],
        userId: Int64,
        clanId: Int64
    ) -> Int32 {
        steps
            .filter { $0.userID == userId && $0.clanID == clanId }
            .map(\.onboardingStep)
            .max() ?? 0
    }

    @MainActor
    private static func applyServerProgress(
        userId: Int64,
        clanId: Int64,
        serverStep: Int32,
        missionCount: Int
    ) {
        let localCount = doneMissionCount(userId: userId, clanId: clanId)
        let serverCount = restoredCompletedCountFromServer(
            serverStep: serverStep,
            missionCount: missionCount
        )
        let effectiveCount = max(localCount, serverCount)
        let cappedCount = missionCount > 0 ? min(effectiveCount, missionCount) : effectiveCount

        if cappedCount > localCount {
            setDoneMissionCount(userId: userId, clanId: clanId, count: cappedCount)
        }

        if missionCount > 0, cappedCount >= missionCount {
            markFullyDone(clanId: clanId, userId: userId)
        } else if isFullyDone(clanId: clanId, userId: userId) {
            clearFullyDone(clanId: clanId, userId: userId)
        }
    }

    @MainActor
    private static func reconcileLocalProgressToServerIfNeeded(
        context: AccountContext,
        clanId: Int64,
        serverStep: Int32,
        missionCount: Int,
        userId: Int64
    ) async {
        guard missionCount > 0 else { return }

        let localCount = doneMissionCount(userId: userId, clanId: clanId)
        guard localCount > Int(serverStep) else { return }
        syncOnboardingStepToServer(
            context: context,
            clanId: clanId,
            onboardingStep: Int32(localCount)
        )
    }

    private static func restoredCompletedCountFromServer(serverStep: Int32, missionCount: Int) -> Int {
        let count = max(0, Int(serverStep))
        guard missionCount > 0 else { return count }
        return min(count, missionCount)
    }

    @MainActor
    private static func syncOnboardingStepToServer(
        context: AccountContext,
        clanId: Int64,
        onboardingStep: Int32
    ) {
        guard clanId != 0, onboardingStep > 0 else { return }
        Task { @MainActor in
            guard let token = await context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                try await MezonHTTPClient.shared.updateOnboardingStep(
                    clanId: clanId,
                    onboardingStep: onboardingStep,
                    token: token
                )
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "MemberOnboardingProgress.syncOnboardingStepToServer",
                    "clanId": clanId,
                    "onboardingStep": onboardingStep,
                ])
            }
        }
    }

    @MainActor
    private static func resolvedUserId(context: AccountContext) -> Int64 {
        for candidate in resolvedUserIdStringCandidates(context: context) {
            if let userId = Int64(candidate), userId != 0 {
                return userId
            }
        }
        return 0
    }

    @MainActor
    private static func resolvedUserIdStringCandidates(context: AccountContext) -> [String] {
        var candidates: [String] = []
        if let id = context.currentUser?.id, !id.isEmpty {
            candidates.append(id)
        }
        if let id = context.session?.userId, !id.isEmpty {
            candidates.append(id)
        }
        if let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.account),
           let api = try? Mezon_Api_Account(serializedData: data),
           api.user.id != 0 {
            candidates.append("\(api.user.id)")
        }
        if !context.account.id.isEmpty {
            candidates.append(context.account.id)
        }
        return candidates
    }

    @MainActor
    private static func awaitResolvedUserId(
        context: AccountContext,
        maxWaitSeconds: TimeInterval = 8
    ) async -> Int64 {
        let deadline = Date().addingTimeInterval(maxWaitSeconds)
        while Date() < deadline {
            let userId = resolvedUserId(context: context)
            if userId != 0 { return userId }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return resolvedUserId(context: context)
    }

    private static func parseMissions(from items: [Mezon_Api_OnboardingItem]) -> [MemberOnboardingMission] {
        items.compactMap { item in
            guard isTaskGuideItem(item) else { return nil }
            guard let taskType = MemberOnboardingMissionType(rawValue: item.taskType) else { return nil }
            let title = missionTitle(from: item)
            guard !title.isEmpty else { return nil }
            return MemberOnboardingMission(
                id: item.id,
                channelId: item.channelID,
                taskType: taskType,
                title: title
            )
        }
    }

    private static func isTaskGuideItem(_ item: Mezon_Api_OnboardingItem) -> Bool {
        item.guideType == 2 || item.guideType == 3
    }

    private static func missionTitle(from item: Mezon_Api_OnboardingItem) -> String {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return item.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private static func clanIsOnboardingEnabled(context: AccountContext, clanId: Int64) -> Bool {
        context.account.postbox.read { tx in
            guard let record = tx.getClan(id: clanId),
                  !record.data.isEmpty,
                  let desc = try? Mezon_Api_ClanDesc(serializedBytes: record.data) else {
                return false
            }
            return desc.isOnboarding
        }
    }

    private static func doneMissionStorageKey(userId: Int64, clanId: Int64) -> String {
        "\(doneMissionKeyPrefix)\(userId).\(clanId)"
    }

    private static func fullyDoneStorageKey(userId: Int64, clanId: Int64) -> String {
        "\(fullyDoneKeyPrefix)\(userId).\(clanId)"
    }

    private static func doneMissionCount(userId: Int64, clanId: Int64) -> Int {
        max(0, UserDefaults.standard.integer(forKey: doneMissionStorageKey(userId: userId, clanId: clanId)))
    }

    private static func setDoneMissionCount(userId: Int64, clanId: Int64, count: Int) {
        UserDefaults.standard.set(count, forKey: doneMissionStorageKey(userId: userId, clanId: clanId))
    }

    private static func isFullyDone(clanId: Int64, userId: Int64) -> Bool {
        guard userId != 0 else { return false }
        return UserDefaults.standard.bool(forKey: fullyDoneStorageKey(userId: userId, clanId: clanId))
    }

    private static func markFullyDone(clanId: Int64, userId: Int64) {
        guard userId != 0 else { return }
        UserDefaults.standard.set(true, forKey: fullyDoneStorageKey(userId: userId, clanId: clanId))
    }

    private static func clearFullyDone(clanId: Int64, userId: Int64) {
        guard userId != 0 else { return }
        UserDefaults.standard.removeObject(forKey: fullyDoneStorageKey(userId: userId, clanId: clanId))
    }
}

extension Notification.Name {
    static let mezonMemberOnboardingDidUpdate = Notification.Name("mezonMemberOnboardingDidUpdate")
}
