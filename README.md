<p align="center">
  <img src="MezonChat/Resources/Assets.xcassets/SplashScreen.imageset/mezon_splash.png" alt="Mezon" width="120" />
</p>

<h1 align="center">Mezon iOS</h1>

<p align="center">
  <strong>Native iOS client for the <a href="https://mezon.ai">Mezon</a> messaging platform.</strong><br/>
  High-performance, real-time communication built with AsyncDisplayKit and SwiftSignalKit.
</p>

<p align="center">
  <a href="https://apps.apple.com/vn/app/mezon/id6502750046"><img src="https://img.shields.io/badge/App_Store-Available-blue?logo=apple&logoColor=white" alt="App Store" /></a>
  <img src="https://img.shields.io/badge/iOS-16.0+-000000?logo=apple" alt="iOS 16+" />
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/License-MIT-green" alt="MIT License" />
</p>

---

## Overview

Mezon iOS is the native Apple platform client for [Mezon](https://github.com/mezonai/mezon) — a Live, Work, and Play platform designed for gaming communities, professional teams, and content creators. The app delivers sub-millisecond UI responsiveness through async rendering and a fully reactive data pipeline.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI Rendering** | [AsyncDisplayKit (Texture)](https://texturegroup.org/) 3.2 — async layout & render off main thread |
| **Declarative UI** | ComponentFlow — SwiftUI-like component system for forms & profiles |
| **Reactive** | SwiftSignalKit — custom `Signal`, `ValuePipe`, `Disposable` |
| **Database** | [SQLCipher](https://www.zetetic.net/sqlcipher/) 4.0 — encrypted SQLite via Postbox layer |
| **Networking** | HTTP REST (Protobuf) + WebSocket (real-time) |
| **Serialization** | [swift-protobuf](https://github.com/apple/swift-protobuf) 1.35 |
| **Build** | Xcode 16+ · CocoaPods · Swift Package Manager |
| **Min Target** | iOS 16.0 |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  AppDelegate                                         │
│  Window1 → isLoggedInSignal                          │
│    ├─ authorized   → MezonRootController (TabBar)    │
│    └─ unauthorized → LoginViewController             │
├─────────────────────────────────────────────────────┤
│  SharedAccountContext (app-wide)                      │
│  mainWindow · theme · controller factories            │
├─────────────────────────────────────────────────────┤
│  AccountContext (per-account)                         │
│  .account  → Account (Postbox + HTTP + Socket)        │
│  .engine   → MezonEngine                              │
│  session · currentUser · login/logout                 │
├─────────────────────────────────────────────────────┤
│  MezonEngine                                          │
│  .auth · .clans · .channels · .messages · .peers      │
│  .data → EngineData (typed subscribe/get)             │
├─────────────────────────────────────────────────────┤
│  Account                                              │
│  .postbox → Postbox (SQLCipher + ViewTracker)         │
│  .network → MezonHTTPClient (REST + Protobuf)         │
│  .socket  → MezonSocket (WebSocket)                   │
└─────────────────────────────────────────────────────┘
```

## Data Flow

```
Network (HTTP / WebSocket)
    │
    ▼
Postbox.write { tx in tx.addMessages(...) }
    │
    ▼  ViewTracker.replay() → incremental updates
    │
engine.data.subscribe(Item.MessageHistory(channelId:))
    │
    ▼  Signal<[MessageRecord], NoError>
    │
Controller  →  stateSignal()  →  ContainerNode / ComponentHostView
    │
    ▼
ASDisplayNode (async render off main thread)
```

All controllers subscribe directly to reactive Postbox signals. No ViewModel layer — state lives in the controller, UI subscribes via `Signal`.

## Project Structure

```
MezonChat/
│
├── Application/                        App lifecycle
│   ├── AppDelegate.swift               Window, auth flow, scene handling
│   └── SplashViewController.swift      Launch screen
│
├── Core/
│   ├── Account/                        Infrastructure layer
│   │   ├── Account.swift               Postbox + HTTP + Socket
│   │   ├── User.swift                  User model
│   │   └── Message.swift               Message model
│   │
│   ├── AccountContext/                  Dependency injection
│   │   ├── AccountContext.swift         Protocol
│   │   ├── AccountContextImpl.swift    Implementation
│   │   └── SharedAccountContext.swift   App-wide context + factories
│   │
│   ├── MezonEngine/                    Domain API layer
│   │   ├── MezonEngine.swift           Engine + lazy sub-engine registry
│   │   ├── MezonEngine+Auth.swift      Login, OTP, refresh, logout
│   │   ├── MezonEngine+Clans.swift     Clan listing + Postbox views
│   │   ├── MezonEngine+Channels.swift  Channels, DMs
│   │   ├── MezonEngine+Messages.swift  Send, list, history views
│   │   ├── MezonEngine+Peers.swift     Profiles
│   │   └── Data/                       Typed reactive Postbox access
│   │       ├── MezonEngineData.swift   subscribe() / get() API
│   │       ├── ClansData.swift
│   │       ├── ChannelsData.swift
│   │       ├── MessagesData.swift
│   │       └── PreferencesData.swift
│   │
│   ├── Postbox/                        Local persistence (SQLCipher)
│   │   ├── Core/                       Postbox, Transaction, ViewTracker
│   │   ├── Database/                   SqliteDatabase, Table
│   │   ├── Auth/                       AuthRecord, AuthTable
│   │   ├── Channel/                    ChannelRecord, ChannelTable
│   │   ├── Clans/                      ClanRecord, ClanTable
│   │   ├── Messages/                   MessageRecord, MessageTable
│   │   ├── Profile/                    ProfileRecord, ProfileTable
│   │   ├── Settings/                   SettingsTable
│   │   ├── Preferences/                PreferencesTable
│   │   └── Coding/                     PostboxCoding protocol
│   │
│   ├── Display/                        UI framework (145 files)
│   │   ├── ViewController.swift        ASDisplayNode-backed base controller
│   │   ├── NavigationBar.swift         Custom navigation bar
│   │   ├── ListView.swift              High-performance scrolling list
│   │   ├── TabBarControllerImpl.swift  Tab bar controller
│   │   └── Navigation/                 NavigationController, containers
│   │
│   ├── ComponentFlow/                  Declarative UI (34 files)
│   │   ├── Base/                       Component, CombinedComponent, Environment
│   │   ├── Components/                 Text, Image, Button, VStack, HStack,
│   │   │                               List, ScrollComponent, CardComponent
│   │   ├── Gestures/                   Tap, Pan, LongPress
│   │   ├── Host/                       ComponentHostView
│   │   └── Utils/                      ActionSlot, Color, Insets, Size
│   │
│   ├── SSignalKit/                     Reactive framework
│   │   ├── SwiftSignalKit/             Signal, Subscriber, ValuePipe, Queue
│   │   └── SSignalKit/                 Obj-C counterpart
│   │
│   ├── Extensions/                     UIColor+Theme, UIView+Layout
│   ├── Localization/                   L10n, LanguageManager
│   ├── Theme/                          ThemeManager, AppTheme
│   ├── Security/                       KeychainHelper
│   └── Utils/                          Constants, ScreenScale, AppLogger
│
├── Features/
│   ├── Auth/Login/                     Login form (ComponentFlow)
│   ├── Auth/VerifyOTP/                 OTP verification
│   ├── Clans/                          Clan sidebar + channel list + chat
│   ├── Main/                           HomeViewController, MezonRootController
│   ├── Messages/                       Direct messages
│   ├── Profile/                        User profile (ComponentFlow)
│   ├── SendMessageInput/               Message input bar
│   ├── Settings/                       Theme & language settings
│   └── TabBar/                         Placeholder tabs
│
├── Networking/
│   ├── MezonHTTPClient.swift           REST client (JSON + Protobuf)
│   ├── MezonSocket.swift               WebSocket real-time messaging
│   ├── MezonSession.swift              Session model
│   ├── MezonEnvironment.swift          Dev / Prod config
│   └── SessionRefreshManager.swift     Token refresh with retry
│
├── Generated/                          Protobuf generated code
│   ├── api/api.pb.swift
│   └── rtapi/realtime.pb.swift
│
└── Resources/
    ├── Info.plist
    ├── Assets.xcassets/
    └── Images.xcassets/
```

## Key Patterns

### Dependency Injection

Every controller receives `AccountContext` via init. No singletons in feature code.

```swift
let vc = ClanListViewController(context: context)

// Access through DI chain:
context.engine.clans.listClanDescs(token:)
context.account.postbox.write { tx in ... }
context.engine.data.subscribe(Item.ClanList())
```

### Reactive Data Access

```swift
// Continuous updates from local database
context.engine.data.subscribe(
    MezonEngine.EngineData.Item.ClanList()
)
|> deliverOnMainQueue
|> start(next: { clans in
    // UI updates automatically when data changes
})

// One-shot read
context.engine.data.get(
    MezonEngine.EngineData.Item.MessageHistory(channelId: "123")
)
```

### Controller → Signal → UI

Controllers own state and expose a reactive signal. Display nodes subscribe and re-render.

```swift
// Controller holds state, exposes signal
final class ClanListViewController: ViewController {
    private let needsReloadPipe = ValuePipe<Void>()
    func stateSignal() -> Signal<ClanListState, NoError> { ... }
}

// Node subscribes to signal
init(signal: Signal<ClanListState, NoError>, interaction: ClanListInteraction) {
    disposables.add(
        (signal |> deliverOnMainQueue).start(next: { state in
            self.state = state
            self.collectionView.reloadData()
        })
    )
}
```

### ComponentFlow

Declarative component system for static and semi-static screens.

```swift
final class ProfileContentComponent: CombinedComponent {
    static var body: Body {
        let nameText = Child(Text.self)
        let card = Child(CardComponent.self)

        return { context in
            let name = nameText.update(
                component: Text(text: context.component.displayName, font: ..., color: ...),
                availableSize: CGSize(width: contentWidth, height: 100),
                transition: context.transition
            )
            context.add(name.position(CGPoint(x: ..., y: ...)))
            return CGSize(width: context.availableSize.width, height: totalHeight)
        }
    }
}
```

## Performance

| Optimization | Detail |
|-------------|--------|
| **Async Rendering** | All UI layout and rendering happens off the main thread via AsyncDisplayKit |
| **Incremental Updates** | Postbox ViewTracker replays only changed records to active views |
| **Encrypted Persistence** | SQLCipher with WAL mode for concurrent reads and fast writes |
| **Lazy Initialization** | MezonEngine sub-engines created on first access, not at startup |
| **Component Diffing** | ComponentFlow skips re-render when props are equal |
| **Signal Deduplication** | `distinctUntilChanged` prevents redundant UI updates |
| **Pixel-Perfect Layout** | ScreenScale rounds all dimensions to device pixels |
| **Image Caching** | Text component renders to CGImage and caches size measurements |

## Getting Started

### Prerequisites

- Xcode 16.0+
- CocoaPods (`gem install cocoapods`)
- iOS 16.0+ simulator or device

### Build & Run

```bash
git clone https://github.com/mezonai/mezon-ios.git
cd mezon-ios

pod install

open MezonChat.xcworkspace
# Select simulator → Cmd+R
```

### Environment

The app connects to Mezon production by default. To switch to development:

```swift
// In AppDelegate.swift
MezonEnvironment.current = .dev   // or .prod
```

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Texture](https://texturegroup.org/) | ~> 3.2 | Async UI layout and rendering |
| [SQLCipher](https://www.zetetic.net/sqlcipher/) | ~> 4.0 | Encrypted SQLite database |
| [swift-protobuf](https://github.com/apple/swift-protobuf) | 1.35 | Protobuf serialization |

## Contributing

We welcome contributions! See the main [Mezon repository](https://github.com/mezonai/mezon) for contribution guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make changes and ensure the project builds
4. Submit a pull request

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

---

<p align="center">
  <strong>Made with care by the <a href="https://mezon.ai">Mezon</a> team</strong><br/>
  <a href="https://mezon.ai">Website</a> · <a href="https://github.com/mezonai/mezon">GitHub</a> · <a href="https://apps.apple.com/vn/app/mezon/id6502750046">App Store</a>
</p>
