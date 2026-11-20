import SwiftUI
import UIKit

struct GridPoint: Equatable, Hashable {
    var x: Int
    var y: Int
}

enum Direction: CaseIterable {
    case up, down, left, right

    var opposite: Direction {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    var delta: GridPoint {
        switch self {
        case .up: return GridPoint(x: 0, y: -1)
        case .down: return GridPoint(x: 0, y: 1)
        case .left: return GridPoint(x: -1, y: 0)
        case .right: return GridPoint(x: 1, y: 0)
        }
    }
}

enum GamePhase {
    case menu, playing, paused, gameOver
}

struct SnakeGameView: View {
    private let cols = 18
    private let rows = 24

    @State private var phase: GamePhase = .menu
    @State private var snake: [GridPoint] = [
        GridPoint(x: 9, y: 12),
        GridPoint(x: 8, y: 12),
        GridPoint(x: 7, y: 12)
    ]
    @State private var direction: Direction = .right
    @State private var inputQueue: [Direction] = []
    @State private var food: GridPoint = GridPoint(x: 14, y: 12)
    @State private var bonusFood: GridPoint? = nil
    @State private var bonusTimer: Int = 0

    @State private var score: Int = 0
    @AppStorage("highScoreSnake") private var highScore: Int = 0
    @State private var combo: Int = 1
    @State private var stepsSinceFood: Int = 0
    @State private var wrapWalls: Bool = false

    private let timer = Timer.publish(every: 0.11, on: .main, in: .common).autoconnect()
    @State private var tickAccumulator: Int = 0

    private var speedIntervalTicks: Int {
        max(1, 3 - (snake.count / 8))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.11), Color(red: 0.09, green: 0.12, blue: 0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                headerBar

                boardView
                    .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
                    .padding(.horizontal, 14)
                    .gesture(swipeGesture)
                    .overlay(overlayView)

                footerControls
            }
            .padding(.vertical, 12)
        }
        .onReceive(timer) { _ in
            guard phase == .playing else { return }
            tickAccumulator += 1
            if tickAccumulator >= speedIntervalTicks {
                tickAccumulator = 0
                stepGame()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("SCORE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(score)")
                    .font(.title2.monospacedDigit().weight(.heavy))
                    .foregroundStyle(.white)
            }

            Spacer()

            if combo > 1 {
                Text("\(combo)x COMBO")
                    .font(.caption.weight(.black))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.22), in: Capsule())
                    .foregroundStyle(.orange)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("BEST")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text("\(highScore)")
                    .font(.title2.monospacedDigit().weight(.heavy))
                    .foregroundStyle(.mint)
            }
        }
        .padding(.horizontal, 20)
    }

    private var boardView: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / CGFloat(cols)
            let cellH = geo.size.height / CGFloat(rows)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(wrapWalls ? Color.cyan.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 2)
                    )

                Canvas { context, _ in
                    let dotColor = Color.white.opacity(0.05)
                    for x in 0..<cols {
                        for y in 0..<rows {
                            let rect = CGRect(
                                x: CGFloat(x) * cellW + cellW * 0.42,
                                y: CGFloat(y) * cellH + cellH * 0.42,
                                width: cellW * 0.16,
                                height: cellH * 0.16
                            )
                            context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                        }
                    }
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.red.opacity(0.95), .pink],
                            center: .center,
                            startRadius: 1,
                            endRadius: max(cellW, cellH) * 0.5
                        )
                    )
                    .frame(width: cellW * 0.72, height: cellH * 0.72)
                    .position(
                        x: (CGFloat(food.x) + 0.5) * cellW,
                        y: (CGFloat(food.y) + 0.5) * cellH
                    )
                    .shadow(color: .red.opacity(0.6), radius: 6)

                if let bonus = bonusFood {
                    DiamondShape()
                        .fill(.yellow)
                        .frame(width: cellW * 0.85, height: cellH * 0.85)
                        .position(
                            x: (CGFloat(bonus.x) + 0.5) * cellW,
                            y: (CGFloat(bonus.y) + 0.5) * cellH
                        )
                        .shadow(color: .yellow.opacity(0.7), radius: 8)
                }

                ForEach(Array(snake.enumerated()), id: \.offset) { index, segment in
                    let isHead = index == 0
                    let ratio = 1.0 - (Double(index) / Double(max(snake.count, 1))) * 0.35
                    RoundedRectangle(cornerRadius: isHead ? cellW * 0.35 : cellW * 0.25)
                        .fill(
                            isHead
                            ? AnyShapeStyle(LinearGradient(colors: [.mint, .green], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.mint.opacity(ratio))
                        )
                        .frame(
                            width: cellW * (isHead ? 0.9 : 0.82),
                            height: cellH * (isHead ? 0.9 : 0.82)
                        )
                        .position(
                            x: (CGFloat(segment.x) + 0.5) * cellW,
                            y: (CGFloat(segment.y) + 0.5) * cellH
                        )
                }
            }
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        switch phase {
        case .menu:
            cardOverlay(
                title: "VIPER // SNAKE",
                subtitle: "Swipe anywhere on the board to steer. Chain quick pickups for combo multipliers.",
                buttonTitle: "Start Run"
            )
        case .paused:
            cardOverlay(
                title: "PAUSED",
                subtitle: "Take a breather.",
                buttonTitle: "Resume"
            )
        case .gameOver:
            cardOverlay(
                title: "GAME OVER",
                subtitle: "Final Score: \(score) • Best: \(highScore)",
                buttonTitle: "Play Again"
            )
        case .playing:
            EmptyView()
        }
    }

    private func cardOverlay(title: String, subtitle: String, buttonTitle: String) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title.weight(.black))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal)
            Button(action: {
                if phase == .paused {
                    phase = .playing
                } else {
                    resetGame()
                    phase = .playing
                }
            }) {
                Text(buttonTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(.mint, in: Capsule())
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(28)
    }

    private var footerControls: some View {
        HStack(spacing: 16) {
            Toggle(isOn: $wrapWalls) {
                Text("Portal Walls")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(.switch)
            .tint(.cyan)
            .frame(maxWidth: 165)

            Spacer()

            if phase == .playing || phase == .paused {
                Button(action: {
                    phase = (phase == .playing) ? .paused : .playing
                }) {
                    Image(systemName: phase == .playing ? "pause.fill" : "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
            }
        }
        .padding(.horizontal, 22)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onEnded { value in
                guard phase == .playing else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let next: Direction
                if abs(dx) > abs(dy) {
                    next = dx > 0 ? .right : .left
                } else {
                    next = dy > 0 ? .down : .up
                }
                enqueueDirection(next)
            }
    }

    private func enqueueDirection(_ candidate: Direction) {
        let lastPlanned = inputQueue.last ?? direction
        if candidate != lastPlanned && candidate != lastPlanned.opposite && inputQueue.count < 2 {
            inputQueue.append(candidate)
        }
    }

    private func resetGame() {
        snake = [
            GridPoint(x: 9, y: 12),
            GridPoint(x: 8, y: 12),
            GridPoint(x: 7, y: 12)
        ]
        direction = .right
        inputQueue.removeAll()
        score = 0
        combo = 1
        stepsSinceFood = 0
        bonusFood = nil
        bonusTimer = 0
        food = spawnFreeCell()
    }

    private func stepGame() {
        if let nextDir = inputQueue.first {
            direction = nextDir
            inputQueue.removeFirst()
        }

        var nextHead = GridPoint(
            x: snake[0].x + direction.delta.x,
            y: snake[0].y + direction.delta.y
        )

        if wrapWalls {
            nextHead.x = (nextHead.x + cols) % cols
            nextHead.y = (nextHead.y + rows) % rows
        } else if nextHead.x < 0 || nextHead.x >= cols || nextHead.y < 0 || nextHead.y >= rows {
            triggerGameOver()
            return
        }

        let willEatStandard = (nextHead == food)
        let willEatBonus = (nextHead == bonusFood)
        let bodyToCheck = (willEatStandard || willEatBonus) ? snake : Array(snake.dropLast())

        if bodyToCheck.contains(nextHead) {
            triggerGameOver()
            return
        }

        snake.insert(nextHead, at: 0)
        stepsSinceFood += 1

        if willEatStandard {
            combo = stepsSinceFood <= 14 ? min(combo + 1, 5) : 1
            score += 10 * combo
            stepsSinceFood = 0
            haptic(.light)
            food = spawnFreeCell()

            if bonusFood == nil && score % 50 == 0 {
                bonusFood = spawnFreeCell()
                bonusTimer = 45
            }
        } else if willEatBonus {
            score += 35 * combo
            bonusFood = nil
            bonusTimer = 0
            haptic(.medium)
        } else {
            snake.removeLast()
        }

        if bonusFood != nil {
            bonusTimer -= 1
            if bonusTimer <= 0 {
                bonusFood = nil
            }
        }

        if score > highScore {
            highScore = score
        }
    }

    private func triggerGameOver() {
        haptic(.heavy)
        phase = .gameOver
    }

    private func spawnFreeCell() -> GridPoint {
        let occupied = Set(snake + [food] + (bonusFood.map { [$0] } ?? []))
        var free: [GridPoint] = []
        free.reserveCapacity(cols * rows)
        for x in 0..<cols {
            for y in 0..<rows {
                let pt = GridPoint(x: x, y: y)
                if !occupied.contains(pt) {
                    free.append(pt)
                }
            }
        }
        return free.randomElement() ?? GridPoint(x: 0, y: 0)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
