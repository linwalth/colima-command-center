// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ColimaCommandCenter",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ColimaCommandCenter",
            path: "Sources/ColimaCommandCenter",
            resources: [
                .copy("../Resources/de.lproj"),
                .copy("../Resources/en.lproj"),
                .copy("../Resources/apps.json")
            ]
        )
    ]
)
