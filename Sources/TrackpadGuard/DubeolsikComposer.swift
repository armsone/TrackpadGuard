import Foundation

// 표준 두벌식 자판 위치를 기준으로 QWERTY 소문자 열을 완성형 한글로 조합한다.
// 완성된 음절로만 끝나지 않는 열(자모가 남거나 조합 불가한 경우)은 nil을 돌려준다.
enum DubeolsikComposer {
    private static let keyToJamo: [Character: Character] = [
        "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ",
        "Q": "ㅃ", "W": "ㅉ", "E": "ㄸ", "R": "ㄲ", "T": "ㅆ",
        "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
        "O": "ㅒ", "P": "ㅖ",
        "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ",
        "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
        "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ",
        "b": "ㅠ", "n": "ㅜ", "m": "ㅡ"
    ]

    private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
    private static let finals = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
    private static let vowels: Set<Character> = Set("ㅏㅐㅑㅓㅔㅕㅗㅛㅜㅠㅡㅣ")

    private static let compoundMedials: [Character: [Character: Character]] = [
        "ㅗ": ["ㅏ": "ㅘ", "ㅐ": "ㅙ", "ㅣ": "ㅚ"],
        "ㅜ": ["ㅓ": "ㅝ", "ㅔ": "ㅞ", "ㅣ": "ㅟ"],
        "ㅡ": ["ㅣ": "ㅢ"]
    ]

    private static let compoundFinals: [Character: [Character: Character]] = [
        "ㄱ": ["ㅅ": "ㄳ"],
        "ㄴ": ["ㅈ": "ㄵ", "ㅎ": "ㄶ"],
        "ㄹ": ["ㄱ": "ㄺ", "ㅁ": "ㄻ", "ㅂ": "ㄼ", "ㅅ": "ㄽ", "ㅌ": "ㄾ", "ㅍ": "ㄿ", "ㅎ": "ㅀ"],
        "ㅂ": ["ㅅ": "ㅄ"]
    ]

    static func compose(fromQwerty word: String) -> String? {
        var output = ""
        var lead: Character?
        var medial: Character?
        var tail: [Character] = []

        func commit() -> Bool {
            guard let lead, let medial,
                  let leadIndex = initials.firstIndex(of: lead),
                  let medialIndex = medials.firstIndex(of: medial) else { return false }
            var finalIndex = 0
            if !tail.isEmpty {
                let tailJamo: Character
                if tail.count == 2 {
                    guard let compound = compoundFinals[tail[0]]?[tail[1]] else { return false }
                    tailJamo = compound
                } else {
                    tailJamo = tail[0]
                }
                guard let index = finals.firstIndex(of: tailJamo) else { return false }
                finalIndex = index + 1
            }
            let scalarValue = 0xAC00 + (leadIndex * 21 + medialIndex) * 28 + finalIndex
            guard let scalar = Unicode.Scalar(scalarValue) else { return false }
            output.append(Character(scalar))
            return true
        }

        func commitAndClear() -> Bool {
            guard commit() else { return false }
            lead = nil
            medial = nil
            tail = []
            return true
        }

        for key in word {
            let normalizedKey = Character(String(key).lowercased())
            guard let jamo = keyToJamo[key] ?? keyToJamo[normalizedKey] else { return nil }
            if vowels.contains(jamo) {
                if medial == nil {
                    // 초성 없는 모음은 완성 음절이 될 수 없다.
                    guard lead != nil else { return nil }
                    medial = jamo
                } else if tail.isEmpty {
                    guard let combined = compoundMedials[medial!]?[jamo] else { return nil }
                    medial = combined
                } else {
                    // 종성 하나를 다음 음절의 초성으로 넘긴다.
                    let stolen = tail.removeLast()
                    guard commitAndClear() else { return nil }
                    lead = stolen
                    medial = jamo
                }
            } else {
                if medial == nil {
                    guard lead == nil else { return nil }
                    lead = jamo
                } else if tail.isEmpty {
                    guard finals.contains(jamo) else { return nil }
                    tail = [jamo]
                } else if tail.count == 1, compoundFinals[tail[0]]?[jamo] != nil {
                    tail.append(jamo)
                } else {
                    guard commitAndClear() else { return nil }
                    lead = jamo
                }
            }
        }

        if lead != nil || medial != nil || !tail.isEmpty {
            guard medial != nil, commitAndClear() else { return nil }
        }
        return output.isEmpty ? nil : output
    }
}
