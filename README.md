# FortiBar

FortiBar is a macOS menu bar app for `openfortivpn`. It supports password and SAML authentication, stores passwords in the login Keychain, and runs the VPN through a privileged helper.

FortiBar does not yet support standalone OTP prompts, client certificates, or custom `openfortivpn` options.

## Requirements

- macOS 26 or newer
- Xcode 26 or newer
- [Homebrew](https://brew.sh/)
- An Apple Development or Developer ID signing identity

Install Mise, then let it install the development tools and `openfortivpn`:

```sh
brew install mise
mise bootstrap
```

Release builds require a bundled `openfortivpn` binary.

## Build and use

1. Open `FortiBar.xcodeproj` in Xcode.
2. Set the same development team on the `FortiBar` and `FortiBarHelper` targets.
3. Build the `FortiBar` scheme in Debug.
4. Copy `FortiBar.app` to `/Applications` and launch it.
5. Open the menu bar app and click `Set Up Helper`.
6. If prompted, approve FortiBar under System Settings > General > Login Items.
7. Open `Settings...`, enter the VPN details, and choose Password or SAML authentication.
8. Connect from the menu bar.

For SAML, complete the login in the browser that FortiBar opens.

After changing the helper executable or launchd property list, click `Remove` in FortiBar before installing and registering the new build.

Do not launch FortiBar with `sudo`. macOS runs only `FortiBarHelper` as root.

## Development

Run the same checks as CI:

```sh
mise run ci
```

Run only the Xcode build and unit tests with `mise run test`.

`project.yml` defines the generated Xcode project. `mise bootstrap` creates it on initial setup. After changing the target structure, regenerate it with:

```sh
mise run generate
```

Run `mise tasks` to list the available commands. When changing tool versions in `mise.toml`, refresh their checksums with `mise lock`.
