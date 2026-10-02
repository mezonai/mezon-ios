import Foundation

enum EventLocationType: CaseIterable {
    case voice, location, external
}

enum EventRepeatType {
    static let doesNotRepeat: Int32 = 1
    static let weekly: Int32 = 2
    static let everyOtherWeek: Int32 = 3
    static let monthly: Int32 = 4
    static let annually: Int32 = 5
    static let everyWeekday: Int32 = 6
}

struct EventEditorDraft {
    static let maximumCoverBytes = 1024 * 1024
    static let maximumTitleLength = 128
    var locationType: EventLocationType?
    var voiceChannelId: Int64 = 0
    var announcementChannelId: Int64 = 0
    var address = ""
    var title = ""
    var description = ""
    var logoURL = ""
    var start: Date
    var end: Date
    var repeatType = EventRepeatType.doesNotRepeat

    init(event: Mezon_Api_EventManagement? = nil, now: Date = Date(), calendar: Calendar = .current) {
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        start = hour < now ? calendar.date(byAdding: .hour, value: 1, to: hour) ?? now : hour
        let nextHour = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        end = calendar.isDate(nextHour, inSameDayAs: start)
            ? nextHour
            : calendar.date(bySettingHour: 23, minute: 59, second: 0, of: start) ?? start
        if let event {
            locationType = event.channelVoiceID != 0 ? .voice : (!event.address.isEmpty ? .location : (event.isPrivate ? .external : .voice))
            voiceChannelId = event.channelVoiceID
            announcementChannelId = event.channelID
            address = event.address
            title = event.title
            description = event.description_p
            logoURL = event.logo
            start = Date(timeIntervalSince1970: TimeInterval(event.startTimeSeconds))
            end = Self.combining(
                date: start,
                time: Date(timeIntervalSince1970: TimeInterval(event.endTimeSeconds)),
                calendar: calendar
            )
            repeatType = event.repeatType
        }
    }

    mutating func setDate(_ date: Date, calendar: Calendar = .current) {
        start = Self.combining(date: date, time: start, calendar: calendar)
        end = Self.combining(date: date, time: end, calendar: calendar)
    }

    mutating func setStartTime(_ time: Date, calendar: Calendar = .current) {
        start = Self.combining(date: start, time: time, calendar: calendar)
    }

    mutating func setEndTime(_ time: Date, calendar: Calendar = .current) {
        end = Self.combining(date: start, time: time, calendar: calendar)
    }

    private static func combining(date: Date, time: Date, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = 0
        return calendar.date(from: components) ?? date
    }

    var channelVoiceId: Int64 { locationType == .voice ? voiceChannelId : 0 }
    var locationAddress: String { locationType == .location ? address : "" }
    var channelId: Int64 { announcementChannelId }
    var startSeconds: UInt32 { UInt32(clamping: Int64(start.timeIntervalSince1970)) }
    var endSeconds: UInt32 { UInt32(clamping: Int64(end.timeIntervalSince1970)) }

    var isLocationValid: Bool {
        switch locationType {
        case .voice: return voiceChannelId != 0
        case .location: return !address.isEmpty && address.utf16.count <= 100
        case .external: return true
        case nil: return false
        }
    }

    var titleError: String? {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return L(L10n.EventEditor.nameRequired) }
        if title.utf16.count > Self.maximumTitleLength { return L(L10n.EventEditor.nameTooLong, Self.maximumTitleLength) }
        if title.contains(where: { "`<>,/\"\\'".contains($0) }) { return L(L10n.EventEditor.invalidName) }
        return nil
    }

    func startError(now: Date = Date(), calendar: Calendar = .current) -> String? {
        let isPastToday = calendar.isDate(start, inSameDayAs: now) && start <= now
        return repeatType == EventRepeatType.doesNotRepeat && isPastToday ? L(L10n.EventEditor.startError) : nil
    }

    func endError() -> String? {
        end <= start ? L(L10n.EventEditor.endError) : nil
    }

    func isDetailsValid(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        titleError == nil && startError(now: now, calendar: calendar) == nil && endError() == nil && description.utf16.count <= 255
    }

    func hasChanges(from event: Mezon_Api_EventManagement) -> Bool {
        title != event.title || description != event.description_p || logoURL != event.logo ||
        channelVoiceId != event.channelVoiceID || locationAddress != event.address ||
        channelId != event.channelID || repeatType != event.repeatType ||
        startSeconds != event.startTimeSeconds || endSeconds != event.endTimeSeconds
    }

    func createRequest(clanId: Int64, creatorId: Int64) -> Mezon_Api_CreateEventRequest {
        var request = Mezon_Api_CreateEventRequest()
        request.clanID = clanId
        request.creatorID = creatorId
        request.title = title
        request.description_p = description
        request.logo = logoURL
        request.channelVoiceID = channelVoiceId
        request.channelID = channelId
        request.address = locationAddress
        request.startTimeSeconds = startSeconds
        request.endTimeSeconds = endSeconds
        request.repeatType = repeatType
        request.isPrivate = locationType == .external
        return request
    }

    func updateRequest(clanId: Int64, original: Mezon_Api_EventManagement) -> Mezon_Api_UpdateEventRequest {
        var request = Mezon_Api_UpdateEventRequest()
        request.eventID = original.id
        request.clanID = clanId
        request.creatorID = original.creatorID
        request.title = title == original.title ? "" : title
        request.description_p = description
        request.logo = logoURL
        request.channelVoiceID = channelVoiceId == original.channelVoiceID ? 0 : channelVoiceId
        request.channelID = channelId
        request.channelIDOld = original.channelID
        request.address = locationAddress == original.address ? "" : locationAddress
        request.startTimeSeconds = startSeconds == original.startTimeSeconds ? 0 : startSeconds
        request.endTimeSeconds = endSeconds == original.endTimeSeconds ? 0 : endSeconds
        request.repeatType = repeatType == original.repeatType ? 0 : repeatType
        return request
    }

    func applying(to original: Mezon_Api_EventManagement) -> Mezon_Api_EventManagement {
        var event = original
        event.title = title
        event.description_p = description
        event.logo = logoURL
        event.channelVoiceID = channelVoiceId
        event.channelID = channelId
        event.address = locationAddress
        event.startTimeSeconds = startSeconds
        event.endTimeSeconds = endSeconds
        event.repeatType = repeatType
        return event
    }

    func repeatOptions(calendar: Calendar = .current, locale: Locale = LanguageManager.shared.current.locale) -> [(Int32, String)] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: start)
        formatter.dateFormat = "MMMM"
        let month = formatter.string(from: start)
        var options: [(Int32, String)] = [
            (EventRepeatType.doesNotRepeat, L(L10n.EventEditor.repeatNone)),
            (EventRepeatType.weekly, L(L10n.EventEditor.repeatWeekly, day)),
            (EventRepeatType.everyOtherWeek, L(L10n.EventEditor.repeatOther, day)),
            (EventRepeatType.monthly, L(L10n.EventEditor.repeatMonthly, calendar.component(.weekdayOrdinal, from: start), day)),
            (EventRepeatType.annually, L(L10n.EventEditor.repeatAnnually, month, calendar.component(.day, from: start)))
        ]
        if !calendar.isDateInWeekend(start) { options.append((EventRepeatType.everyWeekday, L(L10n.EventEditor.repeatWeekday))) }
        return options
    }
}
