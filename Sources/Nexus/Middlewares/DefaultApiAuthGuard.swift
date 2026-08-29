import Vapor

public struct DefaultApiAuthGuard: AsyncMiddleware {
    public init() {}
    
    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let data = request.apiAuthData.getData(at: request.apiAuthData.readerIndex, length: request.apiAuthData.readableBytes) else {
            throw Abort(.internalServerError, reason: "数据解码失败")
        }
        request.auth.login(data)
        return try await next.respond(to: request)
    }
}

extension Data: @retroactive Authenticatable {}
