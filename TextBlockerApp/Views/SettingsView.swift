import SwiftUI

struct SupportedLanguage: Identifiable {
    let id: String  // Language code
    let name: String
    let flag: String

    static let all: [SupportedLanguage] = [
        // Common
        SupportedLanguage(id: "en", name: "English", flag: "🇬🇧"),
        SupportedLanguage(id: "es", name: "Spanish", flag: "🇪🇸"),
        SupportedLanguage(id: "fr", name: "French", flag: "🇫🇷"),
        SupportedLanguage(id: "de", name: "German", flag: "🇩🇪"),
        SupportedLanguage(id: "it", name: "Italian", flag: "🇮🇹"),
        SupportedLanguage(id: "pt", name: "Portuguese", flag: "🇵🇹"),
        SupportedLanguage(id: "nl", name: "Dutch", flag: "🇳🇱"),
        // Asian
        SupportedLanguage(id: "zh-Hans", name: "Chinese (Simplified)", flag: "🇨🇳"),
        SupportedLanguage(id: "zh-Hant", name: "Chinese (Traditional)", flag: "🇹🇼"),
        SupportedLanguage(id: "ja", name: "Japanese", flag: "🇯🇵"),
        SupportedLanguage(id: "ko", name: "Korean", flag: "🇰🇷"),
        SupportedLanguage(id: "vi", name: "Vietnamese", flag: "🇻🇳"),
        SupportedLanguage(id: "th", name: "Thai", flag: "🇹🇭"),
        // Other European
        SupportedLanguage(id: "ru", name: "Russian", flag: "🇷🇺"),
        SupportedLanguage(id: "pl", name: "Polish", flag: "🇵🇱"),
        SupportedLanguage(id: "uk", name: "Ukrainian", flag: "🇺🇦"),
        SupportedLanguage(id: "cs", name: "Czech", flag: "🇨🇿"),
        SupportedLanguage(id: "ro", name: "Romanian", flag: "🇷🇴"),
        SupportedLanguage(id: "el", name: "Greek", flag: "🇬🇷"),
        SupportedLanguage(id: "tr", name: "Turkish", flag: "🇹🇷"),
        // Other
        SupportedLanguage(id: "ar", name: "Arabic", flag: "🇸🇦"),
        SupportedLanguage(id: "he", name: "Hebrew", flag: "🇮🇱"),
        SupportedLanguage(id: "hi", name: "Hindi", flag: "🇮🇳"),
    ]
}

struct SettingsView: View {
    @StateObject private var settings = SettingsService.shared
    @State private var showLanguagePicker = false

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

            // Output Location Section
            Section("Output Location") {
                Toggle("Use custom output folder", isOn: $settings.useCustomOutput)

                if settings.useCustomOutput {
                    HStack {
                        if let outputDir = settings.outputDirectory {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                            Text(outputDir.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No folder selected")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button("Choose...") {
                            selectOutputFolder()
                        }
                    }

                    Text("Processed videos will be saved to this folder instead of next to the original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Processed videos will be saved next to the original file")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

                // Language selection
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Languages")
                        Spacer()
                        Button {
                            showLanguagePicker.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(settings.languages.count) selected")
                                    .foregroundColor(.secondary)
                                Image(systemName: showLanguagePicker ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // Show selected languages as tags
                    if !settings.languages.isEmpty {
                        FlowLayout(spacing: 4) {
                            ForEach(settings.languages, id: \.self) { code in
                                if let lang = SupportedLanguage.all.first(where: { $0.id == code }) {
                                    HStack(spacing: 2) {
                                        Text(lang.flag)
                                        Text(lang.name)
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.15))
                                    .cornerRadius(12)
                                } else {
                                    Text(code)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }

                    if showLanguagePicker {
                        Divider()
                        languagePickerGrid
                    }
                }
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

    @ViewBuilder
    private var languagePickerGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 8) {
            ForEach(SupportedLanguage.all) { lang in
                Button {
                    toggleLanguage(lang.id)
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.name)
                            .lineLimit(1)
                        Spacer()
                        if settings.languages.contains(lang.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(settings.languages.contains(lang.id) ? Color.accentColor.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleLanguage(_ code: String) {
        if let index = settings.languages.firstIndex(of: code) {
            settings.languages.remove(at: index)
        } else {
            settings.languages.append(code)
        }
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

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Select output folder for processed videos"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
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

// MARK: - FlowLayout for displaying language tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = y + rowHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif
