import Vapor

public struct ConfigKey: StorageKey {
    public typealias Value = Environment.Config
}

public extension Request {
    var config: Environment.Config { self.storage[ConfigKey.self]! }
}
