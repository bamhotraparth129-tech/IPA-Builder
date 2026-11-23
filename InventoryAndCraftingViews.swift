import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

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

