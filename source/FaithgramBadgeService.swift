import Foundation
import CryptoKit
import Security

public enum FaithgramBadgeServiceError: Error {
    case configuration, unauthorized, network, invalidSignature, invalidRegistry, server(Int)
}

public struct FaithgramBadgeSnapshot: Codable {
    public let version: Int
    public let revision: Int64
    public let generatedAt: Date
    public let grants: [FaithgramPreferences.BadgeGrant]
}

private final class FaithgramBadgeHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url,
              target.scheme == "https", original.host == target.host, original.port == target.port else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public final class FaithgramBadgeService {
    public static let shared = FaithgramBadgeService()
    private struct Configuration: Codable { let endpoint: String; let publicKey: String; let ownerId: Int64? }
    private struct Envelope: Codable { let payload: Data; let signature: Data }
    private struct AdminResponse: Codable { let grants: [FaithgramPreferences.BadgeGrant] }
    private var configuration: Configuration?
    private var lastRefresh = Date.distantPast
    private var refreshing = false
    private var adminRecords: [FaithgramPreferences.BadgeGrant] = []
    private var revision: Int64 = 0
    private var timer: Timer?
    private let session: URLSession
    private let tokenService = "faithgram.badges.admin"

    public var isConfigured: Bool { configuration != nil }
    public var endpoint: String { configuration?.endpoint ?? "" }
    /// Owner account id injected into the configuration at build time; 0 disables administration.
    public var ownerId: Int64 { return Self.configuredOwnerId }
    /// Read directly from the bundled configuration so it never touches `shared` during its own initialization.
    public static let configuredOwnerId: Int64 = {
        guard let path = Bundle.main.path(forResource: "FaithgramBadgeService", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let value = try? JSONDecoder().decode(Configuration.self, from: data), let ownerId = value.ownerId, ownerId > 0 else { return 0 }
        return ownerId
    }()
    public var syncStatus: String { FaithgramPreferences.text("badgeSyncStatus", fallback: "not configured") }

    private init() {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCache = nil
        sessionConfiguration.timeoutIntervalForRequest = 15
        sessionConfiguration.timeoutIntervalForResource = 25
        session = URLSession(configuration: sessionConfiguration, delegate: FaithgramBadgeHTTPDelegate(), delegateQueue: nil)
        if let path = Bundle.main.path(forResource: "FaithgramBadgeService", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let value = try? JSONDecoder().decode(Configuration.self, from: data),
           let components = URLComponents(string: value.endpoint), components.scheme == "https", components.host != nil,
           components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
           Data(base64Encoded: value.publicKey)?.count == 32 {
            configuration = value
            FaithgramPreferences.setRemoteBadgeRecords([])
        }
        if let configuration, let data = UserDefaults.standard.data(forKey: "faithgram.badgeSnapshot"),
           let snapshot = try? Self.verify(data, publicKey: configuration.publicKey, now: Date(), allowCached: true) {
            revision = snapshot.revision
            FaithgramPreferences.setRemoteBadgeRecords(snapshot.grants)
        }
    }
    public static func verify(_ data: Data, publicKey: String, now: Date = Date(), minimumRevision: Int64 = 0, allowCached: Bool = false) throws -> FaithgramBadgeSnapshot {
        guard data.count <= 8 * 1024 * 1024, let keyData = Data(base64Encoded: publicKey), keyData.count == 32 else { throw FaithgramBadgeServiceError.invalidRegistry }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard key.isValidSignature(envelope.signature, for: envelope.payload) else { throw FaithgramBadgeServiceError.invalidSignature }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(FaithgramBadgeSnapshot.self, from: envelope.payload)
        let age = now.timeIntervalSince(snapshot.generatedAt)
        guard snapshot.version == 1, snapshot.revision >= minimumRevision, snapshot.revision >= 1,
              age >= -300, age <= (allowCached ? 7 * 86400 : 86400), snapshot.grants.count <= 20000 else { throw FaithgramBadgeServiceError.invalidRegistry }
        var ids = Set<String>()
        var roles = Set<String>()
        for grant in snapshot.grants {
            guard !grant.id.isEmpty, grant.id.utf8.count <= 128, grant.peerId > 0,
                  FaithgramPreferences.badgeOwnerId == 0 || grant.issuedBy == FaithgramPreferences.badgeOwnerId, grant.note.isEmpty,
                  grant.revokedAt == nil, ids.insert(grant.id).inserted,
                  roles.insert("\(grant.peerId):\(grant.role.rawValue)").inserted else { throw FaithgramBadgeServiceError.invalidRegistry }
        }
        return snapshot
    }
    public func setForeground(_ value: Bool) {
        timer?.invalidate()
        timer = nil
        guard value, isConfigured else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.refresh() }
    }
    public func refresh(force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        guard isConfigured else { completion?(false); return }
        guard !refreshing, force || Date().timeIntervalSince(lastRefresh) > 60 else { completion?(false); return }
        refreshing = true
        lastRefresh = Date()
        request(path: "v1/badges", actor: nil, body: nil) { [weak self] result in
            guard let self else { return }
            self.refreshing = false
            do {
                let data = try result.get()
                guard let configuration = self.configuration else { throw FaithgramBadgeServiceError.configuration }
                let snapshot = try Self.verify(data, publicKey: configuration.publicKey, minimumRevision: self.revision)
                self.revision = snapshot.revision
                UserDefaults.standard.set(data, forKey: "faithgram.badgeSnapshot")
                FaithgramPreferences.setRemoteBadgeRecords(snapshot.grants)
                FaithgramPreferences.setText("badgeSyncStatus", "synced · revision \(snapshot.revision)")
                completion?(true)
            } catch {
                FaithgramPreferences.setText("badgeSyncStatus", "sync failed · keeping the last verified list")
                completion?(false)
            }
        }
    }
    public func recordsForAdmin(accountPeerId: Int64) -> [FaithgramPreferences.BadgeGrant] {
        guard FaithgramPreferences.canManageBadges(accountPeerId: accountPeerId) else { return [] }
        return isConfigured ? adminRecords : FaithgramPreferences.localBadgeRecords
    }
    public func fetchAdminRecords(accountPeerId: Int64, completion: @escaping (Bool) -> Void) {
        request(path: "v1/admin/badges", actor: accountPeerId, body: nil) { [weak self] result in
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .secondsSince1970
                let value = try decoder.decode(AdminResponse.self, from: result.get())
                guard value.grants.count <= 20000 else { throw FaithgramBadgeServiceError.invalidRegistry }
                self?.adminRecords = value.grants
                completion(true)
            } catch { completion(false) }
        }
    }
    public func grant(_ role: FaithgramPreferences.Badge, peerId: Int64, accountPeerId: Int64, note: String, expiresAt: Date?, completion: @escaping (Bool) -> Void) {
        var body: [String: Any] = ["peerId": peerId, "role": role.rawValue, "note": note]
        if let expiresAt { body["expiresAt"] = expiresAt.timeIntervalSince1970 }
        mutate(path: "v1/admin/grant", actor: accountPeerId, body: body, completion: completion)
    }
    public func revoke(id: String, accountPeerId: Int64, completion: @escaping (Bool) -> Void) {
        mutate(path: "v1/admin/revoke", actor: accountPeerId, body: ["id": id], completion: completion)
    }
    private func mutate(path: String, actor: Int64, body: [String: Any], completion: @escaping (Bool) -> Void) {
        request(path: path, actor: actor, body: body) { [weak self] result in
            guard case .success = result, let self else { completion(false); return }
            self.refresh(force: true)
            self.fetchAdminRecords(accountPeerId: actor, completion: completion)
        }
    }
    public func storeAdminToken(_ token: String, accountPeerId: Int64) -> Bool {
        guard FaithgramPreferences.canManageBadges(accountPeerId: accountPeerId), token.count == 64,
              token.allSatisfy({ $0.isHexDigit }) else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: tokenService, kSecAttrAccount as String: String(accountPeerId)]
        let data = Data(token.utf8)
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
    public func hasAdminToken(accountPeerId: Int64) -> Bool { adminToken(accountPeerId) != nil }
    private func adminToken(_ actor: Int64) -> String? {
        guard FaithgramPreferences.canManageBadges(accountPeerId: actor) else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: tokenService, kSecAttrAccount as String: String(actor), kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private func request(path: String, actor: Int64?, body: [String: Any]?, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let configuration, let baseURL = URL(string: configuration.endpoint) else { completion(.failure(FaithgramBadgeServiceError.configuration)); return }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let actor {
            guard let token = adminToken(actor) else { completion(.failure(FaithgramBadgeServiceError.unauthorized)); return }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            request.setValue(String(actor), forHTTPHeaderField: "X-Faithgram-Actor")
        }
        if let body {
            guard let data = try? JSONSerialization.data(withJSONObject: body) else { completion(.failure(FaithgramBadgeServiceError.invalidRegistry)); return }
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        session.dataTask(with: request) { data, response, error in
            let result: Result<Data, Error>
            if let error { result = .failure(error) }
            else if let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode), let data, data.count <= 8 * 1024 * 1024 { result = .success(data) }
            else { result = .failure(FaithgramBadgeServiceError.server((response as? HTTPURLResponse)?.statusCode ?? 0)) }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
