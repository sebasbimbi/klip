// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
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
        )
    ]
)
