import ErrorHandle

@frozen
public enum NexusErrcase: String, ErrList, Sendable {
    case environmentFailed = "环境变量配置失败"
    case loggingSystemFailed = "初始化日志系统失败"
    case vaporAppCreateFailed = "Vapor App 创建失败"
    case serviceInitFailed = "服务初始化配置失败"
    case executionFailed = "运行时出错，错误未被处理"
    case shutdownFailed = "关闭服务时出错"
}
