import AppKit
import ApplicationServices
import Carbon

// 영문 자판(두벌식 위치)으로 잘못 입력한 한글 구절을 구분자 입력 시점에 자동으로 교정한다.
// 모든 판단은 기기 내부의 보수적 휴리스틱으로만 수행한다.
@MainActor
final class KoreanTypoCorrector {
    var isEnabled = false {
        didSet {
            if !isEnabled { reset() }
        }
    }

    private var buffer = ""
    private var lastKeystrokeAt = Date.distantPast
    private var workspaceObserver: NSObjectProtocol?
    private var inputSourceObserver: NSObjectProtocol?

    private static let syntheticMarker: Int64 = 0x5447_4B54
    private static let maxBufferLength = 80
    private static let staleInterval: TimeInterval = 8
    private static let punctuationDelimiters: Set<Character> = [".", ",", "!", "?", ";", ":"]
    // tab, delete, esc, keypad enter, help, home, pgup, fwd delete, end, pgdn, 방향키
    private static let resetKeyCodes: Set<Int64> = [48, 51, 53, 76, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126]

    init() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(inputSourceObserver)
        }
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    func handleKeyDown(_ event: CGEvent) -> Bool {
        guard isEnabled else { return false }
        // 교정 시 우리가 게시한 합성 이벤트는 다시 처리하지 않는다.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }

        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            reset()
            return false
        }
        if Self.resetKeyCodes.contains(event.getIntegerValueField(.keyboardEventKeycode)) {
            reset()
            return false
        }

        let now = Date()
        if now.timeIntervalSince(lastKeystrokeAt) > Self.staleInterval {
            reset()
        }
        lastKeystrokeAt = now

        guard let character = typedCharacter(of: event) else {
            reset()
            return false
        }

        switch character {
        case "a"..."z":
            buffer.append(character)
            if buffer.count > Self.maxBufferLength { reset() }
            return false
        case " ":
            return handleDelimiter(" ")
        case "\r", "\n":
            return handleDelimiter("\r")
        case let ch where Self.punctuationDelimiters.contains(ch):
            return handleDelimiter(ch)
        default:
            reset()
            return false
        }
    }

    // MARK: - 감지

    private func handleDelimiter(_ delimiter: Character) -> Bool {
        guard !buffer.isEmpty else { return false }

        let parts = buffer.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var converted: [String] = []
        var wordCount = 0
        for part in parts {
            if part.isEmpty {
                converted.append("")
                continue
            }
            guard let hangul = hangulCandidate(for: part) else {
                // 일반 영어로 보이는 단어가 섞이면 구절 전체를 포기한다.
                reset()
                return false
            }
            converted.append(hangul)
            wordCount += 1
        }

        if wordCount >= 2 {
            guard isSafeToCorrect else {
                reset()
                return false
            }
            let deletionCount = buffer.count
            let replacement = converted.joined(separator: " ")
            reset()
            applyCorrection(deleting: deletionCount, replacement: replacement, delimiter: delimiter)
            return true
        } else if delimiter == " " {
            // 화면에 전달되는 공백은 그대로 버퍼에도 반영해 삭제 문자 수가 어긋나지 않게 한다.
            buffer.append(" ")
            if buffer.count > Self.maxBufferLength { reset() }
        } else {
            reset()
        }
        return false
    }

    private func hangulCandidate(for word: String) -> String? {
        guard word.count >= 2,
              word.allSatisfy({ ("a"..."z").contains($0) }),
              !Self.commonEnglishWords.contains(word),
              containsRareEnglishBigram(word) else { return nil }
        return DubeolsikComposer.compose(fromQwerty: word)
    }

    // 영어에서 흔한 두 글자 조합만으로 이루어진 단어는 영어일 수 있으므로 건드리지 않는다.
    private func containsRareEnglishBigram(_ word: String) -> Bool {
        let characters = Array(word)
        guard characters.count >= 2 else { return false }
        for index in 0..<(characters.count - 1) {
            let bigram = String(characters[index]) + String(characters[index + 1])
            if !Self.commonEnglishBigrams.contains(bigram) { return true }
        }
        return false
    }

    // MARK: - 안전 확인

    private var isSafeToCorrect: Bool {
        guard !IsSecureEventInputEnabled() else { return false }
        guard !isKoreanInputSourceActive else { return false }
        guard !focusedElementIsSecureTextField else { return false }
        return true
    }

    private var focusedElementIsSecureTextField: Bool {
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else {
            return false
        }
        return (subrole as? String) == "AXSecureTextField"
    }

    // MARK: - 교정 적용

    private func applyCorrection(deleting deletionCount: Int, replacement: String, delimiter: Character) {
        let text = delimiter == "\r" ? replacement : replacement + String(delimiter)
        Task { @MainActor [weak self] in
            guard let self, self.isEnabled else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            for _ in 0..<deletionCount {
                self.postKey(51, source: source)
            }
            self.postText(text, source: source)
            if delimiter == "\r" {
                self.postKey(36, source: source)
            }
            self.selectKoreanInputSourceIfAvailable()
        }
    }

    private func postKey(_ keyCode: CGKeyCode, source: CGEventSource?) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private func postText(_ text: String, source: CGEventSource?) {
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isDown) else { continue }
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                if isDown {
                    event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                }
                event.post(tap: .cghidEventTap)
            }
            index += 20
        }
    }

    // MARK: - 입력기 전환

    private var isKoreanInputSourceActive: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return false }
        return inputSourceID(of: source)?.contains("Korean") ?? false
    }

    private func selectKoreanInputSourceIfAvailable() {
        guard let listRef = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return }
        var koreanSources: [TISInputSource] = []
        for item in listRef as NSArray {
            let source = item as! TISInputSource
            guard let id = inputSourceID(of: source),
                  id.hasPrefix("com.apple.inputmethod.Korean"),
                  boolProperty(of: source, key: kTISPropertyInputSourceIsSelectCapable) else { continue }
            koreanSources.append(source)
        }
        let preferred = koreanSources.first { inputSourceID(of: $0) == "com.apple.inputmethod.Korean.2SetKorean" }
        if let target = preferred ?? koreanSources.first {
            TISSelectInputSource(target)
        }
    }

    private func inputSourceID(of source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(of source: TISInputSource, key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    // MARK: - 입력 문자 추출

    private func typedCharacter(of event: CGEvent) -> Character? {
        var codeUnits = [UniChar](repeating: 0, count: 4)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &codeUnits)
        let string = String(utf16CodeUnits: codeUnits, count: length)
        guard string.count == 1 else { return nil }
        return string.first
    }

    // MARK: - 영어 판별 자료

    private static let commonEnglishWords: Set<String> = [
        "the", "be", "to", "of", "and", "in", "that", "have", "it", "for", "not", "on", "with", "he",
        "as", "you", "do", "at", "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what", "so", "up", "out",
        "if", "about", "who", "get", "which", "go", "me", "when", "make", "can", "like", "time", "no",
        "just", "him", "know", "take", "people", "into", "year", "your", "good", "some", "could",
        "them", "see", "other", "than", "then", "now", "look", "only", "come", "its", "over", "think",
        "also", "back", "after", "use", "two", "how", "our", "work", "first", "well", "way", "even",
        "new", "want", "because", "any", "these", "give", "day", "most", "us", "is", "was", "are",
        "were", "been", "has", "had", "did", "said", "made", "went", "got", "very", "much", "many",
        "more", "such", "here", "where", "why", "before", "again", "still", "should", "must", "may",
        "might", "shall", "does", "done", "each", "own", "same", "too", "old", "great", "little",
        "world", "life", "hand", "part", "child", "eye", "woman", "man", "place", "case", "week",
        "point", "home", "water", "room", "mother", "area", "money", "story", "fact", "month", "lot",
        "right", "study", "book", "word", "side", "kind", "head", "house", "friend", "father",
        "power", "hour", "game", "line", "end", "member", "law", "car", "city", "name", "team",
        "minute", "idea", "kid", "body", "face", "level", "door", "art", "war", "history",
        "result", "change", "morning", "reason", "girl", "boy", "guy", "moment", "air", "force",
        "state", "never", "always", "really", "thing", "long", "down", "off", "yes", "yet", "let",
        "run", "read", "need", "feel", "seem", "leave", "call", "keep", "help", "talk", "turn",
        "start", "show", "hear", "play", "move", "live", "believe", "bring", "happen", "write",
        "sit", "stand", "lose", "pay", "meet", "include", "continue", "set", "learn", "lead",
        "understand", "watch", "follow", "stop", "create", "speak", "spend", "grow", "open", "walk",
        "win", "offer", "remember", "love", "consider", "appear", "buy", "wait", "serve", "die",
        "send", "expect", "build", "stay", "fall", "cut", "reach", "kill", "remain", "hello", "ok",
        "okay", "please", "thanks", "thank", "sorry", "hi", "bye", "test", "file", "code", "data",
        "user", "app", "mac", "email", "web", "link", "type", "text", "list", "note", "next", "last"
    ]

    private static let commonEnglishBigrams: Set<String> = [
        "ab", "ac", "ad", "af", "ag", "ah", "ai", "ak", "al", "am", "an", "ap", "ar", "as", "at",
        "au", "av", "aw", "ax", "ay", "az",
        "ba", "bb", "be", "bi", "bj", "bl", "bm", "bo", "br", "bs", "bt", "bu", "by",
        "ca", "cc", "ce", "ch", "ci", "ck", "cl", "co", "cq", "cr", "cs", "ct", "cu", "cy",
        "da", "dd", "de", "dg", "di", "dj", "dl", "dm", "dn", "do", "dr", "ds", "du", "dv", "dy",
        "ea", "eb", "ec", "ed", "ee", "ef", "eg", "eh", "ei", "ek", "el", "em", "en", "eo", "ep",
        "eq", "er", "es", "et", "eu", "ev", "ew", "ex", "ey",
        "fa", "fe", "ff", "fi", "fl", "fo", "fr", "ft", "fu", "fy",
        "ga", "ge", "gg", "gh", "gi", "gl", "gn", "go", "gr", "gs", "gt", "gu",
        "ha", "hb", "he", "hi", "hn", "ho", "hr", "hs", "ht", "hu", "hy",
        "ia", "ib", "ic", "id", "ie", "if", "ig", "ik", "il", "im", "in", "io", "ip", "ir", "is",
        "it", "iv", "ix", "iz",
        "ja", "je", "ji", "jo", "ju",
        "ka", "ke", "ki", "kn", "ko", "ks", "ku", "ky",
        "la", "lc", "ld", "le", "lf", "li", "lk", "ll", "lm", "lo", "lp", "lr", "ls", "lt", "lu",
        "lv", "lw", "ly",
        "ma", "mb", "me", "mf", "mi", "ml", "mm", "mn", "mo", "mp", "ms", "mu", "my",
        "na", "nb", "nc", "nd", "ne", "nf", "ng", "nh", "ni", "nj", "nk", "nl", "nm", "nn", "no",
        "np", "nr", "ns", "nt", "nu", "nv", "nw", "ny",
        "oa", "ob", "oc", "od", "oe", "of", "og", "oh", "oi", "ok", "ol", "om", "on", "oo", "op",
        "or", "os", "ot", "ou", "ov", "ow", "ox", "oy",
        "pa", "pe", "ph", "pi", "pl", "po", "pp", "pr", "ps", "pt", "pu", "py",
        "qu",
        "ra", "rb", "rc", "rd", "re", "rf", "rg", "rh", "ri", "rk", "rl", "rm", "rn", "ro", "rp",
        "rr", "rs", "rt", "ru", "rv", "rw", "ry",
        "sa", "sb", "sc", "sd", "se", "sf", "sh", "si", "sk", "sl", "sm", "sn", "so", "sp", "sq",
        "ss", "st", "su", "sw", "sy",
        "ta", "tb", "tc", "te", "tf", "th", "ti", "tl", "tm", "tn", "to", "tr", "ts", "tt", "tu",
        "tw", "ty",
        "ua", "ub", "uc", "ud", "ue", "uf", "ug", "uh", "ui", "ul", "um", "un", "up", "ur", "us",
        "ut", "uy",
        "va", "ve", "vi", "vo", "vy",
        "wa", "wd", "we", "wh", "wi", "wl", "wn", "wo", "wr", "ws",
        "xc", "xi", "xp", "xt",
        "ya", "yb", "yc", "ye", "yi", "yl", "ym", "yn", "yo", "yp", "ys", "yt", "yu", "yw", "yz",
        "za", "ze", "zi", "zo", "zy"
    ]
}
