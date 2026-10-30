import Foundation
import CryptoKit
import UIKit
import MontanaBindings

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

/// EVERY SERVER AND PHONE OF OURS IS A NODE (the author's word 06.10.2026 14:2x UTC: «every server and phone of ours is a node»):
/// this phone opens its own machine of the core -- born once, its secret drawn here and never carried to a second phone -- and
/// reaches the machines of the Global TimeChain's genesis, every server of ours, by the post-quantum handshake of the set. It
/// answers on this phone alone and lives no window: the genesis cohort is the servers, which never sleep, and a machine joining
/// a chain already running is the core's stage fourteen. The person is not opened in the core here: the core keeps a person's
/// entropy in a file, and this phone keeps the words in the keychain alone -- a second home for them waits for the notes that
/// would need it.
@MainActor final class MTNetworkNode: ObservableObject {
    static let shared = MTNetworkNode()
    /// The machines of the genesis (06.10.2026 14:28 UTC) -- Lauterbourg, Moscow, Amsterdam -- each as its operator handed it
    /// over: the endpoint and the key it answers with. The old Frankfurt left on 23.10.2026: that address is a colleague's
    /// server now, and a phone that dialed it would hand a stranger its address; the new Frankfurt joins with the core's stage
    /// fourteen.
    nonisolated static let genesis: [String] = [   // NOT-UI: the acquaintance lines of the genesis machines
        "192.0.2.1:9635@b98a45063346fd71cb8240ff878099e4491682e579e632a84f2bbe08aed1e6f4cb6859e87864edca73c9d47807203d9f72b93b76ebd1c8c93663178f1aef3ee21cd8da1168b5b14b596ca670479266745e5f4f612943a4d7045c286d3d6c58443f2fc1509b90cfc344044f1a81a9b9eecc2b36a7fddac92ec497a9b87caec7850f74ed0759d9f276d6f141df12b2e09a46e77eae691f419bb4622d285d64f6f0835a733bfdeb14c25938963c1e1fe1f76d86c6d887ec82960e06df7167f3ce0fc0e13f9c83bbea75b727b140cc33f1e829027402fce0383adda029f17a1403e6fd4630039090231660e2864d7fbce9de3601f249b039e8e846e47c538e5a8a77bd6a882c1481bd0042aa67b74e32df9407f6381718fcbe30e49b462c07a7d94507c3f0c97236dc7878cd78324d5b72d8e53e77f737d01bac4fc756f557ba5748c252506e1d00f543315354080f540c6ea4e89406b12e759192963c0931a6a8dcd239e3a31d63e3bf5e5bc78c4748e57499b396e6725f1f7e3d28b1dfb89122a1cb0087967f1ca9b00e6be017a063e4994b4ed2301ecc8a745be4edede3ee0c559b739ec651ccdbdf0b56202088241454160a3419aaee8095d3fb9946f4f7141757ac77d743c662a4496d52fb5ac59b381c7246a2dcf5797f630de2a18061decd220b6313b6097d25050dba6ca027bf5ca612a77656dfac3ac3ed6d188e5720d0f887a28ae4c69cfa849df60f121811e3c91356b1050d5e65e84a89e1792dcd974f1d80437ceb1ce6186380640af597aae636c59252636e725bd4977df8eb753094643fc9ba12cbabf58d8cc1348c878fdaeb0b40900c460c9981d8c938cf407a5b14267c65fd12be727b3e33d26c96243f515609dc71c4ccc037937ea3a791961a9f0f96d04dd9957bd1a48991976fecb2c3fc8462477aff85ab943be89af05273135c25416a7f3d3bc7d4fc56d51e5ec2c46913b9759b5cf5ba34b3dae9c1432be74465e003230d1c17a019228b58a96ea5c4c9a55f25174cddaaa80c0d4b5b8860832534f8b9d59faf056bc8b36e8c4f336b57ddcc55f0d575795848abc3fb307519488b2c21da862b9f013e0266aa872c626327207fdfb54371fd09cca07c909b589be052374c3d81227192bd57accc399f48e7e13444b9a03b8d00f2816cac12d0ade28e1578a44f2f3d0a6f7300c7ea139df3ae39e86a350d5dac04af14d4e96d4bdb81dc3e1ec79b44249051341b6796bc1fe6639117bd030118397553001102dcb027c124808ca8a785f0771b428ba085ea39d7341141d60cacb9eedbafff7eb5ceb194b1517be308aade80c5846988d4ba6b481468af03a713aaddeedda25750912869b65e2f12fb5e0b5a74349efd39921961d845208d59f378c200cfebb580fc2448389105c056079bff79bf68bfa91457ed8087e93fb6a9dfe8c096e6ca882befadefbc2a0acc12736f8d70f2e4738f98eb8fcbae598c91ef2d09d95f04b7b39618968671c50b217250a73d08a3c9c248fcd958c0123652fa1a5c6a2103c5ecff9dd2d1d42fda8d13aa31698fad40f303476deb60c76ffa680abe29b371984f1dc9224704133ae755330108f560e33498ce25097a561408aa8ee5e91a48c17ea633538a9a7b204c0e1724fa47af51999becceaf774f5752c7cce89f5147a4a144f59c5c422042d01b9a076485fcc07084f722b315b1db5410d26097b212713d8ccd3aede06baf4511416c0fad3c944238b0021303b468beeccd56d8cd0cf8f867e0e02305126c97b31ea121ba87fcab30545217c91ed05cc1135301ce040b7e40d9f0676423f35f554280175bb2e1d4ed45546645e0eb3b12b99369fafb2a0be54b1fc9e8aae259b06cff683e667e20b370a62a84ae5e0a072be94f0ff56dd37e9e2b4fa0b025978c23b5d82ff7c416ac2694b696dec7a96ddf9d70e213ae7136328e40e2160c8a183b8b27344f64854bf4dce4b5f557cfd04d2eed31e13ea857ee5b6ff099b4a69bc24b6d277a35016b676ea5c85c3b644a0fc054d76852b07d887923319d005ad6272c34732a1a2d030dc83eea56fd0a0a183c740c4f63259161534d95d11b4873313bc13f25f005b959a6b8d1b94ce2a1571cd202bc550a479b4da176fb55d7b48660315caaeb749808751facc2cf22289a8de45a75b16bd895d3a309de3ed65d5f452a83c94239a64bd51c8cd7f7b4f966421ceb734b2bfcc99d3aafff82ed8cd61a528fead4ab737567333a2de08121081a178529e9fd8dfa62c5d3794b5185196f4572776181305f377abbccc35839989be3b93e41def252d29a8b663a7523dc4a05119afe26503717326e5f245a520887c2afea622b337fe3fdbc8be5b8b428a2f37666baf8b3e01261643a066b543edfac9baa6b0fdadf67ebb4fa7bd4bf044cb7f6a184a0aa01988699d813693cff47c0238da7ce6df0a2dd715e369bd676c7697ed19630fb41b80ec5d5d1d9bb4a90571acece58b151a2afaab7aadbbca851cb80af489714f3f602ac3f220987af5bddee280804d3c1391527309e6c6c5df3ffd325137c521f0d34115d227113d9d49bfa831a937f2276da5ce6afa8813fa5282f7c87dd13b77cec86cc5106a787e34c4ff4bf47ccbfdd773384c30ee54739ee2f8c04c8deebd34a1192694cfd8ee2769240d4fd3b50d59087e5102c49e3fb09354eb37eef0125f6fef99f3694c5e7bc234c77da18f8ada4d564423f32a046018b0c74d0d07ede8823fd537077779a",
        "192.0.2.2:9635@6b57fc1625535534d349ba062458cbc3c06a1826bbcfdd98a788e09f9ea6e67b9fe84d7694a686860038ad394da2fb0f3883dd86f7b924b1e0da67f1a84eea1e0707758dc7120454747dee46fae130ce3f9f71f8187d89a8f60964e11f49855d44a1870791cf55f7db5fcfd8d1ccda04aaedad102d45230124a1a857d60c8b25157c4e9e72932a4b27900e396fda7e6377d8af076a38ba1c54814533a294609706198ee2106ccc59ec31b44f355574be5f10e7fb1e01583450c6d41ec7d9ebd72bee617c01e39433198eaa46ad26f5df77483ed4eaafe1de18160d342c778e3ea20c26e134889c840331adfd9976a3dc9c5ca116caafd0285b316cc003e3a9fd5a8cd9759457c01a7aa9070abc85a72c29608e279c3291eec370405e97d09fe787411cc88ba3353108802f3d1267917a14d64caef4b3e39f3a73d2d4fa02d369862b6008be3a5bce01f42bdf327acfed4ac3a12adb8f8a814e5e3405fede975a113a686f556f7dd361975d51211a88e3f069e67df0587a654a642475aad02ea6560876e984d337ec63cf7e67072c8155d5e2cc01467d188aacf7eaec553440fd9dc68e62b37e2c7c2d6a1a82780b76dba5c77c44f829d84b8f13b894192036b36763fb56457eefcb87b5e2d6cd0eb19930e098f5b21aec5e803d8007b9001a5eb7f8b080ce1f940d7d00d6f7d89747fc2c3d39f86e6916d2624d4d1cab443a57036cf869c3fa3cf2aaff690e08926745691a72f7d475924af03513eaed4d23ae5fe4f69619ff01fa2f68f4a665fd04ac0fb41d8d0d201d05e7da55b0c52f772dd908a710e83e786b134cab6f6346c8512a40ea261cee120123fd176534c600a22dd0b827329e7bfd7cae71d460fc9e5a6b6e02d133765e2ed0216f0787129abea1c708ff237775b8a1ff612219e2afa4a8ae53939c6f427249d58231faec91473928eaaf053c30109bf20c306921dd90cbfb7edd0884186bc1d8416e04f695b74f2bd74c65b2db7543304ce3cab190dcfe5360267dd22e672b4140ff83ffe262d76ae845b49a27684eb5f5616931714f5e55df2cfe7d4335e15538003e07f1fb471efcba92858ff30413693b1928e0e05fc5cdfc6d1f03734862c9d8404a278c6f56400ab92ae3a638f2958bf211c741092132eac0fe7804bdee0cd134605018999d40699d473fde8d57c3438ec53de8cd8823e4c0a04c95f3e5a07e0514ff490efe0ee1bf5b89b25083c705b90960335f4ecfcb369418704bfb3ee9e71fa053eca409fab84cf0318e42f9c5b9876c40f012d66125d3b3d33a433c8d379df84d1ca185adef03fd1abb1c5934c63079d7bee9960d0a2c6e134ed639160d8b5225a4b3bbb47fe48a9233571d01a9b85db1b3c174249f7b971cf48a7c10242334235bfc5e108178269c3fb9b874cd420c9d6795cd0a9cba4538a1a82f610f623fd134dac66c4402a6afcbf2c4a1b7af185aea74e20277bb96f53681d811990eaa7ac6b24e581570a98a31281854dc2fbf1617b183abcd2457b1d638520a11e1a83621f594e729a2298e1e1af7b4a6c817548ad6992cec4dd15c7ccbfc06a19d64d6b1a521ac9da1a528b7d9d8fa3a19f40f21f44776013383467d2957a716ec0110dfa6c3d3bdc34aa0cb2188ab9d5a058da06c1dd924ee3e0e20f1c7b232369a6fb83e18a9bdc2fc6004232bdc1d0a23c48ce3132b56408eeb7e1bdb52c47195e56204a9b4349612f88d231d4afc98b78e74d8ba133bf7605e8261c7d379006a3bd791dc4f4ff47248b109a562e0801c8e6bbdd8a929200238761a14e6daf91e874553a618313c965b645a8f14453bf721dabad4c2fc90e82ea528d8eea6feb1364265805c53426de37c2e5b74c4bc4c561d83a5373f73977c7a20e146984ccd25c4ee1333999f9308a8e8506d125e2b7788c5d4d443fa269ac89a09a09639376d36054f694b6b09b3caaad56cd0d683b030c630b1b0cb610a6aaa87c640b958c0ba4ee43adabb1b09f05c51ae02a7b1caf432c9434b97b9740fa64da4d567181cdfa91b9721422bd49cac6073a9cde4568779b552e6ec1a88aaee3c9141ca3ac23a700c4e2c45bc85a4cd2b283714db9dfff8edd454a262e698e7d23f08343a81df5e98b0b9977725be1b7bf52be8dc112aa838ce0e842b0eb834d059388fa7973c70be2e73c3feb77e8d3b55ef49c7941f2ed8a326728ce8458958d8946112f8a830a14a923bace56b19110f4a6ac2af606401cdd71043f7ef7b0fbeb03fbfd2955c15fb7710c06b9aefe587102fc9dafe6970e988e588aecc892164230a72eed78036d19c0e3dfd5cf50c9a5683a13cef3d5aefe1f2f8c3775d94b63706829ae187825f5c17551ae41d5e13eb40a908597dc46957313b22a9c44b8c2fcf9be2270ea523b83bce874860d080e4ca714d6f8b4d50ed47618b832a7e654a76cce9998dfcdf8155b4b6c5057083822693a376e37f441e5758064dd6b59cf6eccd0d1406e9f5bafc6b6cd158a27a1d528aa347a6e5b22a3a30ab3affe234cea4918ee9d47962aff2221cdb4a2f262bafcd469884024b81fe1e19ef00cb94b414068d608045f66600435c6c3a8e8c9663aada182917645507c8c94100426b990cad4c71b5ef6fedb50a4a96b8ad502d0bb6ea7f23b64c3b96d8dfc19d854bb0ed1585874af9d5c2533bf893ce411cc64ce9ab8ddc79d5bc0272a9d3c4cd08e5313f8c0758d6d59aa2e812c068a067b4b8e016155635ce9b91ca982a99cfe386d888e9",
        "192.0.2.3:9635@fca3c6562ecb21c08068d8bc35ac94816b276b417f3fccb5e536d865bac46aa2394c1e6fd94d24eca7405acf0240837b64b2e7f6dae3e809ebcace748d844eb360b18fc8cfb6c396cb711a8f2334bbdf00288f4461aede9a2351b40c2cae395867644142e73deb5751960aef0cbed3ab33bed6b35a7e737c9f3bd60e142c8b5f91589196e6a9acdf8297d8939254205ba2f7e5c9afd16acc9e43a8c7ef60b1108404dceb02ad2cb49d1d328566f1d793fcc4e9652f647a8cd9fcca09fad1b5101227abf51c77c940d5a8693b88116c2336bb5f620f4a7ba0d0db120c8800eb06b64e2b08c9dbda255d1c5e3ffa3041130b2f8eaab26d62bfe1a6282b6c3018036442f80b87e0ab210aa1af2065676af30479b4165ec21cf55c1ccf34d278e6e013139a6cf7d47280e95097a6e2358e9bd2dc3e363807bda70ba45d5f6d787b3aea98117d806142dfcd71e599769de41e4661aa9d4dd598e0b3d6610cdd86ad8290e2b6ca5e69e6c692050f8905a6631f40b763ee27e276884379704292312e280d78a416e509abe12f877a1cac55094cd73ce36aa1912e3d96d5f91e88b7b51ac296c2d4c4a0d9da7908a788188952dd98cb75eb963d391961fa27d3bc31b90499127f0c268b3a5554d3aa668cd0c06a8ed2cfa97adfe1a0124a2edcd01f9d4b14d59d3d55ef38da7bac7269b7b1fb30ebc9bdeb2fca497e97642cf3e55459d0a77c3b4da75b952d2cf1fddc615b61ba8207eae38048b85e21e23b30dc9e9d31a36b5b8b4b691165ed63f0983ded232c2f1cb92e37684cdfc04a4fb1cf87d3856d36d4852d24556ee2aa67c4ce91a2c4d4b03cb77b0e78c1097023e8ab176c8e774054f21e7f6aba0fb4c7b3603f7261a1c68703b8ffc7d53aa664aa6378a2edf65053995c81d7da23b4a45974b85b5e9dcef29d78e4dcc377de5dca59e03229956e9a7766b412195888ed5d2d393f62a4235ab7660ba39dec918bea6b5cfbfa7e4e6e1c21d41c1d3ea8ebbd5402225d8c201738357e9a96d9b03d87bbba231e70dd74645d8ef164bf95857cd43518a486999bc97d3c29b4fa26d436249f1bc8d2ce6309376c1a47f14ab338bdfefc2cd65ee1ed4f7e030abcbe408fe1c539a9db25a1733774090d766184c0cc9e1b91ab441fd6a77eb0c879829f09344d780c380e04efc5ff40fe2199904a9cdc372e36645a1caca17734cf7b8e945e9391d028e0391b55d2f29234fd324a0ed4653c67592d3c2cd26c28455d28f686ed9a5b06f805a6cc599229d629fbeab50ca042ddac7f40d93a8c620f0ec9b1b0a096e65faf53e41f61cbc40ec3aedde99f01bd57fb107f6e0ddf5701d8aa259c426f6e5453e27adb863c111e24e65f480092e34a05ddabc1b877696c4f33284521866ef00a09cc5806559c2601dc23d83c7d0270975fd34d7297383f24055d69cb157c81e8ce759d0f6567d0f3cea80c246dfd75f9ea1ee84814a2a1b2ed31a7fbd163575c795040ad1a0cd8ed31852f97ad8f13ce5290b1d43709958f90546a1af7533afc3ddfa0e24ea000ee31d5fff8126509a668e4a166dafb9c8c2ddffab82529555b16d79cbcc9eea1a6e8d583c60bff45b0815bface213b3ddbc49d39cef678b40a891b481957d6b5e0840a97aaf2a3147684611cb0e0ec34c568f446c5e9aa606e28f6ad1db2470c3a072b5801950b4c883484cc42a3dc903f8e2bb548391d44d8d9d4b9d204cdd8f3772aeda47c203196102264a2eb992600b9c2af0c1b904dbfa25da1054e005414d7c7950605fa176135d4f0d7829ce512b7e598a269fff4fb9c554c76004d23a6bdbab671e311d1abdaa80b7d9a32740791c942ab1cba7694e19f8344edb889924491b50fea5245433b039e9bf2ad61fa5916c3ed9e74ece518e0d85ac7ff1a02c9201867c56c49c4b4a7d02c272e5d09ea69f01a50484654f3b2fd11af894991957b45763d9010aa0ff478cc1d36afc774d2bb5f398460c6fef0ce10af4601a16c96a5075706544114ea21206c777ed8043abe369f717f6519fcfa4ca03280bd3f303982470df62f29d78014725dac4a0f2acca51d99cf63ac793d28095f4115a591a1df23d8504c12d8a70264c1d8513f02762cd941e34293030e46a8c131c493323f34d8f17b8a00a5ecd4315ca32de223b14fae4890992c39f21a027de866da47ab914379962a4349111828d2f628d9ce608f95a5817ec67580674ac599acb7a17245621c15d46a3edb8a66e59760c66fd012e036a8f6b043755830fb4b361e4083ff87a60b064bb6be9ce370af1989636d4ecb2a6ec743a3c1e730419c08d0a2eaad2b258ba33affe00598d8831ea692aced857ddb51324a00b2caf271e875d3173a72b770ad795ce5def45eaa3809f755419ca43c58cb466517e663c695d3ee4f6b5b8ece2ad637ce55cc7194685bbc164721fd6a13373de03fcffee1c412f6bc207a746aa111ea2c9c67456716afd80c2694a8beb4cc51e2b1a6712b4c33fcd205115b5290f0b3bae438ba2484238b6fab49679b8ede75957e2f12ff5f3fd4200ec7dc9649e3c4556040007b6574ad39f32e6c9abda45551027c5b05b11a343569335193402cbad64b868cb004f5d87e53071239c12080bca01574625e2d9bb89dafc30c9340038a21b83771cd1d88a106bf139c6adb13d589df436aef78eb87ae1e3e870487b551677444e592048d9332d71688ab8d8d871af18de597ee07ac5a9fd0601c645a77729ea1795eb21a3da3a266"
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
            MontanaTrace.mark("core_node", "open rc=\(rc) born=\(born) \(said(rc))")
            guard rc == 0 else { return nil }
        }
        var got: [Int] = []
        for i in missing {
            let rc = genesis[i].withCString { line in mtc_machine_reach(line) }
            MontanaTrace.mark("core_node", "reach \(i) rc=\(rc) \(said(rc))")
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

/// THE CHAT'S COINS, READ AS HISTORY (the author's words 02.10 18:29-19:37 began them: «every letter drips one billionth of a
/// Montana to the person, equal to one coin»). Up to the time cut a letter of a pair's ribbon earned a coin in this phone's book by
/// its wire name; from 22.10.2026 21:00 UTC only the chain mints (fold-6, fold-7), and since build 2320 no letter, bubble or feed
/// asks the book at all (the author's decision 375 «a», 29.10.2026 22:01 UTC: the dead local minting removed, the old lines read
/// as history; the word 11871: «only the rule of the constitution, 1 coin is 1 second, by the core»). What stands is the wire
/// name those coins were booked by and the coin's reading in Montana.
enum MTChatMint {
    /// One coin is one billionth of a Montana (the author's word 02.10 19:37).
    static let coinsPerMontana = 1_000_000_000

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

/// BIG NUMBERS PART THEIR THOUSANDS WITH COMMAS (the author's word 04.10.2026 01:20 UTC: «the separators of big numbers are
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
/// LEVELS BY PI (the author's word 04.10.2026 09:23 UTC: «call them levels by pi instead of boxes; if I am of level 5, all my
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
    /// THE LEVEL IS A READING, NEVER A RATE (the constitution of the chain, point 11; the author's words 19.10.2026 12:3x UTC: «this
    /// is the ceiling, the invariant -- nothing else can mint or accelerate it, no music, no VPN and so on»; «the Global Level is
    /// untied from the minting»; 13:4x: «bring it all to one owner of the function 1 coin = 1 second, and that is all»): the one
    /// owner of a second's coin is the book (MTCoinBook.price, MTLocalCoinLedger.priced); a level multiplies nothing.
    /// π as far as a level reveals it: 3, 3.1, 3.14 ...
    static func revealed(_ place: Int) -> String {
        let d = String(digits.prefix(max(0, place)))
        return d.count < 2 ? d : String(d.prefix(1)) + "." + String(d.dropFirst())
    }
    /// Coins in the short form the author named (03.10 21:19: «1k, 10k, 100k and so on up to a whole Montana, 1kkk», the k in the person's language): whole
    /// thousands, millions and billions, never rounded up -- the badge says at least what is held.
    static func short(_ n: Int) -> String {
        max(0, n).formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(MTLanguage.locale))
    }
}

/// THE COINS RISE AT THE SIDES (the author's words 03.10.2026 21:11 UTC: «auto minting one coin a second with an animation at
/// the sides»; «at a chess move the coins' animation too»): the one owner of the minting's sign. The chain's seconds tell it as
/// they come (MTCoinSplit.beat) -- a coin rises only when the chain credits it -- and
/// every screen that wears the sides (MTCoinSides) shows the same coins rising at both edges with the count.
/// ONE RISE, THE SUM (the author's word 04.10.2026 15:08 UTC, T2: «the minting's animation must not double, only give the sum in
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

/// PANTHEON ON FIRE (the author's word 03.10.2026 19:25 UTC: «a tap on the coin in the wallet is +1 too, quick taps all count;
/// the coin spins at a speed from 1 to 13 and the speed is shown; the game is called Pantheon on Fire, the first tap on the
/// wallet's coin lights it»). Since build 2320 a tap mints nothing (the author's decision 375 «a»: only the chain mints, 1 coin is
/// 1 second); the fire and the coin's turn are the game alone. The speed is the taps of the last second, up to thirteen. The speed falls to zero
/// when the taps stop: the number shows the taps, it never holds them.
@MainActor final class MTPantheon: ObservableObject {
    static let shared = MTPantheon()
    static let ceiling = 13
    /// The name a tap's coin stood under in the books of the builds before 2320, read as history.
    nonisolated static let refPrefix = "tap:"
    @Published private(set) var lit = false
    @Published private(set) var speed = 0
    private var taps: [Double] = []
    private var holding = false
    /// THE FIRE RESTS AFTER A MINUTE (the author's word 04.10.2026 10:38 UTC: «at the Pantheon on Fire's activation, under the level's
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
        MontanaTrace.mark("pantheon", "lit")
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
        MontanaTrace.mark("pantheon", "rest")
        resting = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.streak * 1_000_000_000))
            guard !Task.isCancelled, let self, self.restUntil == until else { return }
            self.restUntil = nil
            MontanaTrace.mark("pantheon", "rested")
        }
    }
    private var settling: Task<Void, Never>?
    private var going: Task<Void, Never>?
    /// THE FIRE GOES OUT IN THREE SECONDS OF QUIET (the author's word 04.10.2026 00:13 UTC: «if you do not mint for 3 seconds, switch the
    /// Pantheon on Fire off»; before it, a minute, 03.10 21:19): while it burns the wallet's page does not scroll at all.
    static let quiet: UInt64 = 3

    /// A finger landed on the coin: the game lights at the touch itself, so the page stands from the first finger, before its coin.
    /// THE FIRE BURNS WHILE A FINGER HOLDS THE COIN (the author's word 04.10.2026 10:06 UTC: «if I press and hold the coin in the
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
    /// One touch of the coin: it lights the fire and counts the finger's speed up to thirteen touches -- never a coin (decision 375 «a»).
    func tap() {
        let now = Date().timeIntervalSince1970
        taps.removeAll { 1 <= now - $0 }
        guard !rests else { return }
        light()
        if !holding { goOutAfterQuiet() }
        guard taps.count < Self.ceiling else { return }
        taps.append(now)
        speed = taps.count
        settle()
    }

    private func goOutAfterQuiet() {
        going?.cancel()
        going = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.quiet * 1_000_000_000)
            guard !Task.isCancelled, let self, self.lit else { return }
            self.lit = false
            self.litAt = nil
            self.resting?.cancel()
            MontanaTrace.mark("pantheon", "out after quiet")
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

/// THE BURNS OF THE BUILDS BEFORE (the author's words 03.10.2026 21:51-22:01 UTC): up to build 2111 a call burned its seconds and a
/// letter one coin. The author's words 04.10.2026 22:21-22:31 UTC turned the burn into a payment to the person -- «the one who calls
/// pays the one called, the one who writes pays the one written to» (MTCoinSend.pay); a call moves no coin (the author's word 29.10.2026 19:31 UTC).
/// The names stay to read
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
        lock.lock(); let moved = held != v; held = v; lock.unlock()
        if moved { Task { @MainActor in MTCoinTell.moved(); MTFabric.shared.refresh(); MTLevelDistribution.shared.changed() } }
    }
}

/// THE PEOPLE IN THE APP HEAR MY BALANCE MOVE (the author's words 04.10.2026 00:03 and 01:19 UTC: «the update instant, as by a web
/// socket»): a move of the book says the balance again to the correspondents in the app now, in the app word (E2E.coinBeacon) --
/// one round in two seconds however fast the coins come, so a minute of minting is thirty rounds to the people online, not one a coin.
@MainActor enum MTCoinTell {
    static let pace: UInt64 = 2
    private static var due: Task<Void, Never>?
    static func moved() {
        guard due == nil else { return }
        let wait = pace
        due = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wait * 1_000_000_000)
            guard !Task.isCancelled else { return }
            due = nil
            tell()
        }
    }
    private static func tell() {
        guard let store = ChatStore.live else { return }
        for peer in store.appOnlineChats { E2E.shared.coinBeacon(to: peer) }
        MTTopNet.shared.put()   // the one table hears it in the same round
    }
}

/// THE PEOPLE'S COINS (the author's words 03.10.2026 19:23 and 19:25 UTC: «in the wallet, under the add-account button, the
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
    /// THE PEOPLE'S LEVELS (the author's word 11.10.2026 18:2x UTC, MTLevelShow): the Global Level each pair last told in its
    /// presence words, the newest word wins, and a word that names none takes it away. The book is drawn again only when a level
    /// moves: the moment of every word is kept beside it unpublished, so the faces are not drawn again at every beat.
    struct Level: Codable { var level: Int; var at: Double }
    @Published private(set) var levels: [String: Level] = [:]
    private var levelHeardAt: [String: Double] = [:]
    private static let levelsKey = "coinBoard.levels"

    private init() {
        if let d = UserDefaults.standard.data(forKey: Self.key), let t = try? JSONDecoder().decode([String: Told].self, from: d) { told = t }
        levels = Self.readLevels()
    }
    /// The person lifted into the seat: the balances and the levels their own correspondents told them.
    func reread() {
        told = UserDefaults.standard.data(forKey: Self.key).flatMap { d in try? JSONDecoder().decode([String: Told].self, from: d) } ?? [:]
        levels = Self.readLevels()
        levelHeardAt = [:]
    }
    private static func readLevels() -> [String: Level] {
        UserDefaults.standard.data(forKey: levelsKey).flatMap { d in try? JSONDecoder().decode([String: Level].self, from: d) } ?? [:]
    }

    /// THE TOLD IS CAPPED BY THE CHAIN (18.10.2026, Agent 93, the critic's P-3; the author's word «close every point»): a pair's
    /// word says its balance and its level, and any build can say any number -- a third-party build says L13 and a billion coins, and
    /// every honest phone drew them by the face and in the rating. A told balance is kept now only up to what the pair's own coin
    /// chain proves on its node (proven and declared, by the key the pair named, MTCoinTx.peerFrom), and a told level up to the
    /// wallet member of that balance -- the Global Level is never above it (MTPersonChain.global). A pair whose chain is not read yet
    /// stands in no rating and wears no level; its chain is read at most once in ten minutes.
    private var chain: [String: (coins: Int, at: Double)] = [:]
    private var heardCoins: [String: Told] = [:]
    private var heardLevel: [String: Level] = [:]
    private var asking = Set<String>()
    private func proveChain(_ conv: String) {
        if let c = chain[conv], Date().timeIntervalSince1970 - c.at < 600 { return }
        guard !asking.contains(conv), let from = MTCoinTx.peerFrom(conv), let door = MTCoinTx.chainDoor(from) else { return }
        asking.insert(conv)
        Task { @MainActor in
            let st = await MTCoinTx.chain3(from, door: door)
            self.asking.remove(conv)
            guard let st else { return }
            self.chain[conv] = (Int(clamping: st.proven + st.declared), Date().timeIntervalSince1970)
            if let t = self.heardCoins[conv] { self.keepCoins(conv, t) }
            if let l = self.heardLevel[conv] { self.keepLevel(conv, l) }
        }
    }
    private func keepCoins(_ conv: String, _ t: Told) {
        guard let cap = chain[conv]?.coins else { return }
        // THE CHAIN'S NUMBER, NEVER THE TOLD ONE (P-4 of Agent 95, the author's word 19.10.2026 09:2x UTC «put it in»): the lower of the two
        // still let a build of one's own say 0 and draw every levelling's gift (MTCoinSendPage.levelPlan); the pair's word now only says
        // that it shows its coins, and the number is its chain's
        let coins = cap
        let moved = told[conv]?.coins != coins
        told[conv] = Told(coins: coins, at: t.at)
        guard moved else { return }
        if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
        MontanaTrace.markFolded("coin_board", "told=\(told.count)", window: 60)
    }
    private func keepLevel(_ conv: String, _ l: Level) {
        guard let cap = chain[conv]?.coins else { return }
        let level = min(l.level, MTFabricRules.walletLevel(cap))
        guard levels[conv]?.level != level else { return }
        levels[conv] = Level(level: level, at: l.at)
        if let d = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(d, forKey: Self.levelsKey) }
        MontanaTrace.markFolded("level_board", "told=\(levels.count)", window: 60)
    }

    /// A pair's presence word told its Global Level, or named none (a negative level): kept when the word is newer than the last.
    func noteLevel(_ conv: String, level: Int, at: Double) {
        guard max(levels[conv]?.at ?? 0, levelHeardAt[conv] ?? 0) <= at else { return }
        levelHeardAt[conv] = at
        if 0 <= level {
            heardLevel[conv] = Level(level: level, at: at)
            proveChain(conv)
            keepLevel(conv, Level(level: level, at: at))
            return
        } else {
            heardLevel[conv] = nil
            guard levels.removeValue(forKey: conv) != nil else { return }
        }
        if let d = try? JSONEncoder().encode(levels) { UserDefaults.standard.set(d, forKey: Self.levelsKey) }
        MontanaTrace.markFolded("level_board", "told=\(levels.count)", window: 60)
    }

    /// A pair's word about itself carried its balance: kept when it is newer than the one held.
    func note(_ conv: String, coins: Int, at: Double) {
        guard (told[conv]?.at ?? 0) <= at else { return }
        // A NEGATIVE BALANCE IS «HIDDEN» (04.10, MTCoinShow): the pair turned its coins off, and its row leaves this rating.
        guard 0 <= coins else {
            heardCoins[conv] = nil
            guard told.removeValue(forKey: conv) != nil else { return }
            if let d = try? JSONEncoder().encode(told) { UserDefaults.standard.set(d, forKey: Self.key) }
            MontanaTrace.markFolded("coin_board", "hidden told=\(told.count)", window: 60)
            return
        }
        // Every presence word tells the balance now (E2E.coinTail): kept up to what the pair's chain proves (keepCoins).
        heardCoins[conv] = Told(coins: coins, at: at)
        proveChain(conv)
        keepCoins(conv, Told(coins: coins, at: at))
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

/// THE MONEY FLOW IS A CHAT'S OWN (the author's word 04.10.2026 09:23 UTC: «if my chat is turned with one correspondent, it concerns
/// only the chat with them, not all -- part the states»). Each conversation keeps its own turn of the feed and its live words both
/// ways. Read from any thread; the screens observe the change.
@MainActor final class MTMoneyFlow: ObservableObject {
    static let shared = MTMoneyFlow()
    /// THE FLOW MINTS NOTHING (the author's word 11871, 29.10.2026: «only the rule of the constitution, 1 coin is 1 second, by the
    /// core»; decision 375 «a»): from 22.10.2026 21:00 UTC only the chain mints, and since build 2320 no bubble of a flow's chat
    /// asks the book; the coins its bubbles earned before stand in the book as history (MTChatMint). A call moves no coin (the
    /// author's word 29.10.2026).
    @Published private(set) var turns = 0
    nonisolated static func isOn(_ conv: String) -> Bool { !conv.isEmpty && UserDefaults.standard.bool(forKey: "moneyFlow." + conv) }   // a conversation's own key (SeedScope.dataPrefixes)
    func on(_ conv: String) -> Bool { Self.isOn(conv) }
    func set(_ conv: String, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: "moneyFlow." + conv)
        turns += 1
    }
}

/// The balance badge and disclosure are on by default (14.10.2026). An explicit
/// privacy choice stays in force. Opening the wallet explains the public ranking.
enum MTCoinShow {
    static let key = "coins.shown"   // NOT-UI: the owner's balance privacy preference
    static let toldKey = "top.told"  // NOT-UI: the wallet explained the public ranking
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Reputation is always visible (14.10.2026). The old preference is retained only
/// for reading backups; it no longer suppresses sending or drawing the level.
enum MTLevelShow {
    static let shownKey = "level.shown"   // COMPAT-LOCAL: retired preference
    static var on: Bool { true }
}

/// THE PERSON'S LEVEL FOR A WORD SAID FROM ANY THREAD (11.10.2026, E2E.levelTail): the presence words are built off the main actor,
/// where the chain of the person lives. The chain writes its level here at every count; nil until this life read its seconds, so
/// an unknown level is never said as none.
enum MTPersonLevel {
    private static let lock = NSLock()
    private static var held: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static func set(_ v: Int?) { lock.lock(); held = v; lock.unlock() }
}

/// ACCESS BY LEVEL (the author's words 16.10.2026 15:2x UTC: «both functions of level 7 must be made, and in the settings a path
/// Access by level -- where they open for each»; «we have the gamification of access to Montana's functions»): every function a level
/// opens is named here once, with its level. The person's level is the Global Level the avatar shows (MTPersonChain.global); before
/// this life has read it, the last one this phone knew stands, so a launch's first second never drops a choice the level opened.
/// LEVEL 8 (the author's word 17.10.2026 15:1x UTC: «add to the accesses that only from level 8 can one connect one's own node to
/// the Montana network through the client»): a machine the person owns joins the network through this app -- set up from here
/// (MontanaNodeSetup), its daily copies and a copy sent at a tap (HomeNodeWatch) -- once the level opens it; taking one's own
/// copy back from it asks no level.
enum MTLevelAccess {
    enum Feature: String, CaseIterable {
        case keepDeleted   // a letter the correspondent deletes for everyone stays on this phone, and the correspondent is told
        case autoRecord    // calls are recorded by themselves; below its level a call is recorded by the call screen's own mark
        case ownNode       // a machine the person owns joins Montana's network through this app: set up from here, copies sent to it
        var level: Int { self == .ownNode ? 8 : 7 }
    }
    static let lastKey = "levelAccess.last"                    // NOT-UI: the last Global Level this phone knew of this person
    static let keepKey = "levelAccess.keepDeleted"              // NOT-UI: the person's choice, on once the level opens it
    static var level: Int? {
        guard let p = MTPersonLevel.now, let c = MTCoinBalance.now else { return UserDefaults.standard.object(forKey: lastKey) as? Int }
        let g = MTPersonChain.global(person: p, balance: c)
        if UserDefaults.standard.object(forKey: lastKey) as? Int != g { UserDefaults.standard.set(g, forKey: lastKey) }
        return g
    }
    static func opens(_ f: Feature) -> Bool { f.level <= (level ?? 0) }
    /// The person keeps the letters their correspondents delete: the level opens it, and it stands until they untick it.
    static var keepsDeleted: Bool { opens(.keepDeleted) && (UserDefaults.standard.object(forKey: keepKey) as? Bool ?? true) }
    /// The choice as the notification extension reads it (the shared keychain): it takes a deleted letter's notice off the screen
    /// only while this phone does not keep what others delete.
    static func mirror() { MontanaKeychain.set("keepsDeleted", Data([keepsDeleted ? 1 : 0])) }
}

/// The public distribution contains counts of levels only. A separate, seed-derived
/// owner token lets each person replace their own level without publishing a balance,
/// name, address or contact list. Old clients can continue using every existing door.
@MainActor final class MTLevelDistribution: ObservableObject {
    static let shared = MTLevelDistribution()
    struct Bin: Codable, Equatable { let level: Int; let count: Int }
    @Published private(set) var bins: [Bin] = []
    private var asking = false
    private var again = false
    private var published: String?
    private var publishedAt = Date.distantPast
    private var attemptedAt = Date.distantPast
    private var readAt = Date.distantPast
    nonisolated static let cacheKey = "level.distribution"
    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey), let kept = try? JSONDecoder().decode([Bin].self, from: data) {
            bins = Self.valid(kept)
        }
    }
    static func valid(_ input: [Bin]) -> [Bin] {
        let clean = input.filter { (0...62).contains($0.level) && (1...1_000_000).contains($0.count) }
        guard Set(clean.map(\.level)).count == clean.count, clean.count <= 63 else { return [] }
        return clean.sorted { $0.level < $1.level }
    }
    static func rank(_ level: Int, in bins: [Bin]) -> Double? {
        guard let first = bins.first, let last = bins.last else { return nil }
        if first.level == last.level { return level < first.level ? 0 : 1 }
        if level <= first.level { return 0 }
        if level >= last.level { return 1 }
        let total = bins.reduce(0.0) { $0 + Double($1.count) }
        let before = bins.filter { $0.level < level }.reduce(0.0) { $0 + Double($1.count) }
        let same = Double(bins.first { $0.level == level }?.count ?? 0)
        let low = Double(first.count) / 2, high = total - Double(last.count) / 2
        return max(0, min(1, (before + same / 2 - low) / (high - low)))
    }
    func rank(_ level: Int) -> Double? { Self.rank(level, in: bins) }
    private func own() -> (token: String, level: Int)? {
        guard let person = MTPersonLevel.now, let coins = MTCoinBalance.now,
              let words = MontanaSeed.mnemonic, let entropy = MontanaSeedKeys.entropyFrom(mnemonic: words) else { return nil }
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: entropy), salt: Data(),
            info: Data("mt-level-distribution-v1".utf8), outputByteCount: 32)
        let token = Data(HMAC<SHA256>.authenticationCode(for: Data("owner".utf8), using: key))
        return (MontanaHomeNode.hex(token), MTPersonChain.global(person: person, balance: coins))
    }
    func changed() {
        guard let own = own(), published != own.token + ":" + String(own.level) else { return }
        Task { await refresh() }
    }
    func refresh() async {
        if asking { again = true; return }
        let own = own(), stamp = own.map { $0.token + ":" + String($0.level) }
        let needsPut = stamp != nil && (stamp != published || Date().timeIntervalSince(publishedAt) >= 300)
        guard Date().timeIntervalSince(attemptedAt) >= 5, needsPut || Date().timeIntervalSince(readAt) >= 60 else { return }
        attemptedAt = Date()
        asking = true
        defer {
            asking = false
            if again { again = false; Task { await refresh() } }
        }
        for base in MontanaWakePush.orderedBases(for: "levels").prefix(3) {
            if needsPut, let own {
                if await post(base + "/level-put", body: ["token": own.token, "level": own.level]) != nil { published = stamp; publishedAt = Date() }
            }
            guard let reply = await post(base + "/level-get", body: [:]),
                  let rows = reply["levels"] as? [[String: Int]] else { continue }
            let next = Self.valid(rows.compactMap { row in
                guard let level = row["level"], let count = row["count"] else { return nil }
                return Bin(level: level, count: count)
            })
            if bins != next {
                bins = next
                if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: Self.cacheKey) }
            }
            readAt = Date()
            MontanaTrace.markChanged("level_distribution", "bins=\(next.count)")
            return
        }
    }
    private func post(_ word: String, body: [String: Any]) async -> [String: Any]? {
        guard let url = URL(string: word), let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 6
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        guard let (reply, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, reply.count <= 32_768 else { return nil }
        return (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any]
    }
}

/// THE MONTANA TOP (the author's words 04.10.2026 00:03, 02:40 and 02:47 UTC: «a live set as by a web socket, the update instant from
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
        // THE ROW TELLS THE SEED'S UNION, NEVER ONE DEVICE'S SHARE (the author's word 04.10.2026 12:51 UTC: «check the sync over the
        // network as a pendulum»): a device of the seed that has not gathered the others' moves in half a minute would pull the seed's
        // row down to its own share and the next device would lift it again; it gathers first, and the gathering puts the row.
        guard MTCoinVault.shared.fresh else { MTCoinVault.shared.soon("put", after: 1); return }
        let body: [String: Any] = ["token": MontanaHomeNode.hex(t), "name": String(E2E.myDisplayName().prefix(64)), "coins": coins]
        Task {
            // THE ROW PROVES ITS COIN KEY (P-4 of Agent 95, the author's word 19.10.2026 09:2x UTC «put it in»): the node shows that key's
            // chain as it folds it, never the number told here -- a build of one's own once stood first by saying a billion
            let proof = await Task.detached(priority: .utility) { Self.keyProof(t) }.value
            var b = body
            for (k, v) in proof ?? [:] { b[k] = v }
            await self.send(b, why: "put")
        }
    }
    /// The seed's coin key signs ASCII mt-top-key-v1 and the row's token: the node verifies it with the core and reads that key's chain.
    nonisolated static func keyProof(_ token: Data) -> [String: String]? {
        guard let k = MTCoinTx.keys(), let sig = MontanaPQ.sign(seckey: k.sk, message: Data("mt-top-key-v1".utf8) + token) else { return nil }
        return ["pk": k.pk.base64EncodedString(), "sig": sig.base64EncodedString()]
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
        MontanaTrace.mark("coins_shown", on ? "on" : "off")
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
        MontanaTrace.markFolded("top_put", "why=\(why) doors=\(heard)", window: 60)
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
            if !answered { MontanaTrace.mark("top_get", "rows=\(rows.count) rank=\(rank ?? 0)") }
            answered = true
            return
        }
    }
}


/// THE BOOK RIDES THE SEED (the author's words 04.10.2026 10:36-10:42 UTC: «I must log in by my seed on another device and my
/// balance must surely be kept -- the critical part»; the choice 10:40: «the book by the seed on the nodes»; «build by constitution 6
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
    /// The seed's union was gathered within the minting's minute: what this device tells the top is the seed's, not its own share.
    /// ONE CLOCK FOR THE GATHER (18.10.2026, Agent 89, T1 2238): the moves of a minute ride one piece (soon, after 60), and a half-minute
    /// freshness asked by the top's two-second round gathered twice a minute -- 287 of 372 gathers within 30 s of the one before, a
    /// piece per row each time, the fold to the whole book twice as often as its own count says. The top waits for the same minute.
    static let freshS: Double = 60
    var fresh: Bool { heard && Date().timeIntervalSince1970 - heardAt < Self.freshS }
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
    /// EVERY NODE HOLDS THE BOOK UNDER A ROW OF ITS OWN (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): the one
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
        MontanaTrace.mark("coins_vault", "why=\(why) the seat moved -- the gather writes nothing")
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
            // THE ROW IS ASKED FOR WHAT IT LACKS HERE, NOT FOR AN ARBITRARY 256 OF EVERY ROW'S PIECES (18.10.2026, Agent 89, T1 2238): four
            // rows hold one book under four piece names, the pieces this process opened ran past the node's 256, and the prefix of a
            // dictionary named a different part each time -- 296 of 372 gathers in 11 h took the whole book again (12.3 M moves fetched,
            // opened and decoded, a gather every half minute while minting). A row's own pieces, opened here, are what it need not send.
            let have = Array((held[r.slot] ?? []).filter { pieces[$0] != nil }.prefix(256))
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
        // WHAT EACH ROW LACKS IS RECKONED OFF THE MAIN THREAD (the author's words 23.10.2026 15:0x UTC: «on T1, build 2296, the chats
        // page stutters when I enter and use it -- check it and make it clean, without stalls»). Measured on T1 that minute: this
        // reckoning -- the union of every piece's moves and the book filtered by it, 30 089 moves for each of four rows -- held the
        // main thread 84 ms at a chat's opening, 101 ms in the chats list and 72 ms at the drawer (frame_stack, MTCoinVault.gather
        // at MTWalletCore.swift:1199-1205 by the dSYM of 2296), at every return to the screen and after every spend. The same
        // answer, reckoned on a copy; only the laying, which awaits the nodes anyway, comes back here.
        let plans = await Task.detached(priority: .userInitiated) { [answered, book, pieces, held, full, fold = Self.fold] in
            MTCoinVault.plan(answered, book: book, pieces: pieces, held: held, full: full, fold: fold)
        }.value
        if moved(gen, why) { return }
        var laid = 0, whole = 0
        for plan in plans {
            let slot = plan.slot, lacking = plan.lacking, anew = plan.anew
            guard let r = rows.first(where: { x in x.slot == slot }) else { continue }
            var replace = plan.replace
            for start in stride(from: 0, to: lacking.count, by: Self.span) {
                let part = Array(lacking[start..<min(start + Self.span, lacking.count)])
                // THE OLD PIECES GO WITH THE LAST NEW ONE (the coin audit's sixth point, 05.10.2026 18:4x UTC): the first part
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
        MontanaTrace.mark("coins_vault", "why=\(why) rows=\(answered.count)/\(rows.count) got=\(fresh.count) joined=\(joined) laid=\(laid) whole=\(whole) moves=\(book.count)")
        MTTopNet.shared.put()   // the row tells the union just gathered
    }
    private struct Plan { let slot: String; let lacking: [MTCoinEntry]; let replace: [String]; let anew: Bool }
    private nonisolated static func plan(_ answered: [String], book: [MTCoinEntry], pieces: [String: Set<String>],
                                         held: [String: [String]], full: Set<String>, fold: Int) -> [Plan] {
        var inBook: Set<String>?
        var plans: [Plan] = []
        for slot in answered {
            let ids = held[slot] ?? []
            var carried = Set<String>()
            for id in ids { carried.formUnion(pieces[id] ?? []) }
            let anew = fold <= ids.count || full.contains(slot)
            let lacking = anew ? book : book.filter { !carried.contains($0.id) }
            guard !lacking.isEmpty else { continue }
            // ONLY A PIECE READ HERE IS REPLACED (the coin audit's third point, 05.10.2026 18:4x UTC): a piece that would not open
            // -- a book of a later build, a broken blob -- or whose moves the book did not take was skipped above but stood in the
            // replace list, and its moves left every node. It stays on the node now, beside the whole.
            var replace: [String] = []
            if anew {
                let whole = inBook ?? Set(book.map(\.id))
                inBook = whole
                replace = ids.filter { id in pieces[id].map { moves in moves.isSubset(of: whole) } ?? false }
            }
            plans.append(Plan(slot: slot, lacking: lacking, replace: replace, anew: anew))
        }
        return plans
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

/// THE TIMECHAIN'S TIP RIDES ONE ROUND TRIP (the author's words 04.10.2026 13:30-13:34 UTC: «find the lightest record of the
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

    /// THE LANE CARRIES WHAT THE DEVICE BORE (the author's «yes» 04.10.2026 14:16 UTC to variant (a)): a letter's coin and a coin
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
        MontanaTrace.markFolded("tip_put", "n=\(t.links.last?.n ?? 0) b=\(t.links.last?.b ?? 0) bytes=\(sealed.count) doors=\(laid)", window: 60)
    }

    /// The other devices' tips in one round trip to the first node that answers: a lane's new links join the book by their names;
    /// a lane further behind than the window, or a link whose seal does not follow the head this device took, asks the book.
    func gather(why: String) async {
        guard !getting, let k = MTCoinVault.mine() else { return }
        let gen = MTCoinBook.generation   // the coin audit's second point: a seat moved during the wait joins nothing
        getting = true
        defer { getting = false }
        if !checked { checked = true; MontanaTrace.mark("tip_self", "ok=\(Self.selfCheck() ? 1 : 0)") }
        let own = lane()?.lane
        let token = MontanaHomeNode.hex(k.tip)
        var fresh: [MTCoinEntry] = [], lanes = 0, gap = false, broken = 0, answered = false
        for door in MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) {
            guard case let (200, o?) = await MTCoinVault.post(door + "/vault-get", ["token": token, "have": Array(opened.keys.prefix(256))], timeout: 6),
                  let held = o["held"] as? [String] else { continue }
            guard gen == MTCoinBook.generation else { MontanaTrace.mark("tip_get", "why=\(why) the seat moved -- nothing joined"); return }
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
        if 0 < joined || gap { MontanaTrace.mark("tip_get", kv) } else { MontanaTrace.markFolded("tip_get", kv, window: 60) }
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

/// THE VPN WALL, READ AS HISTORY (the author's words 04.10.2026 14:13-14:24 UTC began it: «while the VPN tunnel is on and alive, the
/// same auto minting as in the wallet»): up to the time cut the living tunnel's seconds were minted into this phone's book under this
/// name; since build 2320 nothing local mints (the author's decision 375 «a»). A living tunnel is presence, and presence is the
/// chain's to mint (fold-7, MTCoinTx.beHere): the tunnel's rise, the app's return and the wallet's opening tell the chain the person
/// is here and run the beat that shows its seconds (MTMintBeat).
enum MTVPNWallMint {
    static let refPrefix = "vpnwall:"
    /// The app stands in front of the person and a VPN is up -- Montana's tunnel or another app's (MTForeignVPN). Not «active» but
    /// «not in the background»: the scene's return reaches count() before the application's state turns active (T3 05.10 11:31Z).
    @MainActor static var wanted: Bool {
        UIApplication.shared.applicationState != .background && (MontanaVPNTunnel.shared.status == .connected || MTForeignVPN.link() != nil)
    }
    /// The app came to the screen, the wallet opened or the tunnel rose: the beat runs and the chain hears the person (fold-7).
    @MainActor static func count() { MTMintBeat.run(); MTCoinTx.beHere() }
}

/// THE PULL SWITCHES THE AUTO MINTING ON (the author's words 04.10.2026 00:52 and 01:18 UTC: «pulling the wallet's page, as the time
/// panel does, calls the coin for a forced refresh of the tops and the activation of the auto minting once a second»; «at such a
/// refresh switch the auto minting on: every second coins by the box's level»): a pull let go past the coin's trigger reads the tops
/// again and runs the beat that shows the chain's seconds while the wallet stands open (MTMintBeat); since build 2320 it mints
/// nothing itself (the author's decision 375 «a»).
/// THE PERSON ENDS IT, NO CLOCK (the author's word 04.10.2026 10:33 UTC: «it must not stop until I touch the coin myself or leave
/// the wallet's page -- it mints only while the wallet's screen is active, without taps on it, and deactivates at any action; all
/// three ran auto and stopped by themselves»; T2 10:29:49-10:30:49Z: on, then off by its window of sixty seconds): the page leaving and the
/// screen locked stop it; nothing else does -- no touch (the author's word 04.10.2026 21:53 UTC: «I did not touch; only leaving the
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
        MontanaTrace.mark("wallet_pull", "auto on")
        MTMintBeat.run()   // its seconds ride the one beat of the minting by the second (04.10 18:08)
    }
    /// The page left or the screen locked: the minting stops with it.
    func stop(why: String) {
        guard on else { return }
        on = false
        MontanaTrace.mark("wallet_pull", "auto off why=\(why)")
    }
    private func tellPairs(_ now: Double) {
        guard 15 <= now - told, let store = ChatStore.live else { return }
        told = now
        for c in store.listChats() where !c.isGroup { if let conv = c.convId { E2E.shared.tellBalance(to: conv) } }
    }
}

/// ONE BEAT FOR THE CHAIN'S SECONDS ON THE SCREEN (the author's word 04.10.2026 15:08 UTC, T2: «the minting's animation must not
/// double, only give the sum in the plus animation»; 23.10.2026 20:2x UTC: «in the client the minting shows just as before, only it
/// all happens at the core's level»): while the wallet's pull or a living VPN wants it, the beat raises the chain's seconds once a
/// second with their sum (MTCoinSplit.beat, MTCoinFlash.rise). It mints nothing (the author's decision 375 «a», build 2320) and
/// stops by itself when neither wants it.
@MainActor enum MTMintBeat {
    private static var beating: Task<Void, Never>?
    static var beats: Bool { beating != nil }
    static func run() {
        guard beating == nil else { return }
        beating = Task { @MainActor in
            while !Task.isCancelled {
                guard MTWalletPull.shared.on || MTVPNWallMint.wanted else { break }
                MTCoinSplit.shared.beat()
                try? await Task.sleep(nanoseconds: UInt64(MTCoinFlash.gather * 1_000_000_000))
                MTCoinFlash.shared.rise()
                try? await Task.sleep(nanoseconds: UInt64((1 - MTCoinFlash.gather) * 1_000_000_000))
            }
            beating = nil
            MTCoinFlash.shared.rise()   // the last second's coins rise too
        }
    }
}

/// THE TIMECHAINS OF THE MINTING (the author's words 03.10.2026 21:25 UTC: «in chess too its own TimeChain of the minting for
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
    /// ONE MOMENT, THE SAME ON EVERY DEVICE TO THE MILLISECOND (the author's word 06.10.2026 08:2x UTC: «everything to the millisecond,
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
        source(ref: r, kind: kind, peer: peer) { p in MTGroup.shared.kind(p) == .channel }
    }
    /// The same reading with the channels said by the caller: a fold off the screen's thread asks no live group (MTCoinHistory).
    static func source(ref r: String, kind: MTCoinEntry.Kind, peer: String?, channel: (String) -> Bool) -> String {
        if MTCoinLegacy.chess(r) { return "chess" }   // the book's chess lines of the builds before (MTCoinLegacy)
        if r.hasPrefix(MTPantheon.refPrefix) { return "pantheon" }
        if r.hasPrefix(MTVPNWallMint.refPrefix) { return "vpnwall" }
        if r.hasPrefix(MTVPNPay.refPrefix) { return "vpnpay" }
        if MTCoinLegacy.call(r) { return "calls" }
        if MTCoinLegacy.timer(r) { return "timer" }
        if MTBoardCoins.owns(r) { return "comments" }
        switch kind {
        case .earn:
            // A GROUP'S AND A CHANNEL'S COINS STAND IN THEIR OWN CHAINS (the author's words 06.10.2026 08:5x-09:0x UTC: «their own
            // TimeChain and their own app»): the letter's conversation names its chain.
            guard let p = peer, MTGroup.isKey(p) else { return "chats" }
            return channel(p) ? "channels" : "groups"
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
        case "vpnwall", "vpnpay": return .vpnWall
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
    /// THE WALL'S CHAIN (the author's word 03.10.2026 23:38 UTC): my wall's posts as they stand -- a post not yet chained joins as
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
            // THE LINKS OF A SECOND RIDE ONE WRITE (the author's word 04.10.2026 09:27 UTC, the heat of the minting): the seal is
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

// MARK: - THE CHAIN OF THE PERSON (the author's words 10.10.2026 10:4x, 12:0x and 12:2x UTC)

/// THE CHAIN OF THE PERSON COUNTS THE SECONDS THE WORDS WERE ON THE NETWORK (the author's word 10.10.2026 10:4x UTC: «in this
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
    /// THE GLOBAL LEVEL OF THE PERSON, THE ONE READING OF IT (the author's words 10.10.2026 12:0x UTC: «the lowest level among the
    /// chain of the person and the chain of the wallet becomes the Global Level of the person»; 17.10.2026 19:24 and 19:41 UTC: the
    /// third level, the Fabric of Time, «bears on the Global level by the rule of the minimum», «under the word level we mean only the
    /// global one»; Canon, «The level of a person»: min(p, w, f)): the lowest of the person's level, the wallet's level of π and the
    /// level of the fabric of time this turn (MTFabricLevel). A fabric this life has not read yet adds no third term -- an unknown
    /// level is never said as none. Every place that speaks of the person's level asks this and computes nothing of its own.
    nonisolated static func global(person: Int?, balance: Int) -> Int {
        MTFabricRules.levelOfPerson(person ?? 0, MTFabricRules.walletLevel(balance), MTFabricLevel.now ?? Int.max)
    }

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
        MTFabric.shared.prime()   // the third level is read with the first (MTFabric)
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
        MTPersonLevel.set(nil)
        MTFabric.shared.reread()   // the fabric of the person who left goes with their folder too
    }
    /// The seconds are read before a node's answer asks for them: a face that shows the level, and a word that says it, need them now.
    func prime() { load() }

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
        MTPersonLevel.set(level)
        MTFabric.shared.refresh()   // the ceiling stands on the person's level (MTFabric)
        MTLevelDistribution.shared.changed()
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
        if away != nil { away = nil; keep() }   // a leave kept by a build before 2320 is let go
        let from = last.flatMap { l in l <= s && s - l <= Self.reach ? l : nil } ?? s
        last = max(last ?? s, s)
        let before = seconds
        spans = Self.joined(spans + [Span(a: from, b: s)])
        recount()
        guard seconds != before else { return }
        dirty = true
        keepSoon()
    }

    /// THE APP LEAVING THE SCREEN ENDS THE STRETCH (the author's word 10.10.2026 12:0x UTC once paid the seconds away here, one coin
    /// each): since build 2320 nothing local mints (the author's decision 375 «a») -- absence is not presence, and the chain mints only
    /// while the person is here (fold-7).
    func left() {
        load()
        last = nil
    }

    // MARK: the devices of the words join their seconds: one sealed piece a device, beside the coin book on every node
    private static let aad = Data("mt.person.chain".utf8)   // NOT-UI: the words the piece's seal is bound to
    private struct Piece: Codable { var lane: String; var spans: [Span] }
    /// The wallet's live beat asks this every turn: the other devices' pieces every half minute, this device's union when it moved,
    /// once a minute at most.
    func tick() async {
        load()
        if !checked { checked = true; MontanaTrace.mark("person_self", "ok=\(Self.levelKAT() ? 1 : 0) fabric=\(MTFabricRules.selfCheck() ? 1 : 0)") }
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
        MontanaTrace.markFolded("person_put", "spans=\(spans.count) seconds=\(seconds) doors=\(laid)", window: 60)
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
            MontanaTrace.markFolded("person_get", "seconds=\(seconds) level=\(level ?? -1) joined=\(seconds - before)", window: 60)
            return
        }
    }
}

// MARK: - THE FABRIC OF TIME (the author's words 17.10.2026 19:24, 19:41, 19:50 and 20:18 UTC)

/// THE RULES OF THE FABRIC OF TIME, AS THE CORE STATES THEM (the author's words 17.10.2026 19:24 UTC: «the 3rd level is the count of
/// levels of the chats real with regular calls over the last 14 days -- t2 -- and it bears on the Global level by the rule of the
/// minimum»; 19:41: «one's own is one's own global level»; 19:50: «a new level that sets the global one, named Fabric of Time»;
/// 17.10.2026 21:4x: «not tied to the turns of t2 -- the current result of a sliding window of t2 over live activity: chats, calls,
/// transfers, chess, games, video, audio, media, stickers, GIFs»; 07:2x: a correspondent weighed by their ceiling, «yes, do it»;
/// Canon, «The level of the wallet», «The level of the fabric of time», «The half of the fabric», «The level of a person», «The
/// testimony of an exchange»). Byte for byte the core's mt-derive levels.rs -- the same functions and the same frozen vectors
/// (selfCheck) -- so a phone and a node that read one testimony name it by one identifier.
enum MTFabricRules {
    /// A call is a live act of the fabric when each side received the other's voice this long (Canon, call_seconds).
    static let callSeconds = 60
    /// τ₂ and its half (Canon, «The half of the fabric»): the last τ₂ is two halves, and a regular correspondent stands in each.
    static let tau2Windows = UInt64(MontanaNames.tau2Windows)
    static let halfWindows = tau2Windows / 2
    /// A segment, Genesis segment_windows (τ₂ / 14): a signer gives one addressee one testimony a segment, a holder keeps one.
    static let segmentWindows = tau2Windows / 14
    static let suite: UInt16 = 1             // Canon, the suite table: row 1, ML-DSA-65
    static let signatureLength = 3309        // Canon, the suite table: the signature of row 1
    static let scopeLength = 43              // Canon, «The testimony of an exchange»: 2 + 32 + 8 + 1
    static let testimonyLength = 3352        // Canon, testimony_len
    static let mostLevels = 19               // Canon: the most levels the wallet holds, which no ceiling exceeds

    /// The level of the wallet (Canon: the count of the prefixes of π the balance reaches): MTPiLevels.place, its one reading.
    static func walletLevel(_ balance: Int) -> Int { MTPiLevels.place(balance) }
    /// H: the greatest g for which at least g of the values stand at g or above. It counts people, not weight, in any order.
    static func fabricLevel(_ values: [Int]) -> Int {
        var level = 0
        for value in values.sorted(by: >) {
            if value <= level { break }
            level += 1
        }
        return level
    }
    /// The half of the last τ₂ a testimony stands in: 0 the newer, 1 the older, 2 and beyond out of the window. The difference
    /// saturates, so a testimony one window ahead of the reading stands in 0.
    static func half(_ now: UInt64, _ window: UInt64) -> UInt64 { (window < now ? now - window : 0) / halfWindows }
    static func segment(_ window: UInt64) -> UInt64 { window / segmentWindows }
    /// The level of a person: the lowest of the three, never a sum or a mean of them.
    static func levelOfPerson(_ person: Int, _ wallet: Int, _ fabric: Int) -> Int { min(person, wallet, fabric) }
    static func weaves(_ heard: Int) -> Bool { callSeconds <= heard }
    /// A LIVE ACT (App, «The fabric of time a client weighs»): what stands in a conversation -- words, voice and video messages,
    /// photographs, files and media, stickers and animations, transfers, a game's moves -- never a receipt, a sign of typing or of
    /// presence, a group's word or the fabric's own; a call is one when it weaves (MTFabric.callClosed).
    nonisolated static func isLiveAct(_ text: String) -> Bool {
        guard !text.hasPrefix(MTGroup.mark) else { return false }
        return !isControlMarker(text) || text.hasPrefix(mediaMark) || text.hasPrefix(voiceMark) || text.hasPrefix(stickerMark)
            || text.hasPrefix(appMark)
    }
    /// DEVIATION (Canon, «The half of the fabric»: «w is the network's window as the device read it from the network»): a phone holds
    /// no window of the core, so its window is the nodes' second -- learned from their answers (MontanaWakePush.nodeNow), the seconds
    /// the chain of the person counts too (MTPersonChain.answered) -- over sixty, counted from the Unix epoch.
    static func windowNow() -> UInt64 { UInt64(max(0, MontanaWakePush.nodeNow())) / MTPipe.windowSeconds }

    /// THE FAR VOICE, AS THIS PHONE RECEIVED IT (App: «A call weaves when each side received the other's voice for at least
    /// call_seconds»): one stretch of the engine's received voice stream -- its played seconds, their energy, the samples received and
    /// the ones the engine made up for packets that never came. A stretch counts when its level stands at a voice's floor or above, and
    /// only by the share of it that was received: a muted microphone sends silence, which carries no energy, and a broken road is
    /// made-up samples -- neither is a voice. The floor is -40 dBov (level 0.01): speech stands near -26 dBov, a quiet room and the
    /// engine's comfort noise near -60 and below, so a stretch holding spoken words stands above it and a silent one below.
    static let voiceFloor = 0.01
    static func voiced(seconds: Double, energy: Double, received: Double, concealed: Double) -> Double {
        guard 0 < seconds, 0 < received, 0 <= energy, voiceFloor <= (energy / seconds).squareRoot() else { return 0 }
        return seconds * max(0, min(1, (received - concealed) / received))
    }

    /// What a correspondent signs on a live act received from the person (Canon, «The testimony of an exchange»; levels.rs, Testimony).
    struct Testimony: Equatable {
        enum Refusal: String { case ceilingBeyondTheWallet }
        var suite: UInt16
        var addressee: Data
        var window: UInt64
        var ceiling: UInt8
        /// The signed scope: every field before the signature, unsigned and little-endian, in the canonical order.
        var scope: Data {
            var out = Data()
            out.append(contentsOf: [UInt8(suite & 0xFF), UInt8(suite >> 8)])
            out.append(addressee)
            out.append(contentsOf: (0..<8).map { i in UInt8((window >> (8 * UInt64(i))) & 0xFF) })
            out.append(ceiling)
            return out
        }
        /// testimony_id = SHA-256("mt-exchange-testimony" || 0x00 || signed_scope), by the tree's one composition (MTPipe.domained).
        var id: Data { MTPipe.domained("mt-exchange-testimony", [scope]) }
        /// What it states of itself that a holder refuses before anything else is asked (levels.rs, refusal).
        var refusal: Refusal? { MTFabricRules.mostLevels < Int(ceiling) ? .ceilingBeyondTheWallet : nil }
        /// The testimony and its signature; one of any other length than testimony_len is refused before it is parsed (Canon).
        static func parse(_ bytes: Data) -> (Testimony, Data)? {
            let b = [UInt8](bytes)
            guard b.count == MTFabricRules.testimonyLength else { return nil }
            func le(_ at: Int, _ n: Int) -> UInt64 { (0..<n).reduce(UInt64(0)) { v, i in v | UInt64(b[at + i]) << (8 * UInt64(i)) } }
            let t = Testimony(suite: UInt16(le(0, 2)), addressee: Data(b[2..<34]), window: le(34, 8), ceiling: b[42])
            return (t, Data(b[MTFabricRules.scopeLength...]))
        }
    }

    /// THE FROZEN VECTORS (Canon, «Frozen vectors»), each named by the wrong reading it refuses: a wallet of 3 and of 314 refuse a
    /// strict comparison, 313 a count of digits, the nineteenth prefix a level capped at the thirteen a page shows; H(5) refuses a
    /// weight, H(2 x 6) a count of correspondents, H(9, 1, 7, 2, 6) values read as already sorted, H() a person who writes to nobody
    /// left without an answer; the age 10079 refuses a half rounded upward, 10080 a boundary drawn after half of τ₂ (and, its windows
    /// exchanged, a subtraction the other way), 20160 a window keeping a testimony τ₂ old; the level of a person refuses a dropped
    /// fabric, a first or a last term, a mean; the testimony's eight distinct bytes of its window refuse a big-endian window and its
    /// ceiling after the window a ceiling written first; a parse that misplaces a field gives another testimony back; the voice
    /// refuses a level read as its energy (0.05 counts, 0.0025 would not), a floor left out (0.001 counts nothing) and made-up samples.
    static func selfCheck() -> Bool {
        guard walletLevel(2) == 0, walletLevel(3) == 1, walletLevel(313) == 2, walletLevel(314) == 3,
              walletLevel(3_141_592_653_589_793_238) == 19 else { return false }
        guard fabricLevel([]) == 0, fabricLevel([5]) == 1, fabricLevel([3, 3, 3]) == 3, fabricLevel([9, 1, 7, 2, 6]) == 3,
              fabricLevel([2, 2, 2, 2, 2, 2]) == 2 else { return false }
        guard halfWindows == 10_080, segmentWindows == 1_440, half(20_160, 10_081) == 0, half(20_160, 10_080) == 1,
              half(20_160, 0) == 2, half(10_080, 20_160) == 0 else { return false }
        guard levelOfPerson(20, 5, 3) == 3, levelOfPerson(7, 2, 9) == 2, levelOfPerson(0, 9, 9) == 0 else { return false }
        var t = Testimony(suite: 1, addressee: Data(repeating: 0x22, count: 32), window: 0x0102_0304_0506_0708, ceiling: 9)
        let signature = Data(repeating: 0x5A, count: signatureLength)
        guard t.scope.count == scopeLength, t.refusal == nil,
              t.id.montanaHexString == "ea5deddd35b6355762867a5e744e4d3fdc76c3e72d9e70d17d5907a3b056d5da",
              let back = Testimony.parse(t.scope + signature), back.0 == t, back.1 == signature,
              Testimony.parse(t.scope) == nil else { return false }
        t.ceiling = 19
        guard t.refusal == nil else { return false }
        t.ceiling = 20
        guard t.refusal == .ceilingBeyondTheWallet else { return false }
        guard voiced(seconds: 2, energy: 2 * 0.05 * 0.05, received: 96_000, concealed: 0) == 2,
              voiced(seconds: 2, energy: 2 * 0.05 * 0.05, received: 96_000, concealed: 48_000) == 1,
              voiced(seconds: 2, energy: 2 * 0.001 * 0.001, received: 96_000, concealed: 0) == 0,
              voiced(seconds: 2, energy: 0, received: 96_000, concealed: 0) == 0 else { return false }
        return true
    }
}

/// THE FABRIC'S WORD FOR A READER OFF THE MAIN ACTOR (MTPersonChain.global, the call's caps): the level of the fabric now and the
/// person's own ceiling as every testimony states it -- written by MTFabric at every reading; nil until this life has read them, so an
/// unknown level is never said as none.
enum MTFabricLevel {
    private static let lock = NSLock()
    private static var held: Int?
    private static var told: Int?
    static var now: Int? { lock.lock(); defer { lock.unlock() }; return held }
    static var ceiling: Int? { lock.lock(); defer { lock.unlock() }; return told }
    static func set(_ level: Int?, ceiling: Int?) { lock.lock(); held = level; told = ceiling; lock.unlock() }
}

/// ONE CALL AS THE FABRIC WEIGHS IT (App, «The fabric of time a client weighs»), kept by the call machine for every call it holds, by
/// the call's name: the identifier its caller drew and its setup carried, the window the call stood from, and the seconds of the far
/// voice this phone received (MTFabricRules.voiced).
struct MTWeave {
    var call: Data?
    var from: UInt64?
    var heard: Double = 0
    var seen: [String: [Double]] = [:]   // a received stream's last counters: seconds, energy, received, made up
    /// A received stream's counters now: what they grew by since that stream's last sample is weighed, and nothing else.
    mutating func hears(_ id: String, seconds: Double, energy: Double, received: Double, concealed: Double) {
        let last = seen[id] ?? [0, 0, 0, 0]
        seen[id] = [seconds, energy, received, concealed]
        let ds = seconds - last[0], de = energy - last[1], dr = received - last[2], dc = concealed - last[3]
        guard 0 < ds, 0 <= de, 0 < dr, 0 <= dc else { return }
        heard += MTFabricRules.voiced(seconds: ds, energy: de, received: dr, concealed: dc)
    }
}

/// THE FABRIC OF TIME OF THIS SEED ON THIS PHONE (App, «The fabric of time a client weighs»; Identity, «The fabric of time»): the
/// testimonies of exchanges the person's correspondents gave, the window this phone last spoke to each correspondent and the
/// segment it last gave each a testimony in, the hash each correspondent told it to name them by, and the level of the fabric --
/// H over the values of the correspondents regular in the window that slides with the network's, a value being the lowest ceiling a
/// correspondent stated in the testimonies of the last τ₂; through the first τ₂ of the fabric on this seed, the ceiling. A
/// correspondent is told apart by the key its testimonies verify under (the hash its fingerprint is read from), and by nothing it
/// states of itself. One file beside the seconds of the person, at the same protection (TimeChain/fabric-v2.json); one link at
/// every change of the level in its chain (TimeChain/wallet-fabric.jsonl), sealed as every chain. What it holds lives τ₂ and then
/// leaves ([I-14]): a testimony counts in the two halves of the last τ₂ and nowhere after them.
///
/// THE CORRESPONDENCE A TESTIMONY STANDS ON (Canon, «The testimony of an exchange»: its addressee is the value the thirty digits two
/// people compare out of band are read from, and it is signed by the key the two of them compare). The two of this client compare the
/// fingerprint of the correspondence's secret (MTPipe.fingerprint, a deviation named in Audit/AUDIT.md), so the addressee is that hash,
/// computed by both ends from the secret alone and told by neither -- a testimony handed to a third person names a correspondence that
/// person does not hold -- and the signer's key is drawn from the seed for that correspondence alone, the same on every device of the
/// seed. [I-17]: no key and no value of a testimony is the same in two correspondences, so none names the person to anyone else.
@MainActor final class MTFabric: ObservableObject {
    static let shared = MTFabric()
    struct Held: Codable { var id: String; var key: String; var conv: String; var window: UInt64; var ceiling: Int; var body: String }
    struct Change: Codable { var window: UInt64; var level: Int; var digest: String }
    private struct Kept: Codable {
        var opened: UInt64?                  // the window the fabric opened in on this seed
        var held: [Held] = []
        var keys: [String: String] = [:]     // the hash a fingerprint is read from: the key its testimonies verify under
        var sent: [String: UInt64] = [:]     // a pipe: the window this phone last left a live act on it
        var given: [String: UInt64] = [:]    // a pipe: the segment this phone last gave a testimony on it
        var changes: [Change] = []
    }
    @Published private(set) var level: Int?
    @Published private(set) var ceiling: Int?
    @Published private(set) var regulars = 0
    @Published private(set) var testimonies = 0
    @Published private(set) var graceDays: Int?
    @Published private(set) var links: [MTTimeChain.Link] = []
    private var kept = Kept()
    private var loaded = false, keepDue = false
    private static var file: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("fabric-v2.json") }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let u = Self.file, let d = try? Data(contentsOf: u), let k = try? JSONDecoder().decode(Kept.self, from: d) { kept = k }
        links = Self.chain(kept.changes)
    }
    private func keep() {
        guard loaded, let u = Self.file, let d = try? JSONEncoder().encode(kept) else { return }
        try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    private func keepSoon() {
        guard !keepDue else { return }
        keepDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.keepDue = false; self?.keep() }
    }
    /// A person lifted into the seat: the fabric of the person who left goes with their folder; the seated person's is read next.
    func reread() {
        loaded = false; kept = Kept()
        level = nil; ceiling = nil; regulars = 0; testimonies = 0; graceDays = nil; links = []
        pairs = [:]
        MTFabricLevel.set(nil, ceiling: nil)
    }
    /// The fabric is read before a level is asked of it.
    func prime() { load() }
    /// The hash a correspondence's fingerprint is read from (MTPipe.fingerprintMaterial over its secret): the addressee of every
    /// testimony on it, both ways. Derived once, at the pipe's birth, and kept by the book (MTPipeKept).
    private var pairs: [String: Data] = [:]
    private func pair(_ conv: String) -> Data? {
        if let m = pairs[conv] { return m }
        guard let m = MTPipeBook.kept(for: conv)?.fingerprint else { return nil }
        pairs[conv] = m
        return m
    }
    /// The key this person signs a correspondence's testimonies with: HKDF-Expand(master_seed, "mt-fabric-key", 0x00 and the
    /// correspondence's hash, 32) into ML-DSA-65 -- one on every device of the words, another in every correspondence, and no relation
    /// to the account's key or the coins'.
    nonisolated static func signer(pair: Data) -> (pk: Data, sk: Data)? {
        guard pair.count == 32, let words = MontanaSeed.mnemonic, let master = MontanaQueueKeys.masterSeed(words), master.count == 64 else { return nil }
        let info = [UInt8](Data("mt-fabric-key".utf8) + Data([0]) + pair)
        var seed = [UInt8](repeating: 0, count: 32)
        let rc = master.withUnsafeBytes { m -> Int32 in
            info.withUnsafeBufferPointer { r -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, r.baseAddress, info.count, &seed)
            }
        }
        guard rc == 0 else { return nil }
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        guard mt_mldsa_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return (Data(pk), Data(sk))
    }

    /// THE READING (App): the ceiling, the regular correspondents and their values, the level -- again whenever what they stand on
    /// moved: the person's seconds, the balance, a testimony coming or leaving the window. A handful of testimonies: it costs nothing.
    func refresh() {
        load()
        let w = MTFabricRules.windowNow()
        guard 0 < w else { return }   // the nodes' clock not heard yet: no window to read in
        var moved = prune(w)
        if kept.opened == nil { kept.opened = w; moved = true }
        var ceil: Int? = nil
        if let p = MTPersonLevel.now, let b = MTCoinBalance.now { ceil = min(MTFabricRules.mostLevels, p, MTFabricRules.walletLevel(b)) }
        let opened = kept.opened ?? w
        let grace = w < opened + MTFabricRules.tau2Windows
        let regs = regulars(w)
        // THE LEVEL: through the first τ₂ the ceiling; past it H over the regulars' values, read now -- no turn, no estimate.
        let lvl: Int? = grace ? ceil : MTFabricRules.fabricLevel(regs.map { k in value(k, w) })
        if let l = lvl, kept.changes.last?.level != l {
            kept.changes.append(Change(window: w, level: l, digest: digest(regs, w)))
            moved = true
            links = Self.chain(kept.changes)
            writeChain()
            MontanaTrace.mark("fabric_level", "level=\(l) regulars=\(regs.count) grace=\(grace ? 1 : 0)")
        }
        MTFabricLevel.set(lvl, ceiling: ceil)
        let left = Double((opened + MTFabricRules.tau2Windows) * MTPipe.windowSeconds) - MontanaWakePush.nodeNow()
        let days: Int? = grace ? max(1, Int((left / 86_400).rounded(.up))) : nil
        let count = kept.held.filter { h in MTFabricRules.half(w, h.window) < 2 }.count
        if level != lvl { level = lvl }
        if ceiling != ceil { ceiling = ceil }
        if regulars != regs.count { regulars = regs.count }
        if testimonies != count { testimonies = count }
        if graceDays != days { graceDays = days }
        if moved { keepSoon() }
    }
    /// The correspondents regular now: a testimony from them in each half of the last τ₂ (Canon, «The half of the fabric»).
    private func regulars(_ w: UInt64) -> [String] {
        var halves: [String: Set<UInt64>] = [:]
        for h in kept.held {
            let x = MTFabricRules.half(w, h.window)
            if x < 2 { halves[h.key, default: []].insert(x) }
        }
        return halves.filter { e in e.value.count == 2 }.keys.sorted()
    }
    /// A correspondent's value: the lowest ceiling they stated in the testimonies of the last τ₂.
    private func value(_ key: String, _ w: UInt64) -> Int {
        kept.held.filter { h in h.key == key && MTFabricRules.half(w, h.window) < 2 }.map(\.ceiling).min() ?? 0
    }
    /// The set a change of the level stood on as its link names it: SHA-256 over the identifiers of the regulars' testimonies in the
    /// window, sorted -- a value of this device alone, never on the wire (LOCAL-HASH-OK), so two readings of one set give one link.
    private func digest(_ regs: [String], _ w: UInt64) -> String {
        let on = Set(regs)
        let ids = kept.held.filter { h in on.contains(h.key) && MTFabricRules.half(w, h.window) < 2 }.map(\.id).sorted()
        return SHA256.hash(data: Data(ids.joined(separator: "\n").utf8)).map { b in String(format: "%02x", b) }.joined()
    }
    /// [I-14]: a testimony leaves at its half 2, a pipe's marks a τ₂ after they were made; a key leaves with its last testimony.
    private func prune(_ w: UInt64) -> Bool {
        let before = (kept.held.count, kept.sent.count, kept.given.count)
        kept.held.removeAll { h in 2 <= MTFabricRules.half(w, h.window) }
        kept.sent = kept.sent.filter { e in MTFabricRules.half(w, e.value) < 2 }
        kept.given = kept.given.filter { e in MTFabricRules.half(w, e.value * MTFabricRules.segmentWindows) < 2 }
        let keys = Set(kept.held.map(\.key))
        kept.keys = kept.keys.filter { e in keys.contains(e.key) }
        if 200 < kept.changes.count { kept.changes.removeFirst(kept.changes.count - 200) }
        return before != (kept.held.count, kept.sent.count, kept.given.count)
    }
    /// One link at every change of the level, named by its window and the set it stood on, sealed on the one before
    /// (MTTimeChain.seal); its moment is the window on the nodes' clock, so the same changes give the same chain.
    nonisolated static func chain(_ changes: [Change]) -> [MTTimeChain.Link] {
        var out: [MTTimeChain.Link] = [], prev = MTTimeChain.genesis
        for c in changes {
            let n = out.count + 1, at = Int64(c.window * MTPipe.windowSeconds) * 1000
            let ref = "w:" + String(c.window) + ":" + String(c.digest.prefix(16))
            let hash = MTTimeChain.seal(n: n, at: at, k: "level", c: c.level, ref: ref, prev: prev)
            out.append(MTTimeChain.Link(n: n, at: at, k: "level", c: c.level, ref: ref, prev: prev, hash: hash))
            prev = hash
        }
        return out
    }
    private func writeChain() {
        guard let u = MTTimeChainPlace.file("fabric") else { return }
        var body = Data()
        for l in links { if let d = try? JSONEncoder().encode(l) { body.append(d); body.append(0x0A) } }
        try? body.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// A LIVE ACT THIS PHONE LEFT FOR A CORRESPONDENT (App: a testimony is given «while it has itself sent that correspondent a live act
    /// within the last half of τ₂»): the window it last spoke on the pipe (MontanaDeliveryEngine.enqueue, MTFabricRules.isLiveAct).
    func spoke(_ conv: String) {
        guard !conv.isEmpty, !MTGroup.isKey(conv) else { return }
        load()
        let w = MTFabricRules.windowNow()
        guard 0 < w, kept.sent[conv] != w else { return }
        kept.sent[conv] = w
        keepSoon()
    }
    /// A LIVE ACT CAME FROM A CORRESPONDENT (App, «When a testimony is given»): when this phone spoke to them within the last half of τ₂
    /// and gave them no testimony this segment, it signs one -- the window it heard them in and its own ceiling -- naming the
    /// correspondence by the hash its secret gives, and gives it by the pair's own road, inside what only they open. A person who only
    /// writes is given none.
    func heard(_ conv: String) {
        guard !conv.isEmpty, !MTGroup.isKey(conv) else { return }
        prime()
        let w = MTFabricRules.windowNow()
        guard 0 < w, let s = kept.sent[conv], MTFabricRules.half(w, s) == 0 else { return }
        let seg = MTFabricRules.segment(w)
        guard kept.given[conv] != seg else { return }
        guard let named = pair(conv) else {
            return MontanaTrace.markFolded("fabric_tx", "held: no secret of the correspondence here", window: 600, key: conv)
        }
        guard let c = MTFabricLevel.ceiling else { return MontanaTrace.mark("fabric_tx", "held: this life has not read its own levels yet") }
        let t = MTFabricRules.Testimony(suite: MTFabricRules.suite, addressee: named, window: w, ceiling: UInt8(clamping: c))
        kept.given[conv] = seg
        keepSoon()
        let scope = t.scope
        Task.detached(priority: .utility) {
            guard let k = MTFabric.signer(pair: named), let sig = MontanaSeedKeys.sign(scope, seckey: k.sk), sig.count == MTFabricRules.signatureLength,
                  let d = try? JSONSerialization.data(withJSONObject: ["t": (scope + sig).base64EncodedString(), "k": k.pk.base64EncodedString()]),
                  let body = String(data: d, encoding: .utf8) else {
                MontanaTrace.mark("fabric_tx", "FAIL the seed's key did not sign")
                return
            }
            await MainActor.run {
                MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: ChatStore.mintMid().mid, text: fabricMark + body, silent: true)
                MontanaTrace.mark("fabric_tx", "to=\(String(conv.prefix(10))) ceiling=\(t.ceiling)")
            }
        }
    }
    /// A CALL OF TWO CLOSED (App: «a call that wove» is a live act): a call this phone heard the far voice in for a minute or more is a
    /// live act both ways -- this side spoke in it and heard.
    func callClosed(conv: String, weave: MTWeave) {
        let heardSeconds = Int(weave.heard)
        MontanaTrace.mark("fabric_call", "heard_s=\(heardSeconds)")
        guard MTFabricRules.weaves(heardSeconds), !conv.isEmpty else { return }
        spoke(conv)
        heard(conv)
    }

    /// THE FABRIC'S WORD CAME (Canon, «Invariants of a testimony»): a testimony of an exchange. It counts only once every question is
    /// answered, in this order -- its length, what it states of itself, that it names this correspondence, that its window stands no more than
    /// one window past this phone's reading and inside the last τ₂, that its signature holds under the key it came with. One a segment
    /// from one key is kept, the one stating the lower ceiling: a second adds nothing (Canon).
    func received(_ payload: String, from conv: String, at: Double) {
        prime()
        guard let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            return refuse("unreadable", conv)
        }
        guard o["t"] != nil else { return }   // a word of an older build: a ceiling and an estimate, which this fabric does not weigh
        guard let body = (o["t"] as? String).flatMap({ s in Data(base64Encoded: s) }),
              let key = (o["k"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { return refuse("unreadable", conv) }
        guard let parsed = MTFabricRules.Testimony.parse(body) else { return refuse("length", conv) }
        let t = parsed.0, sig = parsed.1
        guard t.suite == MTFabricRules.suite else { return refuse("suite", conv) }
        if let r = t.refusal { return refuse(r.rawValue, conv) }
        guard let held = pair(conv), t.addressee == held else { return refuse("addressee", conv) }
        let w = MTFabricRules.windowNow()
        guard t.window <= w + 1 else { return refuse("window", conv) }
        guard MTFabricRules.half(w, t.window) < 2 else { return }   // older than the window: it counts nothing
        guard MontanaPQ.verify(pubkey: key, message: t.scope, signature: sig) else { return refuse("signature", conv) }
        let id = t.id.montanaHexString
        guard !kept.held.contains(where: { h in h.id == id }) else { return }
        let signer = MTPipe.fingerprintMaterial(key).montanaHexString
        let seg = MTFabricRules.segment(t.window)
        if let i = kept.held.firstIndex(where: { h in h.key == signer && MTFabricRules.segment(h.window) == seg }) {
            guard Int(t.ceiling) < kept.held[i].ceiling else { return }
            kept.held.remove(at: i)
        }
        kept.held.append(Held(id: id, key: signer, conv: conv, window: t.window, ceiling: Int(t.ceiling), body: body.base64EncodedString()))
        kept.keys[signer] = key.base64EncodedString()
        keep()
        refresh()
        MontanaTrace.mark("fabric_rx", "ceiling=\(t.ceiling) half=\(MTFabricRules.half(w, t.window))")
    }
    private func refuse(_ why: String, _ conv: String) {
        MontanaTrace.mark("fabric_refused", "why=\(why) from=\(String(conv.prefix(10)))")
    }
}

// MARK: - THE COIN CORE OF THE APP (the author's words 03.10 10:40, 10:52 and 10:53 UTC)

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
    /// A NAME A RESTORE GIVES A LETTER NAMES NO MOVE (the author's words 09.10.2026 08:3x-08:4x UTC: "the balance swelled, this person
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
    /// 05.10.2026 19:29 UTC, «in ordinary chats take away the coin under every message as a reaction», takes it from the bubbles
    /// sent before too, on both phones; the coins stay where the book moved them.
    var shownOn: String? {
        ref.hasPrefix(MTCoinSend.bubblePrefix) || ref.hasPrefix(MTCoinSend.receivedPrefix + MTCoinSend.bubblePrefix) ? nil : on
    }
    /// The coins this move stands under its letter with: a SEND that came back (MTCoinTx.backPrefix) is laid under the letter its
    /// SEND stood under and takes its coins from there, so a paid reaction no node took shows nothing under the letter.
    var shownCoins: Int { ref.hasPrefix(MTCoinTx.backPrefix) ? -c : c }
}

/// THE ONE DOOR OF THE COINS (the author's word 03.10 13:52: «an in-app coin core with no crypto core, behind one
/// protocol»). Every reader and writer of coins in the app speaks to this and to nothing else: the wallet, the paid
/// reactions, the coin letters in a chat. THE SEAM FOR THE REAL MONEY IS THIS PROTOCOL: the day the
/// protocol core opens this person's wallet and offers a door that mints for a letter and transfers between wallets
/// (montana_core.h has neither today), a second implementation answers here and MTCoinBook.ledger names it -- nothing
/// that calls these doors changes. Until then the book is LOCAL: kept on this phone, never a note of the core's wallet.
@MainActor protocol MTCoinLedger: AnyObject {
    var balance: Int { get }
    var entries: [MTCoinEntry] { get }
    // NO DOOR OF THE BOOK MINTS (the author's decision 375 «a», build 2320): earn, mint and the window of τ1 are gone -- only the
    // chain mints, 1 coin is 1 second (the word 11871); the old earned lines stand in the book as history.
    // NO DOOR OF THE BOOK BURNS (decision 383 «a», build 2322): a comment's four of five were the last burn; the old burned lines
    // stand in the book as history.
    /// Coins given on a letter or a post; refused (false) when the balance is short or the name was taken.
    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool
    /// Coins sent to a person in a coin letter; refused (false) when the balance is short or the name was taken.
    func send(_ coins: Int, to peer: String, ref: String) -> Bool
    /// Coins that arrived, credited once by their name; false when the name was taken already.
    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool
    /// How many coins stand on a letter or a post, given and received alike.
    func coins(on target: String) -> Int
}

/// THE TIMECHAIN FOLDER (the author's words 04.10.2026 10:42 UTC: «in the Montana folder make a folder TimeChain, so I see it on all
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
        if 0 < moved { MontanaTrace.mark("timechain_place", "laid=\(moved)") }
    }
}

/// THE BOOK'S CHESS LINES OF THE BUILDS BEFORE (COMPAT-LOCAL; the author's word 29.10.2026 19:31 UTC: «in chess there must be no
/// crediting of coins»): chess and its Timer write no coin; the names their lines carried in the book of the builds before are read
/// here only so a person's history keeps telling where those coins came from. Nothing here writes or moves a coin.
enum MTCoinLegacy {
    nonisolated static let chessNames = ["chess:", "chess-won:", "chess-lost:", "chess-pot:", "chess-stake:", "chess-back:"]
    nonisolated static func chess(_ ref: String) -> Bool { chessNames.contains { ref.hasPrefix($0) } }
    nonisolated static func timer(_ ref: String) -> Bool { ref.hasPrefix("timer:") }   // COMPAT-LOCAL: a name of this phone's own book, never a word on the wire
    /// A call's seconds minted by the builds before (the author's word 29.10.2026 19:31 UTC: «and at a call too»); a call writes no coin.
    nonisolated static func call(_ ref: String) -> Bool { ref.hasPrefix("callmint:") }   // COMPAT-LOCAL: a name of this phone's own book, never a word on the wire
}

/// The app's one book of coins, today (see MTCoinLedger for the seam).
enum MTCoinBook {
    @MainActor static var ledger: any MTCoinLedger { MTLocalCoinLedger.shared.whole }
    /// THE SMALL SPEND (the wallet's history folds them, MTWalletScreen): a coin on a letter or a post carries at most thirteen.
    /// Not a rate: since 19.10.2026 a second of life mints one coin, all minting together (price, below).
    static let smallSpend = 13
    /// THE PRICE OF A SECOND, THE ONE OWNER OF THE FUNCTION «1 COIN = 1 SECOND» (point 11; the author's words 05.10.2026 11:17 UTC:
    /// «a second = 1 coin everywhere»; 19.10.2026 12:3x: «the ceiling, the invariant -- nothing else can mint or accelerate it»;
    /// 13:4x: «one owner of the function 1 coin = 1 second, and that is all»): one coin, the most a second mints, every door
    /// together (MTLocalCoinLedger.priced) -- a person's hour is 3 600 coins and their personal rate is read by it (MTHourWorth, MTPersonalRate).
    static let price = 1
    /// THE TICKER OF THE MONTANA TIME COIN (the constitution of the chain, point 12, the author's word 04.10.2026 14:31 UTC): one
    /// symbol in every language, beside the balance.
    static let ticker = "$TCM"
    /// THE BOOK'S GENERATION (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's second point): one
    /// more at every seat's move, before anything is read again. A gather begun under the person who left took their key, waited on
    /// the nodes, and then read the book of the person seated -- laying it over every piece of the old seed (the whole book lost
    /// to a restore on another phone). A gather compares this after every wait and writes nothing once it moved.
    @MainActor static private(set) var generation = 0
    /// A PERSON LIFTED INTO THE SEAT READS THEIR OWN COINS (the author's word 04.10.2026 00:38 UTC): every owner of coins on this phone
    /// lets the person who left go and reads the folder of the person seated (MTCoinPlace) -- the chains first, so the book's past
    /// joins the seated person's chains.
    @MainActor static func reread() {
        generation &+= 1
        MTCoinVault.shared.forget()
        MTTimeChainTip.shared.reread()
        MTTimeChain.forget()
        MTPersonChain.shared.reread()
        MTLocalCoinLedger.shared.reread()
        MTCoinBoard.shared.reread()
        MontanaTrace.mark("coin_book", "reread")
    }
    /// A SEAT BEGINS TO MOVE (MTSeats.parkThenLift, in the same turn as the last write of the person leaving and before their folder
    /// moves): from this instant no walk of the chain begun under them writes anything (MTCoinSeat).
    @MainActor static func leave() { generation &+= 1 }
    /// NO LIMIT BUT THE BALANCE AND ONE AT LEAST (the author's word 03.10): a move of any whole number of coins from one up; the
    /// one bound is the arithmetic's -- the count must still fit the book's integer beside the balance -- never a rule of the coin.
    static func fits(_ coins: Int, beside balance: Int) -> Bool { 0 < coins && !balance.addingReportingOverflow(coins).overflow }
}

/// A WALK OF THE CHAIN WRITES ONLY ITS OWN PERSON (the critic 19.10.2026 on T2; the author's words 20:25 «a separate person, wholly
/// separate, with none of this mixing» and 20:4x «build by the constitution with chains of time, strictly with no races allowed»): a
/// walk asks the nodes and waits, and a seat that moves during the wait seats another person behind the same book, the same folder
/// and the same key's name. The walk takes its seat at its first step; after every wait it reaches the book, the person's files and
/// the records it signs only through that seat. Once the seat moved it writes nothing: what it had begun waits in the folder of its
/// own person, which moved with them, and their own walks decide it when they sit again.
@MainActor struct MTCoinSeat {
    let generation = MTCoinBook.generation
    var stands: Bool { generation == MTCoinBook.generation }
    var book: MTLocalCoinLedger? { stands ? MTLocalCoinLedger.shared.whole : nil }
}

/// THE LOCAL BOOK: one line of JSON per move, appended, in Application Support (protected until the first unlock, as the
/// chat coins' names are). The balance and the totals are the sum of the lines, recounted at launch -- the file is the one
/// truth, the numbers are its reading.
/// THE PERSON'S COINS LIVE IN THE PERSON'S FOLDER (the author's word 04.10.2026 00:38 UTC: «I came in with another account on T1,
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
    /// THE BOOK OF A PERSON FORGOTTEN LEAVES WITH THEM (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
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
        MontanaTrace.mark("coin_place", "forgotten set aside=\(moved)/\(names.count)")
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
        // A BOOK WHOSE OWNER IS NOT KNOWN STAYS WHERE IT STANDS (the author's word «fix all points in order» 05.10.2026 18:4x UTC,
        // the coin audit's seventh point): born is written at a seat's first move -- after the book's first move -- so with two
        // seats or more the filter found nobody and the book went to whoever sat. It moves only to a person the seats name.
        if owner == nil, 1 < seats.seats.count {
            MontanaTrace.mark("coin_place", "owner unknown -- the root book stays")
            return coins
        }
        var place = coins
        if let owner, owner != seats.active { place = MTSeats.shelf(folder: "AS:Montana/Coins", seat: owner) }
        try? fm.createDirectory(at: place, withIntermediateDirectories: true, attributes: sealed)
        var laid = 0
        for n in names where !fm.fileExists(atPath: place.appendingPathComponent(n).path) {
            if (try? fm.moveItem(at: montana.appendingPathComponent(n), to: place.appendingPathComponent(n))) != nil { laid += 1 }
        }
        MontanaTrace.mark("coin_place", "laid=\(laid)/\(names.count) owner=\(place == coins ? "seated" : "parked")")
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
    /// The coins of chess in the book's lines of the builds before (MTCoinLegacy) -- counted apart, so the received and the
    /// reactions rows count people and reactions alone; chess writes no coin any more.
    var played = 0
    /// The coins the VPN wall minted by its seconds (MTVPNWallMint), counted apart.
    var walled = 0
    /// The coins burned by calls and letters (MTCoinBurn), the Economy of Time's sink.
    var burned = 0
    var received = 0
    var spent = 0
    var sent = 0
    /// The tallies saturate, never trap (the coin audit's ninth point, 05.10.2026 18:4x UTC): a sum past the integer is shown at
    /// its edge, and the app lives.
    static func plus(_ a: Int, _ b: Int) -> Int {
        let (s, over) = a.addingReportingOverflow(b)
        return over ? (0 < b ? Int.max : Int.min) : s
    }
    @MainActor mutating func add(_ e: MTCoinEntry) {
        switch e.k {
        case .earn: earn(e.c, ref: e.ref)
        case .receive: if MTCoinLegacy.chess(e.ref) { played = Self.plus(played, e.c) } else { received = Self.plus(received, e.c) }
        case .spend: if MTCoinLegacy.chess(e.ref) { played = Self.plus(played, -e.c) } else { spent = Self.plus(spent, e.c) }
        case .send: sent = Self.plus(sent, e.c)
        case .burn: burned = Self.plus(burned, e.c)
        }
    }
    /// The game an earning came from, by its name: the Pantheon's taps, chess and its Timer, the VPN wall, the chats.
    @MainActor mutating func earn(_ c: Int, ref: String) {
        if ref.hasPrefix(MTPantheon.refPrefix) { tapped = Self.plus(tapped, c) }
        else if MTCoinLegacy.chess(ref) || MTCoinLegacy.timer(ref) { played = Self.plus(played, c) }   // the Timer is chess too (04.10)
        else if ref.hasPrefix(MTVPNWallMint.refPrefix) { walled = Self.plus(walled, c) }
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
        // nodes are asked for it at once (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's
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
        flush()   // the person who left keeps every move of their last second, in their own book
        entries = []; taken = []; onTarget = [:]; counts = MTCoinCounts(); ownPeers = []
        balance = 0; level = 0
        begin()
    }

    /// THE BOOK IS READ ONCE, OFF THE SCREEN'S THREAD, AND SHOWN AT ONCE (the author's words 04.10.2026 10:04-10:10 UTC: «at 10:04
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
        MontanaTrace.mark("coin_book", "waited ms=\(Int(Date().timeIntervalSince(asked) * 1000))")
        adopt(r)
    }
    /// A line cut short by an ended process is no move: only a whole line counts, once by its name, while the sum still fits.
    nonisolated private static func decode(_ file: URL?) -> ([MTCoinEntry], Set<String>) {
        // ONE BAD BYTE COSTS ONE LINE, NEVER THE BOOK (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
        // audit's tenth point): the book was read as one UTF-8 text, and a single invalid byte read it as nothing -- an empty book
        // until the nodes filled it again. It is read as bytes, and every line is decoded alone.
        guard let file, let data = try? Data(contentsOf: file) else { return ([], []) }
        let decoder = JSONDecoder()
        var moves: [MTCoinEntry] = []
        var taken = Set<String>()
        var sum = 0, passed = 0, passedCoins = 0
        defer { if 0 < passed { MontanaTrace.mark("coin_book", "passed restored names=\(passed) coins=\(passedCoins)") } }
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
    /// A book's balance as its file holds it -- a person's on this phone's shelf (MTSeats.shelfCoins) -- read off the screen's thread.
    nonisolated static func balance(of file: URL) -> Int { decode(file).0.reduce(0) { s, e in MTCoinCounts.plus(s, e.signed) } }
    private func adopt(_ r: Reading) {
        guard reading === r else { return }   // a reading of the person who left the seat
        reading = nil
        var sum = 0, counts = MTCoinCounts(), onTarget: [String: Int] = [:], level = 0
        var levels: [(n: Int, at: Double)] = []
        for e in r.moves {
            sum += e.signed
            counts.add(e)
            if let on = e.shownOn { onTarget[on, default: 0] += e.shownCoins }
            let place = MTPiLevels.place(sum)
            if level < place {
                for n in (level + 1)...place { levels.append((n, e.at)) }
                level = place
            }
        }
        entries = r.moves; taken = r.taken; balance = sum; self.counts = counts; self.onTarget = onTarget; self.level = level
        ownPeers = Self.own(r.moves, names: r.taken)
        MontanaTrace.mark("coin_book", "read moves=\(r.moves.count) balance=\(sum) local=1")
        for l in levels { MTTimeChain.note("pi", kind: "level", coins: l.n, ref: "level:" + String(l.n), at: l.at) }
        // THE CHAINS TAKE THE BOOK'S PAST ONCE (04.10): every move written before the chains stood joins its chain in the book's
        // order; a move the chain already holds is passed by its name.
        MTTimeChain.appendPast(r.moves)
        MTCoinSplit.shared.told()
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
        MTCoinSplit.shared.told()
        reached(at: Date().timeIntervalSince1970)
        // A RESTORED DEVICE TAKES THE WHOLE BOOK IN ONE STROKE (15:51): nineteen thousand moves are encoded and written on the book's
        // queue, not on the screen's thread; their chains take them in one turn of their own queue.
        MTTimeChain.appendPast(fresh)
        if let file { let lines = fresh; disk.async { MTLocalCoinLedger.append(lines, to: file) } }
        MontanaTrace.mark("coin_book", "joined moves=\(fresh.count) balance=\(sum)")
        MTCoinSend.returnUndeliverable(self)
        return fresh.count
    }

    /// THE BALANCE NEVER WRAPS (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin audit's ninth point): a
    /// coin letter of Int.max less the balance passed fits, and every later earning trapped on the sum -- the app died at any
    /// minting. Every move of the hand and the minting passes this one door; a move the integer cannot hold is refused here,
    /// before it is written.
    @discardableResult private func take(_ e: MTCoinEntry) -> Bool {
        guard !e.restoredName else {
            MontanaTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) under a restored name")
            return false
        }
        let (next, over) = balance.addingReportingOverflow(e.signed)
        guard !over else {
            MontanaTrace.mark("coin_refused", "\(e.k.rawValue) coins=\(e.c) the balance cannot hold it")
            return false
        }
        entries.append(e)
        taken.insert(e.id)
        ownPeers.formUnion(Self.own([e], names: taken))
        balance = next
        counts.add(e)
        if let on = e.shownOn { onTarget[on, default: 0] += e.shownCoins }
        MTCoinSplit.shared.told()
        reached(at: e.at)
        return true
    }
    /// THE BOOK SAYS WHICH PAIRS HOLD THESE WORDS (the author's words 06.10.2026 08:1x-08:2x UTC, MTOwnWords): one move of coins seen
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

    /// THE PERSON LEAVING THE SEAT KEEPS EVERY COIN OF THEIR LAST MINUTE (the author's word «fix all points in order» 05.10.2026
    /// 18:4x UTC, the coin audit's fourth point): the book and its chains are on disk in this turn, while the
    /// person's folder still stands -- the seat's park moves the folder, and the lines that waited for their second then found no
    /// folder, or the next person's (MTSeats.parkThenLift asks this before it parks).
    func writeWhole() { writeNow() }

    /// THE BOOK IS WRITTEN ONCE A SECOND, NOT ONCE A COIN (the author's word 04.10.2026 09:27 UTC: «check why the phone heats while
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
        MTCoinTx.mintSoon()   // and the chain takes what the book holds above it within one window of τ1
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
    /// A MOVE BETWEEN PEOPLE IS ON DISK BEFORE ANYONE HEARS OF IT (the author's word 04.10.2026 20:57 UTC: «sent 123 thousand coins
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

    func spend(_ coins: Int, on target: String, peer: String, ref: String) -> Bool {
        move(.spend, coins, peer: peer, ref: ref, on: target)
    }

    func send(_ coins: Int, to peer: String, ref: String) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: nil)
    }
    /// A SEND given on a letter (a paid reaction, MTCoinTx.send3): its coins stand under that letter.
    func send(_ coins: Int, to peer: String, ref: String, on target: String?) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: target)
    }

    /// A COIN LETTER PROVEN DELIVERED TAKES ITS COINS AGAIN, WHATEVER THE BALANCE (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): its
    /// coins came back while it was red (MTCoinSend.hold), the receiver credited it all the same, and its late receipt asks them
    /// again. A refusal on a short balance left them in two books for ever -- the sender had spent them meanwhile. This move stands
    /// whatever the balance: a book may stand below nothing, the truth of a debt, the sum of every book keeps the coins there were,
    /// and no move of the hand leaves a book below what it holds (move).
    func retake(_ coins: Int, to peer: String, ref: String) -> Bool {
        let e = MTCoinEntry(k: .send, c: coins, ref: ref, peer: peer, on: nil, at: MTTimeChain.now())
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_retake", "coins=\(coins) balance=\(balance)")
        return true
    }

    @discardableResult func receive(_ coins: Int, from peer: String, ref: String, on target: String?) -> Bool {
        guard MTCoinBook.fits(coins, beside: balance), !ref.isEmpty, !taken.contains("receive:" + ref) else {
            MontanaTrace.mark("coin_rx", "skipped coins=\(coins) known=\(taken.contains("receive:" + ref) ? 1 : 0)")
            return false
        }
        let e = MTCoinEntry(k: .receive, c: coins, ref: ref, peer: peer, on: target, at: Self.moment(ref))
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_rx", "coins=\(coins) on=\(target == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    /// A SEND THE CHAIN HOLDS STANDS IN THE BOOK WHATEVER ITS BALANCE (fold-7): the chain weighed the sum a moment before
    /// (MTCoinTx.send3), and the book, which mints nothing after the time cut (priced), holds less than the chain -- its refusal
    /// would keep coins the chain lets go. A book below nothing is the truth of what it no longer mints (retake).
    func sendHeld(_ coins: Int, to peer: String, ref: String, on target: String?) -> Bool {
        move(.send, coins, peer: peer, ref: ref, on: target, held: true)
    }

    private func move(_ k: MTCoinEntry.Kind, _ coins: Int, peer: String, ref: String, on: String?, held: Bool = false) -> Bool {
        let e = MTCoinEntry(k: k, c: coins, ref: ref, peer: peer, on: on, at: Self.moment(ref))
        // THE REFUSAL IS THE BOOK'S (the author's word 03.10 13:40): no move leaves more coins than the balance holds -- but a move
        // the chain already weighed (sendHeld).
        guard 0 < coins, !ref.isEmpty, !taken.contains(e.id), held || coins <= balance else {
            MontanaTrace.mark("coin_refused", "\(k.rawValue) coins=\(coins) balance=\(balance)")
            return false
        }
        guard take(e) else { return false }
        keep([e], now: true)
        MontanaTrace.mark("coin_\(k.rawValue)", "coins=\(coins) on=\(on == nil ? 0 : 1) balance=\(balance)")
        return true
    }

    /// A COIN LETTER STANDS AT ITS OWN BIRTH IN EVERY BOOK (the author's word 06.10.2026 08:2x UTC: «the sender and the receivers above
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
    /// THE LETTER NAMES ITSELF (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): its id is the UUID of its own
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

/// A PAIR WHOSE OTHER END HOLDS MY WORDS PAYS NOTHING (the author's words 06.10.2026 08:1x-08:2x UTC: «from the tablet I sent more than
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
        MontanaTrace.mark("own_words", "pair=\(String(conv.prefix(10))) mine=\(mine ? 1 : 0) by=word")
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
    /// A field transfer has three honest outcomes. Only the available the page shows (MTCoinSplit.available) may call it short;
    /// an unanswered node record is pending, not an insufficient balance and not a second send.
    enum TransferResult { case sent(String), short, pending, refused, noKey }
    /// The system chain's name for a restored credit: this prefix and the coin letter's wire name.
    static let restorePrefix = "restore:"
    /// A pair's own conversation, open to letters, of other words than mine: where a bubble burns its coin (pay).
    @MainActor static func pairOpen(_ chat: Chat, store: ChatStore) -> Bool {
        let conv = chat.convId ?? chat.name
        return !chat.isGroup && !ChatStore.isLocalRoom(chat.name) && chat.convId != nil && MontanaConv.holds(conv)
            && !store.refuses(conv) && !store.closedChats.contains(conv) && !MTOwnWords.mine(conv)
    }
    /// WHERE COINS CAN GO: EVERY OPEN PAIR, FOR A PERSON IS THEIR SEED AND THE WALLET IS IN IT (the author's words 11.10.2026 16:5x
    /// UTC: «why does it say Andrey has no wallet and not let me send -- he has a seed, so he has a wallet»; «a gross error -- the seed
    /// is already there, what has a wallet to do with it -- the person is the seed and everything is in it»). A pair had to say it held
    /// coins before it could take them, and on T1 24 of 29 pairs stood dimmed «no wallet yet» (coin_send_page pairs=29 holders=5,
    /// 11.10 15:40Z) -- people on builds with coins who had not yet sent the word that carried the mark. The coins are the seed's:
    /// a letter its build credits at the landing, or at the first launch of a build with coins (settle), and a letter not delivered
    /// in a day gives them back (hold).
    @MainActor static func canPay(_ chat: Chat, store: ChatStore) -> Bool {
        pairOpen(chat, store: store)
    }
    /// COINS TO A PERSON ARE A RECORD ON THE NODES, THE LETTER ONLY TELLS (MTCoinTx, Audit/COIN-TX-V1.md): the record's first node
    /// 200 is the moment they left and the book's debit; then a letter in the chat says how many and carries the confirmation link.
    /// False -- refused (the balance, the chat) or no node took the record: nothing moved.
    @MainActor static func transfer(_ coins: Int, to chat: Chat, store: ChatStore) async -> Bool {
        if case .sent(_) = await transferResult(coins, to: chat, store: store) { return true }
        return false
    }
    /// The same transfer with its record's name: one's own other account lands it at once (MTCoinTx.landOwn).
    @MainActor static func transferId(_ coins: Int, to chat: Chat, store: ChatStore) async -> String? {
        if case let .sent(id) = await transferResult(coins, to: chat, store: store) { return id }
        return nil
    }
    @MainActor static func transferResult(_ coins: Int, to chat: Chat, store: ChatStore) async -> TransferResult {
        let conv = chat.convId ?? chat.name
        let balance = MTCoinBook.ledger.balance
        let available = MTCoinSplit.shared.available   // the number every transfer page shows weighs the sum (16.10.2026 No.72)
        guard canPay(chat, store: store), 0 < coins else {
            MontanaTrace.mark("coin_refused", "transfer invalid coins=\(coins) balance=\(balance) own=\(MTOwnWords.mine(conv) ? 1 : 0)")
            return .refused
        }
        guard coins <= available else {
            MontanaTrace.mark("coin_refused", "transfer coins=\(coins) available=\(available) balance=\(balance) own=\(MTOwnWords.mine(conv) ? 1 : 0)")
            return .short
        }
        var result = await MTCoinTx.sendResult(coins, conv: conv)
        if case .noKey = result {
            // THE KEY IS ASKED, AND THE SAME SEND GOES WHEN IT COMES (the author's word 21.10.2026 09:41 UTC: «if there is a chat
            // there is everything -- the tunnel, the key -- and it must work at once and instantly»): nothing left the book, the
            // correspondent's phone answers the ask with its key (the about word's «q»), a live one within seconds -- T1's diary
            // 09:39:18Z, Petros's receipts in 4 s.
            E2E.shared.sendAboutIfNeeded(to: chat.name, askKey: true)
            var waited = 0
            while MTCoinTx.peerFrom(conv) == nil, waited < 40 {
                waited += 1
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            MontanaTrace.mark("coin_v3", "key asked got=\(MTCoinTx.peerFrom(conv) == nil ? 0 : 1) waited_ms=\(waited * 250)")
            if MTCoinTx.peerFrom(conv) != nil { result = await MTCoinTx.sendResult(coins, conv: conv) }
        }
        switch result {
        case .sent(let id):
            // USER-DATA: the coin glyph, the number of coins and the time they are (the author's word 19.10.2026 14:44 UTC: «1 Coin
            // = 0.000000001 TCM = 1 second; in transfers both the time and the coins» -- coins, never TCM), the time in the sender's
            // language as the words of the letter are; the link is the transfer's own address
            let text = "🪙 " + MTCoinText.count(coins) + " · " + MTCoinText.time(coins) + "\n" + MTCoinTx.link + id
            _ = store.send(text: text, chat: chat.name, convRef: conv, silent: false, noLinkCard: true)
            return .sent(id)
        case .pending:
            MontanaTrace.mark("coin_pending", "transfer coins=\(coins) balance=\(balance)")
            return .pending
        case .refused:
            // NOTHING LEFT, AND THE PERSON IS TOLD SO (the author's word 20.10.2026 19:0x UTC: «on T1 it does not let me send a
            // transfer, it says it is being confirmed /// fix it -- everything must work at once and instantly»): every refused road
            // of send and send3 either never debited the book or
            // gave the coins back before it answered, so «being confirmed» over a refusal was a false gauge. The book already proved
            // the sum, so it is never shown as a shortage either.
            MontanaTrace.mark("coin_refused", "transfer not sent coins=\(coins) balance=\(balance)")
            return .refused
        case .noKey:
            MontanaTrace.mark("coin_refused", "transfer no receiver key coins=\(coins) balance=\(balance)")
            return .noKey
        }
    }
    /// COINS GIVEN ON THE CORRESPONDENT'S LETTER ARE A SEND OF THE CHAIN (the author's words 23.10.2026 00:27 and 00:37 UTC: the
    /// reactions «each a SEND record in the chain, the phone only the chain's mirror»): the coins leave by the pair's version 3 SEND
    /// under the letter's name, and the reaction word only names that SEND («op»: «coin3», «tx») -- the reader's book takes the
    /// coins from the chain alone (MTCoinTx.receive3), never from the word. An older build reads an unknown op as nothing at all.
    @MainActor static func react(_ coins: Int, on m: Message, in chat: Chat, store: ChatStore) async -> Bool {
        guard !m.isMine, let sid = m.msgId, !sid.isEmpty, canPay(chat, store: store) else { return false }
        return await give(coins, on: sid, words: m.text, to: chat.convId ?? chat.name)
    }
    /// An auto-reaction's coins on a chosen person's letter (MTAutoReact): the paid reaction's own road, once a letter -- the name
    /// «auto:» and the letter's wire name is taken before the SEND goes (a builds-before payment stands in the book under it), so a
    /// letter brought twice pays once; a SEND that never went gives the name back.
    static let autoPrefix = "auto:"   // NOT-UI: the book's own name
    @MainActor static func autoGive(_ coins: Int, on m: Message, to conv: String) async -> Bool {
        guard let sid = m.msgId, !sid.isEmpty, !MTLocalCoinLedger.shared.whole.holds(.spend, autoPrefix + sid),
              MTCoinTx.once(autoPrefix + sid) else { return false }
        let paid = await give(coins, on: sid, words: m.text, to: conv)
        if !paid { MTCoinTx.release(autoPrefix + sid) }
        return paid
    }
    /// The one road of a paid reaction: the pair's SEND under the letter's name; the word names it, carries no coins of its own.
    /// A SEND still waiting for its node's word (pending) has left the book and says no name -- the reader's scan credits it.
    @MainActor private static func give(_ coins: Int, on sid: String, words: String, to conv: String) async -> Bool {
        switch await MTCoinTx.send3(coins, conv: conv, on: sid) {
        case .sent(let id):
            let obj: [String: Any] = ["sid": sid, "txt": words, "e": "🪙", "op": "coin3", "c": coins, "tx": id]   // NOT-UI: wire keys
            guard let json = try? JSONSerialization.data(withJSONObject: obj), let body = String(data: json, encoding: .utf8) else { return true }
            MontanaDeliveryEngine.shared.enqueue(to: conv, chat: conv, mid: UUID().uuidString, text: reactionMark + body, silent: true)
            return true
        case .pending:
            return true
        case .notApplicable(let why):
            MontanaTrace.mark("coin_refused", "reaction v3 why=\(why) coins=\(coins)")
            return false
        case .failed:
            return false
        }
    }
    /// THE BUBBLE BURNS ITS COIN (the author's words 04.10.2026 22:21-22:31 UTC: «every bubble -1 coin»; «any bubble in an ordinary
    /// chat with the feed at the bottom»; and 19:29-19:32 UTC: «in ordinary chats take away the coin under every message as a
    /// reaction; the burning in an ordinary chat at both players -- a simple burning without a transfer»; «1 coin»): a bubble of
    /// mine in a pair's ordinary chat -- the Money Flow off; there the letters mint -- burns one coin of my book by the bubble's
    /// name, and nothing goes to the correspondent: no reaction word, no coin under the bubble; their phone burns its own for their
    /// bubbles. It burns when the bubble takes its wire name -- at its landing in the feed, or a media bubble when it is named
    /// (setMediaMid) -- and once, by that name, whichever door hands it over twice; a bubble a build before paid to its reader
    /// burns nothing more. An empty balance burns nothing and the bubble goes all the same; a coin letter is a payment in its own
    /// right, a chess step is the board's, a row of the phone's own goes nowhere.
    static let bubblePrefix = "bubble:"
    /// A letter is fresh for a day from its birth: an auto-reaction pays only a letter born within it (MTAutoReact.landed).
    static let fresh: Double = 86_400
    /// The name a reaction word's coins are credited under on the reader's book: this prefix and the name the word carries.
    static let receivedPrefix = "rc:"   // NOT-UI: the book's own name
    /// A COIN LETTER THAT DID NOT GO GIVES ITS COINS BACK (the author's word 04.10.2026 22:40 UTC: «I sent Narine 60 000 coins from
    /// T1, the letter did not go and they were taken from me; while the retry mark hangs, return them to the sender's balance with
    /// the mark not delivered»): a coin letter of mine holds its coins exactly while it is not red. Red, they come back by one move
    /// (back) and the bubble says so; on its way again under the hand's retry, or proven delivered after all -- the carriage goes on
    /// behind the red and a late receipt turns it delivered -- they are taken again by one move (again). The book's own moves say
    /// which it holds: the transfer, the agains and the backs, each by its name, so a door that asks twice moves nothing twice.
    /// Every door of the ladder asks it after it moves a coin letter of mine (advance, restartSend), and the history's first
    /// reading asks it of every one (settle) -- a letter red before this build gives its coins back at the first launch.
    static let backPrefix = "back:"
    static let againPrefix = "again:"
    /// A COIN LETTER NOT DELIVERED IN A DAY GIVES ITS COINS BACK (the author's words 10.10.2026 20:3x UTC: «a rule common to every
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
        let held = again == back, owed = owes(m, in: key)
        if held, !owed {
            giveBack(coin.c, letter: m.mid, count: back, to: key, why: m.deliveryStatus == .failed ? "red" : "day")
        } else if !held, owed {
            let took = book.retake(coin.c, to: key, ref: againPrefix + m.mid + ":" + String(again + 1))
            MontanaTrace.mark("coin_again", "coins=\(coin.c) took=\(took ? 1 : 0) status=\(m.deliveryStatus)")
        }
    }
    /// Whether a coin letter of mine holds its coins: proven delivered, or on its way and born within the day.
    @MainActor private static func owes(_ m: Message, in key: String) -> Bool {
        switch m.deliveryStatus {
        case .delivered, .read: return true
        case .failed: return false
        case .sending, .sent:
            guard let born = ChatStore.birthMs(fromMid: m.mid) else { return true }   // a name without its birth: held as before
            return Date().timeIntervalSince1970 - born < day
        }
    }
    /// The day ends while no rung moves: every beat of the queue's mirror
    /// (MontanaDeliveryEngine.reconcile) asks the coin letters of mine still on their way.
    @MainActor static func due(_ store: ChatStore) {
        for (chat, rows) in store.messages {
            for m in rows where m.isFromMe && (m.deliveryStatus == .sending || m.deliveryStatus == .sent) && m.coinLetter != nil {
                hold(m, in: chat)
            }
        }
    }
    /// THE LETTERS THE AUTHOR NAMED UNDELIVERABLE (the author's words 10.10.2026 20:2x-20:3x UTC: «there was a transfer from T2 to a
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
        MontanaTrace.mark("coin_back", "coins=\(c) letter=\(why)")
    }
    /// A COIN LETTER OF MINE ON ITS WAY IS NOT DELETED (the author's word «fix all points in order» 05.10.2026 18:4x UTC, the coin
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
        MontanaTrace.mark("coin_again", "coins=\(c) took=\(took ? 1 : 0) row=gone")
    }
    /// The hand's retry of a coin letter whose coins came back takes them again first: a short balance refuses the retry.
    @MainActor static func mayRetry(_ m: Message) -> Bool {
        guard m.isFromMe, let coin = m.coinLetter else { return true }
        let book = MTLocalCoinLedger.shared.whole
        guard book.holds(.send, m.mid) else { return true }
        return moves(book, .send, againPrefix + m.mid) == moves(book, .receive, backPrefix + m.mid) || coin.c <= book.balance
    }
    /// A COIN LETTER IS CREDITED WHEN IT NAMES ITSELF (the author's words 06.10.2026 09:3x-09:4x UTC: «close the double spends»; «the safety of the restore by the seed»): the
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
            MontanaTrace.mark("coin_refused", "a copy under another name from=\(String(chat.prefix(10)))")
            return false
        }
        return true
    }
    /// A reaction word that carried coins arrived: credited once by the name it carries.
    @MainActor static func reacted(_ c: Int, ref: String, on sid: String, from chat: String) {
        guard 0 < c, !ref.isEmpty, !sid.isEmpty else { return }
        MTCoinBook.ledger.receive(c, from: chat, ref: receivedPrefix + ref, on: sid)
    }
    /// THE BOOK HOLDS EVERY COIN LETTER THE CHATS HOLD (the author's word 04.10.2026 20:57 UTC: «close it by construction»): once the
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
                // THE SYSTEM'S OWN BRANCH OF THE TIMECHAIN (the author's word 04.10.2026 21:22 UTC: «repair it by a system branch in the
                // TimeChain, as the diary»): the credit stands in the received chain as any other, and the system chain says why --
                // a coin letter the book had lost, restored by its wire name, its coins and its moment.
                MTTimeChain.note("system", kind: "restore", coins: coin.c, ref: MTCoinSend.restorePrefix + wire)
                letters += 1; coins += coin.c
            }
        }
        // A COIN LETTER OF MINE HOLDS ITS COINS WHILE IT IS NOT RED (hold), asked of every one as the history stands.
        for (chat, rows) in store.messages { for m in rows where m.isFromMe && m.coinLetter != nil { hold(m, in: chat) } }
        if 0 < letters { MTTimeChain.flush() }
        MontanaTrace.mark("coin_settle", "letters=\(letters) coins=\(coins) balance=\(book.balance)")
    }
}

/// AUTO-REACTIONS OF CHOSEN PEOPLE (the author's word 06.10.2026 14:3x UTC: «in the Money Flow's settings, on a long press, open a
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
        let conv = c.convId ?? c.name
        Task { @MainActor in
            let paid = await MTCoinSend.autoGive(r.coins, on: m, to: conv)
            if paid { MTCoinPaid.shared.paid(r.coins, in: chat) }
            MontanaTrace.mark("auto_react", "coins=\(r.coins) paid=\(paid ? 1 : 0)")
        }
    }
}

/// THE COINS I PAID, SEEN IN THE CHAT (the author's word 04.10.2026 22:24 UTC: «in the chat the same way, an animation of a red
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
        MontanaTrace.markFolded("coin_paid", "coins=\(c)", window: 60)
    }
}


// COIN-RULES BEGIN -- tools/mt-coin-rules-check.py compiles this region as it stands with tools/coin-rules-tests.swift (COIN-TX-V3
// section 9: the vectors V1, V2, V3, V6 and the fold's steps); it reads nothing but Foundation and CryptoKit.
/// THE RULES OF A KEY'S CHAIN, ONE PLACE ON THE PHONE (Audit/COIN-TX-V3.md sections 1, 3 and 4): the fields a kind uses, the time a key
/// may mint, the blind and the receiver's commitment, and one record folded onto its key's state -- the rules the chain's node folds by
/// (montana-node-store.py _tx_step) and the Explorer (foldChain), each reading the one document on its own. The phone's sends, its
/// receipts and its copy of the chains ask them here.
enum MTCoinChainRules {
    static let v2Cut: Int64 = 1_792_443_600       // NOT-UI: 19.10.2026 21:00 UTC, the node's TX_V2_CUT (COIN-TX-V3 section 8)
    static let coinEpoch: Int64 = 1_788_210_000   // NOT-UI: 31.08.2026 21:00 UTC, the node's TX_COIN_EPOCH (section 3)
    /// τ1, THE MINTING'S WINDOW (the author's word 12.10.2026 12:5x UTC: «once in τ1 -- 60 seconds must be the window of time»): the
    /// shortest interval a MINT covers (sections 3, 7) and how often the phone asks its chain to take what the book holds above it.
    static let window: Int64 = 60
    static let zero = String(repeating: "0", count: 64)
    enum Kind: UInt8 { case send = 1, recv = 2, mint = 3, refund = 4, genesis = 5, burn = 6 }
    /// A record as the rules read it; a record of the layouts before kinds is a send that names no receiver.
    struct Rec { let id: String; let version: UInt8; let kind: UInt8; let amount: Int64; let from: String; let to: Data; let ref: String; let a: UInt64; let b: UInt64 }
    /// A key's state folded over its chain (section 3).
    struct St: Equatable { var head = MTCoinChainRules.zero; var height = 0; var birth: Int64 = 0; var mintEnd: Int64 = 0; var proven: Int64 = 0; var declared: Int64 = 0; var v3 = false; var lastAt: Int64 = 0; var minted: Int64 = 0 }
    struct SendInfo { let from: String; let amount: Int64; let at: Int64; let to: Data; let dec: Int64 }
    /// A_2(x) of section 4, the doubling rule: what the seconds 1..x of a key's life could mint before the second's cut, and the bound
    /// of every GENESIS -- 2 x min(13, max(1, bit_length(s) - 1)) a second.
    nonisolated static func timeA(_ x: Int64) -> Int64 {
        var total: Int64 = 0, lo: Int64 = 1, k: Int64 = 0
        while 0 < x, lo <= x {
            let hi = min(x, 2 * lo - 1)
            total += (hi - lo + 1) * min(13, max(1, k))
            lo = 2 * lo; k += 1
        }
        return 2 * total
    }
    nonisolated static var genesisCap: Int64 { timeA(v2Cut - coinEpoch) }
    /// 1 SECOND -- 1 COIN (section 4; the constitution, article 11; the author's words 19.10.2026 12:3x UTC: «the ceiling, an invariant --
    /// nothing else can mint or speed it up»): from this node second a MINT is weighed by A(x) = x over the key's whole life less all
    /// it minted; one taken before stands by the doubling rule. The node's TX_SECOND_CUT, the same second as the v2 cut.
    nonisolated static let secondCut: Int64 = v2Cut
    /// What the seconds 1..x of a key's life may mint by a MINT its node takes at the second `at`: chosen by at, never by the interval.
    nonisolated static func allowTime(_ x: Int64, at: Int64) -> Int64 { secondCut <= at ? max(0, x) : timeA(x) }
    /// THE CHAIN MINTS THE KEY'S TIME ITSELF (section 4, fold-6; the author's words 21.10.2026 14:1x UTC: «only the core mints», «1 coin --
    /// 1 second, the client merely shows it»): from this node second every v3 record first folds the seconds its key has lived, so no
    /// phone lays a MINT for its time. The node's TX_TIME_CUT, 22.10.2026 21:00 UTC.
    nonisolated static let timeCut: Int64 = 1_792_702_800
    /// MINTING IS ITS OWN ROAD (fold-7; the author's words 23.10.2026 00:27 and 00:37 UTC: «minting is a separate entity, and it happens
    /// if the person is online or behind the VPN» -- «right, do it»): from this node second the key's life mints nothing by itself, and a
    /// MINT counts only what its interval holds of the last mintFresh seconds before its node took it -- the seconds the key was present.
    /// A BURN is taken from the same second. The node's TX_ONLINE_CUT, 25.10.2026 21:00 UTC.
    nonisolated static let onlineCut: Int64 = 1_792_962_000
    nonisolated static let mintFresh: Int64 = 120
    /// NO MINT AT ALL FROM THE STOP (fold-9; the author's decisions 373 and 377 «a», link 12047; the author's word 29.10.2026 19:31 UTC,
    /// link 11871): from this node second the node refuses every MINT (Stopped, code 18), so the phone lays none and shows no seconds
    /// on their way to one. The node's TX_MINT_STOP (mt-coin), 30.10.2026 12:00 UTC.
    nonisolated static let mintStop: Int64 = 1_793_361_600
    /// The key's seconds of life up to the node second `at`, and never past the online cut, credited once, proven by the same step.
    /// THE PAST NEVER EATS THE PRESENT (fold-8; the author's words 23.10.2026 19:1x and 19:21 UTC: «Andrey's coins are not credited --
    /// fix it in the new build»): a key that minted above its life before the cut by the doubling rule -- 28 of 96 keys on 23.10, every
    /// living phone's -- still gets every second since its last record, never before the cut, so its present seconds are not eaten by
    /// its past: the credit is the greater of its unminted life and those seconds.
    nonisolated static func timeStep(_ s: St, at: Int64) -> St {
        guard timeCut <= at, 0 < s.height else { return s }
        let end = min(at, onlineCut)
        let fresh = max(0, end - max(s.lastAt, timeCut, s.birth))
        let credit = max(end - s.birth - s.minted, fresh)
        guard 0 < credit else { return s }
        var n = s
        n.proven = s.proven + credit; n.minted = s.minted + credit
        return n
    }
    /// What the time step adds to a key folded at the node second `s` by the node second `t`, no record laid between: from the time cut
    /// both sides of its credit grow by one a second up to the online cut, so the node's later word is the earlier one plus these seconds.
    nonisolated static func since(_ s: Int64, to t: Int64) -> Int64 {
        guard timeCut <= s else { return 0 }
        return max(0, min(t, onlineCut) - min(s, onlineCut))
    }
    /// The seconds a MINT taken at the node second `at` may count from the online cut: what its interval holds of the last mintFresh,
    /// never a second before the cut -- the time step credited every one of those (fold-8).
    nonisolated static func present(t0: Int64, t1: Int64, at: Int64) -> Int64 { max(0, t1 - max(t0, at - mintFresh, onlineCut)) }
    /// A BOOK'S PAST, NEVER A FRESH KEY'S WORD (18.10.2026, the critic's P-1; the node's TX_GENESIS_GATE): from this node second a
    /// GENESIS above 0 stands only on the key's own past on its chain and announces at most the time since that past began.
    nonisolated static let genesisGate: Int64 = 1_792_354_500
    /// What a GENESIS of a key at the node second `at` may announce: the book's past, under the cap and the time since its birth.
    nonisolated static func genesisRoom(height: Int, birth: Int64, at: Int64) -> Int64 {
        if v2Cut <= at { return 0 }
        if at < genesisGate { return genesisCap }
        return height == 0 ? 0 : min(genesisCap, timeA(at - birth))
    }
    /// Section 1: a field its kind does not use is zero; a SEND names its commitment, a RECV and a REFUND the SEND they settle, and the
    /// announced part of a SEND or RECV (t0) is never above its amount -- as the node's reader holds them.
    nonisolated static func fieldsHold(kind: UInt8, amount: UInt64, pair: Data, to: Data, ref: Data, a: UInt64, b: UInt64) -> Bool {
        let none = Data(count: 32)
        switch Kind(rawValue: kind) {
        case .send?: return ref == none && b == 0 && to != none && a <= amount
        case .recv?: return pair == none && b == 0 && ref != none && a <= amount
        case .mint?: return pair == none && to == none && ref == none
        case .refund?: return pair == none && to == none && ref != none && a == 0 && b == 0
        case .genesis?: return pair == none && to == none && ref == none && a == 0 && b == 0
        case .burn?: return pair == none && to == none && ref == none && b == 0 && a <= amount
        case nil: return false
        }
    }
    /// The blind of a SEND: HMAC-SHA-256 under the pair's secret over ASCII mt-coin-blind and the SEND's nonce (section 1).
    nonisolated static func blind(secret: Data, nonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("mt-coin-blind".utf8) + nonce, using: SymmetricKey(data: secret)))
    }
    /// The receiver's commitment: SHA-256 of ASCII mt-coin-to, the receiver's from (32 bytes) and the blind (section 1).
    nonisolated static func commitment(from: Data, blind: Data) -> Data { Data(SHA256.hash(data: Data("mt-coin-to".utf8) + from + blind)) }
    nonisolated static func bytes(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
    /// A V2 RECORD THAT SPENT STANDS OPEN AS A SEND (section 5, fold-4; P-3 of Agent 95): on an opened chain it takes this declared
    /// part, and its sender's REFUND gives the same split back after its day -- it names no receiver, so no chain could ever take it.
    /// nil: a v2 record of the book's past (the chain not opened), which spent nothing, or one above the balance.
    nonisolated static func v2Spent(_ s: St, amount: Int64) -> Int64? {
        guard s.v3, amount <= s.proven + s.declared else { return nil }
        return max(0, amount - s.proven)
    }
    /// One record folded onto its key's state by the nodes' rules: the next state, or nil for a record that breaks a rule; wait for a
    /// RECV or REFUND whose SEND is not folded yet.
    nonisolated static func step(_ s: St, _ p: Rec, _ at: Int64, _ sends: [String: SendInfo], _ settled: Set<String>) -> (next: St?, wait: Bool) {
        // first the key's time, then the record's kind (section 3, fold-6); a refused record leaves the state as it stood
        let s = p.version == 3 ? timeStep(s, at: at) : s
        var n = s
        n.head = p.id; n.height += 1; n.lastAt = max(at, s.lastAt)
        if s.height == 0 { n.birth = at; n.mintEnd = at }
        let a = p.amount
        if p.version == 2 {
            // EVERY TRANSFER MOVES ITS BALANCE (section 3, fold-2; the author's words 12.10.2026 09:1x UTC: «all transfers must be
            // simply correct, not versions»): after the chain opened, a send that names no receiver spends as a SEND, proven first
            guard s.v3 else { return (n, false) }
            guard let d = v2Spent(s, amount: a) else { return (nil, false) }
            n.proven = s.proven - (a - d); n.declared = s.declared - d
            return (n, false)
        }
        n.v3 = true
        switch Kind(rawValue: p.kind) {
        case .genesis?:
            if s.v3 || (0 < a && v2Cut <= at) || genesisCap < a { return (nil, false) }
            if 0 < a && genesisGate <= at && (s.height == 0 || timeA(at - s.birth) < a) { return (nil, false) }
            n.declared = a
        case .mint?:
            let t0 = Int64(p.a), t1 = Int64(p.b)
            if s.height == 0 || t0 < s.mintEnd || t1 < t0 + 60 || at < t1 { return (nil, false) }
            // THE SUM OF TIME (section 4, fold-3): all the key's MINTs together stay under A(t1 - birth), so a MINT below its
            // interval's seconds leaves the key's time to the next one (17.10.2026, P1: a MINT of 120 laid before the pay for 4.4 days
            // away had closed those days, and 2 452 406 coins stood in the book and not on the chain); from the cut 1 coin a second
            // from the online cut the present seconds alone weigh it: the intervals never overlap, so the life's sum is not asked and a
            // key that minted above its life before the time cut mints its present seconds like any other (fold-8)
            if onlineCut <= at {
                if present(t0: t0, t1: t1, at: at) < a { return (nil, false) }
            } else if allowTime(t1 - s.birth, at: at) - s.minted < a { return (nil, false) }
            n.proven = s.proven + a; n.mintEnd = t1; n.minted = s.minted + a
        case .send?, .burn?:
            // a BURN spends as a SEND and names no one: no RECV or REFUND can name it (the open SENDs hold SENDs alone)
            if p.kind == Kind.burn.rawValue && at < onlineCut { return (nil, false) }
            let dec = Int64(p.a)
            if s.proven + s.declared < a || dec != max(0, a - s.proven) { return (nil, false) }
            n.proven = s.proven - (a - dec); n.declared = s.declared - dec
        case .recv?, .refund?:
            guard let S = sends[p.ref] else { return (nil, true) }
            if S.amount != a || settled.contains(p.ref) { return (nil, false) }
            if p.kind == Kind.recv.rawValue {
                guard let f = bytes(p.from), S.dec == Int64(p.a), commitment(from: f, blind: p.to) == S.to else { return (nil, false) }
            } else if S.from != p.from || at < S.at + 86_400 {
                return (nil, false)
            }
            n.proven = s.proven + a - S.dec; n.declared = s.declared + S.dec
        case nil:
            return (nil, false)
        }
        return (n, false)
    }
}
// COIN-RULES END

/// THE BALANCE AS ITS CHAIN HOLDS IT (COIN-TX-V3 section 3; the chairman's task 12.10.2026, No.65: «the balance figure stays one, and
/// beneath it the split proven / declared»): what the person's own chain proves by mints and receipts, and what its opening announced.
/// This phone's own copy of the chains says it when the person keeps one (MTCoinReplica, an independent fold); otherwise the chain's
/// node does (POST /tx-head), and a word of the node never stands over the copy's fresher one. Nothing before the chain opened.
@MainActor final class MTCoinSplit: ObservableObject {
    static let shared = MTCoinSplit()
    struct Split: Equatable { let proven: Int64; let declared: Int64; let fromCopy: Bool; let at: TimeInterval; let height: Int; let second: Int64; var mintEnd: Int64 = 0 }
    @Published private(set) var split: Split?
    /// THE NEWEST STATE OF THE CHAIN SPEAKS, WHOEVER FOLDED IT (the author's words 12.10.2026 12:5x UTC: «the available depends on the
    /// network and the confirmed ... everything at once»): the copy's fold stood an hour over every fresher word of the node, so a RECV or
    /// a MINT the node had taken waited for the copy's next round. The chain's height says which word is newer; one height is one state.
    func heard(proven: Int64, declared: Int64, opened: Bool, fromCopy: Bool, height: Int, second: Int64, mintEnd: Int64) {
        guard opened else { return }
        if let s = split, height < s.height { return }
        let now = Date().timeIntervalSince1970
        if split?.proven != proven || split?.declared != declared || split?.height != height || split?.mintEnd != mintEnd {
            split = Split(proven: proven, declared: declared, fromCopy: fromCopy, at: now, height: height, second: second, mintEnd: mintEnd)
            keep(coins: proven &+ declared, height: height)
        }
        if flying.contains(where: { _, f in f.height < height }) { flying = flying.filter { _, f in height <= f.height } }
        told()
        MontanaTrace.markFolded("coin_split", "proven=\(proven) declared=\(declared) copy=\(fromCopy ? 1 : 0)", window: 600)
    }
    /// THE CHAIN'S LAST WORD OUTLIVES THE RUN (the author's word 29.10.2026 09:28 UTC, link 11329: «1.5 million coins were written
    /// off and the balance was 7.9 million, now it is less -- this is not admissible»): Andrey's phone 13498CA8 opened the wallet at
    /// 06:55 UTC on LTE, its road to the chain's node failed (coin_replica code=-1, handshake_timeout), and the page showed the book,
    /// 6 567 126, while the chain held 7 900 616 with no record after the MINT of 27.10 -- a debit the chain never had. The last state
    /// the chain told for the seated key stands in the person's folder (MTCoinPlace, moved with the seat) and speaks until the chain
    /// speaks in this run; the book only before the chain ever spoke for this key. It spends nothing by itself: every send is weighed
    /// again by the chain's own word (send3), and no other road sends after the v2 cut (sendResult).
    private struct LastWord: Codable { let key: String; let coins: Int64; let height: Int; let at: TimeInterval }
    private static let lastName = "chain-last-word.json"   // NOT-UI: the file's name in the person's folder
    private var last: (generation: Int, word: LastWord?)?
    private var lastWord: LastWord? {
        let g = MTCoinBook.generation
        if let l = last, l.generation == g { return l.word }
        var word: LastWord?
        if let u = MTCoinPlace.file(Self.lastName), let d = try? Data(contentsOf: u),
           let w = try? JSONDecoder().decode(LastWord.self, from: d), w.key == MTCoinTx.myKeyTag { word = w }
        last = (g, word)
        return word
    }
    /// Whether the chain ever spoke for the seated key -- in this run or in one before it.
    var spoke: Bool { split != nil || lastWord != nil }
    private func keep(coins: Int64, height: Int) {
        guard let key = MTCoinTx.myKeyTag, let u = MTCoinPlace.file(Self.lastName) else { return }
        let w = LastWord(key: key, coins: coins, height: height, at: Date().timeIntervalSince1970)
        guard let d = try? JSONEncoder().encode(w) else { return }
        try? d.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        last = (MTCoinBook.generation, w)
    }
    /// THE SENDS ON THEIR WAY TO THE CHAIN (fold-7; the author's words 23.10.2026 00:27 UTC: «the phone only mirrors the chain»): a SEND
    /// laid on the head of height h stands in every state of a height above h, or never will -- another record took its place on that
    /// head. Until the chain tells a state above h, its coins are on their way and the available leaves them out. Held in memory: a new
    /// run reads the chain after the send's road has ended.
    @Published private var flying: [String: (height: Int, coins: Int64)] = [:]
    func laid(_ id: String, coins: Int, on height: Int) {
        flying[id] = (height, Int64(coins))
        told()
    }
    /// THE AVAILABLE, ONE NUMBER EVERYWHERE (the author's word 16.10.2026 14:19 UTC: «on the coins page do not show Proven, Declared,
    /// More wait to be minted below -- it is enough to show how much is available with one owner, so that a transfer from the chat
    /// and from any place shows only the available»): what the person's chain holds for its one owner, proven and declared, less the
    /// sends on their way to it; before the chain has spoken in this run, its last word (lastWord), and the book only when it never
    /// spoke for this key. The book no longer caps it (fold-7, the author's
    /// words 23.10.2026 00:37 UTC: «minting is a separate entity»): the book mints nothing after the time cut (MTLocalCoinLedger.priced),
    /// so as a ceiling it would freeze the number while the chain mints. The wallet, the chat's coin plate, the send page, the chess
    /// stake and the word about oneself show it, and a transfer is weighed by it (MTCoinSend.transferResult).
    var available: Int {
        guard let s = split else { return lastWord.map { w in Int(clamping: max(0, w.coins)) } ?? MTLocalCoinLedger.shared.balance }
        let away = flying.values.reduce(Int64(0)) { sum, f in s.height <= f.height ? sum &+ f.coins : sum }
        let lived = MTCoinChainRules.since(s.second, to: s.second &+ Int64(max(0, Date().timeIntervalSince1970 - s.at)))
        return Int(clamping: max(0, s.proven &+ s.declared &+ lived &- away))
    }
    /// THE SECONDS ON THEIR WAY TO THE CHAIN (the author's words 26.10.2026 09:2x UTC, links 8615 and 8617: «I do not see how the
    /// coins are minted every second on the Time Coins page ... even if not all are available or finalized»; «let it count so, then
    /// show visually what happens before the window is finalized»): from the online cut the chain credits a person's seconds only by
    /// a MINT the phone lays while the person is here, once in a minute or so (MTCoinTx.reconcile), so the chain's number stood and
    /// leapt. These are the very seconds the next MINT will name -- from the later of the last MINT's end, the node's freshness less
    /// the road's margin and the person's coming -- counted at the node's second; when it lands the chain holds them and they leave
    /// here, so the sum moves on without a leap. Shown and never spent: the available leaves them out, and a transfer weighs nothing else.
    var minting: Int {
        guard let s = split, let from = MTCoinTx.hereFrom, MTCoinTx.here else { return 0 }
        let now = s.second &+ Int64(max(0, Date().timeIntervalSince1970 - s.at))
        guard MTCoinChainRules.onlineCut <= now, now < MTCoinChainRules.mintStop else { return 0 }
        let t0 = max(s.mintEnd, now - MTCoinChainRules.mintFresh + MTCoinTx.presentMargin, from)
        return Int(clamping: max(0, now - t0))
    }
    /// What the wallet's Time Balance shows: the available and the seconds on their way to it.
    var growing: Int { available + (split == nil ? 0 : minting) }
    /// The number the readers off the main actor hear (MTCoinBalance): the available, told at every move of the book and the chain.
    /// Before the chain has spoken the available is the book's, so its views hear every move of the book here.
    private var shown: Int?
    func told() {
        if split == nil { objectWillChange.send() }
        shown = growing
        MTCoinBalance.set(available)
    }
    /// THE CHAIN'S SECOND ON THE SCREEN (the author's words 23.10.2026 20:2x UTC: «in the client the minting shows just as before, only
    /// it all happens at the core's level»): the chain credits the key every second by its own step (MTCoinChainRules.since), so the
    /// beat of the minting raises those seconds with their sum as the book's coins once rose, and never a coin the chain did not fold.
    /// The seconds on their way rise by the same beat (minting), and when they leave -- the person away, or the MINT landed -- the
    /// figure is told again without a rise.
    func beat() {
        guard split != nil, let before = shown else { return }
        let now = growing
        guard before != now else { return }
        objectWillChange.send()
        told()
        if before < now { MTCoinFlash.shared.born(now - before, ref: MTWalletPull.refPrefix) }
    }
}

/// THE COIN TRANSFER IS ONE RECORD ON THE NODES (Audit/COIN-TX-V1.md; the author's words 11.10.2026 16:5x-17:2x UTC: «a person is
/// their seed and everything is in it»; «so I can pay them in any scenario»; «either the coins left or not -- there is no third»;
/// «professional, in the TimeChain, for auditors»). A coin letter carried the coins inside a letter, so their fate was the letter's:
/// a build that buries the coin link (2162-2179) dropped it and the coins stood a day nowhere (the critic 11.10, B-1). The record is
/// signed by the seed's coin key and laid on the nodes' append-only log; a node's 200 is the moment the coins left, and the
/// receiver's book finds the record by its pair's tag on any later build, on any device of its seed. A chat letter only tells.
enum MTCoinTx {
    static let size = 5330    // version 1 (Audit/COIN-TX-V1.md), read only: builds 2190 and older send it
    static let size2 = 5362   // version 2 (Audit/COIN-TX-V2.md), the record this build sends
    static let refPrefix = "tx:"          // NOT-UI: the book's name of a transfer's moves
    static let backPrefix = "txback:"     // NOT-UI: the book's name of a debit no node took
    static let link = "https://montana.xxx/explorer/#tx="   // NOT-UI: the transfer's confirmation link (the Explorer)
    static let explorer = URL(string: "https://montana.xxx/explorer/") ?? URL(fileURLWithPath: "/")   // NOT-UI: the Explorer's page
    static let keyLink = "https://montana.xxx/explorer/#key="   // NOT-UI: a coin key's whole chain in the Explorer
    /// THE CHAINS' NODES (Audit/COIN-TX-V2.md): the protocol's two nodes, sorted by name, each with its one door -- Moscow and
    /// Amsterdam; a key's chain lives on the one at the index of the key tag's first byte. Every phone and the Explorer read the same
    /// table, so a chain never splits; a node not in it (Lauterbourg keeps no transfers) is no chain node.
    static let chainNodes: [(name: String, host: String)] = [("montana.quest", "api.montana.quest"), ("montana.xxx", "montana.xxx")]   // NOT-UI: the protocol's chain set, one place
    private static let magic = Data("MTTX".utf8)
    private static let signed1 = Data("mt-coin-tx-v1".utf8)
    private static let signed2 = Data("mt-coin-tx-v2".utf8)

    static let zero = String(repeating: "0", count: 64)
    struct Record {
        let id: String; let version: UInt8; let coins: Int; let birthMs: UInt64; let pair: Data; let prev: String; let from: String; let bytes: Data
        var kind: UInt8 = 1; var to = Data(); var ref = ""; var a: UInt64 = 0; var b: UInt64 = 0; var nonce = Data()   // version 3's fields (COIN-TX-V3)
    }
    enum Word: Equatable { case left, notLeft, unknown, behind }

    private static let keyLock = NSLock()
    private static var keyCache: (words: Data, pk: Data, sk: Data)?
    /// The seed's coin key: HKDF-Expand(master_seed, "mt-coin-tx", 32) into ML-DSA-65 -- one on every device of the words, and no
    /// relation to the identity's account key (a coin key names no person's number or card).
    static func keys() -> (pk: Data, sk: Data)? {
        guard let words = MontanaSeed.mnemonic else { return nil }
        let tag = Data(SHA256.hash(data: Data(words.utf8)))
        keyLock.lock()
        if let c = keyCache, c.words == tag { keyLock.unlock(); return (c.pk, c.sk) }
        keyLock.unlock()
        guard let h = derive(words) else { return nil }
        keyLock.lock(); keyCache = (tag, h.pk, h.sk); keyLock.unlock()
        return (h.pk, h.sk)
    }
    /// One key's hands: the person seated (keys()) or a person on this phone's shelf (derive) -- the record is theirs, signed by them.
    struct Hands { let pk: Data; let sk: Data; var from: String { MTCoinTx.keyTag(pk) } }
    /// The coin key of any words this phone holds, derived anew (never cached: a shelf's words are asked rarely).
    static func derive(_ words: String) -> Hands? {
        guard let master = MontanaQueueKeys.masterSeed(words), master.count == 64 else { return nil }
        var seed = [UInt8](repeating: 0, count: 32)
        let role = Array("mt-coin-tx".utf8)
        let rc = master.withUnsafeBytes { m -> Int32 in
            role.withUnsafeBufferPointer { r -> Int32 in
                guard let mb = m.bindMemory(to: UInt8.self).baseAddress else { return -1 }
                return mt_mldsa_seed_for_role(mb, r.baseAddress, role.count, &seed)
            }
        }
        guard rc == 0 else { return nil }
        var pk = [UInt8](repeating: 0, count: 1952), sk = [UInt8](repeating: 0, count: 4032)
        guard mt_mldsa_keypair_from_seed(seed, &pk, &sk) == 0 else { return nil }
        return Hands(pk: Data(pk), sk: Data(sk))
    }
    static func hex(_ d: Data) -> String { d.map { b in String(format: "%02x", b) }.joined() }
    private static func unhex(_ s: String) -> Data? {
        guard s.count % 2 == 0 else { return nil }
        var out = Data(); var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(b); i = j
        }
        return out
    }
    /// The coin key's tag on the wire: SHA-256 of the coin key -- the sender's name in every record.
    static func keyTag(_ pk: Data) -> String { hex(Data(SHA256.hash(data: pk))) }
    static var myKeyTag: String? { keys().map { k in keyTag(k.pk) } }
    /// The pair's tag: HMAC-SHA-256 under the pipe's secret over "mt-coin-pair-v1" -- its two ends know it, no one else does.
    /// Made at the pipe's birth by the secret's one owner (MTPipeKey.kept), so the secret it stands on may walk away.
    static func pairTag(_ conv: String) -> Data? { MTPipeBook.kept(for: conv)?.pair }
    private static func le(_ v: UInt64) -> Data { withUnsafeBytes(of: v.littleEndian) { p in Data(p) } }
    private static func u64(_ b: [UInt8], _ at: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { v, i in v | (UInt64(b[at + i]) << (8 * UInt64(i))) }
    }
    /// The record of version 2, signed by the core on top of the key's head (nil: no words, no pipe, or the core refused).
    static func build(_ coins: Int, conv: String, prev: String) -> Data? {
        guard 0 < coins, let k = keys(), let pair = pairTag(conv), let p = unhex(prev), p.count == 32 else { return nil }
        var nonce = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, nonce.count, &nonce) == errSecSuccess else { return nil }
        var body = magic
        body.append(2)
        body.append(le(UInt64(coins)))
        body.append(le(UInt64(max(0, Date().timeIntervalSince1970 * 1000))))
        body.append(contentsOf: nonce)
        body.append(pair)
        body.append(p)
        body.append(k.pk)
        guard body.count == 2053, let sig = MontanaPQ.sign(seckey: k.sk, message: signed2 + body), sig.count == 3309 else { return nil }
        return body + sig
    }
    static func name(_ rec: Data) -> String { hex(Data(SHA256.hash(data: rec))) }
    /// A record read back -- version 1 or 2 -- believed only when its shape holds and the core verifies its signature. known: the
    /// caller already saw a record of this very name verify, and the name is the hash of every byte, the signature's among them --
    /// the same bytes, the same answer; the caller still holds the read record's name to the one it knew.
    static func read(_ rec: Data, known: Bool = false) -> Record? {
        let b = [UInt8](rec)
        guard 5 <= b.count, Data(b[0..<4]) == magic else { return nil }
        let v = b[4]
        if v == 3 { return read3(rec, known: known) }
        let end: Int, keyAt: Int, total: Int, prefix: Data
        switch v {
        case 1: end = 2021; keyAt = 69; total = size; prefix = signed1
        case 2: end = 2053; keyAt = 101; total = size2; prefix = signed2
        default: return nil
        }
        guard b.count == total else { return nil }
        let coins = u64(b, 5)
        guard 0 < coins, coins <= UInt64(Int.max) else { return nil }
        let body = Data(b[0..<end]), pk = Data(b[keyAt..<end]), sig = Data(b[end..<total])
        guard known || MontanaPQ.verify(pubkey: pk, message: prefix + body, signature: sig) else { return nil }
        return Record(id: name(rec), version: v, coins: Int(coins), birthMs: u64(b, 13), pair: Data(b[37..<69]),
                      prev: v == 2 ? hex(Data(b[69..<101])) : "", from: keyTag(pk), bytes: rec)
    }
    private static func doors() -> [String] { MontanaWakePush.oneDoorPerNode(MontanaWakePush.orderedBases(for: "vault")) }
    /// A door's chain node: the node whose door it is, nil for any other door.
    private static func chainNode(ofDoor door: String) -> String? {
        guard let host = URL(string: door)?.host else { return nil }
        return chainNodes.first { n in n.host == host }?.name
    }
    /// A key's chain node: the one at the index of the key tag's first byte.
    static func chainNode(of from: String) -> String? {
        guard let first = UInt8(from.prefix(2), radix: 16) else { return nil }
        return chainNodes[Int(first) % chainNodes.count].name
    }
    /// THE DOOR OF A KEY'S CHAIN: its node through the api door when the phone knows it, else through any door of that node the
    /// phone holds, else through the node's own api name.
    static func chainDoor(_ from: String) -> String? {
        guard let node = chainNode(of: from) else { return nil }
        return door(ofNode: node)
    }
    private static func door(ofNode node: String) -> String? {
        chainNodes.first { n in n.name == node }.map { n in "https://" + n.host + "/pushwake" }
    }
    /// A node's answer, and whether the request never reached it (no network, no name, no connection): only such a silence
    /// proves nothing was laid there.
    private static func ask(_ url: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]?, unreached: Bool) {
        guard let u = URL(string: url), let d = try? JSONSerialization.data(withJSONObject: body) else { return (-1, nil, true) }   // SERVER-DEBT-ACK: the accelerator node (rung 4), the transfers' log
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 15   // SERVER-DEBT-ACK: the accelerator node (rung 4)
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = d
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)   // SERVER-DEBT-ACK: the accelerator node (rung 4)
            return ((resp as? HTTPURLResponse)?.statusCode ?? -1, try? JSONSerialization.jsonObject(with: data) as? [String: Any], false)
        } catch let e as URLError {
            let never: Set<URLError.Code> = [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff]
            return (-1, nil, never.contains(e.code))
        } catch {
            return (-1, nil, false)
        }
    }
    /// THE NODE'S WORD DECIDES (the keeper's state is said by the keeper): a version 2 record goes to its key's chain node alone --
    /// taken there, left; standing on a head that moved, behind; refused, or the request never reached it, not left; anything else
    /// waits for that node's word. A version 1 record (an older build's, settled here) keeps its own rule: any door that takes it.
    static func lay(_ rec: Data) async -> Word {
        let id = name(rec)
        let b = [UInt8](rec)
        guard 5 <= b.count else { return .notLeft }
        if b[4] == 2 && b.count == size2 || b[4] == 3 && b.count == size3 {
            guard let door = chainDoor(keyTag(b[4] == 2 ? Data(b[101..<2053]) : Data(b[182..<2134]))) else { return .notLeft }
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            if a.code == 200, (a.obj?["id"] as? String) == id { return .left }
            if a.code == 409 { return .behind }
            if a.code == 400 || a.code == 429 || a.code == 507 || a.unreached { return .notLeft }
            let g = await ask(door + "/tx-get", ["id": id])
            return g.code == 200 ? .left : .unknown
        }
        var refused = 0, unreached = 0, all = 0
        for door in doors() {
            all += 1
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            if a.code == 200, (a.obj?["id"] as? String) == id { return .left }
            if a.code == 400 || a.code == 507 { refused += 1 } else if a.unreached { unreached += 1 }
        }
        if 0 < all, refused + unreached == all { return .notLeft }
        for door in doors() {
            let a = await ask(door + "/tx-get", ["id": id])
            if a.code == 200 { return .left }
        }
        return .unknown
    }
    /// THE HEAD IS BELIEVED ONLY AS MY OWN SIGNED RECORD (the chairman's finding 11.10.2026 20:2x UTC: a node that took a record of my
    /// key signed by no one handed it out as my head, and the next honest record stood on it for ever): the head's record is read
    /// from the same chain node, its bytes must be its name, the core must verify it, and it must be of my own key. Anything else --
    /// no record, another key, a forgery -- and nothing is built on it: the coins stay.
    private static func headIsMine(_ head: String, me: String, door: String) async -> Bool {
        if head == zero { return true }
        let g = await ask(door + "/tx-get", ["id": head])
        guard g.code == 200, let b = (g.obj?["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { return false }
        guard let r = await Task.detached(priority: .userInitiated, operation: { read(b) }).value else { return false }
        return r.id == head && r.from == me && (r.version == 2 || r.version == 3)
    }
    private static func pendingURL(_ id: String) -> URL? { MTTimeChainPlace.dir()?.appendingPathComponent("tx-pending-" + id + ".rec") }
    /// SENDS (version 2): the key's head from its chain node, the record on top of it, the debit held under the record's name, the
    /// record laid there. Taken -- the coins left. A head that moved (another device of the words sent meanwhile) -- the coins come
    /// back under the same number, the seed's own records join the book, the balance is asked again and one more record goes on the
    /// new head. Refused, or never reached -- the coins come back. No answer -- the record waits on disk for the node's word (settle).
    enum SendResult { case sent(String), pending, refused, noKey }
    @MainActor static func send(_ coins: Int, conv: String) async -> String? {
        if case let .sent(id) = await sendResult(coins, conv: conv) { return id }
        return nil
    }
    @MainActor static func sendResult(_ coins: Int, conv: String) async -> SendResult {
        // VERSION 3 FIRST (COIN-TX-V3): the chain proves the balance; version 2 only for a correspondent who cannot take v3, until the cut
        switch await send3(coins, conv: conv) {
        case .sent(let id): return .sent(id)
        case .pending: return .pending
        case .failed: return .refused
        case .notApplicable(let why):
            // the reason a version 3 SEND could not go, said: 08:59:58 UTC of 12.10 laid a v2 record and nothing told why
            MontanaTrace.mark("coin_v3", "v2 road why=\(why) coins=\(coins)")
            if v2Cut <= Int64(Date().timeIntervalSince1970) { return why == noReceiverKey ? .noKey : .refused }
        }
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me) else { return .refused }
        // A SEND THAT NAMES NO RECEIVER SPENDS THE CHAIN TOO (COIN-TX-V3 section 3, fold-2): the chain opened and holding the sum first,
        // else the node refuses it as an overspend -- the coins stay, said here before anything is signed
        if let st = await reconcile(force: true), st.v3, st.proven + st.declared < Int64(coins) {
            MontanaTrace.mark("coin_v3", "v2 road refused: chain short coins=\(coins) chain=\(st.proven + st.declared)")
            return .refused
        }
        for attempt in 1...2 {
            let h = await ask(door + "/tx-head", ["from": me])
            guard h.code == 200, let head = h.obj?["head"] as? String, head.count == 64 else {
                MontanaTrace.mark("coin_tx", "no head code=\(h.code) attempt=\(attempt)")
                return .refused
            }
            guard await headIsMine(head, me: me, door: door) else {
                MontanaTrace.mark("coin_tx", "head unverified attempt=\(attempt)")
                return .refused
            }
            guard let rec = await Task.detached(priority: .userInitiated, operation: { build(coins, conv: conv, prev: head) }).value else {
                MontanaTrace.mark("coin_tx", "refused build coins=\(coins)")
                return .refused
            }
            let id = name(rec)
            guard let book = seat.book, book.send(coins, to: conv, ref: refPrefix + id) else { return .refused }
            let pending = pendingURL(id)
            if let pending { try? rec.write(to: pending, options: .atomic) }
            let word = await lay(rec)
            MontanaTrace.mark("coin_tx", "word=\(word) coins=\(coins) id=\(id.prefix(12)) attempt=\(attempt)")
            guard seat.stands else { return .pending }   // the record waits in its person's folder (settle)
            switch word {
            case .left:
                if let pending { try? FileManager.default.removeItem(at: pending) }
                return .sent(id)
            case .notLeft, .behind:
                book.receive(coins, from: conv, ref: backPrefix + id, on: nil)
                if let pending { try? FileManager.default.removeItem(at: pending) }
                if word == .notLeft { return .refused }
                await scanFresh(why: "behind")   // the other device's record joins the book before the balance is asked again
            case .unknown:
                return .pending
            }
        }
        return .refused
    }
    /// The records an ended process left waiting, each decided by a node's word; then the pipes are asked.
    @MainActor static func settle() async {
        let seat = MTCoinSeat()
        let fm = FileManager.default
        if let dir = MTTimeChainPlace.dir() {
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where n.hasPrefix("tx-pending-") && n.hasSuffix(".rec") {
                let u = dir.appendingPathComponent(n)
                guard let rec = try? Data(contentsOf: u), let r = read(rec) else { try? fm.removeItem(at: u); continue }
                let conv = MTPipeBook.all().first { c in pairTag(c) == r.pair }
                let word = await lay(rec)
                guard let book = seat.book else { return }   // the records wait in their person's folder
                switch word {
                case .left: try? fm.removeItem(at: u)
                case .notLeft, .behind:
                    if let conv { book.receive(r.coins, from: conv, ref: backPrefix + r.id, on: book.entry(.send, refPrefix + r.id)?.on) }
                    try? fm.removeItem(at: u)
                case .unknown: continue
                }
            }
        }
        await scan(why: "launch")
    }
    @MainActor private static var scanning = false
    @MainActor private static var again = false
    /// A scan that starts after the one in flight ends: what the node holds now is in the book when it returns.
    @MainActor private static func scanFresh(why: String) async {
        for _ in 0..<150 where scanning { try? await Task.sleep(nanoseconds: 100_000_000) }
        await scan(why: why)
    }
    /// The doors asked for records: each chain node's door, then the phone's other doors (version 1 records of older builds).
    private static func scanDoors() -> [String] {
        var out = chainNodes.compactMap { n in door(ofNode: n.name) }
        for d in doors() where chainNode(ofDoor: d) == nil { out.append(d) }
        return out
    }
    /// RECEIVES: every pipe's tag asked on every node; a verified record from another key is a credit, a record from my own key my
    /// own send from another device of the words -- each once, by its name; a version 2 record is believed only from its key's
    /// chain node, so a record laid on another node (a fork a dishonest client tried) moves nothing.
    @MainActor static func scan(why: String) async {
        if scanning { again = true; return }
        let seat = MTCoinSeat()
        guard let me = myKeyTag else { return }
        var conv: [String: String] = [:]
        for c in MTPipeBook.all() { if let t = pairTag(c) { conv[hex(t)] = c } }
        guard !conv.isEmpty else { return }
        scanning = true
        defer {
            scanning = false
            if again { again = false; Task { @MainActor in await scan(why: "again") } }
        }
        let tags = Array(conv.keys)
        var got = 0, credited = 0, own = 0, bad = 0, foreign = 0
        var seen = Set<String>()
        for door in scanDoors() {
            let node = chainNode(ofDoor: door)
            for start in stride(from: 0, to: tags.count, by: 256) {
                let part = Array(tags[start..<min(start + 256, tags.count)])
                var since = 0
                while true {
                    let a = await ask(door + "/tx-pair", ["tags": part, "since": since])
                    guard a.code == 200, let txs = a.obj?["txs"] as? [[String: Any]] else { break }
                    for x in txs {
                        guard let id = x["id"] as? String, !seen.contains(id),
                              let b = (x["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) else { continue }
                        got += 1
                        guard let r = await Task.detached(priority: .utility, operation: { read(b) }).value, r.id == id,
                              let c = conv[hex(r.pair)] else { bad += 1; continue }
                        if r.version != 1, chainNode(of: r.from) != node { foreign += 1; continue }
                        seen.insert(id)
                        guard let book = seat.book else { return }   // the pipes and the key were the person's who left
                        if r.from == me {
                            if !book.holds(.send, refPrefix + r.id), book.retake(r.coins, to: c, ref: refPrefix + r.id) { own += 1 }
                        } else if r.version == 3 {
                            if await receive3(r, conv: c) { credited += 1 }
                        } else {
                            if book.receive(r.coins, from: c, ref: refPrefix + r.id, on: nil) { credited += 1 }
                            if r.version == 2, book.holds(.receive, refPrefix + r.id) { noteCredit2(r.id, from: r.from, coins: r.coins, conv: c) }
                        }
                    }
                    let last = a.obj?["last"] as? Int ?? since
                    guard txs.count == 512, since < last else { break }
                    since = last
                }
            }
        }
        MontanaTrace.mark("coin_tx_scan", "why=\(why) pipes=\(conv.count) got=\(got) credited=\(credited) own=\(own) bad=\(bad) foreign=\(foreign)")
        guard seat.stands else { return }
        await reconcile()       // the chain announced and the book's mints laid (COIN-TX-V3 sections 3-4)
        await refundDue()       // a SEND no one took in a day comes back (section 5)
        await creditsGone()     // a v2 record its sender took back leaves this book too (fold-4)
        await MTCoinReplica.run(why: why)   // this phone's copy of the network's chains and its signed root (section 6)
    }
}


// MARK: - version 3 (Audit/COIN-TX-V3.md): every move of a key's balance is a signed record of its chain
/// THE BALANCE IS THE FOLD OF THE KEY'S CHAIN (the author's words 11.10.2026 19:5x UTC: "balances must be proven ... the Explorer
/// shows the proof of it locally and globally"; 20:5x: "take the proven balance yourself, check it as the critic and do it
/// yourself"). The book stays the phone's ledger; the chain is what anyone can fold: the key's first v3 record announces the book
/// (GENESIS, declared, never called proven), what the book holds above the chain is laid as a MINT within the time of its interval,
/// a SEND names the receiver's key under a blind only the pair opens, the receiver's RECV takes it, and an untaken SEND comes back
/// by a REFUND after a day. The node of the key's chain folds every record and refuses an overspend; so do the replicas, the phones
/// that keep a copy and the Explorer.
extension MTCoinTx {
    static let size3 = 5443
    typealias Kind3 = MTCoinChainRules.Kind
    private static let signed3 = Data("mt-coin-tx-v3".utf8)
    static var v2Cut: Int64 { MTCoinChainRules.v2Cut }
    static func fresh() -> Data {
        var n = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, n.count, &n)
        return Data(n)
    }
    /// The record of version 3, signed by the core (nil: no words, a field of the wrong size, or the core refused).
    static func build3(_ kind: Kind3, amount: UInt64, prev: String, nonce: Data, pair: Data = Data(count: 32), to: Data = Data(count: 32),
                       ref: String = zero, a: UInt64 = 0, b: UInt64 = 0, hands: Hands? = nil) -> Data? {
        guard let k = hands.map({ h in (pk: h.pk, sk: h.sk) }) ?? keys(), let p = unhex(prev), p.count == 32, let r = unhex(ref), r.count == 32, nonce.count == 16,
              pair.count == 32, to.count == 32 else { return nil }
        var body = magic
        body.append(3); body.append(kind.rawValue)
        body.append(le(amount)); body.append(le(UInt64(max(0, Date().timeIntervalSince1970 * 1000))))
        body.append(nonce); body.append(p); body.append(pair); body.append(to); body.append(r)
        body.append(le(a)); body.append(le(b)); body.append(k.pk)
        guard body.count == 2134, let sig = MontanaPQ.sign(seckey: k.sk, message: signed3 + body), sig.count == 3309 else { return nil }
        return body + sig
    }
    /// A record of version 3 read back -- believed only when its shape holds and the core verifies its signature.
    static func read3(_ rec: Data, known: Bool = false) -> Record? {
        let b = [UInt8](rec)
        guard b.count == size3, Data(b[0..<4]) == magic, b[4] == 3, let kind = Kind3(rawValue: b[5]) else { return nil }
        let amount = u64(b, 6)
        guard amount <= UInt64(Int.max), 0 < amount || kind == .genesis else { return nil }
        guard MTCoinChainRules.fieldsHold(kind: kind.rawValue, amount: amount, pair: Data(b[70..<102]), to: Data(b[102..<134]), ref: Data(b[134..<166]),
                                     a: u64(b, 166), b: u64(b, 174)) else { return nil }
        let body = Data(b[0..<2134]), pk = Data(b[182..<2134]), sig = Data(b[2134..<size3])
        guard known || MontanaPQ.verify(pubkey: pk, message: signed3 + body, signature: sig) else { return nil }
        var r = Record(id: name(rec), version: 3, coins: Int(amount), birthMs: u64(b, 14), pair: Data(b[70..<102]),
                       prev: hex(Data(b[38..<70])), from: keyTag(pk), bytes: rec)
        r.kind = kind.rawValue; r.to = Data(b[102..<134]); r.ref = hex(Data(b[134..<166])); r.a = u64(b, 166); r.b = u64(b, 174)
        r.nonce = Data(b[22..<38])
        return r
    }
    /// The state of a key's chain as its node folds it (POST /tx-head), and the node's own second.
    struct Chain3 { let head: String; let height: Int; let birth: Int64; let mintEnd: Int64; let proven: Int64; let declared: Int64; let v3: Bool; let now: Int64; let minted: Int64? }
    static func chain3(_ me: String, door: String) async -> Chain3? {
        let h = await ask(door + "/tx-head", ["from": me])
        guard h.code == 200, let o = h.obj, let head = o["head"] as? String, head.count == 64 else {
            // THE ROAD THAT FAILED IS SAID (link 11336, 29.10.2026): a silent nil left the diary of 13498CA8 with no word of why the
            // chain never answered; the node and the code are told, folded over ten minutes, never the key.
            MontanaTrace.markFolded("coin_chain3", "code=\(h.code) unreached=\(h.unreached ? 1 : 0) node=\(chainNode(ofDoor: door) ?? "?")", window: 600)
            return nil
        }
        func n(_ k: String) -> Int64 {
            if let s = o[k] as? String { return Int64(s) ?? 0 }
            return (o[k] as? NSNumber)?.int64Value ?? 0
        }
        let now = n("now")
        return Chain3(head: head, height: Int(n("height")), birth: n("birth"), mintEnd: n("mint_end"), proven: n("proven"),
                      declared: n("declared"), v3: n("v3") == 1, now: now == 0 ? Int64(Date().timeIntervalSince1970) : now,
                      minted: o["minted"] == nil ? nil : n("minted"))
    }
    /// One record of my key laid on my chain's head, the head read back and verified as mine first; a head that moved is asked
    /// again once. (the node's code, its word, the record laid).
    @MainActor static func layOnHead(hands: Hands? = nil, _ make: (Chain3) -> Data?) async -> (code: Int, word: String, rec: Data?) {
        guard let me = hands?.from ?? myKeyTag, let door = chainDoor(me) else { return (-1, "no key", nil) }
        for _ in 0..<2 {
            guard let st = await chain3(me, door: door) else { return (-1, "no head", nil) }
            guard await headIsMine(st.head, me: me, door: door) else { return (-1, "head unverified", nil) }
            guard let rec = make(st) else { return (-1, "no record", nil) }
            let a = await ask(door + "/tx-put", ["rec": rec.base64EncodedString()])
            let word = (a.obj?["error"] as? String) ?? ""
            if a.code == 200 { return (200, "", rec) }
            if a.code == 409, word == "not on the head" { continue }
            if a.code == -1, !a.unreached, (await ask(door + "/tx-get", ["id": name(rec)])).code == 200 { return (200, "", rec) }
            return (a.code, word, rec)
        }
        return (409, "not on the head", nil)
    }
    @MainActor private static var mintedAt: TimeInterval = 0
    @MainActor private static var mintDue = false
    /// THE BOOK'S MOVE ASKS ITS CHAIN WITHIN ONE WINDOW (the author's words 12.10.2026 12:5x UTC: «the minting has its own chain of time
    /// and as it is confirmed it releases the available»; «once in τ1»): one ask a window, however many coins the window holds.
    @MainActor static func mintSoon() {
        guard !mintDue else { return }
        mintDue = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(MTCoinChainRules.window)) {
            MainActor.assumeIsolated {
                mintDue = false
                Task { @MainActor in await reconcile() }
            }
        }
    }
    /// THE PERSON HERE MINTS (fold-7): online -- the app in front of the person -- or behind the living tunnel of the VPN.
    @MainActor static var here: Bool {
        UIApplication.shared.applicationState != .background || MontanaVPNTunnel.shared.status == .connected
    }
    /// The seconds the road to the node may take: a MINT reaching it later than this counts less than it names.
    nonisolated static let presentMargin: Int64 = 20
    /// Under the node's minute plus one beat, a MINT's interval never passes the freshness less the margin: no second here is lost.
    nonisolated static let presentBeat: UInt64 = 40
    @MainActor private static var presence: Task<Void, Never>?
    /// THE NODE SECOND THE PERSON CAME (the author's words 26.10.2026 09:2x UTC, links 8615 and 8617: «show how the coins are minted
    /// every second ... so that it works right over the network too»; «let it count so, then show visually what happens before the
    /// window is finalized»): the first second of this stay the chain's node told, nil while the person is away. A MINT counts from
    /// it and never from before it -- minting happens while the person is here (fold-7) -- and the wallet shows the same seconds
    /// rising while they are on their way (MTCoinSplit.minting).
    @MainActor private(set) static var hereFrom: Int64?
    /// The app came to the screen, the wallet opened or the tunnel rose: while the person stays here every beat asks the chain --
    /// before the online cut only to read the key's life the chain mints itself (fold-6), so the person's number grows with the chain
    /// and never by the book, which mints nothing after the time cut (MTLocalCoinLedger.priced).
    @MainActor static func beHere() {
        guard presence == nil else { return }
        hereFrom = nil
        presence = Task { @MainActor in
            while !Task.isCancelled, here {
                await reconcile()
                try? await Task.sleep(nanoseconds: presentBeat * 1_000_000_000)
            }
            presence = nil
            hereFrom = nil
            MTCoinSplit.shared.beat()
        }
    }
    /// THE CHAIN HOLDS WHAT THE BOOK HOLDS (sections 3-4). A key's first v3 record is its GENESIS: the book as it stands, at most
    /// what time could have minted since the coins began, announced and never called proven (before the v2 cut; a GENESIS of 0
    /// after it). After it, what the book holds above the chain is laid as a MINT of the time since the last one, at most what the
    /// interval allows -- once a window of τ1 (MTCoinChainRules.window), or at once when a send needs it. The node's clock decides the
    /// interval, never the phone's.
    @MainActor @discardableResult static func reconcile(force: Bool = false) async -> Chain3? {
        guard let me = myKeyTag, let door = chainDoor(me) else { return nil }
        // ONE PERSON'S BOOK ON ONE PERSON'S CHAIN (the critic 19.10.2026, T2: the author's word 20:25 «a separate person, wholly
        // separate»): a seat that moves during a wait seats another key and another book -- the book read before it would be laid on
        // the next person's chain. Every record is built only while the seat that began this stands and its key is the one laying.
        let seat = MTCoinSeat()
        guard var st = await chain3(me, door: door) else { return nil }
        // what the chain's node folds is told to the wallet's split, after every word of it
        func told(_ s: Chain3?) -> Chain3? {
            if let s, seat.stands { MTCoinSplit.shared.heard(proven: s.proven, declared: s.declared, opened: s.v3, fromCopy: false, height: s.height, second: s.now, mintEnd: s.mintEnd) }
            return s
        }
        guard seat.stands else { MontanaTrace.mark("coin_v3", "the seat moved -- nothing laid"); return nil }
        let book = Int64(MTLocalCoinLedger.shared.whole.balance)
        if !st.v3 {
            let amount = min(max(0, book), MTCoinChainRules.genesisRoom(height: st.height, birth: st.birth, at: st.now))
            let r = await layOnHead { s in seat.stands ? build3(.genesis, amount: UInt64(amount), prev: s.head, nonce: fresh()) : nil }
            MontanaTrace.mark("coin_v3", "genesis code=\(r.code) word=\(r.word) amount=\(amount)")
            guard r.code == 200, let again = await chain3(me, door: door) else { return nil }
            st = again
        }
        // ONLY THE CHAIN MINTS (section 4, fold-6): from the node's TX_TIME_CUT the chain credits the key's seconds itself, so the phone
        // lays no MINT and shows the fold /tx-head answers -- until the node's TX_ONLINE_CUT, past which a key's life mints nothing by itself
        guard st.now < MTCoinChainRules.timeCut else {
            // MINTING IS ITS OWN ROAD (fold-7; the author's words 23.10.2026 00:27 and 00:37 UTC: «minting is a separate entity, and it
            // happens if the person is online or behind the VPN»): the node counts of a MINT only what its interval holds of the last
            // mintFresh seconds before it takes it, so while the person is here the phone lays the seconds since the last MINT, never
            // older than the freshness less the road's margin; the node's minute between two MINTs is the pace
            if here, presence != nil, hereFrom == nil, MTCoinChainRules.onlineCut <= st.now { hereFrom = st.now }
            guard MTCoinChainRules.onlineCut <= st.now, st.now < MTCoinChainRules.mintStop, here, st.mintEnd + 60 <= st.now else { return told(st) }
            let from = hereFrom ?? st.now
            let r = await layOnHead { s in
                guard seat.stands, 0 < s.height, MTCoinChainRules.onlineCut <= s.now, s.now < MTCoinChainRules.mintStop else { return nil }
                let t1 = s.now, t0 = max(s.mintEnd, t1 - MTCoinChainRules.mintFresh + presentMargin, from)
                // the present seconds alone weigh it (fold-8): the life the node credited up to the online cut is not asked again
                let amount = MTCoinChainRules.present(t0: t0, t1: t1, at: t1 + presentMargin)
                guard 0 < amount, t0 + 60 <= t1 else { return nil }
                return build3(.mint, amount: UInt64(amount), prev: s.head, nonce: fresh(), a: UInt64(t0), b: UInt64(t1))
            }
            MontanaTrace.mark("coin_v3", "present mint code=\(r.code) word=\(r.word)")
            return told(r.code == 200 ? await chain3(me, door: door) : st)
        }
        let wall = Date().timeIntervalSince1970
        guard force || Double(MTCoinChainRules.window) <= wall - mintedAt else { return told(st) }
        mintedAt = wall
        let gap = book - st.proven - st.declared
        guard 0 < gap, st.mintEnd + 60 <= st.now - 120 else { return told(st) }
        let r = await layOnHead { s in
            guard seat.stands else { return nil }
            let t0 = s.mintEnd, t1 = s.now - 120
            // the key's time less what it minted (section 4, fold-3; from the second's cut 1 coin a second, weighed at the node's now,
            // the at it gives the record); a node that names no minted still folds by the interval
            let room = MTCoinChainRules.allowTime(t1 - s.birth, at: s.now) - (s.minted ?? MTCoinChainRules.allowTime(t0 - s.birth, at: s.now))
            let amount = min(book - s.proven - s.declared, room)
            guard 0 < amount, t0 + 60 <= t1 else { return nil }
            return build3(.mint, amount: UInt64(amount), prev: s.head, nonce: fresh(), a: UInt64(t0), b: UInt64(t1))
        }
        MontanaTrace.mark("coin_v3", "mint code=\(r.code) word=\(r.word) gap=\(gap)")
        return told(r.code == 200 ? await chain3(me, door: door) : st)
    }
    // -- the correspondents' coin keys, my open sends: files of the TimeChain's own folder (staying on the device). No lock over the
    // files (the layout law: a lock holds a word in memory, never a disk): the open sends are touched only on the main actor, and a
    // correspondent's key lost to a race comes again with their next about word. --
    private static func load(_ name: String) -> [String: Any] {
        guard let u = MTTimeChainPlace.dir()?.appendingPathComponent(name), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return o
    }
    private static func save(_ name: String, _ o: [String: Any]) {
        guard let u = MTTimeChainPlace.dir()?.appendingPathComponent(name), let d = try? JSONSerialization.data(withJSONObject: o) else { return }
        try? d.write(to: u, options: .atomic)
    }
    /// A correspondent's coin key, told in their about word (k): the key a SEND of version 3 commits to.
    static func peerFrom(_ conv: String) -> String? { (load("coin3-peers.json")["k"] as? [String: String])?[conv] }
    static func notePeerFrom(_ conv: String, _ from: String) {
        guard from.count == 64, from.allSatisfy({ ch in ch.isHexDigit }) else { return }
        var o = load("coin3-peers.json")
        var m = (o["k"] as? [String: String]) ?? [:]
        guard m[conv] != from else { return }
        m[conv] = from; o["k"] = m
        save("coin3-peers.json", o)
    }
    /// Whether this correspondent was already told my coin key (the about word carries it until then).
    static func toldKey(_ conv: String, _ k: String) -> Bool { (load("coin3-peers.json")["told"] as? [String: String])?[conv] == k }
    static func noteToldKey(_ conv: String, _ k: String) {
        var o = load("coin3-peers.json")
        var m = (o["told"] as? [String: String]) ?? [:]
        m[conv] = k; o["told"] = m
        save("coin3-peers.json", o)
    }
    static func forgetToldKey(_ conv: String) {
        var o = load("coin3-peers.json")
        var m = (o["told"] as? [String: String]) ?? [:]
        guard m.removeValue(forKey: conv) != nil else { return }
        o["told"] = m
        save("coin3-peers.json", o)
    }
    /// THE KEY DERIVED FOR THE WORD ABOUT ONESELF (the author's word 21.10.2026 09:41 UTC, E2E.sendAboutIfNeeded): once at a time,
    /// off the main thread; when it stands, every correspondent not yet told hears it.
    private static var deriving = false
    static func deriveForTheWord() {
        keyLock.lock(); let busy = deriving; deriving = true; keyLock.unlock()   // LOCK-OK: one flag
        guard !busy else { return }
        DispatchQueue.global(qos: .utility).async {
            let k = keys()
            keyLock.lock(); deriving = false; keyLock.unlock()   // LOCK-OK: one flag
            guard k != nil else { return }
            DispatchQueue.main.async { E2E.shared.broadcastAbout() }
        }
    }
    /// The coin key already derived in this process, never derived here (a main-thread caller must not pay the seed's derivation).
    static var cachedKeyTag: String? {
        keyLock.lock(); let c = keyCache; keyLock.unlock()   // LOCK-OK: one read of the cached key
        return c.map { k in keyTag(k.pk) }
    }
    private static func openSends() -> [[String: Any]] { (load("coin3-open.json")["open"] as? [[String: Any]]) ?? [] }
    private static func keepOpen(_ rows: [[String: Any]]) { save("coin3-open.json", ["open": rows]) }
    /// THE LETTER A PAID REACTION'S SEND STANDS UNDER, AS ITS WORD NAMED IT (MTCoinSend.give): the word moves no coins; it names
    /// the SEND, and the scan asked at once credits that SEND under the letter. A word later than the scan leaves the coins right
    /// and under no letter. The newest 256 names are kept.
    @MainActor static func heard(_ tx: String, on sid: String) {
        guard tx.count == 64, tx.allSatisfy({ ch in ch.isHexDigit }), !sid.isEmpty else { return }
        var rows = ((load(heardFile)["on"] as? [[String]]) ?? []).filter { r in r.first != tx }
        rows.append([tx, sid])
        save(heardFile, ["on": Array(rows.suffix(256))])
        guard !MTLocalCoinLedger.shared.whole.holds(.receive, refPrefix + tx) else { return }
        Task { @MainActor in await scanFresh(why: "reaction") }
    }
    private static let heardFile = "coin3-heard.json"
    private static func heardOn(_ tx: String) -> String? {
        ((load(heardFile)["on"] as? [[String]]) ?? []).last { r in r.first == tx }.flatMap { r in r.count == 2 ? r[1] : nil }
    }
    /// A name taken once (an auto-reaction's «auto:» and its letter): false if it stands. Two days are kept -- an auto-reaction pays
    /// only a letter born within a day (MTCoinSend.fresh).
    @MainActor static func once(_ name: String) -> Bool {
        let now = Date().timeIntervalSince1970
        var o = ((load(onceFile)["n"] as? [String: Double]) ?? [:]).filter { _, at in now - at < 2 * MTCoinSend.fresh }
        guard o[name] == nil else { return false }
        o[name] = now
        save(onceFile, ["n": o])
        return true
    }
    @MainActor static func release(_ name: String) {
        var o = (load(onceFile)["n"] as? [String: Double]) ?? [:]
        o[name] = nil
        save(onceFile, ["n": o])
    }
    private static let onceFile = "coin3-once.json"
    enum Send3 { case sent(String), pending, notApplicable(String), failed }
    private static let noReceiverKey = "no receiver key"   // NOT-UI: the trace's reason, and the one the send page names
    /// SENDS (version 3): the receiver's key known (their about word), my chain announced and holding the sum, the record names
    /// the declared part of it (proven is spent first), commits to the receiver's key under the pair's blind, and is laid on my
    /// chain's head. Anything that makes v3 impossible (an older correspondent, the chain not holding the sum yet) is said as
    /// notApplicable -- the version 2 road takes it until the cut.
    @MainActor static func send3(_ coins: Int, conv: String, on target: String? = nil) async -> Send3 {
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me), let pipe = MTPipeBook.key(for: conv), pipe.isWhole,
              let pair = pairTag(conv) else { return .notApplicable("no pipe") }
        guard let peer = peerFrom(conv), let peerBytes = unhex(peer), peerBytes.count == 32 else { return .notApplicable(noReceiverKey) }
        guard let first = await reconcile(force: true), first.v3, Int64(coins) <= first.proven + first.declared else { return .notApplicable("chain short") }
        let nonce = fresh()
        let blind = pipe.blind(nonce: nonce, by: MTCoinChainRules.blind(secret:nonce:))   // the item key's blind, made by the pipe's owner
        let commit = MTCoinChainRules.commitment(from: peerBytes, blind: blind)
        for attempt in 1...2 {
            guard let st = await chain3(me, door: door), st.v3, Int64(coins) <= st.proven + st.declared else { return .notApplicable("chain short") }
            guard await headIsMine(st.head, me: me, door: door) else { return .failed }
            guard let book = seat.book else { return .failed }
            let dec = max(0, Int64(coins) - st.proven)
            guard let rec = build3(.send, amount: UInt64(coins), prev: st.head, nonce: nonce, pair: pair, to: commit, a: UInt64(dec)) else { return .failed }
            let id = name(rec)
            guard book.sendHeld(coins, to: conv, ref: refPrefix + id, on: target) else { return .failed }
            let pending = pendingURL(id)
            if let pending { try? rec.write(to: pending, options: .atomic) }
            let word = await lay(rec)
            MontanaTrace.mark("coin_v3", "send word=\(word) coins=\(coins) dec=\(dec) id=\(id.prefix(12)) attempt=\(attempt)")
            guard seat.stands else { return .pending }   // the record waits in its person's folder (settle)
            switch word {
            case .left:
                if let pending { try? FileManager.default.removeItem(at: pending) }
                keepOpen(openSends() + [["id": id, "conv": conv, "coins": coins, "at": st.now]])
                MTCoinSplit.shared.laid(id, coins: coins, on: st.height)
                return .sent(id)
            case .notLeft, .behind:
                book.receive(coins, from: conv, ref: backPrefix + id, on: target)
                if let pending { try? FileManager.default.removeItem(at: pending) }
                if word == .notLeft { return .failed }
            case .unknown:
                keepOpen(openSends() + [["id": id, "conv": conv, "coins": coins, "at": st.now]])
                MTCoinSplit.shared.laid(id, coins: coins, on: st.height)
                return .pending
            }
        }
        return .failed
    }
    /// RECEIVES (version 3): a SEND of my pair that commits to my key is taken by a RECV on my chain -- the book credits it only
    /// when my chain holds it (200, or another device of my words took it: the SEND's node names me).
    @MainActor static func receive3(_ s: Record, conv: String) async -> Bool {
        let seat = MTCoinSeat()
        guard s.kind == Kind3.send.rawValue, let me = myKeyTag, let mine = unhex(me),
              let pipe = MTPipeBook.key(for: conv), pipe.isWhole else { return false }
        guard let blind = pipe.blinds(nonce: s.nonce, by: MTCoinChainRules.blind(secret:nonce:))
                .first(where: { b in MTCoinChainRules.commitment(from: mine, blind: b) == s.to }) else { return false }
        let book = MTLocalCoinLedger.shared.whole
        if book.holds(.receive, refPrefix + s.id) { return false }
        guard let st = await reconcile(), st.v3 else { return false }
        let r = await layOnHead { c in seat.stands ? build3(.recv, amount: UInt64(s.coins), prev: c.head, nonce: fresh(), to: blind, ref: s.id, a: s.a) : nil }
        var taken = r.code == 200
        if !taken, r.word == "settled" || r.word == "not yours", let door = chainDoor(s.from) {
            let f = await ask(door + "/tx-settle", ["send": s.id])
            taken = (f.obj?["state"] as? String) == "recv" && (f.obj?["by"] as? String) == me
        }
        MontanaTrace.mark("coin_v3", "recv code=\(r.code) word=\(r.word) taken=\(taken ? 1 : 0) id=\(s.id.prefix(12))")
        return taken && seat.book?.receive(s.coins, from: conv, ref: refPrefix + s.id, on: heardOn(s.id)) == true
    }
    /// A TRANSFER TO ONE'S OWN OTHER ACCOUNT IS ONE PAIR, SENT AND RECEIVED IN THE SAME STEP (the author's words 12.10.2026 10:2x UTC:
    /// «either the coins left or not -- there is no third -- this is point 0»; 12:3x, No.66: «a transfer to oneself in Montana must
    /// become one pair of records, sent and received»). The phone holds both seeds -- the person seated and the person on its shelf --
    /// so the SEND names the other key (knowOwn), and the RECV is laid at once on the other key's own chain with that key, the chain
    /// opened first by its GENESIS of the book its shelf holds, as its own phone would open it. Only then do the coins stand in the
    /// other person's book on the nodes, under the name their own scan credits them by: a SEND whose RECV did not stand stays the
    /// receiver's to take when seated, or comes back to its sender by the REFUND after a day -- never both.
    @MainActor static func knowOwn(seat: String, conv: String) async -> Hands? {
        guard let shelf = await Task.detached(priority: .userInitiated, operation: { MTSeats.shelfCoins(seat) }).value,
              let hands = await Task.detached(priority: .userInitiated, operation: { derive(shelf.words) }).value else {
            MontanaTrace.mark("coin_own", "seat=\(seat) no hands")
            return nil
        }
        notePeerFrom(conv, hands.from)
        return hands
    }
    @MainActor static func landOwn(seat: String, send id: String, coins: Int, conv: String) async {
        guard let shelf = await Task.detached(priority: .userInitiated, operation: { MTSeats.shelfCoins(seat) }).value,
              let hands = await Task.detached(priority: .userInitiated, operation: { derive(shelf.words) }).value,
              let e = MontanaSeedKeys.entropyFrom(mnemonic: shelf.words), e.count == 32,
              let me = myKeyTag, let door = chainDoor(me) else {
            MontanaTrace.mark("coin_own", "seat=\(seat) no hands -- the receiver takes it when seated")
            return
        }
        var v3 = false, taken = false, said = "v2"
        let g = await ask(door + "/tx-get", ["id": id])
        if g.code == 200, let b = (g.obj?["rec"] as? String).flatMap({ s in Data(base64Encoded: s) }) {
            v3 = b.count == size3
            if v3, let s = await Task.detached(priority: .userInitiated, operation: { read3(b) }).value, s.id == id,
               let pipe = MTPipeBook.key(for: conv), pipe.isWhole, let theirs = unhex(hands.from), let tdoor = chainDoor(hands.from) {
                if let blind = pipe.blinds(nonce: s.nonce, by: MTCoinChainRules.blind(secret:nonce:))
                    .first(where: { b in MTCoinChainRules.commitment(from: theirs, blind: b) == s.to }) {
                    if let st = await chain3(hands.from, door: tdoor), !st.v3 {
                        let amount = min(max(0, Int64(shelf.book)), MTCoinChainRules.genesisRoom(height: st.height, birth: st.birth, at: st.now))
                        let r = await layOnHead(hands: hands) { c in build3(.genesis, amount: UInt64(amount), prev: c.head, nonce: fresh(), hands: hands) }
                        MontanaTrace.mark("coin_own", "seat=\(seat) genesis code=\(r.code) word=\(r.word) amount=\(amount)")
                    }
                    let r = await layOnHead(hands: hands) { c in
                        build3(.recv, amount: UInt64(s.coins), prev: c.head, nonce: fresh(), to: blind, ref: s.id, a: s.a, hands: hands)
                    }
                    taken = r.code == 200
                    said = "recv code=\(r.code) word=\(r.word)"
                } else { said = "not their key" }
            }
        } else { said = "no record code=\(g.code)" }
        guard taken || (g.code == 200 && !v3) else {
            MontanaTrace.mark("coin_own", "seat=\(seat) coins=\(coins) \(said) -- the receiver takes it when seated, or it comes back")
            return
        }
        let move = MTCoinEntry(k: .receive, c: coins, ref: refPrefix + id, peer: conv, on: nil, at: Date().timeIntervalSince1970)
        let laid = await MTCoinVault.lay([move], entropy: e)
        MontanaTrace.mark("coin_own", "seat=\(seat) coins=\(coins) \(said) book=\(laid) id=\(id.prefix(12))")
    }
    /// An untaken SEND comes back after a day by a REFUND on my chain (section 5): its node's clock decides, one fate a SEND.
    @MainActor static func refundDue() async {
        let seat = MTCoinSeat()
        guard let me = myKeyTag, let door = chainDoor(me) else { return }
        await refundSpent2(me: me, door: door, seat: seat)
        guard seat.stands else { return }
        let rows = openSends()
        guard !rows.isEmpty else { return }
        var left: [[String: Any]] = []
        for o in rows {
            guard let id = o["id"] as? String, let conv = o["conv"] as? String, let coins = o["coins"] as? Int else { continue }
            let at = (o["at"] as? NSNumber)?.int64Value ?? 0
            let f = await ask(door + "/tx-settle", ["send": id])
            guard let book = seat.book else { return }   // the open sends stay in their person's folder
            let state = (f.obj?["state"] as? String) ?? ""
            if state == "recv" { continue }
            if state == "refund" { book.receive(coins, from: conv, ref: backPrefix + id, on: book.entry(.send, refPrefix + id)?.on); continue }
            guard state == "open", let st = await chain3(me, door: door), at + 86_460 <= st.now else { left.append(o); continue }
            let r = await layOnHead { c in seat.stands ? build3(.refund, amount: UInt64(coins), prev: c.head, nonce: fresh(), ref: id) : nil }
            MontanaTrace.mark("coin_v3", "refund code=\(r.code) word=\(r.word) id=\(id.prefix(12))")
            guard let after = seat.book else { return }
            if r.code == 200 { after.receive(coins, from: conv, ref: backPrefix + id, on: after.entry(.send, refPrefix + id)?.on) } else { left.append(o) }
        }
        guard seat.stands else { return }
        keepOpen(left)
    }
}


extension MTCoinTx {
    /// A V2 RECORD THAT SPENT COMES BACK AFTER ITS DAY (fold-4, P-3 of Agent 95; the author's words 19.10.2026 09:2x UTC «put it in» and
    /// «at 16:23 I sent 1898535 from T1 to the Android»): a v2 record laid on my opened chain names no receiver, so no chain could ever take
    /// its coins -- 18.10 T1 sent 1 369 000 and 2 000 000 that way to an Android phone, which reads no chain, and they stood for no one.
    /// My chain's node names my unsettled sends (/tx-unsettled); a v2 one a day old is taken back by a REFUND, and the book receives it
    /// under the send's own name, from the pair the send left to. A v3 SEND keeps its own road (the open list in refundDue).
    @MainActor static func refundSpent2(me: String, door: String, seat: MTCoinSeat) async {
        let u = await ask(door + "/tx-unsettled", ["from": me])
        guard u.code == 200, let rows = u.obj?["sends"] as? [[String: Any]], !rows.isEmpty, let st = await chain3(me, door: door) else { return }
        for o in rows {
            guard (o["v"] as? NSNumber)?.intValue == 2, let id = o["id"] as? String, let coins = Int((o["amount"] as? String) ?? ""),
                  let at = (o["at"] as? NSNumber)?.int64Value, at + 86_460 <= st.now else { continue }
            let r = await layOnHead { c in seat.stands ? build3(.refund, amount: UInt64(coins), prev: c.head, nonce: fresh(), ref: id) : nil }
            MontanaTrace.mark("coin_v3", "refund v2 code=\(r.code) word=\(r.word) coins=\(coins) id=\(id.prefix(12))")
            guard let book = seat.book else { return }
            if r.code == 200 { book.receive(coins, from: book.entry(.send, refPrefix + id)?.peer ?? "", ref: backPrefix + id, on: nil) }
        }
    }
    /// The v2 records this book credited, each with its sender's key, its coins and its pair: a REFUND by the sender takes them back.
    private static let credits2File = "coin2-credits.json"
    private static let gonePrefix = "txgone:"   // NOT-UI: the book's name of a credit its sender took back
    static func noteCredit2(_ id: String, from: String, coins: Int, conv: String) {
        var o = load(credits2File)
        var m = (o["c"] as? [String: [String: Any]]) ?? [:]
        guard m[id] == nil else { return }
        m[id] = ["f": from, "n": coins, "p": conv]; o["c"] = m
        save(credits2File, o)
    }
    /// THE COINS ARE EITHER GONE OR NOT (constitution, article 8): a v2 record credited here whose sender's REFUND took it back at its
    /// chain node leaves this book by one move under its name, whatever the balance (retake: the truth of a debt). Asked once an hour.
    @MainActor static func creditsGone() async {
        let seat = MTCoinSeat()
        var o = load(credits2File)
        var m = (o["c"] as? [String: [String: Any]]) ?? [:]
        let now = Date().timeIntervalSince1970
        guard !m.isEmpty, 3600 <= now - ((o["at"] as? NSNumber)?.doubleValue ?? 0) else { return }
        for (id, c) in m {
            guard let from = c["f"] as? String, let coins = (c["n"] as? NSNumber)?.intValue, let conv = c["p"] as? String,
                  let door = chainDoor(from) else { m[id] = nil; continue }
            let f = await ask(door + "/tx-settle", ["send": id])
            guard let book = seat.book else { return }   // the credits' file stays in its person's folder
            guard f.code == 200, (f.obj?["state"] as? String) == "refund" else { continue }
            if book.holds(.send, gonePrefix + id) || book.retake(coins, to: conv, ref: gonePrefix + id) { m[id] = nil }
            MontanaTrace.mark("coin_v3", "credit gone coins=\(coins) id=\(id.prefix(12))")
        }
        o["c"] = m; o["at"] = now
        save(credits2File, o)
    }
}

// MARK: - the phone's copy of the network's coin chains (COIN-TX-V3 section 6)
/// EVERY PHONE THAT KEEPS A COPY IS A NODE OF THE COIN CHAINS (the author's words 11.10.2026 19:5x UTC: "the core and the nodes are
/// every device ... agreeing to keep a copy they keep a copy of the chain of time of the coins"; 20:3x: "check as the critic that
/// globally on every device the node is with the new build"). With the person's consent to keep for others (MTKeeping.others) the
/// phone pulls what each chain node took, verifies every signature with the core, folds every chain by the nodes' own rules,
/// computes the root of the newest checkpoint itself and signs it with the seed's coin key; the nodes keep the signature and the
/// Explorer counts it in the quorum. The whole network's chains, never only the correspondents': a holder's signature must not say
/// whose chains it cares about. The diary says what this phone holds (coin_replica), never whose chains.
enum MTCoinReplica {
    struct Row: Codable { let id: String; let rec: String; let at: Int64; let node: String }
    /// at: the moment of the last round, kept with the rows -- a process a push woke is born with nothing in memory. known: the
    /// names of the rows whose signature verified here once.
    struct Held: Codable { var seq: [String: Int] = [:]; var rows: [Row] = []; var at: Double? = nil; var known: [String]? = nil }
    typealias St = MTCoinChainRules.St
    typealias SendInfo = MTCoinChainRules.SendInfo
    @MainActor private static var running = false
    @MainActor private static var ranAt: TimeInterval = 0
    private static var url: URL? { MTTimeChainPlace.dir()?.appendingPathComponent("coin-replica.json") }
    private static func load() -> Held {
        guard let u = url, let d = try? Data(contentsOf: u), let h = try? JSONDecoder().decode(Held.self, from: d) else { return Held() }
        return h
    }
    private static func save(_ h: Held) {
        guard let u = url, let d = try? JSONEncoder().encode(h) else { return }
        try? d.write(to: u, options: .atomic)
    }
    nonisolated private static func bytes(_ s: String) -> Data? { MTCoinChainRules.bytes(s) }
    /// One record folded onto its key's state by the chain's rules (MTCoinChainRules.step, the nodes' _tx_step).
    nonisolated static func step(_ s: St, _ p: MTCoinTx.Record, _ at: Int64, _ sends: [String: SendInfo], _ settled: Set<String>) -> (next: St?, wait: Bool) {
        MTCoinChainRules.step(s, MTCoinChainRules.Rec(id: p.id, version: p.version, kind: p.kind, amount: Int64(p.coins), from: p.from, to: p.to, ref: p.ref,
                                            a: p.a, b: p.b), at, sends, settled)
    }
    struct Folded { var keys = 0; var records = 0; var root = ""; var bad = 0; var waiting = 0; var mine: St?; var verified = Set<String>() }
    /// Every chain folded from its first record in its own order (prev), a RECV after the SEND it settles; then the root of the
    /// checkpoint T exactly as the node computes it (V3 section 6): for every key in ascending from, its last record and its count at T.
    nonisolated static func fold(_ rows: [Row], at T: Int64, me: String? = nil, known: Set<String> = []) -> Folded {
        var out = Folded()
        var byPrev: [String: [String: MTCoinTx.Record]] = [:]
        var atOf: [String: Int64] = [:]
        var seen = Set<String>()
        for row in rows where !seen.contains(row.id) {
            seen.insert(row.id)
            guard let d = Data(base64Encoded: row.rec), let r = MTCoinTx.read(d, known: known.contains(row.id)), r.id == row.id else { out.bad += 1; continue }
            out.verified.insert(r.id)
            if r.version == 1 { continue }   // a version 1 row stands on no chain
            guard MTCoinTx.chainNode(of: r.from) == row.node else { out.bad += 1; continue }   // a node serves only its own chains
            byPrev[r.from, default: [:]][r.prev] = r
            atOf[r.id] = row.at
        }
        var st: [String: St] = [:], sends: [String: SendInfo] = [:], settled = Set<String>(), broken = Set<String>()
        var order: [String: [String]] = [:]
        var moved = true
        while moved {
            moved = false
            for (from, chain) in byPrev where !broken.contains(from) {
                var s = st[from] ?? St()
                while let r = chain[s.head] {
                    let at = atOf[r.id] ?? 0
                    let next = step(s, r, at, sends, settled)
                    if next.wait { break }
                    guard let n = next.next else { broken.insert(from); out.bad += 1; break }
                    if r.version == 3, r.kind == MTCoinTx.Kind3.send.rawValue {
                        sends[r.id] = SendInfo(from: from, amount: Int64(r.coins), at: at, to: r.to, dec: Int64(r.a))
                    }
                    if r.version == 2, let d = MTCoinChainRules.v2Spent(s, amount: Int64(r.coins)) {
                        sends[r.id] = SendInfo(from: from, amount: Int64(r.coins), at: at, to: Data(count: 32), dec: d)
                    }
                    if r.version == 3, r.kind == MTCoinTx.Kind3.recv.rawValue || r.kind == MTCoinTx.Kind3.refund.rawValue { settled.insert(r.ref) }
                    order[from, default: []].append(r.id)
                    s = n; moved = true
                }
                st[from] = s
            }
        }
        for (from, chain) in byPrev where !broken.contains(from) { if chain[st[from]?.head ?? MTCoinChainRules.zero] != nil { out.waiting += 1 } }
        if let me, !broken.contains(me) { out.mine = st[me] }
        var h = SHA256()
        h.update(data: Data("mt-coin-root-v1".utf8))
        for from in order.keys.sorted() {
            let ids = (order[from] ?? []).filter { id in (atOf[id] ?? Int64.max) <= T }
            guard let last = ids.last, let f = bytes(from), let l = bytes(last) else { continue }
            var c = UInt64(ids.count).littleEndian
            h.update(data: f); h.update(data: l); h.update(data: withUnsafeBytes(of: &c) { p in Data(p) })
            out.keys += 1; out.records += ids.count
        }
        out.root = MTCoinTx.hex(Data(h.finalize()))
        return out
    }
    /// One round: what each chain node took since the last round, the whole fold, the root of the nodes' newest checkpoint computed
    /// here and signed with the seed's coin key at both nodes. Once in ten minutes at most, only with the consent to keep for others.
    @MainActor static func run(why: String) async {
        guard MTKeeping.others, !running, 600 <= Date().timeIntervalSince1970 - ranAt, let k = MTCoinTx.keys() else { return }
        running = true
        ranAt = Date().timeIntervalSince1970
        defer { running = false }
        // THE BOOK IS READ AND WRITTEN OFF THE SCREEN'S THREAD (the author's words 18.10.2026 11:3x-11:4x UTC: «the chats lag»; «as
        // the critic, find the cause of all the lags»): the whole network's rows, decoded and encoded on the main thread every ten
        // minutes -- T1 on 2241, 11:38:36Z, a frame of the chat list held 438 ms in JSONEncoder under MTCoinReplica.save.
        var held = await Task.detached(priority: .utility) { load() }.value
        // ONCE IN TEN MINUTES ACROSS PROCESSES (23.10.2026, the author's words 09:16 UTC: «I quit Montana on the Mac, and it hangs and
        // starts by itself»): ranAt lives in memory, and every process a push woke was born with it at zero -- each wake pulled and
        // folded the whole network again, a signature verified per row (sample of a wake on the Mac 09:32:48: 5.6 s of 25 under
        // MTCoinReplica.fold, MontanaPQ.verify on top). The round's moment stands in the file it folds.
        guard 600 <= Date().timeIntervalSince1970 - (held.at ?? 0) else { return }
        held.at = Date().timeIntervalSince1970
        var pulled = 0
        for n in MTCoinTx.chainNodes {
            let door = "https://" + n.host + "/pushwake"
            var since = held.seq[n.name] ?? 0
            for _ in 0..<64 {
                let a = await MTCoinTx.post(door + "/tx-since", ["since": since])
                guard a.code == 200, let txs = a.obj?["txs"] as? [[String: Any]] else { break }
                for x in txs {
                    guard let id = x["id"] as? String, let rec = x["rec"] as? String, let seq = (x["seq"] as? NSNumber)?.intValue else { continue }
                    held.rows.append(Row(id: id, rec: rec, at: (x["at"] as? NSNumber)?.int64Value ?? 0, node: n.name))
                    since = max(since, seq); pulled += 1
                }
                held.seq[n.name] = since
                if txs.count < 512 { break }
            }
        }
        let kept = held
        await Task.detached(priority: .utility) { save(kept) }.value
        let me = MTCoinTx.keyTag(k.pk)
        guard let door = MTCoinTx.chainDoor(me) else { return }
        let r = await MTCoinTx.post(door + "/tx-root", [:])
        guard r.code == 200, let T = (r.obj?["at"] as? NSNumber)?.int64Value, let nodeRoot = r.obj?["root"] as? String else {
            MontanaTrace.mark("coin_replica", "why=\(why) pulled=\(pulled) rows=\(held.rows.count) no checkpoint code=\(r.code)")
            return
        }
        let rows = held.rows
        let known = Set(held.known ?? [])
        let f = await Task.detached(priority: .utility) { fold(rows, at: T, me: me, known: known) }.value
        if f.verified != known {
            held.known = f.verified.sorted()
            let verified = held
            await Task.detached(priority: .utility) { save(verified) }.value
        }
        // the person's own chain as this copy folded it: the wallet's split hears it before the node's word (MTCoinSplit)
        if f.bad == 0, let mine = f.mine { MTCoinSplit.shared.heard(proven: mine.proven, declared: mine.declared, opened: mine.v3, fromCopy: true, height: mine.height, second: T, mintEnd: mine.mintEnd) }
        var signed = 0
        if f.bad == 0, 0 < f.keys, let root = bytes(f.root) {
            var t = UInt64(T).littleEndian
            let msg = Data("mt-coin-root-sig-v1".utf8) + withUnsafeBytes(of: &t) { p in Data(p) } + root
            if let sig = MontanaPQ.sign(seckey: k.sk, message: msg) {
                for n in MTCoinTx.chainNodes {
                    let a = await MTCoinTx.post("https://" + n.host + "/pushwake/tx-root-sign",
                                                ["pk": k.pk.base64EncodedString(), "at": T, "root": f.root, "sig": sig.base64EncodedString()])
                    if a.code == 200 { signed += 1 }
                }
            }
        }
        MontanaTrace.mark("coin_replica", "why=\(why) keys=\(f.keys) records=\(f.records) pulled=\(pulled) bad=\(f.bad) waiting=\(f.waiting) T=\(T) root=\(f.root.prefix(12)) same=\(f.root == nodeRoot ? 1 : 0) signed=\(signed)")
    }
}

extension MTCoinTx {
    /// A node's answer for a reader outside this type (the phone's copy of the chains): the code and the body.
    static func post(_ url: String, _ body: [String: Any]) async -> (code: Int, obj: [String: Any]?) {
        let a = await ask(url, body)
        return (a.code, a.obj)
    }
}
