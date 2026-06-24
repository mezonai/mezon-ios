import UIKit

@MainActor
enum StreamingChannelBackground {

    static func normalizedAvatar(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("avatar-group.png") else { return "" }
        return trimmed
    }

    static func resolveAvatarURL(
        channel: Mezon_Api_ChannelDescription,
        context: AccountContext
    ) -> String {
        let clanId = channel.clanID != 0 ? channel.clanID : context.currentClanId
        let channelId = channel.channelID

        let direct = normalizedAvatar(channel.channelAvatar)
        if !direct.isEmpty { return direct }

        if clanId != 0,
           let data = context.account.postbox.getPreferenceData(key: PreferencesKeys.channelList(clanId: clanId)),
           !data.isEmpty,
           let listed = ChannelPreferenceListCodec.decode(data).first(where: { $0.channelID == channelId }) {
            let avatar = normalizedAvatar(listed.channelAvatar)
            if !avatar.isEmpty { return avatar }
        }

        if let list = context.engine.clanData.getAllChannelsByUser()?.channeldesc,
           let found = list.first(where: { $0.channelID == channelId }) {
            let avatar = normalizedAvatar(found.channelAvatar)
            if !avatar.isEmpty { return avatar }
        }

        if clanId != 0,
           let resolved = context.account.postbox.resolvedChannelDescription(
               clanId: clanId,
               channelId: channelId
           ) {
            let avatar = normalizedAvatar(resolved.channelAvatar)
            if !avatar.isEmpty { return avatar }
        }

        if clanId != 0,
           let proto = context.account.postbox.read({
               $0.getChannels(clanId: clanId).first(where: { $0.id == channelId })?.toProto()
           }) {
            let avatar = normalizedAvatar(proto.channelAvatar)
            if !avatar.isEmpty { return avatar }
        }

        return ""
    }

    static func loadImage(
        raw: String,
        width: Int,
        height: Int,
        completion: @escaping (UIImage?) -> Void
    ) {
        let absolute = ImgproxyURL.absoluteResourceURL(from: raw)
        guard !absolute.isEmpty else {
            completion(nil)
            return
        }
        let w = max(width, 1)
        let h = max(height, 1)
        let proxy = ImgproxyURL.create(from: absolute, width: w, height: h)
        ImageCache.shared.loadAvatar(urlString: proxy) { image in
            if let image {
                completion(image)
                return
            }
            ImageCache.shared.loadImage(urlString: absolute, completion: completion)
        }
    }
}
