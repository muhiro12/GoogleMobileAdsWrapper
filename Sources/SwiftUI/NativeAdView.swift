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
/// call-to-action button follows the inherited UIKit tint color. The ad takes
/// the proposed width, or 320 points when none is proposed, and its natural
/// height up to any proposed height. Until an ad is loaded, and when the
/// proposed space is too small for the required assets, the view has no height.
public struct NativeAdView: View {
    private let adUnitID: String
    private let layout: NativeAdLayout
    private let onLoadStateChange: @MainActor (NativeAdLoadState) -> Void

    /// Creates a native ad view.
    /// - Parameters:
    ///   - adUnitID: The native ad unit ID.
    ///   - layout: The asset arrangement.
    ///   - onLoadStateChange: Called when the request state changes, for example
    ///     to show an app-owned placeholder while loading or after a failure.
    public init(
        adUnitID: String,
        layout: NativeAdLayout = .compact,
        onLoadStateChange: @escaping @MainActor (NativeAdLoadState) -> Void = { _ in
        }
    ) {
        self.adUnitID = adUnitID
        self.layout = layout
        self.onLoadStateChange = onLoadStateChange
    }

    public var body: some View {
        NativeAdViewRepresentable(
            adUnitID: adUnitID,
            layout: layout,
            onLoadStateChange: onLoadStateChange
        )
    }
}

struct NativeAdViewRepresentable {
    let adUnitID: String
    let layout: NativeAdLayout
    let onLoadStateChange: @MainActor (NativeAdLoadState) -> Void
}

extension NativeAdViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> NativeAdContainerView {
        let view = NativeAdContainerView(adUnitID: adUnitID, layout: layout)
        view.onLoadStateChange = onLoadStateChange
        return view
    }

    func updateUIView(_ uiView: NativeAdContainerView, context: Context) {
        uiView.onLoadStateChange = onLoadStateChange
        uiView.update(adUnitID: adUnitID, layout: layout)
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
