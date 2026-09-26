# GoogleMobileAdsWrapper

SwiftUI native ads and explicit Google UMP consent operations on iOS 17 and later.

## Requirements

- Xcode 26.2 or later; Swift 6 language mode.
- Google Mobile Ads SDK 13.10.0 or a compatible 13.x release.
- Google UMP SDK 3.1.0 or a compatible 3.x release.

## Usage

On the main actor, create a `GoogleMobileAdsController` with your native ad
unit ID. Call `start()`
once the app has completed any required consent flow, then display
`controller.buildNativeAd(.small)` or `controller.buildNativeAd(.medium)`.
`NativeAdSize` is a public `Sendable` enum, so adapter packages can map their own
size types to it without duplicating string identifiers.

The existing `buildNativeAd("Small")` and `buildNativeAd("Medium")` calls remain
supported. Unknown string identifiers continue to produce an empty view.

The app owns consent orchestration, ATT, ad placement, and subscription policy.
Configure
`GADApplicationIdentifier` and the applicable `SKAdNetworkItems` in the app's
Info.plist, following Google's [setup guide](https://developers.google.com/admob/ios/quick-start).
Use Google's [test ad units](https://developers.google.com/admob/ios/test-ads)
during development.

SDK upgrades follow Google's [release notes](https://developers.google.com/admob/ios/rel-notes)
and [migration guide](https://developers.google.com/admob/ios/migration).

## Consent operations

Use `GoogleMobileAdsConsentController.shared` on the main actor. It wraps UMP's
SDK operations and reads the current SDK state without storing a separate
consent boolean. It does not start `MobileAds`, load ads, choose a region's
policy, request ATT permission, or share consent identifiers across apps.
Existing ad APIs keep their behavior; adopting this controller is explicit.

Create the applicable messages in AdMob Privacy & messaging and configure the
host app's `GADApplicationIdentifier`. Follow the
[official UMP integration guide](https://developers.google.com/admob/ios/privacy).
The package cannot configure account messages on the app's behalf.

```swift
import GoogleMobileAdsWrapper
import UIKit

@MainActor
func prepareConsent(
    from presenter: UIViewController?,
    request: GoogleMobileAdsConsentRequest
) async throws -> GoogleMobileAdsConsentState {
    let consent = GoogleMobileAdsConsentController.shared
    try await consent.requestConsentInfoUpdate(request)
    return try await consent.loadAndPresentIfRequired(from: presenter)
}
```

The app or its runtime should:

1. Request an information update each app session. Supply the under-age tag
   according to the app's audience policy; the default is `false`.
2. After a successful update, load and present any required form. UMP decides
   whether presentation is needed. Both methods return fresh SDK state.
3. Read `state.canRequestAds` before starting advertising work, together with
   the app's premium and lifecycle checks. Do not infer eligibility from
   `status == .obtained`: that status does not distinguish personalized ads.
4. On an SDK error, inspect the current `consent.state` as well as the error.
   Previous-session consent may still permit ads. Handle cancellation and
   operation conflicts separately; neither is a signal to start ads.
5. When `state.privacyOptionsRequirement == .required`, expose a privacy-options
   control. In response to a user action, call
   `try await consent.presentPrivacyOptions(from: presenter)` and re-evaluate
   ad eligibility after completion or error.

`state` is a live getter, not an observable cache. The runtime owns publishing
state to UI and responding to changes. Pass a view controller from the active
scene when the app has multiple windows; `nil` delegates presentation-host
selection to UMP. No form is presented simply by creating the controller.

Reuse the shared controller and route all UMP operations through it. Overlapping
updates or form presentations throw `OperationError.operationInProgress`; they
are not queued or automatically retried. Do not bypass the adapter with parallel
UMP calls. Repeated sequential update requests are allowed so the app can retry.

Cancellation before a call prevents SDK work. UMP cannot cancel an in-flight
request or dismiss an already-presented form through these operations. A
cancelled task therefore waits for SDK completion, and the controller retains
its operation gate during that time. After successful SDK completion, the task
throws `CancellationError`; SDK failures remain their original errors. The SDK
state remains readable, and the runtime must prevent cancelled work from
starting ads.

### Consent testing

For a test request only, use explicit debug settings:

```swift
let request = GoogleMobileAdsConsentRequest(
    debugSettings: .init(geography: .eea, testDeviceIdentifiers: [])
)
```

UMP treats simulators as test devices. Register physical test-device identifiers
when needed. Other supported overrides are `.regulatedUSState` and `.other`;
`.disabled` disables geography overriding. Omit debug settings in production.
The adapter does not reset SDK consent or change account settings automatically.

Package tests inject an internal SDK client, verifying state, forwarding,
errors, concurrency, and cancellation without displaying live consent forms or
requesting ads. Real message content, offline behavior, and regional/account
configuration still require a configured host app and UMP testing. These tests
are not a claim of regulatory compliance or app release readiness.

## Loading behavior

Ads load when their view is attached to a window. Changing the ad unit ID starts
a new request; changing only the size reuses the loaded ad. Removing the SwiftUI
view disconnects pending callbacks and permanently stops requests for that view
instance, including during later UIKit reattachment. Failed requests remain
hidden and are logged under the `GoogleMobileAdsWrapper` subsystem without
automatic retry loops.

## Native ad presentation

Both layouts include a localized ad attribution badge (English and Japanese)
and keep the top-right corner clear for the SDK's AdChoices overlay. Do not
cover that area with app controls or make the card background a separate
click target. Asset clicks and impressions remain managed by Google.

A compact ad automatically uses the media layout when the response includes
video or an accessibility text size is active. Media preserves its aspect ratio
and at least a 120-point dimension;
portrait creatives and larger text can increase the card height. Let SwiftUI
size the view naturally rather than forcing the old 64/288-point heights.
Headlines and body copy wrap, and system text styles support Dynamic Type.
Verify placements against Google's
[native ad requirements](https://support.google.com/admob/answer/6329638),
including actual creative content and SDK-rendered AdChoices behavior.

## Privacy and app responsibilities

Google Mobile Ads and UMP include their own `PrivacyInfo.xcprivacy` files.
The wrapper adds no independent data collection, tracking domains, persistent
storage, or required-reason API use. It therefore does not duplicate those
SDK declarations in a wrapper manifest. Reassess this when adding storage,
analytics, or additional SDKs.

Inspect the shipping app's archive privacy report, including any mediation
SDKs, and reconcile it with App Store Connect disclosures and the app's
privacy policy. SDK manifests do not replace that work. See Google's
[data disclosure guide](https://developers.google.com/admob/ios/privacy/data-disclosure)
and Apple's
[privacy manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

Before requesting ads, the host must configure applicable child-directed,
under-age, content-rating, consent, and ATT settings. The UMP under-age flag
is separate from the advertising SDK's request configuration; this wrapper
does not infer one from the other. When using mediation, follow Google's
initialization guidance and wait for adapter initialization before loading.
Account message setup, audience choices, app-ads.txt, regional applicability,
and Store declarations remain host-app or publisher responsibilities.

## Migration

The package compiles in Swift 6 language mode. `GoogleMobileAdsController`
is now explicitly main-actor isolated; create and use it from `@MainActor`
code. Existing typed and string layout calls remain available. The actor
requirement and variable card height need review at adopter call sites before
upgrading.

## Tests

Open `Package.swift` in Xcode and run the `GoogleMobileAdsWrapper` scheme on an
iOS Simulator. The Swift Testing suites use stub loaders and fixture assets
without requesting
ads. Their image attachments verify layout; live ad delivery still needs a host
app configured with Google's test application ID and native ad unit ID.
