//
//  ContentView.swift
//  MacUkagaka
//
//  Created by eightman on 2025/07/26.
//

import SwiftUI

/// SSP風右クリックメニューの表示に利用
import AppKit
import OSLog

struct ContentView: View {
    /// サイドバーの表示項目
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case shioriResource = "SHIORI Resource"
        case pluginsEvents = "Plugins & Events"
        case external = "External"
        case headline = "Headline / Balloon"
        case logging = "Logging & Diagnostics"
        case network = "Network"

        var id: String { rawValue }
    }

    @State private var selection: Section? = .general
    @State private var runningTask: Task<Void, Never>? = nil
    @State private var closeDelegate: CloseConfirmationDelegate? = nil

    private let logger = Logger(subsystem: "jp.ourin.devtools", category: "ui")

    var body: some View {
        NavigationView {
            // Sidebar list
            List(Section.allCases, selection: $selection) { section in
                Text(section.rawValue)
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 200)

            // Detail pane with simple placeholders
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItemGroup {
                        Button(action: reload) {
                            Image(systemName: "arrow.clockwise")
                        }.help("Reload")
                        Button(action: runTestScenario) {
                            Image(systemName: "play.fill")
                        }.help("Run Test")
                        Button(action: stopScenario) {
                            Image(systemName: "stop.fill")
                        }.help("Stop")
                        Button(action: exportDiagnostics) {
                            Image(systemName: "square.and.arrow.up")
                        }.help("Export")
                    }
                }
        }
        .background(
            WindowAccessor { win in
                if let win = win, closeDelegate == nil {
                    let del = CloseConfirmationDelegate()
                    win.delegate = del
                    closeDelegate = del
                }
            }
        )
        // 右クリックメニューはメニューバーに移動

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
        case .logging:
            Text("Logging & Diagnostics")
        case .network:
            Text("Network & Listener Status")
        case .none:
            Text("Select a section")
        }
    }

    // MARK: - Toolbar actions
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
        let text = "Diagnostics exported at \(Date())\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OurinDiagnostics.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

#Preview {
    ContentView()
}
