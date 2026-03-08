# Mezon for iOS

**Native Swift client for Mezon – the best Discord alternative for team communication.**

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-16.0+-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ✨ Overview

Mezon iOS is a **native Swift** implementation of the [Mezon](https://mezon.ai) platform. It delivers a fast, modern chat experience built from the ground up for iPhone and iPad, with enterprise-grade real-time messaging and a clean, extensible architecture.

Part of the [Mezon ecosystem](https://github.com/mezonai/mezon) – the Live, Work, and Play platform.

---

## 🏗 Architecture

### High-Level Patterns

| Pattern | Role |
|--------|------|
| **MVVM** | ViewModel handles business logic; View (ViewController) binds via Combine |
| **Coordinator** | Navigation and flow orchestration isolated from ViewControllers |
| **Repository** | Data abstraction over API and local storage |
| **Centralized Store** | Domain stores (Auth, Clans, Channels, Messages) with Combine reactivity |
| **Layered** | Application → Core → Domain → Features → Networking → Persistence |

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    APPLICATION LAYER                              │
│  SceneDelegate → AppCoordinator → AuthCoordinator / MainCoordinator│
└─────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────────────────────────────────────────────────┐
│                    CORE / CONTEXT                                │
│  AppContext  ──→  SharedAccountContext  ──→  SharedDataStore     │
│  (session, user)     (injection point)      AuthStore            │
│                                            ClansStore            │
│                                            ChannelsStore         │
│                                            MessagesStore         │
└─────────────────────────────────────────────────────────────────┘
                                    │
┌─────────────────────┐  ┌─────────────────────┐  ┌──────────────┐
│     NETWORKING      │  │    PERSISTENCE       │  │   FEATURES   │
│  MezonHTTPClient    │  │  MezonPostbox        │  │  ViewModel   │
│  MezonSocket        │  │  (SQLite3)           │  │  ViewController│
│  (REST + WebSocket) │  │  UserDefaults        │  │  (MVVM)      │
└─────────────────────┘  └─────────────────────┘  └──────────────┘
```

### MVVM Flow

```
View (ViewController)  ←──Combine──→  ViewModel  ←──→  Store / Repository
       ↑ sink($published)                    ↑
       └────────────────────────────────────┘
```

---

## 📁 Project Structure

```
MezonChat/
├── Application/           # App lifecycle & coordination
│   ├── AppDelegate.swift
│   ├── AppCoordinator.swift
│   ├── SceneDelegate.swift
│   └── SplashViewController.swift
│
├── Core/                  # Shared infrastructure
│   ├── Base/              # Base classes
│   │   ├── BaseCoordinator.swift
│   │   ├── BaseViewController.swift
│   │   └── BaseViewModel.swift
│   ├── Context/           # Global state
│   │   ├── AppContext.swift
│   │   ├── SharedAccountContext.swift
│   │   ├── SharedDataStore.swift
│   │   └── Store/
│   │       ├── AuthStore.swift
│   │       ├── ClansStore.swift
│   │       ├── ChannelsStore.swift
│   │       └── .....swift
│   ├── Extensions/
│   ├── Localization/      # L10n, LanguageManager
│   ├── Storage/           # MezonPostbox (SQLite)
│   ├── Theme/             # AppTheme, ThemeManager
│   ├── UI/                # ImageUtilities, Toast
│   └── Utils/             # Constants, AppLogger, ScreenScale
│
├── Domain/                # Business models & contracts
│   ├── Models/            # User, Channel, Message, Clan, ....
│   └── Repositories/      # Protocol definitions
│
├── Features/              # Feature modules
│   ├── Auth/              
│   ├── Clans/             
│   ├── Main/              
│   ├── Messages/         
│   ├── Profile/
│   └── ....../
│
├── Generated/             # Protobuf-generated Swift
│   ├── api/
│   └── rtapi/
│
├── Networking/            # HTTP, WebSocket, Session
│   ├── MezonHTTPClient.swift
│   ├── MezonSocket.swift
│   ├── MezonSession.swift
│   ├── MezonConfig.swift
│   └── SessionRefreshManager.swift
│
└── Resources/             # Assets, localization, Info.plist
    ├── Assets.xcassets
    ├── Images.xcassets    # Icons
    └── Info.plist
```

---

## 🔧 Technology Stack

### Core Technologies

| Category | Technology | Why |
|----------|------------|-----|
| **UI Framework** | UIKit | Mature Coordinator support, complex navigation, iOS 15 compatibility |
| **Reactive** | Combine | `@Published`, `sink`, publishers for Store ↔ ViewModel ↔ View binding |
| **Concurrency** | async/await | Clean API calls, token refresh, no callback hell |
| **Serialization** | SwiftProtobuf | Binary protocol for API & WebSocket, type-safe |
| **Persistence** | SQLite3 (MezonPostbox) | Offline-first, lightweight, no ORM, native iOS |
| **Persistence** | UserDefaults | Session, theme, language settings |
| **Project** | XcodeGen | Deterministic project generation |

### Networking

- **REST API**: `URLSession` + async/await
- **Real-time**: `URLSessionWebSocketTask` with binary Protobuf
- **Session**: Auto-refresh via `SessionRefreshManager`

### State Management

- **ObservableObject** + **@Published** for reactive updates
- **SharedDataStore** aggregates domain stores
- **SharedAccountContext** injects to Coordinators/ViewModels
- **MezonPostbox** hydrates state on app launch

---

## 🚀 Quick Start

### Requirements

| Requirement | Version |
|-------------|---------|
| **Xcode** | 16.0+ |
| **Swift** | 5.9 |
| **iOS** | 15.0+ |
| **macOS** | 14.0+ (for development) |

### Installation

```bash
# Clone the repository
git clone https://github.com/mezonai/mezon-ios.git
cd mezon-ios

# Generate Xcode project (XcodeGen required)
brew install xcodegen
xcodegen generate

# Configure secrets for production (optional, dev uses default keys)
cp MezonChat/Networking/Secrets.example.swift MezonChat/Networking/Secrets.swift
# Edit Secrets.swift and add your prod server key
```

### Open & Run

1. Open `MezonChat.xcodeproj` in Xcode
2. Select your development team in **Signing & Capabilities**
3. Choose a simulator or device and press **⌘R**

---

## 🔌 Protobuf Code Generation

The app uses Mezon's binary protocol. Regenerate Swift types from [mezon-protocol](https://github.com/mezonai/mezon-protocol) when the API changes:

```bash
# Install tools
brew install protobuf swift-protobuf protoc-gen-grpc-swift

# Clone mezon-protocol (adjust path in script if needed)
# Default path: /Users/thomas/Documents/Swift/mezon-protocol

# Generate
bash scripts/gen-proto.sh
```

---

## 🌍 Environments

| Environment | API Host | Use Case |
|-------------|----------|----------|
| **Dev** | dev-mezon.nccsoft.vn | Development, Debug builds |
| **Prod** | api.mezon.ai | Release, App Store |

Environment is selected automatically:

- **Debug** → Dev
- **Release** → Prod

---

## 🔐 Secrets

Production API key is kept out of version control:

1. Copy `Secrets.example.swift` → `Secrets.swift`
2. Set `prodServerKey` to your production server key
3. `Secrets.swift` is in `.gitignore` and will not be committed

---

## 📦 Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [SwiftProtobuf](https://github.com/apple/swift-protobuf) | 1.28.0 | Protobuf serialization |

| System | Purpose |
|--------|---------|
| **libsqlite3.tbd** | MezonPostbox persistence |

Managed via **Swift Package Manager** + **XcodeGen**.

---

## 🤝 Contributing

Contributions are welcome! See the main [Mezon repo](https://github.com/mezonai/mezon) for:

- Bug reports and feature requests
- Development guidelines
- Community and support

---

## 📄 License

MIT License – free for personal and commercial use.

---

## 🔗 Resources

- **Mezon Platform**: [mezon.ai](https://mezon.ai)
- **Main Repo**: [github.com/mezonai/mezon](https://github.com/mezonai/mezon)
- **App Store**: [Mezon on App Store](https://apps.apple.com/vn/app/mezon/id6502750046)
- **Privacy**: [mezon.ai/privacy](https://mezon.ai/privacy)
- **Terms**: [mezon.ai/terms](https://mezon.ai/terms)

---

**Built with Swift** • Made with ❤️ by the Mezon Team
