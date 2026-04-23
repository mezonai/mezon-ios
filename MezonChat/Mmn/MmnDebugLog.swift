import Foundation

enum MmnDebugLog {
    static func line(_ s: @autoclosure () -> String) {
        #if DEBUG
        print("[MMN]", s())
        #endif
    }
}
