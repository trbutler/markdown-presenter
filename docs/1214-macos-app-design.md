# 1214: markdown-presenter macOS playback app

Main slides, confidence monitor and NDI overlay, as a native macOS app.
Depends on 1213 (markdown-presenter as a Proclaim replacement). This branch
(`review/hubsup-1214-macos-app`) is a design plus a prototype. Nothing here is
landed.

## 1. Goal

One deck runs in up to four views at once:

| View | Where it goes | What it shows |
|---|---|---|
| audience | projector or main screen | the deck exactly as today |
| confidence | stage display | current and next slide, speaker notes, clock, elapsed timer |
| control | operator laptop | transport buttons, a grid of every slide, clock, timer |
| overlay | NDI only, no display | foreground text only, on a transparent background (key/fill), so OBS or vMix can lay lyrics or lower thirds over camera video |

Each windowed view can go on any connected display. Clicker keys work the way
they do in PowerPoint and Proclaim, whichever window has focus.

## 2. Architecture

```
            +-------------------- PresenterApp (Swift, AppKit) --------------------+
 keys ----> | KeyRouter --> DeckController (owns DeckState) --evaluateJavaScript--> |
 menus ---> |                  ^                                                   |
            |                  |  WKScriptMessage {type: ready|request}             |
            |   WKWebView audience   WKWebView confidence   WKWebView control      |
            |   WKWebView overlay --takeSnapshot--> FrameConverter --> FrameSink   |
            +----------------------------------------------------------------------+
                                       same deck.html, ?view=<role>
```

* **Swift + AppKit + WKWebView.** Each view is a WKWebView that loads the
  same generated deck file, with `?view=audience|confidence|control|overlay`.
  The app also injects `window.__presenterView` at document start, in case a
  file URL ever loses its query. The deck stays one self-contained HTML file,
  so it still works in a browser on its own. SwiftUI adds nothing here: every
  view is a web view inside an NSWindow, and AppKit gives direct control of
  borderless windows, window levels and NSScreen. SwiftUI could come in later
  for a settings sheet.
* **One state, owned natively.** `DeckState` is `{index, black, timerStart,
  count}` (PresenterCore/DeckState.swift). Every input becomes a `DeckCommand`:
  keys, menu items, and clicks in the control view. The controller applies the
  command, then pushes `presenter.apply({...})` to every web view. The JS side
  only renders state. It never echoes it back, so the push cannot loop.
* **JS bridge** (template.html):
  * JS to Swift: `webkit.messageHandlers.presenter.postMessage(...)`.
    * `{type:'ready', view, count, titles}` on load. The controller learns the
      slide count, then pushes the live state to that view. This also covers a
      reload, a regenerated deck (Cmd-R) and a crashed web process.
      `webViewWebContentProcessDidTerminate` reloads the view automatically.
    * `{type:'request', index?, black?, timerStart?}` when the control view
      wants a change.
  * Swift to JS: `window.presenter.apply(state)`. The page also exposes
    `presenter.state()` and `presenter.titles()`.
  * Outside the app (a plain browser), each tab applies changes locally and
    relays them over a `BroadcastChannel`. A confidence or control tab opened
    beside the audience tab stays in sync with no app at all. A new tab says
    hello and picks up the current state.
* **Keys** (PresenterCore/KeyMap.swift). A local `NSEvent` monitor maps keys
  before WebKit sees them. Mapped keys are consumed; unmapped keys pass through.
  The template's own key handler stands down in-app, so nothing double-advances.
  * Next: Right, Down, Page Down, Space.
  * Back: Left, Up, Page Up.
  * Black: B or `.`. The blank button on most clickers sends one of these.
  * Jump: Home, End.
  * As in PowerPoint, Next or Back while blacked only lifts the black.
  * Chords with Command, Control or Option are left alone, so menu shortcuts
    still work.
  * Not mapped yet: F5 and Esc (the "start/stop show" key on Logitech
    clickers), W for white, and number+Enter to jump. These need Tim's call;
    see section 8.
* **Displays** (PresenterCore/ScreenAssignments.swift, WindowManager.swift).
  * Displays are identified by their CoreGraphics display UUID. Unlike
    CGDirectDisplayID, the UUID survives reboots and re-plugging.
  * The Displays menu offers each role either a specific display or Automatic.
    Choices are saved in UserDefaults.
  * Automatic: control goes on the menu-bar display, audience on the first
    external display, and confidence on the second external display, or beside
    the controls if there is only one.
  * A view on a presentation display is a borderless window covering the whole
    screen, one level above that screen's menu bar. A view on the operator
    screen is an ordinary tiled window.
  * Hot-plug: on `didChangeScreenParametersNotification` every window is
    re-placed. A saved choice whose display is unplugged is kept. The view
    falls back to Automatic until that display returns, then moves back by
    itself.
* **Audio**: only the audience view plays sound. The template mutes any media
  that starts playing in the other views. Autoplay without a click is enabled,
  because Tim's 1213 work has video slides and soundtrack beds.

### Template changes (this branch)

* `generate.pl` reads a `Notes:` (or `Note:`) line. Everything after it in
  that slide is HTML-escaped and emitted as `<aside class="notes">`. The
  audience view hides it.
* `template.html` adds the four views as CSS on a `view-<role>` class on
  `<html>`. It also adds black-screen support (B), the clock and timer, and the
  sync bridge above. The audience view renders pixel-identically to the old
  template (verified, section 6).
* Porting to Tim's 1213 template: his working tree has a much larger
  template, with sections, hash routing, lower thirds and audio. The view
  layer is additive (CSS block, `applyState`/`requestState`, the two `setup*`
  functions), so it should port by hand. It has not been tried, because his
  edits are uncommitted. In the overlay view his `.lower-third` element is the
  natural thing to keep visible. Hash writes (`#N`) are harmless in-app.

## 3. NDI output

### How Vingester does it (studied, no code copied; Vingester is GPL-3.0)

* An Electron `BrowserWindow` is created with `offscreen: true`, or
  `transparent: true` when the background colour is "transparent".
  `backgroundThrottling: false` keeps it painting while hidden.
* Frames arrive from the `paint` event, with `setFrameRate()` controlling the
  paint rate. In a second mode it captures an on-screen window with
  `beginFrameSubscription` and skips frames in software.
* `image.getBitmap()` goes over IPC to a worker. The worker sends it through
  `grandiose` (Node NDI bindings) as FourCC BGRA. When alpha is off, it uses
  BGRX instead.
* It passes `clockVideo: false`, so the app paces frames, not NDI. Timecode is
  derived from wall-clock nanoseconds.
* It lowers the capture rate when NDI tally says nobody is watching: 1 fps
  unconnected, 5 fps in preview or program, otherwise a third of the target
  rate with a floor of 5.
* Users report about 2 s of delay and notable CPU load.

### Native macOS options

| Method | Alpha | Cost and latency | Notes |
|---|---|---|---|
| `WKWebView.takeSnapshot` (prototype) | yes, with `drawsBackground = false` | one async GPU readback per frame; expected roughly 10-30 ms at 1080p (unmeasured) | no permissions; `afterScreenUpdates = false` is faster and may lag a frame |
| ScreenCaptureKit `SCStream`, single-window filter | BGRA; window alpha should survive with a clear background (verify) | IOSurface frames at display rate, lowest CPU, about one display frame of latency | needs Screen Recording permission (TCC prompt, possibly re-prompted on macOS 15); window must be on screen |
| `CALayer.render(in:)` / `cacheDisplay` | n/a | n/a | does not work: WKWebView draws in another process, so these return blank |
| Offscreen WebKit (Electron-style) | n/a | n/a | WKWebView has no public offscreen paint API |

The plan is to start with `takeSnapshot`, because it needs no permission
prompt. The capture loop drops a tick rather than queue when the previous
snapshot has not returned, so latency stays bounded at about one frame plus
the snapshot time. Frames go to `FrameConverter`, which produces BGRA at the
output size:

* premultiplied, straight out of CGContext, or
* straight alpha, derived with vImage.

If measured snapshot cost is too high, switch to ScreenCaptureKit. The overlay
content (lyrics, lower thirds) changes rarely, so either path can capture at
full rate only for about 1.5 s after a state change, and repeat or trickle at
around 5 fps otherwise. This is the same idea as Vingester's tally throttling.

The overlay page lives in a small, visible, transparent preview window. WebKit
may stop painting fully hidden or occluded windows, so whether a fully
offscreen window keeps rendering is a phase 2 check.

### Plug-in point

`FrameSink` (PresenterCore/FrameSink.swift) is the only interface the capture
side sees. `StubFrameSink` counts frames and logs fps plus an opaque and
transparent pixel count every 150 frames, which proves alpha is flowing.

`NDIFrameSink` (PresenterCore/NDIRuntime.swift) carries a marked
`NDI SDK PLUG-IN POINT` block that spells out the six steps. `NDIRuntime`
already `dlopen`s `libndi.dylib` from these locations, in order:

* `$NDI_RUNTIME_DIR_V6`
* `$NDI_RUNTIME_DIR_V5`
* `/usr/local/lib`
* the SDK folder

It then resolves `NDIlib_v5_load`. The NDI v6 runtime still exports that
symbol, according to third-party reports; check it against the SDK header.
Nothing from the SDK is in the repo.

### NDI licensing (what matters for us)

* The SDK is royalty-free under its terms and conditions [1].
* We must link to ndi.video "in a location close to all locations where NDI is
  used / selected within the product", on our website and in our
  documentation [1].
* We must use "NDI®" with the ® on the first use in a document, plus the
  statement "NDI® is a registered trademark of Vizrt NDI AB" near it. The
  About box should say the same [1]. The prototype's Output menu already shows
  both the statement and the link.
* Using "NDI" in a product name needs the NDI brand guidelines or NDI's own
  approval [1]. So call the feature "overlay output (NDI®)", not "NDI
  Presenter".
* Redistribution [2]:
  * SDK headers may be distributed with open-source projects under MIT.
  * The runtime binaries may ship inside an app only if our EULA covers the
    NDI SDK EULA's requirements.
  * Redistributable installers may be bundled if kept up to date.
  * NDI Tools may not be redistributed.
  * The brief's premise ("cannot be redistributed, user must download it") is
    stricter than the docs. Shipping libndi is allowed with EULA terms; we
    choose not to.
* Our choice: never vendor or bundle libndi. Load it with `dlopen` from the
  user's NDI runtime install, which is NDI's documented dynamic-loading
  mechanism [3]. On macOS, the runtime installs into `/usr/local/lib`, and
  macOS has no global environment variable to locate it [3, 4].
* Where it matters:
  1. If we ever ship a signed .app with libndi inside it for convenience, we
     need a EULA that covers the NDI terms.
  2. A notarized, hardened-runtime build that `dlopen`s a library from
     `/usr/local/lib` needs `com.apple.security.cs.disable-library-validation`,
     because libndi is signed by a different team.
  3. If markdown-presenter is ever published as open source, add the MIT
     headers in a small C target; the runtime still stays user-installed.
     The repo currently has no LICENSE file.

## 4. Prototype in this branch

* `macos/PresenterApp/`: an Xcode-free Swift package for macOS 13+, Swift 5.9
  tools.
  * `PresenterCore`: no AppKit. It holds state, the key map, bridge parsing and
    script building, display-assignment rules, `FrameSink`, the stub, and the
    NDI loader. XCTest unit tests cover it.
  * `PresenterApp`: `PresenterMain` (@main), `AppDelegate` (menus: Slide,
    Displays, Output, Window), `WindowManager`, `DeckPage` (one WKWebView per
    role), `DeckController`, `KeyRouter`, `OverlayOutput` and
    `FrameConverter`.
* `macos/fixtures/1214-demo.md`: a three-slide deck with notes.
* `macos/tools/check-views.js`: a headless Playwright check of every view,
  keys, black, sync, overlay alpha, a faked native bridge, and a
  pixel-regression test of the audience view.

Build and run on a Mac with the Command Line Tools:

```
perl generate.pl macos/fixtures/1214-demo.md macos/fixtures/1214-demo.html   # from repo root (template path)
cd macos/PresenterApp
swift build -c release
.build/release/PresenterApp ../fixtures/1214-demo.html
swift test        # needs Xcode or CLT with XCTest

# HTML-side check (any machine with node + playwright + chromium):
PLAYWRIGHT=/path/to/node_modules/playwright node macos/tools/check-views.js \
  macos/fixtures/1214-demo.html baseline.html chromium   # baseline: same .md built with the pre-1214 template, or '-'
```

## 5. Phased plan

1. **Phase 1, this branch.** Design, view CSS and JS, notes in the generator,
   and the Swift skeleton. Gate: `swift build` succeeds on a Mac and the three
   windows sync. Not yet done; there is no Mac build host available to this
   agent.
2. **Phase 2, real hardware.** Do one run with the laptop, a projector and a
   stage TV:
   * hot-plug mid-show, sleep and wake, and mirroring on or off;
   * a Logitech R400 or R800 clicker and a Proclaim-style clicker;
   * measure `takeSnapshot` fps and CPU at 1080p30, and check that the overlay
     window keeps painting when covered;
   * port the view layer onto Tim's 1213 template.
3. **Phase 3, NDI.** Write the binding in `NDIFrameSink`, then test with OBS
   (DistroAV/obs-ndi) and vMix. Check that alpha arrives as key/fill, and
   settle premultiplied versus straight alpha. Add NDI tally-driven frame-rate
   throttling. If snapshot cost is too high, switch to ScreenCaptureKit.
4. **Phase 4, show-ready.**
   * deck file watching, so `generate.pl` output reloads itself;
   * a Proclaim-style "service" playlist of several decks;
   * a large-type notes mode and a countdown timer;
   * a signed and notarized .app, with an Info.plist and the
     disable-library-validation entitlement;
   * an About box carrying the NDI attribution.

## 6. Verified so far (dawnredwood, Linux)

* `perl -c generate.pl` passes. The demo deck generates. Notes come out
  escaped: `&lt;angle brackets&gt; &amp;`.
* Headless Chromium 147 via Playwright, `check-views.js`: 31 of 31 pass. They
  cover:
  * every key binding;
  * black, and "advance while black only lifts black";
  * BroadcastChannel sync, including a late-joining tab;
  * confidence: notes, next slide, End card, clock and timer, scaled stage;
  * the control grid driving the audience view;
  * overlay html and body backgrounds both `rgba(0,0,0,0)`;
  * the faked `webkit.messageHandlers` bridge: ready message, JS ignoring keys
    in-app, requests not applied locally, `presenter.apply` rendering native
    state;
  * the audience screenshot byte-identical to the pre-1214 template, with the
    animated bug masked.
* Overlay PNG alpha: the top half is fully transparent and the text band
  reaches alpha 255. 68 % of pixels are alpha 0.
* Not verified:
  * WebKit could not run, because Playwright's WebKit is missing system
    libraries on dawnredwood.
  * Nothing in Swift was compiled or type-checked: there is no Swift toolchain
    on dawnredwood or this host.
  * Neither chanticleer nor poins was reachable with BatchMode SSH (host key
    verification failed).

## 7. Risks

* The Swift code is uncompiled. Expect a round of compiler fixes on the first
  Mac build, mostly around concurrency annotations, which differ between SDKs.
  The design keeps all cross-thread hops as `Task { @MainActor in ... }`.
* `drawsBackground` is set through KVC. It is long-standing and widely used,
  but not public API.
* WebKit may throttle timers and painting in occluded or offscreen windows.
  That would break the overlay capture and the content fade-in timing. Mitigate
  by keeping the window on screen, or by switching to ScreenCaptureKit.
* Snapshot throughput at 1080p30 is unmeasured.
* The borderless window one level above the menu bar is not a native
  full-screen Space. Mission Control and Stage Manager interactions need
  phase 2 testing. The native-full-screen alternative is fragile across
  multiple windows and hot-plug.
* NDI v6 dynamic-load symbol and macOS paths come from docs and third-party
  reports, so check them against the shipped header. The BGRA alpha convention
  (premultiplied or straight) is unconfirmed.
* The content fade-in animation (0.8 s delay plus 1.2 s) also plays in the
  overlay. That is desirable for lyrics, but adds perceived latency.

## 8. Decisions for Tim

1. Are F5/Esc, W (white) and number+Enter wanted? PowerPoint has them;
   Proclaim differs.
2. Overlay look: the current choice is centred lower-third text over a soft
   dark gradient band. Options are no band, a solid bar, or his `.lower-third`
   design.
3. Shipping: user-installed NDI runtime only (current design), or bundle
   libndi in a signed app (needs a EULA)?
4. Does markdown-presenter get an open-source licence? This affects whether
   the MIT NDI headers go in-repo.
5. Notes syntax: `Notes:` to the end of the slide (chosen), or Marp-style
   `<!-- -->` comments?

## Sources

1. NDI SDK documentation, Licensing: https://docs.ndi.video/docs/sdk/licensing
2. NDI SDK documentation, Software Distribution: https://docs.ndi.video/docs/sdk/software-distribution
3. NDI SDK documentation, Dynamic Loading of NDI Libraries: https://docs.ndi.video/docs/sdk/dynamic-loading-of-ndi-libraries
4. ofxNDI issue 49 (dlopen of /usr/local/lib/libndi.dylib on macOS 13): https://github.com/leadedge/ofxndi/issues/49
5. Vingester (GPL-3.0): https://github.com/rse/vingester, specifically `vingester-browser.js` (offscreen window, paint and frame subscription, tally fps) and `vingester-browser-worker.js` (grandiose, FOURCC_BGRA/BGRX, `clockVideo: false`)
6. Electron offscreen rendering: https://www.electronjs.org/docs/latest/tutorial/offscreen-rendering
7. NDI v5/v6 runtime symbol and environment-variable notes (third party): https://git.c64.org/slayradio-public/ndi-shim
8. Vingester NDI latency report (user forum): https://community.troikatronix.com/post/49325
