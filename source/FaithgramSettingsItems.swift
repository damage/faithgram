import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI

private var faithgramIconCache: [String: UIImage] = [:]

/// Renders an SF Symbol as a 29×29 settings icon in the given colour.
func faithgramIcon(_ name: String, color: UIColor) -> UIImage? {
    var red: CGFloat = 0.0, green: CGFloat = 0.0, blue: CGFloat = 0.0, alpha: CGFloat = 0.0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let key = "\(name)|\(Int(red * 255))|\(Int(green * 255))|\(Int(blue * 255))|\(Int(alpha * 255))"
    if let cached = faithgramIconCache[key] { return cached }
    let configuration = UIImage.SymbolConfiguration(pointSize: 22.0, weight: .regular)
    guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
    let canvas = CGSize(width: 29.0, height: 29.0)
    let image = UIGraphicsImageRenderer(size: canvas).image { _ in
        let size = symbol.size.aspectFitted(CGSize(width: 26.0, height: 26.0))
        symbol.withTintColor(color, renderingMode: .alwaysOriginal).draw(in: CGRect(x: floor((canvas.width - size.width) / 2.0), y: floor((canvas.height - size.height) / 2.0), width: size.width, height: size.height))
    }
    faithgramIconCache[key] = image
    return image
}

// MARK: - Slider

final class FaithgramSliderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let value: Int
    let minimumValue: Int
    let maximumValue: Int
    let sectionId: ItemListSectionId
    let updated: (Int) -> Void
    let tag: ItemListItemTag? = nil

    init(theme: PresentationTheme, title: String, value: Int, minimumValue: Int, maximumValue: Int, sectionId: ItemListSectionId, updated: @escaping (Int) -> Void) {
        self.theme = theme
        self.title = title
        self.value = value
        self.minimumValue = minimumValue
        self.maximumValue = maximumValue
        self.sectionId = sectionId
        self.updated = updated
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FaithgramSliderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FaithgramSliderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

final class FaithgramSliderItemNode: ListViewItemNode, ItemListItemNode {
    private let backgroundNode = ASDisplayNode()
    private let topStripeNode = ASDisplayNode()
    private let bottomStripeNode = ASDisplayNode()
    private let maskNode = ASImageNode()
    private let titleNode = ImmediateTextNode()
    private let valueNode = ImmediateTextNode()
    private var slider: UISlider?
    private var item: FaithgramSliderItem?
    private var layoutParams: ListViewItemLayoutParams?

    var tag: ItemListItemTag? { return self.item?.tag }

    init() {
        super.init(layerBacked: false)
        self.backgroundNode.isLayerBacked = true
        self.topStripeNode.isLayerBacked = true
        self.bottomStripeNode.isLayerBacked = true
        self.titleNode.isUserInteractionEnabled = false
        self.valueNode.isUserInteractionEnabled = false
        self.addSubnode(self.titleNode)
        self.addSubnode(self.valueNode)
    }

    override func didLoad() {
        super.didLoad()
        let slider = UISlider()
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(self.sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(self.sliderReleased), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        self.view.addSubview(slider)
        self.slider = slider
        if let item = self.item, let params = self.layoutParams { self.configureSlider(item: item, params: params) }
    }

    private func configureSlider(item: FaithgramSliderItem, params: ListViewItemLayoutParams) {
        guard let slider = self.slider else { return }
        slider.minimumValue = Float(item.minimumValue)
        slider.maximumValue = Float(item.maximumValue)
        if !slider.isTracking { slider.value = Float(item.value) }
        slider.minimumTrackTintColor = item.theme.list.itemAccentColor
        slider.maximumTrackTintColor = item.theme.list.itemSwitchColors.frameColor
        slider.frame = CGRect(x: params.leftInset + 16.0, y: 44.0, width: params.width - params.leftInset - params.rightInset - 32.0, height: 40.0)
    }

    @objc private func sliderChanged() {
        guard let slider = self.slider, let item = self.item else { return }
        self.valueNode.attributedText = NSAttributedString(string: "\(Int(slider.value.rounded()))%", font: Font.regular(17.0), textColor: item.theme.list.itemPrimaryTextColor)
        let size = self.valueNode.updateLayout(CGSize(width: 120.0, height: 30.0))
        if let params = self.layoutParams {
            self.valueNode.frame = CGRect(x: params.width - params.rightInset - 16.0 - size.width, y: 13.0, width: size.width, height: size.height)
        }
    }

    @objc private func sliderReleased() {
        guard let slider = self.slider, let item = self.item else { return }
        let value = Int(slider.value.rounded())
        slider.value = Float(value)
        if value != item.value { item.updated(value) }
    }

    func asyncLayout() -> (_ item: FaithgramSliderItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params, neighbors in
            let contentSize = CGSize(width: params.width, height: 92.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let separatorHeight = UIScreenPixel
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)
            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.item = item
                strongSelf.layoutParams = params
                strongSelf.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
                strongSelf.topStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                strongSelf.bottomStripeNode.backgroundColor = item.theme.list.itemBlocksSeparatorColor
                if strongSelf.backgroundNode.supernode == nil { strongSelf.insertSubnode(strongSelf.backgroundNode, at: 0) }
                if strongSelf.topStripeNode.supernode == nil { strongSelf.insertSubnode(strongSelf.topStripeNode, at: 1) }
                if strongSelf.bottomStripeNode.supernode == nil { strongSelf.insertSubnode(strongSelf.bottomStripeNode, at: 2) }
                if strongSelf.maskNode.supernode == nil { strongSelf.insertSubnode(strongSelf.maskNode, at: 3) }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    strongSelf.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    strongSelf.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                let bottomStripeOffset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = params.leftInset + 16.0
                    bottomStripeOffset = -separatorHeight
                    strongSelf.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    bottomStripeOffset = 0.0
                    hasBottomCorners = true
                    strongSelf.bottomStripeNode.isHidden = hasCorners
                }
                strongSelf.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.theme, top: hasTopCorners, bottom: hasBottomCorners) : nil
                strongSelf.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                strongSelf.maskNode.frame = strongSelf.backgroundNode.frame.insetBy(dx: params.leftInset, dy: 0.0)
                strongSelf.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: layout.size.width, height: separatorHeight))
                strongSelf.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height + bottomStripeOffset), size: CGSize(width: layout.size.width - bottomStripeInset, height: separatorHeight))

                strongSelf.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.regular(17.0), textColor: item.theme.list.itemPrimaryTextColor)
                let titleSize = strongSelf.titleNode.updateLayout(CGSize(width: params.width - 160.0, height: 30.0))
                strongSelf.titleNode.frame = CGRect(x: params.leftInset + 16.0, y: 13.0, width: titleSize.width, height: titleSize.height)
                strongSelf.valueNode.attributedText = NSAttributedString(string: "\(item.value)%", font: Font.regular(17.0), textColor: item.theme.list.itemPrimaryTextColor)
                let valueSize = strongSelf.valueNode.updateLayout(CGSize(width: 120.0, height: 30.0))
                strongSelf.valueNode.frame = CGRect(x: params.width - params.rightInset - 16.0 - valueSize.width, y: 13.0, width: valueSize.width, height: valueSize.height)
                strongSelf.configureSlider(item: item, params: params)
            })
        }
    }
}

// MARK: - Root header (icon, name, version)

final class FaithgramHeaderItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let title: String
    let subtitle: String
    let sectionId: ItemListSectionId
    let tag: ItemListItemTag? = nil
    var isAlwaysPlain: Bool { return true }

    init(theme: PresentationTheme, title: String, subtitle: String, sectionId: ItemListSectionId) {
        self.theme = theme
        self.title = title
        self.subtitle = subtitle
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = FaithgramHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async {
                completion(node, { return (nil, { _ in apply() }) })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? FaithgramHeaderItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params)
                    Queue.mainQueue().async { completion(layout, { _ in apply() }) }
                }
            }
        }
    }
}

final class FaithgramHeaderItemNode: ListViewItemNode, ItemListItemNode {
    private let iconNode = ASImageNode()
    private let titleNode = ImmediateTextNode()
    private let subtitleNode = ImmediateTextNode()
    private var item: FaithgramHeaderItem?

    var tag: ItemListItemTag? { return self.item?.tag }

    init() {
        super.init(layerBacked: false)
        self.iconNode.displaysAsynchronously = false
        self.iconNode.displayWithoutProcessing = true
        self.iconNode.contentMode = .scaleAspectFit
        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.subtitleNode)
    }

    func asyncLayout() -> (_ item: FaithgramHeaderItem, _ params: ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { item, params in
            let layout = ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 222.0), insets: UIEdgeInsets(top: 8.0, left: 0.0, bottom: 8.0, right: 0.0))
            return (layout, { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.item = item
                if strongSelf.iconNode.image == nil {
                    if let path = Bundle.main.path(forResource: "FaithgramIcon", ofType: "png"), let image = UIImage(contentsOfFile: path) {
                        strongSelf.iconNode.image = image
                    } else {
                        strongSelf.iconNode.image = faithgramIcon("paperplane.fill", color: item.theme.list.itemPrimaryTextColor)
                    }
                }
                strongSelf.iconNode.frame = CGRect(x: floor((params.width - 92.0) / 2.0), y: 24.0, width: 92.0, height: 92.0)
                strongSelf.titleNode.attributedText = NSAttributedString(string: item.title, font: Font.semibold(30.0), textColor: item.theme.list.itemPrimaryTextColor)
                let titleSize = strongSelf.titleNode.updateLayout(CGSize(width: params.width - 48.0, height: 44.0))
                strongSelf.titleNode.frame = CGRect(x: floor((params.width - titleSize.width) / 2.0), y: 134.0, width: titleSize.width, height: titleSize.height)
                strongSelf.subtitleNode.attributedText = NSAttributedString(string: item.subtitle, font: Font.regular(15.0), textColor: item.theme.list.itemSecondaryTextColor)
                let subtitleSize = strongSelf.subtitleNode.updateLayout(CGSize(width: params.width - 48.0, height: 30.0))
                strongSelf.subtitleNode.frame = CGRect(x: floor((params.width - subtitleSize.width) / 2.0), y: 178.0, width: subtitleSize.width, height: subtitleSize.height)
            })
        }
    }
}
