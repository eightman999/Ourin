import Foundation
import SwiftUI

/// NARインストールUIの状態管理
@MainActor
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
        
        installedPackages = scanInstalledGhosts()
        
        logger.info("インストール済みパッケージ数: \(installedPackages.count)")
    }

    private func scanInstalledGhosts() -> [NarPackage] {
        guard let ghostsPath = try? OurinPaths.baseDirectory().appendingPathComponent("ghost", isDirectory: true) else {
            logger.warning("Failed to get ghosts directory path")
            return []
        }

        let fileManager = FileManager.default
        guard let ghostDirs = try? fileManager.contentsOfDirectory(at: ghostsPath, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            logger.warning("Failed to list contents of ghosts directory")
            return []
        }

        var packages: [NarPackage] = []

        for ghostDir in ghostDirs {
            let descriptPath = ghostDir.appendingPathComponent("ghost/master/descript.txt")
            if fileManager.fileExists(atPath: descriptPath.path) {
                let attributes = try? fileManager.attributesOfItem(atPath: ghostDir.path)
                let installDate = attributes?[.creationDate] as? Date ?? Date()

                if let name = parseDescript(at: descriptPath) {
                    let package = NarPackage(
                        name: name,
                        version: "不明", // descript.txtにバージョン情報がないため
                        installPath: ghostDir.path,
                        installDate: installDate
                    )
                    packages.append(package)
                }
            }
        }

        return packages
    }

    private func parseDescript(at url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .shiftJIS) else {
            // Shift_JISで読めなかったらUTF-8で試す
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                logger.warning("Failed to read descript.txt at \(url.path)")
                return nil
            }
            return parseDescriptContent(content)
        }
        return parseDescriptContent(content)
    }

    private func parseDescriptContent(_ content: String) -> String? {
        let lines = content.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: ",", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == "name" {
                return parts[1].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: ["\r"])
            }
        }
        return nil
    }
    
    /// エラーメッセージをクリア
    func clearError() {
        errorMessage = nil
    }
}