<h1 align="center">BoardBar</h1>

<p align="center">
  <em>Your GitHub Projects board, one click away in the menu bar.</em>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange?logo=swift">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-blue">
</p>

BoardBar is a menu-bar macOS app that mirrors GitHub Projects v2 board views as
Kanban boards in a popover. Paste a board URL, paste a token, glance at the
board, click a card to open it on github.com.

Several boards can be configured, and a tab switches between them. A tab is one
saved *view*, not one project, so "Main Board" and "My Items" of the same
project are two tabs at no extra cost. With fewer than two configured there is
no tab bar at all.

Built as a personal tool, and read-only by design: it never mutates project
state — no dragging between columns, no assigning, no commenting. A mirror can
beat github.com on latency and ambient presence; a half-featured editor cannot
beat it on features.

## Requirements

- macOS 14+
- A GitHub account with access to the Projects v2 board you want to mirror
- Xcode 26 / Swift 6 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) to build
- An Apple Developer Program membership to sign it (see [Build](#build))

## Setup

1. **Create a token.** Either a classic personal access token with the
   **`read:project`** and **`repo`** scopes, or a fine-grained token with
   read access to the projects and repositories involved. Generate one at
   [github.com/settings/tokens](https://github.com/settings/tokens).
2. **Open Settings** from the popover and paste the token. It goes to the
   Keychain, never to disk in the clear, and one token serves every board.
3. **Add a board** by pasting the URL of a project *view* — the address bar
   while you are looking at the board, e.g.
   `https://github.com/orgs/acme/projects/7/views/1`, or
   `https://github.com/users/<you>/projects/3/views/1` for a personal project.
   A repository issues list is not a project board, and BoardBar will say so.
4. Add more views to get more tabs. The same project's "Main Board" and
   "My Items" are two perfectly good tabs.

Left-click the menu-bar icon for the board; click any card to open it on
github.com.

## Install

Download the latest `BoardBar.dmg` from the
[releases page](https://github.com/Haddadmj/BoardBar/releases), open it, and drag
**BoardBar** into **Applications**. Releases are signed with a Developer ID and
notarized by Apple, so they open with a normal double-click.

Then follow [Setup](#setup) to add a token and a board.

## Build

The `.xcodeproj` is **generated** and not tracked, so a fresh clone needs
XcodeGen before it will open:

```sh
brew install xcodegen
xcodegen generate
open BoardBar.xcodeproj
```

`project.yml` is the only hand-edited project file. `Info.plist` and
`BoardBar.entitlements` are generated from it too — editing them directly is
pointless, since the next `xcodegen` run overwrites both.

Signing needs an Apple Developer Program membership: the App Group entitlement
that the app and its future widget share is not available to free personal
teams.

## Release

```sh
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"
export AC_KEYCHAIN_PROFILE="notary"   # see release.sh header for one-time setup
./scripts/release.sh                  # → .build/dist/BoardBar.dmg
```

`release.sh` regenerates the project, archives, exports a Developer ID build,
packages a DMG, then notarizes and staples it.

Unlike a plain menu-bar binary there is no unsigned fallback, and that is the
App Group's doing: a sandboxed app carrying one needs a real provisioning
profile, so an ad-hoc signature produces a bundle that runs on the machine that
built it and nowhere else. The script asks for `DEVELOPER_ID` up front rather
than producing that bundle and letting you discover the problem on someone
else's Mac.

## App icon

`BoardBar/Assets.xcassets/AppIcon.appiconset` is generated, not drawn by hand.
The PNGs are committed because they are build inputs, and
`Tools/make-appicon.swift` is where they came from:

```sh
swift Tools/make-appicon.swift
```

## Tests

```sh
cd BoardBarCore && swift test
```

All logic lives in the `BoardBarCore` package — URL parsing, GraphQL decoding,
poll cadence, base-direction resolution, staleness. It has no UI dependency, so
the suite runs in well under a second and needs no provisioning profile.

## Architecture

The menu-bar app is the only network client. It polls, writes the result to an
App Group container keyed by board ID, and a widget (not yet built) will read
that file without ever opening a socket. Board traffic stays at one poll no
matter how many surfaces show it.

Cadence backs off: every 5 minutes while the popover has been opened in the last
hour, every 30 otherwise. That is also the whole of the per-tab cadence — only
the selected tab is told the popover was opened, so a background tab is already
a board nobody has looked at recently, which is what the policy calls idle.

The menu-bar icon reflects the selected tab only. Worst-across-all-tabs sounds
more informative and is not: a background tab polls on a 30-minute cadence
against a 30-minute staleness threshold, so it sits permanently at the boundary
and the icon would dim more or less constantly.

## Right-to-left

Cards are mixed-direction — Arabic issue titles alongside Latin issue numbers,
repository names and labels. The rule, carried over from the Qurba project:
**set the base writing direction, never set alignment.** Alignment gets
logically swapped underneath you and cannot be fixed from that side.

Unlike Qurba, direction is **not** forced globally. BoardBar's own chrome is
Latin, so direction is resolved per text run from the first strong directional
character.

## Configuration

- Board URLs — `UserDefaults`, under `boardURLs`, in tab order. They name
  boards, not credentials. v1's single `boardURL` is read once to seed the list
  and then left alone, so rolling back to a v1 build loses nothing.
- Token — Keychain, reached only through the `TokenStore` protocol. One token
  for every board: boards on one account share a credential, and a per-board
  token is a second thing to get wrong for no gain.

## License

[MIT](LICENSE) © Mohammad Al-Haddad
