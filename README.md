# FaithTree / Markdown Presenter

A lightweight HTML presentation generator that replicates a Keynote-style template:

- Full-bleed photo background per slide
- Soft black-to-transparent gradients top and bottom
- Animated "bug" (circular FaithTree logo that drops from top-right to bottom over 30 seconds)
- Headline + up to three bullet points that fade in

See [TODO.md](TODO.md) for planned features (sections, random section inserts, fullscreen video slides, background soundtrack with fade).

## Markdown Format

Slides are separated by `---` on its own line.

Each slide can specify a background with either:

```
bg: path/to/image.jpg
```

or

```
![bg](path/to/image.jpg)
```

Then a `# Heading` and `- Bullet` lines.

Example (`sample.md`):

```
bg: images/mountain.jpg

# Welcome to FaithTree

- A ministry of young adults seeking Jesus together
- Gathering for worship, prayer, and fellowship
- Rooted in the Gospel across the St. Louis area

---

bg: images/forest.jpg

# What We Do

- Sunset Services three times a month
- Feasty Fridays with food and conversation
- Prayer walks, film nights, and more
```

## Usage

1. Put your logo as `logo.png` in this directory (or edit the template to point elsewhere / use a different path).
2. Write your slides in Markdown as above.
3. Generate:

```bash
perl generate.pl your-slides.md presentation.html
```

4. Open `presentation.html` in a browser.
   - Arrow keys / space to advance
   - `f` for fullscreen
   - Swipe on touch devices

## Files

- `template.html` — the visual template (CSS animations, layout)
- `generate.pl` — the Perl generator
- `sample.md` — example input
- `presentation.html` — generated example (uses Unsplash images)

## Customization

- Logo: replace `logo.png` or edit the `<img src>` in `generate.pl`.
- Colors, fonts, gradient strength, bug size/speed: edit `template.html`.
- Animation timing: the bug drops over 30s via `@keyframes dropBug`. Change the duration as desired.
- Text fade delay: controlled by the `animation` on `.content`.

The output is a single self-contained HTML file (plus the images and logo you reference).
