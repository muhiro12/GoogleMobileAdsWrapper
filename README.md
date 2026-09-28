# GoogleMobileAdsWrapper

SwiftUI native ads and explicit Google UMP consent operations on iOS 17 and later.

## Requirements

- Xcode 26.2 or later; Swift 6 language mode.
- Google Mobile Ads SDK 13.10.0 or a compatible 13.x release.
- Google UMP SDK 3.1.0 or a compatible 3.x release.

## Usage

On the main actor, call `try await GoogleMobileAdsController.start()` once the
app has completed any required consent flow, and load ads only after it returns:

```swift
import GoogleMobileAdsWrapper
import SwiftUI

struct FeedView: View {
    let adUnitID: String
    @State private var canShowAds = false

    var body: some View {
        List {
            if canShowAds {
                SponsoredRow(adUnitID: adUnitID)
            }
        }
        .task {
            do {
                try await GoogleMobileAdsController.start()
                canShowAds = true
            } catch {
                // The task was cancelled; do not start loading ads.
            }
        }
    }
}

struct SponsoredRow: View {
    let adUnitID: String
    @State private var presentationState = NativeAdPresentationState.unavailable

    var body: some View {
        NativeAdView(
            adUnitID: adUnitID,
            layout: .compact,
            onPresentationStateChange: { state in
                presentationState = state
            }
        )
        .padding()
        .background {
            if presentationState == .ready {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background.secondary)
            }
        }
    }
}
```

`NativeAdLayout.compact` shows the icon, headline, body, and call to action in a
short arrangement. `.media` adds a bounded media region.

### Load and presentation states

Two independent states let the app make its own placeholder and layout choices:

- `NativeAdLoadState` describes the request: `.loading` while a request is
  pending or waits for a window, `.loaded` after an ad is received, and
  `.failed` after a failed request. Use it for placeholders and retry decisions.
- `NativeAdPresentationState` describes whether the loaded ad fits the space
  the view was actually laid out with. `.ready` means the registered assets fit
  and are shown. `.insufficientSpace` means an ad is loaded but its required
  assets cannot fit that space, so the view stays empty; offering more space
  shows the same ad without a new request. `.unavailable` covers everything
  else: loading, failure, a view outside a window, or a new ad awaiting layout.

Neither state reports on-screen visibility or an impression; the SDK measures
impressions. Presentation reflects committed layout only, not SwiftUI's
intermediate size measurements, and a large Dynamic Type size alone does not
make an ad unavailable.

Pass either closure, or both, with a trailing load-state closure followed by
`onPresentationStateChange:`. Each closure receives the current state once the
view is created (`.loading` and `.unavailable`) and then each change. Calls
arrive asynchronously on the main actor after the current view update, so the
closures can assign SwiftUI state directly. Rapid changes are coalesced into the
latest state, a load state change is delivered before the presentation state it
causes, and a removed view stops reporting.

Keep the view in the hierarchy while it is `.unavailable`. Removing it, for
example with `if presentationState == .ready`, stops its request permanently;
that view instance never loads or reports again. Style around the view instead,
as in the example, or collapse surrounding content. Avoid changing the space
offered to the ad, such as its padding or frame, in response to its own
presentation state: the new space can change the state again.

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

Concurrent and subsequent `start()` calls share one initialization. Complete
consent and audience settings before the first call. Waiting ends when the SDK
reports initialization completion, including its timeout; this does not promise
that every mediation adapter is ready. A cancelled caller waits for that shared
operation to finish and then throws `CancellationError`, so it must not proceed
to load ads. An already-cancelled caller does not start the SDK.

## Consent operations

Use `GoogleMobileAdsConsentController.shared` on the main actor. It wraps UMP's
SDK operations and reads the current SDK state without storing a separate
consent boolean. It does not start `MobileAds`, load ads, choose a region's
policy, request ATT permission, or share consent identifiers across apps.
Adopting this controller is explicit.

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

Ads load when their view is attached to a window. Change the `reloadID` value
(default `0`) to discard the current result and explicitly request another ad:

```swift
@State private var reloadID = 0

var body: some View {
    VStack {
        NativeAdView(adUnitID: adUnitID, reloadID: reloadID)
        Button("Retry ad") {
            reloadID += 1
        }
    }
}
```

Keep the view mounted to retry through `reloadID`; a view removed after a
failure cannot be retried this way, and a new view starts a new request. Keep
that value stable during ordinary updates; do not generate a new value in
`body`. Replacing an in-flight request disconnects its callbacks; only the
newest request can update the view. The app chooses when to retry, subject to
consent, premium, and lifecycle policy.

Changing the ad unit ID starts
a new request; changing only the layout reuses the loaded ad. Removing the SwiftUI
view disconnects pending callbacks and permanently stops requests for that view
instance, including during later UIKit reattachment. Failed requests report
`.failed`, take no height, and are logged under the `GoogleMobileAdsWrapper`
subsystem without automatic retry loops. On window reattachment, a retained ad
that is at least one hour old is discarded and loaded again. There is no timer
refreshing a continuously displayed ad, no preloading cache, and no automatic
retry after failure. Apps retaining a mounted slot across long inactive periods
can change `reloadID` when their own lifecycle policy calls for a fresh ad.

An internal request object owns the loader and result; the UIKit container owns
presentation, layout, and the presentation state derived from its committed
bounds. The SwiftUI view owns that container through
`UIViewRepresentable`. Apps do not need a separate observable ad model.

## Native ad presentation

The SwiftUI interface wraps code-built UIKit assets registered with Google's
`NativeAdView`; no XIB or storyboard resources are required. Ad loading and
presentation lifecycle are separate from asset layout.

The ad view draws no background, border, or outer padding. Card styling,
spacing, and separators belong to the app; apply them with ordinary SwiftUI
modifiers. Text uses system text styles and semantic colors, and the
call-to-action button uses a standard filled configuration that follows the
inherited tint, including SwiftUI's `.tint(_:)` modifier. Fixed spacing, icon,
badge, and corner dimensions follow an eight-point grid; text, button, and
media sizes stay natural to their content.

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
  videos can grow to that height in the Media layout; static images keep a
  smaller region. Creatives that exceed the limit are letterboxed.
- A compact ad whose response contains video shows a minimum-size media region
  rather than omitting the video. The region also accounts for display scale
  so a portrait video reaches the 256-pixel longer-dimension minimum
  (128 points on a 2× display).
- When the proposed height is smaller than the natural height, the view omits
  optional body and advertiser text first, then reduces media to the largest
  height that fits, down to its minimum. Finally it truncates the headline
  while keeping at least its first 25 characters visible. The call to action
  is never truncated.
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

2.0 removes the 1.x controller-built views and the controller instance. Code
that uses them does not compile after updating; replace the calls as follows:

```swift
// 1.x
let controller = GoogleMobileAdsController(adUnitID: adUnitID)
controller.start()
controller.buildNativeAd(.small)
controller.buildNativeAd("Medium")

// 2.0
try await GoogleMobileAdsController.start()
NativeAdView(adUnitID: adUnitID, layout: .compact)
NativeAdView(adUnitID: adUnitID, layout: .media)
```

- `GoogleMobileAdsController` is a namespace with a static `start()` method.
  Initialization is asynchronous and cancellable for the caller; call it with
  `try await` and load ads after it returns.
  It no longer takes an ad unit ID; pass that to each `NativeAdView`.
- `NativeAdSize` and `buildNativeAd(_:)` are removed. `.small` becomes
  `.compact`, and `.medium` becomes `.media`. Map any stored 1.x string IDs
  ("Small", "Medium") to `NativeAdLayout` in the app.
- `NativeAdView` has no maximum width and no minimum height. The 1.x views were
  at most 320 points wide; add `.frame(maxWidth: 320)` to keep that limit. The
  view takes no space until an ad loads and after a failure, so reserve space
  or show a placeholder based on `NativeAdLoadState` if the placement needs it.
  `NativeAdPresentationState` additionally reports whether a loaded ad fits
  the space the view was given.
- `reloadID` requests a replacement ad explicitly; 1.x had no retry input.
- A compact ad no longer switches to the media layout for accessibility text
  sizes. It keeps a compact arrangement and adds a small media region only for
  video responses.
- The attribution badge reads "Ad" in every locale, and the package no longer
  ships localized string resources.
- The view has no background. Add the card background the app previously
  relied on.
- Consent operations are opt-in through `GoogleMobileAdsConsentController.shared`.

Apps pinned to a 1.x release are unaffected until they update the dependency.

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
