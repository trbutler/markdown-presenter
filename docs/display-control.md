# Live display control

This branch preserves the uncommitted Dawnredwood presenter as a baseline commit,
then adds the live output service alongside it. `generate.pl` and the existing
presentation template do not depend on this service. Dawnredwood's original
working directory has not been changed.

## Start locally

Requires Perl 5.26 or newer and Mojolicious 9.42 or newer. With `cpanm` installed:

```sh
cd markdown-presenter
cpanm --local-lib-contained local --installdeps .
perl script/display-server daemon
```

The server automatically finds dependencies installed under `local/lib/perl5`.
Alternatively install Mojolicious with your operating system's package manager
or your usual Perl environment. The default listener is `http://127.0.0.1:3000`.
One server process owns the output state; do not run multiple workers.

- Operator page: `http://127.0.0.1:3000/`
- OBS output: `http://127.0.0.1:3000/output/lower-third`

The initial cue buttons are Timothy Butler / Pastor and Need Prayer? /
tim@littlehills.church. Add or edit cues in the browser. Saving creates
`var/cues.json`; set `PRESENTER_CUES` to choose another file. The file contains a
JSON array matching `config/cues.example.json`. Stop the server before editing
that file manually. Writes from the editor replace the file atomically. Keep
`var/` on a writable local disk and back it up with your production configuration.

The iframe is the live output, with a checkerboard behind transparent areas.
It is not a separate rehearsal bus. Controls remain outside the OBS output.
The active cue button shows a small progress bar and seconds remaining. Progress
includes build-in, hold, and build-out; an early take-out updates the end time.

## OBS and the iPad

Add a Browser Source using the output URL, width **1920**, height **1080**, and
30 or 60 FPS. Keep the default transparent custom CSS. Put the browser source
above video. Leave **Shutdown source when not visible** and **Refresh browser
source when scene becomes active** off for uninterrupted animation. A refresh
still joins the current timeline rather than replaying build-in.

To reach the service from an iPad, bind it to the server's LAN address:

```sh
perl script/display-server daemon -l http://192.168.1.20:3000
```

Use `http://192.168.1.20:3000/` on the iPad. OBS can use the same address, including
when it runs on another computer. Later, bind to the server's NetBird address
and update these URLs. Assets, commands, and state subscriptions use the page's
origin, so there is no hard-coded localhost dependency in the browser code.

This alpha is for a trusted LAN or NetBird mesh, with access controlled by the
network. It has no user login. Do not publish this control port on the public
internet. Browser writes from other origins are rejected. If using a reverse
proxy, forward the host correctly and disable buffering for `/events`; follow
Mojolicious's trusted-proxy configuration for that deployment.

## Playback behavior

- Tap a hidden cue: build in, hold for its configured duration, build out.
- Tap the active cue again: begin build-out immediately, even during build-in.
- Tap a different cue: build out the current one, then build in the replacement.
- Several selections during exit: the latest pending selection wins.
- Clear output: immediately hide everything and cancel the pending selection.
- Edit or delete an active cue: its current content is a snapshot and finishes
  independently. Edits apply on its next activation.
- Service restart: saved cues survive; the output starts hidden.

The default hold is 10 seconds after entry completes. Little Hills regular entry
and exit each take 2 seconds, with the bars growing from the left at different
rates. Build-out reverses the exact build-in poses, including a partial entry
when interrupted. Full-width retains its 1.2-second entry and exit. The original
1.2-second regular animation with the upper bar exiting to the right is preserved
as the **Little Hills (alternate motion)** theme, under
`themes/little-hills-directional/`. No default cue selects it.

The server owns the timeline and broadcasts snapshots
with server timestamps and revisions over Server-Sent Events (SSE). Clients
anchor timestamps to their monotonic clocks rather than their wall clocks.
This is a shared timeline, not frame-accurate broadcast synchronization: delivery
latency can produce small differences between clients.

If an output loses its connection, its current run still expires locally.
It cannot discover a new queued cue until reconnecting. The server sends a named
heartbeat every 2 seconds. Clients mark the connection disconnected and rebuild
the stream after 6.5 seconds without any message or heartbeat (checked once per
second); browser offline events disable controls immediately. Returning online
or bringing a stale tab to the foreground also reconnects. A connection is only
shown as healthy after a fresh playback snapshot arrives, not merely when the
socket opens. Failed initial control-page loads retry automatically, and control
requests time out after 5 seconds without replaying trigger commands.

A fresh connection receives the current state. If an asset fails to load, output
stays transparent, reports the error in its browser console, and retries loading
on the next state update or reconnection, even if the cue has not changed.

## Companion 2.x and Perl control

Use **Generic → HTTP Requests**, with the service address as the Base URL.
Create one POST action per cue, with Content Type `application/json`:

```text
URI: /api/v1/outputs/lower-third/commands
Body: {"action":"trigger","cueId":"timothy"}
```

For another cue, replace `timothy` with its ID. IDs appear in
`GET /api/v1/cues` and remain stable when edited. Use the same trigger action
every press; the server performs the toggle so Companion and iPad presses agree.
Configure only the press action, not a matching release action. Clear button:

```json
{"action":"clear"}
```

`show` brings a cue in or replaces another cue; showing the already-active cue
is idempotent. `hide` builds out the current cue and cancels a pending replacement.
Generic HTTP actions do not provide automatic on-air button feedback. The
installed Companion 2.x application still needs an on-site integration check;
the HTTP requests themselves are covered by automated tests.

For state-driven button lighting, this branch also includes a dedicated
[Companion 2.4.2 adapter](../integrations/companion-2/faithtree-presenter/HELP.md).
It supplies cue presets, trigger actions, on-air feedback, disconnected feedback,
and remaining-time variables using the same state stream as the web controls.
Existing Generic HTTP trigger actions can be retained while adding the adapter's
feedback. Its default light turns off at the start of build-out; the feedback's
**Keep lit during build-out** checkbox keeps it lit until animation completion.

Package it with `sh script/package-companion-2`. This creates an archive under
`public/downloads/`, available from the preview service at
`/downloads/faithtree-presenter-companion-2.4.2.tar.gz`. Installation depends on
the layout of the Companion 2.4.2 application; see the adapter's help before
copying it into an application tree. Modern module-import packages cannot be
assumed to work on 2.x.

Example Perl sender using the same API:

```perl
use Mojo::UserAgent;
my $tx = Mojo::UserAgent->new->post(
    'http://127.0.0.1:3000/api/v1/outputs/lower-third/commands'
    => json => {action => 'trigger', cueId => 'timothy'}
);
die $tx->res->body unless $tx->result->is_success;
```

## API v1

All responses are JSON except the SSE stream. Errors have an `error` string.
The implemented output ID is `lower-third`; unknown outputs return 404. A
future slide renderer can use the same routing and subscription conventions.

| Method | Path | Behavior |
| --- | --- | --- |
| GET | `/api/v1/themes` | Installed theme manifests |
| GET | `/api/v1/cues` | Saved cues |
| POST | `/api/v1/cues` | Create a cue; duplicate ID returns 409 |
| PUT | `/api/v1/cues/:id` | Replace a cue, preserving its ID |
| DELETE | `/api/v1/cues/:id` | Delete a saved cue |
| GET | `/api/v1/outputs/:output/state` | Current playback snapshot |
| GET | `/api/v1/outputs/:output/events` | SSE snapshots; immediate initial state |
| POST | `/api/v1/outputs/:output/commands` | `trigger`, `show`, `hide`, `clear` |

Cue example:

```json
{"id":"speaker","label":"Speaker","theme":"little-hills","variant":"regular","font":"quicksand","line1":"Timothy Butler","line2":"Pastor","holdMs":10000}
```

IDs allow letters, digits, underscores, and hyphens (1–80 characters). Labels
allow 100 characters; each theme content field allows 200 characters on one
line. `holdMs` is an integer from 0 to 3600000. Unknown themes, variants, or fonts
return 400. Cue content is rendered with `textContent`, never as HTML.

Snapshots contain `revision`, `serverNow` (Unix milliseconds), `phase`, `run`,
and `pending`. A run includes the cue snapshot, `startedAt`, `enterMs`, `exitAt`,
`exitMs`, and `exitFrom` (entry progress when an early exit began). Revisions
belong to one service lifetime. Use `public/js/state.js` for subscription and
phase calculations; reconnecting always accepts the new service's snapshot.

## Adding themes

Each installed `themes/<id>/` directory contains:

```text
theme.json       Manifest, variants, text fields, defaults, timing
template.html    Trusted HTML fragment containing the graphic
style.css        Scoped styles and locally served fonts
theme.js         ES module exporting mount()
assets/          Logos, fonts, and their license notices
```

Copy the Little Hills folder as a starting point. Change `theme.json`'s `id`
to match the folder name and give it a unique CSS prefix. The service discovers
manifests at startup, so restart after adding a theme. Installed themes are
trusted code; the editor changes cue content, not templates or executable code.

The manifest has `id`, `name`, `version: 1`, `variants` and `fonts` arrays,
`fields` containing `{id, label}` text fields, `defaults` containing `variant`,
`font`, and `holdMs`, plus positive `enterMs` and `exitMs` durations. Optional
`variantTimings` overrides both durations per variant, for example
`{"regular":{"enterMs":2000,"exitMs":2000}}`. Field IDs
must be unique and must not use reserved cue names (`id`, `label`, `theme`,
`variant`, `font`, `holdMs`, or `holdSeconds`).

The runtime loads the stylesheet, HTML fragment, and ES module. The module's
interface is:

```js
export async function mount(root, {baseUrl, template, cue}) {
  // Install theme markup, set cue text safely, and await fonts/images.
  return {
    render({phase, progress, exitFrom, width, height}) {
      // Render the requested pose. No independent cue timers or networking.
    },
    unmount() {
      // Release resources and remove theme content.
    },
  };
}
```

`phase` is entering, holding, or exiting; `progress` runs 0–1. `exitFrom`
preserves partial entry when interrupted. `render` runs every animation frame
and must support seeking to any pose. The runtime owns hidden state and calls
`unmount` on replacement. Theme CSS positions a 1920×1080 stage; the theme scales
and centers it to fit `width` and `height`. Keep the page background transparent.

## Visual references and fonts

The simplified Singular screenshots and recording are the visual target.
Motion is supporting reference for the staggered layers and logo transform.
The animation is a reconstruction, not an exported Motion animation. The SVG
replaces the old PNG. Regular and full-width variants share a renderer.

Quicksand is the default and is bundled with its OFL notice. Serene Sands is
selectable as an alpha candidate: the bundled Regular WOFF2 was copied from
`/home/agents/serene-sands/fonts/webfonts` (September 19, 2026 build), with its
OFL notice. Its presence is not a production approval. Replace that pinned
asset with the approved build when ready and check text fit. See the theme's
`assets/README.md` for source and checksums. No font build runs during playback.

## Verification

```sh
PERL5LIB=local/lib/perl5 prove -l t
npm ci
npx playwright install chromium
npm run test:browser
npm run test:companion
```

The browser suite starts a temporary service on loopback port 3220, uses a
temporary cue file, and writes screenshots to ignored `test-results/`. It
checks transparency, fonts, synchronized clients, refresh, replacement,
editing, escaping, offline completion, reconnection, tablet layout, exact
reverse animation poses, progress, failed asset recovery, and a silent stalled
server that requires heartbeat-based detection and automatic recovery.
Node and Playwright are development tools only; playback needs Perl and a browser.

Before the first broadcast, inspect both variants over real OBS camera video
and trigger them from the actual iPad and Companion installation. Chromium
automation does not replace checking your installed OBS CEF version.
