import Foundation

/// First-launch walkthrough (§5.13): shown on the setup sheet and spoken through the runner.
enum UIWalkthrough {
    /// Owner rule: every spoken line is at most 8 words.
    static let lines: [String] = [
        "Welcome to DigiFinder. It finds things for you.",
        "It adds to your cane. It doesn't replace it.",
        "Set the phone volume high.",
        "Volume down starts or stops.",
        "Volume up asks for something.",
        "One strong vibration means something's in your way.",
        "Then listen for which way to steer.",
        "A beep means I'm listening.",
    ]
}
