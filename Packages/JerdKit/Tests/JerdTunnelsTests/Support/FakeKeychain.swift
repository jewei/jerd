import Foundation
import JerdTunnels
import Security
import os

/// An in-memory Keychain that records each call and can return a forced status.
final class FakeKeychain: KeychainAccessing {
    struct State {
        var items: [TunnelKeychainItem: Data] = [:]
        var calls: [String] = []
        var forcedStatus: OSStatus?
    }

    let state = OSAllocatedUnfairLock(initialState: State())

    func copyData(_ item: TunnelKeychainItem) -> (status: OSStatus, data: Data?) {
        state.withLock { state in
            state.calls.append("copy \(item.account)")
            if let forced = state.forcedStatus { return (forced, nil) }
            guard let data = state.items[item] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func update(_ item: TunnelKeychainItem, data: Data) -> OSStatus {
        state.withLock { state in
            state.calls.append("update \(item.account)")
            if let forced = state.forcedStatus { return forced }
            guard state.items[item] != nil else { return errSecItemNotFound }
            state.items[item] = data
            return errSecSuccess
        }
    }

    func add(_ item: TunnelKeychainItem, data: Data) -> OSStatus {
        state.withLock { state in
            state.calls.append("add \(item.account)")
            if let forced = state.forcedStatus { return forced }
            guard state.items[item] == nil else { return errSecDuplicateItem }
            state.items[item] = data
            return errSecSuccess
        }
    }

    func delete(_ item: TunnelKeychainItem) -> OSStatus {
        state.withLock { state in
            state.calls.append("delete \(item.account)")
            if let forced = state.forcedStatus { return forced }
            return state.items.removeValue(forKey: item) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}
