import SwiftUI

extension NOAAAlertLevel {
    /// Categorical color for chips, map pins, and chart markers.
    /// Mirrors NOAA's published bleaching-alert palette.
    var color: Color {
        switch self {
        case .noStress: return Color(red: 0.55, green: 0.75, blue: 0.95)
        case .watch:    return Color(red: 1.00, green: 0.85, blue: 0.20)
        case .warning:  return Color(red: 1.00, green: 0.55, blue: 0.10)
        case .alert1:   return Color(red: 0.90, green: 0.10, blue: 0.10)
        case .alert2:   return Color(red: 0.62, green: 0.05, blue: 0.05)
        case .alert3:   return Color(red: 0.40, green: 0.02, blue: 0.10)
        case .alert4:   return Color(red: 0.25, green: 0.00, blue: 0.08)
        case .alert5:   return Color(red: 0.10, green: 0.00, blue: 0.05)
        }
    }
}
