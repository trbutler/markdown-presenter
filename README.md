# FaithTree / Markdown Presenter

A lightweight HTML presentation generator that replicates a Keynote-style template:

- Full-bleed photo background per slide
- Soft black-to-transparent gradients top and bottom
- Animated "bug" (circular FaithTree logo that drops from top-right to bottom over 30 seconds)
- Small category kicker in the upper left
- Headline, an optional subtitle, and bullet points that fade in

`pray-walk.md` is the September 2025 prayer-walk deck extracted from Keynote. Its photos are extracted locally into `media/` and are not part of the git history.

## Markdown format

Slides are separated by `---` on its own line. Instructions for the generator are iA Presenter comments: a line that starts with `//`.

Deck settings go at the top:

```
// seed: 49
// autoAdvance: 30000
// loop
// audio: audio/room.mp3
// fade: 2000
```

`autoAdvance` and `fade` are milliseconds. A bare `// loop` repeats the show. `// audio: stop` fades the bed to silence. `?seed=49` on the page URL overrides the file seed. `?chrome=0` hides the progress bar and the bottom buttons, for a browser source that should show only the slides. Arrow keys still move the show.

`// section: Name` starts a group. `// insert: 1` is the most fillers that group will receive. `// audio:` after a section marker replaces the bed from that section on.

`## Category` is the small upper-left kicker. `# Title` is the headline. A plain line under the title is the subtitle. `- item` is a bullet. Backgrounds stay `bg: path` or `![bg](path)`.

`// position: glued` sticks a slide to the previous slide, or to the start of the section when it is first. A run of glued slides is one unit, so nothing can land in front of it or between its members.

`// video: videos/story.mp4` is a fullscreen slide with no gradient, bug, or body text. It plays through and then advances. A missing file holds on black for one second and advances, so a deck still runs before the videos are added.

`// backdrop: blur` keeps the whole frame on a video slide. The sides are filled with a blurred enlargement of that same picture, so a portrait video stays full height instead of being cropped.

A video slide can carry a lower third. Any one of these four comments turns it on:

```
// name: Ada Lovelace
// title: Pastor
// buildIn: 3000
// buildOut: 8000
```

`name` is the top line and `title` is the bottom line. `buildIn` is when the logo slides in from the right and wipes the green bar on (default 3000 ms). `buildOut` is when that bar fades out over 2000 ms (default 8000 ms). The logo is `logo.png` again, parked one safe margin in from the left and up from the bottom.

`// type: fillers` at the bottom of the file switches the rest of the file into the reusable pool. Each section draws up to its insert count, one per legal gap, without repeating a card inside that section. A later section may draw the same card again. The section still ends on its last authored slide.

```
// section: Gathering
// insert: 1

// video: videos/gathering.mp4
// position: glued
// name: Name
// title: Title

---

// position: glued

## Growth in Christ

bg: images/mountain.jpg

# Welcome to FaithTree

St. Charles, Missouri

- A ministry of young adults seeking Jesus together
```

## Service features

These are for running a Sunday service from the deck. `examples/sunday-service.md` uses all of them.

`!include announcements.md` on its own line pastes that file in place, so one announcements deck can open and close every service. The path is relative to the file that names it and must stay inside the folder of the deck you build: absolute paths, `..`, and symlinks that lead outside are refused, and so is a file that includes itself, directly or around a loop. Picture and video paths inside an included file are still relative to the built page, the same as in the main file.

`!scripture John 3:16-18 (KJV)` on its own line becomes one or more slides of verse text, split between verses at about 330 characters, each with the range and translation as its kicker. Put it in a block of its own. The translation in parentheses is a SWORD module name; `// translation: WEB` changes the default for the lines after it (KJV otherwise). The verses come from `diatheke`, the SWORD command-line tool. If it is not installed, or the module is missing, the build stops and says so; it never writes an empty slide. `MDP_DIATHEKE=/path/to/diatheke` points at a copy that is not on the PATH.

Speaker notes start at a line that begins with `Note:` or `Notes:` (text may follow on the same line), or at `<!-- notes -->`, and run to the end of the slide, or to `<!-- /notes -->`. They are HTML-escaped and only shown in the notes view.

Song copyright notices are off by default. To enable them, add `// ccli: <licence number>` at the top of the deck, replacing the placeholder with your actual numeric licence number. Song metadata uses up to four positional fields:

```markdown
// song: Title | Authors | © year publisher | CCLI Song # number

# First song slide

Lyrics

---

# Last song slide

Lyrics

---

// songEnd

# Prayer
```

A song starts in the block containing `// song:` (or the next visible block if it contains only directives). It ends before the next `// song:`, `// songEnd`, `// section:`, or filler pool. Use `// songEnd` before unrelated slides in the same section. Included files carry the same song scope, so a song may span `!include` boundaries. A notice appears on the first and last authored slide of each song, once for a single-slide song. Filler slides do not inherit notices.

The notice joins the supplied nonempty fields with ` | `, then adds a separate `CCLI License # <number>` line. Only the title is required; empty optional fields can be kept as `||`, and nothing missing is invented. All notice text is HTML-escaped. Malformed song lines (missing title, missing colon, or more than four fields) warn with the original `file:line`, including inside includes. An invalid licence disables notices and warns. Directives inside speaker notes stay note text and cannot create a notice.

Generated notices use `.ccli-notice` with a small font outside the notes `<aside>`. This change supplies generator markup; final positioning and view styling belong to a later template change. The fixture-only Planning Center importer emits song metadata; usage reporting remains a follow-up. Tim still needs to supply the actual licence number, approve first-and-last placement, and decide which streaming licence applies to any streamed service.

The local importer runs as `perl tools/pco-import.pl --fixture plan.json --output service.md` (optionally `--translation WEB`; default KJV). It reads no credentials and makes no network calls. Each song item gets one `// song:` line before its lyric slides and a separate `// songEnd` block after them, including songs with missing-lyrics placeholders. Song title comes from the related Song resource, falling back to the item title if that resource is absent. Song `author`, `copyright`, and `ccli_number` are still **UNVERIFIED API fields**: fixture values are used when supplied, and missing values are omitted without invention. Empty middle positions remain empty to preserve the directive's four-field structure.

Within metadata fields, ASCII pipes become fullwidth `｜`, double slashes become `／／`, and leading presenter syntax gets the same neutralisation as imported prose. Multiline fields are rejected before any deck is written. The generator handles HTML escaping. Import output includes an operator reminder but never a `// ccli:` directive; add that directive by hand with the actual licence number to enable notices. The `pcoWarning` reminder follows the importer's existing warning-comment convention; the generator may report it as an unknown directive while omitting it from slide text.

Pre-service and post-service loops are sections:

```
// section: Before the Service
// insert: 0
// cycle: 8s
// countdown: 10:30am Worship begins in
// countdownEnd: next
```

`// cycle: 8s` turns the section over every 8 seconds and wraps to its own first slide, until the operator presses Next on its last slide. `// countdown: 10:30` shows "Service begins in 4:32" over the section, counting to that clock time; any words after the time replace "Service begins in". `// countdownEnd: next` moves on to the next section when it reaches zero (`stay`, the default, shows "Starting now"). Opening the deck after the time does not jump; `?now=10:25` on the page address pretends it is 10:25, for rehearsing.

### Views

`?view=` on the page address picks a view. It puts `view-<name>` on `<html>` and `<body>`.

- `audience` (default): the slides.
- `notes` (alias `confidence`): the slide small, its notes beside it, a still copy of the next slide (End after the last), the clock, the elapsed timer, the slide number, the countdown and the next slide's heading.
- `lyrics`: only the words, on a transparent page, for an OBS browser source.
- `overlay`: only lower thirds and the countdown, on a transparent page.
- `service` (alias `control`): the service order, every section and slide heading. Click one to go there. Along the bottom: Prev, Next, Black, Reset timer, the slide number, the timer and the clock.

`confidence` and `control` are the macOS app's names (`docs/1214-macos-app-design.md`); they open the same views. An unknown name opens the audience view.

Only the audience view makes sound. Windows of the same deck follow each other in one browser (BroadcastChannel), so the projector can show the plain page while the laptop shows `?view=notes` or `?view=service`, and either one drives. A window opened late joins on the current slide and the running timer.

Inside the macOS app the windows do not talk to each other: Swift owns the state and pushes it to each with `presenter.apply({index, black, timerStart})`, and a page asks for changes with `{type: 'request', index, black, timerStart}` (`macos/PresenterApp/Sources/PresenterCore/Bridge.swift`). `index` counts the play order, fillers included. Only the audience window runs timers, cycles and countdowns there. Each view starts hidden (audience black, lyrics and overlay transparent) until Swift's first `presenter.apply`, so a reload never flashes slide 1. A deck with no slides shows "This deck has no slides." and still reports `ready` with count 0.

### Keys

The keys are PowerPoint's and Proclaim's, so presentation clickers work.

- Next: Right, Down, Page Down, Space, Enter, N
- Back: Left, Up, Page Up, Backspace, P
- Home, End: first and last slide. A number then Enter jumps to that slide; digits not followed by Enter within 1.5 seconds are forgotten, so a stray digit never turns a later Enter into a jump.
- B or `.`: black screen. The next Next or Back brings the picture back without moving. On an auto-advancing deck or a cycling section the show keeps moving underneath the black, so the picture comes back at the live point.
- S: the service order over the slides; Esc closes it.
- F: fullscreen.

In the macOS app the clicker keys (arrows, Page Up/Down, Space, Home, End, B, `.`) are taken by the app before the page sees them; the others above still work through the page.

### Tests

`prove -l t/` runs the generator tests. `t/05-browser.t` drives a built deck in headless Chromium and is skipped when Chromium is not installed. Tests never call a real `diatheke`; `t/bin/fake-diatheke` stands in.

`macos/tools/check-views.js` checks the app views, keys, sync, overlay alpha and a faked native bridge with Playwright, and compares the audience view pixel for pixel with a baseline build:

```
perl generate.pl macos/fixtures/1214-demo.md build/cv/deck.html
PLAYWRIGHT=/path/to/node_modules/playwright node macos/tools/check-views.js build/cv/deck.html build/cv/baseline.html chromium
```

## Usage

1. Put your logo as `logo.png` in this directory (or edit the template to point elsewhere).
2. Write the slides in Markdown as above.
3. Generate:

```bash
perl generate.pl your-slides.md presentation.html
```

4. Open `presentation.html` in a browser.
   - Arrow keys / space to advance
   - `f` for fullscreen
   - Swipe on touch devices

The address bar keeps a `#` and the slide number in the built show, starting at `#1`. A refresh or a link with that anchor opens on that slide. The number includes any filler that was drawn into the list, and the same seed rebuilds the same list.

One click or keypress after the page opens unlocks sound for the rest of that page, including later loops. A reload needs the gesture again.

## Files

- `template.html` — the visual template and the playback script
- `generate.pl` — the Perl generator
- `sample.md` — a short example of the syntax
- `examples/sunday-service.md` — a service deck using includes, scripture, notes, loops and the countdown
- `lib/MdPresenter/` — the include and scripture code used by `generate.pl`
- `t/` — tests (`prove -l t/`)
- `pray-walk.md` — the September 2025 prayer-walk deck
- `presentation.html` — generated from `sample.md`

## Customization

- Logo: `logo.png` is the FaithTree bug. Replace that file, or edit the `<img src>` in `generate.pl`.
- Titles and bullets are Olivette, vendored under `fonts/olivette/` (SIL Open Font License; see `fonts/olivette/LICENSE.txt`). The upper-left topic line uses D-DIN Condensed, vendored under `fonts/d-din/` (SIL Open Font License; see `fonts/d-din/OFL-1.1.txt`). Colors, gradient strength, and bug size/speed live in `template.html`.
- The bug drops over 30 seconds via `@keyframes dropBug`, the same interval as `// autoAdvance: 30000`.
