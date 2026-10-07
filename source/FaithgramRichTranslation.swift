import Foundation
import Postbox
import SwiftSignalKit

private func mapFaithgramRichText(_ text: RichText, transform: (String) -> String) -> RichText {
    func map(_ text: RichText) -> RichText { mapFaithgramRichText(text, transform: transform) }
    switch text {
    case let .plain(value): return .plain(transform(value))
    case let .bold(value): return .bold(map(value))
    case let .italic(value): return .italic(map(value))
    case let .underline(value): return .underline(map(value))
    case let .strikethrough(value): return .strikethrough(map(value))
    case let .url(text, url, id): return .url(text: map(text), url: url, webpageId: id)
    case let .concat(values): return .concat(values.map(map))
    case let .subscript(value): return .subscript(map(value))
    case let .superscript(value): return .superscript(map(value))
    case let .marked(value): return .marked(map(value))
    case let .anchor(value, name): return .anchor(text: map(value), name: name)
    case let .textSpoiler(value): return .textSpoiler(text: map(value))
    default: return text // Preserve code, formulas, usernames, URLs and structured identifiers.
    }
}

private func mapFaithgramBlocks(_ blocks: [InstantPageBlock], transform: (String) -> String) -> [InstantPageBlock] {
    func text(_ value: RichText) -> RichText { mapFaithgramRichText(value, transform: transform) }
    func children(_ value: [InstantPageBlock]) -> [InstantPageBlock] { mapFaithgramBlocks(value, transform: transform) }
    func caption(_ value: InstantPageCaption) -> InstantPageCaption { InstantPageCaption(text: text(value.text), credit: value.credit) }
    return blocks.map { block in
        switch block {
        case let .title(value): return .title(text(value))
        case let .subtitle(value): return .subtitle(text(value))
        case let .header(value): return .header(text(value))
        case let .subheader(value): return .subheader(text(value))
        case let .heading(value, level): return .heading(text: text(value), level: level)
        case let .paragraph(value): return .paragraph(text(value))
        case let .footer(value): return .footer(text(value))
        case let .kicker(value): return .kicker(text(value))
        case let .thinking(value): return .thinking(text(value))
        case let .list(items, ordered):
            return .list(items: items.map { item in
                switch item {
                case let .text(value, number, checked): return .text(text(value), number, checked)
                case let .blocks(value, number, checked): return .blocks(children(value), number, checked)
                case .unknown: return .unknown
                }
            }, ordered: ordered)
        case let .blockQuote(blocks, value, collapsed): return .blockQuote(blocks: children(blocks), caption: text(value), collapsed: collapsed)
        case let .pullQuote(value, label): return .pullQuote(text: text(value), caption: text(label))
        case let .image(id, value, url, page, spoiler): return .image(id: id, caption: caption(value), url: url, webpageId: page, spoiler: spoiler)
        case let .video(id, value, autoplay, loop, spoiler): return .video(id: id, caption: caption(value), autoplay: autoplay, loop: loop, spoiler: spoiler)
        case let .audio(id, value): return .audio(id: id, caption: caption(value))
        case let .cover(value): return .cover(children([value])[0])
        case let .webEmbed(url, html, size, value, stretch, scrolling, cover): return .webEmbed(url: url, html: html, dimensions: size, caption: caption(value), stretchToWidth: stretch, allowScrolling: scrolling, coverId: cover)
        case let .postEmbed(url, page, avatar, author, date, blocks, value): return .postEmbed(url: url, webpageId: page, avatarId: avatar, author: author, date: date, blocks: children(blocks), caption: caption(value))
        case let .collage(items, value): return .collage(items: children(items), caption: caption(value))
        case let .slideshow(items, value): return .slideshow(items: children(items), caption: caption(value))
        case let .table(title, rows, bordered, striped):
            return .table(title: text(title), rows: rows.map { row in
                InstantPageTableRow(cells: row.cells.map { cell in
                    InstantPageTableCell(text: cell.text.map(text), header: cell.header, alignment: cell.alignment, verticalAlignment: cell.verticalAlignment, colspan: cell.colspan, rowspan: cell.rowspan)
                })
            }, bordered: bordered, striped: striped)
        case let .details(title, blocks, expanded): return .details(title: text(title), blocks: children(blocks), expanded: expanded)
        case let .relatedArticles(title, articles): return .relatedArticles(title: text(title), articles: articles)
        case let .map(latitude, longitude, zoom, dimensions, value): return .map(latitude: latitude, longitude: longitude, zoom: zoom, dimensions: dimensions, caption: caption(value))
        default: return block
        }
    }
}

func faithgramTranslateRichMessages(account: Account, messageIds: [EngineMessage.Id], toLang: String) -> Signal<[EngineMessage.Id: InstantPage], TranslationError> {
    guard let service = engineExperimentalInternalTranslationService else { return .fail(.generic) }
    return account.postbox.transaction { transaction -> [(EngineMessage.Id, InstantPage)] in
        return messageIds.compactMap { id in transaction.getMessage(id)?.richText.map { (id, $0.instantPage) } }
    } |> castError(TranslationError.self)
    |> mapToSignal { pages -> Signal<[(EngineMessage.Id, InstantPage)], TranslationError> in
        let signals: [Signal<(EngineMessage.Id, InstantPage), TranslationError>] = pages.map { id, page in
            var texts: [AnyHashable: String] = [:]
            var index = 0
            let _ = mapFaithgramBlocks(page.blocks) { value in
                defer { index += 1 }
                texts[AnyHashable(index)] = value
                return value
            }
            if texts.isEmpty { return .single((id, page)) }
            return service.translate(texts: texts, fromLang: "auto", toLang: toLang)
            |> castError(TranslationError.self)
            |> mapToSignal { result -> Signal<(EngineMessage.Id, InstantPage), TranslationError> in
                guard let result else { return .fail(.generic) }
                var index = 0
                let blocks = mapFaithgramBlocks(page.blocks) { value in
                    defer { index += 1 }
                    return result[AnyHashable(index)] ?? value
                }
                return .single((id, InstantPage(blocks: blocks, media: page.media, isComplete: page.isComplete, rtl: ["ar", "fa", "he", "ur"].contains(toLang), url: page.url, views: page.views)))
            }
        }
        return combineLatest(signals)
    }
    |> mapToSignal { pages -> Signal<[EngineMessage.Id: InstantPage], TranslationError> in
        return account.postbox.transaction { transaction in
            var result: [EngineMessage.Id: InstantPage] = [:]
            for (id, page) in pages {
                result[id] = page
                transaction.updateMessage(id) { message in
                    var attributes = message.attributes.filter { !($0 is TranslationMessageAttribute) }
                    attributes.append(TranslationMessageAttribute(text: "", entities: [], toLang: toLang, instantPage: page))
                    return .update(StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media))
                }
            }
            return result
        } |> castError(TranslationError.self)
    }
}
