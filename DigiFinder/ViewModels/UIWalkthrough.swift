import Foundation

/// First-launch walkthrough (§5.13): shown on the setup sheet and spoken through the runner.
enum UIWalkthrough {
    /// What the app does now (owner decision). Owner rule: every spoken line is at most 8 words.
    static let lines: [String] = [
        "Welcome to DigiFinder. I help you find things.",
        "Wear the phone on your chest, camera out.",
        "I add to your cane, not replace it.",
        "Volume down starts or stops me.",
        "Volume up: tell me what to find.",
        "Directions use a clock. 12 is straight ahead.",
        "3 is right. 9 is left.",
        "One vibration means something is in your way.",
        "Then listen for which way to steer.",
        "I also warn about stairs and wet floors.",
        "When I ask, stop and look around.",
        "Finding things needs an internet connection.",
        "A beep means I'm listening.",
    ]
}
