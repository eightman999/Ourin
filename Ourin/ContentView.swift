//
//  ContentView.swift
//  MacUkagaka
//
//  Created by eightman on 2025/07/26.
//

import SwiftUI
import AppKit
import OSLog

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case shioriResource = "SHIORI Resource"
        case pluginsEvents = "Plugins & Events"
        case external = "External"
        case headline = "Headline / Balloon"
        case narInstall = "NAR Install"
        case logging = "Logging & Diagnostics"
        case network = "Network"

        var id: String { rawValue }

        var localized: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }
    }

    @State private var selection: Section? = .general
    @State private var runningTask: Task<Void, Never>? = nil
    @State private var closeDelegate: CloseConfirmationDelegate? = nil

    private let logger = CompatLogger(subsystem: "jp.ourin.devtools", category: "ui")

    var body: some View {
        NavigationView {
            List(Section.allCases, selection: $selection) { section in
                NavigationLink(
                    destination: EmptyView(),
                    tag: section,
                    selection: $selection
                ) {
                    Text(section.localized)
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(ToolbarModifierIfAvailable(
            reload: reload,
            runTest: runTestScenario,
            stop: stopScenario,
            export: exportDiagnostics
        ))
        .background(
            WindowAccessor { win in
                if let win = win, closeDelegate == nil {
                    let del = CloseConfirmationDelegate()
                    win.delegate = del
                    closeDelegate = del
                }
            }
        )
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            Text("General Settings")
        case .shioriResource:
            Text("SHIORI Resource Viewer")
        case .pluginsEvents:
            Text("Plugin Manager / Event Injector")
        case .external:
            Text("External Events Harness")
        case .headline:
            Text("Headline / Balloon Test")
        case .narInstall:
            NarInstallView()
        case .logging:
            Text("Logging & Diagnostics")
        case .network:
            Text("Network & Listener Status")
        case .none:
            Text("Select a section")
        }
    }

    private func reload() {
        logger.info("reload triggered")
        ResourceBridge.shared.invalidateAll()
        if let app = NSApp.delegate as? AppDelegate {
            app.pluginRegistry?.unloadAll()
            app.pluginRegistry?.discoverAndLoad()
        }
    }

    private func runTestScenario() {
        logger.info("run test scenario")
        stopScenario()
        guard let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher else { return }
        let windows = NSApplication.shared.windows
        let path = Bundle.main.bundlePath
        runningTask = Task {
            dispatcher.onGhostBoot(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
            try? await Task.sleep(nanoseconds: 500_000_000)
            dispatcher.onMenuExec(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
            try? await Task.sleep(nanoseconds: 500_000_000)
            dispatcher.onGhostExit(windows: windows, ghostName: "TestGhost", shellName: "default", ghostID: "test", path: path)
        }
    }

    private func stopScenario() {
        logger.info("stop scenario")
        runningTask?.cancel()
        runningTask = nil
    }

    private func exportDiagnostics() {
        logger.info("export diagnostics")
        let format = NSLocalizedString("Diagnostics exported at %@", comment: "Diagnostics export message")
        let text = String(format: format, Date().description)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// MARK: - Conditional toolbar modifier for macOS 11.0+
private struct ToolbarModifierIfAvailable: ViewModifier {
    var reload: () -> Void
    var runTest: () -> Void
    var stop: () -> Void
    var export: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: reload) {
                    Image(systemName: "arrow.clockwise")
                }.help(Text("Reload"))

                Button(action: runTest) {
                    Image(systemName: "play.fill")
                }.help(Text("Run Test"))

                Button(action: stop) {
                    Image(systemName: "stop.fill")
                }.help(Text("Stop"))

                Button(action: export) {
                    Image(systemName: "square.and.arrow.up")
                }.help(Text("Export"))
            }
        }
    }
}

#Preview {
    ContentView()
}
