import SwiftUI

/// The app's text styles. On iPhone and Vision Pro they are the system text styles. On Apple TV the system styles
/// are very large (body 29 pt, headline 38 pt, title 57 pt); these are roughly half, closer to the Netflix TV app.
extension Font {
    #if os(tvOS)
    static let xLargeTitle = Font.system(size: 40, weight: .bold)
    static let xTitle = Font.system(size: 32, weight: .semibold)
    static let xTitle2 = Font.system(size: 28, weight: .semibold)
    static let xTitle3 = Font.system(size: 24, weight: .medium)
    static let xHeadline = Font.system(size: 22, weight: .semibold)
    static let xSubheadline = Font.system(size: 18)
    static let xBody = Font.system(size: 20)
    static let xCallout = Font.system(size: 19)
    static let xFootnote = Font.system(size: 16)
    static let xCaption = Font.system(size: 17)
    static let xCaption2 = Font.system(size: 15)
    #else
    static let xLargeTitle = Font.largeTitle
    static let xTitle = Font.title
    static let xTitle2 = Font.title2
    static let xTitle3 = Font.title3
    static let xHeadline = Font.headline
    static let xSubheadline = Font.subheadline
    static let xBody = Font.body
    static let xCallout = Font.callout
    static let xFootnote = Font.footnote
    static let xCaption = Font.caption
    static let xCaption2 = Font.caption2
    #endif
}
