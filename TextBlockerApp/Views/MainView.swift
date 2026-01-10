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
    @State private var selectedItem: NavigationItem = .files
    @StateObject private var processingVM = ProcessingViewModel()

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(alignment: .leading, spacing: 4) {
                ForEach(NavigationItem.allCases) { item in
                    SidebarButton(
                        item: item,
                        isSelected: selectedItem == item,
                        badge: badgeCount(for: item),
                        isActive: item == .queue && processingVM.isProcessing
                    ) {
                        selectedItem = item
                    }
                }

                Spacer()

                // Status indicator at bottom of sidebar
                if processingVM.isProcessing {
                    VStack(alignment: .leading, spacing: 4) {
                        Divider()
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(processingVM.currentPhase)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(8)
            .frame(minWidth: 160, maxWidth: 200)
            .background(Color(NSColor.controlBackgroundColor))

            // Detail
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(processingVM)
        .frame(minWidth: 800, minHeight: 500)
        // Auto-navigate to Queue when processing starts
        .onChange(of: processingVM.isProcessing) { _, isProcessing in
            if isProcessing && selectedItem == .files {
                withAnimation {
                    selectedItem = .queue
                }
            }
        }
        // Show notification when job completes
        .onChange(of: processingVM.jobs.map { $0.status }) { _, _ in
            checkForCompletedJobs()
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedItem {
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

    private func checkForCompletedJobs() {
        // Could add notification sound or system notification here
    }
}

struct SidebarButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let badge: Int
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(item.rawValue, systemImage: item.icon)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                Spacer()

                if isActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }

                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    MainView()
}
