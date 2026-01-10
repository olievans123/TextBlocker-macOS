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
                        badge: badgeCount(for: item)
                    ) {
                        selectedItem = item
                    }
                }
                Spacer()
            }
            .padding(8)
            .frame(minWidth: 160, maxWidth: 200)
            .background(Color(NSColor.controlBackgroundColor))

            // Detail
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(processingVM)
        .frame(minWidth: 700, minHeight: 500)
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
}

struct SidebarButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let badge: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Label(item.rawValue, systemImage: item.icon)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
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
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    MainView()
}
