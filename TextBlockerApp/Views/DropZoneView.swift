import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel
    @State private var isTargeted = false

    private let supportedTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

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
                        .font(.system(size: 64))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: isTargeted)

                    Text("Drop video files or folders here")
                        .font(.title2)
                        .fontWeight(.medium)

                    Text("Supported: MP4, MKV, MOV, AVI, WebM")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Button {
                            selectFile()
                        } label: {
                            Label("Select File", systemImage: "doc.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            selectFolder()
                        } label: {
                            Label("Select Folder", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 8)
                }
                .padding(40)
            }
            .frame(maxWidth: 500, maxHeight: 350)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }

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
            }

            Spacer()
        }
        .padding(24)
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

#Preview {
    DropZoneView()
        .environmentObject(ProcessingViewModel())
}
