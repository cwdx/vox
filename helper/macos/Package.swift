// swift-tools-version:6.0
// The vox dictation helper for macOS. FluidAudio runs Parakeet on the Neural Engine for the final pass; it is pinned to the commit
// the benchmark measured. Info.plist is linked in for the microphone and speech-recognition permission strings.
import PackageDescription

let package = Package(
  name: "vox-helper",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "9c9f630b65256101175569276dcd1cc6edaa5e37"),
  ],
  targets: [
    .executableTarget(
      name: "vox-helper",
      dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
      swiftSettings: [.swiftLanguageMode(.v5)],
      linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", "Info.plist"])]
    ),
  ]
)
