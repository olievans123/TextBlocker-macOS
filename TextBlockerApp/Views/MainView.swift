import SwiftUI

enum NavigationItem: String, CaseIterable, Identifiable {
    case files = "Files"
    case youtube = "YouTube"
    case queue = "Queue"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .files: return "doc.fill"
        case .youtube: return "play.rectangle.fill"
        case .queue: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selectedItem: NavigationItem? = .files
    @StateObject private var processingVM = ProcessingViewModel()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                ForEach(NavigationItem.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                        .badge(badgeCount(for: item))
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selected = selectedItem {
                contentView(for: selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DropZoneView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environmentObject(processingVM)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if processingVM.isProcessing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(processingVM.currentPhase)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contentView(for item: NavigationItem) -> some View {
        switch item {
        case .files:
            DropZoneView()
        case .youtube:
            YouTubeInputView()
        case .queue:
            QueueView()
        case .settings:
            SettingsView()
        }
    }

    private func badgeCount(for item: NavigationItem) -> Int {
        switch item {
        case .queue:
            return processingVM.jobs.filter { $0.status.isProcessing || $0.status == .pending }.count
        default:
            return 0
        }
    }
}

#Preview {
    MainView()
}
