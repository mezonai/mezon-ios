---
name: swift-debug-build
description: Debug Swift/iOS build failures. Use when xcodebuild fails, compilation errors, or missing symbols.
---

# Debug Build Issues

## Common fixes

1. **Missing file**: Thêm vào project.pbxproj (PBXFileReference + PBXBuildFile + Sources)
2. **Proto type mismatch**: Int32 vs Bool - dùng `== 0` thay `!intVal`
3. **MainActor isolation**: Thêm `@MainActor` hoặc `Task { @MainActor in }` khi mutate @Published
4. **Closure capture**: Dùng `[weak self]`, `self.` rõ ràng khi compiler yêu cầu

## Build command

```bash
cd /Users/thomas/Documents/Swift/mezon-ios
xcodebuild -scheme MezonChat -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -50
```

## Add new file to Xcode

1. PBXFileReference
2. PBXBuildFile
3. PBXGroup (nếu cần group mới)
4. PBXSourcesBuildPhase files array
