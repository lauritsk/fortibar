# FortiBar

FortiBar is a macOS menu bar front end for `openfortivpn`. The menu shows VPN state and provides connect, disconnect, SAML login, logs, and settings controls. Configuration lives in a separate native Settings window. The app stores the VPN password in the login Keychain and asks a root launch daemon to start or stop the VPN engine. The app itself refuses to run as root.

The current development build supports Homebrew and MacPorts installations of `openfortivpn`. A release build only accepts a bundled binary.

## Requirements

- macOS 26 or newer
- Xcode 26 or newer, not only the Command Line Tools
- An Apple Development or Developer ID signing identity
- `openfortivpn` for Debug builds

Install the development VPN engine with:

```sh
brew install openfortivpn
```

FortiBar supports password and SAML authentication. It does not support standalone OTP prompts, client certificates, or custom `openfortivpn` options yet.

## Build and run

1. Open `FortiBar.xcodeproj` in Xcode.
2. Select the `FortiBar` project, then choose the same development team for the `FortiBar` and `FortiBarHelper` targets. The helper rejects unsigned and ad hoc signed clients.
3. Build the `FortiBar` scheme in Debug.
4. Copy `FortiBar.app` to `/Applications` and launch that copy. Apple recommends `/Applications` for apps that register boot-time launch daemons.
5. Click the FortiBar menu bar icon, then click `Set Up Helper`.
6. Open System Settings > General > Login Items if FortiBar takes you there. Approve the FortiBar background item with an administrator account.
7. Open `Settings...` from the menu bar panel. Enter the VPN details and choose Password or SAML.
8. Connect from the menu bar panel. For SAML, FortiBar opens the URL printed by `openfortivpn` in the default browser. Complete the login there. The browser redirects to the loopback listener on port 8020.

The helper status changes to `Ready` after macOS approves and bootstraps it. Approval can take a few seconds to appear in the app.

If the helper executable or launchd property list changes, unregister the old background item before registering the new build. Disconnect, click `Remove` in FortiBar, rebuild, copy the new app to `/Applications`, and register it again. `SMAppService` requires re-registration after helper updates.

Do not launch FortiBar with `sudo`. macOS launches only `FortiBarHelper` as root.

## Tests

The repository includes an Xcode unit test target. A shell script runs the same validation checks and type-checks the app and helper with Command Line Tools:

```sh
./scripts/test.sh
```

For the complete build and test suite, use Xcode or:

```sh
xcodebuild -project FortiBar.xcodeproj \
  -scheme FortiBar \
  -configuration Debug \
  test
```

A development team may need to be supplied with `DEVELOPMENT_TEAM=YOUR_TEAM_ID` on a clean machine.

`project.yml` is the source for the checked-in Xcode project. Regenerate it after changing target structure with:

```sh
brew install xcodegen
xcodegen generate
```

XcodeGen is not needed to build the checked-in project.

## Security design

Apple deprecated `SMJobBless` in macOS 13. FortiBar uses `SMAppService.daemon(plistName:)`, with the launchd property list under `Contents/Library/LaunchDaemons` and the helper under `Contents/Library/LaunchServices`. An administrator approves the daemon in System Settings.

The GUI talks to one privileged Mach service through `NSXPCConnection`. Both peers set code-signing requirements before accepting messages. Requirements pin each peer's expected signing identifier and signing team. The helper also rejects clients running as root.

The privileged protocol has only three operations: connect, disconnect, and status. Connect accepts a validated hostname, port, authentication method, and the fields required by that method. It cannot pass executable paths, configuration paths, environment variables, shell commands, or unrestricted `openfortivpn` options. The helper starts `openfortivpn` directly with `Process`; it never invokes a shell.

FortiBar passes `--config=/dev/null` so a root process never reads the user-writable Homebrew configuration. For password login, it passes the password over XPC and writes it to `openfortivpn` standard input. The password does not appear in the process arguments, configuration files, UserDefaults, or logs. The app stores it as a generic-password Keychain item accessible only while the Keychain is unlocked. Host, port, username, authentication method, and SAML realm use UserDefaults.

For SAML, the helper permits only `--saml-login=8020` and an optional validated realm. `openfortivpn` binds its callback server to `127.0.0.1`. The unprivileged app waits for the authentication URL in the VPN log, checks its HTTPS host, port, path, and query, then opens it with `NSWorkspace`. The root helper never starts a browser.

Debug builds define `FORTIBAR_ALLOW_HOMEBREW`. This allows these fixed paths:

- `/opt/homebrew/bin/openfortivpn`
- `/usr/local/bin/openfortivpn`
- `/opt/local/bin/openfortivpn`

Homebrew files are normally writable by the local administrator. That is acceptable only for local development. A distributed root helper must not execute them. Release builds require `Contents/Resources/openfortivpn` inside the signed app.

To ship `openfortivpn`, build it for the supported architectures and put it at `FortiBar.app/Contents/Resources/openfortivpn` before the app signing step. Bundle every non-system dynamic library with app-relative install names, sign each nested Mach-O file, preserve the upstream license notices, harden the runtime, and notarize the final app. Do not copy a Homebrew binary that still links to libraries under `/opt/homebrew`.

## VPN engine behavior checked

The implementation was checked against upstream `openfortivpn` and local version 1.24.1. Upstream says macOS needs elevated privileges to start `/usr/sbin/pppd`, change routes, and update DNS. Its password reader reads from standard input when no password option is present. Its SAML mode listens on loopback, prints an HTTPS authentication URL, and accepts the Fortinet redirect containing the session ID. The helper detects the upstream `Tunnel is up and running.` log line and treats process termination as disconnection or failure.

Password login uses this fixed argument list:

```text
openfortivpn --config=/dev/null --username=<username> <host>:<port>
```

SAML login uses:

```text
openfortivpn --config=/dev/null --saml-login=8020 [--realm=<realm>] <host>:<port>
```

The helper supplies passwords on standard input. It sends SIGINT for normal disconnect so `openfortivpn` can restore routes and DNS before exiting.

## Sources reviewed

- Apple, [`SMAppService`](https://developer.apple.com/documentation/servicemanagement/smappservice)
- Apple, [`daemon(plistName:)`](https://developer.apple.com/documentation/servicemanagement/smappservice/daemon(plistname:))
- Apple, [`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register())
- Apple, [Updating your app package installer to use the new Service Management API](https://developer.apple.com/documentation/servicemanagement/updating-your-app-package-installer-to-use-the-new-service-management-api)
- Apple SDK headers for `NSXPCConnection.setCodeSigningRequirement(_:)` and `NSXPCListener.setConnectionCodeSigningRequirement(_:)`
- Upstream [`openfortivpn` README and source](https://github.com/adrienverge/openfortivpn)
- Local `openfortivpn(1)` manual for version 1.24.1
