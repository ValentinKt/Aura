import Foundation

struct Mood: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var theme: String
    var subtheme: String
    var layerMix: [String: Float]
    var wallpaper: WallpaperDescriptor
    var palette: ThemePalette

    init(id: String, name: String, theme: String, subtheme: String, layerMix: [String: Float], wallpaper: WallpaperDescriptor, palette: ThemePalette) {
        self.id = id
        self.name = name
        self.theme = theme
        self.subtheme = subtheme
        self.layerMix = layerMix
        self.wallpaper = wallpaper
        self.palette = palette
    }
}

struct ThemePalette: Codable, Hashable {
    var primary: ColorComponents
    var secondary: ColorComponents
    var accent: ColorComponents

    init(primary: ColorComponents, secondary: ColorComponents, accent: ColorComponents) {
        self.primary = primary
        self.secondary = secondary
        self.accent = accent
    }
}

struct ColorComponents: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

struct WallpaperDescriptor: Codable, Hashable {
    var type: WallpaperType
    var resources: [String]
    var gradientStops: [ColorComponents]
    var fps: Double

    init(type: WallpaperType, resources: [String] = [], gradientStops: [ColorComponents] = [], fps: Double = 12) {
        self.type = type
        self.resources = resources
        self.gradientStops = gradientStops
        self.fps = fps
    }
}

enum WallpaperType: String, Codable, Hashable {
    case staticImage
    case animated
    case gradient
    case particle
    case current // Keep current system wallpaper
    case dynamic // HEIC dynamic wallpaper
    case time // Programmatic time wallpaper
}
