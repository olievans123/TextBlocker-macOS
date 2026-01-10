import Foundation

struct Preset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var ocrHeight: Int
    var sampleFPS: Double
    var padding: Int
    var mergePad: Int
    var sceneThreshold: Int
    var forceInterval: Double
    var quality: String

    init(
        id: UUID = UUID(),
        name: String,
        ocrHeight: Int = 360,
        sampleFPS: Double = 1.0,
        padding: Int = 14,
        mergePad: Int = 6,
        sceneThreshold: Int = 8,
        forceInterval: Double = 2.0,
        quality: String = "balanced"
    ) {
        self.id = id
        self.name = name
        self.ocrHeight = ocrHeight
        self.sampleFPS = sampleFPS
        self.padding = padding
        self.mergePad = mergePad
        self.sceneThreshold = sceneThreshold
        self.forceInterval = forceInterval
        self.quality = quality
    }

    static let builtIn: [Preset] = [
        Preset(
            name: "Default",
            ocrHeight: 360,
            sampleFPS: 1.0,
            padding: 14,
            mergePad: 6,
            sceneThreshold: 8,
            forceInterval: 2.0,
            quality: "balanced"
        ),
        Preset(
            name: "Fast Preview",
            ocrHeight: 240,
            sampleFPS: 0.5,
            padding: 12,
            mergePad: 8,
            sceneThreshold: 12,
            forceInterval: 3.0,
            quality: "fast"
        ),
        Preset(
            name: "High Quality",
            ocrHeight: 480,
            sampleFPS: 2.0,
            padding: 16,
            mergePad: 4,
            sceneThreshold: 6,
            forceInterval: 1.0,
            quality: "high"
        ),
        Preset(
            name: "Aggressive",
            ocrHeight: 360,
            sampleFPS: 1.0,
            padding: 20,
            mergePad: 10,
            sceneThreshold: 10,
            forceInterval: 2.0,
            quality: "balanced"
        )
    ]
}
