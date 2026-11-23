import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

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

    // Persistent client preferences. These are stored independently from world saves.
    @AppStorage("minerva.difficulty") private var difficulty = "Normal"
    @AppStorage("minerva.autoJump") private var autoJump = false
    @AppStorage("minerva.viewBobbing") private var viewBobbing = true
    @AppStorage("minerva.showCoordinates") private var showCoordinates = true
    @AppStorage("minerva.showSubtitles") private var showSubtitles = false
    @AppStorage("minerva.reducedMotion") private var reducedMotion = false
    @AppStorage("minerva.leftHanded") private var leftHanded = false
    @AppStorage("minerva.invertLook") private var invertLook = false
    @AppStorage("minerva.touchSensitivity") private var touchSensitivity = 1.0
    @AppStorage("minerva.uiScale") private var uiScale = 1.0
    @AppStorage("minerva.renderDistance") private var renderDistance = 1
    @AppStorage("minerva.graphics") private var graphics = "Balanced"
    @AppStorage("minerva.clouds") private var clouds = true
    @AppStorage("minerva.particles") private var particles = true
    @AppStorage("minerva.fancyLeaves") private var fancyLeaves = true
    @AppStorage("minerva.screenShake") private var screenShake = true
    @AppStorage("minerva.musicVolume") private var musicVolume = 70.0
    @AppStorage("minerva.soundVolume") private var soundVolume = 80.0
    @AppStorage("minerva.ambientVolume") private var ambientVolume = 70.0
    @AppStorage("minerva.autosave") private var autosave = true
    @AppStorage("minerva.mobSpawning") private var mobSpawning = true
    @AppStorage("minerva.weatherCycle") private var weatherCycle = true
    @AppStorage("minerva.fireSpread") private var fireSpread = true
    @AppStorage("minerva.keepInventory") private var keepInventory = false
    @AppStorage("minerva.friendlyFire") private var friendlyFire = false
    @AppStorage("minerva.showFPS") private var showFPS = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Gameplay") {
                    Picker("Game mode", selection: Binding(get: { world.gameMode }, set: { world.setGameMode($0) })) {
                        ForEach(GameMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(["Peaceful", "Easy", "Normal", "Hard"], id: \.self) { Text($0) }
                    }
                    Picker("Dimension", selection: Binding(get: { world.activeDimension }, set: { world.selectDimension($0) })) {
                        ForEach(GameDimension.allCases) { dimension in Text(dimension.rawValue).tag(dimension) }
                    }
                    Picker("World slot", selection: Binding(get: { world.activeSlot }, set: { world.selectWorldSlot($0) })) {
                        ForEach(1...3, id: \.self) { slot in Text("World \(slot)").tag(slot) }
                    }
                    Toggle("Auto-jump preference", isOn: $autoJump)
                    Toggle("Keep inventory on defeat", isOn: $keepInventory)
                    Toggle("Mob spawning", isOn: $mobSpawning)
                    Toggle("Automatic day / night cycle", isOn: Binding(get: { world.isAutoCycleEnabled }, set: { _ in world.toggleAutoCycle() }))
                    Toggle("Weather cycle preference", isOn: $weatherCycle)
                }
                Section("Video and Graphics") {
                    Picker("Graphics quality", selection: $graphics) {
                        ForEach(["Fast", "Balanced", "Fancy"], id: \.self) { Text($0) }
                    }
                    Picker("Render distance", selection: $renderDistance) {
                        Text("Near").tag(0); Text("Normal").tag(1); Text("Far").tag(2)
                    }
                    Toggle("Clouds", isOn: $clouds)
                    Toggle("Particles preference", isOn: $particles)
                    Toggle("Fancy foliage preference", isOn: $fancyLeaves)
                    Toggle("View bobbing preference", isOn: $viewBobbing)
                    Toggle("Screen shake", isOn: $screenShake)
                    Toggle("Show FPS counter preference", isOn: $showFPS)
                }
                Section("Controls") {
                    Button("Switch camera perspective") { world.toggleCameraMode() }
                    Text("Current camera: \(world.cameraMode.rawValue)").foregroundStyle(.secondary)
                    Toggle("Left-handed layout preference", isOn: $leftHanded)
                    Toggle("Invert look preference", isOn: $invertLook)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Touch look sensitivity"); Spacer(); Text("\(touchSensitivity, specifier: "%.1f")×").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $touchSensitivity, in: 0.4...2.0, step: 0.1, label: { Text("Touch look sensitivity") })
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Interface size"); Spacer(); Text("\(Int(uiScale * 100))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $uiScale, in: 0.75...1.25, step: 0.05, label: { Text("Interface size") })
                    }
                }
                Section("Audio") {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Music volume"); Spacer(); Text("\(Int(musicVolume))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $musicVolume, in: 0...100, step: 5, label: { Text("Music volume") })
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Sound effects volume"); Spacer(); Text("\(Int(soundVolume))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $soundVolume, in: 0...100, step: 5, label: { Text("Sound effects volume") })
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text("Ambient sounds volume"); Spacer(); Text("\(Int(ambientVolume))%").monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $ambientVolume, in: 0...100, step: 5, label: { Text("Ambient sounds volume") })
                    }
                    Toggle("Subtitles preference", isOn: $showSubtitles)
                }
                Section("World Rules") {
                    Toggle("Autosave preference", isOn: $autosave)
                    Toggle("Fire spread preference", isOn: $fireSpread)
                    Toggle("Friendly fire preference", isOn: $friendlyFire)
                    Toggle("Multiplayer LAN", isOn: Binding(get: { world.multiplayerEnabled }, set: { _ in world.toggleMultiplayerLobby() }))
                    Button("Regenerate current world", role: .destructive) { confirmWorldReset = true }
                }
                Section("Accessibility") {
                    Toggle("Show coordinates", isOn: $showCoordinates)
                    Toggle("Reduced motion preference", isOn: $reducedMotion)
                    Text("Preferences marked as such are saved now; options that need engine support are not yet applied to gameplay.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Reset settings to defaults", role: .destructive) { resetPreferences() }
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

    private func resetPreferences() {
        difficulty = "Normal"; autoJump = false; viewBobbing = true; showCoordinates = true
        showSubtitles = false; reducedMotion = false; leftHanded = false; invertLook = false
        touchSensitivity = 1.0; uiScale = 1.0; renderDistance = 1; graphics = "Balanced"
        clouds = true; particles = true; fancyLeaves = true; screenShake = true
        musicVolume = 70; soundVolume = 80; ambientVolume = 70; autosave = true
        mobSpawning = true; weatherCycle = true; fireSpread = true; keepInventory = false
        friendlyFire = false; showFPS = false
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
    @State private var isShowingBlockPicker = false

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
                    HStack(spacing: 5) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .frame(height: 56, alignment: .top)

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
                            ForEach(PotionKind.allCases) { effect in
                                if let remaining = world.activePotionEffects[effect], remaining > 0 {
                                    PotionEffectBadge(
                                        title: effect.rawValue,
                                        seconds: Int(remaining),
                                        symbol: effect.symbol
                                    )
                                }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.vertical, 6)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 12))
                .clipped()

                Spacer()

                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 6) {
                        MoveHoldButton(systemImage: "chevron.up", onPress: { world.setMoveInput(forward: 1, strafe: 0) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                        HStack(spacing: 6) {
                            MoveHoldButton(systemImage: "chevron.left", onPress: { world.setMoveInput(forward: 0, strafe: -1) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                            MoveHoldButton(systemImage: "chevron.down", onPress: { world.setMoveInput(forward: -1, strafe: 0) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                            MoveHoldButton(systemImage: "chevron.right", onPress: { world.setMoveInput(forward: 0, strafe: 1) }, onRelease: { world.setMoveInput(forward: 0, strafe: 0) })
                        }
                    }
                    .padding(.leading, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 7) {
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
                    .frame(maxWidth: 205, alignment: .trailing)
                    .padding(.trailing, 8)
                }
                .frame(maxWidth: .infinity)

                // Minecraft-style survival HUD: hearts and hunger directly above the centered 9-slot hotbar.
                VStack(spacing: 4) {
                    if world.gameMode == .survival {
                        MinecraftHealthHungerBar(health: world.health, hunger: world.hunger)
                            .frame(maxWidth: 430)
                    } else {
                        Text("\(world.experienceLevel)  •  CREATIVE")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    HStack(spacing: 2) {
                        ForEach(0..<9, id: \.self) { index in
                            HotbarSlotButton(
                                block: world.hotbarSlots[index],
                                quantity: world.count(for: world.hotbarSlots[index]),
                                isSelected: world.hotbarSelection == index,
                                onSelect: { world.selectHotbarSlot(index) }
                            )
                            .frame(width: 46, height: 48)
                        }
                    }
                    .padding(4)
                    .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.55), lineWidth: 1))

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { isShowingBlockPicker.toggle() }
                    } label: {
                        Label(isShowingBlockPicker ? "CLOSE BLOCKS" : "BLOCKS", systemImage: isShowingBlockPicker ? "chevron.down" : "square.grid.3x3.fill")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.65), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if isShowingBlockPicker {
                        VStack(spacing: 5) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 5) {
                                    ForEach(BlockCategory.allCases) { category in
                                        CategoryFilterButton(
                                            category: category,
                                            isSelected: world.selectedCategory == category
                                        ) { world.selectedCategory = category }
                                    }
                                }
                                .padding(.horizontal, 3)
                            }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(world.visibleBlocks) { block in
                                        BlockPaletteButton(
                                            block: block,
                                            quantity: world.count(for: block),
                                            isSelected: world.selectedBlock == block
                                        ) {
                                            world.selectedBlock = block
                                            world.hotbarSlots[world.hotbarSelection] = block
                                            world.activeTool = .place
                                            withAnimation(.easeInOut(duration: 0.18)) { isShowingBlockPicker = false }
                                        }
                                    }
                                }
                                .padding(.horizontal, 3)
                            }
                            .frame(height: 58)
                        }
                        .padding(7)
                        .frame(maxWidth: 560)
                        .background(Color.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.bottom, 5)
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
        .onChange(of: scenePhase) { phase in
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


/// Kept separate from VoxelGameView so Swift's type checker does not have to
/// infer the entire block-palette button as part of the already-large HUD view.

private struct MinecraftHealthHungerBar: View {
    let health: Int
    let hunger: Int

    var body: some View {
        HStack(alignment: .center) {
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { index in
                    let value = health - index * 2
                    Image(systemName: value >= 2 ? "heart.fill" : (value == 1 ? "heart.lefthalf.fill" : "heart"))
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(value > 0 ? Color.red : Color.white.opacity(0.55))
                        .shadow(color: .black.opacity(0.85), radius: 1, x: 1, y: 1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 1) {
                ForEach(0..<10, id: \.self) { index in
                    let value = hunger - index * 2
                    Text("🍗")
                        .font(.system(size: 14))
                        .opacity(value >= 2 ? 1 : (value == 1 ? 0.55 : 0.22))
                        .shadow(color: .black.opacity(0.85), radius: 1, x: 1, y: 1)
                }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health \(health) of 20. Hunger \(hunger) of 20.")
    }
}

private struct HotbarSlotButton: View {
    let block: BlockType
    let quantity: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Image(uiImage: block.previewImage)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 27, height: 27)
                Text(String(quantity))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(2)
            .background(
                isSelected
                    ? Color(red: 0.58, green: 0.58, blue: 0.58)
                    : Color(red: 0.28, green: 0.28, blue: 0.28),
                in: RoundedRectangle(cornerRadius: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(isSelected ? Color.white : Color.black.opacity(0.8), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 1)
        }
        .buttonStyle(.plain)
    }
}

private struct BlockPaletteButton: View {
    let block: BlockType
    let quantity: Int
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 3) {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: block.previewImage)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.black.opacity(0.35), lineWidth: 1)
                        )
                    Text(String(quantity))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 3)
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                }
                Text(block.rawValue)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.white.opacity(0.32) : Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.yellow : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
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



private struct CategoryFilterButton: View {
    let category: BlockCategory
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(category.rawValue)
                .font(.caption2.bold())
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.yellow : Color.black.opacity(0.5),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

private struct PotionEffectBadge: View {
    let title: String
    let seconds: Int
    let symbol: String

    var body: some View {
        let durationText = String(seconds) + "s"
        let labelText = title + " " + durationText
        return Label(labelText, systemImage: symbol)
            .font(.caption2.bold())
            .foregroundStyle(.purple)
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
