# GoogleMobileAdsWrapper

A SwiftUI adapter for Google Mobile Ads native ads on iOS 17 and later.

## Requirements

- Xcode 26.2 or later.
- Google Mobile Ads SDK 13.9.0 or a compatible 13.x release.

## Usage

Create a `GoogleMobileAdsController` with your native ad unit ID. Call `start()`
once the app has completed any required consent flow, then display
`controller.buildNativeAd("Small")` or `controller.buildNativeAd("Medium")`.

The app owns consent, ATT, ad placement, and subscription policy. Configure
`GADApplicationIdentifier` and the applicable `SKAdNetworkItems` in the app's
Info.plist, following Google's [setup guide](https://developers.google.com/admob/ios/quick-start).
Use Google's [test ad units](https://developers.google.com/admob/ios/test-ads)
during development.

SDK upgrades follow Google's [release notes](https://developers.google.com/admob/ios/rel-notes)
and [migration guide](https://developers.google.com/admob/ios/migration).
