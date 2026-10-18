# FaithTree Presenter — Companion 2.4.2

Server URL: `http://100.68.136.48:3210` (or your configured Presenter address).
Companion must be able to reach that URL over the LAN or NetBird.

This is a **Companion 2.x API 1.0 module**, targeting 2.4.2 and its Node 14.19
runtime. It is not a Companion 3.x/4.x import package. It has no npm dependencies.

## Button setup

1. Add the **FaithTree → Presenter** connection and enter the server URL.
2. Wait for Connected. Available cues load automatically.
3. Under Presets, drag a **Lower thirds** cue onto a button. It includes the
   trigger action and on-air/disconnected feedback. Leave release actions empty.

For an existing button, keep its Generic HTTP trigger action and add this
connection's **Cue is on air** feedback. Select the same cue and choose the
button's lit background/text colors. Alternatively replace its action with
**Trigger / take out cue**. Use one trigger action per press, not both.

By default, buttons light during build-in and hold, and go dark when build-out
starts. Enable **Keep lit during build-out** to remain lit until the graphic
has completely disappeared. An unrelated or merely pending cue does not light.
Feedback follows the shared server state, including iPad controls, external
HTTP requests, timed take-out, cue replacement, and Clear.

The generated presets use green for on-air and amber for disconnected. Remove
the disconnected feedback or change its style if you prefer another warning.
Connection loss clears the on-air feedback, rather than leaving a stale light.

## Actions and variables

Actions: Trigger / take out cue, Show cue, Animated take-out, Immediately clear
output, Refresh cue list. The cue list also refreshes every 15 seconds and after
reconnection. Editing a cue's label does not change its ID.

Variables (assuming the connection label is `presenter`):

- `$(presenter:connected)` — 1 or 0
- `$(presenter:cue_id)` — current cue ID, including during build-out
- `$(presenter:phase)` — entering, holding, exiting, or hidden
- `$(presenter:remaining)` — whole seconds left, including build-out

This module subscribes to the existing state stream; it does not modify the
graphics service. It rebuilds a stalled stream after 6.5 seconds without data
or heartbeats and retries after 1 second. Commands time out after 3 seconds and
are never automatically replayed. Its own clock expires an on-air indicator at
the scheduled take-out even before a fresh state update arrives.

## Installation for a source/headless Companion 2.4.2 tree

Identify the actual Companion application root containing `instance_skel.js`.
Copy this entire folder to:

```text
<companion-root>/module-local-dev/faithtree-presenter/
```

Keep the directory name `faithtree-presenter`, matching `package.json`. Restart
Companion, then add the connection. Existing Generic HTTP buttons keep working.
No install-time npm command is needed for this module.

A packaged desktop application's files may live inside `app.asar`, so these
instructions are not a universal desktop installer. Inspect the host's actual
2.4.2 installation before changing it; do not assume an arbitrary user module
folder or the newer module-import UI will load this module. Keep a separate
Companion configuration export before changing that installation.

The adapter's behavior is covered by automated tests against the real Presenter
service. The 2.4.2 SDK contract is checked against upstream source, but a physical
Companion application and Stream Deck still need an installation check.

Upstream references:
- https://github.com/bitfocus/companion/blob/v2.4.2/instance_skel.js
- https://github.com/bitfocus/companion/blob/v2.4.2/lib/instance.js
