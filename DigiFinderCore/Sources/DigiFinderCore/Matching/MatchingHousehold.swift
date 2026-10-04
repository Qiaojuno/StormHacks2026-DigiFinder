// Household objects (owner decision): things people look for at home or nearby, mapped to the YOLO (OIV7) class
// that finds them in view. Items the model has no class for (keys, wallet, charger) fall back to reading labels.

public enum MatchingHousehold {
    /// Spoken name (normalizeText form) → model class.
    public static let classes: [String: String] = {
        var m: [String: String] = [:]
        func add(_ cls: String, _ words: [String]) { for w in words { m[w] = cls } }
        add("Mug", ["mug", "coffee mug"])
        add("Coffee cup", ["cup", "coffee cup", "tea cup", "teacup"])
        add("Bottle", ["bottle", "water bottle"])
        add("Wine glass", ["wine glass", "glass"])
        add("Mobile phone", ["phone", "my phone", "cell phone", "cellphone", "mobile phone", "iphone", "smartphone"])
        add("Glasses", ["glasses", "my glasses", "eyeglasses", "reading glasses", "spectacles"])
        add("Sunglasses", ["sunglasses"])
        add("Remote control", ["remote", "remote control", "tv remote", "the remote"])
        add("Backpack", ["backpack", "my backpack"])
        add("Handbag", ["handbag", "purse", "bag", "my bag", "my purse"])
        add("Briefcase", ["briefcase"])
        add("Suitcase", ["suitcase", "luggage"])
        add("Book", ["book", "my book"])
        add("Laptop", ["laptop", "computer", "my laptop"])
        add("Tablet computer", ["tablet", "ipad"])
        add("Computer keyboard", ["keyboard"])
        add("Computer mouse", ["mouse", "computer mouse"])
        add("Headphones", ["headphones", "earphones", "headset"])
        add("Watch", ["watch", "my watch"])
        add("Umbrella", ["umbrella"])
        add("Pen", ["pen", "pencil"])
        add("Scissors", ["scissors"])
        add("Toothbrush", ["toothbrush"])
        add("Spoon", ["spoon"])
        add("Fork", ["fork"])
        add("Knife", ["knife"])
        add("Plate", ["plate"])
        add("Bowl", ["bowl"])
        add("Kettle", ["kettle"])
        add("Teapot", ["teapot"])
        add("Hat", ["hat", "cap", "my hat"])
        add("Coat", ["coat", "my coat"])
        add("Jacket", ["jacket", "my jacket"])
        add("Towel", ["towel"])
        add("Pillow", ["pillow"])
        add("Chair", ["chair"])
        add("Table", ["table"])
        add("Desk", ["desk"])
        add("Couch", ["couch", "sofa"])
        add("Bed", ["bed"])
        add("Lamp", ["lamp"])
        add("Television", ["tv", "television"])
        add("Refrigerator", ["fridge", "refrigerator"])
        add("Microwave oven", ["microwave"])
        add("Sink", ["sink"])
        add("Toilet", ["toilet", "bathroom", "washroom", "restroom"])
        add("Clock", ["clock"])
        add("Calculator", ["calculator"])
        add("Camera", ["camera"])
        add("Box", ["box"])
        add("Envelope", ["envelope", "letter", "mail"])
        add("Light switch", ["light switch", "switch"])
        add("Toilet paper", ["toilet paper"])
        add("Paper towel", ["paper towel", "paper towels"])
        add("Door", ["door"])
        return m
    }()

    /// Every class above (added to the detector's allowlist).
    public static var allClasses: Set<String> { Set(classes.values) }

    /// Model class for a spoken item ("my phone" → "Mobile phone"), trying the whole phrase, then without a leading
    /// "my" / "the", then its last word ("the black mug" → "Mug").
    public static func visualClass(for phrase: String) -> String? {
        let t = normalizeText(phrase)
        if let c = classes[t] { return c }
        var words = t.split(separator: " ").map(String.init)
        while let f = words.first, ["my", "the", "a", "an"].contains(f) { words.removeFirst() }
        if let c = classes[words.joined(separator: " ")] { return c }
        if words.count >= 2, let c = classes[words.suffix(2).joined(separator: " ")] { return c }
        if let last = words.last, let c = classes[last] { return c }
        return nil
    }
}
