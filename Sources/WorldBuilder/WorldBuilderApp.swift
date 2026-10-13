import SwiftUI
import SceneKit
import AppKit

struct Block: Codable, Hashable {
    let x: Int
    let y: Int
    let z: Int
    var kind: BlockKind
}

enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case grass, stone, wood, sand, water, brick
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grass: "草地"
        case .stone: "石头"
        case .wood: "木头"
        case .sand: "沙子"
        case .water: "水"
        case .brick: "砖块"
        }
    }
    var color: NSColor {
        switch self {
        case .grass: NSColor(red: 0.36, green: 0.70, blue: 0.35, alpha: 1)
        case .stone: NSColor(red: 0.53, green: 0.57, blue: 0.62, alpha: 1)
        case .wood: NSColor(red: 0.62, green: 0.39, blue: 0.21, alpha: 1)
        case .sand: NSColor(red: 0.87, green: 0.77, blue: 0.49, alpha: 1)
        case .water: NSColor(red: 0.19, green: 0.55, blue: 0.85, alpha: 1)
        case .brick: NSColor(red: 0.72, green: 0.32, blue: 0.27, alpha: 1)
        }
    }
}

struct WorldFile: Codable {
    var name: String
    var blocks: [Block]
}

enum MergeDirection: String, CaseIterable, Identifiable {
    case east, west, north, south
    var id: String { rawValue }
    var title: String {
        switch self {
        case .east: "东侧"
        case .west: "西侧"
        case .north: "北侧"
        case .south: "南侧"
        }
    }
}

enum WorldMode: String, CaseIterable, Identifiable {
    case create, roam
    var id: String { rawValue }
    var title: String { self == .create ? "创造模式" : "漫游模式" }
}

enum RoamCamera: String, CaseIterable, Identifiable {
    case firstPerson, follow
    var id: String { rawValue }
    var title: String { self == .firstPerson ? "第一人称" : "身后跟随" }
}

@MainActor final class WorldModel: ObservableObject {
    @Published var name = "我的世界"
    @Published var selectedKind: BlockKind = .grass
    @Published var blocks: [Block] = []
    @Published var status = "点击地面或方块来放置；右键删除"
    @Published var revision = 0
    @Published var mode: WorldMode = .create {
        didSet {
            if mode != oldValue {
                status = mode == .roam ? "漫游中 · 使用 WASD 或方向键移动小人" : "创造中 · 左键添加，右键清除方块"
            }
        }
    }
    @Published var mergeDirection: MergeDirection = .east
    @Published var roamCamera: RoamCamera = .firstPerson
    @Published private(set) var canUndoMerge = false
    var currentURL: URL?
    private var blocksBeforeMerge: [Block]?

    init() {
        if let url = Bundle.main.url(forResource: "三层小楼.world", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let world = try? JSONDecoder().decode(WorldFile.self, from: data) {
            name = world.name
            blocks = world.blocks
            status = "示例世界已载入 · 共 \(blocks.count) 个方块"
        } else {
            blocks = [Block(x: 0, y: 0, z: 0, kind: .grass)]
        }
    }

    func add(x: Int, y: Int, z: Int) {
        guard (-128...128).contains(x), (0...32).contains(y), (-128...128).contains(z) else {
            status = "已到达建造边界"
            return
        }
        guard !blocks.contains(where: { $0.x == x && $0.y == y && $0.z == z }) else { return }
        blocksBeforeMerge = nil; canUndoMerge = false
        blocks.append(Block(x: x, y: y, z: z, kind: selectedKind))
        status = "已放置 \(selectedKind.title) · 共 \(blocks.count) 个方块"
    }

    func remove(x: Int, y: Int, z: Int) {
        blocksBeforeMerge = nil; canUndoMerge = false
        blocks.removeAll { $0.x == x && $0.y == y && $0.z == z }
        status = "已删除方块 · 共 \(blocks.count) 个方块"
    }

    func newWorld() {
        mode = .create
        blocksBeforeMerge = nil; canUndoMerge = false
        name = "我的世界"
        blocks = []
        currentURL = nil
        revision += 1
        status = "新世界已创建"
    }

    func supportHeight(x: Int, z: Int, from current: Int) -> Int? {
        guard (-128...128).contains(x), (-128...128).contains(z) else { return nil }
        let occupied = Set(blocks.filter { $0.x == x && $0.z == z }.map(\.y))
        for support in stride(from: min(current + 1, 32), through: max(current - 1, -1), by: -1) {
            guard support == -1 || occupied.contains(support) else { continue }
            if !occupied.contains(support + 1) && !occupied.contains(support + 2) {
                return support
            }
        }
        return nil
    }

    func spawnPoint() -> (Int, Int) {
        guard !blocks.isEmpty else { return (0, 0) }
        let xs = blocks.map(\.x)
        let zs = blocks.map(\.z)
        return ((xs.min()! + xs.max()!) / 2, max(-126, zs.min()! - 2))
    }

    func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (currentURL?.lastPathComponent ?? "\(name).world.json")
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try JSONEncoder.pretty.encode(WorldFile(name: name, blocks: blocks))
                try data.write(to: url, options: .atomic)
                currentURL = url
                status = "已保存到 \(url.lastPathComponent)"
            } catch { status = "保存失败：\(error.localizedDescription)" }
        }
    }

    func open() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let world = try JSONDecoder().decode(WorldFile.self, from: Data(contentsOf: url))
                mode = .create
                blocksBeforeMerge = nil; canUndoMerge = false
                name = world.name
                blocks = world.blocks
                currentURL = url
                revision += 1
                status = "已打开 \(url.lastPathComponent)"
            } catch { status = "打开失败：\(error.localizedDescription)" }
        }
    }

    func mergeWorld() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = Bundle.main.resourceURL
        panel.message = "选择要拼接的世界文件。导入后会接在当前地图的\(mergeDirection.title)。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let world = try JSONDecoder().decode(WorldFile.self, from: Data(contentsOf: url))
            var seen = Set<String>()
            let source = world.blocks.filter { seen.insert("\($0.x),\($0.y),\($0.z)").inserted }
            guard !source.isEmpty else { status = "所选地图没有方块"; return }
            let dx: Int, dz: Int
            if blocks.isEmpty {
                dx = 0; dz = 0
            } else {
                let currentMinX = blocks.map(\.x).min()!, currentMaxX = blocks.map(\.x).max()!
                let currentMinZ = blocks.map(\.z).min()!, currentMaxZ = blocks.map(\.z).max()!
                let sourceMinX = source.map(\.x).min()!, sourceMaxX = source.map(\.x).max()!
                let sourceMinZ = source.map(\.z).min()!, sourceMaxZ = source.map(\.z).max()!
                switch mergeDirection {
                case .east:
                    dx = currentMaxX + 1 - sourceMinX
                    dz = (currentMinZ + currentMaxZ - sourceMinZ - sourceMaxZ) / 2
                case .west:
                    dx = currentMinX - 1 - sourceMaxX
                    dz = (currentMinZ + currentMaxZ - sourceMinZ - sourceMaxZ) / 2
                case .north:
                    dx = (currentMinX + currentMaxX - sourceMinX - sourceMaxX) / 2
                    dz = currentMaxZ + 1 - sourceMinZ
                case .south:
                    dx = (currentMinX + currentMaxX - sourceMinX - sourceMaxX) / 2
                    dz = currentMinZ - 1 - sourceMaxZ
                }
            }
            let translated = source.map { Block(x: $0.x + dx, y: $0.y, z: $0.z + dz, kind: $0.kind) }
            guard translated.allSatisfy({ (-128...128).contains($0.x) && (0...32).contains($0.y) && (-128...128).contains($0.z) }) else {
                status = "拼接后会超出地图边界，请换个方向"
                return
            }
            blocksBeforeMerge = blocks
            canUndoMerge = true
            mode = .create
            blocks.append(contentsOf: translated)
            revision += 1
            status = "已将“\(world.name)”拼接到\(mergeDirection.title) · 新增 \(translated.count) 个方块"
        } catch {
            status = "拼接失败：\(error.localizedDescription)"
        }
    }

    func undoMerge() {
        guard let previous = blocksBeforeMerge else { return }
        blocks = previous
        blocksBeforeMerge = nil
        canUndoMerge = false
        revision += 1
        status = "已撤销上次地图拼接"
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

final class BuildingView: SCNView {
    var onPlace: ((Int, Int, Int) -> Void)?
    var onRemove: ((Int, Int, Int) -> Void)?
    var supportHeight: ((Int, Int, Int) -> Int?)?
    var spawnPoint: (() -> (Int, Int))?
    var perspective: RoamCamera = .firstPerson {
        didSet {
            guard perspective != oldValue, exploring else { return }
            updatePlayer(animated: false)
        }
    }
    var exploring = false {
        didSet {
            guard exploring != oldValue else { return }
            allowsCameraControl = !exploring
            avatar?.isHidden = !exploring || perspective == .firstPerson
            pressedKeys.removeAll()
            walkTimer?.invalidate()
            walkTimer = nil
            if exploring {
                let spawn = spawnPoint?() ?? (0, -7)
                playerX = spawn.0; playerZ = spawn.1
                playerSupport = supportHeight?(playerX, playerZ, 0) ?? -1
                heading = 0
                updatePlayer(animated: false)
                window?.makeFirstResponder(self)
            }
        }
    }
    var avatar: SCNNode?
    var followCamera: SCNNode?
    var shownRevision = -1
    private var playerX = 0
    private var playerZ = -7
    private var playerSupport = 0
    private var heading: Float = 0
    private var pressedKeys = Set<UInt16>()
    private var walkTimer: Timer?
    private var downPoint: NSPoint = .zero
    private var lastDragPoint: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if exploring && (event.keyCode == 12 || event.keyCode == 14) {
            if !event.isARepeat {
                heading += event.keyCode == 12 ? -.pi / 2 : .pi / 2
                updatePlayer(animated: true)
            }
            return
        }
        guard exploring, [0, 1, 2, 13, 123, 124, 125, 126].contains(event.keyCode) else {
            super.keyDown(with: event); return
        }
        if pressedKeys.insert(event.keyCode).inserted { walk() }
        if walkTimer == nil {
            walkTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
                self?.walk()
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        pressedKeys.remove(event.keyCode)
        if pressedKeys.isEmpty { walkTimer?.invalidate(); walkTimer = nil }
    }

    override func resignFirstResponder() -> Bool {
        pressedKeys.removeAll()
        walkTimer?.invalidate(); walkTimer = nil
        return super.resignFirstResponder()
    }

    private func walk() {
        guard exploring, let key = pressedKeys.first else { return }
        let forwardX = sin(heading), forwardZ = cos(heading)
        let vector: (Float, Float)
        switch key {
        case 13, 126: vector = (forwardX, forwardZ)
        case 1, 125: vector = (-forwardX, -forwardZ)
        case 0, 123: vector = (-forwardZ, forwardX)
        case 2, 124: vector = (forwardZ, -forwardX)
        default: return
        }
        let dx = abs(vector.0) >= abs(vector.1) ? (vector.0 >= 0 ? 1 : -1) : 0
        let dz = abs(vector.1) > abs(vector.0) ? (vector.1 >= 0 ? 1 : -1) : 0
        let nextX = playerX + dx, nextZ = playerZ + dz
        guard let nextSupport = supportHeight?(nextX, nextZ, playerSupport) else { return }
        playerX = nextX; playerZ = nextZ; playerSupport = nextSupport
        updatePlayer(animated: true)
    }

    private func updatePlayer(animated: Bool) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.12 : 0
        let px = Float(playerX)
        let py = Float(playerSupport) + 0.5
        let pz = Float(playerZ)
        let position = SCNVector3(px, py, pz)
        avatar?.position = position
        avatar?.eulerAngles.y = CGFloat(heading)
        avatar?.isHidden = !exploring || perspective == .firstPerson
        let forwardX = sin(heading), forwardZ = cos(heading)
        if perspective == .firstPerson {
            let eye = SCNVector3(px, py + 1.55, pz)
            let target = SCNVector3(px + forwardX * 5, py + 1.55, pz + forwardZ * 5)
            followCamera?.position = eye
            followCamera?.look(at: target)
        } else {
            let eye = SCNVector3(px - forwardX * 4, py + 3.2, pz - forwardZ * 4)
            let target = SCNVector3(px + forwardX * 2, py + 1.3, pz + forwardZ * 2)
            followCamera?.position = eye
            followCamera?.look(at: target)
        }
        SCNTransaction.commit()
    }

    func frameWorld(_ blocks: [Block]) {
        guard let camera = followCamera else { return }
        guard !blocks.isEmpty else {
            camera.position = SCNVector3(0, 12, -24)
            camera.look(at: SCNVector3(0, 0, 0))
            return
        }
        let minX = blocks.map(\.x).min()!, maxX = blocks.map(\.x).max()!
        let minZ = blocks.map(\.z).min()!, maxZ = blocks.map(\.z).max()!
        let maxY = blocks.map(\.y).max()!
        let centerX = Float(minX + maxX) / 2
        let centerZ = Float(minZ + maxZ) / 2
        let span = Float(max(maxX - minX, maxZ - minZ, 12))
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        camera.position = SCNVector3(centerX, Float(maxY) / 2 + span * 0.45, centerZ - span * 1.8)
        camera.look(at: SCNVector3(centerX, Float(maxY) / 2, centerZ))
        SCNTransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if exploring { window?.makeFirstResponder(self) }
        downPoint = convert(event.locationInWindow, from: nil)
        lastDragPoint = downPoint
        if !exploring { super.mouseDown(with: event) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard exploring else { super.mouseDragged(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        heading += Float(point.x - lastDragPoint.x) * 0.01
        lastDragPoint = point
        updatePlayer(animated: false)
    }

    override func mouseUp(with event: NSEvent) {
        if exploring { return }
        let point = convert(event.locationInWindow, from: nil)
        if hypot(point.x - downPoint.x, point.y - downPoint.y) < 4 {
            place(at: point)
        }
        super.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        if exploring { window?.makeFirstResponder(self); return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(point, options: [.firstFoundOnly: true, .categoryBitMask: 1]).first,
              let name = hit.node.name, name.hasPrefix("block:") else { return }
        let coords = name.dropFirst(6).split(separator: ",").compactMap { Int($0) }
        guard coords.count == 3 else { return }
        onRemove?(coords[0], coords[1], coords[2])
    }

    private func place(at point: NSPoint) {
        guard let hit = hitTest(point, options: [.firstFoundOnly: true, .categoryBitMask: 1]).first else { return }
        if hit.node.name == "ground" {
            let p = hit.worldCoordinates
            onPlace?(Int(round(p.x)), 0, Int(round(p.z)))
        } else if let name = hit.node.name, name.hasPrefix("block:") {
            let coords = name.dropFirst(6).split(separator: ",").compactMap { Int($0) }
            guard coords.count == 3 else { return }
            let n = hit.worldNormal
            onPlace?(coords[0] + Int(round(n.x)), coords[1] + Int(round(n.y)), coords[2] + Int(round(n.z)))
        }
    }
}

struct WorldScene: NSViewRepresentable {
    @ObservedObject var model: WorldModel

    func makeNSView(context: Context) -> BuildingView {
        let view = BuildingView()
        view.scene = SCNScene()
        view.backgroundColor = NSColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zFar = 600
        camera.position = SCNVector3(0, 12, -24)
        camera.look(at: SCNVector3(0, 0, 0))
        view.scene?.rootNode.addChildNode(camera)
        view.pointOfView = camera
        view.followCamera = camera

        let avatar = SCNNode()
        avatar.name = "explorer"
        avatar.categoryBitMask = 2
        avatar.isHidden = true
        func part(_ geometry: SCNGeometry, color: NSColor, x: CGFloat = 0, y: CGFloat) {
            geometry.firstMaterial?.diffuse.contents = color
            let node = SCNNode(geometry: geometry)
            node.position = SCNVector3(x, y, 0)
            avatar.addChildNode(node)
        }
        part(SCNBox(width: 0.54, height: 0.62, length: 0.34, chamferRadius: 0.08),
             color: NSColor.systemTeal, y: 1.0)
        part(SCNSphere(radius: 0.28), color: NSColor(red: 0.98, green: 0.77, blue: 0.57, alpha: 1), y: 1.57)
        part(SCNBox(width: 0.20, height: 0.52, length: 0.24, chamferRadius: 0.04),
             color: NSColor.systemIndigo, x: -0.16, y: 0.43)
        let rightLeg = SCNNode(geometry: SCNBox(width: 0.20, height: 0.52, length: 0.24, chamferRadius: 0.04))
        rightLeg.geometry?.firstMaterial?.diffuse.contents = NSColor.systemIndigo
        rightLeg.position = SCNVector3(0.16, 0.43, 0)
        avatar.addChildNode(rightLeg)
        let eye = SCNNode(geometry: SCNSphere(radius: 0.04))
        eye.geometry?.firstMaterial?.diffuse.contents = NSColor.black
        eye.position = SCNVector3(0.1, 1.62, 0.26)
        avatar.addChildNode(eye)
        view.scene?.rootNode.addChildNode(avatar)
        view.avatar = avatar

        let ground = SCNNode(geometry: SCNPlane(width: 257, height: 257))
        ground.name = "ground"
        ground.eulerAngles.x = -.pi / 2
        ground.position.y = -0.51
        ground.geometry?.firstMaterial?.diffuse.contents = NSColor(red: 0.15, green: 0.22, blue: 0.22, alpha: 1)
        ground.geometry?.firstMaterial?.lightingModel = .physicallyBased
        view.scene?.rootNode.addChildNode(ground)

        let grid = SCNNode(geometry: SCNPlane(width: 257, height: 257))
        grid.categoryBitMask = 2
        grid.eulerAngles.x = -.pi / 2
        grid.position.y = -0.505
        let gridImage = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.clear.setFill(); rect.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            let path = NSBezierPath()
            path.move(to: .zero); path.line(to: NSPoint(x: 0, y: 32))
            path.move(to: .zero); path.line(to: NSPoint(x: 32, y: 0))
            path.lineWidth = 1; path.stroke()
            return true
        }
        grid.geometry?.firstMaterial?.diffuse.contents = gridImage
        grid.geometry?.firstMaterial?.diffuse.wrapS = .repeat
        grid.geometry?.firstMaterial?.diffuse.wrapT = .repeat
        grid.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeScale(257, 257, 1)
        grid.geometry?.firstMaterial?.isDoubleSided = true
        view.scene?.rootNode.addChildNode(grid)
        view.onPlace = { [weak model] x, y, z in
            guard model?.mode == .create else { return }
            model?.add(x: x, y: y, z: z)
        }
        view.onRemove = { [weak model] x, y, z in
            guard model?.mode == .create else { return }
            model?.remove(x: x, y: y, z: z)
        }
        view.supportHeight = { [weak model] x, z, current in model?.supportHeight(x: x, z: z, from: current) }
        view.spawnPoint = { [weak model] in model?.spawnPoint() ?? (0, 0) }
        return view
    }

    func updateNSView(_ view: BuildingView, context: Context) {
        let wasExploring = view.exploring
        view.perspective = model.roamCamera
        view.exploring = model.mode == .roam
        if wasExploring && model.mode == .create { view.frameWorld(model.blocks) }
        if view.shownRevision != model.revision {
            view.shownRevision = model.revision
            view.frameWorld(model.blocks)
        }
        guard let root = view.scene?.rootNode else { return }
        let existing = Dictionary(uniqueKeysWithValues: root.childNodes.compactMap { node -> (String, SCNNode)? in
            guard let name = node.name, name.hasPrefix("block:") else { return nil }
            return (name, node)
        })
        let desired = Set(model.blocks.map { "block:\($0.x),\($0.y),\($0.z)" })
        for (name, node) in existing where !desired.contains(name) {
            node.removeFromParentNode()
        }
        for block in model.blocks {
            let name = "block:\(block.x),\(block.y),\(block.z)"
            if let node = existing[name] {
                node.geometry?.firstMaterial?.diffuse.contents = block.kind.color
                continue
            }
            let box = SCNBox(width: 0.98, height: 0.98, length: 0.98, chamferRadius: 0.035)
            let material = SCNMaterial()
            material.diffuse.contents = block.kind.color
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.85
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.name = name
            node.position = SCNVector3(block.x, block.y, block.z)
            root.addChildNode(node)
        }
    }
}

struct ContentView: View {
    @StateObject private var model = WorldModel()

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("方块世界").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("创造属于你的 3D 空间").foregroundStyle(.secondary)
                }
                Divider()
                TextField("世界名称", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.mode == .roam)
                if model.mode == .create {
                    Text("选择方块").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(BlockKind.allCases) { kind in
                            Button {
                                model.selectedKind = kind
                            } label: {
                                HStack(spacing: 8) {
                                    RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: kind.color)).frame(width: 23, height: 23)
                                    Text(kind.title)
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(model.selectedKind == kind ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Divider()
                Button("新建世界", systemImage: "plus.square", action: model.newWorld)
                Button("打开世界…", systemImage: "folder", action: model.open)
                Button("保存世界…", systemImage: "square.and.arrow.down", action: model.save)
                Divider()
                Text("地图拼接").font(.headline)
                Picker("方向", selection: $model.mergeDirection) {
                    ForEach(MergeDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .disabled(model.mode == .roam)
                Button("拼接地图…", systemImage: "square.on.square", action: model.mergeWorld)
                    .disabled(model.mode == .roam)
                Button("撤销上次拼接", systemImage: "arrow.uturn.backward", action: model.undoMerge)
                    .disabled(!model.canUndoMerge || model.mode == .roam)
                Text("操作") .font(.headline)
                Text(model.mode == .roam
                     ? "WASD 或方向键：相对镜头移动\n拖动鼠标或 Q/E：转向\n第一人称 / 身后跟随：切换镜头\n点击画面：恢复键盘控制"
                     : "左键点击：放置方块\n右键点击：删除方块\n拖动：旋转视角\n滚轮：缩放\n正面视角：对正建筑")
                    .font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                Text("\(model.blocks.count) 个方块")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
            }
            .frame(width: 270)
            .background(.regularMaterial)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("切换模式").font(.headline)
                    Button { model.mode = .create } label: {
                        Label("创造模式", systemImage: "hammer.fill")
                            .font(.headline)
                            .frame(minWidth: 120)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(model.mode == .create ? Color.accentColor : Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(model.mode == .create ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    Button { model.mode = .roam } label: {
                        Label("漫游模式", systemImage: "figure.walk")
                            .font(.headline)
                            .frame(minWidth: 120)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(model.mode == .roam ? Color.accentColor : Color.secondary.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(model.mode == .roam ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                    if model.mode == .create {
                        Button("正面视角", systemImage: "viewfinder") { model.revision += 1 }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .background(.bar)
                if model.mode == .roam {
                    HStack {
                        Text("镜头视角").font(.callout.weight(.semibold))
                        Picker("镜头视角", selection: $model.roamCamera) {
                            ForEach(RoamCamera.allCases) { camera in
                                Text(camera.title).tag(camera)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 310)
                        Spacer()
                        Text("拖动鼠标或 Q/E 转向")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(.bar)
                }
                WorldScene(model: model)
                HStack {
                    Image(systemName: "cube.transparent")
                    Text(model.status)
                    Spacer()
                    Text("WORLD BUILDER")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(.bar)
            }
        }
        .frame(minWidth: 950, minHeight: 620)
    }
}

@main struct WorldBuilderApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .windowStyle(.titleBar)
    }
}
