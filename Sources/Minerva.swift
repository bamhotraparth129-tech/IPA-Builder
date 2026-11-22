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

// MARK: - Dimensions, Biomes, Weather, Gear, Mobs, Items & Crafting

enum GameDimension: String, Codable, CaseIterable, Identifiable {
    case overworld = "Overworld"
    case hell = "Hell"
    case endgame = "Endgame"

    var id: String { rawValue }
    var fileToken: String {
        switch self {
        case .overworld: return "overworld"
        case .hell: return "hell"
        case .endgame: return "endgame"
        }
    }
    var badgeColor: Color {
        switch self {
        case .overworld: return .green
        case .hell: return .red
        case .endgame: return .purple
        }
    }
    var nextDimension: GameDimension {
        switch self {
        case .overworld: return .hell
        case .hell: return .endgame
        case .endgame: return .overworld
        }
    }
}

enum WeatherKind: String, CaseIterable {
    case clear = "Clear"
    case rain = "Rain"
    case snowstorm = "Snow"
}

enum GearTier: String, CaseIterable {
    case wood = "Wood"
    case iron = "Iron"
    case diamond = "Diamond"

    var next: GearTier {
        switch self {
        case .wood: return .iron
        case .iron: return .diamond
        case .diamond: return .wood
        }
    }
    var attackDamage: Int {
        switch self {
        case .wood: return 4
        case .iron: return 7
        case .diamond: return 11
        }
    }
    var miningSpeed: Double {
        switch self {
        case .wood: return 1.0
        case .iron: return 1.8
        case .diamond: return 2.8
        }
    }
    var maxDurability: Int {
        switch self {
        case .wood: return 60
        case .iron: return 180
        case .diamond: return 420
        }
    }
    var armorReduction: Int {
        switch self {
        case .wood: return 0
        case .iron: return 1
        case .diamond: return 2
        }
    }
}

enum ToolKind: String, CaseIterable, Identifiable {
    case pickaxe = "Pickaxe"
    case axe = "Axe"
    case shovel = "Shovel"
    case sword = "Sword"
    case fishingRod = "Fishing Rod"

    var id: String { rawValue }

    func speedBonus(for block: BlockType) -> Double {
        switch self {
        case .pickaxe:
            return [.stone, .cobblestone, .mossyCobble, .stoneBricks, .bedrock,
                    .coalOre, .ironOre, .goldOre, .diamondOre, .emeraldOre,
                    .redstoneOre, .quartzOre, .furnace, .obsidian, .endStone,
                    .netherrack, .sandstone, .amethyst].contains(block) ? 3.0 : 0.55
        case .axe:
            return [.wood, .spruceLog, .birchLog, .planks, .sprucePlanks,
                    .birchPlanks, .craftingTable, .bookshelf, .chest, .door].contains(block) ? 3.0 : 0.65
        case .shovel:
            return [.dirt, .grass, .snowGrass, .snow, .sand, .clay, .soulSand].contains(block) ? 3.0 : 0.65
        case .sword:
            return [.leaves, .wool, .crop].contains(block) ? 1.8 : 0.35
        case .fishingRod:
            return 0.2
        }
    }

    var attackDamage: Int {
        switch self {
        case .sword: return 6
        case .axe: return 5
        case .pickaxe: return 3
        case .shovel: return 2
        case .fishingRod: return 1
        }
    }
}

enum BiomeType: String, CaseIterable {
    case plains = "Plains"
    case desert = "Desert"
    case forest = "Forest"
    case highlands = "Highlands"
    case ocean = "Ocean"
    case beach = "Beach"
    case swamp = "Swamp"
    case taiga = "Taiga"
    case jungle = "Jungle"
    case hell = "Crimson Wastes"
    case endgame = "Void Outerlands"

    static func biomeAt(x: Int, z: Int, dimension: GameDimension) -> BiomeType {
        switch dimension {
        case .hell: return .hell
        case .endgame: return .endgame
        case .overworld:
            let fx = Float(x) * 0.085
            let fz = Float(z) * 0.085
            let heat = sin(fx * 1.1 + fz * 0.4) * cos(fz * 0.9 - fx * 0.3)
            let moisture = cos(fx * 0.7 - fz * 1.2) + sin((fx + fz) * 0.5) * 0.5
            if moisture < -0.72 && abs(heat) < 0.72 { return .ocean }
            if moisture >= -0.72 && moisture < -0.48 && abs(heat) < 0.82 { return .beach }
            if heat > 0.08 && moisture > 0.78 { return .jungle }
            if moisture > 0.58 && heat > -0.18 && heat <= 0.32 { return .swamp }
            if heat < -0.05 && moisture > -0.12 { return .taiga }
            if heat > 0.32 { return .desert }
            if heat < -0.30 { return .highlands }
            if moisture > 0.28 { return .forest }
            return .plains
        }
    }
}

enum MobKind: String {
    case sheep = "Sheep"
    case pig = "Pig"
    case cow = "Cow"
    case chicken = "Chicken"
    case wolf = "Wolf"
    case fox = "Fox"
    case bear = "Bear"
    case fish = "Fish"
    case dolphin = "Dolphin"
    case turtle = "Turtle"
    case guardian = "Guardian"
    case villager = "Villager"
    case slime = "Slime"
    case zombie = "Zombie"
    case skeleton = "Skeleton"
    case creeper = "Creeper"
    case enderman = "Enderman"
    case enderDragon = "Ender Dragon"
    case ironGolem = "Iron Golem"
    case spider = "Spider"
    case blaze = "Blaze"
}

struct AchievementInfo: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String

    static let all: [AchievementInfo] = [
        .init(id: "first_blood", title: "First Blood", detail: "Defeat your first hostile mob", symbol: "target"),
        .init(id: "monster_hunter", title: "Monster Hunter", detail: "Defeat 10 hostile mobs", symbol: "flame.fill"),
        .init(id: "dragon_slayer", title: "Dragon Slayer", detail: "Defeat the Ender Dragon", symbol: "crown.fill"),
        .init(id: "netherbound", title: "Into the Nether", detail: "Enter the Nether", symbol: "flame.fill"),
        .init(id: "the_end", title: "The End", detail: "Reach the End dimension", symbol: "sparkles"),
        .init(id: "alchemist", title: "Alchemist", detail: "Brew your first potion", symbol: "flask.fill"),
        .init(id: "village_guardian", title: "Village Guardian", detail: "Summon an Iron Golem", symbol: "shield.fill"),
        .init(id: "angler", title: "Angler", detail: "Catch your first fish", symbol: "fish.fill"),
        .init(id: "sailor", title: "Sailor", detail: "Travel 100 blocks by boat", symbol: "sailboat.fill"),
        .init(id: "wreck_diver", title: "Wreck Diver", detail: "Explore an ocean treasure chest", symbol: "water.waves"),
        .init(id: "crystal_caver", title: "Crystal Caver", detail: "Discover a hidden underwater crystal cavern", symbol: "sparkles"),
        .init(id: "monument_conqueror", title: "Monument Conqueror", detail: "Defeat an Elder Guardian", symbol: "crown.fill"),
        .init(id: "deep_sea_cartographer", title: "Deep-Sea Cartographer", detail: "Locate ocean treasure with the treasure compass", symbol: "map.fill"),
        .init(id: "dolphin_friend", title: "Dolphin Friend", detail: "Follow a dolphin to an ocean treasure", symbol: "water.waves"),
        .init(id: "biome_explorer", title: "Biome Explorer", detail: "Discover all nine Overworld biomes", symbol: "globe.americas.fill"),
        .init(id: "swamp_walker", title: "Swamp Walker", detail: "Explore a swamp biome", symbol: "leaf.fill"),
        .init(id: "jungle_explorer", title: "Jungle Explorer", detail: "Explore a jungle biome", symbol: "tree.fill"),
        .init(id: "taiga_traveler", title: "Taiga Traveler", detail: "Explore a taiga biome", symbol: "snowflake"),
        .init(id: "coastal_roamer", title: "Coastal Roamer", detail: "Explore a beach biome", symbol: "sun.horizon.fill"),
        .init(id: "first_companion", title: "A Friend for the Journey", detail: "Tame your first animal companion", symbol: "pawprint.fill"),
        .init(id: "pack_leader", title: "Pack Leader", detail: "Tame three animal companions", symbol: "pawprint.circle.fill"),
        .init(id: "wildlife_friend", title: "Wildlife Friend", detail: "Tame a wolf, fox and bear", symbol: "leaf.fill"),
        .init(id: "watchful_companion", title: "Watchful Companion", detail: "Command a tamed animal to guard a location", symbol: "shield.lefthalf.filled"),
        .init(id: "well_cared_for", title: "Well Cared For", detail: "Restore a companion to full health", symbol: "heart.fill")
    ]
}

enum PotionKind: String, CaseIterable, Identifiable {
    case healing = "Healing"
    case strength = "Strength"
    case speed = "Swiftness"
    case resistance = "Resistance"
    case regeneration = "Regeneration"
    case waterBreathing = "Water Breathing"
    case fireResistance = "Fire Resistance"
    case haste = "Haste"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .healing: return "cross.case.fill"
        case .strength: return "flame.fill"
        case .speed: return "hare.fill"
        case .resistance: return "shield.fill"
        case .regeneration: return "heart.fill"
        case .waterBreathing: return "water.waves"
        case .fireResistance: return "flame"
        case .haste: return "pickaxe"
        }
    }
    var duration: Float {
        switch self {
        case .healing: return 0
        case .regeneration: return 18
        case .waterBreathing, .fireResistance, .haste: return 45
        default: return 30
        }
    }
    var ingredients: [(BlockType, Int)] {
        switch self {
        case .healing: return [(.amethyst, 2), (.goldOre, 1)]
        case .strength: return [(.quartzOre, 2), (.coalOre, 1)]
        case .speed: return [(.glowstone, 2), (.redstoneOre, 1)]
        case .resistance: return [(.ironOre, 2), (.obsidian, 1)]
        case .regeneration: return [(.amethyst, 1), (.glowstone, 1), (.emeraldOre, 1)]
        case .waterBreathing: return [(.water, 3), (.amethyst, 1), (.quartzOre, 1)]
        case .fireResistance: return [(.magma, 2), (.goldOre, 1), (.glowstone, 1)]
        case .haste: return [(.coalOre, 2), (.redstoneOre, 1), (.amethyst, 1)]
        }
    }
}

enum VillagerProfession: String, CaseIterable {
    case farmer = "Farmer"
    case miner = "Miner"
    case builder = "Builder"

    var symbol: String {
        switch self {
        case .farmer: return "leaf.fill"
        case .miner: return "pickaxe"
        case .builder: return "hammer.fill"
        }
    }
}

enum DragonPhase: String {
    case circling = "Circling"
    case diving = "Diving"
    case perching = "Perching"
}

struct VillagerPathCell: Hashable {
    let x: Int
    let z: Int
}

final class WorldMob {
    let id: UUID
    let kind: MobKind
    var position: SIMD3<Float>
    var velocityY: Float = 0
    var knockback: SIMD2<Float> = .zero
    var yaw: Float
    var hp: Int
    var wanderTimer: Float
    var attackCooldown: Float = 1.5
    var dragonPhase: DragonPhase = .circling
    var dragonPhaseTimer: Float = 4.0
    var dragonHealTimer: Float = 0.0
    var loveTimer: Float = 0.0
    var breedCooldown: Float = 0.0
    var isBaby: Bool = false
    var isTamed: Bool = false
    var isSitting: Bool = false
    var isGuarding: Bool = false
    var guardPosition: SIMD3<Float>? = nil
    var petRegenTimer: Float = 0
    var petGuardMoving: Bool = false
    var profession: VillagerProfession = VillagerProfession.allCases.randomElement() ?? .farmer
    var ageTimer: Float = 0.0
    var homePosition: SIMD3<Float>? = nil
    var workstationPosition: SIMD3<Float>? = nil
    var isSleeping: Bool = false
    var isElderGuardian: Bool = false
    var navigationPath: [SIMD3<Float>] = []
    var pathRefreshTimer: Float = 0
    var farmWorkTimer: Float = 0
    var raidDamageCooldown: Float = 0
    var creeperFuseRemaining: Float = 1.45
    var isCreeperPrimed: Bool = false
    let node: SCNNode

    init(id: UUID = UUID(), kind: MobKind, position: SIMD3<Float>, yaw: Float, hp: Int, wanderTimer: Float, node: SCNNode) {
        self.id = id
        self.kind = kind
        self.position = position
        self.yaw = yaw
        self.hp = hp
        self.wanderTimer = wanderTimer
        self.node = node
    }
}

final class ArrowProjectile {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
    var life: Float = 3.0
    let damage: Int
    let node: SCNNode

    init(position: SIMD3<Float>, velocity: SIMD3<Float>, damage: Int = 3, node: SCNNode) {
        self.position = position
        self.velocity = velocity
        self.damage = damage
        self.node = node
    }
}

final class DroppedItemEntity {
    let id: UUID
    let blockType: BlockType
    var position: SIMD3<Float>
    var bobPhase: Float
    let node: SCNNode

    init(id: UUID = UUID(), blockType: BlockType, position: SIMD3<Float>, bobPhase: Float, node: SCNNode) {
        self.id = id
        self.blockType = blockType
        self.position = position
        self.bobPhase = bobPhase
        self.node = node
    }
}

final class ExperienceOrbEntity {
    let id: UUID
    let value: Int
    var position: SIMD3<Float>
    var bobPhase: Float
    let node: SCNNode

    init(id: UUID = UUID(), value: Int, position: SIMD3<Float>, bobPhase: Float, node: SCNNode) {
        self.id = id
        self.value = value
        self.position = position
        self.bobPhase = bobPhase
        self.node = node
    }
}

enum EnchantmentKind: String, CaseIterable, Identifiable {
    case efficiency = "Efficiency"
    case sharpness = "Sharpness"
    case protection = "Protection"
    case unbreaking = "Unbreaking"

    var id: String { rawValue }
    var maximumLevel: Int { self == .unbreaking ? 3 : 3 }
    var baseCost: Int {
        switch self {
        case .efficiency: return 5
        case .sharpness: return 6
        case .protection: return 6
        case .unbreaking: return 8
        }
    }
    var description: String {
        switch self {
        case .efficiency: return "Faster block mining"
        case .sharpness: return "Increases melee damage"
        case .protection: return "Reduces incoming damage"
        case .unbreaking: return "Chance to preserve durability"
        }
    }
}

enum FoodKind: String, CaseIterable, Identifiable {
    case bread = "Bread"
    case cookedMutton = "Cooked Mutton"
    case rawMutton = "Raw Mutton"
    case rawPork = "Raw Porkchop"
    case cookedPork = "Cooked Porkchop"
    case rawBeef = "Raw Beef"
    case cookedBeef = "Steak"
    case rawChicken = "Raw Chicken"
    case cookedChicken = "Cooked Chicken"
    case rawFish = "Raw Fish"
    case cookedFish = "Cooked Fish"
    case wheat = "Wheat"
    case seeds = "Seeds"
    case carrot = "Carrot"

    var id: String { rawValue }
    var isEdible: Bool { ![.rawMutton, .rawPork, .rawBeef, .rawChicken, .rawFish, .wheat, .seeds].contains(self) }
    var hungerRestore: Int {
        switch self {
        case .bread: return 5
        case .cookedMutton, .cookedPork, .cookedBeef: return 6
        case .cookedChicken, .cookedFish: return 5
        case .rawFish: return 2
        case .carrot: return 3
        case .rawMutton, .rawPork, .rawBeef, .rawChicken, .wheat, .seeds: return 0
        }
    }
    var healthRestore: Int {
        switch self {
        case .bread, .carrot: return 2
        case .cookedMutton, .cookedPork, .cookedBeef: return 4
        case .cookedChicken, .cookedFish: return 3
        case .rawFish: return 0
        case .rawMutton, .rawPork, .rawBeef, .rawChicken, .wheat, .seeds: return 0
        }
    }
    var cookingResult: FoodKind? {
        switch self {
        case .rawMutton: return .cookedMutton
        case .rawPork: return .cookedPork
        case .rawBeef: return .cookedBeef
        case .rawChicken: return .cookedChicken
        case .rawFish: return .cookedFish
        default: return nil
        }
    }
}

struct CraftRecipe: Identifiable {
    let id: String
    let title: String
    let output: BlockType
    let outputCount: Int
    let foodOutput: FoodKind?
    let foodCount: Int
    let ingredients: [(BlockType, Int)]
}

enum CraftCatalog {
    static let all: [CraftRecipe] = [
        CraftRecipe(id: "planks_oak", title: "Oak Planks ×4", output: .planks, outputCount: 4, foodOutput: nil, foodCount: 0, ingredients: [(.wood, 1)]),
        CraftRecipe(id: "planks_spruce", title: "Spruce Planks ×4", output: .sprucePlanks, outputCount: 4, foodOutput: nil, foodCount: 0, ingredients: [(.spruceLog, 1)]),
        CraftRecipe(id: "planks_birch", title: "Birch Planks ×4", output: .birchPlanks, outputCount: 4, foodOutput: nil, foodCount: 0, ingredients: [(.birchLog, 1)]),
        CraftRecipe(id: "craft_table", title: "Crafting Table", output: .craftingTable, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 4)]),
        CraftRecipe(id: "furnace_block", title: "Furnace", output: .furnace, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.cobblestone, 4)]),
        CraftRecipe(id: "bed_block", title: "Bed", output: .bed, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 2), (.wool, 2)]),
        CraftRecipe(id: "crop_seeds", title: "Crop Plot ×2", output: .crop, outputCount: 2, foodOutput: nil, foodCount: 0, ingredients: [(.dirt, 1), (.leaves, 1)]),
        CraftRecipe(id: "door_block", title: "Wooden Door", output: .door, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 3)]),
        CraftRecipe(id: "chest_block", title: "Loot Chest", output: .chest, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 4)]),
        CraftRecipe(id: "torches", title: "Torches ×4", output: .torch, outputCount: 4, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 1), (.coalOre, 1)]),
        CraftRecipe(id: "soul_torches", title: "Soul Torches ×4", output: .soulTorch, outputCount: 4, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 1), (.soulSand, 1)]),
        CraftRecipe(id: "stone_bricks", title: "Stone Bricks ×2", output: .stoneBricks, outputCount: 2, foodOutput: nil, foodCount: 0, ingredients: [(.stone, 2)]),
        CraftRecipe(id: "bricks", title: "Bricks ×2", output: .bricks, outputCount: 2, foodOutput: nil, foodCount: 0, ingredients: [(.clay, 2)]),
        CraftRecipe(id: "glass_pane", title: "Smelt Glass ×2", output: .glass, outputCount: 2, foodOutput: nil, foodCount: 0, ingredients: [(.sand, 2), (.coalOre, 1)]),
        CraftRecipe(id: "tnt_block", title: "TNT Charge", output: .tnt, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.sand, 2), (.redstoneOre, 1)]),
        CraftRecipe(id: "redstone_wire", title: "Redstone Dust ×3", output: .redstoneDust, outputCount: 3, foodOutput: nil, foodCount: 0, ingredients: [(.redstoneOre, 1)]),
        CraftRecipe(id: "lever_switch", title: "Redstone Lever", output: .lever, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.cobblestone, 1), (.planks, 1)]),
        CraftRecipe(id: "pressure_plate", title: "Pressure Plate", output: .pressurePlate, outputCount: 2, foodOutput: nil, foodCount: 0, ingredients: [(.planks, 2)]),
        CraftRecipe(id: "redstone_repeater", title: "Redstone Repeater", output: .repeater, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.stone, 2), (.redstoneDust, 1), (.torch, 1)]),
        CraftRecipe(id: "redstone_lamp", title: "Redstone Lamp", output: .redstoneLamp, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.glowstone, 1), (.redstoneDust, 1)]),
        CraftRecipe(id: "redstone_button", title: "Redstone Button", output: .button, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.stone, 2), (.redstoneDust, 1)]),
        CraftRecipe(id: "piston_mech", title: "Piston", output: .piston, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.cobblestone, 2), (.planks, 1), (.redstoneDust, 1)]),
        CraftRecipe(id: "portal_core", title: "Dimension Portal", output: .portal, outputCount: 1, foodOutput: nil, foodCount: 0, ingredients: [(.obsidian, 4), (.endCrystal, 1)]),
        CraftRecipe(id: "bread_food", title: "Bake Bread ×2", output: .crop, outputCount: 0, foodOutput: .bread, foodCount: 2, ingredients: [(.leaves, 2)]),
        CraftRecipe(id: "mutton_food", title: "Cook Mutton ×2", output: .crop, outputCount: 0, foodOutput: .cookedMutton, foodCount: 2, ingredients: [(.wool, 1), (.coalOre, 1)])
    ]
}

struct EquipmentRecipe: Identifiable {
    let id: String
    let title: String
    let tier: GearTier
    let tool: ToolKind?
    let armorSlot: String?
    let ingredients: [(BlockType, Int)]
}

enum EquipmentCraftCatalog {
    static let all: [EquipmentRecipe] = GearTier.allCases.flatMap { tier in
        let material: BlockType = tier == .wood ? .planks : (tier == .iron ? .ironOre : .diamondOre)
        let toolRecipes = ToolKind.allCases.map { tool -> EquipmentRecipe in
            let amount = tool == .pickaxe || tool == .axe ? 3 : 2
            let ingredients: [(BlockType, Int)]
            if tool == .fishingRod {
                ingredients = material == .planks
                    ? [(.planks, 3), (.wool, 2)]
                    : [(material, 2), (.wool, 2)]
            } else {
                ingredients = material == .planks
                    ? [(.planks, amount + 2)]
                    : [(material, amount), (.planks, 2)]
            }
            return EquipmentRecipe(
                id: "gear_\(tier.rawValue.lowercased())_\(tool.rawValue.lowercased())",
                title: "\(tier.rawValue) \(tool.rawValue)", tier: tier, tool: tool, armorSlot: nil,
                ingredients: ingredients
            )
        }
        let armorRecipes = [("Helmet", 5), ("Chestplate", 8), ("Leggings", 7), ("Boots", 4)].map { slot, amount in
            EquipmentRecipe(
                id: "gear_\(tier.rawValue.lowercased())_\(slot.lowercased())",
                title: "\(tier.rawValue) \(slot)", tier: tier, tool: nil, armorSlot: slot,
                ingredients: [(material, amount)]
            )
        }
        return toolRecipes + armorRecipes
    }
}

// MARK: - Block Categories & Voxel Block Types

enum BlockCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case nature = "Nature"
    case stoneOre = "Stone & Ore"
    case woodBuild = "Wood & Build"
    case lightSpecial = "Light & Realms"

    var id: String { rawValue }
}

enum BlockType: String, Codable, CaseIterable, Identifiable {
    case grass = "Grass", snowGrass = "SnowGrass", snow = "Snow", dirt = "Dirt", sand = "Sand", clay = "Clay", ice = "Ice", water = "Water"
    case wood = "OakLog", spruceLog = "SpruceLog", birchLog = "BirchLog", leaves = "Leaves", crop = "Crop"
    case stone = "Stone", cobblestone = "Cobble", mossyCobble = "MossCobble", stoneBricks = "StoneBrick", bricks = "Bricks", sandstone = "Sandstone", bedrock = "Bedrock"
    case coalOre = "CoalOre", ironOre = "IronOre", goldOre = "GoldOre", diamondOre = "DiamondOre", emeraldOre = "EmeraldOre", redstoneOre = "RedstoneOre", quartzOre = "QuartzOre"
    case planks = "OakPlanks", sprucePlanks = "SprucePlank", birchPlanks = "BirchPlank", craftingTable = "CraftTable", furnace = "Furnace", bookshelf = "Bookshelf"
    case bed = "Bed", door = "Door", chest = "Chest", wool = "Wool", glass = "Glass"
    case torch = "Torch", soulTorch = "SoulTorch", redstoneDust = "Redstone", lever = "Lever", piston = "Piston", tnt = "TNT", portal = "Portal"
    case pressurePlate = "PressurePlate", repeater = "Repeater", redstoneLamp = "RedstoneLamp", button = "Button"
    case seaLantern = "SeaLantern", prismarine = "Prismarine", amethyst = "Amethyst", netherrack = "Netherrack", soulSand = "SoulSand", glowstone = "Glowstone", magma = "Magma", endStone = "EndStone", obsidian = "Obsidian", endCrystal = "Crystal"

    var id: String { rawValue }

    var category: BlockCategory {
        switch self {
        case .grass, .snowGrass, .snow, .dirt, .sand, .clay, .ice, .water, .wood, .spruceLog, .birchLog, .leaves, .crop: return .nature
        case .stone, .cobblestone, .mossyCobble, .stoneBricks, .bricks, .sandstone, .bedrock, .coalOre, .ironOre, .goldOre, .diamondOre, .emeraldOre, .redstoneOre, .quartzOre: return .stoneOre
        case .planks, .sprucePlanks, .birchPlanks, .craftingTable, .furnace, .bookshelf, .bed, .door, .chest, .wool, .glass: return .woodBuild
        case .torch, .soulTorch, .redstoneDust, .lever, .piston, .tnt, .portal, .pressurePlate, .repeater, .redstoneLamp, .button, .seaLantern, .prismarine, .amethyst, .netherrack, .soulSand, .glowstone, .magma, .endStone, .obsidian, .endCrystal: return .lightSpecial
        }
    }

    var miningHardness: Double {
        switch self {
        case .bedrock: return .infinity
        case .obsidian: return 8.0
        case .stone, .cobblestone, .stoneBricks, .mossyCobble, .furnace: return 3.2
        case .ironOre, .goldOre, .diamondOre, .emeraldOre, .redstoneOre, .quartzOre, .coalOre: return 3.8
        case .wood, .spruceLog, .birchLog, .planks, .sprucePlanks, .birchPlanks, .craftingTable, .bookshelf, .chest, .door: return 2.0
        case .sand, .dirt, .grass, .snowGrass, .snow, .clay, .soulSand, .netherrack: return 0.8
        case .leaves, .wool, .crop, .torch, .soulTorch, .redstoneDust, .lever, .pressurePlate, .repeater, .button, .glass, .water, .ice: return 0.35
        default: return 1.5
        }
    }

    var isTranslucent: Bool { [.glass, .water, .ice, .torch, .soulTorch, .redstoneDust, .lever, .pressurePlate, .repeater, .button, .crop, .portal, .endCrystal].contains(self) }
    var isPassable: Bool { [.water, .torch, .soulTorch, .redstoneDust, .lever, .pressurePlate, .repeater, .button, .crop, .portal].contains(self) }
    var obeysGravity: Bool { self == .sand || self == .snow }
    var emitsLight: Bool { [.torch, .soulTorch, .glowstone, .magma, .seaLantern, .endCrystal, .portal, .redstoneDust, .furnace, .redstoneLamp].contains(self) }

    var particleColor: UIColor {
        switch self {
        case .grass, .leaves, .crop: return UIColor(red: 0.30, green: 0.68, blue: 0.22, alpha: 1.0)
        case .snowGrass, .snow, .wool: return UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1.0)
        case .dirt, .soulSand: return UIColor(red: 0.48, green: 0.31, blue: 0.17, alpha: 1.0)
        case .sand, .sandstone: return UIColor(red: 0.88, green: 0.81, blue: 0.54, alpha: 1.0)
        case .clay: return UIColor(red: 0.63, green: 0.67, blue: 0.74, alpha: 1.0)
        case .ice, .water, .glass, .seaLantern, .prismarine, .redstoneLamp: return UIColor(red: 0.52, green: 0.84, blue: 0.98, alpha: 0.85)
        case .wood, .spruceLog, .planks, .sprucePlanks, .craftingTable, .bookshelf, .door, .chest: return UIColor(red: 0.52, green: 0.35, blue: 0.19, alpha: 1.0)
        case .bed: return UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1.0)
        case .birchLog, .birchPlanks: return UIColor(red: 0.88, green: 0.82, blue: 0.64, alpha: 1.0)
        case .stone, .cobblestone, .mossyCobble, .stoneBricks, .piston, .furnace, .bedrock, .coalOre, .ironOre, .goldOre, .diamondOre, .emeraldOre: return UIColor(red: 0.48, green: 0.50, blue: 0.53, alpha: 1.0)
        case .redstoneOre, .redstoneDust, .lever, .pressurePlate, .repeater, .button: return UIColor(red: 0.92, green: 0.16, blue: 0.14, alpha: 1.0)
        case .tnt: return UIColor(red: 0.88, green: 0.22, blue: 0.18, alpha: 1.0)
        case .bricks: return UIColor(red: 0.68, green: 0.28, blue: 0.22, alpha: 1.0)
        case .quartzOre, .endStone: return UIColor(red: 0.86, green: 0.84, blue: 0.66, alpha: 1.0)
        case .torch, .glowstone, .magma: return UIColor(red: 1.0, green: 0.65, blue: 0.18, alpha: 1.0)
        case .soulTorch: return UIColor(red: 0.32, green: 0.88, blue: 1.0, alpha: 1.0)
        case .amethyst, .endCrystal, .portal: return UIColor(red: 0.74, green: 0.44, blue: 0.96, alpha: 0.95)
        case .netherrack: return UIColor(red: 0.52, green: 0.15, blue: 0.14, alpha: 1.0)
        case .obsidian: return UIColor(red: 0.14, green: 0.08, blue: 0.22, alpha: 1.0)
        }
    }

    var previewImage: UIImage {
        switch self {
        case .grass: return PixelTextureFactory.image(for: .grassSide)
        case .snowGrass: return PixelTextureFactory.image(for: .snowGrassSide)
        case .snow: return PixelTextureFactory.image(for: .snow)
        case .dirt: return PixelTextureFactory.image(for: .dirt)
        case .sand: return PixelTextureFactory.image(for: .sand)
        case .clay: return PixelTextureFactory.image(for: .clay)
        case .ice: return PixelTextureFactory.image(for: .ice)
        case .water: return PixelTextureFactory.image(for: .water)
        case .wood: return PixelTextureFactory.image(for: .woodSide)
        case .spruceLog: return PixelTextureFactory.image(for: .spruceSide)
        case .birchLog: return PixelTextureFactory.image(for: .birchSide)
        case .leaves: return PixelTextureFactory.image(for: .leaves)
        case .crop: return PixelTextureFactory.image(for: .crop)
        case .stone: return PixelTextureFactory.image(for: .stone)
        case .cobblestone: return PixelTextureFactory.image(for: .cobblestone)
        case .mossyCobble: return PixelTextureFactory.image(for: .mossyCobble)
        case .stoneBricks: return PixelTextureFactory.image(for: .stoneBricks)
        case .bricks: return PixelTextureFactory.image(for: .bricks)
        case .sandstone: return PixelTextureFactory.image(for: .sandstone)
        case .bedrock: return PixelTextureFactory.image(for: .bedrock)
        case .coalOre: return PixelTextureFactory.image(for: .coalOre)
        case .ironOre: return PixelTextureFactory.image(for: .ironOre)
        case .goldOre: return PixelTextureFactory.image(for: .goldOre)
        case .diamondOre: return PixelTextureFactory.image(for: .diamondOre)
        case .emeraldOre: return PixelTextureFactory.image(for: .emeraldOre)
        case .redstoneOre: return PixelTextureFactory.image(for: .redstoneOre)
        case .quartzOre: return PixelTextureFactory.image(for: .quartzOre)
        case .planks: return PixelTextureFactory.image(for: .planks)
        case .sprucePlanks: return PixelTextureFactory.image(for: .sprucePlanks)
        case .birchPlanks: return PixelTextureFactory.image(for: .birchPlanks)
        case .craftingTable: return PixelTextureFactory.image(for: .craftingTop)
        case .furnace: return PixelTextureFactory.image(for: .furnaceSide)
        case .bookshelf: return PixelTextureFactory.image(for: .bookshelfSide)
        case .bed: return PixelTextureFactory.image(for: .bedTop)
        case .door: return PixelTextureFactory.image(for: .door)
        case .chest: return PixelTextureFactory.image(for: .chest)
        case .wool: return PixelTextureFactory.image(for: .wool)
        case .glass: return PixelTextureFactory.image(for: .glass)
        case .torch: return PixelTextureFactory.image(for: .torch)
        case .soulTorch: return PixelTextureFactory.image(for: .soulTorch)
        case .redstoneDust: return PixelTextureFactory.image(for: .redstoneDust)
        case .lever: return PixelTextureFactory.image(for: .lever)
        case .pressurePlate, .button, .repeater: return PixelTextureFactory.image(for: .redstoneDust)
        case .redstoneLamp: return PixelTextureFactory.image(for: .seaLantern)
        case .piston: return PixelTextureFactory.image(for: .piston)
        case .tnt: return PixelTextureFactory.image(for: .tnt)
        case .portal: return PixelTextureFactory.image(for: .portal)
        case .seaLantern: return PixelTextureFactory.image(for: .seaLantern)
        case .prismarine: return PixelTextureFactory.image(for: .stone)
        case .amethyst: return PixelTextureFactory.image(for: .amethyst)
        case .netherrack: return PixelTextureFactory.image(for: .netherrack)
        case .soulSand: return PixelTextureFactory.image(for: .soulSand)
        case .glowstone: return PixelTextureFactory.image(for: .glowstone)
        case .magma: return PixelTextureFactory.image(for: .magma)
        case .endStone: return PixelTextureFactory.image(for: .endStone)
        case .obsidian: return PixelTextureFactory.image(for: .obsidian)
        case .endCrystal: return PixelTextureFactory.image(for: .endCrystal)
        }
    }

    func makeGeometry() -> SCNGeometry {
        if self == .torch {
            let stick = SCNBox(width: 0.22, height: 0.68, length: 0.22, chamferRadius: 0.0)
            let shaftMat = makePixelMaterial(kind: .woodSide)
            let flameMat = makeEmissionMaterial(color: UIColor(red: 1.0, green: 0.92, blue: 0.35, alpha: 1.0), emission: UIColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1.0))
            stick.materials = [shaftMat, shaftMat, shaftMat, shaftMat, flameMat, shaftMat]
            return stick
        }
        if self == .soulTorch {
            let stick = SCNBox(width: 0.22, height: 0.68, length: 0.22, chamferRadius: 0.0)
            let shaftMat = makePixelMaterial(kind: .woodSide)
            let flameMat = makeEmissionMaterial(color: UIColor(red: 0.42, green: 0.95, blue: 1.0, alpha: 1.0), emission: UIColor(red: 0.16, green: 0.72, blue: 1.0, alpha: 1.0))
            stick.materials = [shaftMat, shaftMat, shaftMat, shaftMat, flameMat, shaftMat]
            return stick
        }
        if self == .redstoneDust {
            let pad = SCNBox(width: 0.92, height: 0.08, length: 0.92, chamferRadius: 0.0)
            let mat = makePixelMaterial(kind: .redstoneDust, translucent: true)
            mat.emission.contents = UIColor(red: 0.95, green: 0.14, blue: 0.12, alpha: 0.6)
            pad.materials = [mat, mat, mat, mat, mat, mat]
            return pad
        }
        if self == .lever {
            let stick = SCNBox(width: 0.22, height: 0.52, length: 0.22, chamferRadius: 0.0)
            let mat = makePixelMaterial(kind: .lever, translucent: true)
            stick.materials = [mat, mat, mat, mat, mat, mat]
            return stick
        }
        if self == .pressurePlate || self == .button {
            let plate = SCNBox(width: 0.82, height: 0.09, length: 0.82, chamferRadius: 0.015)
            let mat = makePixelMaterial(kind: .redstoneDust, translucent: true)
            plate.materials = [mat, mat, mat, mat, mat, mat]
            return plate
        }
        if self == .repeater {
            let base = SCNBox(width: 0.82, height: 0.10, length: 0.82, chamferRadius: 0.01)
            let mat = makePixelMaterial(kind: .redstoneDust, translucent: true)
            base.materials = [mat, mat, mat, mat, mat, mat]
            return base
        }
        if self == .redstoneLamp {
            let lamp = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
            let mat = makePixelMaterial(kind: .seaLantern)
            lamp.materials = [mat, mat, mat, mat, mat, mat]
            return lamp
        }
        if self == .crop {
            let stalk = SCNBox(width: 0.78, height: 0.48, length: 0.78, chamferRadius: 0.0)
            let mat = makePixelMaterial(kind: .crop, translucent: true)
            stalk.materials = [mat, mat, mat, mat, mat, mat]
            return stalk
        }
        if self == .door {
            let slab = SCNBox(width: 0.26, height: 1.0, length: 0.96, chamferRadius: 0.0)
            let mat = makePixelMaterial(kind: .door)
            slab.materials = [mat, mat, mat, mat, mat, mat]
            return slab
        }
        if self == .bed {
            let mattress = SCNBox(width: 0.96, height: 0.42, length: 0.96, chamferRadius: 0.02)
            let topMat = makePixelMaterial(kind: .bedTop)
            let sideMat = makePixelMaterial(kind: .planks)
            mattress.materials = [sideMat, sideMat, sideMat, sideMat, topMat, sideMat]
            return mattress
        }

        let box = SCNBox(width: 1.0, height: 1.0, length: 1.0, chamferRadius: 0.0)
        switch self {
        case .grass:
            let side = makePixelMaterial(kind: .grassSide)
            let top = makePixelMaterial(kind: .grassTop)
            let bottom = makePixelMaterial(kind: .dirt)
            box.materials = [side, side, side, side, top, bottom]
        case .snowGrass:
            let side = makePixelMaterial(kind: .snowGrassSide)
            let top = makePixelMaterial(kind: .snow)
            let bottom = makePixelMaterial(kind: .dirt)
            box.materials = [side, side, side, side, top, bottom]
        case .snow:
            let mat = makePixelMaterial(kind: .snow); box.materials = [mat, mat, mat, mat, mat, mat]
        case .dirt:
            let mat = makePixelMaterial(kind: .dirt); box.materials = [mat, mat, mat, mat, mat, mat]
        case .sand:
            let mat = makePixelMaterial(kind: .sand); box.materials = [mat, mat, mat, mat, mat, mat]
        case .clay:
            let mat = makePixelMaterial(kind: .clay); box.materials = [mat, mat, mat, mat, mat, mat]
        case .ice:
            let mat = makePixelMaterial(kind: .ice, translucent: true); box.materials = [mat, mat, mat, mat, mat, mat]
        case .water:
            let mat = makePixelMaterial(kind: .water, translucent: true); box.materials = [mat, mat, mat, mat, mat, mat]
        case .wood:
            let side = makePixelMaterial(kind: .woodSide); let end = makePixelMaterial(kind: .woodTop); box.materials = [side, side, side, side, end, end]
        case .spruceLog:
            let side = makePixelMaterial(kind: .spruceSide); let end = makePixelMaterial(kind: .woodTop); box.materials = [side, side, side, side, end, end]
        case .birchLog:
            let side = makePixelMaterial(kind: .birchSide); let end = makePixelMaterial(kind: .woodTop); box.materials = [side, side, side, side, end, end]
        case .leaves:
            let mat = makePixelMaterial(kind: .leaves); box.materials = [mat, mat, mat, mat, mat, mat]
        case .stone:
            let mat = makePixelMaterial(kind: .stone); box.materials = [mat, mat, mat, mat, mat, mat]
        case .cobblestone:
            let mat = makePixelMaterial(kind: .cobblestone); box.materials = [mat, mat, mat, mat, mat, mat]
        case .mossyCobble:
            let mat = makePixelMaterial(kind: .mossyCobble); box.materials = [mat, mat, mat, mat, mat, mat]
        case .stoneBricks:
            let mat = makePixelMaterial(kind: .stoneBricks); box.materials = [mat, mat, mat, mat, mat, mat]
        case .bricks:
            let mat = makePixelMaterial(kind: .bricks); box.materials = [mat, mat, mat, mat, mat, mat]
        case .sandstone:
            let mat = makePixelMaterial(kind: .sandstone); box.materials = [mat, mat, mat, mat, mat, mat]
        case .bedrock:
            let mat = makePixelMaterial(kind: .bedrock); box.materials = [mat, mat, mat, mat, mat, mat]
        case .coalOre:
            let mat = makePixelMaterial(kind: .coalOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .ironOre:
            let mat = makePixelMaterial(kind: .ironOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .goldOre:
            let mat = makePixelMaterial(kind: .goldOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .diamondOre:
            let mat = makePixelMaterial(kind: .diamondOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .emeraldOre:
            let mat = makePixelMaterial(kind: .emeraldOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .redstoneOre:
            let mat = makePixelMaterial(kind: .redstoneOre); mat.emission.contents = UIColor(red: 0.9, green: 0.12, blue: 0.12, alpha: 0.35); box.materials = [mat, mat, mat, mat, mat, mat]
        case .quartzOre:
            let mat = makePixelMaterial(kind: .quartzOre); box.materials = [mat, mat, mat, mat, mat, mat]
        case .planks:
            let mat = makePixelMaterial(kind: .planks); box.materials = [mat, mat, mat, mat, mat, mat]
        case .sprucePlanks:
            let mat = makePixelMaterial(kind: .sprucePlanks); box.materials = [mat, mat, mat, mat, mat, mat]
        case .birchPlanks:
            let mat = makePixelMaterial(kind: .birchPlanks); box.materials = [mat, mat, mat, mat, mat, mat]
        case .craftingTable:
            let top = makePixelMaterial(kind: .craftingTop); let side = makePixelMaterial(kind: .bookshelfSide); let bottom = makePixelMaterial(kind: .planks); box.materials = [side, side, side, side, top, bottom]
        case .furnace:
            let front = makePixelMaterial(kind: .furnaceSide); let other = makePixelMaterial(kind: .cobblestone); box.materials = [front, other, other, other, other, other]
        case .piston:
            let top = makePixelMaterial(kind: .piston); let side = makePixelMaterial(kind: .cobblestone); box.materials = [side, side, side, side, top, side]
        case .bookshelf:
            let side = makePixelMaterial(kind: .bookshelfSide); let topBottom = makePixelMaterial(kind: .planks); box.materials = [side, side, side, side, topBottom, topBottom]
        case .chest:
            let mat = makePixelMaterial(kind: .chest); box.materials = [mat, mat, mat, mat, mat, mat]
        case .wool:
            let mat = makePixelMaterial(kind: .wool); box.materials = [mat, mat, mat, mat, mat, mat]
        case .glass:
            let mat = makePixelMaterial(kind: .glass, translucent: true); box.materials = [mat, mat, mat, mat, mat, mat]
        case .tnt:
            let mat = makePixelMaterial(kind: .tnt); box.materials = [mat, mat, mat, mat, mat, mat]
        case .portal:
            let mat = makePixelMaterial(kind: .portal, translucent: true); mat.emission.contents = UIColor(red: 0.62, green: 0.22, blue: 0.98, alpha: 0.7); box.materials = [mat, mat, mat, mat, mat, mat]
        case .seaLantern:
            let mat = makePixelMaterial(kind: .seaLantern); mat.emission.contents = UIColor(red: 0.65, green: 0.96, blue: 1.0, alpha: 0.65); box.materials = [mat, mat, mat, mat, mat, mat]
        case .prismarine:
            let mat = makePixelMaterial(kind: .seaLantern)
            mat.diffuse.contents = UIColor(red: 0.24, green: 0.66, blue: 0.61, alpha: 1.0)
            box.materials = [mat, mat, mat, mat, mat, mat]
        case .amethyst:
            let mat = makePixelMaterial(kind: .amethyst); mat.emission.contents = UIColor(red: 0.64, green: 0.35, blue: 0.92, alpha: 0.35); box.materials = [mat, mat, mat, mat, mat, mat]
        case .netherrack:
            let mat = makePixelMaterial(kind: .netherrack); box.materials = [mat, mat, mat, mat, mat, mat]
        case .soulSand:
            let mat = makePixelMaterial(kind: .soulSand); box.materials = [mat, mat, mat, mat, mat, mat]
        case .glowstone:
            let mat = makePixelMaterial(kind: .glowstone); mat.emission.contents = UIColor(red: 1.0, green: 0.78, blue: 0.35, alpha: 0.55); box.materials = [mat, mat, mat, mat, mat, mat]
        case .magma:
            let mat = makePixelMaterial(kind: .magma); mat.emission.contents = UIColor(red: 0.95, green: 0.32, blue: 0.06, alpha: 0.65); box.materials = [mat, mat, mat, mat, mat, mat]
        case .endStone:
            let mat = makePixelMaterial(kind: .endStone); box.materials = [mat, mat, mat, mat, mat, mat]
        case .obsidian:
            let mat = makePixelMaterial(kind: .obsidian); box.materials = [mat, mat, mat, mat, mat, mat]
        case .endCrystal:
            let mat = makePixelMaterial(kind: .endCrystal, translucent: true); mat.emission.contents = UIColor(red: 0.76, green: 0.36, blue: 0.98, alpha: 0.75); box.materials = [mat, mat, mat, mat, mat, mat]
        case .torch, .soulTorch, .redstoneDust, .lever, .pressurePlate, .repeater, .redstoneLamp, .button, .crop, .door, .bed:
            break
        }
        return box
    }

    private func makeEmissionMaterial(color: UIColor, emission: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = emission
        mat.roughness.contents = 0.2
        return mat
    }

    private func makePixelMaterial(kind: PixelTextureKind, translucent: Bool = false) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = PixelTextureFactory.image(for: kind)
        mat.diffuse.magnificationFilter = .nearest
        mat.diffuse.minificationFilter = .nearest
        mat.diffuse.mipFilter = .nearest
        mat.roughness.contents = translucent ? 0.15 : 0.9
        mat.metalness.contents = translucent ? 0.1 : 0.0
        if translucent {
            mat.isDoubleSided = true
            mat.transparencyMode = .aOne
            mat.writesToDepthBuffer = false
        }
        return mat
    }
}

struct BlockCoord: Hashable, Codable {
    let x: Int
    let y: Int
    let z: Int

    var scnVector: SCNVector3 { SCNVector3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5) }

    static func from(worldPosition pos: SCNVector3) -> BlockCoord {
        BlockCoord(x: Int(floor(pos.x)), y: Int(floor(pos.y)), z: Int(floor(pos.z)))
    }
}

struct ChunkCoord: Hashable {
    let cx: Int
    let cz: Int
}

struct CropSaveEntry: Codable {
    let x: Int
    let y: Int
    let z: Int
    let stage: Int
}

struct SavedVillagerEntry: Codable {
    let id: UUID
    let x: Float
    let y: Float
    let z: Float
    let yaw: Float
    let hp: Int
    let profession: String
    let homeX: Float?
    let homeY: Float?
    let homeZ: Float?
    let workX: Float?
    let workY: Float?
    let workZ: Float?
    let isBaby: Bool?
    let ageTimer: Float?
}

struct SavedPetEntry: Codable {
    let id: UUID
    let kind: String
    let x: Float
    let y: Float
    let z: Float
    let yaw: Float
    let hp: Int
    let isSitting: Bool
    let isGuarding: Bool?
    let guardX: Float?
    let guardY: Float?
    let guardZ: Float?
}

struct SavedBoatState: Codable {
    let x: Float
    let y: Float
    let z: Float
    let yaw: Float
}

struct SavedWorldSnapshot: Codable {
    let blocks: [SavedVoxelEntry]
    let spawnCoord: BlockCoord?
    let openDoors: [BlockCoord]
    let openedChests: [BlockCoord]
    let activeLevers: [BlockCoord]
    let crops: [CropSaveEntry]
    // Optional fields preserve compatibility with saves created by older builds.
    let inventory: [String: Int]?
    let foodInventory: [String: Int]?
    let gameMode: String?
    let hotbarSlots: [String]?
    let hotbarSelection: Int?
    let equippedGear: String?
    let gearDurability: Int?
    let selectedTool: String?
    let toolTier: String?
    let toolDurability: Int?
    let armorTier: String?
    let armorDurability: Int?
    let helmetTier: String?
    let chestplateTier: String?
    let leggingsTier: String?
    let bootsTier: String?
    let helmetDurability: Int?
    let chestplateDurability: Int?
    let leggingsDurability: Int?
    let bootsDurability: Int?
    let equipmentInventory: [String: Int]?
    let chestStorage: [String: [String: Int]]?
    let experiencePoints: Int?
    let enchantments: [String: Int]?
    let villagers: [SavedVillagerEntry]?
    let potionInventory: [String: Int]?
    let unlockedAchievements: [String]?
    let defeatedHostileCount: Int?
    let activePotionEffects: [String: Float]?
    let boatCount: Int?
    let deployedBoat: SavedBoatState?
    let discoveredBiomes: [String]?
    let pets: [SavedPetEntry]?
}

struct SavedVoxelEntry: Codable {
    let x: Int
    let y: Int
    let z: Int
    let type: BlockType
}

enum GameMode: String, CaseIterable {
    case survival = "Survival"
    case creative = "Creative"
}

enum InteractionTool: String, CaseIterable {
    case place = "Place"
    case breakBlock = "Mine"
}

enum CameraMode: String, CaseIterable {
    case firstPerson = "1st Person"
    case overview = "Overview"
}

// MARK: - Infinite Voxel World Engine

final class VoxelWorldController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    @Published var selectedBlock: BlockType = .grass
    weak var activeSceneView: SCNView?
    @Published var selectedCategory: BlockCategory = .all
    @Published var activeTool: InteractionTool = .place
    @Published var cameraMode: CameraMode = .firstPerson
    @Published var isNightMode: Bool = false
    @Published var isAutoCycleEnabled: Bool = true
    @Published var weather: WeatherKind = .clear
    @Published var equippedGear: GearTier = .iron
    @Published var gearDurability: Int = GearTier.iron.maxDurability
    @Published var selectedTool: ToolKind = .pickaxe
    @Published var toolTier: GearTier = .iron
    @Published var toolDurability: Int = GearTier.iron.maxDurability
    @Published var armorTier: GearTier = .wood
    @Published var armorDurability: Int = GearTier.wood.maxDurability
    @Published var helmetTier: GearTier = .wood
    @Published var chestplateTier: GearTier = .wood
    @Published var leggingsTier: GearTier = .wood
    @Published var bootsTier: GearTier = .wood
    @Published var helmetDurability: Int = GearTier.wood.maxDurability
    @Published var chestplateDurability: Int = GearTier.wood.maxDurability
    @Published var leggingsDurability: Int = GearTier.wood.maxDurability
    @Published var bootsDurability: Int = GearTier.wood.maxDurability
    @Published var miningProgress: Double = 0
    @Published var miningTarget: BlockCoord?
    @Published var multiplayerEnabled: Bool = false
    @Published var connectedPeerCount: Int = 0
    @Published var activeSlot: Int = 1 // World save slot
    @Published var gameMode: GameMode = .creative
    @Published var hotbarSelection: Int = 0
    @Published var hotbarSlots: [BlockType] = [
        .grass, .dirt, .stone, .wood, .planks, .cobblestone, .torch, .glass, .craftingTable
    ]
    @Published var activeDimension: GameDimension = .overworld
    @Published var currentBiome: BiomeType = .plains
    @Published var discoveredBiomes: Set<String> = []
    @Published var coordsText: String = "X: 0  Y: 7  Z: 6"
    @Published var health: Int = 20
    @Published var hunger: Int = 20
    @Published var oxygen: Int = 10
    @Published var stamina: Double = 100
    @Published var isSprinting: Bool = false
    @Published var isUnderwater: Bool = false
    @Published var boatCount: Int = 0
    @Published var isInBoat: Bool = false
    @Published var inventory: [BlockType: Int] = [:]
    @Published var foodInventory: [FoodKind: Int] = [.bread: 4, .cookedMutton: 2, .wheat: 4, .seeds: 4, .carrot: 2]
    @Published var equipmentInventory: [String: Int] = [:]
    @Published var showInventorySheet: Bool = false
    @Published var showChestSheet: Bool = false
    @Published var showVillagerTradeSheet: Bool = false
    @Published var showBrewingSheet: Bool = false
    @Published var potionInventory: [PotionKind: Int] = [:]
    @Published var activePotionEffects: [PotionKind: Float] = [:]
    @Published var isShieldRaised: Bool = false
    @Published var unlockedAchievements: Set<String> = []
    @Published var defeatedHostileCount: Int = 0
    @Published var bossHealthFraction: Double? = nil
    @Published var bossHealthLabel: String = ""
    @Published var miningFatigueRemaining: Float = 0
    @Published var treasureCompassText: String = "Treasure compass: not scanned"
    @Published var treasureCompassTarget: BlockCoord? = nil
    @Published var activeVillagerID: UUID? = nil
    @Published var activeChestKey: String? = nil
    @Published var chestStorage: [String: [String: Int]] = [:]
    @Published var experiencePoints: Int = 0
    @Published var enchantments: [String: Int] = [:]
    @Published var showEnchantingSheet: Bool = false
    @Published var furnaceBurnRemaining: Double = 0.0
    @Published var furnaceSmeltProgress: Double = 0.0
    @Published var queuedSmeltCount: Int = 0
    @Published var showCraftSheet: Bool = false
    @Published var placedOrMinedCount: Int = 0
    @Published var statusMessage: String = "Complete engine active in Sources/Minerva.swift"

    func unlockAchievement(_ id: String) {
        guard AchievementInfo.all.contains(where: { $0.id == id }), !unlockedAchievements.contains(id) else { return }
        unlockedAchievements.insert(id)
        statusMessage = "Achievement unlocked: \(AchievementInfo.all.first(where: { $0.id == id })?.title ?? id)"
        saveWorld()
    }

    private func syncBossHUD() {
        if let elder = mobs.first(where: { $0.isElderGuardian && $0.hp > 0 }) {
            let fraction = max(0, min(1, Double(elder.hp) / 80.0))
            let label = "ELDER GUARDIAN · \(elder.hp) / 80 HP"
            if bossHealthFraction != fraction { bossHealthFraction = fraction }
            if bossHealthLabel != label { bossHealthLabel = label }
            return
        }
        let dragon = mobs.first(where: { $0.kind == .enderDragon && $0.hp > 0 })
        let fraction = dragon.map { max(0, min(1, Double($0.hp) / 28.0)) }
        let label = dragon.map { "ENDER DRAGON · \($0.hp) / 28 HP" } ?? ""
        if bossHealthFraction != fraction { bossHealthFraction = fraction }
        if bossHealthLabel != label { bossHealthLabel = label }
    }

    var visibleBlocks: [BlockType] {
        if selectedCategory == .all { return BlockType.allCases }
        return BlockType.allCases.filter { $0.category == selectedCategory }
    }

    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let blocksRootNode = SCNNode()
    private let chunkMeshesRootNode = SCNNode()
    private let cloudsRootNode = SCNNode()
    private let weatherRootNode = SCNNode()
    private let mobsRootNode = SCNNode()
    private let projectilesRootNode = SCNNode()
    private let dropsRootNode = SCNNode()
    private let avatarNode = SCNNode()
    private let remotePeerNode = SCNNode()
    private let highlightNode: SCNNode
    private let ambientLightNode = SCNNode()
    private let sunLightNode = SCNNode()
    private let lanManager = LANMultiplayerManager()

    private var blocks: [BlockCoord: BlockType] = [:]
    private var blockNodes: [BlockCoord: SCNNode] = [:]
    private var chunkMeshNodes: [ChunkCoord: SCNNode] = [:]
    private var loadedChunks: Set<ChunkCoord> = []
    private var modifiedCoords: Set<BlockCoord> = []
    private var openedChests: Set<BlockCoord> = []
    private var openDoors: Set<BlockCoord> = []
    private var redstoneToggledDoors: Set<BlockCoord> = []
    private var activeLevers: Set<BlockCoord> = []
    private var activePressurePlates: Set<BlockCoord> = []
    private var activeButtons: [BlockCoord: TimeInterval] = [:]
    private var poweredRedstoneLamps: Set<BlockCoord> = []
    private var lastFishingCastAt: TimeInterval = -100
    private var boatNode: SCNNode?
    private var boatPaddles: [SCNNode] = []
    private var boatSpeed: Float = 0
    private var boatTravelDistance: Float = 0
    private var boatAutosaveTimer: Float = 0
    private var dolphinGuideAchievementTimer: Float = 0
    private var extendedPistons: Set<BlockCoord> = []
    private var cropStages: [BlockCoord: Int] = [:]
    private var mobs: [WorldMob] = []
    private var arrows: [ArrowProjectile] = []
    private var droppedItems: [DroppedItemEntity] = []
    private var experienceOrbs: [ExperienceOrbEntity] = []
    private var sharedGeometries: [BlockType: SCNGeometry] = [:]
    private var cloudNodes: [SCNNode] = []
    private var weatherNodes: [SCNNode] = []

    private let chunkSize = 12
    private let chunkRadius = 1
    private let maxViewDistance: Float = 24.0

    private var saveURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("voxel_world_\(activeSlot)_\(activeDimension.fileToken).json")
    }

    private var playerPos = SIMD3<Float>(0.5, 9.0, 6.5)
    private var customSpawnCoord: BlockCoord?
    private var verticalVelocity: Float = 0.0
    private var fallStartY: Float?
    private var hazardTimer: Float = 0.0
    private var hungerDrainTimer: Float = 0.0
    private var simTickTimer: Float = 0.0
    private var cropGrowthTimer: Float = 0.0
    private var cropGrowthCycle: Int = 0
    private var dayClockTimer: Float = 0.0
    private var villagerGrowthTimer: Float = 0.0
    private var regenerationTickTimer: Float = 0.0
    private var naturalRegenerationTimer: Float = 0.0
    private var starvationTimer: Float = 0.0
    private var drowningTimer: Float = 0.0
    private var oxygenTickTimer: Float = 0.0
    private var staminaRecoveryDelay: Float = 0.0
    private var weatherTimer: Float = 0.0
    private var netSyncTimer: Float = 0.0
    private var yaw: Float = 0.0
    private var pitch: Float = -0.15
    private var moveInput = SIMD2<Float>(0, 0)
    private var lastFrameTime: TimeInterval?
    // Keep SwiftUI/state publication work off the 60 FPS render cadence.
    private var lastMainThreadUpdateTime: TimeInterval = 0
    private var pendingNightCycle: Bool?
    private var pendingWeatherCycle = false
    private var nightProgress: Float = 0.0

    override init() {
        let box = SCNBox(width: 1.02, height: 1.02, length: 1.02, chamferRadius: 0.01)
        let wireMat = SCNMaterial()
        wireMat.diffuse.contents = UIColor.white
        wireMat.emission.contents = UIColor.white.withAlphaComponent(0.65)
        wireMat.fillMode = .lines
        wireMat.isDoubleSided = true
        box.materials = [wireMat]
        self.highlightNode = SCNNode(geometry: box)
        self.highlightNode.isHidden = true

        super.init()

        lanManager.onReceivePayload = { [weak self] data in
            self?.handleNetworkData(data)
        }

        seedStartingInventory()
        setupSharedGeometries()
        setupSceneLightingAndSky()
        setupClouds()
        setupWeatherParticles()
        setupPlayerAvatar()
        setupRemotePeerAvatar()
        setupCamera()

        scene.rootNode.addChildNode(chunkMeshesRootNode)
        scene.rootNode.addChildNode(blocksRootNode)
        scene.rootNode.addChildNode(cloudsRootNode)
        scene.rootNode.addChildNode(weatherRootNode)
        scene.rootNode.addChildNode(mobsRootNode)
        scene.rootNode.addChildNode(projectilesRootNode)
        scene.rootNode.addChildNode(dropsRootNode)
        scene.rootNode.addChildNode(avatarNode)
        scene.rootNode.addChildNode(remotePeerNode)
        scene.rootNode.addChildNode(highlightNode)

        loadOrGenerateWorld()
        respawnPlayer()
    }

    private func seedStartingInventory() {
        inventory.removeAll()
        if gameMode == .creative {
            for type in BlockType.allCases { inventory[type] = 64 }
        } else {
            inventory[.grass] = 32
            inventory[.dirt] = 32
            inventory[.wood] = 8
            inventory[.planks] = 16
            inventory[.torch] = 8
            inventory[.cobblestone] = 8
        }
    }

    func setGameMode(_ mode: GameMode) {
        guard gameMode != mode else { return }
        gameMode = mode
        seedStartingInventory()
        selectedBlock = hotbarSlots[hotbarSelection]
        saveWorld()
        statusMessage = mode == .creative
            ? "Creative mode: unlimited block placement"
            : "Survival mode: collect and manage resources"
    }

    /// Stops player input and the SceneKit render loop while the game is paused.
    /// Saving is performed before leaving gameplay so the selected world is preserved.
    func pauseGame() {
        moveInput = SIMD2<Float>(0, 0)
        isSprinting = false
        lastFrameTime = nil
        activeSceneView?.isPlaying = false
        saveWorld()
    }

    /// Restarts the render loop and resets frame timing to avoid a large delta after a pause.
    func resumeGame() {
        lastFrameTime = nil
        activeSceneView?.isPlaying = true
    }

    func selectHotbarSlot(_ index: Int) {
        guard hotbarSlots.indices.contains(index) else { return }
        hotbarSelection = index
        selectedBlock = hotbarSlots[index]
        activeTool = .place
        saveWorld()
    }

    func villager(for id: UUID) -> WorldMob? { mobs.first(where: { $0.id == id && $0.kind == .villager }) }

    func villagerTradeDescription(for profession: VillagerProfession) -> (cost: String, reward: String) {
        switch profession {
        case .farmer: return ("3 Wheat", "2 Bread")
        case .miner: return ("2 Emerald Ore", "3 Iron Ore")
        case .builder: return ("1 Emerald Ore", "8 Planks")
        }
    }

    func completeVillagerTrade() {
        guard let id = activeVillagerID, let villager = villager(for: id) else {
            statusMessage = "This Villager is no longer available"
            showVillagerTradeSheet = false
            return
        }
        switch villager.profession {
        case .farmer:
            guard foodCount(for: .wheat) >= 3 else { statusMessage = "You need 3 Wheat"; return }
            foodInventory[.wheat, default: 0] -= 3
            foodInventory[.bread, default: 0] += 2
            statusMessage = "Farmer trade complete: +2 Bread"
        case .miner:
            guard count(for: .emeraldOre) >= 2 else { statusMessage = "You need 2 Emerald Ore"; return }
            inventory[.emeraldOre, default: 0] -= 2
            _ = addItems(3, of: .ironOre)
            statusMessage = "Miner trade complete: +3 Iron Ore"
        case .builder:
            guard count(for: .emeraldOre) >= 1 else { statusMessage = "You need 1 Emerald Ore"; return }
            inventory[.emeraldOre, default: 0] -= 1
            _ = addItems(8, of: .planks)
            statusMessage = "Builder trade complete: +8 Planks"
        }
        SoundEngine.shared.play(.pickup)
        saveWorld()
    }

    func count(for type: BlockType) -> Int { inventory[type] ?? 0 }

    private func chestKey(for coord: BlockCoord) -> String { "\(coord.x),\(coord.y),\(coord.z)" }

    func openChest(at coord: BlockCoord) {
        guard blocks[coord] == .chest else { return }
        let key = chestKey(for: coord)
        if chestStorage[key] == nil { chestStorage[key] = [:] }
        activeChestKey = key
        showChestSheet = true
        if BiomeType.biomeAt(x: coord.x, z: coord.z, dimension: activeDimension) == .ocean {
            unlockAchievement("wreck_diver")
            let nearbyCrystal = [
                BlockCoord(x: coord.x + 1, y: coord.y, z: coord.z),
                BlockCoord(x: coord.x - 1, y: coord.y, z: coord.z),
                BlockCoord(x: coord.x, y: coord.y, z: coord.z + 1),
                BlockCoord(x: coord.x, y: coord.y, z: coord.z - 1),
                BlockCoord(x: coord.x, y: coord.y + 1, z: coord.z)
            ].contains { blocks[$0] == .amethyst || blocks[$0] == .seaLantern }
            if nearbyCrystal { unlockAchievement("crystal_caver") }
        }
        statusMessage = "Opened chest storage"
    }

    func chestItems(for key: String) -> [(BlockType, Int)] {
        (chestStorage[key] ?? [:]).compactMap { raw, amount in
            guard let type = BlockType(rawValue: raw), amount > 0 else { return nil }
            return (type, amount)
        }.sorted { $0.0.rawValue < $1.0.rawValue }
    }

    func transferToChest(_ type: BlockType, amount requested: Int, chestKey: String) {
        guard requested > 0 else { return }
        let playerCount = count(for: type)
        let contents = chestStorage[chestKey] ?? [:]
        let existing = contents[type.rawValue] ?? 0
        let hasSlot = existing > 0 || contents.filter { $0.value > 0 }.count < 27
        guard hasSlot else { statusMessage = "Chest is full (27 slots)"; return }
        let accepted = min(requested, playerCount, max(0, 64 - existing))
        guard accepted > 0 else { statusMessage = "No room for that stack"; return }
        inventory[type] = playerCount - accepted
        chestStorage[chestKey, default: [:]][type.rawValue] = existing + accepted
        statusMessage = "Moved \(accepted) \(type.rawValue) into chest"
        saveWorld()
    }

    func transferFromChest(_ type: BlockType, amount requested: Int, chestKey: String) {
        guard requested > 0 else { return }
        let available = chestStorage[chestKey]?[type.rawValue] ?? 0
        let playerCount = count(for: type)
        let accepted = min(requested, available, max(0, 64 - playerCount))
        guard accepted > 0 else { statusMessage = "Your inventory stack is full"; return }
        chestStorage[chestKey, default: [:]][type.rawValue] = available - accepted
        if chestStorage[chestKey]?[type.rawValue] == 0 {
            chestStorage[chestKey]?.removeValue(forKey: type.rawValue)
        }
        inventory[type] = playerCount + accepted
        statusMessage = "Moved \(accepted) \(type.rawValue) to inventory"
        saveWorld()
    }

    func transferAmount(for count: Int, choice: ChestTransferChoice) -> Int {
        switch choice {
        case .one: return min(1, count)
        case .half: return count == 1 ? 1 : max(1, count / 2)
        case .all: return count
        }
    }

    var experienceLevel: Int {
        // A compact progression curve: each next level costs progressively more XP.
        var remaining = max(0, experiencePoints)
        var level = 0
        var nextCost = 7
        while remaining >= nextCost && level < 100 {
            remaining -= nextCost
            level += 1
            nextCost = 7 + level * 3
        }
        return level
    }

    var experienceProgress: Double {
        var remaining = max(0, experiencePoints)
        var level = 0
        var nextCost = 7
        while remaining >= nextCost && level < 100 {
            remaining -= nextCost
            level += 1
            nextCost = 7 + level * 3
        }
        return min(1, Double(remaining) / Double(max(1, nextCost)))
    }

    func enchantmentLevel(_ kind: EnchantmentKind) -> Int {
        enchantments[kind.rawValue, default: 0]
    }

    func enchantmentCost(_ kind: EnchantmentKind) -> Int {
        kind.baseCost * (enchantmentLevel(kind) + 1)
    }

    private func totalXPRequired(forLevel level: Int) -> Int {
        guard level > 0 else { return 0 }
        return (0..<level).reduce(0) { partial, currentLevel in partial + 7 + currentLevel * 3 }
    }

    func canEnchant(_ kind: EnchantmentKind) -> Bool {
        gameMode == .survival && enchantmentLevel(kind) < kind.maximumLevel && experienceLevel >= enchantmentCost(kind)
    }

    func applyEnchantment(_ kind: EnchantmentKind) {
        guard canEnchant(kind) else {
            statusMessage = "Need level \(enchantmentCost(kind)) and an available enchantment tier"
            return
        }
        let currentLevel = experienceLevel
        let levelsToSpend = enchantmentCost(kind)
        let xpCost = totalXPRequired(forLevel: currentLevel) - totalXPRequired(forLevel: currentLevel - levelsToSpend)
        experiencePoints = max(0, experiencePoints - xpCost)
        enchantments[kind.rawValue] = enchantmentLevel(kind) + 1
        statusMessage = "Enchanted gear: \(kind.rawValue) \(enchantmentLevel(kind))"
        SoundEngine.shared.play(.pickup)
        saveWorld()
    }

    private func awardExperience(_ amount: Int, at position: SIMD3<Float>) {
        guard amount > 0, gameMode == .survival else { return }
        let sphere = SCNSphere(radius: 0.13)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.35, green: 1.0, blue: 0.48, alpha: 1)
        material.emission.contents = UIColor(red: 0.12, green: 0.75, blue: 0.24, alpha: 1)
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(position.x, position.y + 0.35, position.z)
        dropsRootNode.addChildNode(node)
        experienceOrbs.append(ExperienceOrbEntity(value: amount, position: SIMD3<Float>(position.x, position.y + 0.35, position.z), bobPhase: Float.random(in: 0...6.28), node: node))
    }

    func scanForTreasure() {
        let origin = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y)), z: Int(floor(playerPos.z)))
        let candidates = blocks.compactMap { coord, type -> (BlockCoord, Float)? in
            guard type == .chest else { return nil }
            let dx = Float(coord.x - origin.x), dy = Float(coord.y - origin.y), dz = Float(coord.z - origin.z)
            let distance = sqrt(dx * dx + dy * dy + dz * dz)
            return distance <= 128 ? (coord, distance) : nil
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else {
            treasureCompassTarget = nil
            treasureCompassText = "No mapped treasure nearby · explore more ocean"
            statusMessage = treasureCompassText
            return
        }
        treasureCompassTarget = nearest.0
        let dx = Float(nearest.0.x) - playerPos.x
        let dz = Float(nearest.0.z) - playerPos.z
        let bearing = atan2(dx, -dz) * 180 / .pi
        let normalized = (Int(bearing.rounded()) + 360) % 360
        treasureCompassText = "Treasure · \(Int(nearest.1))m · bearing \(normalized)° · X:\(nearest.0.x) Z:\(nearest.0.z)"
        statusMessage = treasureCompassText
        unlockAchievement("deep_sea_cartographer")
        if mobs.contains(where: { $0.kind == .dolphin && simd_distance($0.position, playerPos) < 18 }) {
            dolphinGuideAchievementTimer = 8
            unlockAchievement("dolphin_friend")
            statusMessage = "Dolphin nearby! Follow it toward the treasure"
        }
    }

    func craftBoat() {
        guard boatCount < 16 else { statusMessage = "Boat storage is full"; return }
        let cost = 5
        guard gameMode == .creative || count(for: .planks) >= cost else {
            statusMessage = "A wooden boat requires 5 Oak Planks"
            return
        }
        if gameMode == .survival { inventory[.planks] = max(0, count(for: .planks) - cost) }
        boatCount += 1
        statusMessage = "Crafted Oak Boat · Boats: \(boatCount)"
        SoundEngine.shared.play(.place)
        saveWorld()
    }

    private func makeBoatNode() -> SCNNode {
        let root = SCNNode()
        root.name = "minerva_player_boat"
        let wood = SCNMaterial()
        wood.diffuse.contents = UIColor(red: 0.43, green: 0.24, blue: 0.11, alpha: 1)
        let darkWood = SCNMaterial()
        darkWood.diffuse.contents = UIColor(red: 0.29, green: 0.15, blue: 0.07, alpha: 1)
        let hull = SCNBox(width: 1.38, height: 0.28, length: 1.72, chamferRadius: 0.08)
        hull.materials = [wood, wood, darkWood, darkWood, wood, wood]
        let hullNode = SCNNode(geometry: hull)
        hullNode.position = SCNVector3(0, 0, 0)
        root.addChildNode(hullNode)
        let bow = SCNBox(width: 1.05, height: 0.24, length: 0.42, chamferRadius: 0.06)
        bow.materials = [wood, wood, wood, wood, wood, wood]
        let bowNode = SCNNode(geometry: bow)
        bowNode.position = SCNVector3(0, 0.015, -0.88)
        bowNode.eulerAngles.x = -0.12
        root.addChildNode(bowNode)
        let seat = SCNBox(width: 0.62, height: 0.12, length: 0.28, chamferRadius: 0.025)
        seat.materials = [darkWood, darkWood, darkWood, darkWood, darkWood, darkWood]
        let seatNode = SCNNode(geometry: seat)
        seatNode.position = SCNVector3(0, 0.22, 0.12)
        root.addChildNode(seatNode)
        boatPaddles.removeAll()
        for side: Float in [-1, 1] {
            let shaft = SCNCylinder(radius: 0.035, height: 1.12)
            shaft.materials = [darkWood]
            let paddle = SCNNode(geometry: shaft)
            paddle.eulerAngles.z = .pi / 2
            paddle.position = SCNVector3(side * 0.78, 0.02, 0.12)
            let blade = SCNBox(width: 0.16, height: 0.48, length: 0.07, chamferRadius: 0.015)
            blade.materials = [wood]
            let bladeNode = SCNNode(geometry: blade)
            bladeNode.position = SCNVector3(0, -0.68, 0)
            paddle.addChildNode(bladeNode)
            root.addChildNode(paddle)
            boatPaddles.append(paddle)
        }
        return root
    }

    func toggleBoat() {
        if isInBoat {
            guard let boat = boatNode else { isInBoat = false; return }
            let side = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
            let candidate = SIMD3<Float>(boat.position.x, boat.position.y + 1.65, boat.position.z) + side * 1.25
            let exitCoord = BlockCoord(x: Int(floor(candidate.x)), y: Int(floor(candidate.y - 1.5)), z: Int(floor(candidate.z)))
            if blocks[exitCoord]?.isPassable == false {
                statusMessage = "No safe room to exit here"
                return
            }
            playerPos = candidate
            boatSpeed = 0
            isInBoat = false
            updateCameraTransform()
            statusMessage = "Left boat · Boat remains in the water"
            saveWorld()
            return
        }

        // Reboard the deployed boat without consuming another boat item.
        if let existingBoat = boatNode {
            let distance = simd_distance(
                playerPos,
                SIMD3<Float>(existingBoat.position.x, existingBoat.position.y + 1.0, existingBoat.position.z)
            )
            guard distance <= 4.0 else {
                statusMessage = "Your deployed boat is elsewhere. Find it before launching another."
                return
            }
            yaw = existingBoat.eulerAngles.y
            isInBoat = true
            boatSpeed = 0
            playerPos = SIMD3<Float>(existingBoat.position.x, existingBoat.position.y + 1.65, existingBoat.position.z)
            verticalVelocity = 0
            updateCameraTransform()
            statusMessage = "Boarded your deployed boat"
            return
        }

        guard boatCount > 0 else { statusMessage = "Craft a boat first"; return }
        guard activeDimension == .overworld else { statusMessage = "Boats can only be used in the Overworld"; return }
        let px = Int(floor(playerPos.x)), pz = Int(floor(playerPos.z))
        var waterTarget: BlockCoord?
        for radius in 0...3 where waterTarget == nil {
            for dx in -radius...radius {
                for dz in -radius...radius where max(abs(dx), abs(dz)) == radius {
                    for dy in -2...1 {
                        let c = BlockCoord(x: px + dx, y: Int(floor(playerPos.y - 1.4)) + dy, z: pz + dz)
                        if blocks[c] == .water { waterTarget = c; break }
                    }
                    if waterTarget != nil { break }
                }
                if waterTarget != nil { break }
            }
        }
        guard let water = waterTarget else { statusMessage = "Move beside water to launch your boat"; return }
        let boat = makeBoatNode()
        let surfaceY = Float(water.y) + 1.06
        boat.position = SCNVector3(Float(water.x) + 0.5, surfaceY, Float(water.z) + 0.5)
        boat.eulerAngles.y = yaw
        scene.rootNode.addChildNode(boat)
        boatNode = boat
        boatCount = max(0, boatCount - 1)
        boatSpeed = 0
        boatTravelDistance = 0
        playerPos = SIMD3<Float>(boat.position.x, boat.position.y + 1.65, boat.position.z)
        verticalVelocity = 0
        isInBoat = true
        updateCameraTransform()
        statusMessage = "Boarded Oak Boat · Use movement controls to row"
        SoundEngine.shared.play(.place)
        saveWorld()
    }

    private func castFishingRod(at waterCoord: BlockCoord) {
        let now = ProcessInfo.processInfo.systemUptime
        let cooldown = 1.6
        guard now - lastFishingCastAt >= cooldown else {
            statusMessage = "Wait before casting again"
            return
        }
        guard activeDimension == .overworld, blocks[waterCoord] == .water else {
            statusMessage = "Cast the fishing rod into water"
            return
        }
        lastFishingCastAt = now

        let bobberGeometry = SCNSphere(radius: 0.105)
        let bobberMaterial = SCNMaterial()
        bobberMaterial.diffuse.contents = UIColor(red: 0.96, green: 0.24, blue: 0.16, alpha: 1)
        bobberMaterial.emission.contents = UIColor(red: 0.25, green: 0.035, blue: 0.02, alpha: 1)
        bobberGeometry.materials = [bobberMaterial]
        let bobber = SCNNode(geometry: bobberGeometry)
        bobber.position = SCNVector3(Float(waterCoord.x) + 0.5, Float(waterCoord.y) + 0.93, Float(waterCoord.z) + 0.5)
        dropsRootNode.addChildNode(bobber)
        let bob = SCNAction.sequence([
            .moveBy(x: 0, y: -0.10, z: 0, duration: 0.22),
            .moveBy(x: 0, y: 0.13, z: 0, duration: 0.22),
            .wait(duration: 0.42),
            .fadeOut(duration: 0.18),
            .removeFromParentNode()
        ])
        bobber.runAction(bob)

        if gameMode == .survival { damageTool() }
        statusMessage = "Fishing..."
        SoundEngine.shared.play(.pickup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) { [weak self] in
            guard let self else { return }
            let roll = Int.random(in: 0..<100)
            if roll < 72 {
                let amount = Int.random(in: 1...2)
                self.foodInventory[.rawFish, default: 0] += amount
                self.awardExperience(Int.random(in: 1...3), at: SIMD3<Float>(Float(waterCoord.x), Float(waterCoord.y) + 1, Float(waterCoord.z)))
                self.unlockAchievement("angler")
                self.statusMessage = "Caught Raw Fish ×\(amount)"
                SoundEngine.shared.play(.pickup)
            } else if roll < 91 {
                let treasure: BlockType = [.prismarine, .goldOre, .emeraldOre, .amethyst, .seaLantern].randomElement() ?? .prismarine
                let amount = treasure == .seaLantern ? 1 : Int.random(in: 1...2)
                _ = self.addItems(amount, of: treasure)
                self.awardExperience(Int.random(in: 2...5), at: SIMD3<Float>(Float(waterCoord.x), Float(waterCoord.y) + 1, Float(waterCoord.z)))
                self.statusMessage = "Fishing treasure: \(treasure.rawValue) ×\(amount)"
                SoundEngine.shared.play(.pickup)
            } else {
                self.statusMessage = "The fish got away. Try another cast"
            }
            self.saveWorld()
        }
    }

    private func miningPower(for block: BlockType) -> Double {
        if gameMode == .creative { return .infinity }
        let condition = toolDurability > 0 ? 1.0 : 0.18
        let tierMultiplier: Double
        switch toolTier {
        case .wood: tierMultiplier = 1.0
        case .iron: tierMultiplier = 1.8
        case .diamond: tierMultiplier = 2.8
        }
        let efficiencyMultiplier = 1.0 + Double(enchantmentLevel(.efficiency)) * 0.22
        let hasteMultiplier = (activePotionEffects[.haste] ?? 0) > 0 ? 1.65 : 1.0
        let underwaterMultiplier = isUnderwater ? 0.45 : 1.0
        let fatigueMultiplier = (gameMode == .survival && miningFatigueRemaining > 0) ? 0.28 : 1.0
        return (tierMultiplier * selectedTool.speedBonus(for: block) * condition * efficiencyMultiplier * hasteMultiplier * underwaterMultiplier * fatigueMultiplier) / max(0.35, block.miningHardness)
    }

    private func damageTool() {
        guard gameMode == .survival, toolDurability > 0 else { return }
        let unbreaking = enchantmentLevel(.unbreaking)
        if unbreaking > 0 && Int.random(in: 0...(unbreaking + 1)) != 0 { return }
        toolDurability = max(0, toolDurability - 1)
        if toolDurability == 0 { statusMessage = "Your \(toolTier.rawValue) \(selectedTool.rawValue.lowercased()) broke" }
    }

    private func damageArmor() {
        guard gameMode == .survival else { return }
        armorDurability = max(0, armorDurability - 1)
        let unbreaking = enchantmentLevel(.unbreaking)
        func shouldWear() -> Bool { unbreaking == 0 || Int.random(in: 0...(unbreaking + 1)) == 0 }
        if helmetDurability > 0 && shouldWear() { helmetDurability -= 1 }
        if chestplateDurability > 0 && shouldWear() { chestplateDurability -= 1 }
        if leggingsDurability > 0 && shouldWear() { leggingsDurability -= 1 }
        if bootsDurability > 0 && shouldWear() { bootsDurability -= 1 }
    }

    var effectiveArmorReduction: Int {
        guard gameMode == .survival else { return 0 }
        func points(_ tier: GearTier, durability: Int) -> Int {
            guard durability > 0 else { return 0 }
            switch tier {
            case .wood: return 0
            case .iron: return 1
            case .diamond: return 2
            }
        }
        return points(helmetTier, durability: helmetDurability)
            + points(chestplateTier, durability: chestplateDurability)
            + points(leggingsTier, durability: leggingsDurability)
            + points(bootsTier, durability: bootsDurability)
            + enchantmentLevel(.protection)
    }

    func equipTool(_ kind: ToolKind) {
        selectedTool = kind
        statusMessage = "Equipped \(toolTier.rawValue) \(kind.rawValue)"
    }

    func cycleToolTier() {
        toolTier = toolTier.next
        toolDurability = toolTier.maxDurability
        statusMessage = "Equipped \(toolTier.rawValue) \(selectedTool.rawValue)"
        saveWorld()
    }

    func cycleArmorTier() {
        armorTier = armorTier.next
        armorDurability = armorTier.maxDurability
        helmetTier = armorTier; chestplateTier = armorTier
        leggingsTier = armorTier; bootsTier = armorTier
        helmetDurability = armorTier.maxDurability; chestplateDurability = armorTier.maxDurability
        leggingsDurability = armorTier.maxDurability; bootsDurability = armorTier.maxDurability
        statusMessage = "Equipped full \(armorTier.rawValue) armour set"
        saveWorld()
    }

    func cycleArmorPiece(_ slot: String) {
        switch slot {
        case "Helmet": helmetTier = helmetTier.next; helmetDurability = helmetTier.maxDurability
        case "Chestplate": chestplateTier = chestplateTier.next; chestplateDurability = chestplateTier.maxDurability
        case "Leggings": leggingsTier = leggingsTier.next; leggingsDurability = leggingsTier.maxDurability
        default: bootsTier = bootsTier.next; bootsDurability = bootsTier.maxDurability
        }
        statusMessage = "Changed \(slot) armour"
        saveWorld()
    }

    @discardableResult
    func addItems(_ amount: Int, of type: BlockType) -> Int {
        guard amount > 0 else { return 0 }
        let current = count(for: type)
        let accepted = min(amount, max(0, 64 - current))
        inventory[type] = current + accepted
        return accepted
    }

    func potionCount(for kind: PotionKind) -> Int { potionInventory[kind] ?? 0 }

    func canBrew(_ kind: PotionKind) -> Bool {
        gameMode == .creative || kind.ingredients.allSatisfy { count(for: $0.0) >= $0.1 }
    }

    func brewPotion(_ kind: PotionKind) {
        guard canBrew(kind) else {
            statusMessage = "Missing ingredients for \(kind.rawValue) potion"
            return
        }
        if gameMode == .survival {
            for (material, amount) in kind.ingredients {
                inventory[material] = max(0, count(for: material) - amount)
            }
        }
        potionInventory[kind, default: 0] = min(64, potionCount(for: kind) + 1)
        SoundEngine.shared.play(.place)
        statusMessage = "Brewed \(kind.rawValue) Potion"
        unlockAchievement("alchemist")
        saveWorld()
    }

    func drinkPotion(_ kind: PotionKind) {
        guard potionCount(for: kind) > 0 else { return }
        potionInventory[kind, default: 0] -= 1
        switch kind {
        case .healing:
            health = min(20, health + 8)
            statusMessage = "Healing potion restored up to 8 HP"
        case .strength, .speed, .resistance, .regeneration,
             .waterBreathing, .fireResistance, .haste:
            activePotionEffects[kind] = kind.duration
            statusMessage = "\(kind.rawValue) active for \(Int(kind.duration)) seconds"
        }
        SoundEngine.shared.play(.eat)
        saveWorld()
    }

    func foodCount(for kind: FoodKind) -> Int { foodInventory[kind] ?? 0 }

    func equipmentCount(for recipe: EquipmentRecipe) -> Int { equipmentInventory[recipe.id] ?? 0 }

    func canCraftEquipment(_ recipe: EquipmentRecipe) -> Bool {
        let hasRoom = (equipmentInventory[recipe.id] ?? 0) < 64
        return hasRoom && (gameMode == .creative || recipe.ingredients.allSatisfy { count(for: $0.0) >= $0.1 })
    }

    func craftEquipment(_ recipe: EquipmentRecipe) {
        guard canCraftEquipment(recipe) else {
            statusMessage = "Not enough materials for \(recipe.title)"
            return
        }
        if gameMode == .survival {
            for (material, amount) in recipe.ingredients {
                inventory[material] = max(0, count(for: material) - amount)
            }
        }
        equipmentInventory[recipe.id, default: 0] += 1
        SoundEngine.shared.play(.place)
        statusMessage = "Crafted \(recipe.title)"
        saveWorld()
    }

    func equipCraftedEquipment(_ recipe: EquipmentRecipe) {
        guard equipmentCount(for: recipe) > 0 else {
            statusMessage = "You don't have \(recipe.title)"
            return
        }
        equipmentInventory[recipe.id, default: 0] -= 1
        if equipmentInventory[recipe.id] == 0 { equipmentInventory.removeValue(forKey: recipe.id) }
        if let tool = recipe.tool {
            selectedTool = tool
            toolTier = recipe.tier
            toolDurability = recipe.tier.maxDurability
        } else if let slot = recipe.armorSlot {
            switch slot {
            case "Helmet": helmetTier = recipe.tier; helmetDurability = recipe.tier.maxDurability
            case "Chestplate": chestplateTier = recipe.tier; chestplateDurability = recipe.tier.maxDurability
            case "Leggings": leggingsTier = recipe.tier; leggingsDurability = recipe.tier.maxDurability
            default: bootsTier = recipe.tier; bootsDurability = recipe.tier.maxDurability
            }
        }
        statusMessage = "Equipped \(recipe.title)"
        saveWorld()
    }

    func cycleGearTier() {
        equippedGear = equippedGear.next
        gearDurability = equippedGear.maxDurability
        statusMessage = "Equipped new \(equippedGear.rawValue) tool/armour set (DMG \(equippedGear.attackDamage), DEF -\(equippedGear.armorReduction))"
    }

    func toggleMultiplayerLobby() {
        multiplayerEnabled.toggle()
        lanManager.setEnabled(multiplayerEnabled)
        connectedPeerCount = lanManager.connectedPeers.count
        if !multiplayerEnabled { remotePeerNode.isHidden = true }
        statusMessage = multiplayerEnabled ? "LAN Multipeer active (searching peers)" : "LAN Multipeer stopped"
    }

    func queueFurnaceSmelt() {
        guard count(for: .coalOre) > 0 && (count(for: .wool) > 0 || count(for: .leaves) > 0) else {
            statusMessage = "Need CoalOre + Wool or Leaves for furnace queue"
            return
        }
        inventory[.coalOre] = max(0, count(for: .coalOre) - 1)
        if count(for: .wool) > 0 {
            inventory[.wool] = max(0, count(for: .wool) - 1)
        } else {
            inventory[.leaves] = max(0, count(for: .leaves) - 1)
        }
        queuedSmeltCount += 1
        furnaceBurnRemaining = max(furnaceBurnRemaining, 8.0)
        statusMessage = "Queued item in Furnace (\(queuedSmeltCount) in queue)"
    }

    func eatFood(_ kind: FoodKind) {
        guard kind.isEdible, foodCount(for: kind) > 0 else { return }
        consumeFood(kind)
    }

    func bakeBread() {
        guard foodCount(for: .wheat) >= 3 else {
            statusMessage = "Need 3 Wheat to bake Bread"
            return
        }
        foodInventory[.wheat, default: 0] -= 3
        foodInventory[.bread, default: 0] += 1
        statusMessage = "Baked 1 Bread from 3 Wheat"
        SoundEngine.shared.play(.place)
        saveWorld()
    }

    func cookFood(_ rawFood: FoodKind) {
        guard let cooked = rawFood.cookingResult else { return }
        guard foodCount(for: rawFood) > 0, count(for: .coalOre) > 0 else {
            statusMessage = "Cooking needs 1 raw meat and 1 CoalOre"
            return
        }
        foodInventory[rawFood, default: 0] -= 1
        inventory[.coalOre, default: 0] -= 1
        foodInventory[cooked, default: 0] += 1
        statusMessage = "Cooked 1 \(cooked.rawValue)"
        SoundEngine.shared.play(.eat)
        saveWorld()
    }

    private func breedingFood(for kind: MobKind) -> FoodKind? {
        switch kind {
        case .sheep, .cow: return .wheat
        case .wolf: return .cookedBeef
        case .fox: return .rawFish
        case .bear: return .cookedMutton
        case .pig: return .carrot
        case .chicken: return .seeds
        case .fish, .dolphin: return nil
        case .turtle: return .seeds
        case .guardian: return nil
        default: return nil
        }
    }

    @discardableResult
    private func tameCompanion(_ mob: WorldMob) -> Bool {
        guard [.wolf, .fox, .bear].contains(mob.kind), !mob.isTamed else { return false }
        let food: FoodKind = mob.kind == .wolf ? .cookedBeef : (mob.kind == .fox ? .rawFish : .cookedMutton)
        guard foodCount(for: food) > 0 else { return false }
        let distance = simd_length(SIMD2<Float>(mob.position.x - playerPos.x, mob.position.z - playerPos.z))
        guard distance <= 5.0 else { statusMessage = "Move closer to tame the \(mob.kind.rawValue)"; return true }
        foodInventory[food, default: 0] -= 1
        let chance: Float = mob.kind == .bear ? 0.28 : 0.48
        if Float.random(in: 0...1) <= chance {
            mob.isTamed = true
            mob.isSitting = false
            mob.node.runAction(SCNAction.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 1.0, duration: 0.12)]))
            unlockAchievement("first_companion")
            let companions = mobs.filter { $0.isTamed }.count
            if companions >= 3 { unlockAchievement("pack_leader") }
            if Set(mobs.filter { $0.isTamed }.map { $0.kind }).isSuperset(of: Set([MobKind.wolf, .fox, .bear])) { unlockAchievement("wildlife_friend") }
            statusMessage = "\(mob.kind.rawValue) tamed! Tap to cycle Follow, Sit and Guard"
            saveWorld()
        } else {
            statusMessage = "The \(mob.kind.rawValue) is not ready to trust you. Try again"
        }
        SoundEngine.shared.play(.eat)
        return true
    }

    @discardableResult
    private func feedAnimal(_ mob: WorldMob) -> Bool {
        guard !mob.isBaby, mob.breedCooldown <= 0, let feed = breedingFood(for: mob.kind), foodCount(for: feed) > 0 else { return false }
        foodInventory[feed, default: 0] -= 1
        mob.loveTimer = 20.0
        if let mate = mobs.first(where: { $0.id != mob.id && $0.kind == mob.kind && !$0.isBaby && $0.breedCooldown <= 0 && $0.loveTimer > 0 && simd_length($0.position - mob.position) < 20.0 }) {
            mob.loveTimer = 0
            mate.loveTimer = 0
            mob.breedCooldown = 60.0
            mate.breedCooldown = 60.0
            spawnBabyAnimal(kind: mob.kind, between: mob.position, and: mate.position)
            statusMessage = "\(mob.kind.rawValue)s bred! A baby has arrived"
        } else {
            statusMessage = "\(mob.kind.rawValue) is ready to breed. Feed another nearby one"
        }
        SoundEngine.shared.play(.eat)
        saveWorld()
        return true
    }

    private func spawnBabyAnimal(kind: MobKind, between first: SIMD3<Float>, and second: SIMD3<Float>) {
        let pos = (first + second) * 0.5
        let ground = Float(highestSolidY(atX: Int(floor(pos.x)), z: Int(floor(pos.z))))
        let babyPos = SIMD3<Float>(pos.x, ground + 1.0, pos.z)
        let node = makeMobNode(kind: kind)
        node.scale = SCNVector3(0.55, 0.55, 0.55)
        node.position = SCNVector3(babyPos.x, babyPos.y, babyPos.z)
        let baby = WorldMob(kind: kind, position: babyPos, yaw: Float.random(in: 0...(Float.pi * 2)), hp: 4, wanderTimer: 1.0, node: node)
        baby.isBaby = true
        baby.ageTimer = 120.0
        node.name = "mob_\(baby.id.uuidString)"
        mobsRootNode.addChildNode(node)
        mobs.append(baby)
    }

    func eatFood() {
        if foodCount(for: .cookedBeef) > 0 { consumeFood(.cookedBeef); return }
        if foodCount(for: .cookedPork) > 0 { consumeFood(.cookedPork); return }
        if foodCount(for: .cookedMutton) > 0 { consumeFood(.cookedMutton); return }
        if foodCount(for: .cookedChicken) > 0 { consumeFood(.cookedChicken); return }
        if foodCount(for: .bread) > 0 { consumeFood(.bread); return }
        if foodCount(for: .carrot) > 0 { consumeFood(.carrot); return }
        guard hunger < 20 || health < 20 else {
            statusMessage = "Health & hunger are already full"
            return
        }
        hunger = min(20, hunger + 4)
        health = min(20, health + 2)
        SoundEngine.shared.play(.eat)
        statusMessage = "Foraged berries (+4 Food, +2 HP)"
    }

    private func consumeFood(_ kind: FoodKind) {
        guard kind.isEdible, foodCount(for: kind) > 0 else { return }
        guard hunger < 20 || health < 20 else {
            statusMessage = "Health & hunger are already full"
            return
        }
        foodInventory[kind] = max(0, foodCount(for: kind) - 1)
        hunger = min(20, hunger + kind.hungerRestore)
        health = min(20, health + kind.healthRestore)
        SoundEngine.shared.play(.eat)
        statusMessage = "Ate \(kind.rawValue) (×\(foodCount(for: kind)) left)"
        saveWorld()
    }

    func canCraft(_ recipe: CraftRecipe) -> Bool {
        for (reqType, reqCount) in recipe.ingredients where count(for: reqType) < reqCount {
            return false
        }
        return true
    }

    func craft(_ recipe: CraftRecipe) {
        guard canCraft(recipe) else {
            statusMessage = "Missing ingredients for \(recipe.title)"
            return
        }
        for (reqType, reqCount) in recipe.ingredients {
            inventory[reqType] = max(0, count(for: reqType) - reqCount)
        }
        if let food = recipe.foodOutput, recipe.foodCount > 0 {
            foodInventory[food] = foodCount(for: food) + recipe.foodCount
            SoundEngine.shared.play(.eat)
            statusMessage = "Cooked \(recipe.title)"
            return
        }
        inventory[recipe.output] = min(64, count(for: recipe.output) + recipe.outputCount)
        selectedBlock = recipe.output
        hotbarSlots[hotbarSelection] = recipe.output
        saveWorld()
        activeTool = .place
        SoundEngine.shared.play(.place)
        statusMessage = "Crafted \(recipe.title)"
    }

    private func setupSharedGeometries() {
        for type in BlockType.allCases {
            sharedGeometries[type] = type.makeGeometry()
        }
    }

    private func setupPlayerAvatar() {
        let bodyGeom = SCNBox(width: 0.45, height: 0.75, length: 0.25, chamferRadius: 0.02)
        let bodyMat = SCNMaterial(); bodyMat.diffuse.contents = UIColor.systemBlue; bodyGeom.materials = [bodyMat]
        let bodyNode = SCNNode(geometry: bodyGeom); bodyNode.position = SCNVector3(0, -0.95, 0)

        let headGeom = SCNBox(width: 0.42, height: 0.42, length: 0.42, chamferRadius: 0.02)
        let headMat = SCNMaterial(); headMat.diffuse.contents = UIColor(red: 0.92, green: 0.72, blue: 0.56, alpha: 1.0); headGeom.materials = [headMat]
        let headNode = SCNNode(geometry: headGeom); headNode.position = SCNVector3(0, -0.35, 0)

        avatarNode.addChildNode(bodyNode)
        avatarNode.addChildNode(headNode)
        avatarNode.isHidden = true
    }

    private func setupRemotePeerAvatar() {
        let bodyGeom = SCNBox(width: 0.45, height: 0.75, length: 0.25, chamferRadius: 0.02)
        let bodyMat = SCNMaterial(); bodyMat.diffuse.contents = UIColor.systemTeal; bodyGeom.materials = [bodyMat]
        let bodyNode = SCNNode(geometry: bodyGeom); bodyNode.position = SCNVector3(0, 0.38, 0)

        let headGeom = SCNBox(width: 0.42, height: 0.42, length: 0.42, chamferRadius: 0.02)
        let headMat = SCNMaterial(); headMat.diffuse.contents = UIColor.systemYellow; headGeom.materials = [headMat]
        let headNode = SCNNode(geometry: headGeom); headNode.position = SCNVector3(0, 0.98, 0)

        remotePeerNode.addChildNode(bodyNode)
        remotePeerNode.addChildNode(headNode)
        remotePeerNode.isHidden = true
    }

    private func setupSceneLightingAndSky() {
        scene.fogStartDistance = 20
        scene.fogEndDistance = 42
        scene.fogDensityExponent = 1.3

        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        scene.rootNode.addChildNode(ambientLightNode)

        sunLightNode.light = SCNLight()
        sunLightNode.light?.type = .directional
        sunLightNode.light?.castsShadow = true
        sunLightNode.light?.shadowSampleCount = 4
        sunLightNode.light?.shadowRadius = 2.0
        scene.rootNode.addChildNode(sunLightNode)

        applySkyLighting(progress: 0.0)
    }

    private func setupClouds() {
        let cloudMat = SCNMaterial()
        cloudMat.diffuse.contents = PixelTextureFactory.image(for: .cloud)
        cloudMat.diffuse.magnificationFilter = .nearest
        cloudMat.diffuse.minificationFilter = .nearest
        cloudMat.isDoubleSided = true
        cloudMat.transparencyMode = .aOne
        cloudMat.writesToDepthBuffer = false

        let cloudPositions: [(Float, Float, Float, CGFloat)] = [
            (-8, 17, -6, 5.0), (6, 17, -10, 6.0), (-2, 17, 4, 4.5), (10, 17, 5, 5.5)
        ]

        for (x, y, z, w) in cloudPositions {
            let geom = SCNBox(width: w, height: 0.9, length: w * 0.65, chamferRadius: 0.0)
            geom.materials = [cloudMat]
            let node = SCNNode(geometry: geom)
            node.position = SCNVector3(x, y, z)
            node.renderingOrder = 5
            cloudsRootNode.addChildNode(node)
            cloudNodes.append(node)
        }
    }

    private func setupWeatherParticles() {
        let dropGeom = SCNBox(width: 0.04, height: 0.24, length: 0.04, chamferRadius: 0.0)
        let dropMat = SCNMaterial()
        dropMat.diffuse.contents = UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 0.65)
        dropGeom.materials = [dropMat]

        for _ in 0..<45 {
            let n = SCNNode(geometry: dropGeom)
            n.position = SCNVector3(Float.random(in: -14...14), Float.random(in: 2...16), Float.random(in: -14...14))
            n.isHidden = true
            weatherRootNode.addChildNode(n)
            weatherNodes.append(n)
        }
    }

    func selectWorldSlot(_ slot: Int) {
        guard slot != activeSlot else { return }
        saveWorld()
        activeSlot = slot
        unlockedAchievements = []
        defeatedHostileCount = 0
        loadOrGenerateWorld()
        respawnPlayer()
    }

    func selectDimension(_ dimension: GameDimension) {
        guard dimension != activeDimension else { return }
        saveWorld()
        activeDimension = dimension
        cloudsRootNode.isHidden = (dimension != .overworld)
        weatherRootNode.isHidden = (dimension != .overworld)
        loadOrGenerateWorld()
        respawnPlayer()
        if dimension == .hell { unlockAchievement("netherbound") }
        if dimension == .endgame { unlockAchievement("the_end") }
        applySkyLighting(progress: nightProgress)
        SoundEngine.shared.play(.portal)
        statusMessage = "Entered \(dimension.rawValue)"
    }

    func toggleDayNight() {
        isNightMode.toggle()
        statusMessage = isNightMode ? "Switched to Night sky" : "Switched to Day sky"
    }

    func toggleAutoCycle() {
        isAutoCycleEnabled.toggle()
        statusMessage = isAutoCycleEnabled ? "Day-Night auto cycle ON" : "Day-Night auto cycle OFF"
    }

    func cycleWeather() {
        let all = WeatherKind.allCases
        let idx = all.firstIndex(of: weather) ?? 0
        weather = all[(idx + 1) % all.count]
        for n in weatherNodes {
            n.isHidden = (weather == .clear || activeDimension != .overworld)
            n.scale = (weather == .snowstorm) ? SCNVector3(2.4, 0.7, 2.4) : SCNVector3(1.0, 1.0, 1.0)
        }
        statusMessage = "Weather: \(weather.rawValue)"
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private func applySkyLighting(progress t: Float) {
        let clamped = max(0.0, min(1.0, t))
        switch activeDimension {
        case .hell:
            scene.background.contents = UIColor(red: 0.25, green: 0.04, blue: 0.04, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.36, green: 0.07, blue: 0.06, alpha: 1.0)
            ambientLightNode.light?.intensity = 340
            ambientLightNode.light?.color = UIColor(red: 0.95, green: 0.42, blue: 0.32, alpha: 1.0)
            sunLightNode.light?.intensity = 680
            sunLightNode.light?.color = UIColor(red: 1.0, green: 0.56, blue: 0.28, alpha: 1.0)
            sunLightNode.eulerAngles = SCNVector3(-Float.pi / 4.0, Float.pi / 5.0, 0)
        case .endgame:
            scene.background.contents = UIColor(red: 0.04, green: 0.02, blue: 0.09, alpha: 1.0)
            scene.fogColor = UIColor(red: 0.14, green: 0.07, blue: 0.24, alpha: 1.0)
            ambientLightNode.light?.intensity = 240
            ambientLightNode.light?.color = UIColor(red: 0.62, green: 0.44, blue: 0.95, alpha: 1.0)
            sunLightNode.light?.intensity = 520
            sunLightNode.light?.color = UIColor(red: 0.84, green: 0.66, blue: 1.0, alpha: 1.0)
            sunLightNode.eulerAngles = SCNVector3(-Float.pi / 3.0, -Float.pi / 4.0, 0)
        case .overworld:
            let skyColor = UIColor(red: CGFloat(lerp(0.53, 0.05, clamped)), green: CGFloat(lerp(0.78, 0.08, clamped)), blue: CGFloat(lerp(0.98, 0.20, clamped)), alpha: 1.0)
            let fogColor = UIColor(red: CGFloat(lerp(0.62, 0.07, clamped)), green: CGFloat(lerp(0.83, 0.10, clamped)), blue: CGFloat(lerp(0.99, 0.24, clamped)), alpha: 1.0)
            scene.background.contents = skyColor
            scene.fogColor = fogColor
            ambientLightNode.light?.intensity = CGFloat(lerp(550, 150, clamped))
            ambientLightNode.light?.color = UIColor(red: CGFloat(lerp(0.94, 0.35, clamped)), green: CGFloat(lerp(0.94, 0.45, clamped)), blue: CGFloat(lerp(0.96, 0.75, clamped)), alpha: 1.0)
            sunLightNode.light?.intensity = CGFloat(lerp(1050, 220, clamped))
            sunLightNode.light?.color = UIColor(red: CGFloat(lerp(1.0, 0.62, clamped)), green: CGFloat(lerp(0.97, 0.74, clamped)), blue: CGFloat(lerp(0.89, 1.0, clamped)), alpha: 1.0)
            sunLightNode.eulerAngles = SCNVector3(lerp(-Float.pi / 3.2, -Float.pi / 5.5, clamped), lerp(Float.pi / 4.0, -Float.pi / 3.0, clamped), 0)
        }
    }

    private func setupCamera() {
        let cam = SCNCamera()
        cam.fieldOfView = 72
        cam.zNear = 0.08
        cam.zFar = 100
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
    }

    func loadOrGenerateWorld() {
        clearAllBlockNodes()
        clearAllChunkMeshes()
        clearAllMobs()
        clearAllDrops()
        clearAllArrows()
        boatNode?.removeFromParentNode()
        boatNode = nil
        boatPaddles.removeAll()
        isInBoat = false
        boatSpeed = 0
        boatAutosaveTimer = 0
        treasureCompassTarget = nil
        treasureCompassText = "Treasure compass: not scanned"
        miningFatigueRemaining = 0
        blocks.removeAll()
        loadedChunks.removeAll()
        modifiedCoords.removeAll()
        openDoors.removeAll()
        redstoneToggledDoors.removeAll()
        openedChests.removeAll()
        chestStorage.removeAll()
        activeLevers.removeAll()
        activePressurePlates.removeAll()
        activeButtons.removeAll()
        poweredRedstoneLamps.removeAll()
        extendedPistons.removeAll()
        cropStages.removeAll()
        discoveredBiomes.removeAll()
        customSpawnCoord = nil
        var savedVillagers: [SavedVillagerEntry]? = nil
        var savedBoatState: SavedBoatState? = nil
        var savedPets: [SavedPetEntry]? = nil

        if let data = try? Data(contentsOf: saveURL) {
            if let snap = try? JSONDecoder().decode(SavedWorldSnapshot.self, from: data) {
                if let savedInventory = snap.inventory {
                    inventory = Dictionary(uniqueKeysWithValues: savedInventory.compactMap { key, value in
                        guard let type = BlockType(rawValue: key) else { return nil }
                        return (type, max(0, value))
                    })
                }
                if let savedFood = snap.foodInventory {
                    foodInventory = Dictionary(uniqueKeysWithValues: savedFood.compactMap { key, value in
                        guard let food = FoodKind(rawValue: key) else { return nil }
                        return (food, max(0, value))
                    })
                }
                if let rawMode = snap.gameMode, let mode = GameMode(rawValue: rawMode) { gameMode = mode }
                if let savedSlots = snap.hotbarSlots {
                    let restored = savedSlots.compactMap { BlockType(rawValue: $0) }
                    if restored.count == 9 { hotbarSlots = restored }
                }
                if let savedSelection = snap.hotbarSelection, (0..<9).contains(savedSelection) { hotbarSelection = savedSelection }
                equipmentInventory = snap.equipmentInventory ?? [:]
                boatCount = max(0, snap.boatCount ?? 0)
                savedBoatState = snap.deployedBoat
                experiencePoints = max(0, snap.experiencePoints ?? 0)
                enchantments = snap.enchantments ?? [:]
                if let savedPotions = snap.potionInventory {
                    potionInventory = Dictionary(uniqueKeysWithValues: savedPotions.compactMap { key, value in
                        guard let potion = PotionKind(rawValue: key) else { return nil }
                        return (potion, max(0, value))
                    })
                }
                unlockedAchievements.formUnion(snap.unlockedAchievements ?? [])
                discoveredBiomes.formUnion(snap.discoveredBiomes ?? [])
                defeatedHostileCount = max(defeatedHostileCount, snap.defeatedHostileCount ?? 0)
                if let savedEffects = snap.activePotionEffects {
                    activePotionEffects = Dictionary(uniqueKeysWithValues: savedEffects.compactMap { key, value in
                        guard let potion = PotionKind(rawValue: key), value > 0 else { return nil }
                        return (potion, min(value, potion.duration))
                    })
                }
                savedVillagers = snap.villagers
                savedPets = snap.pets
                for entry in snap.blocks {
                    let coord = BlockCoord(x: entry.x, y: entry.y, z: entry.z)
                    blocks[coord] = entry.type
                    modifiedCoords.insert(coord)
                }
                customSpawnCoord = snap.spawnCoord
                if let savedGear = snap.equippedGear, let tier = GearTier(rawValue: savedGear) {
                    equippedGear = tier
                    gearDurability = min(tier.maxDurability, max(0, snap.gearDurability ?? tier.maxDurability))
                }
                if let raw = snap.selectedTool, let value = ToolKind(rawValue: raw) { selectedTool = value }
                if let raw = snap.toolTier, let value = GearTier(rawValue: raw) { toolTier = value }
                toolDurability = min(toolTier.maxDurability, max(0, snap.toolDurability ?? toolTier.maxDurability))
                if let raw = snap.armorTier, let value = GearTier(rawValue: raw) { armorTier = value }
                armorDurability = min(armorTier.maxDurability, max(0, snap.armorDurability ?? armorTier.maxDurability))
                if let raw = snap.helmetTier, let value = GearTier(rawValue: raw) { helmetTier = value }
                if let raw = snap.chestplateTier, let value = GearTier(rawValue: raw) { chestplateTier = value }
                if let raw = snap.leggingsTier, let value = GearTier(rawValue: raw) { leggingsTier = value }
                if let raw = snap.bootsTier, let value = GearTier(rawValue: raw) { bootsTier = value }
                helmetDurability = min(helmetTier.maxDurability, max(0, snap.helmetDurability ?? helmetTier.maxDurability))
                chestplateDurability = min(chestplateTier.maxDurability, max(0, snap.chestplateDurability ?? chestplateTier.maxDurability))
                leggingsDurability = min(leggingsTier.maxDurability, max(0, snap.leggingsDurability ?? leggingsTier.maxDurability))
                bootsDurability = min(bootsTier.maxDurability, max(0, snap.bootsDurability ?? bootsTier.maxDurability))
                openDoors = Set(snap.openDoors)
                openedChests = Set(snap.openedChests)
                chestStorage = (snap.chestStorage ?? [:]).mapValues { contents in
                    contents.reduce(into: [String: Int]()) { result, pair in
                        if BlockType(rawValue: pair.key) != nil && pair.value > 0 {
                            result[pair.key] = min(64, pair.value)
                        }
                    }
                }
                activeLevers = Set(snap.activeLevers)
                for c in snap.crops {
                    cropStages[BlockCoord(x: c.x, y: c.y, z: c.z)] = c.stage
                }
            } else if let entries = try? JSONDecoder().decode([SavedVoxelEntry].self, from: data) {
                for entry in entries {
                    let coord = BlockCoord(x: entry.x, y: entry.y, z: entry.z)
                    blocks[coord] = entry.type
                    modifiedCoords.insert(coord)
                }
            }
        }

        updateChunksAroundPlayer(force: true)
        applyRestoredBlockVisualStates()
        if let savedBoatState, activeDimension == .overworld {
            let restoredBoat = makeBoatNode()
            restoredBoat.position = SCNVector3(savedBoatState.x, savedBoatState.y, savedBoatState.z)
            restoredBoat.eulerAngles.y = savedBoatState.yaw
            scene.rootNode.addChildNode(restoredBoat)
            boatNode = restoredBoat
            boatSpeed = 0
            boatTravelDistance = 0
            isInBoat = false
        }
        spawnMobsNearPlayer(aroundX: 0, z: 0)
        if let savedVillagers {
            for mob in mobs where mob.kind == .villager { mob.node.removeFromParentNode() }
            mobs.removeAll { $0.kind == .villager }
            for entry in savedVillagers {
                guard let profession = VillagerProfession(rawValue: entry.profession) else { continue }
                let position = SIMD3<Float>(entry.x, entry.y, entry.z)
                let node = makeMobNode(kind: .villager)
                node.name = "mob_\(entry.id.uuidString)"
                node.position = SCNVector3(position.x, position.y, position.z)
                mobsRootNode.addChildNode(node)
                let villager = WorldMob(id: entry.id, kind: .villager, position: position, yaw: entry.yaw, hp: max(1, entry.hp), wanderTimer: 1.5, node: node)
                villager.profession = profession
                if let x = entry.homeX, let y = entry.homeY, let z = entry.homeZ {
                    villager.homePosition = SIMD3<Float>(x, y, z)
                }
                if let x = entry.workX, let y = entry.workY, let z = entry.workZ {
                    villager.workstationPosition = SIMD3<Float>(x, y, z)
                }
                villager.isBaby = entry.isBaby ?? false
                villager.ageTimer = entry.ageTimer ?? 0
                if villager.homePosition == nil || villager.workstationPosition == nil {
                    assignVillagerDestinations(villager)
                }
                mobs.append(villager)
            }
        }
        restoreSavedPets(savedPets)
        statusMessage = "Loaded \(activeDimension.rawValue)"
    }

    private func applyRestoredBlockVisualStates() {
        for coord in openDoors { blockNodes[coord]?.eulerAngles.y = .pi / 2 }
        for coord in activeLevers { blockNodes[coord]?.eulerAngles.z = .pi / 4 }
        for (coord, stage) in cropStages {
            blockNodes[coord]?.scale = SCNVector3(1.0, CGFloat(0.45 + Double(stage) * 0.22), 1.0)
        }
    }

    func regenerateNewWorld() {
        if FileManager.default.fileExists(atPath: saveURL.path) {
            try? FileManager.default.removeItem(at: saveURL)
        }
        clearAllBlockNodes()
        clearAllChunkMeshes()
        clearAllMobs()
        clearAllDrops()
        clearAllArrows()
        boatNode?.removeFromParentNode()
        boatNode = nil
        boatPaddles.removeAll()
        isInBoat = false
        boatSpeed = 0
        boatAutosaveTimer = 0
        blocks.removeAll()
        loadedChunks.removeAll()
        modifiedCoords.removeAll()
        openDoors.removeAll()
        redstoneToggledDoors.removeAll()
        openedChests.removeAll()
        chestStorage.removeAll()
        activeLevers.removeAll()
        activePressurePlates.removeAll()
        activeButtons.removeAll()
        poweredRedstoneLamps.removeAll()
        extendedPistons.removeAll()
        cropStages.removeAll()
        discoveredBiomes.removeAll()
        customSpawnCoord = nil
        updateChunksAroundPlayer(force: true)
        respawnPlayer()
        spawnMobsNearPlayer(aroundX: Int(floor(playerPos.x)), z: Int(floor(playerPos.z)))
        saveWorld()
        statusMessage = "Reset \(activeDimension.rawValue)"
    }

    private func chunkCoord(forWorldX x: Int, z: Int) -> ChunkCoord {
        ChunkCoord(cx: Int(floor(Double(x) / Double(chunkSize))), cz: Int(floor(Double(z) / Double(chunkSize))))
    }

    private func restoreSavedPets(_ entries: [SavedPetEntry]?) {
        guard let entries else { return }
        for entry in entries {
            guard let kind = MobKind(rawValue: entry.kind), [.wolf, .fox, .bear].contains(kind), mobs.count < 14 else { continue }
            let pos = SIMD3<Float>(entry.x, entry.y, entry.z)
            let node = makeMobNode(kind: kind)
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            node.name = "mob_\(entry.id.uuidString)"
            mobsRootNode.addChildNode(node)
            let pet = WorldMob(id: entry.id, kind: kind, position: pos, yaw: entry.yaw, hp: max(1, entry.hp), wanderTimer: 1.0, node: node)
            pet.isTamed = true
            pet.isSitting = entry.isSitting
            pet.isGuarding = entry.isGuarding ?? false
            if let x = entry.guardX, let y = entry.guardY, let z = entry.guardZ {
                pet.guardPosition = SIMD3<Float>(x, y, z)
            }
            mobs.append(pet)
        }
    }

    private func updateChunksAroundPlayer(force: Bool = false) {
        let px = Int(floor(playerPos.x))
        let pz = Int(floor(playerPos.z))
        let center = chunkCoord(forWorldX: px, z: pz)

        var desired: Set<ChunkCoord> = []
        for dx in -chunkRadius...chunkRadius {
            for dz in -chunkRadius...chunkRadius {
                desired.insert(ChunkCoord(cx: center.cx + dx, cz: center.cz + dz))
            }
        }

        var generatedNewChunk = false
        for chunk in desired where force || !loadedChunks.contains(chunk) {
            generateChunk(chunk)
            loadedChunks.insert(chunk)
            rebuildMergedChunkNode(chunk)
            generatedNewChunk = true
        }

        if generatedNewChunk && !force {
            spawnMobsNearPlayer(aroundX: px, z: pz)
        }

        for chunk in loadedChunks.subtracting(desired) {
            unloadChunk(chunk)
            loadedChunks.remove(chunk)
        }
    }

    // MARK: - Face-Culled Chunk Mesh Builder

    private func rebuildMergedChunkNode(_ chunk: ChunkCoord) {
        chunkMeshNodes[chunk]?.removeFromParentNode()
        chunkMeshNodes.removeValue(forKey: chunk)

        let minX = chunk.cx * chunkSize
        let maxX = minX + chunkSize - 1
        let minZ = chunk.cz * chunkSize
        let maxZ = minZ + chunkSize - 1

        var positions: [SCNVector3] = []
        var uvs: [CGPoint] = []
        var indices: [Int32] = []

        let faces: [((Float, Float, Float), [SIMD3<Float>], (Int, Int, Int))] = [
            ((1, 0, 0), [SIMD3(0.5, -0.5, 0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(0.5, 0.5, 0.5)], (1, 0, 0)),
            ((-1, 0, 0), [SIMD3(-0.5, -0.5, -0.5), SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5), SIMD3(-0.5, 0.5, -0.5)], (-1, 0, 0)),
            ((0, 1, 0), [SIMD3(-0.5, 0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5)], (0, 1, 0)),
            ((0, -1, 0), [SIMD3(-0.5, -0.5, -0.5), SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, -0.5, 0.5), SIMD3(-0.5, -0.5, 0.5)], (0, -1, 0)),
            ((0, 0, 1), [SIMD3(-0.5, -0.5, 0.5), SIMD3(-0.5, 0.5, 0.5), SIMD3(0.5, 0.5, 0.5), SIMD3(0.5, -0.5, 0.5)], (0, 0, 1)),
            ((0, 0, -1), [SIMD3(0.5, -0.5, -0.5), SIMD3(0.5, 0.5, -0.5), SIMD3(-0.5, 0.5, -0.5), SIMD3(-0.5, -0.5, -0.5)], (0, 0, -1))
        ]

        let quadUVs = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0)]

        for x in minX...maxX {
            for z in minZ...maxZ {
                for y in 0...11 {
                    let coord = BlockCoord(x: x, y: y, z: z)
                    guard let type = blocks[coord], !type.isTranslucent, type != .door, type != .bed else { continue }
                    let center = SIMD3<Float>(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)

                    for (_, corners, nOff) in faces {
                        let nb = BlockCoord(x: x + nOff.0, y: y + nOff.1, z: z + nOff.2)
                        if let nbType = blocks[nb], !nbType.isTranslucent { continue }

                        let baseIdx = Int32(positions.count)
                        for i in 0..<4 {
                            let c = center + corners[i]
                            positions.append(SCNVector3(c.x, c.y, c.z))
                            uvs.append(quadUVs[i])
                        }
                        indices.append(contentsOf: [baseIdx, baseIdx + 1, baseIdx + 2, baseIdx, baseIdx + 2, baseIdx + 3])
                    }
                }
            }
        }

        guard !indices.isEmpty else { return }
        let vertexSource = SCNGeometrySource(vertices: positions)
        let uvSource = SCNGeometrySource(textureCoordinates: uvs)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geom = SCNGeometry(sources: [vertexSource, uvSource], elements: [element])

        let mat = SCNMaterial()
        mat.diffuse.contents = PixelTextureFactory.image(for: .stone)
        mat.diffuse.magnificationFilter = .nearest
        mat.diffuse.minificationFilter = .nearest
        mat.isDoubleSided = false
        geom.materials = [mat]

        let node = SCNNode(geometry: geom)
        node.name = "chunk_\(chunk.cx)_\(chunk.cz)"
        node.opacity = 0.01
        chunkMeshesRootNode.addChildNode(node)
        chunkMeshNodes[chunk] = node
    }

    private func clearAllChunkMeshes() {
        for (_, node) in chunkMeshNodes { node.removeFromParentNode() }
        chunkMeshNodes.removeAll()
    }

    private func generateChunk(_ chunk: ChunkCoord) {
        let minX = chunk.cx * chunkSize
        let maxX = minX + chunkSize - 1
        let minZ = chunk.cz * chunkSize
        let maxZ = minZ + chunkSize - 1

        for x in minX...maxX {
            for z in minZ...maxZ {
                let biome = BiomeType.biomeAt(x: x, z: z, dimension: activeDimension)
                let height = terrainHeight(x: x, z: z, biome: biome)

                for y in 0...height {
                    let coord = BlockCoord(x: x, y: y, z: z)
                    if modifiedCoords.contains(coord) { continue }
                    if isCavePocket(x: x, y: y, z: z, surfaceHeight: height) { continue }
                    let block = blockTypeFor(biome: biome, x: x, y: y, z: z, surfaceHeight: height)
                    setBlockInternal(coord: coord, type: block, markModified: false)
                }

                if activeDimension == .overworld && biome == .ocean && height <= 2 {
                    // A real water column instead of the old one-block surface puddle.
                    let oceanHash = abs((x &* 73856093) ^ (z &* 19349663))
                    let waterDepth = 4 + oceanHash % 3
                    for waterY in 3...(3 + waterDepth) {
                        let waterCoord = BlockCoord(x: x, y: waterY, z: z)
                        if blocks[waterCoord] == nil && !modifiedCoords.contains(waterCoord) {
                            setBlockInternal(coord: waterCoord, type: .water, markModified: false)
                        }
                    }
                }

                let hash = abs((x &* 374761393) ^ (z &* 668265263))
                if abs(x) > 2 || abs(z) > 4 {
                    switch biome {
                    case .forest:
                        if height >= 3 && hash % 14 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: (hash % 3 == 0) ? .birchLog : .wood)
                        }
                    case .plains:
                        if height >= 3 && hash % 48 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: .wood)
                        }
                        if height >= 3 && hash % 61 == 0 {
                            placeVillageHut(baseX: x, baseY: height + 1, baseZ: z)
                        }
                    case .highlands:
                        if height >= 5 && hash % 24 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: .spruceLog)
                        }
                    case .taiga:
                        if height >= 3 && hash % 641 == 0 {
                            placeTaigaCabin(baseX: x, baseY: height + 1, baseZ: z)
                        }
                        if height >= 3 && hash % 13 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: .spruceLog)
                        }
                        if hash % 37 == 0 && height >= 3 {
                            setBlockInternal(coord: BlockCoord(x: x, y: height + 1, z: z), type: .snow, markModified: false)
                        }
                    case .jungle:
                        if height >= 3 && hash % 601 == 0 {
                            placeJungleTemple(baseX: x, baseY: height + 1, baseZ: z)
                        }
                        if height >= 3 && hash % 9 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: .wood)
                        }
                        if hash % 23 == 0 && height >= 3 {
                            setBlockInternal(coord: BlockCoord(x: x, y: height + 1, z: z), type: .leaves, markModified: false)
                        }
                    case .swamp:
                        if height >= 2 && hash % 701 == 0 {
                            placeSwampHut(baseX: x, baseY: height + 1, baseZ: z)
                        }
                        if height >= 2 && hash % 21 == 0 {
                            placeTree(baseX: x, baseY: height + 1, baseZ: z, logType: .wood)
                        }
                        if hash % 11 == 0 && height <= 4 {
                            let shallow = BlockCoord(x: x, y: height + 1, z: z)
                            if blocks[shallow] == nil { setBlockInternal(coord: shallow, type: .water, markModified: false) }
                        }
                        if hash % 31 == 0 && height >= 2 {
                            setBlockInternal(coord: BlockCoord(x: x, y: height + 1, z: z), type: .mossyCobble, markModified: false)
                        }
                    case .beach:
                        if height >= 2 && hash % 701 == 0 {
                            placeBeachCamp(baseX: x, baseY: height + 1, baseZ: z)
                        }
                        if height >= 2 && hash % 79 == 0 {
                            setBlockInternal(coord: BlockCoord(x: x, y: height + 1, z: z), type: .wood, markModified: false)
                        }
                    case .hell:
                        if height >= 4 && hash % 29 == 0 {
                            setBlockInternal(coord: BlockCoord(x: x, y: height + 1, z: z), type: .glowstone, markModified: false)
                        }
                    case .endgame:
                        if height >= 3 && hash % 31 == 0 {
                            placeEndPillar(baseX: x, baseY: height + 1, baseZ: z)
                        }
                    case .desert, .ocean:
                        break
                    }

                    if biome != .ocean && hash % 83 == 0 && height >= 3 {
                        placeDungeonRoom(baseX: x, baseY: height + 1, baseZ: z)
                    }

                    if biome == .ocean && height <= 2 {
                        // Keep large structures inside their generating chunk to avoid
                        // neighboring chunks overwriting their hulls during generation.
                        let localX = ((x % chunkSize) + chunkSize) % chunkSize
                        let localZ = ((z % chunkSize) + chunkSize) % chunkSize
                        if localX >= 2 && localX <= 4 && localZ >= 2 && localZ <= 4 {
                            if hash % 173 == 0 {
                                placeOceanRuin(baseX: x, baseY: height + 1, baseZ: z)
                            } else if hash % 251 == 0 {
                                placeShipwreck(baseX: x, baseY: height + 1, baseZ: z, seed: hash)
                            } else if hash % 137 == 0 {
                                placeCoralGarden(baseX: x, baseY: height + 1, baseZ: z, seed: hash)
                            } else if hash % 401 == 0 {
                                placeOceanMonument(baseX: x, baseY: height + 1, baseZ: z)
                            } else if hash % 307 == 0 {
                                placeUnderwaterCrystalCavern(baseX: x, baseZ: z, seed: hash)
                            }
                        }
                    }

                    if biome != .ocean && hash % 97 == 0 {
                        let chestCoord = BlockCoord(x: x, y: height + 1, z: z)
                        if blocks[chestCoord] == nil {
                            setBlockInternal(coord: chestCoord, type: .chest, markModified: false)
                        }
                    }
                }
            }
        }

        // Deterministic underground points of interest. Each structure is contained
        // within its owning chunk so neighboring chunk generation cannot overwrite it.
        if activeDimension == .overworld {
            let structureSeed = abs((chunk.cx &* 92837111) ^ (chunk.cz &* 689287499) ^ 0x45D9F3B)
            let centerX = minX + 3 + (structureSeed % 6)
            let centerZ = minZ + 3 + ((structureSeed / 7) % 6)
            let structureBiome = BiomeType.biomeAt(x: centerX, z: centerZ, dimension: .overworld)
            if structureSeed % 17 == 0 {
                placeAbandonedMineshaft(centerX: centerX, centerZ: centerZ, seed: structureSeed)
            } else if structureSeed % 23 == 0 {
                placeAmethystGeode(centerX: centerX, centerZ: centerZ, seed: structureSeed)
            } else if structureSeed % 29 == 0 {
                placeUndergroundFossil(centerX: centerX, centerZ: centerZ, seed: structureSeed)
            } else if structureSeed % 31 == 0 {
                placeDungeon(centerX: centerX, centerZ: centerZ, seed: structureSeed)
            } else if structureSeed % 37 == 0 {
                let ground = highestSolidY(atX: centerX, z: centerZ)
                placeRuinedPortal(centerX: centerX, baseY: ground + 1, centerZ: centerZ, seed: structureSeed)
            } else if structureBiome == .desert && structureSeed % 13 == 0 {
                let ground = highestSolidY(atX: centerX, z: centerZ)
                placeDesertWell(centerX: centerX, baseY: ground + 1, centerZ: centerZ)
            } else if structureBiome == .jungle && structureSeed % 19 == 0 {
                let ground = highestSolidY(atX: centerX, z: centerZ)
                placeJungleShrine(centerX: centerX, baseY: ground + 1, centerZ: centerZ, seed: structureSeed)
            }
        }

        if chunk.cx == 0 && chunk.cz == 0 {
            let portalGround = highestSolidY(atX: 2, z: 4)
            let portalCoord = BlockCoord(x: 2, y: portalGround + 1, z: 4)
            if blocks[portalCoord] == nil {
                setBlockInternal(coord: portalCoord, type: .portal, markModified: false)
            }
        }
    }

    private func placeShipwreck(baseX: Int, baseY: Int, baseZ: Int, seed: Int) {
        // A broken wooden hull, raised deck, mast and loot room on the ocean floor.
        for dx in 0...6 {
            for dz in 0...8 {
                let edge = dx == 0 || dx == 6 || dz == 0 || dz == 8
                let keel = dx == 3 && dz >= 1 && dz <= 7
                if edge || keel {
                    let coord = BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz)
                    if blocks[coord] == nil || blocks[coord] == .water {
                        setBlockInternal(coord: coord, type: (seed + dx + dz) % 4 == 0 ? .spruceLog : .sprucePlanks, markModified: false)
                    }
                }
                if (dx == 0 || dx == 6) && dz >= 2 && dz <= 6 && (dz + seed) % 3 != 0 {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz), type: .wood, markModified: false)
                }
            }
        }
        for dx in 1...5 {
            for dz in 1...7 where (dx + dz + seed) % 5 != 0 {
                let deck = BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz)
                if blocks[deck] == nil || blocks[deck] == .water {
                    setBlockInternal(coord: deck, type: .sprucePlanks, markModified: false)
                }
            }
        }
        for dy in 1...4 {
            setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1 + dy, z: baseZ + 4), type: .spruceLog, markModified: false)
        }
        let chestA = BlockCoord(x: baseX + 2, y: baseY + 2, z: baseZ + 3)
        let chestB = BlockCoord(x: baseX + 4, y: baseY + 2, z: baseZ + 5)
        setBlockInternal(coord: chestA, type: .chest, markModified: false)
        setBlockInternal(coord: chestB, type: .chest, markModified: false)

        // Seeded loot is stable across chunk reloads. Existing chest contents are
        // never overwritten, so players cannot regenerate emptied treasure.
        let lootAKey = "\(chestA.x),\(chestA.y),\(chestA.z)"
        let lootBKey = "\(chestB.x),\(chestB.y),\(chestB.z)"
        if chestStorage[lootAKey] == nil {
            var loot: [String: Int] = [
                BlockType.ironOre.rawValue: 2 + seed % 3,
                BlockType.prismarine.rawValue: 2 + (seed >> 2) % 4,
                BlockType.coalOre.rawValue: 2 + (seed >> 4) % 3
            ]
            if seed % 5 == 0 { loot[BlockType.goldOre.rawValue] = 1 + (seed >> 3) % 2 }
            chestStorage[lootAKey] = loot
        }
        if chestStorage[lootBKey] == nil {
            var loot: [String: Int] = [
                BlockType.amethyst.rawValue: 1 + (seed >> 5) % 3,
                BlockType.seaLantern.rawValue: 1 + (seed >> 6) % 2
            ]
            if seed % 7 == 0 { loot[BlockType.emeraldOre.rawValue] = 1 }
            chestStorage[lootBKey] = loot
        }
        // A few missing planks make the wreck visibly damaged.
        for (dx, dz) in [(0, 3), (6, 5), (2, 8)] where (seed + dx * 7 + dz) % 2 == 0 {
            removeBlockInternal(at: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), markModified: false)
        }
    }

    private func placeCoralGarden(baseX: Int, baseY: Int, baseZ: Int, seed: Int) {
        // Colorful coral-like clusters use existing voxel materials, so old saves remain compatible.
        let colors: [BlockType] = [.amethyst, .seaLantern, .glass, .glowstone]
        for cluster in 0..<5 {
            let cx = baseX + (seed >> (cluster + 1) & 3) + (cluster % 2)
            let cz = baseZ + (seed >> (cluster + 3) & 3) + (cluster % 3)
            let stemHeight = 1 + (seed >> (cluster + 2) & 1)
            for dy in 0...stemHeight {
                let coord = BlockCoord(x: cx, y: baseY + dy, z: cz)
                if blocks[coord] == nil || blocks[coord] == .water {
                    setBlockInternal(coord: coord, type: colors[(seed + cluster + dy) % colors.count], markModified: false)
                }
            }
            for (dx, dz) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                if (seed + cluster + dx - dz) % 2 == 0 {
                    let branch = BlockCoord(x: cx + dx, y: baseY + stemHeight, z: cz + dz)
                    if blocks[branch] == nil || blocks[branch] == .water {
                        setBlockInternal(coord: branch, type: colors[(cluster + 1) % colors.count], markModified: false)
                    }
                }
            }
        }
        // Kelp-like vertical growth along the garden edge.
        for offset in 0..<4 {
            let kx = baseX + 1 + offset
            let kz = baseZ + 6
            let height = 2 + ((seed >> offset) & 1)
            for dy in 1...height {
                let coord = BlockCoord(x: kx, y: baseY + dy, z: kz)
                if blocks[coord] == nil || blocks[coord] == .water {
                    setBlockInternal(coord: coord, type: .leaves, markModified: false)
                }
            }
        }
    }

    private func seedOceanChestLoot(at coord: BlockCoord, seed: Int, rich: Bool) {
        let key = "\(coord.x),\(coord.y),\(coord.z)"
        guard chestStorage[key] == nil else { return }
        var loot: [String: Int] = [
            BlockType.prismarine.rawValue: rich ? 5 + seed % 5 : 1 + seed % 3,
            BlockType.ironOre.rawValue: rich ? 3 + (seed >> 2) % 4 : 1 + (seed >> 2) % 3,
            BlockType.coalOre.rawValue: 2 + (seed >> 4) % 4
        ]
        if rich {
            loot[BlockType.seaLantern.rawValue] = 2 + (seed >> 5) % 3
            loot[BlockType.goldOre.rawValue] = 1 + (seed >> 6) % 3
        } else if seed % 4 == 0 {
            loot[BlockType.amethyst.rawValue] = 1 + (seed >> 3) % 2
        }
        if seed % 11 == 0 { loot[BlockType.emeraldOre.rawValue] = 1 }
        chestStorage[key] = loot
    }

    private func spawnElderGuardian(at position: SIMD3<Float>) {
        guard !mobs.contains(where: { $0.isElderGuardian && simd_distance($0.position, position) < 18 }) else { return }
        let node = makeMobNode(kind: .guardian)
        node.name = "minerva_elder_guardian"
        node.scale = SCNVector3(1.65, 1.65, 1.65)
        node.position = SCNVector3(position.x, position.y, position.z)
        let crestMaterial = SCNMaterial()
        crestMaterial.diffuse.contents = UIColor(red: 0.96, green: 0.76, blue: 0.28, alpha: 1.0)
        crestMaterial.emission.contents = UIColor(red: 0.22, green: 0.13, blue: 0.02, alpha: 1.0)
        let crest = SCNTorus(ringRadius: 0.31, pipeRadius: 0.055)
        crest.materials = [crestMaterial]
        let crestNode = SCNNode(geometry: crest)
        crestNode.position = SCNVector3(0, 0.56, 0)
        node.addChildNode(crestNode)
        mobsRootNode.addChildNode(node)
        let elder = WorldMob(kind: .guardian, position: position, yaw: 0,
                             hp: 80, wanderTimer: 2.0, node: node)
        elder.isElderGuardian = true
        elder.attackCooldown = 1.8
        mobs.append(elder)
    }

    private func placeOceanMonument(baseX: Int, baseY: Int, baseZ: Int) {
        // A compact submerged temple with lit corners and a central treasure chamber.
        for dx in 0...6 {
            for dz in 0...6 {
                let perimeter = dx == 0 || dx == 6 || dz == 0 || dz == 6
                let floor = BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz)
                setBlockInternal(coord: floor, type: .stoneBricks, markModified: false)
                if perimeter {
                    for dy in 1...3 {
                        let wall = BlockCoord(x: baseX + dx, y: baseY + dy, z: baseZ + dz)
                        setBlockInternal(coord: wall, type: .mossyCobble, markModified: false)
                    }
                }
            }
        }
        for (dx, dz) in [(1, 1), (1, 5), (5, 1), (5, 5)] {
            setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 2, z: baseZ + dz), type: .seaLantern, markModified: false)
        }
        let monumentChest = BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 3)
        setBlockInternal(coord: monumentChest, type: .chest, markModified: false)
        seedOceanChestLoot(at: monumentChest, seed: abs(baseX * 31 + baseZ * 17), rich: true)
        // Each monument has one persistent-in-session boss guardian. The proximity
        // guard in spawnElderGuardian prevents duplicates during nearby chunk refreshes.
        let elderPosition = SIMD3<Float>(Float(baseX + 3) + 0.5,
                                         Float(baseY + 2) + 0.35,
                                         Float(baseZ + 3) + 0.5)
        spawnElderGuardian(at: elderPosition)
        // Open a doorway on the near wall.
        removeBlockInternal(at: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ), markModified: false)
        removeBlockInternal(at: BlockCoord(x: baseX + 3, y: baseY + 2, z: baseZ), markModified: false)
    }

    private func placeUnderwaterCrystalCavern(baseX: Int, baseZ: Int, seed: Int) {
        // A compact air-pocket cavern beneath the seabed. The existing voxel types
        // are reused so worlds from earlier versions remain fully compatible.
        let floorY = 0
        for dx in 0...4 {
            for dz in 0...4 {
                setBlockInternal(coord: BlockCoord(x: baseX + dx, y: floorY, z: baseZ + dz),
                                 type: .stoneBricks, markModified: false)
                let perimeter = dx == 0 || dx == 4 || dz == 0 || dz == 4
                for dy in 1...2 {
                    let wall = BlockCoord(x: baseX + dx, y: floorY + dy, z: baseZ + dz)
                    if perimeter {
                        setBlockInternal(coord: wall,
                                         type: (seed + dx + dz + dy) % 3 == 0 ? .prismarine : .mossyCobble,
                                         markModified: false)
                    } else {
                        removeBlockInternal(at: wall, markModified: false)
                    }
                }
            }
        }

        // A narrow air passage connects the chamber to the surrounding ocean.
        for dz in -2...0 {
            for dy in 1...2 {
                removeBlockInternal(at: BlockCoord(x: baseX + 2, y: floorY + dy, z: baseZ + dz), markModified: false)
            }
        }
        // Remove the water voxel immediately above the chamber to create a visible
        // dive entrance and a breathable pocket below the ocean floor.
        removeBlockInternal(at: BlockCoord(x: baseX + 2, y: 3, z: baseZ + 2), markModified: false)
        let crystalPositions: [(Int, Int, Int)] = [(1, 1, 1), (3, 1, 1), (1, 1, 3), (3, 1, 3), (2, 2, 2)]
        for (dx, dy, dz) in crystalPositions {
            let coord = BlockCoord(x: baseX + dx, y: floorY + dy, z: baseZ + dz)
            setBlockInternal(coord: coord, type: (seed + dx + dz) % 3 == 0 ? .seaLantern : .amethyst, markModified: false)
        }

        let chest = BlockCoord(x: baseX + 2, y: floorY + 1, z: baseZ + 2)
        setBlockInternal(coord: chest, type: .chest, markModified: false)
        seedOceanChestLoot(at: chest, seed: seed, rich: false)
        let key = "\(chest.x),\(chest.y),\(chest.z)"
        if chestStorage[key] != nil {
            chestStorage[key]?[BlockType.amethyst.rawValue] = 2 + seed % 4
            if seed % 4 == 0 { chestStorage[key]?[BlockType.seaLantern.rawValue] = 1 }
        }
    }

    private func placeOceanRuin(baseX: Int, baseY: Int, baseZ: Int) {
        // A compact, partially collapsed seabed ruin with a buried treasure chest.
        for dx in 0...3 {
            for dz in 0...3 where (dx == 0 || dx == 3 || dz == 0 || dz == 3) {
                let coord = BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz)
                if blocks[coord] == nil || blocks[coord] == .water {
                    setBlockInternal(coord: coord, type: (dx + dz) % 2 == 0 ? .mossyCobble : .stoneBricks, markModified: false)
                }
            }
        }
        let chest = BlockCoord(x: baseX + 1, y: baseY, z: baseZ + 1)
        if blocks[chest] == nil || blocks[chest] == .water {
            setBlockInternal(coord: chest, type: .chest, markModified: false)
            seedOceanChestLoot(at: chest, seed: abs(baseX * 31 + baseZ * 17), rich: false)
        }
        for (dx, dz) in [(1, 3), (2, 0), (3, 2)] {
            let broken = BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz)
            if abs((baseX * 31 + baseZ * 17 + dx * 7 + dz) % 3) == 0 {
                removeBlockInternal(at: broken, markModified: false)
            }
        }
    }

    private func placeDungeonRoom(baseX: Int, baseY: Int, baseZ: Int) {
        for dx in 0...4 {
            for dz in 0...4 {
                let floorC = BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz)
                setBlockInternal(coord: floorC, type: (dx + dz) % 2 == 0 ? .mossyCobble : .stoneBricks, markModified: false)
                let isWall = (dx == 0 || dx == 4 || dz == 0 || dz == 4)
                if isWall {
                    for dy in 1...3 {
                        if !(dx == 2 && dz == 0 && dy <= 2) {
                            setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + dy, z: baseZ + dz), type: .stoneBricks, markModified: false)
                        }
                    }
                }
            }
        }
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ + 2), type: .chest, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 1, y: baseY + 1, z: baseZ + 1), type: .soulTorch, markModified: false)
    }

    private func placeVillageHut(baseX: Int, baseY: Int, baseZ: Int) {
        // Compact 5x5 village house. Deterministic placement keeps chunk generation repeatable.
        for dx in 0...4 {
            for dz in 0...4 {
                setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), type: .cobblestone, markModified: false)
                setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 3, z: baseZ + dz), type: .planks, markModified: false)
                if dx == 0 || dx == 4 || dz == 0 || dz == 4 {
                    if !(dx == 2 && dz == 0) {
                        setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz), type: .wood, markModified: false)
                        setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 2, z: baseZ + dz), type: .planks, markModified: false)
                    }
                }
            }
        }
        // Doorway and interior furnishing
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ), type: .door, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 1, y: baseY + 1, z: baseZ + 2), type: .bed, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 2), type: .craftingTable, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 3), type: .furnace, markModified: false)
        // Small farm plot beside the house
        for dx in 1...3 {
            let cropCoord = BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + 5)
            setBlockInternal(coord: cropCoord, type: .crop, markModified: false)
            cropStages[cropCoord] = 2
        }
        // A short path leading to the entrance
        for step in 1...3 {
            let pathCoord = BlockCoord(x: baseX + 2, y: baseY - 1, z: baseZ - step)
            if blocks[pathCoord] == nil {
                setBlockInternal(coord: pathCoord, type: .cobblestone, markModified: false)
            }
        }
    }

    private func unloadChunk(_ chunk: ChunkCoord) {
        chunkMeshNodes[chunk]?.removeFromParentNode()
        chunkMeshNodes.removeValue(forKey: chunk)

        let minX = chunk.cx * chunkSize
        let maxX = minX + chunkSize - 1
        let minZ = chunk.cz * chunkSize
        let maxZ = minZ + chunkSize - 1

        for coord in blocks.keys where coord.x >= minX && coord.x <= maxX && coord.z >= minZ && coord.z <= maxZ && !modifiedCoords.contains(coord) {
            blocks.removeValue(forKey: coord)
            blockNodes[coord]?.removeFromParentNode()
            blockNodes.removeValue(forKey: coord)
        }
    }

    private func isCavePocket(x: Int, y: Int, z: Int, surfaceHeight: Int) -> Bool {
        guard y > 0 && y < surfaceHeight - 1 else { return false }
        let wave = sin(Float(x) * 0.45 + Float(y) * 0.6) * cos(Float(z) * 0.45 - Float(y) * 0.4)
        let tunnel = sin(Float(x) * 0.19 + Float(z) * 0.13) * cos(Float(z) * 0.17 - Float(y) * 0.31)
        let branch = cos(Float(x) * 0.11 - Float(y) * 0.24) * sin(Float(z) * 0.16 + Float(y) * 0.20)
        return wave > 0.76 || (tunnel > 0.91 && branch > -0.05 && y < surfaceHeight - 2)
    }

    private func blockTypeFor(biome: BiomeType, x: Int, y: Int, z: Int, surfaceHeight: Int) -> BlockType {
        if y == 0 { return .bedrock }
        switch activeDimension {
        case .hell:
            let h = abs((x &* 73856093) ^ (y &* 19349663) ^ (z &* 83492791)) % 100
            if y == 1 { return .magma }
            if y == surfaceHeight {
                if h < 18 { return .soulSand }
                if h < 26 { return .magma }
                return .netherrack
            }
            if h < 6 { return .quartzOre }
            if h < 11 { return .glowstone }
            return .netherrack
        case .endgame:
            if y == surfaceHeight - 1 && abs((x + z) % 7) == 0 { return .obsidian }
            return .endStone
        case .overworld:
            switch biome {
            case .desert:
                if y == surfaceHeight || y == surfaceHeight - 1 { return .sand }
                if y == surfaceHeight - 2 { return .sandstone }
                return oreForCoordinate(x: x, y: y, z: z)
            case .highlands:
                if y == surfaceHeight { return y >= 7 ? .snow : .stone }
                if y == surfaceHeight - 1 && y >= 7 { return .snowGrass }
                return oreForCoordinate(x: x, y: y, z: z)
            case .ocean, .beach:
                if y == surfaceHeight { return .sand }
                if y >= surfaceHeight - 1 { return .sandstone }
                return oreForCoordinate(x: x, y: y, z: z)
            case .swamp:
                if y == surfaceHeight { return .grass }
                if y >= surfaceHeight - 2 { return .clay }
                return oreForCoordinate(x: x, y: y, z: z)
            case .taiga:
                if y == surfaceHeight { return .snowGrass }
                if y == surfaceHeight - 1 { return .dirt }
                return oreForCoordinate(x: x, y: y, z: z)
            case .jungle, .plains, .forest:
                if y == surfaceHeight { return .grass }
                if y >= surfaceHeight - 2 { return .dirt }
                return oreForCoordinate(x: x, y: y, z: z)
            case .hell, .endgame:
                return .stone
            }
        }
    }

    private func oreForCoordinate(x: Int, y: Int, z: Int) -> BlockType {
        // Small deterministic 3D vein cells create connected deposits rather than
        // isolated single-block ore speckles. The original depth rules remain as fallback.
        let cellX = x >> 2
        let cellY = y >> 1
        let cellZ = z >> 2
        let veinHash = abs((cellX &* 73856093) ^ (cellY &* 19349663) ^ (cellZ &* 83492791)) % 100
        let localX = x & 3
        let localZ = z & 3
        let localY = y & 1
        let veinShape = (localX + localZ + localY + (veinHash % 3)) % 5 != 0
        if veinShape {
            if y <= 2 && veinHash < 5 { return .diamondOre }
            if y <= 3 && veinHash >= 5 && veinHash < 12 { return .redstoneOre }
            if y <= 4 && veinHash >= 12 && veinHash < 22 { return .goldOre }
            if y <= 6 && veinHash >= 22 && veinHash < 38 { return .ironOre }
            if veinHash >= 38 && veinHash < 55 { return .coalOre }
            if y <= 2 && veinHash == 56 { return .emeraldOre }
        }
        let h = abs((x &* 73856093) ^ (y &* 19349663) ^ (z &* 83492791)) % 100
        if y <= 2 {
            if h < 2 { return .emeraldOre }
            if h < 5 { return .diamondOre }
            if h < 11 { return .goldOre }
            if h < 19 { return .redstoneOre }
        }
        if y <= 4 && h < 10 { return .ironOre }
        if h < 17 { return .coalOre }
        return .stone
    }

    private func terrainHeight(x: Int, z: Int, biome: BiomeType) -> Int {
        let fx = Float(x)
        let fz = Float(z)
        let baseWave = sin(fx * 0.22) * cos(fz * 0.22) * 1.8 + sin((fx + fz) * 0.11) * 1.2
        let raw: Int
        switch biome {
        case .ocean: raw = Int(round(1.5 + baseWave * 0.28))
        case .beach: raw = Int(round(2.2 + baseWave * 0.24))
        case .swamp: raw = Int(round(2.5 + baseWave * 0.22))
        case .taiga: raw = Int(round(4.4 + baseWave * 1.05))
        case .jungle: raw = Int(round(4.6 + baseWave * 1.15))
        case .plains: raw = Int(round(3.6 + baseWave * 0.75))
        case .desert: raw = Int(round(3.4 + sin(fx * 0.28 + fz * 0.14) * 1.3))
        case .forest: raw = Int(round(4.2 + baseWave))
        case .highlands: raw = Int(round(5.0 + abs(cos(fx * 0.19) * sin(fz * 0.19)) * 4.5 + baseWave * 0.6))
        case .hell: raw = Int(round(4.0 + abs(sin(fx * 0.27 - fz * 0.19)) * 3.8 + baseWave * 0.7))
        case .endgame: raw = Int(round(4.5 + cos(fx * 0.17) * cos(fz * 0.17) * 2.5))
        }
        return max(1, min(10, raw))
    }

    private func setGeneratedBlock(_ coord: BlockCoord, type: BlockType) {
        guard coord.y > 0, !modifiedCoords.contains(coord) else { return }
        setBlockInternal(coord: coord, type: type, markModified: false)
    }

    private func clearGeneratedVolume(x: ClosedRange<Int>, y: ClosedRange<Int>, z: ClosedRange<Int>) {
        for bx in x {
            for by in y {
                for bz in z {
                    let coord = BlockCoord(x: bx, y: by, z: bz)
                    // Never carve bedrock or player-modified blocks.
                    guard by > 0, !modifiedCoords.contains(coord) else { continue }
                    blocks.removeValue(forKey: coord)
                    blockNodes[coord]?.removeFromParentNode()
                    blockNodes.removeValue(forKey: coord)
                }
            }
        }
    }

    private func placeAbandonedMineshaft(centerX: Int, centerZ: Int, seed: Int) {
        let baseY = 1
        let x0 = centerX - 3, z0 = centerZ - 3
        clearGeneratedVolume(x: x0...(x0 + 6), y: 2...5, z: z0...(z0 + 6))
        for dx in 0...6 {
            for dz in 0...6 {
                let floor = BlockCoord(x: x0 + dx, y: baseY, z: z0 + dz)
                setGeneratedBlock(floor, type: .cobblestone)
                if dx == 0 || dx == 6 || dz == 0 || dz == 6 {
                    for dy in 2...4 {
                        let wall = BlockCoord(x: x0 + dx, y: dy, z: z0 + dz)
                        if dy == 2 || dy == 4 || (dx == 0 || dx == 6) {
                            setGeneratedBlock(wall, type: .planks)
                        }
                    }
                }
            }
        }
        for dx in [0, 6] {
            for dz in [0, 6] {
                for dy in 2...5 {
                    setGeneratedBlock(BlockCoord(x: x0 + dx, y: dy, z: z0 + dz), type: .wood)
                }
            }
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: 2, z: centerZ), type: .chest)
        setGeneratedBlock(BlockCoord(x: centerX - 2, y: 2, z: centerZ), type: .torch)
        setGeneratedBlock(BlockCoord(x: centerX + 2, y: 2, z: centerZ), type: .torch)
        if seed % 2 == 0 {
            setGeneratedBlock(BlockCoord(x: centerX, y: 2, z: centerZ + 2), type: .furnace)
        }
    }

    private func placeAmethystGeode(centerX: Int, centerZ: Int, seed: Int) {
        let centerY = 3 + seed % 2
        for dx in -3...3 {
            for dy in -3...3 {
                for dz in -3...3 {
                    let distance = dx * dx + dy * dy + dz * dz
                    guard distance <= 9 else { continue }
                    let coord = BlockCoord(x: centerX + dx, y: centerY + dy, z: centerZ + dz)
                    guard coord.y > 0, !modifiedCoords.contains(coord) else { continue }
                    if distance >= 5 {
                        setGeneratedBlock(coord, type: .amethyst)
                    } else {
                        blocks.removeValue(forKey: coord)
                        blockNodes[coord]?.removeFromParentNode()
                        blockNodes.removeValue(forKey: coord)
                    }
                }
            }
        }
        for (dx, dy, dz) in [(0, 0, 0), (1, 0, 0), (-1, 0, 0), (0, 1, 0)] {
            setGeneratedBlock(BlockCoord(x: centerX + dx, y: centerY + dy, z: centerZ + dz), type: .seaLantern)
        }
    }

    private func placeDungeon(centerX: Int, centerZ: Int, seed: Int) {
        let x0 = centerX - 2
        let z0 = centerZ - 2
        clearGeneratedVolume(x: x0...(x0 + 4), y: 2...5, z: z0...(z0 + 4))
        for dx in 0...4 {
            for dz in 0...4 {
                setGeneratedBlock(BlockCoord(x: x0 + dx, y: 1, z: z0 + dz), type: .stoneBricks)
                for y in 2...4 where dx == 0 || dx == 4 || dz == 0 || dz == 4 {
                    let wallType: BlockType = (seed + dx * 7 + dz * 11 + y) % 4 == 0 ? .mossyCobble : .cobblestone
                    setGeneratedBlock(BlockCoord(x: x0 + dx, y: y, z: z0 + dz), type: wallType)
                }
            }
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: 2, z: centerZ), type: .redstoneLamp)
        setGeneratedBlock(BlockCoord(x: centerX - 1, y: 2, z: centerZ + 1), type: .chest)
        if seed % 2 == 0 {
            setGeneratedBlock(BlockCoord(x: centerX + 1, y: 2, z: centerZ - 1), type: .chest)
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: 3, z: z0), type: .torch)
    }

    private func placeRuinedPortal(centerX: Int, baseY: Int, centerZ: Int, seed: Int) {
        // A broken, partially buried frame using existing obsidian and netherrack blocks.
        let frame: [(Int, Int)] = [(-2, 0), (-2, 1), (-2, 2), (-1, 3), (0, 3), (1, 3), (2, 2), (2, 1), (2, 0), (1, 0)]
        for (dx, dy) in frame {
            let coord = BlockCoord(x: centerX + dx, y: baseY + dy, z: centerZ)
            setGeneratedBlock(coord, type: (seed + dx + dy) % 4 == 0 ? .netherrack : .obsidian)
        }
        for dx in -2...2 where (seed + dx) % 2 == 0 {
            setGeneratedBlock(BlockCoord(x: centerX + dx, y: baseY - 1, z: centerZ), type: .magma)
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: baseY, z: centerZ + 1), type: .chest)
        setGeneratedBlock(BlockCoord(x: centerX - 1, y: baseY, z: centerZ - 1), type: .netherrack)
    }

    private func placeDesertWell(centerX: Int, baseY: Int, centerZ: Int) {
        for dx in -2...2 {
            for dz in -2...2 {
                if abs(dx) == 2 || abs(dz) == 2 {
                    setGeneratedBlock(BlockCoord(x: centerX + dx, y: baseY, z: centerZ + dz), type: .sandstone)
                }
            }
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: baseY, z: centerZ), type: .water)
        for (dx, dz) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] {
            setGeneratedBlock(BlockCoord(x: centerX + dx, y: baseY + 1, z: centerZ + dz), type: .sandstone)
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: baseY + 2, z: centerZ), type: .sandstone)
    }

    private func placeJungleShrine(centerX: Int, baseY: Int, centerZ: Int, seed: Int) {
        for dx in -2...2 {
            for dz in -2...2 {
                let edge = abs(dx) == 2 || abs(dz) == 2
                setGeneratedBlock(BlockCoord(x: centerX + dx, y: baseY, z: centerZ + dz), type: edge ? .mossyCobble : .stoneBricks)
                if edge && (dx + dz + seed) % 3 != 0 {
                    setGeneratedBlock(BlockCoord(x: centerX + dx, y: baseY + 1, z: centerZ + dz), type: .stoneBricks)
                }
            }
        }
        setGeneratedBlock(BlockCoord(x: centerX, y: baseY + 1, z: centerZ), type: .chest)
        setGeneratedBlock(BlockCoord(x: centerX, y: baseY + 2, z: centerZ), type: .glowstone)
        setGeneratedBlock(BlockCoord(x: centerX - 1, y: baseY + 1, z: centerZ - 1), type: .torch)
    }

    private func placeUndergroundFossil(centerX: Int, centerZ: Int, seed: Int) {
        let y = 2
        for segment in 0...5 {
            let offset = segment - 2
            let coord = BlockCoord(x: centerX + offset, y: y + (segment % 2), z: centerZ + ((segment % 3) - 1))
            guard !modifiedCoords.contains(coord) else { continue }
            setGeneratedBlock(coord, type: .sandstone)
            if segment % 2 == 0 {
                setGeneratedBlock(BlockCoord(x: coord.x, y: coord.y + 1, z: coord.z), type: .sandstone)
            }
        }
        if seed % 3 == 0 {
            setGeneratedBlock(BlockCoord(x: centerX, y: y, z: centerZ + 2), type: .chest)
        }
    }

    private func placeSwampHut(baseX: Int, baseY: Int, baseZ: Int) {
        // Small raised hut with a mossy foundation and a storage chest.
        for dx in 0...4 {
            for dz in 0...4 {
                let edge = dx == 0 || dx == 4 || dz == 0 || dz == 4
                if edge || (dx == 2 && dz == 2) {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), type: .wood, markModified: false)
                }
                if dx == 0 || dx == 4 || dz == 0 || dz == 4 {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz), type: .planks, markModified: false)
                }
            }
        }
        for dx in 0...4 {
            for dz in 0...4 where dx == 0 || dx == 4 || dz == 0 || dz == 4 {
                setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 2, z: baseZ + dz), type: .sprucePlanks, markModified: false)
            }
        }
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ + 2), type: .chest, markModified: false)
    }

    private func placeJungleTemple(baseX: Int, baseY: Int, baseZ: Int) {
        // Compact overgrown ruin; deliberately uses existing blocks and chest storage.
        for dx in 0...5 {
            for dz in 0...5 {
                let edge = dx == 0 || dx == 5 || dz == 0 || dz == 5
                if edge || (dx == 2 && dz == 2) || (dx == 3 && dz == 3) {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), type: .mossyCobble, markModified: false)
                }
                if edge && (dx + dz) % 3 != 0 {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz), type: .stoneBricks, markModified: false)
                }
            }
        }
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ + 2), type: .chest, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 3), type: .chest, markModified: false)
    }

    private func placeTaigaCabin(baseX: Int, baseY: Int, baseZ: Int) {
        for dx in 0...4 {
            for dz in 0...4 {
                setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), type: .sprucePlanks, markModified: false)
                if dx == 0 || dx == 4 || dz == 0 || dz == 4 {
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + dz), type: .spruceLog, markModified: false)
                    setBlockInternal(coord: BlockCoord(x: baseX + dx, y: baseY + 2, z: baseZ + dz), type: .sprucePlanks, markModified: false)
                }
            }
        }
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ + 2), type: .furnace, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 1, y: baseY + 1, z: baseZ + 2), type: .chest, markModified: false)
    }

    private func placeBeachCamp(baseX: Int, baseY: Int, baseZ: Int) {
        setBlockInternal(coord: BlockCoord(x: baseX, y: baseY, z: baseZ), type: .planks, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 1, y: baseY, z: baseZ), type: .planks, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX, y: baseY + 1, z: baseZ), type: .torch, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY, z: baseZ + 1), type: .chest, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX - 1, y: baseY, z: baseZ + 1), type: .wood, markModified: false)
    }

    private func placeTree(baseX: Int, baseY: Int, baseZ: Int, logType: BlockType) {
        for dy in 0..<4 {
            setBlockInternal(coord: BlockCoord(x: baseX, y: baseY + dy, z: baseZ), type: logType, markModified: false)
        }
        let canopyCenterY = baseY + 4
        for dx in -2...2 {
            for dy in -1...2 {
                for dz in -2...2 where dx * dx + dy * dy + dz * dz <= 6 {
                    let leafCoord = BlockCoord(x: baseX + dx, y: canopyCenterY + dy, z: baseZ + dz)
                    if blocks[leafCoord] == nil {
                        setBlockInternal(coord: leafCoord, type: .leaves, markModified: false)
                    }
                }
            }
        }
    }

    private func placeEndPillar(baseX: Int, baseY: Int, baseZ: Int) {
        for dy in 0..<3 {
            setBlockInternal(coord: BlockCoord(x: baseX, y: baseY + dy, z: baseZ), type: .obsidian, markModified: false)
        }
        setBlockInternal(coord: BlockCoord(x: baseX, y: baseY + 3, z: baseZ), type: .endCrystal, markModified: false)
    }

    // MARK: - Mobs, Arrows & Dropped Items

    private func clearAllMobs() {
        for mob in mobs { mob.node.removeFromParentNode() }
        mobs.removeAll()
    }

    private func clearAllDrops() {
        for drop in droppedItems { drop.node.removeFromParentNode() }
        droppedItems.removeAll()
        for orb in experienceOrbs { orb.node.removeFromParentNode() }
        experienceOrbs.removeAll()
    }

    private func clearAllArrows() {
        for a in arrows { a.node.removeFromParentNode() }
        arrows.removeAll()
    }

    private func spawnMobsNearPlayer(aroundX cx: Int, z cz: Int) {
        while mobs.count > 14 {
            let removed = mobs.removeFirst()
            removed.node.removeFromParentNode()
        }

        // Spawn livestock in pairs so breeding is possible without waiting for another chunk.
        let kinds: [MobKind]
        switch activeDimension {
        case .overworld:
            let spawnBiome = BiomeType.biomeAt(x: cx, z: cz, dimension: .overworld)
            switch spawnBiome {
            case .swamp:
                kinds = [.pig, .chicken, .sheep, .fox, .bear, .slime, .zombie, .spider, .villager]
            case .jungle:
                kinds = [.pig, .chicken, .sheep, .fox, .wolf, .spider, .zombie, .skeleton, .villager]
            case .taiga, .highlands:
                kinds = [.sheep, .sheep, .cow, .chicken, .wolf, .bear, .skeleton, .zombie, .spider, .villager]
            case .desert:
                kinds = [.pig, .chicken, .zombie, .zombie, .skeleton, .spider, .sheep, .villager]
            case .forest:
                kinds = [.sheep, .sheep, .pig, .cow, .chicken, .fox, .wolf, .spider, .zombie, .villager, .villager]
            case .plains, .beach, .ocean:
                kinds = [.sheep, .sheep, .pig, .cow, .chicken, .wolf, .villager, .villager, .zombie, .skeleton]
            case .hell, .endgame:
                kinds = [.zombie, .skeleton]
            }
        case .hell:
            kinds = [.blaze, .blaze, .skeleton, .slime, .zombie, .enderman, .blaze, .skeleton]
        case .endgame:
            kinds = [.enderman, .enderman, .slime, .skeleton, .zombie, .blaze]
        }
        for idx in 0..<kinds.count {
            let offsetX = (idx % 2 == 0 ? 1 : -1) * Int.random(in: 4...9)
            let offsetZ = (idx < 2 ? 1 : -1) * Int.random(in: 4...9)
            let mx = cx + offsetX
            let mz = cz + offsetZ
            let gy = highestSolidY(atX: mx, z: mz)
            let pos = SIMD3<Float>(Float(mx) + 0.5, Float(gy) + 1.0, Float(mz) + 0.5)
            let kind: MobKind = (activeDimension == .endgame && idx == 0 && !mobs.contains(where: { $0.kind == .enderDragon })) ? .enderDragon : kinds[idx]
            let node = makeMobNode(kind: kind)
            node.position = SCNVector3(pos.x, pos.y, pos.z)
            let hp: Int
            switch kind {
            case .sheep, .pig, .cow, .chicken, .fox, .wolf: hp = 12
            case .bear: hp = 28
            case .villager: hp = 8
            case .fish: hp = 3
            case .dolphin: hp = 10
            case .turtle: hp = 12
            case .guardian: hp = 24
            case .ironGolem: hp = 80
            case .slime: hp = 6
            case .spider: hp = 12
            case .blaze: hp = 18
            case .zombie, .skeleton, .creeper: hp = 10
            case .enderman: hp = 14
            case .enderDragon: hp = 28
            }
            let mob = WorldMob(kind: kind, position: pos, yaw: 0, hp: hp, wanderTimer: 1.5, node: node)
            if kind == .villager {
                mob.profession = villageProfession(near: pos)
                assignVillagerDestinations(mob)
            }
            node.name = "mob_\(mob.id.uuidString)"
            mobsRootNode.addChildNode(node)
            mobs.append(mob)
        }

        // Hostile mobs can also inhabit nearby cave pockets instead of every spawn
        // being placed on the surface. The cap keeps the scene workload bounded.
        if activeDimension == .overworld && mobs.count < 14 {
            for _ in 0..<10 where mobs.count < 14 {
                let caveX = cx + Int.random(in: -7...7)
                let caveZ = cz + Int.random(in: -7...7)
                let surface = terrainHeight(x: caveX, z: caveZ, biome: BiomeType.biomeAt(x: caveX, z: caveZ, dimension: .overworld))
                let caveY = Int.random(in: 2...max(2, min(5, surface - 1)))
                let caveCoord = BlockCoord(x: caveX, y: caveY, z: caveZ)
                let floorCoord = BlockCoord(x: caveX, y: caveY - 1, z: caveZ)
                guard isCavePocket(x: caveX, y: caveY, z: caveZ, surfaceHeight: surface),
                      blocks[caveCoord] == nil,
                      let floor = blocks[floorCoord], !floor.isPassable else { continue }
                let kind: MobKind = (abs(caveX * 31 + caveZ * 17 + caveY) % 3 == 0) ? .spider : .zombie
                let pos = SIMD3<Float>(Float(caveX) + 0.5, Float(caveY), Float(caveZ) + 0.5)
                let node = makeMobNode(kind: kind)
                node.position = SCNVector3(pos.x, pos.y, pos.z)
                let mob = WorldMob(kind: kind, position: pos, yaw: Float.random(in: 0...(Float.pi * 2)), hp: kind == .spider ? 12 : 10, wanderTimer: 1.1, node: node)
                node.name = "mob_\(mob.id.uuidString)"
                mobsRootNode.addChildNode(node)
                mobs.append(mob)
                break
            }
        }

        // Fish are spawned only in ocean water, never on dry land.
        if activeDimension == .overworld {
            for _ in 0..<3 where mobs.count < 14 && mobs.filter({ $0.kind == .fish }).count < 6 {
                let fx = cx + Int.random(in: -7...7)
                let fz = cz + Int.random(in: -7...7)
                guard BiomeType.biomeAt(x: fx, z: fz, dimension: .overworld) == .ocean else { continue }
                let waterCoord = BlockCoord(x: fx, y: 3, z: fz)
                guard blocks[waterCoord] == .water else { continue }
                let pos = SIMD3<Float>(Float(fx) + 0.5, 3.4, Float(fz) + 0.5)
                let node = makeMobNode(kind: .fish)
                node.position = SCNVector3(pos.x, pos.y, pos.z)
                let mob = WorldMob(kind: .fish, position: pos, yaw: Float.random(in: 0...(Float.pi * 2)), hp: 3, wanderTimer: 0.8, node: node)
                node.name = "mob_\(mob.id.uuidString)"
                mobsRootNode.addChildNode(node)
                mobs.append(mob)
            }
        }
        if activeDimension == .overworld {
            let species: [MobKind] = (mobs.filter { $0.kind == .dolphin }.count < 2 ? [.dolphin] : []) + (mobs.filter { $0.kind == .turtle }.count < 3 ? [.turtle] : [])
            for speciesKind in species where mobs.count < 14 {
                for _ in 0..<5 where mobs.count < 14 {
                    let ax = cx + Int.random(in: -8...8), az = cz + Int.random(in: -8...8), ay = Int.random(in: 4...7)
                    guard BiomeType.biomeAt(x: ax, z: az, dimension: .overworld) == .ocean,
                          blocks[BlockCoord(x: ax, y: ay, z: az)] == .water else { continue }
                    let pos = SIMD3<Float>(Float(ax) + 0.5, Float(ay) + 0.25, Float(az) + 0.5)
                    let node = makeMobNode(kind: speciesKind); node.position = SCNVector3(pos.x, pos.y, pos.z)
                    let mob = WorldMob(kind: speciesKind, position: pos, yaw: Float.random(in: 0...(Float.pi * 2)), hp: speciesKind == .dolphin ? 10 : 12, wanderTimer: 1.2, node: node)
                    node.name = "mob_\(mob.id.uuidString)"; mobsRootNode.addChildNode(node); mobs.append(mob); break
                }
            }
            // Guardians patrol deeper ocean water and remain capped to avoid crowding.
            if mobs.filter({ $0.kind == .guardian }).count < 2 && mobs.count < 14 {
                for _ in 0..<8 {
                    let gx = cx + Int.random(in: -8...8), gz = cz + Int.random(in: -8...8), gy = Int.random(in: 3...6)
                    guard BiomeType.biomeAt(x: gx, z: gz, dimension: .overworld) == .ocean,
                          blocks[BlockCoord(x: gx, y: gy, z: gz)] == .water else { continue }
                    let pos = SIMD3<Float>(Float(gx) + 0.5, Float(gy) + 0.4, Float(gz) + 0.5)
                    let node = makeMobNode(kind: .guardian); node.position = SCNVector3(pos.x, pos.y, pos.z)
                    let guardian = WorldMob(kind: .guardian, position: pos, yaw: Float.random(in: 0...(Float.pi * 2)), hp: 24, wanderTimer: 1.4, node: node)
                    node.name = "mob_\(guardian.id.uuidString)"; mobsRootNode.addChildNode(node); mobs.append(guardian)
                    break
                }
            }
        }
    }

    private func assignVillagerDestinations(_ villager: WorldMob) {
        let nearbyBeds = blocks.keys.filter { blocks[$0] == .bed }
        if let bed = nearbyBeds.min(by: { a, b in
            let da = simd_distance(SIMD3<Float>(Float(a.x) + 0.5, Float(a.y) + 1, Float(a.z) + 0.5), villager.position)
            let db = simd_distance(SIMD3<Float>(Float(b.x) + 0.5, Float(b.y) + 1, Float(b.z) + 0.5), villager.position)
            return da < db
        }) {
            villager.homePosition = SIMD3<Float>(Float(bed.x) + 0.5, Float(bed.y) + 1, Float(bed.z) + 0.5)
        }
        let preferred: [BlockType]
        switch villager.profession {
        case .farmer: preferred = [.crop] // crop plots act as farmer work areas
        case .miner: preferred = [.furnace]
        case .builder: preferred = [.craftingTable]
        }
        let candidates = blocks.keys.filter { coord in
            guard let block = blocks[coord] else { return false }
            return preferred.contains(block)
        }
        if let station = candidates.min(by: { a, b in
            let da = simd_distance(SIMD3<Float>(Float(a.x) + 0.5, Float(a.y) + 1, Float(a.z) + 0.5), villager.position)
            let db = simd_distance(SIMD3<Float>(Float(b.x) + 0.5, Float(b.y) + 1, Float(b.z) + 0.5), villager.position)
            return da < db
        }) {
            villager.workstationPosition = SIMD3<Float>(Float(station.x) + 0.5, Float(station.y) + 1, Float(station.z) + 0.5)
        }
    }

    private func villagerCellIsWalkable(_ cell: VillagerPathCell, fromY: Int) -> (Bool, Int) {
        let floorY = highestSolidY(atX: cell.x, z: cell.z)
        guard abs(floorY - fromY) <= 1 else { return (false, floorY) }

        let feet = BlockCoord(x: cell.x, y: floorY + 1, z: cell.z)
        let head = BlockCoord(x: cell.x, y: floorY + 2, z: cell.z)
        let feetBlocked = blocks[feet].map { !$0.isPassable } ?? false
        let headBlocked = blocks[head].map { !$0.isPassable } ?? false
        return (!feetBlocked && !headBlocked, floorY)
    }

    private func buildVillagerPath(from start: SIMD3<Float>, to target: SIMD3<Float>) -> [SIMD3<Float>] {
        let startCell = VillagerPathCell(x: Int(floor(start.x)), z: Int(floor(start.z)))
        let goalCell = VillagerPathCell(x: Int(floor(target.x)), z: Int(floor(target.z)))
        if startCell == goalCell { return [] }

        var queue: [VillagerPathCell] = [startCell]
        var queueIndex = 0
        var previous: [VillagerPathCell: VillagerPathCell] = [:]
        var visited: Set<VillagerPathCell> = [startCell]
        let directions = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let searchRadius = 20
        var found = false

        while queueIndex < queue.count && visited.count < 700 {
            let current = queue[queueIndex]
            queueIndex += 1
            if current == goalCell {
                found = true
                break
            }

            let currentFloor = highestSolidY(atX: current.x, z: current.z)
            for (dx, dz) in directions {
                let next = VillagerPathCell(x: current.x + dx, z: current.z + dz)
                guard abs(next.x - startCell.x) <= searchRadius,
                      abs(next.z - startCell.z) <= searchRadius,
                      !visited.contains(next) else { continue }
                let (walkable, _) = villagerCellIsWalkable(next, fromY: currentFloor)
                guard walkable else { continue }
                visited.insert(next)
                previous[next] = current
                queue.append(next)
            }
        }

        guard found else { return [] }
        var reversed: [VillagerPathCell] = [goalCell]
        var cursor = goalCell
        while cursor != startCell, let parent = previous[cursor] {
            cursor = parent
            if cursor != startCell { reversed.append(cursor) }
        }

        return reversed.reversed().map { cell in
            let floorY = highestSolidY(atX: cell.x, z: cell.z)
            return SIMD3<Float>(Float(cell.x) + 0.5, Float(floorY) + 1.0, Float(cell.z) + 0.5)
        }
    }

    private func updateVillagerNavigation(_ villager: WorldMob, target: SIMD3<Float>, dt: Float) {
        villager.pathRefreshTimer -= dt
        if villager.pathRefreshTimer <= 0 {
            villager.navigationPath = buildVillagerPath(from: villager.position, to: target)
            villager.pathRefreshTimer = 1.0
        }

        while let waypoint = villager.navigationPath.first,
              simd_length(SIMD2<Float>(waypoint.x - villager.position.x,
                                       waypoint.z - villager.position.z)) < 0.42 {
            villager.navigationPath.removeFirst()
        }

        let destination = villager.navigationPath.first ?? target
        let dx = destination.x - villager.position.x
        let dz = destination.z - villager.position.z
        if simd_length(SIMD2<Float>(dx, dz)) > 0.18 {
            villager.yaw = atan2(-dx, -dz)
            villager.isSleeping = false
        } else {
            villager.isSleeping = isNightMode
        }
    }

    private func performVillagerFarmWork(_ villager: WorldMob, dt: Float) {
        guard villager.profession == .farmer, !isNightMode, !villager.isBaby else { return }
        villager.farmWorkTimer -= dt
        guard villager.farmWorkTimer <= 0 else { return }
        villager.farmWorkTimer = 5.0

        let origin = BlockCoord(x: Int(floor(villager.position.x)),
                                y: Int(floor(villager.position.y - 1)),
                                z: Int(floor(villager.position.z)))
        let matureCrop = cropStages.keys
            .filter { coord in
                guard blocks[coord] == .crop, (cropStages[coord] ?? 0) >= 3 else { return false }
                let dx = coord.x - origin.x
                let dz = coord.z - origin.z
                return dx * dx + dz * dz <= 16 && abs(coord.y - origin.y) <= 2
            }
            .min { a, b in
                let da = (a.x - origin.x) * (a.x - origin.x) + (a.z - origin.z) * (a.z - origin.z)
                let db = (b.x - origin.x) * (b.x - origin.x) + (b.z - origin.z) * (b.z - origin.z)
                return da < db
            }

        guard let crop = matureCrop else { return }
        cropStages[crop] = 0
        blockNodes[crop]?.scale = SCNVector3(1.0, 0.45, 1.0)
        foodInventory[.wheat, default: 0] += 2
        foodInventory[.seeds, default: 0] += 1
        statusMessage = "Farmer harvested and replanted crops"
        SoundEngine.shared.play(.pickup)
        saveWorld()
    }

    private func updateVillagerSchedules(dt: Float) {
        let villagers = mobs.filter { $0.kind == .villager && !$0.isBaby }
        for villager in villagers {
            performVillagerFarmWork(villager, dt: dt)
        }
        let bedCount = blocks.values.filter { $0 == .bed }.count
        if villagers.count >= 2 && bedCount > villagers.count {
            villagerGrowthTimer += dt
            if villagerGrowthTimer >= 180 {
                villagerGrowthTimer = 0
                let parents = villagers.sorted { simd_distance($0.position, playerPos) < simd_distance($1.position, playerPos) }
                if parents.count >= 2 {
                    let a = parents[0].position
                    let b = parents[1].position
                    let spawn = SIMD3<Float>((a.x + b.x) * 0.5, max(a.y, b.y), (a.z + b.z) * 0.5)
                    let node = makeMobNode(kind: .villager)
                    let baby = WorldMob(kind: .villager, position: spawn, yaw: Float.random(in: 0...(Float.pi * 2)), hp: 8, wanderTimer: 2, node: node)
                    baby.profession = parents[0].profession
                    baby.isBaby = true
                    baby.ageTimer = 120
                    node.scale = SCNVector3(0.55, 0.55, 0.55)
                    node.position = SCNVector3(spawn.x, spawn.y, spawn.z)
                    mobsRootNode.addChildNode(node)
                    assignVillagerDestinations(baby)
                    mobs.append(baby)
                    statusMessage = "A new villager has joined the village!"
                    DispatchQueue.main.async { self.saveWorld() }
                }
            }
        } else {
            villagerGrowthTimer = 0
        }
    }

    private func villagerScheduleTarget(_ villager: WorldMob) -> SIMD3<Float>? {
        if isNightMode { return villager.homePosition }
        return villager.workstationPosition ?? villager.homePosition
    }

    private func villageProfession(near position: SIMD3<Float>) -> VillagerProfession {
        let x = Int(floor(position.x)), y = Int(floor(position.y)), z = Int(floor(position.z))
        var best: (distance: Int, profession: VillagerProfession)? = nil
        for dx in -8...8 {
            for dy in -2...4 {
                for dz in -8...8 {
                    let coord = BlockCoord(x: x + dx, y: y + dy, z: z + dz)
                    let profession: VillagerProfession?
                    switch blocks[coord] {
                    case .craftingTable?: profession = .builder
                    case .furnace?: profession = .miner
                    case .crop?: profession = .farmer
                    default: profession = nil
                    }
                    guard let profession else { continue }
                    let distance = dx * dx + dy * dy + dz * dz
                    if best == nil || distance < best!.distance { best = (distance, profession) }
                }
            }
        }
        return best?.profession ?? .farmer
    }

    private func makeMobNode(kind: MobKind) -> SCNNode {
        let container = SCNNode()
        switch kind {
        case .fish:
            let body = SCNSphere(radius: 0.20)
            let bodyMat = SCNMaterial(); bodyMat.diffuse.contents = UIColor(red: 0.95, green: 0.58, blue: 0.20, alpha: 1)
            body.materials = [bodyMat]
            let bodyNode = SCNNode(geometry: body)
            let tail = SCNCone(topRadius: 0.015, bottomRadius: 0.13, height: 0.24)
            let tailMat = SCNMaterial(); tailMat.diffuse.contents = UIColor(red: 0.98, green: 0.72, blue: 0.25, alpha: 1); tail.materials = [tailMat]
            let tailNode = SCNNode(geometry: tail); tailNode.eulerAngles.z = .pi / 2; tailNode.position = SCNVector3(0, 0, 0.28)
            let eyeMat = SCNMaterial(); eyeMat.diffuse.contents = UIColor.black
            let eye = SCNSphere(radius: 0.025); eye.materials = [eyeMat]
            let eyeNode = SCNNode(geometry: eye); eyeNode.position = SCNVector3(0.13, 0.06, -0.10)
            container.addChildNode(bodyNode); container.addChildNode(tailNode); container.addChildNode(eyeNode)
        case .dolphin:
            let blue = SCNMaterial(); blue.diffuse.contents = UIColor(red: 0.36, green: 0.62, blue: 0.78, alpha: 1)
            let body = SCNSphere(radius: 0.34); body.materials = [blue]
            let bodyNode = SCNNode(geometry: body); bodyNode.scale = SCNVector3(1.0, 0.78, 1.65)
            let snout = SCNCone(topRadius: 0.035, bottomRadius: 0.13, height: 0.38); snout.materials = [blue]
            let snoutNode = SCNNode(geometry: snout); snoutNode.eulerAngles.x = .pi / 2; snoutNode.position = SCNVector3(0, -0.02, -0.48)
            let fin = SCNBox(width: 0.12, height: 0.06, length: 0.32, chamferRadius: 0.03); fin.materials = [blue]
            let finNode = SCNNode(geometry: fin); finNode.position = SCNVector3(0, -0.22, 0.10)
            let tail = SCNBox(width: 0.34, height: 0.06, length: 0.20, chamferRadius: 0.03); tail.materials = [blue]
            let tailNode = SCNNode(geometry: tail); tailNode.position = SCNVector3(0, 0, 0.58)
            container.addChildNode(bodyNode); container.addChildNode(snoutNode); container.addChildNode(finNode); container.addChildNode(tailNode)
        case .turtle:
            let shellMat = SCNMaterial(); shellMat.diffuse.contents = UIColor(red: 0.22, green: 0.43, blue: 0.25, alpha: 1)
            let shell = SCNSphere(radius: 0.38); shell.materials = [shellMat]
            let shellNode = SCNNode(geometry: shell); shellNode.scale = SCNVector3(1.0, 0.48, 1.15); shellNode.position = SCNVector3(0, 0.16, 0)
            let skin = SCNMaterial(); skin.diffuse.contents = UIColor(red: 0.48, green: 0.64, blue: 0.34, alpha: 1)
            let head = SCNSphere(radius: 0.15); head.materials = [skin]
            let headNode = SCNNode(geometry: head); headNode.position = SCNVector3(0, 0.12, -0.42)
            for side: Float in [-1, 1] {
                let leg = SCNBox(width: 0.13, height: 0.08, length: 0.28, chamferRadius: 0.04); leg.materials = [skin]
                let legNode = SCNNode(geometry: leg); legNode.position = SCNVector3(side * 0.27, -0.04, -0.20); container.addChildNode(legNode)
            }
            container.addChildNode(shellNode); container.addChildNode(headNode)
        case .guardian:
            let teal = SCNMaterial(); teal.diffuse.contents = UIColor(red: 0.18, green: 0.62, blue: 0.58, alpha: 1)
            let dark = SCNMaterial(); dark.diffuse.contents = UIColor(red: 0.08, green: 0.30, blue: 0.34, alpha: 1)
            let body = SCNBox(width: 0.76, height: 0.76, length: 0.76, chamferRadius: 0.08); body.materials = [teal]
            let bodyNode = SCNNode(geometry: body); container.addChildNode(bodyNode)
            let eye = SCNSphere(radius: 0.12); let eyeMaterial = SCNMaterial(); eyeMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.35, blue: 0.20, alpha: 1); eye.materials = [eyeMaterial]
            let eyeNode = SCNNode(geometry: eye); eyeNode.position = SCNVector3(0, 0.12, -0.40); container.addChildNode(eyeNode)
            for side: Float in [-1, 1] {
                for row: Float in [-1, 0, 1] {
                    let spike = SCNCone(topRadius: 0.015, bottomRadius: 0.11, height: 0.30); spike.materials = [dark]
                    let spikeNode = SCNNode(geometry: spike)
                    spikeNode.position = SCNVector3(side * 0.43, row * 0.22, 0)
                    spikeNode.eulerAngles.z = side * .pi / 2
                    container.addChildNode(spikeNode)
                }
            }
        case .sheep:
            let body = SCNBox(width: 0.72, height: 0.58, length: 0.95, chamferRadius: 0.03)
            let m = SCNMaterial(); m.diffuse.contents = UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1.0); body.materials = [m]
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(0, 0.25, 0)
            let head = SCNBox(width: 0.44, height: 0.42, length: 0.44, chamferRadius: 0.02)
            let hm = SCNMaterial(); hm.diffuse.contents = UIColor(red: 0.85, green: 0.72, blue: 0.62, alpha: 1.0); head.materials = [hm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 0.45, -0.56)
            container.addChildNode(bn); container.addChildNode(hn)
        case .pig:
            let body = SCNBox(width: 0.68, height: 0.52, length: 0.90, chamferRadius: 0.03)
            let m = SCNMaterial(); m.diffuse.contents = UIColor(red: 0.94, green: 0.62, blue: 0.66, alpha: 1.0); body.materials = [m]
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(0, 0.22, 0)
            let snout = SCNBox(width: 0.34, height: 0.28, length: 0.34, chamferRadius: 0.02)
            let sm = SCNMaterial(); sm.diffuse.contents = UIColor(red: 0.86, green: 0.48, blue: 0.54, alpha: 1.0); snout.materials = [sm]
            let sn = SCNNode(geometry: snout); sn.position = SCNVector3(0, 0.34, -0.52)
            container.addChildNode(bn); container.addChildNode(sn)
        case .cow:
            let body = SCNBox(width: 0.82, height: 0.62, length: 1.02, chamferRadius: 0.03)
            let bm = SCNMaterial(); bm.diffuse.contents = UIColor(red: 0.34, green: 0.22, blue: 0.15, alpha: 1.0); body.materials = [bm]
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(0, 0.34, 0)
            let head = SCNBox(width: 0.42, height: 0.42, length: 0.42, chamferRadius: 0.02)
            let hm = SCNMaterial(); hm.diffuse.contents = UIColor(red: 0.82, green: 0.76, blue: 0.68, alpha: 1.0); head.materials = [hm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 0.48, -0.62)
            container.addChildNode(bn); container.addChildNode(hn)
        case .chicken:
            let body = SCNSphere(radius: 0.28)
            let bm = SCNMaterial(); bm.diffuse.contents = UIColor(white: 0.94, alpha: 1.0); body.materials = [bm]
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(0, 0.35, 0)
            let head = SCNBox(width: 0.22, height: 0.22, length: 0.22, chamferRadius: 0.02)
            let hm = SCNMaterial(); hm.diffuse.contents = UIColor(white: 0.98, alpha: 1.0); head.materials = [hm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 0.68, -0.20)
            let beak = SCNBox(width: 0.12, height: 0.08, length: 0.12, chamferRadius: 0.01)
            let cm = SCNMaterial(); cm.diffuse.contents = UIColor.orange; beak.materials = [cm]
            let cn = SCNNode(geometry: beak); cn.position = SCNVector3(0, 0.63, -0.34)
            container.addChildNode(bn); container.addChildNode(hn); container.addChildNode(cn)
        case .wolf, .fox, .bear:
            let fur = SCNMaterial()
            switch kind {
            case .wolf: fur.diffuse.contents = UIColor(red: 0.62, green: 0.64, blue: 0.67, alpha: 1)
            case .fox: fur.diffuse.contents = UIColor(red: 0.88, green: 0.38, blue: 0.12, alpha: 1)
            default: fur.diffuse.contents = UIColor(red: 0.34, green: 0.24, blue: 0.17, alpha: 1)
            }
            let body = SCNBox(width: kind == .bear ? 0.95 : 0.62, height: kind == .bear ? 0.78 : 0.52, length: kind == .bear ? 1.15 : 0.88, chamferRadius: 0.12)
            body.materials = [fur]
            let bodyNode = SCNNode(geometry: body); bodyNode.position = SCNVector3(0, kind == .bear ? 0.55 : 0.34, 0)
            let head = SCNBox(width: kind == .bear ? 0.62 : 0.42, height: kind == .bear ? 0.55 : 0.40, length: kind == .bear ? 0.58 : 0.46, chamferRadius: 0.08)
            head.materials = [fur]
            let headNode = SCNNode(geometry: head); headNode.position = SCNVector3(0, kind == .bear ? 0.92 : 0.64, -0.48)
            let dark = SCNMaterial(); dark.diffuse.contents = UIColor(white: 0.10, alpha: 1)
            let nose = SCNSphere(radius: 0.055); nose.materials = [dark]
            let noseNode = SCNNode(geometry: nose); noseNode.position = SCNVector3(0, kind == .bear ? 0.90 : 0.62, -0.76)
            container.addChildNode(bodyNode); container.addChildNode(headNode); container.addChildNode(noseNode)
            for side: Float in [-1, 1] {
                let ear = SCNCone(topRadius: 0.01, bottomRadius: 0.10, height: 0.20); ear.materials = [fur]
                let earNode = SCNNode(geometry: ear); earNode.position = SCNVector3(side * 0.15, kind == .bear ? 1.22 : 0.90, -0.47)
                container.addChildNode(earNode)
                for legZ: Float in [-1, 1] {
                    let leg = SCNBox(width: 0.15, height: 0.34, length: 0.16, chamferRadius: 0.03); leg.materials = [fur]
                    let legNode = SCNNode(geometry: leg); legNode.position = SCNVector3(side * 0.22, 0.16, legZ * 0.27)
                    container.addChildNode(legNode)
                }
            }
        case .villager:
            let robe = SCNBox(width: 0.52, height: 0.82, length: 0.34, chamferRadius: 0.02)
            let m = SCNMaterial(); m.diffuse.contents = UIColor(red: 0.48, green: 0.28, blue: 0.14, alpha: 1.0); robe.materials = [m]
            let rn = SCNNode(geometry: robe); rn.position = SCNVector3(0, 0.42, 0)
            let head = SCNBox(width: 0.44, height: 0.48, length: 0.44, chamferRadius: 0.02)
            let hm = SCNMaterial(); hm.diffuse.contents = UIColor(red: 0.88, green: 0.68, blue: 0.52, alpha: 1.0); head.materials = [hm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 1.06, 0)
            container.addChildNode(rn); container.addChildNode(hn)
        case .slime:
            let cube = SCNBox(width: 0.75, height: 0.75, length: 0.75, chamferRadius: 0.02)
            let m = SCNMaterial(); m.diffuse.contents = UIColor(red: 0.34, green: 0.78, blue: 0.32, alpha: 0.88); m.isDoubleSided = true; cube.materials = [m]
            let cn = SCNNode(geometry: cube); cn.position = SCNVector3(0, 0.38, 0)
            container.addChildNode(cn)
        case .zombie:
            let torso = SCNBox(width: 0.48, height: 0.72, length: 0.26, chamferRadius: 0.02)
            let tm = SCNMaterial(); tm.diffuse.contents = UIColor(red: 0.16, green: 0.52, blue: 0.68, alpha: 1.0); torso.materials = [tm]
            let tn = SCNNode(geometry: torso); tn.position = SCNVector3(0, 0.68, 0)
            let head = SCNBox(width: 0.44, height: 0.44, length: 0.44, chamferRadius: 0.02)
            let hm = SCNMaterial(); hm.diffuse.contents = UIColor(red: 0.32, green: 0.64, blue: 0.30, alpha: 1.0); head.materials = [hm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 1.26, 0)
            container.addChildNode(tn); container.addChildNode(hn)
        case .skeleton:
            let rib = SCNBox(width: 0.44, height: 0.68, length: 0.24, chamferRadius: 0.02)
            let bm = SCNMaterial(); bm.diffuse.contents = UIColor(red: 0.90, green: 0.90, blue: 0.86, alpha: 1.0); rib.materials = [bm]
            let rn = SCNNode(geometry: rib); rn.position = SCNVector3(0, 0.66, 0)
            let skull = SCNBox(width: 0.42, height: 0.42, length: 0.42, chamferRadius: 0.02); skull.materials = [bm]
            let sn = SCNNode(geometry: skull); sn.position = SCNVector3(0, 1.22, 0)
            container.addChildNode(rn); container.addChildNode(sn)
        case .creeper:
            let body = SCNBox(width: 0.46, height: 1.15, length: 0.34, chamferRadius: 0.02)
            let cm = SCNMaterial(); cm.diffuse.contents = UIColor(red: 0.22, green: 0.66, blue: 0.22, alpha: 1.0); body.materials = [cm]
            let bn = SCNNode(geometry: body); bn.position = SCNVector3(0, 0.58, 0)
            let head = SCNBox(width: 0.44, height: 0.44, length: 0.44, chamferRadius: 0.02); head.materials = [cm]
            let hn = SCNNode(geometry: head); hn.position = SCNVector3(0, 1.36, 0)
            container.addChildNode(bn); container.addChildNode(hn)
        case .enderman:
            let tall = SCNBox(width: 0.40, height: 1.55, length: 0.26, chamferRadius: 0.02)
            let vm = SCNMaterial(); vm.diffuse.contents = UIColor(red: 0.08, green: 0.07, blue: 0.10, alpha: 1.0); tall.materials = [vm]
            let tn = SCNNode(geometry: tall); tn.position = SCNVector3(0, 0.78, 0)
            let eye = SCNBox(width: 0.26, height: 0.07, length: 0.06, chamferRadius: 0.0)
            let em = SCNMaterial(); em.diffuse.contents = UIColor(red: 0.88, green: 0.36, blue: 1.0, alpha: 1.0); em.emission.contents = UIColor(red: 0.78, green: 0.24, blue: 1.0, alpha: 0.8); eye.materials = [em]
            let en = SCNNode(geometry: eye); en.position = SCNVector3(0, 1.48, -0.14)
            container.addChildNode(tn); container.addChildNode(en)
        case .spider:
            let dark = SCNMaterial(); dark.diffuse.contents = UIColor(red: 0.12, green: 0.10, blue: 0.12, alpha: 1)
            let body = SCNBox(width: 0.72, height: 0.34, length: 0.92, chamferRadius: 0.08); body.materials = [dark]
            let bodyNode = SCNNode(geometry: body); bodyNode.position = SCNVector3(0, 0.42, 0)
            let head = SCNBox(width: 0.42, height: 0.34, length: 0.40, chamferRadius: 0.04); head.materials = [dark]
            let headNode = SCNNode(geometry: head); headNode.position = SCNVector3(0, 0.46, -0.52)
            let eyeMat = SCNMaterial(); eyeMat.diffuse.contents = UIColor.red; eyeMat.emission.contents = UIColor.red
            for side: Float in [-1, 1] {
                let eye = SCNBox(width: 0.08, height: 0.07, length: 0.04, chamferRadius: 0.0); eye.materials = [eyeMat]
                let eyeNode = SCNNode(geometry: eye); eyeNode.position = SCNVector3(side * 0.12, 0.50, -0.73); container.addChildNode(eyeNode)
                for legIndex in 0..<4 {
                    let leg = SCNBox(width: 0.08, height: 0.08, length: 0.72, chamferRadius: 0.0); leg.materials = [dark]
                    let legNode = SCNNode(geometry: leg)
                    legNode.position = SCNVector3(side * (0.36 + Float(legIndex) * 0.015), 0.30, Float(legIndex - 1) * 0.25)
                    legNode.eulerAngles.y = side * (0.55 + Float(legIndex) * 0.12)
                    container.addChildNode(legNode)
                }
            }
            container.addChildNode(bodyNode); container.addChildNode(headNode)
        case .blaze:
            let gold = SCNMaterial(); gold.diffuse.contents = UIColor(red: 0.98, green: 0.66, blue: 0.12, alpha: 1); gold.emission.contents = UIColor(red: 0.9, green: 0.38, blue: 0.05, alpha: 0.45)
            let core = SCNBox(width: 0.48, height: 0.82, length: 0.48, chamferRadius: 0.04); core.materials = [gold]
            let coreNode = SCNNode(geometry: core); coreNode.position = SCNVector3(0, 0.82, 0); container.addChildNode(coreNode)
            for ring in 0..<3 {
                for segment in 0..<4 {
                    let rod = SCNBox(width: 0.12, height: 0.52, length: 0.12, chamferRadius: 0.02); rod.materials = [gold]
                    let angle = Float(segment) * (.pi / 2) + Float(ring) * 0.45
                    let node = SCNNode(geometry: rod)
                    node.position = SCNVector3(cos(angle) * (0.48 + Float(ring) * 0.06), 0.42 + Float(ring) * 0.38, sin(angle) * (0.48 + Float(ring) * 0.06))
                    container.addChildNode(node)
                }
            }
        case .ironGolem:
            let iron = SCNMaterial(); iron.diffuse.contents = UIColor(red: 0.72, green: 0.76, blue: 0.70, alpha: 1.0)
            let body = SCNBox(width: 0.82, height: 1.05, length: 0.48, chamferRadius: 0.04); body.materials = [iron]
            let bodyNode = SCNNode(geometry: body); bodyNode.position = SCNVector3(0, 0.88, 0)
            let head = SCNBox(width: 0.62, height: 0.58, length: 0.56, chamferRadius: 0.03); head.materials = [iron]
            let headNode = SCNNode(geometry: head); headNode.position = SCNVector3(0, 1.72, -0.02)
            let arm = SCNBox(width: 0.24, height: 1.10, length: 0.30, chamferRadius: 0.03); arm.materials = [iron]
            let leftArm = SCNNode(geometry: arm); leftArm.position = SCNVector3(-0.58, 0.78, 0)
            let rightArm = SCNNode(geometry: arm); rightArm.position = SCNVector3(0.58, 0.78, 0)
            let vine = SCNMaterial(); vine.diffuse.contents = UIColor(red: 0.25, green: 0.48, blue: 0.22, alpha: 1.0)
            let nose = SCNBox(width: 0.10, height: 0.28, length: 0.12, chamferRadius: 0.01); nose.materials = [vine]
            let noseNode = SCNNode(geometry: nose); noseNode.position = SCNVector3(0, 1.68, -0.32)
            container.addChildNode(bodyNode); container.addChildNode(headNode); container.addChildNode(leftArm); container.addChildNode(rightArm); container.addChildNode(noseNode)
        case .enderDragon:
            let torso = SCNBox(width: 1.1, height: 0.9, length: 1.8, chamferRadius: 0.04)
            let dm = SCNMaterial(); dm.diffuse.contents = UIColor(red: 0.14, green: 0.12, blue: 0.18, alpha: 1.0); torso.materials = [dm]
            let tn = SCNNode(geometry: torso); tn.position = SCNVector3(0, 1.6, 0)
            let wingL = SCNBox(width: 1.6, height: 0.14, length: 0.8, chamferRadius: 0.02); wingL.materials = [dm]
            let wln = SCNNode(geometry: wingL); wln.position = SCNVector3(-1.3, 1.85, 0)
            let wingR = SCNBox(width: 1.6, height: 0.14, length: 0.8, chamferRadius: 0.02); wingR.materials = [dm]
            let wrn = SCNNode(geometry: wingR); wrn.position = SCNVector3(1.3, 1.85, 0)
            container.addChildNode(tn); container.addChildNode(wln); container.addChildNode(wrn)
        }
        return container
    }

    private func spawnArrow(from origin: SIMD3<Float>, toward target: SIMD3<Float>, fiery: Bool = false) {
        let geom = SCNBox(width: fiery ? 0.16 : 0.06, height: fiery ? 0.16 : 0.06, length: fiery ? 0.32 : 0.45, chamferRadius: 0.0)
        let mat = SCNMaterial()
        mat.diffuse.contents = fiery ? UIColor.orange : UIColor.white
        if fiery { mat.emission.contents = UIColor(red: 1.0, green: 0.24, blue: 0.02, alpha: 0.9) }
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.position = SCNVector3(origin.x, origin.y, origin.z)
        let dir = simd_normalize(target - origin)
        node.look(at: SCNVector3(origin.x + dir.x, origin.y + dir.y, origin.z + dir.z))
        projectilesRootNode.addChildNode(node)
        arrows.append(ArrowProjectile(position: origin, velocity: dir * (fiery ? 9.0 : 11.5), damage: fiery ? 4 : 3, node: node))
        SoundEngine.shared.play(.arrow)
    }

    private func spawnDroppedItem(type: BlockType, at coord: BlockCoord) {
        let cube = SCNBox(width: 0.28, height: 0.28, length: 0.28, chamferRadius: 0.02)
        let mat = SCNMaterial()
        mat.diffuse.contents = type.previewImage
        mat.diffuse.magnificationFilter = .nearest
        cube.materials = [mat]
        let node = SCNNode(geometry: cube)
        let pos = SIMD3<Float>(Float(coord.x) + 0.5, Float(coord.y) + 0.35, Float(coord.z) + 0.5)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        dropsRootNode.addChildNode(node)
        droppedItems.append(DroppedItemEntity(blockType: type, position: pos, bobPhase: Float.random(in: 0...6.28), node: node))
    }

    private func hasNearbyEndCrystal(around pos: SIMD3<Float>) -> Bool {
        let center = BlockCoord(x: Int(floor(pos.x)), y: Int(floor(pos.y)), z: Int(floor(pos.z)))
        for dx in -6...6 {
            for dy in -4...6 {
                for dz in -6...6 {
                    if blocks[BlockCoord(x: center.x + dx, y: center.y + dy, z: center.z + dz)] == .endCrystal {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func nearestVillager(to position: SIMD3<Float>, within radius: Float) -> WorldMob? {
        mobs
            .filter { $0.kind == .villager }
            .map { ($0, simd_distance(SIMD2<Float>($0.position.x - position.x, $0.position.z - position.z), .zero)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    private func nearbyHostile(to villager: WorldMob, within radius: Float) -> WorldMob? {
        mobs
            .filter { [.zombie, .skeleton, .creeper, .enderman, .spider, .blaze].contains($0.kind) }
            .map { ($0, simd_distance(SIMD2<Float>($0.position.x - villager.position.x, $0.position.z - villager.position.z), .zero)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?.0
    }

    private func ensureVillageGuardian() {
        let villagers = mobs.filter { $0.kind == .villager && !$0.isBaby }
        guard villagers.count >= 3 else { return }
        let center = villagers.reduce(SIMD3<Float>.zero) { $0 + $1.position } / Float(villagers.count)
        let hasGuardian = mobs.contains { $0.kind == .ironGolem && simd_distance($0.position, center) < 28.0 }
        guard !hasGuardian else { return }
        let gx = Int(floor(center.x + 2.0)), gz = Int(floor(center.z + 2.0))
        let gy = highestSolidY(atX: gx, z: gz)
        let pos = SIMD3<Float>(Float(gx) + 0.5, Float(gy) + 1.0, Float(gz) + 0.5)
        let node = makeMobNode(kind: .ironGolem)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        node.name = "mob_iron_golem_\(UUID().uuidString)"
        mobsRootNode.addChildNode(node)
        mobs.append(WorldMob(kind: .ironGolem, position: pos, yaw: 0, hp: 80, wanderTimer: 1.0, node: node))
        unlockAchievement("village_guardian")
        statusMessage = "An Iron Golem has joined the village"
    }

    private func updateMobsArrowsAndDrops(dt: Float) {
        ensureVillageGuardian()
        let playerGround = SIMD3<Float>(playerPos.x, playerPos.y - 1.0, playerPos.z)
        var defeatedVillagerIDs: [UUID] = []

        for mob in mobs {
            mob.wanderTimer -= dt
            mob.attackCooldown = max(0, mob.attackCooldown - dt)
            if mob.isElderGuardian && mob.hp > 0 && simd_distance(mob.position, playerPos) < 18 {
                miningFatigueRemaining = max(miningFatigueRemaining, 0.35)
            }
            mob.loveTimer = max(0, mob.loveTimer - dt)
            mob.breedCooldown = max(0, mob.breedCooldown - dt)
            if mob.isBaby {
                mob.ageTimer = max(0, mob.ageTimer - dt)
                let growth = 0.55 + 0.45 * (1.0 - mob.ageTimer / 120.0)
                mob.node.scale = SCNVector3(growth, growth, growth)
                if mob.ageTimer <= 0 { mob.isBaby = false }
            }
            mob.knockback *= max(0, 1.0 - dt * 8.0)

            let hostile = ([.zombie, .skeleton, .creeper, .enderman, .enderDragon, .spider, .blaze, .guardian].contains(mob.kind))
            if mob.kind == .guardian {
                let distance = simd_distance(mob.position, playerPos)
                let attackRange: Float = mob.isElderGuardian ? 22.0 : 12.0
                if distance < attackRange {
                    let delta = playerPos - mob.position
                    mob.yaw = atan2(-delta.x, -delta.z)
                    if mob.attackCooldown <= 0 {
                        mob.attackCooldown = mob.isElderGuardian ? 2.0 : 3.0
                        let start = mob.position + SIMD3<Float>(0, 0.1, 0)
                        let aim = playerPos + SIMD3<Float>(0, -0.25, 0)
                        DispatchQueue.main.async { self.spawnArrow(from: start, toward: aim, fiery: false) }
                    }
                } else if mob.wanderTimer <= 0 {
                    mob.wanderTimer = Float.random(in: 1.5...3.0)
                    mob.yaw = Float.random(in: 0...(Float.pi * 2))
                }
            } else if mob.isTamed && [.wolf, .fox, .bear].contains(mob.kind) {
                let distanceToPlayer = simd_length(SIMD2<Float>(playerGround.x - mob.position.x, playerGround.z - mob.position.z))
                let maximumHP = mob.kind == .bear ? 28 : 12

                // Companions recover slowly while safely travelling with the player.
                if distanceToPlayer < 10.0 && mob.hp < maximumHP {
                    mob.petRegenTimer += dt
                    if mob.petRegenTimer >= 5.0 {
                        mob.hp = min(maximumHP, mob.hp + 1)
                        mob.petRegenTimer = 0
                        if mob.hp >= maximumHP && !unlockedAchievements.contains("well_cared_for") {
                            DispatchQueue.main.async { self.unlockAchievement("well_cared_for") }
                        }
                    }
                } else {
                    mob.petRegenTimer = 0
                }

                // A following companion that falls far behind catches up near the player.
                if !mob.isSitting && !mob.isGuarding && distanceToPlayer > 20.0 {
                    let angle = yaw + (mob.id.hashValue % 2 == 0 ? 0.8 : -0.8)
                    let catchX = playerPos.x - sin(angle) * 1.8
                    let catchZ = playerPos.z - cos(angle) * 1.8
                    let ground = Float(highestSolidY(atX: Int(floor(catchX)), z: Int(floor(catchZ)))) + 1.0
                    mob.position = SIMD3<Float>(catchX, ground, catchZ)
                    mob.velocityY = 0
                    mob.node.position = SCNVector3(catchX, ground, catchZ)
                }

                if mob.isSitting {
                    mob.velocityY = 0
                    mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                } else {
                    mob.petGuardMoving = false
                    let huntRadius: Float = mob.isGuarding ? 10.0 : 7.0
                    let prey = mobs.filter {
                        [.zombie, .skeleton, .creeper, .spider, .slime, .enderman, .blaze].contains($0.kind) &&
                        $0.hp > 0 && simd_distance($0.position, mob.position) < huntRadius
                    }.min { simd_distance($0.position, mob.position) < simd_distance($1.position, mob.position) }
                    if let prey {
                        let delta = prey.position - mob.position
                        let distance = simd_length(SIMD2<Float>(delta.x, delta.z))
                        if distance > 1.0 {
                            mob.yaw = atan2(-delta.x, -delta.z)
                            mob.petGuardMoving = true
                        }
                        if distance < 1.35 && mob.attackCooldown <= 0 {
                            mob.attackCooldown = mob.kind == .bear ? 1.0 : 1.35
                            prey.hp -= mob.kind == .bear ? 6 : 4
                            let pushVector = SIMD2<Float>(delta.x, delta.z)
                            let pushLength = simd_length(pushVector)
                            if pushLength > 0.01 { prey.knockback += (pushVector / pushLength) * 2.8 }
                            if prey.hp <= 0 { prey.node.removeFromParentNode() }
                        }
                    } else if !mob.isGuarding {
                        let dx = playerGround.x - mob.position.x
                        let dz = playerGround.z - mob.position.z
                        if hypotf(dx, dz) > 2.2 { mob.yaw = atan2(-dx, -dz) }
                        else if hypotf(dx, dz) < 1.2 { mob.wanderTimer = max(mob.wanderTimer, 0.4) }
                    } else if let anchor = mob.guardPosition {
                        let dx = anchor.x - mob.position.x
                        let dz = anchor.z - mob.position.z
                        if hypotf(dx, dz) > 1.0 {
                            mob.yaw = atan2(-dx, -dz)
                            mob.petGuardMoving = true
                        }
                    }
                }
            } else if mob.kind == .ironGolem {
                if let target = mobs.filter({ [.zombie, .skeleton, .creeper, .enderman].contains($0.kind) })
                    .map({ ($0, simd_distance(SIMD2<Float>($0.position.x - mob.position.x, $0.position.z - mob.position.z), .zero)) })
                    .filter({ $0.1 < 16.0 }).min(by: { $0.1 < $1.1 })?.0 {
                    let delta = target.position - mob.position
                    let distance = simd_length(SIMD2<Float>(delta.x, delta.z))
                    if distance > 1.25 { mob.yaw = atan2(-delta.x, -delta.z) }
                    if distance <= 1.55 && mob.attackCooldown <= 0 {
                        mob.attackCooldown = 1.15
                        target.hp -= 7
                        target.knockback += simd_normalize(SIMD2<Float>(delta.x, delta.z)) * 5.5
                        if target.hp <= 0 { target.node.removeFromParentNode() }
                    }
                }
            } else if hostile {
                let raidTarget = isNightMode ? nearestVillager(to: mob.position, within: 12.0) : nil
                let targetPosition = raidTarget?.position ?? playerGround
                let toTarget = targetPosition - mob.position
                let distXZ = simd_length(SIMD2<Float>(toTarget.x, toTarget.z))
                let chaseRadius: Float = raidTarget == nil ? 14.0 : 12.0
                if distXZ < chaseRadius && distXZ > 0.2 {
                    mob.yaw = atan2(-toTarget.x, -toTarget.z)
                } else if mob.wanderTimer <= 0 {
                    mob.wanderTimer = Float.random(in: 1.2...2.8)
                    mob.yaw = Float.random(in: 0...(Float.pi * 2))
                }
            } else if mob.kind == .villager {
                if mob.homePosition == nil || mob.workstationPosition == nil { assignVillagerDestinations(mob) }
                let scheduledTarget = villagerScheduleTarget(mob)
                let retreatTarget = isNightMode ? nil : nearbyHostile(to: mob, within: 7.0)
                let target = retreatTarget.flatMap { _ in mob.homePosition } ?? scheduledTarget
                if let target = target {
                    let distance = simd_length(SIMD2<Float>(target.x - mob.position.x,
                                                            target.z - mob.position.z))
                    if distance > 0.8 {
                        updateVillagerNavigation(mob, target: target, dt: dt)
                    } else {
                        mob.navigationPath.removeAll()
                        mob.isSleeping = isNightMode
                    }
                    mob.wanderTimer = 0.4
                } else if mob.wanderTimer <= 0 {
                    mob.wanderTimer = Float.random(in: 1.2...2.8)
                    mob.yaw = Float.random(in: 0...(Float.pi * 2))
                }
            } else if mob.wanderTimer <= 0 {
                mob.wanderTimer = Float.random(in: 1.2...2.8)
                mob.yaw = Float.random(in: 0...(Float.pi * 2))
            }

            // Creepers pause to prime their fuse at close range, then create a
            // terrain-affecting blast. Moving away before detonation cancels it.
            if mob.kind == .creeper {
                let distanceToPlayer = simd_distance(mob.position, playerGround)
                if distanceToPlayer < 3.15 {
                    mob.isCreeperPrimed = true
                    mob.creeperFuseRemaining -= dt
                    let pulse = 1.0 + 0.13 * abs(sin(mob.creeperFuseRemaining * 17.0))
                    mob.node.scale = SCNVector3(pulse, pulse, pulse)
                    if mob.creeperFuseRemaining <= 0 {
                        explodeCreeper(mob)
                        mob.hp = -999
                    }
                } else if distanceToPlayer > 4.1 {
                    mob.isCreeperPrimed = false
                    mob.creeperFuseRemaining = 1.45
                    mob.node.scale = SCNVector3(1, 1, 1)
                }
            }

            if (mob.kind == .skeleton || mob.kind == .blaze) && mob.attackCooldown <= 0 {
                let dist = simd_distance(mob.position, playerGround)
                let range: Float = mob.kind == .blaze ? 15.0 : 13.0
                if dist < range {
                    mob.attackCooldown = mob.kind == .blaze ? 2.0 : 2.4
                    let start = mob.position + SIMD3<Float>(0, mob.kind == .blaze ? 0.9 : 1.2, 0)
                    let aim = playerPos + SIMD3<Float>(0, -0.3, 0)
                    DispatchQueue.main.async { self.spawnArrow(from: start, toward: aim, fiery: mob.kind == .blaze) }
                }
            }

            if mob.kind == .enderDragon {
                mob.dragonPhaseTimer -= dt
                if hasNearbyEndCrystal(around: mob.position) && mob.hp < 28 {
                    mob.dragonHealTimer += dt
                    if mob.dragonHealTimer >= 2.0 {
                        mob.dragonHealTimer = 0
                        mob.hp = min(28, mob.hp + 1)
                    }
                }
                if mob.attackCooldown <= 0 && simd_distance(mob.position, playerGround) < 19.0 {
                    mob.attackCooldown = 3.6
                    let start = mob.position + SIMD3<Float>(0, 1.5, 0)
                    let aim = playerPos + SIMD3<Float>(0, -0.35, 0)
                    DispatchQueue.main.async { self.spawnArrow(from: start, toward: aim, fiery: true) }
                }
                if mob.dragonPhaseTimer <= 0 {
                    switch mob.dragonPhase {
                    case .circling: mob.dragonPhase = .diving; mob.dragonPhaseTimer = 2.5
                    case .diving: mob.dragonPhase = .perching; mob.dragonPhaseTimer = 3.0
                    case .perching: mob.dragonPhase = .circling; mob.dragonPhaseTimer = 4.0
                    }
                }
                let speed: Float = (mob.dragonPhase == .diving) ? 4.4 : 2.6
                let nextX = mob.position.x - sin(mob.yaw) * speed * dt + mob.knockback.x * dt
                let nextZ = mob.position.z - cos(mob.yaw) * speed * dt + mob.knockback.y * dt
                let gy = Float(highestSolidY(atX: Int(floor(nextX)), z: Int(floor(nextZ))))
                let targetY: Float
                switch mob.dragonPhase {
                case .circling: targetY = gy + 4.2 + sin(mob.wanderTimer * 2.0) * 0.6
                case .diving: targetY = gy + 1.4
                case .perching: targetY = gy + 1.0
                }
                mob.position = SIMD3<Float>(nextX, lerp(mob.position.y, targetY, min(1.0, dt * 4.0)), nextZ)
            } else if [.fish, .dolphin, .turtle, .guardian].contains(mob.kind) {
                if mob.kind == .dolphin, dolphinGuideAchievementTimer > 0, let target = treasureCompassTarget {
                    let dx = Float(target.x) + 0.5 - mob.position.x
                    let dz = Float(target.z) + 0.5 - mob.position.z
                    if hypotf(dx, dz) > 2.0 { mob.yaw = atan2(-dx, -dz) }
                }
                if mob.wanderTimer <= 0 {
                    mob.wanderTimer = Float.random(in: mob.kind == .turtle ? 2.0...4.0 : 1.0...2.6)
                    mob.yaw += Float.random(in: mob.kind == .turtle ? -0.65...0.65 : -1.15...1.15)
                }
                let swimSpeed: Float = mob.kind == .guardian ? (mob.isElderGuardian ? 1.15 : 0.95) : (mob.kind == .dolphin ? 1.65 : (mob.kind == .turtle ? 0.42 : 0.82))
                let nx = mob.position.x - sin(mob.yaw) * swimSpeed * dt
                let nz = mob.position.z - cos(mob.yaw) * swimSpeed * dt
                let gx = Int(floor(nx)), gz = Int(floor(nz))
                let currentY = Int(floor(mob.position.y))
                let waterCell = BlockCoord(x: gx, y: currentY, z: gz)
                if blocks[waterCell] == .water {
                    let bob = sin(Float(CACurrentMediaTime()) * (mob.kind == .turtle ? 0.8 : 2.0) + Float(mob.id.hashValue % 100)) * 0.10
                    let targetY = Float(currentY) + 0.35 + bob
                    mob.position = SIMD3<Float>(nx, lerp(mob.position.y, targetY, min(1, dt * 2.2)), nz)
                } else {
                    mob.yaw += .pi * 0.72
                }
            } else {
                let speed: Float
                switch mob.kind {
                case .enderman: speed = 2.4
                case .spider: speed = 3.0
                case .blaze: speed = 1.35
                case .zombie, .skeleton: speed = 2.0
                case .creeper: speed = mob.isCreeperPrimed ? 0.0 : 2.0
                case .slime: speed = 1.8
                case .sheep, .pig, .cow, .chicken: speed = 1.2
                case .wolf: speed = mob.isTamed ? ((mob.isSitting || (mob.isGuarding && !mob.petGuardMoving)) ? 0.0 : 3.1) : 1.8
                case .fox: speed = mob.isTamed ? ((mob.isSitting || (mob.isGuarding && !mob.petGuardMoving)) ? 0.0 : 2.8) : 2.0
                case .bear: speed = mob.isTamed ? ((mob.isSitting || (mob.isGuarding && !mob.petGuardMoving)) ? 0.0 : 2.4) : 1.45
                case .fish: speed = 0.9
                case .dolphin: speed = 1.65
                case .turtle: speed = 0.42
                case .guardian: speed = 0.95
                case .villager:
                    if let target = villagerScheduleTarget(mob), simd_length(SIMD2<Float>(target.x - mob.position.x, target.z - mob.position.z)) <= 0.8 {
                        speed = 0
                    } else { speed = mob.isBaby ? 0.9 : 1.2 }
                case .enderDragon: speed = 2.6
                case .ironGolem: speed = 2.8
                }

                let nextX = mob.position.x - sin(mob.yaw) * speed * dt + mob.knockback.x * dt
                let nextZ = mob.position.z - cos(mob.yaw) * speed * dt + mob.knockback.y * dt
                let gx = Int(floor(nextX))
                let gz = Int(floor(nextZ))
                let curFloorY = Int(floor(mob.position.y - 0.1))
                let stepBlock = BlockCoord(x: gx, y: curFloorY, z: gz)
                let headBlock = BlockCoord(x: gx, y: curFloorY + 1, z: gz)

                if let b = blocks[stepBlock], !b.isPassable {
                    if blocks[headBlock] == nil || blocks[headBlock]?.isPassable == true {
                        mob.velocityY = max(mob.velocityY, 5.4)
                    }
                }

                mob.velocityY -= 15.0 * dt
                let nextY = mob.position.y + mob.velocityY * dt
                let groundY = Float(highestSolidY(atX: gx, z: gz)) + 1.0
                if nextY <= groundY {
                    mob.position = SIMD3<Float>(nextX, groundY, nextZ)
                    mob.velocityY = 0
                } else {
                    mob.position = SIMD3<Float>(nextX, nextY, nextZ)
                }
            }

            mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
            mob.node.eulerAngles = SCNVector3(mob.isSleeping ? -0.22 : 0, mob.yaw, 0)

            let distToPlayer = simd_distance(mob.position, playerGround)
            if hostile && mob.kind != .creeper && distToPlayer < 1.45 {
                hazardTimer += dt
                if hazardTimer >= 1.1 {
                    hazardTimer = 0
                    let rawDmg = mob.kind == .enderDragon ? 4 : 2
                    DispatchQueue.main.async { self.applyDamage(rawDmg, reason: "\(mob.kind.rawValue) attack") }
                }
            }

            if hostile && isNightMode,
               let villager = nearestVillager(to: mob.position, within: 1.5) {
                villager.raidDamageCooldown = max(0, villager.raidDamageCooldown - dt)
                if villager.raidDamageCooldown <= 0 {
                    villager.raidDamageCooldown = 1.8
                    villager.hp -= 2
                    if villager.hp <= 0 {
                        defeatedVillagerIDs.append(villager.id)
                    }
                }
            }
        }

        let defeatedHostiles = mobs.filter { [.zombie, .skeleton, .creeper, .enderman, .spider, .blaze, .guardian].contains($0.kind) && $0.hp <= 0 }
        if !defeatedHostiles.isEmpty {
            let ids = Set(defeatedHostiles.map(\.id))
            for mob in defeatedHostiles { mob.node.removeFromParentNode() }
            mobs.removeAll { ids.contains($0.id) }
        }

        if !defeatedVillagerIDs.isEmpty {
            for id in defeatedVillagerIDs {
                if let index = mobs.firstIndex(where: { $0.id == id && $0.kind == .villager }) {
                    mobs[index].node.removeFromParentNode()
                    mobs.remove(at: index)
                }
            }
            DispatchQueue.main.async {
                self.statusMessage = "A village villager was lost during the night raid"
                self.saveWorld()
            }
        }

        syncBossHUD()
        var expiredArrows: [Int] = []
        for idx in arrows.indices {
            let arrow = arrows[idx]
            arrow.life -= dt
            arrow.velocity.y -= 9.8 * dt
            arrow.position += arrow.velocity * dt
            arrow.node.position = SCNVector3(arrow.position.x, arrow.position.y, arrow.position.z)

            let hitCoord = BlockCoord(x: Int(floor(arrow.position.x)), y: Int(floor(arrow.position.y)), z: Int(floor(arrow.position.z)))
            let hitSolid = (blocks[hitCoord] != nil && blocks[hitCoord]?.isPassable == false)
            let hitPlayer = simd_distance(arrow.position, playerPos - SIMD3<Float>(0, 0.7, 0)) < 0.85

            if hitPlayer {
                let dmg = arrow.damage
                let reason = arrow.damage >= 4 ? "Fire projectile" : "Skeleton arrow"
                DispatchQueue.main.async { self.applyDamage(dmg, reason: reason) }
                expiredArrows.append(idx)
            } else if hitSolid || arrow.life <= 0 {
                expiredArrows.append(idx)
            }
        }
        if !expiredArrows.isEmpty {
            DispatchQueue.main.async {
                for idx in expiredArrows.reversed() where idx < self.arrows.count {
                    self.arrows[idx].node.removeFromParentNode()
                    self.arrows.remove(at: idx)
                }
            }
        }

        if weather != .clear && activeDimension == .overworld {
            let fallSpeed: Float = (weather == .rain) ? 11.0 : 3.2
            for wNode in weatherNodes {
                var ny = Float(wNode.position.y) - fallSpeed * dt
                var nx = Float(wNode.position.x) + (weather == .snowstorm ? 1.4 * dt : 0)
                if ny < 2.0 {
                    ny = 15.0
                    nx = playerPos.x + Float.random(in: -12...12)
                    wNode.position.z = playerPos.z + Float.random(in: -12...12)
                }
                wNode.position.x = nx
                wNode.position.y = ny
            }
        }

        var collectedIndices: [Int] = []
        for idx in droppedItems.indices {
            let item = droppedItems[idx]
            item.bobPhase += dt * 3.5
            let bobY = item.position.y + sin(item.bobPhase) * 0.08
            item.node.position = SCNVector3(item.position.x, bobY, item.position.z)
            item.node.eulerAngles.y += dt * 2.0

            if simd_distance(item.position, playerGround) < 1.65 {
                collectedIndices.append(idx)
            }
        }

        if !collectedIndices.isEmpty {
            DispatchQueue.main.async {
                for idx in collectedIndices.reversed() where self.droppedItems.indices.contains(idx) {
                    let item = self.droppedItems[idx]
                    item.node.removeFromParentNode()
                    self.droppedItems.remove(at: idx)
                    _ = self.addItems(1, of: item.blockType)
                    SoundEngine.shared.play(.pickup)
                    self.statusMessage = "Picked up \(item.blockType.rawValue)"
                }
            }
        }

        var collectedOrbIndices: [Int] = []
        for idx in experienceOrbs.indices {
            let orb = experienceOrbs[idx]
            orb.bobPhase += dt * 4.2
            let bobY = orb.position.y + sin(orb.bobPhase) * 0.10
            orb.node.position = SCNVector3(orb.position.x, bobY, orb.position.z)
            orb.node.eulerAngles.y += dt * 2.8
            if simd_distance(orb.position, playerGround) < 1.8 { collectedOrbIndices.append(idx) }
        }
        if !collectedOrbIndices.isEmpty {
            DispatchQueue.main.async {
                for idx in collectedOrbIndices.reversed() where self.experienceOrbs.indices.contains(idx) {
                    let orb = self.experienceOrbs.remove(at: idx)
                    orb.node.removeFromParentNode()
                    self.experiencePoints += orb.value
                    self.statusMessage = "+\(orb.value) XP • Level \(self.experienceLevel)"
                    SoundEngine.shared.play(.pickup)
                    self.saveWorld()
                }
            }
        }
    }

    private func explodeCreeper(_ creeper: WorldMob) {
        let center = creeper.position
        SoundEngine.shared.play(.explode)
        let playerDistance = simd_distance(playerPos, center)
        if playerDistance < 4.25 {
            let strength = max(0.25, 1.0 - playerDistance / 4.25)
            let damage = max(1, Int((10.0 * strength).rounded()))
            applyDamage(damage, reason: "Creeper blast")
            let away = SIMD2<Float>(playerPos.x - center.x, playerPos.z - center.z)
            if simd_length(away) > 0.001 {
                let impulse = simd_normalize(away) * (5.0 * strength)
                playerPos.x += impulse.x * 0.12
                playerPos.z += impulse.y * 0.12
                verticalVelocity = max(verticalVelocity, 2.8 * strength)
            }
        }

        let radius: Float = 2.45
        let affected = blocks.keys.filter { coord in
            let dx = Float(coord.x) + 0.5 - center.x
            let dy = Float(coord.y) + 0.5 - center.y
            let dz = Float(coord.z) + 0.5 - center.z
            return dx * dx + dy * dy + dz * dz <= radius * radius
        }.prefix(90)

        for coord in affected {
            guard let type = blocks[coord], type != .bedrock, type != .portal else { continue }
            spawnBreakParticles(at: coord, color: type.particleColor)
            removeBlockInternal(coord: coord)
        }
        statusMessage = "Creeper blast! Nearby terrain was damaged"
        saveWorld()
    }

    private func setBlockInternal(coord: BlockCoord, type: BlockType, markModified: Bool = true) {
        blocks[coord] = type
        if markModified { modifiedCoords.insert(coord) }
        if let existing = blockNodes[coord] {
            existing.geometry = sharedGeometries[type]
            existing.position = coord.scnVector
            existing.renderingOrder = type.isTranslucent ? 10 : 0
            configureBlockLight(on: existing, for: type)
        } else {
            let node = SCNNode(geometry: sharedGeometries[type])
            node.position = coord.scnVector
            node.name = "block_\(coord.x)_\(coord.y)_\(coord.z)"
            node.renderingOrder = type.isTranslucent ? 10 : 0
            configureBlockLight(on: node, for: type)
            blocksRootNode.addChildNode(node)
            blockNodes[coord] = node
        }
        let cc = chunkCoord(forWorldX: coord.x, z: coord.z)
        if loadedChunks.contains(cc) { rebuildMergedChunkNode(cc) }
    }

    private func configureBlockLight(on node: SCNNode, for type: BlockType) {
        node.childNodes.filter { $0.name == "block_light" }.forEach { $0.removeFromParentNode() }
        if type.emitsLight && type != .redstoneLamp {
            let lightNode = SCNNode()
            lightNode.name = "block_light"
            let light = SCNLight()
            light.type = .omni
            light.intensity = (type == .torch || type == .soulTorch) ? 420 : 280
            light.attenuationStartDistance = 1
            light.attenuationEndDistance = 8
            if type == .soulTorch { light.color = UIColor(red: 0.35, green: 0.88, blue: 1.0, alpha: 1.0) }
            else if type == .endCrystal || type == .portal { light.color = UIColor(red: 0.80, green: 0.44, blue: 1.0, alpha: 1.0) }
            else if type == .seaLantern { light.color = UIColor(red: 0.72, green: 0.96, blue: 1.0, alpha: 1.0) }
            else if type == .redstoneDust { light.color = UIColor(red: 1.0, green: 0.18, blue: 0.14, alpha: 1.0) }
            else { light.color = UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1.0) }
            lightNode.light = light
            node.addChildNode(lightNode)
        }
    }

    private func removeBlockInternal(coord: BlockCoord, markModified: Bool = true) {
        blocks.removeValue(forKey: coord)
        if markModified { modifiedCoords.insert(coord) }
        openDoors.remove(coord)
        redstoneToggledDoors.remove(coord)
        openedChests.remove(coord)
        chestStorage.removeValue(forKey: chestKey(for: coord))
        activeLevers.remove(coord)
        activePressurePlates.remove(coord)
        activeButtons.removeValue(forKey: coord)
        poweredRedstoneLamps.remove(coord)
        extendedPistons.remove(coord)
        cropStages.removeValue(forKey: coord)
        blockNodes[coord]?.removeFromParentNode()
        blockNodes.removeValue(forKey: coord)
        let cc = chunkCoord(forWorldX: coord.x, z: coord.z)
        if loadedChunks.contains(cc) { rebuildMergedChunkNode(cc) }
    }

    private func removeBlockInternal(at coord: BlockCoord, markModified: Bool = true) {
        removeBlockInternal(coord: coord, markModified: markModified)
    }

    private func clearAllBlockNodes() {
        for (_, node) in blockNodes { node.removeFromParentNode() }
        blockNodes.removeAll()
    }

    private func spawnBreakParticles(at coord: BlockCoord, color: UIColor) {
        let center = coord.scnVector
        for i in 0..<8 {
            let bitGeom = SCNBox(width: 0.14, height: 0.14, length: 0.14, chamferRadius: 0.0)
            let mat = SCNMaterial(); mat.diffuse.contents = color; bitGeom.materials = [mat]
            let bit = SCNNode(geometry: bitGeom); bit.position = center
            let angle = Float(i) * (Float.pi * 0.25)
            scene.rootNode.addChildNode(bit)
            let move = SCNAction.moveBy(x: CGFloat(cos(angle) * 1.4), y: 0.85, z: CGFloat(sin(angle) * 1.4), duration: 0.35)
            let fade = SCNAction.fadeOut(duration: 0.35)
            bit.runAction(SCNAction.sequence([.group([move, fade]), .removeFromParentNode()]))
        }
    }

    func saveWorld() {
        let entries = modifiedCoords.compactMap { coord -> SavedVoxelEntry? in
            blocks[coord].map { SavedVoxelEntry(x: coord.x, y: coord.y, z: coord.z, type: $0) }
        }
        let cropEntries = cropStages.compactMap { coord, stage -> CropSaveEntry? in
            blocks[coord] == .crop ? CropSaveEntry(x: coord.x, y: coord.y, z: coord.z, stage: stage) : nil
        }
        let snapshot = SavedWorldSnapshot(
            blocks: entries,
            spawnCoord: customSpawnCoord,
            openDoors: Array(openDoors),
            openedChests: Array(openedChests),
            activeLevers: Array(activeLevers),
            crops: cropEntries,
            inventory: Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) }),
            foodInventory: Dictionary(uniqueKeysWithValues: foodInventory.map { ($0.key.rawValue, $0.value) }),
            gameMode: gameMode.rawValue,
            hotbarSlots: hotbarSlots.map { $0.rawValue },
            hotbarSelection: hotbarSelection,
            equippedGear: equippedGear.rawValue,
            gearDurability: gearDurability,
            selectedTool: selectedTool.rawValue,
            toolTier: toolTier.rawValue,
            toolDurability: toolDurability,
            armorTier: armorTier.rawValue,
            armorDurability: armorDurability,
            helmetTier: helmetTier.rawValue,
            chestplateTier: chestplateTier.rawValue,
            leggingsTier: leggingsTier.rawValue,
            bootsTier: bootsTier.rawValue,
            helmetDurability: helmetDurability,
            chestplateDurability: chestplateDurability,
            leggingsDurability: leggingsDurability,
            bootsDurability: bootsDurability,
            equipmentInventory: equipmentInventory,
            chestStorage: chestStorage,
            experiencePoints: experiencePoints,
            enchantments: enchantments,
            villagers: mobs.filter { $0.kind == .villager }.map { mob in
                SavedVillagerEntry(id: mob.id, x: mob.position.x, y: mob.position.y, z: mob.position.z,
                                   yaw: mob.yaw, hp: mob.hp, profession: mob.profession.rawValue,
                                   homeX: mob.homePosition?.x, homeY: mob.homePosition?.y, homeZ: mob.homePosition?.z,
                                   workX: mob.workstationPosition?.x, workY: mob.workstationPosition?.y, workZ: mob.workstationPosition?.z,
                                   isBaby: mob.isBaby, ageTimer: mob.ageTimer)
            },
            potionInventory: Dictionary(uniqueKeysWithValues: potionInventory.map { ($0.key.rawValue, $0.value) }),
            unlockedAchievements: Array(unlockedAchievements),
            defeatedHostileCount: defeatedHostileCount,
            activePotionEffects: Dictionary(uniqueKeysWithValues: activePotionEffects.map { ($0.key.rawValue, $0.value) }),
            boatCount: boatCount,
            deployedBoat: boatNode.map {
                SavedBoatState(x: Float($0.position.x), y: Float($0.position.y),
                               z: Float($0.position.z), yaw: Float($0.eulerAngles.y))
            },
            discoveredBiomes: Array(discoveredBiomes),
            pets: mobs.filter { $0.isTamed && [.wolf, .fox, .bear].contains($0.kind) }.map { mob in
                SavedPetEntry(id: mob.id, kind: mob.kind.rawValue, x: mob.position.x, y: mob.position.y,
                              z: mob.position.z, yaw: mob.yaw, hp: mob.hp, isSitting: mob.isSitting,
                              isGuarding: mob.isGuarding,
                              guardX: mob.guardPosition?.x, guardY: mob.guardPosition?.y,
                              guardZ: mob.guardPosition?.z)
            }
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL, options: Data.WritingOptions.atomic)
        }
    }

    func respawnPlayer() {
        let spawn = customSpawnCoord ?? BlockCoord(x: 0, y: highestSolidY(atX: 0, z: 6) + 1, z: 6)
        let groundY = highestSolidY(atX: spawn.x, z: spawn.z)
        playerPos = SIMD3<Float>(Float(spawn.x) + 0.5, Float(groundY) + 2.2, Float(spawn.z) + 0.5)
        verticalVelocity = 0
        fallStartY = nil
        health = 20
        hunger = 20
        oxygen = 10
        stamina = 100
        isSprinting = false
        isUnderwater = false
        drowningTimer = 0
        oxygenTickTimer = 0
        updateChunksAroundPlayer(force: true)
        updateCameraTransform()
        syncPlayerHUD()
    }

    private func applyDamage(_ amount: Int, reason: String) {
        guard amount > 0 else { return }
        let normalizedReason = reason.lowercased()
        let isHeatDamage = normalizedReason.contains("burn") || normalizedReason.contains("lava") || normalizedReason.contains("magma")
        if isHeatDamage && (activePotionEffects[.fireResistance] ?? 0) > 0 {
            statusMessage = "Fire Resistance absorbed the heat damage"
            return
        }
        let potionReduction = (activePotionEffects[.resistance] ?? 0) > 0 ? 3 : 0
        let shieldReduction = isShieldRaised ? max(1, amount / 2) : 0
        let reducedAmount = max(1, amount - effectiveArmorReduction - potionReduction - shieldReduction)
        health = max(0, health - reducedAmount)
        damageArmor()
        SoundEngine.shared.play(.hurt)
        if health == 0 {
            statusMessage = "You died (\(reason)) — respawning"
            respawnPlayer()
        } else {
            statusMessage = "\(reason) (-\(amount) HP)"
        }
    }

    private func highestSolidY(atX x: Int, z: Int) -> Int {
        for y in stride(from: 20, through: 0, by: -1) {
            if let b = blocks[BlockCoord(x: x, y: y, z: z)], !b.isPassable { return y }
        }
        return 1
    }

    private func syncPlayerHUD() {
        let ix = Int(floor(playerPos.x))
        let iy = Int(floor(playerPos.y - 1.5))
        let iz = Int(floor(playerPos.z))
        coordsText = "X: \(ix)  Y: \(iy)  Z: \(iz)"
        currentBiome = BiomeType.biomeAt(x: ix, z: iz, dimension: activeDimension)
        if activeDimension == .overworld {
            let newlyDiscovered = discoveredBiomes.insert(currentBiome.rawValue).inserted
            if newlyDiscovered {
                switch currentBiome {
                case .swamp: unlockAchievement("swamp_walker")
                case .jungle: unlockAchievement("jungle_explorer")
                case .taiga: unlockAchievement("taiga_traveler")
                case .beach: unlockAchievement("coastal_roamer")
                default: break
                }
                let overworldBiomeNames = Set([BiomeType.plains.rawValue, BiomeType.desert.rawValue,
                                               BiomeType.forest.rawValue, BiomeType.highlands.rawValue,
                                               BiomeType.ocean.rawValue, BiomeType.beach.rawValue,
                                               BiomeType.swamp.rawValue, BiomeType.taiga.rawValue,
                                               BiomeType.jungle.rawValue])
                if overworldBiomeNames.isSubset(of: discoveredBiomes) { unlockAchievement("biome_explorer") }
                saveWorld()
            }
        }
    }

    // MARK: - Camera & Movement Controls

    func setMoveInput(forward: Float, strafe: Float) { moveInput = SIMD2<Float>(strafe, forward) }

    func lookDelta(deltaX: Float, deltaY: Float) {
        let sensitivity: Float = 0.0055
        yaw -= deltaX * sensitivity
        pitch = max(-Float.pi * 0.46, min(Float.pi * 0.46, pitch - deltaY * sensitivity))
        updateCameraTransform()
    }

    func jump() {
        guard !isInBoat else { statusMessage = "Exit the boat before jumping"; return }
        let feetBlock = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 1.72)), z: Int(floor(playerPos.z)))
        if (blocks[feetBlock]?.isPassable == false) || verticalVelocity == 0 {
            verticalVelocity = 6.2
            SoundEngine.shared.play(.jump)
        }
    }

    func toggleCameraMode() {
        cameraMode = (cameraMode == .firstPerson) ? .overview : .firstPerson
        avatarNode.isHidden = (cameraMode != .overview)
        updateCameraTransform()
    }

    private func updateCameraTransform() {
        avatarNode.position = SCNVector3(playerPos.x, playerPos.y, playerPos.z)
        avatarNode.eulerAngles = SCNVector3(0, yaw, 0)
        switch cameraMode {
        case .firstPerson:
            cameraNode.position = SCNVector3(playerPos.x, playerPos.y, playerPos.z)
            cameraNode.eulerAngles = SCNVector3(pitch, yaw, 0)
        case .overview:
            let dist: Float = 14.0
            cameraNode.position = SCNVector3(playerPos.x + sin(yaw) * dist, playerPos.y + 9.5, playerPos.z + cos(yaw) * dist)
            cameraNode.look(at: SCNVector3(playerPos.x, playerPos.y - 0.5, playerPos.z))
        }
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if let prev = lastFrameTime { dt = min(0.05, max(0.001, Float(time - prev))) } else { dt = 0.016 }
        lastFrameTime = time
        updateRedstoneSensors(at: time)
        miningFatigueRemaining = max(0, miningFatigueRemaining - dt)
        dolphinGuideAchievementTimer = max(0, dolphinGuideAchievementTimer - dt)

        var toggledCycleNight: Bool?
        if isAutoCycleEnabled && activeDimension == .overworld {
            dayClockTimer += dt
            if dayClockTimer >= 35.0 { dayClockTimer = 0; toggledCycleNight = !isNightMode }
        }

        weatherTimer += dt
        let nextWeatherCycle = (weatherTimer >= 45.0)
        if nextWeatherCycle { weatherTimer = 0 }

        let targetNight: Float = isNightMode ? 1.0 : 0.0
        let shouldUpdateSky = abs(nightProgress - targetNight) > 0.001
        if shouldUpdateSky {
            let step = dt * 2.4
            nightProgress = nightProgress < targetNight ? min(targetNight, nightProgress + step) : max(targetNight, nightProgress - step)
        }

        for node in cloudNodes {
            var nextX = node.position.x + 0.75 * dt
            if nextX > 16 { nextX = -16 }
            node.position.x = nextX
        }

        let forwardXZ = SIMD2<Float>(-sin(yaw), -cos(yaw))
        let rightXZ = SIMD2<Float>(cos(yaw), -sin(yaw))
        let wishXZ = forwardXZ * moveInput.y + rightXZ * moveInput.x
        let wishLen = simd_length(wishXZ)
        let dirXZ = wishLen > 0.001 ? wishXZ / wishLen : SIMD2<Float>(0, 0)
        let canSprint = isSprinting && stamina > 1 && (gameMode == .creative || hunger > 0)
        var headSubmerged = false
        var landedFallDamage = 0
        var hazardHit: String?

        if isInBoat, let boat = boatNode {
            let steer = moveInput.x
            if abs(steer) > 0.05 { yaw -= steer * dt * 1.75 }
            let forward = moveInput.y
            boatSpeed += forward * 7.0 * dt
            boatSpeed *= pow(0.985, dt * 60.0)
            boatSpeed = max(-2.8, min(8.0, boatSpeed))
            let dx = -sin(yaw) * boatSpeed * dt
            let dz = -cos(yaw) * boatSpeed * dt
            let candidateX = Float(boat.position.x) + dx
            let candidateZ = Float(boat.position.z) + dz
            let waterY = Int(floor(Float(boat.position.y) - 0.8))
            let hullSamples = [
                (0.0, 0.0), (-0.48, -0.58), (0.48, -0.58),
                (-0.48, 0.58), (0.48, 0.58)
            ]
            let supportedSamples = hullSamples.reduce(into: 0) { count, sample in
                let cell = BlockCoord(x: Int(floor(candidateX + Float(sample.0))),
                                      y: waterY,
                                      z: Int(floor(candidateZ + Float(sample.1))))
                if blocks[cell] == .water { count += 1 }
            }
            if supportedSamples >= 3 {
                boat.position.x = candidateX
                boat.position.z = candidateZ
                boatTravelDistance += abs(boatSpeed * dt)
            } else {
                boatSpeed *= 0.68
            }
            boat.eulerAngles.y = yaw
            let rowingFactor = min(1.0, abs(boatSpeed) / 5.0)
            boat.eulerAngles.x = -min(0.045, rowingFactor * 0.045) * (boatSpeed >= 0 ? 1 : -1)
            boat.eulerAngles.z = -moveInput.x * rowingFactor * 0.035
            boat.position.y += sin(Float(time) * 2.1) * 0.012
            boatAutosaveTimer += dt
            if boatAutosaveTimer >= 3.0 {
                boatAutosaveTimer = 0
                saveWorld()
            }
            for (index, paddle) in boatPaddles.enumerated() {
                let phase = Float(time) * (abs(boatSpeed) > 0.15 ? 7.5 : 1.2) + (index == 0 ? 0 : .pi)
                paddle.eulerAngles.x = sin(phase) * (abs(boatSpeed) > 0.15 ? 0.72 : 0.08)
                paddle.eulerAngles.z = .pi / 2 + cos(phase) * 0.12
            }
            playerPos = SIMD3<Float>(Float(boat.position.x), Float(boat.position.y) + 1.65, Float(boat.position.z))
            verticalVelocity = 0
            fallStartY = nil
            if boatTravelDistance >= 100 {
                boatTravelDistance = 0
                DispatchQueue.main.async { self.unlockAchievement("sailor") }
            }
        } else {
        let potionSpeedBoost: Float = (activePotionEffects[.speed] ?? 0) > 0 ? 1.45 : 1.0
        let dolphinGrace: Float = mobs.contains(where: { $0.kind == .dolphin && simd_distance($0.position, playerPos) < 5.0 }) ? 1.28 : 1.0
        let sprintBoost: Float = canSprint ? 1.65 : 1.0
        let moveSpeed: Float = 5.2 * potionSpeedBoost * sprintBoost * dolphinGrace
        let nextX = playerPos.x + dirXZ.x * moveSpeed * dt
        let nextZ = playerPos.z + dirXZ.y * moveSpeed * dt
        let radius: Float = 0.28
        let feetY = Int(floor(playerPos.y - 1.55))
        let headY = Int(floor(playerPos.y - 0.2))

        if !collidesHorizontal(x: nextX, z: playerPos.z, radius: radius, minY: feetY, maxY: headY) {
            playerPos.x = nextX
        } else if collidesHorizontal(x: nextX, z: playerPos.z, radius: radius, minY: feetY, maxY: feetY)
                    && !collidesHorizontal(x: nextX, z: playerPos.z, radius: radius, minY: feetY + 1, maxY: headY + 1) {
            playerPos.x = nextX
            playerPos.y += 1.05
        }

        if !collidesHorizontal(x: playerPos.x, z: nextZ, radius: radius, minY: feetY, maxY: headY) {
            playerPos.z = nextZ
        } else if collidesHorizontal(x: playerPos.x, z: nextZ, radius: radius, minY: feetY, maxY: feetY)
                    && !collidesHorizontal(x: playerPos.x, z: nextZ, radius: radius, minY: feetY + 1, maxY: headY + 1) {
            playerPos.z = nextZ
            playerPos.y += 1.05
        }

        let feetCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 1.55)), z: Int(floor(playerPos.z)))
        let inWater = blocks[feetCoord] == .water
        let headCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 0.2)), z: Int(floor(playerPos.z)))
        headSubmerged = blocks[headCoord] == .water

        if inWater {
            if headSubmerged {
                // Buoyancy counters sinking and gently carries the player upward.
                verticalVelocity = max(-0.45, verticalVelocity - 1.2 * dt)
                if moveInput.y > 0.15 {
                    verticalVelocity = min(2.2, verticalVelocity + 2.8 * dt)
                }
            } else {
                verticalVelocity = max(-2.2, verticalVelocity - 5.5 * dt)
            }
            fallStartY = nil
        } else {
            if verticalVelocity < -1.5 && fallStartY == nil { fallStartY = playerPos.y }
            verticalVelocity -= 15.0 * dt
        }

        let nextEyeY = playerPos.y + verticalVelocity * dt
        let nextFeetY = nextEyeY - 1.65
        if verticalVelocity < 0 {
            let checkFeet = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(nextFeetY)), z: Int(floor(playerPos.z)))
            if let blockBelow = blocks[checkFeet], !blockBelow.isPassable {
                if let startY = fallStartY {
                    let dropDistance = startY - nextEyeY
                    if dropDistance > 4.2 { landedFallDamage = min(10, Int((dropDistance - 4.0) * 1.6)) }
                    fallStartY = nil
                }
                playerPos.y = Float(checkFeet.y + 1) + 1.65
                verticalVelocity = 0
                if blockBelow == .magma {
                    hazardTimer += dt
                    if hazardTimer >= 0.9 { hazardTimer = 0; hazardHit = "Magma burn" }
                } else {
                    hazardTimer = 0
                }
            } else {
                playerPos.y = max(2.2, nextEyeY)
            }
        } else {
            playerPos.y = max(2.2, nextEyeY)
        }

        }
        updateMobsArrowsAndDrops(dt: dt)
        updateVillagerSchedules(dt: dt)

        let viewSq = maxViewDistance * maxViewDistance
        for (coord, node) in blockNodes {
            let dx = coord.scnVector.x - playerPos.x
            let dz = coord.scnVector.z - playerPos.z
            node.isHidden = (dx * dx + dz * dz) > viewSq
        }

        if gameMode == .survival && wishLen > 0.01 { hungerDrainTimer += dt }
        let shouldDrainHunger = (hungerDrainTimer >= (canSprint ? 5.5 : 9.0))
        if shouldDrainHunger { hungerDrainTimer = 0 }

        simTickTimer += dt
        let shouldRunSim = (simTickTimer >= 0.85)
        if shouldRunSim { simTickTimer = 0 }

        netSyncTimer += dt
        let shouldSyncNet = (netSyncTimer >= 0.35 && multiplayerEnabled)
        if shouldSyncNet { netSyncTimer = 0 }

        // Preserve infrequent world events until the next main-thread tick.
        if let toggledCycleNight { pendingNightCycle = toggledCycleNight }
        if nextWeatherCycle && activeDimension == .overworld { pendingWeatherCycle = true }

        // SceneKit camera movement stays smooth at render frequency. SwiftUI-facing
        // state and chunk maintenance are deliberately capped at 10 updates/second.
        updateCameraTransform()
        guard time - lastMainThreadUpdateTime >= 0.10 else { return }
        lastMainThreadUpdateTime = time

        let updatedNight = nightProgress
        let nightToApply = pendingNightCycle
        pendingNightCycle = nil
        let weatherCycleToApply = pendingWeatherCycle
        pendingWeatherCycle = false

        DispatchQueue.main.async {
            self.connectedPeerCount = self.lanManager.connectedPeers.count
            self.isUnderwater = headSubmerged
            if self.gameMode == .survival {
                self.oxygenTickTimer += dt
                if self.oxygenTickTimer >= 1.0 {
                    self.oxygenTickTimer -= 1.0
                    if headSubmerged && (self.activePotionEffects[.waterBreathing] ?? 0) <= 0 {
                        self.oxygen = max(0, self.oxygen - 1)
                    } else {
                        self.oxygen = min(10, self.oxygen + 1)
                    }
                }
                if headSubmerged && (self.activePotionEffects[.waterBreathing] ?? 0) <= 0 {
                    self.drowningTimer += dt
                    if self.oxygen == 0 && self.drowningTimer >= 1.5 {
                        self.drowningTimer = 0
                        self.applyDamage(2, reason: "Drowning")
                    }
                } else {
                    self.drowningTimer = 0
                }
                if canSprint && wishLen > 0.01 {
                    self.stamina = max(0, self.stamina - Double(dt) * 19.0)
                    self.staminaRecoveryDelay = 0.65
                    if self.stamina <= 0 { self.isSprinting = false }
                } else {
                    self.staminaRecoveryDelay = max(0, self.staminaRecoveryDelay - dt)
                    if self.staminaRecoveryDelay <= 0 {
                        let recoveryRate = (self.weather == .snowstorm && self.activeDimension == .overworld) ? 8.0 : 13.0
                        self.stamina = min(100, self.stamina + Double(dt) * recoveryRate)
                    }
                }
            } else {
                self.oxygen = 10
                self.stamina = 100
                self.isSprinting = false
                self.drowningTimer = 0
                self.oxygenTickTimer = 0
            }
            for effect in Array(self.activePotionEffects.keys) {
                let remaining = max(0, (self.activePotionEffects[effect] ?? 0) - dt)
                if remaining <= 0 { self.activePotionEffects.removeValue(forKey: effect) }
                else { self.activePotionEffects[effect] = remaining }
            }
            if (self.activePotionEffects[.regeneration] ?? 0) > 0 && self.health < 20 {
                self.regenerationTickTimer += dt
                if self.regenerationTickTimer >= 3.0 {
                    self.regenerationTickTimer = 0
                    self.health = min(20, self.health + 1)
                }
            } else { self.regenerationTickTimer = 0 }

            // Survival-style natural regeneration at high hunger, and starvation
            // pressure when the food bar has been empty for a sustained period.
            if self.gameMode == .survival && self.hunger >= 18 && self.health > 0 && self.health < 20 {
                self.naturalRegenerationTimer += dt
                if self.naturalRegenerationTimer >= 4.0 {
                    self.naturalRegenerationTimer = 0
                    self.health = min(20, self.health + 1)
                    self.hunger = max(0, self.hunger - 1)
                }
            } else { self.naturalRegenerationTimer = 0 }

            if self.gameMode == .survival && self.hunger == 0 && self.health > 1 {
                self.starvationTimer += dt
                if self.starvationTimer >= 8.0 {
                    self.starvationTimer = 0
                    self.applyDamage(1, reason: "Starvation")
                }
            } else { self.starvationTimer = 0 }
            if let nextNight = nightToApply { self.isNightMode = nextNight }
            if weatherCycleToApply { self.cycleWeather() }
            if shouldUpdateSky { self.applySkyLighting(progress: updatedNight) }
            self.updateChunksAroundPlayer()
            self.tickFurnace(dt: Double(dt))
            if shouldRunSim {
                self.stepFallingBlocks()
                self.stepFlowingWater()
                self.cropGrowthTimer += 0.85
                if self.cropGrowthTimer >= 30.0 {
                    self.cropGrowthTimer = 0
                    self.stepCropGrowth()
                }
            }
            if shouldSyncNet {
                self.broadcastPlayerPosition()
            }
            if self.gameMode == .survival && shouldDrainHunger && self.hunger > 0 {
                self.hunger = max(0, self.hunger - 1)
            }
            if landedFallDamage > 0 { self.applyDamage(landedFallDamage, reason: "Fall damage") }
            if let hazard = hazardHit { self.applyDamage(2, reason: hazard) }
            self.syncPlayerHUD()
        }
    }

    private func tickFurnace(dt: Double) {
        guard queuedSmeltCount > 0 || furnaceBurnRemaining > 0 else {
            furnaceSmeltProgress = 0
            return
        }
        if furnaceBurnRemaining > 0 {
            furnaceBurnRemaining = max(0, furnaceBurnRemaining - dt)
        } else if queuedSmeltCount > 0 && count(for: .coalOre) > 0 {
            inventory[.coalOre] = max(0, count(for: .coalOre) - 1)
            furnaceBurnRemaining = 8.0
        }

        if queuedSmeltCount > 0 && furnaceBurnRemaining > 0 {
            furnaceSmeltProgress += dt / 3.0
            if furnaceSmeltProgress >= 1.0 {
                furnaceSmeltProgress = 0
                queuedSmeltCount -= 1
                foodInventory[.cookedMutton] = foodCount(for: .cookedMutton) + 1
                SoundEngine.shared.play(.eat)
                statusMessage = "Furnace smelted +1 Cooked Mutton"
            }
        }
    }

    private func stepFallingBlocks() {
        for coord in blocks.keys.sorted(by: { $0.y < $1.y }) {
            guard let b = blocks[coord], b.obeysGravity, coord.y > 1 else { continue }
            let below = BlockCoord(x: coord.x, y: coord.y - 1, z: coord.z)
            if blocks[below] == nil {
                removeBlockInternal(coord: coord)
                setBlockInternal(coord: below, type: b, markModified: true)
            }
        }
    }

    private func stepFlowingWater() {
        let waterCoords = blocks.filter { $0.value == .water }.map { $0.key }.prefix(40)
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for coord in waterCoords {
            let below = BlockCoord(x: coord.x, y: coord.y - 1, z: coord.z)
            if blocks[below] == nil && coord.y > 1 {
                setBlockInternal(coord: below, type: .water, markModified: false)
                continue
            }
            for (dx, dz) in dirs {
                let side = BlockCoord(x: coord.x + dx, y: coord.y, z: coord.z + dz)
                let support = BlockCoord(x: side.x, y: side.y - 1, z: side.z)
                if blocks[side] == nil && blocks[support] != nil && blocks[support] != .water {
                    setBlockInternal(coord: side, type: .water, markModified: false)
                    break
                }
            }
        }
    }

    private func isCropHydrated(at crop: BlockCoord) -> Bool {
        // A water source within four horizontal blocks hydrates the crop,
        // provided it is no more than one block above or below the crop.
        for dx in -4...4 {
            for dz in -4...4 {
                guard abs(dx) + abs(dz) <= 4 else { continue }
                for dy in -1...1 {
                    let water = BlockCoord(x: crop.x + dx, y: crop.y + dy, z: crop.z + dz)
                    if blocks[water] == .water { return true }
                }
            }
        }
        return false
    }

    private func stepCropGrowth() {
        cropGrowthCycle += 1
        for (coord, type) in blocks where type == .crop {
            let currentStage = cropStages[coord] ?? 0
            let hydrated = isCropHydrated(at: coord)
            if let cropNode = blockNodes[coord] {
                cropNode.geometry?.firstMaterial?.diffuse.contents = hydrated ? UIColor(red: 0.34, green: 0.72, blue: 0.24, alpha: 1.0) : UIColor(red: 0.48, green: 0.62, blue: 0.22, alpha: 1.0)
                cropNode.geometry?.firstMaterial?.emission.contents = hydrated ? UIColor(red: 0.04, green: 0.10, blue: 0.02, alpha: 1.0) : UIColor.clear
            }
            guard currentStage < 3 else { continue }
            // Hydrated crops grow on each 30-second world tick.
            // Dry crops grow on every second tick.
            let rainHydrated = weather == .rain && activeDimension == .overworld
            guard hydrated || rainHydrated || cropGrowthCycle.isMultiple(of: 2) else { continue }
            if weather == .snowstorm && !hydrated && !cropGrowthCycle.isMultiple(of: 3) { continue }
            let stage = min(3, currentStage + 1)
            cropStages[coord] = stage
            if let cropNode = blockNodes[coord] {
                cropNode.scale = SCNVector3(1.0, CGFloat(0.45 + Double(stage) * 0.22), 1.0)
                let wetTint = hydrated ? UIColor(red: 0.34, green: 0.72, blue: 0.24, alpha: 1.0) : UIColor(red: 0.48, green: 0.62, blue: 0.22, alpha: 1.0)
                cropNode.geometry?.firstMaterial?.diffuse.contents = wetTint
                cropNode.geometry?.firstMaterial?.emission.contents = hydrated ? UIColor(red: 0.04, green: 0.10, blue: 0.02, alpha: 1.0) : UIColor.clear
            }
        }
        saveWorld()
    }

    private func decayNearbyLeaves(around brokenCoord: BlockCoord) {
        let logTypes: Set<BlockType> = [.wood, .spruceLog, .birchLog]
        for dx in -3...3 {
            for dy in -1...4 {
                for dz in -3...3 {
                    let c = BlockCoord(x: brokenCoord.x + dx, y: brokenCoord.y + dy, z: brokenCoord.z + dz)
                    guard blocks[c] == .leaves else { continue }
                    let hasNearbyLog = (-2...2).contains { lx in
                        (-2...2).contains { ly in
                            (-2...2).contains { lz in
                                if let t = blocks[BlockCoord(x: c.x + lx, y: c.y + ly, z: c.z + lz)] { return logTypes.contains(t) }
                                return false
                            }
                        }
                    }
                    if !hasNearbyLog {
                        spawnBreakParticles(at: c, color: BlockType.leaves.particleColor)
                        removeBlockInternal(coord: c)
                        spawnDroppedItem(type: .leaves, at: c)
                    }
                }
            }
        }
    }

    private func collidesHorizontal(x: Float, z: Float, radius: Float, minY: Int, maxY: Int) -> Bool {
        let minX = Int(floor(x - radius))
        let maxX = Int(floor(x + radius))
        let minZ = Int(floor(z - radius))
        let maxZ = Int(floor(z + radius))
        for bx in minX...maxX {
            for by in minY...maxY {
                for bz in minZ...maxZ {
                    let c = BlockCoord(x: bx, y: by, z: bz)
                    if let b = blocks[c], !b.isPassable {
                        if b == .door && openDoors.contains(c) { continue }
                        return true
                    }
                }
            }
        }
        return false
    }

    // MARK: - LAN Sync Payloads

    private func broadcastBlockEdit(coord: BlockCoord, type: BlockType?) {
        guard multiplayerEnabled else { return }
        lanManager.send([
            "kind": "block",
            "x": coord.x,
            "y": coord.y,
            "z": coord.z,
            "type": type?.rawValue ?? ""
        ])
    }

    private func broadcastPlayerPosition() {
        lanManager.send([
            "kind": "pos",
            "x": Double(playerPos.x),
            "y": Double(playerPos.y),
            "z": Double(playerPos.z)
        ])
    }

    private func broadcastMobSync(id: UUID, hp: Int) {
        guard multiplayerEnabled else { return }
        lanManager.send([
            "kind": "mob",
            "id": id.uuidString,
            "hp": hp
        ])
    }

    private func handleNetworkData(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["kind"] as? String else { return }
        if kind == "block",
           let x = obj["x"] as? Int, let y = obj["y"] as? Int, let z = obj["z"] as? Int,
           let typeStr = obj["type"] as? String {
            let coord = BlockCoord(x: x, y: y, z: z)
            if typeStr.isEmpty {
                removeBlockInternal(coord: coord)
            } else if let bt = BlockType(rawValue: typeStr) {
                setBlockInternal(coord: coord, type: bt, markModified: true)
            }
            saveWorld()
        } else if kind == "pos",
                  let x = obj["x"] as? Double, let y = obj["y"] as? Double, let z = obj["z"] as? Double {
            remotePeerNode.position = SCNVector3(Float(x), Float(y) - 1.5, Float(z))
            remotePeerNode.isHidden = false
            statusMessage = "Peer at X:\(Int(x)) Y:\(Int(y)) Z:\(Int(z))"
        } else if kind == "mob",
                  let idStr = obj["id"] as? String, let uuid = UUID(uuidString: idStr),
                  let hp = obj["hp"] as? Int,
                  let idx = mobs.firstIndex(where: { $0.id == uuid }) {
            if hp <= 0 {
                mobs[idx].node.removeFromParentNode()
                mobs.remove(at: idx)
            } else {
                mobs[idx].hp = hp
            }
        }
    }

    // MARK: - Block & Mob Interaction

    func handleTap(at point: CGPoint, in scnView: SCNView) {
        let hits = scnView.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])

        if let mobHit = hits.first(where: { $0.node.name?.hasPrefix("mob_") == true || $0.node.parent?.name?.hasPrefix("mob_") == true }) {
            let rawName = mobHit.node.name?.hasPrefix("mob_") == true ? mobHit.node.name! : (mobHit.node.parent?.name ?? "")
            let uuidStr = String(rawName.dropFirst(4))
            if let uuid = UUID(uuidString: uuidStr), let idx = mobs.firstIndex(where: { $0.id == uuid }) {
                let mob = mobs[idx]
                if mob.isTamed && [.wolf, .fox, .bear].contains(mob.kind) {
                    if !mob.isSitting && !mob.isGuarding {
                        mob.isSitting = true
                        mob.isGuarding = false
                        mob.guardPosition = nil
                        statusMessage = "\(mob.kind.rawValue) is sitting"
                    } else if mob.isSitting {
                        mob.isSitting = false
                        mob.isGuarding = true
                        mob.guardPosition = mob.position
                        unlockAchievement("watchful_companion")
                        statusMessage = "\(mob.kind.rawValue) is guarding this spot"
                    } else {
                        mob.isSitting = false
                        mob.isGuarding = false
                        mob.guardPosition = nil
                        statusMessage = "\(mob.kind.rawValue) will follow you"
                    }
                    saveWorld()
                    return
                }
                if tameCompanion(mob) { return }
                if feedAnimal(mob) { return }
                if mob.kind == .villager {
                    let distance = simd_length(SIMD2<Float>(mob.position.x - playerPos.x, mob.position.z - playerPos.z))
                    guard distance <= 5.0 else { statusMessage = "Move closer to the Villager to trade"; return }
                    activeVillagerID = mob.id
                    showVillagerTradeSheet = true
                    statusMessage = "Trading with \(mob.profession.rawValue) Villager"
                    return
                }
                let weaponCondition = gameMode == .survival && toolDurability == 0 ? 0.5 : 1.0
                let sharpnessBonus = enchantmentLevel(.sharpness) * 2
                let strengthBonus = (activePotionEffects[.strength] ?? 0) > 0 ? 5 : 0
                let criticalBonus = verticalVelocity < -1.0 ? 3 : 0
                mob.hp -= max(1, Int(Double(selectedTool.attackDamage + sharpnessBonus + strengthBonus + criticalBonus + (toolTier == .diamond ? 2 : (toolTier == .iron ? 1 : 0))) * weaponCondition))
                if selectedTool == .sword || selectedTool == .axe { damageTool() }
                saveWorld()
                broadcastMobSync(id: mob.id, hp: mob.hp)
                let pushDir = simd_normalize(SIMD2<Float>(mob.position.x - playerPos.x, mob.position.z - playerPos.z))
                if simd_length(pushDir) > 0.01 {
                    mob.knockback += pushDir * 6.5
                    mob.velocityY = max(mob.velocityY, 3.8)
                }
                SoundEngine.shared.play(.hitMob)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if mob.hp <= 0 {
                    mob.node.removeFromParentNode()
                    mobs.remove(at: idx)
                    let mobXP = mob.kind == .enderDragon ? 80 : ([MobKind.zombie, .skeleton, .creeper, .enderman, .slime, .spider, .blaze].contains(mob.kind) ? 6 : 2)
                    awardExperience(mobXP, at: mob.position)
                    if [.zombie, .skeleton, .creeper, .enderman, .slime, .spider, .blaze, .enderDragon, .guardian].contains(mob.kind) {
                        defeatedHostileCount += 1
                        unlockAchievement("first_blood")
                        if defeatedHostileCount >= 10 { unlockAchievement("monster_hunter") }
                    }
                    if mob.isElderGuardian {
                        unlockAchievement("monument_conqueror")
                        _ = addItems(Int.random(in: 5...8), of: .prismarine)
                        _ = addItems(Int.random(in: 2...4), of: .seaLantern)
                        _ = addItems(Int.random(in: 2...3), of: .amethyst)
                        experiencePoints += 35
                        statusMessage = "ELDER GUARDIAN DEFEATED · Monument treasure secured!"
                    }
                    if mob.kind == .enderDragon {
                        unlockAchievement("dragon_slayer")
                        _ = addItems(12, of: .amethyst)
                        _ = addItems(8, of: .glowstone)
                        experiencePoints += 120
                        statusMessage = "ENDER DRAGON DEFEATED · Legendary loot recovered!"
                    } else if mob.kind == .blaze {
                        _ = addItems(Int.random(in: 1...3), of: .glowstone)
                        statusMessage = "Blaze defeated · Glowstone dropped"
                    } else if mob.kind == .spider {
                        _ = addItems(1, of: .wool)
                        statusMessage = "Spider defeated · Fibre collected"
                    }
                    if mob.kind == .sheep {
                        _ = addItems(2, of: .wool)
                        foodInventory[.rawMutton, default: 0] += 1
                        statusMessage = "Sheep dropped Wool and Raw Mutton"
                    } else if mob.kind == .pig {
                        foodInventory[.rawPork, default: 0] += 2
                        statusMessage = "Pig dropped 2 Raw Porkchops"
                    } else if mob.kind == .cow {
                        foodInventory[.rawBeef, default: 0] += 2
                        statusMessage = "Cow dropped 2 Raw Beef"
                    } else if mob.kind == .chicken {
                        foodInventory[.rawChicken, default: 0] += 1
                        foodInventory[.seeds, default: 0] += 1
                        statusMessage = "Chicken dropped Raw Chicken and Seeds"
                    } else if mob.kind == .guardian {
                        _ = addItems(Int.random(in: 2...4), of: .prismarine)
                        _ = addItems(Int.random(in: 1...2), of: .seaLantern)
                        statusMessage = "Guardian defeated · Prismarine and sea lantern recovered"
                    } else if mob.kind == .fish {
                        foodInventory[.rawFish, default: 0] += 1
                        statusMessage = "Fish dropped Raw Fish"
                    } else if mob.kind == .dolphin {
                        foodInventory[.rawFish, default: 0] += 2
                        statusMessage = "Dolphin dropped 2 Raw Fish"
                    } else if mob.kind == .turtle {
                        statusMessage = "Turtle returned to the ocean"
                    } else if ![MobKind.enderDragon, .blaze, .spider, .wolf, .fox, .bear].contains(mob.kind) {
                        _ = addItems(3, of: .emeraldOre)
                        statusMessage = "Defeated \(mob.kind.rawValue) (+3 EmeraldOre)"
                    }
                } else {
                    statusMessage = "Hit \(mob.kind.rawValue) with \(toolTier.rawValue) \(selectedTool.rawValue) (\(mob.hp) HP left)"
                }
                return
            }
        }

        guard let hit = hits.first(where: { $0.node !== highlightNode && $0.node.name?.hasPrefix("block_") == true }) else {
            highlightNode.isHidden = true
            if selectedTool == .fishingRod { statusMessage = "Aim at a water block to fish" }
            return
        }

        let targetCoord = BlockCoord.from(worldPosition: hit.node.position)
        highlightNode.position = targetCoord.scnVector
        highlightNode.isHidden = false

        let haptic = UIImpactFeedbackGenerator(style: .light)

        if let hitType = blocks[targetCoord] {
            if hitType == .water && selectedTool == .fishingRod {
                castFishingRod(at: targetCoord)
                return
            }
            if hitType == .portal { selectDimension(activeDimension.nextDimension); return }
            if hitType == .obsidian && tryIgniteObsidianFrame(around: targetCoord) { return }
            if hitType == .crop {
                let stage = cropStages[targetCoord] ?? 0
                if stage >= 3 {
                    cropStages[targetCoord] = 0
                    blockNodes[targetCoord]?.scale = SCNVector3(1.0, 0.45, 1.0)
                    let yieldCount = stage >= 3 ? 3 : 1
                    foodInventory[.wheat, default: 0] += yieldCount
                    foodInventory[.seeds, default: 0] += Int.random(in: 1...2)
                    saveWorld()
                    SoundEngine.shared.play(.pickup)
                    statusMessage = "Harvested Wheat (+\(yieldCount) Wheat and Seeds)"
                } else {
                    statusMessage = "Crop growing (stage \(stage)/3)"
                }
                return
            }
            if hitType == .button {
                activeButtons[targetCoord] = ProcessInfo.processInfo.systemUptime + 1.5
                recalculateRedstoneCircuits(around: targetCoord)
                statusMessage = "Button pressed — signal active"
                saveWorld()
                return
            }
            if hitType == .lever {
                if activeLevers.contains(targetCoord) {
                    activeLevers.remove(targetCoord)
                    blockNodes[targetCoord]?.eulerAngles.z = 0
                    recalculateRedstoneCircuits(around: targetCoord)
                    statusMessage = "Lever OFF — depowered circuit"
                } else {
                    activeLevers.insert(targetCoord)
                    blockNodes[targetCoord]?.eulerAngles.z = .pi / 4
                    SoundEngine.shared.play(.piston)
                    recalculateRedstoneCircuits(around: targetCoord)
                    statusMessage = "Lever ON — powered redstone & pistons"
                }
                saveWorld()
                return
            }
            if hitType == .bed && activeTool == .place {
                customSpawnCoord = targetCoord
                if isNightMode {
                    let unsafeHostiles = mobs.contains { mob in
                        let hostile = [.zombie, .skeleton, .creeper, .spider, .blaze, .enderman, .slime].contains(mob.kind)
                        guard hostile else { return false }
                        let dx = mob.position.x - Float(targetCoord.x)
                        let dz = mob.position.z - Float(targetCoord.z)
                        return dx * dx + dz * dz < 64
                    }
                    guard !unsafeHostiles else {
                        statusMessage = "You cannot sleep while hostile mobs are nearby"
                        saveWorld()
                        return
                    }
                    isNightMode = false
                    dayClockTimer = 0
                    health = min(20, health + 4)
                    hunger = min(20, hunger + 2)
                    oxygen = 10
                    stamina = 100
                    statusMessage = "Slept until morning · spawn saved · rested"
                } else {
                    statusMessage = "Respawn point saved at Bed"
                }
                saveWorld()
                SoundEngine.shared.play(.place)
                return
            }
            if hitType == .furnace && activeTool == .place {
                showCraftSheet = true
                statusMessage = "Opened Furnace & Crafting"
                return
            }
            if hitType == .chest {
                openChest(at: targetCoord)
                SoundEngine.shared.play(.place)
                return
            }
            if hitType == .door && activeTool == .place {
                if openDoors.contains(targetCoord) {
                    openDoors.remove(targetCoord)
                    redstoneToggledDoors.remove(targetCoord)
                    blockNodes[targetCoord]?.eulerAngles.y = 0
                    statusMessage = "Closed Door"
                } else {
                    openDoors.insert(targetCoord)
                    blockNodes[targetCoord]?.eulerAngles.y = .pi / 2
                    statusMessage = "Opened Door"
                }
                saveWorld()
                haptic.impactOccurred()
                return
            }
            if hitType == .tnt && activeTool == .place {
                detonateTNT(at: targetCoord)
                return
            }
        }

        switch activeTool {
        case .breakBlock:
            if targetCoord.y > 0, let removedType = blocks[targetCoord] {
                if removedType == .bedrock || !removedType.miningHardness.isFinite {
                    statusMessage = "This block cannot be mined"
                    miningProgress = 0
                    miningTarget = nil
                    return
                }
                if gameMode == .survival {
                    let requiresIronPickaxe: Set<BlockType> = [.ironOre, .goldOre, .diamondOre, .emeraldOre, .redstoneOre]
                    let requiresDiamondPickaxe: Set<BlockType> = [.obsidian]
                    if (requiresIronPickaxe.contains(removedType) || requiresDiamondPickaxe.contains(removedType)) && selectedTool != .pickaxe {
                        statusMessage = "Requires a pickaxe to harvest \(removedType.rawValue)"
                        miningProgress = 0; miningTarget = nil
                        return
                    }
                    if requiresIronPickaxe.contains(removedType) && toolTier == .wood {
                        statusMessage = "Requires an Iron-tier or better pickaxe"
                        miningProgress = 0; miningTarget = nil
                        return
                    }
                    if requiresDiamondPickaxe.contains(removedType) && toolTier != .diamond {
                        statusMessage = "Requires a Diamond pickaxe"
                        miningProgress = 0; miningTarget = nil
                        return
                    }
                }
                if miningTarget != targetCoord {
                    miningTarget = targetCoord
                    miningProgress = 0
                }
                if gameMode == .creative {
                    miningProgress = 1
                } else {
                    miningProgress = min(1, miningProgress + miningPower(for: removedType) * 0.34)
                }
                if miningProgress < 1 {
                    statusMessage = "Mining \(removedType.rawValue): \(Int(miningProgress * 100))%"
                    SoundEngine.shared.play(.mine)
                    return
                }
                spawnBreakParticles(at: targetCoord, color: removedType.particleColor)
                removeBlockInternal(coord: targetCoord)
                spawnDroppedItem(type: removedType, at: targetCoord)
                let oreXP: Int
                switch removedType {
                case .coalOre: oreXP = 2
                case .redstoneOre, .quartzOre: oreXP = 3
                case .diamondOre, .emeraldOre: oreXP = 5
                default: oreXP = 0
                }
                if oreXP > 0 { awardExperience(oreXP, at: SIMD3<Float>(Float(targetCoord.x) + 0.5, Float(targetCoord.y) + 0.5, Float(targetCoord.z) + 0.5)) }
                if removedType == .wood || removedType == .spruceLog || removedType == .birchLog {
                    decayNearbyLeaves(around: targetCoord)
                }
                damageTool()
                placedOrMinedCount += 1
                miningProgress = 0
                miningTarget = nil
                saveWorld()
                broadcastBlockEdit(coord: targetCoord, type: nil)
                SoundEngine.shared.play(.mine)
                haptic.impactOccurred()
                statusMessage = "Mined \(removedType.rawValue) • Tool: \(toolDurability)/\(toolTier.maxDurability)"
            } else {
                statusMessage = "Cannot break bedrock"
                miningProgress = 0
                miningTarget = nil
            }

        case .place:
            let stock = count(for: selectedBlock)
            if gameMode == .survival && stock <= 0 {
                statusMessage = "Out of \(selectedBlock.rawValue) — craft or mine more"
                return
            }

            let normal = hit.worldNormal
            let placeCoord = BlockCoord(
                x: targetCoord.x + Int(round(normal.x)),
                y: targetCoord.y + Int(round(normal.y)),
                z: targetCoord.z + Int(round(normal.z))
            )

            let playerFeetCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 1.5)), z: Int(floor(playerPos.z)))
            let playerHeadCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 0.3)), z: Int(floor(playerPos.z)))

            if !selectedBlock.isPassable && (placeCoord == playerFeetCoord || placeCoord == playerHeadCoord) {
                statusMessage = "Step back slightly to place block there"
                return
            }

            if blocks[placeCoord] == nil {
                setBlockInternal(coord: placeCoord, type: selectedBlock, markModified: true)
                if selectedBlock == .crop { cropStages[placeCoord] = 0 }
                if gameMode == .survival {
                    inventory[selectedBlock] = max(0, stock - 1)
                }
                placedOrMinedCount += 1
                saveWorld()
                broadcastBlockEdit(coord: placeCoord, type: selectedBlock)
                SoundEngine.shared.play(.place)
                haptic.impactOccurred()
                statusMessage = "Placed \(selectedBlock.rawValue)"

                if [.redstoneDust, .repeater, .redstoneLamp, .pressurePlate, .button, .lever, .piston, .door].contains(selectedBlock) {
                    recalculateRedstoneCircuits(around: placeCoord)
                }
            }
        }
    }

    func performCrosshairAction() {
        guard let view = activeSceneView else {
            statusMessage = "Game view is still loading"
            return
        }
        let point = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        handleTap(at: point, in: view)
    }

    private func tryIgniteObsidianFrame(around coord: BlockCoord) -> Bool {
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let cand = BlockCoord(x: coord.x + dx, y: coord.y + dy, z: coord.z + dz)
                    if blocks[cand] == nil && cand.y > 0 {
                        let touchesObsidian = [
                            BlockCoord(x: cand.x + 1, y: cand.y, z: cand.z), BlockCoord(x: cand.x - 1, y: cand.y, z: cand.z),
                            BlockCoord(x: cand.x, y: cand.y + 1, z: cand.z), BlockCoord(x: cand.x, y: cand.y - 1, z: cand.z),
                            BlockCoord(x: cand.x, y: cand.y, z: cand.z + 1), BlockCoord(x: cand.x, y: cand.y, z: cand.z - 1)
                        ].contains { blocks[$0] == .obsidian }

                        if touchesObsidian {
                            setBlockInternal(coord: cand, type: .portal, markModified: true)
                            saveWorld()
                            broadcastBlockEdit(coord: cand, type: .portal)
                            SoundEngine.shared.play(.portal)
                            statusMessage = "Ignited Obsidian Portal!"
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    private func poweredCoordsFromActiveLevers() -> Set<BlockCoord> {
        var powered: Set<BlockCoord> = []
        let dirs = [
            BlockCoord(x: 1, y: 0, z: 0), BlockCoord(x: -1, y: 0, z: 0),
            BlockCoord(x: 0, y: 1, z: 0), BlockCoord(x: 0, y: -1, z: 0),
            BlockCoord(x: 0, y: 0, z: 1), BlockCoord(x: 0, y: 0, z: -1)
        ]
        for lever in activeLevers.union(activePressurePlates).union(Set(activeButtons.keys)) {
            powered.insert(lever)
            var queue: [BlockCoord] = [lever]
            while !queue.isEmpty {
                let cur = queue.removeFirst()
                for off in dirs {
                    let nb = BlockCoord(x: cur.x + off.x, y: cur.y + off.y, z: cur.z + off.z)
                    if powered.contains(nb) { continue }
                    if let t = blocks[nb] {
                        powered.insert(nb)
                        if (t == .redstoneDust || t == .repeater) && powered.count < 48 {
                            queue.append(nb)
                        }
                    }
                }
            }
        }
        return powered
    }

    private func updateRedstoneSensors(at time: TimeInterval) {
        var nextPressed: Set<BlockCoord> = []
        for (coord, type) in blocks where type == .pressurePlate {
            let center = SIMD3<Float>(Float(coord.x) + 0.5, Float(coord.y), Float(coord.z) + 0.5)
            let playerOnPlate = abs(playerPos.y - center.y) < 2.0 &&
                abs(playerPos.x - center.x) < 0.72 && abs(playerPos.z - center.z) < 0.72
            let mobOnPlate = mobs.contains { mob in
                abs(mob.position.y - center.y) < 1.5 &&
                abs(mob.position.x - center.x) < 0.72 && abs(mob.position.z - center.z) < 0.72
            }
            if playerOnPlate || mobOnPlate { nextPressed.insert(coord) }
        }
        let expired = activeButtons.filter { $0.value <= time }.map(\.key)
        for coord in expired { activeButtons.removeValue(forKey: coord) }
        if nextPressed != activePressurePlates || !expired.isEmpty {
            let changed = activePressurePlates.symmetricDifference(nextPressed)
            activePressurePlates = nextPressed
            for coord in changed {
                blockNodes[coord]?.scale = nextPressed.contains(coord)
                    ? SCNVector3(1.0, 0.55, 1.0)
                    : SCNVector3(1.0, 1.0, 1.0)
            }
            recalculateRedstoneCircuits(around: nextPressed.first ?? BlockCoord(x: 0, y: 0, z: 0))
        }
    }

    private func recalculateRedstoneCircuits(around origin: BlockCoord) {
        let powered = poweredCoordsFromActiveLevers()
        poweredRedstoneLamps.removeAll()
        for (coord, type) in blocks where type == .redstoneLamp {
            blockNodes[coord]?.childNodes.filter { $0.name == "powered_lamp_glow" }.forEach { $0.removeFromParentNode() }
        }

        for doorCoord in Array(redstoneToggledDoors) {
            let touchesPower = [
                BlockCoord(x: doorCoord.x + 1, y: doorCoord.y, z: doorCoord.z), BlockCoord(x: doorCoord.x - 1, y: doorCoord.y, z: doorCoord.z),
                BlockCoord(x: doorCoord.x, y: doorCoord.y + 1, z: doorCoord.z), BlockCoord(x: doorCoord.x, y: doorCoord.y - 1, z: doorCoord.z),
                BlockCoord(x: doorCoord.x, y: doorCoord.y, z: doorCoord.z + 1), BlockCoord(x: doorCoord.x, y: doorCoord.y, z: doorCoord.z - 1)
            ].contains { powered.contains($0) }
            if !touchesPower {
                redstoneToggledDoors.remove(doorCoord)
                openDoors.remove(doorCoord)
                blockNodes[doorCoord]?.eulerAngles.y = 0
            }
        }

        let dirs = [(1, 0, 0), (-1, 0, 0), (0, 0, 1), (0, 0, -1)]
        for pCoord in Array(extendedPistons) {
            let pPowered = [
                BlockCoord(x: pCoord.x + 1, y: pCoord.y, z: pCoord.z), BlockCoord(x: pCoord.x - 1, y: pCoord.y, z: pCoord.z),
                BlockCoord(x: pCoord.x, y: pCoord.y, z: pCoord.z + 1), BlockCoord(x: pCoord.x, y: pCoord.y, z: pCoord.z - 1)
            ].contains { powered.contains($0) }
            if !pPowered {
                extendedPistons.remove(pCoord)
                for (dx, dy, dz) in dirs {
                    let front = BlockCoord(x: pCoord.x + dx, y: pCoord.y + dy, z: pCoord.z + dz)
                    if blocks[front] == nil {
                        for step in 2...4 {
                            let src = BlockCoord(x: pCoord.x + dx * step, y: pCoord.y + dy * step, z: pCoord.z + dz * step)
                            let dst = BlockCoord(x: pCoord.x + dx * (step - 1), y: pCoord.y + dy * (step - 1), z: pCoord.z + dz * (step - 1))
                            if let m = blocks[src], blocks[dst] == nil {
                                removeBlockInternal(coord: src)
                                setBlockInternal(coord: dst, type: m, markModified: true)
                            }
                        }
                    }
                }
            }
        }

        for pCoord in powered {
            for (dx, dy, dz) in [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)] {
                let nb = BlockCoord(x: pCoord.x + dx, y: pCoord.y + dy, z: pCoord.z + dz)
                guard let nbType = blocks[nb] else { continue }
                if nbType == .redstoneLamp {
                    poweredRedstoneLamps.insert(nb)
                    if let node = blockNodes[nb] {
                        node.childNodes.filter { $0.name == "powered_lamp_glow" }.forEach { $0.removeFromParentNode() }
                        let glow = SCNNode()
                        glow.name = "powered_lamp_glow"
                        let light = SCNLight(); light.type = .omni; light.intensity = 520
                        light.attenuationEndDistance = 7
                        light.color = UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1)
                        glow.light = light; node.addChildNode(glow)
                    }
                } else if nbType == .tnt {
                    detonateTNT(at: nb)
                    return
                } else if nbType == .door && !openDoors.contains(nb) {
                    openDoors.insert(nb)
                    redstoneToggledDoors.insert(nb)
                    blockNodes[nb]?.eulerAngles.y = .pi / 2
                } else if nbType == .piston && !extendedPistons.contains(nb) {
                    pushChain(from: nb, dx: dx, dy: dy, dz: dz)
                }
            }
        }
        _ = origin
    }

    private func pushChain(from pistonCoord: BlockCoord, dx: Int, dy: Int, dz: Int) {
        let maxPush = 4
        var chain: [(BlockCoord, BlockType)] = []
        for step in 1...maxPush {
            let c = BlockCoord(x: pistonCoord.x + dx * step, y: pistonCoord.y + dy * step, z: pistonCoord.z + dz * step)
            guard let t = blocks[c] else { break }
            if t == .bedrock || t == .obsidian { return }
            chain.append((c, t))
        }
        guard !chain.isEmpty else { return }
        let last = chain.last!.0
        let dest = BlockCoord(x: last.x + dx, y: last.y + dy, z: last.z + dz)
        guard blocks[dest] == nil else { return }

        for (c, t) in chain.reversed() {
            let target = BlockCoord(x: c.x + dx, y: c.y + dy, z: c.z + dz)
            removeBlockInternal(coord: c)
            setBlockInternal(coord: target, type: t, markModified: true)
        }
        extendedPistons.insert(pistonCoord)
        SoundEngine.shared.play(.piston)
    }

    private func detonateTNT(at center: BlockCoord) {
        SoundEngine.shared.play(.explode)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let target = BlockCoord(x: center.x + dx, y: center.y + dy, z: center.z + dz)
                    if target.y > 0, let existing = blocks[target], existing != .bedrock {
                        spawnBreakParticles(at: target, color: existing.particleColor)
                        removeBlockInternal(coord: target)
                        broadcastBlockEdit(coord: target, type: nil)
                    }
                }
            }
        }
        saveWorld()
        statusMessage = "TNT exploded!"
    }
}

// MARK: - SceneKit View Bridge

struct VoxelSceneView: UIViewRepresentable {
    @ObservedObject var controller: VoxelWorldController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        controller.activeSceneView = view
        view.pointOfView = controller.cameraNode
        view.delegate = controller
        view.isPlaying = true
        view.loops = true
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = UIColor(red: 0.53, green: 0.78, blue: 0.98, alpha: 1.0)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)

        context.coordinator.scnView = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.pointOfView = controller.cameraNode
    }

    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        uiView.delegate = nil
        if coordinator.controller.activeSceneView === uiView {
            coordinator.controller.activeSceneView = nil
        }
    }

    final class Coordinator: NSObject {
        let controller: VoxelWorldController
        weak var scnView: SCNView?
        private var lastPanPoint: CGPoint?

        init(controller: VoxelWorldController) { self.controller = controller }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let loc = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began: lastPanPoint = loc
            case .changed:
                if let prev = lastPanPoint {
                    controller.lookDelta(deltaX: Float(loc.x - prev.x), deltaY: Float(loc.y - prev.y))
                }
                lastPanPoint = loc
            default: lastPanPoint = nil
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            controller.handleTap(at: gesture.location(in: view), in: view)
        }
    }
}

// MARK: - Inventory & Equipment

enum ChestTransferChoice: CaseIterable, Hashable {
    case one, half, all
    var title: String {
        switch self { case .one: return "1"; case .half: return "½"; case .all: return "All" }
    }
}

struct ChestItemStack: Identifiable {
    let type: BlockType
    let count: Int
    var id: String { type.rawValue }
}

struct ChestStorageSheetView: View {
    @ObservedObject var world: VoxelWorldController
    let chestKey: String
    @Environment(\.dismiss) private var dismiss

    private var playerItems: [ChestItemStack] {
        BlockType.allCases.compactMap { type in
            let amount = world.count(for: type)
            return amount > 0 ? ChestItemStack(type: type, count: amount) : nil
        }.sorted { $0.type.rawValue < $1.type.rawValue }
    }

    private var storedItems: [ChestItemStack] {
        world.chestItems(for: chestKey).map { ChestItemStack(type: $0.0, count: $0.1) }
    }
    private var usedSlots: Int { storedItems.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Storage slots")
                        Spacer()
                        Text("\(usedSlots) / 27").font(.system(.body, design: .monospaced).bold())
                    }
                }
                Section("Chest contents") {
                    Text("Drop an inventory stack here to deposit it")
                        .font(.caption).foregroundStyle(.secondary)
                        .dropDestination(for: String.self) { payloads, _ in
                            handleDrop(payloads, intoChest: true)
                        }
                    if storedItems.isEmpty {
                        Text("This chest is empty.").foregroundStyle(.secondary)
                    }
                    ForEach(storedItems) { item in
                        HStack(spacing: 8) {
                            Image(uiImage: item.type.previewImage).interpolation(.none).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.type.rawValue)
                                Text("\(item.count) / 64").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            transferButtons(type: item.type, count: item.count, toChest: false)
                        }
                        .draggable("chest:\(item.type.rawValue)")
                    }
                }
                Section("Your inventory") {
                    Text("Drop a chest stack here to withdraw it")
                        .font(.caption).foregroundStyle(.secondary)
                        .dropDestination(for: String.self) { payloads, _ in
                            handleDrop(payloads, intoChest: false)
                        }
                    if playerItems.isEmpty {
                        Text("Your inventory is empty.").foregroundStyle(.secondary)
                    }
                    ForEach(playerItems) { item in
                        HStack(spacing: 8) {
                            Image(uiImage: item.type.previewImage).interpolation(.none).resizable().frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.type.rawValue)
                                Text("\(item.count) / 64").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            transferButtons(type: item.type, count: item.count, toChest: true)
                        }
                        .draggable("player:\(item.type.rawValue)")
                    }
                }
            }
            .navigationTitle("Chest")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func handleDrop(_ payloads: [String], intoChest: Bool) -> Bool {
        guard let payload = payloads.first else { return false }
        let parts = payload.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let type = BlockType(rawValue: parts[1]) else { return false }
        if intoChest, parts[0] == "player" {
            world.transferToChest(type, amount: world.count(for: type), chestKey: chestKey)
            return true
        }
        if !intoChest, parts[0] == "chest" {
            let amount = world.chestItems(for: chestKey).first(where: { $0.0 == type })?.1 ?? 0
            world.transferFromChest(type, amount: amount, chestKey: chestKey)
            return true
        }
        return false
    }

    @ViewBuilder
    private func transferButtons(type: BlockType, count: Int, toChest: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(ChestTransferChoice.allCases, id: \.self) { choice in
                Button(choice.title) {
                    let amount = world.transferAmount(for: count, choice: choice)
                    if toChest { world.transferToChest(type, amount: amount, chestKey: chestKey) }
                    else { world.transferFromChest(type, amount: amount, chestKey: chestKey) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

struct BrewingSheetView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Brewing stand") {
                    Text("Combine rare materials to brew useful survival potions. Healing is instant; other effects last for a limited time.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Recipes") {
                    ForEach(PotionKind.allCases) { potion in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(potion.rawValue, systemImage: potion.symbol).font(.headline)
                                Spacer()
                                Text("Owned: \(world.potionCount(for: potion))").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(potion.ingredients.map { "\($0.0.rawValue) ×\($0.1)  (have \(world.count(for: $0.0)))" }.joined(separator: "  •  "))
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Brew Potion") { world.brewPotion(potion) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!world.canBrew(potion) || world.potionCount(for: potion) >= 64)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Brewing")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct InventorySheetView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    private var sortedBlocks: [BlockType] {
        BlockType.allCases.filter { world.count(for: $0) > 0 }.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Experience") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Level \(world.experienceLevel)").font(.headline)
                            Spacer()
                            Text("\(world.experiencePoints) XP").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ProgressView(value: world.experienceProgress)
                        Text("Collect glowing XP orbs from ore and defeated mobs.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { world.showEnchantingSheet = true } label: {
                        Label("Open Enchanting Table", systemImage: "sparkles")
                    }
                }

                Section("Game inventory • \(world.gameMode.rawValue)") {
                    if sortedBlocks.isEmpty {
                        Text("No blocks in your inventory yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedBlocks) { block in
                            HStack(spacing: 10) {
                                Image(uiImage: block.previewImage)
                                    .interpolation(.none).resizable().frame(width: 30, height: 30)
                                Text(block.rawValue)
                                Spacer()
                                Text("×\(world.count(for: block))")
                                    .font(.system(.body, design: .monospaced).bold())
                            }
                        }
                    }
                }

                Section("Food") {
                    ForEach(FoodKind.allCases) { food in
                        HStack {
                            Text(food.rawValue)
                            Spacer()
                            Text("×\(world.foodCount(for: food))")
                                .font(.system(.body, design: .monospaced).bold())
                        }
                    }
                }

                Section("Potions & active effects") {
                    ForEach(PotionKind.allCases) { potion in
                        HStack(spacing: 10) {
                            Image(systemName: potion.symbol).foregroundStyle(.purple).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(potion.rawValue)
                                if let remaining = world.activePotionEffects[potion], remaining > 0 {
                                    Text("Active · \(Int(remaining))s remaining").font(.caption).foregroundStyle(.green)
                                }
                            }
                            Spacer()
                            Text("×\(world.potionCount(for: potion))").font(.system(.body, design: .monospaced).bold())
                            Button("Drink") { world.drinkPotion(potion) }
                                .buttonStyle(.borderedProminent)
                                .disabled(world.potionCount(for: potion) == 0)
                        }
                    }
                    LabeledContent("Shield", value: world.isShieldRaised ? "Raised" : "Lowered")
                }

                Section("Achievements · \(world.unlockedAchievements.count)/\(AchievementInfo.all.count)") {
                    ForEach(AchievementInfo.all) { achievement in
                        HStack(spacing: 10) {
                            Image(systemName: achievement.symbol)
                                .foregroundStyle(world.unlockedAchievements.contains(achievement.id) ? .yellow : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(achievement.title).font(.subheadline.bold())
                                Text(achievement.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: world.unlockedAchievements.contains(achievement.id) ? "checkmark.seal.fill" : "lock.fill")
                                .foregroundStyle(world.unlockedAchievements.contains(achievement.id) ? .green : .secondary)
                        }
                    }
                }

                Section("Crafted equipment in bag") {
                    let owned = EquipmentCraftCatalog.all.filter { world.equipmentCount(for: $0) > 0 }
                    if owned.isEmpty {
                        Text("No spare equipment. Craft tools or armour below.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(owned) { recipe in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.title).font(.subheadline.bold())
                                    Text("Stack: \(world.equipmentCount(for: recipe))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Equip") { world.equipCraftedEquipment(recipe) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                Section("Craft tools & armour") {
                    ForEach(EquipmentCraftCatalog.all) { recipe in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recipe.title).font(.subheadline.bold())
                                Text(recipe.ingredients.map { "\($0.0.rawValue) ×\($0.1) (have \(world.count(for: $0.0)))" }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Owned: \(world.equipmentCount(for: recipe))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Button("Craft") { world.craftEquipment(recipe) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!world.canCraftEquipment(recipe))
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Currently equipped") {
                    LabeledContent("Tool", value: "\(world.toolTier.rawValue) \(world.selectedTool.rawValue) · \(world.toolDurability)/\(world.toolTier.maxDurability)")
                    LabeledContent("Helmet", value: "\(world.helmetTier.rawValue) · \(world.helmetDurability)")
                    LabeledContent("Chestplate", value: "\(world.chestplateTier.rawValue) · \(world.chestplateDurability)")
                    LabeledContent("Leggings", value: "\(world.leggingsTier.rawValue) · \(world.leggingsDurability)")
                    LabeledContent("Boots", value: "\(world.bootsTier.rawValue) · \(world.bootsDurability)")
                    LabeledContent("Armour protection", value: "\(world.effectiveArmorReduction)")
                }
            }
            .navigationTitle("Inventory")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct EnchantingSheetView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Your experience") {
                    LabeledContent("Level", value: "\(world.experienceLevel)")
                    LabeledContent("Total XP", value: "\(world.experiencePoints)")
                }
                Section("Available enchantments") {
                    ForEach(EnchantmentKind.allCases) { kind in
                        let level = world.enchantmentLevel(kind)
                        let cost = world.enchantmentCost(kind)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(kind.rawValue) \(level > 0 ? "\(level)" : "I")").font(.headline)
                                Spacer()
                                Text("Next cost: \(cost) levels").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(kind.description).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("Max level III").font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Button(level >= kind.maximumLevel ? "MAXED" : "Enchant") {
                                    world.applyEnchantment(kind)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!world.canEnchant(kind))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section("Active enchantments") {
                    let active = EnchantmentKind.allCases.filter { world.enchantmentLevel($0) > 0 }
                    if active.isEmpty {
                        Text("No enchantments yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(active) { kind in
                            LabeledContent(kind.rawValue, value: "Level \(world.enchantmentLevel(kind))")
                        }
                    }
                }
            }
            .navigationTitle("Enchanting Table")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Crafting, Smelting & Food Sheet

struct CraftingSheetView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Furnace Smelt Queue") {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Queued: \(world.queuedSmeltCount)  •  Burn: \(String(format: "%.1fs", world.furnaceBurnRemaining))")
                                .font(.subheadline.bold())
                            ProgressView(value: world.furnaceSmeltProgress)
                        }
                        Spacer()
                        Button("Queue Smelt") {
                            world.queueFurnaceSmelt()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Section("Food Pouch & Farming") {
                    ForEach(FoodKind.allCases) { food in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(food.rawValue) ×\(world.foodCount(for: food))")
                                    .font(.subheadline.bold())
                                Text(food.isEdible ? "Restores +\(food.hungerRestore) Food, +\(food.healthRestore) HP" : (food.cookingResult == nil ? "Farming and breeding ingredient" : "Raw food • cook with CoalOre"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if food.isEdible {
                                Button("Eat") { world.eatFood(food) }
                                    .buttonStyle(.bordered)
                                    .disabled(world.foodCount(for: food) <= 0)
                            } else if food.cookingResult != nil {
                                Button("Cook") { world.cookFood(food) }
                                    .buttonStyle(.bordered)
                                    .disabled(world.foodCount(for: food) <= 0 || world.count(for: .coalOre) <= 0)
                            }
                        }
                    }
                    Button("Bake Bread (3 Wheat)") { world.bakeBread() }
                        .disabled(world.foodCount(for: .wheat) < 3)
                }

                Section("Craft, Smelt & Cook") {
                    ForEach(CraftCatalog.all) { recipe in
                        let craftable = world.canCraft(recipe)
                        HStack {
                            Image(uiImage: recipe.output.previewImage)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 34, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.title)
                                    .font(.subheadline.bold())
                                Text(recipe.ingredients.map { "\($0.0.rawValue) ×\($0.1) (have \(world.count(for: $0.0)))" }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button("Craft") { world.craft(recipe) }
                                .buttonStyle(.borderedProminent)
                                .disabled(!craftable)
                        }
                    }
                }
            }
            .navigationTitle("Craft, Smelt & Food")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct VillagerTradeSheetView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let villager = world.activeVillagerID.flatMap({ world.villager(for: $0) }) {
                    Image(systemName: villager.profession.symbol)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("\(villager.profession.rawValue) Villager")
                        .font(.title2.bold())
                    Text("Choose this villager's available trade.")
                        .foregroundStyle(.secondary)
                    let trade = world.villagerTradeDescription(for: villager.profession)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You give: \(trade.cost)", systemImage: "arrow.up.circle")
                        Label("You receive: \(trade.reward)", systemImage: "arrow.down.circle")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    Button {
                        world.completeVillagerTrade()
                    } label: {
                        Label("Complete Trade", systemImage: "arrow.left.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                        Text("Villager unavailable").font(.headline)
                        Text("The villager may have moved or left the loaded area.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("Villager Trading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Main Menu, Settings & Help

struct MinervaMainMenuView: View {
    @ObservedObject var world: VoxelWorldController
    let onPlay: () -> Void
    let onSettings: () -> Void
    let onHowToPlay: () -> Void

    @State private var showNewWorldConfirmation = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.09, blue: 0.13), Color(red: 0.06, green: 0.19, blue: 0.17), Color(red: 0.025, green: 0.055, blue: 0.09)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle block-like background decoration
            GeometryReader { proxy in
                ZStack {
                    ForEach(0..<18, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(index.isMultiple(of: 2) ? Color.green.opacity(0.10) : Color.white.opacity(0.045))
                            .frame(width: CGFloat(38 + (index % 4) * 16), height: CGFloat(38 + (index % 4) * 16))
                            .rotationEffect(.degrees(Double(index * 11)))
                            .position(
                                x: CGFloat((index * 83 + 31) % max(Int(proxy.size.width), 1)),
                                y: CGFloat((index * 57 + 19) % max(Int(proxy.size.height), 1))
                            )
                    }
                }
            }
            .allowsHitTesting(false)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 7) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(LinearGradient(colors: [.green.opacity(0.95), .green.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 76, height: 76)
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 38, weight: .black))
                                .foregroundStyle(.white)
                        }
                        Text("MINERVA")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(.white)
                        Text("BUILD • EXPLORE • SURVIVE")
                            .font(.caption2.weight(.bold))
                            .tracking(2.2)
                            .foregroundStyle(.green.opacity(0.9))
                    }
                    .padding(.top, 22)

                    VStack(spacing: 10) {
                        Button(action: onPlay) {
                            Label("PLAY", systemImage: "play.fill")
                                .font(.headline.weight(.black))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                        }
                        .buttonStyle(MinervaMenuButtonStyle(tint: .green))

                        HStack(spacing: 10) {
                            Button {
                                world.selectWorldSlot(world.activeSlot)
                                onPlay()
                            } label: {
                                Label("CONTINUE", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(MinervaMenuButtonStyle(tint: .blue))

                            Button { showNewWorldConfirmation = true } label: {
                                Label("NEW WORLD", systemImage: "plus.square.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                            }
                            .buttonStyle(MinervaMenuButtonStyle(tint: .orange))
                        }
                    }
                    .padding(.horizontal, 22)

                    VStack(alignment: .leading, spacing: 11) {
                        Text("WORLD SELECT")
                            .font(.caption.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.72))
                        HStack(spacing: 9) {
                            ForEach(1...3, id: \.self) { slot in
                                Button {
                                    world.selectWorldSlot(slot)
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: world.activeSlot == slot ? "checkmark.circle.fill" : "globe")
                                            .font(.title3)
                                        Text("WORLD \(slot)")
                                            .font(.caption2.bold())
                                    }
                                    .foregroundStyle(world.activeSlot == slot ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(world.activeSlot == slot ? Color.yellow : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.14), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 22)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("GAME MODE")
                            .font(.caption.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.72))
                        HStack(spacing: 10) {
                            ForEach(GameMode.allCases, id: \.self) { mode in
                                Button { world.setGameMode(mode) } label: {
                                    Label(mode.rawValue, systemImage: mode == .creative ? "hammer.fill" : "heart.fill")
                                        .font(.subheadline.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .foregroundStyle(world.gameMode == mode ? .black : .white)
                                        .background(world.gameMode == mode ? Color.yellow : Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Text("Dimension: \(world.activeDimension.rawValue)  ·  Slot: \(world.activeSlot)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.horizontal, 22)

                    VStack(spacing: 10) {
                        Button {
                            world.toggleMultiplayerLobby()
                        } label: {
                            Label(world.multiplayerEnabled ? "MULTIPLAYER: SEARCHING" : "MULTIPLAYER / LAN", systemImage: "person.2.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(MinervaMenuButtonStyle(tint: .purple))

                        HStack(spacing: 10) {
                            Button(action: onSettings) {
                                Label("SETTINGS", systemImage: "gearshape.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(MinervaMenuButtonStyle(tint: .gray))

                            Button(action: onHowToPlay) {
                                Label("HOW TO PLAY", systemImage: "questionmark.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(MinervaMenuButtonStyle(tint: .gray))
                        }
                    }
                    .padding(.horizontal, 22)

                    Text("MINERVA  •  VOXEL SANDBOX")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Create a new world?", isPresented: $showNewWorldConfirmation, titleVisibility: .visible) {
            Button("Generate New World", role: .destructive) {
                world.regenerateNewWorld()
                onPlay()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This regenerates the currently selected world slot and dimension.")
        }
    }
}

struct MinervaMenuButtonStyle: ButtonStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.heavy))
            .foregroundStyle(.white)
            .background(tint.opacity(configuration.isPressed ? 0.55 : 0.78), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct MinervaSettingsView: View {
    @ObservedObject var world: VoxelWorldController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmWorldReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Gameplay") {
                    Picker("Game mode", selection: Binding(get: { world.gameMode }, set: { world.setGameMode($0) })) {
                        ForEach(GameMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Picker("Dimension", selection: Binding(get: { world.activeDimension }, set: { world.selectDimension($0) })) {
                        ForEach(GameDimension.allCases) { dimension in Text(dimension.rawValue).tag(dimension) }
                    }
                    Picker("World slot", selection: Binding(get: { world.activeSlot }, set: { world.selectWorldSlot($0) })) {
                        ForEach(1...3, id: \.self) { slot in Text("World \(slot)").tag(slot) }
                    }
                }
                Section("World") {
                    Toggle("Automatic day / night cycle", isOn: Binding(get: { world.isAutoCycleEnabled }, set: { _ in world.toggleAutoCycle() }))
                    Toggle("Multiplayer LAN", isOn: Binding(get: { world.multiplayerEnabled }, set: { _ in world.toggleMultiplayerLobby() }))
                    Button("Regenerate current world", role: .destructive) { confirmWorldReset = true }
                }
                Section("Camera") {
                    Button("Switch camera perspective") { world.toggleCameraMode() }
                    Text("Current: \(world.cameraMode.rawValue)").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Regenerate this world?", isPresented: $confirmWorldReset, titleVisibility: .visible) {
                Button("Regenerate World", role: .destructive) { world.regenerateNewWorld() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The current world and its saved changes in this dimension will be replaced.")
            }
        }
    }
}

struct MinervaHowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Movement") {
                    Label("Use the on-screen directional controls to move.", systemImage: "arrow.up.left.and.arrow.down.right")
                    Label("Use JUMP to jump and the camera control to change perspective.", systemImage: "arrow.up.circle")
                }
                Section("Building") {
                    Label("Choose a block from the inventory strip or hotbar.", systemImage: "square.grid.3x3.fill")
                    Label("Aim at a surface, then tap PLACE to build.", systemImage: "plus.square.fill")
                    Label("Aim at a block, then tap BREAK to mine it.", systemImage: "hammer.fill")
                }
                Section("Survival & World") {
                    Label("Manage health, hunger, equipment and resources.", systemImage: "heart.fill")
                    Label("Use the top controls for crafting, inventory, weather, dimensions and world options.", systemImage: "slider.horizontal.3")
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - HUD & Game UI

struct VoxelGameView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var world = VoxelWorldController()
    @State private var isShowingMainMenu = true
    @State private var isShowingSettings = false
    @State private var isShowingHowToPlay = false

    var body: some View {
        Group {
            ZStack {
            if isShowingMainMenu {
                MinervaMainMenuView(
                    world: world,
                    onPlay: {
                        world.resumeGame()
                        isShowingMainMenu = false
                    },
                    onSettings: { isShowingSettings = true },
                    onHowToPlay: { isShowingHowToPlay = true }
                )
            } else {
            VoxelSceneView(controller: world)
                .ignoresSafeArea()

            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.75), radius: 2)
                .allowsHitTesting(false)

            VStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                    Button {
                        world.pauseGame()
                        isShowingMainMenu = true
                    } label: {
                        Image(systemName: "house.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Main menu")

                    Picker("Tool", selection: $world.activeTool) {
                        ForEach(InteractionTool.allCases, id: \.self) { tool in
                            Text(tool.rawValue).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    Button { world.showBrewingSheet = true } label: {
                        Image(systemName: "flask.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.purple)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.showInventorySheet = true } label: {
                        Image(systemName: "backpack.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.showCraftSheet = true } label: {
                        Image(systemName: "hammer.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.yellow)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.isShieldRaised.toggle(); world.statusMessage = world.isShieldRaised ? "Shield raised · incoming damage reduced" : "Shield lowered" } label: {
                        Image(systemName: world.isShieldRaised ? "shield.fill" : "shield")
                            .font(.caption.bold())
                            .foregroundStyle(world.isShieldRaised ? .cyan : .white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button {
                        world.isSprinting.toggle()
                        world.statusMessage = world.isSprinting ? "Sprint enabled" : "Sprint disabled"
                    } label: {
                        Image(systemName: "figure.run")
                            .font(.caption.bold())
                            .foregroundStyle(world.isSprinting ? .green : .white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.eatFood() } label: {
                        Image(systemName: "fork.knife")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.cycleWeather() } label: {
                        Image(systemName: world.weather == .rain ? "cloud.rain.fill" : (world.weather == .snowstorm ? "cloud.snow.fill" : "cloud.sun.fill"))
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.toggleDayNight() } label: {
                        Image(systemName: world.isNightMode ? "moon.stars.fill" : "sun.max.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(world.isNightMode ? .yellow : .orange)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button { world.toggleCameraMode() } label: {
                        Image(systemName: "camera.rotate.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Menu {
                        ForEach(GameDimension.allCases) { dim in
                            Button { world.selectDimension(dim) } label: {
                                if world.activeDimension == dim {
                                    Label(dim.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(dim.rawValue)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                            Text(world.activeDimension.rawValue)
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }

                    Menu {
                        ForEach([1, 2, 3], id: \.self) { slot in
                            Button { world.selectWorldSlot(slot) } label: {
                                if world.activeSlot == slot {
                                    Label("World \(slot)", systemImage: "checkmark")
                                } else {
                                    Text("World \(slot)")
                                }
                            }
                        }
                        Divider()
                        Menu("Game Mode: \(world.gameMode.rawValue)") {
                            ForEach(GameMode.allCases, id: \.self) { mode in
                                Button {
                                    world.setGameMode(mode)
                                } label: {
                                    if world.gameMode == mode { Label(mode.rawValue, systemImage: "checkmark") }
                                    else { Text(mode.rawValue) }
                                }
                            }
                        }
                        Button("Inventory & Equipment…") { world.showInventorySheet = true }
                        Button(world.multiplayerEnabled ? "LAN Multipeer: ON (\(world.connectedPeerCount))" : "LAN Multipeer: OFF") {
                            world.toggleMultiplayerLobby()
                        }
                        Button(world.isAutoCycleEnabled ? "Auto Day/Night: ON" : "Auto Day/Night: OFF") { world.toggleAutoCycle() }
                        Button("Respawn at Spawn") { world.respawnPlayer() }
                        Button("Reset Current Dimension", role: .destructive) { world.regenerateNewWorld() }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "globe.americas.fill")
                            Text("W\(world.activeSlot)")
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.horizontal)
                .padding(.top, 4)

                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Text(world.activeDimension.rawValue.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(world.activeDimension.badgeColor)
                        Text("•").foregroundStyle(.white.opacity(0.6))
                        Text(world.currentBiome.rawValue)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                        Text("•").foregroundStyle(.white.opacity(0.6))
                        Text(world.coordsText)
                            .font(.caption2.monospaced().bold())
                            .foregroundStyle(.yellow)
                    }

                    if let bossHealth = world.bossHealthFraction {
                        VStack(spacing: 3) {
                            Text(world.bossHealthLabel).font(.caption2.bold()).foregroundStyle(.purple)
                            ProgressView(value: bossHealth).tint(.purple).frame(maxWidth: 210)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.black.opacity(0.48), in: Capsule())
                    }

                    if !world.activePotionEffects.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(PotionKind.allCases.filter { (world.activePotionEffects[$0] ?? 0) > 0 }) { effect in
                                Label("\(effect.rawValue) \(Int(world.activePotionEffects[effect] ?? 0))s", systemImage: effect.symbol)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.purple)
                            }
                        }
                    }

                    if world.isUnderwater && world.gameMode == .survival {
                        HStack(spacing: 4) {
                            Image(systemName: "water.waves").foregroundStyle(.cyan)
                            ForEach(0..<10, id: \.self) { index in
                                Image(systemName: index < world.oxygen ? "bubble.left.fill" : "bubble.left")
                                    .font(.caption2)
                                    .foregroundStyle(index < world.oxygen ? .cyan : .white.opacity(0.35))
                            }
                        }
                    }
                    if world.gameMode == .survival {
                        HStack(spacing: 5) {
                            Image(systemName: "figure.run").foregroundStyle(.green)
                            ProgressView(value: world.stamina / 100.0)
                                .tint(.green)
                                .frame(width: 74)
                            Text("\(Int(world.stamina))%")
                                .font(.caption2.monospacedDigit().bold())
                                .foregroundStyle(.green)
                        }
                    }

                    HStack(spacing: 10) {
                        Label("HP \(world.health)/20", systemImage: "heart.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.red)
                        Label("Food \(world.hunger)/20", systemImage: "fork.knife")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                        Label("Lv \(world.experienceLevel)", systemImage: "sparkles")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        ProgressView(value: world.experienceProgress)
                            .tint(.green)
                            .frame(width: 42)
                        Text(world.gameMode.rawValue.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(world.gameMode == .creative ? .cyan : .green)
                        if world.miningFatigueRemaining > 0 {
                            Label("MINING FATIGUE", systemImage: "hourglass")
                                .font(.caption2.bold()).foregroundStyle(.purple)
                        }
                        if world.treasureCompassTarget != nil {
                            Text(world.treasureCompassText)
                                .font(.caption2.bold()).foregroundStyle(.cyan)
                                .lineLimit(1)
                        }
                        Text(world.statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        if world.miningProgress > 0 {
                            ProgressView(value: world.miningProgress)
                                .tint(.yellow)
                                .frame(width: 46)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(spacing: 6) {
                        MoveHoldButton(systemImage: "chevron.up", onPress: { world.setMoveInput(forward: 1, strafe: 0) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                        HStack(spacing: 6) {
                            MoveHoldButton(systemImage: "chevron.left", onPress: { world.setMoveInput(forward: 0, strafe: -1) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                            MoveHoldButton(systemImage: "chevron.down", onPress: { world.setMoveInput(forward: -1, strafe: 0) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                            MoveHoldButton(systemImage: "chevron.right", onPress: { world.setMoveInput(forward: 0, strafe: 1) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                        }
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        Button { world.respawnPlayer() } label: {
                            Text("SPAWN")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                        }

                        Button { world.scanForTreasure() } label: {
                            Label("TREASURE MAP", systemImage: "map.fill")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(.blue.opacity(0.68), in: RoundedRectangle(cornerRadius: 9))
                        }
                        HStack(spacing: 6) {
                            Button { world.craftBoat() } label: {
                                Label("CRAFT", systemImage: "hammer.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 8)
                                    .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 9))
                            }
                            Button { world.toggleBoat() } label: {
                                Label(world.isInBoat ? "EXIT" : (world.boatCount > 0 ? "BOAT \(world.boatCount)" : "BOARD"), systemImage: "sailboat.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 8)
                                    .background(world.isInBoat ? Color.blue.opacity(0.75) : Color.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }

                        HStack(spacing: 7) {
                            Button {
                                world.activeTool = .place
                                world.performCrosshairAction()
                            } label: {
                                Label("PLACE", systemImage: "plus.square.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.green.opacity(0.82), in: RoundedRectangle(cornerRadius: 10))
                            }
                            Button {
                                world.activeTool = .breakBlock
                                world.performCrosshairAction()
                            } label: {
                                Label("BREAK", systemImage: "hammer.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        Button { world.jump() } label: {
                            Text("JUMP")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)

                // Nine-slot quick-access hotbar
                HStack(spacing: 5) {
                    ForEach(0..<9, id: \.self) { index in
                        let block = world.hotbarSlots[index]
                        let selected = world.hotbarSelection == index
                        Button {
                            world.selectHotbarSlot(index)
                        } label: {
                            VStack(spacing: 2) {
                                Image(uiImage: block.previewImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 27, height: 27)
                                Text("\(world.count(for: block))")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(selected ? Color.white.opacity(0.30) : Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.yellow : Color.white.opacity(0.25), lineWidth: selected ? 2 : 1))
                        }
                    }
                }
                .padding(.horizontal, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(BlockCategory.allCases) { cat in
                            let active = world.selectedCategory == cat
                            Button { world.selectedCategory = cat } label: {
                                Text(cat.rawValue)
                                    .font(.caption2.bold())
                                    .foregroundStyle(active ? .black : .white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(active ? Color.yellow : Color.black.opacity(0.5), in: Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(world.visibleBlocks) { block in
                            let selected = world.selectedBlock == block
                            let qty = world.count(for: block)
                            Button {
                                world.selectedBlock = block
                                world.hotbarSlots[world.hotbarSelection] = block
                                world.activeTool = .place
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(uiImage: block.previewImage)
                                            .interpolation(.none)
                                            .resizable()
                                            .frame(width: 28, height: 28)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.35), lineWidth: 1))
                                        Text("\(qty)")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 3)
                                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                                    }
                                    Text(block.rawValue)
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.white.opacity(0.32) : Color.black.opacity(0.45)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.yellow : Color.white.opacity(0.2), lineWidth: selected ? 2 : 1))
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 10)
            }
            }
        }
        }
        .sheet(isPresented: $isShowingSettings) {
            MinervaSettingsView(world: world)
        }
        .sheet(isPresented: $isShowingHowToPlay) {
            MinervaHowToPlayView()
        }
        .sheet(isPresented: $world.showCraftSheet) {
            CraftingSheetView(world: world)
        }
        .sheet(isPresented: $world.showInventorySheet) {
            InventorySheetView(world: world)
        }
        .sheet(isPresented: $world.showEnchantingSheet) {
            EnchantingSheetView(world: world)
        }
        .sheet(isPresented: $world.showChestSheet) {
            Group {
                if let chestKey = world.activeChestKey {
                    ChestStorageSheetView(world: world, chestKey: chestKey)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.largeTitle)
                        Text("Chest unavailable")
                            .font(.headline)
                        Text("The selected chest is no longer available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
        .sheet(isPresented: $world.showVillagerTradeSheet) {
            VillagerTradeSheetView(world: world)
        }
        .sheet(isPresented: $world.showBrewingSheet) {
            BrewingSheetView(world: world)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if !isShowingMainMenu { world.resumeGame() }
            case .inactive, .background:
                world.pauseGame()
            @unknown default:
                world.pauseGame()
            }
        }
    }
}

struct MoveHoldButton: View {
    let systemImage: String
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(isPressed ? Color.white.opacity(0.35) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed { isPressed = true; onPress() }
                    }
                    .onEnded { _ in
                        isPressed = false; onRelease()
                    }
            )
    }
}

@main
struct VoxelCraftApp: App {
    var body: some Scene {
        WindowGroup {
            VoxelGameView()
        }
    }
}

}
