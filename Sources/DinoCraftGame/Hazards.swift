import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Something burning through the air: a volcano's lava bomb, a meteorite, or a shooting star that burns up.
final class Fireball {
    enum Kind { case lavaBomb, meteorite, shootingStar }

    let kind: Kind
    var position: DVec3
    var velocity: DVec3
    var age = 0.0
    /// Shooting stars fade out after this long without landing.
    var lifetime = 30.0
    var removed = false
    private var trailTimer = 0.0

    init(kind: Kind, position: DVec3, velocity: DVec3) {
        self.kind = kind
        self.position = position
        self.velocity = velocity
    }

    /// Returns true when it's time to leave another puff of trail.
    func trailDue(_ dt: Double) -> Bool {
        trailTimer -= dt
        guard trailTimer <= 0 else { return false }
        trailTimer = kind == .shootingStar ? 0.02 : 0.04
        return true
    }
}

/// Timers for the world's big events.
struct HazardState {
    var fireballs: [Fireball] = []
    /// The nearest volcano (rescanned every few seconds) and its crater top.
    var volcano: DVec3?
    var volcanoScan = 0.0
    var eruptionTimer = Double.random(in: 40...120)
    var eruptionLeft = 0.0
    var eruptionPuff = 0.0
    var eruptionBomb = 0.0
    /// A meteor shower in progress and when the next star (and the next landing meteorite) comes.
    var showerLeft = 0.0
    var nextStar = 0.0
    var nextMeteorite = 0.0
    var meteoritesLeft = 0
    var lastShowerCheckDay = -1
}

enum Hazards {
    static let volcanoRange = 120.0
    static let showerChance = 0.3
    static let showerLength = 100.0
}

extension GameSession {
    /// Starts an eruption at the nearest volcano (for `/event`). Returns false if none is near.
    @discardableResult
    func startEruption() -> Bool {
        scanForVolcano(force: true)
        guard hazards.volcano != nil else { return false }
        hazards.eruptionTimer = 0
        return true
    }

    func startMeteorShower() {
        hazards.showerLeft = Hazards.showerLength
        hazards.nextStar = 0
        hazards.nextMeteorite = Double.random(in: 6...12)
        hazards.meteoritesLeft = Int.random(in: 2...3)
        onToast?("A meteor shower lights up the sky! Watch for falling meteorites.")
        onSound?("discover", 0.6, 0.7)
    }

    private func scanForVolcano(force: Bool = false) {
        guard force || hazards.volcanoScan <= 0 else { return }
        hazards.volcanoScan = 5
        guard dimension == .overworld, let generator = world.generator as? TerrainGenerator else { hazards.volcano = nil; return }
        let p = player.position
        let found = generator.structures(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: Int(Hazards.volcanoRange)).first { $0.kind == .volcano }
        hazards.volcano = found.map { DVec3(Double($0.x) + 0.5, Double($0.y + TerrainGenerator.volcanoHeight) + 1, Double($0.z) + 0.5) }
    }

    func updateHazards(_ dt: Double) {
        hazards.volcanoScan -= dt
        scanForVolcano()
        updateEruption(dt)
        updateMeteorShower(dt)
        updateFireballs(dt)
        updateWind(dt)
    }

    // MARK: Volcanoes

    private func updateEruption(_ dt: Double) {
        guard let crater = hazards.volcano else { hazards.eruptionLeft = 0; return }
        if hazards.eruptionLeft <= 0 {
            hazards.eruptionTimer -= dt
            // Even between eruptions the crater smokes a little.
            hazards.eruptionPuff -= dt
            if hazards.eruptionPuff <= 0 {
                hazards.eruptionPuff = 1.2
                effectBursts.append((crater, .smoke))
            }
            guard hazards.eruptionTimer <= 0 else { return }
            hazards.eruptionTimer = Double.random(in: 150...360)
            hazards.eruptionLeft = 18
            let distance = simd_distance(crater, player.position)
            onSound?("thunder", Float(max(0.3, 1 - distance / Hazards.volcanoRange)), 0.45)
            if distance < 90 { onToast?("The volcano is erupting! Look out for lava bombs.") }
            advancements.record("eruption")
            return
        }
        hazards.eruptionLeft -= dt
        hazards.eruptionPuff -= dt
        if hazards.eruptionPuff <= 0 {
            hazards.eruptionPuff = 0.15
            effectBursts.append((crater, .smoke))
            if Double.random(in: 0..<1) < 0.5 { effectBursts.append((crater, .lavaSpray)) }
        }
        hazards.eruptionBomb -= dt
        if hazards.eruptionBomb <= 0 {
            hazards.eruptionBomb = Double.random(in: 0.35...0.8)
            let a = Double.random(in: 0..<(2 * .pi)), speed = Double.random(in: 4...11)
            let bomb = Fireball(kind: .lavaBomb, position: crater,
                                velocity: DVec3(cos(a) * speed, Double.random(in: 15...24), sin(a) * speed))
            hazards.fireballs.append(bomb)
        }
    }

    // MARK: Meteor showers

    private func updateMeteorShower(_ dt: Double) {
        // Once a night, a chance of a shower.
        if dimension == .overworld && isNight && hazards.lastShowerCheckDay != day && hazards.showerLeft <= 0 {
            hazards.lastShowerCheckDay = day
            if Double.random(in: 0..<1) < Hazards.showerChance { startMeteorShower() }
        }
        guard hazards.showerLeft > 0 else { return }
        guard dimension == .overworld else { hazards.showerLeft = 0; return }
        hazards.showerLeft -= dt
        hazards.nextStar -= dt
        let p = player.position
        if hazards.nextStar <= 0 {
            hazards.nextStar = Double.random(in: 0.3...1.1)
            let a = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 40...110)
            let start = p + DVec3(cos(a) * r, Double.random(in: 70...110), sin(a) * r)
            let dir = simd_normalize(DVec3(Double.random(in: -1...1), -Double.random(in: 0.25...0.5), Double.random(in: -1...1)))
            let star = Fireball(kind: .shootingStar, position: start, velocity: dir * Double.random(in: 45...70))
            star.lifetime = Double.random(in: 0.8...1.6)
            hazards.fireballs.append(star)
        }
        hazards.nextMeteorite -= dt
        if hazards.nextMeteorite <= 0 && hazards.meteoritesLeft > 0 && !isRemote {
            hazards.nextMeteorite = Double.random(in: 18...32)
            hazards.meteoritesLeft -= 1
            // Aim at open ground a little way off.
            let a = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 22...55)
            let tx = Int(floor(p.x + cos(a) * r)), tz = Int(floor(p.z + sin(a) * r))
            guard world.isLoaded(tx, tz), let ground = world.findStandingY(tx, tz, near: Int(p.y)) else { return }
            let target = DVec3(Double(tx) + 0.5, Double(ground), Double(tz) + 0.5)
            let start = target + DVec3(Double.random(in: -40...40), 95, Double.random(in: -40...40))
            let meteor = Fireball(kind: .meteorite, position: start, velocity: simd_normalize(target - start) * 38)
            hazards.fireballs.append(meteor)
            onSound?("thunder", 0.5, 1.6)
        }
    }

    // MARK: Flight and impact

    private func updateFireballs(_ dt: Double) {
        guard !hazards.fireballs.isEmpty else { return }
        for f in hazards.fireballs where !f.removed {
            f.age += dt
            if f.kind == .lavaBomb { f.velocity.y -= 20 * dt }
            if f.kind == .shootingStar && f.age > f.lifetime { f.removed = true; continue }
            if f.age > 30 { f.removed = true; continue }
            let steps = 3
            for _ in 0..<steps {
                f.position += f.velocity * (dt / Double(steps))
                let b = BlockPos(Int(floor(f.position.x)), Int(floor(f.position.y)), Int(floor(f.position.z)))
                if f.kind != .shootingStar && (blocks.isSolid[Int(world.block(b))] || blocks.isWet[Int(world.block(b))]) {
                    impact(f, at: b)
                    break
                }
            }
            if !f.removed && f.trailDue(dt) { effectBursts.append((f.position, f.kind == .shootingStar ? .starTrail : .trail)) }
            if f.position.y < -80 { f.removed = true }
        }
        hazards.fireballs.removeAll { $0.removed }
    }

    private func impact(_ f: Fireball, at b: BlockPos) {
        f.removed = true
        let center = DVec3(Double(b.x) + 0.5, Double(b.y) + 1, Double(b.z) + 0.5)
        effectBursts.append((center, .impact))
        let distance = simd_distance(center, player.position)
        let loud = Float(max(0.15, 1 - distance / 80))
        onSound?(f.kind == .meteorite ? "thunder" : "break_stone", loud, f.kind == .meteorite ? 0.8 : 0.6)
        let reach = f.kind == .meteorite ? 5.0 : 2.8
        if distance < reach {
            let away = player.position - center
            let flat = simd_length(DVec3(away.x, 0, away.z)) > 0.01 ? simd_normalize(DVec3(away.x, 0, away.z)) : DVec3(1, 0, 0)
            takeDamage(f.kind == .meteorite ? 12 : 6, cause: f.kind == .meteorite ? "Hit by a meteorite" : "Hit by a lava bomb", knockback: flat)
        }
        guard !isRemote, dimension == .overworld else { return }
        if f.kind == .lavaBomb {
            // Bombs leave a lump of glowing rock where they land.
            let above = b.offset(.up)
            if world.block(above) == Blocks.air && Double.random(in: 0..<1) < 0.6 { naturalPlace(above, Blocks.magmaRock) }
            return
        }
        // A meteorite: blast a small crater and leave the meteorite in the bottom.
        let r = 2.6
        for dy in -3...2 {
            for dz in -3...3 {
                for dx in -3...3 {
                    let d = (Double(dx * dx + dz * dz) + Double(dy * dy) * 1.4).squareRoot()
                    guard d <= r else { continue }
                    let p = BlockPos(b.x + Int32(dx), b.y + Int32(dy), b.z + Int32(dz))
                    let id = world.block(p)
                    guard id != Blocks.air, id != Blocks.bedrock, blocks[id]?.isBreakable == true else { continue }
                    naturalPlace(p, Blocks.air)
                }
            }
        }
        let bottom = BlockPos(b.x, b.y - 2, b.z)
        naturalPlace(bottom, Blocks.meteoriteOre)
        for face in [BlockFace.north, .south, .east, .west] where Double.random(in: 0..<1) < 0.45 {
            naturalPlace(bottom.offset(face), Blocks.meteoriteOre)
        }
        for face in [BlockFace.north, .south, .east, .west] {
            let ring = bottom.offset(face).offset(face)
            if world.block(ring) != Blocks.air { naturalPlace(ring, Blocks.magmaRock) }
        }
        if distance < 90 { onToast?("A meteorite crashed nearby! Mine it with an iron pickaxe or better.") }
        advancements.record("meteorite")
        Log.info("Meteorite landed at \(bottom)", category: "Game")
    }

    // MARK: Storm wind

    private func updateWind(_ dt: Double) {
        guard weather.kind == .storm, dimension == .overworld, !player.inWater, !player.flying, riding == nil, !spectator else { return }
        let wind = weather.wind
        guard simd_length(wind) > 0.5, world.light(at: player.eyePosition).sky > 0.9 else { return }
        // Out in the open the gusts shove you along.
        player.velocity += DVec3(Double(wind.x), 0, Double(wind.y)) * 0.45 * dt
    }
}
