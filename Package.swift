// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Scad2Stl",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/Euclid.git", from: "0.7.0")
    ],
    targets: [
        .executableTarget(
            name: "Scad2Stl",
            dependencies: [
                "Euclid"
            ],
            path: "Sources/Scad2Stl"
        ),
        .testTarget(
            name: "Scad2StlTests",
            dependencies: [
                "Scad2Stl",
                "Euclid"
            ],
            path: "Tests/Scad2StlTests"
        )
    ]
)
