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


## 🔧 Technology Stack

| Layer | Technology |
|-------|------------|
| **Language** | Swift 5.9 |
| **UI** | UIKit, Auto Layout, Combine |
| **Architecture** | MVVM + Coordinator |
| **Networking** | URLSession, WebSocket (binary Protobuf) |
| **Serialization** | SwiftProtobuf |
| **State** | Combine publishers & subjects |
| **Project** | XcodeGen, Swift Package Manager |
| **Design** | Adaptive scaling (ScreenScale), theming |

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

Managed via **Swift Package Manager**. Xcode resolves packages automatically.

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

