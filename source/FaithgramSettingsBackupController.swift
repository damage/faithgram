import Foundation
import UIKit
import UniformTypeIdentifiers
import TelegramCore
import AccountContext

final class FaithgramSettingsBackupController: NSObject, UIDocumentPickerDelegate {
    private let context: AccountContext
    private var exportURL: URL?
    init(context: AccountContext) { self.context = context }
    deinit { cleanup() }
    private func cleanup() { if let exportURL { try? FileManager.default.removeItem(at: exportURL.deletingLastPathComponent()); self.exportURL = nil } }
    private func show(_ text: String) {
        let alert = UIAlertController(title: "faithgram", message: FaithgramPreferences.interfaceText(text), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("OK"), style: .default))
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    private func password(export: Bool, completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText(export ? "Encrypt settings backup" : "Open settings backup"), message: FaithgramPreferences.interfaceText(export ? "Choose a password of at least 12 characters. This backup includes Faithgram settings and chat rules. Sessions, badges, message archives and administrator credentials are excluded." : "Enter the backup password."), preferredStyle: .alert)
        alert.addTextField { $0.isSecureTextEntry = true; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        if export { alert.addTextField { $0.placeholder = FaithgramPreferences.interfaceText("Repeat password"); $0.isSecureTextEntry = true } }
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText(export ? "Export" : "Open"), style: .default) { [weak self] _ in
            let value = alert.textFields?.first?.text ?? ""
            guard value.count >= 12, value.utf8.count <= 1024, !export || alert.textFields?.last?.text == value else { self?.show("Passwords must match and contain at least 12 characters."); return }
            completion(value)
        })
        context.sharedContext.mainWindow?.presentNative(alert)
    }
    func exportSettings() {
        password(export: true) { [weak self] password in
            let backup = FaithgramSettingsBackup.capture()
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try backup.encrypted(password: password)
                    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("faithgram-settings-" + UUID().uuidString).appendingPathComponent("faithgram-settings.fgs")
                    try FaithgramVault.write(data, to: url)
                    DispatchQueue.main.async {
                        guard let self else { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()); return }
                        self.cleanup()
                        self.exportURL = url
                        let picker: UIDocumentPickerViewController
                        if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true) }
                        else { picker = UIDocumentPickerViewController(url: url, in: .exportToService) }
                        picker.delegate = self
                        self.context.sharedContext.mainWindow?.presentNative(picker)
                    }
                } catch { DispatchQueue.main.async { self?.show("Settings could not be exported. Check available storage.") } }
            }
        }
    }
    func importSettings() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) { picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true) }
        else { picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import) }
        picker.delegate = self
        context.sharedContext.mainWindow?.presentNative(picker)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cleanup() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if exportURL != nil { cleanup(); return }
        guard let url = urls.first else { return }
        password(export: false) { [weak self] password in
            DispatchQueue.global(qos: .userInitiated).async {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 2 * 1024 * 1024 else { throw FaithgramVaultError.invalidFile }
                    let backup = try FaithgramSettingsBackup.decrypt(Data(contentsOf: url), password: password)
                    DispatchQueue.main.async { self?.confirm(backup) }
                } catch { DispatchQueue.main.async { self?.show("Incorrect password or invalid settings backup. No settings were changed.") } }
            }
        }
    }
    private func confirm(_ backup: FaithgramSettingsBackup) {
        let alert = UIAlertController(title: FaithgramPreferences.interfaceText("Restore settings"), message: FaithgramPreferences.interfaceText("Apply \(backup.values.count) saved settings? This changes local interface and privacy controls. Existing Telegram sessions and message archives are kept."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("Restore"), style: .default) { [weak self] _ in
            do { try backup.apply(); self?.show("Settings restored.") }
            catch { self?.show("This settings backup is invalid. No settings were changed.") }
        })
        context.sharedContext.mainWindow?.presentNative(alert)
    }
}
