//
//  NativeAdView.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import SwiftUI

/// A native ad whose assets are registered with the Google Mobile Ads SDK.
///
/// The view draws no background, border, or outer padding, so apply them with
/// ordinary modifiers such as `.padding`, `.background`, and `.frame`. The
/// call-to-action button follows the inherited tint, including `.tint(_:)`. The ad takes
/// the proposed width, or 320 points when none is proposed, and its natural
/// height up to any proposed height. Until an ad is loaded, and when the
/// proposed space is too small for the required assets, the view has no height.
public struct NativeAdView: View {
    private let adUnitID: String
    private let layout: NativeAdLayout
    private let reloadID: Int
    private let makeAdLoader: NativeAdContainerView.MakeAdLoader
    private let onLoadStateChange: @MainActor (NativeAdLoadState) -> Void

    /// Creates a native ad view.
    /// - Parameters:
    ///   - adUnitID: The native ad unit ID.
    ///   - layout: The asset arrangement.
    ///   - reloadID: Change this value to discard the current ad and request another.
    ///     Keep it stable during ordinary view updates. Multiple changes in one
    ///     SwiftUI update produce only the latest request.
    ///   - onLoadStateChange: Called with `.loading` after the view appears and
    ///     then whenever the request state changes, for example to show an
    ///     app-owned placeholder while loading or after a failure. Calls arrive
    ///     after the current view update, so the closure can update SwiftUI
    ///     state; rapid changes are coalesced into the latest state.
    public init(
        adUnitID: String,
        layout: NativeAdLayout = .compact,
        reloadID: Int = 0,
        onLoadStateChange: @escaping @MainActor (NativeAdLoadState) -> Void = { _ in
        }
    ) {
        self.init(
            adUnitID: adUnitID,
            layout: layout,
            reloadID: reloadID,
            makeAdLoader: NativeAdContainerView.makeDefaultAdLoader,
            onLoadStateChange: onLoadStateChange
        )
    }

    init(
        adUnitID: String,
        layout: NativeAdLayout,
        reloadID: Int = 0,
        makeAdLoader: @escaping NativeAdContainerView.MakeAdLoader,
        onLoadStateChange: @escaping @MainActor (NativeAdLoadState) -> Void
    ) {
        self.adUnitID = adUnitID
        self.layout = layout
        self.reloadID = reloadID
        self.makeAdLoader = makeAdLoader
        self.onLoadStateChange = onLoadStateChange
    }

    public var body: some View {
        NativeAdViewRepresentable(
            adUnitID: adUnitID,
            layout: layout,
            reloadID: reloadID,
            makeAdLoader: makeAdLoader,
            onLoadStateChange: onLoadStateChange
        )
    }
}

struct NativeAdViewRepresentable {
    let adUnitID: String
    let layout: NativeAdLayout
    let reloadID: Int
    let makeAdLoader: NativeAdContainerView.MakeAdLoader
    let onLoadStateChange: @MainActor (NativeAdLoadState) -> Void
}

extension NativeAdViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> NativeAdContainerView {
        let view = NativeAdContainerView(adUnitID: adUnitID, layout: layout, reloadID: reloadID, makeAdLoader: makeAdLoader)
        view.onLoadStateChange = onLoadStateChange
        return view
    }

    func updateUIView(_ uiView: NativeAdContainerView, context: Context) {
        uiView.onLoadStateChange = onLoadStateChange
        uiView.update(adUnitID: adUnitID, layout: layout, reloadID: reloadID)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdContainerView, context: Context) -> CGSize? {
        uiView.fittingSize(width: proposal.width, height: proposal.height)
    }

    static func dismantleUIView(_ uiView: NativeAdContainerView, coordinator: ()) {
        uiView.dismantle()
    }
}

#Preview {
    NativeAdView(adUnitID: DemoAdUnitID.nativeAdvanced.rawValue, layout: .media)
        .padding()
}
