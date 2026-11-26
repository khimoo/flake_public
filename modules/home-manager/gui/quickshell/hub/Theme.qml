pragma Singleton
import QtQuick

QtObject {
    // Catppuccin Mocha ベース（既存の Waybar / swaylock 配色と統一）
    readonly property color base: "#ee1e1e2e"
    readonly property color mantle: "#f2181825"
    readonly property color surface0: "#313244"
    readonly property color surface1: "#45475a"
    readonly property color surface2: "#585b70"
    readonly property color text: "#cdd6f4"
    readonly property color subtext: "#a6adc8"
    readonly property color muted: "#6c7086"
    readonly property color accent: "#89b4fa"
    readonly property color accentSoft: "#3389b4fa"
    readonly property color green: "#a6e3a1"
    readonly property color yellow: "#f9e2af"
    readonly property color red: "#f38ba8"
    readonly property color redSoft: "#33f38ba8"

    readonly property string fontFamily: "IBM Plex Sans JP"
    readonly property string monoFamily: "PlemolJP Console NF"

    readonly property int radiusLarge: 14
    readonly property int radiusMedium: 8
    readonly property int radiusSmall: 6
}
