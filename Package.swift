// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AltiscopeCore", platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "AltiscopeCore", targets: ["AltiscopeCore"])],
    targets: [.target(name: "AltiscopeCore"), .testTarget(name: "AltiscopeCoreTests", dependencies: ["AltiscopeCore"])])
