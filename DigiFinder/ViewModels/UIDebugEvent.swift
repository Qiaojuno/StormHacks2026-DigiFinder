import Foundation
import DigiFinderCore

/// Event buttons of the debug panel: canned `SessionEvent`s that stand in for Perception, Safety and System output.
enum UIDebugEvent: String, CaseIterable, Identifiable {
    case signs, aisleVerdict, arrivedAtAisle, arrivedAtDestination, itemSeen, searchHint, aisleEnd, pointed, confirmed
    case danger, dangerCleared, stairs, outside, inside, onlineOn, onlineOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signs: return "Signs"
        case .aisleVerdict: return "Aisle verdict"
        case .arrivedAtAisle: return "Arrived at aisle"
        case .arrivedAtDestination: return "Arrived at place"
        case .itemSeen: return "Item in reach"
        case .searchHint: return "Search hint"
        case .aisleEnd: return "Aisle end"
        case .pointed: return "Pointed"
        case .confirmed: return "Confirmed"
        case .danger: return "Danger"
        case .dangerCleared: return "Danger cleared"
        case .stairs: return "Stairs"
        case .outside: return "Outside"
        case .inside: return "Inside"
        case .onlineOn: return "Online on"
        case .onlineOff: return "Online off"
        }
    }

    /// Spoken by VoiceOver for the button.
    var accessibilityLabel: String {
        switch self {
        case .signs: return "Send signs: aisle 6, coffee and tea, at 12 o'clock"
        case .aisleVerdict: return "Send aisle verdict: coffee"
        case .arrivedAtAisle: return "Send arrived at aisle, 9 o'clock"
        case .arrivedAtDestination: return "Send arrived at destination"
        case .itemSeen: return "Send item seen at 12 o'clock, 1 meter"
        case .searchHint: return "Send search hint: coffee sign at 10 o'clock"
        case .aisleEnd: return "Send end of aisle"
        case .pointed: return "Send pointed product: Folgers Classic Roast"
        case .confirmed: return "Send confirmed product: Folgers Classic Roast, the goal"
        case .danger: return "Send danger"
        case .dangerCleared: return "Send danger cleared"
        case .stairs: return "Send stairs going up, 8 steps, 1 meter ahead"
        case .outside: return "Send outside"
        case .inside: return "Send inside"
        case .onlineOn: return "Send online on"
        case .onlineOff: return "Send online off"
        }
    }

    var event: SessionEvent {
        switch self {
        case .signs:
            return .signs([AisleSign(number: "6", words: ["coffee", "tea"], clock: 12),
                           AisleSign(number: "7", words: ["cereal"], clock: 1)])
        case .aisleVerdict: return .aisleVerdict("coffee", evidence: ["coffee", "tea"])
        case .arrivedAtAisle: return .arrivedAtAisle(clock: 9)
        case .arrivedAtDestination: return .arrivedAtDestination
        case .itemSeen: return .itemSeen(clock: 12, distance: 1)
        case .searchHint: return .searchHint("Coffee sign at 10 o'clock")
        case .aisleEnd: return .aisleEnd
        case .pointed: return .pointed(PointedProduct(text: "Folgers Classic Roast", match: 0.9))
        case .confirmed:
            return .confirmed(ProductInfo(code: "0025500002312", name: "Classic Roast Ground Coffee",
                                          brand: "Folgers", quantity: "30.5 oz", aisle: "coffee"), isGoal: true)
        case .danger: return .danger(cutRecording: false)
        case .dangerCleared: return .dangerCleared
        case .stairs: return .stairs(StairsObservation(up: true, distance: 1.0, steps: 8))
        case .outside: return .outside(true)
        case .inside: return .outside(false)
        case .onlineOn: return .system(.online(true))
        case .onlineOff: return .system(.online(false))
        }
    }
}
