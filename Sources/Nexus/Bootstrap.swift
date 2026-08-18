import Vapor
import Fluent
import AnyCodable
import LoggingAdvanced

public enum Bootstrap {
    public static let envPrefix = "WHOOSHING"
    
    @frozen
    public struct Paras: Sendable {
        public let logger: Logger
        public let environment: Environment
        public let config: Environment.Config
        public let eventLoopGroup: EventLoopGroup
        public let driverKeys: [any Environment.DriverKey.Type]
        public let loggingFactory: LoggingFactory
        
        @usableFromInline
        init(
            logger: Logger,
            environment: Environment,
            config: Environment.Config,
            eventLoopGroup: EventLoopGroup,
            driverKeys: [any Environment.DriverKey.Type],
            loggingFactory: LoggingFactory
        ) {
            self.logger = logger
            self.environment = environment
            self.config = config
            self.eventLoopGroup = eventLoopGroup
            self.driverKeys = driverKeys
            self.loggingFactory = loggingFactory
        }
    }

    /// - Parameters:
    ///   - mode: 启动环境
    ///   - driverKeys: 要注入的驱动列表
    ///   - logger: 该服务要使用的日志记录器
    ///   - loggingFactory: 该服务将配置的日志工厂，whooshing 实例不主动启动其 bootstrap 函数，仅配置日志策略，但不启动，由外部调用者自行决定合适启用
    @inlinable
    public static func run(
        _ mode: Mode,
        driverKeys: [any Environment.DriverKey.Type] = [],
        logger: Logger,
        loggingFactory: LoggingFactory? = nil
    ) async -> Result<Paras, NexusErrcase.ErrType> {
        await .async { () throws(NexusErrcase.ErrType) in
            let initLogger = logger.derive(subId: "sysinit")
            
            initLogger.info("正在初始化 Whooshing 服务", metadata: ["mode": .summaryData(mode)])
            initLogger.debug("详细参数", metadata: ["mode": .data(mode)])
            
            let config: Environment.Config
            
            var env = mode.envrionment
            
            // 修复 Vapor 在 swift test 下会错误解析 SPM 注入的参数（如 --test-bundle-path 等）
            // 如果是在 testing 环境，或是检测到有 xctest 相关的参数，直接清理参数
            if env == .testing || env.arguments.contains(where: { $0.contains("xctest") || $0.hasPrefix("--test") }) {
                env.arguments = ["vapor"]
            }
            
            if ![Environment.production, .development, .testing].contains(env) {
                fatalError("环境变量 \(env.name) 无法识别")
            }
            
            var strategies: [LoggerStrategy] = []
            
            if let dp = mode.debuging {
                if [Environment.development, .testing].contains(env) {
                    initLogger.info("启动无依赖独立运行模式")
                    config = dp
                } else {
                    config = try required(throws: NexusErrcase.environmentFailed, category: .inherit) {
                        try Environment.get(with: envPrefix, driverKeys: driverKeys)
                    }
                }
            } else {
                if env == .testing {
                    fatalError("未提供调试数据，无法进入 testing 模式")
                } else {
                    config = try required(throws: NexusErrcase.environmentFailed, category: .inherit) {
                        try Environment.get(with: envPrefix, driverKeys: driverKeys)
                    }
                }
            }
            
            let logDir = config.log.directory
            initLogger.debug("准备日志轮转系统", metadata: ["directory": .stringConvertible(logDir)])
            
            let errorLogDir = logDir.appendingPathComponent("error_logs")
            try required(throws: NexusErrcase.loggingSystemFailed, metadata: ["directory": .stringConvertible(errorLogDir)], category: .inherit) {
                try strategies.append(
                    .init(
                        label: "error",
                        level: .error,
                        config: .file(logPrefix: "", directory: errorLogDir, name: "error.log")
                    )
                )
            }
            
            let businessLogDir = logDir.appendingPathComponent("business_logs")
            try required(throws: NexusErrcase.loggingSystemFailed, metadata: ["directory": .stringConvertible(businessLogDir)], category: .inherit) {
                try strategies.append(
                    .init(
                        label: "business",
                        level: .trace,
                        config: .file(
                            match: {
                                $0.contains("vapor") ||
                                $0.hasPrefix(logger.label + "." + "woo")
                            },
                            directory: businessLogDir,
                            name: "business.log"
                        )
                    )
                )
            }
            
            for driverKey in driverKeys {
                strategies += driverKey.loggerStrategies(for: logDir)
            }
            
            let factory = switch loggingFactory {
            case .none: LoggingFactory(strategies: strategies)
            case .some(let f): f.append(strategies: strategies)
            }
            
            return Bootstrap.Paras(
                logger: logger,
                environment: env,
                config: config,
                eventLoopGroup: MultiThreadedEventLoopGroup.singleton,
                driverKeys: driverKeys,
                loggingFactory: factory
            )
        }
    }

}
