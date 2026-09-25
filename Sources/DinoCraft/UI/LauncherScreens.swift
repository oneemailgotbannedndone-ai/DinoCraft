import AppKit
import Foundation
import DinoCraftCore
@testable import DinoCraftGame

// MARK: - Launcher

/// The pre-launcher shown when DinoCraft opens: news about the newest build, the update button,
/// cosmetics, settings and Play (which goes on to the main menu underneath).
final class LauncherScreen: Screen {
    private var installError: String?
    /// Shows the guide to beating DinoCraft instead of the news.
    private var showingGuide = false
    /// Reviews and friends' games are checked once, when the launcher first shows.
    private var primed = false

    override var scene: GameActivityState.Scene { .mainMenu }
    override func back(_ engine: GameEngine) {}

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let intro = appear(0, duration: 0.6)
        if !primed {
            primed = true
            GameLinks.reviews.load()
            FriendList.shared.refreshStatuses()
        }
        d.opacity = intro

        let titleY = max(30, H * 0.06)
        d.outlinedText(Brand.title, x: W / 2, y: titleY, size: Brand.title.count > 9 ? 70 : 80, fill: Color(hex: Brand.top),
                       fillBottom: Color(hex: Brand.bottom), outline: Color(hex: 0x2A1740), outlineWidth: 6, tracking: 0.005)
        d.text(e.options.launcherOnly ? "DINOCRAFT LAUNCHER" : "LAUNCHER", x: W / 2, y: titleY + 96, size: 14, color: Theme.text.alpha(0.85), face: .display, align: .center,
               tracking: 0.2, shadow: Color(linear: 0, 0, 0, 0.7))

        // News
        let top = titleY + 140
        let panelW = min(640, W * 0.5), panelX = max(30, W / 2 - panelW - 20)
        let panelH = max(260, H - top - 70)
        let panel = Rect(panelX, top, panelW, panelH)
        ui.panel(panel, radius: 20)
        var y = panel.y + 26
        let textW = panel.w - 56
        func line(_ text: String, _ size: Float, _ color: Color, face: FontFace = .body) {
            guard y < panel.maxY - 30 else { return }
            d.text(text, x: panel.x + 28, y: y, size: size, color: color, face: face, maxWidth: textW)
            y += size * 1.45
        }
        func wrapped(_ text: String, _ size: Float, _ color: Color) {
            var current = ""
            for word in text.split(separator: " ") {
                let next = current.isEmpty ? String(word) : current + " " + word
                if d.font.measure(next, size: size) > textW && !current.isEmpty {
                    line(current, size, color)
                    current = String(word)
                } else {
                    current = next
                }
            }
            if !current.isEmpty { line(current, size, color) }
        }
        if showingGuide {
            line("How to beat DinoCraft", 26, Theme.amber, face: .display)
            y += 4
            for (i, step) in GameGuide.steps.enumerated() {
                line("\(i + 1). \(step.title)", 16, Theme.text, face: .display)
                wrapped(step.hint, 14, Theme.textMuted)
                y += 4
            }
            wrapped("In game, press G to show or hide your next goal.", 14, Theme.jungle)
        } else if let release = e.updater.latestRelease, release.build > BuildInfo.current.build {
            line("New in the update", 26, Theme.amber, face: .display)
            y += 4
            line(release.title + (release.published.isEmpty ? "" : "  ·  \(release.published)"), 16, Theme.text)
            y += 6
            for raw in release.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
                if text.isEmpty { y += 8; continue }
                wrapped(text, 15, Theme.textMuted)
            }
        } else if !BuildInfo.whatsNew.isEmpty {
            line("What's new", 26, Theme.amber, face: .display)
            y += 4
            for (i, raw) in BuildInfo.whatsNew.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = raw.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { y += 8; continue }
                wrapped(text, 15, i == 0 || !text.hasPrefix("-") ? Theme.text : Theme.textMuted)
            }
        } else {
            line("Welcome, explorer!", 26, Theme.amber, face: .display)
            y += 6
            for tip in ["Press Play to pick a world or join a friend.",
                        "Cosmetics: choose a hat, outfit, cape or dino tail. Friends see it in multiplayer.",
                        "Settings: texture packs, shader packs, controls and more.",
                        "The launcher checks for new versions each time it opens."] {
                wrapped(tip, 15, Theme.textMuted)
                y += 6
            }
        }

        // Buttons
        let bx = panel.maxX + 40, bw = min(400, W - bx - 30), bh: Float = 56, gap: Float = 14
        var by = top
        if ui.button("launcher.play", "Play", Rect(bx, by, bw, bh + 8), style: .primary) {
            if e.options.launcherOnly { e.launchGameApp() } else { e.popScreen() }
            return
        }
        by += bh + 8 + gap

        var label = "Check for Updates", enabled = true, style = ButtonStyle.secondary
        var status = BuildInfo.current.displayName
        var action: (() -> Void)? = { e.updater.check() }
        switch e.updater.state {
        case .idle:
            break
        case .checking:
            label = "Checking for Updates…"; enabled = false; action = nil
        case .upToDate(let release):
            label = "Up to Date"
            status = release.map { BuildInfo.current.isDevelopment ? "Newest release is build \($0.build)" : "You have the newest build (\($0.build))" }
                ?? "No releases published yet"
        case .available(let release, let canInstall):
            if canInstall {
                label = "Update to Build \(release.build)"; style = .primary
                action = { e.updater.download() }
                status = "A new version is ready to download"
            } else {
                label = "Build \(release.build) Available"; enabled = false; action = nil
                status = BuildInfo.current.isDevelopment ? "This copy was built by hand, so it can't update itself"
                    : "This release has no Mac download yet"
            }
        case .downloading(let release, let fraction):
            label = "Downloading… \(Int(fraction * 100))%"; enabled = false; action = nil
            status = "Build \(release.build)"
            d.fill(Rect(bx, by + bh + 3, bw, 5), Color(linear: 0, 0, 0, 0.45), radius: 2.5)
            d.fill(Rect(bx, by + bh + 3, bw * Float(fraction), 5), Theme.amber, radius: 2.5)
        case .downloaded(let release, let file):
            label = "Restart to Update"; style = .primary
            status = "Build \(release.build) downloaded"
            action = { [weak self] in
                if let error = MacUpdater.install(zip: file) {
                    self?.installError = error
                } else {
                    e.quitGame()
                }
            }
        case .failed(let reason):
            label = "Try Again"
            status = reason
        }
        if ui.button("launcher.update", label, Rect(bx, by, bw, bh), style: style, enabled: enabled), let action { action() }
        by += bh + 12
        d.text(installError ?? status, x: bx, y: by, size: 13.5, color: installError != nil ? Theme.danger : Theme.textMuted, maxWidth: bw)
        by += 30
        if ui.button("launcher.cosmetics", "Cosmetics", Rect(bx, by, bw, bh), style: .secondary) { e.pushScreen(CosmeticsScreen()) }
        by += bh + gap
        if ui.button("launcher.skin", "Skin Creator", Rect(bx, by, bw, bh), style: .secondary) { e.pushScreen(SkinCreatorScreen()) }
        by += bh + gap
        if ui.button("launcher.settings", "Settings", Rect(bx, by, bw, bh), style: .secondary) { e.pushScreen(SettingsScreen()) }
        by += bh + gap
        if ui.button("launcher.guide", showingGuide ? "What's New" : "How to Beat the Game", Rect(bx, by, bw, bh), style: .secondary) {
            showingGuide.toggle()
        }
        by += bh + gap
        let halfW = (bw - gap) / 2
        if ui.button("launcher.friends", FriendList.shared.buttonLabel, Rect(bx, by, halfW, bh), style: .secondary) {
            FriendList.shared.refreshStatuses()
            e.pushScreen(FriendsScreen())
        }
        if ui.button("launcher.reviews", GameLinks.reviews.buttonLabel, Rect(bx + halfW + gap, by, halfW, bh), style: .secondary) {
            GameLinks.reviews.load()
            e.pushScreen(ReviewsScreen())
        }
        by += bh + gap
        if ui.button("launcher.quit", "Quit", Rect(bx, by, bw, bh), style: .secondary) { e.quitGame() }

        d.text("DinoCraft \(e.versionString) · \(BuildInfo.current.displayName)", x: 22, y: H - 34, size: 13, color: Theme.textMuted,
               shadow: Color(linear: 0, 0, 0, 0.6))
        let worlds = e.storage.listWorlds()
        let played = worlds.reduce(0) { $0 + $1.playTimeSeconds }
        let who = e.settings.username.isEmpty ? "no name yet" : e.settings.username
        d.text("\(worlds.count) world\(worlds.count == 1 ? "" : "s") · \(Int(played / 3600))h \(Int(played / 60) % 60)m played · \(who)",
               x: panel.x + 4, y: panel.maxY + 12, size: 13.5, color: Theme.textMuted, shadow: Color(linear: 0, 0, 0, 0.6))
        if ui.button("launcher.folder", "Open Game Folder", Rect(W - 222, H - 50, 200, 36), style: .ghost, fontSize: 14) {
            NSWorkspace.shared.open(GamePaths.root)
        }
        if let donate = GameLinks.donate,
           ui.button("launcher.donate", GameLinks.donateLabel, Rect(W - 444, H - 50, 210, 36), style: .primary, fontSize: 14) {
            NSWorkspace.shared.open(donate)
        }
        d.opacity = 1
    }
}

// MARK: - Cosmetics

/// Choose a hat, outfit colours and something to wear on your back. Friends see it in multiplayer.
/// Your one-of-a-kind player card, your friends (and whether they're hosting right now) and the
/// players you've recently been in a game with.
final class FriendsScreen: Screen {
    private var note: String?
    private var scroll = 0

    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let friends = FriendList.shared
        let me = e.settings
        let panel = Rect(max(30, W / 2 - 560), max(30, H / 2 - 350), min(1120, W - 60), min(700, H - 60))
        ui.panel(panel, title: "Friends")
        d.text("Add friends with their friend code. Play together once and they show up here too.", x: panel.midX, y: panel.y + 66,
               size: 14, color: Theme.textMuted, align: .center)

        // Your card
        let card = Rect(panel.x + 30, panel.y + 100, 300, panel.h - 190)
        d.fill(card, Color(linear: 0, 0, 0, 0.25), radius: 18)
        let look = PlayerLook(encoded: me.cosmetics) ?? PlayerLook.oneOfOne(id: me.playerID)
        CosmeticsScreen.drawFront(d, look, in: Rect(card.x + 60, card.y + 10, card.w - 120, card.h * 0.45))
        var y = card.y + card.h * 0.47
        d.text(PlayerIdentity.display(name: me.username, id: me.playerID), x: card.midX, y: y, size: 22, color: Theme.amber, align: .center)
        y += 34
        d.text("1 of 1", x: card.midX, y: y, size: 20, color: Theme.jungle, align: .center)
        y += 28
        d.text("Nobody else has your tag", x: card.midX, y: y, size: 13.5, color: Theme.textMuted, align: .center)
        y += 30
        if ui.button("friends.copy", "Copy My Friend Code", Rect(card.x + 16, y, card.w - 32, 44), style: .primary, fontSize: 15) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(friends.myCode(name: me.username, id: me.playerID), forType: .string)
            note = "Friend code copied! Send it to a friend."
        }
        y += 54
        if ui.button("friends.add", "Add Friend (Paste Code)", Rect(card.x + 16, y, card.w - 32, 44), style: .secondary, fontSize: 15) {
            if let text = NSPasteboard.general.string(forType: .string) {
                note = friends.add(code: text, myID: me.playerID)
                friends.refreshStatuses()
            } else {
                note = "Copy your friend's code first, then press this."
            }
        }
        y += 56
        if let note { d.text(note, x: card.x + 16, y: y, size: 13.5, color: Theme.amber, maxWidth: card.w - 32) }

        // Friends and recent players
        let list = Rect(card.maxX + 24, card.y, panel.maxX - 30 - card.maxX - 24, card.h)
        d.fill(list, Color(linear: 0, 0, 0, 0.25), radius: 18)
        let rowH: Float = 62
        let rows = friends.friends.map { ($0, true) } + friends.recent.map { ($0, false) }
        let visible = max(1, Int((list.h - 70) / rowH))
        if list.contains(ui.mouse) && ui.input.scroll != 0 { scroll -= Int(ui.input.scroll.rounded()) }
        scroll = max(0, min(max(0, rows.count - visible), scroll))
        y = list.y + 16
        if rows.isEmpty {
            d.text("No friends yet.", x: list.midX, y: y + 60, size: 20, color: Theme.text, align: .center)
            d.text("Copy your friend code and send it to someone, or join a friend's game.", x: list.midX, y: y + 92, size: 14,
                   color: Theme.textMuted, align: .center)
        }
        d.text("Friends (\(friends.friends.count))", x: list.x + 18, y: y, size: 15, color: Theme.amber)
        y += 26
        var shownRecent = false
        for (person, isFriend) in rows.dropFirst(scroll).prefix(visible) {
            if !isFriend && !shownRecent {
                shownRecent = true
                d.text("Played with recently", x: list.x + 18, y: y, size: 15, color: Theme.amber)
                y += 26
            }
            guard y + rowH < list.maxY else { break }
            let face = Rect(list.x + 18, y, 40, rowH - 10)
            d.fill(face, Color(linear: 0, 0, 0, 0.3), radius: 6)
            CosmeticsScreen.drawFront(d, PlayerLook.resolve(person.look, name: person.name), in: face)
            d.text(person.display, x: face.maxX + 14, y: y + 4, size: 16, color: Theme.text)
            let status = friends.status(person.id)
            var line: String
            var lineColor = Theme.textMuted
            switch status {
            case .hosting(let world, let players):
                line = "Playing \(world) · \(players) player\(players == 1 ? "" : "s") · you can join!"
                lineColor = Theme.jungle
            case .checking: line = "Checking…"
            case .offline: line = "Not hosting right now"
            case .unknown: line = person.address == nil ? "Hasn't shared where they host yet" : "Press Refresh to check"
            }
            if !isFriend { line = person.lastPlayed.map { "Played together " + FriendsScreen.relative($0) } ?? "Played together" }
            d.text(line, x: face.maxX + 14, y: y + 28, size: 13.5, color: lineColor)
            let bw: Float = 120, bh: Float = 38, by = y + (rowH - 10 - bh) / 2
            if isFriend {
                var canJoin = false
                if case .hosting = status { canJoin = person.address != nil }
                if ui.button("friends.join.\(person.id)", "Join", Rect(list.maxX - 2 * bw - 28, by, bw, bh), style: .primary,
                             enabled: canJoin, fontSize: 15), let address = person.address {
                    if e.options.launcherOnly { e.launchGameApp(join: address) } else { e.joinGame(address: address) }
                }
                if ui.button("friends.remove.\(person.id)", "Remove", Rect(list.maxX - bw - 18, by, bw, bh), style: .secondary, fontSize: 15) {
                    friends.remove(person.id)
                    note = "Removed \(person.display)."
                }
            } else if ui.button("friends.befriend.\(person.id)", "Add Friend", Rect(list.maxX - bw - 18, by, bw, bh), style: .primary, fontSize: 15) {
                friends.befriend(person.id)
                friends.refreshStatuses()
                note = "\(person.display) is now your friend!"
            }
            y += rowH
        }

        if ui.button("friends.refresh", "Refresh", Rect(panel.midX - 250, panel.maxY - 64, 240, 46), style: .secondary) { friends.refreshStatuses() }
        if ui.button("friends.back", "Back", Rect(panel.midX + 10, panel.maxY - 64, 240, 46), style: .secondary) { e.popScreen() }
    }

    /// "today", "yesterday" or "3 days ago".
    static func relative(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        return days <= 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
    }
}

/// Everyone's reviews (read from GitHub), the average rating, and a star picker that opens a
/// pre-filled page for writing your own.
final class ReviewsScreen: Screen {
    private var stars = 5
    private var words = ""
    private var note: String?

    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let panel = Rect(max(30, W / 2 - 480), max(30, H / 2 - 340), min(960, W - 60), min(680, H - 60))
        ui.panel(panel, title: "Player Reviews")
        let board = GameLinks.reviews
        let gold = Color(hex: 0xFFCC40), dimStar = Color(hex: 0x6A5E80)
        func starRow(_ n: Int, x: Float, y: Float, size: Float) {
            for k in 0..<5 { d.text("\u{2605}", x: x + Float(k) * size * 1.05, y: y, size: size, color: k < n ? gold : dimStar, face: .display) }
        }
        var y = panel.y + 76
        let left = panel.x + 34, textW = panel.w - 68
        let listBottom = panel.maxY - 200
        switch board.state {
        case .idle, .loading:
            d.text("Loading reviews…", x: panel.midX, y: y + 30, size: 16, color: Theme.textMuted, align: .center)
        case .failed(let reason):
            d.text(reason, x: panel.midX, y: y + 30, size: 16, color: Theme.danger, align: .center, maxWidth: textW)
        case .loaded(let list):
            if list.isEmpty {
                d.text("No reviews yet. Be the first!", x: panel.midX, y: y + 30, size: 16, color: Theme.textMuted, align: .center)
            } else {
                starRow(Int(board.average.rounded()), x: left, y: y, size: 26)
                d.text(String(format: "%.1f out of 5 from %d review%@", board.average, list.count, list.count == 1 ? "" : "s"),
                       x: left + 150, y: y + 4, size: 17, color: Theme.text)
                y += 44
                for review in list {
                    guard y < listBottom - 40 else { break }
                    starRow(review.stars, x: left, y: y, size: 15)
                    d.text("\(review.author)  ·  \(review.date)", x: left + 92, y: y, size: 14, color: Theme.amber)
                    y += 22
                    d.text(review.text, x: left, y: y, size: 14, color: Theme.textMuted, maxWidth: textW)
                    y += 30
                }
            }
        }
        // Your review: stars and a few words, posted on GitHub (anyone with a free account can post)
        let rowY = panel.maxY - 184
        d.text("Your rating", x: left, y: rowY + 10, size: 16, color: Theme.text, face: .display)
        for k in 1...5 {
            if ui.button("reviews.star\(k)", "\u{2605}", Rect(left + 130 + Float(k - 1) * 50, rowY, 44, 40), style: k <= stars ? .primary : .secondary) {
                stars = k
            }
        }
        let submitted = ui.textField("reviews.words", Rect(left, rowY + 50, textW - 280, 44), &words,
                                     placeholder: "Type your review here…", maxLength: 240)
        if ui.button("reviews.post", "Post Review", Rect(panel.maxX - 294, rowY + 50, 260, 44), style: .primary) || submitted,
           let url = board.writeURL(stars: stars, username: e.settings.username, words: words) {
            if NSWorkspace.shared.open(url) {
                words = ""
                note = nil
            } else {
                note = "Couldn't open your browser. Go to github.com/\(board.repository)/issues/new to post."
            }
        }
        d.text(note ?? "Opens GitHub with your review filled in: sign in (free) and press Create to post it.",
               x: left, y: rowY + 104, size: 13, color: Theme.textMuted, maxWidth: textW)
        if ui.button("reviews.refresh", "Refresh", Rect(panel.midX - 250, panel.maxY - 58, 240, 44), style: .secondary) { board.load() }
        if ui.button("reviews.back", "Back", Rect(panel.midX + 10, panel.maxY - 58, 240, 44), style: .secondary) { e.popScreen() }
    }
}

final class CosmeticsScreen: Screen {
    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let panel = Rect(max(30, W / 2 - 520), max(30, H / 2 - 330), min(1040, W - 60), min(660, H - 60))
        ui.panel(panel, title: "Cosmetics")
        d.text("Friends see your look in multiplayer, on Mac and Windows.", x: panel.midX, y: panel.y + 66, size: 14,
               color: Theme.textMuted, align: .center)

        var look = PlayerLook(encoded: e.settings.cosmetics) ?? PlayerLook.oneOfOne(id: e.settings.playerID)
        let before = look

        // Front view of the explorer, drawn from the same boxes the 3D model uses.
        let preview = Rect(panel.x + 40, panel.y + 110, panel.w * 0.36, panel.h - 200)
        d.fill(preview, Color(linear: 0, 0, 0, 0.25), radius: 18)
        CosmeticsScreen.drawFront(d, look, in: preview)

        // Choices
        let x = preview.maxX + 40, w = panel.maxX - 40 - x
        var y = panel.y + 110
        let rowH: Float = 50
        func row(_ id: String, _ title: String, _ value: String, minus: () -> Void, plus: () -> Void) {
            d.fill(Rect(x, y, w, rowH), Color(linear: 0, 0, 0, 0.22), radius: 12)
            d.text(title, x: x + 16, y: y + 15, size: 17, color: Theme.text)
            let bw: Float = 44, valueW: Float = min(220, w * 0.45)
            let bx = x + w - bw * 2 - valueW - 8
            if ui.button(id + ".minus", "‹", Rect(bx, y + 5, bw, rowH - 10), style: .secondary, fontSize: 22) { minus() }
            d.text(value, x: bx + bw + valueW / 2, y: y + 15, size: 17, color: Theme.amber, align: .center)
            if ui.button(id + ".plus", "›", Rect(bx + bw + valueW, y + 5, bw, rowH - 10), style: .secondary, fontSize: 22) { plus() }
            y += rowH + 10
        }
        func cycle(_ i: inout Int, _ count: Int, _ step: Int) { i = (i + step + count) % count }
        let hats = PlayerLook.Hat.allCases, backs = PlayerLook.Back.allCases
        var hatIndex = hats.firstIndex(of: look.hat) ?? 0, backIndex = backs.firstIndex(of: look.back) ?? 0
        row("cos.hat", "Hat", look.hat.displayName, minus: { cycle(&hatIndex, hats.count, -1) }, plus: { cycle(&hatIndex, hats.count, 1) })
        row("cos.shirt", "Shirt", PlayerLook.shirtNames[look.shirt], minus: { cycle(&look.shirt, PlayerLook.shirtColors.count, -1) },
            plus: { cycle(&look.shirt, PlayerLook.shirtColors.count, 1) })
        row("cos.pants", "Trousers", PlayerLook.pantsNames[look.pants], minus: { cycle(&look.pants, PlayerLook.pantsColors.count, -1) },
            plus: { cycle(&look.pants, PlayerLook.pantsColors.count, 1) })
        row("cos.skin", "Skin", PlayerLook.skinNames[look.skin], minus: { cycle(&look.skin, PlayerLook.skinTones.count, -1) },
            plus: { cycle(&look.skin, PlayerLook.skinTones.count, 1) })
        row("cos.back", "On your back", look.back.displayName, minus: { cycle(&backIndex, backs.count, -1) }, plus: { cycle(&backIndex, backs.count, 1) })
        row("cos.accent", "Accent colour", PlayerLook.accentNames[look.accent],
            minus: { cycle(&look.accent, PlayerLook.accentColors.count, -1) }, plus: { cycle(&look.accent, PlayerLook.accentColors.count, 1) })
        look.hat = hats[hatIndex]
        look.back = backs[backIndex]

        let half = (w - 12) / 2
        if ui.button("cos.random", "Surprise Me", Rect(x, y + 6, half, 50), style: .secondary) {
            look.hat = hats.randomElement()!
            look.back = backs.randomElement()!
            look.shirt = Int.random(in: 0..<PlayerLook.shirtColors.count)
            look.pants = Int.random(in: 0..<PlayerLook.pantsColors.count)
            look.skin = Int.random(in: 0..<PlayerLook.skinTones.count)
            look.accent = Int.random(in: 0..<PlayerLook.accentColors.count)
        }
        if ui.button("cos.reset", "Reset", Rect(x + half + 12, y + 6, half, 50), style: .secondary) {
            look = PlayerLook.oneOfOne(id: e.settings.playerID)
        }
        if look != before { e.settingsStore.update { $0.cosmetics = look.encoded } }
        if ui.button("cos.done", "Done", Rect(panel.midX - 160, panel.maxY - 74, 320, 52), style: .primary) { back(e) }
    }

    /// Draws the explorer from one side: every box of the model as a flat rectangle, back to front.
    static func drawFront(_ d: UIRenderer, _ look: PlayerLook, side: SkinRegion.Side = .front, in r: Rect) {
        var boxes: [(depth: Float, rect: Rect, color: Color)] = []
        let scale = min(r.w / 1.4, r.h / 2.5)
        let cx = r.midX, feet = r.maxY - 20
        for part in PlayerAvatar.parts(look) {
            for box in part.boxes {
                let lo = part.pivot + box.0, hi = part.pivot + box.1
                // Across the screen, and how far the nearest face is from the viewer. The front faces -z,
                // so from the front the explorer's +x side is on the viewer's left.
                let x0: Float, x1: Float, depth: Float
                switch side {
                case .front, .top: (x0, x1, depth) = (-hi.x, -lo.x, lo.z)
                case .back: (x0, x1, depth) = (lo.x, hi.x, -hi.z)
                case .left: (x0, x1, depth) = (lo.z, hi.z, lo.x)
                case .right: (x0, x1, depth) = (-hi.z, -lo.z, -hi.x)
                }
                let rect = Rect(cx + x0 * scale, feet - hi.y * scale, (x1 - x0) * scale, (hi.y - lo.y) * scale)
                boxes.append((depth, rect, Color(linear: box.2.x, box.2.y, box.2.z, 1)))
            }
        }
        for b in boxes.sorted(by: { $0.depth > $1.depth }) { d.fill(b.rect, b.color) }
    }
}

// MARK: - Installing updates

/// Replaces this DinoCraft.app with a downloaded one. The app can't replace itself while it runs, so
/// a small script waits for it to quit, swaps the bundles and opens the new version. Worlds and
/// settings live in Application Support, so they're untouched.
enum MacUpdater {
    /// Returns an error message, or nil when DinoCraft should now quit to finish the update.
    static func install(zip: URL) -> String? {
        let running = Bundle.main.bundleURL
        // DinoCraft Launcher updates the game next to it (and itself).
        let app = running.lastPathComponent.contains("Launcher") ? running.deletingLastPathComponent().appendingPathComponent("DinoCraft.app") : running
        guard app.pathExtension == "app" else { return "Updates install into DinoCraft.app; this copy isn't running from an app." }
        let fm = FileManager.default
        let unpacked = zip.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            return "Couldn't unpack the update: \(error.localizedDescription)"
        }
        let newApp = unpacked.appendingPathComponent("DinoCraft.app")
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/DinoCraft").path) else {
            return "The update download was damaged. Try again."
        }
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            return "DinoCraft can't write to \(app.deletingLastPathComponent().path). Move DinoCraft.app to a folder you own and try again."
        }
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let pid = ProcessInfo.processInfo.processIdentifier
        let newLauncher = unpacked.appendingPathComponent("DinoCraft Launcher.app")
        let launcher = app.deletingLastPathComponent().appendingPathComponent("DinoCraft Launcher.app")
        let launcherSteps = fm.fileExists(atPath: newLauncher.path) ? """
        rm -rf \(quote(launcher.path))
        /usr/bin/ditto \(quote(newLauncher.path)) \(quote(launcher.path))
        /usr/bin/xattr -dr com.apple.quarantine \(quote(launcher.path)) 2>/dev/null
        """ : ""
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        rm -rf \(quote(app.path))
        /usr/bin/ditto \(quote(newApp.path)) \(quote(app.path))
        /usr/bin/xattr -dr com.apple.quarantine \(quote(app.path)) 2>/dev/null
        \(launcherSteps)
        /usr/bin/open \(quote(running.path))

        """
        let scriptURL = zip.deletingLastPathComponent().appendingPathComponent("update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/bin/sh")
            runner.arguments = [scriptURL.path]
            try runner.run()
        } catch {
            return "Couldn't start the updater: \(error.localizedDescription)"
        }
        Log.info("Update ready: \(newApp.path) → \(app.path)", category: "Update")
        return nil
    }
}

// MARK: - Skin creator

/// Paint your whole explorer, every side of every body part, pixel by pixel. Friends see it in multiplayer, and skins can be
/// shared as codes (DINOSKIN:…) through the clipboard.
final class SkinCreatorScreen: Screen {
    private var draft: PlayerLook?
    private var regionID = "hf"
    private var colorIndex: UInt8 = 1
    private var mirror = true
    private var fillMode = false
    private var facePreset = 0
    private var chestPreset = 0
    private var message: String?

    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let panel = Rect(max(20, W / 2 - 600), max(20, H / 2 - 360), min(1200, W - 40), min(720, H - 40))
        ui.panel(panel, title: "Skin Creator")
        d.text("Left-click paints, right-click rubs out. Friends see your skin in multiplayer.", x: panel.midX, y: panel.y + 66,
               size: 14, color: Theme.textMuted, align: .center)

        var look = draft ?? PlayerLook(encoded: e.settings.cosmetics) ?? PlayerLook.oneOfOne(id: e.settings.playerID)
        let region = SkinRegion.byID[regionID] ?? SkinRegion.all[0]
        let isFace = region.id == "hf", isShirt = region.id == "bf"

        // Preview, turned to show the side you're painting
        let preview = Rect(panel.x + 30, panel.y + 110, 260, panel.h - 210)
        d.fill(preview, Color(linear: 0, 0, 0, 0.25), radius: 18)
        CosmeticsScreen.drawFront(d, look, side: region.side, in: preview)

        // Which part and which side
        let partW: Float = 128, partH: Float = 34
        let pickX = preview.maxX + 40, pickY = panel.y + 92
        for (i, part) in SkinRegion.parts.enumerated() {
            let r = Rect(pickX + Float(i % 3) * (partW + 8), pickY + Float(i / 3) * (partH + 8), partW, partH)
            if ui.button("skin.part.\(part)", part, r, style: region.part == part ? .primary : .secondary, fontSize: 14) {
                let sides = SkinRegion.regions(part: part)
                regionID = (sides.first { $0.side == region.side } ?? sides[0]).id
            }
        }
        for (i, side) in SkinRegion.regions(part: region.part).enumerated() {
            let r = Rect(pickX + Float(i) * (100 + 8), pickY + 2 * (partH + 8) + 6, 100, partH)
            if ui.button("skin.side.\(side.id)", side.side.rawValue.capitalized, r, style: side.id == region.id ? .primary : .secondary,
                         fontSize: 14) { regionID = side.id }
        }

        // Canvas
        let cols = region.width, rows = region.height
        let canvasTop = pickY + 3 * (partH + 8) + 30
        let cell = min(34, (panel.maxY - 90 - canvasTop) / Float(rows))
        let canvas = Rect(pickX, canvasTop, cell * Float(cols), cell * Float(rows))
        let baseHex = region.baseColor(look)
        d.fill(Rect(canvas.x - 4, canvas.y - 4, canvas.w + 8, canvas.h + 8), Color(hex: 0x0B0716), radius: 6)
        var pixels = look.pixels(region)
        for r in 0..<rows {
            for c in 0..<cols {
                let v = pixels[r * cols + c]
                let cellRect = Rect(canvas.x + Float(c) * cell, canvas.y + Float(r) * cell, cell - 1, cell - 1)
                d.fill(cellRect, v == 0 ? Color(hex: baseHex, alpha: 0.8) : Color(hex: PlayerLook.paintColors[Int(v)]))
            }
        }
        if mirror { d.fill(Rect(canvas.midX - 1, canvas.y, 2, canvas.h), Theme.amber.alpha(0.4)) }
        let rightDown = ui.input.buttonsDown.contains(1)
        if canvas.contains(ui.mouse) && (ui.mouseDown || rightDown) {
            let c = min(cols - 1, Int((ui.mouse.x - canvas.x) / cell)), r = min(rows - 1, Int((ui.mouse.y - canvas.y) / cell))
            let value: UInt8 = rightDown ? 0 : colorIndex
            if fillMode {
                if ui.mousePressed || ui.input.buttonsPressed.contains(1) {
                    SkinCreatorScreen.floodFill(&pixels, cols: cols, rows: rows, from: r * cols + c, to: value)
                    if mirror { SkinCreatorScreen.floodFill(&pixels, cols: cols, rows: rows, from: r * cols + (cols - 1 - c), to: value) }
                }
            } else {
                pixels[r * cols + c] = value
                if mirror { pixels[r * cols + (cols - 1 - c)] = value }
            }
        }

        // Palette (it stays put while the canvas changes shape between parts)
        let px = canvas.x + max(canvas.w, 8 * min(34, (panel.maxY - 90 - canvasTop) / 8)) + 40, swatch: Float = 44
        var py = canvas.y
        d.text("Colours", x: px, y: py - 26, size: 15, color: Theme.textMuted)
        for i in 0..<16 {
            let r = Rect(px + Float(i % 4) * (swatch + 8), py + Float(i / 4) * (swatch + 8), swatch, swatch)
            if UInt8(i) == colorIndex { d.fill(Rect(r.x - 3, r.y - 3, r.w + 6, r.h + 6), Theme.amber, radius: 8) }
            d.fill(r, i == 0 ? Color(hex: baseHex) : Color(hex: PlayerLook.paintColors[i]), radius: 6)
            if i == 0 { d.text("×", x: r.midX, y: r.y + 12, size: 18, color: Theme.textDark, align: .center) }
            if ui.hoverSilent("skin.swatch\(i)", r) && ui.mousePressed { colorIndex = UInt8(i) }
        }
        py += 4 * (swatch + 8) + 14

        // Tools
        let tw: Float = 170, th: Float = 42
        func tool(_ id: String, _ label: String, _ col: Int, primary: Bool = false) -> Bool {
            ui.button(id, label, Rect(px + Float(col) * (tw + 10), py, tw, th), style: primary ? .primary : .secondary, fontSize: 15)
        }
        if tool("skin.fill", fillMode ? "Fill" : "Brush", 0, primary: fillMode) { fillMode.toggle() }
        if tool("skin.mirror", mirror ? "Mirror On" : "Mirror Off", 1, primary: mirror) { mirror.toggle() }
        py += th + 10
        if isFace || isShirt {
            let presets = isFace ? PlayerLook.facePresets : PlayerLook.chestPresets
            let presetIndex = isFace ? facePreset : chestPreset
            if tool("skin.preset", "Idea: \(presets[presetIndex].name)", 0) {
                pixels = PlayerLook.presetPixels(presets[presetIndex].pixels, count: cols * rows)
                if isFace { facePreset = (facePreset + 1) % presets.count } else { chestPreset = (chestPreset + 1) % presets.count }
            }
        } else if let twin = region.twin, tool("skin.twin", region.copyTwinLabel, 0) {
            pixels = look.pixels(twin)
        }
        if tool("skin.clear", "Clear", 1) { pixels = Array(repeating: 0, count: cols * rows) }
        py += th + 10
        if tool("skin.copy", "Copy Code", 0) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(look.shareCode, forType: .string)
            message = "Skin code copied — paste it to a friend!"
        }
        if tool("skin.paste", "Paste Code", 1) {
            if let text = NSPasteboard.general.string(forType: .string), let pasted = PlayerLook(shareCode: text) {
                look = pasted
                pixels = look.pixels(region)
                message = "Skin pasted!"
            } else {
                message = "The clipboard doesn't hold a DinoCraft skin code."
            }
        }
        py += th + 14
        if let message { d.text(message, x: px, y: py, size: 14, color: Theme.textMuted, maxWidth: panel.maxX - px - 20) }

        look.setPixels(pixels, for: region)
        draft = look

        if ui.button("skin.play", "Save & Play", Rect(panel.midX - 370, panel.maxY - 70, 230, 50), style: .primary) {
            e.settingsStore.update { $0.cosmetics = look.encoded }
            e.popScreen()   // the skin creator
            e.popScreen()   // the launcher, revealing the main menu (like Play)
            return
        }
        if ui.button("skin.save", "Save & Back", Rect(panel.midX - 115, panel.maxY - 70, 230, 50), style: .secondary) {
            e.settingsStore.update { $0.cosmetics = look.encoded }
            e.popScreen()
        }
        if ui.button("skin.cancel", "Cancel", Rect(panel.midX + 140, panel.maxY - 70, 230, 50), style: .secondary) { e.popScreen() }
    }

    /// Fills the area of matching colour around `start`.
    static func floodFill(_ pixels: inout [UInt8], cols: Int, rows: Int, from start: Int, to value: UInt8) {
        let target = pixels[start]
        guard target != value else { return }
        var stack = [start]
        while let i = stack.popLast() {
            guard pixels[i] == target else { continue }
            pixels[i] = value
            let r = i / cols, c = i % cols
            if c > 0 { stack.append(i - 1) }
            if c < cols - 1 { stack.append(i + 1) }
            if r > 0 { stack.append(i - cols) }
            if r < rows - 1 { stack.append(i + cols) }
        }
    }
}
