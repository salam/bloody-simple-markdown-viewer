import Foundation

/// GitHub emoji shortcodes. Not part of CommonMark, GFM or cmark-gfm; GitHub
/// substitutes these itself, so a renderer that wants parity has to as well.
///
/// This is the common subset, not the full gemoji table, which runs to about
/// 1,800 entries and would cost more than it earns in a viewer.
enum Emoji {
    static func substitute(in text: String) -> String {
        guard text.contains(":") else { return text }
        var out = text
        for (code, glyph) in table {
            out = out.replacingOccurrences(of: ":\(code):", with: glyph)
        }
        return out
    }

    static let table: [String: String] = [
        "smile": "😄", "smiley": "😃", "grin": "😁", "laughing": "😆", "joy": "😂",
        "rofl": "🤣", "wink": "😉", "blush": "😊", "heart_eyes": "😍", "thinking": "🤔",
        "neutral_face": "😐", "confused": "😕", "cry": "😢", "sob": "😭", "angry": "😠",
        "rage": "😡", "sunglasses": "😎", "scream": "😱", "sleeping": "😴", "nerd_face": "🤓",
        "tada": "🎉", "rocket": "🚀", "fire": "🔥", "sparkles": "✨", "star": "⭐",
        "star2": "🌟", "boom": "💥", "zap": "⚡", "bulb": "💡", "gem": "💎",
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎", "ok_hand": "👌",
        "wave": "👋", "clap": "👏", "pray": "🙏", "muscle": "💪", "point_right": "👉",
        "heart": "❤️", "broken_heart": "💔", "yellow_heart": "💛", "green_heart": "💚",
        "blue_heart": "💙", "purple_heart": "💜", "orange_heart": "🧡", "black_heart": "🖤",
        "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "warning": "⚠️",
        "exclamation": "❗", "question": "❓", "no_entry": "⛔", "stop_sign": "🛑",
        "bug": "🐛", "beetle": "🪲", "ant": "🐜", "snail": "🐌", "turtle": "🐢",
        "rabbit": "🐰", "cat": "🐱", "dog": "🐶", "bear": "🐻", "panda_face": "🐼",
        "penguin": "🐧", "bird": "🐦", "fish": "🐟", "whale": "🐳", "dolphin": "🐬",
        "book": "📖", "books": "📚", "memo": "📝", "pencil": "📝", "clipboard": "📋",
        "file_folder": "📁", "open_file_folder": "📂", "page_facing_up": "📄",
        "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉", "bar_chart": "📊",
        "computer": "💻", "keyboard": "⌨️", "iphone": "📱", "camera": "📷", "bulb_on": "💡",
        "lock": "🔒", "unlock": "🔓", "key": "🔑", "mag": "🔍", "gear": "⚙️",
        "wrench": "🔧", "hammer": "🔨", "nut_and_bolt": "🔩", "link": "🔗", "package": "📦",
        "coffee": "☕", "beer": "🍺", "pizza": "🍕", "cake": "🍰", "apple": "🍎",
        "sun": "☀️", "cloud": "☁️", "rain": "🌧️", "snowflake": "❄️", "rainbow": "🌈",
        "earth_americas": "🌎", "moon": "🌙", "hourglass": "⏳", "alarm_clock": "⏰",
        "trophy": "🏆", "medal": "🏅", "dart": "🎯", "game_die": "🎲", "art": "🎨",
        "construction": "🚧", "recycle": "♻️", "100": "💯", "ok": "🆗", "new": "🆕",
        "arrow_right": "➡️", "arrow_left": "⬅️", "arrow_up": "⬆️", "arrow_down": "⬇️",
        "eyes": "👀", "brain": "🧠", "skull": "💀", "ghost": "👻", "alien": "👽",
        "robot": "🤖", "santa": "🎅", "gift": "🎁", "balloon": "🎈", "confetti_ball": "🎊"
    ]
}
