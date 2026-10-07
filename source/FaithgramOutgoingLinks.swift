import Foundation
import Postbox

func faithgramCleanOutgoingLinks(text: String, attributes: [MessageAttribute]) -> (String, [MessageAttribute]) {
    guard PatchClientPolicy.isEnabled(.cleanLinks) else { return (text, attributes) }
    let entities = attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { $0.entities }
    let excluded = entities.compactMap { entity -> NSRange? in
        switch entity.type {
        case .Code, .Pre: return NSRange(location: entity.range.lowerBound, length: entity.range.count)
        default: return nil
        }
    }
    let edits = FaithgramLinkCleaner.edits(in: text, excluding: excluded)
    let result = NSMutableString(string: text)
    for edit in edits.reversed() { result.replaceCharacters(in: edit.range, with: edit.replacement) }
    let updated = attributes.map { attribute -> MessageAttribute in
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            return TextEntitiesMessageAttribute(entities: attribute.entities.compactMap { entity in
                guard entity.range.lowerBound >= 0, entity.range.upperBound <= (text as NSString).length else { return nil }
                let range = FaithgramLinkCleaner.remap(NSRange(location: entity.range.lowerBound, length: entity.range.count), through: edits)
                guard range.length > 0 else { return nil }
                let type: MessageTextEntityType
                if case let .TextUrl(url) = entity.type { type = .TextUrl(url: FaithgramLinkCleaner.cleanURL(url)) }
                else { type = entity.type }
                return MessageTextEntity(range: range.location ..< NSMaxRange(range), type: type)
            })
        }
        if let attribute = attribute as? RichTextMessageAttribute {
            return RichTextMessageAttribute(instantPage: faithgramCleanRichPage(attribute.instantPage), fullInstantPage: attribute.fullInstantPage.map(faithgramCleanRichPage))
        }
        return attribute
    }
    return (result as String, updated)
}
