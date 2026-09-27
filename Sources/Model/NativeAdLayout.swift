import Foundation

/// Arrangements for native ad assets.
public enum NativeAdLayout: String, CaseIterable, Sendable {
    /// A short row of icon, headline, and call to action. Video creatives add a
    /// bounded media region instead of being omitted.
    case compact
    /// A bounded media region together with the text assets.
    case media
}

/// The request state of a native ad view, for app placeholder decisions.
public enum NativeAdLoadState: Sendable, Equatable {
    /// A request is pending or waiting for the view to join a window.
    case loading
    /// An ad was received and is displayed when the available space allows.
    case loaded
    /// The request failed. The view stays empty and does not retry.
    case failed
}
