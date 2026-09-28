import GoogleMobileAds
import UIKit

/// UIKit assets registered with the SDK for impression and click handling.
///
/// The view draws no background, border, or outer spacing; the app owns card
/// styling. Space is resolved by rearranging assets first, then omitting
/// optional ones, then truncating required text beyond Google's minimum lengths.
final class NativeAdContentView: GoogleMobileAds.NativeAdView {
    /// Google requires media views of at least 120 × 120 points for video.
    static let minimumMediaHeight: CGFloat = 120
    /// Headlines may only be truncated beyond this many characters.
    static let minimumHeadlineCharacters = 25

    /// Text size limits tried in order: the Dynamic Type bound, then smaller
    /// fallbacks for bounded space, down to the system default size.
    static let textSizeLimits: [UIContentSizeCategory] = [
        .accessibilityMedium,
        .extraExtraExtraLarge,
        .extraExtraLarge,
        .extraLarge,
        .large
    ]

    private enum Arrangement {
        case row
        case stacked
        case media
    }

    private struct Fit: Equatable {
        var arrangement: Arrangement
        var mediaHeight: CGFloat
        var showsBody = true
        var showsAdvertiser = true
        var truncatesHeadline = false
    }

    private var displayedAd: GoogleMobileAds.NativeAd?
    let layout: NativeAdLayout
    private(set) var usesMedia: Bool

    private let headlineLabel = makeLabel(style: .headline, color: .label)
    private let bodyLabel = makeLabel(style: .subheadline, color: .secondaryLabel)
    private let advertiserLabel = makeLabel(style: .footnote, color: .secondaryLabel)
    private let iconImageView = UIImageView()
    private let callToActionButton = NativeAdButton(configuration: .filled())
    private let adMediaView = GoogleMobileAds.MediaView()
    private let attributionLabel = makeAttributionLabel()
    private let attributionContainer = UIView()
    private let metaSpacer = UIView()
    private let metaRow = UIStackView()
    private let headlineRow = UIStackView()
    private let textColumn = UIStackView()
    private let rootStack = UIStackView()
    private let mediaHeightConstraint: NSLayoutConstraint
    private var appliedFit: Fit?

    init(layout: NativeAdLayout) {
        self.layout = layout
        usesMedia = layout == .media
        mediaHeightConstraint = adMediaView.heightAnchor.constraint(equalToConstant: Self.minimumMediaHeight)
        super.init(frame: .zero)
        // Bound Dynamic Type so large text reflows instead of producing very tall ads.
        maximumContentSizeCategory = Self.textSizeLimits[0]
        configureSubviews()
        headlineView = headlineLabel
        mediaView = usesMedia ? adMediaView : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Populates the assets before their final layout is registered with the SDK.
    func display(_ nativeAd: GoogleMobileAds.NativeAd) {
        self.nativeAd = nil
        displayedAd = nativeAd
        headlineLabel.text = nativeAd.headline
        bodyLabel.text = nativeAd.body
        advertiserLabel.text = nativeAd.advertiser
        iconImageView.image = nativeAd.icon?.image
        iconImageView.isHidden = nativeAd.icon == nil
        callToActionButton.configuration?.title = nativeAd.callToAction
        callToActionButton.isHidden = nativeAd.callToAction == nil
        callToActionButton.isUserInteractionEnabled = false
        usesMedia = layout == .media || nativeAd.mediaContent.hasVideoContent
        adMediaView.mediaContent = usesMedia ? nativeAd.mediaContent : nil
        mediaView = usesMedia ? adMediaView : nil
        appliedFit = nil
        apply(fits(width: max(bounds.width, NativeAdMetrics.minimumWidth), aspectRatio: nativeAd.mediaContent.aspectRatio)[0])
        isHidden = false
    }

    /// Registers only after the container commits a viable layout. Registering
    /// during loading or measurement gives the SDK zero or speculative bounds.
    func registerAd() {
        guard let displayedAd, nativeAd !== displayedAd else {
            return
        }
        nativeAd = displayedAd
    }

    /// Releases the displayed ad and its media content.
    func clear() {
        displayedAd?.rootViewController = nil
        displayedAd = nil
        nativeAd = nil
        adMediaView.mediaContent = nil
        isHidden = true
    }

    /// Configures the assets for the given space and returns the resulting size,
    /// or `nil` when the required assets cannot be presented within it.
    func fit(width: CGFloat, maximumHeight: CGFloat?) -> CGSize? {
        guard let nativeAd = displayedAd, width.isFinite, width >= NativeAdMetrics.minimumWidth else {
            return nil
        }
        // Each fit starts from the largest permitted text so a larger proposal
        // restores the reader's Dynamic Type preference. Smaller text is only a
        // fallback for bounded space and never goes below the default size.
        let categories = maximumHeight == nil ? [Self.textSizeLimits[0]] : Self.textSizeLimits
        var previousCategory: UIContentSizeCategory?
        for category in categories {
            maximumContentSizeCategory = category
            updateTraitsIfNeeded()
            let effectiveCategory = traitCollection.preferredContentSizeCategory
            guard effectiveCategory != previousCategory else {
                continue
            }
            previousCategory = effectiveCategory
            for fit in fits(width: width, aspectRatio: nativeAd.mediaContent.aspectRatio) {
                apply(fit, width: width)
                var height = measuredHeight(width: width)
                if let maximumHeight, height > maximumHeight,
                   usesMedia, !fit.showsBody, !fit.showsAdvertiser,
                   fit.mediaHeight > effectiveMinimumMediaHeight {
                    // Keep the largest media region that fits after optional
                    // text is omitted, instead of jumping to the minimum.
                    var reducedFit = fit
                    let availableHeight = fit.mediaHeight - (height - maximumHeight)
                    reducedFit.mediaHeight = max(
                        effectiveMinimumMediaHeight,
                        floor(availableHeight / NativeAdMetrics.gridUnit) * NativeAdMetrics.gridUnit
                    )
                    apply(reducedFit, width: width)
                    height = measuredHeight(width: width)
                }
                if let maximumHeight, height > maximumHeight + 0.5 {
                    continue
                }
                return .init(width: width, height: height)
            }
        }
        return nil
    }

    private var effectiveMinimumMediaHeight: CGFloat {
        guard adMediaView.mediaContent?.hasVideoContent == true else {
            return Self.minimumMediaHeight
        }
        // The video creative's longer dimension must also reach 256 pixels.
        return max(Self.minimumMediaHeight, ceil(256 / max(1, traitCollection.displayScale)))
    }

    private func fits(width: CGFloat, aspectRatio: CGFloat) -> [Fit] {
        var fit = Fit(arrangement: arrangement(width: width), mediaHeight: mediaHeight(width: width, aspectRatio: aspectRatio))
        var fits = [fit]
        fit.showsBody = false
        fits.append(fit)
        fit.showsAdvertiser = false
        fits.append(fit)
        if usesMedia, fit.mediaHeight > effectiveMinimumMediaHeight {
            fit.mediaHeight = effectiveMinimumMediaHeight
            fits.append(fit)
        }
        fit.truncatesHeadline = true
        fits.append(fit)
        return fits
    }

    private func arrangement(width: CGFloat) -> Arrangement {
        if usesMedia {
            return .media
        }
        if traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            return .stacked
        }
        let iconWidth = iconImageView.isHidden ? 0 : NativeAdMetrics.iconSize + NativeAdMetrics.spacing
        let buttonWidth = callToActionButton.isHidden
            ? 0
            : callToActionButton.intrinsicContentSize.width + NativeAdMetrics.spacing
        return width - iconWidth - buttonWidth >= NativeAdMetrics.minimumRowTextWidth ? .row : .stacked
    }

    private func mediaHeight(width: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        guard layout == .media else {
            // Compact video keeps the smallest viable media region.
            return effectiveMinimumMediaHeight
        }
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9
        // Videos can use the full height limit; static creatives keep the
        // more compact image region. Both preserve their aspect ratio.
        let maximumHeight = displayedAd?.mediaContent.hasVideoContent == true
            ? NativeAdMetrics.maximumMediaHeight
            : min(
                max(NativeAdMetrics.mediaHeightLimitBaseline, width * 9 / 16),
                NativeAdMetrics.maximumMediaHeight
            )
        return min(max(width / ratio, effectiveMinimumMediaHeight), max(maximumHeight, effectiveMinimumMediaHeight))
    }

    private func apply(_ fit: Fit, width: CGFloat? = nil) {
        if appliedFit != fit {
            appliedFit = fit
            bodyLabel.isHidden = !fit.showsBody || bodyLabel.text?.isEmpty != false
            advertiserLabel.isHidden = !fit.showsAdvertiser || advertiserLabel.text?.isEmpty != false
            mediaHeightConstraint.constant = fit.mediaHeight
            headlineLabel.numberOfLines = 0
            switch fit.arrangement {
            case .row:
                Self.arrange(textColumn, [headlineLabel, bodyLabel])
                Self.arrange(headlineRow, [iconImageView, textColumn, callToActionButton])
                Self.arrange(rootStack, [metaRow, headlineRow])
            case .stacked:
                Self.arrange(textColumn, [headlineLabel])
                Self.arrange(headlineRow, [iconImageView, textColumn])
                Self.arrange(rootStack, [metaRow, headlineRow, bodyLabel, callToActionButton])
            case .media:
                Self.arrange(textColumn, [headlineLabel])
                Self.arrange(headlineRow, [iconImageView, textColumn])
                Self.arrange(rootStack, [metaRow, headlineRow, adMediaView, bodyLabel, callToActionButton])
            }
            headlineRow.alignment = fit.arrangement == .row ? .center : .top
        }
        // Hidden stack-view children can retain frames outside our bounds.
        // Register only presented assets so the SDK never tracks those frames.
        bodyView = bodyLabel.isHidden ? nil : bodyLabel
        advertiserView = advertiserLabel.isHidden ? nil : advertiserLabel
        iconView = iconImageView.isHidden ? nil : iconImageView
        callToActionView = callToActionButton.isHidden ? nil : callToActionButton
        guard let width else {
            return
        }
        // Give wrapped text its final widths so measurement does not depend on a prior layout pass.
        let headlineWidth = headlineWidth(width: width, arrangement: fit.arrangement)
        headlineLabel.preferredMaxLayoutWidth = headlineWidth
        bodyLabel.preferredMaxLayoutWidth = fit.arrangement == .row ? headlineWidth : width
        advertiserLabel.preferredMaxLayoutWidth = max(
            1,
            width - NativeAdMetrics.adChoicesInset - attributionLabel.intrinsicContentSize.width - NativeAdMetrics.spacing
        )
        // Resolve inherited text-size limits before measuring the configured
        // button; otherwise UIKit can grow it after the ad height is committed.
        callToActionButton.updateTraitsIfNeeded()
        callToActionButton.updateConfiguration()
        callToActionButton.layoutIfNeeded()
        if fit.truncatesHeadline {
            headlineLabel.numberOfLines = minimumLineCount(
                for: headlineLabel,
                width: headlineWidth,
                characters: Self.minimumHeadlineCharacters
            )
        }
    }

    private func headlineWidth(width: CGFloat, arrangement: Arrangement) -> CGFloat {
        var headlineWidth = width
        if !iconImageView.isHidden {
            headlineWidth -= NativeAdMetrics.iconSize + NativeAdMetrics.spacing
        }
        if arrangement == .row, !callToActionButton.isHidden {
            headlineWidth -= callToActionButton.intrinsicContentSize.width + NativeAdMetrics.spacing
        }
        return max(1, headlineWidth)
    }

    private func measuredHeight(width: CGFloat) -> CGFloat {
        var height: CGFloat = 0
        // Buttons and stack views settle some sizes during layout, so measure until stable.
        for _ in 0..<3 {
            let measured = ceil(systemLayoutSizeFitting(
                .init(width: width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height)
            if measured == height {
                break
            }
            height = measured
            frame.size = .init(width: width, height: height)
            layoutIfNeeded()
        }
        return height
    }

    /// Returns the line count that keeps at least the given characters visible.
    private func minimumLineCount(for label: UILabel, width: CGFloat, characters: Int) -> Int {
        guard let text = label.text, text.count > characters, let font = label.font else {
            return 0
        }
        let visibleText = String(text.prefix(characters)) + "…"
        let height = (visibleText as NSString).boundingRect(
            with: .init(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        return max(1, Int(ceil(height / font.lineHeight - 0.01)))
    }

    private func configureSubviews() {
        metaRow.axis = .horizontal
        // The padded badge has a different baseline from the advertiser label.
        // Fill alignment keeps both complete frames inside the header.
        metaRow.alignment = .fill
        metaRow.spacing = NativeAdMetrics.spacing
        // Keep the SDK's default top-trailing AdChoices overlay clear of assets.
        metaRow.isLayoutMarginsRelativeArrangement = true
        metaRow.insetsLayoutMarginsFromSafeArea = false
        metaRow.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 0, trailing: NativeAdMetrics.adChoicesInset)
        metaSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        attributionLabel.setContentHuggingPriority(.required, for: .horizontal)
        attributionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        // The header can grow for a multiline advertiser without stretching
        // the attribution badge to the same height.
        attributionLabel.translatesAutoresizingMaskIntoConstraints = false
        attributionContainer.addSubview(attributionLabel)
        NSLayoutConstraint.activate([
            attributionLabel.leadingAnchor.constraint(equalTo: attributionContainer.leadingAnchor),
            attributionLabel.trailingAnchor.constraint(equalTo: attributionContainer.trailingAnchor),
            attributionLabel.topAnchor.constraint(equalTo: attributionContainer.topAnchor),
            attributionLabel.bottomAnchor.constraint(lessThanOrEqualTo: attributionContainer.bottomAnchor)
        ])
        Self.arrange(metaRow, [attributionContainer, advertiserLabel, metaSpacer])

        textColumn.axis = .vertical
        textColumn.spacing = NativeAdMetrics.spacing
        headlineRow.axis = .horizontal
        headlineRow.spacing = NativeAdMetrics.spacing

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = NativeAdMetrics.iconCornerRadius
        iconImageView.layer.masksToBounds = true
        // A hidden icon collapses its width in the row without a conflict.
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: NativeAdMetrics.iconSize).withPriority(.init(999)),
            iconImageView.heightAnchor.constraint(equalToConstant: NativeAdMetrics.iconSize)
        ])

        callToActionButton.configuration?.buttonSize = .small
        callToActionButton.configuration?.titleLineBreakMode = .byWordWrapping
        callToActionButton.setContentHuggingPriority(.required, for: .horizontal)
        callToActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        callToActionButton.setContentCompressionResistancePriority(.required, for: .vertical)

        // Preserve the creative aspect ratio without cropping.
        adMediaView.contentMode = .scaleAspectFit
        mediaHeightConstraint.isActive = true

        rootStack.axis = .vertical
        rootStack.spacing = NativeAdMetrics.spacing
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor).withPriority(.init(999))
        ])
    }

    private static func arrange(_ stack: UIStackView, _ views: [UIView]) {
        guard stack.arrangedSubviews != views else {
            return
        }
        for view in stack.arrangedSubviews where !views.contains(view) {
            stack.removeArrangedSubview(view)
            // A view already moved into another stack keeps its new superview.
            if view.superview === stack {
                view.removeFromSuperview()
            }
        }
        for (index, view) in views.enumerated() {
            stack.insertArrangedSubview(view, at: index)
        }
    }

    private static func makeLabel(style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    private static func makeAttributionLabel() -> UILabel {
        let label = InsetLabel()
        label.text = "Ad"
        // The system caption style in semibold, scaled like the style itself.
        let descriptor = UIFontDescriptor.preferredFontDescriptor(
            withTextStyle: .caption2,
            compatibleWith: .init(preferredContentSizeCategory: .large)
        ).addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .init(descriptor: descriptor, size: 0))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.backgroundColor = .tertiarySystemFill
        label.layer.cornerRadius = NativeAdMetrics.badgeCornerRadius
        label.layer.masksToBounds = true
        label.accessibilityIdentifier = "nativeAd.attribution"
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: NativeAdMetrics.badgeMinimumWidth),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: NativeAdMetrics.badgeMinimumHeight)
        ])
        return label
    }
}

/// A label with horizontal padding. `UILabel` centers the text vertically within
/// the badge's minimum height.
private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(
        top: 0,
        left: NativeAdMetrics.badgeHorizontalPadding,
        bottom: 0,
        right: NativeAdMetrics.badgeHorizontalPadding
    )

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return .init(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

/// Integral intrinsic widths avoid trailing-edge rounding overflow when Auto
/// Layout subtracts the button width from the row's available space.
private final class NativeAdButton: UIButton {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return .init(width: ceil(size.width), height: size.height)
    }
}
