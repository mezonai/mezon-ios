---
name: swift-add-feature
description: Add a new feature to Mezon iOS following MVVM + Coordinator. Use when implementing a new screen, flow, or API integration.
---

# Add New Feature to Mezon iOS

## Workflow

1. **Model** - Domain model trong `Domain/Models/` nếu cần
2. **ViewModel** - Kế thừa BaseViewModel, @MainActor, @Published, Task { @MainActor in }
3. **ViewController** - Kế thừa BaseViewController, setupUI, setupBindings, applyTheme
4. **Navigation** - Gọi từ Coordinator hoặc parent VC (push/present)

## Checklist

- [ ] ViewModel: init(dependencies), start()/load(), callbacks cho navigation
- [ ] ViewController: constraints, bind $published, Toast cho errorMessage
- [ ] Theme: UIColor.theme, .sw/.sh/.sf
- [ ] Thêm file vào Xcode project (project.pbxproj) nếu tạo file mới
- [ ] L10n keys nếu có string cần localize

## API integration

- MezonHTTPClient: thêm method nếu proto có sẵn
- Proto: KHÔNG sửa Generated/ - chạy gen-proto.sh khi proto thay đổi
