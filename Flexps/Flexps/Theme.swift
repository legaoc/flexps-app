import SwiftUI

// MARK: - Tema claro / oscuro
// La web guarda "theme" en meta (index.html:1972, applyTheme 2000).
// Aquí se guarda en @AppStorage y se aplica con preferredColorScheme.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension View {
    /// Aplica el tema elegido por el usuario (por defecto, el del sistema).
    func appTheme(_ theme: AppTheme) -> some View {
        preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - Formato
enum FlexpsFormat {
    static func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return "\(m):\(String(format: "%02d", s))"
    }

    static func dateAdded(_ addedAtMs: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: addedAtMs / 1000)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}
