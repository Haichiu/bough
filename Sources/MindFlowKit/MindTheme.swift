import Foundation
import CoreGraphics

/// A named visual scheme.
///
/// A theme is deliberately only three things: one accent colour, a set of
/// neutral surfaces, and a node morphology. Everything else in the paint system
/// is derived or shared:
///
/// * the six branch colours are generated from the accent by 60 degree hue
///   rotation in OKLCh, so a new theme inherits the existing gamut mapping and
///   the dark-canvas contrast floor for free;
/// * the marked-node highlight is intentionally NOT part of a theme. It is a
///   status signal, and a status signal that changes meaning with decoration is
///   not a signal. It stays constant across every theme.
///
/// Keeping the surface this narrow is what makes adding a theme safe: a theme
/// cannot introduce a new semantic, only a new appearance.
public enum MindTheme: String, CaseIterable, Codable, Sendable {
    /// The original palette. Reproduces the pre-theme values exactly, so every
    /// existing colour assertion continues to describe a real shipping state.
    case classic
    /// Hierarchy from typography and spacing rather than from fills and borders.
    case minimal
    /// Achromatic. Nothing competes with the text.
    case mono
    /// The classic structure with a cooler, deeper accent.
    case indigo

    public var displayName: String {
        switch self {
        case .classic: return "經典"
        case .minimal: return "極簡"
        case .mono:    return "墨黑"
        case .indigo:  return "靛藍"
        }
    }

    /// Shown in the picker so the choice is describable, not just visible.
    public var summary: String {
        switch self {
        case .classic: return "溫暖紙色底，彩色分支"
        case .minimal: return "無填色無框線，用字級與留白分層"
        case .mono:    return "純灰階，最低視覺干擾"
        case .indigo:  return "深藍強調，結構同經典"
        }
    }
}

/// How nodes are drawn under a given theme.
///
/// The classic look gives every depth a filled or bordered box. Minimalist
/// practice builds hierarchy from type and whitespace *instead of* borders and
/// boxes, so a theme needs to be able to switch those off rather than merely
/// recolour them -- recolouring alone would leave a "minimal" theme still
/// looking like a diagram of boxes.
public struct NodeMorphology: Sendable, Equatable {
    /// Multiplies the classic corner radii. 0 yields square corners.
    public let cornerScale: CGFloat
    /// Depth-1 topics carry a solid branch-coloured fill.
    public let branchFilled: Bool
    /// Deeper topics carry the card surface as a fill.
    public let leafFilled: Bool
    /// Deeper topics carry a hairline border in their branch colour.
    public let leafStroked: Bool

    public init(cornerScale: CGFloat, branchFilled: Bool, leafFilled: Bool, leafStroked: Bool) {
        self.cornerScale = cornerScale
        self.branchFilled = branchFilled
        self.leafFilled = leafFilled
        self.leafStroked = leafStroked
    }
}

/// The raw ingredients of a theme, as sRGB hex so they stay inspectable in diffs.
public struct MindThemeSpec: Sendable {
    public let accent: UInt32
    public let lightCanvas: UInt32
    public let lightCard: UInt32
    public let lightTextPrimary: UInt32
    public let lightTextSecondary: UInt32
    public let lightSecondarySurface: UInt32
    public let lightOnAccent: UInt32
    public let darkCanvas: UInt32
    public let darkCard: UInt32
    public let darkTextPrimary: UInt32
    public let darkTextSecondary: UInt32
    public let darkSecondarySurface: UInt32
    public let darkOnAccent: UInt32
    public let morphology: NodeMorphology
}

extension MindTheme {
    public var spec: MindThemeSpec {
        switch self {
        case .classic:
            // Byte-for-byte the pre-theme palette.
            return MindThemeSpec(
                accent: 0x3368A0,
                lightCanvas: 0xF2EFE7, lightCard: 0xFFFFFF,
                lightTextPrimary: 0x2A2A28, lightTextSecondary: 0x5E6C6F,
                lightSecondarySurface: 0xC8DFDB, lightOnAccent: 0xF2EFE7,
                darkCanvas: 0x101819, darkCard: 0x1B2628,
                darkTextPrimary: 0xE2E9EB, darkTextSecondary: 0x9AA7AA,
                darkSecondarySurface: 0xC8DFDB, darkOnAccent: 0xF2EFE7,
                morphology: NodeMorphology(cornerScale: 1.0, branchFilled: true,
                                           leafFilled: true, leafStroked: true))
        case .minimal:
            // Card equals canvas on purpose: with no fill and no border, a leaf
            // topic is just text on the page, which is the whole point.
            return MindThemeSpec(
                accent: 0x1F1F1F,
                lightCanvas: 0xFFFFFF, lightCard: 0xFFFFFF,
                lightTextPrimary: 0x18181B, lightTextSecondary: 0x71717A,
                lightSecondarySurface: 0xE4E4E7, lightOnAccent: 0xFAFAFA,
                darkCanvas: 0x0C0C0D, darkCard: 0x0C0C0D,
                darkTextPrimary: 0xF4F4F5, darkTextSecondary: 0xA1A1AA,
                darkSecondarySurface: 0x27272A, darkOnAccent: 0x18181B,
                morphology: NodeMorphology(cornerScale: 0.35, branchFilled: false,
                                           leafFilled: false, leafStroked: false))
        case .mono:
            return MindThemeSpec(
                accent: 0x3F3F46,
                lightCanvas: 0xF6F6F6, lightCard: 0xFFFFFF,
                lightTextPrimary: 0x111113, lightTextSecondary: 0x6B6B70,
                lightSecondarySurface: 0xDCDCDE, lightOnAccent: 0xFAFAFA,
                darkCanvas: 0x111112, darkCard: 0x1C1C1F,
                darkTextPrimary: 0xEDEDEF, darkTextSecondary: 0x9B9BA1,
                darkSecondarySurface: 0x2A2A2E, darkOnAccent: 0xFAFAFA,
                morphology: NodeMorphology(cornerScale: 0.0, branchFilled: false,
                                           leafFilled: false, leafStroked: true))
        case .indigo:
            return MindThemeSpec(
                accent: 0x4338CA,
                lightCanvas: 0xF7F7FB, lightCard: 0xFFFFFF,
                lightTextPrimary: 0x1E1B34, lightTextSecondary: 0x5B5878,
                lightSecondarySurface: 0xDDDCF2, lightOnAccent: 0xF5F4FF,
                darkCanvas: 0x0E0D18, darkCard: 0x1A1930,
                darkTextPrimary: 0xE7E6F5, darkTextSecondary: 0x9E9CBE,
                darkSecondarySurface: 0x2A2850, darkOnAccent: 0xF5F4FF,
                morphology: NodeMorphology(cornerScale: 1.0, branchFilled: true,
                                           leafFilled: true, leafStroked: true))
        }
    }
}
