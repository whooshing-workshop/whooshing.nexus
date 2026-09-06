# Whooshing Nexus 服务模块核心

本项目为 [Whooshing](https://github.com/whooshing-workshop/whooshing) 系统的**服务模块核心库**，是所有 Whooshing 服务模块的启动枢纽。它负责识别运行模式、从环境变量中解析模块配置、装配日志轮转系统，并把这些能力统一交付给具体的传输层（`Tube`）与各类驱动（`Driver`）。

`Nexus` 本身不绑定任何 Web 框架。基于 Vapor 的传输层由 [whooshing.tube-vapor](https://github.com/whooshing-workshop/whooshing.tube-vapor) 提供；文件存储、权限系统等能力则由 [whooshing.driver-file-storage](https://github.com/whooshing-workshop/whooshing.driver-file-storage)、[whooshing.driver-privilege-system](https://github.com/whooshing-workshop/whooshing.driver-privilege-system) 等驱动以 `Environment.DriverKey` 的形式挂载。

### 特性

- **运行模式识别**：通过 `Mode` 区分 `production` / `debug` / `independentDebug` / `testing` 四种运行模式，`Mode.detect(...)` 可直接从 `--env` 启动参数中自动识别。
- **环境变量驱动的配置**：生产环境下所有配置（模块 ID、端口、数据库、日志目录等）均以 `WHOOSHING_` 为前缀从环境变量中解析，模块代码**无需书写任何 Swift 配置**；独立调试模式下则以 `Environment.Config` 结构体直接伪造。
- **可扩展的驱动机制**：任何库只需实现 `Environment.DriverKey`，即可把自己的配置段落注入环境变量解析流程，并为自己申请独立的日志轮转文件。
- **日志轮转装配**：自动为错误日志（`error_logs`）、业务日志（`business_logs`）以及各驱动的日志规划 `LoggerStrategy`，并汇总为 `LoggingFactory`，由调用方决定何时 `bootstrap()`。
- **传输层抽象**：`Tube` 协议描述了一个服务的启动、关闭与配置回调，`Nexus<T: Tube>` 负责把配置注入到具体传输层中。
- **统一错误转译**：`Error.vaporlized` 将 `ErrorHandle` 体系中的 `Err` 按其 `ErrCategory` 转换为 Vapor 的 `AbortError`，`RouteEndErrorHandler` 中间件可直接挂载于路由末端。
- **同步桥接工具**：`asyncToSync` / `asyncResultToSync` 用于在 `static let` 等同步上下文中完成异步初始化。

----------

### 导入该依赖库

在你的 `Package.swift` 加入：

``` swift
.package(url: "https://github.com/whooshing-workshop/whooshing.nexus.git", from: "1.0.0")
```

在依赖模块中引入:

```swift
.product(name: "Nexus", package: "whooshing.nexus")
```

在需要的地方:

```swift
import Nexus
```

> `Nexus` 已通过 `@_exported` 重新导出了 `Vapor`、`Fluent`、`FluentPostgresDriver`、`AnyCodable` 与 `LoggingAdvanced`，导入 `Nexus` 后无需再单独导入这些模块。

--------

### 使用介绍

一个服务模块的启动分为三步：**选择运行模式 → 执行 Bootstrap → 用 Bootstrap 参数构建 Tube 与 Nexus**。一般情况下你不需要直接使用本库，而是使用 [whooshing.tube-vapor](https://github.com/whooshing-workshop/whooshing.tube-vapor) 或各类模版项目；以下介绍面向需要理解底层机制或自行实现 `Tube` 的开发者。

#### 1. 选择运行模式

``` swift
import Nexus

// 生产环境：全部配置来自环境变量
let mode: Mode = .production

// 独立调试 / 单元测试：直接提供伪造的配置
let debugConfig = Environment.Config(
    id: UUID(),
    name: "my-module",
    port: 6500,
    dbServices: [
        .init(
            name: "default",
            host: "localhost",
            port: 5432,
            dbParameters: [
                .init(name: "postgres", user: "postgres", password: "password")
            ]
        )
    ],
    managerUrl: .init(string: "http://localhost:6500")!
)
let debugMode: Mode = .independentDebug(debugConfig)

// 根据 `--env` 启动参数自动识别：
//   --env production   -> .production
//   --env development  -> .debug(有调试参数时为 .independentDebug)
//   --env testing      -> .testing
// 传入 nil 表示禁止进入 testing / independentDebug 模式
let detected: Mode = .detect(debugConfig)
```

> **Warning**: `independentDebug` 与 `testing` 模式应当永远仅用于开发与测试，请勿在生产环境使用。

#### 2. 执行 Bootstrap

`Bootstrap.run(...)` 会完成环境变量解析、日志目录与轮转策略的准备，并返回一份 `Bootstrap.Paras`：

``` swift
let paras = try await Bootstrap.run(
    mode,
    driverKeys: [FileStorageDriverKey.self],   // 要注入的驱动，可为空
    logger: Logger(label: "app")
).get()

paras.config          // Environment.Config，当前模块配置
paras.environment     // Vapor Environment
paras.eventLoopGroup  // MultiThreadedEventLoopGroup.singleton
paras.loggingFactory  // 已装配好的日志工厂，需自行决定何时 bootstrap()
```

> `Bootstrap.run` **不会**主动调用 `loggingFactory.bootstrap()`，你可以先把它与其他工厂组合、追加控制台输出策略，再统一启动日志系统。

#### 3. 构建 Tube 与 Nexus

``` swift
// 以 VaporTube 为例，任何 Tube 实现均可
let tube = try await VaporTube.make(paras).get()
let nexus = Nexus(tube: tube, bootstrap: paras)

nexus.config        // 模块配置
nexus.databases     // 该模块连接的所有 Environment.DB
nexus.logger        // 日志器
nexus.driverKeys    // 已注入的驱动列表

try await nexus.executeWithAsyncShutdown()
```

`Nexus` 初始化时会调用 `tube.config(from: self)`，把自己交给传输层保存，之后驱动便可通过 `Nexus` 的扩展方法（例如 `nexus.makeFileStorage(...)`）读取配置并初始化。

#### 4. 环境变量格式

生产环境下，`Environment.Config` 以 `WHOOSHING` 为前缀从环境变量解析，字段名全部大写并以 `_` 连接，数组以 `_COUNT` 声明长度、以 `_1`、`_2`…（从 1 开始）声明元素，嵌套结构体则继续拼接前缀：

```
WHOOSHING_ID=C59C74DC-AF7F-4497-854B-75561D9FE995
WHOOSHING_NAME=my-module
WHOOSHING_PORT=6500
WHOOSHING_HOSTNAME=127.0.0.1
WHOOSHING_DOMAIN=api.example.com            # 可选
WHOOSHING_MANAGER_URL=http://manager:6500
WHOOSHING_LOG_DIRECTORY=/var/log/whooshing

WHOOSHING_DB_SERVICES_COUNT=1
WHOOSHING_DB_SERVICES_1_NAME=default
WHOOSHING_DB_SERVICES_1_HOST=localhost
WHOOSHING_DB_SERVICES_1_PORT=5432
WHOOSHING_DB_SERVICES_1_DBS_COUNT=2
WHOOSHING_DB_SERVICES_1_DBS_1_NAME=postgres
WHOOSHING_DB_SERVICES_1_DBS_1_USER=postgres
WHOOSHING_DB_SERVICES_1_DBS_1_PASSWORD=password
WHOOSHING_DB_SERVICES_1_DBS_2_NAME=file_storage
WHOOSHING_DB_SERVICES_1_DBS_2_USER=postgres
WHOOSHING_DB_SERVICES_1_DBS_2_PASSWORD=password
WHOOSHING_DB_SERVICES_1_DBS_2_FILE_STORAGE_KEY=<base64 主密钥>   # 可选，仅文件存储数据库需要
```

各驱动的配置段落以驱动的 `label` 作为二级前缀（如 `WHOOSHING_FILE_STORAGE_DIR`），具体字段请见对应驱动的 README。解析失败时会抛出 `Environment.Errcase`（`parseFailed` / `typeIncorrect` / `missingKey`）。

数据库在 Fluent 中的 `DatabaseID` 规则为 `数据库服务名/数据库名`，例如上例中的两个数据库分别为 `default/postgres` 与 `default/file_storage`。

#### 5. 编写一个驱动

驱动通过 `Environment.DriverKey` 把自己的配置注入解析流程，并为自己申请日志轮转策略：

``` swift
import Nexus

// 1. 定义配置结构体，并实现 Environment.Template 以描述其环境变量字段
public extension Environment {
    struct MyDriverConfig: Sendable {
        public let endpoint: URL
        public let retries: Int
    }
}

extension Environment.MyDriverConfig: Environment.Template {
    public static func withEnv(dic origin: inout OrderedDictionary<String, Environment.Types>) {
        origin["endpoint"] = .url()
        origin["retries"] = .int()
    }
    
    public init(data: [String: Any], driverKeys: [any Environment.DriverKey.Type], extra: [String: Any]) {
        self.endpoint = data["endpoint"] as! URL
        self.retries = data["retries"] as! Int
    }
}

// 2. 定义 DriverKey，label 决定环境变量前缀：WHOOSHING_MY_DRIVER_ENDPOINT / WHOOSHING_MY_DRIVER_RETRIES
public enum MyDriverKey: Environment.DriverKey {
    public typealias Value = Environment.MyDriverConfig
    public static let label = "my_driver"
    public static let valueType: Environment.Types = .template(Environment.MyDriverConfig.self)
    
    public static func loggerStrategies(for directory: URL) -> [LoggerStrategy] {
        [try! .init(
            label: "my_driver",
            level: .info,
            config: .file(match: { $0.contains("mydriver") }, directory: directory.appendingPathComponent("my_driver_logs"), name: "my_driver.log")
        )]
    }
}

// 3. 为 Environment.Config 增加便捷访问器，以及独立调试模式下的伪造入口
public extension Environment.Config {
    var myDriver: Environment.MyDriverConfig { storage[MyDriverKey.self]! }
    
    func load(myDriver: Environment.MyDriverConfig?) -> Self {
        var new = self
        new.storage[MyDriverKey.self] = myDriver
        return new
    }
}
```

之后在 `Bootstrap.run(mode, driverKeys: [MyDriverKey.self], ...)` 中注册即可。

#### 6. 错误转译与调试路由

``` swift
// 把 ErrorHandle 体系的错误转为 Vapor AbortError：
//   .external(suggestions:userdata:) -> 以 userdata 中的 HTTPResponseStatus 为状态码(默认 400)，并附上 suggestions
//   .internal / .inherit           -> 500，隐藏内部细节
let abort: AbortError = someErr.vaporlized

// 作为路由末端中间件统一处理
app.middleware.use(RouteEndErrorHandler())

// 从 URL 参数中安全提取并转换值
let id: UUID = try parameter("moduleId", from: req) { UUID(uuidString: $0) }

// 独立调试时，用白名单模拟 Manager 的模块校验 API：
//   GET /modules                    -> 所有允许的模块 ID
//   GET /modules/:moduleId/verify   -> { "allowed": Bool }
try app.register(collection: DebugingModuleController(serviceIds: [UUID(), UUID()]))
```

-------

### 运行环境

* **macOS** (> 13.0)
* **iOS** (> 16.0)
* **Linux** (> 20)
* **Swift** (> 6.0)
* **watchOS** (> 6.0) **[未测试]**
* **tvOS** (> 13) **[未测试]**

-------

### 注意事项

- `Bootstrap.run` 在 `swift test` 下会自动清理 SPM 注入的 `--test-*` 参数，避免 Vapor 误解析；若使用 `.testing` 环境则**必须**提供调试配置，否则触发 `fatalError`。
- 数据库的 `Environment.DB.config` 用于生产连接；`testingConfig` 仅供测试使用，它会读取 `GITHUB_PG_TESTING_HOST` 环境变量以适配 CI 中的 docker 网络。
- 日志目录若未在独立调试配置中指定，将默认创建于 `~/whooshing_logs/<模块名>_logs`。
- 通过 `storage[SomeDriverKey.self]!` 访问未注册的驱动配置会导致崩溃，请确保驱动已在 `driverKeys` 中注册，或在独立调试模式下通过 `.load(...)` 伪造。

如需了解更多，请参阅模块内的源码注释与文档说明。

------

### 联系与反馈

如有使用问题或建议，请通过 [GitHub Issues](https://github.com/whooshing-workshop/whooshing.nexus/issues) 提交反馈。

或发至邮箱 [contact@official.whooshings.space](mailto:contact@official.whooshings.space)
