// swift-tools-version:5.9
// FotoAsist GC — open-source edition (GPL-3.0-or-later).
// No external Swift packages. System libraries: SQLite, ImageIO, Vision (macOS) and LibRaw (built by scripts/build_libraw.sh).
// Build and test through scripts/swift.sh, which passes the LibRaw include/library paths. See BUILDING.md.
import PackageDescription

let openEdition: [SwiftSetting] = [.define("GDC_PA_OPEN_EDITION")]

let package = Package(
    name: "PhotoCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "PhotoCore", targets: ["PhotoCore"]),
        .library(name: "PhotoRaw", targets: ["PhotoRaw"]),
        .library(name: "PhotoResolve", targets: ["PhotoResolve"]),
        .executable(name: "PhotoAssist", targets: ["PhotoAssist"]),
        .executable(name: "PhotoDecode", targets: ["PhotoDecode"]),
    ],
    targets: [
        // Open-edition feature policy and update check (no account, activation, trial or licensing server).
        .target(name: "PhotoAccess"),
        .target(name: "PhotoCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "CPhotoCore", path: "Sources/CPhotoCore", publicHeadersPath: "include",
                cxxSettings: [.define("GDC_PC_OPEN_EDITION"), .unsafeFlags(["-std=c++17", "-O2"])]),
        .systemLibrary(name: "CLibRaw", path: "Sources/CLibRaw"),
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(name: "PhotoRaw", dependencies: ["CLibRaw", "CZlib", "PhotoCore"]),
        .target(name: "PhotoResolve", dependencies: ["PhotoCore", "PhotoRaw", "CPhotoCore"],
                resources: [.copy("Resources/resolve_worker.py"), .copy("Resources/drx_chain.py"), .copy("Resources/charts")],
                swiftSettings: openEdition),
        .target(name: "PhotoAssistUI", dependencies: ["PhotoCore", "PhotoRaw", "PhotoResolve", "PhotoAccess"],
                resources: [.copy("Resources/Brand")], swiftSettings: openEdition),
        .executableTarget(name: "PhotoAssist", dependencies: ["PhotoAssistUI"]),
        .executableTarget(name: "PhotoDecode", dependencies: ["PhotoRaw", "PhotoResolve", "CPhotoCore"]),
        .testTarget(name: "PhotoAccessTests", dependencies: ["PhotoAccess"]),
        .testTarget(name: "PhotoCoreTests", dependencies: ["PhotoCore"]),
        .testTarget(name: "PhotoRawTests", dependencies: ["PhotoRaw", "PhotoCore"]),
        .testTarget(name: "CPhotoCoreTests", dependencies: ["CPhotoCore", "PhotoRaw"]),
        .testTarget(name: "PhotoAssistUITests", dependencies: ["PhotoAssistUI", "PhotoResolve", "PhotoCore"]),
        .testTarget(name: "PhotoResolveTests", dependencies: ["PhotoResolve", "PhotoRaw", "PhotoCore"]),
    ]
)
