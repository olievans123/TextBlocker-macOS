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

    private static let defaultPreset = Preset.builtIn.first { $0.name == "Default" } ?? Preset.builtIn[0]

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
    private let useAccurateModeKey = "useAccurateMode"

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

    @Published var useAccurateMode: Bool {
        didSet { defaults.set(useAccurateMode, forKey: useAccurateModeKey) }
    }

    @Published var selectedPresetName: String {
        didSet { defaults.set(selectedPresetName, forKey: selectedPresetKey) }
    }

    init() {
        let preset = SettingsService.defaultPreset

        self.ocrHeight = defaults.object(forKey: ocrHeightKey) as? Int ?? preset.ocrHeight
        self.sampleFPS = defaults.object(forKey: sampleFPSKey) as? Double ?? preset.sampleFPS
        self.padding = defaults.object(forKey: paddingKey) as? Int ?? preset.padding
        self.mergePad = defaults.object(forKey: mergePadKey) as? Int ?? preset.mergePad
        self.sceneThreshold = defaults.object(forKey: sceneThresholdKey) as? Int ?? preset.sceneThreshold
        self.forceInterval = defaults.object(forKey: forceIntervalKey) as? Double ?? preset.forceInterval
        self.maxFilters = defaults.object(forKey: maxFiltersKey) as? Int ?? 1200
        self.skipSimilar = defaults.object(forKey: skipSimilarKey) as? Bool ?? true
        self.useAccurateMode = defaults.object(forKey: useAccurateModeKey) as? Bool ?? true
        self.selectedPresetName = defaults.string(forKey: selectedPresetKey) ?? preset.name

        let qualityRaw = defaults.string(forKey: qualityKey) ?? preset.quality
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
        let preset = SettingsService.defaultPreset
        applyPreset(preset)
        maxFilters = 1200
        skipSimilar = true
        useAccurateMode = true
        languages = ["en", "fr", "de", "es", "it", "pt", "nl"]
    }
}
