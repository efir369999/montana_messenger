import SwiftUI

/// THE WALLET IS THE APP (the author's word 09.10.2026 16:00 MSK: «in the wallet leave only the page of the time coins and the
/// wallet's management; take everything else out, chats and calls among them -- the wallet is a wallet, and the contacts in it
/// too»): this page stands as the root and is never closed; the contacts and the wallet's management are the bar's two marks.
struct MTWalletPage: View {
    @Environment(\.scenePhase) private var phase
    @Environment(UIState.self) private var ui
    @State private var state: Result<MTWalletCore.Snapshot, MTWalletCore.Absence>?
    @State private var loading = false
    /// THE COIN BOOK (the author's word 03.10 13:52): the balance, the moves and the history all read the one ledger.
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var pantheon = MTPantheon.shared
    @ObservedObject private var autoMint = MTWalletPull.shared
    @ObservedObject private var vault = MTCoinVault.shared
    @ObservedObject private var tipNet = MTTimeChainTip.shared
    @AppStorage(MTCoinShow.key) private var coinsShown = false   // the owner's switch (Privacy), read here for the table's line
    @AppStorage(MTPersonalRate.key) private var personalRate = ""   // the person's own rate of the coin, for the balance in their currency
    @State private var sending = false
    @State private var toppingUp = false
    @State private var levelsShown = false
    @State private var contactsShown = false
    @State private var chainsShown = false
    /// THE COIN TURNS ONCE (the author's word 03.10.2026 16:55 MSK: «the coin makes one turn at the opening and at a tap»).
    @State private var coinTurn = 0
    /// The touches of the coin that minted, each its rising +1 until it fades (MTRisingPlus).
    @State private var pops: [MTTapPop] = []
    /// THE PULL OF THE PAGE (MTWalletPull): where the coin stands at rest in the list, how far it is drawn, whether it passed the
    /// coin's trigger, and the round the coin completes after the letting go.
    @State private var pullRest: CGFloat?
    @State private var pull: CGFloat = 0
    @State private var pullArmed = false
    @State private var pullReleased: (at: Date, angle: Double)?
    /// The caption under the name (the author's word 09.10.2026): it comes with a finger on the coin and leaves three seconds after
    /// the last finger lifts; a finger landing again keeps it.
    @State private var hint = false
    @State private var hintTurn = 0
    private func showHint() { hintTurn += 1; hint = true }
    private func hideHintSoon() {
        hintTurn += 1
        let turn = hintTurn
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if turn == hintTurn { hint = false } }
    }
    /// From where to where, as a person reads it: the game or the person the coins came from, and where they went.
    static func route(_ e: MTCoinEntry) -> String {
        let me = String(localized: "You", bundle: MTLanguage.bundle)
        let peer = e.peer.map { MTTimeChainRows.who($0) } ?? "—"
        switch e.k {
        case .earn: return MTTimeChainRows.name(MTTimeChain.source(of: e)) + " → " + me
        case .receive: return peer + " → " + me
        case .send, .spend: return me + " → " + peer
        case .burn: return me + " → " + String(localized: "Burned", bundle: MTLanguage.bundle)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    // THE WALLET'S HEAD (the author's word 03.10 13:53): our mint coin where the card stood, the coin book's balance
                    // in large type under it, and the button that sends coins to a person in their chat.
                    VStack(spacing: 14) {
                        // PANTHEON ON FIRE (the author's word 03.10 22:25): the first tap lights the game, every tap mints one coin, the coin
                        // spins at the speed of the taps (MTPantheon) and rests on its face when they stop.
                        // THE COIN TAKES EVERY FINGER (04.10, T1's diary: not one tap of the Pantheon on 2087 -- the coin's own drawing never
                        // takes a finger; the author's words 00:17-00:18: «multi-tapping over the whole surface of the coin, with the animation
                        // of the crediting»): the platform's touches over the whole circle, every finger its own (MTCoinTapPad), and a «+1»
                        // rising from each touch that minted.
                        // THE NAME BURNS ABOVE THE COIN (the author's word 04.10 00:19: «the name lights up above at the activation and goes
                        // out if you do not tap for more than 60 seconds»): it stands while the game burns and leaves with it.
                        // THE PAGE DOES NOT MOVE UNDER THE GAME (the author's word 04.10.2026 04:21 MSK, T2: «why does the wallet's page pull
                        // so; during the Pantheon on Fire the page must not move»): the name, the speed and the box's bar keep their places
                        // whether the game burns or not -- shown and hidden, never inserted, so the coin never moves under the finger.
                        // THE NAME STANDS ALWAYS AND BURNS WHILE THE GAME BURNS; THE WHOLE RULES STAND ON THE PAGE BELOW (MTCoinRules, the
                        // author's words 08.10.2026 02:2x MSK, «crystal clear»; App Review 2.3.1(a)).
                        Label {
                            Text("Pantheon on Fire")
                        } icon: {
                            Image(systemName: "flame.fill").symbolRenderingMode(.multicolor)
                        }
                        .font(.title2.bold())
                        .shadow(color: .orange.opacity(pantheon.lit ? 0.8 : 0), radius: 8)
                        // THE CAPTION COMES WITH THE FINGER (the author's word 09.10.2026 11:3x MSK: «remove this canvas under the name
                        // Pantheon, and only at a press of the coin show under the name Pantheon on Fire: hold the coin 9 seconds for auto
                        // minting, music doubles auto minting -- then the caption goes; show it only at the touch of the coin»): one line
                        // while a finger is on the coin and three seconds after the last one lifts; hidden, it keeps its place, so the coin
                        // never moves under the finger.
                        Text("Hold the coin for 9 seconds for auto minting; music doubles auto minting.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .opacity(hint ? 1 : 0)
                            .accessibilityHidden(!hint)
                            .animation(.easeInOut(duration: 0.25), value: hint)
                        // THE APPS THAT MINT, ABOVE THE COIN (the author's word 04.10.2026 18:08 MSK): their icons, the row kept in its place.
                        MTMintingApps()
                        ZStack {
                            Group {
                                if pantheon.lit || autoMint.on {
                                    // THE COIN TURNS WHILE IT MINTS: at the taps' speed while the Pantheon burns, at least once a second
                                    // while the auto minting runs (MTWalletPull) -- the nine seconds' hold keeps both at once (04.10 13:06),
                                    // and one view for both, so the fire going out never restarts the turn.
                                    MTMintCoin(spinning: 0 < pantheon.speed || autoMint.on, side: 120, speed: Double(max(pantheon.speed, autoMint.on ? 1 : 0)))
                                } else {
                                    MTMintCoin(side: 120, turn: coinTurn)
                                }
                            }
                            // THE COIN AND A LITTLE PAST ITS RIM (the author's word 04.10.2026 03:13 MSK: «the tap area only on the coin and a
                            // little wider than its border»): the pad reaches past the coin's frame by its rim; the rising capsule stands
                            // where the finger touched, in the coin's own frame.
                            MTCoinTapPad(locked: pantheon.lit, onDown: { pantheon.touched(); showHint() }, onUp: { pantheon.released(); hideHintSoon() },
                                         onLongHold: { autoMint.fire() }) { point in
                                let coins = pantheon.tap()
                                let r = MTCoinTapPad.rim
                                if 0 < coins {
                                    pops.append(MTTapPop(point: CGPoint(x: point.x - r, y: point.y - r), coins: coins))
                                    // Five rise at once at most (the heat, 04.10): the oldest gives way to the newest finger.
                                    if 5 < pops.count { pops.removeFirst(pops.count - 5) }
                                }
                            }
                            .padding(-MTCoinTapPad.rim)
                            ForEach(pops) { pop in
                                MTRisingPlus(point: pop.point, coins: pop.coins) { pops.removeAll { $0.id == pop.id } }
                            }
                        }
                        .frame(width: 120, height: 120)
                        .background(GeometryReader { g in Color.clear.preference(key: MTWalletPullKey.self, value: g.frame(in: .named("walletList")).minY) })
                        // THE BOX ON THE COIN (the author's word 04.10.2026 03:07 MSK: «the box's level as a badge on the coin in the wallet»):
                        // the number of the level of π the balance fills -- the minting's multiplier -- as the platform's badge, at the coin's rim,
                        // and the number of the apps minting at once beside it (MTMintLevelBadge, the author's word 04.10.2026 18:08 MSK).
                        .overlay(alignment: .topTrailing) { MTMintLevelBadge(balance: book.balance).offset(x: -8, y: 8).allowsHitTesting(false) }
                        // THE COIN CATCHES FIRE AT THE TAPS (the author's word 04.10 00:19): its glow grows with the speed and dims to embers
                        // between the taps while the game burns.
                        // THE GLOW IS A STILL CIRCLE UNDER THE COIN (the author's word 04.10.2026 12:27 MSK, the heat of the minting): a
                        // shadow of a spinning coin was drawn anew every frame, its radius moving with the speed; a blurred circle beneath
                        // it is drawn once, and only its light follows the speed.
                        .background(Circle().fill(Color.orange).blur(radius: 14).opacity(pantheon.lit ? (0 < pantheon.speed ? 0.8 : 0.3) : 0).allowsHitTesting(false))
                        .animation(.easeOut(duration: 0.25), value: pantheon.speed)
                        // THE SYSTEM'S RING OF THE GAME (the author's word 04.10 00:10): the platform's ring stands round the coin while the
                        // Pantheon burns, as the chat's coin wears it while it mints.
                        .overlay { if pantheon.lit { Circle().strokeBorder(MTMiniFace.playingRing, lineWidth: 3).padding(-8).allowsHitTesting(false) } }
                        .accessibilityElement()
                        .accessibilityLabel(Text("Coin"))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { pantheon.tap() }
                        // USER-DATA: the taps of the last second, a number from 0 to 13
                        Text(verbatim: String(pantheon.speed) + " / " + String(MTPantheon.ceiling))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .opacity(pantheon.lit ? 1 : 0)
                            .accessibilityHidden(!pantheon.lit)
                        MTLevelProgress(balance: book.balance)
                            .opacity(pantheon.lit || autoMint.on ? 1 : 0)
                            .accessibilityHidden(!(pantheon.lit || autoMint.on))
                        MTSecondPrice()
                        MTPantheonStreak(pantheon: pantheon)
                            .opacity(pantheon.lit || pantheon.restUntil != nil ? 1 : 0)
                            .accessibilityHidden(!(pantheon.lit || pantheon.restUntil != nil))
                        // USER-DATA: the coin book's balance, a number
                        // Until the book lands, the balance a device of the same words told in its tip (MTTimeChainTip, 04.10 16:34).
                        // THE TICKER BESIDE THE BALANCE (the author's word 04.10.2026 17:31 MSK: «to the right of the amount, exactly the
                        // balance's size and style»; MTCoinBook.ticker, point 12): one text under one font, one line that narrows to fit.
                        // USER-DATA: the balance, a number, and the ticker, one symbol in every language
                        (Text(verbatim: MTCoinText.count(vault.heard ? book.balance : max(book.balance, tipNet.seen ?? 0)))
                            + Text(verbatim: " " + MTCoinBook.ticker))
                            .font(.system(size: 48, weight: .bold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
                            .textSelection(.enabled)
                        // THE SEED'S BOOK IS ON ITS WAY (the author's word 04.10.2026 15:51 MSK: «I log in on T3 by T1's seed and see my
                        // balance»): a device restored by its words says it is gathering until the nodes answer, never a balance of nothing.
                        if !vault.heard, book.balance == 0 || tipNet.seen != nil {
                            ProgressView("Gathering your coins").controlSize(.small).font(.footnote)
                        }
                        // USER-DATA: the same balance in Montana (one coin is 0.000000001)
                        Text(verbatim: MTChatMint.montana(book.balance) + " Ɱ").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        // THE BALANCE IN THE PERSON'S CURRENCY (the author's word 05.10.2026 00:25 MSK: «under the line of the coins in
                        // Montana, above the level of π, the wallet's balance in the chosen currency at the person's rate»): the balance
                        // times one coin's worth by their own earning (MTPersonalRate), once that earning is told.
                        if let word = MTPersonalRate.read(personalRate) {
                            // USER-DATA: the balance in the person's currency at their own rate
                            Text(MTPersonalRate.coin(word) * Decimal(book.balance), format: .currency(code: word.code).locale(MTLanguage.locale))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // THE WALLET'S LEVEL IS π AS FAR AS THE BALANCE REVEALS IT (the author's word 04.10 00:51): the level and π to it.
                        // USER-DATA: the level of π the balance fills and π revealed to it
                        Text(verbatim: "π " + MTPiLevels.revealed(MTPiLevels.place(book.balance)) + " · " + String(MTPiLevels.place(book.balance)))
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        // TWO BUTTONS OF THE SYSTEM, ONE WIDTH (the author's word 03.10 16:55: «the button is white and crooked; make
                        // send and top up there»): the page's tint is the label colour, so the prominent button stood white -- the
                        // platform's blue is named on the pair itself.
                        HStack(spacing: 12) {
                            Button { sending = true } label: {
                                // OUR SEND, AS IN THE CHATS (the author's word 05.10: «on the Send button use our send icon, as in the chats»).
                                // The symbol of sending time, a touch larger, in proportion to the word (the author's word 05.10.2026).
                                Label { Text("Send") } icon: { MTTimeSendMark(height: 24) }
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(book.balance <= 0)
                            Button { toppingUp = true } label: {
                                Label("Top up", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(MontanaOctagon.platformBlue)
                        // THE TIMECHAIN IN PLACE OF A SECOND ACCOUNT (the author's words 10.10.2026 13:4x and 15:2x MSK: «remove the Add
                        // account button and put TimeChains in its place»; «the TimeChain, where the first chain of time is the Person,
                        // the second the Wallet»; App, «The chains of time a client shows»): one seed is one person, and what stands
                        // beside it is the evidence of its time.
                        Button { chainsShown = true } label: {
                            Label("TimeChain", systemImage: "link").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(MontanaOctagon.platformBlue)
                        // THE TOP THIRTEEN BY A BUTTON (the author's word 03.10 21:56): the boxes of π and the person's place among them.
                        Button { levelsShown = true } label: {
                            Label("Levels of π", systemImage: "list.number").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(MontanaOctagon.platformBlue)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .animation(.easeInOut(duration: 0.4), value: pantheon.lit)   // the fire comes and goes softly
                    .listRowBackground(Color.clear)
                }
                // THE TOP THIRTEEN PEOPLE UNDER THE HEAD (the author's word 03.10 22:23): the person among the people who told their
                // balance, with the faces and the names of the chats tab (MTCoinTop13).
                // WHAT SHOWING DOES IS SAID WHERE THE TABLE STANDS (App: a client states the consequence before the act), and the
                // row is put only after this page has said it (MTCoinShow.toldKey).
                Section { MTCoinTop13() } header: { Text("Top 13") } footer: {
                    if coinsShown { Text("Your name and coins are shown to everyone in the Montana top. Privacy settings turn it off.") }
                    else { Text("You are not in the Montana top. Privacy settings turn it on.") }
                }
                // EVERY ROAD OF THE COINS, ON THE PAGE ITSELF (the author's words 08.10.2026 02:2x MSK, «crystal clear»): not behind a button.
                // The chains moved to the TimeChain page, the wallet's second chain (10.10.2026).
                Section { MTCoinRules() } header: { Text("How coins come and go") }
                // THE BOOK'S ROWS (the author's word 03.10 13:53: every row reads the coin ledger). The chats, the wall and chess left
                // the wallet (the author's word 09.10.2026 16:00 MSK): their rows stand only on a book that already holds such coins.
                Section {
                    if book.earned != 0 {
                        LabeledContent {
                            // USER-DATA: a number, the coins the chats earned in an earlier version
                            Text(verbatim: MTCoinText.count(book.earned)).monospacedDigit()
                        } label: { Text("Coins from chats") }
                    }
                    LabeledContent {
                        // USER-DATA: a number, the coins the Pantheon on Fire's taps minted
                        Text(verbatim: MTCoinText.count(book.tapped)).monospacedDigit()
                    } label: { Text("Coins from the Pantheon") }
                    if book.played != 0 {
                        LabeledContent {
                            // USER-DATA: a number, the coins of chess an earlier version played
                            Text(verbatim: MTCoinText.count(book.played)).monospacedDigit()
                        } label: { Text("Coins from chess") }
                    }
                    // THE RETIRED WALL'S COINS (08.10.2026: the VPN left for its own app): shown only on a book that holds them.
                    if book.walled != 0 {
                        LabeledContent {
                            // USER-DATA: a number, the coins an earlier version minted (MTRetiredCoins)
                            Text(verbatim: MTCoinText.count(book.walled)).monospacedDigit()
                        } label: { Text("Coins from an earlier version") }
                    }
                    LabeledContent {
                        // USER-DATA: a number, the coins calls and letters burned (MTCoinBurn)
                        Text(verbatim: MTCoinText.count(book.burned)).monospacedDigit()
                    } label: { Text("Coins burned") }
                    LabeledContent {
                        // USER-DATA: a number, the coins that came from people
                        Text(verbatim: MTCoinText.count(book.received)).monospacedDigit()
                    } label: { Text("Coins received") }
                    LabeledContent {
                        // USER-DATA: a number, the coins sent to people
                        Text(verbatim: MTCoinText.count(book.sent)).monospacedDigit()
                    } label: { Text("Coins sent") }
                    if book.spent != 0 {
                        LabeledContent {
                            // USER-DATA: a number, the coins an earlier version gave on letters and posts
                            Text(verbatim: MTCoinText.count(book.spent)).monospacedDigit()
                        } label: { Text("Coins on reactions") }
                    }
                    LabeledContent {
                        // USER-DATA: a number, the balance in Montana (one coin is 0.000000001)
                        Text(verbatim: MTChatMint.montana(book.balance)).monospacedDigit()
                    } label: { Text("Coins in Montana") }
                } header: { Text("Minting") }
                  footer: { Text("Coins are counted on this phone until the wallet opens.") }
                // THE HISTORY IS ITS OWN PAGE (the author's words 04.10.2026 04:00-04:02 MSK: «the history must be grouped correctly, not an
                // endless canvas»; «the history as a link button into it, with the choice of the period and the details of the analysis»;
                // T1 2092 00:59Z, three stalls of the main thread of four seconds: a dictionary of every link's seal was rebuilt at every
                // coin and compared whole at every pass of this page).
                Section {
                    NavigationLink { MTCoinHistoryPage() } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
                if let state, case .success(let wallet) = state {
                    Section("TimeChain") {
                        // The core's confirmed balance, apart from the coin book: only the core turns a right into a note.
                        LabeledContent("Confirmed balance", value: wallet.balance)
                        if let head = wallet.lastConfirmedWindow {
                            LabeledContent("Last confirmed window", value: String(head))
                        } else { Text("No confirmed window yet").foregroundStyle(.secondary) }
                        LabeledContent("Network participation", value: wallet.pulseRunning
                            ? String(localized: "Active", bundle: MTLanguage.bundle)
                            : String(localized: "Not active", bundle: MTLanguage.bundle))
                        LabeledContent("Wallet notes", value: String(wallet.notes))
                    }
                    if !wallet.windows.isEmpty {
                        Section {
                            ForEach(wallet.windows) { window in
                                VStack(alignment: .leading, spacing: 6) {
                                    LabeledContent("Window", value: String(window.id))
                                    LabeledContent("Right to a share", value: String(window.share))
                                    LabeledContent("Redemption window", value: String(window.acceptedIn))
                                        .foregroundStyle(.secondary)
                                }.padding(.vertical, 4)
                            }
                        } header: { Text("Participation") }
                          footer: { Text("A right becomes a wallet note only after the core confirms its redemption.") }
                    }
                }
            }
            .scrollContentBackground(.hidden).montanaPageGround()
            .overlay { MTCoinSides() }   // the coins rise at the sides at every minting (MTCoinFlash, 04.10)
            // THE PAGE STANDS WHILE THE PANTHEON BURNS (the author's words 04.10 00:51 and 03:13 MSK: «when I tap the coin, switch the
            // wallet's scroll off»; «while it is on I do not want to see scrolling at all»): no scroll from the first tap until the fire
            // goes out after three quiet seconds (MTPantheon.quiet); the coin's own touch locks the page even before its first coin.
            .scrollDisabled(pantheon.lit)
            // THE TITLE AT THE LEFT (the author's word 04.10.2026 13:34 MSK: «align the word Wallet to the left, it goes past the
            // borders») AND WHOLE ON EVERY SCREEN (10.10.2026 15:2x MSK: MTFittingTitle). The root has no cross: the contacts and
            // the wallet's management stand at the trailing edge.
            .montanaFittingTitle("TimeCoin")
            .navigationDestination(isPresented: $chainsShown) { MTTimeChainsPage() }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    MontanaBarMark(glyph: "person.2", label: "Contacts") { contactsShown = true }
                    MontanaBarMark(glyph: "gearshape", label: "Settings") { ui.settingsShown = true }
                }
            }
            .coordinateSpace(.named("walletList"))
            .onPreferenceChange(MTWalletPullKey.self) { y in pulled(y) }
            // THE COIN IN THE PULL (the author's words 04.10.2026 03:19-03:56 MSK: «pulling the wallet's page brings our coin, as the
            // time panel does»): the time panel's own coin (MontanaCoinSpinner) turns with the pull; let go past its trigger, it mints
            // and reads the page again (pulled). The platform's spinner is not drawn: the coin is the refresh.
            .overlay(alignment: .top) {
                if MontanaCoinSpinner.pullStart < pull || pullReleased != nil {
                    MontanaCoinSpinner(pull: pull, released: pullReleased).padding(.top, 8).allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $sending) { MTCoinSendSheet() }
            .sheet(isPresented: $contactsShown) { MTWalletContactsPage() }
            .sheet(isPresented: $toppingUp) { MTCoinTopUpSheet() }
            .sheet(isPresented: $levelsShown) { MTPiLevelsSheet() }
            .overlay { if loading && state == nil { ProgressView() } }
        }
        .tint(.primary)
        // THE BOTTOM EDGE STAYS THE WALLET'S (T1 04.10 12:45:49 MSK: a minting swipe landed on the home indicator at y=911 -- the
        // lowest of 85 touches -- and the system took the app home; the author's word: «I did not do that»): the system's swipe at
        // the bottom edge waits for a second stroke here, as a game asks of it.
        .defersSystemGestures(on: .bottom)
        .task { await refresh() }
        // THE AUTO MINTING IS ON BY DEFAULT (the author's word 09.10.2026 20:1x MSK: "in every app the auto minting automatically,
        // by default"): the page standing open mints by the second without a pull or a hold; leaving the page or locking the
        // screen still ends it (MTWalletPull), and the return to the page or to the app begins it again.
        .onAppear { if !pantheon.lit { autoMint.fire() } }
        // THE TOP IS A LIVE SET FROM THE NODES (the author's words 04.10.2026 03:03 and 04:19 MSK: «a live set as by a web socket, the
        // update instant from the nodes»): while the wallet stands open the pairs' last words are asked of the nodes every three
        // seconds in one question -- their balances ride them (E2E.coinTail); a pair in the app hands its own over at once.
        .task {
            UserDefaults.standard.set(true, forKey: MTCoinShow.toldKey)
            await MTTimeChainTip.shared.gather(why: "wallet")   // the other devices' tips in one round trip (04.10 16:34)
            await MTCoinVault.shared.gather(why: "wallet")   // the seed's book first: the row tells what the seed holds (04.10)
            MTWalletOwner.shared.look()   // the person of these words in Montana or Business: the row wears their name (10.10.2026)
            MTTopNet.shared.put()
            var turn = 0
            while !Task.isCancelled {
                await MontanaWakePush.sweepPresence(quiet: true)
                await MTTopNet.shared.read()   // the one table, the same on every phone
                // THE SEED'S OTHER DEVICES SWING IN (the author's word 04.10.2026 15:51 MSK: «check the sync over the network as a
                // pendulum»): while the wallet stands open the seed's book is gathered every fifteen seconds, so a coin minted on one
                // device of the words is on the other's balance within that.
                await MTTimeChainTip.shared.gather(why: "live")   // a tip every three seconds: a coin of another device within that (16:34)
                if turn % 5 == 4 { await MTCoinVault.shared.gather(why: "live") }
                await MTPersonChain.shared.tick()   // the devices of the words join the seconds of the person (10.10.2026)
                turn += 1
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
        .onChange(of: phase) { _, new in
            // THE LOCK ENDS IT, NOT A GLANCE (the author's word 05.10.2026 00:53 MSK): the screen locked or the app left goes to the
            // background; a banner or the Control Center pulled down only makes the scene inactive, and the minting goes on.
            if new == .active { Task { await refresh() }; if !pantheon.lit { autoMint.fire() } } else if new == .background { autoMint.stop(why: "background") }
        }
        .onDisappear { autoMint.stop(why: "page"); pantheon.released() }
    }
    private static func kindKey(_ k: MTCoinEntry.Kind) -> LocalizedStringKey {
        switch k {
        case .earn: return "Earned in a chat"
        case .receive: return "Received"
        case .spend: return "Coins on a letter"
        case .send: return "Sent"
        case .burn: return "Burned"
        }
    }
    private var absence: String {
        if case .failure(let why)? = state { return MTWalletCore.said(why) }
        return MTWalletCore.said(nil)
    }
    /// The coin drawn down past its trigger and let go: one minting of the pull (MTWalletPull) and the page read again. While the
    /// Pantheon burns nothing is pulled -- the page stands.
    private func pulled(_ y: CGFloat) {
        if pantheon.lit { pull = 0; pullArmed = false; return }
        let rest = pullRest ?? y
        if pullRest == nil { pullRest = y }
        let p = max(0, y - rest)
        pull = p
        if MontanaCoinSpinner.pullTrigger <= p { pullArmed = true; return }
        guard pullArmed, p < MontanaCoinSpinner.pullTrigger * 0.8 else { return }
        pullArmed = false
        pullReleased = (Date(), MontanaCoinSpinner.angle(forPull: MontanaCoinSpinner.pullTrigger))
        autoMint.fire()
        Task { await refresh() }
        DispatchQueue.main.asyncAfter(deadline: .now() + MontanaCoinSpinner.finish + 0.15) { pullReleased = nil }
    }
    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true
        let result = await Task.detached(priority: .utility) { MTWalletCore.read() }.value
        loading = false
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let w): MontanaP2PTrace.mark("wallet_read", "balance=\(w.balance) notes=\(w.notes) windows=\(w.windows.count) pulse=\(w.pulseRunning ? 1 : 0)")
        case .failure(let why): MontanaP2PTrace.mark("wallet_read", "absent=\(why)")
        }
        state = result
    }
}

/// WHERE COINS COME FROM (the author's word 03.10.2026 16:55 MSK: «make send and top up there»). Nothing is bought here and no
/// coin is made by a tap: the sheet names the three roads that really bring coins -- the money flow of a chat, a person's
/// coins in their chat, the wall's comments -- each in its own line.
/// THE TOP THIRTEEN PEOPLE (the author's word 03.10.2026 22:23 MSK: «in the wallet, under the add-account button, the top
/// thirteen balances by coins, beautifully, with avatars and names, as in a social network»): the person and the pairs that
/// told their balance (MTCoinBoard), each with the face and the name the chats tab draws, the most coins first. A pair whose
/// chat is gone is not drawn.
struct MTCoinTop13: View {
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var board = MTCoinBoard.shared
    @ObservedObject private var top = MTTopNet.shared
    @ObservedObject private var person = MTWalletOwner.shared   // the person of this wallet: the own row follows their card
    var body: some View {
        if top.answered { network } else if let store = ChatStore.live { rows(store).environmentObject(store) } else { rows(nil) }
    }
    /// THE OWN ROW WEARS THE PERSON OF THIS WALLET (the author's word 10.10.2026 12:4x MSK: the wallet keeps no person of its own):
    /// the name their app holds, Montana first, then Business (E2E.myDisplayName asks MTWalletPerson); none found, the word every
    /// nameless row wears -- the same the table shows of this row on every other phone.
    @ViewBuilder private var myName: some View {
        let n = MontanaAvatar.spokenName(E2E.myDisplayName())
        if n.isEmpty {
            Text("No name").font(.body).foregroundStyle(.secondary).lineLimit(1)
        } else {
            // USER-DATA: the person's own name, as their app holds it
            Text(verbatim: n).font(.body).foregroundColor(.white).lineLimit(1)
        }
    }
    /// THE ONE TABLE (the author's word 04.10.2026 05:40 MSK: «everyone has one source of all data»): the rows the nodes keep, the
    /// same on every phone; the person's own row wears their own face, every other row the letter of the name its owner shows.
    private var network: some View {
        let mine = MTTopNet.myRow()
        return ForEach(Array(top.rows.prefix(13).enumerated()), id: \.element.id) { i, r in
            HStack(spacing: 12) {
                // USER-DATA: the place in the table, a number
                Text(verbatim: String(i + 1)).font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                if r.id == mine {
                    MTSelfFace(size: 40)
                    myName
                } else if r.name.isEmpty {
                    AvatarCircle(photoURL: nil, color: .black, initial: "", size: 40, image: nil)
                    Text("No name").font(.body).foregroundStyle(.secondary).lineLimit(1)
                } else if MontanaSafety.filterOn, MontanaContentFilter.flags(r.name) {
                    // A STRANGER'S NAME PASSES THE ONE FILTER (Guideline 1.2, the critic 04.10): the table shows names of people the
                    // person never chose, so the filter over objectionable words folds them as it folds a letter.
                    AvatarCircle(photoURL: nil, color: .black, initial: "", size: 40, image: nil)
                    Text("Hidden by the filter").font(.body).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // The one owner of a face's letter (MontanaAvatar.initial): a glyph put first is the face itself.
                    AvatarCircle(photoURL: nil, color: .black, initial: MontanaAvatar.initial(title: r.name, name: ""), size: 40, image: nil)
                    // USER-DATA: the name its owner shows in the top
                    Text(verbatim: MontanaAvatar.spokenName(r.name)).font(.body).foregroundColor(.white).lineLimit(1)
                }
                Spacer()
                // USER-DATA: the coins the row's owner shows
                Text(verbatim: MTCoinText.count(r.coins)).font(.headline.monospacedDigit())
            }
            .frame(minHeight: 44)
            .listRowBackground(MTGlassRowPlate())
        }
    }
    private func rows(_ store: ChatStore?) -> some View {
        let chats = store?.listChats() ?? []
        let places = Array(board.rating(mine: book.balance).filter { p in p.mine || chats.contains { $0.name == p.id } }.prefix(13))
        return ForEach(Array(places.enumerated()), id: \.element.id) { i, p in
            HStack(spacing: 12) {
                // USER-DATA: the place in the rating, a number
                Text(verbatim: String(i + 1)).font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                if p.mine {
                    HStack(spacing: 12) {
                        MTSelfFace(size: 40)
                        myName
                    }
                } else if let c = chats.first(where: { $0.name == p.id }) {
                    MontanaChatFace(chat: c)
                }
                Spacer()
                // USER-DATA: the coins this person holds, every one of them (the author's word 04.10.2026 03:15 MSK: «the full real balance»)
                Text(verbatim: MTCoinText.count(p.coins)).font(.headline.monospacedDigit())
            }
            .frame(minHeight: 44)
            .listRowBackground(MTGlassRowPlate())
        }
    }
}

/// Where the wallet's coin stands in its list: the pull reads it (MTWalletPage.pulled).
struct MTWalletPullKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A GROUP OF THE HISTORY: the moves of one source, one way and one person within one minute -- one row with their sum and count.
struct MTCoinGroup: Identifiable {
    let id: String
    let source: String
    let first: MTCoinEntry
    var signed: Int
    var count: Int
    let at: Double
    /// The newest groups of the moves given, the newest first, at most this many -- a page, never the whole book.
    static let shown = 60
    static func recent(_ moves: [MTCoinEntry]) -> [MTCoinGroup] {
        var out: [MTCoinGroup] = []
        var last = ""
        for e in moves.reversed() {
            let source = MTTimeChain.source(of: e)
            let key = source + "|" + e.k.rawValue + "|" + (e.peer ?? "") + "|" + String(Int(e.at / 60))
            if key == last, !out.isEmpty {
                out[out.count - 1].signed += e.signed
                out[out.count - 1].count += 1
                continue
            }
            if out.count == shown { break }
            last = key
            out.append(MTCoinGroup(id: key + "#" + String(out.count), source: source, first: e, signed: e.signed, count: 1, at: e.at))
        }
        return out
    }
}

/// A SOURCE'S TOTALS OVER A PERIOD: what came in by it and what went out.
struct MTCoinTotal: Identifiable {
    let source: String
    var into = 0
    var out = 0
    var id: String { source }
    static func of(_ moves: [MTCoinEntry]) -> [MTCoinTotal] {
        var by: [String: MTCoinTotal] = [:]
        for e in moves {
            let s = MTTimeChain.source(of: e)
            var x = by[s] ?? MTCoinTotal(source: s)
            if 0 < e.signed { x.into += e.signed } else { x.out -= e.signed }
            by[s] = x
        }
        return MTTimeChain.sources.compactMap { s in by[s] }
    }
}

/// THE HISTORY'S OWN PAGE (the author's word 04.10.2026 04:02 MSK: «the history as a link button into it, with the choice of the period
/// and the details of the analysis of the history, grouped neatly, on the history's own page»): the platform's segmented choice of the
/// period, each source's coins in and out over it, and the moves grouped by source, way, person and minute -- each group opening
/// its source's TimeChain, where every link stands with its seal.
/// ONE COIN MOVE ON ITS OWN PAGE (the author's word 05.10.2026: «a tap on the coins opens this transaction»): a coin letter's bubble
/// opens the move it made in this phone's book -- the coins, who they came from or went to, the moment -- and the link its TimeChain
/// sealed for it, with the seal and the seal before it.
/// LOCAL AND GLOBAL (the author's word 06.10.2026 16:2x MSK: «a Local TimeChain and a Global TimeChain, in which the hashes are one
/// in the network's consensus by the set»): one transfer stood as link #344 on the receiver's phone and #5 on the sender's -- each
/// phone's own chain, its number and seals its own. The global seal is the letter's (MTLetterSeal): SHA-256 over its one wire name,
/// the one field both phones hold byte for byte, so every device that holds the transfer reads the same seal.
struct MTCoinMoveRoute: Hashable, Identifiable {
    let ref: String
    let mine: Bool
    var id: String { ref }
}
struct MTCoinMovePage: View {
    let route: MTCoinMoveRoute
    let peer: String
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var node = MTNetworkNode.shared
    @State private var link: MTTimeChain.Link?
    @State private var restored: MTTimeChain.Link?   // the system chain's link when the book lost this move and the system restored it
    private var kind: MTCoinEntry.Kind { route.mine ? .send : .receive }
    var body: some View {
        let move = book.entries.last { e in e.ref == route.ref && e.k == kind }
        List {
            if let move {
                Section {
                    LabeledContent("Amount") {
                        // USER-DATA: the coins the move carried, signed by its way
                        Text(verbatim: (route.mine ? "−" : "+") + MTCoinText.count(move.c)).monospacedDigit()
                            .foregroundStyle(route.mine ? Color.primary : Color.green)
                    }
                    LabeledContent(route.mine ? "To" : "From") {
                        // USER-DATA: the person the coins went to or came from
                        Text(verbatim: peer)
                    }
                    LabeledContent("Date") {
                        // USER-DATA: the move's moment on this phone's clock
                        Text(verbatim: Date(timeIntervalSince1970: move.at).formatted(date: .abbreviated, time: .standard))
                    }
                } header: { Text(route.mine ? "Coins sent" : "Coins received") }
                if let link {
                    Section {
                        LabeledContent("Chain link") {
                            // USER-DATA: the link's number in its chain
                            Text(verbatim: "#" + String(link.n)).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seal").font(.subheadline)
                            // USER-DATA: the link's SHA-256 seal
                            Text(verbatim: link.hash).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Previous seal").font(.subheadline)
                            // USER-DATA: the seal of the link before it
                            Text(verbatim: link.prev).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } header: { Text("Local TimeChain") }
                }
                if let seal = MTLetterSeal.seal(route.ref) {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seal").font(.subheadline)
                            // USER-DATA: the letter's SHA-256 seal, the same on every device that holds it
                            Text(verbatim: seal).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        // THIS PHONE IS A NODE (the author's word 06.10.2026 17:2x MSK): how many machines of the genesis -- every
                        // server of ours -- its own node holds a link to, each by a handshake both sides computed.
                        LabeledContent("Network nodes reached") {
                            // USER-DATA: the count of genesis machines this phone's node reached, of all of them
                            Text(verbatim: node.reached.map { n in String(n) + " / " + String(MTNetworkNode.genesis.count) } ?? "—").monospacedDigit()
                        }
                    } header: { Text("Global TimeChain") } footer: { Text("One seal on every device that holds this transfer") }
                }
                if let restored {
                    Section {
                        LabeledContent("Restored by the system") {
                            // USER-DATA: the restoring link's number in the system chain
                            Text(verbatim: "#" + String(restored.n)).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Seal").font(.subheadline)
                            // USER-DATA: the restoring link's SHA-256 seal
                            Text(verbatim: restored.hash).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    } header: { Text("System chain") }
                }
            } else {
                Text("Not in your book yet").foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text("Transaction"))
        .onAppear {
            node.join()
            let ref = route.ref
            MTTimeChain.read(MTTimeChain.source(ref: ref, kind: kind)) { links in link = links.last { l in l.ref == ref } }
            MTTimeChain.read("system") { links in restored = links.last { l in l.ref == MTCoinSend.restorePrefix + ref } }
        }
    }
}

struct MTCoinHistoryPage: View {
    enum Period: String, CaseIterable, Identifiable {
        case hour, day, week, all
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .hour: return "Hour"
            case .day: return "Day"
            case .week: return "Week"
            case .all: return "All time"
            }
        }
        var seconds: Double? {
            switch self {
            case .hour: return 3600
            case .day: return 86400
            case .week: return 604800
            case .all: return nil
            }
        }
    }
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @State private var period: Period = .day
    var body: some View {
        let since = period.seconds.map { s in Date().timeIntervalSince1970 - s } ?? 0
        let moves = book.entries.filter { e in since <= e.at }
        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { p in Text(p.title).tag(p) }
                }
                .pickerStyle(.segmented)
            }
            if moves.isEmpty {
                Text("No coin moves in this period").foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(MTCoinTotal.of(moves)) { x in
                        NavigationLink { MTTimeChainPage(source: x.source) } label: {
                            LabeledContent {
                                VStack(alignment: .trailing, spacing: 2) {
                                    // USER-DATA: the coins that came in by this source over the period
                                    if 0 < x.into { Text(verbatim: "+" + MTCoinText.count(x.into)).foregroundStyle(.green) }
                                    // USER-DATA: the coins that went out by this source over the period
                                    if 0 < x.out { Text(verbatim: "−" + MTCoinText.count(x.out)) }
                                }
                                .font(.body.monospacedDigit())
                            } label: { Text(LocalizedStringKey(MTTimeChainRows.key(x.source))) }
                        }
                    }
                } header: { Text("By source") }
                Section {
                    ForEach(MTCoinGroup.recent(moves)) { g in
                        NavigationLink { MTTimeChainPage(source: g.source) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    // USER-DATA: the source the moves came by
                                    Text(verbatim: MTTimeChainRows.name(g.source)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    // USER-DATA: the coins the group moved, signed
                                    Text(verbatim: (0 < g.signed ? "+" : "") + MTCoinText.count(g.signed)).font(.body.monospacedDigit())
                                        .foregroundStyle(0 < g.signed ? Color.green : Color.primary)
                                }
                                // USER-DATA: where the coins came from and where they went
                                Text(verbatim: MTWalletPage.route(g.first)).font(.caption)
                                HStack {
                                    // USER-DATA: the minute of the group's newest move, on this phone's clock
                                    Text(verbatim: Date(timeIntervalSince1970: g.at).formatted(date: .abbreviated, time: .shortened))
                                    Spacer()
                                    // USER-DATA: how many moves the group holds
                                    Text(verbatim: "× " + String(g.count)).monospacedDigit()
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: { Text("Coin moves") }
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text("History"))
    }
}

/// THE NEXT BOX FILLS AS A LOAD FILLS (the author's word 04.10.2026 03:48 MSK: «while minting, the system's progress bar of this box to
/// the next, as the filling of the next box, thin, as iCloud loads; and under it, in the system's way, how much is left to the next
/// box -- all in the game»): the platform's linear progress from the box the balance fills to the next one, the coins left under it.
struct MTLevelProgress: View {
    let balance: Int
    var body: some View {
        let place = MTPiLevels.place(balance)
        if place < MTPiLevels.all.count {
            let low = 0 < place ? MTPiLevels.all[place - 1] : 0
            let high = MTPiLevels.all[place]
            VStack(spacing: 6) {
                ProgressView(value: Double(balance - low), total: Double(max(1, high - low)))
                    .progressViewStyle(.linear)
                    // THE FILL IS THE SYSTEM'S BLUE (the author's word 04.10.2026 04:22 MSK: «the fill of the minting's progress in the box --
                    // the system's blue, not white as now»): the page's tint is the label colour, so the bar names its own.
                    .tint(.blue)
                    .frame(maxWidth: 240)
                Text("\(MTCoinText.count(high - balance)) coins to level \(place + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// THE PRICE OF A SECOND, FIXED UNDER THE COUNT (the author's words 04.10.2026 17:32 MSK: «put the price of one second under the
/// field of the level's count as a fixed line: 1 second = 13 coins»; ~18:03: «the rate and the question are seen without the
/// Pantheon's game too»): the rate and the link to the form of the person's hour stand always, under the level's count, which
/// shows only while a game mints.
struct MTSecondPrice: View {
    @State private var asking = false
    @AppStorage(MTPersonalRate.key) private var stored = ""
    var body: some View {
        VStack(spacing: 0) {
            Text("1 second = \(MTCoinBook.price) coins").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            // THE PERSON'S RATE UNDER OURS (the author's word 04.10.2026 19:19 MSK, MTPersonalRate): once their earning is told, one
            // coin in their currency stands under the second's price.
            if let word = MTPersonalRate.read(stored) {
                // USER-DATA: one coin in the person's currency, by their own earning
                Text("Your rate: 1 coin = \(MTPersonalRate.coin(word).formatted(.currency(code: word.code).precision(.significantDigits(1...3)).locale(MTLanguage.locale)))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                // THE HOUR, TOLD AND EDITABLE (the author's word 05.10.2026 14:16 MSK: «on the coins page the hour's number is tappable,
                // as the question, and edited; in the style of the rate above the question»): the person's hour in the rate's own
                // type, a tap opens the form of the hour on it.
                Button { asking = true } label: {
                    // USER-DATA: the person's hour in their currency
                    Text("Your hour: \(MTPersonalRate.hourly(word).formatted(.currency(code: word.code).precision(.significantDigits(1...4)).locale(MTLanguage.locale)))")
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            Button("What is Your hour worth Now?") { asking = true }   // the author's words and capitals, 05.10.2026 20:3x MSK
                .font(.footnote).buttonStyle(.borderless).tint(.blue)
                .frame(minHeight: 44).contentShape(Rectangle())
                .sheet(isPresented: $asking) { MTHourWorth() }
        }
    }
}

/// THE APPS THAT MINT, ABOVE THE COIN (the author's word 04.10.2026 18:08 MSK: «above the coin show the icons of the apps that give
/// the minting»): the library's own icons (MTApplicationIcon, in the style chosen in Appearance) of every app whose coins came in
/// the last second and a half (MTCoinFlash.apps). The row keeps its place when none mints -- shown and hidden, never inserted, so
/// the coin never moves under the finger.
struct MTMintingApps: View {
    @ObservedObject private var flash = MTCoinFlash.shared
    var body: some View {
        HStack(spacing: 10) {
            ForEach(flash.apps) { app in MTApplicationIcon(app: app, side: 30).transition(.opacity) }
        }
        .frame(height: 30)
        .animation(.easeInOut(duration: 0.3), value: flash.apps)
        .accessibilityElement(children: .ignore)
        // USER-DATA: the names of the apps minting now, each already in the person's language
        .accessibilityLabel(Text("Minting") + Text(verbatim: " " + flash.apps.map(\.title).joined(separator: ", ")))
        .accessibilityHidden(flash.apps.isEmpty)
    }
}

/// THE LEVEL ON THE COIN AND THE APPS BESIDE IT (the author's word 04.10.2026 18:08 MSK: «on the badge the level's number as now and
/// x2 beside it»): the platform's badge carries the level of π the balance fills and, while two apps or more mint at once, their
/// number after the sign of times -- the count of the icons above the coin (MTMintingApps).
struct MTMintLevelBadge: View {
    let balance: Int
    @ObservedObject private var flash = MTCoinFlash.shared
    var body: some View {
        let place = MTPiLevels.place(balance), apps = flash.apps.count
        let parts = [0 < place ? String(place) : "", 2 <= apps ? "×" + String(apps) : ""]
        // USER-DATA: the level's number and the count of the apps minting at once
        MTCountBadge(word: parts.filter { part in !part.isEmpty }.joined(separator: " "))
    }
}

/// WHAT AN HOUR IS WORTH (the author's word 04.10.2026 17:27 MSK: «under the rate, a link to a separate form asking how much you
/// earn in an hour; when the person enters it, their hour's price gives their currency to the coin's rate»): an hour is 3 600
/// seconds at one coin each (MTCoinBook.price, point 11 as of 05.10.2026), so a coin is the hour's earning over 3 600 -- a second.
/// THE CURRENCY BESIDE THE SUM (the author's word 04.10.2026 18:01 MSK, the form on 2106: «in the field of the sum per hour, at the
/// right, give as a drop-down list all the currency codes to choose, with flags, beautifully, and in the currency's language»): the
/// person's own currency stands first chosen and every currency in use is a choice (MTCurrencyMenu).
/// AN HOUR, A MONTH OR A YEAR (the author's word 04.10.2026 19:19 MSK, the form on 2108: «the field of the hour's worth takes a
/// month and a year too, and sets the personal rate of the coin»): the platform's segments choose the period of the sum, and the
/// sum told becomes the person's rate at once (MTPersonalRate) -- kept on this phone as the person's setting, never sent; an
/// emptied field takes it back.
struct MTHourWorth: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(MTPersonalRate.key) private var stored = ""
    @State private var amount: Decimal?
    @State private var period = MTPersonalRate.Period.hour
    @State private var code = Locale.current.currency?.identifier ?? "USD"
    private let coins = 3600 * MTCoinBook.price
    private var word: MTPersonalRate.Word? {
        amount.flatMap { sum in 0 < sum ? MTPersonalRate.Word(amount: sum, per: period.rawValue, code: code) : nil }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(MTPersonalRate.Period.allCases) { p in Text(p.title).tag(p) }
                    }
                    .pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        TextField(period.field, value: $amount, format: .currency(code: code))
                            .keyboardType(.decimalPad)
                            .id(code)   // the field's format follows the currency chosen
                        MTCurrencyMenu(code: $code)
                    }
                } header: { Text("How much do you earn?") }
                  footer: { if period != .hour { Text("A year of work is 2,080 hours: forty a week") } }
                Section { confirm }.listRowBackground(Color.clear)
                Section {
                    LabeledContent("1 hour") { Text("\(MTCoinText.count(coins)) coins").monospacedDigit() }
                    if let word {
                        LabeledContent("1 coin") { Text(MTPersonalRate.coin(word), format: .currency(code: code).precision(.significantDigits(1...3))) }
                        LabeledContent("1 second") { Text(MTPersonalRate.hourly(word) / 3600, format: .currency(code: code).precision(.significantDigits(1...3))) }
                    }
                } footer: { Text("1 second = \(MTCoinBook.price) coins") }
            }
            .navigationTitle("Your hour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(Text("Close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }.accessibilityLabel(Text("Done"))
                }
            }
            .onAppear {
                guard let told = MTPersonalRate.read(stored) else { return }
                amount = told.amount
                period = MTPersonalRate.Period(rawValue: told.per) ?? .hour
                code = told.code
            }
            .onChange(of: word) { _, new in stored = MTPersonalRate.write(new) }
        }
    }
    /// THE CHECK THAT KEEPS THE HOUR (the author's word 05.10.2026 14:16 MSK: «a confirmation check in our style at the top right
    /// and at the bottom under the question»): the platform's check, no word -- the sum is kept as it is typed (MTPersonalRate),
    /// the check closes the form with it.
    private var confirm: some View {
        Button { dismiss() } label: {
            Image(systemName: "checkmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text("Done"))
    }
}

/// THE PERSONAL RATE OF THE COIN (the author's word 04.10.2026 19:19 MSK: «when the currency's rate is set, add it under the coin
/// under our rate; let the hour's field take a month and a year too; and then set the personal rate of the coin, to build the
/// network rate of each»): what one coin is worth to this person -- their earning over the hours of its period, over the 3 600
/// coins of an hour (MTCoinBook.price) -- in one place on this phone, the person's setting (SeedScope.settingKeys). The network's
/// rate will be gathered from this seam by a design on the author's yes; nothing of it leaves the phone today.
enum MTPersonalRate {
    static let key = "coinRate.personal"   // NOT-UI: the person's earning, its period and its currency
    enum Period: String, CaseIterable, Identifiable {
        case hour, month, year
        var id: String { rawValue }
        /// THE HOURS OF A PERIOD OF WORK: forty hours a week over the fifty-two weeks of a year -- 2 080, the conversion of a yearly
        /// pay to an hourly one in common use -- and a twelfth of that for a month.
        var hours: Decimal {
            switch self {
            case .hour: return 1
            case .month: return Decimal(2080) / 12
            case .year: return 2080
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .hour: return "Hour"
            case .month: return "Month"
            case .year: return "Year"
            }
        }
        var field: LocalizedStringKey {
            switch self {
            case .hour: return "Per hour"
            case .month: return "Per month"
            case .year: return "Per year"
            }
        }
    }
    struct Word: Codable, Equatable { let amount: Decimal; let per: String; let code: String }
    static func read(_ s: String) -> Word? {
        guard let w = try? JSONDecoder().decode(Word.self, from: Data(s.utf8)), 0 < w.amount else { return nil }
        return w
    }
    static func write(_ w: Word?) -> String {
        guard let w, let d = try? JSONEncoder().encode(w) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }
    /// What one hour of this person's work is worth, in the word's currency.
    static func hourly(_ w: Word) -> Decimal { w.amount / (Period(rawValue: w.per) ?? .hour).hours }
    /// What one coin is worth to this person: an hour holds 3 600 seconds of one coin each.
    static func coin(_ w: Word) -> Decimal { hourly(w) / Decimal(3600 * MTCoinBook.price) }
}

/// THE CURRENCIES, AS A DROP-DOWN (the author's word 04.10.2026 18:01 MSK; MTHourWorth): the platform's menu with its inline
/// picker, every currency in use (NSLocale.commonISOCurrencyCodes) a row -- its flag, its code and its name in its own country's
/// language; the chosen one wears the platform's check, and the field's right edge shows its flag and code.
struct MTCurrencyMenu: View {
    @Binding var code: String
    var body: some View {
        Menu {
            Picker("Currency", selection: $code) {
                ForEach(MTCurrency.all) { currency in
                    // USER-DATA: a currency's flag, code and name in its own language, from the system's locale data
                    Text(verbatim: currency.flag + "  " + currency.code + "  " + currency.name).tag(currency.code)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                // USER-DATA: the chosen currency's flag and code
                Text(verbatim: MTCurrency.flag(code) + " " + code).font(.body.monospacedDigit())
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Currency"))
        // USER-DATA: the chosen currency's name in its own language
        .accessibilityValue(Text(verbatim: MTCurrency.name(code)))
    }
}

/// A currency of the list: ISO 4217 gives a national currency the ISO 3166 code of its country for its first two letters, so the
/// country's flag and the language the country speaks most (the platform's likely subtags) come from it; the euro is named in the
/// person's own language under the Union's flag, and a currency of no one country (the X codes) under the globe.
struct MTCurrency: Identifiable {
    let code: String
    let flag: String
    let name: String
    var id: String { code }
    static let all: [MTCurrency] = NSLocale.commonISOCurrencyCodes.sorted().map { code in MTCurrency(code: code, flag: flag(code), name: name(code)) }
    private static let regions = Set(Locale.Region.isoRegions.map(\.identifier))
    private static func region(_ code: String) -> String? {
        let r = String(code.prefix(2)).uppercased()
        return r == "EU" || regions.contains(r) ? r : nil
    }
    static func flag(_ code: String) -> String {
        guard let r = region(code) else { return "🌐" }
        return String(String.UnicodeScalarView(r.unicodeScalars.compactMap { letter in UnicodeScalar(0x1F1E6 + letter.value - 65) }))
    }
    static func name(_ code: String) -> String {
        var own = MTLanguage.locale
        if let r = region(code), r != "EU" { own = Locale(identifier: Locale.Language(identifier: "und-" + r).maximalIdentifier) }
        let n = own.localizedString(forCurrencyCode: code) ?? MTLanguage.locale.localizedString(forCurrencyCode: code) ?? code
        return n.prefix(1).uppercased(with: own) + n.dropFirst()
    }
}

/// THE FIRE'S MINUTE UNDER THE LEVEL (the author's word 04.10.2026 13:38 MSK; MTPantheon.streak): the platform's bar of the unbroken
/// burn to its sixty seconds, and through the rest after it the seconds left -- drawn by the clock, never by the taps, and paused
/// while neither runs; it always stands, shown or hidden, so the coin never moves under the finger.
struct MTPantheonStreak: View {
    @ObservedObject var pantheon: MTPantheon
    var body: some View {
        let active = pantheon.lit || pantheon.restUntil != nil
        TimelineView(.animation(minimumInterval: 0.5, paused: !active)) { t in
            let now = t.date.timeIntervalSince1970
            let rest = pantheon.restUntil.map { max(0, $0 - now) }
            let run = pantheon.litAt.map { min(MTPantheon.streak, max(0, now - $0)) } ?? 0
            VStack(spacing: 6) {
                ProgressView(value: rest ?? run, total: MTPantheon.streak)
                    .progressViewStyle(.linear)
                    .tint(rest == nil ? .orange : .gray)
                    .frame(maxWidth: 240)
                if let rest {
                    Text("Minting rests \(Int(rest.rounded(.up))) s").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("\(Int(run)) of 60 seconds unbroken").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// THE TIMECHAINS ON THE WALLET (the author's word 04.10.2026 00:25 MSK): every source's chain with its length and the first
/// letters of its head, and the platform's seal when every link's seal holds from the genesis -- read again whenever the book moves.
struct MTTimeChainRows: View {
    /// The chains this list names, in the wallet's order (the TimeChain page parts the wallet's own from the chats' and calls').
    var sources: [String] = MTTimeChain.sources
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @State private var heads: [String: MTTimeChain.Head] = [:]
    var body: some View {
        ForEach(sources.filter { 0 < (heads[$0]?.n ?? 0) }, id: \.self) { source in
            if let h = heads[source] {
                NavigationLink { MTTimeChainPage(source: source) } label: {
                LabeledContent {
                    HStack(spacing: 6) {
                        // USER-DATA: the chain's length and the first letters of its head's seal
                        Text(verbatim: String(h.n) + " · " + String(h.hash.prefix(8))).font(.footnote.monospaced()).foregroundStyle(.secondary)
                        Image(systemName: h.whole ? "checkmark.seal.fill" : "xmark.seal.fill").foregroundStyle(h.whole ? .green : .red)
                    }
                } label: { Text(LocalizedStringKey(Self.key(source))) }
                }
            }
        }
        .task(id: book.entries.count) {
            // THE HEADS ARE READ WHEN THE MINTING RESTS (04.10, T1's stalls): a head is a whole chain checked from its genesis, and a coin
            // a tap must not cost thirteen whole readings -- three quiet seconds first, the first reading at once.
            if !heads.isEmpty { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            guard !Task.isCancelled else { return }
            for source in sources { MTTimeChain.head(source) { heads[source] = $0 } }
        }
    }
    /// A source's word in the catalogue, one table for every place that names it: the game or the road its coins came by.
    static func key(_ source: String) -> String {
        switch source {
        case "chess": return "Coins from chess"
        case "pantheon": return "Coins from the Pantheon"
        case "vpnwall": return "Coins from an earlier version"
        case "vpnpay": return "Paid in an earlier version"
        case "timer": return "Timer"
        case "chats": return "Coins from chats"
        case "groups": return "Coins from groups"
        case "channels": return "Coins from channels"
        case "comments": return "Coins for comments"
        case "wall": return "Wall"
        case "received": return "Coins received"
        case "spent": return "Coins on reactions"
        case "pi": return "Levels of π"
        case "person": return "Person"
        case "calls": return "Burned for calls"
        case "letters": return "Burned for letters"
        case "system": return "System chain"
        default: return "Coins sent"
        }
    }
    /// The same word in the person's language, for a line that joins it with others (the history's way).
    static func name(_ source: String) -> String { String(localized: String.LocalizationValue(key(source)), bundle: MTLanguage.bundle) }
    /// A person by their conversation, as the chats tab names them.
    static func who(_ conv: String) -> String {
        guard let store = ChatStore.live, let c = store.listChats().first(where: { $0.name == conv }) else { return String(conv.prefix(10)) }
        return MontanaAvatar.spokenName(store.title(for: c))
    }
}

/// A TIMECHAIN, LINK BY LINK (the author's word 04.10.2026 00:46 MSK: «the detailed timechain»): every link of one source's
/// chain, the newest first -- its number, its moment, the coins, its seal and the seal it stands on, the move's own name -- and
/// whether every seal holds from the genesis.
struct MTTimeChainPage: View {
    let source: String
    @State private var links: [MTTimeChain.Link] = []
    @State private var head: MTTimeChain.Head?
    var body: some View {
        List {
            if let head {
                LabeledContent {
                    Image(systemName: head.whole ? "checkmark.seal.fill" : "xmark.seal.fill").foregroundStyle(head.whole ? .green : .red)
                } label: {
                    // USER-DATA: the chain's length and its head's seal
                    Text(verbatim: String(head.n) + " · " + String(head.hash.prefix(16))).font(.footnote.monospaced())
                }
            }
            ForEach(links.reversed(), id: \.n) { l in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        // USER-DATA: the link's number in its chain
                        Text(verbatim: "#" + String(l.n)).font(.subheadline.monospacedDigit().weight(.semibold))
                        Spacer()
                        // A LEVEL'S LINK NAMES ITS LEVEL (the chain of the person, the levels of π): it moves no coins.
                        if l.k == "level" {
                            Text("Level \(l.c)").font(.body.monospacedDigit())
                        } else if 0 < l.c {
                            // USER-DATA: the coins the link moved, signed by its way; a link of the wall's posts moves none
                            Text(verbatim: (["earn", "receive", "keep"].contains(l.k) ? "+" : "−") + MTCoinText.count(l.c)).font(.body.monospacedDigit())
                        }
                    }
                    // USER-DATA: the link's moment, on this phone's clock
                    Text(verbatim: Date(timeIntervalSince1970: Double(l.at) / 1000).formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                    // USER-DATA: the link's seal and the seal it stands on
                    Text(verbatim: String(l.hash.prefix(16)) + " ← " + String(l.prev.prefix(16))).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    // USER-DATA: the move's own name
                    Text(verbatim: l.ref).font(.caption2.monospaced()).lineLimit(1).truncationMode(.middle).foregroundStyle(.tertiary)
                }
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text(LocalizedStringKey(MTTimeChainRows.key(source))))
        .task {
            MTTimeChain.read(source) { links = $0 }
            MTTimeChain.head(source) { head = $0 }
        }
    }
}

/// THE TIMECHAIN OF THE PERSON (the author's words 10.10.2026 13:4x, 15:2x and 15:4x MSK: «remove the Add account button and put
/// TimeChains in its place»; «the TimeChain, where the first chain of time is the Person, the second the Wallet»; «the third chain
/// of time is chats and calls»; 14:1x: «the whole TimeChain core shown for an external observer»; App, «The chains of time a client
/// shows»): one seed is one person, and what stands beside it is the evidence of its time -- the Global Level the minting keeps
/// while the app is away, the chain of the person, the wallet's chain of π and coins, the chains of the chats and calls, and what
/// an observer checks for themselves.
struct MTTimeChainsPage: View {
    @ObservedObject private var person = MTPersonChain.shared
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var top = MTTopNet.shared
    @ObservedObject private var node = MTNetworkNode.shared
    @State private var core: Result<MTWalletCore.Snapshot, MTWalletCore.Absence>?
    @State private var chainFiles: [URL] = []
    /// The chats' and calls' chains: the third chain of time; every other source is the wallet's own.
    static let talk = ["chats", "groups", "channels", "comments", "wall", "calls", "letters"]
    private static let own = MTTimeChain.sources.filter { s in s != "pi" && !talk.contains(s) }
    private var vectorsHold: Bool { MTPersonChain.levelKAT() && MTTopNet.keyKAT() && MTCoinVault.keyKAT() && MTTimeChainTip.selfCheck() }
    var body: some View {
        let place = MTPiLevels.place(book.balance)
        List {
            Section {
                LabeledContent {
                    // USER-DATA: the Global Level of the person, a number
                    Text(verbatim: String(MTPersonChain.global(person: person.level, balance: book.balance))).font(.title.bold().monospacedDigit())
                } label: { Label("Global level", systemImage: "globe") }
            } footer: { Text("The lower of the two levels below. While the app is minimized, minting goes on at it.") }
            Section {
                LabeledContent("Level") {
                    // USER-DATA: the level of the chain of the person, a number, or a dash below one second
                    Text(verbatim: person.level.map { n in String(n) } ?? "—").monospacedDigit()
                }
                LabeledContent("Time online") {
                    // USER-DATA: the seconds the chain of the person counts, as the system writes a span of time
                    Text(verbatim: Duration.seconds(person.seconds).formatted(.units(allowed: [.days, .hours, .minutes, .seconds], width: .abbreviated)))
                        .monospacedDigit()
                }
                if let n = person.level, n < 62 {
                    let from = Int64(1) << n
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To the next level").font(.subheadline).foregroundStyle(.secondary)
                        ProgressView(value: Double(person.seconds - from), total: Double(from))
                    }
                    .frame(minHeight: 44)
                }
                NavigationLink { MTTimeChainPage(source: "person") } label: {
                    LabeledContent("Chain links") {
                        // USER-DATA: the chain's length and the first letters of its head's seal
                        Text(verbatim: String(person.links.count) + " · " + String((person.links.last?.hash ?? MTTimeChain.genesis).prefix(8)))
                            .font(.footnote.monospaced()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Person", systemImage: "1.circle")
            } footer: {
                Text("A second counts while the wallet stands open on any of your devices and a node answers it — the node's second, never the phone's clock. Each level doubles the seconds of the one before. Shown only to you, published nowhere.")
            }
            Section {
                LabeledContent("Level of π") {
                    // USER-DATA: the level of π the balance fills and π revealed to it
                    Text(verbatim: String(place) + " · π " + MTPiLevels.revealed(place)).monospacedDigit()
                }
                NavigationLink { MTTimeChainPage(source: "pi") } label: { Text("Levels of π") }
                MTTimeChainRows(sources: Self.own)
            } header: {
                Label("Wallet", systemImage: "2.circle")
            } footer: {
                Text("Your balance reveals π: each level opens when the balance reaches the next amount — 3, 31, 314 …")
            }
            Section {
                MTTimeChainRows(sources: Self.talk)
            } header: {
                Label("Chats and calls", systemImage: "3.circle")
            } footer: {
                Text("Chats and calls live in Montana and Montana Business; here stand the chains of the coins they moved.")
            }
            Section {
                LabeledContent("Frozen vectors") {
                    Image(systemName: vectorsHold ? "checkmark.seal.fill" : "xmark.seal.fill").foregroundStyle(vectorsHold ? .green : .red)
                }
                if top.answered {
                    LabeledContent("People who show their coins") {
                        // USER-DATA: how many rows the public table holds, a number
                        Text(verbatim: String(top.rows.count)).monospacedDigit()
                    }
                    LabeledContent("Coins they show") {
                        // USER-DATA: the coins of every row of the public table together, a number
                        Text(verbatim: MTCoinText.count(top.rows.reduce(0) { n, r in n + r.coins })).monospacedDigit()
                    }
                }
                LabeledContent("Genesis machines reached") {
                    // USER-DATA: how many machines of the genesis this phone's node holds a link to, of all of them
                    Text(verbatim: String(node.reached ?? 0) + " / " + String(MTNetworkNode.genesis.count)).monospacedDigit()
                }
                switch core {
                case .success(let w)?:
                    LabeledContent("Confirmed balance", value: w.balance)
                    if let head = w.lastConfirmedWindow {
                        LabeledContent("Last confirmed window", value: String(head))
                    } else {
                        Text("No confirmed window yet").foregroundStyle(.secondary)
                    }
                    LabeledContent("Wallet notes", value: String(w.notes))
                case .failure(let a)?:
                    // USER-DATA: the core's own state, said by the core's reader in the person's language
                    Text(verbatim: MTWalletCore.said(a)).foregroundStyle(.secondary)
                case nil:
                    // USER-DATA: the core's own state, said by the core's reader in the person's language
                    Text(verbatim: MTWalletCore.said(nil)).foregroundStyle(.secondary)
                }
                if !chainFiles.isEmpty {
                    // The chains' own files go through the app's one share sheet (MTShare), raised by the owner of the stack.
                    Button { MTShare.present(chainFiles) } label: { Label("Share the chains", systemImage: "square.and.arrow.up") }
                        .frame(minHeight: 44)
                }
            } header: {
                Text("For an observer")
            } footer: {
                Text("Every link is sealed by SHA-256 over its number, moment, kind, amount, name and the seal before it; the level of the person is bit_length(seconds) − 1 (Canon). Shared chains can be checked link by link anywhere.")
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle("TimeChain")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let read = await Task.detached(priority: .utility) { MTWalletCore.read() }.value
            core = read
            let fm = FileManager.default
            let dir = MTTimeChainPlace.dir()
            chainFiles = ((try? fm.contentsOfDirectory(atPath: dir?.path ?? "")) ?? []).sorted()
                .filter { n in n.hasPrefix("wallet-") && n.hasSuffix(".jsonl") }
                .compactMap { n in dir?.appendingPathComponent(n) }
            MTNetworkNode.shared.join()
        }
    }
}

/// THE PAGE'S NAME STANDS WHOLE ON EVERY SCREEN (the author's word 10.10.2026 15:2x MSK: «make the words Time Coin adaptive, so they
/// always fit any screen fully»): the platform's inline-large title cut the Russian name of the page short beside the bar's two marks on a narrow
/// phone. The name stands at the bar's leading edge in the largest of the platform's title sizes that fits the width the marks
/// leave, down to the headline, which shrinks before it cuts a letter; the platform's own title keeps the name for VoiceOver and
/// the pages pushed over it, and its centre stays empty.
struct MTFittingTitle: ViewModifier {
    let title: LocalizedStringKey
    @Environment(\.mtWindowSize) private var window
    /// The bar's width the name may take: the window's, less the margins, the bar's two marks and the gap between.
    private var room: CGFloat {
        let w = 0 < window.width ? window.width : (UIApplication.shared.connectedScenes.compactMap { s in (s as? UIWindowScene)?.screen.bounds.width }.first ?? 375)
        return max(120, w - 152)
    }
    private var name: some View {
        ViewThatFits(in: .horizontal) {
            Text(title).font(.largeTitle.bold())
            Text(title).font(.title.bold())
            Text(title).font(.title2.bold())
            Text(title).font(.title3.bold())
            Text(title).font(.headline).minimumScaleFactor(0.4)
        }
        .lineLimit(1)
        .frame(maxWidth: room, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) { name }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }.sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .topBarLeading) { name }
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
        }
    }
}

extension View {
    func montanaFittingTitle(_ title: LocalizedStringKey) -> some View { modifier(MTFittingTitle(title: title)) }
}

/// EVERY ROAD OF THE COINS, SAID WHERE THE COINS ARE (the author's words 08.10.2026 02:2x MSK: «everything explicit, crystal clear»;
/// App Review 2.3.1(a)): how coins come and how they go, each rule as the code keeps it -- the Pantheon (MTPantheon), the auto
/// minting (MTWalletPull), the people of the contacts (MTCoinSend.transfer) -- and what the coins are not. THE WALLET'S OWN ROADS
/// ALONE (the author's word 09.10.2026 16:00 MSK: the chats, the calls, the wall and chess left the wallet). One list for the
/// wallet's page and the Top up sheet.
struct MTCoinRules: View {
    var body: some View {
        Label("Tap the coin: every tap mints coins at your level, up to 13 taps a second, and all coins of one second stop at 13 (26 while music plays). The fire burns while you tap, a minute at most, then rests a minute; three seconds without a tap put it out.", systemImage: "flame")
        Label("Pull this page down past the coin, or hold the coin: coins come by themselves every second at your level while this page stays open. Leaving the page or locking the screen stops it.", systemImage: "arrow.down.circle")
        Label("Your level is how many of the amounts 3, 31, 314 … (the digits of π) your balance reaches, at least 1 and at most 13. While your music plays, every amount at your level doubles. All coins made in one second stop at 13 together, 26 while music plays; Money Flow letters and a chess game's pot are outside this limit.", systemImage: "chart.bar")
        Label("A contact sends you coins, and you send yours to a contact.", systemImage: "person.2")
        Label("Coins cannot be bought or sold in the app, and the app exchanges them for no money. An amount shown in a currency is only your own estimate, from the earnings you entered.", systemImage: "info.circle")
    }
}

struct MTCoinTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section { MTCoinRules() }
            }
            .navigationTitle("Top up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
            }
        }
    }
}

/// THE CURRENT BALANCE WHERE COINS LEAVE (the author's word 06.10.2026 22:1x MSK: «when I put a stake in chess or send, always show
/// the current balance»): the coin book's balance, live, under the page's title -- above every row and above the keyboard, written
/// as the platform writes a subtitle (its own on iOS 26, the title's second line before it).
struct MTBalanceTitle: ViewModifier {
    let title: LocalizedStringKey
    @ObservedObject private var book = MTLocalCoinLedger.shared
    static func line(_ coins: Int) -> Text { Text("\(MTCoinText.count(coins)) coins") }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationTitle(title).navigationSubtitle(Self.line(book.balance))
        } else {
            content.navigationTitle(title).toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        Self.line(book.balance).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The same balance as one caption, on the plate of an invitation that asks a stake.
struct MTBalanceCaption: View {
    @ObservedObject private var book = MTLocalCoinLedger.shared
    var body: some View { MTBalanceTitle.line(book.balance).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
}

extension View {
    func montanaBalanceTitle(_ title: LocalizedStringKey) -> some View { modifier(MTBalanceTitle(title: title)) }
}

/// SEND COINS TO PEOPLE (the author's words 03.10 13:53 and 21:53: «in the wallet when sending, everything seen as in the chats'
/// feed; a mass send divides the sum equally»): the pairs' chats in the chats tab's own rows (MontanaChatFace on the glass row
/// plate, the page's own ground), as many as the person picks. The amount is the whole: every picked chat gets an equal share
/// as a coin letter in it (MTCoinSend.transfer), and what does not divide stays with the sender. A short balance refuses
/// before anything leaves.
struct MTCoinSendSheet: View {
    /// The one person the contacts touched (MTWalletContactsPage): first in the list and picked; nil -- the whole list, none picked.
    var to: String? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var board = MTCoinBoard.shared
    @State private var chats: [Chat] = []
    @State private var picked: Set<String> = []
    /// EACH NAME ITS OWN COINS (the author's word 06.10.2026 17:3x MSK: «the field of the coins entered beside the name»): what is
    /// typed beside a chat is what that chat gets; a chat picked with nothing typed takes the box of π last chosen.
    @State private var amounts: [String: String] = [:]
    @State private var chosen = 1
    @State private var refused = false
    @State private var going: [String: Bool] = [:]   // the coins in flight per chat: false while they go, true when the letter stands
    @State private var levelAsked = false
    @State private var levelNone = false   // no contact shows a balance: the press says so instead of doing nothing
    @FocusState private var typing: String?
    private func coins(_ name: String) -> Int { Int(amounts[name] ?? "") ?? 0 }
    private var total: Int { picked.reduce(0) { sum, name in sum + coins(name) } }
    private var ready: Bool { !picked.isEmpty && picked.allSatisfy { name in 0 < coins(name) } }
    var body: some View {
        if let store = ChatStore.live { sheet.environmentObject(store) } else { sheet }
    }
    private var sheet: some View {
        NavigationStack {
            List {
                Section {
                    // THE THIRTEEN BOXES OF π AS THE AMOUNTS SENT (the author's word 03.10 22:02: «when sending, the same thirteen boxes»):
                    // a box chosen stands beside every chat picked.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(MTPiLevels.all, id: \.self) { n in
                                Button { choose(n) } label: {
                                    // USER-DATA: a box of coins, in its short form
                                    Text(verbatim: MTPiLevels.short(n)).font(.subheadline.weight(.semibold).monospacedDigit())
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color(white: chosen == n ? 0.45 : 0.3), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .disabled(book.balance < n)
                                .opacity(book.balance < n ? 0.4 : 1)
                            }
                        }
                    }
                    // A BUTTON IS NEVER DEAD (the author's word 10.10.2026 15:3x MSK: «in the wallet the button Level the top 13 does
                    // not work»): it stood disabled while fewer than two contacts had told a balance -- on T1 none ever had, so it
                    // never answered a press. Now a press always answers: the levelling's question, or the platform's alert saying
                    // that no contact shows a balance and how one comes.
                    Button { if topThirteen.isEmpty { levelNone = true } else { levelAsked = true } } label: {
                        Label("Level the top 13", systemImage: "chart.bar.xaxis.ascending")
                    }
                    .frame(minHeight: 44)
                    if !picked.isEmpty {
                        // USER-DATA: the coins of every picked chat together, a number
                        LabeledContent { Text(verbatim: MTCoinText.count(total)).monospacedDigit() } label: { Text("Total") }
                    }
                }
                .listRowBackground(MTGlassRowPlate())
                Section {
                    if chats.isEmpty {
                        Text("No contacts yet").foregroundStyle(.secondary).listRowBackground(MTGlassRowPlate())
                    } else {
                        ForEach(chats, id: \.name) { c in
                            HStack(spacing: 12) {
                                Button { toggle(c.name) } label: {
                                    HStack(spacing: 12) {
                                        MontanaChatFace(chat: c)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())   // the face and the name are the target, as in the chats tab
                                }
                                .buttonStyle(.plain)
                                // THE FIELD IS THE SYSTEM'S AND IT TAKES THE CARET (the author's word 07.10.2026 18:3x MSK: the amount field beside
                                // the check -- active, the system's, with a blinking cursor): the platform's rounded field, and a chat picked
                                // hands it the keyboard at once.
                                TextField("0", text: field(c.name))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.body.monospacedDigit())
                                    .textFieldStyle(.roundedBorder)
                                    .focused($typing, equals: c.name)
                                    .frame(width: 96, height: 44)
                                Button { toggle(c.name) } label: { MTPickMark(picked: picked.contains(c.name), going: going[c.name]) }
                                    .buttonStyle(.plain)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .listRowBackground(MTGlassRowPlate())
                        }
                    }
                } header: { Text("Choose people") }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .montanaPageGround()
            .montanaBalanceTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // OUR SEND, NOT A CHECK (the author's word 05.10.2026 18:2x MSK: «put our send button»).
                    Button { send() } label: { MTBarRoundMark(ringed: false) { MTTimeSendMark(height: 22) } }
                        .buttonStyle(.plain)
                        .disabled(!ready || !going.isEmpty)
                        .opacity(ready ? 1 : 0.4)
                        .accessibilityLabel(Text("Send"))
                }
            }
            .alert("Not enough coins", isPresented: $refused) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your coin balance is lower than this.") }
            // LEVELLING ASKS FIRST (the author's word 07.10.2026 18:3x MSK: Level the top 13 needs a mandatory confirmation with a
            // description of what happens next): who receives, how much in all and to what level, said before a field changes.
            .alert("Level the top 13?", isPresented: $levelAsked) {
                if !levelPlan().gifts.isEmpty { Button("Level them") { level() } }
                Button("Cancel", role: .cancel) {}
            } message: { levelWords }
            .alert("No balances to level", isPresented: $levelNone) {
                Button("OK", role: .cancel) {}
            } message: { Text("None of your contacts shows their coins yet. A contact's balance appears here once they turn on Show my coins in their wallet.") }
        }
        .onAppear {
            guard let store = ChatStore.live else { return }
            chats = store.listChats().filter { c in MTCoinSend.canPay(c, store: store) }
            if let to, let i = chats.firstIndex(where: { c in c.name == to }) {
                chats.insert(chats.remove(at: i), at: 0)
                toggle(to)
            }
        }
    }
    /// The coins typed beside a chat: digits alone; coins typed pick the chat, a field emptied lets it go.
    private func field(_ name: String) -> Binding<String> {
        Binding(get: { amounts[name] ?? "" }, set: { typed in
            let digits = String(typed.filter(\.isNumber).prefix(15))
            amounts[name] = digits
            if 0 < (Int(digits) ?? 0) { picked.insert(name) } else { picked.remove(name) }
        })
    }
    private func choose(_ n: Int) {
        chosen = n
        for name in picked { amounts[name] = String(n) }
    }
    private func toggle(_ name: String) {
        if picked.contains(name) {
            picked.remove(name)
            amounts[name] = nil
            if typing == name { typing = nil }
        } else {
            picked.insert(name)
            if coins(name) == 0 { amounts[name] = String(chosen) }
            typing = name
        }
    }
    /// The thirteen chats here whose people told the most coins (MTCoinBoard), the most first.
    private var topThirteen: [(name: String, coins: Int)] {
        Array(chats.compactMap { c in board.told[c.name].map { told in (name: c.name, coins: told.coins) } }
            .sorted { a, b in b.coins < a.coins }.prefix(13))
    }
    /// LEVEL THE TOP THIRTEEN (the author's word 06.10.2026 17:3x MSK: «a button to level the top 13»): the poorest of the thirteen
    /// are raised first, every one to one level, toward the richest of them and as far as this book's balance reaches; each gets
    /// its coins beside its name, the richest none, and nothing leaves before the send.
    /// The levelling a press would write, computed for the question and again for the act: the level the balance reaches, who
    /// receives and how much, and the whole of it.
    private func levelPlan() -> (level: Int, gifts: [(name: String, give: Int)], total: Int) {
        let top = topThirteen
        guard let peak = top.first?.coins, let floor = top.last?.coins else { return (0, [], 0) }
        let budget = book.balance
        func fill(_ level: Int) -> Int { top.reduce(0) { sum, p in sum + max(0, level - p.coins) } }
        var low = floor, high = peak
        while low < high {
            let mid = low + (high - low + 1) / 2
            if fill(mid) <= budget { low = mid } else { high = mid - 1 }
        }
        let gifts: [(name: String, give: Int)] = top.compactMap { p in 0 < low - p.coins ? (name: p.name, give: low - p.coins) : nil }
        return (low, gifts, fill(low))
    }
    private var levelWords: Text {
        let plan = levelPlan()
        guard !plan.gifts.isEmpty else {
            return Text("Your top 13 already stand level, or your balance reaches none of them: nothing changes.")
        }
        return Text("\(plan.gifts.count) of your top 13 receive coins, \(MTCoinText.count(plan.total)) in all, each raised to \(MTCoinText.count(plan.level)) coins; the richest receive none. The amounts are written beside their names, and nothing leaves until you send them.")
    }
    private func level() {
        let plan = levelPlan()
        for p in topThirteen {
            if let gift = plan.gifts.first(where: { g in g.name == p.name }) {
                amounts[p.name] = String(gift.give)
                picked.insert(p.name)
            } else {
                amounts[p.name] = nil
                picked.remove(p.name)
            }
        }
        MontanaP2PTrace.mark("coin_level", "top=\(topThirteen.count) level=\(plan.level) total=\(plan.total) balance=\(book.balance)")
    }
    private func send() {
        guard let store = ChatStore.live else { return }
        let to = chats.filter { c in picked.contains(c.name) && 0 < coins(c.name) }
        guard !to.isEmpty, total <= MTCoinBook.ledger.balance else { refused = true; return }
        let each = Dictionary(uniqueKeysWithValues: to.map { c in (c.name, coins(c.name)) })
        for c in to { going[c.name] = false }
        Task { @MainActor in
            var went: [Chat] = []
            for c in to {
                await Task.yield()   // each ring turns on the screen before its coins go
                if MTCoinSend.transfer(each[c.name] ?? 0, to: c, store: store) { went.append(c); going[c.name] = true } else { going[c.name] = nil }
            }
            MontanaP2PTrace.mark("coin_send_many", "chats=\(to.count) total=\(each.values.reduce(0, +)) went=\(went.count)")
            guard !went.isEmpty else { going = [:]; refused = true; return }
            // THE PAGE LEAVES BY ITSELF (the author's word 05.10.2026 18:2x MSK: «the send page must close and carry into our app to go
            // on; now it hangs on the send page and asks an extra action -- constitution 0»): the closed rings stand a breath, then
            // the page closes onto the wallet -- the wallet holds no chat to open (the author's word 09.10.2026 16:00 MSK).
            try? await Task.sleep(nanoseconds: 450_000_000)
            dismiss()
        }
    }
}

/// THE WALLET'S CONTACTS (the author's word 09.10.2026 16:00 MSK: «the wallet is a wallet, and the contacts in it too»): the
/// people coins can go to, in the send sheet's own rows; a touch opens the send sheet for that one person, never a chat. A person
/// comes in by a username or by a code (the author's choice 08.10.2026: transfers by name and by QR), by the one meeting road.
struct MTWalletContactsPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var people: [Chat] = []
    @State private var paying: MTPageFlag?
    @State private var byName = false
    @State private var byCode = false
    /// The person a name or a code just brought: their send sheet rises once the asking sheet is down.
    @State private var met: String?
    var body: some View {
        if let store = ChatStore.live { page.environmentObject(store) } else { page }
    }
    private var page: some View {
        NavigationStack {
            List {
                Section {
                    if people.isEmpty {
                        Text("No contacts yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(people, id: \.name) { c in
                            Button { paying = MTPageFlag(id: c.name) } label: {
                                HStack(spacing: 12) {
                                    MontanaChatFace(chat: c)
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())   // the whole row is the target
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(MTGlassRowPlate())
            }
            .scrollContentBackground(.hidden)
            .montanaPageGround()
            .navigationTitle("Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { byName = true } label: { Label("By username", systemImage: "at") }
                        Button { byCode = true } label: { Label("Scan code", systemImage: "qrcode.viewfinder") }
                    } label: {
                        MontanaBarGlyph(glyph: "person.badge.plus")
                            .montanaOctagonFace(square: true, bar: true, height: MontanaOctagon.composeHeight, mark: true)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Add contact"))
                }
            }
            .sheet(item: $paying, onDismiss: read) { p in MTCoinSendSheet(to: p.id) }
            .sheet(isPresented: $byName, onDismiss: payMet) {
                StartByNameView { ref in met = ref; byName = false }
            }
            .sheet(isPresented: $byCode, onDismiss: payMet) {
                NavigationStack {
                    ScanMeetingView { ref in met = ref; byCode = false }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { byCode = false } } }
                }
                .preferredColorScheme(.dark)
            }
        }
        .onAppear { read() }
    }
    private func read() {
        guard let store = ChatStore.live else { return }
        people = store.listChats().filter { c in MTCoinSend.canPay(c, store: store) }
    }
    /// The asking sheet is down: the person it brought gets their send sheet at once.
    private func payMet() {
        read()
        guard let ref = met else { return }
        met = nil
        paying = MTPageFlag(id: ref)
    }
}

/// WHOM THE COINS GO TO BY THEMSELVES (MTAutoReact, the author's word 06.10.2026 17:3x MSK: «on a long press, open a page where I
/// choose whom and how much I want to auto-react to, from my contacts»): the person's chats, each with the coins its every new
/// letter is paid, typed beside the name; an emptied field lets the person go. What is typed stands at once.
struct MTAutoReactPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var chats: [Chat] = []
    @State private var amounts: [String: String] = [:]
    var body: some View {
        if let store = ChatStore.live { page.environmentObject(store) } else { page }
    }
    private var page: some View {
        NavigationStack {
            List {
                Section {
                    if chats.isEmpty {
                        Text("No chats yet").foregroundStyle(.secondary).listRowBackground(MTGlassRowPlate())
                    } else {
                        ForEach(chats, id: \.name) { c in
                            HStack(spacing: 12) {
                                MontanaChatFace(chat: c)
                                Spacer(minLength: 0)
                                TextField("0", text: field(c.name))
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.body.monospacedDigit())
                                    .textFieldStyle(.roundedBorder)   // one field of coins everywhere: the system's (07.10.2026)
                                    .frame(width: 96, height: 44)
                            }
                            .listRowBackground(MTGlassRowPlate())
                        }
                    }
                } header: { Text("Coins on each new letter") } footer: {
                    Text("Paid by itself as a reaction on every letter the person writes from now on, while your coins last.")
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .montanaPageGround()
            .navigationTitle("Auto-reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } } }
        }
        .onAppear {
            guard let store = ChatStore.live else { return }
            chats = store.listChats().filter { c in MTCoinSend.canPay(c, store: store) }
            for c in chats { if let r = MTAutoReact.rule(c.name) { amounts[c.name] = String(r.coins) } }
        }
    }
    private func field(_ name: String) -> Binding<String> {
        Binding(get: { amounts[name] ?? "" }, set: { typed in
            let digits = String(typed.filter(\.isNumber).prefix(12))
            amounts[name] = digits
            MTAutoReact.set(name, coins: Int(digits) ?? 0)
        })
    }
}

/// THE PICK AND THE FLIGHT, AS THE PLATFORM'S OWN SHARING DRAWS THEM (the author's word 05.10.2026 18:2x MSK: «the right check marks
/// of the choice, the sending with the system's rings as AirDrop, natively»): the platform's circle and its filled check in the
/// system's blue; while the coins go, the system's ring turns in its place, and it closes into the check when the coin letter
/// stands in the chat (MTCoinSend.transfer answered) -- the ring says what is true, never a drawn progress.
struct MTPickMark: View {
    let picked: Bool
    let going: Bool?   // nil: nothing sent; false: the coins go; true: the letter stands in the chat
    var body: some View {
        ZStack {
            if going == false {
                ProgressView().progressViewStyle(.circular).tint(MontanaOctagon.platformBlue)
            } else if picked || going == true {
                Image(systemName: "checkmark.circle.fill").symbolRenderingMode(.palette)
                    .foregroundStyle(.white, MontanaOctagon.platformBlue)
            } else {
                Image(systemName: "circle").foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .font(.title2)
        .frame(width: 30, height: 30)
        .animation(.easeOut(duration: 0.2), value: going)
    }
}
