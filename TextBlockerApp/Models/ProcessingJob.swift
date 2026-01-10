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
    case failed(error: String)

    var isProcessing: Bool {
        switch self {
        case .pending, .completed, .failed:
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
        case .failed(let error):
            return "Failed: \(error)"
        }
    }

    var progress: Double {
        switch self {
        case .pending:
            return 0
        case .downloading(let p), .extracting(let p), .detecting(let p), .encoding(let p):
            return p
        case .completed:
            return 1
        case .failed:
            return 0
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

    @Published var status: JobStatus = .pending
    @Published var outputURL: URL?
    @Published var detectedRegions: Int = 0

    init(inputURL: URL, type: JobType, sourceURL: String? = nil, title: String? = nil) {
        self.inputURL = inputURL
        self.type = type
        self.sourceURL = sourceURL
        self.title = title ?? inputURL.deletingPathExtension().lastPathComponent
        self.createdAt = Date()
    }
}
