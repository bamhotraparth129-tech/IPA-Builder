import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

// MARK: - Procedural Sound FX

enum SoundEffectKind {
    case mine
    case place
    case jump
    case hurt
    case portal
    case explode
    case hitMob
    case eat
    case pickup
    case piston
    case arrow
}

final class SoundEngine {
    static let shared = SoundEngine()
    private var players: [AVAudioPlayer] = []

    func play(_ kind: SoundEffectKind) {
        let freq: Double
        let duration: Double
        let amplitude: Float

        switch kind {
        case .mine: (freq, duration, amplitude) = (165, 0.07, 0.16)
        case .place: (freq, duration, amplitude) = (260, 0.06, 0.14)
        case .jump: (freq, duration, amplitude) = (340, 0.08, 0.12)
        case .hurt: (freq, duration, amplitude) = (120, 0.14, 0.22)
        case .portal: (freq, duration, amplitude) = (520, 0.22, 0.16)
        case .explode: (freq, duration, amplitude) = (75, 0.25, 0.28)
        case .hitMob: (freq, duration, amplitude) = (210, 0.09, 0.18)
        case .eat: (freq, duration, amplitude) = (410, 0.08, 0.14)
        case .pickup: (freq, duration, amplitude) = (640, 0.05, 0.12)
        case .piston: (freq, duration, amplitude) = (145, 0.10, 0.16)
        case .arrow: (freq, duration, amplitude) = (780, 0.05, 0.10)
        }

        let sampleRate: Double = 22050
        let frameCount = Int(sampleRate * duration)
        var pcmData = Data(capacity: frameCount * 2)

        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            let env = Float(1.0 - (t / duration))
            let wave: Float
            if kind == .explode || kind == .mine || kind == .piston {
                let pseudoNoise = sin(t * 4913.0) * cos(t * 7919.0)
                wave = Float(pseudoNoise * 0.65 + sin(2.0 * .pi * freq * t) * 0.35)
            } else {
                wave = Float(sin(2.0 * .pi * freq * t))
            }
            var sample = Int16(max(-1.0, min(1.0, wave * amplitude * env)) * Float(Int16.max))
            withUnsafeBytes(of: &sample) { pcmData.append(contentsOf: $0) }
        }

        let wav = makeWAV(pcm: pcmData, sampleRate: Int(sampleRate))
        if let player = try? AVAudioPlayer(data: wav) {
            player.prepareToPlay()
            player.play()
            players.append(player)
            players.removeAll { !$0.isPlaying }
        }
    }

    private func makeWAV(pcm: Data, sampleRate: Int) -> Data {
        var data = Data()
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcm.count)
        let chunkSize = 36 + dataSize

        data.append("RIFF".data(using: .ascii)!)
        data.append(u32LE(chunkSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(u32LE(16))
        data.append(u16LE(1))
        data.append(u16LE(channels))
        data.append(u32LE(UInt32(sampleRate)))
        data.append(u32LE(byteRate))
        data.append(u16LE(blockAlign))
        data.append(u16LE(bitsPerSample))
        data.append("data".data(using: .ascii)!)
        data.append(u32LE(dataSize))
        data.append(pcm)
        return data
    }

    private func u16LE(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 2)
    }

    private func u32LE(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }
}

// MARK: - Local LAN Multiplayer Manager

final class LANMultiplayerManager: NSObject, ObservableObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    @Published var connectedPeers: [String] = []
    @Published var isActive: Bool = false

    private let serviceType = "minerva-voxel"
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    var onReceivePayload: ((Data) -> Void)?

    func setEnabled(_ enabled: Bool) {
        isActive = enabled
        if enabled {
            let s = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
            s.delegate = self
            self.session = s

            let adv = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
            adv.delegate = self
            adv.startAdvertisingPeer()
            self.advertiser = adv

            let brw = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
            brw.delegate = self
            brw.startBrowsingForPeers()
            self.browser = brw
        } else {
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            session?.disconnect()
            advertiser = nil
            browser = nil
            session = nil
            DispatchQueue.main.async { self.connectedPeers = [] }
        }
    }

    func send(_ payload: [String: Any]) {
        guard isActive, let session, !session.connectedPeers.isEmpty else { return }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers.map { $0.displayName }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.onReceivePayload?(data)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        guard let session else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

// MARK: - Procedural 16x16 Pixel Texture Generator

enum PixelTextureKind: Hashable {
    case grassTop, grassSide, snowGrassSide, snow, dirt, stone, cobblestone, mossyCobble, stoneBricks, bricks, sandstone, bedrock
    case coalOre, ironOre, goldOre, diamondOre, emeraldOre, redstoneOre, quartzOre
    case woodSide, woodTop, spruceSide, birchSide, planks, sprucePlanks, birchPlanks, craftingTop, furnaceSide, bookshelfSide, bedTop, wool, clay, ice, leaves, crop, sand, glass, water
    case torch, soulTorch, seaLantern, amethyst, redstoneDust, lever, piston, door, chest, tnt, portal, cloud
    case netherrack, soulSand, glowstone, magma, endStone, obsidian, endCrystal
}

enum PixelTextureFactory {
    private static var cache: [PixelTextureKind: UIImage] = [:]

    static func image(for kind: PixelTextureKind) -> UIImage {
        if let cached = cache[kind] { return cached }
        let generated = render16x16(kind: kind)
        cache[kind] = generated
        return generated
    }

    private static func noise(x: Int, y: Int, seed: Int) -> Int {
        var n = x &* 374761393 &+ y &* 668265263 &+ seed &* 1442695041
        n = (n ^ (n >> 13)) &* 1274126177
        return abs((n ^ (n >> 16)) % 100)
    }

    private static func isOreCluster(x: Int, y: Int, seed: Int) -> Bool {
        let spots: [(Int, Int)] = [(3, 3), (4, 3), (3, 4), (10, 4), (11, 4), (10, 5), (11, 5), (6, 10), (7, 10), (6, 11), (12, 12), (13, 12)]
        for (sx, sy) in spots where x == sx && y == sy { return true }
        return noise(x: x, y: y, seed: seed) < 6
    }

    private static func render16x16(kind: PixelTextureKind) -> UIImage {
        let size = 16
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = ![.glass, .water, .torch, .soulTorch, .cloud, .ice, .redstoneDust, .portal, .lever, .crop].contains(kind)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setAllowsAntialiasing(false)
            cg.interpolationQuality = .none

            for y in 0..<size {
                for x in 0..<size {
                    let color = pixelColor(kind: kind, x: x, y: y)
                    cg.setFillColor(color.cgColor)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
    }

    private static func pixelColor(kind: PixelTextureKind, x: Int, y: Int) -> UIColor {
        switch kind {
        case .grassTop:
            let n = noise(x: x, y: y, seed: 11)
            if n < 22 { return UIColor(red: 0.24, green: 0.58, blue: 0.18, alpha: 1.0) }
            if n < 68 { return UIColor(red: 0.32, green: 0.70, blue: 0.24, alpha: 1.0) }
            if n < 90 { return UIColor(red: 0.39, green: 0.77, blue: 0.29, alpha: 1.0) }
            return UIColor(red: 0.45, green: 0.82, blue: 0.33, alpha: 1.0)
        case .grassSide:
            let grassDepth = 3 + (noise(x: x, y: 0, seed: 19) % 3)
            if y < grassDepth {
                let g = noise(x: x, y: y, seed: 23)
                if g < 35 { return UIColor(red: 0.25, green: 0.59, blue: 0.19, alpha: 1.0) }
                if g < 80 { return UIColor(red: 0.33, green: 0.71, blue: 0.25, alpha: 1.0) }
                return UIColor(red: 0.40, green: 0.78, blue: 0.30, alpha: 1.0)
            } else if y == grassDepth {
                return UIColor(red: 0.34, green: 0.21, blue: 0.11, alpha: 1.0)
            } else {
                return pixelColor(kind: .dirt, x: x, y: y)
            }
        case .snowGrassSide:
            return y < 3 + (noise(x: x, y: 0, seed: 29) % 2) ? pixelColor(kind: .snow, x: x, y: y) : pixelColor(kind: .dirt, x: x, y: y)
        case .snow:
            let n = noise(x: x, y: y, seed: 37)
            if n < 25 { return UIColor(red: 0.84, green: 0.90, blue: 0.96, alpha: 1.0) }
            if n < 78 { return UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0) }
            return UIColor(red: 0.99, green: 1.0, blue: 1.0, alpha: 1.0)
        case .dirt:
            let n = noise(x: x, y: y, seed: 31)
            if n < 18 { return UIColor(red: 0.39, green: 0.25, blue: 0.13, alpha: 1.0) }
            if n < 65 { return UIColor(red: 0.48, green: 0.31, blue: 0.17, alpha: 1.0) }
            if n < 90 { return UIColor(red: 0.55, green: 0.36, blue: 0.21, alpha: 1.0) }
            return UIColor(red: 0.44, green: 0.42, blue: 0.40, alpha: 1.0)
        case .stone:
            let band = (y / 3 + (x / 5)) % 2
            let n = noise(x: x, y: y, seed: 47)
            if n < 16 { return UIColor(red: 0.34, green: 0.36, blue: 0.39, alpha: 1.0) }
            if n < 52 { return band == 0 ? UIColor(red: 0.44, green: 0.46, blue: 0.49, alpha: 1.0) : UIColor(red: 0.47, green: 0.49, blue: 0.52, alpha: 1.0) }
            if n < 85 { return UIColor(red: 0.52, green: 0.54, blue: 0.57, alpha: 1.0) }
            return UIColor(red: 0.59, green: 0.61, blue: 0.64, alpha: 1.0)
        case .cobblestone:
            let row = y / 4
            let offsetX = (row % 2 == 0) ? 0 : 2
            let chunkX = (x + offsetX) / 4
            let localX = (x + offsetX) % 4
            let localY = y % 4
            let n = noise(x: x, y: y, seed: 53)
            if localY == 3 || (localX == 0 && (row + chunkX) % 2 == 0) { return UIColor(red: 0.23, green: 0.24, blue: 0.26, alpha: 1.0) }
            if localY == 0 { return UIColor(red: 0.58, green: 0.60, blue: 0.63, alpha: 1.0) }
            if n < 30 { return UIColor(red: 0.36, green: 0.38, blue: 0.41, alpha: 1.0) }
            if n < 75 { return UIColor(red: 0.46, green: 0.48, blue: 0.51, alpha: 1.0) }
            return UIColor(red: 0.54, green: 0.56, blue: 0.59, alpha: 1.0)
        case .mossyCobble:
            if noise(x: x, y: y, seed: 57) < (y < 9 ? 45 : 18) {
                return noise(x: x, y: y, seed: 58) < 50 ? UIColor(red: 0.20, green: 0.48, blue: 0.16, alpha: 1.0) : UIColor(red: 0.30, green: 0.62, blue: 0.22, alpha: 1.0)
            }
            return pixelColor(kind: .cobblestone, x: x, y: y)
        case .stoneBricks:
            let row = y / 4
            let shiftedX = (x + (row % 2 == 0 ? 0 : 4)) % 16
            if y % 4 == 3 || shiftedX % 8 == 0 { return UIColor(red: 0.28, green: 0.29, blue: 0.32, alpha: 1.0) }
            return noise(x: x, y: y, seed: 63) < 45 ? UIColor(red: 0.47, green: 0.49, blue: 0.52, alpha: 1.0) : UIColor(red: 0.54, green: 0.56, blue: 0.59, alpha: 1.0)
        case .bricks:
            let row = y / 4
            let shiftedX = (x + (row % 2 == 0 ? 0 : 4)) % 16
            if y % 4 == 3 || shiftedX % 8 == 0 { return UIColor(red: 0.76, green: 0.73, blue: 0.68, alpha: 1.0) }
            return noise(x: x, y: y, seed: 69) < 50 ? UIColor(red: 0.62, green: 0.25, blue: 0.19, alpha: 1.0) : UIColor(red: 0.72, green: 0.31, blue: 0.24, alpha: 1.0)
        case .sandstone:
            let n = noise(x: x, y: y, seed: 79)
            if y == 0 || y == 1 { return UIColor(red: 0.92, green: 0.85, blue: 0.60, alpha: 1.0) }
            if y >= 13 { return UIColor(red: 0.74, green: 0.66, blue: 0.42, alpha: 1.0) }
            return n < 50 ? UIColor(red: 0.85, green: 0.77, blue: 0.52, alpha: 1.0) : UIColor(red: 0.89, green: 0.81, blue: 0.56, alpha: 1.0)
        case .bedrock:
            let n = noise(x: x, y: y, seed: 83)
            if n < 25 { return UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0) }
            if n < 65 { return UIColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0) }
            return UIColor(red: 0.38, green: 0.38, blue: 0.41, alpha: 1.0)
        case .coalOre:
            return isOreCluster(x: x, y: y, seed: 59) ? (noise(x: x, y: y, seed: 60) < 40 ? UIColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0) : UIColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .ironOre:
            return isOreCluster(x: x, y: y, seed: 67) ? (noise(x: x, y: y, seed: 68) < 45 ? UIColor(red: 0.72, green: 0.56, blue: 0.44, alpha: 1.0) : UIColor(red: 0.84, green: 0.69, blue: 0.57, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .goldOre:
            return isOreCluster(x: x, y: y, seed: 71) ? (noise(x: x, y: y, seed: 72) < 45 ? UIColor(red: 0.88, green: 0.74, blue: 0.14, alpha: 1.0) : UIColor(red: 0.99, green: 0.88, blue: 0.28, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .diamondOre:
            return isOreCluster(x: x, y: y, seed: 77) ? (noise(x: x, y: y, seed: 78) < 50 ? UIColor(red: 0.24, green: 0.86, blue: 0.92, alpha: 1.0) : UIColor(red: 0.65, green: 0.98, blue: 1.0, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .emeraldOre:
            return isOreCluster(x: x, y: y, seed: 81) ? (noise(x: x, y: y, seed: 82) < 50 ? UIColor(red: 0.12, green: 0.78, blue: 0.34, alpha: 1.0) : UIColor(red: 0.45, green: 0.96, blue: 0.62, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .redstoneOre:
            return isOreCluster(x: x, y: y, seed: 85) ? (noise(x: x, y: y, seed: 86) < 50 ? UIColor(red: 0.78, green: 0.10, blue: 0.10, alpha: 1.0) : UIColor(red: 1.0, green: 0.28, blue: 0.24, alpha: 1.0)) : pixelColor(kind: .stone, x: x, y: y)
        case .quartzOre:
            return isOreCluster(x: x, y: y, seed: 91) ? (noise(x: x, y: y, seed: 92) < 50 ? UIColor(red: 0.92, green: 0.89, blue: 0.84, alpha: 1.0) : UIColor(red: 1.0, green: 0.99, blue: 0.97, alpha: 1.0)) : pixelColor(kind: .netherrack, x: x, y: y)
        case .woodSide:
            let ridge = x % 4
            let n = noise(x: x, y: y, seed: 61)
            if ridge == 0 || n < 24 { return UIColor(red: 0.30, green: 0.19, blue: 0.09, alpha: 1.0) }
            if ridge == 2 && n > 45 { return UIColor(red: 0.46, green: 0.30, blue: 0.16, alpha: 1.0) }
            return UIColor(red: 0.39, green: 0.25, blue: 0.13, alpha: 1.0)
        case .spruceSide:
            let n = noise(x: x, y: y, seed: 95)
            return (x % 3 == 0 || n < 30) ? UIColor(red: 0.16, green: 0.10, blue: 0.06, alpha: 1.0) : UIColor(red: 0.24, green: 0.15, blue: 0.09, alpha: 1.0)
        case .birchSide:
            if (x == 5 && y == 6) || (x == 6 && y == 6) || (x == 11 && y == 11) { return UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1.0) }
            return noise(x: x, y: y, seed: 101) < 68 ? UIColor(red: 0.92, green: 0.91, blue: 0.89, alpha: 1.0) : UIColor(red: 0.80, green: 0.78, blue: 0.75, alpha: 1.0)
        case .woodTop:
            if x == 0 || x == 15 || y == 0 || y == 15 { return UIColor(red: 0.32, green: 0.20, blue: 0.10, alpha: 1.0) }
            let ring = max(max(abs(x - 7), abs(x - 8)), max(abs(y - 7), abs(y - 8)))
            let n = noise(x: x, y: y, seed: 73)
            if ring % 2 == 0 { return n < 40 ? UIColor(red: 0.58, green: 0.41, blue: 0.23, alpha: 1.0) : UIColor(red: 0.65, green: 0.47, blue: 0.27, alpha: 1.0) }
            return UIColor(red: 0.74, green: 0.56, blue: 0.34, alpha: 1.0)
        case .planks:
            let plankIndex = y / 4
            let rowInPlank = y % 4
            let jointX = (plankIndex * 7 + 5) % 16
            if rowInPlank == 3 || x == jointX { return UIColor(red: 0.43, green: 0.29, blue: 0.15, alpha: 1.0) }
            if rowInPlank == 0 { return noise(x: x, y: y, seed: 89) < 30 ? UIColor(red: 0.69, green: 0.51, blue: 0.30, alpha: 1.0) : UIColor(red: 0.76, green: 0.58, blue: 0.35, alpha: 1.0) }
            let grain = noise(x: x / 2, y: y, seed: 97)
            if grain < 30 { return UIColor(red: 0.60, green: 0.43, blue: 0.24, alpha: 1.0) }
            if grain < 75 { return UIColor(red: 0.67, green: 0.49, blue: 0.28, alpha: 1.0) }
            return UIColor(red: 0.72, green: 0.54, blue: 0.32, alpha: 1.0)
        case .sprucePlanks:
            let rowInPlank = y % 4
            let jointX = ((y / 4) * 5 + 3) % 16
            if rowInPlank == 3 || x == jointX { return UIColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 1.0) }
            return noise(x: x, y: y, seed: 109) < 50 ? UIColor(red: 0.37, green: 0.24, blue: 0.13, alpha: 1.0) : UIColor(red: 0.44, green: 0.29, blue: 0.16, alpha: 1.0)
        case .birchPlanks:
            let rowInPlank = y % 4
            let jointX = ((y / 4) * 6 + 2) % 16
            if rowInPlank == 3 || x == jointX { return UIColor(red: 0.66, green: 0.58, blue: 0.38, alpha: 1.0) }
            return noise(x: x, y: y, seed: 113) < 50 ? UIColor(red: 0.84, green: 0.76, blue: 0.54, alpha: 1.0) : UIColor(red: 0.90, green: 0.83, blue: 0.61, alpha: 1.0)
        case .craftingTop:
            if x == 0 || x == 15 || y == 0 || y == 15 { return UIColor(red: 0.42, green: 0.27, blue: 0.14, alpha: 1.0) }
            if x % 4 == 0 || y % 4 == 0 { return UIColor(red: 0.36, green: 0.23, blue: 0.11, alpha: 1.0) }
            return pixelColor(kind: .planks, x: x, y: y)
        case .furnaceSide:
            let isOpening = x >= 5 && x <= 10 && y >= 7 && y <= 12
            if isOpening { return (x + y) % 2 == 0 ? UIColor(red: 0.18, green: 0.18, blue: 0.20, alpha: 1.0) : UIColor(red: 0.96, green: 0.45, blue: 0.12, alpha: 1.0) }
            return pixelColor(kind: .cobblestone, x: x, y: y)
        case .bookshelfSide:
            if y < 3 || y > 12 || x < 2 || x > 13 || x == 8 { return pixelColor(kind: .planks, x: x, y: y) }
            let bookSpine = (x + y) % 3
            if bookSpine == 0 { return UIColor(red: 0.68, green: 0.18, blue: 0.16, alpha: 1.0) }
            if bookSpine == 1 { return UIColor(red: 0.20, green: 0.52, blue: 0.24, alpha: 1.0) }
            return UIColor(red: 0.22, green: 0.38, blue: 0.72, alpha: 1.0)
        case .bedTop:
            if y < 4 { return UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) }
            return noise(x: x, y: y, seed: 115) < 50 ? UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1.0) : UIColor(red: 0.64, green: 0.12, blue: 0.12, alpha: 1.0)
        case .wool:
            return noise(x: x, y: y, seed: 119) < 50 ? UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0) : UIColor(red: 0.98, green: 0.98, blue: 0.99, alpha: 1.0)
        case .clay:
            return noise(x: x, y: y, seed: 121) < 50 ? UIColor(red: 0.60, green: 0.64, blue: 0.71, alpha: 1.0) : UIColor(red: 0.67, green: 0.71, blue: 0.78, alpha: 1.0)
        case .ice:
            if (x + y) % 7 == 0 { return UIColor(red: 0.85, green: 0.95, blue: 1.0, alpha: 0.82) }
            return noise(x: x, y: y, seed: 131) < 50 ? UIColor(red: 0.56, green: 0.80, blue: 0.98, alpha: 0.74) : UIColor(red: 0.66, green: 0.86, blue: 0.99, alpha: 0.76)
        case .leaves:
            let n = noise(x: x, y: y, seed: 103)
            if n < 24 { return UIColor(red: 0.11, green: 0.35, blue: 0.13, alpha: 1.0) }
            if n < 68 { return UIColor(red: 0.17, green: 0.50, blue: 0.19, alpha: 1.0) }
            return UIColor(red: 0.24, green: 0.62, blue: 0.25, alpha: 1.0)
        case .crop:
            let stalk = (x == 4 || x == 8 || x == 12) && y >= 5
            if !stalk { return UIColor.clear }
            return y < 8 ? UIColor(red: 0.88, green: 0.74, blue: 0.18, alpha: 1.0) : UIColor(red: 0.28, green: 0.68, blue: 0.22, alpha: 1.0)
        case .sand:
            let n = noise(x: x, y: y, seed: 127)
            if n < 25 { return UIColor(red: 0.80, green: 0.73, blue: 0.46, alpha: 1.0) }
            if n < 75 { return UIColor(red: 0.88, green: 0.81, blue: 0.54, alpha: 1.0) }
            return UIColor(red: 0.94, green: 0.88, blue: 0.62, alpha: 1.0)
        case .glass:
            let isBorder = (x == 0 || x == 15 || y == 0 || y == 15)
            let isGlint = (x == 2 && y == 2) || (x == 3 && y == 2) || (x == 2 && y == 3) || (x == 12 && y == 4) || (x == 13 && y == 4)
            if isBorder { return UIColor(red: 0.78, green: 0.93, blue: 1.0, alpha: 0.78) }
            if isGlint { return UIColor(red: 0.95, green: 0.99, blue: 1.0, alpha: 0.85) }
            return UIColor(red: 0.72, green: 0.89, blue: 0.98, alpha: 0.16)
        case .water:
            let wave = (x + y * 2) % 8
            let n = noise(x: x, y: y, seed: 151)
            if wave == 0 || (wave == 1 && n < 35) { return UIColor(red: 0.25, green: 0.62, blue: 0.96, alpha: 0.76) }
            return n < 45 ? UIColor(red: 0.12, green: 0.42, blue: 0.82, alpha: 0.66) : UIColor(red: 0.17, green: 0.51, blue: 0.90, alpha: 0.68)
        case .torch:
            if !(x >= 6 && x <= 9) { return UIColor.clear }
            if y <= 4 { return (x + y) % 2 == 0 ? UIColor(red: 1.0, green: 0.92, blue: 0.35, alpha: 1.0) : UIColor(red: 1.0, green: 0.55, blue: 0.10, alpha: 1.0) }
            return y % 2 == 0 ? UIColor(red: 0.56, green: 0.37, blue: 0.19, alpha: 1.0) : UIColor(red: 0.45, green: 0.29, blue: 0.14, alpha: 1.0)
        case .soulTorch:
            if !(x >= 6 && x <= 9) { return UIColor.clear }
            if y <= 4 { return (x + y) % 2 == 0 ? UIColor(red: 0.42, green: 0.95, blue: 1.0, alpha: 1.0) : UIColor(red: 0.16, green: 0.68, blue: 0.98, alpha: 1.0) }
            return y % 2 == 0 ? UIColor(red: 0.56, green: 0.37, blue: 0.19, alpha: 1.0) : UIColor(red: 0.45, green: 0.29, blue: 0.14, alpha: 1.0)
        case .seaLantern:
            if x == 0 || x == 15 || y == 0 || y == 15 { return UIColor(red: 0.52, green: 0.82, blue: 0.86, alpha: 1.0) }
            return noise(x: x, y: y, seed: 179) < 50 ? UIColor(red: 0.76, green: 0.96, blue: 0.98, alpha: 1.0) : UIColor(red: 0.92, green: 1.0, blue: 1.0, alpha: 1.0)
        case .amethyst:
            if (x + y * 2) % 6 == 0 { return UIColor(red: 0.88, green: 0.66, blue: 1.0, alpha: 1.0) }
            return noise(x: x, y: y, seed: 191) < 50 ? UIColor(red: 0.56, green: 0.31, blue: 0.82, alpha: 1.0) : UIColor(red: 0.70, green: 0.45, blue: 0.94, alpha: 1.0)
        case .redstoneDust:
            let onLine = (x >= 6 && x <= 9 && y >= 2 && y <= 13) || (y >= 6 && y <= 9 && x >= 2 && x <= 13)
            if !onLine { return UIColor.clear }
            return noise(x: x, y: y, seed: 193) < 55 ? UIColor(red: 0.95, green: 0.14, blue: 0.12, alpha: 1.0) : UIColor(red: 0.62, green: 0.06, blue: 0.06, alpha: 1.0)
        case .lever:
            if y >= 12 && x >= 5 && x <= 10 { return UIColor(red: 0.46, green: 0.48, blue: 0.52, alpha: 1.0) }
            if x >= 7 && x <= 8 && y >= 4 && y <= 11 { return UIColor(red: 0.62, green: 0.42, blue: 0.22, alpha: 1.0) }
            return UIColor.clear
        case .piston:
            return y < 4 ? UIColor(red: 0.68, green: 0.50, blue: 0.30, alpha: 1.0) : pixelColor(kind: .cobblestone, x: x, y: y)
        case .door:
            if x <= 1 || x >= 14 || y <= 1 || y >= 14 || y == 7 { return UIColor(red: 0.42, green: 0.27, blue: 0.13, alpha: 1.0) }
            if x == 12 && (y == 8 || y == 9) { return UIColor(red: 0.85, green: 0.72, blue: 0.25, alpha: 1.0) }
            return noise(x: x, y: y, seed: 195) < 50 ? UIColor(red: 0.64, green: 0.45, blue: 0.25, alpha: 1.0) : UIColor(red: 0.71, green: 0.51, blue: 0.29, alpha: 1.0)
        case .chest:
            if y == 7 || y == 8 { return UIColor(red: 0.34, green: 0.22, blue: 0.11, alpha: 1.0) }
            if x >= 7 && x <= 8 && y >= 6 && y <= 9 { return UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1.0) }
            return noise(x: x, y: y, seed: 196) < 50 ? UIColor(red: 0.66, green: 0.46, blue: 0.24, alpha: 1.0) : UIColor(red: 0.74, green: 0.53, blue: 0.29, alpha: 1.0)
        case .tnt:
            if y < 4 || y > 11 { return noise(x: x, y: y, seed: 197) < 50 ? UIColor(red: 0.84, green: 0.20, blue: 0.16, alpha: 1.0) : UIColor(red: 0.70, green: 0.15, blue: 0.12, alpha: 1.0) }
            return noise(x: x, y: y, seed: 198) < 50 ? UIColor(red: 0.92, green: 0.90, blue: 0.86, alpha: 1.0) : UIColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1.0)
        case .portal:
            let swirl = (x * 3 + y * 5) % 9
            if swirl == 0 { return UIColor(red: 0.88, green: 0.46, blue: 1.0, alpha: 0.86) }
            if swirl < 4 { return UIColor(red: 0.58, green: 0.16, blue: 0.92, alpha: 0.78) }
            return UIColor(red: 0.34, green: 0.08, blue: 0.62, alpha: 0.74)
        case .cloud:
            return noise(x: x, y: y, seed: 199) < 20 ? UIColor(red: 0.91, green: 0.94, blue: 0.98, alpha: 0.92) : UIColor(red: 0.99, green: 0.99, blue: 1.0, alpha: 0.95)
        case .netherrack:
            let n = noise(x: x, y: y, seed: 211)
            if n < 22 { return UIColor(red: 0.34, green: 0.08, blue: 0.08, alpha: 1.0) }
            if n < 65 { return UIColor(red: 0.47, green: 0.13, blue: 0.13, alpha: 1.0) }
            if n < 88 { return UIColor(red: 0.58, green: 0.19, blue: 0.17, alpha: 1.0) }
            return UIColor(red: 0.27, green: 0.07, blue: 0.09, alpha: 1.0)
        case .soulSand:
            let faceSpot = ((x == 4 || x == 10) && y == 6) || ((x >= 5 && x <= 9) && y == 10)
            if faceSpot { return UIColor(red: 0.18, green: 0.12, blue: 0.09, alpha: 1.0) }
            let n = noise(x: x, y: y, seed: 223)
            if n < 30 { return UIColor(red: 0.26, green: 0.18, blue: 0.13, alpha: 1.0) }
            if n < 78 { return UIColor(red: 0.35, green: 0.24, blue: 0.17, alpha: 1.0) }
            return UIColor(red: 0.43, green: 0.30, blue: 0.21, alpha: 1.0)
        case .glowstone:
            let n = noise(x: x, y: y, seed: 239)
            if n < 20 { return UIColor(red: 0.62, green: 0.38, blue: 0.12, alpha: 1.0) }
            if n < 58 { return UIColor(red: 0.88, green: 0.65, blue: 0.24, alpha: 1.0) }
            if n < 85 { return UIColor(red: 0.99, green: 0.85, blue: 0.45, alpha: 1.0) }
            return UIColor(red: 1.0, green: 0.95, blue: 0.72, alpha: 1.0)
        case .magma:
            let vein = (x + y * 3) % 7 == 0 || (abs(x - y) % 8 == 0)
            let n = noise(x: x, y: y, seed: 251)
            if vein && n < 70 { return n < 30 ? UIColor(red: 1.0, green: 0.72, blue: 0.18, alpha: 1.0) : UIColor(red: 0.96, green: 0.36, blue: 0.08, alpha: 1.0) }
            return n < 45 ? UIColor(red: 0.24, green: 0.10, blue: 0.09, alpha: 1.0) : UIColor(red: 0.42, green: 0.14, blue: 0.10, alpha: 1.0)
        case .endStone:
            if (x == 5 && y == 5) || (x == 11 && y == 9) || (x == 3 && y == 12) { return UIColor(red: 0.56, green: 0.55, blue: 0.42, alpha: 1.0) }
            let n = noise(x: x, y: y, seed: 269)
            if n < 25 { return UIColor(red: 0.72, green: 0.71, blue: 0.53, alpha: 1.0) }
            if n < 75 { return UIColor(red: 0.84, green: 0.82, blue: 0.62, alpha: 1.0) }
            return UIColor(red: 0.91, green: 0.89, blue: 0.69, alpha: 1.0)
        case .obsidian:
            let n = noise(x: x, y: y, seed: 283)
            if (x * 3 + y * 2) % 11 == 0 && n < 50 { return UIColor(red: 0.32, green: 0.16, blue: 0.52, alpha: 1.0) }
            return n < 50 ? UIColor(red: 0.06, green: 0.04, blue: 0.10, alpha: 1.0) : UIColor(red: 0.11, green: 0.07, blue: 0.17, alpha: 1.0)
        case .endCrystal:
            if (x + y) % 5 == 0 { return UIColor(red: 0.96, green: 0.74, blue: 1.0, alpha: 1.0) }
            return noise(x: x, y: y, seed: 307) < 50 ? UIColor(red: 0.68, green: 0.32, blue: 0.92, alpha: 1.0) : UIColor(red: 0.84, green: 0.52, blue: 0.99, alpha: 1.0)
        }
    }
}

