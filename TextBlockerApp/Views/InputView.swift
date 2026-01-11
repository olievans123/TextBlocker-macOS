import SwiftUI
import UniformTypeIdentifiers

struct InputView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel
    @State private var urlText = ""
    @State private var isTargeted = false
    @State private var isPlaylist = false

    private var isYouTubeURL: Bool {
        let patterns = [
            #"(www\.|m\.)?youtube\.com/watch\?.*v=[\w-]+"#,
            #"youtu\.be/[\w-]+"#,
            #"(www\.|m\.)?youtube\.com/playlist\?.*list=[\w-]+"#
        ]
        return patterns.contains { pattern in
            urlText.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private var isPlaylistURL: Bool {
        // Detect playlist URLs or video URLs with playlist context
        let playlistPatterns = [
            #"youtube\.com/playlist\?.*list=[\w-]+"#,
            #"[?&]list=[\w-]+"#
        ]
        return playlistPatterns.contains { pattern in
            urlText.range(of: pattern, options: .regularExpression) != nil
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            // URL Input Section
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)

                    TextField("Paste YouTube URL or drop files below...", text: $urlText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if isYouTubeURL {
                                processYouTube()
                            }
                        }

                    if urlText.isEmpty {
                        Button {
                            if let clipboardString = NSPasteboard.general.string(forType: .string) {
                                urlText = clipboardString
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Paste from clipboard")
                    } else {
                        Button {
                            urlText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear")
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isYouTubeURL ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                )

                if isYouTubeURL {
                    HStack(spacing: 16) {
                        Toggle(isOn: $isPlaylist) {
                            Label("Playlist", systemImage: "list.bullet.rectangle")
                        }
                        .toggleStyle(.checkbox)
                        .onChange(of: urlText) { _, _ in
                            // Auto-detect playlist from URL
                            if isPlaylistURL != isPlaylist {
                                isPlaylist = isPlaylistURL
                            }
                        }

                        Spacer()

                        Button {
                            processYouTube()
                        } label: {
                            Label("Process", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(processingVM.isProcessing)
                    }
                    .padding(.horizontal, 4)

                    if processingVM.isProcessing && !processingVM.currentPhase.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(processingVM.currentPhase)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal)

            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 2, dash: [8])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                    )

                VStack(spacing: 16) {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                        .font(.system(size: 56))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isTargeted)

                    Text("Drop video files or folders")
                        .font(.title3)
                        .fontWeight(.medium)

                    Text("MP4, MKV, MOV, AVI, WebM")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            selectFile()
                        } label: {
                            Label("Select File", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            selectFolder()
                        } label: {
                            Label("Select Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(32)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

            // Error display
            if let error = processingVM.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func processYouTube() {
        guard isYouTubeURL else { return }

        Task {
            if isPlaylist {
                await processingVM.processYouTubePlaylist(url: urlText)
            } else {
                await processingVM.processYouTubeVideo(url: urlText)
            }
            urlText = ""
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }

                Task { @MainActor in
                    var isDirectory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

                    if isDirectory.boolValue {
                        await processingVM.processFolder(at: url)
                    } else {
                        await processingVM.processVideo(at: url)
                    }
                }
            }
        }
        return true
    }

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select video files to process"

        if panel.runModal() == .OK {
            for url in panel.urls {
                Task {
                    await processingVM.processVideo(at: url)
                }
            }
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing videos"

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await processingVM.processFolder(at: url)
            }
        }
    }
}

#if DEBUG
struct InputView_Previews: PreviewProvider {
    static var previews: some View {
        InputView()
            .environmentObject(ProcessingViewModel())
    }
}
#endif
