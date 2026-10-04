// Every line the session speaks. Wording follows §5; keep it in sync with the spec.
// Owner rule: at most 8 words per line (fewer is better), actionable only: where to go, what to do, or a direct
// answer. Never narrate the scene, what is missing, or reasoning. `PhraseLengthTests` checks every line.
import Foundation

enum SessionPhrases {
    // MARK: Start and goals (§5.2, §5.10)
    static let askGoal = "What should I find? Press volume up."
    /// App open (owner decision: starts stopped).
    static let pressToStart = "Press volume down to start."
    static let started = "Started. Volume up to ask."
    // Where the user is (once at app open, before the opening question).
    static let inGroceryStore = "You're in a grocery store."
    /// Said instead of "Looking for X." while the grocery check runs (owner decision), then `nowLookingFor`.
    static let loading = "Loading."
    static func nowLookingFor(_ name: String) -> String { "Okay, now looking for \(name)." }
    static let notInGroceryStore = "You're not in a grocery store."
    static let couldntTellPlace = "Couldn't tell the place."
    /// "This looks like a university library."
    static func looksLikePlace(_ scene: String) -> String {
        let s = scene.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !s.isEmpty else { return notInGroceryStore }
        let article = "aeio".contains(s.first ?? "x") ? "an" : "a"
        return "This looks like \(article) \(s)."
    }
    static func lookingFor(_ name: String) -> String { "Looking for \(name)." }
    static func instead(_ name: String) -> String { "Okay, \(name) instead." }
    static func added(_ name: String) -> String { "Added \(name) to the list." }
    static func switchOrAdd(_ name: String) -> String { "Switch to \(name), or add it?" }
    static func willAdd(_ name: String) -> String { "I'll add \(name) to the list." }
    static func stillLooking(_ name: String) -> String { "Okay, still looking for \(name)." }
    static func findFirst(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        return (["I'll find \(first) first"] + names.dropFirst().map { "then \($0)" }).joined(separator: ", ") + "."
    }
    static let notCaught = "I didn't catch that. Say the product name."
    static let notCaughtNoisy = "Didn't catch that. Too noisy."

    // MARK: Unknown items (§5.2)
    static func unknownOffline(_ words: String) -> String {
        "Looking for \(words) on signs."
    }
    static let wordSearch = "Looking for the word on signs."
    static func foundOnline(_ name: String, aisle: String) -> String { "Found it: \(name). Looking for the \(aisle) aisle." }
    static func found(_ name: String) -> String { "Found it: \(name)." }

    // MARK: Ask (§5.11)
    static let offlineQuestion = "Can't answer that offline."
    /// §0: no Secrets.plist.
    static let onlineHelpOff = "Online help isn't set up."

    // MARK: Controls (§5.9, §5.10)
    static let sayAgain = "Say that again."
    static let shorter = "Shorter now."
    static let moreDetail = "More detail."
    static let nothingAround = "I can't see much around you."

    // MARK: Endings (§5.12)
    static let stopped = "Stopped."
    static func shoppingDone(_ n: Int) -> String { "Shopping done. You found \(n) \(n == 1 ? "item" : "items")." }
    static let whatsNext = "What's next?"
    static let pressForAnother = "Volume up for another item."
    static func next(_ name: String) -> String { "Next: \(name)." }
    static func alsoInAisle(_ name: String) -> String { "\(cap(name)) is in this aisle too." }
    static let notFound = "I couldn't find it."
    static let lostTrack = "Lost track. Walk slowly ahead."
    static let guidancePaused = "Paused. Volume up when ready."

    // MARK: Item in view (global rule) and not-a-store search
    static let turnSlowly = "Turn slowly."
    /// Owner decision: instead of "turn around" for context clues.
    static let needContext = "Stop and look around. I need context."
    static let keepGoing = "Keep going."
    static func itemAt(_ name: String, clock: Int, distance: Float?, steps: Bool) -> String {
        "\(name.prefix(1).uppercased() + name.dropFirst()) at \(clock) o'clock" + about(distance, steps: steps) + "."
    }
    /// Within reach, Standing → Pick.
    static let pointAtIt = "Point at it with one finger."
    /// Within reach while Walking (once); Pick follows when the user stands.
    static func stopItem(_ name: String, clock: Int) -> String { "Stop. \(cap(name)) at \(clock) o'clock." }
    static func withinReach(_ name: String) -> String {
        "\(name.prefix(1).uppercased() + name.dropFirst()), within reach."
    }
    static func notFoundNearby(_ name: String) -> String { "I couldn't find \(name)." }
    static let nearbyOn = "Okay, looking nearby."
    static let nearbyOff = "Okay, store mode."

    // MARK: Destinations (§5.6)
    static let toCustomerService = "Going to customer service."
    static let goingToCheckout = "Going to checkout."
    static func stillOnList(_ names: [String]) -> String { "You still have \(list(names)) on your list." }
    static func checkoutsAhead(_ clock: Int, distance: Float? = nil, steps: Bool = false) -> String {
        "Checkouts ahead, \(clock) o'clock" + about(distance, steps: steps) + "."
    }
    static let cashierHelp = "A cashier can help you scan and pay."
    static func serviceDesk(_ clock: Int, distance: Float? = nil, steps: Bool = false) -> String {
        "Customer service desk, \(clock) o'clock" + about(distance, steps: steps) + "."
    }
    /// ", about 3 meters" when known.
    static func about(_ d: Float?, steps: Bool) -> String {
        guard let d, d.isFinite, d > 0 else { return "" }
        return ", about \(distance(d, steps: steps))"
    }
    static let destinationNotFound = "Can't find it. Ask someone nearby."
    static let atCheckout = "You're at the checkout."
    static let atCustomerService = "You're at customer service."

    // MARK: Signage and aisles (§5.2, §5.7)
    static let noSigns = "I can't see any signs. Turn slowly."
    /// "9 o'clock, aisle 6, coffee and tea." Brief drops the category names.
    static func signDirection(clock: Int, number: String?, words: [String], brief: Bool, target: String) -> String {
        var parts = ["\(clock) o'clock"]
        if let n = number { parts.append("aisle \(n)") }
        let names = brief ? (number == nil ? [target] : []) : words.map { $0.lowercased() }
        if !names.isEmpty { parts.append(list(names)) }
        return parts.joined(separator: ", ") + "."
    }
    static func notOnSigns(_ name: String) -> String { "Not on these signs. Keep turning." }
    static func remembered(_ name: String, number: String?, clock: Int) -> String {
        let at = clock == 6 ? "behind you" : "at \(clock) o'clock"
        return number.map { "\(cap(name)) was aisle \($0), \(at)." } ?? "\(cap(name)) was \(at)."
    }
    static func signAt(_ clock: Int) -> String { "Aisle sign, \(clock) o'clock." }
    static let stepBackTwo = "Take two steps back."
    static let faceLeft = "Face the shelf at 9 o'clock."
    static let faceRight = "Now face 3 o'clock."
    static let walkToEnd = "Walk to the aisle end for signs."
    static func stopAtAisle(number: String?, name: String, clock: Int, categories: [String]) -> String {
        number.map { "Stop. Aisle \($0), \(clock) o'clock." } ?? "Stop. \(cap(name)) aisle, \(clock) o'clock."
    }
    static func thisIsAisle(_ name: String) -> String { "This is the \(name) aisle." }
    static let walkSlowly = "Walk through slowly."
    static func seeOnBothSides(_ things: [String]) -> String { "\(cap(list(Array(things.prefix(2))))) on both sides." }
    static func looksLike(_ name: String, things: [String]) -> String {
        "This looks like \(name)."
    }
    static func adjacent(_ other: String, target: String) -> String {
        "\(cap(target)) is usually nearby. Walk slowly."
    }
    static func different(_ other: String, target: String) -> String {
        "Wrong aisle. Go back to the main aisle."
    }
    static let unsure = "I'm not sure yet. Walk slowly ahead."
    /// The shelf sign names the item; Pick follows when the user stands.
    static func stopHereShelf(clock: Int) -> String { "Stop. Shelf at \(clock) o'clock." }
    /// The vote located the item's section (no side known).
    static let stopHere = "Stop here. Turn to the shelf."
    static let aisleEnd = "End of aisle. Item not found here."
    static let aisleEndOffer = "Say 'find staff' or 'next'."

    // MARK: Shelf (§5.2)
    /// "The shelf is about one step ahead." (LiDAR, ~0.7 m per step).
    static func shelfAhead(_ meters: Float) -> String {
        let n = max(1, Int((meters / SessionTuning.stepLengthMeters).rounded()))
        let words = ["one", "two", "three", "four", "five"]
        let count = n <= words.count ? words[n - 1] : "\(n)"
        return "The shelf is about \(count) \(n == 1 ? "step" : "steps") ahead."
    }
    static let pointAtShelf = "Point at the shelf, chest height."
    static func grab(_ text: String) -> String { "That's \(text). Grab it." }
    static func grabWithAlternative(_ text: String, _ alternative: String) -> String { "This is \(text). \(alternative) Grab it." }
    static let holdUp = "Hold it up in front of you."
    static func thatsMove(_ text: String, _ direction: String) -> String { "That's \(text). Move \(direction)." }
    static let notItMoveRight = "Not it. Move slowly to the right."
    static let turnItSlowly = "Turn it slowly."
    static let holdFarther = "Try holding it a little farther away."
    static func gotIt(_ name: String) -> String { "Got it: \(name)." }
    static func thisSays(_ name: String) -> String { "This says \(name)." }
    /// "That's ground, not whole bean. Put it back." `difference` names what differs (`wrongItemLine`).
    static func wrongItem(_ difference: String) -> String { "\(difference) Put it back." }

    // MARK: Entrance (§5.2)
    static let lookingForEntrance = "Looking for the entrance."
    static func entranceAt(_ clock: Int, kind: DoorKind) -> String {
        let door: String
        switch kind {
        case .automatic: door = " Automatic door."
        case .revolving: door = " Revolving, go slowly."
        case .push: door = " Push door."
        case .pull: door = " Pull door."
        case .unknown: door = ""
        }
        return "Entrance at \(clock) o'clock." + door
    }
    static func cartCorral(_ clock: Int) -> String { "Cart corral at \(clock) o'clock." }
    static let cantSeeEntrance = "I can't see the entrance. Turn slowly."
    static func entranceAhead(_ distance: Float, clock: Int, steps: Bool = false) -> String {
        "Entrance ahead, about \(self.distance(distance, steps: steps)), \(clock) o'clock."
    }
    static func doorNoSign(clock: Int, distance: Float?, steps: Bool = false) -> String {
        let at = distance.map { "Door at \(clock) o'clock, about \(self.distance($0, steps: steps))." } ?? "Door at \(clock) o'clock."
        return at
    }
    static func exitDoor(otherClock: Int, distance: Float? = nil, steps: Bool = false) -> String {
        "Exit door. Try \(otherClock) o'clock" + about(distance, steps: steps) + "."
    }
    static let noDoor = "I can't find a door. Ask someone nearby."
    static let inside = "You're inside."

    // MARK: Stairs (§5.4). Never shortened by verbosity.
    static func stairs(_ o: StairsObservation, steps: Bool = false) -> String {
        var parts = ["Stairs \(o.up ? "up" : "down")"]
        if let n = o.steps, n > 0 { parts.append("\(o.more ? "more than" : "about") \(n) \(n == 1 ? "step" : "steps")") }
        parts.append(steps ? distance(o.distance, steps: true) + " away" : meters(o.distance))   // not confused with stair steps
        return parts.joined(separator: ", ") + "."
    }
    static let stairsNear = "Stairs, 1 meter ahead."
    static let crowded = "Crowded here, be careful."
    static func wetFloorSign(clock: Int) -> String { "Wet floor sign, \(clock) o'clock." }

    // MARK: Positioning (§5.8)
    static func positioning(_ hint: PositioningHint) -> String {
        switch hint {
        case .tiltUp: return "Tilt the phone up."
        case .tiltDown: return "Tilt the phone down."
        case .stepBack: return "Step back a little."
        case .moveCloser: return "Move closer."
        case .slowDown: return "Slow down."
        case .pointInFront: return "Point in front of the phone."
        case .tooDark: return "Too dark to read here."
        case .phoneFlipped: return "Phone may be flipped around."
        }
    }

    // MARK: System (§5.16)
    static let pausedCameraOff = "Guidance paused, camera off."
    static let back = "Back. Danger detection is on."
    static func battery(_ percent: Int) -> String { "Battery low, \(percent) percent." }
    static let hot = "Phone is getting hot. Guidance may slow down."
    static let tooHot = "Phone too hot. Only danger alerts on."
    static let cameraOff = "Camera access is off. Check Settings."
    static let micOff = "Microphone access is off. Check Settings."

    // MARK: Helpers
    /// "coffee", "coffee and tea", "coffee, tea and milk".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// Meters, or steps (~0.7 m) when the user chose steps in setup.
    static func distance(_ d: Float, steps: Bool) -> String {
        guard steps else { return meters(d) }
        let n = max(1, Int((d / SessionTuning.stepLengthMeters).rounded()))
        return n == 1 ? "1 step" : "\(n) steps"
    }

    static func meters(_ d: Float) -> String {
        let n = max(1, Int(d.rounded()))
        return n == 1 ? "1 meter" : "\(n) meters"
    }

    /// Owner rule: spoken lines are at most this many words.
    static let maxWords = 8

    /// Gemini text cut to `maxWords` words (the prompt asks for that; this enforces it).
    static func capWords(_ text: String) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count > maxWords else { return text }
        var t = words.prefix(maxWords).joined(separator: " ")
        while let last = t.last, ",;:-".contains(last) { t.removeLast() }
        return t + "."
    }

    /// Words that make a hint actionable (a place to turn or look). A hint without one is narration: dropped.
    static let directionWords = ["o'clock", "oclock", "left", "right", "ahead", "behind", "straight", "turn", "back",
                                 "forward", "up", "down"]

    /// Gemini's hint as a spoken sentence: only if it gives a direction (owner rule), ≤ 8 words, capitalized,
    /// ending with a period. "" = say nothing.
    static func searchHint(_ hint: String) -> String {
        var t = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        let lower = t.lowercased()
        let words = Set(lower.split { !$0.isLetter && $0 != "'" }.map(String.init))
        guard directionWords.contains(where: { $0.contains("'") || $0 == "oclock" ? lower.contains($0) : words.contains($0) })
        else { return "" }
        t = capWords(t)
        if let last = t.last, !".!?".contains(last) { t += "." }
        return cap(t)
    }

    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
