import AppKit

struct UnitZone: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    func frame(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + bounds.width * x,
            y: bounds.maxY - bounds.height * (y + height),
            width: bounds.width * width,
            height: bounds.height * height
        )
    }
}

enum ZonePreset: CaseIterable, Hashable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case verticalCenterThird
    case rightThird
    case topThird
    case horizontalCenterThird
    case bottomThird
    case centered
    case fullScreen

    private static let assetNames: [ZonePreset: String] = [
        .leftHalf: "left-half",
        .rightHalf: "right-half",
        .topHalf: "top-half",
        .bottomHalf: "bottom-half",
        .topLeft: "top-left",
        .topRight: "top-right",
        .bottomLeft: "bottom-left",
        .bottomRight: "bottom-right",
        .leftThird: "left-third",
        .verticalCenterThird: "center-third-vertical",
        .rightThird: "right-third",
        .topThird: "top-third",
        .horizontalCenterThird: "center-third-horizontal",
        .bottomThird: "bottom-third",
        .centered: "center",
        .fullScreen: "fullscreen"
    ]

    var unitZone: UnitZone {
        switch self {
        case .leftHalf: return UnitZone(x: 0, y: 0, width: 0.5, height: 1)
        case .rightHalf: return UnitZone(x: 0.5, y: 0, width: 0.5, height: 1)
        case .topHalf: return UnitZone(x: 0, y: 0, width: 1, height: 0.5)
        case .bottomHalf: return UnitZone(x: 0, y: 0.5, width: 1, height: 0.5)
        case .topLeft: return UnitZone(x: 0, y: 0, width: 0.5, height: 0.5)
        case .topRight: return UnitZone(x: 0.5, y: 0, width: 0.5, height: 0.5)
        case .bottomLeft: return UnitZone(x: 0, y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return UnitZone(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        case .leftThird: return UnitZone(x: 0, y: 0, width: 1 / 3, height: 1)
        case .verticalCenterThird:
            return UnitZone(x: 1 / 3, y: 0, width: 1 / 3, height: 1)
        case .rightThird: return UnitZone(x: 2 / 3, y: 0, width: 1 / 3, height: 1)
        case .topThird: return UnitZone(x: 0, y: 0, width: 1, height: 1 / 3)
        case .horizontalCenterThird:
            return UnitZone(x: 0, y: 1 / 3, width: 1, height: 1 / 3)
        case .bottomThird: return UnitZone(x: 0, y: 2 / 3, width: 1, height: 1 / 3)
        case .centered: return UnitZone(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        case .fullScreen: return UnitZone(x: 0, y: 0, width: 1, height: 1)
        }
    }

    var assetName: String {
        Self.assetNames[self] ?? "fullscreen"
    }

    var localizedName: String {
        switch self {
        case .leftHalf: return L10n.string("preset.left_half")
        case .rightHalf: return L10n.string("preset.right_half")
        case .topHalf: return L10n.string("preset.top_half")
        case .bottomHalf: return L10n.string("preset.bottom_half")
        case .topLeft: return L10n.string("preset.top_left")
        case .topRight: return L10n.string("preset.top_right")
        case .bottomLeft: return L10n.string("preset.bottom_left")
        case .bottomRight: return L10n.string("preset.bottom_right")
        case .leftThird: return L10n.string("preset.left_third")
        case .verticalCenterThird:
            return L10n.string("preset.center_third_vertical")
        case .rightThird: return L10n.string("preset.right_third")
        case .topThird: return L10n.string("preset.top_third")
        case .horizontalCenterThird:
            return L10n.string("preset.center_third_horizontal")
        case .bottomThird: return L10n.string("preset.bottom_third")
        case .centered: return L10n.string("preset.center")
        case .fullScreen: return L10n.string("preset.full_screen")
        }
    }
}
