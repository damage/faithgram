import Foundation
import UIKit
import AsyncDisplayKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

final class FaithgramBadgeAdminController: ViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let context: AccountContext
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let search = UISearchBar()
    private var records: [FaithgramPreferences.BadgeGrant] = []
    private var names: [Int64: String] = [:]
    private var observer: NSObjectProtocol?
    private let lookupDisposable = MetaDisposable()
    private let actionDisposable = MetaDisposable()
    private var ownerId: Int64 { context.account.peerId.id._internalGetInt64Value() }
    private var authorized: Bool { FaithgramPreferences.canManageBadges(accountPeerId: ownerId) }

    init(context: AccountContext) {
        self.context = context
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }, style: .glass))
        self.title = "badges"
        self.statusBar.statusBarStyle = .White
        if self.authorized {
            self.navigationItem.rightBarButtonItems = [UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addPressed)), UIBarButtonItem(title: "sync", style: .plain, target: self, action: #selector(syncPressed))]
        }
        self.observer = NotificationCenter.default.addObserver(forName: FaithgramPreferences.changed, object: nil, queue: .main) { [weak self] _ in self?.reloadRecords() }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        lookupDisposable.dispose()
        actionDisposable.dispose()
    }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .black
        self.displayNodeDidLoad()
        self.table.backgroundColor = .black
        self.table.dataSource = self
        self.table.delegate = self
        self.table.rowHeight = UITableView.automaticDimension
        self.table.estimatedRowHeight = 76
        self.table.contentInsetAdjustmentBehavior = .never
        self.table.keyboardDismissMode = .onDrag
        self.search.placeholder = "peer id, name or badge"
        self.search.searchBarStyle = .minimal
        self.search.barStyle = .black
        self.search.showsScopeBar = true
        self.search.scopeButtonTitles = ["active", "all", "revoked", "expired"]
        self.search.delegate = self
        self.search.autocapitalizationType = .none
        self.search.autocorrectionType = .no
        self.view.addSubview(self.table)
        self.reloadRecords()
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: self.table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top))
        self.table.contentInset.bottom = max(layout.intrinsicInsets.bottom, layout.inputHeight ?? 0) + 16
        self.search.frame = CGRect(x: 0, y: 0, width: layout.size.width, height: 100)
        self.table.tableHeaderView = self.search
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.authorized, FaithgramBadgeService.shared.isConfigured { self.pullAdminRecords() }
    }
    private func reloadRecords() {
        guard self.authorized else { self.records = []; self.table.reloadData(); return }
        let all = FaithgramBadgeService.shared.recordsForAdmin(accountPeerId: ownerId)
        let query = (self.search.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.records = all.filter { record in
            let stateMatches: Bool
            switch self.search.selectedScopeButtonIndex {
            case 1: stateMatches = true
            case 2: stateMatches = record.revokedAt != nil
            case 3: stateMatches = record.revokedAt == nil && !record.isActive()
            default: stateMatches = record.isActive()
            }
            let text = "\(record.peerId) \(self.names[record.peerId] ?? "") \(record.role.title) \(record.note)".lowercased()
            return stateMatches && (query.isEmpty || text.contains(query))
        }.sorted { ($0.issuedAt ?? .distantPast) > ($1.issuedAt ?? .distantPast) }
        self.table.reloadData()
        let ids = Set(all.map { $0.peerId }).filter { self.names[$0] == nil }
        guard !ids.isEmpty else { return }
        self.lookupDisposable.set((self.context.account.postbox.transaction { transaction -> [Int64: String] in
            var result: [Int64: String] = [:]
            for id in ids {
                if let peer = transaction.getPeer(PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))) {
                    result[id] = EnginePeer(peer).debugDisplayTitle
                }
            }
            return result
        } |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, !values.isEmpty else { return }
            self.names.merge(values, uniquingKeysWith: { _, new in new })
            self.reloadRecords()
        }))
    }
    func numberOfSections(in tableView: UITableView) -> Int { return 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { authorized ? max(records.count, 1) : 0 }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { "\(records.count) badges · " + (FaithgramBadgeService.shared.isConfigured ? FaithgramBadgeService.shared.syncStatus : "local registry") }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return FaithgramBadgeService.shared.isConfigured ? "Only peer id 1000 can manage badges. Updates are synchronized through the signed registry. Private notes stay in the admin API." : "Only peer id 1000 can manage badges. The shared service is not configured. Previous local grants have no recorded issue date."
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = UIColor(white: 0.105, alpha: 1)
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = .gray
        cell.detailTextLabel?.numberOfLines = 0
        cell.tintColor = .white
        guard !records.isEmpty else { cell.textLabel?.text = "no badges found"; cell.selectionStyle = .none; return cell }
        let record = records[indexPath.row]
        cell.textLabel?.text = names[record.peerId] ?? String(record.peerId)
        cell.detailTextLabel?.text = record.role.title + " · " + self.dateText(record.issuedAt) + "\n" + String(record.peerId) + " · " + self.stateText(record)
        cell.imageView?.image = UIImage(systemName: record.role.symbol)
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard authorized, !records.isEmpty else { return }
        self.showRecord(records[indexPath.row])
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { self.reloadRecords() }
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) { self.reloadRecords() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    @objc private func addPressed() { guard authorized else { return }; self.showGrantForm(existing: nil) }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "issue date unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    private func stateText(_ record: FaithgramPreferences.BadgeGrant) -> String {
        if record.revokedAt != nil { return "revoked" }
        return record.isActive() ? "active" : "expired"
    }
    private func showRecord(_ record: FaithgramPreferences.BadgeGrant) {
        guard authorized else { return }
        var message = "peer id: \(record.peerId)\nissued: \(dateText(record.issuedAt))\nissued by: \(record.issuedBy)\nexpires: \(record.expiresAt.map { dateText($0) } ?? "never")"
        if let date = record.revokedAt { message += "\nrevoked: " + dateText(date) }
        if !record.note.isEmpty { message += "\n\n" + record.note }
        let alert = UIAlertController(title: record.role.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "open profile", style: .default, handler: { [weak self] _ in self?.openProfile(record.peerId) }))
        alert.addAction(UIAlertAction(title: "copy peer id", style: .default, handler: { _ in UIPasteboard.general.string = String(record.peerId) }))
        alert.addAction(UIAlertAction(title: "issue or update badge", style: .default, handler: { [weak self] _ in self?.showGrantForm(existing: record) }))
        if record.revokedAt == nil {
            alert.addAction(UIAlertAction(title: "revoke badge", style: .destructive, handler: { [weak self] _ in
                guard let self, self.authorized else { return }
                if FaithgramBadgeService.shared.isConfigured {
                    FaithgramBadgeService.shared.revoke(id: record.id, accountPeerId: self.ownerId) { [weak self] success in
                        self?.reloadRecords()
                        if !success { self?.showError("The badge was not revoked. Check the service and administrator key.") }
                    }
                } else { let _ = FaithgramPreferences.revokeBadge(id: record.id, accountPeerId: self.ownerId) }
            }))
        }
        alert.addAction(UIAlertAction(title: "close", style: .cancel))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    private func openProfile(_ peerId: Int64) {
        guard authorized else { return }
        let id = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(peerId))
        actionDisposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: id)) |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else { return }
            guard let peer, let controller = self.context.sharedContext.makePeerInfoController(context: self.context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) else {
                self.showError("This profile is not available locally yet. Open a chat with this user, or add a badge using their @username.")
                return
            }
            (self.navigationController as? NavigationController)?.pushViewController(controller)
        }))
    }
    private func showGrantForm(existing: FaithgramPreferences.BadgeGrant?) {
        guard authorized else { return }
        let alert = UIAlertController(title: existing == nil ? "assign badge" : "update badge", message: "User peer id or @username. Leave validity empty for a permanent badge. Notes are visible only in this admin screen.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "peer id or @username"; field.text = existing.map { String($0.peerId) }; field.autocapitalizationType = .none; field.autocorrectionType = .no }
        alert.addTextField { field in field.placeholder = "admin note"; field.text = existing?.note }
        alert.addTextField { field in
            field.placeholder = "validity in days (optional)"
            field.keyboardType = .numberPad
            if let expiry = existing?.expiresAt { field.text = String(max(1, Int(ceil(expiry.timeIntervalSinceNow / 86400)))) }
        }
        for role in FaithgramPreferences.Badge.allCases {
            alert.addAction(UIAlertAction(title: role.title, style: .default, handler: { [weak self] _ in
                guard let self, self.authorized else { return }
                let input = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let note = alert.textFields?[1].text ?? ""
                let validity = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard note.utf8.count <= 1024 else { self.showError("The note is too long."); return }
                var expiry: Date?
                if !validity.isEmpty {
                    guard let days = Int(validity), (1...36500).contains(days) else { self.showError("Enter a validity from 1 to 36500 days, or leave it empty."); return }
                    expiry = Date().addingTimeInterval(Double(days) * 86400)
                }
                if let id = Int64(input), id > 0 { self.issue(role, peerId: id, note: note, expiry: expiry); return }
                let name = input.hasPrefix("@") ? String(input.dropFirst()) : input
                guard !name.isEmpty else { self.showError("Enter a positive peer id or @username."); return }
                self.actionDisposable.set((self.context.engine.peers.resolvePeerByName(name: name, referrer: nil) |> deliverOnMainQueue).start(next: { [weak self] result in
                    guard let self else { return }
                    if case let .result(peer) = result {
                        guard case let .user(user)? = peer else { self.showError("A user with this username was not found."); return }
                        self.issue(role, peerId: user.id.id._internalGetInt64Value(), note: note, expiry: expiry)
                    }
                }))
            }))
        }
        alert.addAction(UIAlertAction(title: "cancel", style: .cancel))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    private func issue(_ role: FaithgramPreferences.Badge, peerId: Int64, note: String, expiry: Date?) {
        if FaithgramBadgeService.shared.isConfigured {
            FaithgramBadgeService.shared.grant(role, peerId: peerId, accountPeerId: ownerId, note: note, expiresAt: expiry) { [weak self] success in
                self?.reloadRecords()
                if !success { self?.showError("The badge was not saved. Check the service and administrator key.") }
            }
        } else if !FaithgramPreferences.grantBadge(role, peerId: peerId, accountPeerId: ownerId, note: note, expiresAt: expiry) { showError("The badge could not be saved.") }
    }
    private func pullAdminRecords() {
        FaithgramBadgeService.shared.fetchAdminRecords(accountPeerId: ownerId) { [weak self] success in
            self?.reloadRecords()
            if !success { self?.showError("Admin access failed. Enter the administrator key using sync, and check the server connection.") }
        }
    }
    @objc private func syncPressed() {
        guard authorized else { return }
        let service = FaithgramBadgeService.shared
        let alert = UIAlertController(title: "badge service", message: service.isConfigured ? service.endpoint + "\n" + service.syncStatus + "\nAdministrator key: " + (service.hasAdminToken(accountPeerId: ownerId) ? "saved in Keychain" : "not set") : "The shared service endpoint and signing key have not been added to this build.", preferredStyle: .alert)
        if service.isConfigured {
            alert.addAction(UIAlertAction(title: "refresh registry", style: .default, handler: { [weak self] _ in
                service.refresh(force: true)
                self?.pullAdminRecords()
            }))
            alert.addAction(UIAlertAction(title: "set administrator key", style: .default, handler: { [weak self] _ in self?.enterAdminKey() }))
        }
        alert.addAction(UIAlertAction(title: "close", style: .cancel))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    private func enterAdminKey() {
        guard authorized else { return }
        let alert = UIAlertController(title: "administrator key", message: "Enter the private admin-token created on your server. The key stays in this device's Keychain and is sent only to the configured badge service over HTTPS.", preferredStyle: .alert)
        alert.addTextField { field in field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none; field.textContentType = .password }
        alert.addAction(UIAlertAction(title: "save", style: .default, handler: { [weak self] _ in
            guard let self, self.authorized else { return }
            let token = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if FaithgramBadgeService.shared.storeAdminToken(token, accountPeerId: self.ownerId) { self.pullAdminRecords() }
            else { self.showError("Enter the 64-character administrator key from your server.") }
        }))
        alert.addAction(UIAlertAction(title: "cancel", style: .cancel))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    private func showError(_ text: String) {
        let alert = UIAlertController(title: "faithgram", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "close", style: .cancel))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
}
