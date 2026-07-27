@preconcurrency import Foundation
import ThermalIconCore

@MainActor
final class FanHelperClient {
    enum ClientError: LocalizedError {
        case proxyUnavailable
        case helper(String)

        var errorDescription: String? {
            switch self {
            case .proxyUnavailable: "Unable to connect to fan helper"
            case let .helper(message): message
            }
        }
    }

    private var connection: NSXPCConnection?
    var connectionLostHandler: (() -> Void)?
    var isConnected: Bool { connection != nil }

    func getStatus(completion: @escaping (Result<FanControlStatus, Error>) -> Void) {
        do {
            let proxy = try remoteProxy(errorHandler: completion)
            proxy.getStatus { data, message in
                DispatchQueue.main.async {
                    do {
                        guard let data, message == nil else {
                            throw ClientError.helper(message ?? "Fan status unavailable")
                        }
                        completion(.success(try FanStatusCodec.decodeValidated(data)))
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func setMode(
        _ mode: FanControlMode,
        hotThreshold: Double,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) { proxy, reply in
            proxy.setMode(
                mode: mode.rawValue,
                hotThreshold: hotThreshold,
                reply: reply
            )
        }
    }

    func disconnect() {
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }

    private func perform(
        completion: @escaping (Result<Void, Error>) -> Void,
        request: (FanHelperProtocol, @escaping (Bool, String?) -> Void) -> Void
    ) {
        do {
            let proxy = try remoteProxy(errorHandler: completion)
            request(proxy) { success, message in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(ClientError.helper(message ?? "Fan command failed")))
                    }
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func remoteProxy<T>(
        errorHandler: @escaping (Result<T, Error>) -> Void
    ) throws -> FanHelperProtocol {
        let connection = try connectionForRequest()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            DispatchQueue.main.async {
                errorHandler(.failure(error))
            }
        }) as? FanHelperProtocol else {
            throw ClientError.proxyUnavailable
        }
        return proxy
    }

    private func connectionForRequest() throws -> NSXPCConnection {
        if let connection { return connection }

        let teamID = try CurrentCodeSignature.teamIdentifier()
        let requirement = try CodeSigningRequirement(
            identifier: fanHelperBundleIdentifier,
            teamID: teamID
        ).text
        let connection = NSXPCConnection(
            machServiceName: fanHelperMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let connection else { return }
            DispatchQueue.main.async {
                self?.handleConnectionLoss(connection)
            }
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let connection else { return }
            DispatchQueue.main.async {
                self?.handleConnectionLoss(connection)
            }
        }
        self.connection = connection
        connection.activate()
        return connection
    }

    private func handleConnectionLoss(_ lostConnection: NSXPCConnection) {
        guard connection === lostConnection else { return }
        lostConnection.interruptionHandler = nil
        lostConnection.invalidationHandler = nil
        lostConnection.invalidate()
        connection = nil
        connectionLostHandler?()
    }
}
