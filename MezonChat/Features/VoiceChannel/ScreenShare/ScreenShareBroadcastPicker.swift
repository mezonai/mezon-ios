import ReplayKit
import UIKit

final class ScreenShareBroadcastPicker {
    private weak var pickerView: RPSystemBroadcastPickerView?

    func present(in host: UIView) {
        let picker = pickerView ?? makePicker(in: host)
        picker.subviews.compactMap { $0 as? UIButton }.first?.sendActions(for: .allEvents)
    }

    private func makePicker(in host: UIView) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.preferredExtension = ScreenShareBroadcastChannel.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.alpha = 0
        picker.isUserInteractionEnabled = false
        host.addSubview(picker)
        pickerView = picker
        return picker
    }
}
