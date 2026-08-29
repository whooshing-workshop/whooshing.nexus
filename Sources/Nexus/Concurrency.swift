import Dispatch
import ErrorHandle

@usableFromInline
final class SyncResultBox<T, E: Error>: @unchecked Sendable {
    @usableFromInline var result: Result<T, E>? = nil
    @usableFromInline init() {}
}

@inlinable
public func asyncResultToSync<T, E>(
    action: @escaping @Sendable () async -> Result<T, E>
) throws(E) -> T where T: Sendable, E: Error {
    let semaphore = DispatchSemaphore(value: 0)
    let box = SyncResultBox<T, E>()
    
    Task {
        box.result = await action()
        semaphore.signal()
    }
    
    semaphore.wait()
    
    switch box.result {
    case .success(let storage): return storage
    case .failure(let error): throw error
    case .none: fatalError("异步任务未返回结果却触发了信号量")
    }
}

@inlinable
public func asyncToSync<T, E>(
    action: @escaping @Sendable () async throws(E) -> T
) throws(E) -> T where T: Sendable, E: Error {
    try asyncResultToSync {
        do {
            let value = try await action()
            return Result<T, E>.success(value)
        } catch {
            return Result<T, E>.failure(error as! E)
        }
    }
}

@inlinable
public func fatalIfFail<T>(
    action: () throws -> T
) -> T {
    do {
        return try action()
    } catch {
        fatalError(String(reflecting: error))
    }
}
