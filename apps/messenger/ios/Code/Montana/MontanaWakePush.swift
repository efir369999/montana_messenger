import Foundation
import UIKit
import CryptoKit
import UserNotifications

// Rung 4 — notifications through the accelerator node. The module is isolated: it touches no
// nodes, callsigns or live typing.
//
// Privacy: what leaves the device is the APNs token (issued by Apple), the TOPIC — our
// install's name, named by the node, not the accelerator, the DAILY conversation tag conv_w
// (the accelerator never sees a conversation's eternal name — today's observation cannot be
// tied to yesterday's) and the subscription tag sub_id instead of the Montana address: the
// address never reaches the accelerator, the reverse walk is closed by SHA-256 one-wayness.
// The wake payload is an E2E envelope of a single size.
enum MontanaWakePush {

    // THE ACCELERATOR ADDRESS IS NOT BAKED IN: it comes from the NODE LIST — the same single place
    // the doors live in ([I-10]/[C-1]). One name used to stand here, and a phone whose tunnel does
    // not carry packets to it could not expand a link AT ALL: measured 24.08 on the seventeenth — a
    // link tap and not one completion line in a minute, every request waiting on an unreachable
    // address while a live door stood beside it. The list is data; another implementation carries
    // its own. SERVER-DEBT-ACK: the accelerator node (rung 4).
    private static var chosenBase: String?
    private static let baseLock = NSLock()

    /// While the two were mixed, letters left down a road that does not exist, the meeting store
    /// split into two disagreeing copies, and a spent card resurrected from the copy the tombstone
    /// never reached.
    ///
    /// So a path counts as a path ONLY once it has answered for itself. Candidates come from the
    /// node list (no baked-in address — the author's word); the right to be a path is granted by
    /// verification. WHAT A NODE CAN, IN ITS OWN WORDS (stage 15.2). A node tells its capability
    /// map, so the client stops sorting paths by kind and stops guessing: a request goes to a node
    /// that says it holds THAT capability. One boolean per node could only say «something answered
    /// here» — and a wake was sent to a node whose appendage was down while a capable node stood
    /// beside it.
    static let allCaps: Set<String> = ["box", "blob", "signal", "turn", "diag", "stun", "notify"]
    private static var capsOf: [String: Set<String>] = [:]
    /// Asked and did not answer. Silence is knowledge, and losing it costs dearly: with «absent
    /// means unknown» the fallback below returns the doors nothing is known about — so after every
    /// network flap the walk went to doors that had just refused to speak, and each of them spends
    /// the minute budget of a machine that is already saturated (measured 01.09: 965 refusals in an
    /// hour, zero on any other hour of the day).
    private static var silentDoors: Set<String> = []
    private static var verifiedAt: Date = .distantPast
    private static let verifyLock = NSLock()

    static func candidates() -> [String] {
        let live = Set(MontanaNodes.live().map { $0.host })
        let hosts = MontanaNodes.list().map { $0.host }
        var seen = Set<String>()
        var out: [String] = []
        for h in hosts.filter({ live.contains($0) }) + hosts.filter({ !live.contains($0) })
        where !h.isEmpty && !seen.contains(h) {
            seen.insert(h); out.append("https://\(h)/pushwake")
        }
        return out
    }

    /// Verified paths. Before any verification every candidate counts as a path (otherwise
    /// the first action after launch would be left without an address), but verification
    /// follows and cuts off those that do not hold the accelerator.
    static func bases(for cap: String? = nil) -> [String] {
        verifyLock.lock()
        let known = capsOf
        let fresh = Date().timeIntervalSince(verifiedAt) < 600
        verifyLock.unlock()
        let all = candidates()
        if !fresh { Task { await verifyBases() } }
        let good = all.filter { b in known[b].map { held in cap.map { held.contains($0) } ?? true } ?? false }
        if !good.isEmpty { return electedFirst(good) }
        verifyLock.lock(); let mute = silentDoors; verifyLock.unlock()
        let unknown = all.filter { known[$0] == nil && !mute.contains($0) }
        return electedFirst(unknown.isEmpty ? all : unknown)
    }

    /// Doors PROVEN to hold a capability — no fallback to «every candidate». `bases(for:)` keeps
    /// its fallback so a first action after launch has an address; this answers a different
    /// question: is there any store alive at all? An empty answer is the honest one.
    static func doorsHolding(_ cap: String) -> [String] {
        verifyLock.lock(); let known = capsOf; verifyLock.unlock()
        return candidates().filter { known[$0]?.contains(cap) == true }
    }

    static func verifyBases(_ pass: Int = 0) async {
        let before = Set(candidates())
        var found: [String: Set<String>?] = [:]   // a value that is nil says «asked and silent»
        await withTaskGroup(of: (String, Set<String>?).self) { group in
            for b in candidates() {
                group.addTask {
                    // The one probe of a door (MTNodeWire.health) — the sheet asks through it too.
                    // The node names what it holds. A node that names nothing held everything
                    // yesterday and holds everything today — its silence is not a refusal.
                    guard let h = await MTNodeWire.health(b, timeout: 6) else { return (b, nil) }
                    guard let caps = h.caps else { return (b, allCaps) }
                    return (b, caps)
                }
            }
            for await (b, held) in group { found[b] = held }
        }
        verifyLock.lock()
        // Merged, not replaced: a door that answered once and is silent now keeps its capabilities
        // (a single failed round is not a lost capability), but its silence is written down.
        for (b, held) in found {
            if let held { capsOf[b] = held; silentDoors.remove(b) } else { silentDoors.insert(b) }
        }
        verifiedAt = Date()
        verifyLock.unlock()
        for (b, held) in found where held != nil { proveDoor(b) }   // the round's answer is proof for the call's walk
        // The extension's door mirror holds VERIFIED doors only — the one owner of the
        // list is this verification, not the raw candidate roster.
        // In the app's own order (the author's word 16.09: the sheet on cellular walked a dead
        // door first) — the live nodes first, as candidates() ranks them — never the alphabet.
        let goodDoors = candidates().filter { found[$0] != nil }
        if !goodDoors.isEmpty, let d = try? JSONEncoder().encode(Array(goodDoors)) {
            MontanaKeychain.set("wakeBases", d)
        }
        var good: [String] = []
        for (b, held) in found {
            guard let held else { continue }
            let host = URL(string: b)?.host ?? "-"
            good.append(host + "[" + held.sorted().joined(separator: "|") + "]")
        }
        good.sort()
        MontanaTrace.mark("accel_paths", "ok=\(good.joined(separator: ",")) of=\(candidates().count)")
        // THE RELAY PASS IS FETCHED BY THE DOORS' PROBE, NOT BY THE CALL (12.09): a call that
        // found no remembered pass raced a 1.5 s fetch on cellular, lost, and went host-only —
        // no relay, no call across carrier NAT. The probe already stands at the doors; the pass
        // is taken here and remembered, so the call finds it waiting.
        if rememberedTurnPass() == nil { _ = await fetchTurnCred() }
        // The network names its own doors: the list rides down from a verified accelerator
        // and lands in MontanaNodes — a new node door reaches every install without a
        // rebuild (the same law the TURN uris live by).
        if let b = goodDoors.first, let u = URL(string: b + "/doors") {   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: u); req.timeoutInterval = 8   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            if let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let doors = j["doors"] as? [String], !doors.isEmpty {
                MontanaNodes.learn(doors.joined(separator: "\n"))
                // The network names its MACHINES too (15.22): which doors are one node. Absent in
                // an older node's answer — then the client groups by what the handshakes taught it.
                if let nodes = j["nodes"] as? [[String: Any]] {
                    MontanaNodes.learnMachines(nodes.compactMap { n in
                        guard let id = n["id"] as? String, let ds = n["doors"] as? [String], !id.isEmpty else { return nil }
                        return (id, ds)
                    })
                }
                // THE BARRED (Guideline 1.2): the addresses the network's operators barred after a
                // report ride the same answer; every install refuses their letters on every road.
                if let barred = j["barred"] as? [String] { MontanaSafety.setBarred(barred) }
            }
            // A NEW TESTFLIGHT BUILD IS TOLD ONLY ON OUR OWN PHONES (App Review 2.2, 08.10.2026: «betas ... don't belong on the App
            // Store -- use TestFlight instead»): TestFlight itself tells its testers; a build from the App Store never points at a beta.
            #if DEBUG
            await MontanaRelease.check(door: b)   // a new build in TestFlight rides the same round (29.09)
            #endif
        }
        // A DOOR LEARNED THIS ROUND ENTERS WORK IN A SECOND, NOT IN TEN MINUTES (15.09). The doors
        // of the node inside the whitelists arrive as DATA, and they arrive AFTER this round has
        // already asked the old list; `bases(for:)` uses only doors whose capabilities are known,
        // so the new door sat unused until the next round — no sooner than ten minutes, and only
        // if something asked. Measured on a tester's phone: launch at 13:07 wrote «accel_paths
        // of=4» and «doors_learned n=6» 350 ms apart, and until the app was relaunched it never
        // knocked at the third node, while its own page showed that node as lost.
        if pass == 0, !Set(candidates()).subtracting(before).isEmpty {
            await verifyBases(1)
        }
        // A DOOR THAT DID NOT ANSWER IS A QUESTION, NOT A VERDICT: the mode is measured then, so a
        // quiet minute costs the phone nothing. But a probe that never fires is a probe nobody has
        // proven — and without a baseline of open lines, a single «whitelist» has nothing to stand
        // against. So the round also runs once an hour on its own (two header requests), measured
        // 15.09: a phone with all six doors alive wrote 73 rounds and not one line of mode.
        let mute = found.filter { $0.value == nil }.keys.compactMap { URL(string: $0)?.host }
        let alive = found.filter { $0.value != nil }.keys.compactMap { URL(string: $0)?.host }
        if (!mute.isEmpty && MontanaNetProbe.minutePassed()) || MontanaNetProbe.hourPassed() {
            await MontanaNetProbe.round(mute: mute, alive: alive)
        }
    }

    /// STORE-CONVERGENT ORDER. The per-node stores do not talk to each other, so wake and
    /// signal must land where the OTHER side will ask. The order is the network's own list
    /// order (/doors), never the local live-door shuffle: both sides walk the same list and
    /// fall to the same fallback together when a node dies.
    static func orderedBases(for cap: String? = nil) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for h in MontanaNodes.list().map({ $0.host }) where !h.isEmpty && !seen.contains(h) {
            seen.insert(h); out.append("https://\(h)/pushwake")
        }
        verifyLock.lock(); let known = capsOf; let mute = silentDoors; verifyLock.unlock()
        let good = out.filter { b in known[b].map { held in cap.map { held.contains($0) } ?? true } ?? false }
        if !good.isEmpty { return electedFirst(good) }
        // 16.6.17 (F3) — A CAPABILITY ASKED BY NAME IS NOT GUESSED. Once the map knows the doors
        // and none of them holds the capability, the answer is «nobody», not «everybody»: the
        // fallback to unknown doors posted every call signal to the dead wss door too — 34
        // «sig_tx code=-1 door=door.montana.quest», pauses up to a minute (measured 04.09
        // 16:16-18:23). The fallback stays for the cold start, when the map is still empty.
        if cap != nil, !known.isEmpty { return [] }
        let unknown = out.filter { !mute.contains($0) }
        return electedFirst(unknown.isEmpty ? out : unknown)
    }

    /// One address for a single request, chosen among those that hold the named capability.
    /// The sticky choice survives only while it still holds it.
    /// ONE DOOR PER MACHINE. Two doors lead to one node, and a node counts the ring by CONVERSATION,
    /// not by door: knocking both spends the same minute budget twice and buys nothing. The door book
    /// says which door led to which machine; a door whose machine is unknown keeps its place.
    static func oneDoorPerNode(_ doors: [String]) -> [String] {
        let book = MontanaNodes.book()
        let known = MontanaNodes.list()
        var seen = Set<Data>(); var out: [String] = []
        for d in doors {
            guard let host = URL(string: d)?.host else { continue }
            let id = known.first { $0.host == host }.flatMap { book[$0.label]?.overlay }
            if let id { if seen.insert(id).inserted { out.append(d) } } else { out.append(d) }
        }
        return out
    }

    /// A machine that answered «too often» is not asked again until its own window has passed.
    /// It named the rule itself; obeying it once per machine is the whole difference between a
    /// pause and a storm that eats the budget of the person's own letter.
    private static var busyUntil: [String: Date] = [:]
    private static var busyStreak: [String: Int] = [:]
    private static let busyLock = NSLock()
    /// 16.6.17 (F2) — «TOO OFTEN» IS COUNTED BY THE NODE PER CONVERSATION, so the rest is kept
    /// per (door, conversation): one pair's storm used to rest the whole door for every pair
    /// (measured 04.09 17:50-18:23: three 429 for one offline correspondent, «every machine
    /// asked to wait», the live pair's address word blocked up to 32 minutes). A door that does
    /// not answer at all (-1, 5xx) is dead for everybody and rests as a door, as before.
    private static func busyKey(_ host: String, _ conv: String?) -> String { conv.map { host + "|" + $0 } ?? host }
    static func noteTooOften(_ door: String, conv: String? = nil) {
        guard let host = URL(string: door)?.host else { return }
        // A door that keeps refusing rests longer each time (a minute, two, four… half an
        // hour): a dead machine is not re-tried every minute at the price of an 8-second wait.
        let key = busyKey(host, conv)
        busyLock.lock()
        // ONE SILENCE PER VOLLEY (30.09, the rule baseFailed has kept since 17.09): parallel posts that time out together
        // are one silence, not several -- on build 1976 three per door rested it 60, 120 and 240 s within 250 ms (29.09
        // 13:18:11Z) and 480, 960 and 1920 s within 17 ms (08:02:05Z). A silent door already resting is not silent again;
        // a refusal named by the node (per pair) still counts every time.
        if conv == nil, let u = busyUntil[key], u > Date() { busyLock.unlock(); return }
        let n = min((busyStreak[key] ?? 0) + 1, 6)
        busyStreak[key] = n
        let rest = 60.0 * pow(2.0, Double(n - 1))
        busyUntil[key] = Date().addingTimeInterval(rest)
        busyLock.unlock()
        MontanaTrace.markChanged("wakepush_hold", "\(host) refused\(conv.map { " pair=" + String($0.prefix(10)) } ?? "") — resting \(Int(rest))s", every: 60, key: key)
    }
    static func noteAnswered(_ door: String, conv: String? = nil) {
        guard let host = URL(string: door)?.host else { return }
        busyLock.lock()
        busyStreak[host] = nil; busyUntil[host] = nil
        if let conv { let k = busyKey(host, conv); busyStreak[k] = nil; busyUntil[k] = nil }
        busyLock.unlock()
    }
    static func notBusy(_ doors: [String], conv: String? = nil) -> [String] {
        busyLock.lock(); let m = busyUntil; busyLock.unlock()
        let now = Date()
        return doors.filter { d in
            guard let host = URL(string: d)?.host else { return true }
            if let u = m[host], u > now { return false }
            if let conv, let u = m[busyKey(host, conv)], u > now { return false }
            return true
        }
    }

    /// The hosts that say they hold a capability. A reflector is asked by NAME and PORT, not by a
    /// web address, so the same map is read in the form that question needs.
    static func hosts(for cap: String? = nil) -> [String] {
        orderedBases(for: cap).compactMap { URL(string: $0)?.host }
    }

    // THE ELECTED DOOR (1638, the author's word: the phone elects ONE live node and works with it; a
    // node that dies on the way is left and the next is elected). One choice for the app and the
    // sheet — mirrored into the shared keychain — and it stands FIRST in every order of doors this
    // file hands out, so every write starts at the elected door and walks on only past its death.
    // Reads that look for what ANOTHER phone wrote (the box, the chunks) keep sweeping every store:
    // the other phone elected its own door.
    static func elected() -> String? {
        baseLock.lock(); let c = chosenBase; baseLock.unlock()
        if let c { return c }
        guard let d = MontanaKeychain.get(MTNodeWire.electedKey), let s = String(data: d, encoding: .utf8), !s.isEmpty else { return nil }
        baseLock.lock(); if chosenBase == nil { chosenBase = s }; baseLock.unlock()
        return s
    }
    static func electedFirst(_ doors: [String]) -> [String] {
        guard let e = elected(), doors.contains(e) else { return doors }
        return [e] + doors.filter { $0 != e }
    }
    // NOTHING BUT THE CHOICE UNDER THE LOCK: the keychain and the trace are asked outside it — a
    // lock that is not reentrant must never hold a call that could come back to it.
    private static func base(_ cap: String) -> String {
        let all = bases(for: cap)
        let mirrored = MontanaKeychain.get(MTNodeWire.electedKey).flatMap { String(data: $0, encoding: .utf8) }
        var fresh: String? = nil
        baseLock.lock()
        let chosen: String
        if let c = chosenBase, all.contains(c) { chosen = c }
        else if let s = mirrored, all.contains(s) { chosenBase = s; chosen = s }
        else if let b = all.first(where: { !(signalDoorDead[$0].map { $0 > Date() } ?? false) }) ?? all.first { chosenBase = b; chosen = b; fresh = b }
        else { chosen = "" }
        baseLock.unlock()
        if let b = fresh {
            MontanaKeychain.set(MTNodeWire.electedKey, Data(b.utf8))
            MontanaTrace.mark("door_elected", "\(URL(string: b)?.host ?? b)")
        }
        return chosen
    }

    /// THE ONE VERDICT OF A DOOR'S DEATH (17.09): two silences in a row — no code, or 5xx — the rule
    /// the signal lane has lived by since 15.2, now the rule for the election and for every walk. A
    /// door that answered with any code, even a refusal, is alive; a cancelled request is no answer
    /// at all and never reaches here. Four places used to decide death by four rules (a lost race,
    /// a five-second wait, a refused diary), and the elected door died on every fetch it did not win
    /// (T1 21:50:42Z: five «unreachable» in the millisecond another door answered; «api.montana.quest
    /// died» 0.2 s after every launch on both phones). A dead door rests a minute, then two, four,
    /// eight at most; any answer or a path change forgives it. Under the lock: memory only.
    private static var deathStreak: [String: Int] = [:]
    static func baseFailed(_ b: String, code: Int = -1) {
        guard code == -1 || code >= 500 else { doorSpoke(b); return }
        var died = false, wasChosen = false, rest = 0
        baseLock.lock()
        if let until = signalDoorDead[b], until > Date() { baseLock.unlock(); return }   // already resting: the late answers of parallel posts add nothing
        let n = (doorFails[b] ?? 0) + 1
        doorFails[b] = n
        if n >= 2 {
            doorFails[b] = 0
            let streak = min((deathStreak[b] ?? 0) + 1, 4)   // a minute, two, four, eight at most: a death that was a tunnel's drop must not cost half an hour
            deathStreak[b] = streak
            rest = 60 * (1 << (streak - 1))
            signalDoorDead[b] = Date().addingTimeInterval(Double(rest))
            wasChosen = signalDoorChosen == b
            if wasChosen { signalDoorChosen = nil }
            if chosenBase == b { chosenBase = nil; died = true }
        }
        baseLock.unlock()
        guard rest > 0 else { return }
        MontanaTrace.mark("sig_door", "dead \(URL(string: b)?.host ?? b) code=\(code) — not asked for \(rest)s")
        if died {
            MontanaKeychain.delete(MTNodeWire.electedKey)
            MontanaTrace.mark("door_elected", "\(URL(string: b)?.host ?? b) died — the next live door is elected")
        }
        // THE STANDING QUESTION LEAVES A DEAD DOOR NOW (13.09 15:20): the posts found the door dead
        // at +6 s, the long question stood on it until its own deadline at +15 s — seven seconds of
        // the peer's «ringing» lying on the node. The lane is cut and re-elected the same instant.
        if wasChosen { cutStandingQuestion("door \(URL(string: b)?.host ?? b) dead — the standing question leaves it") }
    }
    /// Any answer proves the door alive: the silence count and the rest streak are forgiven -- in every book that
    /// keeps them. THE KNOCK'S REST IS THE SAME VERDICT (30.09): a door silent for the registration rested for the
    /// knock walk in its own book, and no answer on another lane reached it -- on build 1976 (29.09) both machines'
    /// first doors answered at 13:18:26Z and still rested by that book until 13:22Z, while the walk had found
    /// "every machine asked to wait" at 13:18:20Z. A per-pair refusal named by the node is not a silence and stays.
    static func doorSpoke(_ b: String) {
        baseLock.lock()
        let revived = (deathStreak[b] ?? 0) > 0 || (signalDoorDead[b].map { $0 > Date() } ?? false)
        // AN ANSWER ENDS THE REST TOO (07.10, the finding of the Business's №32, measured on T1 Business 61 18:30Z): the count and the
        // streak were forgiven, the rest's moment stood -- four doors answered a second after the tunnel's drop and still rested a
        // minute, and a photo's chunks found «no live door» four rounds twice. The rule above says any answer forgives it.
        doorFails[b] = 0; deathStreak[b] = nil; signalDoorDead[b] = nil
        baseLock.unlock()
        noteAnswered(b)   // the knock's rest book: an answer ends the silence there too
        if revived { doorRevived(b) }
    }
    /// A DOOR THAT WAS DEAD ANSWERED — THE QUEUE DRAINS THIS SECOND (18.09). Measured 17.09 on the
    /// tester's phone: no road for a minute, then the network lived for twenty-five seconds; two
    /// knocks passed and carried service words, while the text letter stood on the bell's ramp
    /// (a knock on tries 1, 3, 6, 10 — its try was the ninth) and waited nineteen hours for the next
    /// opening of the app. A revived door is reachability, exactly as a peer's appearance is: every
    /// loud letter knocks at once, past the ramp. Outside the lock: the engine takes its own queue.
    private static var revivedAt: [String: Date] = [:]
    private static func doorRevived(_ b: String) {
        let host = URL(string: b)?.host ?? b
        // ONE REVIVAL IS ONE PIECE OF NEWS, NOT ONE PER ASKER (22.09). Measured on T1 at 19:23:54:
        // seven cargo asks each saw the same door come back, so this ran seven times in one second and
        // handed the node its pairs fifteen times over -- 128 pairs a call, nine calls a second in the
        // record. The door did not revive seven times; seven askers heard one revival.
        baseLock.lock()
        let fresh = revivedAt[b].map { Date().timeIntervalSince($0) < 10 } ?? false
        if !fresh { revivedAt[b] = Date() }
        baseLock.unlock()
        guard !fresh else { return }   // SILENT-OK: the same news, and the first telling did the work
        MontanaTrace.mark("door_alive", "\(host) answered after silence — the queue drains now")
        forgetGoneChunks("\(host) came back")
        MontanaDeliveryEngine.shared.drainOnDoorAlive(host)
        DispatchQueue.main.async { MTBoard.shared.roadBack("door-alive") }   // a post's files the node did not take go again (25.09)
        registerConvs()   // a door back from the dead gets the pairs it missed while it rested (20.09)
    }
    /// The knock lane keeps its own memory of silence, by host: it does not sit under the one death
    /// verdict (a knock that timed out must not rest the door for the signal lane), it only knows
    /// whether the last knock at this host failed — so the first answer after a failure is an event.
    private static var knockSilent: Set<String> = []
    private static func knockOutcome(_ door: String, code: Int) {
        guard let host = URL(string: door)?.host else { return }
        var revived = false
        busyLock.lock()
        if code < 0 || code >= 500 { knockSilent.insert(host) }
        else if knockSilent.remove(host) != nil { revived = true }
        busyLock.unlock()
        if revived { doorRevived(door) }
    }

    // ═══ ONE DOOR FOR SIGNALS (15.2) ═══
    // The signal lane — the long question, every draft word, every presence word — has ONE
    // decision point: this door. Elected once by the network's own list order among the doors
    // that hold the signal capability, and elected as long as it answers. While it lives the
    // phone knocks nowhere else. Measured 04.09 22:40–23:00: each draft word went to three
    // doors (~1500 posts per door in twenty minutes) while the question walked a FOURTH rule
    // (the live-door shuffle) — the two sides never shared one rule at all.
    // Re-election on ONE fact only: two questions in a row the door did not answer (no code,
    // or a 5xx). A single lost question is the tunnel's blink, not a dead door. The dead door
    // is remembered for a minute, then it is first in line again — the reserve node comes
    // back the moment it answers.
    private static var signalDoorChosen: String?
    private static var signalDoorFails = 0
    private static var signalDoorDead: [String: Date] = [:]
    static func signalDoor() -> String {
        // THE LIST IS ASKED BEFORE THE LOCK (16.09): the ordered list asks elected(), and elected() takes
        // this very lock. Held across that call, the lock hung the signal thread on itself forever
        // (1638–1639: not one «sig_door elected» after the install; every entry into a chat stood on
        // the dead lock until the watchdog killed the app — 166 s, 56 s, 28 s, 29 s). Under the lock:
        // the choice and nothing else; the trace after it. Guard: tools/mt-lock-check.py.
        let order = orderedBases(for: "signal")
        let now = Date()
        var fresh: String? = nil
        baseLock.lock()
        let all = order.filter { signalDoorDead[$0].map { $0 <= now } ?? true }
        let chosen: String
        if let c = signalDoorChosen, all.contains(c) { chosen = c }
        else if let b = all.first ?? order.first { signalDoorChosen = b; signalDoorFails = 0; chosen = b; fresh = b }
        else { chosen = "" }
        baseLock.unlock()
        // A DOOR ELECTED AGAIN IS NOT NEWS (29.09, a phone with no path: 146 «elected» rows in 55 seconds, the same door
        // every 300 ms). The line is written when the elected door changes, and once a minute while it stands.
        if let b = fresh { MontanaTrace.markChanged("sig_door", "elected \(URL(string: b)?.host ?? b)", every: 60, key: "elected") }
        return chosen
    }
    static func signalDoorHost() -> String { URL(string: signalDoor())?.host ?? "" }
    /// A door that did not answer twice in a row is dead FOR ME for a minute — for the question
    /// and for every word posted to it alike. Measured 05.09 02:08: 423 posts to a door the tunnel
    /// does not carry, each standing three attempts of five seconds, at four words a second —
    /// sixty requests hanging at once on a phone that was only trying to say one sentence.
    private static var doorFails: [String: Int] = [:]
    /// PROOF OF A DOOR: the moment it last answered me with 200 — a word, a wake, the health round —
    /// since the last path change. A call from an app that has been working already knows its
    /// doors (the author's word 13.09): the walk goes to the proven ones first. Keyed by host.
    private static var doorProof: [String: Date] = [:]
    private static func signalDoorAnswered(_ b: String) {
        baseLock.lock()
        let revived = (deathStreak[b] ?? 0) > 0 || (signalDoorDead[b].map { $0 > Date() } ?? false)
        doorFails[b] = 0; deathStreak[b] = nil; signalDoorDead[b] = nil   // an answer ends the rest too (doorSpoke, 07.10)
        doorProof[URL(string: b)?.host ?? b] = Date(); if signalDoorChosen == b { signalDoorFails = 0 }
        baseLock.unlock()
        noteAnswered(b)   // the knock's rest book, as doorSpoke does
        if revived { doorRevived(b) }
    }
    private static func proveDoor(_ b: String) {
        baseLock.lock(); doorProof[URL(string: b)?.host ?? b] = Date(); baseLock.unlock()
    }
    private static func signalDoorFailed(_ b: String, code: Int) { baseFailed(b, code: code) }   // one verdict for every lane
    /// Alive FOR ME: not dead by my own two silent answers, and not silent in the last health round.
    private static func doorAlive(_ b: String) -> Bool {
        verifyLock.lock(); let mute = silentDoors.contains(b); verifyLock.unlock()
        if mute { return false }
        baseLock.lock(); defer { baseLock.unlock() }
        return signalDoorDead[b].map { $0 <= Date() } ?? true
    }
    /// THE DOORS OF A CALL — ONE RULE FOR EVERY CALL ROAD (13.09, deep closure): the doors alive
    /// for me first, in the network's order, then the doors my own silence marked dead. A call
    /// knocks every door (15.13), but a door dead for me is knocked LAST. Measured 13.09 09:07:
    /// the voip walk knew no dead-door memory and stood three attempts of five seconds on a
    /// door the tunnel did not carry — the first ring reached Apple 15.6 s after the dial, and
    /// every ring of that call the same.
    static func callDoors(for cap: String) -> [String] {
        let all = orderedBases(for: cap)
        let alive = all.filter { doorAlive($0) }
        // THE PROVEN DOORS FIRST (13.09 15:20): the first knock stood five seconds on a door that had
        // never answered on this network while three others had answered a second before. Proof is
        // what the app already knows — every 200 since the path change; an unproven door is knocked
        // after the proven ones, a dead one last. No proof at all (a cold start) — the network's order.
        baseLock.lock(); let proven = doorProof; baseLock.unlock()
        func isProven(_ b: String) -> Bool { proven[URL(string: b)?.host ?? b] != nil }
        let provenAlive = alive.filter { isProven($0) }
        return provenAlive + alive.filter { !isProven($0) } + all.filter { !alive.contains($0) }
    }
    /// THE WALK'S OWN BOUND: doors × the one post deadline, plus a breath. The caller waits
    /// this long for a knock's answer and not a number of its own (13.09: a three-second
    /// guillotine cut the walk on a dead door, threw the real «200» away and told the person
    /// «not reachable»).
    static func knockBudgetS(for cap: String) -> TimeInterval {
        Double(max(1, orderedBases(for: cap).count)) * MTNodeWire.postTimeoutS + 2
    }
    /// The doors alive for me, in the network's order — what I NAME to the peer with every word.
    static func signalDoors() -> [String] {
        orderedBases(for: "signal").filter { doorAlive($0) }.compactMap { URL(string: $0)?.host }
    }

    /// THE DOOR OF A CONVERSATION — one rule both sides compute alike: the FIRST door, in the
    /// network's own list order, that is alive for me AND named alive by the peer. Measured 05.09
    /// 02:08 and 14:25: the ru phone under its tunnel cannot reach api.montana.quest at all, the en
    /// phone on cellular cannot reach door.montana.quest — the two have no common Moscow door, and
    /// «the later of the two elected» could not know it: each side posted into the other's hole.
    /// Each names the doors alive FOR ITSELF; the intersection is the same set on both screens, its
    /// first door the same door, and a door one side finds dead leaves the intersection with that
    /// side's next word. No common door yet — mine, and the word knocks every living door.
    static func signalDoor(for conv: String) -> String {
        let mine = signalDoor()
        guard let theirs = peerDoors(conv) else { return mine }
        let order = orderedBases(for: "signal")
        return order.first { b in doorAlive(b) && (URL(string: b)?.host).map { theirs.contains($0) } ?? false } ?? mine
    }

    /// THE NETWORK PATH CHANGED. Measured 05.09 14:25:18: Wi-Fi off, and the long question stood
    /// on the dead Wi-Fi socket until its own deadline — sixteen seconds of a hole into which the
    /// peer's fifty-eight words fell (they arrived in one heap at 14:25:34, thirty-four of them
    /// already stale). A path change cuts every lane NOW: the questions in flight fail this
    /// instant, a fresh lane opens on the new path and the question leaves at once; the posts in
    /// flight fail and retry fresh; the dead-door memory is cleared, because dead on Wi-Fi says
    /// nothing about cellular.
    private static var sigGen = 0
    private static var postLane = URLSession(configuration: .default)
    static func networkPathChanged(_ key: String) {
        let lane = URLSession(configuration: .default)   // built before the lock: under it, only the swap
        baseLock.lock()
        signalDoorDead.removeAll(); doorFails.removeAll(); deathStreak.removeAll(); doorProof.removeAll(); signalDoorChosen = nil   // proof on Wi-Fi says nothing about cellular
        let old = postLane; postLane = lane
        baseLock.unlock()
        old.invalidateAndCancel()
        cutStandingQuestion("path=\(key) — every lane cut")
    }
    /// THE STANDING QUESTION IS CUT — one move for three facts: the network path changed, a call was
    /// born, the lane's door was declared dead by the posts. The questions in flight fail this instant
    /// (their cancellation teaches nothing about a door), the lanes open fresh, the question leaves at
    /// once — built for the state the machine is in NOW: a call's short question on a living door.
    /// Measured 13.09 15:20: without it the caller stood deaf fifteen seconds on a dead door.
    static func cutStandingQuestion(_ why: String) {
        sigQ.async {
            sigGen += 1
            for s in sigSessions.values { s.invalidateAndCancel() }
            sigSessions.removeAll(); sigInFlight.removeAll(); sigLaneDirty = false
            MontanaTrace.mark("sig_lane", "\(why) — asking again now")
            for c in sigConvs.union(chatConvs).union(boardConvs).union(roomConvs) { fetchSignals(c) }
        }
    }
    private static func currentPostLane() -> URLSession { baseLock.lock(); defer { baseLock.unlock() }; return postLane }

    /// WHERE THE PEER LISTENS. A word from the peer names the door they ask — the draft word in
    /// its JSON, the chat beacon in its tail. A word for them goes to THAT door and nowhere else.
    private static var peerDoorBook: [String: (hosts: [String], at: Date)] = [:]
    /// `host` — one name or several, comma-separated: the doors alive for the peer, in their order.
    static func notePeerDoor(_ conv: String, host: String) {
        let hs = host.lowercased().split(separator: ",").map(String.init).filter { h in
            !h.isEmpty && h.count <= 64 && h.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        }
        guard !hs.isEmpty, hs.count <= 16 else { return }
        baseLock.lock(); let old = peerDoorBook[conv]?.hosts; peerDoorBook[conv] = (hs, Date()); baseLock.unlock()
        if old != hs { MontanaTrace.mark("sig_door", "peer \(String(conv.prefix(10))) listens at \(hs.joined(separator: ","))") }
    }
    static func peerDoors(_ conv: String) -> [String]? {
        baseLock.lock(); defer { baseLock.unlock() }
        guard let p = peerDoorBook[conv], Date().timeIntervalSince(p.at) < 60 else { return nil }   // three beats of 20 s
        return p.hosts
    }

    private static let ownTokenKey  = "wakeOwnToken"    // my APNs token (hex, diagnostics)
    private static let regDigestKey = "wakeRegDigest"   // the last registration's digest (debounce)
    static let windowsAhead: UInt64 = 30                // windows ahead + one back (skewed clocks)

    // ── tags: the address and the conversation's eternal name never leave the node ─────────
    // Formulas and frozen vectors — the node-wake checklist; the same set is frozen on the
    // accelerator (test_node_wake.py). The accelerator does NOT compute tags — only compares,
    // so a formula divergence would lose the subscription silently. The canon vector insures.
    static func subId(_ conv: String, ref: String) -> String { MTNodeWire.subId(conv, ref: ref) }
    /// THIS DEVICE'S subscription id under a wire label — computed in ONE place from the twin
    /// reference, never from a variable passed along. A free variable is a variable a loop can
    /// shadow: build 1480 renamed the outer `addr` to `ref`, the pipes loop below (its variable was
    /// already `ref`) took it over, subscriptions went out under the PIPE's reference, the node could no longer tell
    /// the caller from the callee, and the caller rang itself.
    private static func mySubId(_ cw: String) -> String { subId(cw, ref: twinRef) }
    /// THE VERSION OF THE ID FORMULA rides in the registration digest: when the formula changes
    /// (as it did by the shadow of 1480, which registered ids of pipes), the digest changes and
    /// EVERY subscription is posted anew under the true id — the node forgets the false rows by
    /// its own rule (one id per label per token). Without this, a corrected phone kept its old
    /// rows on the node and went on ringing itself (measured 06:26, build 1484).
    private static let subIdFormat = "sid-v2"

    /// The conversation's daily tag: both sides derive it from the shared pipe secret with no contact.
    static func convW(_ secret: Data, window: UInt64) -> String { MTNodeWire.convW(secret, window: window) }

    static func dayWindow() -> UInt64 { UInt64(Date().timeIntervalSince1970) / 86400 }

    /// The daily tag of a HANDED-OUT INVITE: both sides derive it from the invite itself.
    /// The first letter's receiver has no pipe secret yet — but they hold the invite, and that
    /// is enough for the node to ring their doorbell (F-2: the first-letter wake).
    static func rdvConvW(_ invite: Data, window: UInt64) -> String { MTNodeWire.rdvConvW(invite, window: window) }

    /// Frozen vectors: V1 catches a conv-addr swap and a hash without the domain separator,
    /// V2 — concatenation without the second separator, CW — reading the window from the
    /// other end (BE) and a daily tag without its domain.
    static func agreesWithCanon() -> Bool {
        subId("mt-conv-Q7", ref: "mtAddrZ93kLmNoPq") ==
            "e5438bfedc8b1fdcdadfb9f4d3995fac7722c0074f3a20ccd3e911ce5beb35de"
        && subId("ab", ref: "c") ==
            "a279974b24ff1b84299330076b5f5858684d56733458de21b152aa8521c7a230"
        && subId("a", ref: "bc") ==
            "c04b7d58e4c7aaca35800d119fd6fde021f95f7d3c9438e3ca46cd855afe6a8a"
        && convW(Data(0..<32), window: 29737) ==
            "43eaf2811da7947166d4e851e52c4ab89e09c8c92247370d3c734ef08ca1e6ea"
        && convW(Data(0..<32), window: 29738) ==
            "f5f2941435d76c0a80dd229722ef42382695e88fdd1fabf89d71f317bef05430"
    }

    // ── registering our token under our conversations ──────────────────────────
    static func bootstrap() {
        MontanaKeychain.set("wakeBase", Data(base("box").utf8))   // the node address — for the extension (config, not hardcode)
        // This line only seeds a first-launch mirror before any verification.
        if MontanaKeychain.get("wakeBases") == nil,
           let d = try? JSONEncoder().encode(bases(for: "box")) { MontanaKeychain.set("wakeBases", d) }
        mirrorSecrets()   // pipe secrets into the shared keychain — the extension decrypts the envelope
        UNUserNotificationCenter.current().getNotificationSettings { st in
            MontanaTrace.mark("wakepush_boot", "authz=\(st.authorizationStatus.rawValue) canon=\(agreesWithCanon() ? 1 : 0)")
        }
        DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Mirrors pipe secrets into the shared keychain so the notification extension opens the
    /// envelope on the device. Secrets stay device-only (WhenUnlocked keychain), never reach the accelerator.
    static func mirrorSecrets() {
        var m: [String: Data] = [:]
        var alias: [String: String] = [:]
        for conv in MTPipeBook.all() {
            guard let sec = MTPipeBook.secret(for: conv) else { continue }
            m[conv] = sec
            // One pipe may lie under the address AND under a local name (ref) — the sides key
            // differently. The extension opens with EITHER, while the mirrors (name/avatar/
            // mute/tap) live under the chat key. The mapping derives from the secret: ref -> chat key.
            if let ref = MTPipeBook.reference(of: sec), ref != conv { alias[ref] = conv }
        }
        // First-meeting letter secrets: live cards hand the same keys to the extension so the
        // first letter opens from a push without a live channel (key «rdv:<invite>»).
        for inv in MontanaCard.outstandingInvites() {
            m["rdv:" + inv.base64urlNoPad] = rdvLetterSecret(inv)
        }
        // The pipes of the slots this phone keeps (MTKeeping): the extension opens a loud call in them and shows whose copy it is.
        for (name, secret) in MTKeeping.listening() { m[name] = secret }
        if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set("nsePipeSecrets", d) }
        if let d = try? JSONEncoder().encode(alias) { MontanaKeychain.set("nsePipeAlias", d) }
        // The share extension sends letters itself; the sender identity rides sealed inside
        // the envelope, so the mirror carries it the same way it carries the pipe secrets
        // (device-only keychain, never the node).
        MontanaKeychain.set("wakeMyAddr", Data(twinRef.utf8))
        MontanaKeychain.set("wakeMyName", Data(E2E.myDisplayName().utf8))
        MontanaKeychain.set("wakeMyGlyph", Data(E2E.myFaceGlyph().utf8))
    }

    private static var twinRef: String { MontanaSeed.twin ?? "" }

    /// Apple issued the device token — register the subscriptions on the accelerator. A wake to a
    /// door goes out the instant a letter is queued — and on a phone whose tunnel is re-forming as
    /// it walks from Wi-Fi to cellular, the app-wide session fails it at once, before the tunnel is
    /// back (T1, 12–13.09: 126 of 474 wakes on cellular under a tunnel answered -1 within a
    /// millisecond, both doors in the same instant, then the letter waited for the next retry). The
    /// system's own answer is a session that WAITS for connectivity, bounded by the same eight
    /// seconds.
    static let knockSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 12
        return URLSession(configuration: cfg)
    }()
    /// The short name of a transport failure, for the diary: a URL error code, or none.
    static func errWord(_ e: Error?) -> String {
        guard let e else { return "-" }
        if let u = e as? URLError { return "url\(u.code.rawValue)" }
        return "e\((e as NSError).code)"
    }
    static func onDeviceToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        // THE TOKEN'S ARRIVAL IS A LINE, AND ITS CHANGE IS NAMED (20.09, the critic): the door's
        // standing map is named by the token below, so a changed token finds an empty map and every
        // pair is due again — measured 20.09 15:45Z: the node held T3's letter token of the day before
        // (production) while the phone lived under a new one (sandbox); nine pushes were accepted by
        // Apple and reached nothing, the map said «nothing new» for a week.
        let before = MontanaKeychain.get(ownTokenKey).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        MontanaKeychain.set(ownTokenKey, Data(hex.utf8))
        MontanaTrace.mark("wakepush_token", "len=\(hex.count) env=\(apsEnvironment()) changed=\(before.isEmpty ? "first" : (before == hex ? "0" : "1"))")
        registerConvs()
    }

    /// Register the token under all conversations' windows: (conv_w, sub_id) pairs for
    /// yesterday and 30 days ahead — a sleeping node cannot renew on demand, the tags are
    /// derived in advance. The node names the topic (Bundle.main.bundleIdentifier); the
    /// accelerator checks the form, not a list.
    /// Debounce: same set, same day — no repeat registration is sent.
    // The registration strobe: a squall of establishes (a batch of first cards) queued
    // requests and broke the node's rate — 429 muted the needed subscriptions too (the tablet
    // precedent). At most once in 3s; called during the strobe — exactly one repeat follows.
    private static var regStrobe = false
    private static var regTrail = false
    /// THIS ROUND NEVER STANDS ON THE MAIN THREAD (28.09, the author's word: «find every cause of the chat and the
    /// chat list freezing»). Measured on the 17 Pro Max under 1963: EVERY letter that landed held the main thread
    /// here -- main_slow what=wake ms=345, doors ms=345, rx:wall ms=375 -- sixty-three such lines in five hours, a
    /// quarter to a third of a second frozen at every arrival, which is exactly what the author sees. Nothing in
    /// this round belongs to a screen: the pipe book is unsealed, a tag is derived for every pipe and every window
    /// of the month, each door's standing map is unsealed, compared and sealed again, and the differences are
    /// posted. It runs on its own queue; the one main-thread fact it needs -- whom this device refuses -- is asked
    /// where the store lives and carried in.
    private static let regQ = DispatchQueue(label: "montana.wakepush.register", qos: .utility)
    static func registerConvs() {
        if regStrobe { regTrail = true; return }
        regStrobe = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            regStrobe = false
            if regTrail { regTrail = false; registerConvs() }
        }
        let refused = ChatStore.refusedNow()
        regQ.async { registerRound(refusing: refused) }
    }
    private static func registerRound(refusing refused: Set<String>) {
        mirrorSecrets()   // pipe secrets into the shared keychain — the extension decrypts the envelope
        registerVoip(refusing: refused)    // voip subscriptions march WITH the letter ones: a new pipe after a
                          // re-introduction entered the letter table (noteIncoming →
                          // registerConvs) but never voip (only on token issue, and the token
                          // does not change) → the call hit 404 (precedent T1↔T2)
        guard let hex = MontanaKeychain.get(ownTokenKey).flatMap({ String(data: $0, encoding: .utf8) }), !hex.isEmpty else { return }
        let ref = twinRef; guard !ref.isEmpty else { return }
        guard agreesWithCanon() else { MontanaTrace.mark("wakepush_canon", "FAIL"); return }
        // Fresh pipes FIRST: the node trims the body by size, and the alphabet used to decide
        // what survived. A new correspondence fell into the cut-off part, its wake hit 404
        // (precedent 17.08).
        let refs = MTPipeBook.registrable(refusing: refused)
        // Handed-out invites are subscriptions too (F-2): a device with one card and zero
        // pipes must register exactly like a device with pipes.
        let invites = MontanaCard.outstandingInvites()
        // AN EMPTY BOOK IS «UNKNOWN», NOT «NOTHING WANTED» (the critic's pass on 1574): before the
        // first unlock the vault is sealed and the book reads empty — reconciling against that
        // would withdraw every subscription of a phone that merely rebooted. A book that HOLDS
        // pipes and wants none of them (all blocked, all dying) is a decision, and it reconciles.
        guard !refs.isEmpty || !invites.isEmpty || !MTPipeBook.all().isEmpty else { return }
        let topic = Bundle.main.bundleIdentifier ?? ""
        let w0 = dayWindow()
        var subs: [[String: String]] = []
        // Invite tags FIRST: the node trims the body by size and rate (429 at 128 pairs,
        // 21:33), and order decides what survives. The daily code's doorbell outranks the
        // subscription of a long-silent pipe.
        for inv in invites {
            for w in (w0 - 1)...(w0 + windowsAhead) {
                let cw = rdvConvW(inv, window: w)
                subs.append(["conv": cw, "sid": mySubId(cw)])
            }
        }
        for pipe in refs {
            guard let secret = MTPipeBook.secret(for: pipe) else { continue }
            // The S-2 sign of life gates the fan-out: a pipe nobody ever answered has nobody
            // to wake us, and its first letter lives seven days in the node box anyway — the
            // box fetch is the road, the wake is a rung-4 accelerator. Full 31-day fan-out is
            // for ANSWERED correspondences only: hundreds of dead introductions at 32 rows
            // each hit the node's per-token cap (8192), and eviction cut LIVE pairs blind
            // (measured 26.08: one token at exactly 8192 rows, a receipt's wake answered 404).
            let ahead: UInt64 = MTPipeBook.first(for: pipe) == nil ? windowsAhead : 1
            for w in (w0 - 1)...(w0 + ahead) {
                let cw = convW(secret, window: w)
                subs.append(["conv": cw, "sid": mySubId(cw)])
            }
        }
        // THE SLOTS THIS PHONE KEEPS RING IT (MTKeeping, the author's word 08.10.2026 22:4x MSK: the restore by silent pushes): a
        // call in the pipe of a slot wakes this phone by a background push, and its answer leaves within the wake.
        for (_, secret) in MTKeeping.listening() {
            for w in (w0 - 1)...(w0 + 1) {
                let cw = convW(secret, window: w)
                subs.append(["conv": cw, "sid": mySubId(cw)])
            }
        }
        // THE SHELF RINGS THE PHONE TOO (07.10, MTShelfPost): the persons waiting on this phone's shelf are registered under
        // their own references, after the person seated -- the node trims the tail first.
        let seated = Set(MTPipeBook.all().compactMap { MTPipeBook.secret(for: $0) })
        subs += MTShelfPost.wakePairs(w0, seatedHolds: { seated.contains($0) })
        // ONLY WHAT CHANGED LEAVES (21.1). The whole set used to go to every door whenever its
        // digest moved — and the digest moved with the day, with the door order, with every
        // failed chunk: twelve posts of 128 pairs in seven seconds on one phone (08.09 08:31).
        // Each door keeps its standing set with the moment each pair was posted; a pair leaves
        // when the door does not hold it or held it for a week (the store forgets rows after 31
        // days, so a weekly refresh keeps the far windows alive). Nothing new — nothing leaves.
        // 128 pairs ≈ 21KB < the node's 64KiB body limit; chunks go AS A CHAIN, not a volley;
        // the 429 retry is ONE per call, with a growing pause.
        // THE DOOR'S SET IS A MIRROR, NOT A LEDGER OF ADDITIONS (the critic's word 15.09, measured
        // 13:56: a block made under an older build left its pairs standing at the node for the
        // rows' month of life — every letter and every call of the blocked person still woke this
        // phone, and the system showed «Montana» and a missed call before the app could refuse).
        // Two differences travel: what the door lacks goes to /register, what the door still holds
        // and this phone no longer wants goes to /unregister (letters and calls in one deletion).
        // The standing map is the one record of what the door holds; a pair leaves the map only
        // when the door answered 200 to its removal, so a failed removal is asked again next time.
        let now = Date().timeIntervalSince1970
        let wanted = Set(subs.map(pairKey))
        // A BLOCKED PERSON'S PAIRS ARE ASKED GONE UNTIL THE DOOR CONFIRMS IT (measured 15.09 15:05):
        // the map may hold no record of them — a removal under an older build named the letter
        // token only, the map forgot the pair, and the door's call row lived on and woke the
        // phone. So for every blocked correspondence the pairs whose answer is UNKNOWN to the map
        // are asked gone; a door's «gone» is recorded (a negative moment) and never asked again.
        var blockedPairs: [[String: String]] = []
        for pipe in MTPipeBook.all() where refused.contains(pipe) {
            guard let secret = MTPipeBook.secret(for: pipe) else { continue }
            for w in (w0 - 1)...(w0 + windowsAhead) {
                let cw = convW(secret, window: w)
                blockedPairs.append(["conv": cw, "sid": mySubId(cw)])
            }
        }
        // A DOOR THAT DOES NOT ANSWER RESTS (20.09, the critic): a registration to a door that
        // answered nothing (-1) or a 5xx used to be asked again on the growing pause and again at
        // every launch — T3 posted 128 pairs to door.montana.xxx every twenty seconds for hours. The
        // door rests as it rests for a knock (noteTooOften: a minute, two, four… half an hour) and is
        // asked the moment it answers anything again (doorRevived → registerConvs).
        // ONE DOOR PER MACHINE (24.09): a machine keeps the pairs in ONE table whatever name led to it, so the
        // second name of a held machine is asked nothing -- the law the ring has kept since P-104. Measured 23.09
        // 20:43-21:06 on T1 (1915): api.* held every pair, and door.* of the SAME two machines was posted to at
        // every revival -- a proxied POST timed out, the door rested, a small read revived it a minute later, and
        // the round went out again: eight timeouts to two doors that held nothing new. The second name is walked
        // only while the first rests (notBusy runs first), and then its own map decides what is due there.
        for b in oneDoorPerNode(notBusy(orderedBases(for: "notify"))) {
            guard let url = URL(string: b + "/register"), let gone = URL(string: b + "/unregister") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            let host = URL(string: b)?.host ?? b
            let standing = registeredPairs(host, token: hex)   // positive: held by the door since; negative: confirmed gone at; absent: unknown
            let due = doubtedNow(host, token: hex) ? subs : subs.filter { p in (standing[pairKey(p)] ?? 0) < now - regRefresh }
            var stale: [[String: String]] = standing.filter { 0 < $0.value && !wanted.contains($0.key) }.keys.compactMap { k in
                let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
                return parts.count == 2 ? ["conv": parts[0], "sid": parts[1]] : nil
            }
            stale += blockedPairs.filter { standing[pairKey($0)] == nil }
            // A door that does not know the question (404, an unpatched node) is not asked again
            // for six hours: the stale pairs stay in the map, and every registration round used
            // to carry a 21KB body to it for nothing (the critic's pass on 1574).
            // The removal names BOTH tokens (measured 15.09 14:51): the letter table holds the
            // letter token, the call table the call token; a removal under one left the other's
            // row standing, and the blocked caller still woke the phone.
            let vtoken = MontanaKeychain.get(voipTokenKey).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if !stale.isEmpty, (unregisterUnknown[host] ?? 0) < now - 6 * 3600 {
                sendChunks(stale, url: gone, token: hex, topic: topic, digestKey: regDigestKey, tag: "wakepush_unreg",
                           recorded: { chunk in
                               noteGone(host, chunk, at: now, token: hex)
                               // the removal named the call token too: the call map mirrors the same answer
                               if !vtoken.isEmpty { noteGone(host, chunk, at: now, token: vtoken) }
                           },
                           extra: vtoken.isEmpty ? [:] : ["vtoken": vtoken],
                           refused: { code in if code == 404 { unregisterUnknown[host] = now } })
            }
            guard !due.isEmpty else {
                MontanaTrace.markFolded("wakepush_reg", "standing=\(subs.count) door=\(host) token=\(String(hex.prefix(8))) — nothing new", window: 600)
                if let p = subs.first { askHeld(url, host: host, token: hex, topic: topic, pair: p, extra: ["faces": 1, "heard": 1], tag: "wakepush_held") }
                continue
            }
            // «faces»: this build holds the fallback keys in its catalog, so the node may send a
            // loc-key instead of the English literal. A build without them never says it, and the
            // node keeps the literal for it — the raw key must never reach a screen.
            // «heard»: this build's extension tells the doors which bell it heard (NotificationService.tellHeard), so the
            // node may keep the token's last bell loud until then (10.10).
            sendChunks(due, url: url, token: hex, topic: topic, digestKey: regDigestKey, tag: "wakepush_reg",
                       recorded: { chunk in noteRegistered(host, chunk, at: now, token: hex) }, extra: ["faces": 1, "heard": 1])
        }
    }

    /// Doors that answered 404 to /unregister, with the moment: asked again after six hours.
    private static var unregisterUnknown: [String: Double] = [:]
    /// A pair the door confirmed gone (200 to the removal) is recorded as a NEGATIVE moment: known
    /// not held, not asked again; a later registration overwrites it with the positive one.
    private static func noteGone(_ host: String, _ pairs: [[String: String]], at now: Double, token hex: String) {
        regSetLock.lock(); defer { regSetLock.unlock() }   // LOCK-OK: read-modify-write of the registration-set record
        var m: [String: Double] = [:]
        if let d = MontanaLocalVault.getDecrypted(regSetKey(host, token: hex)),
           let mm = try? JSONDecoder().decode([String: Double].self, from: d) { m = mm }
        for p in pairs { m[pairKey(p)] = -now }
        m = m.filter { now - 31 * 86400 < abs($0.value) }
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(regSetKey(host, token: hex), d) }
    }
    /// The pairs a door already holds, with the moment each was posted (21.1) — one map per door,
    /// sealed in the vault; pruned past the store's own memory of 31 days.
    private static let regRefresh: Double = 7 * 86400
    private static let regSetLock = NSLock()
    private static func pairKey(_ p: [String: String]) -> String { (p["conv"] ?? "") + "|" + (p["sid"] ?? "") }
    /// THE STANDING MAP IS NAMED BY THE TOKEN (20.09, the critic): what a door holds is a row
    /// «pair → token», so the map of «held» pairs is only true for the token it was posted under.
    /// A new token — a reinstall, a change of environment — finds an empty map and every pair is
    /// due at once; the door's one-label-per-pair rule then replaces the old token's row. Before
    /// this the map was named by the door alone and a changed token stood on «nothing new» for a
    /// week while the door rang the token of yesterday.
    /// The door's standing maps are named under this prefix, once: SeedScope names it as this device's own.
    static let regSetPrefix = "regSet_"
    /// THE MAPS ARE BORN AGAIN ONCE (10.10.2026). Until the node kept one row per token, another app of the same seed took a
    /// pair's row and its withdrawal deleted it while this map still called the pair held: T1's letters of 23:10Z and 00:00Z
    /// found no row at either node (woken=0/0). A new generation finds every map empty and posts every pair once.
    private static let regGeneration = "-g2"
    /// The call token keeps maps of its own under the same law (23.09): the caller names the token the pairs
    /// were posted under -- the letters' token or the call token -- and each gets its own map per door.
    private static func regSetKey(_ host: String, token hex: String) -> String {
        let tok = SHA256.hash(data: Data(hex.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return regSetPrefix + subIdFormat + regGeneration + "_" + host + "_" + tok
    }
    private static func registeredPairs(_ host: String, token hex: String) -> [String: Double] {
        regSetLock.lock(); defer { regSetLock.unlock() }   // LOCK-OK: read-modify-write of the registration-set record
        // The standing set is named by the id formula too: when the formula moves (sid-v2, 12.09),
        // every pair is new to the door by construction — the door then drops the rows of the old
        // formula (its one-label-per-token rule), and no stale row is left to ring us with our own
        // letters. Measured 12.09: a phone registered before the door's rule stood on «nothing new»
        // 27 times while the door still held its old labels — and rang it with its own ring letter.
        guard let d = MontanaLocalVault.getDecrypted(regSetKey(host, token: hex)),
              let m = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
        return m
    }
    /// WHAT A DOOR KEEPS IS ASKED, NOT REMEMBERED (the author's word 10.10.2026 12:5x MSK: «notifications reinforced concrete, not
    /// one error in principle»). The standing map is this phone's belief, and the belief stood a week while the door had lost the
    /// rows under it. A round with nothing to post asks the door, at most twice an hour, how many rows it keeps for this token
    /// (montana-notify answers "rows" since 10.10, re-asserting one pair); a door keeping fewer than the map believes is posted
    /// the whole set at the next round. The node keeps at most 8192 rows for a token, so a belief above that is read at the cap.
    private static var heldAskedAt: [String: Double] = [:]   // BOUND-OK: one moment per door and token
    private static var doubted: Set<String> = []             // BOUND-OK: doors whose rows fell short, until the next round
    private static let heldLock = NSLock()
    private static func doubtedNow(_ host: String, token hex: String) -> Bool {
        heldLock.withLock { doubted.remove(host + "@" + hex) != nil }
    }
    private static func askHeld(_ url: URL, host: String, token hex: String, topic: String, pair: [String: String],
                                extra: [String: Any], tag: String) {
        let now = Date().timeIntervalSince1970
        let key = host + "@" + hex
        let ask: Bool = heldLock.withLock {
            if let at = heldAskedAt[key], now - at < 1800 { return false }
            heldAskedAt[key] = now
            return true
        }
        guard ask else { return }
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: Any] = ["token": hex, "environment": apsEnvironment(), "topic": topic, "subs": [pair]]
        for (k, v) in extra { body[k] = v }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        knockSession.dataTask(with: req) { data, resp, _ in   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let o = data.flatMap({ try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any],
                  let rows = o["rows"] as? Int else { return }   // a door before 10.10 does not say what it keeps
            let believed = min(8192, registeredPairs(host, token: hex).values.filter { 0 < $0 && now - 31 * 86400 < $0 }.count)
            MontanaTrace.markFolded(tag, "door=\(host) keeps=\(rows) believed=\(believed)", window: 3600)
            guard rows < believed else { return }
            MontanaTrace.mark(tag, "door=\(host) keeps=\(rows) believed=\(believed) -- rows lost at the door, the whole set goes again")
            heldLock.withLock { _ = doubted.insert(key) }
            DispatchQueue.main.async { registerConvs() }
        }.resume()
    }
    private static func noteRegistered(_ host: String, _ chunk: [[String: String]], at now: Double, token hex: String) {
        regSetLock.lock(); defer { regSetLock.unlock() }   // LOCK-OK: read-modify-write of the registration-set record
        var m: [String: Double] = [:]
        if let d = MontanaLocalVault.getDecrypted(regSetKey(host, token: hex)),
           let mm = try? JSONDecoder().decode([String: Double].self, from: d) { m = mm }
        for p in chunk { m[pairKey(p)] = now }
        m = m.filter { now - 31 * 86400 < abs($0.value) }   // a «gone» record lives as long as the door's own memory of the row
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(regSetKey(host, token: hex), d) }
    }

    // ── the shared registration engineer: a chunk chain + one retry with a growing pause ──
    private static var regRetryDelay: Double = 12
    private static var regRetryArmed = false
    /// ONE CHAIN PER DOOR PER LANE (24.09). Two rounds 180 ms apart at the launch of 1915 (the call token's own
    /// arrival and the letters' round) each found every pair due -- the first chain had recorded nothing yet --
    /// and the same 736 pairs went to each machine twice (T1 20:43:45, twelve posts a door). A chain in flight IS
    /// the answer to «what is due at this door» until it ends; a second one is not started, and the next round
    /// reads the map the first one wrote.
    private static var regChains: Set<String> = []
    private static let regChainLock = NSLock()
    private static func regChainStarts(_ tag: String, _ host: String) -> Bool {
        regChainLock.lock(); defer { regChainLock.unlock() }   // LOCK-OK: one set insert
        return regChains.insert(tag + "@" + host).inserted
    }
    private static func regChainEnds(_ tag: String, _ host: String) {
        regChainLock.lock(); regChains.remove(tag + "@" + host); regChainLock.unlock()
    }
    private static func sendChunks(_ subs: [[String: String]], url: URL, token: String, topic: String,
                                   digestKey: String, tag: String, index: Int = 0,
                                   recorded: (([[String: String]]) -> Void)? = nil, extra: [String: Any] = [:],
                                   refused: ((Int) -> Void)? = nil) {
        let host = url.host ?? "-"
        guard index < subs.count else { regRetryDelay = 12; regChainEnds(tag, host); return }   // the whole chain passed — the pace is forgiven
        if index == 0, !regChainStarts(tag, host) {
            MontanaTrace.markFolded(tag, "in flight door=\(host) -- one chain at a time", window: 60, key: tag + "@" + host)
            return
        }
        let chunk = Array(subs[index..<min(index + 128, subs.count)])
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var regBody: [String: Any] = ["token": token, "environment": apsEnvironment(), "topic": topic, "subs": chunk]
        for (k, v) in extra { regBody[k] = v }
        req.httpBody = try? JSONSerialization.data(withJSONObject: regBody)
        knockSession.dataTask(with: req) { _, resp, _ in   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            MontanaTrace.mark(tag, "code=\(code) pairs=\(chunk.count) door=\(url.host ?? "-") token=\(String(token.prefix(8)))")
            if code == 200 {
                noteAnswered(url.absoluteString)
                recorded?(chunk)   // the door holds these now — they will not leave again this week
                sendChunks(subs, url: url, token: token, topic: topic, digestKey: digestKey, tag: tag,
                           index: index + 128, recorded: recorded, extra: extra, refused: refused)   // the next car — only after the answer
                return
            }
            refused?(code)
            MontanaKeychain.set(digestKey, Data())   // failure — the set does not count as standing
            if code < 0 || code >= 500 { noteTooOften(url.absoluteString) }   // a silent door rests; the retry below walks the doors that answer
            regChainEnds(tag, host)   // the chain stops at the first refusal: the next round asks this door afresh
            // A DOOR THAT DID NOT ANSWER IS ASKED AGAIN (15.09): a removal that times out leaves the
            // door holding a pair this phone withdrew, and the next occasion may be an hour away —
            // measured 14:45, Amsterdam's removal answered -1 and the blocked caller's wake found the
            // row twenty-five seconds later. Every failure but «the door does not know the question»
            // (404) rides the one retry, on the same growing pause the rate limit uses.
            guard code != 404 else { return }
            DispatchQueue.main.async {          // one thread owns the retry lock — no race
                guard !regRetryArmed else { return }
                regRetryArmed = true
                let delay = regRetryDelay
                regRetryDelay = min(300, regRetryDelay * 2)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    regRetryArmed = false
                    registerConvs()   // the single entrance: the strobe holds, both sets re-register
                }
            }
        }.resume()
    }

    /// The token environment is read from the embedded profile (aps-environment), NOT from
    /// #if DEBUG: hard-setting yields sandbox even in Release (the production notification contract's lesson).
    private static func apsEnvironment() -> String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let s = String(data: data, encoding: .isoLatin1),
              let r = s.range(of: "<key>aps-environment</key>") else { return "production" }
        let value = s[r.upperBound...].prefix(200)
        return value.contains("development") ? "sandbox" : "production"
    }

    // Compatibility with older callers: every road leads to re-registration (the debounce
    // makes it cheap — no set change, same day, no request leaves).
    static func announceAll() { registerConvs() }
    static func announce(to conv: String, handle: String? = nil) { registerConvs() }
    static func noteIncoming(from conv: String) { registerConvs() }
    static func reannounce(to conv: String) { registerConvs() }
    static func rememberPeer(_ conv: String, handle: String) {}   // the handle model is gone — the subscription lives by tag
    static func forgetPeer(_ conv: String) {}

    private static var knocked: [String: UInt64] = [:]
    private static let knockLock = NSLock()

    // ── the node's clock, learned in passing ([C-1] — one owner) ─────────────
    private static var skewLock = NSLock()
    /// THE CLOCK LEARNED IN THE LAST LIFE STARTS THIS ONE (24.09, the second critic's pass): the skew was learned only
    /// from the lane's fetch and the diary's ship, and every launch began at zero — the words said before the first
    /// answer, the app's greeting among them, wore the phone's own time, and a phone set wrong stood outside every peer's
    /// «now» for a whole session. The last skew learned stays on this device, and the next life starts from it.
    static let skewKey = "mt.node.skew"
    private static var _nodeSkewMs = UserDefaults.standard.integer(forKey: skewKey)
    /// This phone's clock minus the node's, in milliseconds, from the last answer's Date header.
    static var nodeSkewMs: Int {
        get { skewLock.lock(); defer { skewLock.unlock() }; return _nodeSkewMs }
        set { skewLock.lock(); _nodeSkewMs = newValue; skewLock.unlock() }
    }
    /// «Now» by the node's clock: the one moment both ends of a call can agree on, however
    /// wrong either phone's own clock is. The local clock only in a first life, until a node answers.
    static func nodeNow() -> TimeInterval { Date().timeIntervalSince1970 - Double(nodeSkewMs) / 1000 }
    /// How far the node clocks of two phones may disagree: the Date header's whole second and the road's latency. A
    /// moment held further ahead than this was said by a wrong clock (ChatStore.liveWordMoves); a correction larger than
    /// this moved this phone's own «now» (learnSkew).
    static let clockSlackS: TimeInterval = 2
    static let httpDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
    static func learnSkew(from resp: URLResponse?) {
        guard let hdr = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"),
              let server = httpDateFormatter.date(from: hdr) else { return }
        let skew = Int(Date().timeIntervalSince(server) * 1000)
        let tolMs = Int(clockSlackS * 1000)
        // A CORRECTION IS TOLD ONLY WHEN IT STANDS (24.09, the noticed point 3 — the author's word «close it»): the first
        // answer of a life, or two answers in a row that agree. Two doors whose clocks disagreed would flip the skew at
        // every answer, and each flip would say the greeting again. Measured 24.09 from Lauterbourg (NTP-synchronised):
        // the four doors of both nodes stand within 0.26 s of it; this keeps the greeting quiet if one ever drifts.
        skewLock.lock()   // LOCK-OK: the skew, its last sample and the one told, in memory
        let moved = abs(skew - _nodeSkewMs)
        let stands = lastSkewSample.map { abs($0 - skew) <= tolMs } ?? true
        let tell = stands && abs(skew - toldSkewMs) > tolMs
        _nodeSkewMs = skew; lastSkewSample = skew
        if tell { toldSkewMs = skew }
        skewLock.unlock()
        if moved >= 250 { UserDefaults.standard.set(skew, forKey: skewKey) }   // the next life starts from it
        // A CORRECTION LARGER THAN TWO CLOCKS DISAGREE moved my «now»: the app's word said by a clock behind read as
        // history everywhere — it is said once more (E2E.clockCorrected). A clock that ran ahead keeps the word counter
        // ahead until real time passes it: the counter never steps back (P-95).
        if tell { DispatchQueue.main.async { E2E.shared.clockCorrected() } }
    }
    private static var lastSkewSample: Int?
    private static var toldSkewMs = UserDefaults.standard.integer(forKey: skewKey)   // the skew the life's first words were said by

    /// Open a letter envelope IN THE APP (a background push bypasses the extension): the same
    /// pipe walk and format as the extension's. Returns (conversation, mid, text).
    static func openLetterEnvelope(_ sealed: Data) -> (conv: String, mid: String, text: String)? {
        for conv in MTPipeBook.all() {
            guard let secret = MTPipeBook.secret(for: conv),
                  let plain = MTPipe.openBody(sealed, sharedSecret: secret),
                  let sep = plain.firstIndex(of: 0) else { continue }
            let mid = String(data: plain[..<sep], encoding: .utf8) ?? ""
            let tail = plain[plain.index(after: sep)...]
            let text = String(data: tail[..<(tail.firstIndex(of: 0) ?? tail.endIndex)], encoding: .utf8) ?? ""
            if !mid.isEmpty, !text.isEmpty { return (conv, mid, text) }
        }
        return nil
    }

    /// A long letter (text over the 2048 envelope): the full body rides as a sealed blob, the
    /// envelope carries the invisible reference \u{2063}LB:{r,k} (the key inside the E2E envelope, the node is blind).
    static let letterBlobMark = "\u{2063}LB:"

    /// 7.2b: a long letter's reference is born ONCE and reused. The seal key used to be random
    /// per run: every retry of an undelivered letter uploaded a NEW orphan blob (litter grew
    /// with retries), and the name was incomputable at burial. Now the blob is one, and it is
    /// in the ledger (releaseLetter returns it on delivery, expiry and burial).
    private static let longRefsKey = "longLetterRefs"
    private static let longRefLock = NSLock()
    private static func longRef(_ mid: String) -> String? {
        longRefLock.lock(); defer { longRefLock.unlock() }   // LOCK-OK: one read of the long-refs record
        guard let d = MontanaLocalVault.getDecrypted(longRefsKey),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return nil }
        return m[mid]
    }
    private static func setLongRef(_ mid: String, _ link: String?) {
        longRefLock.lock(); defer { longRefLock.unlock() }   // LOCK-OK: read-modify-write of the long-refs record
        var m = MontanaLocalVault.getDecrypted(longRefsKey)
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        if let link { m[mid] = link } else if m.removeValue(forKey: mid) == nil { return }
        if let d = try? JSONEncoder().encode(m) { _ = MontanaLocalVault.setEncrypted(longRefsKey, d) }
    }
    /// The letter ended by any outcome — the reference is forgotten; true if there was one (a long letter).
    static func takeLongRef(_ mid: String) -> Bool {
        let had = longRef(mid) != nil
        if had { setLongRef(mid, nil) }
        return had
    }

    static func sealLongLetter(mid: String, text: String) async -> String? {
        // ONE BLOB PER LETTER, WHILE ITS CARGO IS STILL OURS TO SERVE (23.09, the critic). The cached
        // reference was reused whatever had happened to its cargo: a letter whose chunks were released —
        // the cargo check found them gone and the row went red — was resent by hand under the same name
        // with the same dead reference, and the receiver asked for a cargo nobody would ever hold. The
        // ledger is the one record of what this phone keeps on the node: a cached reference whose chunk
        // the ledger no longer names for this letter is sealed afresh.
        if let cached = longRef(mid) {
            if let bid = longLinkBid(cached), bidsOf(letter: mid).contains(bid) { return cached }
            setLongRef(mid, nil)
            MontanaTrace.mark("letter_blob", mid: mid, "the cached reference names a released cargo — a fresh one is sealed")
        }
        var full = Data(mid.utf8); full.append(0); full.append(contentsOf: text.utf8)
        let mk = montanaRandom(32)
        guard let sealed = MontanaDirect.seal(key: [UInt8](mk), full) else { return nil }
        let bid = MontanaMedia.blobIdHex(sealed)
        guard await putBlob(bid, data: sealed) else { MontanaTrace.mark("letter_blob", "FAIL up"); return nil }
        let refObj: [String: String] = ["r": bid, "k": mk.base64EncodedString()]
        guard let j = try? JSONSerialization.data(withJSONObject: refObj),
              let js = String(data: j, encoding: .utf8) else { return nil }
        let link = letterBlobMark + js
        noteChunks(letter: mid, bids: [bid])
        setLongRef(mid, link)
        return link
    }

    /// The chunk a long-letter reference names.
    static func longLinkBid(_ link: String) -> String? {
        guard link.hasPrefix(letterBlobMark),
              let d = link.dropFirst(letterBlobMark.count).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else { return nil }
        return o["r"]
    }

    /// What a long letter's reference yields. «GONE» IS A VERDICT, «LATER» IS WEATHER (23.09, the
    /// critic): the store road knew both — every door answering «no such cargo» against a door busy or
    /// out of reach — and this road flattened them into one failure that then waited a whole day. A
    /// reference that does not parse, or a cargo that comes and does not open with its own key, is a
    /// verdict too: asking again returns the same bytes.
    enum LongLetter { case words(String); case gone; case later }
    static func fetchLongLetter(_ text: String) async -> LongLetter {
        guard text.hasPrefix(letterBlobMark),
              let d = text.dropFirst(letterBlobMark.count).data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              let bid = o["r"], let mkB64 = o["k"], let mk = Data(base64Encoded: mkB64) else {
            MontanaTrace.mark("letter_blob", "FAIL ref — the reference does not parse")
            return .gone
        }
        switch await askBlob(bid) {
        case .found(let sealed):
            guard let plain = MontanaDirect.open(key: [UInt8](mk), sealed),
                  let sep = plain.firstIndex(of: 0),
                  let full = String(data: plain[plain.index(after: sep)...], encoding: .utf8), !full.isEmpty else {
                MontanaTrace.mark("letter_blob", "FAIL open — the cargo came and does not open with its key")
                return .gone
            }
            return .words(full)
        case .gone:
            MontanaTrace.mark("letter_blob", "FAIL dl gone — every door answered: no such cargo")
            return .gone
        case .busy, .unreachable:
            MontanaTrace.mark("letter_blob", "FAIL dl later — no door could answer now")
            return .later
        }
    }

    static func resolveLongLetter(_ text: String) async -> String? {
        guard text.hasPrefix(letterBlobMark) else { return nil }   // not a reference — ordinary. SILENT-OK
        if case .words(let full) = await fetchLongLetter(text) { return full }
        return nil
    }

    /// The letter envelope format — ONE place (SSOT): mid‖0x00‖text‖0x00‖zeros to 2048, under
    /// the pipe key. A single size — the accelerator cannot tell letter lengths apart. Called
    /// by both enqueue (the instant wake) and attempt (the insurance).
    static func sealLetterEnvelope(mid: String, text: String, secret: Data,
                                   quoteText: String? = nil, quoteMid: String? = nil,
                                   linkPreview: String? = nil) -> String? {
        // The sender's identity rides WITH THE LETTER, inside the E2E seal — as in the server
        // model where the banner carried the sender: the name in exact case + the face glyph
        // (callsign emoji). Deposits and one-shot NM letters are not needed for the banner:
        // the receiver always holds a fresh name.
        // AIR-CHECKED: the fields are under the pipe key; the node sees only the uniform 2048 block.
        // The head — and the quote tail — come from the one owner (MTNodeWire.letterHead): the
        // sheet and the landing door seal the very same bytes (SSOT-CONSOLIDATE, 18.09).
        var body = MTNodeWire.letterHead(mid: mid, text: text, name: E2E.myDisplayName(), glyph: E2E.myFaceGlyph(),
                                         quoteText: quoteText, quoteMid: quoteMid)
        let quoted = quoteText?.isEmpty == false
        if let card = MTLinkPreview.parse(linkPreview)?.withoutImage.json,
           let tail = quoted ? MTLinkPreviewBuilder.wireTailAfterQuote(lp: card)
                             : MTLinkPreviewBuilder.wireTail(lp: card),
           body.count + tail.count <= MTNodeWire.envelopeSize {
            // Decoration: does not fit — rides without it.
            body.append(tail)
        }
        guard let padded = MTNodeWire.padEnvelope(body) else { return nil }
        return MTPipe.sealBody(padded, sharedSecret: secret)?.base64EncodedString()
    }

    /// Wake a sleeping peer: the accelerator sends the APNs wake to every subscription of this
    /// conversation's daily tag EXCEPT the presented sender tag. Carries the E2E envelope of a
    /// single size; the accelerator does not read it. Fire-and-forget.
    private static var lastWakeAt: [String: Date] = [:]
    private static let wakeBudgetLock = NSLock()

    /// `envelope` — THE SEAL IS MADE AT THE KNOCK (16.09): a sealed body wears the minute it was
    /// sealed in, and the receiver opens by the minute the node took it; a walk over dead doors,
    /// a suspended app or a stalled carrier route carries one seal into the next minutes. The
    /// maker seals afresh for every door. `sealedEnvelopeB64` stays for a body made once on purpose.
    static func wake(_ conv: String, mid: String, sealedEnvelopeB64: String?, envelope: (() -> String?)? = nil,
                     silent: Bool = false, recall: Bool = false, look: String = "", slot: String = "",
                     completion: ((Int) -> Void)? = nil) {
        var silent = silent
        let ref = twinRef; guard !ref.isEmpty else {
            MontanaTrace.mark("wakepush_skip", "no-addr to=\(String(conv.prefix(10)))"); return
        }
        guard agreesWithCanon() else { MontanaTrace.mark("wakepush_canon", "FAIL"); return }
        guard let secret = MTPipeBook.secret(for: conv) else {
            MontanaTrace.mark("wakepush_skip", "no-pipe to=\(String(conv.prefix(10)))"); return
        }
        let w = MTPipe.window()
        knockLock.lock()
        // A recall bypasses the lock: it is not a ring but a ring's CANCELLATION — a cached
        // «200» here would mean «cancelled» without cancelling (and the trace would honestly lie with a cached code).
        let dup = !recall && knocked["\(conv):\(mid)"] == w
        knockLock.unlock()
        // The lock stands ONLY on success: the node has ALREADY accepted this mid in this
        // window — the 200 is honest. The lock used to be set BEFORE sending, and after a
        // failed knock (404, a break) every retry got a fake 200 — the engine dropped the
        // letter from the queue as «handed to the node» which the node had never seen. Letter
        // 8FD71703, lost 17.08, died exactly so.
        if dup { MontanaTrace.mark("wakepush_dup", "cached-200 to=\(String(conv.prefix(10)))"); completion?(200); return }
        // THE WAKE BUDGET IS THE BELL'S — BUT THE LETTER ALWAYS RIDES. The node allows thirty
        // wakes a minute per correspondence, and a call burned them on its own ICE candidates
        // (04.09 17:51:14), so a second wake to the same correspondence within three seconds
        // folds its RING. It used to fold the whole call — «the letter is boxed either way» —
        // and that was false: the box is filled by this very post, so a letter that lost the
        // three-second race was never boxed at all, and every five-minute retry re-ran the same
        // volley in the same order with the same loser. Measured 08.09: a media letter rode from
        // 10:32 to 15:00 without ever reaching the box while the two texts beside it did (T1,
        // 104 folded wakes to one correspondence in a day). Now a folded wake still posts the
        // envelope — silently: the peer woken three seconds ago drains the box on that wake.
        // Bells («ans-») and recalls always ring.
        let bell = mid.hasPrefix("ans-")
        // ONLY A RING SPENDS THE RING'S WINDOW (13.09 16:51): a silent service wake set the
        // three-second mark, and the person's text 1.6 s later lost its ring to it — a
        // background push iOS held for seventy-four minutes until the app was opened. A silent
        // wake neither takes the window nor is folded; a ring folds only after a RING.
        if !bell && !recall && !silent {
            wakeBudgetLock.lock()
            let last = lastWakeAt[conv] ?? .distantPast   // the last RING to this correspondence
            let coalesce = Date().timeIntervalSince(last) < 3
            if !coalesce { lastWakeAt[conv] = Date() }
            wakeBudgetLock.unlock()
            if coalesce {
                MontanaTrace.markFolded("wakepush_coalesced", "to=\(String(conv.prefix(10))) — the ring folds, the letter still rides", window: 30)
                silent = true
            }
        }
        let cw = convW(secret, window: dayWindow())
        var body: [String: Any] = ["conv": cw, "from_id": mySubId(cw), "mid": mid]
        if silent { body["silent"] = true }   // a service letter: a background push, no banner
        if recall { body["recall"] = true }   // recall: the node erases «already rang» — the retry regains its loud knock
        // A notification accelerates, it does not carry: the Mac turned none into a letter and read an empty
        // box four times while four forwarded letters waited 9 min 45 s. Every reader of the node's 200 (the
        // silent repeat, the knock lock of the minute, the service letter settled on 200, the one checkmark)
        // stands on «the box holds it» -- true again. The node still knows the word; nothing asks it until a
        // road proves it carried the letter. The face of the fallback alert (13.09): the node turns it into
        // words the receiver's own catalog holds.
        if !silent, !look.isEmpty { body["look"] = look }
        // One call, one slot: two loud letters of the same call replace each other on the screen
        // instead of standing side by side.
        if !silent, !slot.isEmpty { body["slot"] = slot }
        // THE LETTER RIDES THE LANE BESIDE THE BOX (the author's word 29.09: a move must be as instant as a word in the chat --
        // we play there). While this phone holds the live lane to the correspondent (their chat or their board on the screen),
        // the very envelope the box will hold leaves on the lane too and lands at once on a peer whose lane is up; the box stays
        // the road that survives a sleeping peer, and the receiver buries the box's copy as a repeat (the mid dedup of the one
        // incoming door). Measured 1998 with both boards open: the box's walk waited five seconds on a dead door (T3 16:07:59.48
        // to 16:08:04.51) and the store's hint came five seconds late (T1 16:08:18.13 to 16:08:23.22); the lane answers the
        // same millisecond. Nothing rides twice to a phone whose chat is closed here; bells and recalls carry no envelope.
        if let laneEnv = envelope?() ?? sealedEnvelopeB64 {
            sigQ.async {
                guard chatConvs.contains(conv) || boardConvs.contains(conv) else { return }
                MontanaTrace.mark("lane_letter", "tx mid=\(String(mid.prefix(8))) to=\(String(conv.prefix(10)))")
                DispatchQueue.global(qos: .userInitiated).async { postSignal(conv, epoch: "letter", payloadB64: laneEnv) }
            }
        }
        // THE RING WALKS THE DOORS in the network's order and stops at the FIRST 200 —
        // one ring, never two (per-node stores do not talk to each other; a dead first
        // node hands the walk to the next inside seconds, not a minute).
        // One door per machine, and no machine that has just asked to be left alone.
        let doors = notBusy(oneDoorPerNode(orderedBases(for: "box")), conv: conv)
        guard !doors.isEmpty else {
            MontanaTrace.markChanged("wakepush_hold", "every machine asked to wait — the letter keeps its place in the queue", every: 60)
            completion?(429); return
        }
        func knock(_ i: Int) {
            guard i < doors.count, let url = URL(string: doors[i] + "/wake") else { completion?(-1); return }
            // THE PAUSE IS READ AT THE MOMENT OF FIRING, not when the list was drawn up. A drain
            // releases a volley of letters inside one millisecond: every one of them passed the
            // filter before the first «too often» came back, and then all of them hammered the very
            // door that had just asked to be left alone — measured 18:56, 438 hold lines and 300
            // knocks in nine minutes, our own storm against our own node, driving its rate limit
            // deeper on every pass.
            guard notBusy([doors[i]], conv: conv).count == 1 else {
                if i + 1 < doors.count { knock(i + 1) } else { completion?(429) }
                return
            }
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 8
            var kb = body
            let env = envelope?() ?? sealedEnvelopeB64   // sealed NOW, for this door
            if let e = env { kb["env"] = e }
            req.httpBody = try? JSONSerialization.data(withJSONObject: kb)
            let dh = URL(string: doors[i])?.host ?? String(i)   // the trace names the door, not its index (08.09)
            // SERVER-DEBT-ACK: the wake request to the accelerator node; letters are not delivered through it.
            knockSession.dataTask(with: req) { d, resp, err in   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                // The node names the ring itself: woken > 0 — somebody was actually rung here;
                // 0 — this store holds no subscription for the tag; -1 — its publisher is down.
                let woken = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any])?["woken"] as? Int ?? -1
                let carry = env == nil ? 0 : 1
                if code == 429 {
                    MontanaTrace.markFolded("wakepush_tx", "code=429 door=\(dh) carry=\(carry) to=\(String(conv.prefix(10)))", window: 30)
                    noteTooOften(doors[i], conv: conv)
                } else {
                    if code == 200 { noteAnswered(doors[i], conv: conv) }   // an answer ends the rest — the streak does not outlive it
                    knockOutcome(doors[i], code: code)                       // the first answer after a failed knock drains the queue
                    MontanaTrace.mark("wakepush_tx", "code=\(code) woken=\(woken) door=\(dh) carry=\(carry) to=\(String(conv.prefix(10)))" + (code < 0 ? " err=\(errWord(err))" : ""))
                }
                if code == 200, woken > 0 {
                    knockLock.lock()
                    knocked["\(conv):\(mid)"] = w
                    knocked = knocked.filter { $0.value &+ 2 > w }
                    knockLock.unlock()
                    completion?(200); return
                }
                // No ring here — walk on. The letter is already boxed at every door we pass,
                // and the receiver's read sweeps every store, so nothing is lost on the way.
                if i + 1 < doors.count { knock(i + 1) } else { completion?(code) }
            }.resume()
        }
        knock(0)
    }

    /// THE DOORBELL of the invite's owner (F-2): the first letter of an introduction rides the
    /// live channel, and this silent push wakes the sleeping owner so someone opens the
    /// channel. The device itself raises the banner when the letter lands. The node glues
    /// repeats by mid (48h), the client by minute window: the ring is cheap and does not spam.
    static let rdvRingMagic = "mt-rdv-ring"
    /// The FIRST-MEETING letter key: derived from the invite — exactly the two sides know it
    /// (the code's owner and its opener), the node is blind, the push targets one device.
    static func rdvLetterSecret(_ invite: Data) -> Data {
        var m = Data("mt-rdv-letter".utf8); m.append(0); m.append(invite)
        return Data(SHA256.hash(data: m))
    }
    private static var rdvKnocked: [String: UInt64] = [:]
    private static let rdvKnockLock = NSLock()
    /// `answered` hears the node's code of every ring that went (07.10): 200 is the letter safe in the box (the node's /wake), and
    /// the queue turns it into one checkmark (MontanaDeliveryEngine.noteNodeAck). A ring not made says nothing.
    static func wakeRdv(invite: Data, mid: String, text: String, ct: Data, conf: String, answered: ((Int) -> Void)? = nil) {
        guard ct.count == 1088 else { MontanaTrace.mark("rdv_ring_skip", mid: mid, "why=ct-size"); return }
        let ref = twinRef
        guard !ref.isEmpty else { MontanaTrace.mark("rdv_ring_skip", mid: mid, "why=no-addr"); return }
        guard agreesWithCanon() else { MontanaTrace.mark("rdv_ring_skip", mid: mid, "why=canon"); return }
        let inv64 = invite.base64urlNoPad
        let w = MTPipe.window()
        rdvKnockLock.lock()
        let dup = rdvKnocked[inv64 + ":" + mid] == w
        if !dup { rdvKnocked[inv64 + ":" + mid] = w; rdvKnocked = rdvKnocked.filter { $0.value &+ 2 > w } }
        rdvKnockLock.unlock()
        if dup { return }
        let cw = rdvConvW(invite, window: dayWindow())
        guard let url = URL(string: base("box") + "/wake") else { return }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // The ring is VISIBLE and CARRIES THE LETTER ITSELF (the author's word 22.08: a banner
        // without the letter is half a road; empty banners do not exist): an envelope of the
        // same build as the pipes', but under the card key — the extension opens it and shows
        // the classic banner (name, text, face). A long letter rides as a blob with the
        // reference in the envelope — the same mechanism as the pipes'. A repeated mid the
        // node itself turns silent (wake_seen).
        let secret = rdvLetterSecret(invite)
        let fire: (String) -> Void = { env in
            var req2 = req
            let body: [String: Any] = ["conv": cw, "from_id": mySubId(cw), "mid": mid, "env": env]
            req2.httpBody = try? JSONSerialization.data(withJSONObject: body)
            knockSession.dataTask(with: req2) { _, resp, _ in   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                MontanaTrace.mark("wakepush_rdv", "code=\(code) inv=\(String(inv64.prefix(8))) mid=\(String(mid.prefix(8)))")
                answered?(code)
            }.resume()
        }
        // The first-meeting envelope: [encapsulation 1088][mid\0 text\0 name\0 glyph\0 padding]
        // = 1536. The receiver begets the pipe and puts the letter into the chat FROM THE PUSH
        // ITSELF; the banner is the placement's result.
        let seal: (String) -> String? = { t in
            var body = ct
            body.append(Data(mid.utf8)); body.append(0)
            body.append(Data(t.utf8)); body.append(0)
            body.append(Data(E2E.myDisplayName().utf8)); body.append(0)
            body.append(Data(E2E.myFaceGlyph().utf8)); body.append(0)
            // The fifth field is the key confirmation. An old receiver reads four and never
            // sees it; a new one without it does not beget a pipe from a push: no body seal on this road.
            body.append(Data(conf.utf8)); body.append(0)
            guard body.count <= 1536 else { return nil }
            body.append(Data(count: 1536 - body.count))
            return MTPipe.sealBody(body, sharedSecret: secret)?.base64EncodedString()
        }
        if let env = seal(text) {
            fire(env)
        } else {
            Task {
                guard let linkText = await sealLongLetter(mid: mid, text: text),
                      let env = seal(linkText) else {
                    MontanaTrace.mark("wakepush_rdv", "long-seal FAIL inv=\(String(inv64.prefix(8)))"); return
                }
                fire(env)
            }
        }
    }

    /// Temporary TURN credentials from the node (TURN-REST, self-expiring): without a relay a
    /// cellular (CGNAT) call physically cannot assemble — the server version worked exactly so.
    /// THE RELAY PASS IS REMEMBERED. It lives six hours by construction, and a call that is
    /// born without it is born blind: no relay candidate, no reflexive address, and on a
    /// cellular network behind carrier NAT that is a call which can never connect. The pass
    /// used to live only in memory, so every app relaunch started bare (measured 29.08: the
    /// caller relaunched, the fetch timed out on a dead door, the call gathered host
    /// candidates alone and stood in ICE checking until the minute cut-off).
    private static let turnPassKey = "turnPass"
    /// THE PASS NAMES ITS OWN END (13.09): the relay's username IS the moment of expiry (TURN-REST,
    /// six hours from the node). A pass within ten minutes of it is not taken on a call — the
    /// in-memory copy used to be taken at any age, and the first call after a quiet day went to
    /// the relay with a dead pass: no relay candidate, no call behind carrier NAT.
    static func turnPassLive(_ t: (uris: [String], name: String, credential: String, stun: [String])) -> Bool {
        guard let exp = Double(t.name) else { return true }   // a pass without a moment is judged by nobody
        return exp - Date().timeIntervalSince1970 > 600
    }
    static func rememberedTurnPass() -> (uris: [String], name: String, credential: String, stun: [String])? {
        guard let d = MontanaKeychain.get(turnPassKey),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let u = o["u"] as? String, let c = o["c"] as? String,
              let uris = o["uris"] as? [String], !uris.isEmpty else { return nil }
        let t = (uris, u, c, (o["stun"] as? [String]) ?? [])
        return turnPassLive(t) ? t : nil
    }
    private static func rememberTurnPass(_ t: (uris: [String], name: String, credential: String, stun: [String])) {
        let o: [String: Any] = ["u": t.name, "c": t.credential, "uris": t.uris,
                                "stun": t.stun, "at": Date().timeIntervalSince1970]
        if let d = try? JSONSerialization.data(withJSONObject: o) { MontanaKeychain.set(turnPassKey, d) }
    }

    /// THE PASS RIDES THE WAKE (29.09): the node that wakes a phone for a call mints the relay pass into the same push --
    /// it holds the secret, and the phone it wakes needs the pass within the second. A phone whose remembered pass had died
    /// (six hours; the app lay thirteen) used to fetch one first, 3.4 s on flapping doors, and only then build its answer.
    /// Adopted before the ring is posted: the connection built under the ringtone finds it in hand.
    static func adoptTurnPass(_ o: [String: Any]) -> Bool {
        guard let u = o["username"] as? String, let c = o["credential"] as? String,
              let uris = o["uris"] as? [String], !uris.isEmpty else { return false }
        let t = (uris: uris, name: u, credential: c, stun: (o["stun"] as? [String]) ?? [])
        guard turnPassLive(t) else { return false }
        rememberTurnPass(t)
        MontanaCall.adoptTurnPass(t)
        return true
    }

    /// EVERY DOOR AT ONCE, the first answer wins. One chosen door was the whole defect: on a
    /// fresh launch no door is verified yet, so the choice degenerates into list order — and
    /// list order put a node that was switched off first. The pass fetch then spent its whole
    /// budget on a dead address while a living door stood beside it.
    static func fetchTurnCred() async -> (uris: [String], name: String, credential: String, stun: [String])? {
        let all = bases(for: "turn")
        guard !all.isEmpty else { return nil }
        return await withTaskGroup(of: (uris: [String], name: String, credential: String, stun: [String])?.self) { group in
            for b in all {
                group.addTask {
                    guard let url = URL(string: b + "/turn-cred") else { return nil }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.timeoutInterval = 6
                    req.httpBody = Data("{}".utf8)
                    guard let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                          (resp as? HTTPURLResponse)?.statusCode == 200,
                          let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let u = o["username"] as? String, let c = o["credential"] as? String,
                          let uris = o["uris"] as? [String], !uris.isEmpty else { return nil }
                    return (uris, u, c, (o["stun"] as? [String]) ?? [])
                }
            }
            for await r in group {
                if let r {
                    group.cancelAll()
                    rememberTurnPass(r)
                    return r
                }
            }
            return nil
        }
    }

    // ── media blobs through the node (sealed on the device, the node is blind) ──────────
    /// A chunk to the node with a retry: a part that missed the first time goes on the
    /// second or third — one part's failure does not drop the file.
    /// Idempotent by content address: re-sending a chunk already stored is harmless. A
    /// failure goes to the trace, never silently.
    static func putBlob(_ bid: String, data: Data, over: Bool = false,
                        cargo: String? = nil, last: Bool = false, assumeAbsent: Bool = false) async -> Bool {
        // A CHUNK ALREADY ON THE NODE IS NOT SENT AGAIN (08.09): the face letter to nine
        // correspondences and every retry of it re-uploaded the same 64 KB, twelve times a
        // minute, and a person's 221 KB photo crawled behind them at 94 kbps for nineteen
        // seconds. The name is the content; one small question first, the bytes only when the
        // node lacks them. A chunk walk (uploadChunks) has already asked for its whole batch.
        if !over, !assumeAbsent, let have = await blobsPresent([bid]), have.contains(bid) {
            MontanaTrace.markFolded("blob_put", "already on the node id=\(String(bid.prefix(8))) — not sent again", window: 30)
            return true
        }
        let t0 = Date()
        defer {
            let ms = max(1, Int(Date().timeIntervalSince(t0) * 1000))
            MontanaTrace.mark("blob_put", "bytes=\(data.count) ms=\(ms) kbps=\(data.count * 8 / ms)")
        }
        var body: [String: Any] = ["bid": bid, "data": data.base64EncodedString()]
        if over { body["over"] = true }   // re-depositing the rendezvous card: same bid, fresh term
        // Cargo marks: a random label and the last-chunk flag. No manifest, no size.
        if let cargo { body["cg"] = cargo; if last { body["last"] = true } }
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return false }
        // The refusal's cause IS NAMED. It used to be swallowed by `try?`, and the trace said
        // only «FAIL» — impossible to tell a node refusal from a dropped connection. Precedent
        // 20.08 16:09: the node answered 200 forty-one times and then saw NOTHING, while the
        // phone wrote three causeless «FAIL»s.
        var why = "?"
        for attempt in 0..<3 {
            if Task.isCancelled { why = "cancelled"; break }
            // The doors are read AT EVERY ATTEMPT, never once per chunk: a door that died between
            // two attempts is no longer first.
            let doors = bases(for: "blob").filter { !doorResting($0) }.map { ($0, $0 + "/blob-put") }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            guard !doors.isEmpty else { why = "no live door"; break }
            let (code, w) = await hedgedPut(doors, payload: payload, bytes: data.count, bid: bid)
            if code == 200 { return true }
            why = w
            if code == 429 { try? await Task.sleep(nanoseconds: 1_200_000_000); continue }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 600_000_000) }
        }
        if !Task.isCancelled { MontanaTrace.mark("blob_up", "FAIL id=\(String(bid.prefix(8))) — \(why)") }
        return false
    }

    /// ONE CHUNK, THE NEXT DOOR THE MOMENT THE FIRST ONE DIES (23.09). A chunk used to ride one URL,
    /// fixed when the request was built. Measured on T3 at 23:24:23Z under the subscription: the
    /// elected door could not be reached through that exit (dial_timeout ifs=tunnel), the signal
    /// lane declared it dead 3 s later and moved on, and the chunk kept waiting at it until the 45 s
    /// silence watchdog gave the photo up, with a living door beside it the whole time. Now the chunk
    /// goes to the next live door as soon as the first is declared dead by ANY road, or has not
    /// answered in half its own deadline. The first 200 wins and the rest are cancelled. A put is
    /// idempotent by its name, and a receiver asks every door at once, so the chunk found on a
    /// second node is the same chunk. A healthy slow link is never uploaded twice: it neither dies
    /// nor goes silent past half its deadline.
    private static func hedgedPut(_ doors: [(door: String, road: String)], payload: Data, bytes: Int, bid: String) async -> (Int, String) {
        let deadline = MTNodeWire.cargoTimeoutS(bytes: bytes)   // one deadline rule with the sheet (17.09)
        let patience = deadline / 2
        enum Step { case answer(String, Int, String); case tick }
        return await withTaskGroup(of: Step.self) { group -> (Int, String) in
            var next = 0, inFlight = 0
            var started: [String: Date] = [:]
            func launch() {
                guard next < doors.count else { return }
                let (door, road) = doors[next]; next += 1; inFlight += 1
                started[door] = Date()
                if next > 1 { MontanaTrace.mark("blob_up", "id=\(String(bid.prefix(8))) next door=\(URL(string: door)?.host ?? "-")") }
                group.addTask {
                    guard let url = URL(string: road) else { return .answer(door, -1, "bad door") }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.httpBody = payload
                    req.timeoutInterval = deadline
                    do {
                        let (_, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                        return .answer(door, code, "code \(code)")
                    } catch {
                        let cancelled = Task.isCancelled || (error as NSError).code == NSURLErrorCancelled
                        return .answer(door, cancelled ? -2 : -1, cancelled ? "cancelled" : error.localizedDescription)
                    }
                }
            }
            launch()
            group.addTask { try? await Task.sleep(nanoseconds: 1_000_000_000); return .tick }
            var last = (-1, "?")
            while let step = await group.next() {
                switch step {
                case .answer(let door, let code, let w):
                    inFlight -= 1
                    started[door] = nil
                    if code == 200 { doorSpoke(door); group.cancelAll(); return (200, "") }
                    if code == -2 { break }   // a lost race says nothing about the door
                    if code == -1 || code >= 500 { baseFailed(door, code: code) } else { doorSpoke(door) }
                    last = (code, w)
                    if code != 429 { launch() }   // the next door at once; a busy node is waited, not jumped
                case .tick:
                    if Task.isCancelled { group.cancelAll(); return (-2, "cancelled") }
                    // An in-flight door that died by any road's verdict, or overstayed half its
                    // deadline, calls the next one in. One extra door per second at most: never a storm.
                    let stale = started.contains { d, t in doorResting(d) || Date().timeIntervalSince(t) > patience }
                    if stale { launch() }
                    if inFlight > 0 { group.addTask { try? await Task.sleep(nanoseconds: 1_000_000_000); return .tick } }
                }
                if inFlight == 0 { group.cancelAll(); return last }
            }
            return last
        }
    }

    /// A door resting after its death verdict (the one rule, baseFailed). Read, never written, here.
    static func doorResting(_ b: String) -> Bool {
        baseLock.lock(); defer { baseLock.unlock() }
        return signalDoorDead[b].map { $0 > Date() } ?? false
    }

    /// «No answer» and «the node answered NO» are different things, and mixing them means being
    /// unable to tell a dropped connection from a dead letter. A break — wait and retry; a «NO»
    /// from a living node — the cargo will never exist again (removed by receipt, by term, or by
    /// the owner's hand). «BUSY» IS A THIRD ANSWER (21.09, the critic): a 429 or a 5xx is a
    /// living node that refuses THIS MOMENT, not a missing cargo and not a dead road.
    enum BlobAnswer { case found(Data); case gone; case busy; case unreachable }
    static func askBlob(_ bid: String) async -> BlobAnswer {
        // The doors are asked AT ONCE, and the first to answer wins. The queue was a bug: a
        // link tap lands in the first second after launch when no channel is up yet — «live
        // first» degenerated into list order, and the 24.08 measurement showed 9.7 seconds to
        // an open conversation, EIGHT of them waiting on a dead address beside a living door.
        // Asked at once, the dead cost nothing: their silence delays nobody. «No cargo» is
        // KNOWLEDGE only when EVERY door answered and every answer was «no»: the cargo lies on
        // one door, and a «no» from a door that never held it says nothing while the holder is
        // busy or silent.
        let all = bases(for: "blob")
        guard !all.isEmpty else { return .unreachable }
        let began = Date()
        return await withTaskGroup(of: BlobAnswer.self) { group -> BlobAnswer in
            for b in all {
                group.addTask {
                    guard let url = URL(string: b + "/blob-get") else { return .unreachable }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.timeoutInterval = 8
                    req.httpBody = try? JSONSerialization.data(withJSONObject: ["bid": bid])
                    let host = URL(string: b)?.host ?? "-"
                    let d: Data, code: Int
                    do {
                        let (dd, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                        guard let c = (resp as? HTTPURLResponse)?.statusCode else { return .unreachable }
                        d = dd; code = c
                    } catch {
                        // A LOST RACE IS NOT A DEATH (17.09): the first door to answer cancels the rest, and
                        // a cancelled question says nothing about the door it was asked. It used to be
                        // written «unreachable» and to bury the election five times per fetch.
                        if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled { return .unreachable }
                        MontanaTrace.mark("blob_get", "unreachable at=\(host)")
                        baseFailed(b); return .unreachable
                    }
                    doorSpoke(b)
                    if code == 404 { MontanaTrace.mark("blob_get", "gone at=\(host)"); return .gone }
                    guard code == 200,
                          let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          let b64 = obj["data"] as? String,
                          let data = Data(base64Encoded: b64) else {
                        MontanaTrace.mark("blob_get", "code=\(code) at=\(host)")
                        return (code == 429 || (500...599).contains(code)) ? .busy : .unreachable
                    }
                    MontanaTrace.mark("blob_get", "found at=\(host) ms=\(Int(Date().timeIntervalSince(began) * 1000))")
                    return .found(data)
                }
            }
            var gone = 0, busy = 0
            for await answer in group {
                if case .found = answer { group.cancelAll(); return answer }
                if case .gone = answer { gone += 1 }
                if case .busy = answer { busy += 1 }
            }
            if gone == all.count { return .gone }
            return busy != 0 ? .busy : .unreachable
        }
    }
    static func getBlob(_ bid: String) async -> Data? {
        if case .found(let d) = await askBlob(bid) { return d }
        return nil
    }

    /// All manifest chunks — to the node, in a window of three parallel parts: a gigabyte
    /// (2048 chunks) leaves in minutes, a failed chunk retries without dropping the file.
    // Stage 8.3: the caller flips this when the system grace window expires — the loop stops
    // launching interactive uploads and hands the remaining chunks to the background session.
    static let handOffFlag = MTAtomicFlagSet()

    static func uploadChunks(_ ref: [String: Any], letter: String? = nil,
                             progress: (@Sendable (Int, Int) -> Void)? = nil) async -> Bool {
        let bids = (ref["chunks"] as? [[String: Any]] ?? []).compactMap { $0["bid"] as? String }
        // TWO CONTENT-FREE CARGO MARKS (9-D.5). The random label is shared by chunks of ONE
        // media and tied to nothing; the «last» flag closes the cargo. By them the node tells
        // abandoned-midway from awaiting-its-receiver, knowing nothing of the contents: no
        // manifest, no size, no names. An unclosed cargo it removes in an hour, not a week.
        // The mark is a FUNCTION of the manifest, not a fresh random: a resumed upload
        // continues the SAME node-side group. A random mark split every resume into a new
        // group and left the first one unclosed — the node swept it as abandoned in an hour,
        // eating chunks from under a letter that was legitimately waiting. Derived from the
        // chunk names only (which the node sees anyway) — zero new knowledge.
        let cargoMark = String(MontanaQueueKeys.sha256(Data(bids.joined().utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(32))
        let lastBid = bids.last
        guard !bids.isEmpty else { MontanaTrace.mark("blob_up", "FAIL empty-manifest"); return false }
        let total = bids.count
        // Any file of any size rides (the author's rule 23.08). The gigabyte crash was a
        // MEMORY bug — hundreds of bodies alive at once — closed by the per-chunk pools
        // below, not by refusing mass.
        // ONE failed chunk no longer kills the whole upload. The first refusal used to cancel
        // the group whole: 41 chunks of 71 already lay on the node, the letter never queued,
        // and the sender's bubble stood as sent — a phantom send (precedent 20.08 16:09).
        // The rounds repeat ONLY what did not pass; what the node holds is not re-uploaded.
        // WE ASK THE NODE WHAT IT ALREADY HAS. The seal is now deterministic per letter: the same
        // file under the same letter name yields THE SAME chunk names. So a retry must
        // continue, not start over — else all the determinism's savings vanish on the wire.
        // Measured 20.08: a retry re-uploaded all 71 chunks though most already lay on the node.
        var known = Set<String>()
        // A cargo of a couple of chunks is put at once (18.09): the put is idempotent by name, and
        // the question would cost the same round trip the answer could save.
        if bids.count > 2, let have = await blobsPresent(bids), !have.isEmpty {
            known = have
            MontanaLog.event("upload RESUME chunks already on the node=\(have.count)/\(total) — uploading only the rest")
        }
        for b in known { MontanaBlobStore.drop([b]) }   // these chunks' crate is no longer needed on the phone
        var pending = bids.filter { !known.contains($0) }
        var uploaded = known.count
        progress?(uploaded, total)
        if pending.isEmpty { MontanaTrace.mark("blob_up", "everything already on the node — nothing to upload"); return true }
        for round in 0..<4 {
            if pending.isEmpty { break }
            // A watchdog that gave the upload up cancels it: no further round, no «FAIL cancelled» lines.
            if Task.isCancelled { return false }
            // Stage 8.3: the grace window expired — stop the interactive rounds, hand the
            // remaining chunks to the system session and report a handoff (not a failure).
            if let l = letter, Self.handOffFlag.check(l) {
                // Each body is ~5.5 MB transient (base64 + JSON); without a per-chunk pool a
                // burst of hundreds held them all at once — NSMallocException (23.08 00:09).
                for bid in pending {
                    autoreleasepool {
                        if let sealed = MontanaBlobStore.get(bid) { MontanaBlobUpload.shared.enqueue(bid: bid, sealed: sealed) }
                    }
                }
                MontanaTrace.mark("blob_up", "HANDOFF n=\(pending.count) of \(total) — the system delivers")
                return true
            }
            let batch = pending
            let base = uploaded
            let results = await withTaskGroup(of: (String, Bool).self) { group -> [(String, Bool)] in
                var next = 0
                func launch(_ i: Int) {
                    let bid = batch[i]
                    // Stage 8.3: the expiry flag is checked PER LAUNCH, not only per round — a
                    // round spans hundreds of chunks, and the system freezes the process seconds
                    // after expiry: the first run died mid-burst with no handoff at 21:50:29.
                    if let l = letter, Self.handOffFlag.check(l) {
                        group.addTask { (bid, false) }   // not launched — the leftover goes to the system session below
                        return
                    }
                    group.addTask {
                        guard let sealed = MontanaBlobStore.get(bid) else {
                            // The crate is not on disk — it is removed ONLY after a successful
                            // hand-over to the node. A missing crate is not a missing cargo.
                            MontanaTrace.mark("blob_up", "no crate id=\(String(bid.prefix(8))) — counting as handed over")
                            return (bid, true)
                        }
                        let ok = await putBlob(bid, data: sealed, cargo: cargoMark, last: bid == lastBid, assumeAbsent: true)
                        if ok {
                            MontanaTrace.mark("blob_up", "id=\(String(bid.prefix(8))) bytes=\(sealed.count)")
                            MontanaBlobStore.drop([bid])
                        }
                        return (bid, ok)
                    }
                }
                for _ in 0..<min(3, batch.count) { launch(next); next += 1 }
                var out: [(String, Bool)] = []
                var okLocal = 0
                for await r in group {
                    if r.1 { okLocal += 1; progress?(base + okLocal, total) }   // honest NETWORK progress
                    out.append(r)
                    if next < batch.count { launch(next); next += 1 }
                }
                return out
            }
            uploaded += results.filter { $0.1 }.count
            pending = results.filter { !$0.1 }.map { $0.0 }
            // The flag may have risen mid-round: everything not confirmed uploaded goes to the
            // system session NOW — the process has seconds to live.
            if let l = letter, Self.handOffFlag.check(l), !pending.isEmpty {
                for bid in pending {
                    autoreleasepool {
                        if let sealed = MontanaBlobStore.get(bid) { MontanaBlobUpload.shared.enqueue(bid: bid, sealed: sealed) }
                    }
                }
                MontanaTrace.mark("blob_up", "HANDOFF n=\(pending.count) of \(total) — the system delivers")
                return true
            }
            if Task.isCancelled { return false }
            if !pending.isEmpty, round < 3 {
                MontanaTrace.mark("blob_up", "round \(round + 1): unpassed \(pending.count) of \(total) — retrying")
                try? await Task.sleep(nanoseconds: UInt64(1_500_000_000) << UInt64(round))
            }
        }
        guard pending.isEmpty else {
            MontanaTrace.mark("blob_up", "FAIL unpassed \(pending.count) of \(total) after four rounds")
            return false
        }
        return true
    }

    // ── THE LEDGER OF CHUNKS LYING ON THE NODE ───────────────────────────────
    // A chunk is named by its content fingerprint and is therefore SHARED: one avatar rides
    // to twenty addressees as ONE chunk. Only the one who knows no living letter references
    // it may remove it — and that is the SENDER, not the node: to the node an unclaimed chunk
    // is indistinguishable from one awaiting a sleeping receiver. The ledger: chunk -> the letters carrying it.
    private static let ledgerKey = "nodeChunkLedger"
    /// The node box keeps a letter's row this long (BOX_TTL of the node store, 24 h on both nodes): a
    /// reference taken from the box is at most this old, and the cargo it names lives at least as long.
    static let boxTerm: TimeInterval = 24 * 3600
    private static let ledgerLock = NSLock()

    private static func loadLedger() -> [String: [String]] {
        guard let s = MontanaLocalVault.getString(ledgerKey), let d = s.data(using: .utf8),
              let m = try? JSONSerialization.jsonObject(with: d) as? [String: [String]] else { return [:] }
        return m
    }
    private static func saveLedger(_ m: [String: [String]]) {
        if let d = try? JSONSerialization.data(withJSONObject: m),
           let s = String(data: d, encoding: .utf8) { _ = MontanaLocalVault.setString(ledgerKey, s) }
    }

    /// A letter carries these chunks — record it, to know when to remove them.
    static func noteChunks(letter: String, bids: [String]) {
        guard !letter.isEmpty, !bids.isEmpty else { return }
        ledgerLock.lock(); defer { ledgerLock.unlock() }
        var m = loadLedger()
        for b in bids where !(m[b]?.contains(letter) ?? false) { m[b, default: []].append(letter) }
        saveLedger(m)
    }

    /// Which chunks this letter rides — reverse lookup for the sender-side cargo check.
    static func bidsOf(letter: String) -> [String] {
        guard !letter.isEmpty else { return [] }
        ledgerLock.lock(); defer { ledgerLock.unlock() }
        return loadLedger().compactMap { b, letters in letters.contains(letter) ? b : nil }
    }

    /// The letter has ended — delivered or failed. Returns the chunks referenced by NO letter
    /// any more: only those may leave the node.
    static func releaseLetter(_ letter: String) -> [String] {
        guard !letter.isEmpty else { return [] }
        ledgerLock.lock(); defer { ledgerLock.unlock() }
        var m = loadLedger()
        var freed: [String] = []
        for (b, letters) in m where letters.contains(letter) {
            let rest = letters.filter { $0 != letter }
            if rest.isEmpty { freed.append(b); m[b] = nil } else { m[b] = rest }
        }
        if !freed.isEmpty || !m.isEmpty { saveLedger(m) }
        return freed
    }

    /// Chunks of letters NOT IN THE QUEUE are orphans: the letter either ended (its ledger is
    /// already empty) or died with the process BEFORE queueing. The second left cargo on the
    /// store: measured 20.08 — a broken upload added 19 chunks and 9 MB with nobody to remove
    /// them. Called ONLY on cold start: at that instant no uploads are in flight by
    /// construction, so «not in the queue» means exactly «will never ride». At any other time
    /// a lawful window exists between the ledger write and the queueing, and an orphan cannot
    /// be told from a live send.
    /// «WILL NEVER RIDE» IS NOT «NOBODY WILL COME FOR IT» (23.09, the critic). A letter leaves the
    /// queue without a receipt — a face or a name retired after its hour, a silent word settled on the
    /// node's 200 — while its reference still lies in the receiver's node box for the box's own term.
    /// The sweep took the cargo at the next cold start and the reference outlived it: T1 retired face
    /// letters to a phone that was off for 49 hours (21.09 22:20 and 23:25 UTC), swept their chunks at
    /// the cold starts of 22.09 from 01:19, and the phone came back at 13:54 to ask for them 57 times
    /// each. An orphan's chunks now leave the node only once the box term has passed since the first
    /// sweep that found its letter outside the queue: the reference and its cargo share one life.
    private static let orphanSinceKey = "nodeChunkOrphanSince"
    static func sweepOrphanChunks(aliveLetters: Set<String>) async {
        ledgerLock.lock()   // LOCK-OK: read-modify-write of the ledger and its orphan marks, one record under one lock
        var m = loadLedger()
        let now = Date().timeIntervalSince1970
        var since = MontanaLocalVault.getString(orphanSinceKey)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String: Double].self, from: $0) } ?? [:]
        var outside = Set<String>()
        for (_, letters) in m { for l in letters where !aliveLetters.contains(l) { outside.insert(l) } }
        // A letter back in the queue, or gone from the ledger, sheds its mark; a new orphan takes one now.
        since = since.filter { outside.contains($0.key) }
        for l in outside where since[l] == nil { since[l] = now }
        let dead = outside.filter { now - (since[$0] ?? now) >= boxTerm }
        var freed: [String] = []
        if !dead.isEmpty {
            for (b, letters) in m {
                let rest = letters.filter { !dead.contains($0) }
                if rest.isEmpty { freed.append(b); m[b] = nil } else { m[b] = rest }
            }
            saveLedger(m)
            for l in dead { since[l] = nil }
        }
        if let d = try? JSONEncoder().encode(since), let s = String(data: d, encoding: .utf8) {
            _ = MontanaLocalVault.setString(orphanSinceKey, s)
        }
        ledgerLock.unlock()
        let kept = outside.count - dead.count
        if kept > 0 {
            MontanaTrace.mark("blob_orphans", "kept letters=\(kept) — outside the queue less than the box term, a receiver may still take their reference")
        }
        guard !freed.isEmpty else { return }
        MontanaTrace.mark("blob_orphans", "dead letters=\(dead.count) chunks to remove=\(freed.count)")
        MontanaLog.event("NODE orphans: letters=\(dead.count) chunks=\(freed.count) — removing from the node")
        await dropBids(freed)
    }

    /// Which of the named chunks a store already holds. «Don't know» (network, an old node)
    /// reads as «assume none»: a spare upload costs more but is honester than a skipped chunk.
    /// THE QUESTION COSTS ONE ROUND TRIP, NEVER A WALK (18.09, the author's word: everything
    /// instant). It used to ask every store one after another with a twenty-second deadline each,
    /// and a fresh cargo — which no store holds yet — walked the list until a dead door hung it:
    /// measured 18.09 14:04 on T1, a 71 KB voice sealed in 66 ms, put in 36 ms, and 14.6 s of
    /// silence between the two. Now the stores are asked AT ONCE under the one post deadline.
    /// `everyStore` is for a verdict of loss (1638: the cargo lies on the one store the upload
    /// reached, so every proven store must answer — one silent store makes the question
    /// unanswerable, «don't know», never «gone»); an upload's savings ask only the store the
    /// bytes are going to.
    static func blobsPresent(_ bids: [String], everyStore: Bool = false) async -> Set<String>? {
        guard !bids.isEmpty else { return nil }
        let doors = everyStore ? electedFirst(orderedBases(for: "blob")) : [base("blob")].filter { !$0.isEmpty }
        guard !doors.isEmpty else { return nil }
        let t0 = Date()
        let asked = Set(bids)
        let answers = await withTaskGroup(of: Set<String>?.self) { group -> [Set<String>?] in
            for b in doors { group.addTask { await Self.askHave(b, bids: bids, asked: asked) } }
            var out: [Set<String>?] = []
            for await r in group { out.append(r) }
            return out
        }
        var have = Set<String>(); var silent = 0
        for a in answers { if let a { have.formUnion(a) } else { silent += 1 } }
        MontanaTrace.markFolded("blob_have", "doors=\(doors.count) silent=\(silent) have=\(have.count)/\(bids.count) ms=\(Int(Date().timeIntervalSince(t0) * 1000))", window: 30)
        if have.count == bids.count { return have }
        return silent > 0 ? nil : have
    }
    private static func askHave(_ b: String, bids: [String], asked: Set<String>) async -> Set<String>? {
        // The door was chosen by the blob capability (P-98): a store that never claimed it is not asked.
        guard orderedBases(for: "blob").contains(b) || base("blob") == b,
              let url = URL(string: b + "/blob-have") else { return nil }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = MTNodeWire.postTimeoutS   // the one deadline of a post to a node (13.09)
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["bids": bids])
        guard let (d, r) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
              (r as? HTTPURLResponse)?.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let h = o["have"] as? [String] else { return nil }
        // THE ANSWER IS MET WITH THE QUESTION (18.09). A store that names chunks nobody asked
        // about — a stale index, a wrong build, a lying front — used to cancel the whole upload:
        // «everything already on the node», one checkmark, and the receiver could never assemble
        // the file (the /blob-have precedent of 08.09, seen from the phone's side). Only the
        // chunks we asked about count; the rest is named in the diary and dropped.
        let foreign = h.filter { !asked.contains($0) }
        if !foreign.isEmpty {
            MontanaTrace.mark("blob_have_foreign", "door=\(URL(string: b)?.host ?? b) named=\(foreign.count) asked=\(bids.count) — ignored")
        }
        return Set(h.filter { asked.contains($0) })
    }

    /// Remove the named chunks from the node. Idempotent: a missing chunk is not an error.
    /// REMOVAL DOES NOT GIVE UP ON THE FIRST TRY. One network hiccup used to leave chunks
    /// lying for a week: the trace honestly wrote «the node's term will sweep it», and the
    /// hand dropped. Measured 24.08: 46 chunks of a delivered letter stayed exactly so — the
    /// request never landed and nobody tried again. The unremoved now lives as a list on disk
    /// and is re-sent at every good occasion, exactly like queued letters: deliver, not blush.
    private static let unsentDropKey = "wakeUnsentDrops"

    private static func rememberDrops(_ bids: [String]) {
        var a = UserDefaults.standard.stringArray(forKey: unsentDropKey) ?? []
        a.append(contentsOf: bids.filter { !a.contains($0) })
        if a.count > 8192 { a.removeFirst(a.count - 8192) }   // the cap: the store is another's, the memory is ours
        UserDefaults.standard.set(a, forKey: unsentDropKey)
    }

    @discardableResult
    static func dropBids(_ bids: [String]) async -> Bool {
        guard !bids.isEmpty else { return true }
        // THE DROP GOES TO EVERY STORE (1638): the chunks lie on the one store the upload reached,
        // and a drop sent to another store was a free no-op that left them for the seven-day term.
        let doors = electedFirst(orderedBases(for: "blob"))   // every store that names the capability, the elected first
        var landed = false, dropped = 0
        for b in doors {
            guard let url = URL(string: b + "/blob-drop") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.timeoutInterval = 15
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["bids": bids])
            if let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                landed = true; dropped += o["dropped"] as? Int ?? 0
            }
        }
        if landed {
            MontanaTrace.mark("blob_drop", "removed n=\(dropped) of \(bids.count) doors=\(doors.count)")
            return true
        }
        rememberDrops(bids)
        MontanaTrace.mark("blob_drop", "did not land n=\(bids.count) — deferred, re-sending later")
        return false
    }

    /// Re-sending deferred removals: called on every return to the person (AppDelegate.appBecameActive, 24.09 — it stood
    /// in a delegate method UIKit never calls, and the deferred removals were never sent again).
    static func flushPendingDrops() async {
        let pending = UserDefaults.standard.stringArray(forKey: unsentDropKey) ?? []
        guard !pending.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: unsentDropKey)
        for chunk in stride(from: 0, to: pending.count, by: 512) {
            let part = Array(pending[chunk..<min(chunk + 512, pending.count)])
            _ = await dropBids(part)   // failed again — dropBids itself puts it back
        }
    }

    // ── THE NODE BOX (7.2c): the letter waits for its receiver, the push is only a doorbell ──
    // APNs keeps ONE last push for a powered-off device and discards the rest. The letter
    // does not die of that: the node stores the sealed envelope (E2E, the node is blind, term
    // 7 days) and yields it to the receiver via /fetch. The node does not hand a letter to
    // its own sender — the filter by presented sender tags, the same principle as /wake.

    private static func parseLetterFields(_ plain: Data) -> [String] {
        var fields: [String] = []; var rest = plain[plain.startIndex...]
        while fields.count < 7 {
            guard let z = rest.firstIndex(of: 0) else {
                fields.append(String(data: rest, encoding: .utf8) ?? ""); break
            }
            fields.append(String(data: rest[rest.startIndex..<z], encoding: .utf8) ?? "")
            rest = rest[rest.index(after: z)...]
        }
        while fields.count < 7 { fields.append("") }
        return fields
    }

    private static var boxLast: TimeInterval = 0
    private static var boxKickBooked = false   // one pickup booked for the end of the gate
    /// When the last box pickup FINISHED — the red mark's evidence (15.46): «no receipt» means
    /// something only after the box has been asked.
    static var lastBoxFetchAt: TimeInterval = 0
    private static var boxBusy = false
    private static var boxTrail = false
    private static var boxStartedAt: TimeInterval = 0
    private static var boxGen = 0
    private static let boxLock = NSLock()
    /// A WAKE READS THE BOX WITHIN ITS OWN LIFE (21.09, the critic): the read is awaited, bounded
    /// by the wake's seconds, and the wake's completion follows it — a read begun in a previous
    /// life (the tablet at 22:23: nine seconds awake, the fetch of 22:06 «finishing») counts for
    /// nothing. The dedup of fetchBoxKick is bypassed on purpose: a wake is a fact, not a repeat.
    static func fetchBoxOnWake(seconds: Double = 8) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await fetchBox() }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
            await group.next()
            group.cancelAll()
        }
    }
    /// A «YOU HAVE A LETTER» IS NEVER THROWN AWAY, ONLY DEFERRED (23.09, the author's word). The gate folds a
    /// burst of activation calls into one pickup, and it used to DROP every call inside the gate: the store's
    /// hint came 2 s after a pickup that found the box empty (the letters were boxed in between), and six
    /// letters lay in the box 4 min 59 s while the Mac sat in the chat, the diary saying «box hint — fetching»
    /// six times with no fetch (23.09 14:15:53-14:20:52). A call inside the gate books ONE pickup at the gate's
    /// end. Returns the seconds until the pickup: 0 when it runs now.
    @discardableResult
    static func fetchBoxKick() -> TimeInterval {
        boxLock.lock()
        let now = Date().timeIntervalSince1970
        let wait = boxLast + 8 - now   // activation calls from several places in a row — one pickup
        if wait <= 0 {
            boxLast = now
            boxLock.unlock()
            Task { await fetchBox() }
            return 0
        }
        let booked = boxKickBooked
        boxKickBooked = true
        boxLock.unlock()
        if !booked {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + wait) {
                boxLock.lock(); boxKickBooked = false; boxLast = Date().timeIntervalSince1970; boxLock.unlock()
                Task { await fetchBox() }
            }
        }
        return wait
    }
    /// THE STORE'S HINT IS FETCHED NOW (the author's word 29.09: «everything must be instant in the game»): the node's
    /// «box» on the held lane is its own word that a letter of mine lies in the box, and booked behind the gate above it
    /// cost a chess move up to eight seconds («box hint -- deferred 7s», T1 13:44:06) while a silent push carried the
    /// rest eight to fourteen seconds late. The hint refreshes the gate, so the activation calls that follow still fold
    /// onto this pickup; one pickup in flight is fetchBox's own rule (busy: a trail, repeated once).
    static func fetchBoxNow() {
        boxLock.lock()
        boxLast = Date().timeIntervalSince1970
        boxLock.unlock()
        Task { await fetchBox() }
    }

    /// Box rows that stayed sealed after the day-deep walk — per process, so a fetch every
    /// minute does not walk the same dead row a thousand minutes deep again.
    private static var sealedRows = Set<String>()
    static func fetchBox() async {
        // ONE pickup in flight: parallel ones (activation + hatching) staged a storm of 34
        // requests a second and split the letters between themselves (precedent 02:46:15). A
        // second call leaves a trail — and the pickup repeats once when the first finishes.
        boxLock.lock()
        let nowT = Date().timeIntervalSince1970
        if boxBusy {
            // A READ OLDER THAN A WAKE'S LIFE IS STALE (21.09): a pickup frozen with the process kept
            // «busy» across the sleep, and the next wake left only a trail that never ran before the
            // process slept again. A stale read is abandoned — its late tail no longer speaks for
            // the box — and a fresh one starts now.
            if nowT - boxStartedAt < 25 { boxTrail = true; boxLock.unlock(); return }
            boxGen += 1
            MontanaTrace.mark("box_fetch", "stale read of \(Int(nowT - boxStartedAt))s abandoned — a fresh one starts")
        }
        boxBusy = true; boxStartedAt = nowT
        let myGen = boxGen
        boxLock.unlock()
        defer {
            boxLock.lock()
            var again = false
            if boxGen == myGen {
                boxBusy = false
                again = boxTrail; boxTrail = false
            }
            boxLock.unlock()
            if again { Task { await fetchBox() } }
        }
        let ref = twinRef
        guard !ref.isEmpty, agreesWithCanon() else { return }
        // A store nobody proved holds no letters, and the walk over four dead doors on every
        // drain wrote ~20 lines a minute for nothing (measured 03.09 22:12). A store that proves
        // itself is walked again.
        guard !doorsHolding("box").isEmpty else {
            MontanaTrace.markFolded("box_fetch", "no proven box — the walk waits for a store that answers", window: 300)
            return
        }
        // Tags across the box's term (7 days) plus a day ahead — for the sender's skewed clock.
        var pipes: [String: Data] = [:]
        for conv in MTPipeBook.all() {   // a blocked person's letters are read too — and buried below, not left to wait
            if let secret = MTPipeBook.secret(for: conv) { pipes[conv] = secret }
        }
        for (name, secret) in MTKeeping.listening() { pipes[name] = secret }   // the pipes of the slots this phone keeps (MTKeeping)
        let ear = BoxEar(invites: MontanaCard.outstandingInvites(), pipes: pipes, owner: ref)
        guard !ear.subs.isEmpty else { MontanaTrace.mark("box_fetch", "subs=0 — the book/invites are empty (vault busy?)"); return }
        MontanaTrace.mark("box_fetch", "subs=\(ear.subs.count) invites=\(ear.rdvLabels.count / 10) pipes=\(ear.chatOf.count / 10)")
        let stashed = await pickup(ear, buries: { chat, mid in
            // A BLOCKED PERSON'S LETTER IS BURIED HERE, NOT LEFT TO WAIT (the author's
            // question 15.09: after an unblock the letters of the block arrived — the
            // reference delivers them never). The tombstone the feed already keeps for
            // «deleted for everyone» takes the letter's name, and the node is told to
            // drop it like a placed one; a later resend meets the tombstone.
            guard ChatStore.refusesNow(chat) else { return false }
            let sid = "mid:" + mid
            await MainActor.run { ChatStore.live?.deletedMids.insert(sid) }
            MontanaTrace.markFolded("rx_blocked", "box buried peer=\(String(chat.prefix(10)))", window: 60, key: "box:" + chat)
            return true
        }, keep: { row in restash(row); return true })
        MontanaTrace.mark("box_fetch", "letters=\(stashed)")
        lastBoxFetchAt = Date().timeIntervalSince1970
        // DELIVERY IS CONFIRMED, NOT ASSUMED: the node removes a letter only on the placement
        // confirmation (sent page by page above). Destructive yield used to destroy a letter
        // on any unsealing failure — silently and forever (precedent 24.08, two runs).
        if stashed > 0 { await MainActor.run { drainInbox() } }
        // THE PERSONS ON THE SHELF HEAR THE BOX TOO (07.10, MTShelfPost): a pickup of the person seated is the moment the phone
        // also reads for every person waiting on its shelf -- one road, their own labels, their own keys.
        MTShelfPost.soon()
        MTSeats.landShelf()   // and the person seated takes what the shelf received for them in the instant of a move
    }

    /// THE LABELS ONE PERSON LISTENS AT (07.10, MTShelfPost): the person seated now, or a person on this phone's shelf -- one
    /// recipe for both, so the phone hears every person it holds the same way. Tags across the box's term (7 days) plus a day
    /// ahead, for the sender's skewed clock.
    struct BoxEar {
        var subs: [String] = [], sids: [String] = []
        var secretOf: [String: Data] = [:], invOf: [String: String] = [:], chatOf: [String: String] = [:]
        var rdvLabels = Set<String>()
        init(invites: [Data], pipes: [String: Data], owner: String) {   // owner: the person's own reference (P-118.1)
            let w0 = MontanaWakePush.dayWindow()
            for inv in invites {
                let sec = MontanaWakePush.rdvLetterSecret(inv)
                for w in (w0 - 8)...(w0 + 1) {
                    let cw = MontanaWakePush.rdvConvW(inv, window: w)
                    rdvLabels.insert(cw); secretOf[cw] = sec; invOf[cw] = inv.base64urlNoPad
                    subs.append(cw); sids.append(MontanaWakePush.subId(cw, ref: owner))
                }
            }
            for (conv, secret) in pipes {
                for w in (w0 - 8)...(w0 + 1) {
                    let cw = MontanaWakePush.convW(secret, window: w)
                    secretOf[cw] = secret; chatOf[cw] = conv
                    subs.append(cw); sids.append(MontanaWakePush.subId(cw, ref: owner))
                }
            }
        }
    }

    /// THE ONE PICKUP OF THE BOX (07.10, MTShelfPost): one person's labels go to every store page by page, every row opens under
    /// its label's secret and becomes the inbox row the landing reads -- the person seated now (restash) and a person on the
    /// shelf (MTSeats.fileShelf) alike. The keep closure says the row is in hand: only a row in hand is confirmed to the node,
    /// which then removes it. The buries closure takes a refused person's letter before it is kept. The count of rows kept.
    static func pickup(_ ear: BoxEar, buries: ((String, String) async -> Bool)?, keep: ([String: String]) -> Bool) async -> Int {
        let subs = ear.subs, sids = ear.sids, secretOf = ear.secretOf
        let rdvLabels = ear.rdvLabels, invOf = ear.invOf, chatOf = ear.chatOf
        var stashed = 0
        var confirmed: [String] = []   // stored letters — confirmed to the node, it removes them (the box no longer erases on yield)
        // A chunk of 128 pairs — as in registration: 512 labels ≈ 69KB exceeded the node's
        // 64KiB body limit — the node answered 413 and only the tail arrived (precedent
        // labels=2, 22.08: 204 pipes -> 2050 labels -> 16 chunk receipts never collected).
        for start in stride(from: 0, to: subs.count, by: 128) {
            let end = min(start + 128, subs.count)
            for _ in 0..<4 {   // a page is 128 letters; a full page means «there is more»
                // The page walks the DOORS: one dead door must not starve the box for minutes
                // (measured 26.08 19:04-19:07: ~40 refusals against one broken base while the
                // letter waited on the node; door.montana.quest was alive the whole time).
                // THE READ SWEEPS EVERY STORE. Stores are per-node and never talk to each
                // other: a letter lies on the ONE node whose door answered its wake.
                var code = -1
                var letters: [[String: Any]] = []
                var seenMid = Set<String>()
                var anyDoor = false
                // THE DOORS ARE ASKED AT ONCE (17.09): the walk went door by door, five seconds each,
                // and two doors dead on this network cost every fetch ten seconds (T2 21:52:07 to
                // 21:52:11) before the living one was asked. One deadline for all; a door resting
                // after two silences is not asked while it rests, unless no door is left.
                let page = try? JSONSerialization.data(withJSONObject:
                    ["subs": Array(subs[start..<end]), "sids": Array(sids[start..<end])])
                let doors = bases(for: "box")
                let awake = doors.filter { doorAlive($0) }
                typealias DoorAnswer = (door: String, code: Int, letters: [[String: Any]]?)
                let answers = await withTaskGroup(of: DoorAnswer.self, returning: [DoorAnswer].self) { group in
                    for b in (awake.isEmpty ? doors : awake) {
                        group.addTask {
                            guard let u = URL(string: b + "/fetch") else { return (b, -1, nil) }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
                            var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), E2E envelope — the node is blind
                            req.timeoutInterval = 5   // hatch delay waits for this round — it must be short
                            req.setValue("application/json", forHTTPHeaderField: "content-type")
                            req.httpBody = page
                            var c = -1
                            var ls: [[String: Any]]? = nil
                            if let (d, resp) = try? await URLSession.shared.data(for: req) {   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                                c = (resp as? HTTPURLResponse)?.statusCode ?? -1
                                if c == 200, let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                                    ls = o["letters"] as? [[String: Any]]
                                }
                            }
                            return (b, c, ls)
                        }
                    }
                    var out: [DoorAnswer] = []
                    for await a in group { out.append(a) }
                    return out
                }
                for a in answers {
                    guard let ls = a.letters else {
                        code = a.code
                        baseFailed(a.door, code: a.code)
                        MontanaTrace.mark("box_fetch", "door refused code=\(a.code) at=\(URL(string: a.door)?.host ?? a.door)")
                        continue
                    }
                    doorSpoke(a.door)
                    anyDoor = true
                    for l in ls where seenMid.insert(l["m"] as? String ?? UUID().uuidString).inserted {
                        letters.append(l)
                    }
                }
                guard anyDoor else {
                    // Every door refused this page: -1 = the network died (offline moment) —
                    // ordinary life, the next round fetches; 4xx/5xx = the node refused —
                    // a real finding (413 was invisible once and cost receipts a half hour).
                    MontanaTrace.mark("box_fetch", "chunk refused code=\(code)")
                    break
                }
                for l in letters {
                    let lm = String((l["m"] as? String ?? "").prefix(8))
                    guard let cw = l["c"] as? String, let e = l["e"] as? String,
                          let sealed = Data(base64Encoded: e) else {
                        MontanaTrace.mark("box_skip", "broken yield row mid=\(lm)"); continue
                    }
                    guard let secret = secretOf[cw] else {
                        // The refusal is NAMED (the rule: every refusal is named): this
                        // continue used to be mute, and the letter vanished traceless —
                        // diagnosis was impossible (24.08).
                        MontanaTrace.mark("box_skip", "no secret for tag \(String(cw.prefix(10))) mid=\(lm)"); continue
                    }
                    // The envelope is sealed with the SEND minute window: the node names the
                    // receive moment (send and receive share a minute), unsealing walks windows around it.
                    // The node names the minute it TOOK the letter; the seal wears the minute it was
                    // MADE — the opener walks back a day (16.09: six letters, 26 fetches each, never
                    // opened, landed hours later on a resend). A row that stays sealed after that walk
                    // is remembered for the process: it is not walked again on every fetch.
                    let atS = UInt64(max(0, l["at"] as? Int ?? 0))
                    let rowKey = lm + "@" + String(atS)
                    if sealedRows.contains(rowKey) {
                        MontanaTrace.markFolded("box_skip", "still sealed mid=\(lm)", window: 600, key: "sealed:" + rowKey)
                        continue
                    }
                    guard let opened = MTPipe.openBoxed(sealed, sharedSecret: secret, at: atS) else {
                        sealedRows.insert(rowKey)
                        MontanaTrace.mark("box_skip", "envelope did not open within a day mid=\(lm) age_s=\(Int(Date().timeIntervalSince1970) - Int(atS))")
                        continue
                    }
                    let plain = opened.plain
                    if opened.back > 1 { MontanaTrace.mark("box_late", "sealed \(opened.back) min before the node took it mid=\(lm)") }
                    if rdvLabels.contains(cw) {
                        guard plain.count > 1092 else { continue }
                        let ct = plain.prefix(1088)
                        let f = parseLetterFields(plain.dropFirst(1088))
                        guard !f[0].isEmpty, !f[1].isEmpty else { continue }
                        // THE INVITE AND THE CONFIRMATION RIDE WITH THE LETTER (1636): the extension's road
                        // stored both, this road stored neither, and the drain refused every first-meeting
                        // letter the app fetched itself («rdv_stash_dead invite=0 conf=0», T2 19:57:18Z) —
                        // without a push the meeting was dead by construction.
                        guard keep(["c": "rdv", "m": f[0], "t": f[1], "n": f[2], "g": f[3],
                                     "k": Data(ct).base64EncodedString(), "i": invOf[cw] ?? "", "cf": f[4]]) else { continue }
                    } else {
                        let f = parseLetterFields(plain)
                        guard !f[0].isEmpty, !f[1].isEmpty, let chat = chatOf[cw] else { continue }
                        if let buries, await buries(chat, f[0]) {
                            if let m = l["m"] as? String, !m.isEmpty { confirmed.append(m) }
                            continue
                        }
                        guard keep(["c": chat, "m": f[0], "t": f[1], "n": f[2], "g": f[3],
                                     "qt": f[4], "qm": f[5], "lp": f[6],
                                     // The minute the seal was MADE — the node's moment less the walk
                                     // the opener took (16.09). For a build whose names carry no birth,
                                     // this is the honest moment: a letter that lay sealed for an hour
                                     // used to wear the hour of its arrival.
                                     "at": String(Int(atS) - opened.back * 60)]) else { continue }
                    }
                    stashed += 1
                    if let m = l["m"] as? String, !m.isEmpty { confirmed.append(m) }
                }
                // Confirmation RIGHT AFTER the page: the yield is non-destructive, and it is
                // our placement confirmation that opens the next page. THE LETTERS DO NOT WAIT FOR
                // THEIR BURIAL (21.09, measured 13:50:13→13:50:23 on the tablet: the rows were in hand,
                // and the drain stood ten seconds behind burials to two doors dead on that network).
                // A burial is a cleanup — it rides beside; only a full page, which needs the box
                // cleared to yield the next one, waits for it.
                if letters.count >= 128 { await boxDel(confirmed); confirmed.removeAll() }
                else if !confirmed.isEmpty {
                    let mids = confirmed; confirmed.removeAll()
                    Task.detached(priority: .utility) { await boxDel(mids) }
                }
                if letters.count < 128 { break }
            }
        }
        return stashed
    }

    /// A letter's burial in the node box: delivered by the direct road or «delete for both» —
    /// nothing stays on the node beyond what awaits delivery.
    static func boxDel(_ mids: [String]) async {
        guard !mids.isEmpty else { return }
        // THE BURIAL GOES TO EVERY STORE. The letter lies on exactly one of them, and the
        // rest bury nothing at no cost — while a burial sent to a single door leaves the
        // letter standing on the other node until its seven-day term, to be re-delivered.
        // THE STORES ARE ASKED AT ONCE, AND ONLY THE LIVING ONES (21.09): the walk went door by door,
        // five seconds each, and the two doors this network cannot reach cost every burial ten seconds.
        // One deadline for all; the door book that the fetch and the signal lane already keep is the
        // one book here too (SSOT) — a door resting after its silences is not asked while it rests.
        let doors = orderedBases(for: "box")
        let awake = doors.filter { doorAlive($0) }
        let body = try? JSONSerialization.data(withJSONObject: ["mids": mids])
        await withTaskGroup(of: Void.self) { group in
            for b in (awake.isEmpty ? doors : awake) {
                group.addTask {
                    guard let url = URL(string: b + "/box-del") else { return }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
                    var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                    req.timeoutInterval = 5   // a burial never outlives a wake: the default minute froze a pickup across a sleep (21.09)
                    req.setValue("application/json", forHTTPHeaderField: "content-type")
                    req.httpBody = body
                    // SILENT-OK: a cleanup, not delivery — if it missed now, the node's term (7 days) sweeps it.
                    _ = try? await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                }
            }
        }
    }

    /// The file is assembled — the node's chunks serve no one, and the receiver removes them
    /// AT ONCE. They used to lie there until the seven-day term: the phones cleaned up after
    /// themselves while a third copy stayed on the node — a third of a gigabyte per shared track.
    static func dropChunks(_ manifest: [[String: Any]]) async {
        let bids = manifest.compactMap { $0["bid"] as? String }
        guard !bids.isEmpty else { return }
        // Every store, same law as the burial: the chunks lie on whichever node the upload
        // reached, and only that node has anything to drop.
        for b in orderedBases(for: "blob") {
            guard let url = URL(string: b + "/blob-drop") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["bids": bids])
            // SILENT-OK: a cleanup, not delivery. If it missed now — the node's term sweeps it.
            if let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let n = o["dropped"] as? Int, n > 0 {
                MontanaTrace.mark("blob_drop", "n=\(n) at=\(URL(string: b)?.host ?? "-")")
            }
        }
    }

    /// Fetch the missing chunks from the node into the store (window of 3, retries; a chunk's
    /// failure goes to the trace, assembly queues the media for a retry) — the existing
    /// assembly then finds them itself.
    /// The outcome of a cargo pickup try. «Gone for good» is KNOWLEDGE (the node is alive and
    /// honestly refused), while «could not reach» is a passing hindrance. Both used to stay
    /// silent alike, and a person waited twenty seconds where the answer was known on the first.
    enum CargoOutcome { case complete; case lost; case unreachable }

    /// CHUNKS EVERY DOOR HAS ALREADY CALLED GONE (22.09). Measured on T1: the same seven identifiers
    /// were asked of every door at 18:20 and again at 19:23 -- fifteen calls, all of them answered
    /// "gone", one of them costing a five-second wait on a door that had fallen silent -- and the answer
    /// was the same one the record had already written down an hour before. Dead work repeated on every
    /// opening of the chat; the cargo of a letter does not come back by being asked twice.
    ///
    /// The memory lives for this process and no longer: a launch knows nothing and asks once, which is
    /// honest. And it is FORGOTTEN the moment a door that was silent answers again (door_alive) -- that
    /// is new knowledge, and a store that was unreachable may hold what a reachable one did not.
    private static let goneLock = NSLock()
    private static var goneChunks: Set<String> = []

    static func forgetGoneChunks(_ why: String) {
        goneLock.lock(); let n = goneChunks.count; goneChunks.removeAll(); goneLock.unlock()
        if n > 0 { MontanaTrace.mark("blob_dl", "forgot \(n) gone — \(why)") }
    }

    private final class MTFlag: @unchecked Sendable {
        private var on = false
        private let lock = NSLock()
        func raise() { lock.lock(); on = true; lock.unlock() }
        var value: Bool { lock.lock(); defer { lock.unlock() }; return on }
    }

    /// ONE PIECE FROM THE DOORS, WITH THE DOORS' OWN PATIENCE (21.09): a busy door is waited for on a growing pause
    /// (0.7 s doubling, six tries, ~45 s); a silent road gets three quick tries. Neither is «gone». A piece found is put
    /// in the store; a piece every door called gone is remembered so (goneChunks). WHEN this runs is the lane's decision
    /// (MTCargoLane, 25.09): three pieces in flight for the whole phone, the one a player waits for first.
    static func bringChunk(_ bid: String) async -> MTCargoLane.Answer {
        if let d = MontanaBlobStore.get(bid) { return .found(d) }
        var unreachableTries = 0, busyTries = 0
        while unreachableTries < 3 && busyTries < 6 {
            switch await askBlob(bid) {
            case .found(let d):
                MontanaBlobStore.put(bid, d)
                MontanaTrace.mark("blob_dl", "id=\(String(bid.prefix(8))) bytes=\(d.count)")
                return .found(d)
            case .gone:
                MontanaTrace.mark("blob_dl", "GONE id=\(String(bid.prefix(8))) — every door answered, no cargo")
                goneLock.lock(); goneChunks.insert(bid); goneLock.unlock()
                return .gone
            case .busy:
                let pause = 0.7 * pow(2.0, Double(busyTries))
                busyTries += 1
                MontanaTrace.markFolded("blob_dl", "BUSY id=\(String(bid.prefix(8))) — the node refuses this moment, pause=\(Int(pause))s", window: 10, key: "busy")
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            case .unreachable:
                unreachableTries += 1
                if unreachableTries < 3 { try? await Task.sleep(nanoseconds: 700_000_000) }
            }
        }
        MontanaTrace.mark("blob_dl", "FAIL id=\(String(bid.prefix(8))) — could not reach")
        return .unreachable
    }

    @discardableResult
    static func fetchChunks(_ manifest: [[String: Any]], need: MTCargoLane.Need = .look,
                            progress: (@Sendable (Int, Int) -> Void)? = nil) async -> CargoOutcome {
        let total = manifest.count
        let missing = manifest.compactMap { c -> String? in
            guard let bid = c["bid"] as? String, MontanaBlobStore.get(bid) == nil else { return nil }
            return bid
        }
        // An empty list = every chunk is already in the store, nothing to fetch — a normal exit. SILENT-OK.
        guard !missing.isEmpty else { progress?(total, total); return .complete }
        let already = total - missing.count
        // What every door has already called gone is not asked again (see goneChunks).
        goneLock.lock(); let gone = goneChunks; goneLock.unlock()
        let askable = missing.filter { !gone.contains($0) }
        guard !askable.isEmpty else {
            MontanaTrace.markFolded("blob_dl",
                "skip=gone n=\(missing.count) — every door answered for these already", window: 60, key: "gone")
            return .lost
        }
        let someAlreadyGone = askable.count < missing.count
        let lostFlag = MTFlag()
        var allGood = false
        await withTaskGroup(of: Bool.self) { group in
            var next = 0
            func launch(_ i: Int) {
                let bid = askable[i]
                group.addTask { () -> Bool in
                    // THE LANE BRINGS IT (25.09): in its turn among every piece the phone asks for, three in flight at most.
                    switch await MTCargoLane.shared.bring(bid, need: need) {
                    case .found: return true
                    case .gone: lostFlag.raise(); return false
                    case .unreachable: return false
                    }
                }
            }
            for _ in 0..<min(3, askable.count) { launch(next); next += 1 }
            var done = already
            // PROGRESS COUNTS ONLY WHAT ARRIVED. The count used to grow on EVERY finished
            // task, failures included: the bar reached the end when NOTHING downloaded, and a
            // person stared at «fully loaded» over a file that does not exist (precedent 20.08).
            var bad = 0
            for await ok in group {
                if ok { done += 1; progress?(done, total) } else { bad += 1 }
                if next < askable.count { launch(next); next += 1 }
            }
            if bad > 0 { MontanaTrace.mark("blob_dl", "missing \(bad) of \(askable.count)") }
            allGood = (bad == 0)
        }
        if allGood, !someAlreadyGone { return .complete }
        return (lostFlag.value || someAlreadyGone) ? .lost : .unreachable
    }

    // ── a call on a sleeping node (stage 5) ──────────────────────────────────── A separate
    // PushKit token, the same daily tags.
    private static let voipTokenKey  = "wakeVoipToken"
    private static let voipDigestKey = "wakeVoipDigest"

    static func onVoipToken(_ token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        MontanaKeychain.set(voipTokenKey, Data(hex.utf8))
        MontanaTrace.mark("wakepush_vtoken", "len=\(hex.count)")
        registerVoip()
    }

    /// Registering the voip token under all conversations' windows — mirrors registerConvs, its own debounce.
    static func registerVoip(refusing refused: Set<String>? = nil) {
        guard let hex = MontanaKeychain.get(voipTokenKey).flatMap({ String(data: $0, encoding: .utf8) }), !hex.isEmpty else {
            MontanaTrace.mark("wakepush_vreg", "skip no-token"); return   // no PushKit token yet; onVoipToken brings it
        }
        let ref = twinRef; guard !ref.isEmpty else { MontanaTrace.mark("wakepush_vreg", "skip no-addr"); return }
        guard agreesWithCanon() else { MontanaTrace.mark("wakepush_canon", "FAIL"); return }
        let refs = MTPipeBook.registrable(refusing: refused ?? ChatStore.refusedNow()); guard !refs.isEmpty else { return }
        let topic = Bundle.main.bundleIdentifier ?? ""
        let w0 = dayWindow()
        var subs: [[String: String]] = []
        for pipe in refs {
            guard let secret = MTPipeBook.secret(for: pipe) else { continue }
            // The S-2 sign of life gates the fan-out: a pipe nobody ever answered has nobody
            // to wake us, and its first letter lives seven days in the node box anyway — the
            // box fetch is the road, the wake is a rung-4 accelerator. Full 31-day fan-out is
            // for ANSWERED correspondences only: hundreds of dead introductions at 32 rows
            // each hit the node's per-token cap (8192), and eviction cut LIVE pairs blind
            // (measured 26.08: one token at exactly 8192 rows, a receipt's wake answered 404).
            let ahead: UInt64 = MTPipeBook.first(for: pipe) == nil ? windowsAhead : 1
            for w in (w0 - 1)...(w0 + ahead) {
                let cw = convW(secret, window: w)
                subs.append(["conv": cw, "sid": mySubId(cw)])
            }
        }
        guard !subs.isEmpty else { return }
        let answered = refs.filter { MTPipeBook.first(for: $0) == nil }.count
        // ONLY WHAT A DOOR LACKS LEAVES, DOOR BY DOOR (23.09) -- the law the letter registration keeps since 21.1.
        // The call set used to be gated by ONE digest for all doors: any door that failed wiped it, the pause was
        // reset by the doors that answered, and the whole set went to every door again -- measured 23.09 on T1:
        // 837 posts in a day, 736 pairs a round, rounds twelve to twenty-five seconds apart while a door behind
        // Cloudflare flickered. Now each door keeps its own map under the call token; a door that does not answer
        // rests (notBusy), and a door that holds the set is asked nothing. The node adds pairs row by row
        // (montana-notify /register-voip), so a part of the set never erases the rest.
        // One door per machine and one chain per door at a time (24.09): the law and the measurement stand at registerConvs.
        let now = Date().timeIntervalSince1970
        var told = false
        for b in oneDoorPerNode(notBusy(orderedBases(for: "notify"))) {
            guard let url = URL(string: b + "/register-voip") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            let host = URL(string: b)?.host ?? b
            let standing = registeredPairs(host, token: hex)
            let due = doubtedNow(host, token: hex) ? subs : subs.filter { p in (standing[pairKey(p)] ?? 0) < now - regRefresh }
            guard !due.isEmpty else {
                MontanaTrace.markFolded("wakepush_vreg", "standing=\(subs.count) door=\(host) -- nothing new", window: 600)
                if let p = subs.first {
                    askHeld(url, host: host, token: hex, topic: topic, pair: p, extra: ["life": Int(MontanaCall.callLifeS)], tag: "wakepush_vheld")
                }
                continue
            }
            if !told {
                told = true
                MontanaTrace.mark("wakepush_vreg", "pipes=\(refs.count) answered=\(answered) subs=\(subs.count)")   // what the phone offers the node to ring it by
            }
            sendChunks(due, url: url, token: hex, topic: topic, digestKey: voipDigestKey, tag: "wakepush_vreg",
                       recorded: { chunk in noteRegistered(host, chunk, at: now, token: hex) },
                       extra: ["life": Int(MontanaCall.callLifeS)])
        }
    }

    /// Letters the extension stored from pushes — into the chat by the same reception road as
    /// any incoming (.montanaIncoming, mid dedup at the receiver). Called on activation.
    /// A long letter whose blob is not yet reachable waits in the inbox like any pushed letter.
    static func stashLongLetter(conv: String, mid: String, text: String) {
        restash(["c": conv, "m": mid, "t": text])
    }

    /// Rows the shelf received for the person now seated (MTSeats.landShelf): into the inbox as a pickup's rows, then the drain.
    static func stashFromShelf(_ rows: [[String: String]]) {
        for r in rows { restash(r) }
        drainInbox()
    }

    private static func restash(_ row: [String: String]) {
        if MTKeeping.takes(row) { return }   // a call in the pipe of a slot this phone keeps: answered there, never a letter of the feed
        var arr: [[String: String]] = []
        if let d = MontanaKeychain.get("nseInbox"),
           let a = try? JSONDecoder().decode([[String: String]].self, from: d) { arr = a }
        guard let m = row["m"] else { return }
        if let i = arr.firstIndex(where: { $0["m"] == m }) {
            // The legs land in any order: a quote arriving second settles onto the row.
            if let qt = row["qt"], !qt.isEmpty, (arr[i]["qt"] ?? "").isEmpty {
                arr[i]["qt"] = qt; arr[i]["qm"] = row["qm"] ?? ""
                if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", d) }
            }
            return
        }
        arr.append(row.filter { !$0.value.isEmpty })
        if let d = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", d) }
    }

    // A DEAD CARGO IS NOT ASKED FOR EVERY FIFTEEN SECONDS (21.09, the critic): two long letters whose
    // cargo no store held any more were asked for at 15 s for fifteen hours from one tablet; from the
    // fleet, 1 069 709 of 1 088 638 store journal lines in eight hours read «no such chunk», the node
    // journals rolled over within hours and the receivers' background budget burned with them. The
    // retry doubles from 15 s to an hour; the sender is told ONCE by the cargo-lost word the chat
    // already speaks (the refill road of 1638); after the box's own term — a day — the reference is
    // buried: a cargo nobody holds for a day is a cargo its sender no longer sends.
    // THE LETTER'S AGE IS THE LETTER'S, NOT THE PROCESS'S (the critic 22.09). The day after which a
    // cargo nobody holds is buried was counted in memory: every launch reset the birth and the try
    // count, so the day never arrived and a dead reference knocked for ever. Measured on the fleet,
    // iPhone 14 Plus: six letters of 20.09 19:22 were still asking at 22.09 11:26 — 2 015 rounds of
    // four doors each on one phone, some 8 000 answers of «no such chunk», and not one «lb_dead» line
    // in three days. The record now lies beside the box (the same keychain the inbox uses), so the
    // burial arrives on the wall clock, whatever happens to the process.
    private static let lbKey = "mt.longblob.wait"
    private static func lbLoad() -> [String: [String: Double]] {
        guard let d = MontanaKeychain.get(lbKey),
              let m = try? JSONDecoder().decode([String: [String: Double]].self, from: d) else { return [:] }
        return m
    }
    private static func lbSave(_ m: [String: [String: Double]]) {
        if let d = try? JSONEncoder().encode(m) { MontanaKeychain.set(lbKey, d) }
    }
    private static var lbDue: TimeInterval = 0
    private static var lbGen = 0
    @MainActor static func lbForget(_ mid: String) {
        var m = lbLoad(); guard m.removeValue(forKey: mid) != nil else { return }; lbSave(m)
    }
    /// THE LETTER KEEPS ITS OWN HOUR (23.09, the critic). The record said «retry in 3600s» while every
    /// ring, box pickup and return to the screen drained the inbox and asked for the cargo at once:
    /// measured on the Mac 23.09, rounds 13, 14 and 15 within ten seconds, each announcing an hour —
    /// 29 rounds in four hours instead of eleven, every round all chunks on four doors. The next hour
    /// lives in the record now, and a road that drains the inbox or answers a ring asks only a letter
    /// whose hour has come.
    static func lbDueNow(_ mid: String) -> Bool {
        guard let next = lbLoad()[mid]?["next"] else { return true }
        return next <= Date().timeIntervalSince1970
    }

    /// «No such cargo» from every door is final once it has held for ten minutes over three rounds: a
    /// long letter's cargo is uploaded before its reference is sealed, and a store answers «no» only
    /// when neither it nor its siblings hold the chunk. The reference is buried then, and the sender is
    /// told then — once in the letter's life, and never on a mere «later». «Later» keeps the day of the
    /// box's own term.
    private static let lbGoneRounds = 3
    private static let lbGoneSpan: TimeInterval = 600
    @discardableResult
    @MainActor static func lbFailed(_ mid: String, conv: String, gone: Bool, bornAt: Double? = nil) -> Bool {
        let now = Date().timeIntervalSince1970
        var stored = lbLoad()
        let old = stored[mid]
        var rec = old ?? [:]
        let born = min(rec["born"] ?? now, bornAt ?? now)   // a row brings its letter's birth: past the box's term, one refusal buries it
        let n = Int(rec["tries"] ?? 0)
        rec["born"] = born; rec["tries"] = Double(n + 1)
        // A record written before the hour was kept told its sender at its first failure.
        if old != nil, rec["next"] == nil, rec["told"] == nil { rec["told"] = born }
        if gone {
            rec["goneAt"] = rec["goneAt"] ?? now
            rec["goneN"] = (rec["goneN"] ?? 0) + 1
        }
        let goneN = Int(rec["goneN"] ?? 0)
        let goneFor = now - (rec["goneAt"] ?? now)
        if goneN >= lbGoneRounds, goneFor >= lbGoneSpan {
            lbForget(mid)
            inboxDrop([mid])
            MontanaTrace.mark("lb_dead", mid: mid, "every door answered «no such cargo» \(goneN) times over \(Int(goneFor / 60)) min — the reference is buried")
            return true
        }
        if now - born > boxTerm {
            lbForget(mid)
            inboxDrop([mid])
            MontanaTrace.mark("lb_dead", mid: mid, "asked \(n + 1) rounds over \(Int((now - born) / 3600))h — the reference is buried")
            return true
        }
        if gone, rec["told"] == nil, !conv.isEmpty, conv != "rdv" {
            rec["told"] = now
            MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString,
                                                 text: cargoLostMark + mid, silent: true)
        }
        let delay = min(15.0 * pow(2.0, Double(n)), 3600.0)
        rec["next"] = now + delay
        stored[mid] = rec
        lbSave(stored)
        MontanaTrace.mark("lb_wait", mid: mid, "retry in \(Int(delay))s try=\(n + 1) verdict=\(gone ? "gone" : "later")")
        let due = now + delay
        if lbDue > now, lbDue <= due { return false }   // an earlier retry already stands
        lbDue = due; lbGen += 1; let g = lbGen
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard lbGen == g else { return }
            lbDue = 0; drainInbox()
        }
        return false
    }

    /// ONE ROAD FOR A LONG LETTER'S CARGO (23.09): the ring and the drain both take a long letter
    /// through here, so it keeps its own hour whichever road wakes it, one question at a time, and its
    /// final word is spoken once. It says which of three it came to: the words landed, the letter waits
    /// (its hour has not come, another question is in flight, or the cargo did not come), or the
    /// reference was buried — so a road never lays a buried reference back into the box.
    enum LongTake { case landed(String); case waiting; case buried }
    @MainActor private static var longInFlight = Set<String>()
    @MainActor static func takeLongLetter(conv: String, mid: String, text: String, bornAt: Double? = nil) async -> LongTake {
        guard lbDueNow(mid), longInFlight.insert(mid).inserted else { return .waiting }
        defer { longInFlight.remove(mid) }
        switch await fetchLongLetter(text) {
        case .words(let full): lbForget(mid); return .landed(full)
        case .gone: return lbFailed(mid, conv: conv, gone: true, bornAt: bornAt) ? .buried : .waiting
        case .later: return lbFailed(mid, conv: conv, gone: false, bornAt: bornAt) ? .buried : .waiting
        }
    }

    /// Letters this life has posted, or holds on an asynchronous road — never posted twice (main thread).
    private static var inboxTaken = Set<String>()
    /// The letter leaves the box — after its row is on disk, never before ([C-1]: the one remover).
    static func inboxDrop(_ mids: [String]) {
        guard !mids.isEmpty, let d = MontanaKeychain.get("nseInbox"),
              var arr = try? JSONDecoder().decode([[String: String]].self, from: d) else { return }
        let gone = Set(mids); let before = arr.count
        arr.removeAll { gone.contains($0["m"] ?? "") }
        if arr.count != before, let out = try? JSONEncoder().encode(arr) { MontanaKeychain.set("nseInbox", out) }
    }
    static func drainInbox() {
        // THE OVERLAY IS NOT DISCARDED BEFORE ITS REPLACEMENT EXISTS. It carries what the
        // extension learned while the app was dead — the newest truth there is. Deleting it at
        // the START of the drain opened a window where the screen fell back to the persisted
        // past: the person opened a notification and read stale unread for a second or two
        // (the author's word 29.08). It dies at the END, when the letters it describes are
        // actually in the store.
        if let d = MontanaKeychain.get("nseDiag"),
           let a = try? JSONDecoder().decode([String].self, from: d), !a.isEmpty {
            for line in a { MontanaTrace.mark("nse_diag", line) }
            MontanaKeychain.set("nseDiag", Data())
        }
        // THE QUIET PLATES LEAVE THE LIST (03.10): a letter the extension kept quiet still wears a passive plate,
        // since an empty content shows bare without Apple's filtering entitlement; its request is written down
        // and taken off here, the moment the person is in the app.
        if let d = MontanaKeychain.get("nseQuietIds"),
           let ids = try? JSONDecoder().decode([String].self, from: d), !ids.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            MontanaKeychain.set("nseQuietIds", Data())
            MontanaTrace.mark("nse_quiet", "removed=\(ids.count)")
        }
        if let d = MontanaKeychain.get("shareDiag"),
           let a = try? JSONDecoder().decode([String].self, from: d), !a.isEmpty {
            for line in a { MontanaTrace.mark("share_diag", line) }
            MontanaKeychain.set("shareDiag", Data())
        }
        // The box empties ONLY when there is someone to hand to: on cold start the drain used
        // to outrun the engine's and the store's birth — letters were broadcast into the void
        // and lost from the box (precedent 23:29:59, proc_ms=110: «the notification exists,
        // no file in the chat»). The store, on attaching, calls drainInbox itself — the
        // letter waits for it in the box.
        guard MontanaDeliveryEngine.shared.store != nil else {
            MontanaTrace.mark("drain_wait", "store not ready"); return
        }
        guard let d = MontanaKeychain.get("nseInbox"),
              let arr = try? JSONDecoder().decode([[String: String]].self, from: d), !arr.isEmpty else {
            // An empty box SPEAKS: silence here hid the two-second «opened — empty» hole
            // (22:42: the drain at 22.6 found zero, the letters showed only at 24.6).
            MontanaTrace.mark("wakepush_drain", "n=0")
            // An empty box is an ANSWER: the app now holds everything the landing door left,
            // and only from here may it rewrite the count record.
            DispatchQueue.main.async {
                let st = MontanaDeliveryEngine.shared.store
                if st?.inboxDrained == false { st?.inboxDrained = true; st?.recalcBadge() }
            }
            return
        }
        MontanaTrace.mark("wakepush_drain", "n=\(arr.count)")
        // THE BOX EMPTIES LETTER BY LETTER, AFTER THE ROW IS ON DISK (16.09). The box used to be
        // wiped whole before the first letter was posted: a process killed while the rows were still
        // in memory lost them for good — the box gone, the node's copy buried, the snapshot never
        // written (T1 18:25:54Z, the seventeenth's letter, «delivered» at the sender). A letter is
        // posted — the receiver journals its row on this very thread — and only then leaves the box;
        // a letter still on an asynchronous road (a long letter, a first meeting) leaves when that
        // road ends. What this life has already taken is not taken twice (main thread, as every call).
        var handled: [String] = []
        var taken = 0
        for it in arr {
            guard let c = it["c"], let m = it["m"], let t = it["t"], !m.isEmpty, !t.isEmpty else {
                if let m = it["m"], !m.isEmpty { handled.append(m) }   // a row without words is not a letter
                continue
            }
            // A long letter waiting for its own hour is not asked by this drain: every ring and pickup
            // drains the box, and the hour is the letter's, not the drain's (lbDueNow).
            if t.hasPrefix(letterBlobMark), !lbDueNow(m) { continue }
            guard inboxTaken.insert(m).inserted else { continue }
            taken += 1
            // A first-meeting letter from a push: the encapsulation rides WITH the letter —
            // the pipe and the chat are born HERE, from the box, without waiting for a live
            // channel (the author's word 22.08: the message goes straight into the chats).
            // The live channel brings the same letter — the door dedups by mid.
            if c == "rdv", let k = it["k"], let ct = Data(base64Encoded: k) {
                // The extension recorded WHOSE seal opened the letter — only that one is tried.
                guard let inv = it["i"],
                      let ref = MontanaCard.accept(firstLetter: ct, invite: inv, conf: it["cf"] ?? "") else {
                    MontanaTrace.mark("rdv_stash_dead",
                        "mid=\(m.prefix(8)) invite=\(it["i"] == nil ? 0 : 1) conf=\(it["cf"] == nil ? 0 : 1)")
                    handled.append(m)
                    continue
                }
                var ui2: [String: Any] = ["from": ref, "mid": m, "text": t, "transport": "push"]
                if let n = it["n"], !n.isEmpty { ui2["senderName"] = n }
                if let g = it["g"], !g.isEmpty { ui2["senderGlyph"] = g }
                // A-3: the «delete for both» tombstone waits on the node until the pipe's
                // birth yields the key to deliver it — before this line there was nothing to
                // deliver with. The hatching delay: the pipe is already born (quietly),
                // subscriptions and the box pickup go at once; the chat is shown ONLY if no
                // tombstone arrived within the delay. Otherwise a conversation erased at both
                // ends would flash at the second side with a letter from the extension box.
                MontanaTrace.mark("wakepush_drain", "rdv mid=\(m.prefix(8)) ref=\(String(ref.prefix(10))) hatch-hold")
                // The name and face — AT ONCE on hatching (from the letter's envelope): the
                // delay holds only the letter's DISPLAY, not the peer's identity — «Peer» on a
                // fresh meeting lived exactly in that gap (precedent 02:46).
                if let n = it["n"], !n.isEmpty, n.count <= 64 {
                    MontanaDeliveryEngine.shared.store?.setPeerName(ref: ref, name: n, at: Double(it["at"] ?? "") ?? 0, source: "first-letter")
                }
                // «g» rides for the older builds; the face is derived from the name ([C-1], 20.09).
                // The delay is DYNAMIC: exactly until the pickup round ends (the tombstone
                // rides there if the conversation was erased at both ends) — not a hard 2.5s.
                // An offline round is short by construction (request timeout 5s), and offline
                // a tombstone cannot arrive any more than a letter can.
                Task {
                    await fetchBox()
                    try? await Task.sleep(nanoseconds: 400_000_000)   // the tombstone drain has time to apply
                    await MainActor.run {
                        if MontanaDeliveryEngine.shared.store?.deletedChats.contains(ref) == true {
                            MontanaTrace.mark("rdv_hatch_dead", "ref=\(String(ref.prefix(10))) the tombstone made it — the chat is not shown")
                        } else {
                            NotificationCenter.default.post(name: .montanaIncoming, object: nil, userInfo: ui2)
                        }
                        inboxDrop([m])   // the road ended — the letter leaves the box
                    }
                }
                continue
            }
            var ui: [String: Any] = ["from": c, "mid": m, "text": t, "transport": "push"]
            if let a = it["at"], let v = Double(a), v > 0 { ui["sentAt"] = v }
            if let n = it["n"], !n.isEmpty { ui["senderName"] = n }
            if let g = it["g"], !g.isEmpty { ui["senderGlyph"] = g }
            if let qt = it["qt"], !qt.isEmpty { ui["quoteText"] = qt; ui["quoteMid"] = it["qm"] ?? "" }
            if let lp = it["lp"], !lp.isEmpty { ui["linkPreview"] = lp }
            if t.hasPrefix(letterBlobMark) {
                Task {   // a long letter: pull the blob and store the FULL text
                    if case .landed(let full) = await takeLongLetter(conv: c, mid: m, text: t) {
                        await MainActor.run {
                            ui["text"] = full
                            NotificationCenter.default.post(name: .montanaIncoming, object: nil, userInfo: ui)
                            inboxDrop([m])
                        }
                    } else {
                        // The cargo did not come — the letter WAITS in the box (it was never taken out of
                        // it) for its own hour or its final word (takeLongLetter). Substituting «New
                        // message» buried the file manifest forever: the mid was taken by the text, the
                        // real file was bounced by dedup (precedent «the notification arrived, no file in the chat»).
                        _ = await MainActor.run { inboxTaken.remove(m) }
                    }
                }
                continue
            }
            NotificationCenter.default.post(name: .montanaIncoming, object: nil, userInfo: ui)
            handled.append(m)
        }
        if !handled.isEmpty { inboxDrop(handled) }
        MontanaTrace.mark("wakepush_drain", "letters=\(taken)")
        // THE LIST IS MEASURED AGAINST THE FEED ONCE THE DRAINED LETTERS HAVE LANDED (17.09): the audit
        // at launch ran before they reached the feed and could not tell a lost letter from one still
        // on its way. Three seconds is longer than any landing hop; a disagreement then is a failure.
        // THE BOX IS EMPTY, THE FEED IS THE ONLY TRUTH (the critic's word 19.09): once the drained
        // letters have landed, every list record is rebuilt from the feed — the door's records
        // included, nothing kept — and then measured. Detection without this step was theatre.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let store = MontanaDeliveryEngine.shared.store else { return }
            store.reconcileListWithFeed(store.messages, keepDoorRecords: false)
            if taken > 0 { store.auditListAgainstFeed(stage: "drained") }
        }
        // NOW the overlay may die: the letters it described are through the ordinary door and
        // their writer owns the list record again. Before this line it was the freshest truth
        // on the device (stage 9 + the author's word 29.08 — no stale flicker at cold start).
        MontanaKeychain.delete("chatListOverlay")
        // The number needs no cleanup here: the landing door incremented the ONE record, and the
        // app rewrites that record wholesale on its next recount — once the history those letters
        // now belong to has actually been read AND this box has been emptied ([C-1]).
        DispatchQueue.main.async {
            MontanaDeliveryEngine.shared.store?.inboxDrained = true
            MontanaDeliveryEngine.shared.store?.recalcBadge()
        }
    }

    // Deadline five seconds; each retry opens a FRESH connection through an ephemeral
    // session the zombie cannot poison.
    private static func callPost(_ req: URLRequest, attempts: Int, tag: String, lane: URLSession? = nil,
                                 done: @escaping (Int, Data?) -> Void) {
        // The deadline-and-fresh-lane rule lives in MTNodeWire (the one owner); this wrapper
        // keeps the callback shape and the trace tags the call roads expect.
        Task {
            let (code, d) = await MTNodeWire.postRaw(req, attempts: attempts, lane: lane)
            if code != 200 { MontanaTrace.mark(tag, "FAIL code=\(code) attempts=\(attempts)") }
            done(code, d)
        }
    }

    // ── THE SIGNAL LANE OF A DOOR IS ONE LANE (29.09) ─────────────────────────────────────────────
    // Every word to a door used to open a connection of its own, and a failed word a second, fresh
    // one: at two to four words a second (the presence beats, the drafts) with a door that did not
    // answer, twenty to forty TLS handshakes stood through the tunnel at once (T1 23:31:45Z, 1988:
    // twenty-five sig_tx in flight the moment the tunnel came up, the engine at 912 goroutines and
    // 40 MB 2.4 s after UP, and the system took the extension). A door takes two words at a time
    // here; the rest wait in the order they were said, a newer chat word of a conversation replacing
    // the older one still waiting (a draft supersedes a draft, a beat a beat); a chat word that finds
    // its door dead by the time its turn comes does not dial it -- a call's word alone knocks a dead
    // door, as before (15.13). Under the lock only the two tables move; the word itself runs after it.
    private static let sigLaneLock = NSLock()
    private static var sigLaneBusy: [String: Int] = [:]
    private static var sigLaneQueue: [String: [(key: String?, run: () -> Void)]] = [:]
    private static let sigLaneWidth = 2
    private static let sigLaneDepth = 16
    private static func onSignalLane(_ door: String, coalesce key: String?, _ run: @escaping () -> Void) {
        sigLaneLock.lock()
        if (sigLaneBusy[door] ?? 0) >= sigLaneWidth {
            var q = sigLaneQueue[door] ?? []
            if let key { q.removeAll { $0.key == key } }
            if q.count >= sigLaneDepth, let i = q.firstIndex(where: { $0.key != nil }) { q.remove(at: i) }   // the oldest chat word gives way
            q.append((key, run))
            sigLaneQueue[door] = q
            sigLaneLock.unlock()
            return
        }
        sigLaneBusy[door, default: 0] += 1
        sigLaneLock.unlock()
        run()
    }
    private static func leaveSignalLane(_ door: String) {
        sigLaneLock.lock()
        sigLaneBusy[door] = max(0, (sigLaneBusy[door] ?? 1) - 1)
        var next: (() -> Void)? = nil
        if var q = sigLaneQueue[door], !q.isEmpty {
            next = q.removeFirst().run
            sigLaneQueue[door] = q
            sigLaneBusy[door, default: 0] += 1
        }
        sigLaneLock.unlock()
        next?()
    }

    // The node sees only the daily tag and the moment. Short-step polling ONLY for the call's
    // duration.
    static func postSignal(_ conv: String, epoch: String, payloadB64: String) {
        let ref = twinRef
        guard !ref.isEmpty else { MontanaTrace.mark("sig_tx", "SKIP no-addr"); return }
        guard let secret = laneSecret(conv) else { MontanaTrace.mark("sig_tx", "SKIP no-secret to=\(String(conv.prefix(10)))"); return }
        guard let gz = Data(base64Encoded: payloadB64).flatMap({ try? ($0 as NSData).compressed(using: .zlib) as Data }) else { MontanaTrace.mark("sig_tx", "SKIP gz"); return }
        var body = Data(ref.utf8); body.append(0); body.append(contentsOf: epoch.utf8); body.append(0); body.append(gz)
        guard let sealed = MTPipe.sealBody(body, sharedSecret: secret) else { return }
        let cw = convW(secret, window: dayWindow())
        // The peer named the door they ask — the word goes there and nowhere else. A peer who
        // has not (an old build, or a fresh chat before the first beacon) gets the word on
        // EVERY store, and whichever door they ask, it is already there (per-node stores do
        // not talk to each other; the consumers are idempotent).
        var doors = peerDoors(conv) != nil ? [signalDoor(for: conv)]
                  : orderedBases(for: "signal").filter { doorAlive($0) }
        // A CALL KNOCKS EVERY DOOR (15.13). The dead-door memory spares the network four chat words
        // a second; a call has a dozen words in all, and a door dead sixty seconds ago is the very
        // door the phone's path may carry again now. Measured 07.09 07:24: the callee's two doors
        // died in one second, the answer's eight resends met an empty door list and left the phone
        // without a single line — and the caller heard nothing at all.
        if MontanaCall.stateSnapshot != "idle" || doors.isEmpty {
            for b in callDoors(for: "signal") where !doors.contains(b) { doors.append(b) }
        }
        guard !doors.isEmpty else { MontanaTrace.mark("sig_tx", "SKIP no-door"); return }
        let chatWord = epoch == "chat"
        let failLock = NSLock(); var failed = 0
        for b in doors {
            guard let url = URL(string: b + "/signal") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["conv": cw, "from_id": mySubId(cw), "env": sealed.base64EncodedString()])
            let host = URL(string: b)?.host ?? "-"
            // ONE LANE PER DOOR (29.09): the word waits its turn; a chat word of this conversation replaces the one still waiting.
            onSignalLane(b, coalesce: chatWord ? conv : nil) {
                // A chat word that waited past its door's death does not dial it; a call's word knocks every door (15.13).
                if chatWord, !doorAlive(b), MontanaCall.stateSnapshot == "idle" {
                    MontanaTrace.markFolded("sig_tx", "SKIP dead door=\(host)", window: 10, key: "dead:" + host)
                    leaveSignalLane(b); return
                }
                callPost(req, attempts: 2, tag: "sig_tx", lane: currentPostLane()) { code, _ in
                    leaveSignalLane(b)
                    MontanaTrace.mark("sig_tx", "code=\(code) door=\(host)")
                    if code == 200 { signalDoorAnswered(b); return }
                    signalDoorFailed(b, code: code)
                    failLock.lock(); failed += 1; let every = failed == doors.count; failLock.unlock()
                    // EVERY DOOR REFUSED A CALL WORD: the diary says so (call_noroute) and the call
                    // machine judges the road by its own state. NO LINE UNDER THE NAME (the author's
                    // word 13.09): this line stood on the screen at 15:27 while the two were talking —
                    // the doors were dead for a call WORD, the media path was alive — and said «the call
                    // cannot connect» over a connected call. A post's failure is not the call's state.
                    if every, MontanaCall.stateSnapshot != "idle" {
                        MontanaTrace.mark("call_noroute", "doors=\(doors.count)")
                    }
                }
            }
        }
    }

    /// POLLING CALL SIGNALS — on its own timer, outside the main loop.
    ///
    /// An ordinary main-loop timer stood here, and it froze while the screen was busy with
    /// its own work: a three-point measurement — the answer lay on the node at 21:40:06, and
    /// the caller collected it only at 21:40:12. Six seconds of silence over a live answer,
    /// and exactly those made «video takes long to connect». A queue timer depends neither on
    /// the loop's mode nor on what the screen draws.
    private static var sigTimer: DispatchSourceTimer?
    private static let sigQ = DispatchQueue(label: "montana.sigpoll")
    private static var sigIdle = 0
    /// The polled conversations are a SET, not the first one that came.
    ///
    /// A conversation used to be captured into the handler forever: the second call in a row
    /// (to another person, or the same one under another key) was left without a signalling
    /// channel — its answer, candidates and call end lay on the node and were NEVER
    /// collected, while the person stared at «Connecting…» until the minute cut-off. The set
    /// also closes «two calls at once».
    private static var sigConvs = Set<String>()
    private static var chatConvs = Set<String>()
    /// Conversations whose BOARD is on the screen (29.09): the board and the chat held the lane in one set, and the chat's
    /// farewell under the pushed board (T1 15:25:10.656 open=0 why=left, 15:25:10.845 stop) took the board's hold with it --
    /// the correspondent's move then rode the silent push, eight to fourteen seconds. Each holder owns its own set; the lane
    /// dies only when every set is empty.
    private static var boardConvs = Set<String>()
    /// A GROUP ROOM'S PAIR LANES (MTGroupRoom, the author's word 07.10.2026 00:2x MSK: calls of up to 13 in a group). Two people of
    /// a group carried by its owner hold no pipe between them, so their lane is sealed by a key the two derive from the room's key
    /// and their two seats; it is named here by the room, never written into the book of pipes, and asked only while the room lives.
    private static var roomConvs = Set<String>()
    private static let roomLock = NSLock()
    private static var roomSecrets: [String: Data] = [:]
    static func openRoomLane(_ conv: String, secret: Data) {
        roomLock.lock(); roomSecrets[conv] = secret; roomLock.unlock()
        sigQ.async { roomConvs.insert(conv); ensureSigTimer("room") }
    }
    static func closeRoomLane(_ conv: String) {
        roomLock.lock(); roomSecrets.removeValue(forKey: conv); roomLock.unlock()
        sigQ.async { roomConvs.remove(conv) }
    }
    /// The key a lane is sealed by: a pipe's own, or a room pair's.
    private static func laneSecret(_ conv: String) -> Data? {
        if let s = MTPipeBook.secret(for: conv) { return s }
        roomLock.lock(); defer { roomLock.unlock() }
        return roomSecrets[conv]
    }
    static func startSignalPolling(_ conv: String) {
        sigQ.async {
            sigIdle = 0
            sigConvs.insert(conv)
            ensureSigTimer("call to=\(String(conv.prefix(10)))")
        }
    }
    static func startChatPolling(_ conv: String) {
        sigQ.async {
            chatConvs.insert(conv)
            ensureSigTimer("chat to=\(String(conv.prefix(10)))")
        }
    }
    static func stopChatPolling(_ conv: String) {
        sigQ.async { chatConvs.remove(conv) }
    }
    static func startBoardPolling(_ conv: String) {
        sigQ.async {
            boardConvs.insert(conv)
            ensureSigTimer("board to=\(String(conv.prefix(10)))")
        }
    }
    static func stopBoardPolling(_ conv: String) {
        sigQ.async { boardConvs.remove(conv) }
    }
    /// Sealing and zlib run off the caller's thread: drafts call this at 4/s from the main actor
    /// while a person types, and the screen owes those milliseconds to the keyboard.
    static func postChatSignal(_ conv: String, text: String) {
        DispatchQueue.global(qos: .utility).async {
            postSignal(conv, epoch: "chat", payloadB64: Data(text.utf8).base64EncodedString())
        }
    }
    private static func ensureSigTimer(_ why: String) {
        // SILENT-OK: polling already runs — the conversation is added, no second timer needed.
        guard sigTimer == nil else { return }
        MontanaTrace.mark("wakepush_sigpoll", "start \(why) n=\(sigConvs.count + chatConvs.count + boardConvs.count)")
        let tm = DispatchSource.makeTimerSource(queue: sigQ)
        tm.schedule(deadline: .now(), repeating: .milliseconds(300), leeway: .milliseconds(50))
        tm.setEventHandler {
            for c in sigConvs.union(chatConvs).union(boardConvs).union(roomConvs) { fetchSignals(c) }
            // THE LANE LIVES WHILE THE PHONE RINGS (13.09). The counter read the machine's state
            // alone, and a ring raised by the push road stands with the machine still «idle»: nine
            // seconds later the lane retired, the caller's hang-up lay uncollected on the node, and
            // the phone rang on with nothing left to stop it. A standing ring is a call as much as
            // a machine is.
            let idle = MontanaCall.stateSnapshot == "idle" && !MontanaCall.ringPosted   // K-1: snapshots, not the machine's fields
            sigIdle = idle ? sigIdle + 1 : 0
            if sigIdle > 30 { sigConvs.removeAll() }        // the call lane retires on idle alone
            if sigConvs.isEmpty && chatConvs.isEmpty && boardConvs.isEmpty && roomConvs.isEmpty {      // the lane dies only when NOBODY needs it
                sigTimer?.cancel(); sigTimer = nil
                MontanaTrace.mark("wakepush_sigpoll", "stop")
            }
        }
        sigTimer = tm
        tm.resume()
    }
    /// One request in flight per conversation: without this a slow cellular link stacked
    /// five-seven of them, the node throttled them with refusals, and we never even read
    /// that — the only signalling channel clogged invisibly.
    private static var sigInFlight = Set<String>()
    private static var sigLaneDirty = false   // a failed question taints the lane — the next one opens fresh
    /// THE HELD LANE. One session to the elected door, kept for as long as the door lives —
    /// not the app-wide shared session a zombie tunnel poisons, not a fresh one per failure.
    /// A failed question closes the lane; the next question opens it anew. Called on sigQ.
    private static var sigSessions: [String: URLSession] = [:]   // one held lane per door
    private static func sigLane(for door: String) -> URLSession {
        if let s = sigSessions[door], !sigLaneDirty { return s }
        if sigLaneDirty { for s in sigSessions.values { s.finishTasksAndInvalidate() }; sigSessions.removeAll() }
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 2
        let s = URLSession(configuration: cfg)
        sigSessions[door] = s; sigLaneDirty = false
        MontanaTrace.mark("sig_rx", "fresh lane door=\(URL(string: door)?.host ?? "-")")
        return s
    }
    /// THE LAST WORD OF EVERY PEER, IN ONE QUESTION (the author's word 11.09: «T2 does not see that
    /// T1 was online until the chat is opened»). A presence word enters through THE ONE incoming
    /// door with its own moment: fresh, it lights «online»; old, it is the stamp. Any other word of
    /// the peer is proof of the moment alone.
    static func sweepPresence(quiet: Bool = false) async {
        let ref = twinRef; guard !ref.isEmpty else { return }
        var q: [[String: String]] = []
        var chatOf: [String: String] = [:]
        let w0 = dayWindow()
        for conv in MTPipeBook.all() {
            guard MontanaConv.holds(conv), let secret = MTPipeBook.secret(for: conv) else { continue }
            for w in (w0 - 1)...w0 {
                let cw = convW(secret, window: w)
                chatOf[cw] = conv
                q.append(["conv": cw, "from_id": mySubId(cw)])
            }
        }
        guard !q.isEmpty else { return }
        var best: [String: (env: String, at: Int)] = [:]   // per conversation, the newest word across the doors
        var doors = 0
        for b in orderedBases(for: "signal") where doorAlive(b) {
            for start in stride(from: 0, to: q.count, by: 128) {
                guard let u = URL(string: b + "/signal-last") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                req.timeoutInterval = 6
                req.setValue("application/json", forHTTPHeaderField: "content-type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["q": Array(q[start..<min(start + 128, q.count)])])
                guard let reply = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                      (reply.1 as? HTTPURLResponse)?.statusCode == 200,
                      let obj = try? JSONSerialization.jsonObject(with: reply.0) as? [String: Any],
                      let rows = obj["last"] as? [[String: Any]] else { continue }
                doors += 1
                for r in rows {
                    guard let cw = r["conv"] as? String, let env = r["env"] as? String, let at = r["at"] as? Int,
                          let chat = chatOf[cw] else { continue }
                    if (best[chat]?.at ?? 0) < at { best[chat] = (env, at) }
                }
            }
        }
        var words = 0, stamps = 0
        for (chat, w) in best {
            guard let secret = MTPipeBook.secret(for: chat), let sealed = Data(base64Encoded: w.env),
                  let plain = MTPipe.openBody(sealed, sharedSecret: secret),
                  let sep = plain.firstIndex(of: 0) else { continue }
            let afterPeer = plain[plain.index(after: sep)...]
            guard let sep2 = afterPeer.firstIndex(of: 0),
                  String(data: afterPeer[..<sep2], encoding: .utf8) == "chat",
                  let j = try? (Data(afterPeer[afterPeer.index(after: sep2)...]) as NSData).decompressed(using: .zlib) as Data,
                  let text = String(data: j, encoding: .utf8), !text.isEmpty else { continue }
            // The word's own moment first (15.09) — unless the node refutes it: a moment AHEAD of the one the node took the
            // word at, by more than two node clocks and the node's whole second may differ, was said by a clock set ahead,
            // and the node's moment stands (24.09, the critic's third pass: «last seen just now» at every activation for such
            // a peer). A moment behind the node's is kept: a farewell retried later is still said when it was said.
            let said = ChatStore.presenceMoment(text)
            let at = said.map { $0 - Double(w.at) > clockSlackS + 1 ? Double(w.at) : $0 } ?? Double(w.at)
            if text.hasPrefix(appMark) || text.hasPrefix(watchMark) {
                // HISTORY NEVER LIGHTS A PRESENCE (13.09 15:15): a «1» swept from the node twelve
                // seconds after a phone locked lit «in chat» for a locked phone. The node's last
                // word is a STAMP — when the peer was there — and the peer's capability, hiding
                // flag and door are learned from it; «in chat» and «online» are lit only by a
                // live word on the lane, which arrives within one beat when both are here.
                words += 1
                let mark = text.hasPrefix(appMark) ? appMark : watchMark
                let payload = text.dropFirst(mark.count)
                await MainActor.run {
                    E2E.notePresenceCapable(chat)
                    E2E.heardCapable(from: chat, payload: payload)   // what its build reads, learned from the stamp as its presence is (25.09)
                    MontanaPresencePrivacy.notePeerHides(chat, payload.dropFirst(1).contains("h"), at: at)
                    if let a = payload.firstIndex(of: "@") { notePeerDoor(chat, host: String(payload[payload.index(after: a)...])) }
                    MontanaDeliveryEngine.shared.store?.noteSeen(chat, at: at)
                    // The letters it names as held whole stay delivered however old the word (23.09).
                    MontanaDeliveryEngine.shared.store?.heardHeldLetters(chat, payload: payload)
                    // The swept word says «gone» or «here» the same way the door reads it (15.09):
                    // a stamp alone let the block's word pass for a moment of presence.
                    if mark == appMark, payload.dropFirst(1).hasPrefix("B") { MontanaDeliveryEngine.shared.store?.peerGone(chat, at: at) }   // «B» right after the digit (24.09)
                    else if mark == appMark { MontanaDeliveryEngine.shared.store?.peerBack(chat, at: at) }
                }
            } else {
                stamps += 1   // a draft, a typing word: proof of the moment, never replayed as live
                await MainActor.run { MontanaDeliveryEngine.shared.store?.noteSeen(chat, at: at) }
            }
        }
        if quiet { MontanaTrace.markFolded("presence_sweep", "convs=\(chatOf.count / 2) doors=\(doors) words=\(words) stamps=\(stamps)", window: 60) }
        else { MontanaTrace.mark("presence_sweep", "convs=\(chatOf.count / 2) doors=\(doors) words=\(words) stamps=\(stamps)") }
    }
    private static func fetchSignals(_ conv: String) {
        // SILENT-OK: the previous request for this conversation is still in flight — a second adds nothing.
        guard !sigInFlight.contains(conv) else { return }
        sigInFlight.insert(conv)
        let ref = twinRef; guard !ref.isEmpty, let secret = laneSecret(conv) else { sigInFlight.remove(conv); return }
        let cw = convW(secret, window: dayWindow())
        let door = signalDoor(for: conv)   // the conversation's door: the first alive for both among orderedBases(for: "signal")
        guard !door.isEmpty, let url = URL(string: door + "/signal-fetch") else { sigInFlight.remove(conv); return }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // A LONG QUESTION instead of frequent polling: the node holds the request up to twenty seconds
        // and answers THE SAME MILLISECOND a signal appears. The old frequent polling cost two troubles
        // at once: a signal waited a whole polling step, and the shared per-conversation counter muted
        // both sides of the call with «too often» — the node refused forty-four of three hundred
        // thirty-three requests, each refusal delaying the call. While a call is being BUILT the
        // questions are short: a silently dead one costs six seconds, not thirty.
        let st = MontanaCall.stateSnapshot   // K-1: a snapshot, not the machine's field
        let building = st == "outgoing" || st == "incoming" || st == "connecting" || st == "reconnecting" || st == "active"
        // TWELVE SECONDS, NOT TWENTY. The doors' nginx holds a request fifteen seconds; the
        // question used to ask for twenty, so on the fifteenth second nginx cut the pipe while
        // the store had ALREADY taken the words out of the queue — and wrote them into a dead
        // socket (measured 04.09: 48 answers 504 in twenty minutes on one phone, 17 broken
        // pipes in half an hour in the store's journal). Every word that landed between the
        // fifteenth and the twentieth second was lost by construction. The question now ends
        // before any door can cut it.
        let wait = building ? 3 : (st == "connected" ? 10 : 12)
        req.timeoutInterval = TimeInterval(wait + 3)
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["conv": cw, "from_id": mySubId(cw), "wait": wait])
        let session = sigLane(for: door)
        let gen = sigGen
        session.dataTask(with: req) { d, resp, err in   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            // CUT BY OUR OWN HAND (a path change, a call's birth, a door declared dead): the new lane
            // already asks, and a question we cancelled says nothing about the door — it must not
            // count as the door's silence.
            if (err as? URLError)?.code == .cancelled { return }
            learnSkew(from: resp)   // the node's clock, in passing — the call's one shared «now» (K-11)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code != 200 {
                MontanaTrace.mark("sig_rx", "code=\(code)")   // throttling is no longer invisible
                signalDoorFailed(door, code: code)
            } else {
                signalDoorAnswered(door)
            }
            sigQ.async {
                guard gen == sigGen else { return }   // cut by a path change — the new lane already asks
                sigInFlight.remove(conv)
                if code != 200 { sigLaneDirty = true; return }
                // BACK TO BACK. The next question leaves the moment the answer arrives — the
                // lane to the door stands without a gap; the 300ms tick is only the watchdog.
                if sigConvs.contains(conv) || chatConvs.contains(conv) || boardConvs.contains(conv) || roomConvs.contains(conv) { fetchSignals(conv) }
            }
            guard let d, let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let envs = obj["envs"] as? [String], !envs.isEmpty else { return }
            MontanaTrace.mark("sig_rx", "n=\(envs.count)")
            let knownEpochs = MontanaCall.epochSnapshot   // K-1: the living epochs, snapshotted under a lock
            // HANG-UPS FIRST. A post-sleep batch carries both offers and one call's hang-up;
            // applying in arrival order raised the screen with the offer and killed it with
            // the hang-up half a second later — a phantom ring (precedent 22.08 01:44:38, a
            // 13ms race). First the whole end, then the rest: the seed graveyard fills BEFORE
            // the screen rises.
            func isEnd(_ e64: String) -> Bool {
                guard let sealed = Data(base64Encoded: e64),
                      let plain = MTPipe.openBody(sealed, sharedSecret: secret),
                      let sep = plain.firstIndex(of: 0) else { return false }
                let afterPeer = plain[plain.index(after: sep)...]
                guard let sep2 = afterPeer.firstIndex(of: 0),
                      let j = try? (Data(afterPeer[afterPeer.index(after: sep2)...]) as NSData)
                          .decompressed(using: .zlib) as Data,
                      let t = String(data: j, encoding: .utf8) else { return false }
                return t.contains("\"ctrl\":\"call-end\"")
            }
            let marked = envs.map { ($0, isEnd($0)) }
            let ordered = marked.filter { $0.1 }.map { $0.0 } + marked.filter { !$0.1 }.map { $0.0 }
            for e in ordered {
                // THE STORE'S HINT (08.09): a bare «box» on the lane says the box holds a letter of
                // ours — it is fetched this second, no bell needed while both are in the chat.
                if e == "box" {
                    // THE HINT IS A FACT, NOT A REPEAT (29.09): the letter the node announced is fetched this second, never
                    // booked behind the pickup gate (fetchBoxNow).
                    fetchBoxNow()
                    MontanaTrace.markFolded("sig_rx", "box hint — fetching", window: 8, key: "box-now")
                    continue
                }
                guard let sealed = Data(base64Encoded: e),
                      let plain = MTPipe.openBody(sealed, sharedSecret: secret),
                      let sep = plain.firstIndex(of: 0) else { continue }
                let peer = String(data: plain[..<sep], encoding: .utf8) ?? ""
                let afterPeer = plain[plain.index(after: sep)...]
                guard let sep2 = afterPeer.firstIndex(of: 0) else { MontanaTrace.mark("sig_rx", "STALE old-format"); continue }
                let epoch = String(data: afterPeer[..<sep2], encoding: .utf8) ?? ""
                // No second handler exists. A GROUP ROOM'S PAIR WORD (MTGroupRoom, 07.10): sealed by the pair's own
                // key, read by the room alone.
                if epoch == "room" {
                    let gz = Data(afterPeer[afterPeer.index(after: sep2)...])
                    guard let j = try? (gz as NSData).decompressed(using: .zlib) as Data else {
                        MontanaTrace.mark("sig_rx", "OPEN-FAIL lane=room"); continue
                    }
                    DispatchQueue.main.async { MTGroupRoom.shared.laneWord(conv: conv, payload: j) }
                    continue
                }
                if epoch == "chat" {
                    let gz = Data(afterPeer[afterPeer.index(after: sep2)...])
                    guard let j = try? (gz as NSData).decompressed(using: .zlib) as Data,
                          let text = String(data: j, encoding: .utf8), !text.isEmpty else {
                        MontanaTrace.mark("sig_rx", "OPEN-FAIL lane=chat"); continue
                    }
                    MontanaTrace.mark("sig_apply", "lane=chat kind=\(MontanaNotify.kind(for: text)) from=\(String(conv.prefix(10)))")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .montanaIncoming, object: nil,
                                                        userInfo: ["from": conv, "mid": UUID().uuidString, "text": text])
                    }
                    continue
                }
                // THE LETTER ON THE LANE (29.09, see wake): the correspondent's envelope, the one the box holds, sealed once
                // more for the lane. It lands by the box's own road -- opened by the minute, the seven fields, the inbox, the
                // drain -- so the box's copy, read later, meets the row and is buried as a repeat.
                if epoch == "letter" {
                    let gz = Data(afterPeer[afterPeer.index(after: sep2)...])
                    let now = UInt64(Date().timeIntervalSince1970)
                    guard let env = try? (gz as NSData).decompressed(using: .zlib) as Data,
                          let opened = MTPipe.openBoxed(env, sharedSecret: secret, at: now) else {
                        MontanaTrace.mark("sig_rx", "OPEN-FAIL lane=letter"); continue
                    }
                    let f = parseLetterFields(opened.plain)
                    guard !f[0].isEmpty, !f[1].isEmpty, !ChatStore.refusesNow(conv) else { continue }
                    MontanaTrace.mark("sig_apply", "lane=letter mid=\(String(f[0].prefix(8))) from=\(String(conv.prefix(10)))")
                    restash(["c": conv, "m": f[0], "t": f[1], "n": f[2], "g": f[3], "qt": f[4], "qm": f[5], "lp": f[6],
                             "at": String(Int(now) - opened.back * 60)])
                    DispatchQueue.main.async { drainInbox() }
                    continue
                }
                // Only signals of a call this machine is LIVING (current, second line or
                // parked): another's/an old one is a past call's corpse; applying it =
                // killing the fresh one (precedent: a queued call-end closed ICE in 84ms).
                // BY CONSTRUCTION an idle receiver has no epoch, so a call can NEVER be BORN
                // through this lane — the birth roads are the voip wake and the ring letter,
                // both carrying the seed. This lane only serves a call both sides already know.
                guard knownEpochs.contains(epoch) else {
                    MontanaTrace.mark("sig_rx", "STALE epoch=\(String(epoch.prefix(8))) my=\(String((knownEpochs.first ?? "-").prefix(8)))")
                    answerGone(conv: conv, epoch: epoch, gz: Data(afterPeer[afterPeer.index(after: sep2)...]))
                    continue
                }
                let gz = Data(afterPeer[afterPeer.index(after: sep2)...])
                guard !peer.isEmpty,
                      let j = try? (gz as NSData).decompressed(using: .zlib) as Data else { MontanaTrace.mark("sig_rx", "OPEN-FAIL"); continue }
                MontanaTrace.mark("sig_apply", "from=\(String(peer.prefix(10))) conv=\(String(conv.prefix(10))) bytes=\(j.count)")
                // The call runs under the PIPE KEY that opened the envelope (rule 759) — the
                // address inside is only a reference. Passing the address as the key switched
                // the call machine onto a secretless address: answers went to SKIP no-secret,
                // the call never assembled, the call record flew past the chat (precedent
                // T2→T1 after QR). Unsealing and parsing happen here, on our thread; only the
                // application reaches the main one, in one hop instead of the former two.
                E2E.shared.handleLiveCallSignal(from: conv, payload: j.base64EncodedString())
            }
        }.resume()
    }

    /// A CALL THIS PHONE DOES NOT HOLD IS SAID SO (24.09, iPhone 15 13:03 and 13:07). iOS ended the app when its person
    /// changed a privacy switch in Settings; the phone came back with no call, and the far phone went on asking it for
    /// fresh checks under the dead call's epoch — buried here as STALE, answered by nothing — and stood «reconnecting»
    /// until its own deadline. Only an ask for fresh checks is answered: it is spoken by a call that stood connected and
    /// never precedes a birth (a candidate may arrive before its call is born here, and must stay buried). Once per epoch.
    private static var goneSaid = Set<String>()
    private static func answerGone(conv: String, epoch: String, gz: Data) {
        guard let j = try? (gz as NSData).decompressed(using: .zlib) as Data,
              let msgs = try? JSONDecoder().decode([E2E.CallSigMsg].self, from: j) else { return }
        answerGone(conv: conv, epoch: epoch, msgs: msgs)
    }
    /// The same answer for the pipe's words, which arrive already open (24.09: the pipe names every word's call).
    static func answerGone(conv: String, epoch: String, msgs: [E2E.CallSigMsg]) {
        guard !epoch.isEmpty, epoch != "chat", epoch == MontanaCall.lostEpoch,   // only the call THIS device held and lost
              msgs.contains(where: { $0.ctrl == "call-restart" || $0.ctrl == "call-restart-answer" }) else { return }
        DispatchQueue.main.async {
            // The run is going back into this very call as soon as its person faces the screen: nothing is said yet --
            // only a rejoin judged not to be tried leaves the call lost (24.09).
            guard !MontanaCall.rejoinAwaits(epoch) else { return }
            guard !goneSaid.contains(epoch) else { return }
            goneSaid.insert(epoch)
            MontanaTrace.mark("call_gone", "tx epoch=\(String(epoch.prefix(8))) to=\(String(conv.prefix(10)))")
            var gone = CallSignalOut(ctrl: "call-gone")
            gone.callSeed = epoch
            gone.epoch = epoch
            E2E.shared.sendCallSignal(to: conv, gone)
        }
    }

    struct RingPush { let conv: String; let ref: String; let offer: String?; let video: Bool
                      let callSeed: String?; let name: String?; let glyph: String?
                      /// The ANSWER of the far phone, when this wake carries one instead of a ring.
                      let answer: String?
                      /// The caller reads an answer off this road — declared in their ring.
                      let readsVoipAnswer: Bool
                      /// The caller goes back into this call when iOS ends its app — declared in their ring (24.09).
                      let rebuilds: Bool
                      /// What the ring declares of the caller's build, as the call machine reads any word's caps.
                      var caps: CallCaps { CallCaps(tier: nil, ver: nil, opus_max: nil, hw_aec: nil, sframe: nil,
                                                    av: readsVoipAnswer, rejoin: rebuilds) } }

    /// The call wake: envelope "ring"‖0x00‖address‖0x00‖gzip(JSON{o,v,s}). Without an offer (a bare early ring) — an
    /// empty tail. The pipe key; the accelerator does not read. The call wake's outcome is a QUANTITY, not a guess:
    /// the caller decides by it whether to re-ring.
    static func wakeVoip(_ conv: String, offer: String? = nil, video: Bool = false, callSeed: String? = nil,
                         answer: String? = nil, completion: ((Int) -> Void)? = nil) {
        // ONE EXIT (13.09): every path of the walk answers exactly once through this funnel —
        // a path that returned in silence (the seal that failed) left the caller's wait to a
        // guillotine, and the guillotine lied. Early exits answer with a refusal: the caller
        // must learn the wake never even left — or they listen to ringing until the cut-off.
        var done = false
        func finish(_ code: Int) { guard !done else { return }; done = true; completion?(code) }
        // «NOBODY» IS A VERDICT OF EVERY DOOR (13.09): the publishers keep separate books, and a
        // phone registers where it could reach at the time — one door's 404 used to stop the
        // ring and tell the caller «not set up» while the other door held the token.
        var saw404 = false, sawOther = false, lastCode = -1
        let ref = twinRef; guard !ref.isEmpty else { finish(-1); return }
        guard agreesWithCanon() else { MontanaTrace.mark("wakepush_canon", "FAIL"); finish(-1); return }
        guard let secret = MTPipeBook.secret(for: conv) else { finish(-1); return }
        // THE WORD OF THE ENVELOPE. «ring» is an invitation; «answ» is the far phone's answer taking
        // the same road back.
        let tag = answer == nil ? "ring" : "answ"
        var body = Data(tag.utf8); body.append(0); body.append(contentsOf: ref.utf8); body.append(0)
        // The video flag rides IN EVERY envelope, the bare ring included: without it the
        // callee raised the audio screen for a video call (the production push always carried video — hence it worked there).
        // `av`: this phone reads an answer off the wake road — the callee learns it here, before any
        // lane of its own exists, and that is the whole point of the flag riding in the ring.
        let obj: [String: Any] = answer.map { ["a": $0, "s": callSeed ?? ""] }
            ?? ["o": offer ?? "", "v": video, "s": callSeed ?? "",
                "n": E2E.myDisplayName(), "g": E2E.myFaceGlyph(), "av": true, "rj": true]
        if let j = try? JSONSerialization.data(withJSONObject: obj),
           let gz = try? (j as NSData).compressed(using: .zlib) as Data {
            body.append(gz)
        }
        // The APNs voip payload limit is 5KB; base64 inflates by a third.
        var sealed = MTPipe.sealBody(body, sharedSecret: secret)
        // An answer that does not fit the road simply does not take it: the lane copy already left,
        // and a truncated answer is no answer.
        if answer != nil, let s0 = sealed, s0.base64EncodedString().count > 4600 {
            MontanaTrace.mark("wakepush_vtx", "answer too big for the wake road — the lane carries it")
            finish(-1); return
        }
        if let s0 = sealed, s0.base64EncodedString().count > 4600 {
            var bare = Data("ring".utf8); bare.append(0); bare.append(contentsOf: ref.utf8); bare.append(0)
            let bobj: [String: Any] = ["o": "", "v": video, "s": callSeed ?? "",
                                       "n": E2E.myDisplayName(), "g": E2E.myFaceGlyph(), "rj": true]
            if let j = try? JSONSerialization.data(withJSONObject: bobj),
               let gz = try? (j as NSData).compressed(using: .zlib) as Data { bare.append(gz) }
            sealed = MTPipe.sealBody(bare, sharedSecret: secret)
        }
        guard let sealedFinal = sealed else { MontanaTrace.mark("wakepush_vtx", "FAIL seal"); finish(-1); return }
        let cw = convW(secret, window: dayWindow())
        let payload = try? JSONSerialization.data(withJSONObject:
            ["conv": cw, "from_id": mySubId(cw), "env": sealedFinal.base64EncodedString()])
        // The call ring walks the doors in the network's order and stops where a phone was
        // ACTUALLY rung: a store that holds no subscription for this tag, or whose publisher
        // is down, must hand the ring on rather than swallow it.
        let doors = callDoors(for: "notify")
        func ring(_ i: Int) {
            guard i < doors.count, let url = URL(string: doors[i] + "/wake-voip") else { finish(-1); return }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = payload
            // ONE ATTEMPT PER DOOR: the walk itself is the retry — the next door stands beside.
            callPost(req, attempts: 1, tag: "wakepush_vtx") { code, data in
                // The wake service answers {"sent": n, "of": m, "apns": code} — never "woken":
                // the walk read a field that was not there, saw «nobody rung» on every 200 and
                // knocked on EVERY door, and every door fronts the same service — four VoIP
                // pushes per dial, thirty stale reports in one burst on the callee (04.09 17:51,
                // 06.09 08:28). A 404 is «no recipients»: the callee never registered — walking on
                // cannot change that, and the caller must hear it instead of a minute of ringing.
                let j = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                let woken = (j?["sent"] as? Int) ?? (j?["woken"] as? Int) ?? -1
                MontanaTrace.mark("wakepush_vtx", "code=\(code) woken=\(woken) door=\(i) carry=\(offer == nil ? 0 : 1) to=\(String(conv.prefix(10)))")
                // The walk teaches the same dead-door memory the call words read: a door silent
                // to a ring is silent to the answer that must come back through it.
                if code == 200 { signalDoorAnswered(doors[i]) } else { signalDoorFailed(doors[i], code: code) }
                if code == 200, woken > 0 { finish(200); return }   // rung — the caller stops here
                if code == 404 { saw404 = true } else { sawOther = true; lastCode = code }
                if i + 1 < doors.count { ring(i + 1) }
                else { finish(saw404 && !sawOther ? 404 : lastCode) }   // every door said «nobody» — or the last real refusal
            }
        }
        ring(0)
    }

    /// Open a call envelope: the pipe walk + windows. Returns the caller's address and (if present) the offer.
    static func openRingEnvelope(_ sealed: Data) -> RingPush? {
        for conv in MTPipeBook.all() {
            guard let secret = MTPipeBook.secret(for: conv) else { continue }
            guard let plain = MTPipe.openBody(sealed, sharedSecret: secret),
                  let sep1 = plain.firstIndex(of: 0),
                  let word = String(data: plain[..<sep1], encoding: .utf8),
                  word == "ring" || word == "answ" else { continue }
            let afterTag = plain[plain.index(after: sep1)...]
            guard let sep2 = afterTag.firstIndex(of: 0) else { continue }
            let ref = String(data: afterTag[..<sep2], encoding: .utf8) ?? ""
            let gz = plain[plain.index(after: sep2)...]
            var offer: String? = nil; var video = false; var seed: String? = nil
            var name: String? = nil; var glyph: String? = nil
            var answer: String? = nil; var readsAnswer = false; var rebuilds = false
            if !gz.isEmpty, let j = try? (Data(gz) as NSData).decompressed(using: .zlib) as Data,
               let obj = try? JSONSerialization.jsonObject(with: j) as? [String: Any] {
                offer = (obj["o"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                video = (obj["v"] as? Bool) ?? false
                seed = (obj["s"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                name = (obj["n"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                glyph = (obj["g"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                answer = (obj["a"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                readsAnswer = (obj["av"] as? Bool) ?? false
                rebuilds = (obj["rj"] as? Bool) ?? false
            }
            // conv is the key the pipe opened with: the callee runs the call under IT (their
            // native conversation name); one secret, one daily tag — both sides in one queue.
            return RingPush(conv: conv, ref: ref, offer: offer, video: video,
                            callSeed: seed, name: name, glyph: glyph,
                            answer: word == "answ" ? answer : nil, readsVoipAnswer: readsAnswer, rebuilds: rebuilds)
        }
        return nil
    }
}

// A tiny thread-safe flag set: the expiry hook (main thread) raises a letter's flag, the
// upload loop (task pool) reads it. One check consumes nothing — the flag lives until the
// letter's flow ends.
final class MTAtomicFlagSet {
    private var set = Set<String>()
    private let lock = NSLock()
    func raise(_ key: String) { lock.lock(); set.insert(key); lock.unlock() }
    func check(_ key: String) -> Bool { lock.lock(); defer { lock.unlock() }; return set.contains(key) }
    func clear(_ key: String) { lock.lock(); set.remove(key); lock.unlock() }
}

// Stage 8.3: chunks that do not fit the system grace window ride the BACKGROUND upload
// session — the system delivers them itself, even after the process dies, and wakes the app
// when they are done. The request body is written to a file (a background session uploads
// only from files); the wire shape is the same /blob-put the node already freezes with tests.
// SERVER-DEBT-ACK: the accelerator node (rung 4) — the same acknowledged accelerator leg.
final class MontanaBlobUpload: NSObject, URLSessionDataDelegate {
    static let shared = MontanaBlobUpload()
    static var wakeCompletion: (() -> Void)?
    private static let sessionId = "quest.montana.app.blob-up"

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.sessionId)
        c.isDiscretionary = false
        c.sessionSendsLaunchEvents = true
        return URLSession(configuration: c, delegate: self, delegateQueue: nil)
    }()

    private var bodyDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mt-bgup")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Hand a sealed chunk to the system. Idempotent per bid: an existing body file means the
    /// task is already enqueued (the node dedups by content name anyway).
    func enqueue(bid: String, sealed: Data) {
        // No baked-in address (the author's rule): the background hand-over takes the first
        // living door; a failed task re-enqueues on the next pass through the ordinary road.
        guard let b = MontanaWakePush.bases(for: "blob").first,
              let url = URL(string: b + "/blob-put") else { return }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        let bodyURL = bodyDir.appendingPathComponent(bid + ".json")
        if FileManager.default.fileExists(atPath: bodyURL.path) { return }
        guard let body = try? JSONSerialization.data(withJSONObject:
            ["bid": bid, "data": sealed.base64EncodedString()]) else { return }
        guard (try? body.write(to: bodyURL, options: .atomic)) != nil else {
            MontanaTrace.mark("blob_bgup", "body write refused bid=\(bid.prefix(8))"); return
        }
        var req = URLRequest(url: url); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        let t = session.uploadTask(with: req, fromFile: bodyURL)
        t.taskDescription = bid
        t.resume()
        MontanaTrace.mark("blob_bgup", "enqueued bid=\(bid.prefix(8))")
    }

    /// Orphan body sweep: bodies no live task owns are dead weight AND they silence the
    /// sender-side cargo check (a body on disk reads as «still riding»). Swept on background
    /// relaunch since 8.3, and on every return to the person (AppDelegate.appBecameActive, 24.09 — it stood in a delegate
    /// method UIKit never calls, and a crashed handoff muted the check for its letter indefinitely).
    /// A BODY BORN A MOMENT AGO IS NO ORPHAN (24.09): the sweep now runs beside a queue that may be laying a body this very
    /// instant — the file comes before its task — so a body younger than five minutes is left to its task.
    static func sweepOrphanBodies() {
        shared.session.getAllTasks { tasks in
            let live = Set(tasks.compactMap { $0.taskDescription })
            let dir = shared.bodyDir
            let bornBefore = Date().addingTimeInterval(-300)
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let bid = f.deletingPathExtension().lastPathComponent
                let born = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if !live.contains(bid), born < bornBefore { try? FileManager.default.removeItem(at: f) }
            }
        }
    }

    /// Any of these chunks still riding the system session? (a body file exists per queued bid)
    static func anyPending(_ bids: [String]) -> Bool {
        let dir = shared.bodyDir
        return bids.contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0 + ".json").path) }
    }

    /// The app was relaunched for background-session events: touch the session so the system
    /// can deliver them, and keep the completion handler for urlSessionDidFinishEvents.
    static func reconnect(completion: @escaping () -> Void) {
        wakeCompletion = completion
        // A crashed handoff burst leaves body files no task owns — gigabytes in Caches.
        sweepOrphanBodies()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let bid = task.taskDescription ?? "?"
        let code = (task.response as? HTTPURLResponse)?.statusCode ?? -1
        if error == nil, code == 200 {
            MontanaTrace.mark("blob_bgup", "done bid=\(bid.prefix(8))")
            if bid.count == 64 { try? FileManager.default.removeItem(at: bodyDir.appendingPathComponent(bid + ".json")) }
        } else {
            // One honest retry for a node-side refusal; a transport error the system retried
            // already. Beyond that the receiver's pending-media re-fetch and the sender's
            // manual repeat stay the honest legs — nothing pretends the chunk made it.
            MontanaTrace.mark("blob_bgup", "FAIL bid=\(bid.prefix(8)) code=\(code)\(error == nil ? "" : " err")")
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // The chunks are on the node — the queued manifest letter can go NOW, without the
        // person opening the app: drain the delivery queue and the node mailbox in the few
        // seconds this wake grants.
        DispatchQueue.main.async {
            MontanaTrace.mark("blob_bgup", "session events done — kicking the drain")
            MontanaDeliveryEngine.shared.drainAll()
            MontanaWakePush.fetchBoxKick()
            MontanaBlobUpload.wakeCompletion?(); MontanaBlobUpload.wakeCompletion = nil
        }
    }
}



// ── BETA OBSERVABILITY (stage 8-N, the author's decision 23.08): the FULL telemetry of
// every beta tester rides to our node, ANONYMOUSLY BY CONSTRUCTION — not by promise.
// The diagnostic identity is a random UUID born locally (never derived from the address
// or the seed, rotatable); peer address prefixes in trace lines are replaced with salted
// hashes BEFORE leaving the device (the salt never leaves it); message content does not
// exist in these lines at all. What rides: event marks, durations, error codes, device
// model, iOS version, app build — everything needed to debug any class of error from the
// birth of a seed to a notification, with nobody identifiable.
/// THE DIARY LEAVES THE PHONE ONLY BY THE PERSON'S YES (App Review 5.1.1(ii), 08.10.2026, word for word: «Apps that collect user
/// or usage data must secure user consent for the collection, even if such data is considered to be anonymous ... Apps must also
/// provide the customer with an easily accessible and understandable way to withdraw consent»). The switch stands in Settings,
/// Privacy. A Debug build of our own phones is born with it on; a build from TestFlight or the App Store is born with it off. The
/// extensions read the same yes through the diary's id in the shared keychain: it stands there only while the switch is on.
enum MontanaDiagConsent {
    static let key = "diagShare"
    #if DEBUG
    static let birth = true
    #else
    static let birth = false
    #endif
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? birth }
    /// Off: the extensions lose the diary's id and ship nothing; the app's one door refuses (MontanaDiagShip.put).
    static func apply() {
        // Off: the id leaves both stores, so a later yes starts a diary no one can join to the one before (the critic 08.10).
        if !on { MontanaKeychain.set("diagId", Data()); UserDefaults.standard.removeObject(forKey: "diagId") }
        MontanaTrace.markChanged("diag_consent", on ? "on" : "off", every: 86400)
    }
}

enum MontanaDiagShip {
    private static let ud = UserDefaults.standard

    private static var dgId: String {
        let v: String
        if let known = ud.string(forKey: "diagId") { v = known }
        else { v = UUID().uuidString; ud.set(v, forKey: "diagId") }
        // The sheet writes into the SAME diary (the author's word 16.09: every event, at once):
        // the id rides the shared keychain, the one store both processes read.
        if MontanaKeychain.get("diagId").flatMap({ String(data: $0, encoding: .utf8) }) != v {
            MontanaKeychain.set("diagId", Data(v.utf8))
        }
        return v
    }
    // A line ships exactly as it lay on disk. There is NO second cleansing here and must not
    // be: the address and the correspondence name never enter the journal at all
    // (MontanaLog.hide), so a second anonymiser would be a second owner of one rule — and
    // the first place the two rules diverge ([C-1]).

    /// The ONE door outward ([C-1]). Both the live file and the one finished after rotation
    /// leave through it, so the node address, the body shape and the request's politeness are decided in one place.
    private static func put(_ lines: [String], file name: String) async -> Bool {
        guard MontanaDiagConsent.on else { return false }   // no yes, nothing leaves: the lines wait on the phone (5.1.1(ii))
        let body: [String: Any] = [
            "dg": dgId,
            "file": name.hasPrefix("telemetry") ? "tele" : "trace",
            // Stitching three clocks (sender, node, receiver) needs each device's offset from the
            // node's own clock — measured, not assumed, from the node's Date header on the last
            // shipment. tz and a two-letter language say how to read the person's screen, and
            // neither names anyone.
            "dev": ["model": MTNodeWire.deviceModel(),
                    "ios": MTNodeWire.osVersion(),
                    "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
                    "tz": TimeZone.current.secondsFromGMT(),
                    "lang": MTNodeWire.screenLang(),
                    "skew_ms": MontanaWakePush.nodeSkewMs],
            "lines": lines
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            MontanaTrace.mark("diag_ship", "refused=encode"); return false
        }
        // The journal walks the DOORS like everything else — no baked-in address (the author's
        // rule). A hardcoded api.montana.quest stood here, and a phone whose route does not
        // carry packets to it went MUTE as a witness: the very device with the broken road was
        // the one whose journal never arrived (measured 26.08 19:38: the app open, the diag
        // dead for four minutes, while the door beside was alive).
        var lastCode = -1
        for b in MontanaWakePush.bases(for: "diag") {
            guard let u = URL(string: b + "/diag-put") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
            var req = URLRequest(url: u); req.httpMethod = "POST"   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            // THE DEADLINE GROWS WITH THE BODY (25.09) -- the cargo road's one rule (MTNodeWire.cargoTimeoutS): a
            // quarter-megabyte of diary is not a knock, and ten flat seconds on a cellular day sent the small telemetry
            // and lost the transport trace until the evening's Wi-Fi.
            req.timeoutInterval = MTNodeWire.cargoTimeoutS(bytes: data.count)
            req.httpBody = data
            req.networkServiceType = .background   // a live conversation and a letter take the wire first
            guard let (_, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                  let code = (resp as? HTTPURLResponse)?.statusCode else {
                MontanaWakePush.baseFailed(b, code: -1)
                lastCode = -1
                continue
            }
            lastCode = code
            guard code == 200 else {
                MontanaWakePush.baseFailed(b, code: code)   // a refusal is an answer; only 5xx counts as silence
                continue
            }
            MontanaWakePush.learnSkew(from: resp)   // one owner of the skew ([C-1])
            notePutOutcome(landed: true)
            return true
        }
        notePutOutcome(landed: false)
        MontanaTrace.markFolded("diag_ship", "refused=\(lastCode == -1 ? "no-answer" : "code \(lastCode)") lines=\(lines.count) — every door", window: 300)
        return false
    }

    // The device's name, its system and its language are MTNodeWire's: one owner for the app and the extensions (25.09).

    // ── THE TAIL MUST CATCH UP, AND IT MUST WEIGH NOTHING ────────────────────────
    // One pass used to ship a single 256 KB chunk and then sleep an hour: a device eight megabytes
    // behind needed a day and a half of being held open to say what happened this morning. So a
    // pass now keeps going while the file still has a tail — and every part of that catching up is
    // built to be unfelt:
    //   • the work runs at .background, the lowest priority the system offers, so a person's own
    //     tap always preempts it;
    //   • the request is marked background service type, so a live call or a letter takes the wire
    //     first and the diagnostics wait behind them;
    //   • a breath between chunks keeps the radio from being held by the catch-up alone;
    //   • a call in progress stops it outright — the same rule the profile push already obeys,
    //     because a voice is worth more than a journal;
    //   • the file is read in chunks and never held whole in memory.
    private static var running = false
    private static let perPass = 32                            // up to 8 MB of catching up per pass
    private static let firstDelayNs: UInt64 = 60_000_000_000   // a minute, so a launch is never shared
    private static let liveSleepNs: UInt64 = 600_000_000_000   // ten minutes while a person is looking (the author's word 16.09: the ordinary rhythm; a failure ships within five seconds — the rhythm only carries the tail)
    private static let idleSleepNs: UInt64 = 900_000_000_000   // a quarter of an hour once they are not
    /// Refusals in a row by EVERY door. With the stores off, the half-minute rhythm knocked on
    /// four dead doors twice a minute for as long as the app was open (measured 03.09 20:10:
    /// `refused … every door` every 30 s, ten-second timeouts each). Each refusal doubles the
    /// pause, up to the idle rhythm; one journal that lands resets it.
    private static var refusedStreak = 0
    private static let refusedLock = NSLock()
    private static func notePutOutcome(landed: Bool) {
        refusedLock.lock(); refusedStreak = landed ? 0 : refusedStreak + 1; refusedLock.unlock()
    }
    private static func pauseNs(active: Bool) -> UInt64 {
        let base: UInt64 = active ? liveSleepNs : idleSleepNs   // P-64: half a minute while a person looks
        guard active else { return base }
        refusedLock.lock(); let n = refusedStreak; refusedLock.unlock()
        return min(idleSleepNs, base << UInt64(min(n, 5)))
    }
    private static let breathNs: UInt64 = 250_000_000          // between chunks, so the radio is shared

    /// A CRASH SHIPS FIRST. The minute's delay exists so as not to share the app's busiest
    /// second with launch — but a crash outranks politeness.
    ///
    /// It was the one case covered by nothing. A person whose app crashed does not usually
    /// reopen it at once — and the «CRASH signal» record, the very thing diagnostics exists
    /// for, lay in their phone until they changed their mind. Every other case is closed:
    /// open — a minute, then a quarter hour; folded — a pass under the holder; a letter
    /// arrived — the wake calls the shipment; not opened and no letters — the journal is
    /// empty, nothing to collect.
    ///
    /// The PREVIOUS run judges the crash, not the whole file: the launch line separates runs,
    /// and the place to look is exactly between the second-to-last and the last. Otherwise an
    /// ancient crash would forever rush the shipment ahead of the queue.
    static func crashedInLastRun(_ tail: String) -> Bool {
        let runs = tail.components(separatedBy: "=== launch")
        guard runs.count >= 2 else { return false }
        let previous = runs[runs.count - 2]
        return previous.contains("CRASH") || previous.contains("HANG main-thread")   // NOT-UI: the diary's own words
    }

    private static func lastRunEndedBadly() -> Bool {
        let u = MontanaLog.url(.telemetry)
        guard let h = try? FileHandle(forReadingFrom: u) else { return false }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let take = min(size, 131_072)
        try? h.seek(toOffset: size - take)
        guard let d = try? h.read(upToCount: Int(take)) else { return false }
        return crashedInLastRun(String(decoding: d, as: UTF8.self))
    }

    static func kick() {
        guard !running else { return }
        running = true
        let hurt = lastRunEndedBadly()
        if hurt { MontanaTrace.mark("diag_ship", "urgent=last-run-crashed") }
        Task.detached(priority: .background) {
            // A launch is the busiest second of the app's life — the journal can wait a minute,
            // unless the previous run died: then it has waited long enough already.
            if !hurt { try? await Task.sleep(nanoseconds: firstDelayNs) }
            while true {
                await catchUp()
                // The author tests with the app open: while it is on screen the journal must not
                // lag behind the test by a quarter of an hour. Half a minute costs a few dozen
                // kilobytes of tail at background priority; asleep, the old rhythm returns.
                let active = await MainActor.run { UIApplication.shared.applicationState == .active }
                let pause = pauseNs(active: active)
                if active, pause > liveSleepNs { MontanaTrace.markChanged("diag_ship", "pause=\(pause / 1_000_000_000)s — every door refused") }
                try? await Task.sleep(nanoseconds: pause)
            }
        }
    }

    /// The moments a phone certainly has something to say and may not get another chance: it just
    /// came back to the person, it is about to leave them, and it woke in the background for a
    /// letter. None of them can wait for the next quarter of an hour — the app may be killed in
    /// between, and everything past the last watermark would go with it.
    /// Shipping on an error. It differs from shipNow by exactly one thing — a breath: errors
    /// arrive in bursts (six 502s in fifteen seconds on 26.08) while one report is enough — the
    /// first; the remaining lines of the same breakdown ride inside it.
    private static var lastFailureShip: Double = 0
    private static let failureLock = NSLock()
    static func shipOnFailure() {
        let now = Date().timeIntervalSince1970
        failureLock.lock()
        refusedLock.lock(); let refusing = refusedStreak > 0; refusedLock.unlock()
        let due = now - lastFailureShip > 5 && !refusing   // five seconds fold a burst; a dead store is not told about its own death every breath (the author's word 16.09: at once)
        if due { lastFailureShip = now }
        failureLock.unlock()
        guard due else { return }
        MontanaTrace.mark("diag_ship", "cause=failure")
        shipNow()
    }

    static func shipNow() {
        Task.detached(priority: .background) {
            // Going background, the phone gets scant seconds from the system. Without the
            // holder the pass breaks on the first chunk, and everything accumulated since the
            // last mark ships only on the next opening — which may never come.
            let hold = await MainActor.run { MTSendAssertion("diag-ship") }
            await catchUp()
            await MainActor.run { hold.end() }
        }
    }

    /// Journals written before the «no addresses in the journal» rule hold addresses in the
    /// open — and would ride to the node on the first catch-up. They are truncated once, on
    /// the first launch of the build where the rule appeared. Diagnostics loses its past; the
    /// person loses nothing, because no correspondence, keys or content live in these files.
    private static let ruleKey = "diagHideRule"
    private static func forgetJournalsWrittenBeforeTheRule() {
        guard ud.string(forKey: ruleKey) != "1" else { return }
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana/Diagnostics")
        var gone = 0
        for n in ["telemetry.log", "trace.log", "telemetry.log.prev", "trace.log.prev"] {
            let u = dir.appendingPathComponent(n)
            guard FileManager.default.fileExists(atPath: u.path) else { continue }
            try? Data().write(to: u); gone += 1
        }
        ud.set(0, forKey: "diagWmTele"); ud.set(0, forKey: "diagWmTrace")
        ud.set("1", forKey: ruleKey)
        MontanaTrace.mark("diag_ship", "cleared_before_rule=\(gone)")
    }

    /// How many chunks a pass may ship: a FULL catch-up on ANY network — the author's word
    /// 26.08. A «one chunk on cellular» limit stood here — thrift with another's traffic.
    /// Tests run on cellular data only, and the limit hid exactly the runs that must be
    /// seen: a cellular breakage was invisible BY CONSTRUCTION. Weightlessness is held by
    /// the other supports: lowest priority, background network class, a breath between
    /// chunks, stop during a call.
    private static func allowance() async -> Int { perPass }

    // TWO shippers ran this loop at once — the kick cycle and the foreground/background
    // shipNow — and raced one watermark: after a rotation one mover reset it while the other
    // wrote its old offset back, and the diary on the node silently stopped growing while the
    // local file kept writing. One pass at a time; whoever arrives second leaves.
    private static var passBusy = false
    private static let passLock = NSLock()

    private static func catchUp() async {
        // The truncation stands at the door of EVERY pass (P-61) — before the busy gate too:
        // it is idempotent and must precede any byte that could leave the device.
        forgetJournalsWrittenBeforeTheRule()
        passLock.lock()
        let busy = passBusy
        if !busy { passBusy = true }
        passLock.unlock()
        guard !busy else { MontanaTrace.mark("diag_ship", "skip=busy"); return }
        defer { passLock.lock(); passBusy = false; passLock.unlock() }
        let cap = await allowance()
        var passes = 0
        while passes < cap {
            if MontanaCall.isBusy {                 // the voice outranks the journal
                MontanaTrace.mark("diag_ship", "held=call passes=\(passes)")
                return
            }
            guard await shipOnce() else { break }
            passes += 1
            try? await Task.sleep(nanoseconds: breathNs)
        }
        if passes > 0 { MontanaTrace.mark("diag_ship", "passes=\(passes) cap=\(cap)") }
    }

    /// Finish off a file nobody will write to again (a rotated generation). Returns where the reading stopped
    /// -- the watermark of the next pass -- and whether the file was read to its end with every chunk landed:
    /// a generation is deleted only when it says so.
    private static func shipRange(_ url: URL, from: UInt64, name: String) async -> (offset: UInt64, done: Bool) {
        guard let h = try? FileHandle(forReadingFrom: url) else { return (from, true) }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        guard size > from else { return (from, true) }
        try? h.seek(toOffset: from)
        var at = from
        var done = false
        var sent = 0
        var carry = ""      // HALF A LINE left at a chunk boundary is not a line
        while sent < perPass {
            let chunk = (try? h.read(upToCount: 262_144)) ?? Data()
            let last = chunk.isEmpty
            var text = carry + String(decoding: chunk, as: UTF8.self)
            let carried = UInt64(carry.utf8.count)
            carry = ""
            // A break at a chunk boundary begets two halves, and each ships as a «line»: no
            // timestamp, no mark kind, yet with whatever stood in the middle. Exactly so a
            // home address shipped to the node out of a line the rule already knew how to hide whole.
            if !last, let nl = text.lastIndex(of: "\n") {
                carry = String(text[text.index(after: nl)...])
                text = String(text[..<nl])
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            if !lines.isEmpty { guard await put(lines, file: name) else { break } }
            at += carried + UInt64(chunk.count) - UInt64(carry.utf8.count)   // the bytes of every line that landed
            if last { done = true; break }
            sent += 1
            try? await Task.sleep(nanoseconds: breathNs)
        }
        MontanaTrace.mark("diag_ship", "rotated=\(name) chunks=\(sent) done=\(done ? 1 : 0)")
        return (at, done)
    }

    /// The birth of a file, the name by which the watermark knows the file it measures: a rename keeps it, a
    /// fresh file has its own.
    private static func birth(of url: URL) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        let d = (a?[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return String(format: "%.6f", d)
    }
    private static func bytes(of url: URL) -> UInt64 {
        let a = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (a?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Returns true when a file still had a tail after this pass — the caller keeps going. False
    /// when both files are fully shipped, or nothing could be shipped at all.
    @discardableResult
    private static func shipOnce() async -> Bool {
        var more = false
        // A silent zero is indistinguishable from a breakage: every skipped file names its
        // reason, and the reason ships once per change — not once per half minute.
        var idle: [String] = []
        var tail: [String] = []
        let fm = FileManager.default
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Montana/Diagnostics")
        for (name, wmKey, genKey) in [("telemetry.log", "diagWmTele", "diagGenTele"), ("trace.log", "diagWmTrace", "diagGenTrace")] {
            let url = dir.appendingPathComponent(name)
            // ONE WATERMARK, BOUND TO THE FILE IT MEASURES (25.09). The offset alone could not tell a rotated file
            // from a grown one: when the fresh file outgrew the old offset before the next pass, the pass shipped
            // from the middle of the new file and the end of the old one never left the phone -- and two rotations
            // between two passes lost a whole generation. The watermark now carries the birth of its file. The
            // finished generations are sent first, the oldest first, each deleted once it has landed whole; then
            // the live file -- from its start when it is not the file the watermark measured.
            var wm = UInt64(max(0, ud.integer(forKey: wmKey)))
            var wmBirth = ud.string(forKey: genKey) ?? ""
            var pending: UInt64 = 0
            var held = false
            for g in stride(from: MontanaLog.keep, through: 0, by: -1) {
                let gen = dir.appendingPathComponent(name + (g == 0 ? ".prev" : ".prev." + String(g)))
                guard fm.fileExists(atPath: gen.path) else { continue }
                if held { pending += bytes(of: gen); continue }
                let b = birth(of: gen)
                if b != wmBirth { wm = 0; wmBirth = b; ud.set(0, forKey: wmKey); ud.set(b, forKey: genKey) }
                let r = await shipRange(gen, from: wm, name: name)
                wm = r.offset; ud.set(Int(r.offset), forKey: wmKey)
                guard r.done else { held = true; pending += bytes(of: gen) - min(bytes(of: gen), r.offset); continue }
                try? fm.removeItem(at: gen)
                wm = 0
            }
            if held { idle.append(name + "=generation-held"); more = true }
            guard let h = try? FileHandle(forReadingFrom: url) else { idle.append(name + "=no-file"); continue }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            let liveBirth = birth(of: url)
            if held {
                pending += size
                tail.append(name + "=" + String(pending / 65_536 * 64) + "KB")
                continue
            }
            if wmBirth.isEmpty { wmBirth = liveBirth; ud.set(liveBirth, forKey: genKey) }   // the offset of the build before this rule measured the live file
            if liveBirth != wmBirth { wm = 0; wmBirth = liveBirth; ud.set(0, forKey: wmKey); ud.set(liveBirth, forKey: genKey) }
            tail.append(name + "=" + String((size - min(size, wm)) / 65_536 * 64) + "KB")
            guard size > wm else { idle.append(name + "=uptodate"); continue }
            try? h.seek(toOffset: wm)
            // at most ~256 KB per pass per file: the tail catches up over the next passes
            let chunk = (try? h.read(upToCount: 262_144)) ?? Data()
            guard !chunk.isEmpty else { idle.append(name + "=read-empty"); continue }
            var lines = String(decoding: chunk, as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            // an incomplete trailing line stays for the next pass
            var shipped = chunk.count
            if chunk.last != UInt8(ascii: "\n"), lines.count > 1 {
                let lastLen = lines.removeLast().utf8.count
                shipped -= min(lastLen, shipped)
            }
            guard !lines.isEmpty else { idle.append(name + "=half-line"); continue }
            guard await put(lines, file: name) else { idle.append(name + "=put-failed"); continue }
            ud.set(Int(wm) + shipped, forKey: wmKey)
            if UInt64(Int(wm) + shipped) < size { more = true }   // this file is not finished telling
        }
        let r = idle.joined(separator: " ")
        if !r.isEmpty { MontanaTrace.markChanged("diag_ship", "idle " + r) }
        // THE SHIPPER'S LEDGER GOES INTO THE TELEMETRY (25.09): what the transport trace could not say about its own
        // hole -- its words lay in the hole. The unsent tail of every file, in quarter-megabytes, with the standing
        // refusal if any; written when it changes, so a day that never caught up is read the next morning.
        refusedLock.lock(); let refusing = refusedStreak; refusedLock.unlock()
        MontanaTrace.markChanged("diag_tail", tail.joined(separator: " ") + (refusing > 0 ? " refused=" + String(refusing) : ""), tele: true)
        return more
    }
}

// THE MODE OF THE NETWORK IS MEASURED, NEVER GUESSED (15.09). «The node does not work» meant four
// different things in one month: our own door was down, the phone had no network at all, the
// operator's tunnel dropped, or the country's whitelist was on and only permitted destinations
// passed. All four wrote the same word in the diary — «unreachable» — and a whole day went into
// telling them apart by hand (a tester's phone: 416 refusals at our node and 581 at another IN THE
// SAME HOUR, with the tunnel dropping at 08:14). So the diary names the mode itself: two beacons
// stand beside our doors — one service the public accounts of the list name as permitted, one that
// nobody claims is permitted yet answers on any ordinary line — and their pair of answers reads
// the mode. Only then does the answer of our own door mean anything.
enum MontanaNetProbe {

    /// Named as permitted in the public accounts of the list (the state portal, the national
    /// messenger, the mail and the search of the two majors, the largest social network). Every
    /// target is a small static file, and it is asked for HEADERS only.
    private static let permitted: [(url: String, want: String)] = [
        ("https://max.ru/robots.txt", "text"),
        ("https://mail.ru/robots.txt", "text"),
        ("https://ya.ru/favicon.ico", "image"),
        ("https://vk.com/robots.txt", "text"),
        ("https://www.gosuslugi.ru/robots.txt", "text"),
    ]

    /// Nobody claims these are permitted, and all five answered from inside and from outside the
    /// country when they were chosen (measured 15.09). Services closed by the ordinary block list
    /// are deliberately absent: they answer nowhere, so they would read as «filtered» even on a
    /// wide-open line, and a verdict built on them would be worth nothing.
    private static let ordinary: [(url: String, want: String)] = [
        ("https://detectportal.firefox.com/success.txt", "text"),
        ("https://www.gstatic.com/generate_204", "any"),
        ("https://captive.apple.com/hotspot-detect.html", "text"),
        ("https://example.com/", "text"),
        ("https://duckduckgo.com/robots.txt", "text"),
    ]

    /// ONE TABLE OF FAILURE CLASSES for every road of this app. «No answer» is not a fact; the fact
    /// is WHICH no-answer: a name that does not resolve, a refusal before the first byte, a reset
    /// in the middle, a silence to the deadline. Without the class a dropped tunnel and a
    /// country-wide filter write the same line — which is exactly how a day was lost.
    static func failClass(_ why: String) -> String {
        let w = why.lowercased()
        if w.contains("bad record") || w.contains("record mac") { return "tls-reset" }
        if w.contains("-9806") || w.contains("handshake") { return "handshake" }
        if w.contains("-1003") || w.contains("cannot find host") || w.contains("hostname") { return "name" }
        if w.contains("-1001") || w.contains("timed out") || w.contains("timeout") { return "timeout" }
        if w.contains("-1004") || w.contains("could not connect") || w.contains("refused") { return "refused" }
        if w.contains("-1009") || w.contains("offline") || w.contains("network is down") || w.contains("50") { return "net-down" }
        if w.contains("53") || w.contains("abort") { return "reset" }
        if w.contains("54") || w.contains("57") { return "peer-closed" }
        return "other"
    }

    private struct Shot { let host: String; let code: Int; let cls: String; let ms: Int; let ok: Bool }

    private static func ask(_ t: (url: String, want: String)) async -> Shot {
        let host = URL(string: t.url)?.host ?? "-"
        // A cached answer measures nothing, so the query carries a number nobody asked before.
        guard var parts = URLComponents(string: t.url) else { return Shot(host: host, code: 0, cls: "other", ms: 0, ok: false) }
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "mt", value: String(UInt32.random(in: 1 ... UInt32.max)))]
        guard let url = parts.url else { return Shot(host: host, code: 0, cls: "other", ms: 0, ok: false) }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"   // the body is not needed; the fact of an answer is
        req.timeoutInterval = 4
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let began = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int(Date().timeIntervalSince(began) * 1000)
            guard let http = resp as? HTTPURLResponse else { return Shot(host: host, code: 0, cls: "other", ms: ms, ok: false) }
            // A PERMITTED PAGE BEHIND A GATE IS NOT AN OPEN LINE. The published requirements for the
            // list include refusing a visitor whose tunnel is up, and the way in can be gated by a
            // captcha — and a gate answers 200 with a page of its own. So the kind of the answer is
            // checked beside its code: a page where a small file was asked for is a gate, not a road.
            let kind = (resp.mimeType ?? "").lowercased()
            let kindOK = t.want == "any" || kind.contains(t.want)
            let ok = (http.statusCode == 200 || http.statusCode == 204) && kindOK
            return Shot(host: host, code: http.statusCode, cls: ok ? "-" : (kindOK ? "code" : "gate"), ms: ms, ok: ok)
        } catch {
            let e = error as NSError
            return Shot(host: host, code: 0, cls: failClass("\(e.localizedDescription) \(e.code)"),
                        ms: Int(Date().timeIntervalSince(began) * 1000), ok: false)
        }
    }

    private static let rotKey = "mt.probe.rot"
    private static let modeKey = "mt.probe.mode"
    private static let confKey = "mt.probe.conf"
    private static let atKey = "mt.probe.at"
    /// The verdict and its hysteresis live in MTNetLine; only a round no tunnel carried moves it.
    private static let lineKey = "mt.probe.line"
    static var line: MTNetLine {
        UserDefaults.standard.data(forKey: lineKey).flatMap { data in try? JSONDecoder().decode(MTNetLine.self, from: data) } ?? MTNetLine()
    }
    static var underWhitelist: Bool { line.holds(now: Date().timeIntervalSince1970) }
    /// A call has no road under the list unless a tunnel carries this app past the filter.
    static var filtersCalls: Bool { underWhitelist && !MontanaNetWitness.tunnelPresent() }
    /// The mode and its confidence in one word for a summary line: «open/3», «whitelist/1», «-/0».
    static var verdictWord: String {
        (UserDefaults.standard.string(forKey: modeKey) ?? "-") + "/" + String(UserDefaults.standard.integer(forKey: confKey))
    }

    /// WHAT CARRIED THE ROUND, IN THREE WORDS. The full interface roll is nineteen names on a
    /// phone with a tunnel up (measured 15.09: pdp_ip0, anpi0, en1, en2, utun0…utun7, ipsec0…3,
    /// awdl0, llw0) — a line nobody reads to the end and a diary that grows for nothing. The
    /// facts are read from the one source that owns them and written as a summary: which radio
    /// carried it and how many tunnels stood.
    private static func shortIfs() -> String {
        let all = MontanaNetFacts.interfaces().lowercased()
        var carried: [String] = []
        if all.contains("pdp_ip") { carried.append("cell") }
        if all.contains("en0") || all.contains("en1") { carried.append("wifi") }
        let tunnels = all.split(separator: ",").filter { $0.hasPrefix("utun") || $0.hasPrefix("ipsec") }.count
        return (carried.isEmpty ? "none" : carried.joined(separator: "+")) + (tunnels > 0 ? "/tun\(tunnels)" : "")
    }

    /// The probe keeps its own clock: the door round runs far more often, and paying for beacons on
    /// every one of them would be a gift of traffic nobody asked for. Two clocks, for two reasons.
    /// An hour is the BASELINE — without a run of open lines a single «whitelist» stands against
    /// nothing. A minute is the CEILING on the answer to a silent door: at launch the doors wake one
    /// by one, and each one still asleep asked for its own round — measured 15.09, two rounds in
    /// five seconds on one launch.
    static func hourPassed() -> Bool {
        let last = UserDefaults.standard.double(forKey: atKey)
        return Date().timeIntervalSince1970 - last > 3600
    }

    static func minutePassed() -> Bool {
        let last = UserDefaults.standard.double(forKey: atKey)
        return Date().timeIntervalSince1970 - last > 60
    }

    /// ONE TARGET FROM EACH GROUP PER ROUND, in turn. Five in a group are there so that one service
    /// being down is never read as the mode of a country, and so that the phone pays for two
    /// requests instead of ten; on disagreement the round asks a second pair, because a verdict
    /// must not stand on a single site.
    /// True when this round decided the line's verdict afresh: it confirmed a standing filter, or a destination nobody permits
    /// answered where none stood (MontanaNetProbe.settle stops there).
    @discardableResult
    static func round(mute: [String], alive: [String]) async -> Bool {
        // THE CLOCK IS STAMPED BEFORE THE BEACONS FLY. Stamped after, it loses a race it cannot
        // see: the door round is called from more than one place at once, and two rounds both read
        // the old stamp and both flew — measured 15.09, two rounds 28 ms apart on one launch.
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: atKey)
        let turn = UserDefaults.standard.integer(forKey: rotKey)
        UserDefaults.standard.set(turn &+ 1, forKey: rotKey)
        let tunnelAtStart = MontanaNetWitness.tunnelPresent()
        var wl = await ask(permitted[turn % permitted.count])
        var nw = await ask(ordinary[turn % ordinary.count])
        var pairs = 1
        if wl.ok != nw.ok {
            let wl2 = await ask(permitted[(turn &+ 1) % permitted.count])
            let nw2 = await ask(ordinary[(turn &+ 1) % ordinary.count])
            if wl2.ok { wl = wl2 }
            if nw2.ok { nw = nw2 }
            pairs = 2
        }
        let mode: String
        switch (wl.ok, nw.ok) {
        case (true, true):   mode = "open"
        case (true, false):  mode = "whitelist"
        case (false, true):  mode = "unclear"
        case (false, false): mode = (wl.cls == "name" && nw.cls == "name") ? "name-blocked" : "no-net"
        }
        // THREE ROUNDS AGREEING BEFORE A WORD IS BELIEVED. One round says «whitelist» at every blink
        // of a lift, a handover or a locked screen, and a verdict that cheap is worse than none.
        let same = UserDefaults.standard.string(forKey: modeKey) == mode
        let conf = same ? min(3, UserDefaults.standard.integer(forKey: confKey) + 1) : 1
        UserDefaults.standard.set(mode, forKey: modeKey)
        UserDefaults.standard.set(conf, forKey: confKey)
        // THE LINE'S VERDICT MOVES ONLY ON A ROUND NO TUNNEL CARRIED (30.09): a tunnel walks around the filter, and its round is
        // the tunnel's word, not the line's (measured 15.09: the ordinary beacon timed out at 4001 ms beside the permitted one at
        // 69 ms under a standing tunnel). A tunnel at either end of the round counts; the fleet's reader drops such rounds too.
        let tunnel = tunnelAtStart || MontanaNetWitness.tunnelPresent()
        let now = Date().timeIntervalSince1970
        let before = line
        let after = tunnel ? before : before.step(mode: mode, ordinary: nw.ok, now: now)
        if !tunnel, let data = try? JSONEncoder().encode(after) { UserDefaults.standard.set(data, forKey: lineKey) }
        let held = after.holds(now: now)
        if held != before.holds(now: now) {
            // The proof rides the verdict's change: the pair of beacons that moved it, and how many rounds agreed.
            MontanaTrace.mark("net_line", "filtered=\(held ? 1 : 0) run=\(after.run) wl=\(wl.host):\(wl.code)/\(wl.cls) nonwl=\(nw.host):\(nw.code)/\(nw.cls)")
        }
        let up = alive.sorted().joined(separator: ",")
        let down = mute.sorted().joined(separator: ",")
        let body = "wl=\(wl.host):\(wl.code)/\(wl.cls)/\(wl.ms)ms"
            + " nonwl=\(nw.host):\(nw.code)/\(nw.cls)/\(nw.ms)ms"
            + " doors_up=\(up.isEmpty ? "-" : up) doors_mute=\(down.isEmpty ? "-" : down)"
            + " ifs=\(shortIfs()) utun=\(tunnel ? 1 : 0)"
            + " mode=\(mode) conf=\(conf) pairs=\(pairs) line=\(held ? "whitelist" : "-")/\(after.run)"
        // Written when the mode CHANGES, and otherwise at most once a quarter of an hour: a diary
        // that grows two megabytes a day is a diary nobody reads to the end.
        MontanaTrace.markChanged("net_probe", body, every: 900)
        return !tunnel && (after.filtered ? mode == "whitelist" : nw.ok)
    }

    /// Up to three rounds a quarter of a minute apart -- a blink of the radio is shorter than that -- ending at the first round
    /// that decides the verdict afresh. Nil while any tunnel stands: its round would be the tunnel's word; a tunnel that has
    /// just fallen is given ten seconds to leave the system's table first.
    static func settle() async -> Bool? {
        for _ in 0..<5 where MontanaNetWitness.tunnelPresent() { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        for turn in 0..<MTNetLine.enter {
            if 0 < turn { try? await Task.sleep(nanoseconds: 15_000_000_000) }
            guard !MontanaNetWitness.tunnelPresent() else { return nil }
            if await round(mute: [], alive: []) { break }
        }
        return underWhitelist
    }
}

/// THE LINE UNDER THE PERMITTED LIST, WITH HYSTERESIS (the author's word 30.09). Three agreeing rounds enter the verdict, as the
/// mode's own word always needed (one round calls every lift, handover or locked screen a whitelist); it is left only by two
/// rounds in a row in which a destination nobody permits answered -- the one thing the filter cannot let through -- so a blink
/// of the radio (no network, a name that does not resolve) neither enters nor leaves it, and the roads that ask do not flap.
/// A verdict no round confirmed for six hours lapses and is earned again by three rounds: six missed hourly baselines
/// (MontanaNetProbe.hourPassed) mean it no longer describes this line. Pure, so its law is read in one place.
struct MTNetLine: Codable, Equatable {
    var filtered = false
    var at: Double = 0      // the last round that confirmed the filter
    var run = 0             // rounds in a row: up for the permitted-only answer, down for an answer nobody permits
    static let enter = 3
    static let leave = 2
    static let lapse: Double = 6 * 3600
    func holds(now: Double) -> Bool { filtered && now - at < Self.lapse }
    func step(mode: String, ordinary: Bool, now: Double) -> MTNetLine {
        var next = filtered && !holds(now: now) ? MTNetLine() : self
        if mode == "whitelist" {
            next.run = min(Self.enter, max(0, next.run) + 1)
            if Self.enter <= next.run { next.filtered = true }
            if next.filtered { next.at = now }
        } else if ordinary {
            next.run = max(-Self.leave, min(0, next.run) - 1)
            if Self.leave <= -next.run { next.filtered = false }
        } else {
            next.run = 0
        }
        return next
    }
}

/// A NEW BUILD IN TESTFLIGHT IS TOLD BY THE MONTANA ROOM (the author's word 29.09): the upload road writes the release --
/// the build, the version, what changed since the build before, the TestFlight link -- to the nodes; every phone reads
/// it with the doors' round, and a build newer than its own lands once as a letter of the room (the crown, the changes,
/// the button) and rings as a letter of Montana. An older or equal build says nothing; a build already told is not told again.
enum MontanaRelease {
    private static let toldKey = "mt.release.told"
    static var ownBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    static func check(door b: String) async {
        guard let u = URL(string: b + "/release") else { return }   // SERVER-DEBT-ACK: the accelerator node (rung 4), not the delivery road
        var req = URLRequest(url: u); req.timeoutInterval = 8   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        guard let (d, resp) = try? await URLSession.shared.data(for: req),   // SERVER-DEBT-ACK: the accelerator node (rung 4)
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let build = j["build"] as? Int, build > 0 else { return }
        let version = String(((j["version"] as? String) ?? "").prefix(16))
        let notes = Array(((j["notes"] as? [String]) ?? []).map { String($0.prefix(300)) }.prefix(40))
        let url = String(((j["url"] as? String) ?? "").prefix(200))
        // WHAT CHANGED, IN EVERY LANGUAGE OF THE APP (the author's word 03.10): the road writes the English list and each own
        // language's beside it; the row keeps them all and the letter speaks the phone's (releaseInfoOf).
        var l10n: [String: [String]] = [:]
        for (lang, list) in (j["l10n"] as? [String: [String]]) ?? [:] where MTLanguage.own.contains(lang) {
            l10n[lang] = Array(list.map { String($0.prefix(300)) }.prefix(40))
        }
        let own = ownBuild
        let told = UserDefaults.standard.integer(forKey: toldKey)
        MontanaTrace.markChanged("release", "seen=\(build) own=\(own) told=\(told)", every: 3600)
        guard build > own, build != told, !url.isEmpty else { return }
        UserDefaults.standard.set(build, forKey: toldKey)
        await MainActor.run {
            guard let store = MontanaDeliveryEngine.shared.store else { return }
            guard store.appendRelease(build: build, version: version, notes: notes, l10n: l10n, url: url) else { return }
            MontanaTrace.mark("release", "told build=\(build) notes=\(notes.count)")
            MontanaLog.event("RELEASE told build=\(build) own=\(own)")
            MontanaNotify.presentRelease(build: build, version: version)
        }
    }
}
