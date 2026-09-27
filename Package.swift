// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AntiscopeCore", platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AntiscopeCore", targets: ["AntiscopeCore"])],
    targets: [.target(name: "AntiscopeCore"), .testTarget(name: "AntiscopeCoreTests", dependencies: ["AntiscopeCore"])])
