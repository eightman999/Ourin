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
        var all: [NarPackage] = []
        // Ghost/Shell/Balloon/Plugin/Package の順で走査
        all.append(contentsOf: scanInstalled(kind: "ghost"))
        all.append(contentsOf: scanInstalled(kind: "shell"))
        all.append(contentsOf: scanInstalled(kind: "balloon"))
        all.append(contentsOf: scanInstalled(kind: "plugin"))
        all.append(contentsOf: scanInstalled(kind: "package"))
        installedPackages = all
        logger.info("インストール済みパッケージ数: \(installedPackages.count)")
    }

    /// 指定種別のインストール済みパッケージを走査
    private func scanInstalled(kind: String) -> [NarPackage] {
        guard let base = try? OurinPaths.baseDirectory() else { return [] }
        let root = base.appendingPathComponent(kind, isDirectory: true)
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            return []
        }
        var result: [NarPackage] = []
        for dir in dirs {
            let attrs = (try? fm.attributesOfItem(atPath: dir.path)) ?? [:]
            let cdate = (attrs[.creationDate] as? Date) ?? Date()
            let displayName: String? = {
                switch kind {
                case "ghost":
                    let path = dir.appendingPathComponent("ghost/master/descript.txt")
                    return parseDescript(at: path)
                case "shell":
                    let path = dir.appendingPathComponent("shell/master/descript.txt")
                    return parseDescript(at: path)
                case "balloon":
                    // balloon はルート直下に descript.txt がある想定
                    let root = dir.appendingPathComponent("balloon", isDirectory: true)
                    // いくつかの配布では balloon/ を含まずに直接置かれることがあるため両方試す
                    let balloonRoot = FileManager.default.fileExists(atPath: root.path) ? root : dir
                    if let dict = try? DescriptorLoader.load(from: balloonRoot), let name = dict["name"] {
                        return name
                    }
                    return nil
                default:
                    return nil
                }
            }()
            let pkgName = displayName ?? dir.lastPathComponent
            result.append(NarPackage(name: pkgName, version: "不明", installPath: dir.path, installDate: cdate))
        }
        return result
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
