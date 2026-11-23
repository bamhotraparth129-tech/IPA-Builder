import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

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
    // Chunk creation is queued so entering a world never generates the full view radius in one frame.
    private var pendingChunkQueue: [ChunkCoord] = []
    private var pendingChunkSet: Set<ChunkCoord> = []
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
    // Serial background persistence keeps JSON encoding and disk writes out of
    // the interactive main-thread path while preserving save order.
    private let saveQueue = DispatchQueue(label: "Minerva.WorldSave", qos: .utility)

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
        pendingChunkQueue.removeAll()
        pendingChunkSet.removeAll()
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
        // Defer expensive entity construction until the first frame can render.
        // Terrain and the player become visible first, avoiding a long blank/frozen
        // transition while dozens of animated SceneKit nodes are created.
        statusMessage = "World loaded. Preparing nearby creatures…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            if UserDefaults.standard.object(forKey: "minerva.mobSpawning") as? Bool != false {
                self.spawnMobsNearPlayer(aroundX: 0, z: 0)
            }
            if let savedVillagers {
                for mob in self.mobs where mob.kind == .villager { mob.node.removeFromParentNode() }
                self.mobs.removeAll { $0.kind == .villager }
                for entry in savedVillagers {
                    guard let profession = VillagerProfession(rawValue: entry.profession) else { continue }
                    let position = SIMD3<Float>(entry.x, entry.y, entry.z)
                    let node = self.makeMobNode(kind: .villager)
                    node.name = "mob_\(entry.id.uuidString)"
                    node.position = SCNVector3(position.x, position.y, position.z)
                    self.mobsRootNode.addChildNode(node)
                    let villager = WorldMob(id: entry.id, kind: .villager, position: position, yaw: entry.yaw, hp: max(1, entry.hp), wanderTimer: 1.5, node: node)
                    villager.profession = profession
                    if let x = entry.homeX, let y = entry.homeY, let z = entry.homeZ { villager.homePosition = SIMD3<Float>(x, y, z) }
                    if let x = entry.workX, let y = entry.workY, let z = entry.workZ { villager.workstationPosition = SIMD3<Float>(x, y, z) }
                    villager.isBaby = entry.isBaby ?? false
                    villager.ageTimer = entry.ageTimer ?? 0
                    if villager.homePosition == nil || villager.workstationPosition == nil { self.assignVillagerDestinations(villager) }
                    self.mobs.append(villager)
                }
            }
            self.restoreSavedPets(savedPets)
            self.statusMessage = "Loaded \(self.activeDimension.rawValue)"
        }
    }

    private func applyRestoredBlockVisualStates() {
        for coord in openDoors { blockNodes[coord]?.eulerAngles.y = .pi / 2 }
        for coord in activeLevers { blockNodes[coord]?.eulerAngles.z = .pi / 4 }
        for (coord, stage) in cropStages {
            blockNodes[coord]?.scale = SCNVector3(1.0, CGFloat(0.45 + Double(stage) * 0.22), 1.0)
        }
    }

    func regenerateNewWorld() {
        // Finish earlier queued writes before deleting this world's save file.
        saveQueue.sync {}
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
        pendingChunkQueue.removeAll()
        pendingChunkSet.removeAll()
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

        // Drop queued chunks that are no longer near the player. A forced refresh
        // rebuilds the queue in nearest-first order, but still processes only one
        // chunk per maintenance tick instead of freezing the UI for the full radius.
        if force {
            pendingChunkQueue.removeAll()
            pendingChunkSet.removeAll()
        } else {
            pendingChunkQueue.removeAll { !desired.contains($0) || loadedChunks.contains($0) }
            pendingChunkSet = Set(pendingChunkQueue)
        }

        let missing = desired.subtracting(loadedChunks).subtracting(pendingChunkSet)
        let orderedMissing = missing.sorted { lhs, rhs in
            let ldx = lhs.cx - center.cx
            let ldz = lhs.cz - center.cz
            let rdx = rhs.cx - center.cx
            let rdz = rhs.cz - center.cz
            let ld = ldx * ldx + ldz * ldz
            let rd = rdx * rdx + rdz * rdz
            if ld != rd { return ld < rd }
            if lhs.cx != rhs.cx { return lhs.cx < rhs.cx }
            return lhs.cz < rhs.cz
        }
        pendingChunkQueue.append(contentsOf: orderedMissing)
        pendingChunkSet.formUnion(orderedMissing)

        var generatedNewChunk = false
        if let nextChunk = pendingChunkQueue.first {
            pendingChunkQueue.removeFirst()
            pendingChunkSet.remove(nextChunk)
            if desired.contains(nextChunk) && !loadedChunks.contains(nextChunk) {
                generateChunk(nextChunk)
                loadedChunks.insert(nextChunk)
                rebuildMergedChunkNode(nextChunk)
                generatedNewChunk = true
            }
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
        while mobs.count > 9 {
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
        for idx in 0..<min(kinds.count, 6) {
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
        if activeDimension == .overworld && mobs.count < 9 {
            for _ in 0..<4 where mobs.count < 9 {
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
        let destinationURL = saveURL
        saveQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: destinationURL, options: .atomic)
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

