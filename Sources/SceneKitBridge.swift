import SwiftUI
import SceneKit
import UIKit
import AVFoundation
import MultipeerConnectivity

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

