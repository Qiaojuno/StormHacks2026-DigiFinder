import Foundation

/// First-launch walkthrough (§5.13): shown on the setup sheet and spoken through the runner.
enum UIWalkthrough {
    static let lines: [String] = [
        "Welcome to DigiFinder. It helps you find items in a grocery store. "
            + "It adds to your cane or guide dog. It does not replace them.",
        "Use a basket, or pull the cart behind you, so the camera can see the way ahead.",
        "Set the phone volume high before you start.",
        "Press volume up to talk. Press volume down when you're done talking.",
        "To start hands-free, say: Hey Siri, open DigiFinder.",
        "Two or three strong vibrations mean something is in your way. Listen for which way to steer. "
            + "Nothing else vibrates. Stairs are spoken, not vibrated.",
        "A beep means I'm listening. A chime means done. Soft ticks mean I'm scanning.",
    ]
}
