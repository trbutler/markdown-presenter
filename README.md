# FaithTree / Markdown Presenter

The `feature/display-control` branch adds a separate live lower-third service.
Existing deck generation and playback are preserved. See [Live display setup](docs/display-control.md)
for OBS, iPad controls, Companion, and the theme folder interface.

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

`autoAdvance` and `fade` are milliseconds. A bare `// loop` repeats the show. `// audio: stop` fades the bed to silence. `?seed=49` on the page URL overrides the file seed.

`// section: Name` starts a group. `// insert: 1` is the most fillers that group will receive. `// audio:` after a section marker replaces the bed from that section on.

`## Category` is the small upper-left kicker. `# Title` is the headline. A plain line under the title is the subtitle. `- item` is a bullet. Backgrounds stay `bg: path` or `![bg](path)`.

`// position: glued` sticks a slide to the previous slide, or to the start of the section when it is first. A run of glued slides is one unit, so nothing can land in front of it or between its members.

`// video: videos/story.mp4` is a fullscreen slide with no gradient, bug, or body text. It plays through and then advances. A missing file holds on black for one second and advances, so a deck still runs before the videos are added.

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
- `pray-walk.md` — the September 2025 prayer-walk deck
- `presentation.html` — generated from `sample.md`

## Customization

- Logo: `logo.png` is the FaithTree bug. Replace that file, or edit the `<img src>` in `generate.pl`.
- Titles and bullets are Olivette, vendored under `fonts/olivette/` (SIL Open Font License; see `fonts/olivette/LICENSE.txt`). The upper-left topic line uses D-DIN Condensed, vendored under `fonts/d-din/` (SIL Open Font License; see `fonts/d-din/OFL-1.1.txt`). Colors, gradient strength, and bug size/speed live in `template.html`.
- The bug drops over 30 seconds via `@keyframes dropBug`, the same interval as `// autoAdvance: 30000`.
