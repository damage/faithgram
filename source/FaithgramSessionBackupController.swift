import Foundation
import UIKit
import UniformTypeIdentifiers
import SwiftSignalKit
import TelegramCore
import AccountContext

final class FaithgramSessionBackupController: NSObject, UIDocumentPickerDelegate {
    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var exportURL: URL?
    init(context: AccountContext) { self.context = context }
    deinit { disposable.dispose(); cleanupExport() }
    private func present(_ alert: UIAlertController) { context.sharedContext.mainWindow?.presentNative(alert) }
    private func failure(_ text: String) {
        let alert = UIAlertController(title: "faithgram", message: FaithgramPreferences.interfaceText(text), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("OK"), style: .default))
        present(alert)
    }
    private func password(export: Bool, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText(export ? "Encrypt sessions backup" : "Open sessions backup"), message: FaithgramPreferences.interfaceText(export ? "Choose a password with at least 12 characters. Keep it separately; Faithgram cannot recover it. This file restores only sessions that remain active on Telegram servers." : "Enter the backup password."), preferredStyle: .alert)
        alert.addTextField { field in field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none }
        if export { alert.addTextField { field in field.placeholder = FaithgramPreferences.interfaceText("Repeat password"); field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none } }
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(export ? "Create backup" : "Open"), style: .default, handler: { [weak self] _ in
            let value = alert.textFields?.first?.text ?? ""
            guard value.count >= 12, value.utf8.count <= 1024, !export || alert.textFields?.last?.text == value else {
                self?.failure("The passwords must match and contain at least 12 characters.")
                return
            }
            completion(value)
        }))
        present(alert)
    }
    func exportSessions() {
        password(export: true) { [weak self] password in
            guard let self else { return }
            self.disposable.set((self.context.sharedContext.activeAccountContexts |> take(1) |> mapToSignal { value -> Signal<[FaithgramSavedSession?], NoError> in
                return combineLatest(value.accounts.map { _, account, _ in
                    accountBackupData(postbox: account.account.postbox) |> map { data in data.map { FaithgramSavedSession(testingEnvironment: account.account.testingEnvironment, data: $0) } }
                })
            } |> deliverOnMainQueue).start(next: { [weak self] sessions in
                guard let self else { return }
                let backup = FaithgramSessionBackup(sessions: sessions.compactMap { $0 })
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    do {
                        let data = try backup.encrypted(password: password)
                        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("faithgram-export-" + UUID().uuidString, isDirectory: true).appendingPathComponent("faithgram-sessions.fgb")
                        try FaithgramVault.write(data, to: url)
                        DispatchQueue.main.async {
                            guard let self else { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
                            self.cleanupExport()
                            self.exportURL = url
                            let picker: UIDocumentPickerViewController
                            if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
                            else { picker = UIDocumentPickerViewController(url: url, in: .exportToService) }
                            picker.delegate = self
                            self.context.sharedContext.mainWindow?.presentNative(picker)
                        }
                    } catch { DispatchQueue.main.async { self?.failure("The backup could not be created. Check active accounts and available storage.") } }
                }
            }))
        }
    }
    func importSessions() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true) }
        else { picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import) }
        picker.delegate = self
        context.sharedContext.mainWindow?.presentNative(picker)
    }
    private func cleanupExport() {
        if let url = exportURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); exportURL = nil }
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanupExport() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportURL != nil { cleanupExport(); return }
        guard let url = urls.first else { return }
        password(export: false) { [weak self] password in
            DispatchQueue.global(qos: .userInitiated).async {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
                    let backup = try FaithgramSessionBackup.decrypt(Data(contentsOf: url), password: password)
                    DispatchQueue.main.async { self?.confirmRestore(backup) }
                } catch { DispatchQueue.main.async { self?.failure("The password is incorrect or the backup is invalid. No accounts were changed.") } }
            }
        }
    }
    private func confirmRestore(_ backup: FaithgramSessionBackup) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText("Restore saved sessions"), message: FaithgramPreferences.interfaceText("Restore \(backup.sessions.count) saved sessions? Existing accounts will be kept. Sessions revoked on Telegram servers require a new login."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Restore"), style: .default, handler: { [weak self] _ in
            guard let self else { return }
            self.disposable.set((self.context.sharedContext.accountManager.transaction { transaction -> Int in
                var existing = Set<String>()
                for record in transaction.getRecords() {
                    var testing = false
                    var peer: Int64?
                    for attribute in record.attributes {
                        if case let .environment(value) = attribute { testing = value.environment == .test }
                        if case let .backupData(value) = attribute { peer = value.data?.peerId }
                    }
                    if let peer { existing.insert("\(testing):\(peer)") }
                }
                var restored = 0
                for session in backup.sessions {
                    let identity = "\(session.testingEnvironment):\(session.data.peerId)"
                    if existing.contains(identity) { continue }
                    let attributes: [TelegramAccountManagerTypes.Attribute] = [.environment(AccountEnvironmentAttribute(environment: session.testingEnvironment ? .test : .production)), .backupData(AccountBackupDataAttribute(data: session.data))]
                    let _ = transaction.createRecord(attributes)
                    existing.insert(identity)
                    restored += 1
                }
                return restored
            } |> deliverOnMainQueue).start(next: { [weak self] count in self?.failure("\(count) saved sessions added. Telegram will validate them when they connect.") }))
        }))
        present(alert)
    }
}
