import Foundation

enum MezonConstants {

    enum ChannelType: Int32 {
        case channel = 1       // CHANNEL_TYPE_CHANNEL
        case group = 2         // CHANNEL_TYPE_GROUP - group DM
        case dm = 3           // CHANNEL_TYPE_DM - direct message (1-1)
        case forum = 5        // CHANNEL_TYPE_FORUM
        case streaming = 6    // CHANNEL_TYPE_STREAMING
        case thread = 7       // CHANNEL_TYPE_THREAD
        case app = 8          // CHANNEL_TYPE_APP
        case announcement = 9 // CHANNEL_TYPE_ANNOUNCEMENT
        case mezonVoice = 10  // CHANNEL_TYPE_MEZON_VOICE
    }
}
