import GoogleMobileAds
import OSLog

/// Owns one ad request and its result independently of UIKit asset layout.
@MainActor
final class NativeAdRequest: NSObject {
    typealias MakeAdLoader = @MainActor (String, UIViewController?) -> GoogleMobileAds.AdLoader

    private static let logger = Logger(subsystem: "GoogleMobileAdsWrapper", category: "NativeAd")
    /// Google asks apps not to display ads retained for longer than an hour.
    private static let expiration = Duration.seconds(3600)
    private let makeAdLoader: MakeAdLoader
    private let now: () -> ContinuousClock.Instant
    private var adUnitID: String
    private var reloadID: Int
    private var loader: GoogleMobileAds.AdLoader?
    private var receivedAt: ContinuousClock.Instant?
    private var isStopped = false
    private(set) var nativeAd: GoogleMobileAds.NativeAd?
    private(set) var state = NativeAdLoadState.loading
    var onChange: (() -> Void)?

    init(
        adUnitID: String,
        reloadID: Int,
        makeAdLoader: @escaping MakeAdLoader,
        // The continuous clock keeps advancing while the device sleeps.
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.adUnitID = adUnitID
        self.reloadID = reloadID
        self.makeAdLoader = makeAdLoader
        self.now = now
    }

    func update(adUnitID: String, reloadID: Int) {
        guard !isStopped, self.adUnitID != adUnitID || self.reloadID != reloadID else {
            return
        }
        self.adUnitID = adUnitID
        self.reloadID = reloadID
        reset()
    }

    /// Recheck retained results when returning to a window, not on a refresh timer.
    func prepareForAttachment() {
        guard !isStopped, let receivedAt, receivedAt.duration(to: now()) >= Self.expiration else {
            return
        }
        reset()
    }

    func loadIfNeeded(from controller: UIViewController?) {
        guard !isStopped, loader == nil, let controller else {
            return
        }
        let loader = makeAdLoader(adUnitID, controller)
        self.loader = loader
        loader.delegate = self
        loader.load(GoogleMobileAds.Request())
    }

    func stop() {
        isStopped = true
        reset()
        onChange = nil
    }

    private func reset() {
        loader?.delegate = nil
        loader = nil
        nativeAd?.rootViewController = nil
        nativeAd = nil
        receivedAt = nil
        state = .loading
        onChange?()
    }
}

extension NativeAdRequest: GoogleMobileAds.NativeAdLoaderDelegate {
    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didReceive nativeAd: GoogleMobileAds.NativeAd) {
        guard !isStopped, adLoader === loader else {
            return
        }
        self.nativeAd = nativeAd
        receivedAt = now()
        state = .loaded
        onChange?()
    }

    func adLoader(_ adLoader: GoogleMobileAds.AdLoader, didFailToReceiveAdWithError error: Error) {
        guard !isStopped, adLoader === loader else {
            return
        }
        nativeAd = nil
        receivedAt = nil
        state = .failed
        onChange?()
        let error = error as NSError
        Self.logger.error("Native ad request failed: \(error.domain, privacy: .public) (\(error.code))")
    }
}
