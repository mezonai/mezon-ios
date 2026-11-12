# Loading UI test environments

`UITestConfiguration` resolves each variable in this order:

1. The test runner process environment (scheme, or `TEST_RUNNER_*` passed to `xcodebuild`).
2. `MezonChat/_Tests/uitest.env`.

Running `source` in a terminal does not affect Xcode. Building the app does not read the file. Run a UI test so the test runner loads `uitest.env`.

This is not the environment used when you Run the app, and it is not `app.launchEnvironment`. Do not commit a real email or OTP into the shared scheme `MezonChat.xcodeproj/xcshareddata/xcschemes/MezonChat.xcscheme`.

| Test runner variable | When unset |
| --- | --- |
| `UITEST_EMAIL` | login tests that need an account are skipped |
| `UITEST_OTP` | `testEmailOTPLoginSucceeds` is skipped |
| `UITEST_INVALID_OTP` | `111111` |
| `UITEST_CLAN_ID` | channel tests are skipped |
| `UITEST_CHANNEL_ID` | none; the test finds the channel by name |
| `UITEST_CHANNEL_NAME` | `general` |

Set `UITEST_CLAN_ID` to the positive numeric ID of the automation clan. The test account must be a member of that clan.

Do not set `UITEST_LOGIN_MODE` here. `LoginScreen` passes that variable to the app at launch (`0` SMS, `1` email OTP, `2` password).

## Xcode

Create `MezonChat/_Tests/uitest.env`, then run the UI test (Product → Test, or the test diamond). No scheme setup is required for this file.

The Environment Variables field does not import a file. Use it only when a value must override `uitest.env`:

1. Scheme **MezonChat** → **Edit Scheme** → **Test** → **Arguments**.
2. Uncheck **Use the Run action's arguments and environment variables**. The shared scheme has this enabled, so Test uses the Run environment until you uncheck it.
3. Under **Environment Variables**, add the names from the table above. Do not add the `TEST_RUNNER_` prefix.

Values entered in the shared scheme are committed. To keep them on your machine, duplicate the scheme and uncheck Shared. That copy lives in `xcuserdata/`, which Git ignores.

## File format

`MezonChat/_Tests/uitest.env` is listed in `.gitignore`. The same file works for Xcode and `xcodebuild`. Keep the OTP as a string so a leading zero is preserved.

```sh
TEST_RUNNER_UITEST_EMAIL=mezon-test@example.com
TEST_RUNNER_UITEST_OTP=000000
TEST_RUNNER_UITEST_INVALID_OTP=111111
TEST_RUNNER_UITEST_CLAN_ID=
```

## Terminal and CI

`xcodebuild` also forwards variables prefixed with `TEST_RUNNER_` and strips that prefix. Those values override `uitest.env`. `source` is unnecessary when the file is present, because the test runner reads it.

On CI, store the secrets in the CI system and export the `TEST_RUNNER_*` names before `xcodebuild`. Do not print the secrets in the log.

## GitHub Actions

`.github/workflows/uitests.yml` runs on demand: **Actions** → **iOS UI Tests** → **Run workflow**. It stops before building if a required value is missing, so a run never passes with every test skipped.

| Name | Kind | Value |
| --- | --- | --- |
| `IOS_SECRETS_SWIFT_B64` | secret | `base64 -i MezonChat/Networking/Secrets.swift` |
| `IOS_GOOGLE_SERVICE_INFO_B64` | secret | `base64 -i MezonChat/GoogleService-Info.plist` |
| `UITEST_EMAIL` | secret | test account email |
| `UITEST_OTP` | secret | fixed OTP of the test account |
| `UITEST_CLAN_ID` | variable | automation clan ID |
| `UITEST_CHANNEL_ID` | variable | optional |
| `UITEST_CHANNEL_NAME` | variable | optional, defaults to `general` |

The repository is public, so Actions logs are public. Use an account and clan that exist only for automation.
