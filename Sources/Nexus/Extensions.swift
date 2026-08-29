import Vapor

public func parameter<T>(_ name: String, from req: Request, to: (String) throws -> T?) throws -> T {
    guard let varString = req.parameters.get(name) else {
        throw Abort(.badRequest, reason: "URL 中未找到 \(name) 参数")
    }
    
    guard let res = try to(varString) else {
        throw Abort(.badRequest, reason: "URL 中的 \(name) 参数无效(\(varString))")
    }
    
    return res
}
