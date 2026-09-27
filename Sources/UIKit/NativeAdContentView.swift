import GoogleMobileAds
import UIKit

/// UIKit assets registered with the SDK for impression and click handling.
///
/// The view draws no background, border, or outer spacing; the app owns card
/// styling. Space is resolved by rearranging assets first, then omitting
/// optional ones, then truncating required text beyond Google's minimum lengths.
final class NativeAdContentView: GoogleMobileAds.NativeAdView {
    /// Narrower placements cannot present the required assets and stay empty.
    static let minimumWidth: CGFloat = 160
    /// Google requires media views of at least 120 × 120 points for video.
    static let minimumMediaHeight: CGFloat = 120
    /// Headlines may only be truncated beyond this many characters.
    static let minimumHeadlineCharacters = 25

    private static let adChoicesInset: CGFloat = 28
    private static let iconSize: CGFloat = 40
    private static let spacing: CGFloat = 8
    private static let minimumRowTextWidth: CGFloat = 140

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

    let layout: NativeAdLayout
    private(set) var usesMedia: Bool

    private let headlineLabel = makeLabel(style: .headline, color: .label)
    private let bodyLabel = makeLabel(style: .subheadline, color: .secondaryLabel)
    private let advertiserLabel = makeLabel(style: .footnote, color: .secondaryLabel)
    private let iconImageView = UIImageView()
    private let callToActionButton = UIButton(configuration: .filled())
    private let adMediaView = GoogleMobileAds.MediaView()
    private let attributionLabel = makeAttributionLabel()
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
        maximumContentSizeCategory = .accessibilityMedium
        configureSubviews()
        headlineView = headlineLabel
        bodyView = bodyLabel
        advertiserView = advertiserLabel
        iconView = iconImageView
        callToActionView = callToActionButton
        mediaView = usesMedia ? adMediaView : nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Displays the ad, assigning it after its assets are registered.
    func display(_ nativeAd: GoogleMobileAds.NativeAd) {
        self.nativeAd = nil
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
        apply(fits(width: max(bounds.width, Self.minimumWidth), aspectRatio: nativeAd.mediaContent.aspectRatio)[0])
        self.nativeAd = nativeAd
        isHidden = false
    }

    /// Releases the displayed ad and its media content.
    func clear() {
        nativeAd?.rootViewController = nil
        nativeAd = nil
        adMediaView.mediaContent = nil
        isHidden = true
    }

    /// Configures the assets for the given space and returns the resulting size,
    /// or `nil` when the required assets cannot be presented within it.
    func fit(width: CGFloat, maximumHeight: CGFloat?) -> CGSize? {
        guard let nativeAd, width.isFinite, width >= Self.minimumWidth else {
            return nil
        }
        updateTraitsIfNeeded()
        for fit in fits(width: width, aspectRatio: nativeAd.mediaContent.aspectRatio) {
            apply(fit, width: width)
            let height = measuredHeight(width: width)
            if let maximumHeight, height > maximumHeight + 0.5 {
                continue
            }
            return .init(width: width, height: height)
        }
        return nil
    }

    private func fits(width: CGFloat, aspectRatio: CGFloat) -> [Fit] {
        var fit = Fit(arrangement: arrangement(width: width), mediaHeight: mediaHeight(width: width, aspectRatio: aspectRatio))
        var fits = [fit]
        if usesMedia, fit.mediaHeight > Self.minimumMediaHeight {
            fit.mediaHeight = Self.minimumMediaHeight
            fits.append(fit)
        }
        fit.showsBody = false
        fits.append(fit)
        fit.showsAdvertiser = false
        fits.append(fit)
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
        let iconWidth = iconImageView.isHidden ? 0 : Self.iconSize + Self.spacing
        let buttonWidth = callToActionButton.isHidden
            ? 0
            : callToActionButton.intrinsicContentSize.width + Self.spacing
        return width - iconWidth - buttonWidth >= Self.minimumRowTextWidth ? .row : .stacked
    }

    private func mediaHeight(width: CGFloat, aspectRatio: CGFloat) -> CGFloat {
        guard layout == .media else {
            // Compact video keeps the smallest viable media region.
            return Self.minimumMediaHeight
        }
        let ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 16 / 9
        // Tall creatives are letterboxed with aspect fit rather than growing the ad.
        let maximumHeight = min(max(180, width * 9 / 16), 320)
        return min(max(width / ratio, Self.minimumMediaHeight), maximumHeight)
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
        guard let width else {
            return
        }
        // Give wrapped text its final widths so measurement does not depend on a prior layout pass.
        let headlineWidth = headlineWidth(width: width, arrangement: fit.arrangement)
        headlineLabel.preferredMaxLayoutWidth = headlineWidth
        bodyLabel.preferredMaxLayoutWidth = fit.arrangement == .row ? headlineWidth : width
        advertiserLabel.preferredMaxLayoutWidth = max(
            1,
            width - Self.adChoicesInset - attributionLabel.intrinsicContentSize.width - Self.spacing
        )
        callToActionButton.updateConfiguration()
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
            headlineWidth -= Self.iconSize + Self.spacing
        }
        if arrangement == .row, !callToActionButton.isHidden {
            headlineWidth -= callToActionButton.intrinsicContentSize.width + Self.spacing
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
        metaRow.alignment = .firstBaseline
        metaRow.spacing = Self.spacing
        // Keep the SDK's default top-trailing AdChoices overlay clear of assets.
        metaRow.isLayoutMarginsRelativeArrangement = true
        metaRow.insetsLayoutMarginsFromSafeArea = false
        metaRow.directionalLayoutMargins = .init(top: 0, leading: 0, bottom: 0, trailing: Self.adChoicesInset)
        metaSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        metaSpacer.heightAnchor.constraint(equalToConstant: 0).isActive = true
        attributionLabel.setContentHuggingPriority(.required, for: .horizontal)
        attributionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        Self.arrange(metaRow, [attributionLabel, advertiserLabel, metaSpacer])

        textColumn.axis = .vertical
        textColumn.spacing = 2
        headlineRow.axis = .horizontal
        headlineRow.spacing = Self.spacing

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.layer.cornerRadius = Self.iconSize * 0.2
        iconImageView.layer.masksToBounds = true
        // A hidden icon collapses its width in the row without a conflict.
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: Self.iconSize).withPriority(.init(999)),
            iconImageView.heightAnchor.constraint(equalToConstant: Self.iconSize)
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
        rootStack.spacing = Self.spacing
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
        label.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.textAlignment = .center
        label.backgroundColor = .tertiarySystemFill
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.accessibilityIdentifier = "nativeAd.attribution"
        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 16)
        ])
        return label
    }
}

/// A label with padding so the attribution badge stays at least 15 points in each dimension.
private final class InsetLabel: UILabel {
    private let insets = UIEdgeInsets(top: 1, left: 4, bottom: 1, right: 4)

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
