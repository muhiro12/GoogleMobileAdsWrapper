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

## Loading behavior

Ads load when their view is attached to a window. Changing the ad unit ID starts
a new request; changing only the size reuses the loaded ad. Removing the SwiftUI
view disconnects pending callbacks and permanently stops requests for that view
instance, including during later UIKit reattachment. Failed requests remain
hidden and are logged under the `GoogleMobileAdsWrapper` subsystem without automatic retry loops.

## Tests

Open `Package.swift` in Xcode and run the `GoogleMobileAdsWrapper` scheme on an
iOS Simulator. The tests use stub loaders and fixture assets without requesting
ads. Their image attachments verify layout; live ad delivery still needs a host
app configured with Google's test application ID and native ad unit ID.
