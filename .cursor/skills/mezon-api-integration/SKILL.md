---
name: mezon-api-integration
description: Integrate new Mezon API endpoint from Proto. Use when adding ListX, CreateX, or other gRPC/HTTP Proto API calls.
---

# Mezon API Integration

## 1. Verify Proto exists

- Generated types: `Mezon_Api_*Request`, `Mezon_Api_*Response` trong `Generated/api/api.pb.swift`
- Nếu chưa có: chạy `bash scripts/gen-proto.sh` từ mezon-protocol

## 2. Add to MezonHTTPClient

```swift
func someMethod(param: Type, token: String) async throws -> Mezon_Api_ResponseType {
    var req = Mezon_Api_SomeRequest()
    req.field = param
    let response: Mezon_Api_ResponseType = try await postProto(
        path: "/mezon.api.Mezon/MethodName",
        message: req,
        auth: .bearer(token)
    )
    return response
}
```

## 3. Map to Domain

- Tạo `mapApiToDomain(_ api: Mezon_Api_X) -> DomainModel`
- Xử lý content JSON `{"t":"..."}` nếu API trả structured content

## 4. Use in ViewModel

```swift
guard let token = context.session?.token else { return }
let response = try await MezonHTTPClient.shared.someMethod(..., token: token)
items = response.items.map { mapApiToDomain($0) }
```
