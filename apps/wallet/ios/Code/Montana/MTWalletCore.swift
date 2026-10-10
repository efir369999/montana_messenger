import Foundation
import CryptoKit
import UIKit

// A reader of the protocol boundary. Missing state stays missing: zero is shown only when
// mtc_wallet_balance actually returns it. This reader never creates a test network or a person.
enum MTWalletCore {
    enum Absence: Error, Sendable { case unavailable, device, person, refused }
    struct Window: Identifiable, Sendable {
        let id: UInt64
        let share: UInt64
        let acceptedIn: UInt64
    }
    struct Snapshot: Sendable {
        let balance: String
        let notes: Int
        let lastConfirmedWindow: UInt64?
        let pulseRunning: Bool
        let windows: [Window]
    }
    static func read() -> Result<Snapshot, Absence> {
        #if MONTANA_PROTOCOL_CORE
        var standing: Int32 = 0
        guard mtc_device_standing(&standing) == 0 else { return .failure(.refused) }
        guard standing == 1 else { return .failure(.device) }
        guard mtc_person_stands(&standing) == 0 else { return .failure(.refused) }
        guard standing == 1 else { return .failure(.person) }
        var bytes = [UInt8](repeating: 0, count: 16)
        var notes = 0, present: Int32 = 0, head: UInt64 = 0, running: Int32 = 0, count = 0
        guard mtc_wallet_balance(&bytes) == 0, mtc_wallet_notes(&notes) == 0,
              mtc_machine_head(&head, &present) == 0, mtc_pulse_running(&running) == 0,
              mtc_pulse_lived(&count) == 0 else { return .failure(.refused) }
        var windows: [Window] = []
        // A bounded view of core receipts; the core retains the source. Nothing here mints.
        for i in max(0, count - 100)..<count {
            var window: UInt64 = 0, rounds: UInt32 = 0, living = 0, share: UInt64 = 0, accepted: UInt64 = 0
            guard mtc_pulse_lived_at(i, &window, &rounds, &living, &share, &accepted) == 0 else { return .failure(.refused) }
            windows.append(.init(id: window, share: share, acceptedIn: accepted))
        }
        return .success(.init(balance: decimal(bytes), notes: notes, lastConfirmedWindow: present == 1 ? head : nil,
                              pulseRunning: running == 1, windows: Array(windows.reversed())))
        #else
        return .failure(.unavailable)
        #endif
    }
    // Formatting the core's u128 little-endian value, without floating-point rounding.

    static func said(_ absence: Absence?) -> String {
        switch absence {
        case .unavailable: return String(localized: "The protocol core is unavailable on this device.", bundle: MTLanguage.bundle)
        case .device: return String(localized: "The protocol device has not joined the network.", bundle: MTLanguage.bundle)
        case .person: return String(localized: "The core has not opened your wallet.", bundle: MTLanguage.bundle)
        case .refused: return String(localized: "The core could not confirm the wallet state. Try refreshing.", bundle: MTLanguage.bundle)
        case nil: return String(localized: "Reading the wallet…", bundle: MTLanguage.bundle)
        }
    }

    static func decimal(_ bytes: [UInt8]) -> String {
        var digits = [0]
        for byte in bytes.reversed() {
            var carry = Int(byte)
            for i in digits.indices {
                let next = digits[i] * 256 + carry
                digits[i] = next % 10; carry = next / 10
            }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }
}

/// EVERY SERVER AND PHONE OF OURS IS A NODE (the author's word 06.10.2026 17:2x MSK: «every server and phone of ours is a node»):
/// this phone opens its own machine of the core -- born once, its secret drawn here and never carried to a second phone -- and
/// reaches the machines of the Global TimeChain's genesis, every server of ours, by the post-quantum handshake of the set. It
/// answers on this phone alone and lives no window: the genesis cohort is the servers, which never sleep, and a machine joining
/// a chain already running is the core's stage fourteen. The person is not opened in the core here: the core keeps a person's
/// entropy in a file, and this phone keeps the words in the keychain alone -- a second home for them waits for the notes that
/// would need it.
@MainActor final class MTNetworkNode: ObservableObject {
    static let shared = MTNetworkNode()
    /// The machines of the genesis (06.10.2026 17:28 MSK), each as its operator handed it over: its name and the key it answers
    /// with. A name, never an address, stands in the build (the author's word 08.10.2026: no address of a node in any published
    /// file); the core resolves it at the dial, and the key in the same line is what the handshake verifies, so a name that
    /// pointed elsewhere would reach a machine that cannot answer with that key and ends in silence.
    nonisolated static let genesis: [String] = [   // NOT-UI: the acquaintance lines of the genesis machines
        "g1.montana.quest:9635@b98a45063346fd71cb8240ff878099e4491682e579e632a84f2bbe08aed1e6f4cb6859e87864edca73c9d47807203d9f72b93b76ebd1c8c93663178f1aef3ee21cd8da1168b5b14b596ca670479266745e5f4f612943a4d7045c286d3d6c58443f2fc1509b90cfc344044f1a81a9b9eecc2b36a7fddac92ec497a9b87caec7850f74ed0759d9f276d6f141df12b2e09a46e77eae691f419bb4622d285d64f6f0835a733bfdeb14c25938963c1e1fe1f76d86c6d887ec82960e06df7167f3ce0fc0e13f9c83bbea75b727b140cc33f1e829027402fce0383adda029f17a1403e6fd4630039090231660e2864d7fbce9de3601f249b039e8e846e47c538e5a8a77bd6a882c1481bd0042aa67b74e32df9407f6381718fcbe30e49b462c07a7d94507c3f0c97236dc7878cd78324d5b72d8e53e77f737d01bac4fc756f557ba5748c252506e1d00f543315354080f540c6ea4e89406b12e759192963c0931a6a8dcd239e3a31d63e3bf5e5bc78c4748e57499b396e6725f1f7e3d28b1dfb89122a1cb0087967f1ca9b00e6be017a063e4994b4ed2301ecc8a745be4edede3ee0c559b739ec651ccdbdf0b56202088241454160a3419aaee8095d3fb9946f4f7141757ac77d743c662a4496d52fb5ac59b381c7246a2dcf5797f630de2a18061decd220b6313b6097d25050dba6ca027bf5ca612a77656dfac3ac3ed6d188e5720d0f887a28ae4c69cfa849df60f121811e3c91356b1050d5e65e84a89e1792dcd974f1d80437ceb1ce6186380640af597aae636c59252636e725bd4977df8eb753094643fc9ba12cbabf58d8cc1348c878fdaeb0b40900c460c9981d8c938cf407a5b14267c65fd12be727b3e33d26c96243f515609dc71c4ccc037937ea3a791961a9f0f96d04dd9957bd1a48991976fecb2c3fc8462477aff85ab943be89af05273135c25416a7f3d3bc7d4fc56d51e5ec2c46913b9759b5cf5ba34b3dae9c1432be74465e003230d1c17a019228b58a96ea5c4c9a55f25174cddaaa80c0d4b5b8860832534f8b9d59faf056bc8b36e8c4f336b57ddcc55f0d575795848abc3fb307519488b2c21da862b9f013e0266aa872c626327207fdfb54371fd09cca07c909b589be052374c3d81227192bd57accc399f48e7e13444b9a03b8d00f2816cac12d0ade28e1578a44f2f3d0a6f7300c7ea139df3ae39e86a350d5dac04af14d4e96d4bdb81dc3e1ec79b44249051341b6796bc1fe6639117bd030118397553001102dcb027c124808ca8a785f0771b428ba085ea39d7341141d60cacb9eedbafff7eb5ceb194b1517be308aade80c5846988d4ba6b481468af03a713aaddeedda25750912869b65e2f12fb5e0b5a74349efd39921961d845208d59f378c200cfebb580fc2448389105c056079bff79bf68bfa91457ed8087e93fb6a9dfe8c096e6ca882befadefbc2a0acc12736f8d70f2e4738f98eb8fcbae598c91ef2d09d95f04b7b39618968671c50b217250a73d08a3c9c248fcd958c0123652fa1a5c6a2103c5ecff9dd2d1d42fda8d13aa31698fad40f303476deb60c76ffa680abe29b371984f1dc9224704133ae755330108f560e33498ce25097a561408aa8ee5e91a48c17ea633538a9a7b204c0e1724fa47af51999becceaf774f5752c7cce89f5147a4a144f59c5c422042d01b9a076485fcc07084f722b315b1db5410d26097b212713d8ccd3aede06baf4511416c0fad3c944238b0021303b468beeccd56d8cd0cf8f867e0e02305126c97b31ea121ba87fcab30545217c91ed05cc1135301ce040b7e40d9f0676423f35f554280175bb2e1d4ed45546645e0eb3b12b99369fafb2a0be54b1fc9e8aae259b06cff683e667e20b370a62a84ae5e0a072be94f0ff56dd37e9e2b4fa0b025978c23b5d82ff7c416ac2694b696dec7a96ddf9d70e213ae7136328e40e2160c8a183b8b27344f64854bf4dce4b5f557cfd04d2eed31e13ea857ee5b6ff099b4a69bc24b6d277a35016b676ea5c85c3b644a0fc054d76852b07d887923319d005ad6272c34732a1a2d030dc83eea56fd0a0a183c740c4f63259161534d95d11b4873313bc13f25f005b959a6b8d1b94ce2a1571cd202bc550a479b4da176fb55d7b48660315caaeb749808751facc2cf22289a8de45a75b16bd895d3a309de3ed65d5f452a83c94239a64bd51c8cd7f7b4f966421ceb734b2bfcc99d3aafff82ed8cd61a528fead4ab737567333a2de08121081a178529e9fd8dfa62c5d3794b5185196f4572776181305f377abbccc35839989be3b93e41def252d29a8b663a7523dc4a05119afe26503717326e5f245a520887c2afea622b337fe3fdbc8be5b8b428a2f37666baf8b3e01261643a066b543edfac9baa6b0fdadf67ebb4fa7bd4bf044cb7f6a184a0aa01988699d813693cff47c0238da7ce6df0a2dd715e369bd676c7697ed19630fb41b80ec5d5d1d9bb4a90571acece58b151a2afaab7aadbbca851cb80af489714f3f602ac3f220987af5bddee280804d3c1391527309e6c6c5df3ffd325137c521f0d34115d227113d9d49bfa831a937f2276da5ce6afa8813fa5282f7c87dd13b77cec86cc5106a787e34c4ff4bf47ccbfdd773384c30ee54739ee2f8c04c8deebd34a1192694cfd8ee2769240d4fd3b50d59087e5102c49e3fb09354eb37eef0125f6fef99f3694c5e7bc234c77da18f8ada4d564423f32a046018b0c74d0d07ede8823fd537077779a",
        "g2.montana.quest:9635@6b57fc1625535534d349ba062458cbc3c06a1826bbcfdd98a788e09f9ea6e67b9fe84d7694a686860038ad394da2fb0f3883dd86f7b924b1e0da67f1a84eea1e0707758dc7120454747dee46fae130ce3f9f71f8187d89a8f60964e11f49855d44a1870791cf55f7db5fcfd8d1ccda04aaedad102d45230124a1a857d60c8b25157c4e9e72932a4b27900e396fda7e6377d8af076a38ba1c54814533a294609706198ee2106ccc59ec31b44f355574be5f10e7fb1e01583450c6d41ec7d9ebd72bee617c01e39433198eaa46ad26f5df77483ed4eaafe1de18160d342c778e3ea20c26e134889c840331adfd9976a3dc9c5ca116caafd0285b316cc003e3a9fd5a8cd9759457c01a7aa9070abc85a72c29608e279c3291eec370405e97d09fe787411cc88ba3353108802f3d1267917a14d64caef4b3e39f3a73d2d4fa02d369862b6008be3a5bce01f42bdf327acfed4ac3a12adb8f8a814e5e3405fede975a113a686f556f7dd361975d51211a88e3f069e67df0587a654a642475aad02ea6560876e984d337ec63cf7e67072c8155d5e2cc01467d188aacf7eaec553440fd9dc68e62b37e2c7c2d6a1a82780b76dba5c77c44f829d84b8f13b894192036b36763fb56457eefcb87b5e2d6cd0eb19930e098f5b21aec5e803d8007b9001a5eb7f8b080ce1f940d7d00d6f7d89747fc2c3d39f86e6916d2624d4d1cab443a57036cf869c3fa3cf2aaff690e08926745691a72f7d475924af03513eaed4d23ae5fe4f69619ff01fa2f68f4a665fd04ac0fb41d8d0d201d05e7da55b0c52f772dd908a710e83e786b134cab6f6346c8512a40ea261cee120123fd176534c600a22dd0b827329e7bfd7cae71d460fc9e5a6b6e02d133765e2ed0216f0787129abea1c708ff237775b8a1ff612219e2afa4a8ae53939c6f427249d58231faec91473928eaaf053c30109bf20c306921dd90cbfb7edd0884186bc1d8416e04f695b74f2bd74c65b2db7543304ce3cab190dcfe5360267dd22e672b4140ff83ffe262d76ae845b49a27684eb5f5616931714f5e55df2cfe7d4335e15538003e07f1fb471efcba92858ff30413693b1928e0e05fc5cdfc6d1f03734862c9d8404a278c6f56400ab92ae3a638f2958bf211c741092132eac0fe7804bdee0cd134605018999d40699d473fde8d57c3438ec53de8cd8823e4c0a04c95f3e5a07e0514ff490efe0ee1bf5b89b25083c705b90960335f4ecfcb369418704bfb3ee9e71fa053eca409fab84cf0318e42f9c5b9876c40f012d66125d3b3d33a433c8d379df84d1ca185adef03fd1abb1c5934c63079d7bee9960d0a2c6e134ed639160d8b5225a4b3bbb47fe48a9233571d01a9b85db1b3c174249f7b971cf48a7c10242334235bfc5e108178269c3fb9b874cd420c9d6795cd0a9cba4538a1a82f610f623fd134dac66c4402a6afcbf2c4a1b7af185aea74e20277bb96f53681d811990eaa7ac6b24e581570a98a31281854dc2fbf1617b183abcd2457b1d638520a11e1a83621f594e729a2298e1e1af7b4a6c817548ad6992cec4dd15c7ccbfc06a19d64d6b1a521ac9da1a528b7d9d8fa3a19f40f21f44776013383467d2957a716ec0110dfa6c3d3bdc34aa0cb2188ab9d5a058da06c1dd924ee3e0e20f1c7b232369a6fb83e18a9bdc2fc6004232bdc1d0a23c48ce3132b56408eeb7e1bdb52c47195e56204a9b4349612f88d231d4afc98b78e74d8ba133bf7605e8261c7d379006a3bd791dc4f4ff47248b109a562e0801c8e6bbdd8a929200238761a14e6daf91e874553a618313c965b645a8f14453bf721dabad4c2fc90e82ea528d8eea6feb1364265805c53426de37c2e5b74c4bc4c561d83a5373f73977c7a20e146984ccd25c4ee1333999f9308a8e8506d125e2b7788c5d4d443fa269ac89a09a09639376d36054f694b6b09b3caaad56cd0d683b030c630b1b0cb610a6aaa87c640b958c0ba4ee43adabb1b09f05c51ae02a7b1caf432c9434b97b9740fa64da4d567181cdfa91b9721422bd49cac6073a9cde4568779b552e6ec1a88aaee3c9141ca3ac23a700c4e2c45bc85a4cd2b283714db9dfff8edd454a262e698e7d23f08343a81df5e98b0b9977725be1b7bf52be8dc112aa838ce0e842b0eb834d059388fa7973c70be2e73c3feb77e8d3b55ef49c7941f2ed8a326728ce8458958d8946112f8a830a14a923bace56b19110f4a6ac2af606401cdd71043f7ef7b0fbeb03fbfd2955c15fb7710c06b9aefe587102fc9dafe6970e988e588aecc892164230a72eed78036d19c0e3dfd5cf50c9a5683a13cef3d5aefe1f2f8c3775d94b63706829ae187825f5c17551ae41d5e13eb40a908597dc46957313b22a9c44b8c2fcf9be2270ea523b83bce874860d080e4ca714d6f8b4d50ed47618b832a7e654a76cce9998dfcdf8155b4b6c5057083822693a376e37f441e5758064dd6b59cf6eccd0d1406e9f5bafc6b6cd158a27a1d528aa347a6e5b22a3a30ab3affe234cea4918ee9d47962aff2221cdb4a2f262bafcd469884024b81fe1e19ef00cb94b414068d608045f66600435c6c3a8e8c9663aada182917645507c8c94100426b990cad4c71b5ef6fedb50a4a96b8ad502d0bb6ea7f23b64c3b96d8dfc19d854bb0ed1585874af9d5c2533bf893ce411cc64ce9ab8ddc79d5bc0272a9d3c4cd08e5313f8c0758d6d59aa2e812c068a067b4b8e016155635ce9b91ca982a99cfe386d888e9",
        "g3.montana.quest:9635@fca3c6562ecb21c08068d8bc35ac94816b276b417f3fccb5e536d865bac46aa2394c1e6fd94d24eca7405acf0240837b64b2e7f6dae3e809ebcace748d844eb360b18fc8cfb6c396cb711a8f2334bbdf00288f4461aede9a2351b40c2cae395867644142e73deb5751960aef0cbed3ab33bed6b35a7e737c9f3bd60e142c8b5f91589196e6a9acdf8297d8939254205ba2f7e5c9afd16acc9e43a8c7ef60b1108404dceb02ad2cb49d1d328566f1d793fcc4e9652f647a8cd9fcca09fad1b5101227abf51c77c940d5a8693b88116c2336bb5f620f4a7ba0d0db120c8800eb06b64e2b08c9dbda255d1c5e3ffa3041130b2f8eaab26d62bfe1a6282b6c3018036442f80b87e0ab210aa1af2065676af30479b4165ec21cf55c1ccf34d278e6e013139a6cf7d47280e95097a6e2358e9bd2dc3e363807bda70ba45d5f6d787b3aea98117d806142dfcd71e599769de41e4661aa9d4dd598e0b3d6610cdd86ad8290e2b6ca5e69e6c692050f8905a6631f40b763ee27e276884379704292312e280d78a416e509abe12f877a1cac55094cd73ce36aa1912e3d96d5f91e88b7b51ac296c2d4c4a0d9da7908a788188952dd98cb75eb963d391961fa27d3bc31b90499127f0c268b3a5554d3aa668cd0c06a8ed2cfa97adfe1a0124a2edcd01f9d4b14d59d3d55ef38da7bac7269b7b1fb30ebc9bdeb2fca497e97642cf3e55459d0a77c3b4da75b952d2cf1fddc615b61ba8207eae38048b85e21e23b30dc9e9d31a36b5b8b4b691165ed63f0983ded232c2f1cb92e37684cdfc04a4fb1cf87d3856d36d4852d24556ee2aa67c4ce91a2c4d4b03cb77b0e78c1097023e8ab176c8e774054f21e7f6aba0fb4c7b3603f7261a1c68703b8ffc7d53aa664aa6378a2edf65053995c81d7da23b4a45974b85b5e9dcef29d78e4dcc377de5dca59e03229956e9a7766b412195888ed5d2d393f62a4235ab7660ba39dec918bea6b5cfbfa7e4e6e1c21d41c1d3ea8ebbd5402225d8c201738357e9a96d9b03d87bbba231e70dd74645d8ef164bf95857cd43518a486999bc97d3c29b4fa26d436249f1bc8d2ce6309376c1a47f14ab338bdfefc2cd65ee1ed4f7e030abcbe408fe1c539a9db25a1733774090d766184c0cc9e1b91ab441fd6a77eb0c879829f09344d780c380e04efc5ff40fe2199904a9cdc372e36645a1caca17734cf7b8e945e9391d028e0391b55d2f29234fd324a0ed4653c67592d3c2cd26c28455d28f686ed9a5b06f805a6cc599229d629fbeab50ca042ddac7f40d93a8c620f0ec9b1b0a096e65faf53e41f61cbc40ec3aedde99f01bd57fb107f6e0ddf5701d8aa259c426f6e5453e27adb863c111e24e65f480092e34a05ddabc1b877696c4f33284521866ef00a09cc5806559c2601dc23d83c7d0270975fd34d7297383f24055d69cb157c81e8ce759d0f6567d0f3cea80c246dfd75f9ea1ee84814a2a1b2ed31a7fbd163575c795040ad1a0cd8ed31852f97ad8f13ce5290b1d43709958f90546a1af7533afc3ddfa0e24ea000ee31d5fff8126509a668e4a166dafb9c8c2ddffab82529555b16d79cbcc9eea1a6e8d583c60bff45b0815bface213b3ddbc49d39cef678b40a891b481957d6b5e0840a97aaf2a3147684611cb0e0ec34c568f446c5e9aa606e28f6ad1db2470c3a072b5801950b4c883484cc42a3dc903f8e2bb548391d44d8d9d4b9d204cdd8f3772aeda47c203196102264a2eb992600b9c2af0c1b904dbfa25da1054e005414d7c7950605fa176135d4f0d7829ce512b7e598a269fff4fb9c554c76004d23a6bdbab671e311d1abdaa80b7d9a32740791c942ab1cba7694e19f8344edb889924491b50fea5245433b039e9bf2ad61fa5916c3ed9e74ece518e0d85ac7ff1a02c9201867c56c49c4b4a7d02c272e5d09ea69f01a50484654f3b2fd11af894991957b45763d9010aa0ff478cc1d36afc774d2bb5f398460c6fef0ce10af4601a16c96a5075706544114ea21206c777ed8043abe369f717f6519fcfa4ca03280bd3f303982470df62f29d78014725dac4a0f2acca51d99cf63ac793d28095f4115a591a1df23d8504c12d8a70264c1d8513f02762cd941e34293030e46a8c131c493323f34d8f17b8a00a5ecd4315ca32de223b14fae4890992c39f21a027de866da47ab914379962a4349111828d2f628d9ce608f95a5817ec67580674ac599acb7a17245621c15d46a3edb8a66e59760c66fd012e036a8f6b043755830fb4b361e4083ff87a60b064bb6be9ce370af1989636d4ecb2a6ec743a3c1e730419c08d0a2eaad2b258ba33affe00598d8831ea692aced857ddb51324a00b2caf271e875d3173a72b770ad795ce5def45eaa3809f755419ca43c58cb466517e663c695d3ee4f6b5b8ece2ad637ce55cc7194685bbc164721fd6a13373de03fcffee1c412f6bc207a746aa111ea2c9c67456716afd80c2694a8beb4cc51e2b1a6712b4c33fcd205115b5290f0b3bae438ba2484238b6fab49679b8ede75957e2f12ff5f3fd4200ec7dc9649e3c4556040007b6574ad39f32e6c9abda45551027c5b05b11a343569335193402cbad64b868cb004f5d87e53071239c12080bca01574625e2d9bb89dafc30c9340038a21b83771cd1d88a106bf139c6adb13d589df436aef78eb87ae1e3e870487b551677444e592048d9332d71688ab8d8d871af18de597ee07ac5a9fd0601c645a77729ea1795eb21a3da3a266",
        "g4.montana.quest:9635@6348c9d2462edf6bffe68a628dc60dfdc87437ae9cc344824e34358735e24a4c760f28653df98b0b49ac8366ebfc28807927d13414f83da6702cdef1f45dde9fa3983c8a03abf2517ba7b83e94a906adba61db5cde0044e19cb33e5317ebaab9281a6e866f29a54e6e6e7791638ef2645c7571f0caa325a415a4fc6f61fb42778300c8933a31a2da14ab8f7ab0ad50fded6b1372c6d5198c7c679dbf4e3b855882285d37e919c4e7f5ce0657c3dde0f6b65d484cb86f31ab03651c220ed9af635a54e6cc83fa88e285df3f6a2a8751435418f5a86884bfbd9bed2cbf15f9bb2431e62a2f5a8672c27198d51478e033c69b2625fdb50662cf34b15be92d480a7f5be5c284f049160fea7daad6a1d3303b9e6d67919dfd138988ff53177afeb78eefb38bb0dc4143a2943dbb087ee39e4f46e84316c47b3139f6bcb9137cf1630db81d6702a60d3c222242b65618d0e83d84e08ff7b00f3d7c2b2ce4428a00d9b0d4434794da10a4cc20eeff9682d47c1fb9f111219d87547486517f2020777b829c3dca0965f4d3305000392c9d0b48e74f961cd42df0c3f7d5d8323dc5ada969112ddfa06e2720eb3a134e7844c39e318d074eb160ca604a0099f935ca96772f2015fb8326463639728189265a9c1a8b810acb52dc263c0ca00e9a173a172d1ed6de2d43919b9e2875a0fa842cf544cee159af407929d97a1a11c002875c92b1bd1b48702698028c2cc576419bcbcd9a9e9042a535344d7d4bbeabf4891de91943e7d5ece08ddfa0406067645d68fc35d361cb4c7634e9b65c6dee8111351d5e9350fed8bf4b22214add6b8d08b75bab4f4b78deb5d75bf11ebac17da0cb28e32a994b6f44a54df04232bdd7427e50df011f970cd00c7e074400e3ff9997b7a3084e171b1e18614010fe0bf3d386a912ee13a87353fb945dd228e70d20be2d7bbe9a0b9ca40436c15dd8b61073cea908fb98cf229dc0d738dffd7ef214023ff836992774b0a117629c9a45bc312fd23231d81fa823581ce37517c72473622987121c57b9de61208b07041d4797751df2a5f1b16b1247e3e9afb8793a48f492c6c0a69318e5b2c364e3a2259a4ac9eb7a67852de180b8abd5de899427c60c8f221b6c19a357b888ab9f2f512a202326c78ebafcab08577197fa0a04b2de44269adae048fa7b83db9e7811eb1c82812b92df9274a4f093def6cde245bcba6733c271272c6e1d07dac8688ce12c5d64b3829e664bd1a3578c6852024d0caddd6e0385609564cf956b2c9d185406db4cb9694aeb053127dbfd75105a93de3714c93a42b59b897da99bea291d17b619b0ad7639759714d9f07a91c3a987b3771b101afe0b3df716b9e15a89da4727e212800c17a0e9e94a364df5fcc6279473d0a3b8aeaade69dc0fe4bad54e012092b146dfadefb522a6de9dc7a164093808df94f138571d4fdffa0e6809932e79ac2be46070670f227a6175c3a5542d377fb0dc235699fdded38fdbf84ed231f1106ded54b96645bb9b15cca28c07c9c6f170fc26ddc1636efba54eee21d571161143c0ccbf8f3d2693a42e7415c342a48a9fd3724f8d101f57be68debe357a4ca0546d3d83efae38afaa3cba9af246a49d8f7a809a0bf3600cca3e3e99c801655550fa0c18984a83ea34ec7ffa3237f79cca994da9a139c32ff8c66021f8a4235c4de754335e2d12ca6a67f0a5b300e9f1574b32c7207e9b6b6938d83bdf7851b20fd5709fb2d08aeb8c41ef93da429988118d68973c98321e3330016ef966f6ffd1cda3a1bc2d5890c4476831b6c5ddf45bd7581e6bcbf15a608cecc59182432366447354296f95c5151edd908930c17774aa9756b1e867d83df4db25b4bb355eb63a4353439713f560f878c04660864f2792a68c4f4b876c74507f9fff4569a85e9d8448a7ed6fe5b772e8ac6d3bed77d66f3a05cd33f6db23001233d654c3a4fb8801d79c369e48739d04dadab6a81db0a6115c2842ea87fadb289b679418d0c4872f5c6168aee32f210228a099e6da3e3bc33fd9d074151c5f36d888169902d252304971e93aa8d4589c23c82e1d6c73170fe6f335254381b7ee9dcb6a8700dfa8fde34c622e9ae4ebf6e30a236fdad90470206fb165956fe945b02b737c7b4216c94952595bdc135a63087d779c19433bbb278917d3bab97f190325f4717c487816dcf502ae531f6a205c19c88f1b15e1ad1e745bac42dec1b3c870b8d4ad027177cacb05434c474d7930fc112bfd137767273e7af86e29a149c693904f7a38468de579cf9e5b7a7a6a4441ca147fca256ba510d29c8366bc4003753f9def49eaab6d824690c01b740e1a99182a5939bef9c90e9c92316e3ef8a3f4007882ff0831461e63ce452b23cad821c43ebd25eb5f0bc994219ad66ac2d3d6f51953a5c256949116ca68a435790a76f7fdddb2ebfbec14e89beb05fa9432517b9abc33d1bb72508ad69128163284c8cd28e45a66cc878ccd6b3e6b08f92d2141a3f5fd719f7f0c09b005e87b3c6807aae40f9c34cfadc0d7aa6247a9f5175e067b91a02d4dc5d9e28a5ccd54cb5e27a8661541361540f77b5a0c1ea3a6d32564b67061b52bc6ac30980c622daaa53620d2fb7de6f692ae9a2b5eb0b689f1fe156c90aae4892f58900e0db6aa955cb343ca0525d350cd3550ed63ebc6bac217fcd46a5b68820edf845a610b719bce046a9c68e22d9fd8fed88435202227275240b97ea9d4103828b755004ab86980616d17e4d7231a"
    ]
    nonisolated private static let dir: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Montana", isDirectory: true).appendingPathComponent("Core", isDirectory: true)
    /// How many machines of the genesis this phone's node holds a link to, each by a handshake both sides computed; nil while
    /// its machine is not opened.
    @Published private(set) var reached: Int?
    private var held = Set<Int>()
    private var joining = false

    /// The node opened once and every machine of the genesis it does not hold yet reached, off the main thread.
    func join() {
        guard !joining, held.count < Self.genesis.count else { return }
        joining = true
        let missing = Self.genesis.indices.filter { i in !held.contains(i) }
        Task.detached(priority: .utility) {
            let got = Self.reach(missing)
            await MTNetworkNode.shared.joined(got)
        }
    }
    private func joined(_ got: [Int]?) {
        joining = false
        guard let got else { return }
        held.formUnion(got)
        reached = held.count
    }
    nonisolated private static func reach(_ missing: [Int]) -> [Int]? {
        #if MONTANA_PROTOCOL_CORE
        guard let dir else { return nil }
        var standing: Int32 = 0
        guard mtc_device_standing(&standing) == 0 else { return nil }
        if standing == 0 {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            // The machine's secret is this phone's: no backup carries it to another device.
            var kept = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? kept.setResourceValues(values)
            var born: Int32 = 0
            let rc = dir.path.withCString { d in "127.0.0.1:0".withCString { l in mtc_device_open(d, l, &born) } }
            MontanaP2PTrace.mark("core_node", "open rc=\(rc) born=\(born) \(said(rc))")
            guard rc == 0 else { return nil }
        }
        var got: [Int] = []
        for i in missing {
            let rc = genesis[i].withCString { line in mtc_machine_reach(line) }
            MontanaP2PTrace.mark("core_node", "reach \(i) rc=\(rc) \(said(rc))")
            if rc == 0 { got.append(i) }
        }
        return got
        #else
        return nil
        #endif
    }
    nonisolated private static func said(_ rc: Int32) -> String {
        #if MONTANA_PROTOCOL_CORE
        guard rc != 0 else { return "" }
        var out = [CChar](repeating: 0, count: 512)
        var len = 0
        guard mtc_last_said(&out, out.count, &len) == 0 else { return "" }
        return String(cString: out)
        #else
        return ""
        #endif
    }
}

/// THE CHAT'S COINS (the author's words 02.10 18:29, 19:24 and 19:37: «while the coin is on in a chat and the chat is turned
/// into the ribbon of time, every letter drips one billionth of a Montana to the person, equal to one coin; the balance shows
/// on the wallet at once»).
///
/// LOCAL TALLY, NOT MINTING. Nothing here is a note of the wallet and nothing here is added into the confirmed balance. The
/// protocol core has no door that mints for a letter (montana_core.h), and this phone's wallet is not opened: mtc_device_open
/// is called nowhere, and which person the wallet is, is the author's choice -- no identity is picked or invented here. What
/// this keeps is the honest count of the letters that earned a coin, so the real mint can take them over by the one seam
/// (mint, below) the day the wallet opens.
///
/// THE RULE, the same reading on both phones: a letter earns one coin when it carries a wire name («mid:t<ms>-<uuid>», the
/// name both phones hold byte for byte -- MTLetterSeal), it is a letter of the pair rather than a local row (a call log row,
/// a missed-call row and the room's words begin with the invisible service mark and are each side's own), and it was born
/// (the millisecond in its name) while this phone's coin was on. A name earns once, ever: the names are kept in a file and
/// read again at launch, so a turn off and on, a second opening of the chat or a relaunch never pays a letter twice.
@MainActor final class MTChatMint: ObservableObject {
    static let shared = MTChatMint()
    /// One coin is one billionth of a Montana (the author's word 02.10 19:37).
    static let coinsPerMontana = 1_000_000_000
    /// LOCAL TALLY: the count of the names kept below -- never a wallet note.
    @Published private(set) var coins = 0
    /// MINTING IS ON SOMEWHERE (the author's word 03.10 13:40: «the wallet shows the minting coin while minting happens
    /// anywhere»): the ribbon of time stands, so every letter of a pair's chat earns. The wallet's coin spins by this.
    @Published private(set) var minting = false
    /// EVERY MINTING IS SEEN (the author's word 03.10 16:46): one more each time letters earn, and how many the last time --
    /// the chat's +1 turns its coin by this (MTMintPop).
    @Published private(set) var minted = 0
    @Published private(set) var lastBatch = 0
    private var earned = Set<String>()
    /// The moment this phone's coin was switched on (seconds since 1970); zero while it is off.
    private var since: Double
    private static let sinceKey = "chatCoinSince"
    /// A letter is looked at only near the moment the coin came on: a list walked from its newest end stops this far
    /// before that moment, so a long chat costs the letters born since, not its whole history.
    private static let margin: Double = 600
    private var file: URL? { MTCoinPlace.file(MTCoinPlace.tally) }
    private let disk = DispatchQueue(label: "montana.chat-mint", qos: .utility)

    private init() {
        since = UserDefaults.standard.double(forKey: Self.sinceKey)
        load()
    }
    /// The person lifted into the seat: their names and their coin's moment, read again (MTCoinBook.reread).
    func reread() {
        earned = []
        since = UserDefaults.standard.double(forKey: Self.sinceKey)
        load()
    }
    private func load() {
        if let file, let text = try? String(contentsOf: file, encoding: .utf8) {
            // A line cut short by an ended process is no name: only a whole wire name counts.
            for line in text.split(separator: "\n") where Self.wireName(String(line)) { earned.insert(String(line)) }
        }
        coins = earned.count
        minting = since != 0
        // ONE BOOK (the author's word 03.10 13:53: «the coins from chats agree with the ledger»): every name this tally ever
        // paid stands in the coin book as one earned coin -- the names of the builds before the book are taken in here,
        // once, by their own names.
        MTCoinBook.ledger.earn(Array(earned), times: 1, peer: nil)
    }

    /// The coin of a chat switched on or off: the letters born from now on earn while it stays on.
    func turned(_ on: Bool) {
        since = on ? Date().timeIntervalSince1970 : 0
        minting = on
        UserDefaults.standard.set(since, forKey: Self.sinceKey)
    }

    /// A GROUP'S AND A CHANNEL'S LETTER EARNS WHEN ITS BUBBLE HOLDS MORE THAN THIRTEEN (the author's word 05.10.2026 21:4x MSK:
    /// «in groups and channels credit coins for the messages by the user's level when the text bubble is more than 13
    /// characters with spaces»): the count is the bubble's characters, spaces included; the level's rate is the book's.
    static let groupLetterFloor = 13
    /// A TEXT BUBBLE (the author's word 05.10.2026 22:41 MSK: «x100 is credited only for a text, and more than 13 characters in
    /// it»): words alone -- no picture, video, voice, file, coin letter or chess step, no row of the phone's own. A floor passes
    /// only these, in a group's or a channel's feed and in the Money Flow alike, and counts their characters.
    static func isText(_ m: Message) -> Bool {
        m.imageFile == nil && m.videoFile == nil && m.audioFile == nil && m.docFile == nil
            && m.coinLetter == nil && m.chessLetter == nil && !MTRowLetter.ownRow(m.text)
    }
    /// The letters of a chat shown in the ribbon of time, oldest first as the store keeps them; a group's and a channel's
    /// feed passes its floor, and a letter of that many characters or fewer, or no text bubble (isText), earns nothing; the
    /// Money Flow mints the level's coins a bubble of any kind, by its name (oneEach, MTMoneyFlow); a group's or a channel's letters
    /// name their conversation (key), and their coins stand in their own chains.
    func credit(_ letters: [Message], longerThan floor: Int? = nil, times: Int = 1, in key: String? = nil, oneEach: Bool = false) {
        // THE BOOK IS HEARD BEFORE A LETTER MINTS (09.10.2026, the author's words: «only unambiguous mathematics; the restore must
        // bring back the incomes and the expenses right»): the tally of letters paid lives on this phone alone, so a phone opened by
        // its words paid every letter again at today's level before the seed's vault answered -- the same name under another
        // amount than the one every other device holds, and the vault's move passed by its name. Nothing mints until the vault
        // answered; the walk takes every letter since the coin came on, so a letter waits and is paid by the book that holds it.
        guard MTCoinVault.shared.heard else { return }
        if since == 0 { turned(true) }   // a ribbon kept on from a build before the coin: it earns from this moment
        var fresh: [String] = []
        // NO LIMIT ON THE MINTING (the author's word 03.10: «no limit on the coins earned, architecturally»): every letter born
        // since the coin came on is looked at -- a run of letters paid before no longer stops the walk, so a letter that lands
        // late among many newer ones is paid too.
        for m in letters.reversed() {
            if m.createdAt < since - Self.margin { break }
            if earned.contains(m.mid) { continue }
            if let floor, m.text.count <= floor || !Self.isText(m) { continue }
            if oneEach, m.coinLetter != nil || m.chessLetter != nil || MTRowLetter.ownRow(m.text) { continue }   // a bubble of words or media alone
            guard Self.wireName(m.mid), !m.text.hasPrefix("\u{200B}\u{200B}"),
                  let born = ChatStore.birthMs(fromMid: m.mid), since <= born else { continue }
            earned.insert(m.mid)
            fresh.append(m.mid)
        }
        guard !fresh.isEmpty else { return }
        coins = earned.count
        // THE CHAT SHOWS THE LEVEL'S COINS (the author's word 04.10.2026 12:23 MSK: «one function of the level's multiplier
        // everywhere»): the rising «+N» is what the book paid at the level's rate, not the count of the letters.
        lastBatch = mint(fresh, times: times, peer: key, oneEach: oneEach)
        minted += 1
        MontanaP2PTrace.markFolded("chat_coin", "earned=\(fresh.count) paid=\(lastBatch) coins=\(coins)", window: 60)
    }

    /// The coins this tally paid for one chat's letters, both sides' -- the chat's common count (the author's words 03.10).
    func count(in letters: [Message]) -> Int { letters.reduce(0) { earned.contains($1.mid) ? $0 + 1 : $0 } }

    /// THE ONE SEAM between a letter that earned and the wallet. The names go to the coin book (MTCoinLedger) -- one coin each,
    /// in the same move, so the wallet's balance rises the instant the letter is sealed -- and are written down here as the
    /// tally's own memory. REAL MINTING belongs behind the book's protocol: the day the core opens this person's wallet and
    /// offers a door that mints a coin for a letter, the book that answers MTCoinBook.ledger hands the names to that door.
    @discardableResult private func mint(_ names: [String], times: Int, peer: String? = nil, oneEach: Bool = false) -> Int {
        // ONE COIN TIMES THE LEVEL A BUBBLE (MTMoneyFlow): the level read at every name, minted by the bubble's name -- the name keeps
        // it one, whichever door asks.
        let paid = oneEach ? names.reduce(0) { sum, n in sum + MTCoinBook.ledger.mint(MTPiLevels.multiplier(MTCoinBook.ledger.balance), ref: n, peer: peer) }
                           : MTCoinBook.ledger.earn(names, times: times, peer: peer)
        guard let file else { return paid }
        let lines = Data((names.joined(separator: "\n") + "\n").utf8)
        disk.async {
            if let h = try? FileHandle(forWritingTo: file) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: lines)
                try? h.close()
            } else if !FileManager.default.fileExists(atPath: file.path) {
                // Born only where none stands: a file that stands but would not open is never written over.
                try? lines.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        return paid
    }

    /// «mid:t» + birth millisecond + «-» + a uuid: the name a sender mints (ChatStore.mintMid).
    static func wireName(_ s: String) -> Bool {
        s.hasPrefix("mid:t") && s.count == 5 + String(s.dropFirst(5).prefix { $0 != "-" }).count + 37
            && UUID(uuidString: String(s.suffix(36))) != nil
    }

    /// The coins as Montana, in integers alone: one coin is 0.000000001.
    static func montana(_ coins: Int) -> String {
        let whole = coins / coinsPerMontana, part = coins % coinsPerMontana
        let digits = String(part)
        return MTCoinText.count(whole) + "." + String(repeating: "0", count: 9 - digits.count) + digits
    }
}

/// BIG NUMBERS PART THEIR THOUSANDS WITH COMMAS (the author's word 04.10.2026 04:20 MSK: «the separators of big numbers are
/// commas»): in every language of the phone, the one owner of how a count of coins reads -- 1,234,567.
enum MTCoinText {
    static func count(_ n: Int) -> String {
        let digits = String(n.magnitude)
        var out = ""
        for (i, d) in digits.enumerated() {
            if 0 < i, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(d)
        }
        return (n < 0 ? "-" : "") + out
    }
}

/// THE THIRTEEN BOXES OF π (the author's words 03.10 21:59-22:02: «boxes by the number π, ascending by share of emission, the
/// top thirteen»; «on the coin's badge your number in the rating»; «when sending, the same thirteen boxes in the reaction»;
/// «a table of the top thirteen in the wallet by a button»). Box n holds the first n digits of π as whole coins -- 3, 31,
/// 314 … 3 141 592 653 589 -- each a share of a Montana (a Montana is a billion coins). A balance's place is the number of
/// boxes it fills, read on this phone from its own book; the same boxes are the amounts a person gives.
/// LEVELS BY PI (the author's word 04.10.2026 12:23 MSK: «call them levels by pi instead of boxes; if I am of level 5, all my
/// minting everywhere is counted by one function of the level's multiplier»): the boxes of 03.10 are the levels of π, and
/// `multiplier` is the one function every minting asks -- the book applies it to every earning and every minting.
enum MTPiLevels {
    /// THE LEVELS HAVE NO BORDER BUT THE INTEGER'S (the author's word 04.10 00:51: «the wallet's level is defined so, without
    /// borders, 13 always»): nineteen digits of π, the most a count of coins holds; the wallet shows thirteen of them at a time.
    static let digits = "3141592653589793238"
    static let all: [Int] = (1...digits.count).map { Int(digits.prefix($0)) ?? 0 }
    /// How many levels stand on the page at once.
    static let shown = 13
    /// The number of levels the balance fills: 0 below the first.
    static func place(_ balance: Int) -> Int { all.filter { $0 <= balance }.count }
    /// THE BOX IS THE MINTING'S MULTIPLIER (the author's words 04.10.2026 03:06 MSK: «every open box is a multiplier of the minting:
    /// box 1 one coin, box 2 two coins for a tap, a move, a chat and everywhere, as the box's invariant; box 5 five coins a tap»):
    /// every coin minted anywhere is the box's number of coins, one below the first box. Each next box asks about ten times the
    /// coins of the one before (the digits of π), so the rate grows with the logarithm of the balance, and time still bounds it.
    /// «Every mechanism multiplies by the level, and the minting's highest level is 13» (04.10.2026 17:27 MSK): the price of a second.
    /// THE MUSIC DOUBLES WHAT THERE IS (the author's words 05.10.2026 14:16-14:17 MSK: «music is a hidden ×2 to what there is, at
    /// any level: level 5 gives 10, not 13»; «even if you already have the limit of 13, it doubles»; «music ×2 above the limit of
    /// 13, up to 26 a second»): the level's coins, bounded by the most a second mints, then twice that while a track plays.
    static func multiplier(_ balance: Int) -> Int { min(MTCoinBook.limit, max(1, place(balance))) * (musicPlays ? 2 : 1) }
    /// The most one second mints, all minting together (MTLocalCoinLedger.priced): thirteen, twice that while a track plays.
    static var ceiling: Int { MTCoinBook.limit * (musicPlays ? 2 : 1) }
    /// A track of the music plays: not resting, not a voice -- a voice and music are two things (10.09), and a voice taking the
    /// player is a voice before its sound starts, while the track's facts still stand (VoicePlayer.park(handing:)).
    static var musicPlays: Bool { let p = VoicePlayer.shared; return p.currentTrack != nil && p.playingFile != nil && !p.paused && !p.isVoice }
    /// π as far as a level reveals it: 3, 3.1, 3.14 ...
    static func revealed(_ place: Int) -> String {
        let d = String(digits.prefix(max(0, place)))
        return d.count < 2 ? d : String(d.prefix(1)) + "." + String(d.dropFirst())
    }
    /// Coins in the short form the author named (03.10 21:19: «1k, 10k, 100k and so on up to a whole Montana, 1kkk», the k in the person's language): whole
    /// thousands, millions and billions, never rounded up -- the badge says at least what is held.
    static func short(_ n: Int) -> String {
        let k = String(localized: "k", bundle: MTLanguage.bundle)
        if 1_000_000_000 <= n { return String(n / 1_000_000_000) + k + k + k }
        if 1_000_000 <= n { return String(n / 1_000_000) + k + k }
        if 1_000 <= n { return String(n / 1_000) + k }
        return String(max(0, n))
    }
}

/// THE COINS RISE AT THE SIDES (the author's words 04.10.2026 00:11 MSK: «auto minting one coin a second with an animation at
/// the sides»; «at a chess move the coins' animation too»): the one owner of the minting's sign. The book tells it at the birth of
/// every coin it mints (MTLocalCoinLedger: mintInWindow, earn) -- a coin rises only when it is born, with what the book took -- and
/// every screen that wears the sides (MTCoinSides) shows the same coins rising at both edges with the count.
/// ONE RISE, THE SUM (the author's word 04.10.2026 18:08 MSK, T2: «the minting's animation must not double, only give the sum in
/// the plus animation»; T2's diary 15:10Z: the pull's +5 and the VPN wall's +5 rose apart every second -- the first coin rose at
/// once and the coins after it rose again half a second later): while the minting by the second beats (MTMintBeat), the beat
/// alone raises the coins, once a second, with the sum of everything minted in that second; without it the coins gather a fifth
/// of a second and rise once, twice a second at most (the heat, 04.10 12:27).
/// THE APPS THAT MINT (the same word: «above the coin the icons of the apps that give the minting; on the badge the level and x2
/// beside it»): the app of a coin is the app of its TimeChain (MTTimeChain.app, constitution point 4), and an app whose coins were
/// born within the last second and a half mints now.
@MainActor final class MTCoinFlash: ObservableObject {
    static let shared = MTCoinFlash()
    @Published private(set) var tick = 0
    @Published private(set) var coins = 0
    @Published private(set) var apps: [MTApplication] = []
    static let gather: Double = 0.2
    static let apart: Double = 0.5
    static let lasting: Double = 1.5
    private var held = 0
    private var gathering = false
    private var rose: Double = 0
    private var minted: [MTApplication: Double] = [:]
    private var looks = 0
    func born(_ n: Int, ref: String) {
        guard 0 < n else { return }
        let now = Date().timeIntervalSince1970
        held += n
        if let app = MTTimeChain.app(MTTimeChain.source(ref: ref, kind: .earn)) { minted[app] = now }
        guard !MTMintBeat.beats, !gathering else { return }
        gathering = true
        let wait = max(Self.gather, rose + Self.apart - now)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self?.rise()
        }
    }
    /// The coins held rise now, with their sum; the beat calls it once a second.
    func rise() {
        gathering = false
        if 0 < held {
            coins = held
            held = 0
            rose = Date().timeIntervalSince1970
            tick += 1
        }
        look()
        looks += 1
        let at = looks
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.lasting * 1_000_000_000))
            guard let self, self.looks == at else { return }
            self.look()
        }
    }
    private func look() {
        let now = Date().timeIntervalSince1970
        let fresh = MTApplication.allCases.filter { app in minted[app].map { at in now - at < Self.lasting } ?? false }
        if fresh != apps { apps = fresh }
    }
}

/// PANTHEON ON FIRE (the author's word 03.10.2026 22:25 MSK: «a tap on the coin in the wallet is +1 too, quick taps all count;
/// the coin spins at a speed from 1 to 13 and the speed is shown; the game is called Pantheon on Fire, the first tap on the
/// wallet's coin lights it»). Every tap mints one coin into the one book. The speed is the taps of the last second, and a tap
/// past thirteen in one second mints nothing -- time bounds the coins, not a quicker finger ([I-15]). The speed falls to zero
/// when the taps stop: the number shows the taps, it never holds them.
@MainActor final class MTPantheon: ObservableObject {
    static let shared = MTPantheon()
    static let ceiling = 13
    /// A tap's coin in the book: the prefix, the millisecond and a uuid -- a name taken once, ever.
    nonisolated static let refPrefix = "tap:"
    @Published private(set) var lit = false
    @Published private(set) var speed = 0
    private var taps: [Double] = []
    private var holding = false
    /// THE FIRE RESTS AFTER A MINUTE (the author's word 04.10.2026 13:38 MSK: «at the Pantheon on Fire's activation, under the level's
    /// progress, a progress of the minting's unbroken run too; when it runs unbroken over 60 seconds, the next 60 the minting
    /// pauses»): a burn counts its seconds from its lighting; at sixty the fire goes out and the coin rests sixty -- no tap mints --
    /// and the next burn counts anew. The quiet that puts the fire out breaks the count (MTPantheonStreak draws both).
    static let streak: Double = 60
    @Published private(set) var litAt: Double?
    @Published private(set) var restUntil: Double?
    private var resting: Task<Void, Never>?
    var rests: Bool { restUntil.map { Date().timeIntervalSince1970 < $0 } ?? false }
    private func light() {
        guard !lit, !rests else { return }
        lit = true
        let at = Date().timeIntervalSince1970
        litAt = at
        MontanaP2PTrace.mark("pantheon", "lit")
        resting?.cancel()
        resting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.streak * 1_000_000_000))
            guard !Task.isCancelled, let self, self.litAt == at else { return }
            self.rest()
        }
    }
    private func rest() {
        going?.cancel()
        lit = false; litAt = nil; speed = 0; taps = []
        let until = Date().timeIntervalSince1970 + Self.streak
        restUntil = until
        MontanaP2PTrace.mark("pantheon", "rest")
        resting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.streak * 1_000_000_000))
            guard !Task.isCancelled, let self, self.restUntil == until else { return }
            self.restUntil = nil
            MontanaP2PTrace.mark("pantheon", "rested")
        }
    }
    private var settling: Task<Void, Never>?
    private var going: Task<Void, Never>?
    /// THE FIRE GOES OUT IN THREE SECONDS OF QUIET (the author's word 04.10.2026 03:13 MSK: «if you do not mint for 3 seconds, switch the
    /// Pantheon on Fire off»; before it, a minute, 04.10 00:19): while it burns the wallet's page does not scroll at all.
    static let quiet: UInt64 = 3

    /// A finger landed on the coin: the game lights at the touch itself, so the page stands from the first finger, before its coin.
    /// THE FIRE BURNS WHILE A FINGER HOLDS THE COIN (the author's word 04.10.2026 13:06 MSK: «if I press and hold the coin in the
    /// wallet, do not switch the Pantheon on Fire off, and after the seconds switch the auto minting on»): on T1 the fire went out
    /// at the third second of a held finger, the finger left at the fourth and the ninth never came. The quiet counts from the
    /// last finger's lift.
    func touched() {
        holding = true
        light()
        going?.cancel()
    }
    /// The last finger left the coin -- or the page left under it, which the platform need not tell the coin (MTWalletScreen).
    func released() {
        guard holding else { return }
        holding = false
        goOutAfterQuiet()
    }
    /// One touch of the coin: the coins it minted -- the box's number of them -- or none past the thirteenth of a second.
    @discardableResult func tap() -> Int {
        let now = Date().timeIntervalSince1970
        taps.removeAll { 1 <= now - $0 }
        guard !rests else { return 0 }
        light()
        if !holding { goOutAfterQuiet() }
        guard taps.count < Self.ceiling else { return 0 }
        taps.append(now)
        speed = taps.count
        let coins = MTCoinBook.ledger.mintInWindow(1, prefix: Self.refPrefix, seconds: 1)   // the tap joins the game's window of τ1 (04.10)
        settle()
        return coins
    }

    private func goOutAfterQuiet() {
        going?.cancel()
        going = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.quiet * 1_000_000_000)
            guard !Task.isCancelled, let self, self.lit else { return }
            self.lit = false
            self.litAt = nil
            self.resting?.cancel()
            MontanaP2PTrace.mark("pantheon", "out after quiet")
        }
    }

    /// The speed reads the last second again ten times a second until no tap is left in it.
    private func settle() {
        settling?.cancel()
        settling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                let now = Date().timeIntervalSince1970
                self.taps.removeAll { 1 <= now - $0 }
                self.speed = self.taps.count
                if self.taps.isEmpty { return }
            }
        }
    }
}

/// THE BURNS OF THE BUILDS BEFORE (the author's words 04.10.2026 00:51-01:01 MSK): up to build 2111 a call burned its seconds and a
/// letter one coin. The author's words 05.10.2026 01:21-01:31 MSK turned the burn into a payment to the person -- «the one who calls
/// pays the one called, the one who writes pays the one written to» (MTCoinSend.pay; a call mints its seconds to both since 07.10.2026,
/// MTCallMint). The names stay to read
/// the burns the books already hold.
enum MTCoinBurn {
    static let callPrefix = "call:"
    static let letterPrefix = "letter:"
}

/// THE BOOK'S BALANCE FOR A READER OFF THE MAIN ACTOR (03.10): the word about oneself is built on the delivery's own threads,
/// and the book lives on the main actor. The book writes its balance here at every move; until it has read its file this holds
/// nothing, so the word never tells a pair a balance of nothing it does not hold.
enum MTCoinBalance {
    private static let lock = NSLock()
    private static var held: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static func set(_ v: Int) {
        lock.lock(); let moved = held != nil && held != v; held = v; lock.unlock()
        if moved { Task { @MainActor in MTCoinTell.moved() } }
    }
}

/// THE PEOPLE IN THE APP HEAR MY BALANCE MOVE (the author's words 04.10.2026 03:03 and 04:19 MSK: «the update instant, as by a web
/// socket»): a move of the book says the balance again to the correspondents in the app now, in the app word (E2E.coinBeacon) --
/// one round in two seconds however fast the coins come, so a minute of minting is thirty rounds to the people online, not one a coin.
@MainActor enum MTCoinTell {
    static let pace: UInt64 = 2
    private static var due: Task<Void, Never>?
    static func moved() {
        guard due == nil else { return }
        due = Task { @MainActor in
            try? await Task.sleep(nanoseconds: pace * 1_000_000_000)
            due = nil
            guard let store = ChatStore.live else { return }
            for peer in store.appOnlineChats { E2E.shared.coinBeacon(to: peer) }
            MTTopNet.shared.put()   // the one table hears it in the same round
        }
    }
}

/// THE PEOPLE'S COINS (the author's words 03.10.2026 22:23 and 22:25 MSK: «in the wallet, under the add-account button, the
/// top thirteen balances by coins, beautifully, with avatars and names, as in a social network»; «the coin's badge is the
/// number in the common rating»). Balances are public ([I-2]): every phone tells its pairs its own balance in its word about
/// itself (the key c beside the bio and the link), and this book keeps what each pair last told -- the newest word wins. The
/// rating is this phone's person among the people who told it: one owner of the people's balances on this phone.
@MainActor final class MTCoinBoard: ObservableObject {
    static let shared = MTCoinBoard()
    struct Told: Codable { var coins: Int; var at: Double }
    struct Place: Identifiable { let id: String; let coins: Int; let mine: Bool }
    @Published private(set) var told: [String: Told] = [:]
    private static let key = "coinBoard.told"

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let t = try? JSONDecoder().decode([String: Told].self, from: d) { told = t }
    }
    /// The person lifted into the seat: the balances their own correspondents told them.
    func reread() {
        told = UserDefaults.standard.data(forKey: Self.key).flatMap { d in try? JSONDecoder().decode([String: Told].self, from: d) } ?? [:]
    }

    /// A pair's word about itself carried its balance: kept when it is newer than the one held.
    func note(_ conv: String, coins: Int, at: Double) {
        guard (told[conv]?.at ?? 0) <= at else { return }
        // A NEGATIVE BALANCE IS «HIDDEN» (04.10, MTCoinShow): the pair turned its coins off, and its row leaves this rating.
        guard 0 <= coins else {
            guard told.removeValue(forKey: conv) != nil else { return }
            if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
            MontanaP2PTrace.markFolded("coin_board", "hidden told=\(told.count)", window: 60)
            return
        }
        // Every presence word tells the balance now (E2E.coinTail): the moment always moves, the disk only when the coins did.
        let moved = told[conv]?.coins != coins
        told[conv] = Told(coins: coins, at: at)
        guard moved else { return }
        if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
        MontanaP2PTrace.markFolded("coin_board", "told=\(told.count)", window: 60)
    }

    /// A pair holding my words told my own coins, not a person's beside me (MTOwnWords): it stands in no rating.
    private var others: [String: Told] { told.filter { !MTOwnWords.mine($0.key) } }
    /// The rating: this phone's person and every pair that told its balance, the most coins first; a tie keeps me first.
    func rating(mine: Int) -> [Place] {
        (others.map { Place(id: $0.key, coins: $0.value.coins, mine: false) } + [Place(id: "", coins: mine, mine: true)])
            .sorted { $0.coins != $1.coins ? $1.coins < $0.coins : $0.mine }
    }

    /// My place in the rating: one more than the people who told more coins than I hold.
    func rank(mine: Int) -> Int { 1 + others.values.filter { mine < $0.coins }.count }
}

/// THE MONEY FLOW IS A CHAT'S OWN (the author's word 04.10.2026 12:23 MSK: «if my chat is turned with one correspondent, it concerns
/// only the chat with them, not all -- part the states»). The flow's coin turned one switch for the whole phone: the moment one chat
/// turned, every chat stood turned, spoke its live words and minted. Now each conversation keeps its own -- the turn of its feed,
/// its live words both ways, its minting. Read from any thread; the screens observe the change.
@MainActor final class MTMoneyFlow: ObservableObject {
    static let shared = MTMoneyFlow()
    /// A BUBBLE OF THE FLOW IS ONE COIN TIMES THE LEVEL (the author's words 07.10.2026 21:3x and 21:4x MSK: «one coin for one
    /// message bubble -- any bubble: +1 in the money flow and -1 in an ordinary chat»; «the minting in the money flow's chats is one
    /// coin multiplied by the level: for the 7th level 7 coins a message and 7 coins a second of talk; a level 1 on the call -- x1
    /// for him»; it replaces the hundred levels a long text minted, 05.10): every bubble of a chat whose flow is on -- words, a
    /// picture, a voice, a file, of either side -- mints the level's coins on this phone, once by its name (MTChatMint.credit,
    /// oneEach; MTPiLevels.multiplier, the one function of the level); a coin letter, a chess step and a row of the phone's own mint
    /// nothing. In an ordinary chat a bubble of mine burns one (MTCoinSend.pay). A call follows its chat the same way (MTCallMint).
    @Published private(set) var turns = 0
    nonisolated static func isOn(_ conv: String) -> Bool { !conv.isEmpty && UserDefaults.standard.bool(forKey: "moneyFlow." + conv) }   // a conversation's own key (SeedScope.dataPrefixes)
    func on(_ conv: String) -> Bool { Self.isOn(conv) }
    func set(_ conv: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "moneyFlow." + conv)
        turns += 1
    }
}

/// THE OWNER SHOWS OR HIDES THEIR COINS (the author's words 04.10.2026 05:47 and 05:48 MSK: «whether the balance is shown each
/// decides, on by default; who does not show is not in the top -- the privacy settings»; «the owner governs privacy»). One switch,
/// on unless its owner turned it off: the Montana top, the coins told to correspondents (the word about oneself, the presence
/// words' tail) and the coin's badge all ask it. Read from any thread.
/// THE TOP ASKS A YES FIRST (App Review 5.1.2(i), 08.10.2026, word for word: «you may not use, transmit, or share someone's
/// personal data without first obtaining their permission»): the name and the balance reach the public table and the
/// correspondents only after their owner turns the switch on; it is born off.
enum MTCoinShow {
    static let key = "coins.shown"   // NOT-UI: the owner's switch, off until the owner turns it on
    static let toldKey = "top.told"  // NOT-UI: the wallet has shown its owner what showing does (MTTopNet.put waits for it)
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? false }
}

/// THE MONTANA TOP (the author's words 04.10.2026 03:03, 05:40 and 05:47 MSK: «a live set as by a web socket, the update instant from
/// the nodes»; «everyone has one source of all data»; «who does not show is not in the top»). One public table of the game's coins,
/// the same on every node (/top-put, /top-get): this phone puts its own row and the table comes back whole. A row is named by sha256
/// of a token only the words derive -- HKDF of the entropy under one label, then one HMAC, as the shelf of one's own node
/// (MontanaHomeNode) -- so only its owner rewrites or withdraws it; a row stands at its owner's balance at once, the fact (05.10).
/// The game's coins are not Montana: the protocol's money stays unseen ([I-2]); the table holds what its owners chose to show.
@MainActor final class MTTopNet: ObservableObject {
    static let shared = MTTopNet()
    struct Row: Identifiable, Equatable { let id: String; let name: String; let coins: Int }
    /// The rows the nodes answered, the most coins first; empty until a node that keeps the table speaks.
    @Published private(set) var rows: [Row] = []
    /// A node answered: before the nodes keep the table the wallet shows the pairs' rating (MTCoinBoard).
    @Published private(set) var answered = false
    /// This person's place in the whole table, or nil when they are not in it.
    @Published private(set) var rank: Int?
    private static let keyLabel = Data("mt-top-owner-v1".utf8)   // NOT-UI: the derivation's own label
    private static let tokenLabel = Data("mt-top-token".utf8)    // NOT-UI: the token's own label
    private var asking = false

    static func key(entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: keyLabel, outputByteCount: 32)
    }
    static func token(_ k: SymmetricKey) -> Data { Data(HMAC<SHA256>.authenticationCode(for: tokenLabel, using: k)) }
    static func row(token t: Data) -> String { MontanaHomeNode.hex(Data(SHA256.hash(data: t))) }
    private static func myToken() -> Data? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return token(key(entropy: e))
    }
    /// The row this seed owns, or nil without a seed.
    static func myRow() -> String? { myToken().map { row(token: $0) } }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes
    /// 0x00..0x1f; tools/mt-top-check.py computes them again on every build): the home node's label in place of this one, a
    /// reversed root or a row hashed as hex text all fail them.
    static func keyKAT() -> Bool {
        let counting = Data((0..<32).map { UInt8($0) })
        let k = key(entropy: counting)
        let t = token(k)
        return MontanaHomeNode.hex(k.withUnsafeBytes { Data($0) }) == "7a504b1911419189651d037cfa3776404731270ebe01a2cbefe7aabbca5140d5"
            && MontanaHomeNode.hex(t) == "67b2f9e4f8ba74bffee41cdfd8de2d3efca20554a495910ebc823b8ef4545ce2"
            && row(token: t) == "f0b3cb47ae97a4849fd8d42d75bbbcc395f93b9b4adae16c5bb0e91b4641d369"
    }

    /// The row says the coins now -- paced by MTCoinTell, never before the wallet told its owner what showing does, never when
    /// the owner hid the coins.
    func put() {
        guard MTCoinShow.on else { withdrawUnasked(); return }
        guard UserDefaults.standard.bool(forKey: MTCoinShow.toldKey), let t = Self.myToken(), let coins = MTCoinBalance.now else { return }
        // THE ROW TELLS THE SEED'S UNION, NEVER ONE DEVICE'S SHARE (the author's word 04.10.2026 15:51 MSK: «check the sync over the
        // network as a pendulum»): a device of the seed that has not gathered the others' moves in half a minute would pull the seed's
        // row down to its own share and the next device would lift it again; it gathers first, and the gathering puts the row.
        guard MTCoinVault.shared.fresh else { MTCoinVault.shared.soon("put", after: 1); return }
        let body: [String: Any] = ["token": MontanaHomeNode.hex(t), "name": String(E2E.myDisplayName().prefix(64)), "coins": coins]
        Task { await self.send(body, why: "put") }
    }
    /// A ROW PUT BEFORE THE YES WAS ASKED LEAVES (5.1.2(i), 08.10.2026): earlier builds showed a person in the table by default; a
    /// person who never turned the switch has their row withdrawn from every node once, as soon as their words can name it.
    static let unaskedKey = "top.unaskedWithdrawn"   // NOT-UI: this device withdrew the row of a person never asked
    /// WHAT THIS BUILD FOUND AT ITS FIRST LAUNCH (the critic 08.10): whether an earlier build of this device had already published
    /// the row (its wallet had told what showing does). Read once, before any wallet of this build opens -- the wallet sets the
    /// told mark at every opening, and a device that never published must not take away a row a yes put on another device.
    nonisolated static let toldBeforeKey = "top.toldBeforeConsent"   // NOT-UI: the told mark as this build first found it
    static func noteFirstLaunch() {
        let d = UserDefaults.standard
        if d.object(forKey: toldBeforeKey) == nil { d.set(d.bool(forKey: MTCoinShow.toldKey), forKey: toldBeforeKey) }
    }
    private func withdrawUnasked() {
        let d = UserDefaults.standard
        guard d.object(forKey: MTCoinShow.key) == nil, d.bool(forKey: Self.toldBeforeKey), !d.bool(forKey: Self.unaskedKey),
              Self.myToken() != nil else { return }
        d.set(true, forKey: Self.unaskedKey)
        withdraw()
    }
    /// The owner hid the coins: the row leaves the table on every node, and leaves this screen at once.
    func withdraw() {
        guard let t = Self.myToken() else { return }
        let mine = Self.row(token: t)
        rows.removeAll { $0.id == mine }
        rank = nil
        Task { await self.send(["token": MontanaHomeNode.hex(t), "hide": true], why: "hide", everyDoor: true) }
    }
    /// The owner's switch moved: the table and the correspondents hear it now, not at the next coin.
    func showChanged(_ on: Bool) {
        if on { put() } else { withdraw() }
        if let store = ChatStore.live {
            for c in store.listChats() where !c.isGroup { if let conv = c.convId { E2E.shared.tellBalance(to: conv) } }
        }
        MontanaP2PTrace.mark("coins_shown", on ? "on" : "off")
    }
    /// A withdrawal knocks every node itself (everyDoor): a row hidden on one node and forwarded nowhere would stand on the other.
    private func send(_ body: [String: Any], why: String, everyDoor: Bool = false) async {
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        var heard = 0
        for b in MontanaWakePush.orderedBases(for: "top") {
            guard let u = URL(string: b + "/top-put") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the public table
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 8   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = d
            if let r = try? await URLSession.shared.data(for: req), (r.1 as? HTTPURLResponse)?.statusCode == 200 {   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                heard += 1
                if !everyDoor { break }
            }
        }
        MontanaP2PTrace.markFolded("top_put", "why=\(why) doors=\(heard)", window: 60)
    }
    /// The whole table and this person's place in it, asked of the first node that keeps it.
    func read() async {
        guard !asking else { return }
        asking = true
        defer { asking = false }
        var body: [String: Any] = [:]
        if let me = Self.myRow() { body["row"] = me }
        guard let d = try? JSONSerialization.data(withJSONObject: body) else { return }
        for b in MontanaWakePush.orderedBases(for: "top") {
            guard let u = URL(string: b + "/top-get") else { continue }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the public table
            var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 6   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
            req.httpBody = d
            guard let r = try? await URLSession.shared.data(for: req), (r.1 as? HTTPURLResponse)?.statusCode == 200,   // SERVER-DEBT-ACK: the accelerator node (rung 4)
                  let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
                  let list = o["rows"] as? [[String: Any]] else { continue }
            rows = list.compactMap { x in
                guard let id = x["row"] as? String, let coins = x["coins"] as? Int else { return nil }
                // A NAME IS SHOWN AS LETTERS ONLY (the critic, 04.10): the node strips the controls and the direction marks, and the
                // phone does again -- a node of another hand owes this screen nothing.
                let name = String(String.UnicodeScalarView(((x["name"] as? String) ?? "").unicodeScalars.filter { u in
                    u.properties.generalCategory != .control && u.properties.generalCategory != .format
                }))
                return Row(id: id, name: name, coins: coins)
            }
            rank = o["rank"] as? Int
            if !answered { MontanaP2PTrace.mark("top_get", "rows=\(rows.count) rank=\(rank ?? 0)") }
            answered = true
            return
        }
    }
}


/// THE BOOK RIDES THE SEED (the author's words 04.10.2026 13:36-13:42 MSK: «I must log in by my seed on another device and my
/// balance must surely be kept -- the critical part»; the choice 13:40: «the book by the seed on the nodes»; «build by constitution 6
/// fully» -- the phone is a full node). Every move of the book is sealed under a key only the words derive (ChaCha20-Poly1305, the
/// vault's own cipher [I-1]) and laid on every node in pieces; any device with the same words gathers the union of all of them -- a
/// move is its name, so the union is the book, the same on every device of the seed. What a node holds is the node's own word: it
/// answers with the names of the pieces it keeps, and each node is sent the moves its pieces lack, never more. Past `fold` pieces on
/// a node the whole book is laid there anew and the old pieces go in the same breath. The top waits for the first answer (heard):
/// a device that has not gathered its seed's book never tells the table a balance it does not hold.
@MainActor final class MTCoinVault: ObservableObject {
    static let shared = MTCoinVault()
    nonisolated private static let keyLabel = Data("mt-coins-vault-key-v1".utf8)       // NOT-UI: the seal's derivation label
    nonisolated private static let ownerLabel = Data("mt-coins-vault-owner-v1".utf8)   // NOT-UI: the row's derivation label
    nonisolated private static let tokenLabel = Data("mt-coins-vault-token".utf8)      // NOT-UI: the token's own label
    nonisolated private static let aad = Data("mt.coins.vault".utf8)                   // NOT-UI: the words the seal is bound to
    nonisolated private static let tipLabel = Data("mt-timechain-tip-token".utf8)      // NOT-UI: the tips' row label (MTTimeChainTip)
    nonisolated private static let ownLabel = Data("mt-own-words-v1".utf8)             // NOT-UI: the own-words tag's label (MTOwnWords)
    nonisolated private static let nodeLabel = Data("mt-coins-vault-node-v1".utf8)     // NOT-UI: a node's own row label (nodeToken)
    /// How many pieces a node keeps for a seed before the whole book is laid there as one (about three hours of minting, a piece a
    /// minute); a piece carries `span` moves at most.
    static let fold = 192
    static let span = 8000
    /// A node answered this seed's book since the launch or the seat's move.
    @Published private(set) var heard = false
    private var heardAt: Double = 0
    /// The seed's union was gathered within half a minute: what this device tells the top is the seed's, not its own share.
    var fresh: Bool { heard && Date().timeIntervalSince1970 - heardAt < 30 }
    private var pieces: [String: Set<String>] = [:]   // a piece's name -> the names of the moves it carries, opened once
    private var held: [String: [String]] = [:]         // a node's door -> the pieces it said it keeps
    private var full = Set<String>()                   // the doors that refused a piece as full: laid whole next
    private var running = false, again = false
    private var dueAt = Double.infinity

    nonisolated static func keys(entropy: Data) -> (seal: SymmetricKey, token: Data, tip: Data) {
        let ikm = SymmetricKey(data: entropy)
        let seal = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: Data(), info: keyLabel, outputByteCount: 32)
        let owner = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: Data(), info: ownerLabel, outputByteCount: 32)
        return (seal, Data(HMAC<SHA256>.authenticationCode(for: tokenLabel, using: owner)),
                Data(HMAC<SHA256>.authenticationCode(for: tipLabel, using: owner)))
    }
    nonisolated private static let personLabel = Data("mt-person-chain-token".utf8)   // NOT-UI: the chain of the person's row label (MTPersonChain)
    /// The chain of the person's row and seal (MTPersonChain): the book's seal key, and a row of its own under the owner key.
    static func personRow() -> (seal: SymmetricKey, token: Data)? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return (keys(entropy: e).seal, Data(HMAC<SHA256>.authenticationCode(for: personLabel, using: ownerKey(e))))
    }
    /// THE TAG OF A PAIR ONLY THE SAME WORDS MAKE (MTOwnWords): HMAC-SHA-256 under the owner key over the label and the conversation's
    /// name. A pair of other words reads 32 bytes it can neither check nor tie to any other conversation; no node sees them (the word
    /// about oneself rides end to end).
    nonisolated static func ownTag(entropy: Data, conv: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: ownLabel + Data(conv.utf8), using: ownerKey(entropy)))
    }
    nonisolated static func ownTagHolds(_ tag: Data, entropy: Data, conv: String) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(tag, authenticating: ownLabel + Data(conv.utf8), using: ownerKey(entropy))
    }
    /// EVERY NODE HOLDS THE BOOK UNDER A ROW OF ITS OWN (the author's words 06.10.2026 12:3x-12:4x MSK: «close the double spends»; «the safety of the restore by the seed»): the one
    /// token the seed sent to every node named the same row on all of them, and a put deletes the pieces it names -- one node that
    /// read the token from a request could empty the book on every other node, and the words restored nothing. A node's row is
    /// HMAC-SHA-256 under the owner key over this label and the node's host: a node learns its own row and no other. The common row
    /// stays beside it, read and laid, while builds before this one read nothing else.
    nonisolated static func nodeToken(entropy: Data, host: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: nodeLabel + Data(host.utf8), using: ownerKey(entropy)))
    }
    /// Every node's two rows: its own first, then the common one.
    private static func rows(_ doors: [String], common: String, entropy: Data) -> [(slot: String, door: String, token: String)] {
        doors.flatMap { door in
            [(slot: door + "#own", door: door, token: MontanaHomeNode.hex(nodeToken(entropy: entropy, host: URL(string: door)?.host ?? door))),
             (slot: door, door: door, token: common)]
        }
    }
    nonisolated private static func ownerKey(_ entropy: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(), info: ownerLabel, outputByteCount: 32)
    }
    fileprivate static func mine() -> (seal: SymmetricKey, token: Data, tip: Data)? {
        guard let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return keys(entropy: e)
    }
    /// THE FROZEN VECTORS (computed outside this code: RFC 5869 HKDF-SHA-256, HMAC-SHA-256 and SHA-256 on the counting bytes
    /// 0x00..0x1f; tools/mt-top-check.py computes them again on every build): the top's labels in place of these, a reversed
    /// root or a row hashed as hex text all fail them.
    static func keyKAT() -> Bool {
        let k = keys(entropy: Data((0..<32).map { UInt8($0) }))
        return MontanaHomeNode.hex(k.seal.withUnsafeBytes { Data($0) }) == "e9720340e7dcb4b6c2befea9a657718560646f727614f732971bf9ea7d3795fb"
            && MontanaHomeNode.hex(k.token) == "4b7fc64e903945bee08b4fc45f7ca094d9b61ae2c96f4d97ebd1ccd8b4b9ab86"
            && MontanaHomeNode.hex(Data(SHA256.hash(data: k.token))) == "9e34605e5200c5f339f4a527f0654af5436a96b629f66835f91495b65e0ba245"
    }
    nonisolated static func seal(_ moves: [MTCoinEntry], with key: SymmetricKey) -> Data? {
        guard let plain = try? JSONEncoder().encode(moves), let packed = try? (plain as NSData).compressed(using: .lzfse) as Data else { return nil }
        return try? ChaChaPoly.seal(packed, using: key, authenticating: aad).combined
    }
    nonisolated static func open(_ sealed: Data, with key: SymmetricKey) -> [MTCoinEntry]? {
        guard let box = try? ChaChaPoly.SealedBox(combined: sealed), let packed = try? ChaChaPoly.open(box, using: key, authenticating: aad),
              let plain = try? (packed as NSData).decompressed(using: .lzfse) as Data else { return nil }
        return try? JSONDecoder().decode([MTCoinEntry].self, from: plain)
    }
    /// The person who left the seat takes their vault's memory with them.
    func forget() { heard = false; heardAt = 0; pieces = [:]; held = [:]; full = [] }
    /// A gathering soon: the moves of a minute -- the minting's own window -- ride one piece, never one each; the nearest ask wins, so
    /// a row waiting for the seed's union never waits behind a minute's.
    func soon(_ why: String, after seconds: Double = 60) {
        let at = Date().timeIntervalSince1970 + seconds
        guard at < dueAt else { return }
        dueAt = at
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.dueAt == at else { return }
            self.dueAt = .infinity
            Task { await self.gather(why: why) }
        }
    }
    /// The seat moved while the gather waited (MTCoinBook.generation): nothing of the person who left is written or kept.
    private func moved(_ gen: Int, _ why: String) -> Bool {
        guard gen != MTCoinBook.generation else { return false }
        MontanaP2PTrace.mark("coins_vault", "why=\(why) the seat moved -- the gather writes nothing")
        return true
    }
    func gather(why: String) async {
        if running { again = true; return }
        guard let k = Self.mine(), let words = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: words), e.count == 32 else { return }
        let gen = MTCoinBook.generation
        let doors = MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault"))
        guard !doors.isEmpty else { return }
        running = true
        defer { running = false; if again { again = false; soon("again", after: 1) } }
        let rows = Self.rows(doors, common: MontanaHomeNode.hex(k.token), entropy: e)
        var answered: [String] = []
        var fresh: [MTCoinEntry] = []
        for r in rows {
            let door = r.door
            let have = Array(pieces.keys.prefix(256))
            guard case let (200, o?) = await Self.post(door + "/vault-get", ["token": r.token, "have": have], timeout: 20),
                  let ids = o["held"] as? [String] else { continue }
            if moved(gen, why) { return }
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ Data(base64Encoded: $0) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id else { continue }   // a piece is its own name
                let key = k.seal
                guard let moves = await Task.detached(priority: .utility, operation: { MTCoinVault.open(b, with: key) }).value else { continue }
                if moved(gen, why) { return }
                pieces[id] = Set(moves.map(\.id))
                fresh += moves
            }
            held[r.slot] = ids
            answered.append(r.slot)
        }
        guard !answered.isEmpty, !moved(gen, why) else { return }
        heard = true
        heardAt = Date().timeIntervalSince1970
        let ledger = MTLocalCoinLedger.shared.whole
        let joined = ledger.join(fresh)
        let book = ledger.entries
        var laid = 0, whole = 0
        for slot in answered {
            guard let r = rows.first(where: { x in x.slot == slot }) else { continue }
            let ids = held[slot] ?? []
            var carried = Set<String>()
            for id in ids { carried.formUnion(pieces[id] ?? []) }
            let anew = Self.fold <= ids.count || full.contains(slot)
            let lacking = anew ? book : book.filter { !carried.contains($0.id) }
            guard !lacking.isEmpty else { continue }
            // ONLY A PIECE READ HERE IS REPLACED (the coin audit's third point, 05.10.2026 21:4x MSK): a piece that would not open
            // -- a book of a later build, a broken blob -- or whose moves the book did not take was skipped above but stood in the
            // replace list, and its moves left every node. It stays on the node now, beside the whole.
            let inBook = anew ? Set(book.map(\.id)) : []
            var replace = anew ? ids.filter { id in pieces[id].map { moves in moves.isSubset(of: inBook) } ?? false } : []
            for start in stride(from: 0, to: lacking.count, by: Self.span) {
                let part = Array(lacking[start..<min(start + Self.span, lacking.count)])
                // THE OLD PIECES GO WITH THE LAST NEW ONE (the coin audit's sixth point, 05.10.2026 21:4x MSK): the first part
                // carried the replace, so a refusal or an ended process after it left the node a part of the book, and «full»
                // repeated that same part. Every part is laid first; the last one takes the old pieces away.
                let last = lacking.count <= start + Self.span
                let key = k.seal
                guard let sealed = await Task.detached(priority: .utility, operation: { MTCoinVault.seal(part, with: key) }).value else { break }
                if moved(gen, why) { return }
                let (code, o) = await Self.post(r.door + "/vault-put", ["token": r.token, "blob": sealed.base64EncodedString(), "replace": last ? replace : []], timeout: 30)
                if moved(gen, why) { return }   // the old seed's own book went to its own row; nothing more is kept here
                if code == 413 { full.insert(slot); break }
                guard code == 200, let id = o?["piece"] as? String else { break }
                pieces[id] = Set(part.map(\.id))
                let gone = last ? replace : []
                held[slot] = (held[slot] ?? []).filter { !gone.contains($0) } + [id]
                if last { replace = [] }
                laid += part.count
                if anew { whole += 1 }
            }
            if anew, whole > 0 { full.remove(slot) }
        }
        let live = Set(held.values.flatMap { $0 })
        pieces = pieces.filter { live.contains($0.key) }   // a piece no node keeps is forgotten here too
        MontanaP2PTrace.mark("coins_vault", "why=\(why) rows=\(answered.count)/\(rows.count) got=\(fresh.count) joined=\(joined) laid=\(laid) whole=\(whole) moves=\(book.count)")
        MTTopNet.shared.put()   // the row tells the union just gathered
    }
    fileprivate static func post(_ url: String, _ body: [String: Any], timeout: Double) async -> (Int, [String: Any]?) {
        guard let u = URL(string: url), let d = try? JSONSerialization.data(withJSONObject: body) else { return (-1, nil) }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the seed's sealed book
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = timeout   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = d
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return (-1, nil) }   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        MTPersonChain.shared.answered(resp)   // a node's answer is a second of the person on the network (MTPersonChain)
        return ((resp as? HTTPURLResponse)?.statusCode ?? -1, try? JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A PERSON ON THE SHELF IS CREDITED IN THEIR OWN BOOK (07.10, MTShelfPost): the moves are sealed under the key only their
    /// words derive and laid on every node under both their rows -- the node's own and the common one -- exactly as their own
    /// gather lays them; their gather at the lift, or any device of their words, takes the union. The rows that took the piece.
    static func lay(_ moves: [MTCoinEntry], entropy: Data) async -> Int {
        guard entropy.count == 32, !moves.isEmpty else { return 0 }
        let k = keys(entropy: entropy)
        let doors = MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault"))
        guard !doors.isEmpty, let sealed = seal(moves, with: k.seal) else { return 0 }
        var took = 0
        for r in rows(doors, common: MontanaHomeNode.hex(k.token), entropy: entropy) {
            let (code, _) = await post(r.door + "/vault-put", ["token": r.token, "blob": sealed.base64EncodedString(), "replace": [String]()], timeout: 30)
            if code == 200 { took += 1 }
        }
        return took
    }
}

/// THE TIMECHAIN'S TIP RIDES ONE ROUND TRIP (the author's words 04.10.2026 16:30-16:34 MSK: «find the lightest record of the
/// TimeChain, so the sync tends to the speed of a ping -- a special file and only the last 13 records; by the constitution, points 0 4 5
/// 6 8 10»; «right, fix it and build it in 2105»). Every device of the words writes its own lane -- one writer, so two phones never
/// contend for one link -- and every link carries, beside its move, the lane's running balance: the last link says the lane's coins.
/// The tip is the lane's last thirteen links in their own bytes, sealed under the words' key: one piece of each device on every node,
/// beside the book (MTCoinVault) in a row of its own, replaced as the lane grows. A device reads the others' tips in one round trip:
/// pieces it opened before ride nothing back; a lane behind by thirteen links or less gives its missing moves in the same piece,
/// joined by their names; a longer gap or a seal that breaks the chain asks the book. The head also says the writer's balance of the
/// whole book once it had gathered it, so a device restored by its words shows the seed's coins before the book lands. The number
/// shown stays the book's, where a move counts once by its name: a coin of a letter is born on every device of the words the letter
/// reaches, and lanes summed would count it twice.
@MainActor final class MTTimeChainTip: ObservableObject {
    static let shared = MTTimeChainTip()
    nonisolated static let depth = 13
    static let file = "timechain-tip.bin"   // NOT-UI: the tip's file name
    nonisolated static let aad = Data("mt.timechain.tip".utf8)   // NOT-UI: the words the tip's seal is bound to
    nonisolated static let kinds: [MTCoinEntry.Kind] = [.earn, .receive, .spend, .send, .burn]
    struct Link: Equatable {
        var n: UInt32, at: Int64, k: UInt8, c: UInt64, b: Int64
        var ref: String, peer: String, on: String
        var signed: Int64 { k < 2 ? Int64(c) : -Int64(c) }
    }
    struct Tip {
        var lane = Data(), seen: Int64 = 0, heard = false, prev = Data(count: 32), links: [Link] = []
    }
    /// The balance of the whole book the freshest tip of another device told, written after that device had gathered the book.
    @Published private(set) var seen: Int?
    private var tip: Tip?
    private var heads: [Data: (n: UInt32, hash: Data)] = [:]   // another device's lane: the last link of it this device took
    private var seenAt: Int64 = 0
    private var opened: [String: Data] = [:]   // a piece's name: its lane, opened once
    private var mine: [String: String] = [:]   // a node's door: the piece of this lane it holds now
    private var stale = Set<String>()          // pieces of this lane from before, gone at the next put
    private var putDue = false, putting = false, again = false, getting = false, checked = false
    private var putAt: Double = 0
    private let disk = DispatchQueue(label: "montana.timechain-tip", qos: .utility)

    /// The person lifted into the seat: the lane of the person who left goes with them; the seated person's is read at the next ask.
    func reread() { tip = nil; heads = [:]; seen = nil; seenAt = 0; opened = [:]; mine = [:]; stale = [] }

    /// This device's lane, read once from its file; born at the first ask where none stands. A file that stands and would not
    /// open is never written over: the lane waits for the next ask.
    private func lane() -> Tip? {
        if let tip { return tip }
        guard let u = MTCoinPlace.file(Self.file) else { return nil }
        if let d = try? Data(contentsOf: u) {
            guard let read = Self.decode(d), read.lane.count == 16 else { return nil }
            tip = read
        } else if !FileManager.default.fileExists(atPath: u.path) {
            tip = Tip(lane: Data((0..<16).map { _ in UInt8.random(in: 0...255) }))
        }
        return tip
    }

    /// This device's own moves (MTLocalCoinLedger.keep) join its lane: the running balance moves with each, the window keeps the last
    /// thirteen, and the tip leaves for the nodes within two seconds.
    func add(_ moves: [MTCoinEntry], book balance: Int) {
        guard !moves.isEmpty, var t = lane() else { return }
        for e in moves where Self.bore(e) {
            guard let k = Self.kinds.firstIndex(of: e.k), 0 < e.c, [e.ref, e.peer ?? "", e.on ?? ""].allSatisfy({ s in s.utf8.count <= 1024 }) else { continue }
            let signed = k < 2 ? Int64(e.c) : -Int64(e.c)
            let (b, over) = (t.links.last?.b ?? 0).addingReportingOverflow(signed)
            guard !over else { continue }
            t.links.append(Link(n: (t.links.last?.n ?? 0) + 1, at: MTTimeChain.ms(e.at), k: UInt8(k), c: UInt64(e.c), b: b,
                                ref: e.ref, peer: e.peer ?? "", on: e.on ?? ""))
            if Self.depth < t.links.count { t.prev = Self.seal(t.prev, t.links.removeFirst()) }
        }
        t.seen = Int64(balance)
        t.heard = MTCoinVault.shared.heard
        tip = t
        if let u = MTCoinPlace.file(Self.file) {
            let d = Self.encode(t)
            disk.async { try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        }
        soonPut()
    }

    /// THE LANE CARRIES WHAT THE DEVICE BORE (the author's «yes» 04.10.2026 17:16 MSK to variant (a)): a letter's coin and a coin
    /// letter reach every device of the words by the letter itself and the book counts each once by its name, so they ride no lane
    /// -- a sum of lanes would count them once a device; the lane carries what this device alone bore: the Pantheon, the VPN wall,
    /// chess and its Timer, the pull, spending, sending, burning.
    static func bore(_ e: MTCoinEntry) -> Bool {
        let s = MTTimeChain.source(of: e)
        return !(e.k == .earn && (s == "chats" || s == "groups" || s == "channels")) && !(e.k == .receive && s != "chess")
    }

    /// The tips leave at most once in two seconds: the moves of those seconds ride one piece.
    private func soonPut() {
        guard !putDue else { return }
        putDue = true
        let wait = max(0.3, putAt + 2 - Date().timeIntervalSince1970)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { Task { @MainActor in await MTTimeChainTip.shared.put() } }
    }
    private func put() async {
        putDue = false
        if putting { again = true; return }
        putting = true
        defer { putting = false; if again { again = false; soonPut() } }
        putAt = Date().timeIntervalSince1970
        guard let t = tip, let k = MTCoinVault.mine(),
              let sealed = try? ChaChaPoly.seal(Self.encode(t), using: k.seal, authenticating: Self.aad).combined else { return }
        let token = MontanaHomeNode.hex(k.tip)
        let id = MontanaHomeNode.hex(Data(SHA256.hash(data: sealed)))
        var laid = 0
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            // A piece named in its own replace would be taken off and not laid again (the node checks before it deletes).
            let gone = Array(stale.union(mine[door].map { p in [p] } ?? [])).filter { p in p != id }
            let (code, o) = await MTCoinVault.post(door + "/vault-put", ["token": token, "blob": sealed.base64EncodedString(), "replace": gone], timeout: 10)
            guard code == 200, let piece = o?["piece"] as? String else { continue }
            mine[door] = piece
            opened[piece] = t.lane
            laid += 1
        }
        if 0 < laid { stale = [] }
        MontanaP2PTrace.markFolded("tip_put", "n=\(t.links.last?.n ?? 0) b=\(t.links.last?.b ?? 0) bytes=\(sealed.count) doors=\(laid)", window: 60)
    }

    /// The other devices' tips in one round trip to the first node that answers: a lane's new links join the book by their names;
    /// a lane further behind than the window, or a link whose seal does not follow the head this device took, asks the book.
    func gather(why: String) async {
        guard !getting, let k = MTCoinVault.mine() else { return }
        let gen = MTCoinBook.generation   // the coin audit's second point: a seat moved during the wait joins nothing
        getting = true
        defer { getting = false }
        if !checked { checked = true; MontanaP2PTrace.mark("tip_self", "ok=\(Self.selfCheck() ? 1 : 0)") }
        let own = lane()?.lane
        let token = MontanaHomeNode.hex(k.tip)
        var fresh: [MTCoinEntry] = [], lanes = 0, gap = false, broken = 0, answered = false
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            guard case let (200, o?) = await MTCoinVault.post(door + "/vault-get", ["token": token, "have": Array(opened.keys.prefix(256))], timeout: 6),
                  let held = o["held"] as? [String] else { continue }
            guard gen == MTCoinBook.generation else { MontanaP2PTrace.mark("tip_get", "why=\(why) the seat moved -- nothing joined"); return }
            answered = true
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ s in Data(base64Encoded: s) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id,   // a piece is its own name
                      let box = try? ChaChaPoly.SealedBox(combined: b),
                      let plain = try? ChaChaPoly.open(box, using: k.seal, authenticating: Self.aad),
                      let t = Self.decode(plain), t.lane.count == 16 else { continue }
                opened[id] = t.lane
                if t.lane == own {
                    if mine[door] != id { stale.insert(id) }
                    continue
                }
                lanes += 1
                guard let first = t.links.first, let last = t.links.last else { continue }
                let seals = Self.chain(t)
                let had = heads[t.lane]
                guard Self.whole(t), Self.follows(had, t, seals) else { broken += 1; gap = true; continue }
                guard (had?.n ?? 0) < last.n else { continue }
                if (had?.n ?? 0) + 1 < first.n { gap = true }   // further behind than the window: the book carries the rest
                fresh += t.links.filter { l in (had?.n ?? 0) < l.n }.map(Self.entry)
                heads[t.lane] = (last.n, seals[seals.count - 1])
                if t.heard, seenAt < last.at { seenAt = last.at; seen = Int(t.seen) }
            }
            let standing = Set(held)
            opened = opened.filter { e in standing.contains(e.key) }   // a piece no node keeps is forgotten here too
            break
        }
        guard answered else { return }
        let joined = fresh.isEmpty ? 0 : MTLocalCoinLedger.shared.whole.join(fresh)
        if gap { MTCoinVault.shared.soon("tip", after: 1) }
        let kv = "why=\(why) lanes=\(lanes) joined=\(joined) gap=\(gap ? 1 : 0) broken=\(broken) seen=\(seen ?? -1)"
        if 0 < joined || gap { MontanaP2PTrace.mark("tip_get", kv) } else { MontanaP2PTrace.markFolded("tip_get", kv, window: 60) }
    }

    // MARK: the bytes, little-endian: the format 1, the lane (16), the seen balance (i64), heard (u8), prev (32), the count (u8), the
    // links; a link: n (u32), at in ms (i64), the kind (u8), the coins (u64), the running balance (i64), then ref, peer and on, each a
    // u16 length and its UTF-8.
    nonisolated static func encode(_ t: Tip) -> Data {
        var d = Data([1])
        d.append(t.lane); put(&d, t.seen); d.append(t.heard ? 1 : 0); d.append(t.prev); d.append(UInt8(t.links.count))
        for l in t.links { d.append(bytes(l)) }
        return d
    }
    nonisolated static func bytes(_ l: Link) -> Data {
        var d = Data()
        put(&d, l.n); put(&d, l.at); d.append(l.k); put(&d, l.c); put(&d, l.b)
        for s in [l.ref, l.peer, l.on] { let u = Data(s.utf8); put(&d, UInt16(u.count)); d.append(u) }
        return d
    }
    nonisolated private static func put<T: FixedWidthInteger>(_ d: inout Data, _ v: T) {
        withUnsafeBytes(of: v.littleEndian) { b in d.append(contentsOf: b) }
    }
    nonisolated static func decode(_ d: Data) -> Tip? {
        var r = Reader(d)
        guard r.u8() == 1, let lane = r.take(16), let seen: Int64 = r.int(), let heard = r.u8(), let prev = r.take(32),
              let count = r.u8(), Int(count) <= depth else { return nil }
        var t = Tip(lane: lane, seen: seen, heard: heard == 1, prev: prev)
        for _ in 0..<count {
            guard let n: UInt32 = r.int(), let at: Int64 = r.int(), let k = r.u8(), let c: UInt64 = r.int(), let b: Int64 = r.int(),
                  let ref = r.text(), let peer = r.text(), let on = r.text() else { return nil }
            t.links.append(Link(n: n, at: at, k: k, c: c, b: b, ref: ref, peer: peer, on: on))
        }
        return r.done ? t : nil
    }
    private struct Reader {
        let d: Data
        var i: Int
        init(_ d: Data) { self.d = d; i = d.startIndex }
        mutating func take(_ n: Int) -> Data? {
            guard n <= d.endIndex - i else { return nil }
            defer { i += n }
            return d.subdata(in: i..<(i + n))
        }
        mutating func u8() -> UInt8? { take(1)?.first }
        mutating func int<T: FixedWidthInteger>() -> T? {
            take(MemoryLayout<T>.size).map { b in b.withUnsafeBytes { p in T(littleEndian: p.loadUnaligned(as: T.self)) } }
        }
        mutating func text() -> String? {
            guard let n: UInt16 = int(), let b = take(Int(n)) else { return nil }
            return String(data: b, encoding: .utf8)
        }
        var done: Bool { i == d.endIndex }
    }

    // MARK: the chain: a link's seal is SHA-256 over the seal before it and the link's bytes, so the head seals the lane to its birth.
    nonisolated static func seal(_ prev: Data, _ l: Link) -> Data {
        var b = prev
        b.append(bytes(l))
        return Data(SHA256.hash(data: b))
    }
    nonisolated static func chain(_ t: Tip) -> [Data] {
        var prev = t.prev, out: [Data] = []
        for l in t.links { prev = seal(prev, l); out.append(prev) }
        return out
    }
    /// The window counts on: every link numbered after the one before, its balance the one before's and its own move.
    nonisolated static func whole(_ t: Tip) -> Bool {
        for (i, l) in t.links.enumerated() {
            guard Int(l.k) < kinds.count, 0 < l.c, l.c <= UInt64(Int.max) else { return false }
            guard 0 < i else { continue }
            let p = t.links[i - 1]
            let (b, over) = p.b.addingReportingOverflow(l.signed)
            guard l.n == p.n + 1, !over, b == l.b else { return false }
        }
        return true
    }
    /// The window follows the head this device took of that lane: the seal at that link is the one taken, or the window begins right
    /// after it. A lane never taken follows by itself.
    nonisolated static func follows(_ had: (n: UInt32, hash: Data)?, _ t: Tip, _ seals: [Data]) -> Bool {
        guard let had, let first = t.links.first else { return true }
        if had.n + 1 == first.n { return t.prev == had.hash }
        if first.n <= had.n, let i = t.links.firstIndex(where: { l in l.n == had.n }) { return seals[i] == had.hash }
        return true   // further behind than the window: nothing to compare, the book carries the rest
    }
    /// The bytes read back as they were written: thirteen links of every kind, a peer on every other one, the seal followed from the
    /// sixth -- a writer and a reader that disagree on an order, a width or a length fail here, on the phone, in the diary.
    nonisolated static func selfCheck() -> Bool {
        var t = Tip(lane: Data((0..<16).map { i in UInt8(i) }), seen: 13, heard: true)
        var b: Int64 = 0
        for n in 1...UInt32(depth) {
            let k = UInt8(n % 5), c = UInt64(n) * 1_000_003
            b += k < 2 ? Int64(c) : -Int64(c)
            t.links.append(Link(n: n, at: 1_759_000_000_000 + Int64(n), k: k, c: c, b: b, ref: "r" + String(n), peer: n % 2 == 0 ? "a:" + String(n) : "", on: ""))
        }
        guard let back = decode(encode(t)) else { return false }
        return back.lane == t.lane && back.seen == t.seen && back.heard && back.prev == t.prev && back.links == t.links && whole(back)
            && follows((t.links[5].n, chain(t)[5]), back, chain(back)) && !follows((t.links[5].n, chain(t)[4]), back, chain(back))
    }
    nonisolated static func entry(_ l: Link) -> MTCoinEntry {
        MTCoinEntry(k: kinds[Int(l.k)], c: Int(l.c), ref: l.ref, peer: l.peer.isEmpty ? nil : l.peer, on: l.on.isEmpty ? nil : l.on,
                    at: Double(l.at) / 1000)
    }
}

/// THE RETIRED SOURCES OF COINS (the author's word 08.10.2026 00:5x MSK: the VPN leaves Montana and Montana Business wholly, for
/// its own app, Montana VPN): the coins its wall minted and the coins burned to pay for it stay in the person's book and in their own
/// chains, read as they were written; nothing in this app mints or pays them any more.
enum MTRetiredCoins {
    static let wallPrefix = "vpnwall:"
    static let payPrefix = "vpnpay:"
}

/// THE CALLS' COINS ARE RETIRED (the author's word 09.10.2026 16:00 MSK: «take everything else out, chats and calls among
/// them»): the seconds an earlier build's calls minted or burned stay in the person's book and in their own chain, read as they
/// were written; nothing in the wallet mints or burns them any more.
enum MTCallMint {
    static let refPrefix = "callmint:"
    static let burnPrefix = "callburn:"
}

/// THE PULL SWITCHES THE AUTO MINTING ON (the author's words 04.10.2026 03:52 and 04:18 MSK: «pulling the wallet's page, as the time
/// panel does, calls the coin for a forced refresh of the tops and the activation of the auto minting once a second»; «at such a
/// refresh switch the auto minting on: every second coins by the box's level»): a pull let go past the coin's trigger mints at once
/// and goes on minting every second -- the box's number of coins, the book multiplies (MTPiLevels.multiplier) -- while the wallet
/// stands open. Time bounds it, not a quicker hand.
/// THE PERSON ENDS IT, NO CLOCK (the author's word 04.10.2026 13:33 MSK: «it must not stop until I touch the coin myself or leave
/// the wallet's page -- it mints only while the wallet's screen is active, without taps on it, and deactivates at any action; all
/// three ran auto and stopped by themselves»; T2 10:29:49-10:30:49Z: on, then off by its window of sixty seconds): the page leaving and the
/// screen locked stop it; nothing else does -- no touch (the author's word 05.10.2026 00:53 MSK: «I did not touch; only leaving the
/// page or locking the screen, touches do not reset the auto minting»; T2 and T3 21:45Z stopped why=touch by a tap on a row). The pull tells the person's pairs the balance now, at most once in fifteen seconds, so their tops move and a
/// hand that pulls on does not flood the queue. The coins are the Pantheon's, the wallet's game.
@MainActor final class MTWalletPull: ObservableObject {
    static let shared = MTWalletPull()
    static let refPrefix = MTPantheon.refPrefix + "pull-"
    @Published private(set) var on = false
    private var told: Double = 0

    func fire() {
        let now = Date().timeIntervalSince1970
        tellPairs(now)
        Task { await MontanaWakePush.sweepPresence(quiet: true) }   // the tops read again from the nodes at once
        Task { await MTTopNet.shared.read() }
        guard !on else { return }
        on = true
        MontanaP2PTrace.mark("wallet_pull", "auto on")
        MTMintBeat.run()   // its seconds ride the one beat of the minting by the second (04.10 18:08)
    }
    /// The page left or the screen locked: the minting stops with it.
    func stop(why: String) {
        guard on else { return }
        on = false
        MontanaP2PTrace.mark("wallet_pull", "auto off why=\(why)")
    }
    func mintSecond() {
        let coins = MTCoinBook.ledger.mintInWindow(1, prefix: Self.refPrefix, seconds: 1)   // the second joins the window of τ1 (04.10)
        MontanaP2PTrace.markFolded("wallet_pull", "coins=\(coins)", window: 60)
    }
    private func tellPairs(_ now: Double) {
        guard 15 <= now - told, let store = ChatStore.live else { return }
        told = now
        for c in store.listChats() where !c.isGroup { if let conv = c.convId { E2E.shared.tellBalance(to: conv) } }
    }
}

/// ONE BEAT FOR THE MINTING BY THE SECOND (the author's word 04.10.2026 18:08 MSK, T2: «the minting's animation must not double,
/// only give the sum in the plus animation»): every source minting by the second -- the wallet's pull, a connected call -- is
/// asked at the same instant, and the second's coins rise once (MTCoinFlash.rise); any other coin of that second -- a tap, a
/// move, the Timer's -- joins the same rise. It runs while any source wants it and stops by itself when none does.
@MainActor enum MTMintBeat {
    private static var beating: Task<Void, Never>?
    static var beats: Bool { beating != nil }
    static func run() {
        guard beating == nil else { return }
        beating = Task { @MainActor in
            while !Task.isCancelled {
                guard MTWalletPull.shared.on else { break }
                MTWalletPull.shared.mintSecond()
                try? await Task.sleep(nanoseconds: UInt64(MTCoinFlash.gather * 1_000_000_000))
                MTCoinFlash.shared.rise()
                try? await Task.sleep(nanoseconds: UInt64((1 - MTCoinFlash.gather) * 1_000_000_000))
            }
            beating = nil
            MTCoinFlash.shared.rise()   // the last second's coins rise too
        }
    }
}

/// THE TIMECHAINS OF THE MINTING (the author's words 04.10.2026 00:25 MSK: «in chess too its own TimeChain of the minting for
/// every move, put in order»; the chain's constitution, points 4 and 5: «build by the Architecture of TimeChains», «build the
/// Economy of Time»). Every source of coins keeps its own chain on this phone -- chess, the Pantheon, the VPN wall, the Timer, the
/// chats' letters, the coins received, given and sent: one link per move of coins, numbered, stamped in milliseconds and sealed
/// by SHA-256 over the link and the seal of the one before, so a link changed or moved breaks every seal after it. The book keeps
/// the balance; the chains keep how every coin came. One seam writes them -- the book's keep, where every new move is written --
/// and a move joins its chain once, by its name. Local today; the core's key from the seed signs their heads next.
enum MTTimeChain {
    struct Link: Codable { let n: Int; let at: Int64; let k: String; let c: Int; let ref: String; let prev: String; let hash: String }
    struct Head: Equatable { let n: Int; let hash: String; let whole: Bool }
    static let genesis = String(repeating: "0", count: 64)
    /// ONE MOMENT, THE SAME ON EVERY DEVICE TO THE MILLISECOND (the author's word 06.10.2026 11:2x MSK: «everything to the millisecond,
    /// exact on all nodes, the sender and the receivers above all»): a move is born at a whole millisecond, and every road writes that
    /// millisecond as it is -- the lane, the chains, the book of another device of the words. `Int64(at * 1000)` cut the fraction:
    /// 5 185 of the iPhone 17's 15 331 moves reached the seed's other devices a millisecond earlier than their owner wrote them.
    nonisolated static func ms(_ moment: Double) -> Int64 { Int64((moment * 1000).rounded()) }
    nonisolated static func now() -> Double { Double(ms(Date().timeIntervalSince1970)) / 1000 }
    /// The sources, each its own chain, in the wallet's order.
    static let sources = ["pi", "chess", "pantheon", "vpnwall", "vpnpay", "timer", "chats", "groups", "channels", "comments", "wall", "received", "spent", "sent", "calls", "letters", "system"]
    private static let q = DispatchQueue(label: "montana.TimeChains", qos: .utility)
    private struct Held { var n: Int; var hash: String; var refs: Set<String> }
    private static var held: [String: Held] = [:]   // each chain read once, on q

    static func source(of e: MTCoinEntry) -> String { source(ref: e.ref, kind: e.k, peer: e.peer) }
    static func source(ref r: String, kind: MTCoinEntry.Kind, peer: String? = nil) -> String {
        if MTChessCoins.owns(r) { return "chess" }   // the moves, the wins and losses before the pot, the pot and its stakes (06.10)
        if r.hasPrefix(MTPantheon.refPrefix) { return "pantheon" }
        if r.hasPrefix(MTRetiredCoins.wallPrefix) { return "vpnwall" }   // the retired VPN wall's chains, read as written (08.10)
        if r.hasPrefix(MTRetiredCoins.payPrefix) { return "vpnpay" }
        if r.hasPrefix(MTCallMint.refPrefix) { return "calls" }
        if r.hasPrefix(MTChessTimer.refPrefix) { return "timer" }
        if MTBoardCoins.owns(r) { return "comments" }
        switch kind {
        case .earn:
            // A GROUP'S AND A CHANNEL'S COINS STAND IN THEIR OWN CHAINS (the author's words 06.10.2026 11:5x-12:0x MSK: «their own
            // TimeChain and their own app»): the letter's conversation names its chain.
            guard let p = peer, MTGroup.isKey(p) else { return "chats" }
            return MTGroup.shared.kind(p) == .channel ? "channels" : "groups"
        case .receive: return "received"
        case .spend: return "spent"
        case .send: return "sent"
        case .burn: return r.hasPrefix(MTCoinBurn.callPrefix) ? "calls" : "letters"
        }
    }
    /// The app whose coins a chain keeps: the icon above the wallet's coin while the chain's coins are born (MTCoinFlash.apps).
    static func app(_ source: String) -> MTApplication? {
        switch source {
        case "chess", "timer": return .chess
        case "pantheon": return .wallet
        case "calls": return .calls
        case "chats": return .chats
        case "groups": return .groups
        case "channels": return .channels
        case "comments", "wall": return .feed
        default: return nil
        }
    }
    private static func file(_ chain: String) -> URL? { MTTimeChainPlace.file(chain) }
    /// The person lifted into the seat: the chains held in memory belong to the person who left, and the lifted person's chains of
    /// the builds before are laid into their TimeChain folder at the next ask.
    static func forget() { q.async { held = [:]; MTTimeChainPlace.settle() } }
    /// The seal: SHA-256 over the link's fields, one per line, the previous seal last.
    static func seal(n: Int, at: Int64, k: String, c: Int, ref: String, prev: String) -> String {
        let body = [String(n), String(at), k, String(c), ref, prev].joined(separator: "\n")
        return SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private static func links(_ chain: String) -> [Link] {
        guard let u = file(chain), let text = try? String(contentsOf: u, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        return text.split(separator: "\n").compactMap { try? decoder.decode(Link.self, from: Data($0.utf8)) }
    }
    private static func state(_ chain: String) -> Held {
        if let h = held[chain] { return h }
        let all = links(chain)
        let h = Held(n: all.last?.n ?? 0, hash: all.last?.hash ?? genesis, refs: Set(all.map(\.ref)))
        held[chain] = h
        return h
    }
    /// One move of coins joins its source's chain, once by its name, in the order the moves were written.
    static func append(_ e: MTCoinEntry) { note(source(of: e), kind: e.k.rawValue, coins: e.c, ref: e.ref, at: e.at) }
    /// The book's whole past in one turn of the queue, not a turn for every move (04.10).
    static func appendPast(_ moves: [MTCoinEntry]) {
        let links = moves.map { e in (chain: source(of: e), kind: e.k.rawValue, coins: e.c, ref: e.ref, at: e.at) }
        q.async { for l in links { write(l.chain, kind: l.kind, coins: l.coins, ref: l.ref, at: l.at) } }
    }
    /// One link that is not a move of coins (a level of π reached): the same seal, the same once-by-name.
    static func note(_ chain: String, kind: String, coins: Int, ref: String, at moment: Double = Date().timeIntervalSince1970) {
        q.async { write(chain, kind: kind, coins: coins, ref: ref, at: moment) }
    }
    /// THE WALL'S CHAIN (the author's word 04.10.2026 02:38 MSK): my wall's posts as they stand -- a post not yet chained joins as
    /// born (post), one whose words or files moved as changed (edit), one chained and no longer standing as taken down (gone); the
    /// births in the order the posts were born. One queue, so every link keeps its place.
    static func wall(_ posts: [(id: String, sig: String, at: Double)]) {
        q.async {
            let refs = state("wall").refs
            var chained = Set<String>(), gone = Set<String>()
            for r in refs {
                let parts = r.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 3, parts[0] == "post" { chained.insert(String(parts[1])) }
                if parts.count == 2, parts[0] == "gone" { gone.insert(String(parts[1])) }
            }
            let now = Date().timeIntervalSince1970
            for p in posts.sorted(by: { a, b in a.at < b.at }) {
                let ref = "post:" + p.id + ":" + p.sig
                guard !refs.contains(ref) else { continue }
                let changed = chained.contains(p.id)
                write("wall", kind: changed ? "edit" : "post", coins: 0, ref: ref, at: changed ? now : p.at)
                chained.insert(p.id)
            }
            let standing = Set(posts.map { p in p.id })
            for id in chained.subtracting(standing).subtracting(gone).sorted() {
                write("wall", kind: "gone", coins: 0, ref: "gone:" + id, at: now)
            }
        }
    }
    /// Queue-only: one link joins its chain, once by its name.
    private static func write(_ chain: String, kind: String, coins: Int, ref: String, at moment: Double) {
        let at = ms(moment)
        do {
            var h = state(chain)
            guard !h.refs.contains(ref), let u = file(chain) else { return }
            let n = h.n + 1
            let hash = seal(n: n, at: at, k: kind, c: coins, ref: ref, prev: h.hash)
            guard var line = try? JSONEncoder().encode(Link(n: n, at: at, k: kind, c: coins, ref: ref, prev: h.hash, hash: hash)) else { return }
            line.append(0x0A)
            // THE LINKS OF A SECOND RIDE ONE WRITE (the author's word 04.10.2026 12:27 MSK, the heat of the minting): the seal is
            // made at once and the link waits a second for its file with the others. A write that fails leaves the link out of the
            // file, and the next reading of the book appends it again by its name (MTLocalCoinLedger.load).
            waiting[u, default: Data()].append(line)
            h.n = n; h.hash = hash; h.refs.insert(ref)
            held[chain] = h
            if !due {
                due = true
                q.asyncAfter(deadline: .now() + 1) { writeWaiting() }
            }
        }
    }
    private static var waiting: [URL: Data] = [:]   // on q: the links sealed and not yet in their files
    private static var due = false
    /// Queue-only: every waiting link into its chain's file.
    private static func writeWaiting() {
        due = false
        let all = waiting
        waiting = [:]
        for (u, data) in all {
            if let f = try? FileHandle(forWritingTo: u) {
                _ = try? f.seekToEnd()
                try? f.write(contentsOf: data)
                try? f.close()
            } else if !FileManager.default.fileExists(atPath: u.path) {
                // Born only where none stands: a chain that stands but would not open is never written over.
                try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }
    /// The app leaves the screen: the waiting links are written now.
    static func flush() { q.async { writeWaiting() } }
    /// Every link of a chain as its file holds it (the chain's own page, the history's seals).
    static func read(_ chain: String, done: @escaping ([Link]) -> Void) {
        q.async {
            let all = links(chain)
            DispatchQueue.main.async { done(all) }
        }
    }
    /// The chain read whole from its file and every seal checked from the genesis: its length, its head, whether it is whole.
    static func head(_ chain: String, done: @escaping (Head) -> Void) {
        q.async {
            var prev = genesis, whole = true, n = 0
            for l in links(chain) {
                n += 1
                guard l.n == n, l.prev == prev, l.hash == seal(n: l.n, at: l.at, k: l.k, c: l.c, ref: l.ref, prev: l.prev) else { whole = false; break }
                prev = l.hash
            }
            let h = Head(n: n, hash: prev, whole: whole)
            DispatchQueue.main.async { done(h) }
        }
    }
}

// MARK: - THE CHAIN OF THE PERSON (the author's words 10.10.2026 13:4x, 15:0x and 15:2x MSK)

/// THE CHAIN OF THE PERSON COUNTS THE SECONDS THE WORDS WERE ON THE NETWORK (the author's word 10.10.2026 13:4x MSK: «in this
/// section the first TimeChain is called Person: it shows the levels of the person, and the count goes only for the seconds this
/// seed was actually online on any device»; App, «The chains of time a client shows»). A second counts while the wallet stands on
/// the screen and a node answers its exchanges: the seconds are the node's own, read from the answer's Date header, never this
/// phone's clock, and two answers at most `reach` apart vouch for every second between them. The seconds are kept as spans and
/// joined with the spans every other device of the words laid under the words' own key -- one sealed piece a device on every
/// node, beside the coin book -- so two devices present in one second add one second. The level is the number of whole doublings
/// of the count (Canon, «The level of the chain of the person»: bit_length(s) - 1, none below one second); one link a level, at
/// the second the count reached it, sealed on the one before by MTTimeChain's own seal, so the same union gives the same chain on
/// every device. The person sees it; it is published nowhere and leaves the phone only sealed under the words.
@MainActor final class MTPersonChain: ObservableObject {
    static let shared = MTPersonChain()
    struct Span: Codable, Equatable { var a: Int64; var b: Int64 }   // node seconds, both ends counted
    struct Away: Codable { var at: Int64; var level: Int }
    /// Two answers this far apart or nearer vouch for every second between them: the wallet asks the nodes every three seconds
    /// while it stands open, and an answer slow by a beat or two still continues the span.
    static let reach: Int64 = 10
    static let awayPrefix = MTPantheon.refPrefix + "away-"
    @Published private(set) var seconds: Int64 = 0
    @Published private(set) var links: [MTTimeChain.Link] = []
    var level: Int? { Self.level(seconds) }
    private var spans: [Span] = []
    private var lane = Data()
    private var last: Int64?   // the node second of the last answer in this stretch on the screen
    private var away: Away?    // the app left the screen: the node second of its last answer and the Global Level of then
    private var loaded = false, dirty = false, putting = false, keepDue = false, checked = false
    private var putAt: Double = 0, gotAt: Double = 0
    private var opened: [String: Data] = [:]   // a piece's name: its lane, opened once
    private var mine: [String: String] = [:]   // a node's door: the piece of this lane it holds now
    private var stale = Set<String>()

    /// THE LEVEL (Canon, «The level of the chain of the person»): the whole doublings of the count, none below one second.
    nonisolated static func level(_ s: Int64) -> Int? { s < 1 ? nil : 63 - s.leadingZeroBitCount }
    /// THE FROZEN VECTORS (Canon: level(1) = 0, level(3) = 1, level(1048576) = 20, none below one second) and the doubling's edge at
    /// every power: three refuses a logarithm rounded upward, one refuses a bit length taken without its minus one, the edges refuse
    /// a level that opens a second early or late.
    nonisolated static func levelKAT() -> Bool {
        guard level(1) == 0, level(3) == 1, level(1_048_576) == 20, level(0) == nil, level(-5) == nil else { return false }
        for k in 1...62 where level(Int64(1) << k) != k || level((Int64(1) << k) - 1) != k - 1 { return false }
        return level(Int64.max) == 62
    }
    /// THE GLOBAL LEVEL OF THE PERSON (the author's word 10.10.2026 15:0x MSK: «the lowest level among the chain of the person and
    /// the chain of the wallet becomes the Global Level of the person»): the lower of the person's level and the wallet's level of π.
    static func global(person: Int?, balance: Int) -> Int { min(person ?? 0, MTPiLevels.place(balance)) }

    private struct Kept: Codable { var lane: String; var spans: [Span]; var away: Away? }
    private static var file: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("person-seconds.json") }
    private func load() {
        guard !loaded else { return }
        loaded = true
        if let u = Self.file, let d = try? Data(contentsOf: u), let k = try? JSONDecoder().decode(Kept.self, from: d),
           let l = Data(base64Encoded: k.lane), l.count == 16 {
            lane = l; spans = Self.joined(k.spans); away = k.away
        } else {
            lane = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        }
        recount(write: false)
    }
    private func keep() {
        guard let u = Self.file, let d = try? JSONEncoder().encode(Kept(lane: lane.base64EncodedString(), spans: spans, away: away)) else { return }
        try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func keepSoon() {
        guard !keepDue else { return }
        keepDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.keepDue = false; self?.keep() }
    }
    /// A person lifted into the seat: the seconds of the person who left go with their folder; the seated person's are read next.
    func reread() {
        loaded = false; spans = []; links = []; seconds = 0; last = nil; away = nil
        opened = [:]; mine = [:]; stale = []; dirty = false
    }

    /// Spans joined: sorted, and any two that touch or overlap become one -- a second is counted once however many devices held it.
    nonisolated static func joined(_ all: [Span]) -> [Span] {
        var out: [Span] = []
        for s in all.filter({ x in x.a <= x.b }).sorted(by: { x, y in x.a < y.a }) {
            if let l = out.last, s.a <= l.b + 1 { out[out.count - 1].b = max(l.b, s.b) } else { out.append(s) }
        }
        return out
    }
    /// One link a level, at the node second the count reached 2^k, each sealed on the one before (MTTimeChain.seal).
    nonisolated static func chain(_ spans: [Span]) -> [MTTimeChain.Link] {
        var out: [MTTimeChain.Link] = [], count: Int64 = 0, next: Int64 = 1, prev = MTTimeChain.genesis
        for s in spans {
            let len = s.b - s.a + 1
            while next <= count + len {
                let at = (s.a + (next - count) - 1) * 1000
                let k = out.count, ref = "level:" + String(out.count)
                let hash = MTTimeChain.seal(n: k + 1, at: at, k: "level", c: k, ref: ref, prev: prev)
                out.append(MTTimeChain.Link(n: k + 1, at: at, k: "level", c: k, ref: ref, prev: prev, hash: hash))
                prev = hash
                guard next <= Int64.max / 2 else { return out }
                next *= 2
            }
            count += len
        }
        return out
    }
    /// The count and the links read again; the chain's file (TimeChain/wallet-person.jsonl, seen in Files) follows a new level.
    private func recount(write: Bool = true) {
        seconds = spans.reduce(0) { n, s in n + (s.b - s.a + 1) }
        let fresh = Self.chain(spans)
        guard fresh.last?.hash != links.last?.hash else { return }   // the head's seal seals the whole chain
        links = fresh
        guard write, let u = MTTimeChainPlace.file("person") else { return }
        var body = Data()
        for l in fresh { if let d = try? JSONEncoder().encode(l) { body.append(d); body.append(0x0A) } }
        try? body.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// A node answered an exchange of this app (MTCoinVault.post): while the app stands on the screen its second counts, and so does
    /// every second back to the answer before it when they are no further apart than the reach.
    func answered(_ resp: URLResponse?) {
        guard UIApplication.shared.applicationState == .active,
              let hdr = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date"),
              let at = MontanaWakePush.httpDateFormatter.date(from: hdr) else { return }
        load()
        let s = Int64(at.timeIntervalSince1970)
        if let w = away { came(back: s, from: w) }
        let from = last.flatMap { l in l <= s && s - l <= Self.reach ? l : nil } ?? s
        last = max(last ?? s, s)
        let before = seconds
        spans = Self.joined(spans + [Span(a: from, b: s)])
        recount()
        guard seconds != before else { return }
        dirty = true
        keepSoon()
    }

    /// THE MINTING GOES ON WHILE THE APP IS AWAY (the author's word 10.10.2026 15:0x MSK: «when any of our apps is minimized, the
    /// minting must go on at the lowest level among the chain of the person and the chain of the wallet -- the levels of π»): the app
    /// leaving the screen keeps the node second of its last answer and the Global Level of that moment; the first answer after its
    /// return names the second it came back, and every second between is minted at that level, the limit of a second at most
    /// (MTCoinBook.limit). Both ends are the nodes' seconds, so a clock turned on the phone moves nothing, and a stretch with no
    /// answer before the leave mints nothing.
    func left(level global: Int) {
        load()
        defer { last = nil }
        guard let from = last, 0 < global else { return }
        away = Away(at: from, level: min(global, MTCoinBook.limit))
        keep()
        Task { await self.put() }
    }
    private func came(back s: Int64, from w: Away) {
        away = nil
        keep()
        let gone = s - w.at
        guard 0 < gone, 0 < w.level else { return }
        let (coins, over) = Int(gone).multipliedReportingOverflow(by: w.level)
        guard !over else { return }
        let minted = MTCoinBook.ledger.mintInWindow(coins, prefix: Self.awayPrefix, seconds: Int(gone), byLevel: false)
        MontanaP2PTrace.mark("person_away", "seconds=\(gone) level=\(w.level) minted=\(minted)")
    }

    // MARK: the devices of the words join their seconds: one sealed piece a device, beside the coin book on every node
    private static let aad = Data("mt.person.chain".utf8)   // NOT-UI: the words the piece's seal is bound to
    private struct Piece: Codable { var lane: String; var spans: [Span] }
    /// The wallet's live beat asks this every turn: the other devices' pieces every half minute, this device's union when it moved,
    /// once a minute at most.
    func tick() async {
        load()
        if !checked { checked = true; MontanaP2PTrace.mark("person_self", "ok=\(Self.levelKAT() ? 1 : 0)") }
        let now = Date().timeIntervalSince1970
        if 30 <= now - gotAt { gotAt = now; await gather() }
        if dirty, 60 <= now - putAt { await put() }
    }
    private func put() async {
        guard !putting, let k = MTCoinVault.personRow(),
              let plain = try? JSONEncoder().encode(Piece(lane: lane.base64EncodedString(), spans: spans)),
              let sealed = try? ChaChaPoly.seal(plain, using: k.seal, authenticating: Self.aad).combined else { return }
        putting = true
        defer { putting = false }
        putAt = Date().timeIntervalSince1970
        dirty = false
        let token = MontanaHomeNode.hex(k.token)
        let id = MontanaHomeNode.hex(Data(SHA256.hash(data: sealed)))
        var laid = 0
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            let gone = Array(stale.union(mine[door].map { p in [p] } ?? [])).filter { p in p != id }
            let (code, o) = await MTCoinVault.post(door + "/vault-put", ["token": token, "blob": sealed.base64EncodedString(), "replace": gone], timeout: 10)
            guard code == 200, let piece = o?["piece"] as? String else { continue }
            mine[door] = piece
            opened[piece] = lane
            laid += 1
        }
        if 0 < laid { stale = [] } else { dirty = true }
        MontanaP2PTrace.markFolded("person_put", "spans=\(spans.count) seconds=\(seconds) doors=\(laid)", window: 60)
    }
    private func gather() async {
        guard let k = MTCoinVault.personRow() else { return }
        let gen = MTCoinBook.generation
        let token = MontanaHomeNode.hex(k.token)
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            guard case let (200, o?) = await MTCoinVault.post(door + "/vault-get", ["token": token, "have": Array(opened.keys.prefix(256))], timeout: 6),
                  let held = o["held"] as? [String] else { continue }
            guard gen == MTCoinBook.generation else { return }   // the seat moved during the wait: nothing of the person who left joins
            let horizon = Int64(MontanaWakePush.nodeNow()) + 60   // no second of the future is a second lived
            var got: [Span] = []
            for x in (o["pieces"] as? [[String: Any]]) ?? [] {
                guard let id = x["piece"] as? String, let b = (x["blob"] as? String).flatMap({ s in Data(base64Encoded: s) }),
                      MontanaHomeNode.hex(Data(SHA256.hash(data: b))) == id,   // a piece is its own name
                      let box = try? ChaChaPoly.SealedBox(combined: b),
                      let plain = try? ChaChaPoly.open(box, using: k.seal, authenticating: Self.aad),
                      let p = try? JSONDecoder().decode(Piece.self, from: plain), let l = Data(base64Encoded: p.lane) else { continue }
                opened[id] = l
                if l == lane {
                    if mine[door] != id { stale.insert(id) }
                    continue
                }
                got += p.spans.filter { s in s.b <= horizon }
            }
            let standing = Set(held)
            opened = opened.filter { e in standing.contains(e.key) }
            let before = seconds
            spans = Self.joined(spans + got)
            recount()
            if seconds != before { dirty = true; keepSoon() }
            MontanaP2PTrace.markFolded("person_get", "seconds=\(seconds) level=\(level ?? -1) joined=\(seconds - before)", window: 60)
            return
        }
    }
}

// MARK: - THE COIN CORE OF THE APP (the author's words 03.10 13:40, 13:52 and 13:53 MSK)

/// ONE MOVE OF COINS on this phone's book: a coin earned by a letter of the ribbon, coins received in a chat or on a letter,
/// coins given on a letter or a post, coins sent to a person. The amount is whole coins (one coin is one billionth of a
/// Montana) and always positive; the kind says which way it goes. `ref` is the move's own name -- a letter's wire name, the
/// name a reaction carries -- and a name is taken once, ever: a letter that lands twice, a word the lane repeats, a launch
/// that reads the book again, never pays twice.
struct MTCoinEntry: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case earn, receive, spend, send, burn }
    var k: Kind
    var c: Int
    var ref: String
    var peer: String? = nil
    var on: String? = nil      // the letter (its wire name) or the post («post:» + its id) the coins were given on
    var at: Double
    var id: String { k.rawValue + ":" + ref }
    var signed: Int { (k == .earn || k == .receive) ? c : -c }
    /// A NAME A RESTORE GIVES A LETTER NAMES NO MOVE (the author's words 09.10.2026 11:3x-11:4x MSK: "the balance swelled, this person
    /// never had 5 million -- check it, it is a hole"; "we have a cryptographic TimeChain: only unambiguous mathematics, and the
    /// restore must bring back the incomes and the expenses right"). A coin letter moves its coins once, under its wire name, the one
    /// name both phones hold. A restore names its copy of the letter anew (MTRestoredMid: the archive's "arc:", the keepers' "given:"),
    /// and the book credited the same letter again under that name: T1's book of 09.10 held 20 credits under "arc:", 5 316 382
    /// coins, beside the same letters' 22 credits under their wire names, 5 316 541, and the seed's vault had carried them to every
    /// device of the words (the balance 5 850 661 where the moves sum to 534 279). Every door of the book passes such a move -- the
    /// reading, the joining, the taking -- on every device alike.
    var restoredName: Bool { MTRestoredMid.holds(ref) }
    /// THE LETTER THE COINS STAND UNDER (MTLocalCoinLedger.coins(on:)), or nil. A bubble's own coin of the builds before the burning
    /// (MTCoinSend.pay) -- paid by the writer to the reader as a reaction word -- stands under no bubble: the author's word
    /// 05.10.2026 22:29 MSK, «in ordinary chats take away the coin under every message as a reaction», takes it from the bubbles
    /// sent before too, on both phones; the coins stay where the book moved them.
    var shownOn: String? {
        ref.hasPrefix(MTCoinSend.bubblePrefix) || ref.hasPrefix(MTCoinSend.receivedPrefix + MTCoinSend.bubblePrefix) ? nil : on
    }
}

/// THE ONE DOOR OF THE COINS (the author's word 03.10 13:52: «an in-app coin core with no crypto core, behind one
/// protocol»). Every reader and writer of coins in the app speaks to this and to nothing else: the wallet, the ribbon's
/// minting, the paid reactions, the coin letters in a chat. THE SEAM FOR THE REAL MONEY IS THIS PROTOCOL: the day the
/// protocol core opens this person's wallet and offers a door that mints for a letter and transfers between wallets
/// (montana_core.h has neither today), a second implementation answers here and MTCoinBook.ledger names it -- nothing
/// that calls these doors changes. Until then the book is LOCAL: kept on this phone, never a note of the core's wallet.
@MainActor protocol MTCoinLedger: AnyObject {
    var balance: Int { get }
    var entries: [MTCoinEntry] { get }
    /// The box's coins for every name not paid before (MTPiLevels.multiplier), `times` levels a name (one, since the Money Flow
    /// mints a bubble's level by mint, 07.10); the coins this call added. `peer` names the conversation the
    /// letters came in when it is a group's or a channel's: their coins stand in their own chains.
    @discardableResult func earn(_ names: [String], times: Int, peer: String?) -> Int
    /// A game's coins gathered in its open window of τ1 and booked as one move when it closes (MTLocalCoinLedger.mintInWindow).
    /// `seconds` is the span the coins were earned over: one for a tap or a second now, more for seconds lived away. `byLevel`
    /// multiplies the coins by the box's level (MTPiLevels.multiplier); a call's second is one coin and no level (MTCallMint).
    @discardableResult func mintInWindow(_ coins: Int, prefix: String, seconds: Int, byLevel: Bool) -> Int
    /// Coins already counted elsewhere, minted once under their name: a chess game's pot at its end (MTChessCoins.pay), whose
    /// moves named their coins at their makers' levels. The coins this call added; none when the name was minted before.
    @discardableResult func mint(_ coins: Int, ref: String, peer: String?) -> Int
    /// Coins burned by a service used (a call's seconds, a letter through a node not one's own): never more than the balance
    /// holds, never a refusal of the service; the count burned.
    @discardableResult func burn(_ coins: Int, ref: String) -> Int
    /// Coins given on a letter or a post; refused (false) when the balance is short or the name was taken.
    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool
    /// Coins sent to a person in a coin letter; refused (false) when the balance is short or the name was taken.
    func send(_ coins: Int, to peer: String, ref: String) -> Bool
    /// Coins that arrived, credited once by their name; false when the name was taken already.
    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool
    /// How many coins stand on a letter or a post, given and received alike.
    func coins(on target: String) -> Int
}

extension MTCoinLedger {
    /// A letter's coins in a conversation of two (the ribbon's chats).
    @discardableResult func earn(_ names: [String]) -> Int { earn(names, times: 1, peer: nil) }
    /// A game's or a ribbon's coins with no conversation named.
    @discardableResult func earn(_ names: [String], times: Int) -> Int { earn(names, times: times, peer: nil) }
    /// A game's coins at the box's level.
    @discardableResult func mintInWindow(_ coins: Int, prefix: String, seconds: Int) -> Int {
        mintInWindow(coins, prefix: prefix, seconds: seconds, byLevel: true)
    }
}

/// THE TIMECHAIN FOLDER (the author's words 04.10.2026 13:42 MSK: «in the Montana folder make a folder TimeChain, so I see it on all
/// devices, with the wallet's TimeChain of each device in it»; «TimeChain is written so, exactly, everywhere»): the one folder the
/// Files app shows as On My iPhone, Montana, TimeChain -- the comment chains a person wrote (MTBoardSeen, the author's word 02.10
/// 15:09) and the wallet's chains, one file a source (wallet-pantheon.jsonl, wallet-chats.jsonl ...). The folder is the seated
/// person's (SeedScope.seatFolders): parked and lifted with them, so no chain of one person stays to the next. Laid once a seat:
/// the comment chains' folder of the builds before («Timechain») takes the one name -- through a step on a disk that knows no case,
/// its files moving in on one that does -- and the wallet's chains of the builds before move in from the book's folder.
enum MTTimeChainPlace {
    private static let lock = NSLock()
    private static var laid = false
    static func dir() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let root = docs.appendingPathComponent(MontanaPaths.root).appendingPathComponent("TimeChain", isDirectory: true)
        lock.lock(); defer { lock.unlock() }
        if !laid {
            laid = true
            lay(root, before: docs.appendingPathComponent(MontanaPaths.root).appendingPathComponent("Timechain", isDirectory: true))
        }
        return root
    }
    static func file(_ chain: String) -> URL? { dir()?.appendingPathComponent("wallet-" + chain + ".jsonl") }
    /// A seat's move: the lifted person's folder is laid again at the next ask.
    static func settle() { lock.lock(); laid = false; lock.unlock() }
    private static func lay(_ root: URL, before old: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path) {
            let was = (try? old.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            let now = (try? root.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier
            if let was, let now, was.isEqual(now) {
                let step = old.deletingLastPathComponent().appendingPathComponent("TimeChain-" + UUID().uuidString, isDirectory: true)
                if (try? fm.moveItem(at: old, to: step)) != nil { try? fm.moveItem(at: step, to: root) }
            } else if !fm.fileExists(atPath: root.path) {
                try? fm.moveItem(at: old, to: root)
            } else {
                for n in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where !fm.fileExists(atPath: root.appendingPathComponent(n).path) {
                    try? fm.moveItem(at: old.appendingPathComponent(n), to: root.appendingPathComponent(n))
                }
                if ((try? fm.contentsOfDirectory(atPath: old.path)) ?? ["held"]).isEmpty { try? fm.removeItem(at: old) }
            }
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        guard let coins = MTCoinPlace.dir, let names = try? fm.contentsOfDirectory(atPath: coins.path) else { return }
        var moved = 0
        for n in names where n.hasPrefix("chain-") && n.hasSuffix(".jsonl") {
            let to = root.appendingPathComponent("wallet-" + String(n.dropFirst("chain-".count)))
            guard !fm.fileExists(atPath: to.path) else { continue }
            if (try? fm.moveItem(at: coins.appendingPathComponent(n), to: to)) != nil { moved += 1 }
        }
        if 0 < moved { MontanaP2PTrace.mark("timechain_place", "laid=\(moved)") }
    }
}

/// The app's one book of coins, today (see MTCoinLedger for the seam).
enum MTCoinBook {
    @MainActor static var ledger: any MTCoinLedger { MTLocalCoinLedger.shared.whole }
    /// THE LIMIT OF A SECOND (the constitution of the chain, point 11, the author's words 04.10.2026 17:27 MSK and 05.10.2026 14:17
    /// MSK): a second of life mints thirteen coins at most -- the level's multiplier stops at it, MTLocalCoinLedger.priced shares it
    /// among every minting of the second, and the music doubles it (MTPiLevels.ceiling); a bubble of the Money Flow mints the
    /// level's coins by its name, beside the second's room (MTMoneyFlow, 07.10.2026 21:4x MSK).
    static let limit = 13
    /// THE PRICE OF A SECOND (point 11 as the author changed it 05.10.2026 14:17 MSK: «a second = 1 coin everywhere, point 11
    /// changes»): one coin -- a person's hour is 3 600 coins and their personal rate is read by it (MTHourWorth, MTPersonalRate);
    /// a second of a connected call mints it times each side's level in a Money Flow chat and burns it on each side in an ordinary
    /// one (MTCallMint, 07.10.2026 21:3x-21:4x MSK).
    static let price = 1
    /// THE TICKER OF THE MONTANA TIME COIN (the constitution of the chain, point 12, the author's word 04.10.2026 17:31 MSK): one
    /// symbol in every language, beside the balance.
    static let ticker = "$TCM"
    /// THE BOOK'S GENERATION (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin audit's second point): one
    /// more at every seat's move, before anything is read again. A gather begun under the person who left took their key, waited on
    /// the nodes, and then read the book of the person seated -- laying it over every piece of the old seed (the whole book lost
    /// to a restore on another phone). A gather compares this after every wait and writes nothing once it moved.
    @MainActor static private(set) var generation = 0
    /// A PERSON LIFTED INTO THE SEAT READS THEIR OWN COINS (the author's word 04.10.2026 03:38 MSK): every owner of coins on this phone
    /// lets the person who left go and reads the folder of the person seated (MTCoinPlace) -- the chains first, so the book's past
    /// joins the seated person's chains.
    @MainActor static func reread() {
        generation &+= 1
        MTCoinVault.shared.forget()
        MTTimeChainTip.shared.reread()
        MTTimeChain.forget()
        MTPersonChain.shared.reread()
        MTLocalCoinLedger.shared.reread()
        MTChatMint.shared.reread()
        MTCoinBoard.shared.reread()
        MontanaP2PTrace.mark("coin_book", "reread")
    }
    /// NO LIMIT BUT THE BALANCE AND ONE AT LEAST (the author's word 03.10): a move of any whole number of coins from one up; the
    /// one bound is the arithmetic's -- the count must still fit the book's integer beside the balance -- never a rule of the coin.
    static func fits(_ coins: Int, beside balance: Int) -> Bool { 0 < coins && !balance.addingReportingOverflow(coins).overflow }
}

/// THE LOCAL BOOK: one line of JSON per move, appended, in Application Support (protected until the first unlock, as the
/// chat coins' names are). The balance and the totals are the sum of the lines, recounted at launch -- the file is the one
/// truth, the numbers are its reading.
/// THE PERSON'S COINS LIVE IN THE PERSON'S FOLDER (the author's word 04.10.2026 03:38 MSK: «I came in with another account on T1,
/// another seed, and the wallet's balance of the other account is here -- a gross violation»). The book, its TimeChains and the
/// chats' tally lay among the phone's own files, so a seat's move (MTSeats) parked the person and left their coins to the next
/// one. They live in Montana/Coins, a folder of the person seated (SeedScope.seatFolders): parked with the person, lifted with
/// them. The files of the builds before belong to the person who held the phone when the book was born -- the first seat born
/// before the book's first move -- and are laid into that person's folder once, the first time the place is asked for.
enum MTCoinPlace {
    static let book = "coin-ledger.jsonl"   // NOT-UI: the book's file name
    static let tally = "chat-coins.txt"     // NOT-UI: the chats' tally
    private static let montana = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Montana", isDirectory: true)
    static let dir: URL? = settle(montana?.appendingPathComponent("Coins", isDirectory: true))
    static func file(_ name: String) -> URL? { dir?.appendingPathComponent(name) }
    /// THE BOOK OF A PERSON FORGOTTEN LEAVES WITH THEM (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin
    /// audit's eighth point): «Forget the device» with no other seat left this folder in place, and the next seed's book was the
    /// forgotten one's -- read, shown and laid on the nodes under the new seed. The folder's files are set aside whole, under the
    /// moment of the forgetting, and nothing reads them again: the coins ride their own seed on the nodes (MTCoinVault), and this
    /// copy is the phone's last word for whatever a node had not heard yet.
    private static let forgottenRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Montana", isDirectory: true).appendingPathComponent("CoinsForgotten", isDirectory: true)
    static func setAside() {
        guard let dir, let forgottenRoot else { return }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        guard !names.isEmpty else { return }
        let place = forgottenRoot.appendingPathComponent(String(Int64(Date().timeIntervalSince1970 * 1000)), isDirectory: true)
        try? fm.createDirectory(at: place, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var moved = 0
        for name in names where (try? fm.moveItem(at: dir.appendingPathComponent(name), to: place.appendingPathComponent(name))) != nil { moved += 1 }
        MontanaP2PTrace.mark("coin_place", "forgotten set aside=\(moved)/\(names.count)")
    }

    private static func settle(_ coins: URL?) -> URL? {
        guard let montana, let coins else { return nil }
        let fm = FileManager.default
        let sealed: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        try? fm.createDirectory(at: coins, withIntermediateDirectories: true, attributes: sealed)
        let names = ((try? fm.contentsOfDirectory(atPath: montana.path)) ?? []).filter { n in
            n == book || n == tally || (n.hasPrefix("chain-") && n.hasSuffix(".jsonl"))
        }
        guard !names.isEmpty else { return coins }
        let first = firstMove(montana.appendingPathComponent(book))
        let seats = MTSeats.book()
        let owner = seats.seats.filter { s in first.map { at in s.born <= at } ?? true }.min { a, b in a.born < b.born }?.id
        // A BOOK WHOSE OWNER IS NOT KNOWN STAYS WHERE IT STANDS (the author's word «fix all points in order» 05.10.2026 21:4x MSK,
        // the coin audit's seventh point): born is written at a seat's first move -- after the book's first move -- so with two
        // seats or more the filter found nobody and the book went to whoever sat. It moves only to a person the seats name.
        if owner == nil, 1 < seats.seats.count {
            MontanaP2PTrace.mark("coin_place", "owner unknown -- the root book stays")
            return coins
        }
        var place = coins
        if let owner, owner != seats.active { place = MTSeats.shelf(folder: "AS:Montana/Coins", seat: owner) }
        try? fm.createDirectory(at: place, withIntermediateDirectories: true, attributes: sealed)
        var laid = 0
        for n in names where !fm.fileExists(atPath: place.appendingPathComponent(n).path) {
            if (try? fm.moveItem(at: montana.appendingPathComponent(n), to: place.appendingPathComponent(n))) != nil { laid += 1 }
        }
        MontanaP2PTrace.mark("coin_place", "laid=\(laid)/\(names.count) owner=\(place == coins ? "seated" : "parked")")
        return coins
    }
    /// The moment of the book's first move, from its first line.
    private static func firstMove(_ url: URL) -> Double? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4096), let line = String(decoding: d, as: UTF8.self).split(separator: "\n").first,
              let e = try? JSONDecoder().decode(MTCoinEntry.self, from: Data(line.utf8)) else { return nil }
        return e.at
    }
}

/// THE BOOK'S COUNTS BY SOURCE, ONE CLASSIFICATION (04.10): a move adds to its source's count here, the same for a move taken now
/// and for the whole file folded at its reading.
struct MTCoinCounts {
    var earned = 0
    /// The coins the Pantheon on Fire's taps minted (MTPantheon), counted apart: «coins from chats» counts the chats alone.
    var tapped = 0
    /// The coins of chess (MTChessCoins): a move's coin, a won game's sum taken, a lost game's sum given -- counted apart, so
    /// the received and the reactions rows count people and reactions alone.
    var played = 0
    /// The coins the VPN wall minted by its seconds before the VPN left for its own app (MTRetiredCoins), counted apart.
    var walled = 0
    /// The coins burned by calls and letters (MTCoinBurn), the Economy of Time's sink.
    var burned = 0
    var received = 0
    var spent = 0
    var sent = 0
    /// The tallies saturate, never trap (the coin audit's ninth point, 05.10.2026 21:4x MSK): a sum past the integer is shown at
    /// its edge, and the app lives.
    private static func plus(_ a: Int, _ b: Int) -> Int {
        let (s, over) = a.addingReportingOverflow(b)
        return over ? (0 < b ? Int.max : Int.min) : s
    }
    @MainActor mutating func add(_ e: MTCoinEntry) {
        switch e.k {
        case .earn: earn(e.c, ref: e.ref)
        case .receive: if e.ref.hasPrefix(MTChessCoins.wonPrefix) { played = Self.plus(played, e.c) } else { received = Self.plus(received, e.c) }
        case .spend: if e.ref.hasPrefix(MTChessCoins.lostPrefix) { played = Self.plus(played, -e.c) } else { spent = Self.plus(spent, e.c) }
        case .send: sent = Self.plus(sent, e.c)
        case .burn: burned = Self.plus(burned, e.c)
        }
    }
    /// The game an earning came from, by its name: the Pantheon's taps, chess and its Timer, the retired VPN wall, the chats.
    @MainActor mutating func earn(_ c: Int, ref: String) {
        if ref.hasPrefix(MTPantheon.refPrefix) { tapped = Self.plus(tapped, c) }
        else if ref.hasPrefix(MTChessCoins.movePrefix) || ref.hasPrefix(MTChessTimer.refPrefix) { played = Self.plus(played, c) }   // the Timer is chess too (04.10)
        else if ref.hasPrefix(MTRetiredCoins.wallPrefix) { walled = Self.plus(walled, c) }
        else { earned = Self.plus(earned, c) }
    }
}

@MainActor final class MTLocalCoinLedger: ObservableObject, MTCoinLedger {
    static let shared = MTLocalCoinLedger()
    @Published private(set) var entries: [MTCoinEntry] = []
    @Published private(set) var balance = 0
    @Published private(set) var onTarget: [String: Int] = [:]
    @Published private(set) var counts = MTCoinCounts()
    var earned: Int { counts.earned }
    var tapped: Int { counts.tapped }
    var played: Int { counts.played }
    var walled: Int { counts.walled }
    var burned: Int { counts.burned }
    var received: Int { counts.received }
    var spent: Int { counts.spent }
    var sent: Int { counts.sent }
    /// The highest level of π the balance has filled since the book was read (MTPiLevels): a level reached for the first time is a link.
    private var level = 0
    private var taken = Set<String>()
    /// The pairs whose other end holds these words, as the book says (MTOwnWords): read from the moves at every reading and kept with
    /// every move taken or joined.
    private(set) var ownPeers = Set<String>()
    private var file: URL? { MTCoinPlace.file(MTCoinPlace.book) }
    private let disk = DispatchQueue(label: "montana.coin-ledger", qos: .utility)

    /// The book is born at the app's start (ContentView), so its one reading lands before anyone asks for it.
    static func warm() { _ = shared }

    private init() {
        begin()
        // What waits for the second's write is on disk the moment the app leaves the screen, in that same turn, and the seed's
        // nodes are asked for it at once (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin audit's
        // fifth point: an asynchronous write and an upload a minute later lost the open windows to a process ended in the
        // background, and to a phone lost after it, what no node held yet).
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                MTLocalCoinLedger.shared.writeWhole()
                MTCoinVault.shared.soon("leave", after: 1)
            }
            MTTimeChain.flush()
        }
    }
    /// The person lifted into the seat: the book of the person who left is let go and the seated person's book is read
    /// (MTCoinBook.reread).
    func reread() {
        closeWindows(); flush()   // the person who left keeps every coin of their last minute, in their own book
        entries = []; taken = []; onTarget = [:]; counts = MTCoinCounts(); ownPeers = []
        balance = 0; level = 0
        begin()
    }

    /// THE BOOK IS READ ONCE, OFF THE SCREEN'S THREAD, AND SHOWN AT ONCE (the author's words 04.10.2026 13:04-13:10 MSK: «at 13:04
    /// on T1 I open the wallet and it opens long, from a hang -- close it by construction»; «build by constitution 0»). T1's book
    /// of 19 358 moves was read on the main thread the first time anything asked for it -- the wallet's opening, 3.7 s of a still
    /// screen: a decoder made anew for every line, every move appended to a published array that copied itself whole, and a task
    /// of the balance's word queued on the main actor for every move. Now the file is decoded on the book's own queue from the
    /// book's birth, folded into plain sums and published as one assignment; a door of the book asked before the reading lands
    /// waits for that one reading (whole), never for a second.
    private final class Reading: @unchecked Sendable {   // written on the book's queue only, read on the main actor after that queue
        var moves: [MTCoinEntry] = []
        var taken = Set<String>()
    }
    private var reading: Reading?
    var whole: MTLocalCoinLedger { landed(); return self }

    private func begin() {
        let r = Reading()
        reading = r
        let file = self.file
        disk.async {
            (r.moves, r.taken) = MTLocalCoinLedger.decode(file)
            DispatchQueue.main.async { MainActor.assumeIsolated { MTLocalCoinLedger.shared.adopt(r) } }
        }
    }
    private func landed() {
        guard let r = reading else { return }
        let asked = Date()
        // MAIN-SAFE-SYNC: only a door asked before the book's one reading lands waits, and only for that reading, begun at the
        // app's start (warm); the main thread used to do the same reading in full by itself (3.7 s on T1, 04.10), and the queue
        // holds nothing else but the appends of a second's moves. The diary says how long a door waited.
        disk.sync {}
        MontanaP2PTrace.mark("coin_book", "waited ms=\(Int(Date().timeIntervalSince(asked) * 1000))")
        adopt(r)
    }
    /// A line cut short by an ended process is no move: only a whole line counts, once by its name, while the sum still fits.
    nonisolated private static func decode(_ file: URL?) -> ([MTCoinEntry], Set<String>) {
        // ONE BAD BYTE COSTS ONE LINE, NEVER THE BOOK (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin
        // audit's tenth point): the book was read as one UTF-8 text, and a single invalid byte read it as nothing -- an empty book
        // until the nodes filled it again. It is read as bytes, and every line is decoded alone.
        guard let file, let data = try? Data(contentsOf: file) else { return ([], []) }
        let decoder = JSONDecoder()
        var moves: [MTCoinEntry] = []
        var taken = Set<String>()
        var sum = 0, passed = 0, passedCoins = 0
        defer { if 0 < passed { MontanaP2PTrace.mark("coin_book", "passed restored names=\(passed) coins=\(passedCoins)") } }
        for line in data.split(separator: 0x0A) {
            guard let e = try? decoder.decode(MTCoinEntry.self, from: Data(line)), 0 < e.c, !taken.contains(e.id) else { continue }
            if e.restoredName { passed += 1; passedCoins += e.c; continue }
            let (next, over) = sum.addingReportingOverflow(e.signed)
            guard !over else { continue }
            sum = next
            moves.append(e)
            taken.insert(e.id)
        }
        return (moves, taken)
    }
    private func adopt(_ r: Reading) {
        guard reading === r else { return }   // a reading of the person who left the seat
        reading = nil
        var sum = 0, counts = MTCoinCounts(), onTarget: [String: Int] = [:], level = 0
        var levels: [(n: Int, at: Double)] = []
        for e in r.moves {
            sum += e.signed
            counts.add(e)
            if let on = e.shownOn { onTarget[on, default: 0] += e.c }
            let place = MTPiLevels.place(sum)
            if level < place {
                for n in (level + 1)...place { levels.append((n, e.at)) }
                level = place
            }
        }
        entries = r.moves; taken = r.taken; balance = sum; self.counts = counts; self.onTarget = onTarget; self.level = level
        ownPeers = Self.own(r.moves, names: r.taken)
        MontanaP2PTrace.mark("coin_book", "read moves=\(r.moves.count) balance=\(sum) local=1")
        for l in levels { MTTimeChain.note("pi", kind: "level", coins: l.n, ref: "level:" + String(l.n), at: l.at) }
        // THE CHAINS TAKE THE BOOK'S PAST ONCE (04.10): every move written before the chains stood joins its chain in the book's
        // order; a move the chain already holds is passed by its name.
        MTTimeChain.appendPast(r.moves)
        MTCoinBalance.set(sum)
        MTCoinVault.shared.soon("read", after: 1)
        MTCoinSend.returnUndeliverable(self)
    }

    /// THE MOVES OF THE SEED'S OTHER DEVICES (MTCoinVault): taken once by their names into this book and this phone's file, in one
    /// assignment -- a device restored by its words takes the whole book here; they are on the nodes already and ride no piece back.
    @discardableResult func join(_ moves: [MTCoinEntry]) -> Int {
        var all = entries, names = taken, sum = balance, c = counts, on = onTarget
        var fresh: [MTCoinEntry] = []
        for e in moves where 0 < e.c && !e.restoredName && !names.contains(e.id) {
            let (next, over) = sum.addingReportingOverflow(e.signed)
            guard !over else { continue }
            sum = next
            all.append(e); names.insert(e.id); c.add(e)
            if let t = e.shownOn { on[t, default: 0] += e.c }
            fresh.append(e)
        }
        guard !fresh.isEmpty else { return 0 }
        entries = all; taken = names; balance = sum; counts = c; onTarget = on
        ownPeers.formUnion(Self.own(fresh, names: names))
        MTCoinBalance.set(sum)
        reached(at: Date().timeIntervalSince1970)
        // A RESTORED DEVICE TAKES THE WHOLE BOOK IN ONE STROKE (15:51): nineteen thousand moves are encoded and written on the book's
        // queue, not on the screen's thread; their chains take them in one turn of their own queue.
        MTTimeChain.appendPast(fresh)
        if let file { let lines = fresh; disk.async { MTLocalCoinLedger.append(lines, to: file) } }
        MontanaP2PTrace.mark("coin_book", "joined moves=\(fresh.count) balance=\(sum)")
        MTCoinSend.returnUndeliverable(self)
        return fresh.count
    }

    /// THE BALANCE NEVER WRAPS (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin audit's ninth point): a
    /// coin letter of Int.max less the balance passed fits, and every later earning trapped on the sum -- the app died at any
    /// minting. Every move of the hand and the minting passes this one door; a move the integer cannot hold is refused here,
    /// before it is written.
    @discardableResult private func take(_ e: MTCoinEntry) -> Bool {
        guard !e.restoredName else {
            MontanaP2PTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) under a restored name")
            return false
        }
        let (next, over) = balance.addingReportingOverflow(e.signed)
        guard !over else {
            MontanaP2PTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) the balance cannot hold it")
            return false
        }
        entries.append(e)
        taken.insert(e.id)
        ownPeers.formUnion(Self.own([e], names: taken))
        balance = next
        counts.add(e)
        if let on = e.shownOn { onTarget[on, default: 0] += e.c }
        MTCoinBalance.set(balance)
        reached(at: e.at)
        return true
    }
    /// THE BOOK SAYS WHICH PAIRS HOLD THESE WORDS (the author's words 06.10.2026 11:1x-11:2x MSK, MTOwnWords): one move of coins seen
    /// from both its ends -- a coin letter sent and credited under its one name, a paid reaction given and credited under its one
    /// name -- lies in one book only when both ends hold the same words, for the book is the union of one seed's devices; the pair of
    /// such a move is the words' own. The book of the iPhone 17 says it of the iPad from the first coin letter between them, 08:13:24Z.
    nonisolated static func own(_ moves: [MTCoinEntry], names: Set<String>) -> Set<String> {
        var out = Set<String>()
        for e in moves {
            guard let peer = e.peer, !peer.isEmpty else { continue }
            let twin: String
            switch e.k {
            case .send: twin = "receive:" + e.ref
            case .receive: twin = e.ref.hasPrefix("rc:") ? "spend:" + String(e.ref.dropFirst(3)) : "send:" + e.ref   // COMPAT-LOCAL: the book's own names, never a word on the wire
            case .spend: twin = "receive:rc:" + e.ref   // COMPAT-LOCAL: the book's own names, never a word on the wire
            case .earn, .burn: continue
            }
            if names.contains(twin) { out.insert(peer) }
        }
        return out
    }
    /// A LEVEL OF π REACHED IS A LINK (the author's word 04.10 00:51: «every new level on top, as comments in the TimeChain,
    /// revealing π as your balance»): the first time the balance fills a level, the level joins its chain, at the move's moment.
    private func reached(at moment: Double) {
        let place = MTPiLevels.place(balance)
        if level < place {
            for n in (level + 1)...place { MTTimeChain.note("pi", kind: "level", coins: n, ref: "level:" + String(n), at: moment) }
            level = place
        }
    }

    /// THE MINTING WINDOW (the author's word 04.10.2026 12:52 MSK: «put time windows of 60 seconds at the minting's activation»): the
    /// coins of a game -- the Pantheon's taps, the pull's seconds -- gather in an open window of τ1 and join the book as ONE move when
    /// it closes: one line of the book, one link of its TimeChain, one line of the diary, never one per tap (T1 had tens of thousands
    /// of moves read and held at every launch). The balance and the game's count show every coin at once; the window's end, the app
    /// leaving the screen or a change of person closes it, so no coin waits longer than a minute and none is lost. Each game keeps
    /// its own window, so two games at once do not cut each other's.
    static let window: Double = 60
    private var windows: [String: (ref: String, coins: Int, at: Double)] = [:]
    @discardableResult func mintInWindow(_ coins: Int, prefix: String, seconds: Int, byLevel: Bool) -> Int {
        let (whole, over) = coins.multipliedReportingOverflow(by: byLevel ? MTPiLevels.multiplier(balance) : 1)
        guard !over, 0 < whole, MTCoinBook.fits(whole, beside: balance) else { return 0 }
        let c = priced(whole, seconds: seconds)
        guard 0 < c else { return 0 }
        let now = MTTimeChain.now()
        if windows[prefix] == nil {
            let ref = prefix + "w" + String(MTTimeChain.ms(now)) + "-" + UUID().uuidString
            windows[prefix] = (ref, 0, now)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.window) { [weak self] in
                guard let self, self.windows[prefix]?.ref == ref else { return }
                self.close(prefix)
            }
        }
        windows[prefix]?.coins += c
        balance += c
        counts.earn(c, ref: prefix)
        MTCoinBalance.set(balance)
        reached(at: now)
        MTCoinFlash.shared.born(c, ref: prefix)
        return c
    }
    private func close(_ prefix: String) {
        guard let w = windows.removeValue(forKey: prefix), 0 < w.coins else { return }
        let e = MTCoinEntry(k: .earn, c: w.coins, ref: w.ref, at: w.at)
        entries.append(e); taken.insert(e.id)
        keep([e])
        MontanaP2PTrace.markFolded("coin_window", "coins=\(w.coins) balance=\(balance)", window: 60)
    }
    /// THE LIMIT OF A SECOND (point 11, MTCoinBook.limit): all the minting of one second -- letters, taps, the pull, the VPN wall,
    /// chess -- shares that second's thirteen coins; a payment for seconds lived away carries thirteen for each of its seconds before
    /// this one, which it shares like any other. What the price leaves out is not minted.
    private var second: (at: Int64, minted: Int) = (0, 0)
    private func priced(_ coins: Int, seconds: Int) -> Int {
        let now = Int64(Date().timeIntervalSince1970)
        if second.at != now { second = (now, 0) }
        let (away, over) = MTPiLevels.ceiling.multipliedReportingOverflow(by: max(0, seconds - 1))
        let room = max(0, MTPiLevels.ceiling - second.minted)
        let c = over ? coins : min(coins, room + away)
        second.minted += min(room, max(0, c - (over ? c : away)))
        return c
    }

    /// Every open window into the book now (the app leaves the screen, a person leaves the seat).
    func closeWindows() { for prefix in Array(windows.keys) { close(prefix) } }
    /// THE PERSON LEAVING THE SEAT KEEPS EVERY COIN OF THEIR LAST MINUTE (the author's word «fix all points in order» 05.10.2026
    /// 21:4x MSK, the coin audit's fourth point): the windows close and the book and its chains are on disk in this turn, while the
    /// person's folder still stands -- the seat's park moves the folder, and the lines that waited for their second then found no
    /// folder, or the next person's (MTSeats.parkThenLift asks this before it parks).
    func writeWhole() { closeWindows(); writeNow() }

    /// THE BOOK IS WRITTEN ONCE A SECOND, NOT ONCE A COIN (the author's word 04.10.2026 12:27 MSK: «check why the phone heats while
    /// minting actively, and do it by constitution 0»; the iPhone 15 Pro Max on 04.10: twenty thousand coins in a day, every one a
    /// file opened, written and closed twice -- the book and its TimeChain -- and a line of the diary). The moves of a second ride one
    /// write, in the file of the person they belong to; the app leaving the screen and a change of person write what waits at once.
    private var pending = Data()
    private var pendingFile: URL?
    private var flushDue = false
    private func keep(_ fresh: [MTCoinEntry], now: Bool = false) {
        MTTimeChain.appendPast(fresh)   // every new move joins its source's TimeChain (04.10), all of them in one turn of its queue
        MTTimeChainTip.shared.add(fresh, book: balance)   // and this device's lane, whose tip rides one round trip (04.10 16:34)
        guard let file, !fresh.isEmpty else { return }
        MTCoinVault.shared.soon(now ? "move" : "moves", after: now ? 1 : 60)   // a move between people reaches the seed's devices at once
        if let was = pendingFile, was != file { flush() }
        pendingFile = file
        for e in fresh {
            guard let d = try? JSONEncoder().encode(e) else { continue }
            pending.append(d); pending.append(0x0A)
        }
        if now { writeNow(); return }
        guard !flushDue else { return }
        flushDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.flush() }
    }
    /// A MOVE BETWEEN PEOPLE IS ON DISK BEFORE ANYONE HEARS OF IT (the author's word 04.10.2026 23:57 MSK: «sent 123 thousand coins
    /// from T3, they did not appear for her, and T3 was debited -- a gross breach of the constitution; close it by construction»).
    /// The iPhone 15 Pro Max credited them at 20:54:30Z in a background wake, and the process ended inside the second the book waits
    /// before it writes; the next launch read the book without them (209 216, then 86 216). A coin sent, received or given is
    /// written in the same turn, with every line that waited before it; the minting's lines keep their second.
    private func writeNow() {
        flushDue = false
        guard let file = pendingFile, !pending.isEmpty else { return }
        let data = pending
        pending = Data()
        // MAIN-SAFE-SYNC: the book's queue holds only appends of a second's lines; a coin between people waits for its own line.
        disk.sync { MTLocalCoinLedger.write(data, to: file) }
        MTTimeChain.flush()
    }
    func flush() {
        flushDue = false
        guard let file = pendingFile, !pending.isEmpty else { return }
        let data = pending
        pending = Data()
        disk.async { MTLocalCoinLedger.write(data, to: file) }
    }
    nonisolated private static func append(_ moves: [MTCoinEntry], to file: URL) {
        let encoder = JSONEncoder()
        var data = Data()
        for e in moves { if let d = try? encoder.encode(e) { data.append(d); data.append(0x0A) } }
        write(data, to: file)
    }
    /// The book's queue alone: lines appended to the book's file.
    nonisolated private static func write(_ data: Data, to file: URL) {
        guard !data.isEmpty else { return }
        if let h = try? FileHandle(forUpdating: file) {
            // A line cut short by an ended process is ended here first, so the next move stands on a line of its own and is never
            // swallowed by the broken one (the coin audit's tenth point).
            if let end = try? h.seekToEnd(), 0 < end {
                try? h.seek(toOffset: end - 1)
                let last = try? h.read(upToCount: 1)
                _ = try? h.seekToEnd()
                if last != Data([0x0A]) { try? h.write(contentsOf: Data([0x0A])) }
            }
            try? h.write(contentsOf: data)
            try? h.close()
        } else if !FileManager.default.fileExists(atPath: file.path) {
            // Born only where none stands: a book that stands but would not open is never written over.
            try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    @discardableResult func earn(_ names: [String], times: Int, peer: String?) -> Int {
        let now = MTTimeChain.now()
        var fresh: [MTCoinEntry] = []
        for n in names where !taken.contains("earn:" + n) {
            let born = ChatStore.birthMs(fromMid: n) ?? now
            // The box is read at every name: a name that opens a box mints the next one at the new rate; more than one level a
            // name stands above the limit of a second and takes none of the second's room.
            let level = MTPiLevels.multiplier(balance)
            let c = 1 < times ? level * times : priced(level, seconds: 1)
            guard 0 < c else { continue }
            let e = MTCoinEntry(k: .earn, c: c, ref: n, peer: peer, at: born)
            guard take(e) else { continue }
            fresh.append(e)
        }
        keep(fresh)
        for e in fresh { MTCoinFlash.shared.born(e.c, ref: e.ref) }
        let coins = fresh.reduce(0) { sum, e in sum + e.c }
        if !fresh.isEmpty { MontanaP2PTrace.markFolded("coin_earn", "names=\(fresh.count) coins=\(coins) balance=\(balance)", window: 60) }
        return coins
    }

    @discardableResult func mint(_ coins: Int, ref: String, peer: String?) -> Int {
        guard MTCoinBook.fits(coins, beside: balance), !ref.isEmpty, !taken.contains("earn:" + ref) else { return 0 }
        let e = MTCoinEntry(k: .earn, c: coins, ref: ref, peer: peer, at: MTTimeChain.now())
        guard take(e) else { return 0 }
        keep([e])
        MTCoinFlash.shared.born(coins, ref: ref)
        MontanaP2PTrace.markFolded("coin_earn", "named coins=\(coins) balance=\(balance)", window: 60)
        return coins
    }

    @discardableResult func burn(_ coins: Int, ref: String) -> Int {
        let c = min(coins, balance)
        guard 0 < c, !ref.isEmpty, !taken.contains("burn:" + ref) else { return 0 }
        let e = MTCoinEntry(k: .burn, c: c, ref: ref, at: MTTimeChain.now())
        guard take(e) else { return 0 }
        keep([e])
        MontanaP2PTrace.markFolded("coin_burn", "coins=\(c) balance=\(balance)", window: 60)
        return c
    }

    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool {
        move(.spend, coins, peer: peer, ref: ref, on: target)
    }

    func send(_ coins: Int, to peer: String, ref: String) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: nil)
    }

    /// A COIN LETTER PROVEN DELIVERED TAKES ITS COINS AGAIN, WHATEVER THE BALANCE (the author's words 06.10.2026 12:3x-12:4x MSK: «close the double spends»; «the safety of the restore by the seed»): its
    /// coins came back while it was red (MTCoinSend.hold), the receiver credited it all the same, and its late receipt asks them
    /// again. A refusal on a short balance left them in two books for ever -- the sender had spent them meanwhile. This move stands
    /// whatever the balance: a book may stand below nothing, the truth of a debt, the sum of every book keeps the coins there were,
    /// and no move of the hand leaves a book below what it holds (move).
    func retake(_ coins: Int, to peer: String, ref: String) -> Bool {
        let e = MTCoinEntry(k: .send, c: coins, ref: ref, peer: peer, on: nil, at: MTTimeChain.now())
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), take(e) else { return false }
        keep([e], now: true)
        MontanaP2PTrace.mark("coin_retake", "coins=\(coins) balance=\(balance)")
        return true
    }

    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool {
        guard MTCoinBook.fits(coins, beside: balance), !ref.isEmpty, !taken.contains("receive:" + ref) else {
            MontanaP2PTrace.mark("coin_rx", "skipped coins=\(coins) known=\(taken.contains("receive:" + ref) ? 1 : 0)")
            return false
        }
        let e = MTCoinEntry(k: .receive, c: coins, ref: ref, peer: peer, on: target, at: Self.moment(ref))
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaP2PTrace.mark("coin_rx", "coins=\(coins) on=\(target == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    private func move(_ k: MTCoinEntry.Kind, _ coins: Int, peer: String, ref: String, on: String?) -> Bool {
        let e = MTCoinEntry(k: k, c: coins, ref: ref, peer: peer, on: on, at: Self.moment(ref))
        // THE REFUSAL IS THE BOOK'S (the author's word 03.10 13:40): no move leaves more coins than the balance holds.
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), coins <= balance else {
            MontanaP2PTrace.mark("coin_refused", "\(k.rawValue) coins=\(coins) balance=\(balance)")
            return false
        }
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaP2PTrace.mark("coin_\(k.rawValue)", "coins=\(coins) on=\(on == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    /// A COIN LETTER STANDS AT ITS OWN BIRTH IN EVERY BOOK (the author's word 06.10.2026 11:2x MSK: «the sender and the receivers above
    /// all»): its name carries the millisecond the sender's phone gave it (ChatStore.mintMid), so the sender's transfer and the
    /// receiver's credit stand at that one millisecond -- as a letter's coin does (earn) -- not at two clocks' readings of two moments.
    /// Every other move stands at the millisecond it is made.
    private static func moment(_ ref: String) -> Double {
        (ref.hasPrefix("mid:t") ? ChatStore.birthMs(fromMid: ref) : nil) ?? MTTimeChain.now()
    }

    func coins(on target: String) -> Int { onTarget[target] ?? 0 }
    /// Whether the book holds a coin letter's credit by the letter's wire name (MTCoinSend.settle).
    func received(_ ref: String) -> Bool { taken.contains("receive:" + ref) }
    /// Whether the book holds a move of this kind under this name (MTCoinSend.hold counts a coin letter's moves by them).
    func holds(_ k: MTCoinEntry.Kind, _ ref: String) -> Bool { taken.contains(k.rawValue + ":" + ref) }
    /// One move by its kind and name (a coin letter's transfer, read when its row is gone: MTCoinSend.arrived, returnUndeliverable).
    func entry(_ k: MTCoinEntry.Kind, _ ref: String) -> MTCoinEntry? {
        let id = k.rawValue + ":" + ref
        return entries.last { e in e.id == id }
    }
}

/// A COIN LETTER (the author's word 03.10 13:52: «send coins to a contact in the chat as a coin-transfer bubble»): coins
/// sent to a person ride the chat's own letter road, as the chess letters do -- the coin and the number on the first line,
/// the machine line under it. A build that does not know it reads the words; this one draws the coin's bubble, and the
/// receiver's book credits it once by the letter's wire name (the same on both phones).
struct MTCoinLetter: Codable, Hashable {
    static let link = "montana://coin/1/"   // NOT-UI: the letter's machine line
    /// The text the transfer's one door is sending now (MTCoinSend.transfer): ChatStore.send lets no other coin letter leave.
    static var born: String?
    var c: Int
    var id: String
    /// THE LETTER NAMES ITSELF (the author's words 06.10.2026 12:3x-12:4x MSK: «close the double spends»; «the safety of the restore by the seed»): its id is the UUID of its own
    /// wire name, so a copy carried under another name -- pasted from a bubble, shared in, typed -- names a letter that is not
    /// itself (MTCoinSend.credits).
    func bound(to mid: String) -> Bool {
        let core = mid.hasPrefix("mid:") ? mid.dropFirst(4) : Substring(mid)
        guard let dash = core.firstIndex(of: "-") else { return false }
        return core[core.index(after: dash)...].caseInsensitiveCompare(id) == .orderedSame
    }
    func text() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        let code = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "🪙 " + String(c) + "\n" + Self.link + code   // NOT-UI: the coin glyph and a number, the same in every language
    }
    static func parse(_ text: String) -> MTCoinLetter? {
        guard text.hasPrefix("🪙 "), text.utf8.count <= 512,
              let line = text.split(separator: "\n", omittingEmptySubsequences: false).last, line.hasPrefix(link) else { return nil }
        let code = line.dropFirst(link.count).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: code), let letter = try? JSONDecoder().decode(Self.self, from: data),
              0 < letter.c, UUID(uuidString: letter.id) != nil else { return nil }
        return letter
    }
}

extension Message {
    /// The coin letter this row is, when it is one in its own right (a forward or a reply quoting one pays nothing).
    var coinLetter: MTCoinLetter? {
        // An edited row is never a coin letter: its coins were taken once, under the words it was born with (06.10).
        guard !isForwarded, !edited, replyText == nil, imageFile == nil, videoFile == nil, audioFile == nil, docFile == nil else { return nil }
        return MTCoinLetter.parse(text)
    }
}

/// A PAIR WHOSE OTHER END HOLDS MY WORDS PAYS NOTHING (the author's words 06.10.2026 11:1x-11:2x MSK: «from the tablet I sent more than
/// 700 thousand to the iPhone 17, and in the end they were debited from her, not credited»; «check that the TimeChain does not allow
/// this»). The iPad (iPad12,1) and the iPhone 17 hold the same 24 words -- one book -- and the three coin letters between them took the
/// coins out of that book and laid them back: the receiver took the sender's debit by the seed's lane before the letter's credit
/// (762 000 at 08:14:21Z, the balance 134 until the letter landed at 08:19:13Z), and the sender took the receiver's credit by the vault
/// and sent again. A coin moved to one's own words is no move; it is refused at its birth -- the transfer, the paid reaction, the
/// bubble's coin, the call's seconds (MTCoinSend.canPay). Two witnesses say a pair is mine: the book (MTLocalCoinLedger.own) and the
/// pair's word about itself, carrying a tag only the same words make (MTCoinVault.ownTag). A coin letter of an older build still
/// lands and is credited: the book holds both ends to stand whole.
enum MTOwnWords {
    private static func key(_ conv: String) -> String { "ownWords." + conv }   // NOT-UI: the mark's key
    /// The tag my word about myself carries to this pair; nil while no words stand on the phone.
    static func tag(for conv: String) -> String? {
        guard !conv.isEmpty, let m = MontanaSeed.mnemonic, let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return nil }
        return MTCoinVault.ownTag(entropy: e, conv: conv).base64EncodedString()
    }
    /// The pair's word told its tag: the pair is mine when my words make the same one; a tag of other words lets the mark go.
    static func heard(_ tag: String, from conv: String) {
        guard !conv.isEmpty, let t = Data(base64Encoded: tag), t.count == 32, let m = MontanaSeed.mnemonic,
              let e = MontanaSeedKeys.entropyFrom(mnemonic: m), e.count == 32 else { return }
        let mine = MTCoinVault.ownTagHolds(t, entropy: e, conv: conv)
        guard UserDefaults.standard.bool(forKey: key(conv)) != mine else { return }
        if mine { UserDefaults.standard.set(true, forKey: key(conv)) } else { UserDefaults.standard.removeObject(forKey: key(conv)) }
        MontanaP2PTrace.mark("own_words", "pair=\(String(conv.prefix(10))) mine=\(mine ? 1 : 0) by=word")
    }
    /// Whether the other end of this pair holds my words: by the book or by the pair's word.
    @MainActor static func mine(_ conv: String) -> Bool {
        !conv.isEmpty && (UserDefaults.standard.bool(forKey: key(conv)) || MTLocalCoinLedger.shared.whole.ownPeers.contains(conv))
    }
}

/// THE COINS LEAVE BY THE CHAT'S OWN ROADS (the author's words 03.10 13:40 and 13:52): a transfer is a letter of the pair,
/// a paid reaction is a reaction word that carries its coins. Both ask the book first: a short balance refuses here and
/// nothing leaves.
enum MTCoinSend {
    /// The system chain's name for a restored credit: this prefix and the coin letter's wire name.
    static let restorePrefix = "restore:"
    /// A pair's own conversation, open to letters: where coins can go.
    @MainActor static func canPay(_ chat: Chat, store: ChatStore) -> Bool {
        let conv = chat.convId ?? chat.name
        return !chat.isGroup && !ChatStore.isLocalRoom(chat.name) && chat.convId != nil && MontanaConv.holds(conv)
            && !store.refuses(conv) && !store.closedChats.contains(conv) && !MTOwnWords.mine(conv)
    }
    /// Coins to a person, as a coin letter in their chat. False -- refused (the balance, the chat), nothing sent.
    @MainActor static func transfer(_ coins: Int, to chat: Chat, store: ChatStore) -> Bool {
        let conv = chat.convId ?? chat.name
        let minted = ChatStore.mintMid()   // the letter's wire name first: the letter names itself by it (MTCoinLetter.bound)
        let named = String(minted.mid.drop { ch in ch != "-" }.dropFirst())
        guard canPay(chat, store: store), 0 < coins, coins <= MTCoinBook.ledger.balance,
              let text = MTCoinLetter(c: coins, id: named).text() else {
            MontanaP2PTrace.mark("coin_refused", "transfer coins=\(coins) balance=\(MTCoinBook.ledger.balance) own=\(MTOwnWords.mine(conv) ? 1 : 0)")
            return false
        }
        MTCoinLetter.born = text
        let m = store.send(text: text, chat: chat.name, convRef: conv, silent: false, noLinkCard: true, minted: minted)
        MTCoinLetter.born = nil
        guard !m.text.isEmpty, !m.mid.isEmpty else { return false }
        return MTCoinBook.ledger.send(coins, to: conv, ref: m.mid)
    }
    /// Coins given on the correspondent's letter: the book pays, the reaction word carries them («op»: «coin»). An older build
    /// reads an unknown op as nothing at all.
    @MainActor static func react(_ coins: Int, on m: Message, in chat: Chat, store: ChatStore) -> Bool {
        guard !m.isMine, let sid = m.msgId, !sid.isEmpty, canPay(chat, store: store) else { return false }
        return give(coins, on: sid, words: m.text, to: chat.convId ?? chat.name, ref: UUID().uuidString)
    }
    /// An auto-reaction's coins on a chosen person's letter (MTAutoReact): the paid reaction's own road, under the name «auto:» and
    /// the letter's wire name, so a letter brought twice pays once.
    static let autoPrefix = "auto:"   // NOT-UI: the book's own name
    @MainActor static func autoGive(_ coins: Int, on m: Message, to conv: String) -> Bool {
        guard let sid = m.msgId, !sid.isEmpty else { return false }
        return give(coins, on: sid, words: m.text, to: conv, ref: autoPrefix + sid)
    }
    /// The one road of a paid reaction: the book pays on the letter's name, the reaction word carries the coins.
    @MainActor private static func give(_ coins: Int, on sid: String, words: String, to conv: String, ref: String) -> Bool {
        guard MTCoinBook.ledger.spend(coins, on: sid, peer: conv, ref: ref) else { return false }
        let obj: [String: Any] = ["sid": sid, "txt": words, "e": "🪙", "op": "coin", "c": coins, "r": ref]   // NOT-UI: wire keys
        guard let json = try? JSONSerialization.data(withJSONObject: obj), let body = String(data: json, encoding: .utf8) else { return true }
        MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: reactionMark + body, silent: true)
        return true
    }
    /// THE BUBBLE BURNS ITS COIN (the author's words 05.10.2026 01:21-01:31 MSK: «every bubble -1 coin»; «any bubble in an ordinary
    /// chat with the feed at the bottom»; and 22:29-22:32 MSK: «in ordinary chats take away the coin under every message as a
    /// reaction; the burning in an ordinary chat at both players -- a simple burning without a transfer»; «1 coin»): a bubble of
    /// mine in a pair's ordinary chat -- the Money Flow off; there the letters mint -- burns one coin of my book by the bubble's
    /// name, and nothing goes to the correspondent: no reaction word, no coin under the bubble; their phone burns its own for their
    /// bubbles. It burns when the bubble takes its wire name -- at its landing in the feed, or a media bubble when it is named
    /// (setMediaMid) -- and once, by that name, whichever door hands it over twice; a bubble a build before paid to its reader
    /// burns nothing more. An empty balance burns nothing and the bubble goes all the same; a coin letter is a payment in its own
    /// right, a chess step is the board's, a row of the phone's own goes nowhere.
    static let bubblePrefix = "bubble:"
    /// The name a reaction word's coins are credited under on the reader's book: this prefix and the name the word carries.
    static let receivedPrefix = "rc:"   // NOT-UI: the book's own name
    /// A bubble burns while it is on its way and born within a day: a history laid in again never burns twice.
    static let fresh: Double = 86_400
    @MainActor static func pay(_ m: Message, in key: String, store: ChatStore) {
        guard m.isFromMe, m.deliveryStatus == .sending || m.deliveryStatus == .sent, let sid = m.msgId, MTChatMint.wireName(sid),
              !MTMoneyFlow.isOn(key), m.coinLetter == nil, m.chessLetter == nil, !m.text.hasPrefix("\u{200B}\u{200B}"),
              let born = ChatStore.birthMs(fromMid: sid), Date().timeIntervalSince1970 - born <= fresh,
              let chat = store.listChats().first(where: { c in c.name == key }), canPay(chat, store: store),
              !MTLocalCoinLedger.shared.whole.holds(.spend, bubblePrefix + sid),
              0 < MTCoinBook.ledger.burn(1, ref: bubblePrefix + sid) else { return }
        MTCoinPaid.shared.paid(1, in: key)
    }
    /// A COIN LETTER THAT DID NOT GO GIVES ITS COINS BACK (the author's word 05.10.2026 01:40 MSK: «I sent Narine 60 000 coins from
    /// T1, the letter did not go and they were taken from me; while the retry mark hangs, return them to the sender's balance with
    /// the mark not delivered»): a coin letter of mine holds its coins exactly while it is not red. Red, they come back by one move
    /// (back) and the bubble says so; on its way again under the hand's retry, or proven delivered after all -- the carriage goes on
    /// behind the red and a late receipt turns it delivered -- they are taken again by one move (again). The book's own moves say
    /// which it holds: the transfer, the agains and the backs, each by its name, so a door that asks twice moves nothing twice.
    /// Every door of the ladder asks it after it moves a coin letter of mine (advance, restartSend), and the history's first
    /// reading asks it of every one (settle) -- a letter red before this build gives its coins back at the first launch.
    static let backPrefix = "back:"
    static let againPrefix = "again:"
    /// A COIN LETTER NOT DELIVERED IN A DAY GIVES ITS COINS BACK (the author's words 10.10.2026 23:3x MSK: «a rule common to every
    /// wallet: if it did not arrive in 24 hours -- it comes back»): T2's 727 639 coins to an account whose phone is gone rode 44 hours
    /// without a receipt and stayed taken, for a letter of mine rides to its receipt (MTRefusal) and only red gave coins back. The
    /// coins follow the letter's proof as well as its rung: delivered or read, they are the receiver's; on its way and born within
    /// the day, held; red, or on its way past the day, back. The letter rides on under its rung, and a receipt after the day takes
    /// them again by the same again move -- a coin never stands in two books.
    static let day: Double = 86_400
    @MainActor static func hold(_ m: Message, in key: String) {
        guard m.isFromMe, let coin = m.coinLetter, !m.mid.isEmpty else { return }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return }   // a transfer the book refused never took a coin
        let again = moves(book, .send, againPrefix + m.mid), back = moves(book, .receive, backPrefix + m.mid)
        let held = again == back, owed = owes(m)
        if held, !owed {
            giveBack(coin.c, letter: m.mid, count: back, to: key, why: m.deliveryStatus == .failed ? "red" : "day")
        } else if !held, owed {
            let took = book.retake(coin.c, to: key, ref: againPrefix + m.mid + ":" + String(again + 1))
            MontanaP2PTrace.mark("coin_again", "coins=\(coin.c) took=\(took ? 1 : 0) status=\(m.deliveryStatus)")
        }
    }
    /// Whether a coin letter of mine holds its coins: proven delivered, or on its way and born within the day.
    @MainActor private static func owes(_ m: Message) -> Bool {
        switch m.deliveryStatus {
        case .delivered, .read: return true
        case .failed: return false
        case .sending, .sent:
            guard let born = ChatStore.birthMs(fromMid: m.mid) else { return true }   // a name without its birth: held as before
            return Date().timeIntervalSince1970 - born < day
        }
    }
    /// The day ends while no rung moves: every beat of the queue's mirror (MontanaDeliveryEngine.reconcile) asks the coin letters
    /// of mine still on their way past their day.
    @MainActor static func due(_ store: ChatStore) {
        let edge = Date().timeIntervalSince1970 - day
        for (chat, rows) in store.messages {
            for m in rows where m.isFromMe && (m.deliveryStatus == .sending || m.deliveryStatus == .sent) {
                guard let born = ChatStore.birthMs(fromMid: m.mid), born < edge, m.coinLetter != nil else { continue }
                hold(m, in: chat)
            }
        }
    }
    /// THE LETTERS THE AUTHOR NAMED UNDELIVERABLE (the author's words 10.10.2026 23:2x-23:3x MSK: «there was a transfer from T2 to a
    /// dead account on Android, the coins were not received, they got stuck somewhere -- find them and return them to the sender»;
    /// «and return them to the sender now»): T2's coin letter of 08.10 18:18:19Z rode 44 hours without a receipt, no device of the
    /// account waking (woken=0), and the Montana build that took the coins out of the chats ended its row and its queue item
    /// (queue_mirror 10.10 14:05:46Z) -- no chat of any wallet holds it, and the day above cannot reach it. Its name stands here;
    /// the book that holds its transfer -- T2's words, in whichever wallet they open -- gives the coins back once, by the back move.
    static let undeliverable = ["mid:t1791483499406-5CA782B0-A754-4443-B673-0579412060C2"]   // NOT-UI: a letter's wire name
    @MainActor static func returnUndeliverable(_ book: MTLocalCoinLedger) {
        for name in undeliverable {
            guard let sent = book.entry(.send, name), let peer = sent.peer else { continue }
            let back = moves(book, .receive, backPrefix + name)
            guard moves(book, .send, againPrefix + name) == back else { continue }
            giveBack(sent.c, letter: name, count: back, to: peer, why: "named")
        }
    }
    /// How many moves of one kind a coin letter's name has drawn: name:1, name:2 ...
    @MainActor private static func moves(_ book: MTLocalCoinLedger, _ k: MTCoinEntry.Kind, _ name: String) -> Int {
        var n = 0
        while book.holds(k, name + ":" + String(n + 1)) { n += 1 }
        return n
    }
    /// The one back move of a coin letter: its coins come home under the letter's next back name, and the system chain says why.
    @MainActor private static func giveBack(_ c: Int, letter mid: String, count back: Int, to key: String, why: String) {
        let ref = backPrefix + mid + ":" + String(back + 1)
        guard MTLocalCoinLedger.shared.whole.receive(c, from: key, ref: ref, on: nil) else { return }
        MTTimeChain.note("system", kind: "back", coins: c, ref: ref)
        MontanaP2PTrace.mark("coin_back", "coins=\(c) letter=\(why)")
    }
    /// A COIN LETTER OF MINE ON ITS WAY IS NOT DELETED (the author's word «fix all points in order» 05.10.2026 21:4x MSK, the coin
    /// audit's first point): a row deleted by the hand while it said «sending» or «sent» took its letter out of the queue and the
    /// node box (the queue's mirror law, cargoGone, clearChat) and left its coins taken -- the receiver never had them and the
    /// sender never got them back. Giving them back at the deletion would pay twice whenever the receiver had already opened the
    /// letter and its receipt was still on the road; so the letter keeps its row until its road ends: delivered (the coins are the
    /// receiver's) or red (they come back by hold). Every door of the hand asks this first (ChatStore.deleteLocally,
    /// deleteEverywhere, deleteChat) and the menu offers no deletion of it.
    @MainActor static func travels(_ m: Message) -> Bool {
        guard m.isFromMe, m.deliveryStatus == .sending || m.deliveryStatus == .sent, !m.mid.isEmpty, m.coinLetter != nil else { return false }
        let book = MTLocalCoinLedger.shared.whole
        return book.holds(.send, m.mid) && moves(book, .send, againPrefix + m.mid) == moves(book, .receive, backPrefix + m.mid)
    }
    /// The row leaves by a road the hand does not hold -- the correspondent erased the conversation for both, and its queue and
    /// node box go with it (clearChat): a coin letter of mine not proven delivered and still holding its coins gives them back by
    /// the back move before the row goes.
    @MainActor static func release(_ m: Message, in key: String) {
        guard m.isFromMe, m.deliveryStatus != .delivered, m.deliveryStatus != .read, !m.mid.isEmpty, let coin = m.coinLetter else { return }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return }
        let back = moves(book, .receive, backPrefix + m.mid)
        guard moves(book, .send, againPrefix + m.mid) == back else { return }
        giveBack(coin.c, letter: m.mid, count: back, to: key, why: "gone")
    }
    /// A receipt for a coin letter of mine whose row is gone (released above, or red and then deleted): the letter did arrive, so
    /// the coins that came back are taken again by one move -- the same again a living row takes (hold) -- by the amount the
    /// book's own transfer named.
    @MainActor static func arrived(_ mid: String, from key: String) {
        let name = mid.hasPrefix("mid:") ? mid : "mid:" + mid
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, name), let c = book.entry(.send, name)?.c else { return }
        let again = moves(book, .send, againPrefix + name), back = moves(book, .receive, backPrefix + name)
        guard again < back else { return }
        let took = book.retake(c, to: key, ref: againPrefix + name + ":" + String(again + 1))
        MontanaP2PTrace.mark("coin_again", "coins=\(c) took=\(took ? 1 : 0) row=gone")
    }
    /// The hand's retry of a coin letter whose coins came back takes them again first: a short balance refuses the retry.
    @MainActor static func mayRetry(_ m: Message) -> Bool {
        guard m.isFromMe, let coin = m.coinLetter else { return true }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return true }
        return moves(book, .send, againPrefix + m.mid) == moves(book, .receive, backPrefix + m.mid) || coin.c <= book.balance
    }
    /// A COIN LETTER IS CREDITED WHEN IT NAMES ITSELF (the author's words 06.10.2026 12:3x-12:4x MSK: «close the double spends»; «the safety of the restore by the seed»): the
    /// first letter of a pair that names itself (MTCoinLetter.bound) notes its birth; from then on a letter of that pair born later
    /// under another name is a copy -- pasted, shared in, typed -- and credits nothing. A letter born before it, of a build that named
    /// none of its letters, stands as such letters always did.
    @MainActor static func credits(_ coin: MTCoinLetter, mid: String, from chat: String) -> Bool {
        let born = ChatStore.birthMs(fromMid: mid) ?? Date().timeIntervalSince1970
        let since = UserDefaults.standard.double(forKey: "coinBinds." + chat)   // 0: the pair never named a letter
        if coin.bound(to: mid) {
            if since == 0 || born < since { UserDefaults.standard.set(born, forKey: "coinBinds." + chat) }
            return true
        }
        guard since == 0 || born < since else {
            MontanaP2PTrace.mark("coin_refused", "a copy under another name from=\(String(chat.prefix(10)))")
            return false
        }
        return true
    }
    /// A reaction word that carried coins arrived: credited once by the name it carries.
    @MainActor static func reacted(_ c: Int, ref: String, on sid: String, from chat: String) {
        guard 0 < c, !ref.isEmpty, !sid.isEmpty else { return }
        MTCoinBook.ledger.receive(c, from: chat, ref: receivedPrefix + ref, on: sid)
    }
    /// THE BOOK HOLDS EVERY COIN LETTER THE CHATS HOLD (the author's word 04.10.2026 23:57 MSK: «close it by construction»): once the
    /// history stands, a correspondent's coin letter the book never credited is credited now by its wire name -- the 123 000 coins
    /// the iPhone 15 Pro Max lost with an ended process come back at its next launch; a letter credited before is passed by its name.
    @MainActor static func settle(_ store: ChatStore) {
        let book = MTLocalCoinLedger.shared.whole
        var letters = 0, coins = 0
        for (chat, rows) in store.messages {
            for m in rows where !m.isFromMe {
                // ONE LETTER, ONE NAME, ONE CREDIT (09.10, MTCoinEntry.restoredName): a letter is credited under its wire name alone.
                // A copy a correspondent gave back carries that name inside its own (MTRestoredMid.given), so it is credited under it
                // -- the letter and its copy credit once, and a letter the vault had not heard of before the phone was lost comes
                // back; an archive's copy names no wire name and credits nothing -- its coins moved under the wire name.
                let wire = m.mid.hasPrefix(MTRestoredMid.given) ? String(m.mid.dropFirst(MTRestoredMid.given.count)) : m.mid
                guard MTChatMint.wireName(wire), !book.received(wire) else { continue }
                guard let coin = m.coinLetter, !MTGroup.isKey(chat), credits(coin, mid: wire, from: chat),
                      book.receive(coin.c, from: chat, ref: wire, on: nil) else { continue }
                // THE SYSTEM'S OWN BRANCH OF THE TIMECHAIN (the author's word 05.10.2026 00:22 MSK: «repair it by a system branch in the
                // TimeChain, as the diary»): the credit stands in the received chain as any other, and the system chain says why --
                // a coin letter the book had lost, restored by its wire name, its coins and its moment.
                MTTimeChain.note("system", kind: "restore", coins: coin.c, ref: MTCoinSend.restorePrefix + wire)
                letters += 1; coins += coin.c
            }
        }
        // A COIN LETTER OF MINE HOLDS ITS COINS WHILE IT IS NOT RED (hold), asked of every one as the history stands.
        for (chat, rows) in store.messages { for m in rows where m.isFromMe && m.coinLetter != nil { hold(m, in: chat) } }
        if 0 < letters { MTTimeChain.flush() }
        MontanaP2PTrace.mark("coin_settle", "letters=\(letters) coins=\(coins) balance=\(book.balance)")
    }
}

/// AUTO-REACTIONS OF CHOSEN PEOPLE (the author's word 06.10.2026 17:3x MSK: «in the Money Flow's settings, on a long press, open a
/// page where I choose whom and how much I want to auto-react to, from my contacts»): a person chosen with a number of coins is paid
/// that many on every letter of theirs born after the choice, within a day of its birth, by the paid reaction's own road
/// (MTCoinSend.autoGive) -- once a letter, whichever door brings it. A short balance pays nothing and the letter stands as any other.
enum MTAutoReact {
    static let prefix = "autoReact."   // NOT-UI: a conversation's own rule (SeedScope.dataPrefixes)
    struct Rule { let coins: Int; let since: Double }
    static func rule(_ conv: String) -> Rule? {
        guard let d = UserDefaults.standard.dictionary(forKey: prefix + conv), let c = d["c"] as? Int, 0 < c,   // NOT-UI: the rule's keys
              let s = d["s"] as? Double else { return nil }   // NOT-UI: the rule's keys
        return Rule(coins: c, since: s)
    }
    /// The coins a person's every new letter is paid; nought lets the person go. The moment of the first choice stays while the
    /// number changes, so a letter between two edits is paid by the rule that stood.
    static func set(_ conv: String, coins: Int) {
        guard 0 < coins else { UserDefaults.standard.removeObject(forKey: prefix + conv); return }
        let since = rule(conv)?.since ?? Date().timeIntervalSince1970
        UserDefaults.standard.set(["c": coins, "s": since], forKey: prefix + conv)   // NOT-UI: the rule's keys
    }
    /// A letter of the pair landed (ChatStore, beside a coin letter's credit): a chosen person's fresh letter is paid.
    @MainActor static func landed(_ m: Message, in chat: String, store: ChatStore) {
        guard !m.isFromMe, let r = rule(chat), m.coinLetter == nil, m.chessLetter == nil, !MTRowLetter.ownRow(m.text),
              let born = ChatStore.birthMs(fromMid: m.mid), r.since <= born, Date().timeIntervalSince1970 - born <= MTCoinSend.fresh,
              let c = store.listChats().first(where: { c in c.name == chat }), MTCoinSend.canPay(c, store: store) else { return }
        let paid = MTCoinSend.autoGive(r.coins, on: m, to: c.convId ?? c.name)
        if paid { MTCoinPaid.shared.paid(r.coins, in: chat) }
        MontanaP2PTrace.mark("auto_react", "coins=\(r.coins) paid=\(paid ? 1 : 0)")
    }
}

/// THE COINS I PAID, SEEN IN THE CHAT (the author's word 05.10.2026 01:24 MSK: «in the chat the same way, an animation of a red
/// minus coin»): the one owner of the payment's sign -- what the book just burned from me for a bubble or paid for a call, and in which chat;
/// that chat shows it (MTPayPop).
@MainActor final class MTCoinPaid: ObservableObject {
    static let shared = MTCoinPaid()
    @Published private(set) var tick = 0
    private(set) var coins = 0
    private(set) var chat = ""
    func paid(_ c: Int, in key: String) {
        coins = c
        chat = key
        tick += 1
        MontanaP2PTrace.markFolded("coin_paid", "coins=\(c)", window: 60)
    }
}
