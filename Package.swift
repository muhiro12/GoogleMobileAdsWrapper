// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GoogleMobileAdsWrapper",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "GoogleMobileAdsWrapper",
            targets: [
                "GoogleMobileAdsWrapper"
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads.git", branch: "main")
    ],
    targets: [
        .target(
            name: "GoogleMobileAdsWrapper",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads")
            ]
        )
    ]
)
