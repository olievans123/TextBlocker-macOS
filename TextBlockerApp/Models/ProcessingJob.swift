import Foundation

enum JobType {
    case localFile
    case youtubeVideo
    case youtubePlaylist
}

enum JobStatus: Equatable {
    case pending
    case downloading(progress: Double)
    case extracting(progress: Double)
    case detecting(progress: Double)
    case encoding(progress: Double)
    case completed
    case cancelled
    case failed(error: String)

    var isProcessing: Bool {
        switch self {
        case .pending, .completed, .cancelled, .failed:
            return false
        default:
            return true
        }
    }

    var displayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .extracting(let progress):
            return "Extracting frames \(Int(progress * 100))%"
        case .detecting(let progress):
            return "Detecting text \(Int(progress * 100))%"
        case .encoding(let progress):
            return "Encoding \(Int(progress * 100))%"
        case .completed:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    var progress: Double {
        switch self {
        case .pending, .cancelled, .failed:
            return 0
        case .downloading(let p), .extracting(let p), .detecting(let p), .encoding(let p):
            return p
        case .completed:
            return 1
        }
    }

    /// Overall progress across all phases (0-1)
    /// extracting (0-33%), detecting (33-66%), encoding (66-100%)
    var overallProgress: Double {
        switch self {
        case .pending, .cancelled, .failed:
            return 0
        case .downloading(let p):
            return p * 0.1  // 0-10%
        case .extracting(let p):
            return 0.1 + p * 0.23  // 10-33%
        case .detecting(let p):
            return 0.33 + p * 0.33  // 33-66%
        case .encoding(let p):
            return 0.66 + p * 0.34  // 66-100%
        case .completed:
            return 1
        }
    }
}

class ProcessingJob: Identifiable, ObservableObject {
    let id = UUID()
    let inputURL: URL
    let type: JobType
    let sourceURL: String?
    let title: String
    let createdAt: Date

    @Published var status: JobStatus = .pending {
        didSet {
            // Track when processing actually starts
            if processingStartTime == nil && status.isProcessing {
                processingStartTime = Date()
            }
        }
    }
    @Published var outputURL: URL?
    @Published var detectedRegions: Int = 0

    /// When processing started (for ETA calculation)
    var processingStartTime: Date?

    /// Flag to request cancellation
    var isCancellationRequested: Bool = false

    init(inputURL: URL, type: JobType, sourceURL: String? = nil, title: String? = nil) {
        self.inputURL = inputURL
        self.type = type
        self.sourceURL = sourceURL
        self.title = title ?? inputURL.deletingPathExtension().lastPathComponent
        self.createdAt = Date()
    }

    /// Estimated time remaining based on progress and elapsed time
    var estimatedTimeRemaining: TimeInterval? {
        guard let startTime = processingStartTime,
              status.overallProgress > 0.05 else { return nil }

        let elapsed = Date().timeIntervalSince(startTime)
        let progress = status.overallProgress
        let totalEstimated = elapsed / progress
        let remaining = totalEstimated - elapsed

        return remaining > 0 ? remaining : nil
    }

    /// Format time remaining as human readable string
    var formattedTimeRemaining: String? {
        guard let remaining = estimatedTimeRemaining else { return nil }

        if remaining < 60 {
            return "\(Int(remaining))s remaining"
        } else if remaining < 3600 {
            let mins = Int(remaining / 60)
            let secs = Int(remaining.truncatingRemainder(dividingBy: 60))
            return "\(mins)m \(secs)s remaining"
        } else {
            let hours = Int(remaining / 3600)
            let mins = Int((remaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(mins)m remaining"
        }
    }
}
