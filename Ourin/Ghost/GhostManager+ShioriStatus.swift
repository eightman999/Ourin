import AppKit

extension GhostManager {
    /// Snapshot the receiving ghost's real UI state without creating windows or view models.
    func shioriStatusFlags() -> [String] {
        if !Thread.isMainThread { return DispatchQueue.main.sync { self.shioriStatusFlags() } }
        var flags: [String] = []
        if isPlaying { flags.append("talking") }
        let visibleBalloons = balloonWindows.keys.sorted().filter { scope in
            guard let window = balloonWindows[scope] else { return false }
            return window.isVisible && !window.isMiniaturized && balloonViewModels[scope] != nil
        }
        let hasVisibleChoices = visibleBalloons.contains { scope in
            balloonViewModels[scope]?.anchors.contains(where: { $0.choiceIndex != nil }) == true
        }
        if activeChoiceAlert?.window.isVisible == true || hasVisibleChoices { flags.append("choosing") }
        if characterWindows.values.contains(where: { $0.isMiniaturized }) { flags.append("minimizing") }
        if inductionModeActive { flags.append("induction") }
        if passiveModeActive { flags.append("passive") }
        if timeCriticalActive { flags.append("timecritical") }
        if noUserBreakModeActive { flags.append("nouserbreak") }
        if balloonViewModels.values.contains(where: { $0.onlineModeActive }) { flags.append("online") }
        var opening: [String] = []
        if activeCommunicateAlert?.window.isVisible == true { opening.append("communicate") }
        if activeInputDialogs.contains(where: { $0.isOpen && $0.alert.window.isVisible }) {
            opening.append("input")
        }
        if utilityWindows["teachbox"]?.isVisible == true { opening.append("teach") }
        if activeSystemDialogWindow?.isVisible == true || utilityWindows["systemdialog.color"]?.isVisible == true {
            opening.append("dialog")
        }
        if !opening.isEmpty { flags.append("opening(\(opening.joined(separator: "/")))") }
        if !visibleBalloons.isEmpty {
            let surfaces = visibleBalloons.compactMap { scope -> String? in
                guard let id = balloonViewModels[scope]?.balloonID else { return nil }
                return "\(scope)=\(id)"
            }
            flags.append("balloon(\(surfaces.joined(separator: "/")))")
        }
        return flags
    }
}
