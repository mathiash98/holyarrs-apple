#if os(visionOS)
import RealityKit
import SwiftUI
import UIKit

/// The HolyArrs Theater: a dark cinema hall you sit in, front row, with a wall-sized screen the system player
/// docks into (DockingRegionComponent). Opened before playback starts and closed when the player goes away.
struct TheaterSpace: SwiftUI.Scene {
    static let id = "theater"
    @State private var style: ImmersionStyle = .full

    var body: some SwiftUI.Scene {
        ImmersiveSpace(id: Self.id) {
            TheaterView()
        }
        .immersionStyle(selection: $style, in: .full)
    }
}

struct TheaterView: View {
    var body: some View {
        RealityView { content in
            content.add(Theater.makeHall())
        }
    }
}

enum Theater {
    /// Screen size and place: 16 m wide, 10 m ahead, centre 5 m up — about the view from a cinema's front rows.
    static let screenWidth: Float = 16
    static let screenDistance: Float = 10
    static let screenHeight: Float = 5

    static func makeHall() -> Entity {
        let root = Entity()

        // The hall: an inside-out box (negative x scale flips the faces so they show from inside).
        let hall = ModelEntity(mesh: .generateBox(width: 26, height: 13, depth: 22), materials: [unlit(0.018, 0.016, 0.02)])
        hall.scale = [-1, 1, 1]
        hall.position = [0, 6.5, -4]
        root.addChild(hall)

        // Carpet.
        let floor = ModelEntity(mesh: .generatePlane(width: 26, depth: 22), materials: [unlit(0.11, 0.025, 0.03)])
        floor.position = [0, 0.005, -4]
        root.addChild(floor)

        // The screen wall: a dark frame and a faint silver surface behind where the picture docks.
        let frame = ModelEntity(mesh: .generatePlane(width: screenWidth + 1.2, height: screenWidth * 9 / 16 + 1.0), materials: [unlit(0.0, 0.0, 0.0)])
        frame.position = [0, screenHeight, -screenDistance - 0.06]
        root.addChild(frame)
        let surface = ModelEntity(mesh: .generatePlane(width: screenWidth, height: screenWidth * 9 / 16), materials: [unlit(0.05, 0.05, 0.055)])
        surface.position = [0, screenHeight, -screenDistance - 0.04]
        root.addChild(surface)

        // Red curtains either side of the screen.
        for side: Float in [-1, 1] {
            let curtain = ModelEntity(mesh: .generateBox(width: 2.2, height: 12, depth: 0.3), materials: [unlit(0.32, 0.03, 0.04)])
            curtain.position = [side * (screenWidth / 2 + 1.8), 6, -screenDistance + 0.1]
            root.addChild(curtain)
        }

        // Where the player docks.
        let dock = Entity()
        var region = DockingRegionComponent()
        region.width = screenWidth
        dock.components.set(region)
        dock.position = [0, screenHeight, -screenDistance]
        root.addChild(dock)

        // Seats: you sit in the front row; more rows rise behind you (stadium seating).
        let seatColor = unlit(0.26, 0.04, 0.05)
        for row in 0 ..< 7 {
            let z = Float(row) * 1.1 + 0.25
            let rise = Float(row) * 0.32
            if row > 0 {
                let step = ModelEntity(mesh: .generateBox(width: 24, height: rise, depth: 1.1), materials: [unlit(0.08, 0.02, 0.025)])
                step.position = [0, rise / 2, z]
                root.addChild(step)
            }
            var x: Float = -9.5
            while x <= 9.5 {
                // Leave your own seat free in the front row so nothing sits inside you.
                if !(row == 0 && abs(x) < 0.5) {
                    root.addChild(seat(color: seatColor, at: [x, rise, z]))
                }
                x += 0.62
            }
        }

        // Aisle lights along the walls.
        for side: Float in [-1, 1] {
            for i in 0 ..< 14 {
                let light = ModelEntity(mesh: .generateBox(size: 0.06), materials: [unlit(1.0, 0.62, 0.25)])
                light.position = [side * 11.5, 0.05, Float(i) * -1.2 + 6]
                root.addChild(light)
            }
        }
        return root
    }

    private static func seat(color: UnlitMaterial, at p: SIMD3<Float>) -> Entity {
        let s = Entity()
        let cushion = ModelEntity(mesh: .generateBox(width: 0.54, height: 0.14, depth: 0.5, cornerRadius: 0.04), materials: [color])
        cushion.position = [0, 0.45, 0]
        let back = ModelEntity(mesh: .generateBox(width: 0.54, height: 0.62, depth: 0.1, cornerRadius: 0.04), materials: [color])
        back.position = [0, 0.78, 0.24]
        s.addChild(cushion)
        s.addChild(back)
        s.position = p
        return s
    }

    private static func unlit(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(red: r, green: g, blue: b, alpha: 1))
    }
}

/// Opens the theatre before the player appears and closes it after, when Settings › Cinema theatre is on.
struct TheaterHooks: ViewModifier {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    func body(content: Content) -> some View {
        content.onAppear {
            Player.prepare = {
                guard UserDefaults.standard.object(forKey: "theaterMode") as? Bool ?? true else { return }
                _ = await openImmersiveSpace(id: TheaterSpace.id)
            }
            Player.cleanup = {
                guard UserDefaults.standard.object(forKey: "theaterMode") as? Bool ?? true else { return }
                await dismissImmersiveSpace()
            }
        }
    }
}
#endif
