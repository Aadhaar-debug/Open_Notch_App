// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenNotch",
            path: "Sources/OpenNotch",
            swiftSettings: [.unsafeFlags(["-O"])],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("EventKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
