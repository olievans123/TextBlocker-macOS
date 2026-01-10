import SwiftUI

struct QueueView: View {
    @EnvironmentObject var processingVM: ProcessingViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Processing Queue")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                if !processingVM.jobs.isEmpty {
                    Button("Clear Completed") {
                        processingVM.clearCompleted()
                    }
                    .buttonStyle(.bordered)
                    .disabled(processingVM.jobs.allSatisfy { $0.status.isProcessing || $0.status == .pending })
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

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No jobs in queue")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Drop files or enter a YouTube URL to get started")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var jobsList: some View {
        List {
            ForEach(processingVM.jobs) { job in
                JobRowView(job: job)
            }
        }
        .listStyle(.inset)
    }
}

struct JobRowView: View {
    @ObservedObject var job: ProcessingJob

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .frame(width: 32, height: 32)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(job.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(job.status.displayText)
                    .font(.caption)
                    .foregroundColor(statusColor)

                if job.status.isProcessing {
                    ProgressView(value: job.status.progress)
                        .progressViewStyle(.linear)
                }
            }

            Spacer()

            // Actions
            if case .completed = job.status, let outputURL = job.outputURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.bordered)
                .help("Show in Finder")
            }

            if case .failed = job.status {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.status {
        case .pending:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundColor(.blue)
        case .extracting:
            Image(systemName: "film")
                .foregroundColor(.purple)
        case .detecting:
            Image(systemName: "text.viewfinder")
                .foregroundColor(.orange)
        case .encoding:
            Image(systemName: "gearshape.2")
                .foregroundColor(.green)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .downloading: return .blue
        case .extracting: return .purple
        case .detecting: return .orange
        case .encoding: return .green
        case .completed: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    QueueView()
        .environmentObject(ProcessingViewModel())
}
