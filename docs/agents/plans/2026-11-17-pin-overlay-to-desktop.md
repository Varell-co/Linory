---
date: 2026-11-17T22:16:54+00:00
git_commit: e6462d93125e3b85ff18cccc13e9c72c17251abf
branch: main
topic: "Pin the lyrics overlay to one desktop (Space)"
tags: [plan, overlay, app-delegate, menu-panel, localization]
status: done
---

# PLAN: Pin the lyrics overlay to one desktop

Today the overlay floats on every desktop (Space). Users who keep music on a dedicated desktop want it to stay there. Add a menu toggle that binds the overlay to the desktop it is on when the toggle is switched on.

## Acceptance Criteria

- A new menu toggle **"Pin to this desktop" / "An diesen Desktop heften"** sits directly below "Click-through". Default: off.
- On: the overlay appears only on the desktop it was on when the toggle was switched on. Off: it appears on all desktops again (today's behavior).
- Showing and hiding (⌥⇧L, menu, auto-hide) never moves a pinned overlay to another desktop.
- The pin setting survives relaunch. After relaunch the overlay is pinned to the desktop that is active at launch.
- Reopening Linory from Finder or the Dock brings a pinned overlay to the current desktop and pins it there.
- Strings exist in English and German, `docs/USAGE.md` describes the feature, `swift build` and `swift run LyricsCoreChecks` pass.

## Technical Key Decisions and Tradeoffs

1. **Bind to a Space, keep `.floating` level, public API only.**
   - Why: private CGS Space APIs break with macOS updates, and Space IDs change when desktops are removed.
   - Impact: no way to target a specific desktop after relaunch; the overlay lands on the desktop active at launch.
2. **While pinned, hide with `alphaValue = 0` + `ignoresMouseEvents = true` instead of `orderOut`.**
   - Why: a window that is ordered out and back in is placed on the active Space, which would silently move the pin.
   - Impact: `applyVisibility` gets a pinned branch; `ignoresMouseEvents` must restore to `clickThrough` on show. Needs verification on real hardware (see Manual Verification).
3. **Showing via hotkey/menu while on another desktop keeps the overlay on its pinned desktop.**
   - Why: a pin is a pin. Reopen from Finder/Dock is the escape hatch.
   - Impact: no special handling in `toggleVisibility`.
4. **Full-screen apps no longer show a pinned overlay.**
   - Why: full-screen apps are their own Spaces; that is the pin working as intended.
   - Impact: documented in `docs/USAGE.md`.

## Current State

```
AppDelegate.applicationDidFinishLaunching (Sources/Linory/AppDelegate.swift:44-47)
 overlay: NSPanel [.borderless, .nonactivatingPanel]
  ├─ level              = .floating
  ├─ collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
  └─ ignoresMouseEvents = clickThrough   (didSet, AppDelegate.swift:26-32)

applyVisibility (AppDelegate.swift:172-194)
  show → alpha 0→1, orderFrontRegardless
  hide → alpha 1→0, then orderOut, alpha reset to 1

applicationShouldHandleReopen (AppDelegate.swift:110-115)
  clickThrough = false; setUserHidden(false); showSettings()

Menu (Sources/Linory/MenuPanel.swift:52-54)
  Show overlay [toggle] / Click-through [toggle] / Position ›
  MenuActions (MenuPanel.swift:5-14) bridges state + closures from AppDelegate
```

## Desired End State

```
┌──────────────────────────────────┐
│  ♪ Song – Artist                 │
├──────────────────────────────────┤
│ ▭ Show overlay            [●━━]  │
│ ↯ Click-through           [━━○]  │
│ 📌 Pin to this desktop    [━━○]  │  ← new
│ ⤢ Position                   ›   │
└──────────────────────────────────┘

pinToDesktop = false → collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
pinToDesktop = true  → collectionBehavior [.managed]   (belongs to one Space)

applyVisibility, pinned:
  show → alpha 0→1, ignoresMouseEvents = clickThrough
  hide → alpha 1→0, ignoresMouseEvents = true   (no orderOut)
```

## Abstractions and Code Reuse

- `Sources/Linory/AppDelegate.swift`
  - `pinToDesktop` - new persisted property (`UserDefaults` key `"pinToDesktop"`, registered default `false`), `didSet` calls `applySpaceBehavior(movingHere: true)` and mirrors to `menuActions.pinToDesktop`. Same pattern as `clickThrough`.
  - `applySpaceBehavior(movingHere:)` - new; sets `collectionBehavior` for the current pin state. With `movingHere` and pinned: `orderOut`, set behavior, `orderFrontRegardless` (if currently shown) so the window joins the active Space.
  - `applyVisibility` - pinned branch using alpha + `ignoresMouseEvents` instead of `orderOut`.
  - `applicationDidFinishLaunching` - read `pinToDesktop`, apply behavior before the first `orderFrontRegardless`.
  - `applicationShouldHandleReopen` - re-pin to the current desktop when pinned.
- `Sources/Linory/MenuPanel.swift`
  - `MenuActions` - `@Published var pinToDesktop`, `var togglePinToDesktop`.
  - `MenuPanel.body` - one `toggleRow("pin", …)` below click-through.
- `Sources/LyricsCore/Localization.swift`
  - `L10nKey` - new case `pinToDesktop`, EN + DE strings. Existing check in `Checks/main.swift:225` covers missing translations.
- `docs/USAGE.md` - "Using the overlay" bullets.

No new types. `VisibilityPolicy` stays unchanged; pinning only changes how a decided show/hide is carried out.

## Logging & Observability

None. The app has no logging for overlay visibility today.

## Implementation

### Phase 1: Pin toggle end to end

Dependencies: None

Add the persisted setting, the Space behavior switch, pin-safe hiding, the menu row, strings and docs.

**Tasks**:
- [x] `Localization.swift`: add `pinToDesktop` to `L10nKey` (next to `clickThrough`), EN `"Pin to this desktop"`, DE `"An diesen Desktop heften"`.
- [x] `MenuPanel.swift` `MenuActions`: add `@Published var pinToDesktop = false` and `var togglePinToDesktop: () -> Void = {}`.
- [x] `MenuPanel.swift` `body`: add `toggleRow("pin", t(.pinToDesktop), isOn: actions.pinToDesktop, action: actions.togglePinToDesktop)` directly below the click-through row.
- [x] `AppDelegate.swift`: register default `"pinToDesktop": false` in `applicationDidFinishLaunching`.
- [x] `AppDelegate.swift`: add `applySpaceBehavior(movingHere:)`:
  ```swift
  /// Pinned, the overlay belongs to one Space. Ordering it out and in again places it on the active Space.
  private func applySpaceBehavior(movingHere: Bool) {
      let pinned = pinToDesktop
      if pinned && movingHere && isShowing { overlay.orderOut(nil) }
      overlay.collectionBehavior = pinned ? [.managed] : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      if pinned && movingHere && isShowing { overlay.orderFrontRegardless() }
  }
  ```
  If verification shows `orderFrontRegardless` does not move the window to the active Space, add `.moveToActiveSpace` for that one call and remove it afterwards.
- [x] `AppDelegate.swift`: add `var pinToDesktop = false { didSet { UserDefaults…set; menuActions.pinToDesktop = pinToDesktop; applySpaceBehavior(movingHere: true) } }`. Guard `overlay != nil` like `clickThrough`.
- [x] `AppDelegate.swift` `applicationDidFinishLaunching`: replace the hard-coded `collectionBehavior` line with reading `pinToDesktop` from `UserDefaults` and calling `applySpaceBehavior(movingHere: false)` before `overlay.orderFrontRegardless()`.
- [x] `AppDelegate.swift` `buildMenu`: wire `menuActions.togglePinToDesktop = { [weak self] in self?.pinToDesktop.toggle() }`.
- [x] `AppDelegate.swift` `applyVisibility`: when `pinToDesktop`, never call `orderOut`. On hide set `overlay.ignoresMouseEvents = true` and fade alpha to 0; on show restore `overlay.ignoresMouseEvents = clickThrough` and fade alpha to 1 (`orderFrontRegardless` only if not already visible on screen). Keep the unpinned path unchanged.
- [x] `AppDelegate.swift` `clickThrough.didSet`: only set `overlay.ignoresMouseEvents` when the overlay is showing, so a hidden pinned overlay keeps ignoring clicks.
- [x] `AppDelegate.swift` `pinToDesktop.didSet`: when switching pin off while hidden by alpha, `orderOut` and reset alpha to 1 so the unpinned path's invariants hold.
- [x] `docs/USAGE.md` "Using the overlay": add a bullet: pin toggle in the menu binds the overlay to the current desktop; remembered across relaunches, then pinned to the desktop active at launch; showing it from another desktop keeps it on its desktop; full-screen apps don't show a pinned overlay. Mention the toggle in the menu bullet ("show or hide the overlay, position it, toggle click-through, pin it to a desktop, or quit").

**Automated Verification**:
- [x] `swift build` passes.
- [x] `swift run LyricsCoreChecks` passes (includes the EN/DE translation check for `pinToDesktop`).

**Manual Verification** (needs at least two desktops in Mission Control):
- [x] Pin off: overlay shows on every desktop, as before.
- [x] On desktop 2, switch pin on: overlay stays on desktop 2 and is gone on desktop 1.
- [x] Pinned on desktop 2: ⌥⇧L hide and show on desktop 2 keeps it there; hide on desktop 2, switch to desktop 1, show via ⌥⇧L, return to desktop 2: overlay is on desktop 2.
- [x] Pinned, auto-hide on: pause and resume playback; overlay fades out and back in on its desktop, and clicks pass through while hidden.
- [x] Pinned and hidden: click-through toggled in the menu does not make the invisible overlay catch clicks.
- [x] Switch pin off: overlay appears on all desktops again; hiding/showing still works.
- [x] Quit and relaunch with pin on: menu shows pin on, overlay is on the desktop active at launch only.
- [x] Full-screen Spotify with pin on: overlay not shown there; with pin off: shown.

### Phase 2: Reopen brings a pinned overlay here

Dependencies: Phase 1

Finder/Dock reopen is the escape hatch for a pinned overlay on another desktop.

**Tasks**:
- [x] `AppDelegate.swift` `applicationShouldHandleReopen`: after `setUserHidden(false)`, call `applySpaceBehavior(movingHere: true)` when `pinToDesktop` is on.
- [x] `docs/USAGE.md`: extend the reopen bullet: "Reopening the app from Finder or the Dock turns click-through off and brings a pinned overlay to the current desktop."

**Automated Verification**:
- [x] `swift build` passes.
- [x] `swift run LyricsCoreChecks` passes.

**Manual Verification** (bundled app via `./build-app.sh`):
- [x] Pin on desktop 1, switch to desktop 2, open `Linory.app` from Finder: overlay appears on desktop 2, is gone from desktop 1, pin stays on.
- [x] Same with the overlay hidden via ⌥⇧L before reopening: it becomes visible on desktop 2.

## Implementation Notes

During implementation, document user feedback, problems, and decisions here.

- Both phases implemented together; Phase 2 is one line in `applicationShouldHandleReopen`.
- Mouse handling simplified to one rule: `ignoresMouseEvents = clickThrough || !isShowing`, set in `applyVisibility` and `clickThrough.didSet`. Applies to the unpinned path too (harmless: hidden there means ordered out).
- Pinning while hidden: `applySpaceBehavior(movingHere: true)` orders the overlay in at alpha 0, so it joins the current Space now instead of whichever Space is active at the next show.
- `pinToDesktop` is read from `UserDefaults` before the overlay is created, so its `didSet` skips the Space move at launch; `applySpaceBehavior(movingHere: false)` replaces the hard-coded `collectionBehavior` line.
- Pinned show calls `orderFrontRegardless` only if `!overlay.isVisible`. Unverified whether `isVisible` stays true for a window on another Space; if not, showing from desktop 1 would pull it over (manual check covers this).
- Manual verification confirmed by the user on 2026-11-17. Dragging a pinned overlay to another screen moves it to that screen's current desktop; kept as intended, since a drag is deliberate.

## References

- `Sources/Linory/AppDelegate.swift` - overlay setup, visibility, reopen
- `Sources/Linory/MenuPanel.swift` - menu rows and `MenuActions`
- `Sources/LyricsCore/Localization.swift` - `L10nKey`
- `Checks/main.swift:225` - translation completeness check
- `docs/USAGE.md` - user docs
- Apple: `NSWindow.CollectionBehavior` (`canJoinAllSpaces`, `managed`, `moveToActiveSpace`)
