<p align="center">
  <img src="assets/bitpaste-logo.svg" alt="BitPaste logo" width="120">
</p>

# BitPaste

BitPaste is a tiny macOS utility for the annoying kind of paste.

Some apps handle huge clipboard text badly. They freeze, miss characters, or decide the text should become an attachment. BitPaste takes whatever text is on your clipboard and pastes it in smaller pieces, using one keyboard shortcut.

Default shortcut:

```text
command+option+shift+v
```

That shortcut reads your clipboard, splits the text into chunks, pastes each chunk with `command+v`, and then restores your original clipboard.

## Install

```sh
make install
```

The installer builds BitPaste, places the app here:

```text
~/Applications/BitPaste.app
```

and starts it at login with this LaunchAgent:

```text
~/Library/LaunchAgents/app.bitpaste.plist
```

## Permission

BitPaste needs macOS Accessibility permission so it can send paste keystrokes.

Open:

```text
System Settings > Privacy & Security > Accessibility
```

Then add and enable:

```text
~/Applications/BitPaste.app
```

If you previously installed an older local build, remove any stale BitPaste entry from that list and add the app again.

## Configure

The installer creates:

```text
~/.config/bitpaste/config.json
```

Default config:

```json
{
  "chunkSize": 1200,
  "delayMs": 75,
  "initialDelayMs": 120,
  "waitForShortcutReleaseMs": 1000,
  "hotkey": "command+option+shift+v",
  "restoreClipboard": true
}
```

If an app drops chunks or pastes them out of order, increase `delayMs` to `100` or `150`. If the receiving app can handle more text at once, increase `chunkSize`.

Supported hotkey keys are letters, digits, `space`, `tab`, `return`, and `escape`. Supported modifiers are `command`, `control`, `option`, and `shift`.

After changing config, restart BitPaste:

```sh
launchctl kickstart -k gui/$UID/app.bitpaste
```

## Uninstall

```sh
make uninstall
```

This removes the LaunchAgent and installed app. Your config file is left in place.
