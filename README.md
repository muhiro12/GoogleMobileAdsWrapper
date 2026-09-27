# GoogleMobileAdsWrapper

SwiftUI native ads and explicit Google UMP consent operations on iOS 17 and later.

## Requirements

- Xcode 26.2 or later; Swift 6 language mode.
- Google Mobile Ads SDK 13.10.0 or a compatible 13.x release.
- Google UMP SDK 3.1.0 or a compatible 3.x release.

## Usage

On the main actor, call `GoogleMobileAdsController(adUnitID:).start()` once the
app has completed any required consent flow. Then place a `NativeAdView`:

```swift
import GoogleMobileAdsWrapper
import SwiftUI

struct SponsoredRow: View {
    let adUnitID: String
    @State private var loadState = NativeAdLoadState.loading

    var body: some View {
        if loadState != .failed {
            NativeAdView(adUnitID: adUnitID, layout: .compact) { state in
                loadState = state
            }
            .padding()
            .background(.background.secondary, in: .rect(cornerRadius: 12))
        }
    }
}
```

`NativeAdLayout.compact` shows the icon, headline, body, and call to action in a
short arrangement. `.media` adds a bounded media region. `NativeAdLoadState`
reports `.loading`, `.loaded`, and `.failed` so the app can decide whether to
show a placeholder, collapse the slot, or keep it.

The load-state closure receives `.loading` once the view is created and then
each change. Calls arrive asynchronously on the main actor after the current
view update, so the closure can assign SwiftUI state directly. Rapid changes
are coalesced into the latest state, and a removed view stops reporting.

If the app also imports `GoogleMobileAds`, qualify the view as
`GoogleMobileAdsWrapper.NativeAdView` to distinguish it from the SDK's UIKit
class.

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
a new request; changing only the layout reuses the loaded ad. Removing the SwiftUI
view disconnects pending callbacks and permanently stops requests for that view
instance, including during later UIKit reattachment. Failed requests report
`.failed`, take no height, and are logged under the `GoogleMobileAdsWrapper`
subsystem without automatic retry loops.

## Native ad presentation

The SwiftUI interface wraps code-built UIKit assets registered with Google's
`NativeAdView`; no XIB or storyboard resources are required. Ad loading and
presentation lifecycle are separate from asset layout.

The ad view draws no background, border, or outer padding. Card styling,
spacing, and separators belong to the app; apply them with ordinary SwiftUI
modifiers. Text uses system text styles and semantic colors, and the
call-to-action button uses a standard filled configuration that follows the
inherited tint, including SwiftUI's `.tint(_:)` modifier.

Each layout shows an "Ad" badge next to the advertiser and keeps the top-trailing
corner clear for the SDK's AdChoices overlay. The badge text is the same in
every locale by design. Google's policy asks for attribution that users can
recognize and that is localized appropriately, so confirm this choice for the
markets the app serves. Do not cover the AdChoices corner with app controls or
make the card background a separate click target. Asset clicks and impressions
remain managed by Google.

### Sizing

The view takes the width its parent proposes, or 320 points when no width is
proposed. There is no fixed maximum width; use `.frame(maxWidth:)` to limit it.
The height is the natural height of the assets, up to the proposed height.

- Narrow widths and accessibility text sizes move the compact call to action
  below the headline instead of switching to the media layout.
- Dynamic Type is bounded at `accessibilityMedium` so large text reflows without
  producing very tall ads. The ad is not hidden merely because a large text
  size is selected.
- Media keeps its aspect ratio with aspect-fit scaling inside a region of at
  least 120 × 120 points and at most 320 points tall. Portrait and square
  creatives are letterboxed rather than growing the ad.
- A compact ad whose response contains video shows a minimum-size media region
  rather than omitting the video. The region also accounts for display scale
  so a portrait video reaches the 256-pixel longer-dimension minimum
  (128 points on a 2× display).
- When the proposed height is smaller than the natural height, the view shrinks
  media to its minimum, then omits the body and advertiser, then truncates the
  headline while keeping at least its first 25 characters visible. The call to
  action is never truncated.
- If that still does not fit, the view repeats those steps with smaller text,
  stepping down through `extraExtraExtraLarge`, `extraExtraLarge`, and
  `extraLarge` to the default `large` size, and never smaller. A larger
  proposal restores the reader's text size. For example, a 320 × 96 point
  compact slot or a 320 × 320 point media slot with typical copy stays visible
  at the largest accessibility size.
- When the space is still too small at the default text size, or the width is
  below 160 points, the ad stays empty rather than violating the app's
  constraints or Google's minimum asset sizes. Long copy can need more space
  than a given slot; there is no guarantee for every fixed size.

Fixed heights cannot guarantee that every creative is shown. Verify placements
against Google's
[native ad requirements](https://support.google.com/admob/answer/6329638) with
real creatives, including video, and check the SDK-rendered AdChoices behavior.

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

### 2.0

2.0 replaces the controller-built views with a public SwiftUI view:

```swift
// 1.x
controller.buildNativeAd(.small)
controller.buildNativeAd("Medium")

// 2.0
NativeAdView(adUnitID: adUnitID, layout: .compact)
NativeAdView(adUnitID: adUnitID, layout: .media)
```

- `buildNativeAd(_:)` and `NativeAdSize` remain as deprecated shims. They keep
  the 1.x maximum width of 320 points; `NativeAdSize.layout` maps a legacy size
  to `NativeAdLayout`.
- `NativeAdView` has no maximum width and no minimum height. It takes no space
  until an ad loads and after a failure, so reserve space or show a placeholder
  based on `NativeAdLoadState` if the placement needs it.
- A compact ad no longer switches to the media layout for accessibility text
  sizes. It keeps a compact arrangement and adds a small media region only for
  video responses.
- The attribution badge reads "Ad" in every locale, and the package no longer
  ships localized string resources.
- The view has no background. Add the card background the app previously
  relied on.
- Consent operations and `GoogleMobileAdsController.start()` are unchanged.

### 1.x Swift 6

The package compiles in Swift 6 language mode. `GoogleMobileAdsController`
is main-actor isolated; create and use it from `@MainActor` code.

## Releases

Versions follow Semantic Versioning from 2.0.0. The `Release` workflow creates
a tag and GitHub release for every push to `main`, incrementing the minor
version and resetting the patch version (2.0.0, then 2.1.0). The first automatic
release after the legacy `1.x` tags is 2.0.0.

For a major or patch release, run the workflow manually with an explicit
`MAJOR.MINOR.PATCH` version. It must be greater than every existing release
and at least 2.0.0. `.github/scripts/next-version.sh` selects and validates the
version; a rerun on an already tagged commit publishes nothing.

## Tests

Open `Package.swift` in Xcode and run the `GoogleMobileAdsWrapper` scheme on an
iOS Simulator. The Swift Testing suites use stub loaders and fixture assets
without requesting ads. Their image attachments show layouts across widths,
text sizes, and missing assets; the SDK does not draw fixture media, so media
regions appear empty. Live ad delivery, video, and AdChoices still need a host
app configured with Google's test application ID and native ad unit ID.
