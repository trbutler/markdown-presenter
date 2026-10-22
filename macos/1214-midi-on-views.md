# Hub 1214: MIDI on configurable views

This change ports the MIDI branch (84438cc, fc7acbf, d5de19d) onto the
5fd4d19 configurable-views review line. It does not use fixed ViewRole authority.

## Authority and relay

`ViewBridgeGate` tracks native page instance UUIDs and the first canonical
instance of each saved view. Only the canonical instance of the first Main
Slides entry may emit MIDI. A second Main Slides entry, duplicate canonical
registration, display cast, Overlay, Presenter View, Custom (including a Custom
URL pointing at the deck), unknown instance, or subframe cannot acquire MIDI
authority. Removal/unregister revokes the instance; view-list reorder changes
which Main Slides entry is authoritative. DeckPage additionally checks the main
frame and exact source WKWebView before parsing. DeckController checks that
source again against its registration.

Lower-third requests use the existing canonical operator policy: the first
Main Slides canonical page and canonical Overlay/Presenter pages can request
state; other Main Slides pages, casts and Custom pages cannot. `lowerThird`
accepts CFBoolean-backed bridge booleans, rejecting numeric NSNumber 0/1 and
other malformed values. Every registered deck page receives the resulting
apply, including casts; this rendering path does not grant control authority.

## Lower-third clock

`DeckState.lowerStart` is the current slide's origin in Date.now milliseconds.
First nonempty ready establishes it. Actual index changes restart it and clear
the manual lowerThird override; same-index requests, black/unblack, timer reset,
manual L and a late ready preserve it. One controller transition batch uses one
clock reading. Older serialized state without these optional fields decodes.

Both apply paths carry lowerThird and lowerStart. The current template's native
apply ignores lowerStart, so the native script also calls its existing global
`startLowerThird` helper for the active slide with elapsed milliseconds when
its local origin differs. That helper cancels old timers and seeks buildIn /
buildOut, including already expired transitions. It runs after apply and before
the acknowledgement/paint frames; it does not run while a manual override is
present. This uses the page content world and needs verification on macOS 27.
The template source remains untouched.

## MIDI and shutdown

Strict atomic MIDI batch validation, lazy CoreMIDI setup, case-insensitive
substring destination selection (empty selects first), setup-change cache
invalidation and a private serial MIDI queue are retained. Missing endpoints
and send/setup failures are logged without blocking the main actor.

Every scheduled note-off (including velocity-zero note-on) is tracked by token
and endpoint until successfully sent. stop queues immediate pending offs, then
All Notes Off (CC 123, value 0) on every endpoint/channel used, before disposing
the port and client. Delayed callbacks cannot emit after stop. AppKit waits
asynchronously for queue completion with a 500 ms deadline; no semaphore or
synchronous main-actor wait is used. If a driver stalls beyond the deadline,
termination proceeds and delivery cannot be guaranteed. A physically removed
endpoint may also reject shutdown sends.

## Validation / Mac handoff

PresenterCore tests are authored for MIDI validation, pending-note-off tracking,
instance authority, strict lowerThird booleans and transitions, lowerStart
transitions/serialization and both generated apply paths. They have not run.
No Swift compiler or macOS SDK is available in this job. CoreMIDI, WebKit
page-world helper visibility and AppKit termination integration are marked
VERIFY-ON-MAC where needed.

On the Mac, compile and run PresenterCore tests, exercise multiple Main Slides
and Custom views, reorder authority, reconnect a cast mid-lower-third timing,
reload a page with L overridden, and quit within 200 ms of a note-on while
monitoring the destination's note-offs and CC 123. These are proposed checks,
not executed results. No network or SSH is needed for this patch's preparation.
