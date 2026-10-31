import SwiftUI

/// The only spacing values the views use. Every gap is one of these, so the
/// rhythm of the popover and the settings window is decided here and not one
/// padding at a time.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    /// Small things inside other things: tabs.
    static let inner: CGFloat = 6
    /// Cards.
    static let card: CGFloat = 8
    /// Lanes, which hold cards and so sit one step further out.
    static let lane: CGFloat = 10
}
