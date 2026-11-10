/// Vimium-style jump labels. All labels share one length, so none is a prefix of another.
public enum HintLabels {
    /// Home-row letters minus j/k, which move the selection, and minus n/x, which are commands.
    public static let alphabet: [Character] = Array("asdfghl")

    public static func labels(count: Int, alphabet: [Character] = alphabet) -> [String] {
        guard count > 0, !alphabet.isEmpty else { return [] }
        var length = 1
        var capacity = alphabet.count
        while capacity < count {
            length += 1
            capacity *= alphabet.count
        }
        return (0..<count).map { index in
            var remainder = index
            var label = ""
            for _ in 0..<length {
                label = String(alphabet[remainder % alphabet.count]) + label
                remainder /= alphabet.count
            }
            return label
        }
    }
}
