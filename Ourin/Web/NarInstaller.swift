import Foundation

public enum NarInstaller {
    /// Download and install a NAR archive from https URL
    public static func install(from urlString: String) {
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            NSLog("[NarInstaller] invalid url: \(urlString)")
            return
        }
        let task = URLSession.shared.downloadTask(with: url) { local, response, error in
            if let error = error {
                NSLog("[NarInstaller] download error: \(error)")
                return
            }
            guard let local = local else { return }
            NSLog("[NarInstaller] downloaded: \(local.path)")
            // Placeholder: unzip and apply install.txt
        }
        task.resume()
    }
}
