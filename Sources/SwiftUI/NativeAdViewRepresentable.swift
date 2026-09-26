//
//  NativeAdViewRepresentable.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import SwiftUI

struct NativeAdViewRepresentable {
    private let adUnitID: String
    private let size: NativeAdSize

    init(adUnitID: String, size: NativeAdSize) {
        self.adUnitID = adUnitID
        self.size = size
    }
}

extension NativeAdViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> NativeAdView {
        NativeAdView(adUnitID: adUnitID, size: size)
    }

    func updateUIView(_ uiView: NativeAdView, context: Context) {
        uiView.update(adUnitID: adUnitID, size: size)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeAdView, context: Context) -> CGSize? {
        uiView.fittingSize(width: min(proposal.width ?? size.width, size.width))
    }

    static func dismantleUIView(_ uiView: NativeAdView, coordinator: ()) {
        uiView.dismantle()
    }
}

#Preview {
    NativeAdViewRepresentable(
        adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
        size: .medium
    )
}
