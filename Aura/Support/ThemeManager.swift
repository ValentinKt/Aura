import Observation
import SwiftUI

@MainActor
@Observable
final class ThemeManager {
    private(set) var palette: ThemePalette
    static let defaultPalette = ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.5, green: 0.5, blue: 0.6))

    init(initial: ThemePalette) {
        palette = initial
    }

    convenience init() {
        self.init(initial: Self.defaultPalette)
    }

    func updatePalette(_ palette: ThemePalette) {
        self.palette = palette
    }

    func color(from components: ColorComponents) -> Color {
        Color(red: components.red, green: components.green, blue: components.blue, opacity: components.alpha)
    }
}
