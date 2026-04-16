import Foundation
import MultipeerConnectivity
import OSLog
import GoBirdieCore

private let logger = Logger(subsystem: "com.gobirdie", category: "SyncServer")

final class SyncServer: NSObject {
    private let roundStore: RoundStore
    private let serviceType = "gobirdie"
    private var peerID: MCPeerID?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var session: MCSession?
    private var isAdvertising = false
    var onStateChange: (@Sendable (Bool) -> Void)?

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
        onStateChange?(true)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session?.disconnect()
        session = nil
        peerID = nil
        isAdvertising = false
        logger.info("Stopped")
        onStateChange?(false)
    }

    // MARK: - Request handling

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
