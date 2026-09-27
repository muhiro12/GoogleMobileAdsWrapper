import GoogleMobileAds
import UIKit

/// UIKit assets registered with the SDK for impression and click handling.
final class NativeAdContentView: GoogleMobileAds.NativeAdView {
    private let size: NativeAdSize
    private let footerStack: UIStackView?
    private var mediaAspectConstraint: NSLayoutConstraint?
    private var callToActionHeightConstraint: NSLayoutConstraint?
    private var callToActionWidthConstraint: NSLayoutConstraint?
    private var accessibleFooterConstraints: [NSLayoutConstraint] = []

    init(size: NativeAdSize) {
        self.size = size
        let headline = Self.label(style: .subheadline)
        let body = Self.label(style: .caption1)
        body.textColor = .secondaryLabel
        let advertiser = Self.label(style: .caption2)
        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 48 * 0.2
        let button = UIButton(configuration: {
            var configuration = UIButton.Configuration.filled()
            configuration.buttonSize = .mini
            return configuration
        }())
        let text = UIStackView(arrangedSubviews: [headline, body])
        text.axis = .vertical
        text.spacing = 4
        let content: UIStackView
        let media: GoogleMobileAds.MediaView?
        if size == .medium {
            let mediaView = GoogleMobileAds.MediaView()
            media = mediaView
            let footer = UIStackView(arrangedSubviews: [icon, advertiser, button])
            footer.spacing = 8
            footer.alignment = .center
            footerStack = footer
            content = UIStackView(arrangedSubviews: [mediaView, text, footer])
            content.axis = .vertical
            mediaView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
            let fallback = mediaView.heightAnchor.constraint(equalToConstant: 160)
            fallback.priority = .init(249)
            fallback.isActive = true
        } else {
            media = nil
            footerStack = nil
            content = UIStackView(arrangedSubviews: [icon, text, button])
            content.alignment = .center
        }
        super.init(frame: .zero)
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 32),
            content.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
        // A hidden arranged asset must be allowed to collapse without conflicts.
        let iconWidth = icon.widthAnchor.constraint(equalToConstant: 48)
        iconWidth.priority = .defaultHigh
        iconWidth.isActive = true
        let iconHeight = icon.heightAnchor.constraint(equalToConstant: 48)
        iconHeight.priority = .defaultHigh
        iconHeight.isActive = true
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        headlineView = headline
        bodyView = body
        iconView = icon
        callToActionView = button
        advertiserView = size == .medium ? advertiser : nil
        mediaView = media
        configureAttribution(in: self)
        // Preserve the creative aspect ratio without cropping.
        mediaView?.contentMode = .scaleAspectFit
        iconView?.layer.masksToBounds = true
        for label in [headlineView, bodyView, advertiserView].compactMap({ $0 as? UILabel }) {
            label.numberOfLines = 0
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        if let button = callToActionView as? UIButton {
            button.titleLabel?.numberOfLines = 0
            button.configuration?.titleLineBreakMode = .byWordWrapping
            let height = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
            height.priority = .defaultHigh
            height.isActive = true
            callToActionHeightConstraint = height
            let width = button.widthAnchor.constraint(equalToConstant: 100)
            width.isActive = true
            callToActionWidthConstraint = width
            if let footer = footerStack {
                accessibleFooterConstraints = [button.widthAnchor.constraint(equalTo: footer.widthAnchor)]
                if let advertiser = advertiserView {
                    accessibleFooterConstraints.append(advertiser.widthAnchor.constraint(equalTo: footer.widthAnchor))
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func fittingSize(width: CGFloat) -> CGSize {
        updateTraitsIfNeeded()
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        if let footer = footerStack {
            footer.axis = accessible ? .vertical : .horizontal
            footer.alignment = accessible ? .leading : .center
            callToActionWidthConstraint?.isActive = !accessible
            for constraint in accessibleFooterConstraints {
                constraint.isActive = accessible
            }
        }
        let iconWidth: CGFloat = iconView?.isHidden == false ? 48 : 0
        let button = callToActionView as? UIButton
        let hasButton = button?.isHidden == false
        let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let title = button?.configuration?.title ?? ""
        let naturalWidth = ceil((title as NSString).size(withAttributes: [.font: font]).width) + 24
        let buttonWidth = hasButton ? (accessible ? width : min(naturalWidth, width * 0.45)) : 0
        callToActionWidthConstraint?.constant = buttonWidth
        if let button {
            button.configuration?.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
            button.configuration?.titleTextAttributesTransformer = .init { attributes in
                var attributes = attributes
                attributes.font = font
                return attributes
            }
            let titleHeight = (title as NSString).boundingRect(
                with: .init(width: max(1, buttonWidth - 24), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font], context: nil
            ).height
            callToActionHeightConstraint?.constant = max(32, ceil(titleHeight) + 16)
        }
        let remainingWidth = width - iconWidth - (iconWidth > 0 ? 8 : 0)
            - buttonWidth - (hasButton ? 8 : 0)
        let textWidth = size == .small ? max(1, remainingWidth) : width
        (headlineView as? UILabel)?.preferredMaxLayoutWidth = textWidth
        (bodyView as? UILabel)?.preferredMaxLayoutWidth = textWidth
        (advertiserView as? UILabel)?.preferredMaxLayoutWidth = accessible ? width : max(1, remainingWidth)
        let height = systemLayoutSizeFitting(
            .init(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        return .init(width: width, height: ceil(max(size.height, height)))
    }

    private func configureAttribution(in view: GoogleMobileAds.NativeAdView) {
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = String(localized: "nativeAd.attribution", bundle: .module)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .label
        label.backgroundColor = .secondarySystemBackground
        label.textAlignment = .center
        label.accessibilityIdentifier = "nativeAd.attribution"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        // Keep the SDK's default top-right AdChoices overlay clear of assets.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 32),
            label.heightAnchor.constraint(equalToConstant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -64)
        ])
    }

    func display(_ nativeAd: GoogleMobileAds.NativeAd) {
        (headlineView as? UILabel)?.text = nativeAd.headline
        (bodyView as? UILabel)?.text = nativeAd.body
        bodyView?.isHidden = nativeAd.body == nil
        (advertiserView as? UILabel)?.text = nativeAd.advertiser
        advertiserView?.isHidden = nativeAd.advertiser == nil
        (iconView as? UIImageView)?.image = nativeAd.icon?.image
        iconView?.isHidden = nativeAd.icon == nil
        if let button = callToActionView as? UIButton {
            button.setTitle(nativeAd.callToAction, for: .normal)
            button.configuration?.title = nativeAd.callToAction
        }
        callToActionView?.isHidden = nativeAd.callToAction == nil
        callToActionView?.isUserInteractionEnabled = false
        mediaView?.mediaContent = nativeAd.mediaContent
        mediaAspectConstraint?.isActive = false
        if let mediaView = mediaView {
            let ratio = nativeAd.mediaContent.aspectRatio
            let safeRatio = ratio.isFinite && ratio > 0 ? ratio : 16 / 9
            let constraint = mediaView.heightAnchor.constraint(
                equalTo: mediaView.widthAnchor,
                multiplier: 1 / safeRatio
            )
            // The minimum video dimension takes priority at narrow widths.
            constraint.priority = .defaultHigh
            constraint.isActive = true
            mediaAspectConstraint = constraint
        }
        self.nativeAd = nativeAd
        isHidden = false
    }

    private static func label(style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }
}
