import Foundation

func faithgramAppConfiguration(_ original: JSON?) -> JSON? {
    guard let original, case var .dictionary(values) = original else { return original }
    if PatchClientPolicy.isEnabled(.disableMonetizationConfig) {
        values = values.filter { key, _ in
            let key = key.lowercased()
            return !["premium", "stars", "ton_", "stargift", "star_gift", "boost", "giveaway", "paid_reaction"].contains(where: key.contains)
        }
        values["premium_purchase_blocked"] = .bool(true)
        values["premium_promo_order"] = .array([])
        values["stars_purchase_blocked"] = .bool(true)
    }
    if PatchClientPolicy.isEnabled(.hidePremiumUI) { values["premium_purchase_blocked"] = .bool(true) }
    if PatchClientPolicy.isEnabled(.hidePremiumUI) || PatchClientPolicy.isEnabled(.hideGifts) {
        values["premium_gift_attach_menu_icon"] = .bool(false)
        values["premium_gift_text_field_icon"] = .bool(false)
        values["giveaway_gifts_purchase_available"] = .bool(false)
    }
    if PatchClientPolicy.isEnabled(.hideGifts) {
        values["stars_gifts_enabled"] = .bool(false)
        values["stargifts_blocked"] = .bool(true)
    }
    if PatchClientPolicy.isEnabled(.hideCurrencies) { values["stars_purchase_blocked"] = .bool(true) }
    if PatchClientPolicy.isEnabled(.customProfile) {
        if let since = FaithgramVisualPreferences.int("freezeSince") { values["freeze_since_date"] = .number(Double(since)) }
        if let until = FaithgramVisualPreferences.int("freezeUntil") { values["freeze_until_date"] = .number(Double(until)) }
        let appeal = FaithgramVisualPreferences.value("freezeAppealUrl")
        if !appeal.isEmpty { values["freeze_appeal_url"] = .string(appeal) }
    }
    return .dictionary(values)
}
