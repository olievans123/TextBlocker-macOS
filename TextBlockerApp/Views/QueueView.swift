import SwiftUI

struct QueueView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Processing Queue")
                        .font(.title2)
                        .fontWeight(.bold)

                    if processingVM.isProcessing {
                        Text(processingVM.currentPhase)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !processingVM.jobs.isEmpty {
                    Button("Clear Completed") {
                        withAnimation {
                            processingVM.clearCompleted()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasCompletedJobs)
                }
            }
            .padding()

            Divider()

            if processingVM.jobs.isEmpty {
                emptyState
            } else {
                jobsList
            }
        }
    }

    private var hasCompletedJobs: Bool {
        processingVM.jobs.contains { job in
            if case .completed = job.status { return true }
            if case .failed = job.status { return true }
            if case .cancelled = job.status { return true }
            return false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 56))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 8) {
                Text("No jobs in queue")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("Drop files on the Files tab or\nenter a YouTube URL to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(processingVM.jobs) { job in
                    JobCardView(job: job)
                }
            }
            .padding()
        }
    }
}

struct JobCardView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel
    @ObservedObject var job: ProcessingJob

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                statusIcon
                    .frame(width: 36, height: 36)
                    .background(statusColor.opacity(0.15))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(job.inputURL.path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 8) {
                        Text(job.status.displayText)
                            .font(.caption)
                            .foregroundColor(statusColor)

                        if job.detectedRegions > 0 {
                            Text("\(job.detectedRegions) regions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Action buttons
                actionButtons
            }

            // Progress bar for active jobs
            if job.status.isProcessing {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.status.progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(job.status.progress * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if case .downloading = job.status {
                            EmptyView()
                        } else if case .merging = job.status {
                            EmptyView()
                        } else if let eta = job.formattedTimeRemaining {
                            Text(eta)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Success message with output path
            if case .completed = job.status, let outputURL = job.outputURL {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)

                    Text("Saved to: \(outputURL.lastPathComponent)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(8)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }

            // Error message
            if case .failed(let error) = job.status {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)

                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    @ViewBuilder
    private var statusIcon: some View {
        Group {
            switch job.status {
            case .pending:
                Image(systemName: "clock")
            case .downloading:
                Image(systemName: "arrow.down.circle")
            case .merging:
                Image(systemName: "arrow.triangle.2.circlepath")
            case .extracting:
                Image(systemName: "film")
            case .detecting:
                Image(systemName: "text.viewfinder")
            case .encoding:
                Image(systemName: "gearshape.2")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .cancelled:
                Image(systemName: "stop.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            }
        }
        .font(.system(size: 18))
        .foregroundColor(statusColor)
    }

    private var statusColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .downloading: return .blue
        case .merging: return .blue
        case .extracting: return .purple
        case .detecting: return .orange
        case .encoding: return .cyan
        case .completed: return .green
        case .cancelled: return .gray
        case .failed: return .red
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Cancel button for active jobs
            if job.status.isProcessing {
                Button {
                    processingVM.cancelJob(job)
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }

            // Show/Play buttons for completed jobs
            if case .completed = job.status, let outputURL = job.outputURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Label("Show", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    NSWorkspace.shared.open(outputURL)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Delete button for non-processing jobs
            if !job.status.isProcessing {
                Button {
                    processingVM.removeJob(job)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .help("Remove from queue")
            }
        }
    }
}

#if DEBUG
struct QueueView_Previews: PreviewProvider {
    static var previews: some View {
        QueueView()
            .environmentObject(ProcessingViewModel())
    }
}
#endif
