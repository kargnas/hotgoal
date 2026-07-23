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

    func getFanStatus(completion: @escaping (Result<[FanSnapshot], Error>) -> Void) {
        do {
            let proxy = try remoteProxy(errorHandler: completion)
            proxy.getFanStatus { data, message in
                DispatchQueue.main.async {
                    do {
                        guard let data, message == nil else {
                            throw ClientError.helper(message ?? "Fan status unavailable")
                        }
                        completion(.success(try FanPayloadCodec.decodeValidated(data)))
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
        thresholds: TemperatureThresholds,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        perform(completion: completion) { proxy, reply in
            proxy.setMode(
                mode: mode.rawValue,
                warmThreshold: thresholds.warm,
                hotThreshold: thresholds.hot,
                reply: reply
            )
        }
    }

    func restoreAutomatic(completion: @escaping (Result<Void, Error>) -> Void) {
        perform(completion: completion) { proxy, reply in
            proxy.restoreAutomatic(reply: reply)
        }
    }

    func disconnect() {
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
        connection.activate()
        self.connection = connection
        return connection
    }
}
