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
                id: "gear_\(tier.rawValue.lowercased())_\(slot.rawValue.lowercased())",
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
        case .redstoneOre, .redstoneDust, .lever, .pressurePlate, .repeater, .button, .redstoneLamp: return UIColor(red: 0.92, green: 0.16, blue: 0.14, alpha: 1.0)
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
            let mat = makePixelMaterial(kind: .stone); box.materials = [mat, mat, mat, mat, mat, mat]
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
        if let dolphin = mobs.first(where: { $0.kind == .dolphin && simd_distance($0.position, playerPos) < 18 }) {
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
        for (dx, dz) in [(0, 3), (6, 5), (2, 8)] where (seed + dx * 7 + dz) % 2 == 0 {
            removeBlockInternal(at: BlockCoord(x: baseX + dx, y: baseY, z: baseZ + dz), markModified: false)
        }
    }

    private func placeCoralGarden(baseX: Int, baseY: Int, baseZ: Int, seed: Int) {
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
        let elderPosition = SIMD3<Float>(Float(baseX + 3) + 0.5,
                                         Float(baseY + 2) + 0.35,
                                         Float(baseZ + 3) + 0.5)
        spawnElderGuardian(at: elderPosition)
        removeBlockInternal(at: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ), markModified: false)
        removeBlockInternal(at: BlockCoord(x: baseX + 3, y: baseY + 2, z: baseZ), markModified: false)
    }

    private func placeUnderwaterCrystalCavern(baseX: Int, baseZ: Int, seed: Int) {
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

        for dz in -2...0 {
            for dy in 1...2 {
                removeBlockInternal(at: BlockCoord(x: baseX + 2, y: floorY + dy, z: baseZ + dz), markModified: false)
            }
        }
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
        setBlockInternal(coord: BlockCoord(x: baseX + 2, y: baseY + 1, z: baseZ), type: .door, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 1, y: baseY + 1, z: baseZ + 2), type: .bed, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 2), type: .craftingTable, markModified: false)
        setBlockInternal(coord: BlockCoord(x: baseX + 3, y: baseY + 1, z: baseZ + 3), type: .furnace, markModified: false)
        for dx in 1...3 {
            let cropCoord = BlockCoord(x: baseX + dx, y: baseY + 1, z: baseZ + 5)
            setBlockInternal(coord: cropCoord, type: .crop, markModified: false)
            cropStages[cropCoord] = 2
        }
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
        case .farmer: preferred = [.crop]
        case .miner: preferred = [.furnace]
        case .builder: preferred = [.craftingTable]
        }
        let candidates = blocks.keys.filter { preferred.contains(blocks[$0] ?? .grass) }
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
        while let parent = previous[cursor], parent != startCell {
            reversed.append(parent)
            cursor = parent
        }
        reversed.reverse()
        return reversed.map { cell in
            let floorY = highestSolidY(atX: cell.x, z: cell.z)
            return SIMD3<Float>(Float(cell.x) + 0.5, Float(floorY) + 1.0, Float(cell.z) + 0.5)
        }
    }

    private func advanceVillagerAlongPath(_ mob: WorldMob, toward target: SIMD3<Float>, speed: Float, dt: Float) -> Bool {
        let toGoal = target - mob.position
        let flatToGoal = SIMD2<Float>(toGoal.x, toGoal.z)
        if simd_length(flatToGoal) <= 1.25 {
            mob.navigationPath.removeAll()
            return true
        }

        mob.pathRefreshTimer -= dt
        if mob.pathRefreshTimer <= 0 || mob.navigationPath.isEmpty {
            mob.navigationPath = buildVillagerPath(from: mob.position, to: target)
            mob.pathRefreshTimer = 1.15
        }

        let waypoint = mob.navigationPath.first ?? target
        let stepVector = waypoint - mob.position
        let flatStep = SIMD2<Float>(stepVector.x, stepVector.z)
        let dist = simd_length(flatStep)
        if dist <= 0.35 && !mob.navigationPath.isEmpty {
            mob.navigationPath.removeFirst()
        }
        let activeTarget = mob.navigationPath.first ?? target
        let activeDelta = activeTarget - mob.position
        let activeFlat = SIMD2<Float>(activeDelta.x, activeDelta.z)
        let activeDist = simd_length(activeFlat)
        if activeDist > 0.05 {
            let dir = activeFlat / activeDist
            mob.position.x += dir.x * speed * dt
            mob.position.z += dir.y * speed * dt
            mob.yaw = atan2(dir.x, dir.y)
        }
        return false
    }

    private func makeMobNode(kind: MobKind) -> SCNNode {
        let root = SCNNode()
        let bodyGeom: SCNGeometry
        let bodyColor: UIColor

        switch kind {
        case .sheep: bodyGeom = SCNBox(width: 0.72, height: 0.56, length: 0.92, chamferRadius: 0.02); bodyColor = UIColor(red: 0.94, green: 0.94, blue: 0.96, alpha: 1.0)
        case .pig: bodyGeom = SCNBox(width: 0.68, height: 0.52, length: 0.88, chamferRadius: 0.02); bodyColor = UIColor(red: 0.95, green: 0.62, blue: 0.68, alpha: 1.0)
        case .cow: bodyGeom = SCNBox(width: 0.82, height: 0.74, length: 1.08, chamferRadius: 0.02); bodyColor = UIColor(red: 0.34, green: 0.21, blue: 0.12, alpha: 1.0)
        case .chicken: bodyGeom = SCNBox(width: 0.42, height: 0.44, length: 0.48, chamferRadius: 0.02); bodyColor = UIColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
        case .fox: bodyGeom = SCNBox(width: 0.54, height: 0.46, length: 0.78, chamferRadius: 0.02); bodyColor = UIColor(red: 0.92, green: 0.44, blue: 0.14, alpha: 1.0)
        case .bear: bodyGeom = SCNBox(width: 0.94, height: 0.88, length: 1.18, chamferRadius: 0.03); bodyColor = UIColor(red: 0.42, green: 0.26, blue: 0.14, alpha: 1.0)
        case .fish: bodyGeom = SCNBox(width: 0.22, height: 0.26, length: 0.52, chamferRadius: 0.02); bodyColor = UIColor(red: 0.28, green: 0.72, blue: 0.92, alpha: 1.0)
        case .dolphin: bodyGeom = SCNBox(width: 0.46, height: 0.44, length: 1.15, chamferRadius: 0.05); bodyColor = UIColor(red: 0.46, green: 0.66, blue: 0.86, alpha: 1.0)
        case .turtle: bodyGeom = SCNBox(width: 0.72, height: 0.28, length: 0.86, chamferRadius: 0.04); bodyColor = UIColor(red: 0.22, green: 0.64, blue: 0.36, alpha: 1.0)
        case .guardian: bodyGeom = SCNBox(width: 0.78, height: 0.78, length: 0.78, chamferRadius: 0.02); bodyColor = UIColor(red: 0.22, green: 0.68, blue: 0.64, alpha: 1.0)
        case .villager: bodyGeom = SCNBox(width: 0.52, height: 0.92, length: 0.34, chamferRadius: 0.02); bodyColor = UIColor(red: 0.42, green: 0.24, blue: 0.14, alpha: 1.0)
        case .ironGolem: bodyGeom = SCNBox(width: 1.15, height: 1.75, length: 0.78, chamferRadius: 0.02); bodyColor = UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1.0)
        case .slime: bodyGeom = SCNBox(width: 0.66, height: 0.66, length: 0.66, chamferRadius: 0.02); bodyColor = UIColor(red: 0.36, green: 0.84, blue: 0.32, alpha: 0.85)
        case .zombie: bodyGeom = SCNBox(width: 0.54, height: 1.25, length: 0.34, chamferRadius: 0.02); bodyColor = UIColor(red: 0.28, green: 0.62, blue: 0.32, alpha: 1.0)
        case .skeleton: bodyGeom = SCNBox(width: 0.46, height: 1.25, length: 0.30, chamferRadius: 0.02); bodyColor = UIColor(red: 0.86, green: 0.86, blue: 0.82, alpha: 1.0)
        case .creeper: bodyGeom = SCNBox(width: 0.52, height: 1.18, length: 0.36, chamferRadius: 0.02); bodyColor = UIColor(red: 0.22, green: 0.72, blue: 0.24, alpha: 1.0)
        case .enderman: bodyGeom = SCNBox(width: 0.44, height: 1.65, length: 0.30, chamferRadius: 0.02); bodyColor = UIColor(red: 0.12, green: 0.08, blue: 0.16, alpha: 1.0)
        case .enderDragon: bodyGeom = SCNBox(width: 2.2, height: 1.1, length: 2.8, chamferRadius: 0.05); bodyColor = UIColor(red: 0.24, green: 0.08, blue: 0.36, alpha: 1.0)
        case .spider: bodyGeom = SCNBox(width: 0.92, height: 0.42, length: 1.02, chamferRadius: 0.02); bodyColor = UIColor(red: 0.22, green: 0.17, blue: 0.15, alpha: 1.0)
        case .blaze: bodyGeom = SCNBox(width: 0.56, height: 1.18, length: 0.56, chamferRadius: 0.02); bodyColor = UIColor(red: 0.98, green: 0.62, blue: 0.12, alpha: 1.0)
        }

        let bodyMat = SCNMaterial()
        bodyMat.diffuse.contents = bodyColor
        if kind == .blaze { bodyMat.emission.contents = UIColor(red: 0.95, green: 0.45, blue: 0.05, alpha: 0.65) }
        bodyGeom.materials = [bodyMat]
        let bodyNode = SCNNode(geometry: bodyGeom)
        bodyNode.position = SCNVector3(0, 0.35, 0)
        root.addChildNode(bodyNode)

        if kind == .enderDragon {
            let wingMat = SCNMaterial(); wingMat.diffuse.contents = UIColor(red: 0.68, green: 0.24, blue: 0.96, alpha: 0.9)
            let leftWing = SCNNode(geometry: SCNBox(width: 2.4, height: 0.12, length: 1.3, chamferRadius: 0.02))
            leftWing.geometry?.materials = [wingMat]; leftWing.position = SCNVector3(-2.1, 0.55, 0)
            let rightWing = SCNNode(geometry: SCNBox(width: 2.4, height: 0.12, length: 1.3, chamferRadius: 0.02))
            rightWing.geometry?.materials = [wingMat]; rightWing.position = SCNVector3(2.1, 0.55, 0)
            root.addChildNode(leftWing); root.addChildNode(rightWing)
        }

        let headGeom = SCNBox(width: 0.40, height: 0.40, length: 0.40, chamferRadius: 0.02)
        let headMat = SCNMaterial()
        headMat.diffuse.contents = (kind == .villager) ? UIColor(red: 0.92, green: 0.72, blue: 0.56, alpha: 1.0) : bodyColor
        headGeom.materials = [headMat]
        let headNode = SCNNode(geometry: headGeom)
        headNode.position = SCNVector3(0, 0.85, 0.35)
        root.addChildNode(headNode)

        if kind == .villager {
            let nose = SCNNode(geometry: SCNBox(width: 0.10, height: 0.16, length: 0.12, chamferRadius: 0.01))
            nose.geometry?.materials = [headMat]
            nose.position = SCNVector3(0, 0.82, 0.58)
            root.addChildNode(nose)
        }

        if [.zombie, .skeleton, .creeper, .enderman, .enderDragon, .spider, .blaze].contains(kind) {
            let eyeGeom = SCNBox(width: 0.10, height: 0.08, length: 0.05, chamferRadius: 0.0)
            let eyeMat = SCNMaterial()
            eyeMat.diffuse.contents = (kind == .enderman || kind == .enderDragon) ? UIColor.magenta : (kind == .spider ? UIColor.red : UIColor.yellow)
            eyeMat.emission.contents = eyeMat.diffuse.contents
            eyeGeom.materials = [eyeMat]
            let leftEye = SCNNode(geometry: eyeGeom); leftEye.position = SCNVector3(-0.10, 0.88, 0.56)
            let rightEye = SCNNode(geometry: eyeGeom); rightEye.position = SCNVector3(0.10, 0.88, 0.56)
            root.addChildNode(leftEye); root.addChildNode(rightEye)
        }

        return root
    }

    private func spawnArrow(from origin: SIMD3<Float>, target: SIMD3<Float>, damage: Int = 3, color: UIColor = UIColor.white) {
        let dir = simd_normalize(target - origin)
        let geom = SCNBox(width: 0.08, height: 0.08, length: 0.52, chamferRadius: 0.0)
        let mat = SCNMaterial(); mat.diffuse.contents = color; mat.emission.contents = color
        geom.materials = [mat]
        let node = SCNNode(geometry: geom)
        node.position = SCNVector3(origin.x, origin.y, origin.z)
        node.look(at: SCNVector3(origin.x + dir.x, origin.y + dir.y, origin.z + dir.z))
        projectilesRootNode.addChildNode(node)
        arrows.append(ArrowProjectile(position: origin, velocity: dir * 13.0, damage: damage, node: node))
        SoundEngine.shared.play(.arrow)
    }

    private func spawnDroppedItem(blockType: BlockType, at worldPos: SIMD3<Float>) {
        let geom = SCNBox(width: 0.28, height: 0.28, length: 0.28, chamferRadius: 0.01)
        if let shared = sharedGeometries[blockType] { geom.materials = shared.materials }
        let node = SCNNode(geometry: geom)
        node.position = SCNVector3(worldPos.x, worldPos.y + 0.2, worldPos.z)
        dropsRootNode.addChildNode(node)
        droppedItems.append(DroppedItemEntity(blockType: blockType, position: SIMD3<Float>(worldPos.x, worldPos.y + 0.2, worldPos.z), bobPhase: Float.random(in: 0...6.28), node: node))
    }

    private func spawnParticles(at worldPos: SIMD3<Float>, color: UIColor, count: Int = 6) {
        for _ in 0..<count {
            let geom = SCNBox(width: 0.11, height: 0.11, length: 0.11, chamferRadius: 0.0)
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.emission.contents = color.withAlphaComponent(0.3)
            geom.materials = [mat]
            let pNode = SCNNode(geometry: geom)
            pNode.position = SCNVector3(worldPos.x + Float.random(in: -0.25...0.25), worldPos.y + Float.random(in: -0.15...0.25), worldPos.z + Float.random(in: -0.25...0.25))
            scene.rootNode.addChildNode(pNode)

            let dx = CGFloat(Float.random(in: -0.8...0.8))
            let dy = CGFloat(Float.random(in: 0.35...1.1))
            let dz = CGFloat(Float.random(in: -0.8...0.8))
            let action = SCNAction.sequence([
                .group([.moveBy(x: dx, y: dy, z: dz, duration: 0.35), .fadeOut(duration: 0.35)]),
                .removeFromParentNode()
            ])
            pNode.runAction(action)
        }
    }

    // MARK: - Block Editing, Redstone, Crops & Persistence

    private func setBlockInternal(coord: BlockCoord, type: BlockType, markModified: Bool) {
        blocks[coord] = type
        if markModified { modifiedCoords.insert(coord) }
        refreshBlockNode(at: coord)
    }

    private func removeBlockInternal(at coord: BlockCoord, markModified: Bool) {
        blocks.removeValue(forKey: coord)
        if markModified { modifiedCoords.insert(coord) }
        openDoors.remove(coord)
        redstoneToggledDoors.remove(coord)
        activeLevers.remove(coord)
        activePressurePlates.remove(coord)
        activeButtons.removeValue(forKey: coord)
        poweredRedstoneLamps.remove(coord)
        cropStages.removeValue(forKey: coord)
        blockNodes[coord]?.removeFromParentNode()
        blockNodes.removeValue(forKey: coord)
    }

    private func refreshBlockNode(at coord: BlockCoord) {
        blockNodes[coord]?.removeFromParentNode()
        blockNodes.removeValue(forKey: coord)

        guard let type = blocks[coord] else { return }
        let dist = simd_distance(SIMD3<Float>(Float(coord.x) + 0.5, Float(coord.y) + 0.5, Float(coord.z) + 0.5), playerPos)
        guard dist <= maxViewDistance else { return }

        let node = SCNNode(geometry: sharedGeometries[type] ?? type.makeGeometry())
        node.position = coord.scnVector
        node.name = "block_\(coord.x)_\(coord.y)_\(coord.z)"
        if type == .door && openDoors.contains(coord) { node.eulerAngles.y = .pi / 2 }
        if type == .lever && activeLevers.contains(coord) { node.eulerAngles.z = .pi / 4 }
        if type == .crop {
            let st = cropStages[coord] ?? 0
            node.scale = SCNVector3(1.0, CGFloat(0.45 + Double(st) * 0.22), 1.0)
        }
        blocksRootNode.addChildNode(node)
        blockNodes[coord] = node
    }

    private func clearAllBlockNodes() {
        for (_, node) in blockNodes { node.removeFromParentNode() }
        blockNodes.removeAll()
    }

    func setMovementInput(x: Float, z: Float) { moveInput = SIMD2<Float>(x, z) }

    func setSprint(_ active: Bool) {
        if active && stamina <= 2 {
            isSprinting = false
            return
        }
        isSprinting = active
    }

    func toggleShield() {
        isShieldRaised.toggle()
        statusMessage = isShieldRaised ? "Shield raised — incoming damage reduced" : "Shield lowered"
    }

    func rotateCamera(deltaX: Float, deltaY: Float) {
        yaw -= deltaX * 0.0055
        pitch = max(-1.35, min(1.35, pitch - deltaY * 0.0055))
        updateCameraTransform()
    }

    func jump() {
        if isInBoat { return }
        let feetY = Int(floor(playerPos.y - 1.55))
        let px = Int(floor(playerPos.x))
        let pz = Int(floor(playerPos.z))
        let onGround = hasSolidBlock(atX: px, y: feetY, z: pz) || hasSolidBlock(atX: px, y: feetY, z: pz - 1) || hasSolidBlock(atX: px, y: feetY, z: pz + 1)
        if onGround || isUnderwater {
            verticalVelocity = isUnderwater ? 4.8 : 7.4
            SoundEngine.shared.play(.jump)
        }
    }

    func toggleCameraMode() {
        cameraMode = (cameraMode == .firstPerson) ? .overview : .firstPerson
        updateCameraTransform()
        statusMessage = (cameraMode == .overview) ? "Overview camera" : "First-person camera"
    }

    func setCustomSpawnHere() {
        let coord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 1.0)), z: Int(floor(playerPos.z)))
        customSpawnCoord = coord
        saveWorld()
        statusMessage = "Respawn set to X:\(coord.x) Y:\(coord.y) Z:\(coord.z)"
    }

    func respawnPlayer() {
        if isInBoat {
            isInBoat = false
            boatSpeed = 0
        }
        if let sp = customSpawnCoord {
            let gy = max(sp.y, highestSolidY(atX: sp.x, z: sp.z))
            playerPos = SIMD3<Float>(Float(sp.x) + 0.5, Float(gy) + 2.5, Float(sp.z) + 0.5)
        } else {
            let gy = highestSolidY(atX: 0, z: 6)
            playerPos = SIMD3<Float>(0.5, Float(gy) + 2.5, 6.5)
        }
        verticalVelocity = 0.0
        fallStartY = nil
        health = 20
        hunger = 20
        oxygen = 10
        stamina = 100
        isSprinting = false
        isUnderwater = false
        drowningTimer = 0
        oxygenTickTimer = 0
        staminaRecoveryDelay = 0
        updateChunksAroundPlayer(force: true)
        updateCameraTransform()
    }

    private func triggerExplosion(at center: BlockCoord, radius: Int = 2) {
        SoundEngine.shared.play(.explode)
        spawnParticles(at: center.scnVector, color: UIColor.orange, count: 14)
        for dx in -radius...radius {
            for dy in -radius...radius {
                for dz in -radius...radius where dx * dx + dy * dy + dz * dz <= radius * radius + 1 {
                    let target = BlockCoord(x: center.x + dx, y: center.y + dy, z: center.z + dz)
                    if target.y > 0 && blocks[target] != .bedrock {
                        removeBlockInternal(at: target, markModified: true)
                    }
                }
            }
        }
        let distToPlayer = simd_distance(center.scnVector.simd, playerPos)
        if distToPlayer < 4.5 && gameMode == .survival {
            applyPlayerDamage(6, source: "TNT blast")
        }
        saveWorld()
    }

    private func applyPlayerDamage(_ amount: Int, source: String) {
        guard gameMode == .survival, health > 0 else { return }
        if isShieldRaised {
            statusMessage = "Blocked \(source) with shield"
            SoundEngine.shared.play(.piston)
            return
        }
        let resistanceActive = (activePotionEffects[.resistance] ?? 0) > 0
        let resistanceMitigation = resistanceActive ? max(1, (amount + 1) / 2) : 0
        let reduced = max(1, amount - effectiveArmorReduction - resistanceMitigation)
        damageArmor()
        health = max(0, health - reduced)
        SoundEngine.shared.play(.hurt)
        statusMessage = "\(source) (-\(reduced) HP)"
        if health == 0 {
            statusMessage = "Defeated by \(source) — Respawning"
            respawnPlayer()
        }
    }

    // MARK: - Redstone Propagation & Piston Extension

    private func isCoordPowered(_ coord: BlockCoord) -> Bool {
        let now = CACurrentMediaTime()
        for activeButton in activeButtons where now - activeButton.value > 1.2 {
            activeButtons.removeValue(forKey: activeButton.key)
            blockNodes[activeButton.key]?.scale = SCNVector3(1.0, 1.0, 1.0)
        }
        let neighbors = [
            BlockCoord(x: coord.x + 1, y: coord.y, z: coord.z),
            BlockCoord(x: coord.x - 1, y: coord.y, z: coord.z),
            BlockCoord(x: coord.x, y: coord.y + 1, z: coord.z),
            BlockCoord(x: coord.x, y: coord.y - 1, z: coord.z),
            BlockCoord(x: coord.x, y: coord.y, z: coord.z + 1),
            BlockCoord(x: coord.x, y: coord.y, z: coord.z - 1)
        ]
        for n in neighbors {
            if blocks[n] == .lever && activeLevers.contains(n) { return true }
            if blocks[n] == .pressurePlate && activePressurePlates.contains(n) { return true }
            if blocks[n] == .button && activeButtons[n] != nil { return true }
            if blocks[n] == .redstoneDust { return true }
        }
        return false
    }

    private func propagateRedstone(around origin: BlockCoord) {
        let candidates = [
            origin,
            BlockCoord(x: origin.x + 1, y: origin.y, z: origin.z),
            BlockCoord(x: origin.x - 1, y: origin.y, z: origin.z),
            BlockCoord(x: origin.x, y: origin.y + 1, z: origin.z),
            BlockCoord(x: origin.x, y: origin.y - 1, z: origin.z),
            BlockCoord(x: origin.x, y: origin.y, z: origin.z + 1),
            BlockCoord(x: origin.x, y: origin.y, z: origin.z - 1)
        ]

        for c in candidates {
            guard let b = blocks[c] else { continue }
            let powered = isCoordPowered(c)

            if b == .tnt && powered {
                triggerExplosion(at: c, radius: 2)
            } else if b == .redstoneLamp {
                if powered && !poweredRedstoneLamps.contains(c) {
                    poweredRedstoneLamps.insert(c)
                    let lit = SCNMaterial()
                    lit.diffuse.contents = UIColor(red: 1.0, green: 0.85, blue: 0.42, alpha: 1.0)
                    lit.emission.contents = UIColor(red: 1.0, green: 0.68, blue: 0.18, alpha: 0.92)
                    blockNodes[c]?.geometry?.materials = [lit, lit, lit, lit, lit, lit]
                    SoundEngine.shared.play(.piston)
                } else if !powered && poweredRedstoneLamps.contains(c) {
                    poweredRedstoneLamps.remove(c)
                    refreshBlockNode(at: c)
                }
            } else if b == .door {
                if powered && !openDoors.contains(c) {
                    openDoors.insert(c)
                    redstoneToggledDoors.insert(c)
                    blockNodes[c]?.eulerAngles.y = .pi / 2
                    SoundEngine.shared.play(.piston)
                } else if !powered && redstoneToggledDoors.contains(c) {
                    openDoors.remove(c)
                    redstoneToggledDoors.remove(c)
                    blockNodes[c]?.eulerAngles.y = 0
                }
            } else if b == .piston {
                let headCoord = BlockCoord(x: c.x, y: c.y + 1, z: c.z)
                if powered && !extendedPistons.contains(c) && blocks[headCoord] == nil {
                    extendedPistons.insert(c)
                    setBlockInternal(coord: headCoord, type: .planks, markModified: true)
                    SoundEngine.shared.play(.piston)
                } else if !powered && extendedPistons.contains(c) {
                    extendedPistons.remove(c)
                    if blocks[headCoord] == .planks {
                        removeBlockInternal(at: headCoord, markModified: true)
                    }
                }
            }
        }
    }

    private func interactWithBlock(at coord: BlockCoord, type: BlockType) -> Bool {
        if type == .door {
            if openDoors.contains(coord) {
                openDoors.remove(coord)
                redstoneToggledDoors.remove(coord)
                blockNodes[coord]?.eulerAngles.y = 0
                statusMessage = "Closed door"
            } else {
                openDoors.insert(coord)
                blockNodes[coord]?.eulerAngles.y = .pi / 2
                statusMessage = "Opened door"
            }
            SoundEngine.shared.play(.piston)
            saveWorld()
            return true
        }
        if type == .chest {
            openChest(at: coord)
            return true
        }
        if type == .craftingTable {
            showCraftSheet = true
            statusMessage = "Opened Crafting Bench"
            return true
        }
        if type == .furnace {
            queueFurnaceSmelt()
            return true
        }
        if type == .bed {
            isNightMode.toggle()
            health = min(20, health + 6)
            setCustomSpawnHere()
            statusMessage = isNightMode ? "Slept until night (+6 HP, spawn set)" : "Slept until morning (+6 HP, spawn set)"
            SoundEngine.shared.play(.eat)
            return true
        }
        if type == .lever {
            if activeLevers.contains(coord) {
                activeLevers.remove(coord)
                blockNodes[coord]?.eulerAngles.z = 0
                statusMessage = "Lever OFF"
            } else {
                activeLevers.insert(coord)
                blockNodes[coord]?.eulerAngles.z = .pi / 4
                statusMessage = "Lever ON"
            }
            SoundEngine.shared.play(.piston)
            propagateRedstone(around: coord)
            saveWorld()
            return true
        }
        if type == .button {
            activeButtons[coord] = CACurrentMediaTime()
            blockNodes[coord]?.scale = SCNVector3(1.0, 0.45, 1.0)
            SoundEngine.shared.play(.piston)
            propagateRedstone(around: coord)
            statusMessage = "Button pressed"
            return true
        }
        if type == .tnt {
            triggerExplosion(at: coord, radius: 2)
            return true
        }
        if type == .portal {
            selectDimension(activeDimension.nextDimension)
            return true
        }
        if type == .crop {
            let st = cropStages[coord] ?? 0
            if st >= 3 {
                cropStages[coord] = 0
                blockNodes[coord]?.scale = SCNVector3(1.0, 0.45, 1.0)
                foodInventory[.wheat, default: 0] += 2
                foodInventory[.seeds, default: 0] += 1
                _ = addItems(2, of: .leaves)
                SoundEngine.shared.play(.pickup)
                statusMessage = "Harvested crop (+2 Wheat, +1 Seeds)"
                saveWorld()
            } else {
                cropStages[coord] = st + 1
                blockNodes[coord]?.scale = SCNVector3(1.0, CGFloat(0.45 + Double(st + 1) * 0.22), 1.0)
                statusMessage = "Tended crop (stage \(st + 1)/3)"
            }
            return true
        }
        return false
    }

    @discardableResult
    func performPrimaryAction(at point: CGPoint? = nil, in view: SCNView? = nil) -> String {
        if selectedTool == .fishingRod && activeTool == .breakBlock {
            let px = Int(floor(playerPos.x)), py = Int(floor(playerPos.y - 1.1)), pz = Int(floor(playerPos.z))
            let forward = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
            for step in 1...4 {
                let sample = playerPos + forward * Float(step)
                let c = BlockCoord(x: Int(floor(sample.x)), y: Int(floor(sample.y)), z: Int(floor(sample.z)))
                if blocks[c] == .water { castFishingRod(at: c); return statusMessage }
            }
            for dx in -2...2 {
                for dz in -2...2 {
                    for dy in -2...0 {
                        let c = BlockCoord(x: px + dx, y: py + dy, z: pz + dz)
                        if blocks[c] == .water { castFishingRod(at: c); return statusMessage }
                    }
                }
            }
            castFishingRod(at: BlockCoord(x: px, y: py, z: pz))
            return statusMessage
        }

        if let view, let point {
            let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                if let mob = hitMob(from: hit.node) {
                    let meleeBonus = selectedTool == .sword ? 2 : 0
                    let sharpnessBonus = enchantmentLevel(.sharpness) * 2
                    let strengthBonus = (activePotionEffects[.strength] ?? 0) > 0 ? 4 : 0
                    let dmg = max(2, equippedGear.attackDamage + selectedTool.attackDamage + meleeBonus + sharpnessBonus + strengthBonus)
                    let wasHostile = [.zombie, .skeleton, .creeper, .enderman, .enderDragon, .spider, .blaze, .guardian].contains(mob.kind)
                    mob.hp -= dmg
                    if gameMode == .survival { damageTool() }
                    let pushDir = simd_normalize(SIMD2<Float>(mob.position.x - playerPos.x, mob.position.z - playerPos.z) + SIMD2<Float>(0.001, 0.001))
                    mob.knockback = pushDir * 6.5
                    SoundEngine.shared.play(.hitMob)
                    spawnParticles(at: mob.position, color: UIColor.red, count: 6)
                    if mob.hp <= 0 {
                        let wasElderGuardian = mob.isElderGuardian
                        if mob.kind == .enderDragon {
                            unlockAchievement("dragon_slayer")
                            awardExperience(35, at: mob.position)
                        } else if wasElderGuardian {
                            unlockAchievement("monument_conqueror")
                            awardExperience(25, at: mob.position)
                        } else if wasHostile {
                            defeatedHostileCount += 1
                            unlockAchievement("first_blood")
                            if defeatedHostileCount >= 10 { unlockAchievement("monster_hunter") }
                            awardExperience(4, at: mob.position)
                        }
                        if mob.kind == .sheep { foodInventory[.rawMutton, default: 0] += 1; _ = addItems(1, of: .wool) }
                        else if mob.kind == .pig { foodInventory[.rawPork, default: 0] += 1 }
                        else if mob.kind == .cow { foodInventory[.rawBeef, default: 0] += 1 }
                        else if mob.kind == .chicken { foodInventory[.rawChicken, default: 0] += 1; foodInventory[.seeds, default: 0] += 1 }
                        else if mob.kind == .fish { foodInventory[.rawFish, default: 0] += 1 }
                        else if mob.kind == .spider { _ = addItems(1, of: .redstoneOre) }
                        else if mob.kind == .blaze { _ = addItems(1, of: .glowstone) }
                        else if mob.kind == .enderDragon { _ = addItems(2, of: .endCrystal) }
                        else if mob.kind == .guardian { _ = addItems(2, of: .prismarine) }
                        mob.node.removeFromParentNode()
                        mobs.removeAll { $0.id == mob.id }
                        if wasElderGuardian || mob.kind == .enderDragon { syncBossHUD() }
                        statusMessage = "Defeated \(mob.kind.rawValue)"
                    } else {
                        if wasElderGuardian || mob.kind == .enderDragon { syncBossHUD() }
                        statusMessage = "Hit \(mob.kind.rawValue) (-\(dmg) HP)"
                    }
                    return statusMessage
                }
            }
        }

        if activeTool == .breakBlock {
            guard let target = targetedBlock(from: point, in: view), let existing = blocks[target] else {
                statusMessage = "No block in range to mine"
                return statusMessage
            }
            if existing == .bedrock {
                statusMessage = "Bedrock cannot be mined"
                return statusMessage
            }
            let dropType: BlockType
            switch existing {
            case .grass, .snowGrass: dropType = .dirt
            case .stone: dropType = .cobblestone
            default: dropType = existing
            }
            removeBlockInternal(at: target, markModified: true)
            if gameMode == .survival { damageTool() }
            if [.coalOre, .ironOre, .goldOre, .diamondOre, .emeraldOre, .redstoneOre, .quartzOre].contains(existing) {
                awardExperience(existing == .diamondOre || existing == .emeraldOre ? 4 : 2, at: target.scnVector.simd)
            }
            spawnDroppedItem(blockType: dropType, at: target.scnVector.simd)
            spawnParticles(at: target.scnVector.simd, color: existing.particleColor, count: 8)
            placedOrMinedCount += 1
            SoundEngine.shared.play(.mine)
            sendBlockDelta(coord: target, type: nil)
            saveWorld()
            statusMessage = "Mined \(existing.rawValue)"
            return statusMessage
        }

        if let hitBlock = targetedBlock(from: point, in: view), let hitType = blocks[hitBlock] {
            if interactWithBlock(at: hitBlock, type: hitType) {
                return statusMessage
            }
        }

        guard let placeCoord = placementCoordinate(from: point, in: view) else {
            statusMessage = "Aim at a surface to place a block"
            return statusMessage
        }

        let currentCount = count(for: selectedBlock)
        if gameMode == .survival && currentCount <= 0 {
            statusMessage = "Out of \(selectedBlock.rawValue) in Survival"
            return statusMessage
        }

        if gameMode == .survival {
            inventory[selectedBlock] = max(0, currentCount - 1)
        }

        setBlockInternal(coord: placeCoord, type: selectedBlock, markModified: true)
        if selectedBlock == .crop { cropStages[placeCoord] = 0 }
        spawnParticles(at: placeCoord.scnVector.simd, color: selectedBlock.particleColor, count: 6)
        placedOrMinedCount += 1
        SoundEngine.shared.play(.place)
        propagateRedstone(around: placeCoord)
        checkIronGolemSummon(around: placeCoord)
        sendBlockDelta(coord: placeCoord, type: selectedBlock)
        saveWorld()
        statusMessage = "Placed \(selectedBlock.rawValue)"
        return statusMessage
    }

    private func checkIronGolemSummon(around coord: BlockCoord) {
        guard selectedBlock == .glowstone || selectedBlock == .tnt || selectedBlock == .seaLantern else { return }
        let below1 = BlockCoord(x: coord.x, y: coord.y - 1, z: coord.z)
        let below2 = BlockCoord(x: coord.x, y: coord.y - 2, z: coord.z)
        guard blocks[below1] == .ironOre && blocks[below2] == .ironOre else { return }
        let armL = BlockCoord(x: coord.x - 1, y: coord.y - 1, z: coord.z)
        let armR = BlockCoord(x: coord.x + 1, y: coord.y - 1, z: coord.z)
        guard blocks[armL] == .ironOre && blocks[armR] == .ironOre else { return }

        removeBlockInternal(at: coord, markModified: true)
        removeBlockInternal(at: below1, markModified: true)
        removeBlockInternal(at: below2, markModified: true)
        removeBlockInternal(at: armL, markModified: true)
        removeBlockInternal(at: armR, markModified: true)

        let pos = SIMD3<Float>(Float(below2.x) + 0.5, Float(below2.y) + 1.0, Float(below2.z) + 0.5)
        let node = makeMobNode(kind: .ironGolem)
        node.position = SCNVector3(pos.x, pos.y, pos.z)
        let golem = WorldMob(kind: .ironGolem, position: pos, yaw: 0, hp: 80, wanderTimer: 1.5, node: node)
        node.name = "mob_\(golem.id.uuidString)"
        mobsRootNode.addChildNode(node)
        mobs.append(golem)
        unlockAchievement("village_guardian")
        SoundEngine.shared.play(.piston)
        statusMessage = "Summoned Iron Golem!"
    }

    func handleWorldTap(at point: CGPoint, in view: SCNView) {
        if let hitMob = tappedMob(at: point, in: view) {
            if hitMob.kind == .villager {
                let dist = simd_length(SIMD2<Float>(hitMob.position.x - playerPos.x, hitMob.position.z - playerPos.z))
                if dist <= 6.0 {
                    activeVillagerID = hitMob.id
                    showVillagerTradeSheet = true
                    statusMessage = "Trading with \(hitMob.profession.rawValue) Villager"
                } else {
                    statusMessage = "Move closer to trade with the Villager"
                }
                return
            }
            if [.wolf, .fox, .bear].contains(hitMob.kind) {
                if hitMob.isTamed {
                    if hitMob.hp < 12 {
                        let healFood: FoodKind = hitMob.kind == .wolf ? .cookedBeef : (hitMob.kind == .fox ? .rawFish : .cookedMutton)
                        if foodCount(for: healFood) > 0 {
                            foodInventory[healFood, default: 0] -= 1
                            hitMob.hp = 12
                            unlockAchievement("well_cared_for")
                            statusMessage = "Restored \(hitMob.kind.rawValue) to full health"
                            SoundEngine.shared.play(.eat)
                            saveWorld()
                            return
                        }
                    }
                    if !hitMob.isSitting && !hitMob.isGuarding {
                        hitMob.isSitting = true; hitMob.isGuarding = false; hitMob.guardPosition = nil
                        statusMessage = "\(hitMob.kind.rawValue) is sitting"
                    } else if hitMob.isSitting {
                        hitMob.isSitting = false; hitMob.isGuarding = true; hitMob.guardPosition = hitMob.position
                        unlockAchievement("watchful_companion")
                        statusMessage = "\(hitMob.kind.rawValue) is guarding this spot"
                    } else {
                        hitMob.isSitting = false; hitMob.isGuarding = false; hitMob.guardPosition = nil
                        statusMessage = "\(hitMob.kind.rawValue) is following you"
                    }
                    SoundEngine.shared.play(.pickup)
                    saveWorld()
                    return
                }
                if tameCompanion(hitMob) { return }
            }
            if [.sheep, .pig, .cow, .chicken, .wolf, .fox, .bear, .fish, .dolphin, .turtle].contains(hitMob.kind), feedAnimal(hitMob) {
                return
            }
        }
        _ = performPrimaryAction(at: point, in: view)
    }

    private func tappedMob(at point: CGPoint, in view: SCNView) -> WorldMob? {
        let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
        for hit in hits {
            if let mob = hitMob(from: hit.node) { return mob }
        }
        return nil
    }

    private func hitMob(from node: SCNNode) -> WorldMob? {
        var cur: SCNNode? = node
        while let n = cur {
            if let name = n.name, name.hasPrefix("mob_"), let uuid = UUID(uuidString: String(name.dropFirst(4))) {
                return mobs.first(where: { $0.id == uuid })
            }
            cur = n.parent
        }
        return nil
    }

    private func targetedBlock(from point: CGPoint?, in view: SCNView?) -> BlockCoord? {
        if let view, let point {
            let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                if let coord = coordFromNode(hit.node) { return coord }
            }
        }
        let ray = forwardRay()
        for step in stride(from: Float(1.0), through: Float(5.5), by: Float(0.25)) {
            let sample = ray.origin + ray.dir * step
            let c = BlockCoord(x: Int(floor(sample.x)), y: Int(floor(sample.y)), z: Int(floor(sample.z)))
            if blocks[c] != nil { return c }
        }
        return nil
    }

    private func placementCoordinate(from point: CGPoint?, in view: SCNView?) -> BlockCoord? {
        if let view, let point {
            let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.closest.rawValue])
            for hit in hits {
                if let hitCoord = coordFromNode(hit.node) {
                    let n = hit.worldNormal
                    let candidate = BlockCoord(x: hitCoord.x + Int(round(n.x)), y: hitCoord.y + Int(round(n.y)), z: hitCoord.z + Int(round(n.z)))
                    if candidate.y >= 0 && candidate.y <= 15 && blocks[candidate] == nil && !intersectsPlayer(candidate) {
                        return candidate
                    }
                }
            }
        }
        let ray = forwardRay()
        var previousEmpty: BlockCoord?
        for step in stride(from: Float(1.2), through: Float(5.0), by: Float(0.25)) {
            let sample = ray.origin + ray.dir * step
            let c = BlockCoord(x: Int(floor(sample.x)), y: Int(floor(sample.y)), z: Int(floor(sample.z)))
            if blocks[c] != nil {
                if let prev = previousEmpty, prev.y >= 0 && prev.y <= 15 && !intersectsPlayer(prev) { return prev }
                return nil
            }
            previousEmpty = c
        }
        return nil
    }

    private func coordFromNode(_ node: SCNNode) -> BlockCoord? {
        var cur: SCNNode? = node
        while let n = cur {
            if let name = n.name, name.hasPrefix("block_") {
                let parts = name.split(separator: "_")
                if parts.count == 4, let x = Int(parts[1]), let y = Int(parts[2]), let z = Int(parts[3]) {
                    return BlockCoord(x: x, y: y, z: z)
                }
            }
            cur = n.parent
        }
        return nil
    }

    private func forwardRay() -> (origin: SIMD3<Float>, dir: SIMD3<Float>) {
        let dir = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        return (playerPos, simd_normalize(dir))
    }

    private func intersectsPlayer(_ coord: BlockCoord) -> Bool {
        let bx = Float(coord.x) + 0.5, by = Float(coord.y) + 0.5, bz = Float(coord.z) + 0.5
        let dx = abs(playerPos.x - bx), dz = abs(playerPos.z - bz)
        let dyMin = playerPos.y - 1.45, dyMax = playerPos.y + 0.25
        return dx < 0.72 && dz < 0.72 && (Float(coord.y) + 1.0) > dyMin && Float(coord.y) < dyMax
    }

    private func hasSolidBlock(atX x: Int, y: Int, z: Int) -> Bool {
        guard let b = blocks[BlockCoord(x: x, y: y, z: z)] else { return false }
        return !b.isPassable
    }

    private func highestSolidY(atX x: Int, z: Int) -> Int {
        for y in stride(from: 11, through: 0, by: -1) {
            if let b = blocks[BlockCoord(x: x, y: y, z: z)], !b.isPassable { return y }
        }
        return 0
    }

    // MARK: - Frame Loop, Mobs, Projectiles & LAN Sync

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt: Float
        if let last = lastFrameTime { dt = Float(min(0.05, max(0.001, time - last))) } else { dt = 0.016 }
        lastFrameTime = time

        if isAutoCycleEnabled {
            dayClockTimer += dt
            if dayClockTimer >= 45.0 {
                dayClockTimer = 0.0
                isNightMode.toggle()
            }
        }

        let targetNight: Float = isNightMode ? 1.0 : 0.0
        if abs(nightProgress - targetNight) > 0.005 {
            nightProgress = lerp(nightProgress, targetNight, min(1.0, dt * 1.8))
            applySkyLighting(progress: nightProgress)
        }

        updateCloudsAndWeather(dt: dt)
        updatePlayerPhysics(dt: dt)
        updateBoatMotion(dt: dt)
        updateMobs(dt: dt)
        updateArrows(dt: dt)
        updateDroppedItems(dt: dt)
        updateExperienceOrbs(dt: dt)
        updateActiveEffectsAndRegeneration(dt: dt)
        updateCameraTransform()

        for (coord, node) in blockNodes {
            let d = simd_distance(node.simdPosition, playerPos)
            if d > maxViewDistance + 2.0 {
                node.removeFromParentNode()
                blockNodes.removeValue(forKey: coord)
            }
        }

        simTickTimer += dt
        if simTickTimer >= 0.25 {
            simTickTimer = 0
            updateChunksAroundPlayer()
            updatePressurePlates()
            updateFurnace(dt: 0.25)
            syncBossHUD()
            let px = Int(floor(playerPos.x)), py = Int(floor(playerPos.y - 1.0)), pz = Int(floor(playerPos.z))
            let biome = BiomeType.biomeAt(x: px, z: pz, dimension: activeDimension)
            currentBiome = biome
            if activeDimension == .overworld {
                discoveredBiomes.insert(biome.rawValue)
                if biome == .swamp { unlockAchievement("swamp_walker") }
                if biome == .jungle { unlockAchievement("jungle_explorer") }
                if biome == .taiga { unlockAchievement("taiga_traveler") }
                if biome == .beach { unlockAchievement("coastal_roamer") }
                let overworldBiomes: Set<String> = [
                    BiomeType.plains.rawValue, BiomeType.desert.rawValue, BiomeType.forest.rawValue,
                    BiomeType.highlands.rawValue, BiomeType.ocean.rawValue, BiomeType.beach.rawValue,
                    BiomeType.swamp.rawValue, BiomeType.taiga.rawValue, BiomeType.jungle.rawValue
                ]
                if discoveredBiomes.isSuperset(of: overworldBiomes) { unlockAchievement("biome_explorer") }
            }
            coordsText = "\(biome.rawValue) · X: \(px)  Y: \(py)  Z: \(pz)"
        }

        cropGrowthTimer += dt
        if cropGrowthTimer >= 4.0 {
            cropGrowthTimer = 0
            cropGrowthCycle += 1
            for coord in blocks.keys where blocks[coord] == .crop {
                let st = cropStages[coord] ?? 0
                if st < 3 {
                    let next = st + 1
                    cropStages[coord] = next
                    blockNodes[coord]?.scale = SCNVector3(1.0, CGFloat(0.45 + Double(next) * 0.22), 1.0)
                }
            }
            if cropGrowthCycle % 6 == 0 {
                saveWorld()
            }
        }

        if multiplayerEnabled {
            netSyncTimer += dt
            if netSyncTimer >= 0.12 {
                netSyncTimer = 0
                sendPlayerState()
            }
            connectedPeerCount = lanManager.connectedPeers.count
        }
    }

    private func updateCloudsAndWeather(dt: Float) {
        for c in cloudNodes {
            c.position.x += dt * 0.45
            if c.position.x > 18 { c.position.x = -18 }
        }
        guard weather != .clear && activeDimension == .overworld else { return }
        let speedY: Float = (weather == .snowstorm) ? -2.4 : -9.5
        let driftX: Float = (weather == .snowstorm) ? 1.1 : -0.35
        for n in weatherNodes {
            n.position.y += speedY * dt
            n.position.x += driftX * dt
            if n.position.y < 1.5 {
                n.position = SCNVector3(playerPos.x + Float.random(in: -12...12), playerPos.y + Float.random(in: 7...13), playerPos.z + Float.random(in: -12...12))
            }
        }
    }

    private func updatePressurePlates() {
        var nowActive: Set<BlockCoord> = []
        let pCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 1.2)), z: Int(floor(playerPos.z)))
        for offset in [BlockCoord(x: 0, y: 0, z: 0), BlockCoord(x: 0, y: 1, z: 0)] {
            let test = BlockCoord(x: pCoord.x + offset.x, y: pCoord.y + offset.y, z: pCoord.z + offset.z)
            if blocks[test] == .pressurePlate { nowActive.insert(test) }
        }
        for mob in mobs {
            let mCoord = BlockCoord(x: Int(floor(mob.position.x)), y: Int(floor(mob.position.y)), z: Int(floor(mob.position.z)))
            if blocks[mCoord] == .pressurePlate { nowActive.insert(mCoord) }
        }
        if nowActive != activePressurePlates {
            for plate in activePressurePlates.subtracting(nowActive) {
                blockNodes[plate]?.scale = SCNVector3(1.0, 1.0, 1.0)
                propagateRedstone(around: plate)
            }
            for plate in nowActive.subtracting(activePressurePlates) {
                blockNodes[plate]?.scale = SCNVector3(1.0, 0.4, 1.0)
                SoundEngine.shared.play(.piston)
                propagateRedstone(around: plate)
            }
            activePressurePlates = nowActive
        }
    }

    private func updateFurnace(dt: Double) {
        if furnaceBurnRemaining > 0 {
            furnaceBurnRemaining = max(0, furnaceBurnRemaining - dt)
        }
        if queuedSmeltCount > 0 && furnaceBurnRemaining > 0 {
            furnaceSmeltProgress += dt / 3.0
            if furnaceSmeltProgress >= 1.0 {
                furnaceSmeltProgress = 0.0
                queuedSmeltCount -= 1
                _ = addItems(1, of: .glass)
                SoundEngine.shared.play(.pickup)
                statusMessage = "Furnace smelted 1 Glass"
            }
        } else if queuedSmeltCount == 0 {
            furnaceSmeltProgress = 0.0
        }
    }

    private func updateBoatMotion(dt: Float) {
        guard isInBoat, let boat = boatNode else { return }
        let turnRate: Float = 1.65
        let accel: Float = 5.4
        let maxSpeed: Float = 6.2
        let drag: Float = 0.92
        boat.eulerAngles.y -= moveInput.x * turnRate * dt
        yaw = boat.eulerAngles.y
        pitch = -0.06
        if abs(moveInput.y) > 0.05 {
            boatSpeed += moveInput.y * accel * dt
            boatSpeed = max(-maxSpeed * 0.55, min(maxSpeed, boatSpeed))
        } else {
            boatSpeed *= pow(drag, dt * 20)
            if abs(boatSpeed) < 0.04 { boatSpeed = 0 }
        }
        let forward = SIMD3<Float>(-sin(boat.eulerAngles.y), 0, -cos(boat.eulerAngles.y))
        let delta = forward * boatSpeed * dt
        let nextX = boat.position.x + delta.x
        let nextZ = boat.position.z + delta.z
        let probeCoord = BlockCoord(x: Int(floor(nextX)), y: Int(floor(boat.position.y - 0.15)), z: Int(floor(nextZ)))
        if let blockAtNext = blocks[probeCoord], blockAtNext != .water && !blockAtNext.isPassable {
            boatSpeed = 0
        } else {
            let movedDistance = sqrt(delta.x * delta.x + delta.z * delta.z)
            boat.position.x = nextX
            boat.position.z = nextZ
            boatTravelDistance += movedDistance
            if boatTravelDistance >= 100 { unlockAchievement("sailor") }
            if movedDistance > 0.001 {
                boatAutosaveTimer += dt
                if boatAutosaveTimer >= 3.0 {
                    boatAutosaveTimer = 0
                    saveWorld()
                }
            }
        }
        let waterCoord = BlockCoord(x: Int(floor(boat.position.x)), y: Int(floor(boat.position.y - 0.65)), z: Int(floor(boat.position.z)))
        if blocks[waterCoord] == .water {
            boat.position.y = Float(waterCoord.y) + 1.06 + sin(CACurrentMediaTime() * 3.0) * 0.03
        } else {
            boatSpeed = 0
        }
        let paddleAngle = sin(CACurrentMediaTime() * 8.0) * min(0.55, abs(boatSpeed) * 0.14)
        for (index, paddle) in boatPaddles.enumerated() {
            paddle.eulerAngles.y = (index == 0 ? 1 : -1) * paddleAngle
        }
        playerPos = SIMD3<Float>(boat.position.x, boat.position.y + 1.65, boat.position.z)
        verticalVelocity = 0
    }

    private func updatePlayerPhysics(dt: Float) {
        if isInBoat { return }
        let speedBoostActive = (activePotionEffects[.speed] ?? 0) > 0
        let sprintMultiplier: Float = (isSprinting && stamina > 1 && moveInput.y > 0.1) ? 1.48 : 1.0
        let speed: Float = (isUnderwater ? 3.2 : 6.0) * sprintMultiplier * (speedBoostActive ? 1.32 : 1.0)
        let forwardXZ = simd_normalize(SIMD2<Float>(-sin(yaw), -cos(yaw)))
        let rightXZ = simd_normalize(SIMD2<Float>(cos(yaw), -sin(yaw)))
        let wishXZ = forwardXZ * moveInput.y + rightXZ * moveInput.x
        let wishLen = simd_length(wishXZ)
        let stepXZ = (wishLen > 0.001) ? (wishXZ / wishLen) * speed * dt : SIMD2<Float>.zero

        if isSprinting && wishLen > 0.05 && !isUnderwater {
            stamina = max(0, stamina - Double(20 * dt))
            staminaRecoveryDelay = 1.1
            if stamina <= 0.1 { isSprinting = false }
        } else {
            if staminaRecoveryDelay > 0 {
                staminaRecoveryDelay = max(0, staminaRecoveryDelay - dt)
            } else {
                stamina = min(100, stamina + Double(15 * dt))
            }
        }

        let r: Float = 0.28
        let feetY0 = Int(floor(playerPos.y - 1.45))
        let feetY1 = Int(floor(playerPos.y - 0.6))

        let nextX = playerPos.x + stepXZ.x
        let canMoveX = !hasSolidBlock(atX: Int(floor(nextX + (stepXZ.x >= 0 ? r : -r))), y: feetY0, z: Int(floor(playerPos.z)))
            && !hasSolidBlock(atX: Int(floor(nextX + (stepXZ.x >= 0 ? r : -r))), y: feetY1, z: Int(floor(playerPos.z)))
        if canMoveX { playerPos.x = nextX }

        let nextZ = playerPos.z + stepXZ.y
        let canMoveZ = !hasSolidBlock(atX: Int(floor(playerPos.x)), y: feetY0, z: Int(floor(nextZ + (stepXZ.y >= 0 ? r : -r))))
            && !hasSolidBlock(atX: Int(floor(playerPos.x)), y: feetY1, z: Int(floor(nextZ + (stepXZ.y >= 0 ? r : -r))))
        if canMoveZ { playerPos.z = nextZ }

        let eyeCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y + 0.05)), z: Int(floor(playerPos.z)))
        let bodyCoord = BlockCoord(x: Int(floor(playerPos.x)), y: Int(floor(playerPos.y - 0.7)), z: Int(floor(playerPos.z)))
        isUnderwater = (blocks[eyeCoord] == .water)
        let inWater = (blocks[eyeCoord] == .water || blocks[bodyCoord] == .water)

        if inWater {
            fallStartY = nil
            verticalVelocity = max(-2.2, verticalVelocity - 6.5 * dt)
        } else {
            verticalVelocity -= 18.5 * dt
        }
        playerPos.y += verticalVelocity * dt

        if verticalVelocity < 0 && fallStartY == nil && !inWater {
            fallStartY = playerPos.y
        }

        let px = Int(floor(playerPos.x))
        let pz = Int(floor(playerPos.z))
        let groundCheckY = Int(floor(playerPos.y - 1.5))
        let landed = hasSolidBlock(atX: px, y: groundCheckY, z: pz)

        if landed && verticalVelocity < 0 {
            if let startY = fallStartY {
                let fallDistance = startY - playerPos.y
                if fallDistance > 4.2 && gameMode == .survival {
                    let dmg = Int(min(12, floor((fallDistance - 3.5) * 2.0)))
                    if dmg > 0 { applyPlayerDamage(dmg, source: "Fall") }
                }
            }
            fallStartY = nil
            playerPos.y = Float(groundCheckY + 1) + 1.5
            verticalVelocity = 0.0
        }

        let footBlock = blocks[BlockCoord(x: px, y: groundCheckY, z: pz)]
        let atBlock = blocks[BlockCoord(x: px, y: Int(floor(playerPos.y - 0.9)), z: pz)]
        let fireImmune = (activePotionEffects[.fireResistance] ?? 0) > 0
        if (footBlock == .magma || atBlock == .magma) && gameMode == .survival && !fireImmune {
            hazardTimer += dt
            if hazardTimer >= 0.8 {
                hazardTimer = 0
                applyPlayerDamage(2, source: "Magma")
            }
        } else if activeDimension == .hell && playerPos.y < 1.3 && gameMode == .survival && !fireImmune {
            hazardTimer += dt
            if hazardTimer >= 0.7 {
                hazardTimer = 0
                applyPlayerDamage(3, source: "Lava crust")
            }
        } else {
            hazardTimer = 0
        }

        if gameMode == .survival && wishLen > 0.1 {
            hungerDrainTimer += dt
            if hungerDrainTimer >= 9.0 {
                hungerDrainTimer = 0
                if hunger > 0 { hunger = max(0, hunger - 1) }
            }
        }

        if playerPos.y < -8.0 {
            statusMessage = "Fell into the void — Respawning"
            respawnPlayer()
        }
    }

    private func updateActiveEffectsAndRegeneration(dt: Float) {
        var expired: [PotionKind] = []
        for (potion, remaining) in activePotionEffects {
            let next = remaining - dt
            if next <= 0 {
                expired.append(potion)
            } else {
                activePotionEffects[potion] = next
            }
        }
        for potion in expired {
            activePotionEffects.removeValue(forKey: potion)
        }
        if miningFatigueRemaining > 0 {
            miningFatigueRemaining = max(0, miningFatigueRemaining - dt)
        }
        if dolphinGuideAchievementTimer > 0 {
            dolphinGuideAchievementTimer = max(0, dolphinGuideAchievementTimer - dt)
            if let dolphin = mobs.first(where: { $0.kind == .dolphin && simd_distance($0.position, playerPos) < 16 }) {
                unlockAchievement("dolphin_friend")
                dolphinGuideAchievementTimer = 0
                statusMessage = "Dolphin guided you to treasure!"
                saveWorld()
            }
        }
        guard gameMode == .survival, health > 0 else { return }

        if (activePotionEffects[.regeneration] ?? 0) > 0 && health < 20 {
            regenerationTickTimer += dt
            if regenerationTickTimer >= 2.2 {
                regenerationTickTimer = 0
                health = min(20, health + 2)
            }
        } else {
            regenerationTickTimer = 0
        }

        if isUnderwater && (activePotionEffects[.waterBreathing] ?? 0) <= 0 {
            oxygenTickTimer += dt
            if oxygenTickTimer >= 1.0 {
                oxygenTickTimer = 0
                oxygen = max(0, oxygen - 1)
            }
            if oxygen == 0 {
                drowningTimer += dt
                if drowningTimer >= 1.5 {
                    drowningTimer = 0
                    applyPlayerDamage(2, source: "Drowning")
                }
            }
        } else {
            oxygenTickTimer = 0
            drowningTimer = 0
            if oxygen < 10 { oxygen = min(10, oxygen + 1) }
        }

        if hunger >= 18 && health < 20 {
            naturalRegenerationTimer += dt
            starvationTimer = 0
            if naturalRegenerationTimer >= 4.0 {
                naturalRegenerationTimer = 0
                health = min(20, health + 1)
            }
        } else if hunger == 0 {
            naturalRegenerationTimer = 0
            starvationTimer += dt
            if starvationTimer >= 4.0 && health > 1 {
                starvationTimer = 0
                health = max(1, health - 1)
                statusMessage = "Starving — eat food to restore hunger"
            }
        } else {
            naturalRegenerationTimer = 0
            starvationTimer = 0
        }
    }

    private func villageProfession(near position: SIMD3<Float>) -> VillagerProfession {
        let index = Int(abs(position.x.rounded() * 3 + position.z.rounded() * 7)) % VillagerProfession.allCases.count
        return VillagerProfession.allCases[index]
    }

    private func updateMobs(dt: Float) {
        let isNight = (activeDimension == .overworld && nightProgress > 0.55)
        let isDaylight = (activeDimension == .overworld && nightProgress <= 0.55)

        for mob in mobs {
            if mob.loveTimer > 0 { mob.loveTimer = max(0, mob.loveTimer - dt) }
            if mob.breedCooldown > 0 { mob.breedCooldown = max(0, mob.breedCooldown - dt) }
            if mob.isBaby {
                mob.ageTimer = max(0, mob.ageTimer - dt)
                if mob.ageTimer <= 0 {
                    mob.isBaby = false
                    mob.node.scale = SCNVector3(1.0, 1.0, 1.0)
                }
            }
            if mob.kind == .villager && mob.isBaby {
                villagerGrowthTimer += dt
                if villagerGrowthTimer >= 60.0 {
                    villagerGrowthTimer = 0.0
                    mob.isBaby = false
                    mob.node.scale = SCNVector3(1.0, 1.0, 1.0)
                    statusMessage = "A young Villager has grown up!"
                    saveWorld()
                }
            }

            if simd_length(mob.knockback) > 0.05 {
                mob.position.x += mob.knockback.x * dt
                mob.position.z += mob.knockback.y * dt
                mob.knockback *= pow(0.08, dt)
            }

            if mob.kind == .enderDragon {
                mob.dragonPhaseTimer -= dt
                if mob.dragonPhaseTimer <= 0 {
                    switch mob.dragonPhase {
                    case .circling: mob.dragonPhase = .diving; mob.dragonPhaseTimer = 2.6
                    case .diving: mob.dragonPhase = .perching; mob.dragonPhaseTimer = 2.2
                    case .perching: mob.dragonPhase = .circling; mob.dragonPhaseTimer = 4.0
                    }
                }

                let t = Float(CACurrentMediaTime()) * 0.65
                switch mob.dragonPhase {
                case .circling:
                    let orbitRadius: Float = 8.5
                    let targetX = cos(t) * orbitRadius
                    let targetZ = sin(t) * orbitRadius
                    let dx = targetX - mob.position.x
                    let dz = targetZ - mob.position.z
                    mob.position.x += dx * min(1.0, dt * 2.2)
                    mob.position.z += dz * min(1.0, dt * 2.2)
                    mob.position.y = 8.5 + sin(t * 2.0) * 1.1
                    mob.yaw = atan2(dx, dz)
                case .diving:
                    let toPlayer = playerPos - mob.position
                    let dist = max(0.1, simd_length(toPlayer))
                    mob.position += (toPlayer / dist) * 5.2 * dt
                    mob.yaw = atan2(toPlayer.x, toPlayer.z)
                case .perching:
                    let perchX: Float = 0.5
                    let perchZ: Float = 0.5
                    let perchY = Float(highestSolidY(atX: 0, z: 0)) + 2.2
                    mob.position.x += (perchX - mob.position.x) * min(1.0, dt * 2.5)
                    mob.position.z += (perchZ - mob.position.z) * min(1.0, dt * 2.5)
                    mob.position.y += (perchY - mob.position.y) * min(1.0, dt * 2.5)
                    mob.yaw = atan2(playerPos.x - mob.position.x, playerPos.z - mob.position.z)
                }

                let crystalNear = blocks.first(where: { $0.value == .endCrystal && simd_distance($0.key.scnVector.simd, mob.position) < 6.0 })
                if crystalNear != nil && mob.hp < 28 {
                    mob.dragonHealTimer += dt
                    if mob.dragonHealTimer >= 1.5 {
                        mob.dragonHealTimer = 0
                        mob.hp = min(28, mob.hp + 2)
                        spawnParticles(at: mob.position, color: UIColor.magenta, count: 4)
                    }
                }

                if simd_distance(mob.position, playerPos) < 2.4 && gameMode == .survival {
                    mob.attackCooldown -= dt
                    if mob.attackCooldown <= 0 {
                        mob.attackCooldown = 1.4
                        applyPlayerDamage(4, source: "Ender Dragon")
                    }
                }
                mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                continue
            }

            if mob.kind == .blaze {
                let toPlayer = playerPos - mob.position
                let dist = simd_length(toPlayer)
                let hoverY = Float(highestSolidY(atX: Int(floor(mob.position.x)), z: Int(floor(mob.position.z)))) + 2.2 + sin(Float(CACurrentMediaTime()) * 3.0) * 0.35
                mob.position.y += (hoverY - mob.position.y) * min(1.0, dt * 3.0)
                if dist < 13.0 {
                    let dirXZ = simd_normalize(SIMD2<Float>(toPlayer.x, toPlayer.z) + SIMD2<Float>(0.001, 0.001))
                    if dist > 5.0 {
                        mob.position.x += dirXZ.x * 2.1 * dt
                        mob.position.z += dirXZ.y * 2.1 * dt
                    }
                    mob.yaw = atan2(dirXZ.x, dirXZ.y)
                    mob.attackCooldown -= dt
                    if mob.attackCooldown <= 0 {
                        mob.attackCooldown = 2.0
                        spawnArrow(from: mob.position + SIMD3<Float>(0, 0.4, 0), target: playerPos, damage: 3, color: UIColor.orange)
                    }
                }
                mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                continue
            }

            if [.fish, .dolphin, .turtle, .guardian].contains(mob.kind) {
                let speed: Float = mob.kind == .fish ? 1.8 : (mob.kind == .dolphin ? 3.4 : (mob.kind == .guardian ? 2.1 : 1.1))
                var swimDir = SIMD2<Float>(sin(mob.yaw), cos(mob.yaw))
                if mob.kind == .dolphin && dolphinGuideAchievementTimer > 0, let target = treasureCompassTarget {
                    let delta = SIMD2<Float>(Float(target.x) + 0.5 - mob.position.x, Float(target.z) + 0.5 - mob.position.z)
                    if simd_length(delta) > 0.4 {
                        swimDir = simd_normalize(delta)
                        mob.yaw = atan2(swimDir.x, swimDir.y)
                    }
                } else {
                    mob.wanderTimer -= dt
                    if mob.wanderTimer <= 0 {
                        mob.wanderTimer = Float.random(in: 1.0...2.4)
                        mob.yaw = Float.random(in: 0...(Float.pi * 2))
                        swimDir = SIMD2<Float>(sin(mob.yaw), cos(mob.yaw))
                    }
                }
                let nextPos = mob.position + SIMD3<Float>(swimDir.x * speed * dt, 0, swimDir.y * speed * dt)
                let probe = BlockCoord(x: Int(floor(nextPos.x)), y: Int(floor(mob.position.y)), z: Int(floor(nextPos.z)))
                if blocks[probe] == .water {
                    mob.position.x = nextPos.x
                    mob.position.z = nextPos.z
                } else {
                    mob.yaw += Float.pi * 0.65
                }
                let waterColumnY = Int(floor(mob.position.y))
                if blocks[BlockCoord(x: Int(floor(mob.position.x)), y: waterColumnY, z: Int(floor(mob.position.z)))] == .water {
                    mob.position.y = Float(waterColumnY) + 0.35 + sin(Float(CACurrentMediaTime()) * 3.0 + Float(mob.wanderTimer)) * 0.08
                }
                if mob.kind == .guardian && gameMode == .survival {
                    let dist = simd_distance(mob.position, playerPos)
                    let range: Float = mob.isElderGuardian ? 11.5 : 8.5
                    if dist < range {
                        mob.attackCooldown -= dt
                        if mob.attackCooldown <= 0 {
                            mob.attackCooldown = mob.isElderGuardian ? 1.85 : 2.1
                            applyPlayerDamage(mob.isElderGuardian ? 5 : 3, source: mob.isElderGuardian ? "Elder Guardian" : "Guardian")
                            if mob.isElderGuardian {
                                miningFatigueRemaining = 6.0
                                statusMessage = "Elder Guardian mining fatigue applied"
                            }
                        }
                    }
                }
                mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                continue
            }

            if [.wolf, .fox, .bear].contains(mob.kind) && mob.isTamed {
                if mob.hp < 12 {
                    mob.petRegenTimer += dt
                    if mob.petRegenTimer >= 2.2 {
                        mob.petRegenTimer = 0
                        mob.hp = min(12, mob.hp + 1)
                    }
                }
                if mob.isSitting {
                    mob.node.position = SCNVector3(mob.position.x, mob.position.y - 0.14, mob.position.z)
                    mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                    continue
                }
                if mob.isGuarding, let gp = mob.guardPosition {
                    if let targetHostile = mobs.first(where: { [.zombie, .skeleton, .creeper, .enderman, .spider, .blaze].contains($0.kind) && simd_distance($0.position, gp) < 11.0 }) {
                        let toHostile = targetHostile.position - mob.position
                        let dist = simd_length(toHostile)
                        if dist > 1.3 {
                            let dir = simd_normalize(SIMD2<Float>(toHostile.x, toHostile.z))
                            mob.position.x += dir.x * 3.6 * dt; mob.position.z += dir.y * 3.6 * dt; mob.yaw = atan2(dir.x, dir.y)
                        } else {
                            mob.attackCooldown -= dt
                            if mob.attackCooldown <= 0 {
                                mob.attackCooldown = 0.85; targetHostile.hp -= 4; SoundEngine.shared.play(.hitMob)
                                if targetHostile.hp <= 0 { targetHostile.node.removeFromParentNode(); mobs.removeAll { $0.id == targetHostile.id } }
                            }
                        }
                    } else {
                        let delta = gp - mob.position
                        let dist = simd_length(SIMD2<Float>(delta.x, delta.z))
                        if dist > 0.7 {
                            let dir = simd_normalize(SIMD2<Float>(delta.x, delta.z))
                            mob.position.x += dir.x * 2.5 * dt; mob.position.z += dir.y * 2.5 * dt; mob.yaw = atan2(dir.x, dir.y)
                        }
                    }
                    let gy = Float(highestSolidY(atX: Int(floor(mob.position.x)), z: Int(floor(mob.position.z))))
                    mob.position.y = gy + 1.0
                    mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                    mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                    continue
                }
                if let targetHostile = mobs.first(where: { [.zombie, .skeleton, .creeper, .enderman, .spider, .blaze].contains($0.kind) && simd_distance($0.position, playerPos) < 12.0 }) {
                    let toHostile = targetHostile.position - mob.position
                    let dist = simd_length(toHostile)
                    if dist > 1.3 {
                        let dir = simd_normalize(SIMD2<Float>(toHostile.x, toHostile.z))
                        mob.position.x += dir.x * 3.8 * dt; mob.position.z += dir.y * 3.8 * dt; mob.yaw = atan2(dir.x, dir.y)
                    } else {
                        mob.attackCooldown -= dt
                        if mob.attackCooldown <= 0 {
                            mob.attackCooldown = 0.85; targetHostile.hp -= 4; SoundEngine.shared.play(.hitMob)
                            if targetHostile.hp <= 0 { targetHostile.node.removeFromParentNode(); mobs.removeAll { $0.id == targetHostile.id } }
                        }
                    }
                } else {
                    let delta = playerPos - mob.position
                    let dist = simd_length(SIMD2<Float>(delta.x, delta.z))
                    if dist > 3.2 {
                        let dir = simd_normalize(SIMD2<Float>(delta.x, delta.z))
                        mob.position.x += dir.x * 3.4 * dt; mob.position.z += dir.y * 3.4 * dt; mob.yaw = atan2(dir.x, dir.y)
                    }
                }
                let gy = Float(highestSolidY(atX: Int(floor(mob.position.x)), z: Int(floor(mob.position.z))))
                mob.position.y = gy + 1.0
                mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)
                continue
            }

            if mob.kind == .villager {
                if mob.raidDamageCooldown > 0 { mob.raidDamageCooldown = max(0, mob.raidDamageCooldown - dt) }
                if let raider = mobs.first(where: { [.zombie, .skeleton, .creeper, .spider].contains($0.kind) && simd_distance($0.position, mob.position) < 9.0 }) {
                    let away = mob.position - raider.position
                    let dist = simd_length(SIMD2<Float>(away.x, away.z))
                    if dist > 0.1 {
                        let dir = simd_normalize(SIMD2<Float>(away.x, away.z))
                        mob.position.x += dir.x * 2.5 * dt
                        mob.position.z += dir.y * 2.5 * dt
                        mob.yaw = atan2(dir.x, dir.y)
                    }
                    if simd_distance(raider.position, mob.position) < 1.5 && mob.raidDamageCooldown <= 0 {
                        mob.raidDamageCooldown = 1.6
                        mob.hp -= 2
                        if mob.hp <= 0 {
                            mob.node.removeFromParentNode()
                            mobs.removeAll { $0.id == mob.id }
                            statusMessage = "A \(mob.profession.rawValue) Villager fell in a raid!"
                            continue
                        }
                    }
                } else if isNight {
                    if mob.homePosition == nil || mob.workstationPosition == nil { assignVillagerDestinations(mob) }
                    if let home = mob.homePosition {
                        let arrivedHome = advanceVillagerAlongPath(mob, toward: home, speed: 1.75, dt: dt)
                        mob.isSleeping = arrivedHome
                    }
                } else {
                    mob.isSleeping = false
                    if mob.homePosition == nil || mob.workstationPosition == nil { assignVillagerDestinations(mob) }
                    if let station = mob.workstationPosition {
                        let arrivedWork = advanceVillagerAlongPath(mob, toward: station, speed: 1.55, dt: dt)
                        if arrivedWork && mob.profession == .farmer {
                            mob.farmWorkTimer += dt
                            if mob.farmWorkTimer >= 6.0 {
                                mob.farmWorkTimer = 0.0
                                foodInventory[.wheat, default: 0] = min(64, foodCount(for: .wheat) + 1)
                            }
                        }
                    }
                }
                let gy = Float(highestSolidY(atX: Int(floor(mob.position.x)), z: Int(floor(mob.position.z))))
                mob.position.y = gy + (mob.isSleeping ? 0.65 : 1.0)
                mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
                mob.node.eulerAngles = SCNVector3(mob.isSleeping ? .pi / 2.4 : 0, mob.yaw, 0)
                continue
            }

            if mob.kind == .ironGolem {
                if let threat = mobs.first(where: { [.zombie, .skeleton, .creeper, .enderman, .spider].contains($0.kind) && simd_distance($0.position, mob.position) < 9.0 }) {
                    let delta = threat.position - mob.position
                    let dist = simd_length(SIMD2<Float>(delta.x, delta.z))
                    if dist > 1.4 {
                        let dir = simd_normalize(SIMD2<Float>(delta.x, delta.z))
                        mob.position.x += dir.x * 2.2 * dt
                        mob.position.z += dir.y * 2.2 * dt
                        mob.yaw = atan2(dir.x, dir.y)
                    } else {
                        mob.attackCooldown -= dt
                        if mob.attackCooldown <= 0 {
                            mob.attackCooldown = 1.0
                            threat.hp -= 6
                            SoundEngine.shared.play(.hitMob)
                            if threat.hp <= 0 {
                                threat.node.removeFromParentNode()
                                mobs.removeAll { $0.id == threat.id }
                            }
                        }
                    }
                }
            } else {
                let isHostile = [.zombie, .skeleton, .creeper, .enderman, .spider].contains(mob.kind)
                let distToPlayer = simd_distance(mob.position, playerPos)
                if isHostile && distToPlayer < 11.0 {
                    let delta = playerPos - mob.position
                    let dirXZ = simd_normalize(SIMD2<Float>(delta.x, delta.z) + SIMD2<Float>(0.001, 0.001))
                    mob.position.x += dirXZ.x * 1.9 * dt
                    mob.position.z += dirXZ.y * 1.9 * dt
                    mob.yaw = atan2(dirXZ.x, dirXZ.y)

                    if mob.kind == .skeleton {
                        mob.attackCooldown -= dt
                        if mob.attackCooldown <= 0 {
                            mob.attackCooldown = 2.2
                            spawnArrow(from: mob.position + SIMD3<Float>(0, 0.3, 0), target: playerPos)
                        }
                    } else if mob.kind == .creeper && distToPlayer < 2.2 {
                        mob.isCreeperPrimed = true
                        mob.creeperFuseRemaining -= dt
                        let pulse = 1.0 + CGFloat(sin(CACurrentMediaTime() * 28.0) * 0.14)
                        mob.node.scale = SCNVector3(pulse, pulse, pulse)
                        if mob.creeperFuseRemaining <= 0 {
                            let c = BlockCoord(x: Int(floor(mob.position.x)), y: Int(floor(mob.position.y)), z: Int(floor(mob.position.z)))
                            mob.node.removeFromParentNode()
                            mobs.removeAll { $0.id == mob.id }
                            triggerExplosion(at: c, radius: 2)
                            continue
                        }
                    } else if distToPlayer < 1.55 && gameMode == .survival {
                        mob.attackCooldown -= dt
                        if mob.attackCooldown <= 0 {
                            mob.attackCooldown = 1.35
                            let dmg = (mob.kind == .enderman) ? 3 : 2
                            applyPlayerDamage(dmg, source: mob.kind.rawValue)
                        }
                    }
                } else {
                    mob.wanderTimer -= dt
                    if mob.wanderTimer <= 0 {
                        mob.wanderTimer = Float.random(in: 1.2...2.8)
                        mob.yaw = Float.random(in: 0...(Float.pi * 2))
                    }
                    let speed: Float = (mob.kind == .bear) ? 1.5 : 1.1
                    mob.position.x += sin(mob.yaw) * speed * dt
                    mob.position.z += cos(mob.yaw) * speed * dt
                }
            }

            let gy = Float(highestSolidY(atX: Int(floor(mob.position.x)), z: Int(floor(mob.position.z))))
            mob.position.y = gy + 1.0
            mob.node.position = SCNVector3(mob.position.x, mob.position.y, mob.position.z)
            mob.node.eulerAngles = SCNVector3(0, mob.yaw, 0)

            if isDaylight && [.zombie, .skeleton].contains(mob.kind) && simd_distance(mob.position, playerPos) > 14.0 {
                mob.node.removeFromParentNode()
                mobs.removeAll { $0.id == mob.id }
            }
        }
    }

    private func updateArrows(dt: Float) {
        for idx in arrows.indices.reversed() {
            let a = arrows[idx]
            a.life -= dt
            a.velocity.y -= 9.8 * dt
            a.position += a.velocity * dt
            a.node.position = SCNVector3(a.position.x, a.position.y, a.position.z)

            let hitCoord = BlockCoord(x: Int(floor(a.position.x)), y: Int(floor(a.position.y)), z: Int(floor(a.position.z)))
            let hitSolid = blocks[hitCoord] != nil && !(blocks[hitCoord]?.isPassable ?? true)
            let hitPlayer = simd_distance(a.position, playerPos) < 0.85

            if hitPlayer && gameMode == .survival {
                applyPlayerDamage(a.damage, source: "Arrow")
            }

            if a.life <= 0 || hitSolid || hitPlayer {
                a.node.removeFromParentNode()
                arrows.remove(at: idx)
            }
        }
    }

    private func updateDroppedItems(dt: Float) {
        for idx in droppedItems.indices.reversed() {
            let d = droppedItems[idx]
            d.bobPhase += dt * 3.0
            d.node.eulerAngles.y += dt * 1.8
            d.node.position = SCNVector3(d.position.x, d.position.y + sin(d.bobPhase) * 0.08, d.position.z)

            if simd_distance(d.position, playerPos) < 1.85 {
                let accepted = addItems(1, of: d.blockType)
                if accepted > 0 {
                    SoundEngine.shared.play(.pickup)
                    statusMessage = "Picked up \(d.blockType.rawValue)"
                }
                d.node.removeFromParentNode()
                droppedItems.remove(at: idx)
            }
        }
    }

    private func updateExperienceOrbs(dt: Float) {
        for index in experienceOrbs.indices.reversed() {
            let orb = experienceOrbs[index]
            orb.bobPhase += dt * 3.4
            orb.node.position = SCNVector3(orb.position.x, orb.position.y + sin(orb.bobPhase) * 0.08, orb.position.z)
            if simd_distance(orb.position, playerPos) < 2.2 {
                experiencePoints += orb.value
                SoundEngine.shared.play(.pickup)
                statusMessage = "+\(orb.value) XP (Level \(experienceLevel))"
                orb.node.removeFromParentNode()
                experienceOrbs.remove(at: index)
            }
        }
    }

    private func updateCameraTransform() {
        let lookDir = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        let normDir = simd_normalize(lookDir)

        if cameraMode == .overview {
            avatarNode.isHidden = false
            avatarNode.position = SCNVector3(playerPos.x, playerPos.y, playerPos.z)
            avatarNode.eulerAngles = SCNVector3(0, yaw, 0)
            let camPos = playerPos - normDir * 6.5 + SIMD3<Float>(0, 2.6, 0)
            cameraNode.position = SCNVector3(camPos.x, camPos.y, camPos.z)
            cameraNode.look(at: SCNVector3(playerPos.x + normDir.x * 2.0, playerPos.y + normDir.y * 1.5, playerPos.z + normDir.z * 2.0))
        } else {
            avatarNode.isHidden = true
            cameraNode.position = SCNVector3(playerPos.x, playerPos.y, playerPos.z)
            cameraNode.look(at: SCNVector3(playerPos.x + normDir.x, playerPos.y + normDir.y, playerPos.z + normDir.z))
        }

        if let target = targetedBlock(from: nil, in: nil) {
            highlightNode.isHidden = false
            highlightNode.position = target.scnVector
        } else {
            highlightNode.isHidden = true
        }
    }

    func saveWorld() {
        let entries: [SavedVoxelEntry] = blocks.compactMap { coord, type in
            guard modifiedCoords.contains(coord) else { return nil }
            return SavedVoxelEntry(x: coord.x, y: coord.y, z: coord.z, type: type)
        }
        let cropEntries: [CropSaveEntry] = cropStages.map { coord, st in
            CropSaveEntry(x: coord.x, y: coord.y, z: coord.z, stage: st)
        }
        let villagerEntries: [SavedVillagerEntry] = mobs.filter { $0.kind == .villager }.map { mob in
            SavedVillagerEntry(id: mob.id, x: mob.position.x, y: mob.position.y, z: mob.position.z,
                               yaw: mob.yaw, hp: mob.hp, profession: mob.profession.rawValue,
                               homeX: mob.homePosition?.x, homeY: mob.homePosition?.y, homeZ: mob.homePosition?.z,
                               workX: mob.workstationPosition?.x, workY: mob.workstationPosition?.y, workZ: mob.workstationPosition?.z,
                               isBaby: mob.isBaby, ageTimer: mob.ageTimer)
        }
        let petEntries: [SavedPetEntry] = mobs.filter { [.wolf, .fox, .bear].contains($0.kind) && $0.isTamed }.map { mob in
            SavedPetEntry(id: mob.id, kind: mob.kind.rawValue, x: mob.position.x, y: mob.position.y, z: mob.position.z,
                          yaw: mob.yaw, hp: mob.hp, isSitting: mob.isSitting, isGuarding: mob.isGuarding,
                          guardX: mob.guardPosition?.x, guardY: mob.guardPosition?.y, guardZ: mob.guardPosition?.z)
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
            hotbarSlots: hotbarSlots.map(\.rawValue),
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
            villagers: villagerEntries,
            potionInventory: Dictionary(uniqueKeysWithValues: potionInventory.map { ($0.key.rawValue, $0.value) }),
            unlockedAchievements: Array(unlockedAchievements),
            defeatedHostileCount: defeatedHostileCount,
            activePotionEffects: Dictionary(uniqueKeysWithValues: activePotionEffects.map { ($0.key.rawValue, $0.value) }),
            boatCount: boatCount,
            deployedBoat: boatNode.map { SavedBoatState(x: $0.position.x, y: $0.position.y, z: $0.position.z, yaw: $0.eulerAngles.y) },
            discoveredBiomes: Array(discoveredBiomes),
            pets: petEntries
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }

    private func sendPlayerState() {
        lanManager.send([
            "type": "pos",
            "x": playerPos.x,
            "y": playerPos.y - 1.5,
            "z": playerPos.z,
            "yaw": yaw
        ])
    }

    private func sendBlockDelta(coord: BlockCoord, type: BlockType?) {
        lanManager.send([
            "type": "block",
            "x": coord.x,
            "y": coord.y,
            "z": coord.z,
            "block": type?.rawValue ?? ""
        ])
    }

    private func handleNetworkData(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = obj["type"] as? String else { return }

        if kind == "pos",
           let x = obj["x"] as? Double,
           let y = obj["y"] as? Double,
           let z = obj["z"] as? Double,
           let ryaw = obj["yaw"] as? Double {
            remotePeerNode.isHidden = false
            remotePeerNode.position = SCNVector3(Float(x), Float(y), Float(z))
            remotePeerNode.eulerAngles = SCNVector3(0, Float(ryaw), 0)
        } else if kind == "block",
                  let x = obj["x"] as? Int,
                  let y = obj["y"] as? Int,
                  let z = obj["z"] as? Int,
                  let raw = obj["block"] as? String {
            let coord = BlockCoord(x: x, y: y, z: z)
            if raw.isEmpty {
                removeBlockInternal(at: coord, markModified: true)
            } else if let bType = BlockType(rawValue: raw) {
                setBlockInternal(coord: coord, type: bType, markModified: true)
            }
        }
    }
}

private extension SCNVector3 {
    var simd: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

// MARK: - SceneKit Touch & Gesture View

struct VoxelSceneView: UIViewRepresentable {
    @ObservedObject var controller: VoxelWorldController

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.pointOfView = controller.cameraNode
        view.delegate = controller
        view.isPlaying = true
        view.rendersContinuously = true
        view.antialiasingMode = .none
        view.allowsCameraControl = false
        view.backgroundColor = UIColor(red: 0.53, green: 0.78, blue: 0.98, alpha: 1.0)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.42
        view.addGestureRecognizer(longPress)

        context.coordinator.sceneView = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.pointOfView = controller.cameraNode
    }

    final class Coordinator: NSObject {
        let controller: VoxelWorldController
        weak var sceneView: SCNView?
        private var lastPanPoint: CGPoint?

        init(controller: VoxelWorldController) { self.controller = controller }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let pt = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began: lastPanPoint = pt
            case .changed:
                if let prev = lastPanPoint {
                    controller.rotateCamera(deltaX: Float(pt.x - prev.x), deltaY: Float(pt.y - prev.y))
                }
                lastPanPoint = pt
            default: lastPanPoint = nil
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let pt = gesture.location(in: sceneView)
            controller.handleWorldTap(at: pt, in: sceneView!)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            let pt = gesture.location(in: sceneView)
            let prevTool = controller.activeTool
            controller.activeTool = .breakBlock
            _ = controller.performPrimaryAction(at: pt, in: sceneView)
            controller.activeTool = prevTool
        }
    }
}

// MARK: - Virtual D-Pad Joystick

struct VirtualDPadView: View {
    let onMoveChanged: (Float, Float) -> Void
    @State private var thumbOffset: CGSize = .zero
    private let radius: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.36)).frame(width: radius * 2, height: radius * 2)
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1.5))
            Image(systemName: "arrowtriangle.up.fill").font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).offset(y: -radius + 10)
            Image(systemName: "arrowtriangle.down.fill").font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).offset(y: radius - 10)
            Image(systemName: "arrowtriangle.left.fill").font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).offset(x: -radius + 10)
            Image(systemName: "arrowtriangle.right.fill").font(.system(size: 9)).foregroundColor(.white.opacity(0.55)).offset(x: radius - 10)
            Circle().fill(Color.white.opacity(0.85)).frame(width: 34, height: 34).shadow(radius: 3).offset(thumbOffset)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width, dy = value.translation.height
                    let dist = sqrt(dx * dx + dy * dy)
                    let clampedDist = min(dist, radius - 14)
                    let angle = atan2(dy, dx)
                    let nx = cos(angle) * clampedDist, ny = sin(angle) * clampedDist
                    thumbOffset = CGSize(width: nx, height: ny)
                    let normX = Float(nx / (radius - 14))
                    let normZ = Float(-ny / (radius - 14))
                    onMoveChanged(normX, normZ)
                }
                .onEnded { _ in
                    thumbOffset = .zero
                    onMoveChanged(0, 0)
                }
        )
    }
}

// MARK: - Crafting Bench & Block Palette Sheets

enum ChestTransferChoice { case one, half, all }

struct ChestStorageSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChoice: ChestTransferChoice = .one

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Transfer Amount", selection: $selectedChoice) {
                        Text("1").tag(ChestTransferChoice.one)
                        Text("Half").tag(ChestTransferChoice.half)
                        Text("All").tag(ChestTransferChoice.all)
                    }
                    .pickerStyle(.segmented)

                    Text("Chest Contents").font(.headline)
                    let key = controller.activeChestKey ?? ""
                    let stored = controller.chestItems(for: key)
                    if stored.isEmpty {
                        Text("Chest is empty").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(stored, id: \.0.id) { type, amount in
                            HStack {
                                Image(uiImage: type.previewImage).resizable().interpolation(.none).frame(width: 26, height: 26).cornerRadius(4)
                                Text(type.rawValue).font(.subheadline.bold())
                                Spacer()
                                Text("×\(amount)").font(.subheadline.monospacedDigit())
                                Button("Take") {
                                    controller.transferFromChest(type, amount: controller.transferAmount(for: amount, choice: selectedChoice), chestKey: key)
                                }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                            }
                            .padding(8).background(Color(.secondarySystemBackground)).cornerRadius(8)
                        }
                    }

                    Text("Your Inventory").font(.headline)
                    let owned = BlockType.allCases.filter { controller.count(for: $0) > 0 }
                    if owned.isEmpty {
                        Text("No blocks in inventory").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(owned) { type in
                            let amount = controller.count(for: type)
                            HStack {
                                Image(uiImage: type.previewImage).resizable().interpolation(.none).frame(width: 26, height: 26).cornerRadius(4)
                                Text(type.rawValue).font(.subheadline.bold())
                                Spacer()
                                Text("×\(amount)").font(.subheadline.monospacedDigit())
                                Button("Store") {
                                    controller.transferToChest(type, amount: controller.transferAmount(for: amount, choice: selectedChoice), chestKey: key)
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                            .padding(8).background(Color(.secondarySystemBackground)).cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Chest").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct CraftingBenchSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Blocks & Redstone") {
                    ForEach(CraftCatalog.all) { recipe in
                        let ok = controller.canCraft(recipe)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recipe.title).font(.subheadline.bold())
                                Text(recipe.ingredients.map { "\($0.1) \($0.0.rawValue)" }.joined(separator: " + "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Craft") { controller.craft(recipe) }
                                .buttonStyle(.borderedProminent).disabled(!ok)
                        }
                    }
                }
                Section("Tools & Armour") {
                    ForEach(EquipmentCraftCatalog.all) { recipe in
                        let ok = controller.canCraftEquipment(recipe)
                        let owned = controller.equipmentCount(for: recipe)
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(recipe.title).font(.subheadline.bold())
                                Text(recipe.ingredients.map { "\($0.1) \($0.0.rawValue)" }.joined(separator: " + "))
                                    .font(.caption).foregroundColor(.secondary)
                                if owned > 0 {
                                    Text("In Pack: ×\(owned)").font(.caption2).foregroundColor(.green)
                                }
                            }
                            Spacer()
                            if owned > 0 {
                                Button("Equip") { controller.equipCraftedEquipment(recipe) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                            Button("Craft") { controller.craftEquipment(recipe) }
                                .buttonStyle(.borderedProminent).controlSize(.small).disabled(!ok)
                        }
                    }
                }
            }
            .navigationTitle("Crafting Bench").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct VillagerTradeSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let id = controller.activeVillagerID, let villager = controller.villager(for: id) {
                    let offer = controller.villagerTradeDescription(for: villager.profession)
                    Label("\(villager.profession.rawValue) Villager", systemImage: villager.profession.symbol)
                        .font(.title3.bold())
                    Text("Give \(offer.cost) → Receive \(offer.reward)")
                        .font(.subheadline).foregroundColor(.secondary)
                    Button("Complete Trade") {
                        controller.completeVillagerTrade()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("No active Villager trade.").foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("Villager Trade").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct EnchantingSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Experience") {
                    Text("Level \(controller.experienceLevel) · \(controller.experiencePoints) XP")
                        .font(.subheadline.bold())
                    if controller.gameMode != .survival {
                        Text("Switch to Survival mode to spend XP on enchantments.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("Enchantments") {
                    ForEach(EnchantmentKind.allCases) { kind in
                        let level = controller.enchantmentLevel(kind)
                        let cost = controller.enchantmentCost(kind)
                        let maxed = level >= kind.maximumLevel
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(kind.rawValue)\(level > 0 ? " \(level)" : "")")
                                    .font(.subheadline.bold())
                                Text(kind.description).font(.caption).foregroundColor(.secondary)
                                Text(maxed ? "Max level reached" : "Cost: Level \(cost)")
                                    .font(.caption2).foregroundColor(.accentColor)
                            }
                            Spacer()
                            Button(maxed ? "Max" : "Enchant") {
                                controller.applyEnchantment(kind)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(!controller.canEnchant(kind))
                        }
                    }
                }
            }
            .navigationTitle("Enchanting").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct BrewingStandSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Brew Potions") {
                    ForEach(PotionKind.allCases) { potion in
                        let owned = controller.potionCount(for: potion)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(potion.rawValue).font(.subheadline.bold())
                                Text(potion.ingredients.map { "\($0.1) \($0.0.rawValue)" }.joined(separator: " + "))
                                    .font(.caption).foregroundColor(.secondary)
                                if owned > 0 {
                                    Text("Brewed: ×\(owned)").font(.caption2).foregroundColor(.purple)
                                }
                            }
                            Spacer()
                            if owned > 0 {
                                Button("Drink") { controller.drinkPotion(potion) }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                            Button("Brew") { controller.brewPotion(potion) }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                                .disabled(!controller.canBrew(potion))
                        }
                    }
                }
            }
            .navigationTitle("Brewing Stand").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct AchievementsSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section("Unlocked \(controller.unlockedAchievements.count) of \(AchievementInfo.all.count)") {
                    ForEach(AchievementInfo.all) { item in
                        let unlocked = controller.unlockedAchievements.contains(item.id)
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .foregroundColor(unlocked ? .yellow : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.bold())
                                Text(item.detail).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(unlocked ? "Unlocked" : "Locked")
                                .font(.caption2.bold())
                                .foregroundColor(unlocked ? .green : .secondary)
                        }
                    }
                }
            }
            .navigationTitle("Achievements").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct InventoryBagSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss
    @State private var showAchievements = false

    var body: some View {
        NavigationView {
            List {
                Section("Progression") {
                    Text("Level \(controller.experienceLevel) · \(controller.experiencePoints) XP")
                        .font(.subheadline.bold())
                    Text("Defeated Hostile Mobs: \(controller.defeatedHostileCount)")
                        .font(.caption).foregroundColor(.secondary)
                    Button("Achievements (\(controller.unlockedAchievements.count)/\(AchievementInfo.all.count))") {
                        showAchievements = true
                    }
                }
                Section("Potions") {
                    ForEach(PotionKind.allCases) { potion in
                        let owned = controller.potionCount(for: potion)
                        let active = controller.activePotionEffects[potion]
                        if owned > 0 || (active ?? 0) > 0 {
                            HStack {
                                Label(potion.rawValue, systemImage: potion.symbol).font(.subheadline.bold())
                                Spacer()
                                if let rem = active {
                                    Text("\(Int(rem))s").font(.caption.monospacedDigit()).foregroundColor(.purple)
                                }
                                if owned > 0 {
                                    Button("Drink (×\(owned))") { controller.drinkPotion(potion) }
                                        .buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Section("Food & Cooking") {
                    Button("Bake Bread (3 Wheat → 1 Bread)") { controller.bakeBread() }
                        .disabled(controller.foodCount(for: .wheat) < 3)
                    ForEach(FoodKind.allCases) { food in
                        let c = controller.foodCount(for: food)
                        if c > 0 {
                            HStack {
                                Text(food.rawValue).font(.subheadline.bold())
                                Spacer()
                                Text("×\(c)").font(.subheadline.monospacedDigit())
                                if let cooked = food.cookingResult {
                                    Button("Cook → \(cooked.rawValue)") { controller.cookFood(food) }
                                        .buttonStyle(.bordered).controlSize(.small)
                                        .disabled(controller.count(for: .coalOre) <= 0)
                                } else if food.isEdible {
                                    Button("Eat") { controller.eatFood(food) }
                                        .buttonStyle(.borderedProminent).controlSize(.small)
                                }
                            }
                        }
                    }
                }
                Section("Blocks") {
                    ForEach(BlockType.allCases) { type in
                        let c = controller.count(for: type)
                        HStack {
                            Image(uiImage: type.previewImage).resizable().interpolation(.none).frame(width: 28, height: 28).cornerRadius(4)
                            Text(type.rawValue).font(.subheadline.bold())
                            Spacer()
                            Text("×\(c)").font(.subheadline.monospacedDigit())
                            Button("Hotbar") {
                                controller.hotbarSlots[controller.hotbarSelection] = type
                                controller.selectHotbarSlot(controller.hotbarSelection)
                                dismiss()
                            }
                            .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            .navigationTitle("Inventory").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAchievements) { AchievementsSheet(controller: controller) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct BlockPaletteSheet: View {
    @ObservedObject var controller: VoxelWorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {
                Picker("Category", selection: $controller.selectedCategory) {
                    ForEach(BlockCategory.allCases) { cat in Text(cat.rawValue).tag(cat) }
                }
                .pickerStyle(.segmented).padding(.horizontal)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) {
                        ForEach(controller.visibleBlocks) { type in
                            Button {
                                controller.selectedBlock = type
                                controller.hotbarSlots[controller.hotbarSelection] = type
                                controller.saveWorld()
                                controller.activeTool = .place
                                dismiss()
                            } label: {
                                VStack(spacing: 5) {
                                    Image(uiImage: type.previewImage).resizable().interpolation(.none).frame(width: 44, height: 44).cornerRadius(6)
                                    Text(type.rawValue).font(.caption2.bold()).lineLimit(1)
                                    Text("\(controller.gameMode == .creative ? 64 : controller.count(for: type))")
                                        .font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity).padding(8)
                                .background(controller.selectedBlock == type ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
                                .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Block Palette").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Main Voxel Gameplay View

struct ContentView: View {
    @StateObject private var controller = VoxelWorldController()
    @State private var showPaletteSheet = false
    @State private var sceneViewRef: SCNView?

    private let barColor = Color(red: 0.08, green: 0.10, blue: 0.14).opacity(0.68)

    var body: some View {
        ZStack {
            VoxelSceneView(controller: controller)
                .onAppear { sceneViewRef = nil }
                .ignoresSafeArea()

            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .shadow(color: .black, radius: 1)
                .allowsHitTesting(false)

            VStack(spacing: 8) {
                topBar
                if let fraction = controller.bossHealthFraction {
                    VStack(spacing: 3) {
                        Text(controller.bossHealthLabel)
                            .font(.caption2.bold().monospacedDigit())
                            .foregroundColor(.white)
                        ProgressView(value: fraction)
                            .tint(.red)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.62))
                    .cornerRadius(8)
                }
                Spacer()
                bottomControls
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showPaletteSheet) { BlockPaletteSheet(controller: controller) }
        .sheet(isPresented: $controller.showCraftSheet) { CraftingBenchSheet(controller: controller) }
        .sheet(isPresented: $controller.showInventorySheet) { InventoryBagSheet(controller: controller) }
        .sheet(isPresented: $controller.showChestSheet) { ChestStorageSheet(controller: controller) }
        .sheet(isPresented: $controller.showVillagerTradeSheet) { VillagerTradeSheet(controller: controller) }
        .sheet(isPresented: $controller.showEnchantingSheet) { EnchantingSheet(controller: controller) }
        .sheet(isPresented: $controller.showBrewingSheet) { BrewingStandSheet(controller: controller) }
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Minerva").font(.subheadline.bold()).foregroundColor(.white)
                Menu {
                    ForEach(1...3, id: \.self) { slot in
                        Button("World Slot \(slot)") { controller.selectWorldSlot(slot) }
                    }
                } label: {
                    Text("S\(controller.activeSlot)").font(.caption2.bold().monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.18)).cornerRadius(5).foregroundColor(.white)
                }
                Menu {
                    ForEach(GameDimension.allCases) { dim in
                        Button(dim.rawValue) { controller.selectDimension(dim) }
                    }
                } label: {
                    Text(controller.activeDimension.rawValue).font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(controller.activeDimension.badgeColor.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                }
                Button { controller.setGameMode(controller.gameMode == .creative ? .survival : .creative) } label: {
                    Text(controller.gameMode == .creative ? "Creative" : "Survival")
                        .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(controller.gameMode == .creative ? Color.cyan.opacity(0.35) : Color.orange.opacity(0.35))
                        .cornerRadius(5).foregroundColor(.white)
                }
                Spacer()
                Text(controller.coordsText).font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.9))
                Button { controller.toggleDayNight() } label: {
                    Image(systemName: controller.isNightMode ? "moon.fill" : "sun.max.fill")
                        .font(.caption.bold()).foregroundColor(controller.isNightMode ? .indigo : .yellow).padding(5)
                }
                Button { controller.cycleWeather() } label: {
                    Image(systemName: controller.weather == .rain ? "cloud.rain.fill" : (controller.weather == .snowstorm ? "snowflake" : "sun.min"))
                        .font(.caption.bold()).foregroundColor(.white).padding(5)
                }
                Button { controller.toggleMultiplayerLobby() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        if controller.multiplayerEnabled { Text("\(controller.connectedPeerCount)").font(.caption2.monospacedDigit()) }
                    }
                    .font(.caption.bold()).foregroundColor(controller.multiplayerEnabled ? .green : .white).padding(5)
                }
                Button { controller.toggleCameraMode() } label: {
                    Image(systemName: controller.cameraMode == .firstPerson ? "eye" : "person.crop.square")
                        .font(.caption.bold()).foregroundColor(.white).padding(5)
                }
                Button { controller.saveWorld() } label: {
                    Image(systemName: "square.and.arrow.down").font(.caption.bold()).foregroundColor(.white).padding(5)
                }
                Button { controller.regenerateNewWorld() } label: {
                    Image(systemName: "arrow.clockwise").font(.caption.bold()).foregroundColor(.white).padding(5)
                }
            }

            if controller.gameMode == .survival {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { idx in
                            Image(systemName: idx * 2 + 2 <= controller.health ? "heart.fill" : (idx * 2 + 1 == controller.health ? "heart.lefthalf.filled" : "heart"))
                                .font(.system(size: 10)).foregroundColor(.red)
                        }
                    }
                    HStack(spacing: 2) {
                        ForEach(0..<10, id: \.self) { idx in
                            Image(systemName: idx * 2 + 2 <= controller.hunger ? "fork.knife.circle.fill" : "circle")
                                .font(.system(size: 10)).foregroundColor(.orange)
                        }
                    }
                    if controller.isUnderwater || controller.oxygen < 10 {
                        HStack(spacing: 2) {
                            Image(systemName: "drop.fill").font(.system(size: 10)).foregroundColor(.cyan)
                            Text("\(controller.oxygen)/10").font(.caption2.bold().monospacedDigit()).foregroundColor(.cyan)
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundColor(controller.stamina > 25 ? .yellow : .red)
                        ProgressView(value: controller.stamina / 100.0).frame(width: 44).tint(controller.stamina > 25 ? .yellow : .red)
                    }
                    Spacer()
                    Button { controller.eatFood() } label: {
                        Text("Eat").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.green.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Button { controller.showCraftSheet = true } label: {
                        Text("Craft").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Button { controller.showInventorySheet = true } label: {
                        Text("Bag").font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                }
                HStack(spacing: 6) {
                    Menu {
                        ForEach(ToolKind.allCases) { tool in
                            Button(tool.rawValue) { controller.equipTool(tool) }
                        }
                    } label: {
                        Text("\(controller.toolTier.rawValue) \(controller.selectedTool.rawValue) (\(controller.toolDurability))")
                            .font(.caption2.bold().monospacedDigit()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.16)).cornerRadius(5).foregroundColor(.white)
                    }
                    Button { controller.cycleToolTier() } label: {
                        Text("Tier").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.teal.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Menu {
                        Button("Cycle Full Set (\(controller.armorTier.rawValue))") { controller.cycleArmorTier() }
                        Button("Helmet (\(controller.helmetTier.rawValue))") { controller.cycleArmorPiece("Helmet") }
                        Button("Chestplate (\(controller.chestplateTier.rawValue))") { controller.cycleArmorPiece("Chestplate") }
                        Button("Leggings (\(controller.leggingsTier.rawValue))") { controller.cycleArmorPiece("Leggings") }
                        Button("Boots (\(controller.bootsTier.rawValue))") { controller.cycleArmorPiece("Boots") }
                    } label: {
                        Text("DEF -\(controller.effectiveArmorReduction) (\(controller.armorDurability))")
                            .font(.caption2.bold().monospacedDigit()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Button { controller.showEnchantingSheet = true } label: {
                        Text("Lv.\(controller.experienceLevel)").font(.caption2.bold().monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Button { controller.showBrewingSheet = true } label: {
                        Text("Brew").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.purple.opacity(0.35)).cornerRadius(5).foregroundColor(.white)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6).background(barColor).cornerRadius(10)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom) {
                VirtualDPadView { x, z in controller.setMovementInput(x: x, z: z) }
                Spacer()
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { controller.setSprint(!controller.isSprinting) } label: {
                            Text(controller.isSprinting ? "Sprint ON" : "Sprint")
                                .font(.caption.bold()).foregroundColor(controller.isSprinting ? .yellow : .white)
                                .padding(.horizontal, 10).padding(.vertical, 8).background(barColor).cornerRadius(8)
                        }
                        if controller.gameMode == .survival {
                            Button { controller.toggleShield() } label: {
                                Text(controller.isShieldRaised ? "Shield ON" : "Shield")
                                    .font(.caption.bold()).foregroundColor(controller.isShieldRaised ? .cyan : .white)
                                    .padding(.horizontal, 10).padding(.vertical, 8).background(barColor).cornerRadius(8)
                            }
                        }
                        Menu {
                            Button("Craft Boat (5 Oak Planks)") { controller.craftBoat() }
                            Button(controller.isInBoat ? "Leave Boat" : "Use Boat") { controller.toggleBoat() }
                            Button("Scan Treasure") { controller.scanForTreasure() }
                        } label: {
                            Text("Boat (\(controller.boatCount))").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 8).background(barColor).cornerRadius(8)
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            controller.activeTool = .place
                            _ = controller.performPrimaryAction(at: nil, in: sceneViewRef)
                        } label: {
                            Text("Place").font(.caption.bold()).foregroundColor(controller.activeTool == .place ? .cyan : .white)
                                .padding(.horizontal, 12).padding(.vertical, 9).background(barColor).cornerRadius(8)
                        }
                        Button {
                            controller.activeTool = .breakBlock
                            _ = controller.performPrimaryAction(at: nil, in: sceneViewRef)
                        } label: {
                            Text("Mine").font(.caption.bold()).foregroundColor(controller.activeTool == .breakBlock ? .orange : .white)
                                .padding(.horizontal, 12).padding(.vertical, 9).background(barColor).cornerRadius(8)
                        }
                        Button { controller.jump() } label: {
                            Text("Jump").font(.caption.bold()).foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 9).background(barColor).cornerRadius(8)
                        }
                    }
                }
            }

            HStack(spacing: 5) {
                ForEach(0..<9, id: \.self) { idx in
                    let block = controller.hotbarSlots[idx]
                    let selected = controller.hotbarSelection == idx
                    Button { controller.selectHotbarSlot(idx) } label: {
                        VStack(spacing: 1) {
                            Image(uiImage: block.previewImage).resizable().interpolation(.none).frame(width: 24, height: 24).cornerRadius(3)
                            Text("\(controller.gameMode == .creative ? 64 : controller.count(for: block))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                        .background(selected ? Color.white.opacity(0.32) : Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.yellow : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                Button { showPaletteSheet = true } label: {
                    Image(systemName: "square.grid.2x2.fill").font(.caption.bold()).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 10).background(Color.white.opacity(0.16)).cornerRadius(6)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 5).background(barColor).cornerRadius(10)
        }
    }
}
