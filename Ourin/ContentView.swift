//
//  ContentView.swift
//  MacUkagaka
//
//  Created by eightman on 2025/07/26.
//

import SwiftUI

/// SSP風右クリックメニューの表示に利用
import AppKit

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
                        Button(action: {}) {
                            Image(systemName: "arrow.clockwise")
                        }.help("Reload")
                        Button(action: {}) {
                            Image(systemName: "play.fill")
                        }.help("Run Test")
                        Button(action: {}) {
                            Image(systemName: "stop.fill")
                        }.help("Stop")
                        Button(action: {}) {
                            Image(systemName: "square.and.arrow.up")
                        }.help("Export")
                    }
                }
        }
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
}

#Preview {
    ContentView()
}
