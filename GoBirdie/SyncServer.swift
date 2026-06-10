import Foundation
import MultipeerConnectivity
import Network
import OSLog
import GoBirdieCore

private let logger = Logger(subsystem: "com.gobirdie", category: "SyncServer")
let SYNC_PORT: UInt16 = 7743

final class SyncServer: NSObject {
    private let roundStore: RoundStore
    private let serviceType = "gobirdie"
    private var peerID: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?
    private var isAdvertising = false
    var onStateChange: (@Sendable (Bool) -> Void)?

    // HTTP + mDNS for Windows / cross-platform sync
    private var httpListener: NWListener?
    private var nwAdvertiser: NWListener?
    private var mdnsBrowser: NWBrowser?

    init(roundStore: RoundStore) {
        self.roundStore = roundStore
        super.init()
    }

    func start() {
        logger.info("start() called")
        guard advertiser == nil else {
            logger.info("already running, skipping")
            return
        }
        let peer = MCPeerID(displayName: UIDevice.current.name)
        peerID = peer

        let sess = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .none)
        sess.delegate = self
        session = sess

        let adv = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: serviceType)
        adv.delegate = self
        advertiser = adv

        adv.startAdvertisingPeer()
        isAdvertising = true
        logger.info("Advertising as \(peer.displayName)")

        startHTTPServer()
        onStateChange?(true)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        peerID = nil
        isAdvertising = false
        stopHTTPServer()
        logger.info("Stopped")
        onStateChange?(false)
    }

    // MARK: - HTTP Server (cross-platform WiFi sync)

    private func startHTTPServer() {
        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: SYNC_PORT)!)

            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .global(qos: .userInitiated))
                self?.handleHTTPConnection(connection)
            }

            // Advertise as _gobirdie._tcp via NWListener's built-in Bonjour
            listener.service = NWListener.Service(
                name: UIDevice.current.name,
                type: "_gobirdie._tcp"
            )

            listener.start(queue: .global(qos: .userInitiated))
            httpListener = listener
            logger.info("HTTP sync server started on port \(SYNC_PORT)")
        } catch {
            logger.error("Failed to start HTTP server: \(error)")
        }
    }

    private func stopHTTPServer() {
        httpListener?.cancel()
        httpListener = nil
    }

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { return }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            guard parts.count >= 2 else { return }
            let path = parts[1]

            let (status, body) = self.handleHTTPRequest(path: path)
            let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
            let responseData = response.data(using: .utf8)! + body
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func handleHTTPRequest(path: String) -> (String, Data) {
        if path == "/api/rounds" {
            return ("200 OK", buildRoundList())
        }
        if path.hasPrefix("/api/rounds/") {
            let id = String(path.dropFirst("/api/rounds/".count))
            let data = buildRound(id: id)
            return data.isEmpty ? ("404 Not Found", Data("[]".utf8)) : ("200 OK", data)
        }
        return ("404 Not Found", Data("[]".utf8))
    }

    // MARK: - Request handling (MultipeerConnectivity)

    private func handleRequest(_ message: String, from peer: MCPeerID) {
        logger.debug("Request from \(peer.displayName): \(message)")

        let data: Data
        if message == "list" {
            data = buildRoundList()
        } else if message.hasPrefix("round:") {
            let id = String(message.dropFirst("round:".count))
            data = buildRound(id: id)
        } else {
            logger.warning("Unknown request: \(message)")
            return
        }

        do {
            try session?.send(data, toPeers: [peer], with: .reliable)
        } catch {
            logger.error("Failed to send response: \(error)")
        }
    }

    private func buildRoundList() -> Data {
        let rounds = (try? roundStore.loadAll()) ?? []
        let summaries: [[String: Any]] = rounds.compactMap { r in
            guard r.endedAt != nil else { return nil }
            return [
                "id":            r.id,
                "source":        r.source,
                "course_name":   r.courseName,
                "started_at":    iso8601(r.startedAt),
                "ended_at":      r.endedAt.map { iso8601($0) } as Any,
                "holes_played":  r.holesPlayed,
                "total_strokes": r.totalStrokes,
                "total_putts":   r.totalPutts,
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: summaries)) ?? Data()
    }

    private func buildRound(id: String) -> Data {
        guard let round = try? roundStore.load(id: id) else { return Data() }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(round)) ?? Data()
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension SyncServer: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("Invitation from \(peerID.displayName) — accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logger.error("Failed to advertise: \(error)")
        isAdvertising = false
        onStateChange?(false)
    }
}

// MARK: - MCSessionDelegate

extension SyncServer: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let label = switch state {
        case .notConnected: "disconnected"
        case .connecting:   "connecting"
        case .connected:    "connected"
        @unknown default:   "unknown"
        }
        logger.info("Peer \(peerID.displayName) \(label)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        handleRequest(message, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
