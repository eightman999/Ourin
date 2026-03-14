import SwiftUI
import AppKit

/// Input box view for user input in balloons
struct InputBoxView: View {
    @State private var inputText: String = ""
    @State private var isFocused: Bool = false
    
    let id: Int
    let placeholder: String
    let onComplete: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        TextField(
            placeholder,
            text: $inputText,
            onCommit: {
                onComplete(inputText)
            }
        )
        .textFieldStyle(.roundedBorder)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
        .onDisappear {
            onCancel()
        }
    }
}

/// Input box view for date input
struct DateInputView: View {
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var month: Int = Calendar.current.component(.month, from: Date())
    @State private var day: Int = Calendar.current.component(.day, from: Date())
    
    let id: Int
    let placeholder: String
    let onComplete: (Int, Int, Int) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("年", text: Binding(
                    get: { String(year) },
                    set: { if let value = Int($0) { year = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                
                Text("年")
                
                TextField("月", text: Binding(
                    get: { String(month) },
                    set: { if let value = Int($0) { month = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                
                Text("月")
                
                TextField("日", text: Binding(
                    get: { String(day) },
                    set: { if let value = Int($0) { day = value } }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                
                Text("日")
            }
            
            HStack(spacing: 8) {
                Button("OK") {
                    onComplete(year, month, day)
                }
                Button("キャンセル") {
                    onCancel()
                }
            }
        }
        .padding()
    }
}

/// Input box view for slider input
struct SliderInputView: View {
    @State private var value: Double = 0.0
    
    let id: Int
    let title: String
    let minimum: Double
    let maximum: Double
    let displayTime: TimeInterval
    let onComplete: (Double) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("値: \(value, specifier: "%.1f")")
                    .frame(maxWidth: 300, alignment: .leading)
                
                Slider(value: $value, in: minimum...maximum) {
                    Text(String(format: "%.0f", minimum))
                    Text(String(format: "%.0f", maximum))
                }
            }
            
            HStack(spacing: 8) {
                Button("OK") {
                    onComplete(value)
                }
                Button("キャンセル") {
                    onCancel()
                }
            }
        }
        .padding()
    }
}
