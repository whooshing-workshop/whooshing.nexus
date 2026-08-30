import Vapor
import ErrorHandle

/// 用于将所有 Vapor 路由返回的错误转为 AbortError
public struct RouteEndErrorHandler: AsyncMiddleware {
    @inlinable
    public init() {}
    
    @inlinable
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            if let e = error as? Err {
                request.logger.errThrow(e)
                throw error.vaporlized
            } else {
                let e = error.vaporlized
                request.logger.report(error: e)
                throw e
            }
        }
    }
}
