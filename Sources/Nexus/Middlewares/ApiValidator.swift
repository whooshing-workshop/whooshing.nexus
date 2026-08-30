import Vapor
import Cryptos
import LoggingAdvanced
import NIOFoundationEssentialsCompat

/// 用于对用户口令验证
///
/// 当有用户请求发起时，该 Middleware 负责将其凭据及Token 转发与认证模块
/// 若认证模块认证通过，则得到用户的具体信息及其解密的密钥(该密钥目前没有用处)
/// 若认证未通过，则拒绝连接
///
/// 该中间件提供了调试模式
/// 通过将 Strategy 指定为 debuging 以使用白名单验证而非认证服务验证
/// 白名单验证需提供所有允许用户的凭据及Token (Token 为 SymmKey 加密密钥自己加密自己的密文 base64)
public struct ApiValidator: AsyncMiddleware {
    /// 调试模式配置策略
    public enum Strategy: Sendable, Loggerable {
        /// 正常生产模式：全部走远程认证
        case normal(authURL: URL)
        /// 调试白名单模式：校验 (credential, token) 键值对
        case debuging(
            whitelist: [String: SendableSymmKey] // [Credential: Token]
        )
        
        public var logDescription: String {
            switch self {
            case .normal(authURL: let url): ".normal(authURL: \(url)"
            case .debuging(whitelist: let whitelist): ".debuging(whitelist: [\(whitelist.count) Entries])"
            }
        }
    }

    /// 当前功能模块的 Module ID
    let moduleID: UUID
    /// 验证策略
    let strategy: Strategy

    // 不直接提供 init(moduleID: strategy:) 是为了避免开发者任意传参
    public init<T>(
        from nexus: Nexus<T>
    ) {
        self.strategy = nexus.config.apiStrategy
        self.moduleID = nexus.config.id
    }

    public func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        try await run(to: request, chainingTo: next)
    }
    
    public func run(to request: Request, chainingTo next: AsyncResponder) async throws(NexusErrcase.ErrType) -> Response {
        guard let credential = request.headers.first(name: "X-Credential"), !credential.isEmpty else {
            throw NexusErrcase.apiValidateFailed.d("未找到 'X-Credential' 请求头", category: .external(suggestions: ["请提供用户登陆身份"], userdata: .init(HTTPResponseStatus.unauthorized)))
        }

        guard let tokenEncrypted = request.headers.first(name: "X-Encrypted-Token"), !tokenEncrypted.isEmpty else {
            throw NexusErrcase.apiValidateFailed.d("未找到 'X-Encrypted-Token' 请求头", category: .external(suggestions: ["请提供用户的加密 Token"], userdata: .init(HTTPResponseStatus.unauthorized)))
        }
        
        let logger = request.logger.derive(metadata: ["credential": .string(credential)])
        logger.info("正在进行 API 用户身份验证")
        logger.debug("用户身份", metadata: ["token_encrypted": .string(tokenEncrypted)])
        
        let buffer: ByteBuffer

        switch strategy {
        case .normal(authURL: let authURL):
            let payload = AuthExchangeData(
                credential: credential,
                tokenEncrypted: tokenEncrypted
            )
            
            let uri = URI(string: authURL.appending(components: "inline", "authenticate").absoluteString)
            logger.info("向身份认证模块请求认证", metadata: ["auth_url": .stringConvertible(uri), "module_id": .summaryData(moduleID)])
            logger.debug("完整模块 ID", metadata: ["module_id": .data(moduleID)])
            
            let clientResponse: ClientResponse
            do {
                clientResponse = try await request.client.post(uri) { clientReq in
                    clientReq.headers.replaceOrAdd(name: "X-Module-ID", value: moduleID.uuidString)
                    try clientReq.content.encode(payload, as: .json)
                }
            } catch {
                request.logger.error("身份认证模块不可及: \(error)")
                throw NexusErrcase.apiValidateFailed.d("身份认证模块不可及", category: .external(suggestions: ["请稍后再试"], userdata: .init(HTTPResponseStatus.serviceUnavailable)))
            }
            
            logger.debug("认证模块详细相应", metadata: ["response": .stringConvertible(clientResponse)])
            guard clientResponse.status == .ok else {
                var suggestions: [String] = ["请提供正确的用户凭据及加密 Token"]
                if
                    let encryptedData = try? tokenEncrypted.dataRes.get(),
                    let possibleToken = try? Crypto.Symm.encrypt(Crypto.hash(encryptedData), key: .init(data: encryptedData)).get().base64EncodedString()
                {
                    suggestions.append("可能是由于提供的 Token 为未加密格式，尝试加密格式: \(possibleToken)")
                }
                
                throw NexusErrcase.apiValidateFailed.d("身份不合法: 状态码 \(clientResponse.status.code)", category: .external(suggestions: suggestions, userdata: .init(HTTPResponseStatus.unauthorized)))
            }
            
            guard let b = clientResponse.body else {
                throw NexusErrcase.apiValidateFailed.d("本服务认证服务响应异常，未成功从响应体解析 ByteBuffer", category: .internal)
            }
            
            buffer = b
            
        case .debuging(whitelist: let whitelist):
            logger.info("[Debug] 从白名单认证用户")
            
            if let token = whitelist[credential] {
                (_, buffer) = try debugTokenAuth(with: token.data, encrypted: tokenEncrypted, credential: credential)
                logger.warning("[Debug] 凭据与 Token 命中白名单，跳过远程认证直接放行")
            } else {
                logger.warning("[Debug] 凭据或 Token 不在白名单中/不匹配，调试模式拒绝访问")
                throw NexusErrcase.apiValidateFailed.d("[Debug] 凭据或 Token 未在白名单中", category: .external(suggestions: ["请提供在 Debug 白名单中的用户凭据和加密 Token"], userdata: .init(HTTPResponseStatus.forbidden)))
            }
        }
        
        logger.info("成功取得用户身份信息，身份合法", metadata: ["buffer_byte_count": .stringConvertible(buffer.readableBytes)])
        logger.debug("用户身份信息", metadata: ["buffer": .stringConvertible(buffer)])
        
        request.storage[ApiAuthDataKey.self] = buffer
        
        return try await required(throws: NexusErrcase.executionFailed, category: .inherit) {
            try await next.respond(to: request)
        }
    }
    
    /// 验证一个加密过后的用户密钥(encrypted)是否是由原密钥(origin)加密且 Hash 得来的
    /// 加密算法为 [origin 加密[origin hashed]] = encrypted
    ///
    /// - Parameters
    ///   - origin: 原用户密钥，为 256 bit(64 bytes) 数据的 base64 编码的字符串
    ///   - encrypted: 加密后的用户密钥
    /// - Returns
    ///   若 encrypted 确为 origin 加密得到的，则返回原用户密钥
    /// - Throws
    ///   若 encrypted 并非为 origin 加密得到的，则抛出错误 "用户口令不正确"
    @inlinable
    func debugTokenAuth(with origin: Data, encrypted: String, credential: String) throws(NexusErrcase.ErrType)  -> (SendableSymmKey, ByteBuffer) {
        let key = SendableSymmKey(key: .init(data: origin))
        
        let encryptedData = try required(throws: NexusErrcase.apiValidateFailed, "用户 Token 非合法 base64 字符串", category: .external(suggestions: ["请提供正确的用户加密 Token 的 base64 字符串"], userdata: .init(HTTPResponseStatus.badRequest))) {
            try Base64String(encrypted).dataRes.get()
        }
        
        let authData: Data
        do {
            authData = try Crypto.Symm.decrypt(encryptedData, key: key.key).get()
        } catch {
            var suggestions: [String] = ["请提供正确的 Token"]
            if let possibleToken = try? Crypto.Symm.encrypt(Crypto.hash(encryptedData), key: .init(data: encryptedData)).get().base64EncodedString() {
                suggestions.append("可能是由于提供的 Token 为未加密格式，尝试加密格式: \(possibleToken)")
            }
            
            throw NexusErrcase.apiValidateFailed.d("[Debug] 所提供的 Token 无法解析", category: .external(suggestions: suggestions))
        }
        
        let keyHashed = Crypto.hash(origin)
        guard keyHashed == authData else { throw NexusErrcase.apiValidateFailed.d("[Debug] 用户 Token 不正确", category: .external(suggestions: ["请提供正确的 Token"])) }
        let rawData: [String: AnyCodable] = [
            "key": AnyCodable(key),
            "token": AnyCodable(Generator.fakeTokenData(credential: credential, token: encrypted))
        ]
        var buffer = ByteBuffer()
        try required(throws: NexusErrcase.apiValidateFailed, "[Debug] 登陆信息 Json 转码失败", category: .internal) {
            try JSONEncoder().encode(rawData, into: &buffer)
        }
        return (key, buffer)
    }
}

/// 记录用户的认证信息，用于之后的认证验证机制
@frozen
public struct AuthExchangeData: Content {
    /// 用户凭据
    public let credential: String
    /// 加密后的用户口令
    public let tokenEncrypted: String
    
    enum CodingKeys: String, CodingKey {
        case credential
        case tokenEncrypted = "token_encrypted"
    }
}

public struct ApiAuthDataKey: StorageKey {
    public typealias Value = ByteBuffer
}

public extension Request {
    var apiAuthData: ByteBuffer { self.storage[ApiAuthDataKey.self]! }
}
