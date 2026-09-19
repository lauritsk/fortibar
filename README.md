# FortiBar

FortiBar is a macOS menu bar app for `openfortivpn`. It supports password and SAML authentication, stores passwords in the login Keychain, and runs the VPN through a privileged helper.

FortiBar does not yet support standalone OTP prompts, client certificates, or custom `openfortivpn` options.

## Requirements

- macOS 26 or newer
- Xcode 26 or newer
- [Mise](https://mise.jdx.dev/)
- An Apple Development or Developer ID signing identity

Install the development tools:

```sh
mise bootstrap
```

VPN connections require `openfortivpn` at `/Library/PrivilegedHelperTools/com.lauritsk.FortiBar.openfortivpn`. The file and every directory above it must be owned by root, have no extended ACL, and cannot be writable by group or other users. The executable must use the hardened runtime and a code signature with identifier `com.lauritsk.FortiBar.openfortivpn`, issued to the same Apple development team as FortiBar.

FortiBar deliberately refuses to run a Homebrew executable as root. Development builds can run the interface and tests without the trusted executable, but cannot connect to a VPN. The release installer will need to install the signed executable with the required ownership and permissions.

## Build and use

1. Open `FortiBar.xcodeproj` in Xcode.
2. Set the same development team on the `FortiBar` and `FortiBarHelper` targets.
3. Build the `FortiBar` scheme in Debug.
4. Copy `FortiBar.app` to `/Applications` and launch it.
5. Make sure the trusted `openfortivpn` executable described above is installed before attempting a connection.
6. Open the menu bar app and click `Set Up Helper`.
7. If prompted, approve FortiBar under System Settings > General > Login Items.
8. Open `Settings...`, enter the VPN details, and choose Password or SAML authentication.
9. Connect from the menu bar.

For SAML, complete the login in the browser that FortiBar opens.

After changing the helper executable or launchd property list, click `Remove` in FortiBar before installing and registering the new build.

Do not launch FortiBar with `sudo`. macOS runs only `FortiBarHelper` as root.

## Development

Run the same checks as CI:

```sh
mise run ci
```

Run only the Xcode build and unit tests with `mise run test`.

`project.yml` defines the checked-in Xcode project. After changing the target structure, regenerate it with:

```sh
mise run generate
```

Run `mise tasks` to list the available commands. When changing tool versions in `mise.toml`, refresh their checksums with `mise lock`.
