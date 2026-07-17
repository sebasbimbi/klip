// swift-tools-version: 5.10
// 5.10 (not 6.0) on purpose: it is the floor for swift-testing while keeping the Swift 5 language
// mode. Tools 6.0 would switch the package to Swift 6 strict concurrency, which this AppKit app is
// not ready for. swift-testing (not XCTest) because XCTest ships only with Xcode, and Klip builds
// on the Command Line Tools alone — see build.sh.
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned to 0.18.x: WhisperKit is pre-1.0, so any 0.x bump can break the API. Bump deliberately.
        .package(url: "https://github.com/argmaxinc/WhisperKit", .upToNextMinor(from: "0.18.0"))
    ],
    targets: [
        .executableTarget(
            name: "Klip",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/Klip",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Vision"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        // Pure-logic only: no UI, no disk, no network. Everything else in Klip needs a running
        // NSApplication or the user's real ~/Library, which a test target has no business touching.
        .testTarget(name: "KlipTests", dependencies: ["Klip"], path: "Tests/KlipTests")
    ]
)
