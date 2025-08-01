import SwiftUI
import UniformTypeIdentifiers

/// NARインストールのメインUI
struct NarInstallView: View {
    @StateObject private var viewModel = NarInstallViewModel()
    
    var body: some View {
        VStack(spacing: 20) {
            // MARK: - ドラッグ&ドロップエリア
            DropZoneView(viewModel: viewModel)
                .frame(height: 150)
                .padding()
            
            // MARK: - インストール進捗とステータス
            if viewModel.isInstalling {
                VStack(spacing: 10) {
                    ProgressView(value: viewModel.progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())
                    
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            } else if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            
            // MARK: - エラーメッセージ
            if let errorMessage = viewModel.errorMessage {
                HStack {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Button("✕") {
                        viewModel.clearError()
                    }
                    .foregroundColor(.red)
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
            
            // MARK: - インストール済みパッケージ一覧
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("インストール済みパッケージ")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("更新") {
                        viewModel.loadInstalledPackages()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                
                List {
                    if viewModel.installedPackages.isEmpty {
                        HStack {
                            Image(systemName: "cube")
                                .foregroundColor(.gray)
                            Text("インストール済みのパッケージはありません")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(viewModel.installedPackages) { package in
                            PackageRowView(package: package)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("NARインストール")
        .onAppear {
            viewModel.loadInstalledPackages()
        }
    }
}

/// パッケージリストの行表示
private struct PackageRowView: View {
    let package: NarPackage
    
    var body: some View {
        HStack {
            Image(systemName: "cube.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack {
                    Text("バージョン: \(package.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(package.installDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("詳細") {
                // TODO: パッケージ詳細表示
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }
}

/// ドラッグ&ドロップエリア
struct DropZoneView: View {
    @ObservedObject var viewModel: NarInstallViewModel
    @State private var isTargeted: Bool = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.gray.opacity(0.5),
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [5, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.05))
                )
            
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 36))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)
                
                Text("NARファイルをここにドラッグ&ドロップ")
                    .font(.headline)
                    .foregroundColor(isTargeted ? .accentColor : .primary)
                
                Text("(.nar または .zip 形式)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            
            if #available(macOS 11.0, *) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
                    DispatchQueue.main.async {
                        if let urlData = urlData as? Data,
                           let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            viewModel.installNar(from: url)
                        } else if let error = error {
                            viewModel.errorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                // macOS 10.15以前の場合の処理
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { (urlData, error) in
                    DispatchQueue.main.async {
                        if let urlData = urlData as? Data,
                           let url = URL(dataRepresentation: urlData, relativeTo: nil) {
                            viewModel.installNar(from: url)
                        } else if let error = error {
                            viewModel.errorMessage = "ファイルの読み込みに失敗しました: \(error.localizedDescription)"
                        }
                    }
                }
            }
            return true
        }
        .disabled(viewModel.isInstalling)
        .opacity(viewModel.isInstalling ? 0.6 : 1.0)
    }
}

#Preview {
    NarInstallView()
}