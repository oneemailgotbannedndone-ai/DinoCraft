import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif

public enum GameMode: String, Codable, CaseIterable, Sendable {
    case survival, creative
    public var displayName: String { self == .survival ? "Survival" : "Creative" }
}

public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case peaceful, easy, normal, hard
    public var displayName: String { rawValue.capitalized }
}

/// Per-frame movement intent, produced by the input layer.
public struct MovementInput: Sendable {
    public var forward: Double = 0      // -1 ... 1
    public var strafe: Double = 0       // -1 (left) ... 1 (right)
    public var jump = false             // held
    public var jumpPressed = false      // pressed this frame
    public var sprint = false
    public var sneak = false
    public init() {}
}

public enum PlayerEvent: Sendable {
    case footstep(BlockID)
    case jumped
    case landed(fallDistance: Double, onBlock: BlockID)
    case enteredWater
    case exitedWater
    case startedFlying
    case stoppedFlying
}

/// First-person movement and voxel collision. Input-agnostic and deterministic
/// for a given sequence of inputs, which makes it unit-testable.
public final class PlayerController {
    public struct Tuning {
        public var walkSpeed = 4.3
        public var sprintSpeed = 7.4
        public var sneakSpeed = 1.35
        public var swimSpeed = 2.4
        public var flySpeed = 10.9
        public var flySprintSpeed = 21.6
        public var gravity = 28.0
        public var jumpVelocity = 8.6
        public var terminalVelocity = 60.0
        public var groundAccel = 16.0
        public var airAccel = 3.2
        public var waterGravity = 7.0
        public init() {}
    }

    public var tuning = Tuning()
    public var position: DVec3            // feet centre
    public var velocity = DVec3.zero
    public var yaw: Double = 0
    public var pitch: Double = 0
    public var width = 0.6
    public var standingHeight = 1.8
    public var sneakingHeight = 1.5

    public var gameMode: GameMode = .survival
    public private(set) var flying = false
    /// Lets Survival players fly too (the /fly command).
    public var allowFlight = false
    public private(set) var onGround = false
    public private(set) var inWater = false
    public private(set) var headInWater = false
    public private(set) var isSprinting = false
    public private(set) var isSneaking = false
    public private(set) var collidedHorizontally = false
    public private(set) var horizontalSpeed: Double = 0

    private var fallStartY: Double?
    private var stepDistance = 0.0
    private var lastJumpPressTime = -1.0
    private var clock = 0.0
    private var scratch: [DBox] = []

    public var events: [PlayerEvent] = []

    public init(position: DVec3) {
        self.position = position
    }

    public var height: Double { isSneaking && !flying ? sneakingHeight : standingHeight }
    public var eyeHeight: Double { isSneaking && !flying ? 1.32 : 1.62 }
    public var eyePosition: DVec3 { position + DVec3(0, eyeHeight, 0) }

    public var box: DBox {
        let hw = width / 2
        return DBox(min: DVec3(position.x - hw, position.y, position.z - hw),
                    max: DVec3(position.x + hw, position.y + height, position.z + hw))
    }

    public var lookDirection: DVec3 {
        DVec3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    public func setFlying(_ value: Bool) {
        guard value != flying else { return }
        if value && gameMode != .creative && !allowFlight { return }
        flying = value
        events.append(value ? .startedFlying : .stoppedFlying)
        if value { velocity.y = 0; fallStartY = nil }
    }

    public func teleport(to p: DVec3) {
        position = p
        velocity = .zero
        fallStartY = nil
    }

    /// Advances physics by `dt` seconds, sub-stepping for stable collisions.
    public func update(dt: Double, input: MovementInput, world: BlockSource) {
        let total = min(dt, 0.1)
        if gameMode != .creative && !allowFlight && flying { setFlying(false) }

        if input.jumpPressed {
            if (gameMode == .creative || allowFlight) && clock - lastJumpPressTime < 0.3 {
                setFlying(!flying)
                lastJumpPressTime = -1
            } else {
                lastJumpPressTime = clock
            }
        }

        let steps = max(1, Int(ceil(total / (1.0 / 120.0))))
        let h = total / Double(steps)
        for i in 0..<steps {
            var stepInput = input
            if i > 0 { stepInput.jumpPressed = false }
            step(h, stepInput, world)
        }
    }

    private func step(_ dt: Double, _ input: MovementInput, _ world: BlockSource) {
        clock += dt
        let reg = world.registry
        let wasInWater = inWater
        let hw = width / 2
        let body = DBox(min: DVec3(position.x - hw, position.y + 0.1, position.z - hw),
                        max: DVec3(position.x + hw, position.y + 0.9, position.z + hw))
        inWater = VoxelPhysics.anyBlock(world, in: body) { reg.shape[Int($0)] == .liquid }
        let eye = eyePosition
        if let id = world.blockIfLoaded(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))) {
            headInWater = reg.shape[Int(id)] == .liquid
        } else {
            headInWater = false
        }
        if inWater != wasInWater { events.append(inWater ? .enteredWater : .exitedWater) }

        // Sneak state (can't stand up under a ceiling).
        let wantsSneak = input.sneak && !flying
        if wantsSneak {
            isSneaking = true
        } else if isSneaking {
            let standBox = DBox(min: DVec3(position.x - hw, position.y, position.z - hw),
                                max: DVec3(position.x + hw, position.y + standingHeight, position.z + hw))
            if !VoxelPhysics.collides(world, standBox, scratch: &scratch) { isSneaking = false }
        }

        let moving = abs(input.forward) > 0.01 || abs(input.strafe) > 0.01
        if input.sprint && input.forward > 0.1 && !isSneaking && (flying || !collidedHorizontally) {
            isSprinting = true
        } else if !moving || input.forward <= 0.1 || isSneaking {
            isSprinting = false
        }

        // Desired horizontal velocity in world space.
        var fwd = input.forward, str = input.strafe
        let len = sqrt(fwd * fwd + str * str)
        if len > 1 { fwd /= len; str /= len }
        let sinY = sin(yaw), cosY = cos(yaw)
        let dirX = -sinY * fwd + cosY * str
        let dirZ = -cosY * fwd - sinY * str

        let speed: Double
        if flying {
            speed = isSprinting ? tuning.flySprintSpeed : tuning.flySpeed
        } else if inWater {
            speed = tuning.swimSpeed * (isSprinting ? 1.35 : 1)
        } else if isSneaking {
            speed = tuning.sneakSpeed
        } else {
            speed = isSprinting ? tuning.sprintSpeed : tuning.walkSpeed
        }
        let targetX = dirX * speed, targetZ = dirZ * speed
        let accel = flying ? 10.0 : (onGround ? tuning.groundAccel : (inWater ? 6.0 : tuning.airAccel))
        let blend = 1 - exp(-accel * dt)
        velocity.x += (targetX - velocity.x) * blend
        velocity.z += (targetZ - velocity.z) * blend

        // Vertical
        if flying {
            var vy = 0.0
            if input.jump { vy += speed * 0.75 }
            if input.sneak { vy -= speed * 0.75 }
            velocity.y += (vy - velocity.y) * (1 - exp(-12 * dt))
        } else if inWater {
            velocity.y -= tuning.waterGravity * dt
            velocity.y *= exp(-2.2 * dt)
            if input.jump {
                velocity.y = min(velocity.y + 22 * dt, collidedHorizontally ? 5.0 : 3.4)
            }
            fallStartY = nil
        } else {
            if input.jump && onGround {
                velocity.y = tuning.jumpVelocity
                onGround = false
                events.append(.jumped)
            }
            velocity.y -= tuning.gravity * dt
            velocity.y = max(velocity.y, -tuning.terminalVelocity)
        }

        move(velocity * dt, world, sneakEdge: isSneaking && onGround)

        horizontalSpeed = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)

        // Fall tracking & landing
        if onGround || flying || inWater {
            if let start = fallStartY, onGround {
                let dist = start - position.y
                let below = world.blockIfLoaded(Int(floor(position.x)), Int(floor(position.y - 0.2)), Int(floor(position.z))) ?? Blocks.air
                events.append(.landed(fallDistance: dist, onBlock: below))
            }
            fallStartY = nil
        } else {
            if fallStartY == nil || position.y > fallStartY! { fallStartY = position.y }
        }

        // Footsteps
        if onGround && !flying {
            stepDistance += horizontalSpeed * dt
            let stride = isSprinting ? 2.3 : 1.9
            if stepDistance > stride {
                stepDistance = 0
                let below = world.blockIfLoaded(Int(floor(position.x)), Int(floor(position.y - 0.2)), Int(floor(position.z))) ?? Blocks.air
                events.append(.footstep(below))
            }
        } else if inWater && horizontalSpeed > 0.5 {
            stepDistance += horizontalSpeed * dt
            if stepDistance > 2.6 { stepDistance = 0; events.append(.footstep(Blocks.water)) }
        }
    }

    private func move(_ delta: DVec3, _ world: BlockSource, sneakEdge: Bool) {
        var box = self.box
        var dx = delta.x, dy = delta.y, dz = delta.z

        if sneakEdge {
            // Keep the player on the ledge while sneaking.
            let probe = 0.05
            func supported(_ ox: Double, _ oz: Double) -> Bool {
                VoxelPhysics.collides(world, box.offset(DVec3(ox, -0.6, oz)), scratch: &scratch)
            }
            while dx != 0 && !supported(dx, 0) { dx = abs(dx) < probe ? 0 : dx - probe * (dx > 0 ? 1 : -1) }
            while dz != 0 && !supported(0, dz) { dz = abs(dz) < probe ? 0 : dz - probe * (dz > 0 ? 1 : -1) }
            while dx != 0 && dz != 0 && !supported(dx, dz) {
                dx = abs(dx) < probe ? 0 : dx - probe * (dx > 0 ? 1 : -1)
                dz = abs(dz) < probe ? 0 : dz - probe * (dz > 0 ? 1 : -1)
            }
        }

        let sweep = box.expanded(DVec3(dx, dy, dz))
        VoxelPhysics.colliders(world, in: DBox(min: sweep.min - 0.01, max: sweep.max + 0.01), into: &scratch)
        let colliders = scratch

        let origY = dy, origX = dx, origZ = dz
        for c in colliders { dy = VoxelPhysics.clipY(c, box, dy) }
        box = box.offset(DVec3(0, dy, 0))
        for c in colliders { dx = VoxelPhysics.clipX(c, box, dx) }
        box = box.offset(DVec3(dx, 0, 0))
        for c in colliders { dz = VoxelPhysics.clipZ(c, box, dz) }
        box = box.offset(DVec3(0, 0, dz))

        position = DVec3((box.min.x + box.max.x) / 2, box.min.y, (box.min.z + box.max.z) / 2)
        onGround = origY < 0 && dy != origY
        if dy != origY { velocity.y = 0 }
        collidedHorizontally = dx != origX || dz != origZ
        if dx != origX { velocity.x = 0 }
        if dz != origZ { velocity.z = 0 }
        if flying && onGround { setFlying(false) }
    }
}
