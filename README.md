# BoardBar

A menu-bar macOS app that mirrors GitHub Projects v2 board views as Kanban
boards in a popover. Paste a board URL, paste a token, glance at the board,
click a card to open it on github.com.

Several boards can be configured, and a tab switches between them. A tab is one
saved *view*, not one project, so "Main Board" and "My Items" of the same
project are two tabs at no extra cost. With fewer than two configured there is
no tab bar at all.

Personal tool. Read-only by design: it never mutates
project state — no dragging between columns, no assigning, no commenting. A
mirror can beat github.com on latency and ambient presence; a half-featured
editor cannot beat it on features.

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
