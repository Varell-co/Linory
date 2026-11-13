import SwiftUI

struct SettingsView: View {
    @AppStorage("fontSize") private var fontSize = 25.0
    @AppStorage("opacity") private var opacity = 0.78
    @AppStorage("overlayOpacity") private var overlayOpacity = 1.0
    @AppStorage("offset") private var offset = 0.0
    @AppStorage("overlayWidth") private var width = 400.0
    @AppStorage("overlayHeight") private var height = 240.0
    var resize: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Lyrics Overlay").font(.title2.bold())
            control("Schriftgröße", value: $fontSize, range: 14...44, suffix: " pt")
            control("Transparenz: gesamtes Overlay", value: $overlayOpacity, range: 0.15...1, multiplier: 100, suffix: " % Deckkraft")
            control("Transparenz: Hintergrund", value: $opacity, range: 0...1, multiplier: 100, suffix: " % Deckkraft")
            control("Breite", value: $width, range: 260...800, suffix: " px")
            control("Höhe", value: $height, range: 160...500, suffix: " px")
            control("Timing-Korrektur", value: $offset, range: -5...5, suffix: " s", decimals: 1)
            Text("Overlay ein-/ausblenden: ⌥ ⇧ L\nPositive Werte zeigen die Lyrics früher. Songtitel und Interpret werden zur Suche an LRCLIB gesendet.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 420)
        .onChange(of: width) { _ in resize() }
        .onChange(of: height) { _ in resize() }
    }
    private func control(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, multiplier: Double = 1, suffix: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); Text(String(format: "%.*f", decimals, value.wrappedValue * multiplier) + suffix).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
