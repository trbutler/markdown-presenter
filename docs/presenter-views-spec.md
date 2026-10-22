# Presenter views spec (Tim, Oct 22 2026)

- SwiftUI Preferences window with a native list and a + button. Each entry is a view.
- Each view can be cast to any available macOS display and/or NDI, chosen per view. This replaces the overlay-vs-lyrics NDI question.
- Preloaded views: Main Slides, Overlay Slides and Presenter View. Each loads our deck URL with the right query string. There's also Custom, which takes any URL.
- Long term: the slide stack thinks in terms of arbitrary views, not a fixed three.
- macOS 27 only, no legacy code. Use Metal and Apple Silicon optimizations wherever they help (rendering, NDI frame capture and encoding, zero-copy IOSurface/CVPixelBuffer paths).
