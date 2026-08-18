import RoutingKit
import Logging

public protocol Tube: Sendable {
    associatedtype Request: Sendable
    associatedtype Response: Sendable
    associatedtype HandlerResponse: Sendable
    associatedtype Failure: Error
    
    typealias Handler = @Sendable (Request) async throws -> HandlerResponse
    
    var router: TrieRouter<Handler> { get }
    var logger: Logger { get }
    
    func execute() async -> Result<Void, Failure>
    func asyncShutdown() async -> Result<Void, Failure>
    func executeWithAsyncShutdown() async -> Result<Void, Failure>
}
