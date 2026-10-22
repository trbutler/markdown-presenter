# Hub 1213: markdown-presenter as a Proclaim replacement

Status: design plus phase 1 code on branch `review/hubsup-1213-phase1`. Nothing has been merged or pushed.

Branch base: the first commit on the branch is a copy of Tim's uncommitted working tree (`generate.pl`, `template.html`, `sample.md`, `README.md`, `TODO.md`, `.gitignore`) as of 2026-10-22. The committed `main` still has the old 90-line generator, and work on top of that would conflict with everything Tim has since written. His own checkout was only read. The commits after that snapshot are the 1213 work.

Compatibility with hub 1214 (the native macOS app): views are chosen with `?view=audience|notes|lyrics|overlay|service`. That puts `view-<name>` on both `<html>` and `<body>` and sets `data-view` on `<body>`. A native shell can load the same HTML file with a different query in each window. The BroadcastChannel sync described under (c) works between those windows only if they share a web origin. Otherwise the native app can send the same small `{type:'show', n, node}` messages itself.

## Requirements and phases

| Req | What | Phase | State |
|-----|------|-------|-------|
| a | Songs from Planning Center Services (preferred) or CCLI SongSelect | 2 | designed below; CCLI direct is not feasible |
| b | Scripture via SWORD/diatheke | 1 | built: `!scripture John 3:16-18 (KJV)`; parser tested; diatheke not installed on dawnredwood |
| c | PowerPoint/Proclaim keys, clicker-safe; service view for jumping | 1 | built |
| d | MIDI on slide change (Web MIDI) | 2 | designed below |
| e | Lower thirds | 1 (exists) / 2 | Tim's video-slide lower third already works and shows in `view=overlay`; manual trigger designed |
| f | CSS display variants (lyrics-only for OBS) | 1 | built: `lyrics`, `overlay` |
| g | Presenter notes view; notes hidden elsewhere | 1 | built |
| h | Pre/post-service loops; countdown to a clock time | 1 | built: `// cycle`, `// countdown`, `// countdownEnd` |
| i | Includes for reusable decks | 1 | built: `!include` |

### Phase 1 (built, on the branch)

1. `!include path.md`: line-level and recursive. The path is relative to the including file. It must stay inside the top-level deck's folder: absolute, `~`, drive-letter and backslash paths are refused, as is any `..` segment and any symlink whose real path leaves the folder. Cycles are reported as a chain (`a.md -> b.md -> a.md`), with a depth limit of 16. Every error names `file:line`. Code: `lib/MdPresenter/Expand.pm`.
2. Speaker notes: `Note:` / `Notes:` at the start of a line, or `<!-- notes -->`, up to the end of the slide or `<!-- /notes -->`. They are rendered as `<aside class="notes">` inside the slide, which is always `display:none`. The notes view copies them into its own panel.
3. Views via `?view=`: audience (default), notes, lyrics, overlay and service. Only the audience view makes sound. Lyrics and overlay hide the chrome and use a transparent page.
4. Keys: Next is Right, Down, PageDown, Space, Enter or N. Back is Left, Up, PageUp, Backspace or P. Home and End go to the first and last slide, and a number followed by Enter jumps to that slide. B or `.` blacks the screen (in lyrics and overlay views this clears the screen instead). Next or Back from black only restores the picture, which is PowerPoint's behaviour, so a clicker never skips a slide the room has not seen. S opens the service order over any view and Esc closes it. Windows of one deck stay in step over BroadcastChannel, black state included. A window opened late asks the others for the current slide instead of pulling them back to slide 1.
5. Scripture: `!scripture <ref> (<MODULE>)`, with `// translation: WEB` setting the default for later lines. The parser handles book names, abbreviations and numbered books (`1 Jn`, `I John`, `First John`). It accepts verse ranges, cross-chapter ranges, whole chapters, comma lists and `;` groups. Single-chapter books take a bare verse (`Jude 3`). It checks chapter counts against KJV versification, rejects backwards ranges, and only accepts module names matching `[A-Za-z0-9_]`. diatheke runs as an argument list, never through a shell. Verses are packed into slides of about 330 characters and never split. Each slide's kicker is its own range, for example `John 3:16-17 (KJV)`. If diatheke is missing, the module is missing, or diatheke exits non-zero, the build stops with a message saying which. Code: `lib/MdPresenter/Scripture.pm`.
6. Loops and countdown: `// cycle: 8s` makes a section an auto-advancing loop that wraps within itself. `// countdown: 10:30am [label]` overlays the time left. `// countdownEnd: next` leaves the section at zero, but only if that window saw time left, so opening or rehearsing late never jumps. `?now=10:25` fakes the clock for rehearsal.

Tests: `prove -l t/` (unit, end-to-end generator, and a headless Chromium run of a built deck). Tim's `pray-walk.md` builds to byte-identical slide markup with the old and new generator. The only difference is the deck config, where each section gains four null keys.

### Phase 2: Planning Center import (designed, not built)

Workflow: build the service in Planning Center Services, then run `perl pco-import.pl --plan <id> > services/2026-10-25.md`. That writes plain Markdown the operator can edit, and `generate.pl` builds it like any other deck. The importer is a separate step, so Sunday morning never depends on the network.

Mapping, per plan item, in order:

- `header` item: becomes `// section: <title>`.
- `song` item: the arrangement's lyrics are split into slides on blank lines (or section labels such as `Verse 1`, `Chorus`), in the order of the arrangement `sequence` when it has one. The song title is the kicker. The last slide carries the CCLI notice (see below).
- `item` with a title such as "Scripture: John 3:16-18" becomes `!scripture John 3:16-18`. A plan-level or item-level field chooses the translation.
- `media` item: becomes `// video:` when a local file of that name exists, otherwise a placeholder slide with a warning.
- Item description and item notes: become `Note:` blocks.
- Announcements: `!include announcements.md`.

API facts and what still needs checking:

- Docs: https://developer.planning.center/docs/#/apps/services and https://github.com/planningcenter/developers. A Personal Access Token is an application ID plus a secret, sent with HTTP Basic auth (source: the developers repo). OAuth 2 is for apps used by other organisations, and this tool does not need it.
- Endpoint (from memory; check it against the docs with a real token): `GET /services/v2/service_types/{st}/plans/{plan}/items?include=song,arrangement,key`. Lyrics should be on the Arrangement (`lyrics`, `chord_chart`, `sequence`). Not verified: whether third-party API reads return lyrics that came in through Planning Center's SongSelect import. Lyrics exist in Planning Center only if the church typed them in or imported them. The SongSelect import needs a SongSelect subscription and an admin to enable it (https://www.planningcenter.com/blog/songselect-by-ccli-integration).
- Rate limit, reported by a third-party source only: 100 requests per 20 seconds (https://www.usecarly.com/blog/planning-center-api/). One plan import is a handful of requests.
- Tests: the importer would run only against a recorded JSON fixture (`t/fixtures/pco/plan.json`). No test or build step would call the live API.

Secrets (PCO token):

- The token lives in `~/.config/markdown-presenter/pco.json`, mode 0600, as `{"application_id": "...", "secret": "..."}`. `MDP_PCO_CREDENTIALS=/path` can point elsewhere.
- The importer refuses a credentials file that is group- or world-readable, or that sits inside the repository (it resolves both real paths and compares them). `.gitignore` would also list `pco.json` as a second guard.
- The token never appears in generated Markdown or HTML, in error messages, or in `--verbose` output. Errors say "Planning Center refused the token (401)" and nothing more.
- The importer never creates a token. Tim creates one at api.planningcenteronline.com under Personal Access Tokens and writes the file himself.

### Phase 2: CCLI SongSelect

- I found no public SongSelect API. Secondhand reports say it was partner-only (OAuth with PKCE plus a subscription key) and that CCLI is not taking new partners. Contact: partners@ccli.com (unverified: https://git.stadtmission-butzbach.de/public/pp-planer/src/branch/master/CCLI-API.md). Plan to bring SongSelect lyrics in through Planning Center's own SongSelect integration, not by calling CCLI directly.
- Licensing when projecting lyrics: the CCLI Church Copyright License covers projecting lyrics in worship. Common practice is to show the song title, writers, copyright line and the church's CCLI licence number once per song, usually on the first or last slide (third-party summary: https://www.musicademy.com/blog/how-to-properly-display-copyright-notices-for-ccli-license-holders/). Get CCLI's own wording before relying on that. Usage reporting goes to CCLI, and for sampled churches this is periodic (https://mediashout.com/?p=313822).
- Proposed: `// ccli: 1234567` at deck level. A song slide's last page gets a small footer line with the song's copyright line and `CCLI License #1234567`. The importer writes each song's `ccli_number` and copyright line into a directive. A run log, `services/ccli-log.csv`, lists date, song and CCLI number to help with reporting. Automatic reporting is out of scope without CCLI API access.
- Livestream (the OBS lyrics view): showing lyrics in a stream needs the separate CCLI Streaming License (https://www.vineyardchurches.org.uk/?p=18464, a UK source; check the US terms).

### Phase 2: MIDI on slide change (designed, not built)

- Directive `// midi: pc 1 5` (program change, channel 1, program 5), `// midi: note 1 60` or `// midi: cc 1 20 127`, on the slide that should send it. A deck-level `// midiOut: <port name substring>` picks the port.
- Only the audience window sends, so two open windows never send twice. It sends after `showSlide` settles, and does not send again when a remote sync message re-shows the same slide.
- Browser support: Chrome and Edge, behind a permission prompt (https://developer.chrome.com/blog/web-midi-permission-prompt); Firefox 108 and later with permission; no Safari (https://caniuse.com/webmidi). It needs a secure context (https://developer.mozilla.org/en-US/docs/Web/API/Navigator/requestMIDIAccess). `file://` behaviour varies, so serve the deck from `http://localhost` (for example `python3 -m http.server`). The macOS app from 1214 could send MIDI natively instead, which would avoid both the Safari gap and the permission prompt.

### Phase 2: lower thirds (bonus)

Tim's lower third already exists on video slides (`// name`, `// title`, `buildIn`, `buildOut`) and shows alone in `view=overlay`. The next step is to allow the same directives on any slide, plus a key (L) that fires or clears it by hand. It would use the same CSS and timing.

## Scripture translations and licensing

- Public domain, safe to project and stream: KJV (outside the UK, where Crown patent applies), ASV, WEB (World English Bible), and BSB (Berean Standard Bible, listed as public domain on eBible.org: https://ebible.org/details.php?id=engbsb). The status of the KJV, WEB and ASV SWORD modules was not checked against CrossWire's pages.
- Copyrighted: ESV allows up to 500 verses without written permission, never half a book, with a notice required (third-party copy of the notice: https://store.thegospelcoalition.org/assets/product_downloads/286/IHIZ3v3RNuRtDtfWEt0nXmkWGVGMvksVoXUrDfz8.pdf; check crossway.org). NIV allows 500 verses, and church non-saleable media need only "NIV" (https://www.biblica.com/permissions/). Whether projection counts is not stated. These are generally not available as free SWORD modules.
- diatheke: `diatheke -b KJV -f plain -k "John 3:16"`, and `-k` must come last (https://wiki.crosswire.org/Frontends:Diatheke). The parser expects plain output in the form `John 3:16: text`, with a `(KJV)` trailer. That layout comes from memory and the test fixture, not from a real run. diatheke is not installed on dawnredwood, so check the parser against real output once it is.

## Decisions only Tim can make

1. Planning Center: whether to use it, which service type, and whether to create a Personal Access Token and save it as described above. Also whether the church's arrangements actually hold lyrics (typed in or imported from SongSelect).
2. Bible translations: the default module (KJV is set now) and whether to use WEB or BSB for modern English. Installing diatheke and modules is a machine change, and nothing was installed for this ticket.
3. CCLI: the licence number, where the notice goes (first or last slide of each song), and whether services are streamed (Streaming Licence).
4. MIDI: which device and port (lighting desk, ProPresenter, or a sound board scene recall), which messages, and whether MIDI belongs in the browser or in the 1214 macOS app.
5. Key choices: Enter as Next (PowerPoint) and Backspace as Back; whether B should also pause the music.
6. The base snapshot: whether to commit his working tree on `main` first, so that this branch rebases onto it cleanly.
