import SwiftUI
import SafariServices
import Combine

struct MTWalletPage: View {
    @Environment(\.montanaClose) private var close
    @Environment(\.scenePhase) private var phase
    @Environment(UIState.self) private var ui
    @State private var windows = MTBoard.MTWallWindowList()
    /// THE COIN BOOK (the author's word 03.10 13:52): the balance, the moves and the history all read the one ledger.
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var pantheon = MTPantheon.shared
    @ObservedObject private var autoMint = MTWalletPull.shared
    @ObservedObject private var vault = MTCoinVault.shared
    @ObservedObject private var tipNet = MTTimeChainTip.shared
    @ObservedObject private var coinSplit = MTCoinSplit.shared   // the balance as its chain holds it, proven and declared
    @AppStorage(MTCoinShow.key) private var coinsShown = true   // the owner's switch (Privacy), read here for the table's line
    @AppStorage(MTPersonalRate.key) private var personalRate = ""   // the person's own rate of the coin, for the balance in their currency
    @AppStorage(MTCoinUnit.mainKey) private var mainUnit = MTCoinUnit.time   // the sum the person made the main one, time by default
    @State private var sending = false
    @State private var toppingUp = false
    @State private var levelsShown = false
    @State private var chainsShown = false
    @State private var historyShown = false
    @State private var analyticsShown = false
    @State private var topOpen = true   // the Top 13 folds away and opens again (the author's word 12.10.2026 10:1x UTC)
    /// THE COIN TURNS ONCE (the author's word 03.10.2026 13:55 UTC: «the coin makes one turn at the opening and at a tap»).
    @State private var coinTurn = 0
    /// The touches of the coin that minted, each its rising +1 until it fades (MTRisingPlus).
    @State private var pops: [MTTapPop] = []
    /// THE PULL OF THE PAGE (MTWalletPull): where the coin stands at rest in the list, how far it is drawn, whether it passed the
    /// coin's trigger, and the round the coin completes after the letting go.
    @State private var pullRest: CGFloat?
    @State private var pull: CGFloat = 0
    @State private var pullArmed = false
    @State private var pullReleased: (at: Date, angle: Double)?
    /// THE PERSON'S COINS ARE THE CHAIN'S (fold-7; the author's words 23.10.2026 00:27 UTC: «the phone only mirrors the chain»): once the
    /// chain has spoken in this run, the available it holds (MTCoinSplit.available); before it, every coin the book holds, and before
    /// the seed's book lands, the balance a device of the same words told in its tip (04.10 16:34).
    /// THE SECONDS BEFORE THE WINDOW IS FINALIZED RISE ON THE PAGE (the author's words 26.10.2026 09:2x UTC, links 8615 and 8617): the
    /// Time Balance is the available and the person's seconds on their way to the chain (MTCoinSplit.growing), so it moves every second
    /// while the person is here; the line Available beneath stays what the chain holds, and Send is weighed by that alone.
    private var total: Int {
        if coinSplit.split != nil { return coinSplit.growing }
        return vault.heard ? book.balance : max(book.balance, tipNet.seen ?? 0)
    }
    private var spendable: Int { coinSplit.split != nil ? coinSplit.available : total }
    /// One of the three sums of the balance: the main one large and white, the others small; the whole row takes the finger and
    /// makes its sum the main one.
    private func balanceSum(_ unit: MTCoinUnit) -> some View {
        let main = unit == mainUnit
        return Button { withAnimation(.snappy) { mainUnit = unit } } label: {
            unit.balance(total)
                .font(main ? .system(size: 48, weight: .bold).monospacedDigit() : .subheadline.monospacedDigit())
                .foregroundStyle(main ? .white : .secondary)
                .lineLimit(1).minimumScaleFactor(main ? 0.3 : 0.5)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(main ? .isSelected : [])
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
                        // THE PAGE DOES NOT MOVE UNDER THE GAME (the author's word 04.10.2026 01:21 UTC, T2: «why does the wallet's page pull
                        // so; during the Pantheon on Fire the page must not move»): the name, the speed and the box's bar keep their places
                        // whether the game burns or not -- shown and hidden, never inserted, so the coin never moves under the finger.
                        // THE NAME STANDS ALWAYS AND BURNS WHILE THE GAME BURNS; THE WHOLE RULES STAND ON THE PAGE BELOW (MTCoinRules, the
                        // author's words 07.10.2026 23:2x UTC, «crystal clear»; App Review 2.3.1(a)).
                        Label {
                            Text("Pantheon on Fire")
                        } icon: {
                            Image(systemName: "flame.fill").symbolRenderingMode(.multicolor)
                        }
                        .font(.title2.bold())
                        .shadow(color: .orange.opacity(pantheon.lit ? 0.8 : 0), radius: 8)
                        // NO CAPTION UNDER THE NAME (the author's word 19.10.2026 14:4x UTC: «on the Time Coins page remove the words
                        // hold 9 seconds»): the hold still starts the auto minting; the rules behind Top up say it (MTCoinRules).
                        // THE APPS THAT MINT, ABOVE THE COIN (the author's word 04.10.2026 15:08 UTC): their icons, the row kept in its place.
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
                            // THE COIN AND A LITTLE PAST ITS RIM (the author's word 04.10.2026 00:13 UTC: «the tap area only on the coin and a
                            // little wider than its border»): the pad reaches past the coin's frame by its rim; the rising capsule stands
                            // where the finger touched, in the coin's own frame.
                            MTCoinTapPad(locked: pantheon.lit, onDown: { pantheon.touched() }, onUp: { pantheon.released() },
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
                        // THE BOX ON THE COIN (the author's word 04.10.2026 00:07 UTC: «the box's level as a badge on the coin in the wallet»):
                        // the number of the level of π the balance fills -- the minting's multiplier -- as the platform's badge, at the coin's rim,
                        // and the number of the apps minting at once beside it (MTMintLevelBadge, the author's word 04.10.2026 15:08 UTC).
                        .overlay(alignment: .topTrailing) { MTMintLevelBadge(balance: total).offset(x: -8, y: 8).allowsHitTesting(false) }
                        // THE COIN CATCHES FIRE AT THE TAPS (the author's word 04.10 00:19): its glow grows with the speed and dims to embers
                        // between the taps while the game burns.
                        // THE GLOW IS A STILL CIRCLE UNDER THE COIN (the author's word 04.10.2026 09:27 UTC, the heat of the minting): a
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
                        // NO COUNT OF THE TAPS UNDER THE COIN (the author's word 19.10.2026 14:4x UTC: «at taps and swipes on the coin do
                        // not show 13/13 below; leave the taps, at most +1 a second»): a tap mints the second's one coin at most
                        // (MTPantheon.tap, MTLocalCoinLedger.priced) and its +1 rises only when it minted.
                        MTLevelProgress(balance: total)
                            .opacity(pantheon.lit || autoMint.on ? 1 : 0)
                            .accessibilityHidden(!(pantheon.lit || autoMint.on))
                        MTSecondPrice()
                        MTPantheonStreak(pantheon: pantheon)
                            .opacity(pantheon.lit || pantheon.restUntil != nil ? 1 : 0)
                            .accessibilityHidden(!(pantheon.lit || pantheon.restUntil != nil))
                        // USER-DATA: the coin book's balance, a number
                        // Until the book lands, the balance a device of the same words told in its tip (MTTimeChainTip, 04.10 16:34).
                        // THE TICKER BESIDE THE BALANCE (the author's word 04.10.2026 14:31 UTC: «to the right of the amount, exactly the
                        // balance's size and style»; MTCoinBook.ticker, point 12): one text under one font, one line that narrows to fit.
                        // THE TOTAL IS THE BOOK'S, THE AVAILABLE THE NETWORK'S (the author's words 12.10.2026 12:5x UTC: «the total balance must
                        // always grow with the minting and show everything, and the available depends on the network and the confirmed --
                        // everything at once»; «the minting has its own chain of time, and as it is confirmed it releases the available, never
                        // holding back the credits of transfers»). T1 at 12:44:25Z: a transfer of 100 000 credited, and the figure -- then the
                        // chain's fold -- stood still. The figure is every coin the book holds, minted and received by every road; under it the
                        // part the person's chain on the network holds for its one owner (MTCoinSplit.available), and nothing more.
                        // THE TIME BALANCE (the author's words 19.10.2026 14:2x UTC: «the time on the Time Coins page white and large, as in
                        // the film In Time -- seconds, minutes, days and so on; the transfer by the fact of the coins, Montana, TCM»; 14:4x:
                        // «in 2250 I want to see Time Balance, and below it in a small font the TCM»; 14:44: «the rate is exactly 1 Coin =
                        // 0.000000001 TCM = 1 second; white and large the Time Balance, below it in Coins, and in transfers and everywhere in
                        // the TimeChain both the time and the coins»): a coin is a second (the constitution, article 11), so the figure is the
                        // time the book holds; the coins under it are what a transfer moves -- coins, never TCM (a TCM is a billion of them).
                        Text("Time Balance").font(.subheadline).foregroundStyle(.secondary)
                        // THE MAIN SUM BY THE PERSON'S TAP (the author's words 19.10.2026 17:4x UTC: «at a tap on the coins or on $TCM show
                        // it as the main currency, the user's choice on the page -- of the 3, the one you tap becomes the main, large and
                        // white, and by default the Time Balance in units of time»; «leave the words Time Balance, and the tap area of the
                        // kind of balance right, native, system, so it switches easily»): the three are one count read three ways
                        // (MTCoinUnit); the chosen stands large under the words, the other two small beneath, each a whole row's button.
                        balanceSum(mainUnit)
                        ForEach(MTCoinUnit.allCases.filter { $0 != mainUnit }) { balanceSum($0) }
                        // THE SEED'S BOOK IS ON ITS WAY (the author's word 04.10.2026 12:51 UTC: «I log in on T3 by T1's seed and see my
                        // balance»): a device restored by its words says it is gathering until the nodes answer, never a balance of nothing.
                        if !vault.heard, book.balance == 0 || tipNet.seen != nil {
                            ProgressView("Gathering your coins").controlSize(.small).font(.footnote)
                        }
                        // THE AVAILABLE, AND NOTHING MORE BENEATH (the author's word 16.10.2026 14:19 UTC: «on the coins page do not show
                        // below Proven, Declared, More wait to be minted -- it is enough to show how much is available with one owner»):
                        // the one number every transfer page shows and weighs by (MTCoinSplit.available).
                        // USER-DATA: the coins the person's chain holds for its one owner, the spendable part of the total
                        Text("Available \(MTCoinText.count(coinSplit.available))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        // THE BALANCE IN THE PERSON'S CURRENCY (the author's word 04.10.2026 21:25 UTC: «under the line of the coins in
                        // Montana, above the level of π, the wallet's balance in the chosen currency at the person's rate»): the balance
                        // times one coin's worth by their own earning (MTPersonalRate), once that earning is told.
                        if let word = MTPersonalRate.read(personalRate) {
                            // USER-DATA: the balance in the person's currency at their own rate
                            Text(MTPersonalRate.coin(word) * Decimal(total), format: .currency(code: word.code).locale(MTLanguage.locale))
                                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // THE WALLET'S LEVEL IS π AS FAR AS THE BALANCE REVEALS IT (the author's word 04.10 00:51): the level and π to it.
                        // USER-DATA: the level of π the balance fills and π revealed to it
                        Text(verbatim: "π " + MTPiLevels.revealed(MTPiLevels.place(total)) + " · " + String(MTPiLevels.place(total)))
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
                            .disabled(spendable <= 0)
                            Button { toppingUp = true } label: {
                                Label("Top up", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(MontanaOctagon.platformBlue)
                        // THE TIMECHAIN IN PLACE OF A SECOND ACCOUNT (the author's words 10.10.2026 10:4x and 12:2x UTC: «remove the Add
                        // account button and put TimeChains in its place»; «the TimeChain, where the first chain of time is the Person,
                        // the second the Wallet»; App, «The chains of time a client shows»): one seed is one person, and what stands
                        // beside it is the evidence of its time.
                        // Carried into Montana by the author's word 11.10.2026 12:2x UTC, «and make everything there correct» (MTTimeChainsPage).
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
                        // THE HISTORY UNDER THE LEVELS OF π (the author's word 12.10.2026 10:1x UTC: «under the button Levels of Pi put the
                        // button History on the page of the Time Coins»): the one door to the history of operations (MTCoinHistoryPage).
                        Button { historyShown = true } label: {
                            Label("History", systemImage: "clock.arrow.circlepath").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(MontanaOctagon.platformBlue)
                        // THE ANALYTICS BY ITS OWN BUTTON (the author's word 12.10.2026 12:2x UTC: «make the analytics a separate button, so it
                        // opens and nothing lags»): under the History -- the months, the spending and the income, where the coins came from and
                        // went (MTCoinAnalyticsPage), read from the one fold of the history.
                        Button { analyticsShown = true } label: {
                            Label("Analytics", systemImage: "chart.pie").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
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
                Section { DisclosureGroup(isExpanded: $topOpen) { MTCoinTop13() } label: { Text("Top 13").font(.headline) } } footer: {
                    if coinsShown { Text("Your name and coins are shown to everyone in the Montana top. Privacy settings turn it off.") }
                    else { Text("You are not in the Montana top. Privacy settings turn it on.") }
                }
                // EVERY ROAD OF THE COINS STANDS BEHIND TOP UP (the author's word 11.10.2026 17:2x UTC: «take the canvas of the ways of
                // minting off the coins' page onto the Top up button»): the page keeps the coin, the balance and its buttons; Top up opens
                // the whole list (MTCoinTopUpSheet, MTCoinRules). The chains moved to the TimeChain page, the wallet's second chain (10.10.2026).
                // THE WALL'S MINTING STANDS ON THE WALLET (the author's word 02.10 15:28): the rights the comment windows hold,
                // beside the confirmed balance and never added into it -- only the core turns a right into a note.
                Section {
                    LabeledContent("Minting now", value: String(windows.filter(\.open).reduce(0) { $0 + $1.share }))
                    LabeledContent("Rights from the wall", value: String(windows.reduce(0) { $0 + $1.share }))
                    // THE CHATS' COINS (the author's word 02.10 19:37): one coin for every letter of a chat in the ribbon of time,
                    // live. LOCAL TALLY, NOT MINTING -- counted on this phone, never added into the confirmed balance (MTChatMint).
                    // ONE BOOK (the author's word 03.10 13:53): every row reads the coin ledger, the chats' coins included.
                    LabeledContent {
                        // USER-DATA: a number, the coins the chats earned
                        Text(verbatim: MTCoinText.count(book.earned)).monospacedDigit()
                    } label: { Text("Coins from chats") }
                    LabeledContent {
                        // USER-DATA: a number, the coins the Pantheon on Fire's taps minted
                        Text(verbatim: MTCoinText.count(book.tapped)).monospacedDigit()
                    } label: { Text("Coins from the Pantheon") }
                    LabeledContent {
                        // USER-DATA: a number, the coins of chess: the moves, the sums won and given up (MTChessCoins)
                        Text(verbatim: MTCoinText.count(book.played)).monospacedDigit()
                    } label: { Text("Coins from chess") }
                    LabeledContent {
                        // USER-DATA: a number, the coins the VPN wall's seconds minted (MTVPNWallMint)
                        Text(verbatim: MTCoinText.count(book.walled)).monospacedDigit()
                    } label: { Text("Coins from the VPN Wall") }
                    .task { MTVPNWallMint.shared.count() }   // the wallet opened: the wall's seconds since the last count are paid
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
                    LabeledContent {
                        // USER-DATA: a number, the coins given on letters and posts
                        Text(verbatim: MTCoinText.count(book.spent)).monospacedDigit()
                    } label: { Text("Coins on reactions") }
                    LabeledContent {
                        // USER-DATA: a number, the balance in Montana (one coin is 0.000000001)
                        Text(verbatim: MTChatMint.montana(total)).monospacedDigit()
                    } label: { Text("Coins in Montana") }
                } header: { Text("Minting") }
                  footer: { Text("Coins are counted on this phone until the wallet opens.") }
                // THE TIMECHAIN STANDS BEHIND ITS BUTTON, NOT UNDER THE PAGE (the author's word 12.10.2026 12:2x UTC: «remove the TimeChain's
                // description from the bottom of the Time Coins page, it is behind the button already»): the core's confirmed balance, its
                // last window and its notes stand on the TimeChain page («For an observer», MTTimeChainsPage), the wall's chains among the
                // chains of chats and calls; this page reads the core no more at every opening.
            }
            .scrollContentBackground(.hidden).montanaPageGround()
            .overlay { MTCoinSides() }   // the coins rise at the sides at every minting (MTCoinFlash, 04.10)
            // THE PAGE STANDS WHILE THE PANTHEON BURNS (the author's words 03.10 21:51 and 04.10 00:13 UTC: «when I tap the coin, switch the
            // wallet's scroll off»; «while it is on I do not want to see scrolling at all»): no scroll from the first tap until the fire
            // goes out after three quiet seconds (MTPantheon.quiet); the coin's own touch locks the page even before its first coin.
            .scrollDisabled(pantheon.lit)
            // THE MINI PLAYER STANDS ON THE COINS PAGE TOO (the author's word 04.10.2026 21:50 UTC): the same bar as the chats' and a
            // person's page, by reference; its taps leave the wallet for the music or the letter by the one road.
            .safeAreaInset(edge: .bottom) {
                MontanaPlayerBar(onPlace: { t in close?(); ui.askMusic(); MTMusicFocus.shared.show(t) },
                                 onSearch: { close?(); ui.askMusic() },
                                 onGoTo: { c, f in
                    close?()
                    NotificationCenter.default.post(name: .montanaGoToLetter, object: nil, userInfo: ["chat": c, "file": f])
                })
            }
            .navigationTitle("TimeCoin")
            // THE TITLE AT THE LEFT, THE CROSS IN THE RIGHT CORNER (the author's word 04.10.2026 10:34 UTC: «align the word Wallet to
            // the left, it goes past the borders; take the refresh button out of the right corner and put the closing cross there»):
            // the platform's large title inline at the bar's leading edge, one mark on the bar -- the page reads itself again by its
            // pull, the coin (pulled).
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(isPresented: $chainsShown) { MTTimeChainsPage() }
            .navigationDestination(isPresented: $historyShown) { MTCoinHistoryPage() }
            .navigationDestination(isPresented: $analyticsShown) { MTCoinAnalyticsPage() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { MontanaBarMark(glyph: "xmark", label: "Close") { close?() } }
            }
            .coordinateSpace(.named("walletList"))
            .onPreferenceChange(MTWalletPullKey.self) { y in pulled(y) }
            // THE COIN IN THE PULL (the author's words 04.10.2026 00:19-00:56 UTC: «pulling the wallet's page brings our coin, as the
            // time panel does»): the time panel's own coin (MontanaCoinSpinner) turns with the pull; let go past its trigger, it mints
            // and reads the page again (pulled). The platform's spinner is not drawn: the coin is the refresh.
            .overlay(alignment: .top) {
                if MontanaCoinSpinner.pullStart < pull || pullReleased != nil {
                    MontanaCoinSpinner(pull: pull, released: pullReleased).padding(.top, 8).allowsHitTesting(false)
                }
            }
            .sheet(isPresented: $sending) { MTCoinSendSheet() }
            .environment(\.mtBalanceAlreadyVisible, true)
            .sheet(isPresented: $toppingUp) { MTCoinTopUpSheet() }
            .sheet(isPresented: $levelsShown) { MTPiLevelsSheet() }
        }
        .tint(.primary)
        // THE BOTTOM EDGE STAYS THE WALLET'S (T1 04.10 09:45:49 UTC: a minting swipe landed on the home indicator at y=911 -- the
        // lowest of 85 touches -- and the system took the app home; the author's word: «I did not do that»): the system's swipe at
        // the bottom edge waits for a second stroke here, as a game asks of it.
        .defersSystemGestures(on: .bottom)
        .task { await refresh() }
        // THE AUTO MINTING IS ON BY DEFAULT (the author's word 09.10.2026 17:1x UTC: "in every app the auto minting automatically,
        // by default"): the page standing open mints by the second without a pull or a hold; leaving the page or locking the
        // screen still ends it (MTWalletPull), and the return to the page or to the app begins it again.
        .onAppear { if !pantheon.lit { autoMint.fire() }; MTCoinHistory.shared.warm() }   // the history's fold is ready before its door
        // THE TOP IS A LIVE SET FROM THE NODES (the author's words 04.10.2026 00:03 and 01:19 UTC: «a live set as by a web socket, the
        // update instant from the nodes»): while the wallet stands open the pairs' last words are asked of the nodes every three
        // seconds in one question -- their balances ride them (E2E.coinTail); a pair in the app hands its own over at once.
        .task {
            UserDefaults.standard.set(true, forKey: MTCoinShow.toldKey)
            await MTTimeChainTip.shared.gather(why: "wallet")   // the other devices' tips in one round trip (04.10 16:34)
            await MTCoinVault.shared.gather(why: "wallet")   // the seed's book first: the row tells what the seed holds (04.10)
            await MTCoinTx.scan(why: "wallet")   // the transfers' records of every pipe, whatever build sent them (MTCoinTx)
            MTTopNet.shared.put()
            var turn = 0
            while !Task.isCancelled {
                await MontanaWakePush.sweepPresence(quiet: true)
                await MTTopNet.shared.read()   // the one table, the same on every phone
                // THE SEED'S OTHER DEVICES SWING IN (the author's word 04.10.2026 12:51 UTC: «check the sync over the network as a
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
            // THE LOCK ENDS IT, NOT A GLANCE (the author's word 04.10.2026 21:53 UTC): the screen locked or the app left goes to the
            // background; a banner or the Control Center pulled down only makes the scene inactive, and the minting goes on.
            if new == .active { Task { await refresh() }; if !pantheon.lit { autoMint.fire() } } else if new == .background { autoMint.stop(why: "background") }
        }
        .onDisappear { autoMint.stop(why: "page"); pantheon.released() }
        // the page's own beat: the seconds on their way rise once a second, with the +1 of the minting (MTCoinSplit.beat)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in coinSplit.beat() }
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
    /// The wall's windows read again: the minting rows stand on them (the core's own state lives on the TimeChain page).
    @MainActor private func refresh() async {
        windows = MTBoard.shared.wallWindows()
    }
}

/// WHERE COINS COME FROM (the author's word 03.10.2026 13:55 UTC: «make send and top up there»). Nothing is bought here and no
/// coin is made by a tap: the sheet names the three roads that really bring coins -- the money flow of a chat, a person's
/// coins in their chat, the wall's comments -- each in its own line.
/// THE TOP THIRTEEN PEOPLE (the author's word 03.10.2026 19:23 UTC: «in the wallet, under the add-account button, the top
/// thirteen balances by coins, beautifully, with avatars and names, as in a social network»): the person and the pairs that
/// told their balance (MTCoinBoard), each with the face and the name the chats tab draws, the most coins first. A pair whose
/// chat is gone is not drawn.
struct MTCoinTop13: View {
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number of the person's coins (fold-7)
    @ObservedObject private var board = MTCoinBoard.shared
    @ObservedObject private var top = MTTopNet.shared
    var body: some View {
        if top.answered { network } else if let store = ChatStore.live { rows(store).environmentObject(store) } else { rows(nil) }
    }
    /// THE ONE TABLE (the author's word 04.10.2026 02:40 UTC: «everyone has one source of all data»): the rows the nodes keep, the
    /// same on every phone; the person's own row wears their own face, every other row the letter of the name its owner shows.
    private var network: some View {
        let mine = MTTopNet.myRow()
        return ForEach(Array(top.rows.prefix(13).enumerated()), id: \.element.id) { i, r in
            HStack(spacing: 12) {
                // USER-DATA: the place in the table, a number
                Text(verbatim: String(i + 1)).font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                if r.id == mine {
                    MTSelfFace(size: 40)
                    // USER-DATA: the person's own name
                    Text(verbatim: MontanaAvatar.spokenName(E2E.myDisplayName())).font(.body).foregroundColor(.primary).lineLimit(1)
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
                    Text(verbatim: MontanaAvatar.spokenName(r.name)).font(.body).foregroundColor(.primary).lineLimit(1)
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
        let places = Array(board.rating(mine: split.available).filter { p in p.mine || chats.contains { $0.name == p.id } }.prefix(13))
        return ForEach(Array(places.enumerated()), id: \.element.id) { i, p in
            HStack(spacing: 12) {
                // USER-DATA: the place in the rating, a number
                Text(verbatim: String(i + 1)).font(.headline.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                if p.mine {
                    HStack(spacing: 12) {
                        MTSelfFace(size: 40)
                        // USER-DATA: the person's own name
                        Text(verbatim: MontanaAvatar.spokenName(E2E.myDisplayName())).font(.body).foregroundColor(.primary).lineLimit(1)
                    }
                } else if let c = chats.first(where: { $0.name == p.id }) {
                    MontanaChatFace(chat: c)
                }
                Spacer()
                // USER-DATA: the coins this person holds, every one of them (the author's word 04.10.2026 00:15 UTC: «the full real balance»)
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


/// THE TIME A COUNT OF COINS IS (the constitution, article 11: «1 second -- 1 coin»; the author's word 19.10.2026 14:44 UTC: «in
/// transfers and everywhere in the TimeChain both the time and the coins»): the one owner, written in the app's language.
/// THE UNITS AS PEOPLE COUNT THEM (the author's word 19.10.2026 17:2x UTC: «divide the units of time humanly -- second, minute,
/// hour, day, week, month, year, century, epoch»): the spans of MTTimeSpan, each taking what the larger left, a unit at zero
/// unsaid. Split here, never by a calendar, so one count reads the same on every date; the system writes year to second, the
/// catalogue the century and the epoch.
extension MTCoinText {
    static func time(_ coins: Int, signed: Bool = true) -> String {
        var rest = coins.magnitude
        func take(_ span: MTTimeSpan) -> Int {
            let n = rest / UInt(span.seconds)
            rest %= UInt(span.seconds)
            return Int(n)
        }
        let epochs = take(.epoch), centuries = take(.century)
        var c = DateComponents()
        c.year = take(.year)
        c.month = take(.month)
        c.weekOfMonth = take(.week)
        c.day = take(.day)
        c.hour = take(.hour)
        c.minute = take(.minute)
        c.second = Int(rest)
        var parts: [String] = []
        if 0 < epochs { parts.append(String(localized: "\(epochs) ep.", bundle: MTLanguage.bundle)) }
        if 0 < centuries { parts.append(String(localized: "\(centuries) cent.", bundle: MTLanguage.bundle)) }
        if parts.isEmpty || coins.magnitude % UInt(MTTimeSpan.century.seconds) != 0 {
            let f = DateComponentsFormatter()
            f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
            f.unitsStyle = .abbreviated
            f.zeroFormattingBehavior = .dropAll
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = MTLanguage.locale
            f.calendar = calendar
            parts.append(f.string(from: c) ?? String(coins.magnitude))
        }
        let told = parts.joined(separator: " ")
        return signed && coins < 0 ? "−" + told : told
    }
}

/// THE UNIT A SUM IS TYPED IN (the author's word 19.10.2026 17:1x UTC: «when sending, an option to type either time, or coins,
/// or Montana -- a choice, like a currency»): a coin is a second (the constitution, article 11) and a Montana a billion coins, so
/// the three are one count read three ways. The page keeps coins; the field reads and writes the unit chosen -- the time in the
/// span chosen beside it (MTTimeSpan), the Montana with up to nine places after the point.
@MainActor enum MTCoinUnit: String, CaseIterable, Identifiable {
    case time, coins, montana
    nonisolated var id: String { rawValue }
    var title: Text {
        switch self {
        case .time: return Text("Time")
        case .coins: return Text("Coins")
        case .montana: return Text(verbatim: MTCoinBook.ticker)   // USER-DATA: the ticker, as the balance writes it (constitution, article 12)
        }
    }
    /// The sum the person made the main one on the wallet's page (the author's word 19.10.2026 17:4x UTC), a setting of the person.
    nonisolated static let mainKey = "mt.coin.mainUnit"
    /// The whole balance as its row on the wallet's page reads it.
    func balance(_ coins: Int) -> Text {
        switch self {
        // USER-DATA: the balance as a span of time, years, days, hours, minutes and seconds
        case .time: return Text(verbatim: MTCoinText.time(coins))
        // USER-DATA: the balance in coins, a number
        case .coins: return Text("\(MTCoinText.count(coins)) coins")
        // USER-DATA: the balance in Montana (one coin is 0.000000001) under the ticker
        case .montana: return Text(verbatim: told(coins))
        }
    }
    var keyboard: UIKeyboardType { self == .coins ? .numberPad : .decimalPad }
    /// A sum as the person reads it beside the total.
    func told(_ coins: Int) -> String {
        switch self {
        case .time: return MTCoinText.time(coins, signed: false)
        case .coins: return MTCoinText.count(coins)
        case .montana: return MTChatMint.montana(coins) + " " + MTCoinBook.ticker
        }
    }
    /// A sum as its field shows it; none shows nothing, so the field's own zero stands. A span holds no whole count of a sum the
    /// page wrote itself (a box of π in hours): it shows six places, and the total beside says the sum exactly.
    func written(_ coins: Int, in span: MTTimeSpan) -> String {
        guard 0 < coins else { return "" }
        switch self {
        case .coins: return String(coins)
        case .time: return Self.decimal(coins, over: span.seconds, places: 6)
        case .montana: return Self.decimal(coins, over: MTChatMint.coinsPerMontana, places: 9)
        }
    }
    /// What is typed, as the field keeps it and as the coins it is, never more than fifteen digits of coins. Digits of every
    /// script are read, as the keyboard gives them; the point is either mark the keyboard of the language gives.
    func read(_ typed: String, in span: MTTimeSpan) -> (shown: String, coins: Int) {
        switch self {
        case .coins:
            let digits = String(Self.digits(typed).prefix(15))
            return (digits, Int(digits) ?? 0)
        case .time: return Self.number(typed, per: span.seconds, places: 6)
        case .montana: return Self.number(typed, per: MTChatMint.coinsPerMontana, places: 9)
        }
    }
    private static let ceiling = 999_999_999_999_999
    private static func digits(_ typed: String) -> String { typed.compactMap(\.wholeNumberValue).map(String.init).joined() }
    /// A number with a point, read as so many units of `per` coins, rounded down to a whole coin.
    private static func number(_ typed: String, per: Int, places: Int) -> (shown: String, coins: Int) {
        var whole = "", fraction = "", pointed = false
        for c in typed {
            if let d = c.wholeNumberValue {
                if pointed { if fraction.count < places { fraction += String(d) } } else if whole.count < 15 { whole += String(d) }
            } else if c == "." || c == ",", !pointed {
                pointed = true
            }
        }
        let shown = whole + (pointed ? "." + fraction : "")
        guard let value = Decimal(string: (whole.isEmpty ? "0" : whole) + "." + fraction + "0", locale: Locale(identifier: "en_US_POSIX")) else { return (shown, 0) }
        var exact = value * Decimal(per), down = Decimal()
        NSDecimalRound(&down, &exact, 0, .down)
        // A digit past the ceiling is not taken, so the field never shows more than it sends.
        guard down <= Decimal(ceiling) else { return number(String(typed.dropLast()), per: per, places: places) }
        return (shown, Int(truncating: NSDecimalNumber(decimal: down)))
    }
    /// A count of coins as so many units of `per`, its places trimmed of the zeros that end them.
    private static func decimal(_ coins: Int, over per: Int, places: Int) -> String {
        var value = Decimal(coins) / Decimal(per), kept = Decimal()
        NSDecimalRound(&kept, &value, places, .down)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = places
        f.usesGroupingSeparator = false
        return f.string(from: NSDecimalNumber(decimal: kept)) ?? String(coins)
    }
}

/// THE SPANS OF TIME AS PEOPLE COUNT THEM (the author's word 19.10.2026 17:2x UTC: «divide the units of time humanly -- second,
/// minute, hour, day, week, month, year, century, epoch»): the one table of their lengths in seconds, the same the Time Balance
/// splits by (MTCoinText.time) -- a year of 365 days, a month its twelfth, a century a hundred years, an epoch a thousand.
enum MTTimeSpan: Int, CaseIterable, Identifiable {
    case second = 1, minute = 60, hour = 3_600, day = 86_400, week = 604_800, month = 2_628_000, year = 31_536_000
    case century = 3_153_600_000, epoch = 31_536_000_000
    var id: Int { rawValue }
    var seconds: Int { rawValue }
    var title: Text {
        switch self {
        case .second: return Text("Second")
        case .minute: return Text("Minute")
        case .hour: return Text("Hour")
        case .day: return Text("Day")
        case .week: return Text("Week")
        case .month: return Text("Month")
        case .year: return Text("Year")
        case .century: return Text("Century")
        case .epoch: return Text("Epoch")
        }
    }
}

/// THE TIME UNDER THE COINS (the author's word 19.10.2026 14:44 UTC): one look beside every count of coins a transfer or a link of
/// the TimeChain moved -- the count's own time, small and secondary, never signed (the coins beside it carry the way).
struct MTCoinTime: View {
    let coins: Int
    var body: some View {
        // USER-DATA: the coins as a span of time
        Text(verbatim: MTCoinText.time(coins, signed: false)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
    }
}

/// ONE COIN MOVE ON ITS OWN PAGE (the author's word 05.10.2026: «a tap on the coins opens this transaction»): a coin letter's bubble
/// opens the move it made in this phone's book -- the coins, who they came from or went to, the moment -- and the link its TimeChain
/// sealed for it, with the seal and the seal before it.
/// LOCAL AND GLOBAL (the author's word 06.10.2026 13:2x UTC: «a Local TimeChain and a Global TimeChain, in which the hashes are one
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
                    LabeledContent("Time") {
                        // USER-DATA: the coins the move carried as a span of time
                        Text(verbatim: MTCoinText.time(move.c)).monospacedDigit()
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
                        // THIS PHONE IS A NODE (the author's word 06.10.2026 14:2x UTC): how many machines of the genesis -- every
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
                Text("Not in your TimeChain yet").foregroundStyle(.secondary)
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

/// THE HISTORY IS FOLDED OFF THE SCREEN'S THREAD, ONCE A CHANGE OF THE BOOK (the author's words 12.10.2026 12:2x UTC: «the history in the
/// Time Coins on T1 lags; make the analytics a separate button so it opens and nothing lags; at the history's opening the transactions
/// open at once»). T1 on 2194, a book of 24 320 moves: 823 ms of a still main thread at the opening -- every line asked the chats' whole
/// list, decoded from the vault, for its name -- and 445 ms at the leaving, every pass of the page filtering the whole book by the
/// calendar's month. The names are read once a fold, a day and a month by the moments' own intervals, the fold runs on its own thread
/// and is kept whole for the history, the analytics and a person's page alike; the pages only read it.
@MainActor final class MTCoinHistory: ObservableObject {
    static let shared = MTCoinHistory()
    /// One line of the history: a move of the book, or a day's minting folded into one.
    struct Line: Identifiable, Hashable {
        let id: String
        let at: Double
        let signed: Int
        let title: String
        let category: String
        let glyph: String
        let source: String
        let ref: String
        let peer: String?
        let tx: String?
        let count: Int
    }
    struct Day: Identifiable { let id: Date; let lines: [Line]; let sum: Int }
    struct Share: Identifiable { let name: String; let signed: Int; let moved: Int; var id: String { name } }
    struct Month: Identifiable { let id: Date; let spending: Int; let income: Int; let shares: [Share] }
    struct Fold { let days: [Day]; let months: [Month]; let whole: Month; let byPeer: [String: [Line]]; let moves: Int }
    /// What a fold needs of the screen's world, read on the screen's thread once: the people's names, the channels, the sources' words.
    struct Ask {
        let names: [String: String]; let channels: Set<String>; let words: [String: String]; let minted: String; let mintedDay: String
        let burnedDay: String; let spentDay: String; let calendar: Calendar
    }
    @Published private(set) var fold: Fold?
    private var watchers = 0
    private var bag: AnyCancellable?
    private var folding = false
    private var again = false
    /// A page that reads the history stands: the book's moves fold again, at most one fold a second and a half, the newest book each.
    func watch() {
        watchers += 1
        guard bag == nil else { return }
        bag = MTLocalCoinLedger.shared.$entries
            .throttle(for: .seconds(1.5), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] moves in self?.refold(moves) }
    }
    func unwatch() {
        watchers = max(0, watchers - 1)
        if watchers == 0 { bag = nil }
    }
    /// The wallet's page stands: one fold ahead of the history's door, so the door opens on lines, never on an empty page.
    func warm() {
        let moves = MTLocalCoinLedger.shared.entries
        if fold?.moves != moves.count { refold(moves) }
    }
    private func refold(_ moves: [MTCoinEntry]) {
        if folding { again = true; return }
        folding = true
        let ask = Ask(names: MTTimeChainRows.names(),
                      channels: Set(MTGroup.shared.groups.compactMap { k, g in g.kind == .channel ? MTGroup.key(of: k) : nil }),
                      words: Dictionary(MTTimeChain.sources.map { s in (s, MTTimeChainRows.name(s)) }, uniquingKeysWith: { a, _ in a }),
                      minted: String(localized: "Minted", bundle: MTLanguage.bundle),
                      mintedDay: String(localized: "Minting of the day", bundle: MTLanguage.bundle),
                      burnedDay: String(localized: "Burning of the day", bundle: MTLanguage.bundle),
                      spentDay: String(localized: "Spending of the day", bundle: MTLanguage.bundle),
                      calendar: Calendar.current)
        let started = Date()
        Task.detached(priority: .userInitiated) {
            let f = MTCoinHistory.fold(moves, ask)
            await MainActor.run {
                let me = MTCoinHistory.shared
                me.fold = f
                me.folding = false
                MontanaTrace.markFolded("coin_history", "fold moves=\(f.moves) days=\(f.days.count) ms=\(Int(Date().timeIntervalSince(started) * 1000))", window: 60)
                if me.again { me.again = false; me.refold(MTLocalCoinLedger.shared.entries) }
            }
        }
    }
    nonisolated static func glyph(_ k: MTCoinEntry.Kind) -> String {
        switch k {
        case .earn: return "sparkles"
        case .receive: return "arrow.down.left"
        case .send: return "arrow.up.right"
        case .spend: return "hand.thumbsup"
        case .burn: return "flame"
        }
    }
    /// A DAY'S SMALL EXPENSES FOLD AS ITS MINTING DOES (the author's word 17.10.2026 10:46 UTC: «and in the history group the small
    /// expenses, such as the burning for likes, comments and the other small ones, as a day's, the same as with the minting»): a burn or
    /// a small spend of at most thirteen coins (MTCoinBook.smallSpend) -- a coin on a letter or a post, a comment's coin,
    /// a letter's burn of the builds before, a small move of a game. A transfer to a person, a call's seconds and a larger expense stay
    /// lines of their own.
    nonisolated static func small(_ e: MTCoinEntry, _ source: String) -> Bool {
        (e.k == .spend || e.k == .burn) && source != "calls" && e.c <= MTCoinBook.smallSpend
    }
    /// Every move of the book folded once: the lines day after day, a day's minting one line of it, a day's small expenses one line of
    /// each source and kind, the months' and the whole's sums by source, and the transfers with each person. The days are found by the
    /// interval of the day the moment before fell in (and a quarter-hour's memory of the days asked), never by a calendar's question for
    /// every move.
    nonisolated static func fold(_ moves: [MTCoinEntry], _ ask: Ask) -> Fold {
        let cal = ask.calendar
        var low = 0.0, high = -1.0, current = Date.distantPast
        var quarters: [Int: (Date, Double)] = [:]
        func dayOf(_ at: Double) -> Date {
            if low <= at, at < high { return current }
            let key = Int((at / 900).rounded(.down))
            let span: (Date, Double)
            if let s = quarters[key] { span = s } else {
                let d = cal.startOfDay(for: Date(timeIntervalSince1970: at))
                span = (d, (cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)).timeIntervalSince1970)
                quarters[key] = span
            }
            current = span.0; low = span.0.timeIntervalSince1970; high = span.1
            return current
        }
        var monthOfDay: [Date: Date] = [:]
        func monthOf(_ d: Date) -> Date {
            if let m = monthOfDay[d] { return m }
            let m = cal.dateInterval(of: .month, for: d)?.start ?? d
            monthOfDay[d] = m
            return m
        }
        struct Agg { var spending = 0; var income = 0; var by: [String: (signed: Int, moved: Int)] = [:] }
        func add(_ a: inout Agg, _ e: MTCoinEntry, _ name: String) {
            if e.signed < 0 { a.spending = MTCoinCounts.plus(a.spending, -e.signed) } else { a.income = MTCoinCounts.plus(a.income, e.signed) }
            let had = a.by[name] ?? (0, 0)
            a.by[name] = (MTCoinCounts.plus(had.signed, e.signed), MTCoinCounts.plus(had.moved, e.c))
        }
        var byMonth: [Date: Agg] = [:], whole = Agg()
        var byDay: [Date: [Line]] = [:]
        var minted: [Date: (sum: Int, count: Int, at: Double)] = [:]
        struct Small: Hashable { let day: Date; let source: String; let kind: MTCoinEntry.Kind }
        var smalls: [Small: (sum: Int, count: Int, at: Double)] = [:]
        var byPeer: [String: [Line]] = [:]
        for e in moves {
            let day = dayOf(e.at)
            let source = MTTimeChain.source(ref: e.ref, kind: e.k, peer: e.peer) { p in ask.channels.contains(p) }
            let name = ask.words[source] ?? source
            add(&byMonth[monthOf(day), default: Agg()], e, name)
            add(&whole, e, name)
            if e.k == .earn {
                let had = minted[day] ?? (0, 0, 0)
                minted[day] = (MTCoinCounts.plus(had.sum, e.c), had.count + 1, max(had.at, e.at))
                continue
            }
            if small(e, source) {
                // Only the line folds: the months' and the whole's sums took the move above, one by one.
                let key = Small(day: day, source: source, kind: e.k)
                let had = smalls[key] ?? (0, 0, 0)
                smalls[key] = (MTCoinCounts.plus(had.sum, e.c), had.count + 1, max(had.at, e.at))
                continue
            }
            let who = e.peer.map { p in ask.names[p] ?? String(p.prefix(10)) } ?? name
            let tx = e.ref.hasPrefix(MTCoinTx.refPrefix) ? String(e.ref.dropFirst(MTCoinTx.refPrefix.count)) : nil
            let line = Line(id: e.id, at: e.at, signed: e.signed, title: who, category: name, glyph: glyph(e.k), source: source, ref: e.ref,
                            peer: e.peer, tx: tx?.count == 64 ? tx : nil, count: 1)
            byDay[day, default: []].append(line)
            if let p = e.peer, source == "sent" || source == "received" { byPeer[p, default: []].append(line) }
        }
        for (day, m) in minted {
            byDay[day, default: []].append(Line(id: "minted:" + String(Int(day.timeIntervalSince1970)), at: m.at, signed: m.sum, title: ask.minted,
                                                category: ask.mintedDay, glyph: "sparkles", source: "mint", ref: "", peer: nil, tx: nil, count: m.count))
        }
        for (k, m) in smalls {
            byDay[k.day, default: []].append(Line(id: "small:" + k.kind.rawValue + ":" + k.source + ":" + String(Int(k.day.timeIntervalSince1970)),
                                                  at: m.at, signed: -m.sum, title: ask.words[k.source] ?? k.source,
                                                  category: k.kind == .burn ? ask.burnedDay : ask.spentDay, glyph: glyph(k.kind), source: k.source,
                                                  ref: "", peer: nil, tx: nil, count: m.count))
        }
        let days = byDay.map { d, lines in
            let sorted = lines.sorted { a, b in b.at < a.at }
            return Day(id: d, lines: sorted, sum: sorted.reduce(0) { s, l in MTCoinCounts.plus(s, l.signed) })
        }.sorted { a, b in b.id < a.id }
        func month(_ id: Date, _ a: Agg) -> Month {
            Month(id: id, spending: a.spending, income: a.income,
                  shares: a.by.map { k, v in Share(name: k, signed: v.signed, moved: v.moved) }.sorted { x, y in y.moved < x.moved })
        }
        for k in Array(byPeer.keys) { byPeer[k]?.sort { a, b in b.at < a.at } }
        return Fold(days: days, months: byMonth.map { k, v in month(k, v) }.sorted { a, b in b.id < a.id }, whole: month(.distantPast, whole),
                    byPeer: byPeer, moves: moves.count)
    }
    /// The history as its page shows it: the lines of a flow and a search, day after day, newest first, at most `limit` of them -- a
    /// page of the book, never the whole; `more` says lines stand past it.
    func shown(_ flow: MTCoinHistoryPage.Flow, query: String, limit: Int) -> (days: [Day], more: Bool) {
        guard let fold else { return ([], false) }
        let all = flow == .all && query.isEmpty
        var out: [Day] = [], n = 0
        for d in fold.days {
            let lines = all ? d.lines : d.lines.filter { l in flow.holds(l.signed) && (query.isEmpty || l.title.localizedCaseInsensitiveContains(query)) }
            guard !lines.isEmpty else { continue }
            if limit <= n { return (out, true) }
            let cut = Array(lines.prefix(limit - n))
            out.append(Day(id: d.id, lines: cut, sum: all ? d.sum : lines.reduce(0) { s, l in MTCoinCounts.plus(s, l.signed) }))
            n += cut.count
            if cut.count < lines.count { return (out, true) }
        }
        return (out, false)
    }
    /// THE TRANSFERS WITH ONE PERSON (the author's word 12.10.2026 12:2x UTC: «on the correspondent's page, after the wall, a section of
    /// transactions -- only what was sent to them and received from them»): the coins sent and received, newest first.
    func with(_ peers: Set<String>) -> [Line] {
        guard let fold else { return [] }
        let all = peers.flatMap { p in fold.byPeer[p] ?? [] }
        return peers.count <= 1 ? all : all.sorted { a, b in b.at < a.at }
    }
}

/// THE HISTORY OF OPERATIONS IN A BANK'S FORMAT (the author's words 12.10.2026 10:1x UTC: «the history of operations must look like
/// this page in a bank's format, with separators by days, in the order of time, filters by spending and income, with a search by
/// contacts, and inside the Explorer at once in the app»; «the sum of a day's minting -- simply one line for that day»; 12:2x: «at the
/// history's opening the transactions open at once», the analytics by its own button): the flow, then day after day, newest first, each
/// day with its own sum, a page of lines at a time that grows as it is read. Reads the one fold (MTCoinHistory).
struct MTCoinHistoryPage: View {
    enum Flow: String, CaseIterable, Identifiable {
        case all, spending, income
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .spending: return "Spending"
            case .income: return "Income"
            }
        }
        func holds(_ signed: Int) -> Bool { self == .all || (self == .spending ? signed < 0 : 0 < signed) }
    }
    typealias Line = MTCoinHistory.Line
    static let page = 120
    @ObservedObject private var history = MTCoinHistory.shared
    @State private var flow: Flow = .all
    @State private var query = ""
    @State private var limit = MTCoinHistoryPage.page
    @State private var explorer: MTExplorerLink?
    private static let calendar = Calendar.current
    var body: some View {
        let shown = history.shown(flow, query: query, limit: limit)
        List {
            Section {
                Picker("Operations", selection: $flow) {
                    ForEach(Flow.allCases) { f in Text(f.title).tag(f) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            if history.fold == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            } else if shown.days.isEmpty {
                Text("No operations").foregroundStyle(.secondary)
            }
            ForEach(shown.days) { day in
                Section {
                    ForEach(day.lines) { l in MTHistoryRow(line: l) { link in explorer = link } }
                } header: {
                    HStack {
                        Self.dayTitle(day.id)
                        Spacer()
                        // USER-DATA: the day's coins, signed
                        Text(verbatim: (0 < day.sum ? "+" : "") + MTCoinText.count(day.sum)).monospacedDigit()
                    }
                }
            }
            if shown.more {
                // THE PAGE GROWS AS IT IS READ: the next lines come when the last is near, never the whole book at the opening.
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    .id(limit)
                    .onAppear { limit += Self.page }
            }
        }
        .searchable(text: $query, prompt: Text("Search contacts"))
        .onChange(of: flow) { _, _ in limit = Self.page }
        .onChange(of: query) { _, _ in limit = Self.page }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text("History"))
        .sheet(item: $explorer) { link in MTExplorerSheet(url: link.url).ignoresSafeArea() }
        .onAppear { history.watch() }
        .onDisappear { history.unwatch() }
    }
    @ViewBuilder static func dayTitle(_ day: Date) -> some View {
        if calendar.isDateInToday(day) { Text("Today") }
        else if calendar.isDateInYesterday(day) { Text("Yesterday") }
        // USER-DATA: a day of the book, in the phone's language
        else { Text(verbatim: day.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(MTLanguage.locale))) }
    }
}

/// ONE LINE OF THE HISTORY (MTCoinHistoryPage): the glyph, who or what, the category and the moment, the signed coins -- the whole row
/// one target. A transfer opens its record in the Explorer inside the app, a move between people the transaction's own page (the one a
/// coin letter's bubble opens, MTCoinMovePage), every other line its card.
struct MTHistoryRow: View {
    let line: MTCoinHistory.Line
    let explore: (MTExplorerLink) -> Void
    var body: some View {
        let content = HStack(spacing: 12) {
            Image(systemName: line.glyph).font(.body).frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                // USER-DATA: who or what the operation was with
                Text(verbatim: line.title).font(.body).lineLimit(1)
                // USER-DATA: the operation's category and its moment on this phone's clock
                Text(verbatim: line.category + " · " + Date(timeIntervalSince1970: line.at).formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                // USER-DATA: the operation's coins, signed
                Text(verbatim: (0 < line.signed ? "+" : "") + MTCoinText.count(line.signed)).font(.body.monospacedDigit())
                    .foregroundStyle(0 < line.signed ? Color.green : Color.primary)
                MTCoinTime(coins: line.signed)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        if let tx = line.tx, let url = URL(string: MTCoinTx.link + tx) {
            Button { explore(MTExplorerLink(url: url)) } label: { content }.buttonStyle(.plain)
        } else if line.source == "sent" || line.source == "received" {
            NavigationLink { MTCoinMovePage(route: MTCoinMoveRoute(ref: line.ref, mine: line.signed < 0), peer: line.title) } label: { content }
        } else {
            NavigationLink { MTHistoryCard(line: line) } label: { content }
        }
    }
}

/// THE ANALYTICS BY ITS OWN BUTTON (the author's word 12.10.2026 12:2x UTC: «make the analytics a separate button so it opens and
/// nothing lags»): the months as chips (and every month), the spending and the income, where the coins came from and went with each
/// source's share -- read from the one fold of the history (MTCoinHistory), never from the book at the page's pass.
struct MTCoinAnalyticsPage: View {
    @ObservedObject private var history = MTCoinHistory.shared
    @State private var month: Date?
    var body: some View {
        let fold = history.fold
        let m = month.flatMap { id in fold?.months.first { x in x.id == id } } ?? fold?.whole
        let moved = MTCoinCounts.plus(m?.spending ?? 0, m?.income ?? 0)
        List {
            Section {
                // THE MONTHS AS CHIPS: every month the book holds a move in, the newest first, and all of them
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(Text("Every month"), on: month == nil) { month = nil }
                        ForEach(fold?.months ?? []) { x in
                            // USER-DATA: a month of the book, in the phone's language
                            chip(Text(verbatim: x.id.formatted(Date.FormatStyle().month(.wide).year().locale(MTLanguage.locale))), on: month == x.id) { month = x.id }
                        }
                    }
                }
                HStack(spacing: 12) {
                    total(Text("Spending"), m?.spending ?? 0, "arrow.up.right")
                    total(Text("Income"), m?.income ?? 0, "arrow.down.left")
                }
            }
            .listRowBackground(Color.clear)
            if fold == nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            }
            Section {
                ForEach(m?.shares ?? []) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            // USER-DATA: where the coins came from or went
                            Text(verbatim: a.name).font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                // USER-DATA: the coins of this source over the period, signed
                                Text(verbatim: (0 < a.signed ? "+" : "") + MTCoinText.count(a.signed)).font(.subheadline.monospacedDigit())
                                    .foregroundStyle(0 < a.signed ? Color.green : Color.primary)
                                MTCoinTime(coins: a.signed)
                            }
                        }
                        ProgressView(value: Double(a.moved), total: Double(max(1, moved)))
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text("Analytics"))
        .onAppear { history.watch() }
        .onDisappear { history.unwatch() }
    }
    private func chip(_ label: Text, on: Bool, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { label.font(.subheadline).padding(.horizontal, 12).frame(minHeight: 44) }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).tint(on ? MontanaOctagon.platformBlue : .secondary)
    }
    private func total(_ title: Text, _ coins: Int, _ glyph: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label { title } icon: { Image(systemName: glyph) }.font(.subheadline).foregroundStyle(.secondary)
            // USER-DATA: the period's coins of this side
            Text(verbatim: MTCoinText.count(coins)).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
            MTCoinTime(coins: coins)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// AN OPERATION'S OWN CARD (the author's word 12.10.2026 10:1x UTC: «the analytics of each operation»): what it was, with whom, how
/// many coins and when; a day's minting says how many moves it folds; the person's own chain opens in the Explorer inside the app.
struct MTHistoryCard: View {
    let line: MTCoinHistoryPage.Line
    @State private var explorer: MTExplorerLink?
    var body: some View {
        List {
            Section {
                // USER-DATA: the operation's coins, signed
                LabeledContent { Text(verbatim: (0 < line.signed ? "+" : "") + MTCoinText.count(line.signed)).monospacedDigit() } label: { Text("Amount") }
                // USER-DATA: the operation's coins as a span of time
                LabeledContent { Text(verbatim: MTCoinText.time(line.signed, signed: false)).monospacedDigit() } label: { Text("Time") }
                // USER-DATA: who or what the operation was with
                LabeledContent { Text(verbatim: line.title) } label: { Text("Kind") }
                // USER-DATA: the operation's category
                LabeledContent { Text(verbatim: line.category) } label: { Text("Category") }
                // USER-DATA: the operation's moment on this phone's clock
                LabeledContent { Text(verbatim: Date(timeIntervalSince1970: line.at).formatted(date: .abbreviated, time: .shortened)) } label: { Text("When") }
                if 1 < line.count {
                    // USER-DATA: how many moves the line folds
                    LabeledContent { Text(verbatim: String(line.count)).monospacedDigit() } label: { Text("Operations") }
                }
            }
            if let from = MTCoinTx.cachedKeyTag, let url = URL(string: MTCoinTx.keyLink + from) {
                Section {
                    Button { explorer = MTExplorerLink(url: url) } label: {
                        Label("Open in Explorer", systemImage: "magnifyingglass").frame(minHeight: 44)
                    }
                } footer: { Text("Your coin key's whole chain, checked in the Explorer.") }
            }
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text("Operation"))
        .sheet(item: $explorer) { link in MTExplorerSheet(url: link.url).ignoresSafeArea() }
    }
}

/// THE EXPLORER INSIDE THE APP (the author's word 12.10.2026 10:1x UTC: «inside the Explorer at once in the app»): the platform's own
/// browser sheet over the record's page, never a jump out of the app.
struct MTExplorerLink: Identifiable { let url: URL; var id: String { url.absoluteString } }
struct MTExplorerSheet: UIViewControllerRepresentable {
    let url: URL
    static func open(_ url: URL) {
        MTTop.present(SFSafariViewController(url: url), kind: "coin-explorer")
    }
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

struct MTCallCoinReceipt: View {
    let coins: Int
    var body: some View {
        Button {
            let url = MTCoinTx.cachedKeyTag.flatMap { URL(string: MTCoinTx.keyLink + $0) } ?? MTCoinTx.explorer
            MTExplorerSheet.open(url)
        } label: {
            HStack(spacing: 5) {
                MTMintCoin(spinning: false, side: 18)
                // USER-DATA: only the amount settled for this call and its own time (1 coin = 1 second), never a duration estimate.
                Text(verbatim: (coins > 0 ? "+" : "") + MTCoinText.count(coins) + " · " + MTCoinText.time(coins, signed: false))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(coins > 0 ? Color.green : (coins < 0 ? Color.red : Color.secondary))
                    .lineLimit(1).minimumScaleFactor(0.65)
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.thinMaterial, in: Capsule())
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Open in Explorer"))
    }
}

/// THE NEXT BOX FILLS AS A LOAD FILLS (the author's word 04.10.2026 00:48 UTC: «while minting, the system's progress bar of this box to
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
                    // THE FILL IS THE SYSTEM'S BLUE (the author's word 04.10.2026 01:22 UTC: «the fill of the minting's progress in the box --
                    // the system's blue, not white as now»): the page's tint is the label colour, so the bar names its own.
                    .tint(.blue)
                    .frame(maxWidth: 240)
                // THE NEXT LEVEL IN TIME (the author's word 19.10.2026 21:08 UTC: «on the coins page, to the next level under the coin,
                // show it in units of time»): one coin is one second, so what is left reads as the Time Balance writes a span.
                Text("\(MTCoinText.time(high - balance, signed: false)) to level \(place + 1)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

/// THE PRICE OF A SECOND, FIXED UNDER THE COUNT (the author's words 04.10.2026 14:32 UTC: «put the price of one second under the
/// field of the level's count as a fixed line: 1 second = 13 coins»; ~15:03: «the rate and the question are seen without the
/// Pantheon's game too»): the rate and the link to the form of the person's hour stand always, under the level's count, which
/// shows only while a game mints.
struct MTSecondPrice: View {
    @State private var asking = false
    @AppStorage(MTPersonalRate.key) private var stored = ""
    var body: some View {
        VStack(spacing: 0) {
            MTCurrentMintRate().font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            // THE PERSON'S RATE UNDER OURS (the author's word 04.10.2026 16:19 UTC, MTPersonalRate): once their earning is told, one
            // coin in their currency stands under the second's price.
            if let word = MTPersonalRate.read(stored) {
                // USER-DATA: one coin in the person's currency, by their own earning
                Text("Your rate: 1 coin = \(MTPersonalRate.coin(word).formatted(.currency(code: word.code).precision(.significantDigits(1...3)).locale(MTLanguage.locale)))")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                // THE HOUR, TOLD AND EDITABLE (the author's word 05.10.2026 11:16 UTC: «on the coins page the hour's number is tappable,
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
            Button("What is Your hour worth Now?") { asking = true }   // the author's words and capitals, 05.10.2026 17:3x UTC
                .font(.footnote).buttonStyle(.borderless).tint(.blue)
                .frame(minHeight: 44).contentShape(Rectangle())
                .sheet(isPresented: $asking) { MTHourWorth() }
        }
    }
}

/// THE APPS THAT MINT, ABOVE THE COIN (the author's word 04.10.2026 15:08 UTC: «above the coin show the icons of the apps that give
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

/// THE LEVEL ON THE COIN AND THE APPS BESIDE IT (the author's word 04.10.2026 15:08 UTC: «on the badge the level's number as now and
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

/// WHAT AN HOUR IS WORTH (the author's word 04.10.2026 14:27 UTC: «under the rate, a link to a separate form asking how much you
/// earn in an hour; when the person enters it, their hour's price gives their currency to the coin's rate»): an hour is 3 600
/// seconds at one coin each (MTCoinBook.price, point 11 as of 05.10.2026), so a coin is the hour's earning over 3 600 -- a second.
/// THE CURRENCY BESIDE THE SUM (the author's word 04.10.2026 15:01 UTC, the form on 2106: «in the field of the sum per hour, at the
/// right, give as a drop-down list all the currency codes to choose, with flags, beautifully, and in the currency's language»): the
/// person's own currency stands first chosen and every currency in use is a choice (MTCurrencyMenu).
/// AN HOUR, A MONTH OR A YEAR (the author's word 04.10.2026 16:19 UTC, the form on 2108: «the field of the hour's worth takes a
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
    /// THE CHECK THAT KEEPS THE HOUR (the author's word 05.10.2026 11:16 UTC: «a confirmation check in our style at the top right
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

/// THE PERSONAL RATE OF THE COIN (the author's word 04.10.2026 16:19 UTC: «when the currency's rate is set, add it under the coin
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

/// THE CURRENCIES, AS A DROP-DOWN (the author's word 04.10.2026 15:01 UTC; MTHourWorth): the platform's menu with its inline
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

/// THE FIRE'S MINUTE UNDER THE LEVEL (the author's word 04.10.2026 10:38 UTC; MTPantheon.streak): the platform's bar of the unbroken
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

/// THE TIMECHAINS ON THE WALLET (the author's word 03.10.2026 21:25 UTC): every source's chain with its length and the first
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
        case "vpnwall": return "Coins from the VPN Wall"
        case "vpnpay": return "Paid for the VPN"
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
        case "fabric": return "Fabric of Time"
        case "calls": return "Burned for calls"
        case "letters": return "Burned for letters"
        case "system": return "System chain"
        default: return "Coins sent"
        }
    }
    /// The same word in the person's language, for a line that joins it with others (the history's way).
    static func name(_ source: String) -> String { String(localized: String.LocalizationValue(key(source)), bundle: MTLanguage.bundle) }
    /// THE PEOPLE BY THEIR CONVERSATIONS, AS THE CHATS TAB NAMES THEM -- ONE READING FOR A WHOLE FOLD (T1 on 2194: a person asked one
    /// by one decoded the chats' whole list from the vault for every line of the history, 823 ms of a still screen). The first row of a
    /// name speaks for it, as the list's own order has it.
    static func names() -> [String: String] {
        guard let store = ChatStore.live else { return [:] }
        var out: [String: String] = [:]
        for c in store.listChats() where out[c.name] == nil { out[c.name] = MontanaAvatar.spokenName(store.title(for: c)) }
        return out
    }
}

/// A TIMECHAIN, LINK BY LINK (the author's word 03.10.2026 21:46 UTC: «the detailed timechain»): every link of one source's
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
                MTTimeChainLinkRow(ref: l.ref) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        // USER-DATA: the link's number in its chain
                        Text(verbatim: "#" + String(l.n)).font(.subheadline.monospacedDigit().weight(.semibold))
                        Spacer()
                        // A LEVEL'S LINK NAMES ITS LEVEL (the chain of the person, the levels of π): it moves no coins.
                        if l.k == "level" {
                            Text("Level \(l.c)").font(.body.monospacedDigit())
                        } else if 0 < l.c {
                            VStack(alignment: .trailing, spacing: 2) {
                                // USER-DATA: the coins the link moved, signed by its way; a link of the wall's posts moves none
                                Text(verbatim: (["earn", "receive", "keep"].contains(l.k) ? "+" : "−") + MTCoinText.count(l.c)).font(.body.monospacedDigit())
                                MTCoinTime(coins: l.c)
                            }
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
        }
        .scrollContentBackground(.hidden).montanaPageGround()
        .navigationTitle(Text(LocalizedStringKey(MTTimeChainRows.key(source))))
        .task {
            MTTimeChain.read(source) { links = $0 }
            MTTimeChain.head(source) { head = $0 }
        }
    }
}

/// A TRANSFER'S LINK OPENS ITS RECORD (the author's word 11.10.2026 17:2x UTC: «on any transaction a link that confirms the sending,
/// so I can send it too»): a link whose move is a transfer (MTCoinTx, "tx:" + the record's name) is the whole row's road to the
/// Explorer, and its menu copies or shares the confirmation link; every other link stands as it was.
struct MTTimeChainLinkRow<Content: View>: View {
    let ref: String
    @ViewBuilder var content: () -> Content
    private var url: URL? {
        guard ref.hasPrefix(MTCoinTx.refPrefix) else { return nil }
        let id = String(ref.dropFirst(MTCoinTx.refPrefix.count))
        return id.count == 64 ? URL(string: MTCoinTx.link + id) : nil
    }
    var body: some View {
        if let url {
            Button { MTExplorerSheet.open(url) } label: { content().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle()) }
                .foregroundStyle(.primary)
                .contextMenu {
                    Button { MTExplorerSheet.open(url) } label: { Label("Open in Explorer", systemImage: "magnifyingglass") }
                    Button { UIPasteboard.general.string = url.absoluteString } label: { Label("Copy confirmation link", systemImage: "doc.on.doc") }
                    Button { MTShare.present([url]) } label: { Label("Share confirmation link", systemImage: "square.and.arrow.up") }
                }
        } else {
            content()
        }
    }
}

/// THE TIMECHAIN OF THE PERSON (the author's words 10.10.2026 10:4x, 12:2x and 12:4x UTC: «remove the Add account button and put
/// TimeChains in its place»; «the TimeChain, where the first chain of time is the Person, the second the Wallet»; «the third chain
/// of time is chats and calls»; 11:1x: «the whole TimeChain core shown for an external observer»; App, «The chains of time a client
/// shows»): one seed is one person, and what stands beside it is the evidence of its time -- the Global Level the minting keeps
/// while the app is away, the chain of the person, the wallet's chain of π and coins, the chains of the chats and calls, and what
/// an observer checks for themselves.
/// IN MONTANA (the author's word 11.10.2026 12:2x UTC: «in the messenger carry over from the wallet the TimeChain button in place
/// of Add account, and make everything there correct»): every sentence of the page is true of this app. The chats and calls live
/// here, so their section says what its chains hold, not where they live. A node answers this app's coin exchange at every
/// gather of the book (MTCoinVault.post), on this wallet every few seconds and elsewhere now and then, and the person's footer
/// says both. The minting while the app is away (MTPersonChain.left) is not called here: the last answer of a messenger may
/// stand minutes before it leaves the screen, and those minutes on the screen would be minted as away -- so the Global Level's
/// footer names the level alone.
struct MTTimeChainsPage: View {
    @ObservedObject private var person = MTPersonChain.shared
    @ObservedObject private var fabric = MTFabric.shared
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number of the person's coins (fold-7)
    @ObservedObject private var top = MTTopNet.shared
    @ObservedObject private var node = MTNetworkNode.shared
    @State private var core: Result<MTWalletCore.Snapshot, MTWalletCore.Absence>?
    @State private var chainFiles: [URL] = []
    /// The chats' and calls' chains of coins; every other source is the wallet's own. The third chain of time is the Fabric of Time.
    static let talk = ["chats", "groups", "channels", "comments", "wall", "calls", "letters"]
    private static let own = MTTimeChain.sources.filter { s in s != "pi" && !talk.contains(s) }
    private var vectorsHold: Bool { MTPersonChain.levelKAT() && MTFabricRules.selfCheck() && MTTopNet.keyKAT() && MTCoinVault.keyKAT() && MTTimeChainTip.selfCheck() }
    var body: some View {
        let place = MTPiLevels.place(split.available)
        List {
            Section {
                LabeledContent {
                    // USER-DATA: the Global Level of the person, a number
                    Text(verbatim: String(MTPersonChain.global(person: person.level, balance: split.available))).font(.title.bold().monospacedDigit())
                } label: { Label("Global level", systemImage: "globe") }
            } footer: { Text("The lowest of the three levels below.") }
            Section {
                LabeledContent("Level") {
                    // USER-DATA: the level of the chain of the person, a number, or a dash below one second
                    Text(verbatim: person.level.map { n in String(n) } ?? "—").monospacedDigit()
                }
                LabeledContent("Time online") {
                    // USER-DATA: the seconds the chain of the person counts, in the units of the Time Balance
                    Text(verbatim: MTCoinText.time(Int(person.seconds), signed: false))
                        .monospacedDigit()
                }
                // THE NEXT LEVEL IN TIME (the author's word 19.10.2026 17:12 UTC: «on the page, in the row to the next level, write it
                // as the Time Balance does -- measured in time»): the seconds left until the level doubles, by the Time Balance's owner.
                if let n = person.level, n < 62 {
                    let from = Int64(1) << n
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent {
                            // USER-DATA: the seconds left to the next level, as the Time Balance writes a span of time
                            Text(verbatim: MTCoinText.time(Int(max(0, 2 * from - person.seconds)), signed: false))
                                .font(.subheadline.monospacedDigit())
                        } label: {
                            Text("To the next level").font(.subheadline).foregroundStyle(.secondary)
                        }
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
                Text("A second counts while the app is open on any of your devices and a node answers its coin exchange: every few seconds while TimeCoin stands open, at each exchange elsewhere. The node's second, never the phone's clock. Each level doubles the seconds of the one before. Shown only to you, published nowhere.")
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
            // THE FABRIC OF TIME (the author's words 17.10.2026 19:24-19:50 UTC: «the 3rd level ... regular calls over the last 14 days»;
            // «a new level that sets the global one, named Fabric of Time»; 17.10.2026 21:4x «a sliding window of t2 over live activity»;
            // App, «The chains of time a client shows»): the third chain of time -- the level now, the regular correspondents it weighs,
            // the testimonies held in the window, the person's own ceiling, and its chain; through the first τ₂, the days until the
            // first count, the level standing at the ceiling.
            Section {
                LabeledContent("Level") {
                    // USER-DATA: the level of the fabric of time now, a number, or a dash before this life has read it
                    Text(verbatim: fabric.level.map { n in String(n) } ?? "—").monospacedDigit()
                }
                if let days = fabric.graceDays {
                    Text("Days until the first count: \(days)").font(.subheadline).foregroundStyle(.secondary)
                }
                LabeledContent("Regular correspondents") {
                    // USER-DATA: how many correspondents the window weighs now, a number
                    Text(verbatim: String(fabric.regulars)).monospacedDigit()
                }
                LabeledContent("Signatures") {
                    // USER-DATA: how many testimonies of exchanges this phone holds in the window, a number
                    Text(verbatim: String(fabric.testimonies)).monospacedDigit()
                }
                LabeledContent("Ceiling") {
                    // USER-DATA: the person's own ceiling, a number, or a dash before it is read
                    Text(verbatim: fabric.ceiling.map { n in String(n) } ?? "—").monospacedDigit()
                }
                NavigationLink { MTTimeChainPage(source: "fabric") } label: {
                    LabeledContent("Chain links") {
                        // USER-DATA: the chain's length and the first letters of its head's seal
                        Text(verbatim: String(fabric.links.count) + " · " + String((fabric.links.last?.hash ?? MTTimeChain.genesis).prefix(8)))
                            .font(.footnote.monospaced()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Label("Fabric of Time", systemImage: "3.circle")
            } footer: {
                Text("The people you write to and call regularly, each weighed by the level their own time and wallet give them: the greatest number g for which at least g people you exchanged with — words, voice, video, photos, stickers, transfers, games or a call — in each of the last two weeks stand at level g or above. An exchange counts when both of you write: once a day each phone signs that the other's word reached it and gives the signature to the other. Counted again whenever a signature comes or leaves the two weeks; through its first two weeks it stands at the lower of your two levels above. Your ceiling goes only to the people you write to, inside your conversation.")
            }
            Section {
                MTTimeChainRows(sources: Self.talk)
            } header: {
                Label("Chats and calls", systemImage: "bubble.left.and.bubble.right")
            } footer: {
                Text("The chains of the coins your chats, calls and comments minted and burned, and the chain of your wall's posts.")
            }
            // THE EXPLORER (the author's word 11.10.2026 17:2x UTC: «on the TimeChain page an Explorer button to open and check a
            // transaction ... everything professional in the TimeChain, for auditors»): the public page that reads a transfer's
            // record from the nodes and verifies its signature with the core (Audit/COIN-TX-V1.md); every transfer link opens it.
            Section {
                Button { MTExplorerSheet.open(MTCoinTx.explorer) } label: {
                    Label("Explorer", systemImage: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
            } footer: {
                Text("Every transfer is a record on the nodes signed by its sender's seed. The Explorer reads it from the nodes and checks its signature; a transfer's link in the Wallet chains opens it there.")
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
            fabric.prime(); fabric.refresh()   // the third level is read when its page opens (MTFabric)
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

/// The wallet reads the one owner of a second's coin (MTCoinBook.price), the same the book mints by.
/// The player's face changes only with playback state, never with its progress clock.
struct MTCurrentMintRate: View {
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var music = VoicePlayer.shared.face
    var body: some View {
        Text("1 second = \(MTCoinBook.price) coins")
    }
}

/// ONE COIN, ONE SECOND -- ALL THE TOP UP SAYS (the author's word 21.10.2026 14:3x UTC: «on the Top up button on the coins page the
/// information is old -- leave only 1 coin - 1 second, \"Live here and now\"»): only the core mints, by the seconds a person lives
/// (COIN-TX-V3 section 4, fold-6), so the sheet names the rule and nothing that would mint beside it.
struct MTCoinRules: View {
    var body: some View {
        Section {
            Text("1 coin — 1 second").font(.title3.weight(.semibold))
            Text("Live here and now")
        }
    }
}

struct MTCoinTopUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                MTCoinRules()
            }
            .navigationTitle("Top up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("Close"))
                }
            }
        }
    }
}

/// THE CURRENT BALANCE WHERE COINS LEAVE (the author's word 06.10.2026 19:1x UTC: «when I put a stake in chess or send, always show
/// the current balance»): the coin book's balance, live, under the page's title -- above every row and above the keyboard, written
/// as the platform writes a subtitle (its own on iOS 26, the title's second line before it).
struct MTBalanceTitle: ViewModifier {
    let title: LocalizedStringKey
    /// A TRANSFER'S PAGE SHOWS THE AVAILABLE (the author's word 16.10.2026 14:19 UTC: «a transfer from the chat and from any place
    /// shows only the available»): the number the send is weighed by, not the book's whole.
    var available = false
    @ObservedObject private var split = MTCoinSplit.shared
    static func line(_ coins: Int) -> Text { Text("\(MTCoinText.count(coins)) coins") }
    // USER-DATA: a count of coins beside its word
    private var subtitle: Text { available ? Text("Available \(MTCoinText.count(split.available))") : Self.line(split.available) }
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationTitle(title).navigationSubtitle(subtitle)
        } else {
            content.navigationTitle(title).toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(title).font(.headline)
                        subtitle.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// The same balance as one caption, on the plate of an invitation that asks a stake.
struct MTBalanceCaption: View {
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number of the person's coins (fold-7)
    var body: some View { MTBalanceTitle.line(split.available).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
}

extension View {
    func montanaBalanceTitle(_ title: LocalizedStringKey, available: Bool = false) -> some View {
        modifier(MTBalanceTitle(title: title, available: available)).environment(\.mtBalanceAlreadyVisible, true)
    }
}

/// SEND COINS TO PEOPLE (the author's words 03.10 13:53 and 21:53: «in the wallet when sending, everything seen as in the chats'
/// feed; a mass send divides the sum equally»): the pairs' chats in the chats tab's own rows (MontanaChatFace on the glass row
/// plate, the page's own ground), as many as the person picks. The amount is the whole: every picked chat gets an equal share
/// as a coin letter in it (MTCoinSend.transfer), and what does not divide stays with the sender. A short balance refuses
/// before anything leaves.
struct MTCoinSendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var book = MTLocalCoinLedger.shared
    @ObservedObject private var board = MTCoinBoard.shared
    @ObservedObject private var seats = MTSeats.shared   // the persons waiting on this phone's shelf: my other accounts
    @ObservedObject private var split = MTCoinSplit.shared   // the available, the one number a transfer shows and is weighed by
    /// A GROUP'S COIN IS THIS PAGE OVER THE GROUP'S PEOPLE (the author's word 17.10.2026 21:14 UTC, asked whether a coin in a group is
    /// a transfer to one chosen member or no coin at all: «yes, with a choice by check marks among the members, as on the Send page
    /// of the time coin»): the group's key when the page opens from a group's field, nil from the wallet. The rows are the people a
    /// coin of this phone reaches (MTGroup.coinPeople), the picks, the boxes and the fields are the page's own, and each person picked
    /// gets the pair's own transfer -- one record on the nodes for one receiver (MTCoinSend.transfer); the group is only told how
    /// many were paid (MTGroup.tellCoins).
    private let group: String?
    /// Told once coins went, so the field the page opened from empties.
    private let sent: () -> Void
    /// The group's people no coin of this phone reaches, each with why (no pipe of its own with them, or a pair closed to coins).
    @State private var unreached: [MTGroupPayee] = []
    init(group: String? = nil, each: Int = 0, sent: @escaping () -> Void = {}) {
        self.group = group
        self.sent = sent
        _chosen = State(initialValue: 0 < each ? each : 1)   // the number written in the group's field: each pick's coins
    }
    /// EVERY PAIR OF THE CHATS TAB, IN ITS ORDER, EVERY ONE OPEN (the author's words 11.10.2026 14:5x UTC: «put full order in the list
    /// of chats for sending the time coins -- not all chats show on the send page»; 16:5x: «the person is the seed and everything is in
    /// it»): a person is their seed and their wallet is in it, so no row stands dimmed «no wallet yet» (MTCoinSend.canPay).
    @State private var chats: [Chat] = []
    @State private var picked: Set<String> = []
    /// EACH NAME ITS OWN COINS (the author's word 06.10.2026 14:3x UTC: «the field of the coins entered beside the name»): what is
    /// typed beside a chat is what that chat gets; a chat picked with nothing typed takes the box of π last chosen.
    @State private var amounts: [String: String] = [:]
    /// The unit the fields are typed in (MTCoinUnit) and each field's text as typed in it; amounts stay coins.
    @State private var unit = MTCoinUnit.coins
    @State private var span = MTTimeSpan.hour
    @State private var typed: [String: String] = [:]
    @State private var chosen = 1
    @State private var going: [String: Bool] = [:]   // the coins in flight per chat: false while they go, true when the letter stands
    /// THE ONE QUESTION OF THE PAGE (the author's word 11.10.2026 14:5x UTC: «the button Level the top 13 does not work»): three alerts
    /// stood chained on the one list, the levelling's question in the middle of them; one alert now, its words by the case.
    private enum Ask: Equatable {
        case short, level, noBalances, link
    }
    @State private var ask: Ask?
    /// THE SEALING RULE (the financial layer's document, «Montana Financial Layer and Anonymous Owner» 1.0.0, section 5.3; the chairman's
    /// task 12.10.2026, No.65): a transfer between two accounts of one owner links them publicly and forever, so it is never sent as an
    /// ordinary act -- the person reads what it does and agrees, once a sheet.
    @State private var linkAgreed = false
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
                    HStack(spacing: 12) {
                        Picker("Amount", selection: $unit) {
                            ForEach(MTCoinUnit.allCases) { u in u.title.tag(u) }
                        }
                        .pickerStyle(.segmented)
                        if unit == .time {
                            Picker("Unit of time", selection: $span) {
                                ForEach(MTTimeSpan.allCases) { s in s.title.tag(s) }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    .frame(minHeight: 44)
                    .onChange(of: unit) { typed = [:] }
                    .onChange(of: span) { typed = [:] }
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
                                .disabled(split.available < n)
                                .opacity(split.available < n ? 0.4 : 1)
                            }
                        }
                    }
                    // A BUTTON IS NEVER DEAD (the author's word 10.10.2026 12:3x UTC: «in the wallet the button Level the top 13 does
                    // not work»): it stood disabled while fewer than two contacts had told a balance -- on T1 none ever had, so it
                    // never answered a press. Now a press always answers: the levelling's question, or the platform's alert saying
                    // that no contact shows a balance and how one comes.
                    Button {
                        MontanaTrace.mark("coin_level_ask", "told=" + String(topThirteen.count) + " pairs=" + String(chats.count))
                        ask = topThirteen.isEmpty ? .noBalances : .level
                    } label: {
                        Label("Level the top 13", systemImage: "chart.bar.xaxis.ascending")
                    }
                    .frame(minHeight: 44)
                    if !picked.isEmpty {
                        // USER-DATA: the coins of every picked chat together, a number
                        LabeledContent { Text(verbatim: unit.told(total)).monospacedDigit() } label: { Text("Total") }
                    }
                }
                .listRowBackground(MTGlassRowPlate())
                // TO ONESELF ON ANOTHER ACCOUNT (the author's word 11.10.2026 14:13 UTC, No.62: «with several accounts, an option in a
                // transfer to send to oneself on another account»): every person waiting on this phone's shelf, by the face and the
                // name the drawer shows; the coins ride the pipe the two persons share, born on this phone when they have none
                // (MTSeats.pairWithShelf), and the shelf files them in that person's own book.
                if group == nil, !seats.parked.isEmpty {
                    Section {
                        ForEach(seats.parked) { s in
                            let key = Self.seatKey(s.id)
                            HStack(spacing: 12) {
                                Button { toggle(key) } label: {
                                    HStack(spacing: 12) {
                                        AvatarCircle(photoURL: nil, color: .black, initial: s.glyph, size: 40, image: MTSeats.face(s.id))
                                        Text(verbatim: MontanaAvatar.spokenName(s.name.isEmpty ? "Montana" : s.name))   // USER-DATA: the person's own name
                                            .foregroundColor(.primary).lineLimit(1).truncationMode(.tail)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                TextField("0", text: field(key))
                                    .keyboardType(unit.keyboard)
                                    .multilineTextAlignment(.trailing)
                                    .font(.body.monospacedDigit())
                                    .textFieldStyle(.roundedBorder)
                                    .focused($typing, equals: key)
                                    .frame(width: 120, height: 44)
                                Button { toggle(key) } label: { MTPickMark(picked: picked.contains(key), going: going[key]) }
                                    .buttonStyle(.plain)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .listRowBackground(MTGlassRowPlate())
                        }
                    } header: { Text("My other accounts") } footer: { Text("A transfer to your own account links the two accounts publicly forever.") }
                }
                Section {
                    if chats.isEmpty, unreached.isEmpty {
                        Group { if group == nil { Text("No chats yet") } else { Text("No members yet") } }
                            .foregroundStyle(.secondary).listRowBackground(MTGlassRowPlate())
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
                                // THE FIELD IS THE SYSTEM'S AND IT TAKES THE CARET (the author's word 07.10.2026 15:3x UTC: the amount field beside
                                // the check -- active, the system's, with a blinking cursor): the platform's rounded field, and a chat picked
                                // hands it the keyboard at once.
                                TextField("0", text: field(c.name))
                                    .keyboardType(unit.keyboard)
                                    .multilineTextAlignment(.trailing)
                                    .font(.body.monospacedDigit())
                                    .textFieldStyle(.roundedBorder)
                                    .focused($typing, equals: c.name)
                                    .frame(width: 120, height: 44)
                                Button { toggle(c.name) } label: { MTPickMark(picked: picked.contains(c.name), going: going[c.name]) }
                                    .buttonStyle(.plain)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .listRowBackground(MTGlassRowPlate())
                        }
                        // THE PEOPLE NO COIN OF THIS PHONE REACHES stand greyed with why, as the platform draws a row that takes no pick.
                        ForEach(unreached, id: \.seat) { p in
                            HStack(spacing: 12) {
                                AvatarCircle(photoURL: nil, color: Color(montanaHexString: MontanaAvatar.colorHex(p.name)),
                                             initial: MontanaAvatar.initial(title: p.name, name: ""), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: p.name).foregroundStyle(.secondary).lineLimit(1)   // USER-DATA: a person's name in the group
                                    Group {
                                        if p.held { Text("Coins can't go to this chat") } else { Text("No chat of your own with this member") }
                                    }
                                    .font(.caption).foregroundStyle(.tertiary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                            .accessibilityElement(children: .combine)
                            .listRowBackground(MTGlassRowPlate())
                        }
                    }
                } header: {
                    if group == nil { Text("Choose chats") } else { Text("Choose members") }
                } footer: {
                    if group != nil {
                        Text("Each member you pick gets a transfer of their own in your chat with them. The group is told only how many members you sent coins to.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .montanaPageGround()
            .montanaBalanceTitle("Send", available: true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MontanaBarMark(glyph: "xmark", label: "Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    // OUR SEND, NOT A CHECK (the author's word 05.10.2026 15:2x UTC: «put our send button»).
                    Button { send() } label: { MTBarRoundMark(ringed: false) { MTTimeSendMark(height: 22) } }
                        .buttonStyle(.plain)
                        .disabled(!ready || !going.isEmpty)
                        .opacity(ready ? 1 : 0.4)
                        .accessibilityLabel(Text("Send"))
                }
            }
            // LEVELLING ASKS FIRST (the author's word 07.10.2026 15:3x UTC: Level the top 13 needs a mandatory confirmation with a
            // description of what happens next): who receives, how much in all and to what level, said before a field changes.
            .alert(askTitle, isPresented: Binding(get: { ask != nil }, set: { shown in if !shown { ask = nil } }), presenting: ask) { a in
                if a == .level {
                    if !levelPlan().gifts.isEmpty { Button("Level them") { level() } }
                    Button("Cancel", role: .cancel) {}
                } else if a == .link {
                    Button("Send and link") { linkAgreed = true; send() }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { a in
                switch a {
                case .short: Text("Your coin balance is lower than this.")
                case .level: levelWords
                case .noBalances: Text("None of your contacts shows their coins yet. A contact's balance appears here once they turn on Show my coins in their wallet.")
                case .link: Text("A transfer between two of your accounts links them publicly and forever: anyone who reads the TimeChain sees that both belong to one owner. Coins you send to other people never link your accounts.")
                }
            }
        }
        .onAppear {
            guard let store = ChatStore.live else { return }
            if let key = group {
                let people = MTGroup.shared.coinPeople(key, store: store)
                chats = people.compactMap { p in p.chat }
                unreached = people.filter { p in p.chat == nil }
                MontanaTrace.mark("coin_send_page", "group pairs=" + String(chats.count) + " unreached=" + String(unreached.count))
                return
            }
            // Every pair of the chats tab in its order: no group, no room of the phone's own, no blocked or closed person, no device
            // of my own words, one row a person (MTSamePair). A row born before the conversation took its id is named by its pipe.
            let pairs: [Chat] = store.listChats().compactMap { c in
                let conv = c.convId ?? c.name
                guard !c.isGroup, !MTGroup.isKey(c.name), !ChatStore.isLocalRoom(c.name), MontanaConv.holds(conv), !store.refuses(conv),
                      !store.closedChats.contains(conv), !MTOwnWords.mine(conv), MTSamePair.root(c.name) == c.name else { return nil }
                var row = c
                if row.convId == nil { row.convId = conv }
                return row
            }
            chats = pairs
            MontanaTrace.mark("coin_send_page", "pairs=" + String(pairs.count))
        }
    }
    /// The sum typed beside a chat, in the unit chosen: kept as typed, weighed as coins; coins typed pick the chat, a field emptied
    /// lets it go. A sum the page writes itself (a box, the levelling) drops the typed text, and the field shows it in the unit.
    private func field(_ name: String) -> Binding<String> {
        Binding(get: { typed[name] ?? unit.written(coins(name), in: span) }, set: { text in
            let read = unit.read(text, in: span)
            typed[name] = read.shown
            amounts[name] = 0 < read.coins ? String(read.coins) : ""
            if 0 < read.coins { picked.insert(name) } else { picked.remove(name) }
        })
    }
    private func choose(_ n: Int) {
        chosen = n
        for name in picked { amounts[name] = String(n); typed[name] = nil }
    }
    private func toggle(_ name: String) {
        typed[name] = nil
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
    /// The question's title, by its case.
    private var askTitle: Text {
        switch ask {
        case .short: return Text("Not enough coins")
        case .level: return Text("Level the top 13?")
        case .noBalances: return Text("No balances to level")
        case .link: return Text("Link your accounts forever?")
        case nil: return Text(verbatim: "")   // USER-DATA: no question stands, no title is read
        }
    }
    /// The thirteen chats here whose people told the most coins (MTCoinBoard), the most first.
    private var topThirteen: [(name: String, coins: Int)] {
        Array(chats.compactMap { c in board.told[c.name].map { told in (name: c.name, coins: told.coins) } }
            .sorted { a, b in b.coins < a.coins }.prefix(13))
    }
    /// LEVEL THE TOP THIRTEEN (the author's word 06.10.2026 14:3x UTC: «a button to level the top 13»): the poorest of the thirteen
    /// are raised first, every one to one level, toward the richest of them and as far as this book's balance reaches; each gets
    /// its coins beside its name, the richest none, and nothing leaves before the send.
    /// The levelling a press would write, computed for the question and again for the act: the level the balance reaches, who
    /// receives and how much, and the whole of it.
    private func levelPlan() -> (level: Int, gifts: [(name: String, give: Int)], total: Int) {
        let top = topThirteen
        guard let peak = top.first?.coins, let floor = top.last?.coins else { return (0, [], 0) }
        let budget = split.available
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
            typed[p.name] = nil
            if let gift = plan.gifts.first(where: { g in g.name == p.name }) {
                amounts[p.name] = String(gift.give)
                picked.insert(p.name)
            } else {
                amounts[p.name] = nil
                picked.remove(p.name)
            }
        }
        MontanaTrace.mark("coin_level", "top=\(topThirteen.count) level=\(plan.level) total=\(plan.total) available=\(split.available)")
    }
    /// A shelf person's key among the picks: never a chat's name.
    private static func seatKey(_ id: String) -> String { "seat:" + id }   // NOT-UI: the pick's key
    private func send() {
        guard let store = ChatStore.live else { return }
        let to = chats.filter { c in picked.contains(c.name) && 0 < coins(c.name) }
        let toSeats = seats.parked.filter { s in picked.contains(Self.seatKey(s.id)) && 0 < coins(Self.seatKey(s.id)) }
        guard !to.isEmpty || !toSeats.isEmpty, total <= split.available else { ask = .short; return }
        if !toSeats.isEmpty, !linkAgreed { ask = .link; return }
        let each = Dictionary(uniqueKeysWithValues: to.map { c in (c.name, coins(c.name)) })
        for c in to { going[c.name] = false }
        for s in toSeats { going[Self.seatKey(s.id)] = false }
        Task { @MainActor in
            var went: [Chat] = []
            for s in toSeats {
                let key = Self.seatKey(s.id)
                let sum = coins(key)
                await Task.yield()
                let conv = await Task.detached(priority: .userInitiated) { MTSeats.pairWithShelf(s.id) }.value
                guard let conv else { going[key] = nil; continue }
                store.setPeerName(ref: conv, name: s.name, at: Date().timeIntervalSince1970, source: "seat")
                let chat = store.listChats().first { c in (c.convId ?? c.name) == conv } ?? Chat(name: conv, lastMessage: "", time: "", unread: 0, convId: conv)
                // ONE PAIR, SENT AND RECEIVED (No.66, point 0): the SEND names my other key, and its RECV is laid at once by this phone
                _ = await MTCoinTx.knowOwn(seat: s.id, conv: conv)
                if let tx = await MTCoinSend.transferId(sum, to: chat, store: store) {
                    await MTCoinTx.landOwn(seat: s.id, send: tx, coins: sum, conv: conv)
                    went.append(chat); going[key] = true
                } else { going[key] = nil }
            }
            for c in to {
                await Task.yield()   // each ring turns on the screen before its coins go
                if await MTCoinSend.transfer(each[c.name] ?? 0, to: c, store: store) { went.append(c); going[c.name] = true } else { going[c.name] = nil }
            }
            MontanaTrace.mark("coin_send_many", "chats=\(to.count) own=\(toSeats.count) total=\(total) went=\(went.count)")
            guard !went.isEmpty else { going = [:]; ask = .short; return }
            if let key = group {
                MTGroup.shared.tellCoins(went.count, in: key, store: store)
                sent()
            }
            // THE PAGE LEAVES BY ITSELF (the author's word 05.10.2026 15:2x UTC: «the send page must close and carry into our app to go
            // on; now it hangs on the send page and asks an extra action -- constitution 0»): the closed rings stand a breath, then
            // one recipient's chat opens at once (the outside road closes the sheet and the wallet in one move), many close the page.
            try? await Task.sleep(nanoseconds: 450_000_000)
            // From a group the page closes back into the group, where its words now stand.
            if group == nil, went.count == 1, let ref = went.first?.name { MontanaOutsideOpen.chat(ref) } else { dismiss() }
        }
    }
}

/// WHOM THE COINS GO TO BY THEMSELVES (MTAutoReact, the author's word 06.10.2026 14:3x UTC: «on a long press, open a page where I
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

/// THE PICK AND THE FLIGHT, AS THE PLATFORM'S OWN SHARING DRAWS THEM (the author's word 05.10.2026 15:2x UTC: «the right check marks
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
