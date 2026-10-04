// Whole-utterance voice commands (§5.2, §5.9, §5.10). Input is normalizeText output,
// so "what's around" arrives as "what s around".
// Order: exact phrase → phrase with politeness words trimmed from the ends ("um repeat that please")
// → "stop/skip/cancel <item>" ("skip the coffee").

public enum VoiceCommandParser {
    static let table: [String: VoiceCommand] = {
        var t: [String: VoiceCommand] = [:]
        func add(_ cmd: VoiceCommand, _ phrases: [String]) { for p in phrases { t[p] = cmd } }
        add(.stop, ["stop", "skip", "skip item", "skip it", "skip this", "skip that", "skip this one", "skip this item",
                    "skip the item", "next item", "cancel", "cancel it", "cancel this", "cancel that", "never mind",
                    "nevermind", "stop looking", "stop searching", "stop it", "forget it", "forget that",
                    "forget about it", "don t bother", "move on", "give up", "i give up",
                    // After "End of aisle. … or 'next' for the next item." / "I didn't find it" (§5.12)
                    "next", "next one", "go to the next item", "i didn t find it", "didn t find it", "i can t find it",
                    "can t find it", "not here", "it s not here"])
        add(.thatsAll, ["that s all", "that is all", "that s it", "that is it", "that will be all", "that ll be all",
                        "that s everything", "that s all thanks", "that s all thank you", "that s it thanks",
                        "i m done", "i am done", "i m all done", "all done", "we re done", "we are done",
                        "done shopping", "i m done shopping", "finished shopping", "i m finished shopping",
                        "nothing", "nothing else", "nothing more", "no that s all", "no thanks", "no thank you",
                        "i m good", "i am good", "end shopping", "stop shopping", "end session"])
        add(.repeatLast, ["repeat", "repeat that", "repeat it", "say that again", "say it again", "say again", "again",
                          "one more time", "come again", "what did you say", "what was that", "pardon", "pardon me",
                          "sorry", "sorry what", "what", "huh", "i didn t hear", "i didn t hear that",
                          "i didn t catch that", "last one", "repeat the last one"])
        add(.lessDetail, ["quieter", "be quieter", "quiet", "less detail", "less details", "fewer details", "shorter",
                          "less", "less talking", "talk less", "keep it short", "brief", "be brief", "simpler"])
        add(.moreDetail, ["more detail", "more details", "more", "tell me more", "more info", "more information",
                          "give me more detail", "give me more details", "be more detailed", "detailed", "explain more"])
        add(.whatsAround, ["what s around", "what s around me", "what is around", "what is around me", "what s around here",
                           "where am i", "where am i now", "where are we", "look around", "what do you see",
                           "what can you see", "what s near me", "what s nearby", "what is nearby", "what s here",
                           "what s in front of me", "what s ahead", "describe", "describe the area",
                           "describe my surroundings", "describe surroundings", "tell me what s around"])
        add(.outside(true), ["i m outside", "i am outside", "outside", "we re outside", "we are outside",
                             "i m outdoors", "i am outdoors", "i m outside the store", "i am outside the store",
                             "i m in the parking lot", "i m outside now"])
        add(.outside(false), ["i m inside", "i am inside", "inside", "we re inside", "we are inside", "i m indoors",
                              "i m in the store", "i am in the store", "i m inside the store", "i am inside the store",
                              "i m already inside", "already inside", "i m inside now", "i m in the store now"])
        add(.nearby(true), ["it s nearby", "it is nearby", "nearby", "it s close", "it s close by", "close by",
                            "in this room", "it s in this room", "it s in the room", "i m at home", "i am at home",
                            "at home", "look nearby", "search nearby", "find it nearby", "home mode", "nearby mode"])
        add(.nearby(false), ["store mode", "i m in a store", "i am in a store", "i m at the store",
                             "shopping mode"])
        add(.finishTalking, ["done", "finished", "i m finished", "over", "done talking", "i m done talking",
                             "finished talking", "send", "send it"])
        add(.switchGoal, ["switch", "switch it", "switch to it", "switch to that", "switch that", "switch goals",
                          "replace", "replace it", "change it", "change", "change to that", "swap", "swap it",
                          "do that instead", "that instead", "that one instead", "go for that instead"])
        add(.addGoal, ["add it", "add", "add that", "add this", "add it to the list", "add to list", "add to the list",
                       "add it to my list", "add to my list", "add both", "both", "keep both", "queue it",
                       "add it after", "do it after", "after that", "later"])
        return t
    }()

    /// Politeness / hesitation words dropped from either end before a second lookup.
    static let edgeWords: Set<String> = ["um", "uh", "er", "erm", "hmm", "okay", "ok", "so", "oh", "hey", "yeah", "yes",
                                         "please", "well", "and", "now", "just", "can", "could", "would", "will", "you",
                                         "thanks", "thank", "then", "alright", "right"]

    /// "skip the coffee", "stop looking for milk", "cancel coffee": a goal cancel naming the item.
    static let stopPrefixes: [[String]] = [["stop", "looking", "for"], ["stop", "searching", "for"], ["stop", "finding"],
                                           ["skip", "the"], ["skip"], ["cancel", "the"], ["cancel"],
                                           ["forget", "about", "the"], ["forget", "about"], ["forget", "the"]]
    /// Words that turn "forget the coffee, get milk" into a change of mind rather than a plain stop.
    static let notAStop: Set<String> = ["instead", "find", "get", "want", "need", "look", "switch", "and", "then", "to"]

    public static func parse(_ normalized: String) -> VoiceCommand? {
        let t = normalized.split(separator: " ").joined(separator: " ")
        guard !t.isEmpty else { return nil }
        if let c = table[t] { return c }
        var words = t.split(separator: " ").map(String.init)
        while let f = words.first, edgeWords.contains(f), words.count > 1 { words.removeFirst() }
        while let l = words.last, edgeWords.contains(l), words.count > 1 { words.removeLast() }
        if words.count == 1, edgeWords.contains(words[0]) { return nil }
        if let c = table[words.joined(separator: " ")] { return c }
        for p in stopPrefixes where words.count > p.count && Array(words.prefix(p.count)) == p {
            if words.dropFirst(p.count).contains(where: notAStop.contains) { return nil }
            return .stop
        }
        return nil
    }
}
