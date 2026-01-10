import SwiftUI

struct YouTubeInputView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel
    @State private var urlText = ""
    @State private var isPlaylist = false
    @State private var isValidURL = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)

                Text("YouTube Video")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Enter a YouTube video or playlist URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)

                    TextField("https://youtube.com/watch?v=...", text: $urlText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            processURL()
                        }
                        .onChange(of: urlText) { _, newValue in
                            validateURL(newValue)
                        }

                    if !urlText.isEmpty {
                        Button {
                            urlText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isValidURL ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
                )

                Toggle(isOn: $isPlaylist) {
                    Label("Process as playlist", systemImage: "list.bullet.rectangle")
                }
                .toggleStyle(.checkbox)

                Button {
                    processURL()
                } label: {
                    HStack {
                        if processingVM.isProcessing {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text(processingVM.isProcessing ? "Processing..." : "Process Video")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isValidURL || processingVM.isProcessing)
            }
            .frame(maxWidth: 400)

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

            // Tips section
            VStack(alignment: .leading, spacing: 8) {
                Text("Supported URLs:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Group {
                    Text("youtube.com/watch?v=...")
                    Text("youtu.be/...")
                    Text("youtube.com/playlist?list=...")
                }
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
                .padding(.leading, 12)
            }
            .frame(maxWidth: 400, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding(24)
    }

    private func validateURL(_ url: String) {
        let patterns = [
            #"youtube\.com/watch\?v=[\w-]+"#,
            #"youtu\.be/[\w-]+"#,
            #"youtube\.com/playlist\?list=[\w-]+"#
        ]

        isValidURL = patterns.contains { pattern in
            url.range(of: pattern, options: .regularExpression) != nil
        }

        // Auto-detect playlist
        if url.contains("playlist?list=") || url.contains("&list=") {
            isPlaylist = true
        }
    }

    private func processURL() {
        guard isValidURL else { return }

        Task {
            if isPlaylist {
                await processingVM.processYouTubePlaylist(url: urlText)
            } else {
                await processingVM.processYouTubeVideo(url: urlText)
            }
        }
    }
}

#Preview {
    YouTubeInputView()
        .environmentObject(ProcessingViewModel())
}
