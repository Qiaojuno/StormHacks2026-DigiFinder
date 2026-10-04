// Whole-utterance voice commands (§5.2, §5.9, §5.10). Input is normalizeText output,
// so "what's around" arrives as "what s around".

public enum VoiceCommandParser {
    static let table: [String: VoiceCommand] = {
        var t: [String: VoiceCommand] = [:]
        func add(_ cmd: VoiceCommand, _ phrases: [String]) { for p in phrases { t[p] = cmd } }
        add(.stop, ["stop", "skip", "skip item", "skip it", "skip this", "skip this item", "cancel", "never mind",
                    "nevermind", "stop looking", "forget it"])
        add(.thatsAll, ["that s all", "that is all", "that s it", "that is it", "i m done", "i am done",
                        "done shopping", "nothing else", "no that s all", "that s everything"])
        add(.repeatLast, ["repeat", "repeat that", "say that again", "say again", "again", "what did you say", "pardon"])
        add(.lessDetail, ["quieter", "be quieter", "less detail", "less details", "shorter", "less"])
        add(.moreDetail, ["more detail", "more details", "more", "tell me more"])
        add(.whatsAround, ["what s around", "what s around me", "what is around", "what is around me",
                           "where am i", "look around"])
        add(.outside(true), ["i m outside", "i am outside", "outside", "we re outside"])
        add(.outside(false), ["i m inside", "i am inside", "inside", "i m in the store", "i am in the store"])
        add(.finishTalking, ["done", "finished", "i m finished", "over"])
        add(.switchGoal, ["switch", "switch it", "switch to it", "switch that", "replace", "replace it", "change it"])
        add(.addGoal, ["add it", "add", "add that", "add this", "add it to the list", "add to list", "add to the list"])
        return t
    }()

    public static func parse(_ normalized: String) -> VoiceCommand? { table[normalized] }
}
