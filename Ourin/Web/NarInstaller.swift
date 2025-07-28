import Foundation

/// `.nar` アーカイブをダウンロードして展開する簡易インストーラ。
/// 挙動の詳細仕様は docs/NAR_INSTALL_1.0M_SPEC.md を参照。

public enum NarInstaller {
    /// 指定された URL から NAR アーカイブを取得して展開する
    /// - Parameter urlString: `https://` から始まる NAR の場所
    ///
    /// 取得後は `install.txt` の語彙に従ってゴースト等を配置する想定。
    public static func install(from urlString: String) {
        // URL の妥当性チェック。https 以外は拒否
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            NSLog("[NarInstaller] invalid url: \(urlString)")
            return
        }

        // URLSession で非同期ダウンロード
        let task = URLSession.shared.downloadTask(with: url) { local, response, error in
            if let error = error {
                NSLog("[NarInstaller] download error: \(error)")
                return
            }
            guard let local = local else { return }
            NSLog("[NarInstaller] downloaded: \(local.path)")
            // TODO: zip を解凍し install.txt を解析する処理を追加
        }
        task.resume()
    }
}
