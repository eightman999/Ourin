import Foundation
import SwiftUI

/// NARインストールUIの状態管理
final class NarInstallViewModel: ObservableObject {
    @Published var isInstalling: Bool = false
    @Published var progress: Double = 0.0
    @Published var statusMessage: String = ""
    @Published var errorMessage: String? = nil
    @Published var installedPackages: [NarPackage] = []
    
    private let installer = NarInstaller()
    private let logger = CompatLogger(subsystem: "jp.ourin.ui", category: "nar-install")
    
    /// NARファイルをインストールする
    func installNar(from url: URL) {
        guard !isInstalling else {
            errorMessage = "現在、別のインストールが進行中です。"
            return
        }
        
        // ファイル形式の検証
        let allowedExtensions = ["nar", "zip"]
        let fileExtension = url.pathExtension.lowercased()
        guard allowedExtensions.contains(fileExtension) else {
            errorMessage = "無効なファイル形式です。NARファイル（.narまたは.zip）をドロップしてください。"
            return
        }
        
        logger.info("NARインストール開始: \(url.lastPathComponent)")
        
        isInstalling = true
        progress = 0.0
        statusMessage = "インストールを開始しています..."
        errorMessage = nil
        
        Task {
            do {
                // プログレス更新のクロージャ
                let progressHandler: (Double, String) -> Void = { [weak self] currentProgress, currentStatus in
                    DispatchQueue.main.async {
                        self?.progress = currentProgress
                        self?.statusMessage = currentStatus
                    }
                }
                
                // インストール実行
                progressHandler(0.1, "ファイルを検証中...")
                let installURL = try installer.install(fromNar: url)
                
                progressHandler(0.5, "パッケージを展開中...")
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒待機（UI表示のため）
                
                progressHandler(0.8, "設定を適用中...")
                try await Task.sleep(nanoseconds: 300_000_000) // 0.3秒待機
                
                progressHandler(1.0, "インストール完了！")
                
                DispatchQueue.main.async {
                    self.statusMessage = "インストールが正常に完了しました"
                    self.isInstalling = false
                    self.loadInstalledPackages() // インストール後、リストを更新
                    self.logger.info("NARインストール完了: \(installURL.path)")
                }
                
            } catch let error as NarInstaller.Error {
                DispatchQueue.main.async {
                    self.errorMessage = "インストールエラー: \(error.description)"
                    self.isInstalling = false
                    self.progress = 0.0
                    self.statusMessage = "インストール失敗"
                    self.logger.warning("NARインストール失敗: \(error.localizedDescription)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "予期しないエラーが発生しました: \(error.localizedDescription)"
                    self.isInstalling = false
                    self.progress = 0.0
                    self.statusMessage = "インストール失敗"
                    self.logger.warning("NARインストール失敗: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// インストール済みパッケージ一覧を読み込む
    func loadInstalledPackages() {
        logger.info("インストール済みパッケージを読み込み中")
        
        // サンプルデータ（実際の実装では、インストールディレクトリを走査する）
        installedPackages = [
            NarPackage(name: "Sample Ghost A", version: "1.2.0", installPath: "/path/to/ghost_a"),
            NarPackage(name: "Sample Ghost B", version: "2.0.1", installPath: "/path/to/ghost_b")
        ]
        
        // TODO: 実際のインストールディレクトリを走査してパッケージリストを構築
        // let ghostsPath = Paths.ghostsInstallPath()
        // let packages = scanInstalledPackages(at: ghostsPath)
        // installedPackages = packages
        
        logger.info("インストール済みパッケージ数: \(installedPackages.count)")
    }
    
    /// エラーメッセージをクリア
    func clearError() {
        errorMessage = nil
    }
}