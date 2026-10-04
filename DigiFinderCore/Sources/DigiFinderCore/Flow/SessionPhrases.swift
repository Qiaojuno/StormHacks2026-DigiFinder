// Every line the session speaks. Wording follows §5; keep it in sync with the spec.
import Foundation

enum SessionPhrases {
    // MARK: Start and goals (§5.2, §5.10)
    static let askGoal = "What are you looking for? Press volume up to tell me."
    /// App open (owner decision: starts stopped).
    static let pressToStart = "Press volume up to start."
    // Where the user is (once at app open, before the opening question).
    static let inGroceryStore = "You're in a grocery store."
    /// Said instead of "Looking for X." while the grocery check runs (owner decision), then `nowLookingFor`.
    static let loading = "Loading."
    static func nowLookingFor(_ name: String) -> String { "Okay, now looking for \(name)." }
    static let notInGroceryStore = "You're not in a grocery store."
    static let couldntTellPlace = "I couldn't tell if this is a grocery store."
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
    static let notCaughtNoisy = "Sorry, I didn't catch that. It's noisy here."

    // MARK: Unknown items (§5.2)
    static func unknownOffline(_ words: String) -> String {
        "I don't have \(words) in my list. I'll look for the word on signs and labels."
    }
    static let wordSearch = "I'll look for the word on signs and labels."
    static func foundOnline(_ name: String, aisle: String) -> String { "Found it: \(name). Looking for the \(aisle) aisle." }
    static func found(_ name: String) -> String { "Found it: \(name)." }

    // MARK: Ask (§5.11)
    static let offlineQuestion = "I can't answer that offline. I can still find products, checkout, or staff."
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
    static func next(_ name: String) -> String { "Next: \(name)." }
    static func alsoInAisle(_ name: String) -> String { "\(cap(name)) is in this aisle too." }
    static let notFound = "I didn't find it. It may be out of stock. Say 'find staff' for help."
    static let lostTrack = "I've lost track. Walk ahead slowly and I'll look for signs."
    static let guidancePaused = "Guidance paused. Press volume up when you're ready."

    // MARK: Item in view (global rule) and not-a-store search
    static let turnSlowly = "Turn slowly."
    static func itemAt(_ name: String, clock: Int, distance: Float?, steps: Bool) -> String {
        "\(name.prefix(1).uppercased() + name.dropFirst()) at \(clock) o'clock" + about(distance, steps: steps) + "."
    }
    /// Within reach, Standing → Pick.
    static let pointAtIt = "Point at it with one finger."
    /// Within reach while Walking (once); Pick follows when the user stands.
    static func stopItem(_ name: String, clock: Int) -> String { "Stop. \(cap(name)) at \(clock) o'clock." }
    static func withinReach(_ name: String) -> String {
        "\(name.prefix(1).uppercased() + name.dropFirst()) is right in front of you, within reach."
    }
    static func notFoundNearby(_ name: String) -> String { "I can't find \(name) nearby. Try another spot." }
    static let nearbyOn = "Okay, looking nearby."
    static let nearbyOff = "Okay, store mode."

    // MARK: Destinations (§5.6)
    static let toCustomerService = "I'll take you to customer service. You can also ask anyone nearby."
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
    static let destinationNotFound = "I can't find it. Ask anyone nearby for help."
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
    static func notOnSigns(_ name: String) -> String { "\(cap(name)) isn't on these signs. Keep turning slowly." }
    static func remembered(_ name: String, number: String?, clock: Int) -> String {
        let at = clock == 6 ? "at 6 o'clock behind you" : "at \(clock) o'clock"
        return number.map { "\(cap(name)) was aisle \($0), \(at)." } ?? "\(cap(name)) was \(at)."
    }
    static func signAt(_ clock: Int) -> String { "Aisle sign, \(clock) o'clock." }
    static let stepBackTwo = "Take two steps back."
    static let faceLeft = "Face the shelf at 9 o'clock."
    static let faceRight = "Now face 3 o'clock."
    static let walkToEnd = "Walk to the end of the aisle; the signs are usually there."
    static func stopAtAisle(number: String?, name: String, clock: Int, categories: [String]) -> String {
        let head = number.map { "Stop. Aisle \($0) is at \(clock) o'clock" } ?? "Stop. The \(name) aisle is at \(clock) o'clock"
        return categories.isEmpty ? head + "." : head + ", " + list(categories.map { $0.lowercased() }) + "."
    }
    static func thisIsAisle(_ name: String) -> String { "This is the \(name) aisle." }
    static let walkSlowly = "Walk through slowly."
    static func seeOnBothSides(_ things: [String]) -> String { "I see \(list(things)) on both sides." }
    static func looksLike(_ name: String, things: [String]) -> String {
        things.isEmpty ? "This looks like \(name)." : "This looks like \(name): \(list(things)) ahead."
    }
    static func adjacent(_ other: String, target: String) -> String {
        "This looks like \(other). \(cap(target)) is usually nearby. Walk slowly ahead."
    }
    static func different(_ other: String, target: String) -> String {
        "This looks like \(other), not \(target). Go back to the main aisle."
    }
    static let unsure = "I'm not sure yet. Walk slowly ahead."
    /// The shelf sign names the item; Pick follows when the user stands.
    static func stopHereShelf(clock: Int) -> String { "Stop here. Turn to the shelf at \(clock) o'clock." }
    /// The vote located the item's section (no side known).
    static let stopHere = "Stop here. Turn to the shelf."
    static let aisleEnd = "End of aisle. Item not found here."
    static let aisleEndOffer = "Say 'find staff' for help, or 'next' for the next item."

    // MARK: Shelf (§5.2)
    /// "The shelf is about one step ahead." (LiDAR, ~0.7 m per step).
    static func shelfAhead(_ meters: Float) -> String {
        let n = max(1, Int((meters / SessionTuning.stepLengthMeters).rounded()))
        let words = ["one", "two", "three", "four", "five"]
        let count = n <= words.count ? words[n - 1] : "\(n)"
        return "The shelf is about \(count) \(n == 1 ? "step" : "steps") ahead."
    }
    static let pointAtShelf = "Point at the shelf with one finger. Start at chest height."
    static func grab(_ text: String) -> String { "That's \(text). Grab it." }
    static func grabWithAlternative(_ text: String, _ alternative: String) -> String { "This is \(text). \(alternative) Grab it." }
    static let holdUp = "Hold it up in front of you."
    static func thatsMove(_ text: String, _ direction: String) -> String { "That's \(text). Move \(direction)." }
    static let notItMoveRight = "Not it. Move slowly to the right."
    static let turnItSlowly = "Turn it slowly."
    static let holdFarther = "Try holding it a little farther away."
    static func gotIt(_ name: String) -> String { "Got it: \(name). Put it in your cart." }
    static func thisSays(_ name: String) -> String { "This says \(name). Put it in your cart." }
    /// "That's ground, not whole bean. Put it back." `difference` names what differs (`wrongItemLine`).
    static func wrongItem(_ difference: String) -> String { "\(difference) Put it back." }

    // MARK: Entrance (§5.2)
    static let lookingForEntrance = "Looking for the entrance."
    static func entranceAt(_ clock: Int, kind: DoorKind) -> String {
        let door: String
        switch kind {
        case .automatic: door = " Automatic door."
        case .revolving: door = " It's a revolving door. Go slowly."
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
        return at + " I can't see an entrance sign."
    }
    static func exitDoor(otherClock: Int, distance: Float? = nil, steps: Bool = false) -> String {
        "This door says exit. Another door at \(otherClock) o'clock" + about(distance, steps: steps) + "."
    }
    static let noDoor = "I can't find a door. Ask someone nearby."
    static let inside = "You're inside."

    // MARK: Stairs (§5.4). Never shortened by verbosity.
    static func stairs(_ o: StairsObservation, steps: Bool = false) -> String {
        var parts = ["Stairs going \(o.up ? "up" : "down")"]
        if let n = o.steps, n > 0 { parts.append("\(o.more ? "more than" : "about") \(n) \(n == 1 ? "step" : "steps")") }
        parts.append(steps ? distance(o.distance, steps: true) + " away" : meters(o.distance))   // not confused with stair steps
        parts.append("12 o'clock")
        return parts.joined(separator: ", ") + "."
    }
    static let stairsNear = "Stairs, 1 meter ahead."

    // MARK: Positioning (§5.8)
    static func positioning(_ hint: PositioningHint) -> String {
        switch hint {
        case .tiltUp: return "Tilt the phone up."
        case .tiltDown: return "Tilt the phone down."
        case .stepBack: return "Step back a little."
        case .moveCloser: return "Move closer."
        case .slowDown: return "Slow down."
        case .pointInFront: return "Point in front of the phone, at chest height."
        case .tooDark: return "It's too dark for me to read here."
        case .phoneFlipped: return "Phone may be flipped around."
        }
    }

    // MARK: System (§5.16)
    static let pausedCameraOff = "Guidance paused, camera off."
    static let back = "Back. Danger detection is on."
    static func battery(_ percent: Int) -> String { "Battery low, \(percent) percent." }
    static let hot = "Phone is getting hot. Guidance may slow down."
    static let tooHot = "Phone is too hot. Only danger alerts are on."
    static let cameraOff = "Camera access is off. Ask someone to turn it on in Settings."
    static let micOff = "Microphone access is off. Ask someone to turn it on in Settings."

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

    /// Gemini's hint as a spoken sentence: trimmed, capitalized, ending with a period.
    static func searchHint(_ hint: String) -> String {
        var t = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let last = t.last, !".!?".contains(last) { t += "." }
        return cap(t)
    }

    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
