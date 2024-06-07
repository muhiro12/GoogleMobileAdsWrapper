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
    func makeUIView(context: Context) -> some UIView {
        NativeAdView(adUnitID: adUnitID, size: size)
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {}
}

#Preview {
    NativeAdViewRepresentable(
        adUnitID: DemoAdUnitID.nativeAdvanced.rawValue,
        size: .medium
    )
}
