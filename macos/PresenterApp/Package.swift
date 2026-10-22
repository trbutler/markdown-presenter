// swift-tools-version:5.9
// markdown-presenter macOS playback app (hub 1214). Build without Xcode:
//   swift build -c release && .build/release/PresenterApp path/to/deck.html
import PackageDescription

let package = Package(
    name: "PresenterApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PresenterApp", targets: ["PresenterApp"])
    ],
    targets: [
        // Platform-neutral logic (state, key map, bridge protocol, display
        // assignment, frame sinks). No AppKit or WebKit, so it can be
        // type-checked and unit-tested on any Swift toolchain.
        .target(name: "PresenterCore"),
        // AppKit + WKWebView shell: windows, menus, key routing, NDI capture.
        .executableTarget(name: "PresenterApp", dependencies: ["PresenterCore"]),
        .testTarget(name: "PresenterCoreTests", dependencies: ["PresenterCore"])
    ]
)
