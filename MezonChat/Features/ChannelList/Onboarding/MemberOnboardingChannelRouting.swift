import Foundation

struct MemberOnboardingChannelNavigation {
    let openChat: (Mezon_Api_ChannelDescription) -> Void
    let presentVoice: (Mezon_Api_ChannelDescription) -> Void
}

enum MemberOnboardingChannelRouting {
    @MainActor
    static func openChannel(
        channelId: Int64,
        completeVisit: Bool,
        context: AccountContext,
        clanId: Int64,
        channels: [Mezon_Api_ChannelDescription],
        navigation: MemberOnboardingChannelNavigation
    ) {
        guard channelId != 0 else { return }

        let completeIfNeeded = {
            if completeVisit {
                MemberOnboardingProgress.completeVisitMissionIfNeeded(
                    context: context,
                    clanId: clanId,
                    channelId: channelId
                )
            }
        }

        let navigate: (Mezon_Api_ChannelDescription) -> Void = { channel in
            if channel.type == MezonConstants.ChannelType.mezonVoice.rawValue {
                navigation.presentVoice(channel)
            } else {
                navigation.openChat(channel)
            }
            completeIfNeeded()
        }

        if let channel = channels.first(where: { $0.channelID == channelId }) {
            navigate(channel)
            return
        }

        if let channel = context.account.postbox.resolvedChannelDescription(clanId: clanId, channelId: channelId) {
            navigate(channel)
            return
        }

        Task { @MainActor in
            guard let token = await context.getToken() else {
                Toast.error(L(L10n.ClanInviteSheet.sessionNotFound))
                return
            }
            do {
                let fetched = try await MezonHTTPClient.shared.listChannelDescs(clanId: clanId, token: token)
                guard let channel = fetched.first(where: { $0.channelID == channelId }) else { return }
                navigate(channel)
            } catch {
                SentryLogger.capture(error, extras: [
                    "where": "MemberOnboardingChannelRouting.openChannel",
                    "clanId": clanId,
                    "channelId": channelId,
                ])
            }
        }
    }
}
