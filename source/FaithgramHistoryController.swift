import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import AccountContext

final class FaithgramHistoryController: ViewController, UITableViewDataSource, UITableViewDelegate {
    private let context: AccountContext
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private var records: [FaithgramHistoryRecord] = []
    private let message: (peer: Int64, namespace: Int32, id: Int32)?
    init(context: AccountContext, message: (peer: Int64, namespace: Int32, id: Int32)? = nil) {
        self.context = context
        self.message = message
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }, style: .glass))
        self.title = FaithgramPreferences.interfaceText("Message history")
        self.statusBar.statusBarStyle = .White
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = .black
        self.displayNodeDidLoad()
        table.backgroundColor = .black
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 84
        table.contentInsetAdjustmentBehavior = .never
        view.addSubview(table)
        let context = self.context
        let message = self.message
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let store = try FaithgramMessageHistory.store(mediaBox: context.account.postbox.mediaBox, accountPeerId: context.account.peerId)
                let records: [FaithgramHistoryRecord]
                if let message { records = try store.record(peerId: message.peer, namespace: message.namespace, messageId: message.id).map { [$0] } ?? [] }
                else { records = try store.records() }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.records = records
                    self.table.reloadData()
                    if records.isEmpty { self.showMessage("No archived messages yet. History starts when saving is enabled and this device receives an edit or deletion.") }
                }
            } catch { DispatchQueue.main.async { self?.showMessage("Message history could not be opened. Check device access and available storage.") } }
        }
    }
    private func showMessage(_ text: String) {
        let label = UILabel()
        label.text = FaithgramPreferences.interfaceText(text)
        label.textColor = .gray
        label.numberOfLines = 0
        label.textAlignment = .center
        table.backgroundView = label
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        transition.updateFrame(view: table, frame: CGRect(x: 0, y: top, width: layout.size.width, height: layout.size.height - top))
        table.contentInset.bottom = layout.intrinsicInsets.bottom + 16
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { return records.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let record = records[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = UIColor(white: 0.105, alpha: 1)
        cell.textLabel?.textColor = .white
        cell.textLabel?.numberOfLines = 3
        cell.textLabel?.text = record.revisions.last?.text.isEmpty == false ? record.revisions.last?.text : FaithgramPreferences.interfaceText("Media message")
        cell.detailTextLabel?.textColor = .gray
        let status = record.deletedAt == nil ? "edited" : "deleted"
        cell.detailTextLabel?.text = "\(status) · \(record.revisions.count) versions · \(record.peerId) / \(record.messageId)"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let record = records[indexPath.row]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        let text = record.revisions.enumerated().map { index, revision in
            let heading = FaithgramPreferences.interfaceText("Version \(index + 1)") + " · " + formatter.string(from: revision.capturedAt)
            return heading + "\n\n" + (revision.text.isEmpty ? FaithgramPreferences.interfaceText("Media message") : revision.text)
        }.joined(separator: "\n\n──────────\n\n")
        (navigationController as? NavigationController)?.pushViewController(FaithgramTextController(context: context, title: FaithgramPreferences.interfaceText("Message history"), text: text, save: nil))
    }
}

final class FaithgramTextController: ViewController {
    private let context: AccountContext
    private let editor = UITextView()
    private let initialText: String
    private let save: ((String) throws -> Void)?
    init(context: AccountContext, title: String, text: String, save: ((String) throws -> Void)?) {
        self.context = context
        self.initialText = text
        self.save = save
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: context.sharedContext.currentPresentationData.with { $0 }, style: .glass))
        self.title = title
        self.statusBar.statusBarStyle = .White
        if save != nil { navigationItem.rightBarButtonItem = UIBarButtonItem(title: FaithgramPreferences.interfaceText("Save"), style: .done, target: self, action: #selector(saveText)) }
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadDisplayNode() {
        displayNode = ASDisplayNode()
        displayNode.backgroundColor = .black
        displayNodeDidLoad()
        editor.backgroundColor = .black
        editor.textColor = .white
        editor.font = .preferredFont(forTextStyle: .body)
        editor.autocapitalizationType = .none
        editor.autocorrectionType = .no
        editor.smartQuotesType = .no
        editor.smartDashesType = .no
        editor.isEditable = save != nil
        editor.text = initialText
        editor.textContainerInset = UIEdgeInsets(top: 20, left: 18, bottom: 20, right: 18)
        view.addSubview(editor)
    }
    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = navigationLayout(layout: layout).navigationFrame.maxY
        let bottom = layout.insets(options: [.input]).bottom
        transition.updateFrame(view: editor, frame: CGRect(x: 0, y: top, width: layout.size.width, height: max(0, layout.size.height - top - bottom)))
    }
    @objc private func saveText() {
        do {
            try save?(editor.text ?? "")
            let _ = self.navigationController?.popViewController(animated: true)
        } catch {
            let alert = UIAlertController(title: "faithgram", message: FaithgramPreferences.interfaceText("Invalid rules. Use one regular expression per line, up to 32 expressions and 512 characters each."), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: FaithgramPreferences.interfaceText("OK"), style: .default))
            context.sharedContext.mainWindow?.presentNative(alert)
        }
    }
}

public func faithgramMessageHistoryController(context: AccountContext, peerId: Int64, namespace: Int32, messageId: Int32) -> ViewController {
    return FaithgramHistoryController(context: context, message: (peerId, namespace, messageId))
}
