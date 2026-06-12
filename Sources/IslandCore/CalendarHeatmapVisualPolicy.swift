import Foundation

public enum CalendarHeatmapVisualPolicy {
    public static func emptyCellOpacity(mode: DataPanelMode) -> Double {
        mode == .all ? 0.48 : 0.58
    }

    public static func dataCellOpacity(intensity: Double, mode: DataPanelMode) -> Double {
        let clampedIntensity = min(1, max(0, intensity))
        let base = mode == .all ? 0.66 : 0.76
        let span = mode == .all ? 0.22 : 0.22
        return min(1, base + (clampedIntensity * span))
    }

    public static func cellBorderOpacity(isActive: Bool, mode: DataPanelMode) -> Double {
        let base = isActive ? 0.18 : 0.12
        return mode == .all ? base * 0.84 : base
    }
}
