import Foundation
import SwiftUI

enum VideoQuality: String, CaseIterable, Identifiable {
    case lossless = "lossless"
    case high = "high"
    case balanced = "balanced"
    case fast = "fast"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lossless: return "Lossless"
        case .high: return "High"
        case .balanced: return "Balanced"
        case .fast: return "Fast"
        }
    }

    var ffmpegArgs: [String] {
        switch self {
        case .lossless:
            return ["-c:v", "libx264", "-crf", "0", "-preset", "veryslow"]
        case .high:
            return ["-c:v", "libx264", "-crf", "18", "-preset", "slow"]
        case .balanced:
            return ["-c:v", "libx264", "-crf", "23", "-preset", "medium"]
        case .fast:
            return ["-c:v", "libx264", "-crf", "28", "-preset", "fast"]
        }
    }
}

class SettingsService: ObservableObject {
    static let shared = SettingsService()

    private let defaults = UserDefaults.standard

    // Keys
    private let ocrHeightKey = "ocrHeight"
    private let sampleFPSKey = "sampleFPS"
    private let paddingKey = "padding"
    private let mergePadKey = "mergePad"
    private let sceneThresholdKey = "sceneThreshold"
    private let forceIntervalKey = "forceInterval"
    private let qualityKey = "quality"
    private let languagesKey = "languages"
    private let maxFiltersKey = "maxFilters"
    private let skipSimilarKey = "skipSimilar"
    private let selectedPresetKey = "selectedPreset"

    @Published var ocrHeight: Int {
        didSet { defaults.set(ocrHeight, forKey: ocrHeightKey) }
    }

    @Published var sampleFPS: Double {
        didSet { defaults.set(sampleFPS, forKey: sampleFPSKey) }
    }

    @Published var padding: Int {
        didSet { defaults.set(padding, forKey: paddingKey) }
    }

    @Published var mergePad: Int {
        didSet { defaults.set(mergePad, forKey: mergePadKey) }
    }

    @Published var sceneThreshold: Int {
        didSet { defaults.set(sceneThreshold, forKey: sceneThresholdKey) }
    }

    @Published var forceInterval: Double {
        didSet { defaults.set(forceInterval, forKey: forceIntervalKey) }
    }

    @Published var quality: VideoQuality {
        didSet { defaults.set(quality.rawValue, forKey: qualityKey) }
    }

    @Published var languages: [String] {
        didSet { defaults.set(languages, forKey: languagesKey) }
    }

    @Published var maxFilters: Int {
        didSet { defaults.set(maxFilters, forKey: maxFiltersKey) }
    }

    @Published var skipSimilar: Bool {
        didSet { defaults.set(skipSimilar, forKey: skipSimilarKey) }
    }

    @Published var selectedPresetName: String {
        didSet { defaults.set(selectedPresetName, forKey: selectedPresetKey) }
    }

    init() {
        self.ocrHeight = defaults.object(forKey: ocrHeightKey) as? Int ?? 480
        self.sampleFPS = defaults.object(forKey: sampleFPSKey) as? Double ?? 1.0
        self.padding = defaults.object(forKey: paddingKey) as? Int ?? 14
        self.mergePad = defaults.object(forKey: mergePadKey) as? Int ?? 6
        self.sceneThreshold = defaults.object(forKey: sceneThresholdKey) as? Int ?? 8
        self.forceInterval = defaults.object(forKey: forceIntervalKey) as? Double ?? 2.0
        self.maxFilters = defaults.object(forKey: maxFiltersKey) as? Int ?? 1200
        self.skipSimilar = defaults.object(forKey: skipSimilarKey) as? Bool ?? true
        self.selectedPresetName = defaults.string(forKey: selectedPresetKey) ?? "Default"

        let qualityRaw = defaults.string(forKey: qualityKey) ?? VideoQuality.balanced.rawValue
        self.quality = VideoQuality(rawValue: qualityRaw) ?? .balanced

        // Include common Western languages by default for better text detection
        self.languages = defaults.object(forKey: languagesKey) as? [String] ?? ["en", "fr", "de", "es", "it", "pt", "nl"]
    }

    func applyPreset(_ preset: Preset) {
        ocrHeight = preset.ocrHeight
        sampleFPS = preset.sampleFPS
        padding = preset.padding
        mergePad = preset.mergePad
        sceneThreshold = preset.sceneThreshold
        forceInterval = preset.forceInterval
        quality = VideoQuality(rawValue: preset.quality) ?? .balanced
        selectedPresetName = preset.name
    }

    func resetToDefaults() {
        ocrHeight = 480
        sampleFPS = 1.0
        padding = 14
        mergePad = 6
        sceneThreshold = 8
        forceInterval = 2.0
        maxFilters = 1200
        skipSimilar = true
        quality = .balanced
        languages = ["en", "fr", "de", "es", "it", "pt", "nl"]
        selectedPresetName = "Default"
    }
}
