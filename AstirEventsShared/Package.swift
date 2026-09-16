// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AstirEventsShared",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "AstirEventsShared", targets: ["AstirEventsShared"])],
    targets: [
        .target(name: "AstirEventsShared", path: "Contracts"),
        .testTarget(name: "AstirEventsContractTests", dependencies: ["AstirEventsShared"], path: "Tests")
    ]
)
