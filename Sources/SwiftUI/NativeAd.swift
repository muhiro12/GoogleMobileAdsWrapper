//
//  NativeAdMob.swift
//
//
//  Created by Hiromu Nakano on 2024/06/07.
//

import SwiftUI

struct NativeAd: View {
    @Environment(\.adUnitID) private var adUnitID

    private let size: NativeAdSize

    init(size: NativeAdSize) {
        self.size = size
    }

    var body: some View {
        NativeAdViewRepresentable(adUnitID: adUnitID, size: size)
            .frame(maxWidth: size.width,
                   minHeight: size.height)
    }
}

#Preview {
    NativeAd(size: .small)
}
