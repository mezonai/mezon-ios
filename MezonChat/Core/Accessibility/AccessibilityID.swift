enum AccessibilityID {
    static func makeAccessibilityID(_ key: String, id: String? = nil) -> String {
        let base = key.split(separator: ".").joined(separator: "-")
        return id.map { "\(base)-\($0)" } ?? base
    }

    enum Main {
        static let root = makeAccessibilityID("main.root")
    }

    enum ChannelList {
        static let search = makeAccessibilityID("channel.list.search")
        static let discover = makeAccessibilityID("channel.list.discover")
        static let scanQR = makeAccessibilityID("channel.list.scan.qr")
        static let actionSheet = makeAccessibilityID("channel.action.sheet")

        static func actionSheetAction(_ action: String) -> String {
            makeAccessibilityID("channel.action", id: action)
        }
    }

    enum ChannelDetail {
        static let inviteMembers = makeAccessibilityID("channel.detail.invite.members")

        static func action(_ name: String) -> String {
            makeAccessibilityID("channel.detail.action", id: name)
        }
    }

    enum Search {
        static func input(_ scope: String) -> String {
            makeAccessibilityID("search.input", id: scope)
        }

        static let filterFrom = makeAccessibilityID("search.filter.from")
        static let filterMentions = makeAccessibilityID("search.filter.mentions")
    }

    enum Profile {
        static let settings = makeAccessibilityID("profile.settings")
    }

    enum GeneralSettings {
        static let updateEmailInput = makeAccessibilityID("settings.update.email.input")
        static let screen = makeAccessibilityID("settings.screen")
        static let back = makeAccessibilityID("settings.back")
        static let search = makeAccessibilityID("settings.search")

        static func row(_ name: String) -> String {
            makeAccessibilityID("settings.row", id: name)
        }
    }

    enum Discover {
        static let list = makeAccessibilityID("discover.list")
        static let search = makeAccessibilityID("discover.search")
        static let scanQR = makeAccessibilityID("discover.scan.qr")
        static let addFriend = makeAccessibilityID("discover.add.friend")
        static let detail = makeAccessibilityID("discover.detail")
        static let back = makeAccessibilityID("discover.detail.back")
        static let join = makeAccessibilityID("discover.detail.join")

        static func clan(_ id: Int64) -> String {
            makeAccessibilityID("discover.clan", id: String(id))
        }
    }

    enum CreateClan {
        static let entry = makeAccessibilityID("create.clan.entry")
        static let back = makeAccessibilityID("create.clan.back")

        static func template(_ id: String) -> String {
            makeAccessibilityID("create.clan.template", id: id)
        }
    }

    enum ClanSettings {
        static let screen = makeAccessibilityID("clan.settings.screen")

        static func communityHashtag(_ tag: String) -> String {
            makeAccessibilityID("clan.settings.community.hashtag", id: tag.lowercased())
        }

        static func action(_ action: String) -> String {
            makeAccessibilityID("clan.settings.action", id: action)
        }
    }

    enum ThreadList {
        static let empty = makeAccessibilityID("thread.list.empty")
        static let createFromEmpty = makeAccessibilityID("thread.list.empty.create")
    }

    enum ChannelSettings {
        static func screen(_ scope: String) -> String {
            makeAccessibilityID("channel.settings.\(scope).screen")
        }

        static func action(_ scope: String, _ action: String) -> String {
            makeAccessibilityID("channel.settings.\(scope)", id: action)
        }

        static func item(_ scope: String, _ id: Int64) -> String {
            makeAccessibilityID("channel.settings.\(scope).item", id: String(id))
        }
    }

    enum QuickActionSettings {
        static func screen(_ scope: String) -> String {
            makeAccessibilityID("quick.action.settings.\(scope).screen")
        }

        static func action(_ scope: String, _ action: String) -> String {
            makeAccessibilityID("quick.action.settings.\(scope)", id: action)
        }

        static func item(_ kind: Int32, _ id: Int64) -> String {
            makeAccessibilityID("quick.action.settings.\(kind).item", id: String(id))
        }
    }

    enum ChannelPermissions {
        static func screen(_ scope: String) -> String {
            makeAccessibilityID("channel.permissions.\(scope).screen")
        }

        static func action(_ scope: String, _ action: String) -> String {
            makeAccessibilityID("channel.permissions.\(scope)", id: action)
        }

        static func item(_ scope: String, _ kind: String, _ id: Int64) -> String {
            makeAccessibilityID("channel.permissions.\(scope).\(kind)", id: String(id))
        }
    }

    enum RoleSettings {
        static func screen(_ scope: String) -> String {
            makeAccessibilityID("role.settings.\(scope).screen")
        }

        static func action(_ scope: String, _ action: String) -> String {
            makeAccessibilityID("role.settings.\(scope)", id: action)
        }

        static func role(_ id: Int64) -> String {
            makeAccessibilityID("role.settings.role", id: String(id))
        }
    }

    enum EventList {
        static let sheet = makeAccessibilityID("event.list.sheet")
        static let create = makeAccessibilityID("event.list.create")

        static func item(_ eventId: Int64) -> String {
            makeAccessibilityID("event.list.item", id: String(eventId))
        }

        static func action(_ action: String, eventId: Int64) -> String {
            makeAccessibilityID("event.list.action.\(action)", id: String(eventId))
        }
    }

    enum EventDetail {
        static let sheet = makeAccessibilityID("event.detail.sheet")

        static func action(_ action: String) -> String {
            makeAccessibilityID("event.detail.action", id: action)
        }
    }

    enum PeerCall {
        static let screen = makeAccessibilityID("peer.call.screen")
        static let close = makeAccessibilityID("peer.call.close")
        static let switchCamera = makeAccessibilityID("peer.call.switch.camera")
        static let video = makeAccessibilityID("peer.call.video")
        static let speaker = makeAccessibilityID("peer.call.speaker")
        static let microphone = makeAccessibilityID("peer.call.microphone")
        static let end = makeAccessibilityID("peer.call.end")
        static let answer = makeAccessibilityID("peer.call.answer")
        static let decline = makeAccessibilityID("peer.call.decline")
    }

    enum JoinChannel {
        static let voiceSheet = makeAccessibilityID("join.channel.voice.sheet")
        static let streamSheet = makeAccessibilityID("join.channel.stream.sheet")
        static let close = makeAccessibilityID("join.channel.close")
        static let invite = makeAccessibilityID("join.channel.invite")
        static let join = makeAccessibilityID("join.channel.join")
        static let chat = makeAccessibilityID("join.channel.chat")
        static let roleDropdown = makeAccessibilityID("join.channel.role.dropdown")
        static let speakerRole = makeAccessibilityID("join.channel.role.speaker")
        static let audienceRole = makeAccessibilityID("join.channel.role.audience")
        static let externalSheet = makeAccessibilityID("join.channel.external.sheet")
        static let externalJoin = makeAccessibilityID("join.channel.external.join")
        static let externalBrowser = makeAccessibilityID("join.channel.external.browser")
    }

    enum VoiceRoom {
        static let screen = makeAccessibilityID("voice.room.screen")
        static let expandedScreen = makeAccessibilityID("voice.room.expanded.screen")
        static let expandedClose = makeAccessibilityID("voice.room.expanded.close")
        static let collapse = makeAccessibilityID("voice.room.collapse")
        static let switchCamera = makeAccessibilityID("voice.room.switch.camera")
        static let audioOutput = makeAccessibilityID("voice.room.audio.output")
        static let more = makeAccessibilityID("voice.room.more")
        static let menuEmoji = makeAccessibilityID("voice.room.menu.emoji")
        static let menuSounds = makeAccessibilityID("voice.room.menu.sounds")
        static let menuNoiseSuppression = makeAccessibilityID("voice.room.menu.noise.suppression")
        static let networkWarningClose = makeAccessibilityID("voice.room.network.warning.close")
        static let raiseHand = makeAccessibilityID("voice.room.raise.hand")
        static let camera = makeAccessibilityID("voice.room.camera")
        static let microphone = makeAccessibilityID("voice.room.microphone")
        static let chat = makeAccessibilityID("voice.room.chat")
        static let screenShare = makeAccessibilityID("voice.room.screen.share")
        static let end = makeAccessibilityID("voice.room.end")
        static let pushToTalk = makeAccessibilityID("voice.room.push.to.talk")
        static let audienceEnd = makeAccessibilityID("voice.room.audience.end")
        static let audienceRaiseHand = makeAccessibilityID("voice.room.audience.raise.hand")
        static let audienceChat = makeAccessibilityID("voice.room.audience.chat")
    }

    enum StreamRoom {
        static let screen = makeAccessibilityID("stream.room.screen")
        static let collapse = makeAccessibilityID("stream.room.collapse")
        static let fullscreen = makeAccessibilityID("stream.room.fullscreen")
        static let chat = makeAccessibilityID("stream.room.chat")
        static let leave = makeAccessibilityID("stream.room.leave")
        static let audioOutput = makeAccessibilityID("stream.room.audio.output")
        static let quality = makeAccessibilityID("stream.room.quality")
        static let viewers = makeAccessibilityID("stream.room.viewers")
        static let pipClose = makeAccessibilityID("stream.room.pip.close")
        static let qualityClose = makeAccessibilityID("stream.room.quality.close")
        static let qualityDefault = makeAccessibilityID("stream.room.quality.default")

        static func qualityOption(_ quality: String) -> String {
            makeAccessibilityID("stream.room.quality.option", id: quality)
        }
    }

    enum Auth {
        static let welcomeStart = makeAccessibilityID("auth.welcome.start")
        static let email = makeAccessibilityID("auth.login.email")
        static let phone = makeAccessibilityID("auth.login.phone")
        static let password = makeAccessibilityID("auth.login.password")
        static let submit = makeAccessibilityID("auth.login.submit")
        static let otpSubmit = makeAccessibilityID("auth.otp.submit")

        static func otpDigit(_ index: Int) -> String {
            makeAccessibilityID("auth.otp.digit", id: String(index))
        }
    }

    enum Clan {
        static let list = makeAccessibilityID("clan.list")

        static func item(_ id: String) -> String {
            makeAccessibilityID("clan.item", id: id)
        }

        static func unreadBadge(_ id: String) -> String {
            makeAccessibilityID("clan.unread.badge", id: id)
        }

        static func channelList(_ id: String) -> String {
            makeAccessibilityID("clan.channel.list", id: id)
        }
    }

    enum Chat {
        static let screen = makeAccessibilityID("chat.screen")
        static let messageMenu = makeAccessibilityID("message.menu")
        static let replyAction = makeAccessibilityID("message.action.reply")
        static let editAction = makeAccessibilityID("message.action.edit")
        static let deleteAction = makeAccessibilityID("message.action.delete")
        static let copyAction = makeAccessibilityID("message.action.copy")
        static let reactionPicker = makeAccessibilityID("message.reaction.picker")
        static func mentionUser(_ id: String) -> String {
            makeAccessibilityID("mention.suggestion.user", id: id)
        }

        static func hashtagChannel(_ id: String) -> String {
            makeAccessibilityID("hashtag.suggestion.channel", id: id)
        }

        static let emojiSearch = makeAccessibilityID("emoji.search")

        static func emojiItem(_ id: String) -> String {
            makeAccessibilityID("emoji.item", id: id)
        }

        static let editCancel = makeAccessibilityID("mention.edit.cancel")
        static let replyBanner = makeAccessibilityID("mention.reply.target")
        static let replyReference = makeAccessibilityID("replied_message.item")
        static let channelDetails = makeAccessibilityID("chat.channel.details")
        static let detailsBack = makeAccessibilityID("channel.details.back")
        static let membersTab = makeAccessibilityID("channel.details.members")
        static let pinAction = makeAccessibilityID("message.action.pin")
        static let unpinAction = makeAccessibilityID("message.action.unpin")

        static func pinnedMessage(_ id: String) -> String {
            makeAccessibilityID("channel.pins.message", id: id)
        }

        static func pinnedMessageUnpin(_ id: String) -> String {
            makeAccessibilityID("channel.pins.unpin", id: id)
        }

        static let pinsTab = makeAccessibilityID("channel.details.pins")
        static let back = makeAccessibilityID("chat.back")
        static let input = makeAccessibilityID("mention.input")
        static let composerAttach = makeAccessibilityID("chat.composer.attach")
        static let composerMenu = makeAccessibilityID("chat.composer.menu")
        static let composerEmoji = makeAccessibilityID("chat.composer.emoji")
        static let composerMic = makeAccessibilityID("chat.composer.mic")
        static let send = makeAccessibilityID("mention.button.send")
        static let messages = makeAccessibilityID("message.list")
        static let typingIndicator = makeAccessibilityID("chat.typing.indicator")
        static let jumpToPresent = makeAccessibilityID("chat.jump.to.present")
        static let reactionRemove = makeAccessibilityID("message.reaction.remove")

        static func roleSuggestion(_ id: Int64) -> String {
            makeAccessibilityID("mention.suggestion.role", id: String(id))
        }

        static func contactAction(_ action: String) -> String {
            makeAccessibilityID("message.contact.action", id: action)
        }

        static func pollDetails(_ messageId: String) -> String {
            makeAccessibilityID("message.poll.details", id: messageId)
        }

        static func advancedAction(_ id: String) -> String {
            makeAccessibilityID("chat.composer.advanced.action", id: id)
        }

        static func quickReaction(_ emojiID: String) -> String {
            makeAccessibilityID("message.quick.reaction", id: emojiID)
        }

        static func reactionCount(_ emojiID: String) -> String {
            makeAccessibilityID("message.reaction.count", id: emojiID)
        }

        static func channelRow(_ id: String) -> String {
            makeAccessibilityID("channel.item", id: id)
        }

        static func messageText(_ id: String) -> String {
            makeAccessibilityID("message.text", id: id)
        }

        static func message(_ id: String) -> String {
            makeAccessibilityID("message.item", id: id)
        }
    }

    enum Event {
        static let openList = makeAccessibilityID("event.list.open")
        static let list = makeAccessibilityID("event.list")
        static let detail = makeAccessibilityID("event.detail")

        static func itemTitle(_ eventId: Int64) -> String {
            makeAccessibilityID("event.item.title", id: String(eventId))
        }
    }

    enum Video {
        static let playPause = makeAccessibilityID("video.play.pause")
        static let scrubberPlayPause = makeAccessibilityID("video.scrubber.play.pause")
        static let seekBackward = makeAccessibilityID("video.seek.backward")
        static let seekForward = makeAccessibilityID("video.seek.forward")
        static let scrubber = makeAccessibilityID("video.scrubber")
        static let loading = makeAccessibilityID("video.loading")
        static let progress = makeAccessibilityID("video.progress")
        static let error = makeAccessibilityID("video.error")
        static let openInBrowser = makeAccessibilityID("video.error.open.in.browser")
        static let closeError = makeAccessibilityID("video.error.close")
    }

    enum MediaPicker {
        static let uploadFile = makeAccessibilityID("mediaPicker.uploadFile")
        static let album = makeAccessibilityID("mediaPicker.album")
    }

    enum DirectMessage {
        static let search = makeAccessibilityID("direct.message.search")
        static let addMember = makeAccessibilityID("chat.direct_message.header.right_container.add_member")
        static let createGroup = makeAccessibilityID("chat.direct_message.button.create_group")
        static let actionSheet = makeAccessibilityID("dm.menu")
        static let blockUser = makeAccessibilityID("dm.menu.block.user")
        static let unblockUser = makeAccessibilityID("dm.menu.unblock.user")
        static let blockLoading = makeAccessibilityID("dm.menu.block.loading")

        static func action(_ name: String) -> String {
            makeAccessibilityID("dm.menu", id: name)
        }
    }

    enum QRCode {
        static let myScreen = makeAccessibilityID("qr.my.screen")
        static let myBack = makeAccessibilityID("qr.my.back")
        static let profileTab = makeAccessibilityID("qr.my.profile.tab")
        static let transferTab = makeAccessibilityID("qr.my.transfer.tab")
        static let editCenterImage = makeAccessibilityID("qr.my.edit.center.image")
        static let myDownload = makeAccessibilityID("qr.my.download")
        static let myShare = makeAccessibilityID("qr.my.share")
        static let clanScreen = makeAccessibilityID("qr.clan.screen")
        static let clanDownload = makeAccessibilityID("qr.clan.download")
        static let clanShare = makeAccessibilityID("qr.clan.share")
    }

    enum TransferSuccess {
        static let screen = makeAccessibilityID("transfer.success.screen")
        static let share = makeAccessibilityID("transfer.success.share")
        static let newTransfer = makeAccessibilityID("transfer.success.new.transfer")
        static let done = makeAccessibilityID("transfer.success.done")
    }

    enum MemberProfile {
        static let sheet = makeAccessibilityID("member.profile.sheet")
        static let message = makeAccessibilityID("member.profile.message")
        static let call = makeAccessibilityID("member.profile.call")
        static let addFriend = makeAccessibilityID("member.profile.add.friend")
        static let transfer = makeAccessibilityID("member.profile.transfer")
        static let voiceMute = makeAccessibilityID("member.profile.voice.mute")
        static let voiceKick = makeAccessibilityID("member.profile.voice.kick")
        static let blockUser = makeAccessibilityID("member.profile.block.user")
        static let unblockUser = makeAccessibilityID("member.profile.unblock.user")
        static let blockLoading = makeAccessibilityID("member.profile.block.loading")
    }

    enum BlockedUsers {
        static let screen = makeAccessibilityID("settings.blocked.users")
        static let back = makeAccessibilityID("settings.blocked.users.back")
        static let list = makeAccessibilityID("settings.blocked.users.list")
        static let empty = makeAccessibilityID("settings.blocked.users.empty")
        static let unblockLoading = makeAccessibilityID("settings.blocked.users.unblock.loading")

        static func user(_ id: Int64) -> String {
            makeAccessibilityID("settings.blocked.users.item", id: String(id))
        }

        static func unblock(_ id: Int64) -> String {
            makeAccessibilityID("settings.blocked.users.unblock", id: String(id))
        }
    }
}
