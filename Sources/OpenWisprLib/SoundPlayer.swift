import AppKit
import Foundation

public enum SoundPlayer {
    public static func play(_ nameOrPath: String?) {
        guard let value = nameOrPath, !value.isEmpty else { return }

        if value.hasPrefix("/") || value.hasPrefix("~") {
            let expanded = (value as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)
            if let sound = NSSound(contentsOf: url, byReference: true) {
                sound.play()
                return
            }
            fputs("Warning: unable to load sound at \(expanded)\n", stderr)
            return
        }

        if let sound = NSSound(named: value) {
            sound.play()
            return
        }

        fputs("Warning: unknown sound name '\(value)'\n", stderr)
    }
}
