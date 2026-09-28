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

/// Whether a loaded native ad can be presented in the view's current layout,
/// for app decisions about space. This is not on-screen visibility or an
/// impression; Google measures impressions.
public enum NativeAdPresentationState: Sendable, Equatable {
    /// No ad is laid out: the request is loading or failed, the view is not in
    /// a window, or the current ad has not completed a layout pass.
    case unavailable
    /// The registered assets fit the view's current bounds and are shown.
    case ready
    /// An ad is loaded, but its required assets cannot fit the space the view
    /// was given, so the view stays empty. More space shows the same ad.
    case insufficientSpace
}
