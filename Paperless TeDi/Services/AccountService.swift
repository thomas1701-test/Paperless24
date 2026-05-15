import Foundation

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var serverUrl: String
    var username: String
}

enum AccountService {
    private static let accountsKey = "accounts_v2"
    private static let activeIdKey = "activeAccountId"

    static func load() -> [Account] {
        guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
        return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    static func save(_ accounts: [Account]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: accountsKey)
    }

    static func activeId() -> UUID? {
        guard let str = UserDefaults.standard.string(forKey: activeIdKey) else { return nil }
        return UUID(uuidString: str)
    }

    static func setActiveId(_ id: UUID?) {
        if let id = id {
            UserDefaults.standard.set(id.uuidString, forKey: activeIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeIdKey)
        }
    }
}
