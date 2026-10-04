// Owner rule: every spoken line is at most 8 words (fewer is better), and only actionable information.
import XCTest
@testable import DigiFinderCore

final class PhraseLengthTests: XCTestCase {
    private func words(_ s: String) -> Int { s.split(whereSeparator: \.isWhitespace).count }

    /// Every fixed line, and every template with a typical one-word name and a 2-item list.
    func testEveryLineIsAtMostEightWords() {
        let name = "coffee", list = ["coffee", "tea"]
        let stairs = StairsObservation(up: true, distance: 3, steps: 8, more: true)
        var lines: [String] = [
            SessionPhrases.askGoal, SessionPhrases.pressToStart, SessionPhrases.started, SessionPhrases.loading,
            SessionPhrases.nowLookingFor(name), SessionPhrases.couldntTellPlace, SessionPhrases.lookingFor(name),
            SessionPhrases.instead(name), SessionPhrases.added(name), SessionPhrases.willAdd(name),
            SessionPhrases.stillLooking(name), SessionPhrases.notCaught, SessionPhrases.notCaughtNoisy,
            SessionPhrases.unknownOffline(name), SessionPhrases.wordSearch, SessionPhrases.foundOnline(name, aisle: "tea"),
            SessionPhrases.found(name), SessionPhrases.offlineQuestion, SessionPhrases.onlineHelpOff,
            SessionPhrases.sayAgain, SessionPhrases.nothingAround, SessionPhrases.stopped, SessionPhrases.shoppingDone(2),
            SessionPhrases.pressForAnother, SessionPhrases.next(name), SessionPhrases.alsoInAisle(name),
            SessionPhrases.notFound, SessionPhrases.lostTrack, SessionPhrases.guidancePaused, SessionPhrases.turnSlowly,
            SessionPhrases.itemAt(name, clock: 2, distance: 3, steps: false), SessionPhrases.pointAtIt,
            SessionPhrases.stopItem(name, clock: 12), SessionPhrases.withinReach(name),
            SessionPhrases.notFoundNearby(name), SessionPhrases.toCustomerService, SessionPhrases.goingToCheckout,
            SessionPhrases.stillOnList([name]), SessionPhrases.checkoutsAhead(12, distance: 5),
            SessionPhrases.cashierHelp, SessionPhrases.serviceDesk(3, distance: 4),
            SessionPhrases.destinationNotFound, SessionPhrases.atCheckout, SessionPhrases.atCustomerService,
            SessionPhrases.noSigns, SessionPhrases.signDirection(clock: 9, number: "6", words: list, brief: false, target: name),
            SessionPhrases.notOnSigns(name), SessionPhrases.remembered(name, number: "6", clock: 6),
            SessionPhrases.signAt(9), SessionPhrases.stepBackTwo, SessionPhrases.faceLeft, SessionPhrases.faceRight,
            SessionPhrases.walkToEnd, SessionPhrases.stopAtAisle(number: "6", name: name, clock: 9, categories: list),
            SessionPhrases.stopAtAisle(number: nil, name: name, clock: 9, categories: list),
            SessionPhrases.thisIsAisle(name), SessionPhrases.walkSlowly, SessionPhrases.seeOnBothSides(list + ["milk"]),
            SessionPhrases.looksLike(name, things: list), SessionPhrases.adjacent("tea", target: name),
            SessionPhrases.different("pasta", target: name), SessionPhrases.unsure, SessionPhrases.stopHereShelf(clock: 9),
            SessionPhrases.stopHere, SessionPhrases.aisleEnd, SessionPhrases.aisleEndOffer, SessionPhrases.shelfAhead(1.4),
            SessionPhrases.pointAtShelf, SessionPhrases.grab(name), SessionPhrases.holdUp, SessionPhrases.thatsMove(name, "left"),
            SessionPhrases.notItMoveRight, SessionPhrases.turnItSlowly, SessionPhrases.holdFarther, SessionPhrases.gotIt(name),
            SessionPhrases.thisSays(name), SessionPhrases.lookingForEntrance, SessionPhrases.cartCorral(12),
            SessionPhrases.cantSeeEntrance, SessionPhrases.entranceAhead(5, clock: 1),
            SessionPhrases.doorNoSign(clock: 1, distance: 8), SessionPhrases.exitDoor(otherClock: 10, distance: 6),
            SessionPhrases.noDoor, SessionPhrases.inside, SessionPhrases.stairs(stairs), SessionPhrases.stairsNear,
            SessionPhrases.crowded, SessionPhrases.wetFloorSign(clock: 1), SessionPhrases.pausedCameraOff,
            SessionPhrases.back, SessionPhrases.battery(15), SessionPhrases.hot, SessionPhrases.tooHot,
            SessionPhrases.cameraOff, SessionPhrases.micOff,
            alertPhrase(label: "Barrier", steer: .clock(2)), alertPhrase(label: "Person", steer: .stop),
            clearPathPhrase(meters: 4),
        ]
        for kind in [DoorKind.automatic, .revolving, .push, .pull, .unknown] { lines.append(SessionPhrases.entranceAt(1, kind: kind)) }
        for h in [PositioningHint.tiltUp, .tiltDown, .stepBack, .moveCloser, .slowDown, .pointInFront, .tooDark, .phoneFlipped] {
            lines.append(SessionPhrases.positioning(h))
        }
        for line in lines {
            XCTAssertLessThanOrEqual(words(line), SessionPhrases.maxWords, "too long: \(line)")
        }
    }

    func testGeminiTextIsCutToEightWords() {
        XCTAssertEqual(SessionPhrases.capWords("Yes, Oatly oat milk."), "Yes, Oatly oat milk.")
        XCTAssertEqual(SessionPhrases.capWords("There is a long hallway with doors on both sides and a bench"),
                       "There is a long hallway with doors on.")
    }

    /// The owner's example: narration with no direction is never spoken.
    func testHintsWithoutADirectionAreDropped() {
        XCTAssertEqual(SessionPhrases.searchHint("I don't see group of three girls, I only see one boy on his laptop"), "")
        XCTAssertEqual(SessionPhrases.searchHint("try 3 o'clock"), "Try 3 o'clock.")
        XCTAssertEqual(SessionPhrases.searchHint("shelves behind you may have it"), "Shelves behind you may have it.")
        XCTAssertEqual(SessionPhrases.searchHint("a blue mug and some books on a desk"), "")
    }
}
