import Vapor
import Fluent
import AnyCodable
import LoggingAdvanced

/// 启动模式枚举，表示当前服务运行的目标环境
///
/// 可以指定运行模式为 production, debug, independentDebug
///
/// Mode.detect 表示自动从环境变量检测运行模式
///
/// 其中，independentDebug 表示不依赖任何外部模块，比如用户身份认证模块，服务管理模块等等
/// 自动内部处理这些认证请求，保证可无依赖运行在本机。
///
/// - Warning: independentDebug 模式应当永远仅仅用作测试，请勿在生产环境使用
@frozen
public struct Mode: Sendable, CustomStringConvertible, Loggerable {
    
    /// 生产环境，使用正式配置
    @inlinable public static var production: Mode { Mode(envrionment: .production) }
    
    /// 调试环境，使用 development 配置
    @inlinable public static var debug: Mode { Mode(envrionment: .development) }
    
    /// 独立调试配置，传入调试参数结构体
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
    /// - Warning: 该模式应当永远仅仅用作测试，请勿在生产环境使用
    @inlinable public static func independentDebug(_ debuging: Environment.Config) -> Mode { Mode(envrionment: .development, debuging: debuging) }
    
    /// 测试配置，传入调试参数结构体应当仅仅用在单元测试中
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
    /// - Warning: 该模式应当永远仅仅用作测试，请勿在生产环境使用
    @inlinable public static func testing(_ debuging: Environment.Config) -> Mode { Mode(envrionment: .testing, debuging: debuging) }
    
    /// 自动从环境变量变量判断运行模式，你需要选择提供调试参数
    /// 若你希望永远不使用 testing 或 independentDebug 模式，可以指定为 nil
    /// 这样若环境中出现了这两个模式，将会直接触发 fatalError
    ///
    /// Mode.production 对应 --env production
    /// Mode.debug 与 Mode.independentDebug 对应 --env development
    /// Mode.testing 对应 --env testing
    ///
    /// > 在一般的 .production 或 .debug 模式下，
    /// 这些参数会通过 Whooshing 系统的环境变量解析得到，
    /// 而在无依赖 debug 模式下，则需要提供伪造的参数进行运行测试
    @inlinable public static func detect(_ debuging: Environment.Config? = nil) -> Mode {
        let env = try! Environment.detect()
        return Mode(envrionment: env, debuging: debuging)
    }
    
    /// 当前运行的环境
    public var envrionment: Environment
    
    @usableFromInline
    let debuging: Environment.Config?
    
    @inlinable init(envrionment: Environment, debuging: Environment.Config? = nil) {
        self.envrionment = envrionment
        self.debuging = debuging
    }
    
    public var json: [String: AnyCodable] {[
        "env": AnyCodable(envrionment.name),
        "is_release": AnyCodable(envrionment.isRelease),
        "arguments": AnyCodable(envrionment.arguments)
    ]}
    
    public var description: String {
        formatJson(json)
    }
    
    public var summaryDescription: String {
        "env-\(envrionment.name)\(envrionment.isRelease ? "-release" : "")"
    }
}

public protocol AnyNexus: Sendable {
    var config: Environment.Config { get }
}

public struct Nexus<T: Tube>: AnyNexus {
    public let tube: T
    /// 当前环境的配置项（端口、数据库等）
    public let config: Environment.Config
    /// 所运行与的 eventloop 组
    public let eventLoopGroup: EventLoopGroup
    /// 当前服务使用的日志记录器
    public let logger: Logger
    
    /// 该服务所有连接的数据库
    public private(set) lazy var databases: Set<Environment.DB> = {
        .init(self.config.dbServices.flatMap { $0.dbs })
    }()
    
    public let driverKeys: [any Environment.DriverKey.Type]
    public let loggingFactory: LoggingFactory
    
    public init(
        tube: T,
        bootstrap: Bootstrap.Paras
    ) {
        self.tube = tube
        self.logger = bootstrap.logger
        self.config = bootstrap.config
        self.driverKeys = bootstrap.driverKeys
        self.eventLoopGroup = bootstrap.eventLoopGroup
        self.loggingFactory = bootstrap.loggingFactory
        tube.config(from: self)
    }
    
    public func execute() async throws {
        try await tube.execute().get()
    }
    
    public func asyncShutdown() async throws {
        try await tube.asyncShutdown().get()
    }
    
    public func executeWithAsyncShutdown() async throws {
        try await tube.executeWithAsyncShutdown().get()
    }
}
