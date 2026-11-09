# Accessibility identifiers

Apply these guidelines when adding or changing screens, controls, list items, or interaction flows in `MezonChat`. Add identifiers as part of feature development rather than waiting for UI tests. Do not expand non-UI tasks solely to add identifiers.

Scope: developers declare and attach identifiers to the necessary elements on each screen. The automation team owns page objects, selectors, and test cases. Do not create or modify automation tests as part of this workflow unless explicitly requested.

All paths below are relative to the repository root.

## Naming

- Read `MezonChat/Core/Accessibility/AccessibilityID.swift` first. It is the shared source of identifiers for the app and UI tests; keep it independent of UIKit.
- Reuse existing constants. Add constants or functions to the appropriate feature enum for new elements. Reference these constants in app code instead of scattering identifier literals.
- Follow the e2e naming style: `mention-input`, `message-item-<messageId>`, `auth-login-email`. The current helper converts `makeAccessibilityID("mention.input")` to `mention-input`. Do not change conventions or rename existing identifiers unless the task requires it.
- Use stable data IDs as suffixes for repeated items. Do not use message contents, email addresses, OTPs, translated names, cell positions, or UUIDs generated on each render. Indices are appropriate only for fixed slots such as OTP digits.
- Preserve the trailing hyphen returned by `makeAccessibilityID(key, id: "")`; test prefix queries and ID extraction depend on it.
- If the e2e source is available, reuse matching keys where their meaning is the same. Do not require another repository checkout for iOS development or claim web parity without checking.

## Attaching identifiers

- Cover the main screen of a flow, inputs, buttons, menu actions, interactive list items, and result elements used for assertions. Decorative images, spacers, and separators do not all need identifiers.
- Attach identifiers to the actual interactive or exposed accessibility element. For UIKit, use `.identified(by:)` or `accessibilityIdentifier`; for Texture, use the actual node/control.
- Do not set `isAccessibilityElement = true` on a container just to attach an identifier: this can hide its children. Preserve meaningful VoiceOver labels and traits; never replace labels with technical IDs.
- In normal launches, set `accessibilityValue` only when the value conveys meaningful information to VoiceOver users. If XCUITest needs to read raw IDs or internal state through `accessibilityValue`, set those values only when the app is launched with an explicit UI test argument.
- For UIKit controls hosted inside Texture, verify that children appear in the accessibility tree. Refer to `MessageActionSheet` and `ChatContainerNode` before changing `accessibilityElements`; do not discard other accessible elements.
- For reusable cells/nodes, update identifiers and state whenever data is bound, and clear stale values when no longer applicable. See `MessageTextContentNode.updateAccessibility`.
- Keep identifiers unique within their screen or item scope. If a child identifier repeats across items, expose a stable identifier on the parent so the automation team can locate the correct instance.

## Developer verification and handoff

- Check that each affected screen exposes identifiers for its necessary interactive controls and observable results, including relevant loading, empty, error, and success states.
- Run appropriate syntax, typecheck, or build checks. When a simulator is available, inspect the accessibility tree to confirm identifiers are exposed on the intended elements. No automated test cases are required by this workflow.
- Preserve existing identifiers where possible. If an identifier must change, report the old and new values so the automation team can update its selectors.
- Report identifiers added or changed, their screen/element mapping, and checks actually performed. State when accessibility-tree verification was not performed; typechecking alone does not prove that Recorder can discover an element.
