import Foundation

enum MezonConstants {

    enum ChannelType: Int32 {
        case channel = 1
        case group = 2
        case dm = 3
        case forum = 5
        case streaming = 6
        case thread = 7
        case app = 8
        case announcement = 9
        case mezonVoice = 10
    }

    enum ChannelStreamMode: Int32 {
        case channel = 2
        case group = 3
        case dm = 4
        case clan = 5
        case thread = 6
    }

    enum MessageCode: Int32 {
        case buzz = 8
    }
}
