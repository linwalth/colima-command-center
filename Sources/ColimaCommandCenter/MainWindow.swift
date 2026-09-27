import Cocoa
import SwiftUI

enum MainTab: Hashable {
    case editor, health
}

@MainActor
final class TabSelection: ObservableObject {
    @Published var selected: MainTab = .editor
}

@MainActor
final class PowerViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var isBusy = false
    @Published var outputLines: [String] = []
    @Published var logExpanded = true

    func refresh() {
        Lifecycle.shared.checkStatus { [weak self] running in
            DispatchQueue.main.async {
                self?.isRunning = running
            }
        }
    }

    func start() {
        guard !isBusy else { return }
        isBusy = true
        outputLines = []
        Lifecycle.shared.startStream(
            onOutput: { [weak self] line in
                DispatchQueue.main.async {
                    self?.outputLines.append(line)
                }
            },
            completion: { [weak self] wasAlreadyRunning, exitCode in
                DispatchQueue.main.async {
                    self?.isBusy = false
                    self?.refresh()
                    if !wasAlreadyRunning && exitCode == 0 {
                        Notifier.shared.post(
                            title: L10n.tr("notif.toggle_title"),
                            body: L10n.tr("notif.started")
                        )
                    }
                }
            }
        )
    }

    func stop() {
        guard !isBusy else { return }
        isBusy = true
        outputLines = []
        Lifecycle.shared.stopStream(
            onOutput: { [weak self] line in
                DispatchQueue.main.async {
                    self?.outputLines.append(line)
                }
            },
            completion: { [weak self] wasAlreadyStopped, exitCode in
                DispatchQueue.main.async {
                    self?.isBusy = false
                    self?.refresh()
                    if !wasAlreadyStopped && exitCode == 0 {
                        Notifier.shared.post(
                            title: L10n.tr("notif.toggle_title"),
                            body: L10n.tr("notif.stopped")
                        )
                    }
                }
            }
        )
    }
}

@MainActor
final class MainWindowController: NSWindowController {
    let tabSelection = TabSelection()
    let powerVM = PowerViewModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.tr("window.title")
        window.center()
        let editorVM = EditorViewModel()
        let healthVM = HealthViewModel()
        window.contentView = NSHostingView(rootView: MainContentView(
            tabSelection: tabSelection,
            powerVM: powerVM,
            editorVM: editorVM,
            healthVM: healthVM
        ))
        super.init(window: window)
        powerVM.refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func selectTab(_ tab: MainTab) {
        tabSelection.selected = tab
    }
}

struct MainContentView: View {
    @ObservedObject var tabSelection: TabSelection
    @ObservedObject var powerVM: PowerViewModel
    @ObservedObject var editorVM: EditorViewModel
    @ObservedObject var healthVM: HealthViewModel

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tabSelection.selected) {
                EditorView(viewModel: editorVM)
                    .tabItem { Label(L10n.tr("tab.editor"), systemImage: "slider.horizontal.3") }
                    .tag(MainTab.editor)
                    .onAppear {
                        editorVM.reload()
                    }

                HealthView(viewModel: healthVM)
                    .tabItem { Label(L10n.tr("tab.health"), systemImage: "chart.bar.doc.horizontal") }
                    .tag(MainTab.health)
            }
            .onChange(of: tabSelection.selected) { newTab in
                if newTab == .health {
                    healthVM.startAutoRefresh()
                } else {
                    healthVM.stopAutoRefresh()
                }
            }
            .onAppear {
                if tabSelection.selected == .health {
                    healthVM.startAutoRefresh()
                }
            }
            Divider()
            PowerBar(powerVM: powerVM)
        }
    }
}

private struct PowerBar: View {
    @ObservedObject var powerVM: PowerViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(powerVM.isRunning ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
                Text(powerVM.isRunning ? L10n.tr("power.running") : L10n.tr("power.stopped"))
                    .font(.headline)
                Spacer()
                if powerVM.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                if powerVM.isRunning {
                    Button(L10n.tr("menu.stop")) { powerVM.stop() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(powerVM.isBusy)
                } else {
                    Button(L10n.tr("menu.start")) { powerVM.start() }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(powerVM.isBusy)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !powerVM.outputLines.isEmpty {
                Divider()
                if powerVM.logExpanded {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(powerVM.outputLines.indices, id: \.self) { idx in
                                Text(powerVM.outputLines[idx])
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 120)
                }
                Button(powerVM.logExpanded ? L10n.tr("power.collapse_log") : L10n.tr("power.expand_log")) {
                    powerVM.logExpanded.toggle()
                }
                .font(.caption)
                .padding(.bottom, 6)
            }
        }
    }
}
