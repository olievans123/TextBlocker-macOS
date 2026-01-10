import SwiftUI
import AppKit

enum NavigationItem: String, CaseIterable, Identifiable {
    case input = "Add Video"
    case queue = "Queue"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .input: return "plus.rectangle.fill"
        case .queue: return "list.bullet.rectangle.fill"
        case .settings: return "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selectedItem: NavigationItem = .input
    @StateObject private var processingVM = ProcessingViewModel()
    @State private var showDependencyAlert = false
    @AppStorage("hasShownOnboarding") private var hasShownOnboarding = false
    @State private var previousCompletedCount = 0

    private var missingDependencies: [String] {
        var missing: [String] = []
        if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") {
            missing.append("ffmpeg")
        }
        if !FileManager.default.fileExists(atPath: "/opt/homebrew/bin/yt-dlp") {
            missing.append("yt-dlp")
        }
        return missing
    }

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
            if isProcessing && selectedItem == .input {
                withAnimation {
                    selectedItem = .queue
                }
            }
        }
        // Show notification when job completes
        .onChange(of: processingVM.jobs.map { $0.status }) { _, _ in
            checkForCompletedJobs()
        }
        // Check dependencies on first launch
        .onAppear {
            if !hasShownOnboarding && !missingDependencies.isEmpty {
                showDependencyAlert = true
                hasShownOnboarding = true
            }
        }
        .alert("Missing Dependencies", isPresented: $showDependencyAlert) {
            Button("Open Settings") {
                selectedItem = .settings
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("TextBlocker requires \(missingDependencies.joined(separator: " and ")) to work.\n\nInstall with: brew install \(missingDependencies.joined(separator: " "))")
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedItem {
        case .input:
            InputView()
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
        let completedCount = processingVM.jobs.filter {
            if case .completed = $0.status { return true }
            return false
        }.count

        // Play sound when a new job completes
        if completedCount > previousCompletedCount {
            NSSound.beep()  // System sound
            // Or use: NSSound(named: "Glass")?.play()
        }
        previousCompletedCount = completedCount
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
