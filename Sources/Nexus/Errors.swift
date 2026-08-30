import ErrorHandle
import NIOAdvanced

@frozen
public enum NexusErrcase: String, ErrList, Sendable {
    case environmentFailed = "环境变量配置失败"
    case loggingSystemFailed = "初始化日志系统失败"
    case vaporAppCreateFailed = "Vapor App 创建失败"
    case serviceInitFailed = "服务初始化配置失败"
    case executionFailed = "运行时出错，错误未被处理"
    case shutdownFailed = "关闭服务时出错"
    case apiValidateFailed = "用户身份验证失败"
}

public extension Error {
    var vaporlized: AbortError {
        return errorInterpret(error: self)
        
        @Sendable
        func errorInterpret<T: Error>(error: T) -> AbortError {
            if let err = error as? any Err {
                let reason = String(describing: err.error.rawValue) + (err.explain == nil ? "" : ", " + err.explain!)
                
                switch err.category {
                case .external(suggestions: let suggestions, let userdata):
                    let status: HTTPResponseStatus
                    if let s = userdata?.value as? HTTPResponseStatus {
                        status = s
                    } else {
                        status = .badRequest
                    }
                    // Abort init 存在 bug，suggestedFixes 未正确录入到实例中，只好将 suggestions 追加到 reason 中
                    return Abort(
                        status,
                        reason: reason + "; " + suggestions.joined(separator: "; "),
                        identifier: err.error.identifier,
                        suggestedFixes: [suggestions.joined(separator: "; ")],
                        file: err.file,
                        function: err.function,
                        line: .init(err.line)
                    )
                case .inherit:
                    if let subError = err.subError {
                        return errorInterpret(error: subError)
                    }
                    
                    fallthrough
                case .internal:
                    // Abort init 存在 bug，suggestedFixes 未正确录入到实例中，只好将 suggestions 追加到 reason 中
                    return Abort(
                        .internalServerError,
                        reason: "服务器内部错误, 请联系管理员以解决该错误",
                        identifier: err.error.identifier,
                        suggestedFixes: ["请联系管理员以解决该错误"],
                        file: err.file,
                        function: err.function,
                        line: .init(err.line)
                    )
                case .none: fatalError("错误处理系统异常")
                }
            } else if let err = error as? AbortError {
                return err
            } else {
                // Abort init 存在 bug，suggestedFixes 未正确录入到实例中，只好将 suggestions 追加到 reason 中
                return Abort(
                    .internalServerError,
                    reason: "服务器内部错误, 请联系管理员以解决该错误",
                    identifier: "Unknown",
                    suggestedFixes: ["请联系管理员以解决该错误"]
                )
            }
        }
    }
}

public extension EventLoopResult {
    var vaporlized: EventLoopFuture<Value> {
        return self.wrapped.flatMapErrorThrowing { error in
            throw error.vaporlized
        }
    }
}
