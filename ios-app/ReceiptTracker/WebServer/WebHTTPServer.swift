import Foundation
import Network

/// Minimal HTTP/1.1 server on a TCP port (same approach as AnyPlay Drive's
/// `WiFiUploadServer`: `NWListener`, one request per connection). It only
/// moves bytes — what each request does is decided by `handler`.
final class WebHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    enum State: Equatable, Sendable {
        case ready
        case failed(String)
        case stopped
    }

    let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "ReceiptTracker.WebHTTPServer")
    private var listener: NWListener?

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    /// `onStateChange` is called on the main queue.
    func start(onStateChange: @escaping @Sendable @MainActor (State) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.stateUpdateHandler = { state in
            let mapped: State?
            switch state {
            case .ready: mapped = .ready
            case .failed(let error): mapped = .failed(error.localizedDescription)
            case .cancelled: mapped = .stopped
            default: mapped = nil
            }
            if let mapped {
                Task { @MainActor in onStateChange(mapped) }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPRequestParser.parse(buffer) {
            case .complete(let request):
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    self.send(response, on: connection)
                }
            case .tooLarge:
                self.send(.error("File is too large", status: 413), on: connection)
            case .invalid:
                self.send(.error("Bad request", status: 400), on: connection)
            case .incomplete:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    self.receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
