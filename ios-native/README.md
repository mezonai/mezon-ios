To use this in a Swift project `Bridging-Header.h`:
```
#import "MezonWrapper.h"
```

Usage in Swift
```
class MezonService {
    let mezon = MezonWrapper(host: "172.29.223.11", port: 4433)

    func sendMessage(text: String) {
        if let data = text.data(using: .utf8) {
            mezon?.sendData(data)
        }
    }
    
    // You might run this on a background timer or DisplayLink
    func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.mezon?.poll()
        }
    }
}
```