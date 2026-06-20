import AVFoundation
import UIKit

/// Plays the "vehicle appeared" cue when the app is in the foreground.
///
/// Uses the `.ambient` category with `.mixWithOthers`, so the cue layers
/// over any music or podcast without interrupting or ducking it, and stays
/// silent when the ring switch is set to silent. The background case is
/// handled separately by the Live Activity alert.
@MainActor
final class AlertPlayer {
    private var player: AVAudioPlayer?
    private let haptics = UINotificationFeedbackGenerator()

    func playContactAlert() {
        haptics.notificationOccurred(.warning)
        guard let url = Bundle.main.url(forResource: "contact", withExtension: "caf") else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            print("[alert] sound failed: \(error.localizedDescription)")
        }
    }
}
