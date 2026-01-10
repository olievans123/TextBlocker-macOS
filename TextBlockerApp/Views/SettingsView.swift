import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsService.shared

    var body: some View {
        Form {
            // Presets Section
            Section("Presets") {
                Picker("Preset", selection: $settings.selectedPresetName) {
                    ForEach(Preset.builtIn) { preset in
                        Text(preset.name).tag(preset.name)
                    }
                }
                .onChange(of: settings.selectedPresetName) { _, newValue in
                    if let preset = Preset.builtIn.first(where: { $0.name == newValue }) {
                        settings.applyPreset(preset)
                    }
                }

                Text("Presets provide optimized settings for different use cases")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Quality Section
            Section("Output Quality") {
                Picker("Quality", selection: $settings.quality) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                .pickerStyle(.segmented)

                qualityDescription
            }

            // OCR Section
            Section("Text Detection") {
                Toggle("Accurate Mode", isOn: $settings.useAccurateMode)
                Text("Better detection but slower processing")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("OCR Resolution")
                    Spacer()
                    Picker("", selection: $settings.ocrHeight) {
                        Text("360p (Fast)").tag(360)
                        Text("480p (Balanced)").tag(480)
                        Text("720p (Accurate)").tag(720)
                        Text("1080p (Best)").tag(1080)
                    }
                    .frame(width: 160)
                }

                HStack {
                    Text("Sample Rate")
                    Spacer()
                    Picker("", selection: $settings.sampleFPS) {
                        Text("0.5 fps (Fast)").tag(0.5)
                        Text("1.0 fps (Balanced)").tag(1.0)
                        Text("2.0 fps (Accurate)").tag(2.0)
                        Text("4.0 fps (Best)").tag(4.0)
                    }
                    .frame(width: 160)
                }

                TextField("Languages", text: languagesBinding)
                    .help("Comma-separated language codes (e.g., en,es,fr)")
            }

            // Advanced Section
            Section("Advanced") {
                HStack {
                    Text("Box Padding")
                    Spacer()
                    Stepper("\(settings.padding) px", value: $settings.padding, in: 0...50)
                        .frame(width: 120)
                }

                HStack {
                    Text("Merge Distance")
                    Spacer()
                    Stepper("\(settings.mergePad) px", value: $settings.mergePad, in: 0...30)
                        .frame(width: 120)
                }

                HStack {
                    Text("Scene Threshold")
                    Spacer()
                    Stepper("\(settings.sceneThreshold)", value: $settings.sceneThreshold, in: 1...20)
                        .frame(width: 120)
                }
                Text("Lower = more sensitive to scene changes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Force OCR Interval")
                    Spacer()
                    Stepper("\(String(format: "%.1f", settings.forceInterval))s", value: $settings.forceInterval, in: 0.5...10, step: 0.5)
                        .frame(width: 120)
                }

                Toggle("Skip Similar Frames", isOn: $settings.skipSimilar)

                HStack {
                    Text("Max Filters")
                    Spacer()
                    TextField("", value: $settings.maxFilters, format: .number)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Dependencies Section
            Section("Dependencies") {
                dependencyRow(name: "ffmpeg")
                dependencyRow(name: "yt-dlp")

                Text("Install with: brew install ffmpeg yt-dlp")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Reset Section
            Section {
                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.red)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450)
    }

    private var languagesBinding: Binding<String> {
        Binding(
            get: { settings.languages.joined(separator: ", ") },
            set: { newValue in
                settings.languages = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }

    @ViewBuilder
    private var qualityDescription: some View {
        let description: String = {
            switch settings.quality {
            case .lossless: return "No quality loss, largest file size"
            case .high: return "Near-lossless, good for archiving"
            case .balanced: return "Good quality, reasonable file size"
            case .fast: return "Quick encoding, smaller file size"
            }
        }()

        Text(description)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func dependencyRow(name: String) -> some View {
        let exists = DependencyLocator.isInstalled(name)

        HStack {
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(exists ? .green : .red)

            Text(name)

            Spacer()

            Text(exists ? "Installed" : "Not found")
                .font(.caption)
                .foregroundColor(exists ? .secondary : .red)
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
