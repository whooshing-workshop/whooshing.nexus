import Vapor

/// 用于服务模块的 Debug 测试阶段
///
/// 加载一个 Router，根据所提供的白名单服务模块 ID，来通过来源服务的合法验证
/// 从而不需要操作数据库就可进行测试，更加方便
/// 如果白名单未命中，则会拒绝访问
public struct DebugingModuleController: RouteCollection, Sendable {
    let serviceIds: [UUID]
    
    public func boot(routes: any RoutesBuilder) throws {
        let modules = routes.grouped("modules")
        modules.get(use: fetchAllModules)
        modules.get(":moduleId", "verify", use: verifyModule)
    }
    
    @Sendable
    func fetchAllModules(req: Request) async throws -> ModuleListResponse {
        ModuleListResponse(moduleIds: serviceIds)
    }

    @Sendable
    func verifyModule(req: Request) async throws -> ModuleVerifyResponse {
        let moduleId = try parameter("moduleId", from: req) { UUID(uuidString: $0) }
        return ModuleVerifyResponse(allowed: serviceIds.contains(moduleId))
    }
    
    public init(serviceIds: [UUID]) {
        self.serviceIds = serviceIds
    }
}

struct ModuleVerifyResponse: Content {
    let allowed: Bool
}

struct ModuleListResponse: Content {
    let moduleIds: [UUID]
}
