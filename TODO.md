# TODO

Planned features for Markdown Presenter:

1. **Dual decks / random section inserts**
   - Main deck of unique slides.
   - Secondary "filler" deck of a few reusable slides that get randomly inserted into each section.
   - Requires section awareness.

2. **Section language**
   - Introduce section markers (proposal: `------` on its own line, or a YAML-style frontmatter / directive).
   - iA Presenter does not have native sections; this is an extension.
   - Sections group slides for the random-insert logic above and could also control transitions, audio, etc.

3. **Fullscreen video slides**
   - Slides that bypass the normal template (no gradients, bug, or text overlay).
   - Play a video fullscreen.
   - Auto-advance to the next slide when the video ends.
   - Markdown idea: `video: path/to/video.mp4` or a special content block.

4. **Background soundtrack**
   - Ambient/looping audio on normal (non-video) slides.
   - Fade out slowly when transitioning into a video slide.
   - Resume or start fresh on the next non-video slide.
   - Configurable via a top-level `audio:` directive or per-section.

All of the above look feasible with the current HTML/CSS/JS + Perl generator approach. The generator would need to emit additional data attributes or a JS config object, and the template's script would handle section logic, random insertion, video events, and Web Audio / HTML5 audio fading.
