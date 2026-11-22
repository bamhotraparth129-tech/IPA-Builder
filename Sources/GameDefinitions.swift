import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

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

