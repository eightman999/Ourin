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
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
        // 右クリックメニューはメニューバーに移動
    }
}

#Preview {
    ContentView()
}
