import Foundation
import AuthenticationServices
import SwiftUI
import UIKit

// ════════════════════════════════════════════════════════════
// MONTANA: SIGN-IN BY THE PHONE NUMBER
// ════════════════════════════════════════════════════════════
// The author's words 06.10.2026 18:1x-18:4x MSK: «build the same page for the Montana messenger as the Business has, and put it
// through their bot»; «attach the number at once»; «the name is given from there too». The page is the Business's own
// (MTBusinessPhone.swift), carried over by the platform's own means. The person is born on this phone by the one road of a birth;
// the Business's one service confirms that this number belongs to this key and signs the confirmation with its ML-DSA-65 key,
// which this app holds pinned and proves by the core's own verify (MTPhoneProof). The roads of the confirmation come from the
// service itself (health): no outer service is named anywhere in the app, and without a living service there is no road on the
// screen, never a dead button.

/// The confirmation service on Montana's own site (Info.plist MontanaPhoneService): the roads it keeps, the start of a
/// confirmation, the wait for it, the code of the bot's own sign-in redeemed.
enum MTPhoneService {
    static var base: String {
        "https://" + (Bundle.main.object(forInfoDictionaryKey: "MontanaPhoneService") as? String ?? "").lowercased() + "/b/v1"
    }
    /// One road of a confirmation as the service names it: its number (1, 2, 3), its title in the person's language, its glyph.
    struct Road: Decodable, Identifiable, Equatable {
        var channel: Int
        var title: String
        var glyph: String
        var id: Int { channel }
        private enum Keys: String, CodingKey { case channel, title, glyph }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            channel = try c.decode(Int.self, forKey: .channel)
            // The title comes as one word, or as a word for each language the service speaks.
            if let one = try? c.decode(String.self, forKey: .title) {
                title = one
            } else {
                let many = try c.decode([String: String].self, forKey: .title)
                title = many[MTLanguage.code] ?? many["en"] ?? many.values.first ?? ""
            }
            let g = (try? c.decode(String.self, forKey: .glyph)) ?? ""
            glyph = UIImage(systemName: g) == nil ? "phone.fill" : g
        }
    }
    /// The roads, and beside them the bot's own sign-in, named apart so that a build reading only the roads never offers it.
    struct Health: Decodable {
        var ok: Bool; var paths: [Road]; var signIn: Road?
        private enum CodingKeys: String, CodingKey { case ok, paths, signIn = "account" }
    }
    static let signInChannel = 3
    /// The start's answer: the nonce the outer link carries (no secret there), the claim this phone alone holds and waits with,
    /// the link, the term.
    struct Started: Decodable { var nonce: String; var claim: String; var link: String; var app_link: String?; var expires_ms: UInt64 }
    /// The person's card as the bot's profile names it, given with the confirmation to this claim alone: the name, the bio, the
    /// face, and the public name the profile is reached by there.
    struct Card: Identifiable { var id = UUID(); var name: String; var bio: String; var photo: Data?; var publicName: String }
    enum Wait { case confirmed(Data, Card?), again, expired, failed, mismatch, unverified }

    /// The roads the service keeps now; none when it does not answer.
    static func roads() async -> [Road] {
        guard let u = URL(string: base + "/health") else { return [] }
        var q = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        q.httpMethod = "GET"
        guard let got = try? await URLSession.shared.data(for: q), (got.1 as? HTTPURLResponse)?.statusCode == 200,
              let h = try? JSONDecoder().decode(Health.self, from: got.0), h.ok else { return [] }
        // The bot's own sign-in first when the service offers it: it is the road the person takes.
        return ((h.signIn.map { [$0] } ?? []) + h.paths).filter { 0 < $0.channel && !$0.title.isEmpty }
    }
    /// The confirmation begins: the number, the key it is for (SHA-256 of the person's public key, hex), the road, and the app
    /// the sign-in comes back to (the service's word 06.10.2026 18:38 MSK: the messenger has its own way back).
    static func start(e164: String, subject: String, channel: Int) async -> Started? {
        guard let u = URL(string: base + "/phone/start"),
              let body = try? JSONSerialization.data(withJSONObject: ["e164": e164, "subject": subject, "channel": channel, "app": "messenger"]) else { return nil }
        var q = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        q.httpMethod = "POST"
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        q.httpBody = body
        guard let got = try? await URLSession.shared.data(for: q), (got.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(Started.self, from: got.0)
    }
    /// One long wait (the service holds it 25 seconds): the confirmation, «not yet», or the term ran out. Only the claim takes
    /// the confirmation away: the nonce alone, as the outer service saw it in the link, is answered «gone».
    static func wait(nonce: String, claim: String) async -> Wait {
        var c = URLComponents(string: base + "/phone/wait")
        c?.queryItems = [URLQueryItem(name: "nonce", value: nonce), URLQueryItem(name: "claim", value: claim)]
        guard let u = c?.url else { return .failed }
        var q = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        q.httpMethod = "GET"
        guard let got = try? await URLSession.shared.data(for: q), let code = (got.1 as? HTTPURLResponse)?.statusCode else { return .failed }
        switch code {
        case 200: return attestation(in: got.0).map { .confirmed($0, card(in: got.0)) } ?? .failed
        case 204: return .again
        case 410: return .expired
        default: return .failed
        }
    }
    /// The bot's own sign-in came back with its code: the service redeems it with the verifier it alone holds and answers with
    /// the confirmation itself -- the verified number must be the one asked for.
    static func finish(nonce: String, claim: String, code: String) async -> Wait {
        guard let u = URL(string: base + "/account/finish"),
              let body = try? JSONSerialization.data(withJSONObject: ["nonce": nonce, "claim": claim, "code": code]) else { return .failed }
        var q = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        q.httpMethod = "POST"
        q.setValue("application/json", forHTTPHeaderField: "Content-Type")
        q.httpBody = body
        guard let got = try? await URLSession.shared.data(for: q), let status = (got.1 as? HTTPURLResponse)?.statusCode else { return .failed }
        switch status {
        case 200: return attestation(in: got.0).map { .confirmed($0, card(in: got.0)) } ?? .failed
        case 409: return .mismatch
        case 403: return .unverified
        case 410: return .expired
        default: return .failed
        }
    }
    /// The card beside the confirmation: the name (first and last), the bio, the face, the public name; a card with nothing in it
    /// is none.
    static func card(in d: Data) -> Card? {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = o["card"] as? [String: Any] else { return nil }
        func word(_ k: String) -> String { (c[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let name = [word("first"), word("last")].filter { !$0.isEmpty }.joined(separator: " ")
        let photo = (c["photo"] as? String).flatMap { Data(base64Encoded: $0) }
        let held = word("nick")
        if name.isEmpty && word("bio").isEmpty && photo == nil && held.isEmpty { return nil }
        return Card(name: name, bio: word("bio"), photo: photo, publicName: held)
    }
    /// The confirmation's bytes, whichever way the answer carries them: raw, hex, or hex under «attest» in JSON.
    static func attestation(in d: Data) -> Data? {
        if d.prefix(4) == Data("MTBA".utf8) { return d }
        if let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let hex = o["attest"] as? String { return Data(montanaHex: hex) }
        return String(data: d, encoding: .utf8).flatMap { Data(montanaHex: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

/// THE NUMBER CONFIRMED FOR THIS PERSON: the service's signed confirmation in the Business's own frame, byte for byte
/// (mt-business attest.rs): MTBA, version 1, the road (1 or 2), the moment in milliseconds (u64, little-endian), SHA-256 of the
/// person's public key, the number's length and the number (E.164), then the ML-DSA-65 signature over
/// SHA-256("mt-biz-attest", 0x00, everything before it) -- the one domained hash of the set (MTPipe.domained). It lies in the
/// person's own content (SeedScope: a copy carries it, a seat parks it) and is read only once the pinned key proves it.
enum MTPhoneProof {
    struct Opened: Equatable { var e164: String; var subject: Data; var channel: UInt8; var atMs: UInt64 }
    /// The service's public key (ML-DSA-65, 1952 bytes): the Business core's pinned service_key.hex byte for byte, generated on
    /// Lauterbourg 06.10.2026 (mt-business 0df73b3) and the very file the service on the German server signs by -- SHA-256 of
    /// the file 0b1ac90dc7f0c4a94e54a79759c8cb6f8ac054915ee5c50b353539a21ec154e7 on both, measured 06.10.2026 18:5x MSK.
    private static let serviceKey = Data(montanaHex: "19d1c9dc0c8ea78f745ecfce35e1ed59ed4d118da2a6a7c1994e95c7ff95ffe501ea3f1ab56ee0a76ebb606ef06448063c89bfe084c924fe34bb845bb400825633c784c670e681998bbd86da0f286c16cf76fe40779c9d448e81c3589998c23cac79d1cb36b57f185b49b4228e0a8a6cf66d320e898d5aabdca859c8db9093619d1d5739ab568fb23fd7cbdb01dfc84eeb0da3f9a3a3c298c03d9ccd12a10adda4633b11ffeb969c54423669b5a7f0673d45fd52d009cb0e88dc3d7267a9e99ee0e4a1c1cffc7001b181e392df52320a9918e03e17e3f6e26bd9be70a0d7e74db6caa8943f8ab14b61016ee9fd8800e59dc708054c17bd23264e6c2dd617c272a9a2c5643c47c473f20d9558be44e2942871c6b971e67a62d1fbbd50cd3749603ccca6aa1a221c5ba3aac3bcf46b43d8c980ac58282a5346288ac7cb21dfb1f78ad21b12201b00cf080ec8733f8de6248f2d7c51cccf7286afd7d81093dedf534272ac8ec7bc5b16081b99447de1b986c467ed2732bd3abeb4a445b5ed2c2b047c5245c44536211c7687c42f2dafcc9422f30e6a9b5f5acbb97ba40acb793bcfc61a53f7d3bd116ef49aad1a3bf7b8f63126c5d5f6c810847e1e1c67155d98a77e56d09905cd28f8c2f3c95bfa5ce76f113a8f6cdcb3c963e1208e0896773eaa7e143dd11f5c535df5ade9648607d6238306661d9867810182f3eed683737e09f36b3e0b70397d54f2a65d9b9f2794f7c37c106348b807e85aa28e360169ea6b83a47348d6e1cd729ae4405abf843aec209810d3e67dd7facc1871fa05975331721c009645961e0686d662eaf7198543bbc8d5f863d121f180fc4be7ff21cbeb1de09461d0be9269cfe03d5709df7f3d21c9c331bb51de691880c44abda65dbaaba49ce574db2bc9c294c04c11f82855b4248ac09b77f7176d5a6bac66e71856711aad39b1e9808400b49ce0878ca18103908f24b3f78aa278a3cf5fd5dfcba051154fc11a046c6ba32498cf706a138c73c5a2b3fc326cce3151b775206494c8819fe8b1ed30dc8f4ee8f6e472ff6e43bd5bbe3cd2e5a428edf9d0e1fbfb4347f8de2107c651a6a5659aa853381fbff962f928dfabfce92d7fbaeaa55f334cc21439f363e6e8f28e66adf4eb968c9e45ca1d1f9dc580947870526af2c22f8cf52d9115ad69ed41f1cae420021a253246dd8f7c29a1e24f0ff378aaf86f63a154b138573e61809e1db0522af57a15824ab9aa7db1e867a1ca8c41c119f7d47920c4b55fdf5f0031869eb95809ff1cd59e976df292d9c4d6839f21aa49db0acf0a610037bc9ad62b707bf69ba72e1b146bf5dfbd71f2ab7494168aafacdb74f717ea19dbaf8872822036d90eee98edeb50e18ed942ebd3527f7f4c39309efc272433459aff4c88d1893d08611b09a05fdf549875886902070f8eeef6d90d7f80859553acc6dc044bcd50e416d7fa0816eecbab2cec886de7a3f783b5cc03aef3be25aa20e94a05d9c3ea57c1b1a5f6620f26de2ca4a53567e705d49fb1501f93955f072c014379c15e1964816ffdbb2870c848e662d210686df469d31c389259518506a50e766ab0d09013a00b68f0061d129ccd613babdea449fb10b9759fd74c0927c6bddd1d5434a00d1ebade16d7d273ec276375f1482aee9a5d7d204a9591deb6a746a0bc80ab23c6a8d1739599b8add8543c30c9a31fe4690f8fe93d529193a781e571a1a59b1ca2359a2ffbacd7f4c564fc5419fb0784b0c168193a4c36e24c4fde8cf10818bc62c8f1bcca9433889f3706a807c288fcd466830cf088a7c77d769c7f56163a627a4e5331bf71bbe4331ad1d098377a228b1742366d8ed9c20d2ebf95e7e1183919b8e54a65caa771d02234d284161330bdfd76d02bd1a54b6bdb97cafaa210c97b5d10677a195a53821d6c31e3a665b0649969924706b42cbfb842e23b496b8a4b101dbe316de84953c4e3155f19f3481a583058acd3b51510ddcb2943ff5f634c1a35f090b26090dbde9ac303d670ba7133b7a521c0a65c52d1eb297c4aa547043fe02732901cc273879e2f5fc8d9b73f7cb31b9160d19c83defa0449239dfc3ce0046f9a15e8cdcf8d620e76582ef912ab048816fe50e49be522f7dec329fa427e60088eb2cb91e048c2825e8db5aab90e33325fa988e0af028d7ef62d6ba7ac033271bf85478b353f8bcc48d7c43892ba2b5884967b4bbd7979589b1c6fa635847eebb386ce725f34e7582597c33ee273743cc4674217c5e1b79eaa26b4efe7b5225ca7839242936646a41799c5f0eca8620cf9087aabf8c693306e9b9f537c1d6262b8a8436c085bdffe45ceffc4cee29427dfaa92e4f67571e9875778436218d619ae77a1145f05d0ab9a2c5bd63684ab075321b9480d017598b87ca505250334ade0ad531bb03afdc59ce21f76e2ca717ed95f197edb91727969d5f13350335a056a12b0a56d8ca3554fd996fa9204ca3072ff553ab85f1d013b878811af7b0b08655ccb36320d40fdf64c539a32986b62187d22ff8922815b30ec1fd5da0fa386809b87bc476cf53c575530293dfcdf8db5f6bcb9fec1dc4dc6662528c1ecb59026b8a9043cfa7cd43113c1266361c6ec0cc1983c5f192400bec494b055e55575404472b8caf4a19ba91e1b37cd4f0b1be95bc6413df3b17bbc0249f3f5f72e4122e0768335c74324f49928921a4face01c67aee2675cf90586fdcf2cf44df530f66fffb090b2e621b55b2a4280a80cb40d30f2") ?? Data()
    private static let frontLength = 4 + 1 + 1 + 8 + 32 + 1
    private static let signatureLength = 3309

    /// The frame read and proved: nil for a frame of another shape, a number of another shape, or a signature the pinned key
    /// does not prove.
    static func open(_ d: Data) -> Opened? {
        let b = [UInt8](d)
        guard frontLength < b.count, Data(b[0..<4]) == Data("MTBA".utf8), b[4] == 1, [UInt8(1), UInt8(2)].contains(b[5]) else { return nil }
        let unsignedLength = frontLength + Int(b[frontLength - 1])
        guard b.count == unsignedLength + signatureLength else { return nil }
        let e164 = String(decoding: b[frontLength..<unsignedLength], as: UTF8.self)
        guard MTPhoneCountries.valid(e164) else { return nil }
        let unsigned = Data(b[0..<unsignedLength])
        guard MontanaPQ.verify(pubkey: serviceKey, message: MTPipe.domained("mt-biz-attest", [unsigned]),
                               signature: Data(b[unsignedLength...])) else { return nil }
        var at: UInt64 = 0
        for k in 0..<8 { at |= UInt64(b[6 + k]) << UInt64(8 * k) }
        return Opened(e164: e164, subject: Data(b[14..<46]), channel: b[5], atMs: at)
    }
    /// A confirmation is kept only when the pinned key proves it and it names this person's key and the number asked for.
    @discardableResult
    static func keep(_ a: Data, e164: String) -> Bool {
        guard let pub = MontanaSeed.keys()?.pub, let o = open(a), o.subject == MontanaQueueKeys.sha256(pub), o.e164 == e164 else { return false }
        UserDefaults.standard.set(a, forKey: "phoneProof")
        return true
    }
    /// The number confirmed for the person seated, proved again at every reading.
    static var number: String? { UserDefaults.standard.data(forKey: "phoneProof").flatMap { open($0) }?.e164 }
    /// The confirmation leaves this phone at the person's own removal (MTPhoneSheet); no service holds anything to let go.
    static func forget() { UserDefaults.standard.removeObject(forKey: "phoneProof") }
    /// The confirmed number as the field writes it: the plus, the calling code, the national digits in groups.
    static var shownNumber: String? {
        guard let n = number else { return nil }
        let digits = String(n.dropFirst())
        return MTPhoneCountries.shown(digits, code: MTPhoneCountries.match(digits, prefer: MTPhoneCountries.initial)?.code)
    }
}

/// THE CARD COMES INTO THE PROFILE BY THE PERSON'S CHOICE (the author's words 06.10.2026 18:3x MSK «the name is given from there
/// too»; App Review 5.1.2(i) and the author's word 08.10.2026 17:2x MSK «do everything as it should be»): nothing of another
/// service's profile is used or published without the person's permission. The bot's card is offered (MTPhoneCardSheet) with
/// only what it would change -- a field the person already filled is theirs and stays -- and only the parts the person leaves on
/// come in: the name, the bio and the face into the profile, the public name the profile is reached by there into the person's
/// name in Montana (montana.quest/n/), taken at the keeper of names by the one road of a taking (MontanaNamePlane.take).
enum MTPhoneCard {
    /// What the card would change here; nil when it would change nothing, and then nothing is asked.
    @MainActor static func offered(_ c: MTPhoneService.Card?) -> MTPhoneService.Card? {
        guard var c else { return nil }
        let d = UserDefaults.standard
        func blank(_ key: String) -> Bool { (d.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        c.name = blank("userName") ? String(MTCrown.plain(c.name).prefix(64)) : ""
        if !blank("profileBio") { c.bio = "" }
        if !(d.data(forKey: "avatarData") ?? Data()).isEmpty { c.photo = nil }
        if let p = c.photo, UIImage(data: p) == nil { c.photo = nil }
        let held = NameSheet.normalized(c.publicName)
        c.publicName = !held.isEmpty && MontanaNames.currentName == nil && NameSheet.rejection(held) == nil ? held : ""
        if c.name.isEmpty && c.bio.isEmpty && c.photo == nil && c.publicName.isEmpty { return nil }
        return c
    }
    /// The parts the person left on, and nothing else.
    @MainActor static func adopt(_ c: MTPhoneService.Card, name takeName: Bool, bio takeBio: Bool, face takeFace: Bool, publicName takePublic: Bool) {
        let d = UserDefaults.standard
        func blank(_ key: String) -> Bool { (d.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var took: [String] = []
        let name = String(MTCrown.plain(c.name).prefix(64))   // the profile's own bound and rule: 64 letters, a crown is never taken in
        if takeName, !name.isEmpty, blank("userName") { d.set(name, forKey: "userName"); E2E.shared.broadcastName(); took.append("name") }
        if takeBio, !c.bio.isEmpty, blank("profileBio") { d.set(c.bio, forKey: "profileBio"); E2E.shared.broadcastAbout(); took.append("bio") }
        if takeFace, let face = c.photo, (d.data(forKey: "avatarData") ?? Data()).isEmpty { MontanaSelfFace.set(face); took.append("face") }
        let held = NameSheet.normalized(c.publicName)
        if takePublic, !held.isEmpty, MontanaNames.currentName == nil, NameSheet.rejection(held) == nil {
            took.append("public")
            Task {
                let out = await MontanaNamePlane.take(held)
                if case .taken = out { MontanaTrace.mark("phone_card", "public name taken") } else { MontanaTrace.mark("phone_card", "public name not taken") }
            }
        }
        MontanaTrace.mark("phone_card", "took=" + (took.isEmpty ? "-" : took.joined(separator: ",")))
    }
}

/// The countries a number is chosen by: the region and its calling code (ITU-T E.164), written once. The name is the system's
/// own, in the person's language; the flag is the region's two letters.
enum MTPhoneCountries {
    struct Country: Identifiable, Hashable { var region: String; var code: String; var id: String { region } }
    private static let table = "US 1,CA 1,RU 7,KZ 7,EG 20,ZA 27,GR 30,NL 31,BE 32,FR 33,ES 34,HU 36,IT 39,RO 40,CH 41,AT 43,GB 44,DK 45,SE 46,NO 47,PL 48,DE 49,PE 51,MX 52,CU 53,AR 54,BR 55,CL 56,CO 57,VE 58,MY 60,AU 61,ID 62,PH 63,NZ 64,SG 65,TH 66,JP 81,KR 82,VN 84,CN 86,TR 90,IN 91,PK 92,AF 93,LK 94,MM 95,IR 98,MA 212,DZ 213,TN 216,LY 218,SN 221,CI 225,GH 233,NG 234,CM 237,ET 251,KE 254,TZ 255,UG 256,ZW 263,PT 351,LU 352,IE 353,IS 354,AL 355,MT 356,CY 357,FI 358,BG 359,LT 370,LV 371,EE 372,MD 373,AM 374,BY 375,AD 376,MC 377,UA 380,RS 381,ME 382,HR 385,SI 386,BA 387,MK 389,CZ 420,SK 421,LI 423,GT 502,SV 503,HN 504,NI 505,CR 506,PA 507,BO 591,EC 593,PY 595,UY 598,HK 852,MO 853,KH 855,LA 856,BD 880,TW 886,MV 960,LB 961,JO 962,SY 963,IQ 964,KW 965,SA 966,YE 967,OM 968,AE 971,IL 972,BH 973,QA 974,MN 976,NP 977,TJ 992,TM 993,AZ 994,GE 995,KG 996,UZ 998"   // NOT-UI: regions and their calling codes
    static let all: [Country] = table.split(separator: ",").compactMap { row in
        let p = row.split(separator: " ")
        return p.count == 2 ? Country(region: String(p[0]), code: String(p[1])) : nil
    }
    static var initial: Country {
        let r = Locale.current.region?.identifier ?? "US"
        return all.first { $0.region == r } ?? all[0]
    }
    static func name(_ c: Country) -> String { MTLanguage.locale.localizedString(forRegionCode: c.region) ?? c.region }
    static func flag(_ c: Country) -> String {
        String(String.UnicodeScalarView(c.region.unicodeScalars.compactMap { Unicode.Scalar(127_397 + $0.value) }))
    }
    /// The one shape of a number the service and the core accept (mt-business valid_e164): the plus, then 6 to 15 digits, the
    /// first of them never 0.
    static func valid(_ s: String) -> Bool {
        guard s.first == "+" else { return false }
        let digits = s.dropFirst()
        return (6...15).contains(digits.count) && digits.allSatisfy { $0.isASCII && $0.isNumber } && digits.first != "0"
    }
    /// The country a number's digits name: the longest calling code they begin with; where two countries share a code (1, 7)
    /// the one the person chose keeps it.
    static func match(_ digits: String, prefer: Country) -> Country? {
        var n = min(3, digits.count)
        while 0 < n {
            let lead = String(digits.prefix(n))
            if prefer.code == lead { return prefer }
            if let c = all.first(where: { $0.code == lead }) { return c }
            n -= 1
        }
        return nil
    }
    /// The number as the field shows it: the plus, the calling code, then the national digits -- up to ten of them as 3 3-2-2,
    /// more in threes. Digits that name no country stand as typed.
    static func shown(_ digits: String, code: String?) -> String {
        guard !digits.isEmpty else { return "" }
        guard let code, digits.hasPrefix(code), code.count < digits.count else { return "+" + digits }
        let national = Array(digits.dropFirst(code.count))
        var out = "+" + code + " "
        for (i, ch) in national.enumerated() {
            if national.count <= 10 {
                if i == 3 { out += " " } else if i == 6 || i == 8 { out += "-" }
            } else if 0 < i, i % 3 == 0 {
                out += " "
            }
            out.append(ch)
        }
        return out
    }
}

/// THE FLOW OF ONE CONFIRMATION: the roads read from the service, the start for the person's own key, the outer service opened
/// by the link the service hands, and the long wait until the signed confirmation comes or its term ends. The person is never
/// born here: the login page's door of the number makes them first, by the one road of a birth (MontanaOnboardingView.createSeed).
@MainActor
final class MTPhoneFlow: ObservableObject {
    @Published var roads: [MTPhoneService.Road] = []
    @Published var asked = false   // the service was asked at least once: its silence is spoken from here on, never guessed before
    @Published var waiting: MTPhoneService.Road?
    @Published var refusal: String?
    @Published private(set) var link: URL?      // the bot's link the service handed, opened by the person's own tap
    @Published private(set) var opened = false  // the bot was opened at least once: the page says it waits
    @Published private(set) var signIn = false  // the road taken is the bot's own sign-in: no link stands on the page
    @Published var offered: MTPhoneService.Card?   // the bot's card waits for the person's choice before the door says done
    private var appLink: URL?                     // the door into the other app, when the service named one this app may open
    private var returnTo: URL?                    // where the sign-in comes back to (its redirect: this app's own scheme)
    private var e164: String?
    private var finished: (() -> Void)?
    private var session: ASWebAuthenticationSession?
    /// The flow whose sign-in stands now: the one entrance of links hands the way back to it (MTPhoneReturn).
    static weak var current: MTPhoneFlow?
    private var started: MTPhoneService.Started?
    private var task: Task<Void, Never>?
    private var asking: Task<MTPhoneService.Wait, Never>?
    private static var nowMs: UInt64 { UInt64(max(0, Date().timeIntervalSince1970 * 1000)) }

    /// The roads are asked while the door stands: a service silent at the first look (no network yet at the first launch) is
    /// asked again every five seconds, until it names its roads or the door leaves.
    func watch() async {
        while !Task.isCancelled {
            let got = await MTPhoneService.roads()
            roads = got
            asked = true
            if !got.isEmpty { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }
    func cancel() {
        task?.cancel()
        task = nil
        asking?.cancel()
        asking = nil
        waiting = nil
        started = nil
        link = nil
        opened = false
        session?.cancel()
        session = nil
        signIn = false
        appLink = nil
        returnTo = nil
        e164 = nil
        finished = nil
        release()
    }
    /// The person came back from the bot: a wait held across the app's sleep may hang on a connection that died with it, so it
    /// is let go and asked again at once, not after its 35 seconds; the service keeps the answer for the claim until the term.
    func cameBack() {
        asking?.cancel()
    }
    /// THE BOT OPENS BY THE PERSON'S OWN TAP, as often as they tap; nothing leaves the app before it.
    func openLink() {
        guard let u = link else { return }
        opened = true
        guard signIn else { UIApplication.shared.open(u); return }
        // THE BOT'S OWN SIGN-IN OPENS IN ITS OWN APP, its native confirmation; a phone without that app gets the issuer's page in
        // the system's sheet. Either way the way back carries the code to this page.
        if let door = appLink {
            UIApplication.shared.open(door) { ok in Task { @MainActor [weak self] in if !ok { self?.openPage(u) } } }
        } else {
            openPage(u)
        }
    }
    /// THE WAY BACK IS THIS APP'S OWN SCHEME: the redirect registered with the bot for the messenger is montana://tglogin
    /// (the author's word 06.10.2026 18:37 MSK). A code caught by another app on that scheme is worth nothing: only the service
    /// holds the PKCE verifier that redeems it.
    private func openPage(_ u: URL) {
        guard let to = returnTo, let scheme = to.scheme?.lowercased() else { UIApplication.shared.open(u); return }
        let back: (URL?, Error?) -> Void = { url, _ in
            Task { @MainActor [weak self] in
                self?.session = nil
                if let url { self?.cameBackWith(url) }
            }
        }
        let s: ASWebAuthenticationSession
        if scheme == "https" {
            if #available(iOS 17.4, *), let host = to.host {
                s = ASWebAuthenticationSession(url: u, callback: .https(host: host, path: to.path.isEmpty ? "/" : to.path), completionHandler: back)
            } else {
                UIApplication.shared.open(u)   // the universal link brings the way back
                return
            }
        } else {
            s = ASWebAuthenticationSession(url: u, callbackURLScheme: scheme, completionHandler: back)
        }
        s.presentationContextProvider = MTPhoneSheetAnchor.shared
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }
    /// THE OTHER APP'S DOOR IS FOLLOWED ONLY UNDER THE SCHEME THIS APP NAMES (Info.plist MontanaPhoneAppDoor): the service's answer
    /// names the door, the app decides whether it is one it may open -- never a telephone, a message or a stranger's app.
    static func appDoor(_ link: String?) -> URL? {
        let allowed = (Bundle.main.object(forInfoDictionaryKey: "MontanaPhoneAppDoor") as? String ?? "").lowercased()
        guard !allowed.isEmpty, let s = link, let u = URL(string: s), u.scheme?.lowercased() == allowed else { return nil }
        return u
    }
    /// THE LINK THE SERVICE HANDS IS OPENED ONLY ON THE WEB'S SECURE ROAD (point 0 of the constitution): an answer that named
    /// another scheme is not followed; the service's answer is no word of command over the phone.
    static func road(_ link: String) -> URL? {
        guard let u = URL(string: link), u.scheme?.lowercased() == "https", u.host?.isEmpty == false else { return nil }
        return u
    }
    /// The road is taken: the person's key, then the start, the link, the wait.
    func start(_ road: MTPhoneService.Road, e164: String, done: @escaping () -> Void) {
        guard waiting == nil else { return }
        waiting = road
        task = Task {
            await MontanaSeed.birth?.value   // a person still being born behind the number's page: the road waits for the birth
            let keys = Task.detached(priority: .userInitiated) { MontanaSeed.keys()?.pub }
            guard let pub = await keys.value else {
                refuse("The identity could not be stored on this device")
                return
            }
            guard let s = await MTPhoneService.start(e164: e164, subject: MontanaQueueKeys.sha256(pub).montanaHexString, channel: road.channel),
                  let u = Self.road(s.link) else {
                refuse("The confirmation service did not answer. Try again in a minute.")
                return
            }
            started = s
            link = u
            MontanaTrace.mark("phone_door", "started channel=\(road.channel)")
            if road.channel == MTPhoneService.signInChannel {
                // THE SIGN-IN'S ANSWER COMES WITH THE WAY BACK, not by the wait: the code the sign-in returns is redeemed here.
                signIn = true
                self.e164 = e164
                finished = done
                appLink = Self.appDoor(s.app_link)
                let back = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "redirect_uri" }?.value
                returnTo = back.flatMap { URL(string: $0) }
                Self.current = self
                MTPhoneReturn.expect(returnTo)
                return
            }
            while !Task.isCancelled {
                if s.expires_ms < Self.nowMs { refuse("The confirmation took too long. Start again."); return }
                let ask = Task { await MTPhoneService.wait(nonce: s.nonce, claim: s.claim) }
                asking = ask
                switch await ask.value {
                case .confirmed(let a, let card):
                    confirm(a, card: card, e164: e164, channel: road.channel, done: done)
                    return
                case .mismatch, .unverified: refuse("The confirmation does not match this number."); return
                case .again: continue
                case .expired: refuse("The confirmation took too long. Start again."); return
                case .failed: if !ask.isCancelled { try? await Task.sleep(nanoseconds: 2_000_000_000) }
                }
            }
        }
    }
    /// The sign-in came back -- the link the other app opens after its confirmation, or the sheet's own end -- with the code;
    /// the service redeems it and answers with the confirmation itself.
    func cameBackWith(_ url: URL) {
        guard signIn, let s = started, let n = e164, let done = finished else { return }
        guard let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            refuse("The sign-in did not come back. Start again.")
            return
        }
        MontanaTrace.mark("phone_door", "sign-in came back")
        task = Task {
            switch await MTPhoneService.finish(nonce: s.nonce, claim: s.claim, code: code) {
            case .confirmed(let a, let card): confirm(a, card: card, e164: n, channel: MTPhoneService.signInChannel, done: done)
            case .mismatch: refuse("The confirmation does not match this number.")
            case .unverified: refuse("This account has no verified number.")
            case .expired: refuse("The confirmation took too long. Start again.")
            case .again, .failed: refuse("The confirmation service did not answer. Try again in a minute.")
            }
        }
    }
    private func confirm(_ a: Data, card: MTPhoneService.Card?, e164: String, channel: Int, done: @escaping () -> Void) {
        guard MTPhoneProof.keep(a, e164: e164) else { refuse("The confirmation does not match this number."); return }
        MontanaTrace.mark("phone_door", "confirmed channel=\(channel)")
        waiting = nil
        release()
        // The card is offered, never taken: the door says done once the person has chosen (MTPhoneCardSheet).
        if let offer = MTPhoneCard.offered(card) { finished = done; offered = offer; return }
        done()
    }
    /// The person answered the card's sheet, by its checkmark, its cross or a pull down: the door's way on.
    func answered() {
        let go = finished
        finished = nil
        offered = nil
        go?()
    }
    private func release() {
        if Self.current === self { Self.current = nil; MTPhoneReturn.expect(nil) }
    }
    private func refuse(_ key: String) {
        waiting = nil
        refusal = key
        release()
        MontanaTrace.mark("phone_door", "refused")
    }
}

/// THE WAY BACK OF THE SIGN-IN: the scheme and host it returns to while a sign-in stands, read by the one entrance of links
/// (MontanaMeeting.handleLink) on whatever thread a link lands.
enum MTPhoneReturn {
    private static let lock = NSLock()
    private static var key: String?
    private static func form(_ u: URL) -> String { (u.scheme ?? "").lowercased() + "://" + (u.host ?? "").lowercased() }
    static func expect(_ to: URL?) {
        lock.lock()   // LOCK-OK: one word in memory
        key = to.map { form($0) }
        lock.unlock()
    }
    static func matches(_ url: URL) -> Bool {
        lock.lock()   // LOCK-OK: one word in memory
        defer { lock.unlock() }
        return key != nil && form(url) == key
    }
}

/// The window the system's sign-in sheet rises over: the top of the one stack of modals (MTTop).
final class MTPhoneSheetAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MTPhoneSheetAnchor()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { MTTop.controller?.view.window } ?? ASPresentationAnchor()
    }
}

/// THE NUMBER'S DOOR (the Business's own, the author's word 06.10.2026 18:1x MSK: «the same page as the Business has»): one
/// field -- the flag of the country the number names and its mark, the number with its calling code, the clear mark -- and
/// «Next» at the foot. The flag follows the code the person types; its mark opens the countries with a search. «Next» takes the
/// bot's own sign-in when the service offers it, one road when it keeps one, and asks how the code should come when it keeps
/// several. While a confirmation waits, the door says so, with the way back (the cross) and the bot opened again. Without a
/// living service the question's sheet says one honest line and, where the page has a way on, gives the door to go on without
/// a number.
struct MTPhoneDoor: View {
    var onConfirmed: () -> Void
    /// The way on without a number (the login page): the number is confirmed later from the profile.
    var onWithout: (() -> Void)? = nil
    @StateObject private var flow = MTPhoneFlow()
    @State private var chosen = MTPhoneCountries.initial
    @State private var digits = MTPhoneCountries.initial.code
    @State private var countries = false
    @State private var asking = false
    @FocusState private var typing: Bool
    @Environment(\.scenePhase) private var phase
    /// The country the digits name; nil while they name none (the field then shows a globe).
    private var country: MTPhoneCountries.Country? { MTPhoneCountries.match(digits, prefer: chosen) }
    /// THE NUMBER AS TYPED: a number no country names is taken as written -- the service and the sign-in judge it, not a table
    /// of countries; a number that names one must be longer than its code.
    private var e164: String? {
        if let c = country, digits.count <= c.code.count { return nil }
        guard (6...15).contains(digits.count), digits.first != "0" else { return nil }
        return "+" + digits
    }
    private var shown: Binding<String> {
        Binding(get: { MTPhoneCountries.shown(digits, code: country?.code) }, set: { typed in
            digits = String(typed.filter { $0.isASCII && $0.isNumber }.prefix(15))
            if let c = MTPhoneCountries.match(digits, prefer: chosen) { chosen = c }
        })
    }
    private var without: (() -> Void)? {
        guard let go = onWithout else { return nil }
        return { asking = false; go() }
    }

    var body: some View {
        Group {
            if let road = flow.waiting {
                waitingFace(road)
            } else {
                VStack(spacing: 16) {
                    field
                    // WHO CONFIRMS AND WHO KEEPS IS SAID BEFORE THE NUMBER LEAVES (the author's words 10.10.2026 17:2x-17:3x MSK:
                    // «state that by number one can, that we do not keep them»; App Review 5.1.1(i)): the bot confirms, the
                    // service signs and forgets, the confirmation stays on this phone.
                    Text("A messaging bot confirms your number. Montana keeps no phone numbers: the confirmation stays on this phone.")
                        .font(.footnote).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    foot
                }
            }
        }
        .frame(maxWidth: 420)
        .task { await flow.watch() }
        .task {
            try? await Task.sleep(nanoseconds: 400_000_000)   // a field focused while its page still rises does not take the keyboard
            typing = true
        }
        .onDisappear { flow.cancel() }   // a door that leaves leaves its wait: nothing walks on behind the person
        .onChange(of: phase) { _, now in if now == .active { flow.cameBack() } }
        .onChange(of: countries) { _, open in if !open { typing = true } }
        .sheet(isPresented: $countries) {
            MTPhoneCountrySheet(chosen: country ?? chosen) { c in
                chosen = c
                digits = c.code
            }
        }
        .sheet(isPresented: $asking) {
            MTPhoneRoadSheet(flow: flow, onWithout: without) { road in
                asking = false
                guard let n = e164 else { return }
                flow.start(road, e164: n, done: onConfirmed)
            }
        }
        .mtPhoneWord($flow.refusal, title: "Phone number")
        .sheet(item: $flow.offered, onDismiss: { flow.answered() }) { card in
            MTPhoneCardSheet(card: card) { name, bio, face, publicName in
                MTPhoneCard.adopt(card, name: name, bio: bio, face: face, publicName: publicName)
            }
        }
    }

    private var field: some View {
        HStack(spacing: 0) {
            Button { typing = false; countries = true } label: {
                HStack(spacing: 6) {
                    if let c = country {
                        // USER-DATA: the flag of the country the number names
                        Text(verbatim: MTPhoneCountries.flag(c)).font(.title2)
                    } else {
                        Image(systemName: "globe").font(.title3).foregroundColor(.white)
                    }
                    Image(systemName: "arrowtriangle.down.fill").font(.caption2).foregroundColor(.white)
                }
                .frame(minWidth: 64, minHeight: 64)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Country"))
            TextField("Phone number", text: shown)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .font(.title3.weight(.semibold)).foregroundColor(.white)
                .monospacedDigit()
                .focused($typing)
            if (country?.code.count ?? 0) < digits.count {
                Button { digits = country?.code ?? "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundColor(.gray)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.trailing, 8)
        .frame(height: 64)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MontanaOctagon.barMaterial))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(typing ? 1 : 0.35), lineWidth: typing ? 2 : 1))
    }

    /// «Next» stands whatever the service says: the question comes after the number, and the sheet of the question speaks the
    /// service's silence honestly, with the way on where the page has one. THE NUMBER IS OPTIONAL IN SIGHT (audit No.57, A-12):
    /// where the page has a way on, it stands under «Next» at once -- a person, or a reviewer without the bot's messenger, is
    /// never asked for a number to go on (5.1.1(v): «Apps may not require users to enter personal information to function»).
    private var foot: some View {
        VStack(spacing: 12) {
            nextButton
            if let without {
                Button { without() } label: { Text("Continue without a number") }
                    .buttonStyle(MTLoginDoorStyle())
            }
        }
    }

    private var nextButton: some View {
        Button {
            typing = false
            // THE BOT'S OWN SIGN-IN IS THE ROAD TAKEN when the service offers it; a service that keeps one road is not asked
            // about -- its page stands at once; several roads are asked.
            let door = flow.roads.first { $0.channel == MTPhoneService.signInChannel }
            if let road = door ?? (flow.roads.count == 1 ? flow.roads.first : nil), let n = e164 {
                flow.start(road, e164: n, done: onConfirmed)
            } else {
                asking = true
            }
        } label: { Text("Next") }
            .buttonStyle(MTLoginDoorStyle(tint: MontanaOctagon.platformBlue))
            .disabled(e164 == nil)
    }

    /// THE PAGE OF THE BOT: the platform's prominent capsule at the large size, in the blue of my bubbles as the number's door
    /// wears it, opens the bot; the service's link stands under it as the web writes it (the sign-in shows none); once the bot
    /// was opened the page says it waits. The cross leaves the wait.
    private func waitingFace(_ road: MTPhoneService.Road) -> some View {
        VStack(spacing: 12) {
            HStack {
                MontanaCallMark(glyph: "xmark", label: "Cancel") { flow.cancel() }
                Spacer()
            }
            Spacer(minLength: 0)
            Image(systemName: road.glyph).font(.system(size: 44, weight: .semibold)).foregroundColor(.white).accessibilityHidden(true)
            Text("Tap the button to confirm your number in our bot, then come back here.")
                .font(.body).foregroundColor(.white).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { flow.openLink() } label: {
                Text("Verify Number")
                    .textCase(.uppercase)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(MontanaOctagon.platformBlue)
            .disabled(flow.link == nil)
            if flow.link != nil, flow.signIn {
                EmptyView()   // the sign-in shows no link: its page is the other app's own
            } else if let link = flow.link {
                Button { flow.openLink() } label: {
                    // USER-DATA: the bot's link as the confirmation service hands it
                    Text(verbatim: link.absoluteString)
                        .font(.footnote).foregroundColor(Color.white.opacity(0.7))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().tint(.white).frame(minHeight: 44)   // the service is handing the link
            }
            if flow.opened {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Waiting for the confirmation…").font(.subheadline).foregroundColor(.white)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// HOW THE CODE COMES: a sheet from the foot of the screen, the question, and one row for every road the service keeps -- its
/// glyph and its name in the person's language, both the service's own; the whole row is the target. While the service is
/// still being asked, the platform's spinner; when it answers with none, the honest line and, where the page has one, the way
/// on without a number.
struct MTPhoneRoadSheet: View {
    @ObservedObject var flow: MTPhoneFlow
    var onWithout: (() -> Void)?
    var onRoad: (MTPhoneService.Road) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                MontanaCallMark(glyph: "xmark", label: "Close") { dismiss() }
            }
            Text("How would you like to get the code?")
                .font(.title.bold()).foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            if !flow.roads.isEmpty {
                ForEach(flow.roads) { road in
                    Button { onRoad(road) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: road.glyph).font(.title2.weight(.semibold)).foregroundColor(.white)
                                .frame(width: 36).accessibilityHidden(true)
                            // USER-DATA: the road's own name, as the confirmation service names it in the person's language
                            Text(verbatim: road.title).font(.title3).foregroundColor(.white)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } else if flow.asked {
                Text("Phone number confirmation is unavailable right now").font(.subheadline).foregroundColor(.gray)
                if let onWithout {
                    Button { onWithout() } label: { Text("Continue without a number") }
                        .buttonStyle(MTLoginDoorStyle())
                        .padding(.top, 12)
                }
            } else {
                ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 56)   // the service is being asked for its roads
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24).padding(.top, 16)
        .presentationDetents([.height(340)])
        .preferredColorScheme(.dark)
    }
}

/// THE COUNTRIES: the platform's sheet with its search; the country the number names and the phone's own region first, then
/// every country by its name in the person's language; the whole row is the target.
struct MTPhoneCountrySheet: View {
    let chosen: MTPhoneCountries.Country
    var onChoose: (MTPhoneCountries.Country) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var first: [MTPhoneCountries.Country] {
        let home = MTPhoneCountries.initial
        return home == chosen ? [chosen] : [chosen, home]
    }
    private var rest: [MTPhoneCountries.Country] {
        MTPhoneCountries.all.filter { !first.contains($0) }
            .sorted { MTPhoneCountries.name($0).localizedCompare(MTPhoneCountries.name($1)) == .orderedAscending }
    }
    private var found: [MTPhoneCountries.Country] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits = q.filter { $0.isASCII && $0.isNumber }
        return (first + rest).filter { c in
            MTPhoneCountries.name(c).localizedCaseInsensitiveContains(q) || c.region.localizedCaseInsensitiveContains(q)
                || (!digits.isEmpty && c.code.hasPrefix(digits))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section { ForEach(first) { row($0) } }
                    Section { ForEach(rest) { row($0) } }
                } else {
                    Section { ForEach(found) { row($0) } }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search for a country or region"))
            .scrollContentBackground(.hidden).montanaPageGround()
            .navigationTitle("Choose your country or region").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ c: MTPhoneCountries.Country) -> some View {
        Button { onChoose(c); dismiss() } label: {
            HStack(spacing: 14) {
                // USER-DATA: a country's flag, its name in the system's words, its calling code
                Text(verbatim: MTPhoneCountries.flag(c)).font(.title2)
                Text(verbatim: MTPhoneCountries.name(c) + " (+" + c.code + ")").foregroundColor(.white)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .listRowBackground(MTGlassRowPlate())
    }
}

/// WHAT THE BOT'S PROFILE GIVES IS CHOSEN HERE (App Review 5.1.2(i): another service's data is used or published only with the
/// person's permission): every part the card would change stands as the platform's own switch -- the face, the name and the bio on,
/// for they only fill what the profile still lacks; the public name off, for it publishes the person, until the person turns it on.
/// The checkmark takes what is on; the cross and a pull down take nothing.
struct MTPhoneCardSheet: View {
    let card: MTPhoneService.Card
    var onTake: (Bool, Bool, Bool, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = true
    @State private var bio = true
    @State private var face = true
    @State private var publicName = false

    var body: some View {
        NavigationStack {
            List {
                if !card.name.isEmpty || !card.bio.isEmpty || card.photo != nil {
                    Section {
                        if let d = card.photo, let picture = UIImage(data: d) {
                            Toggle(isOn: $face) {
                                HStack(spacing: 12) {
                                    Image(uiImage: picture).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(Circle())
                                    Text("Photo").foregroundColor(.white)
                                }
                            }
                        }
                        if !card.name.isEmpty {
                            Toggle(isOn: $name) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Name").foregroundColor(.white)
                                    // USER-DATA: the name the bot's profile gives
                                    Text(verbatim: card.name).font(.footnote).foregroundColor(.secondary)
                                }
                            }
                        }
                        if !card.bio.isEmpty {
                            Toggle(isOn: $bio) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Bio").foregroundColor(.white)
                                    // USER-DATA: the bio the bot's profile gives
                                    Text(verbatim: card.bio).font(.footnote).foregroundColor(.secondary).lineLimit(3)
                                }
                            }
                        }
                    } footer: {
                        Text("Only what your profile still lacks is filled, and only what is on. The people you write to see your profile.")
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
                if !card.publicName.isEmpty {
                    Section {
                        Toggle(isOn: $publicName) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Public name").foregroundColor(.white)
                                // USER-DATA: the public name the bot's profile is reached by
                                Text(verbatim: "@" + card.publicName).font(.footnote).foregroundColor(.secondary)
                            }
                        }
                    } footer: {
                        Text("A public name lets anyone who knows it write to you first. It stays off unless you turn it on.")
                    }
                    .listRowBackground(MTGlassRowPlate())
                }
            }
            .scrollContentBackground(.hidden).montanaPageGround()
            .navigationTitle("Your messenger profile").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { MontanaCloseMark { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { MontanaDoneMark { onTake(name, bio, face, publicName); dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// THE NUMBER'S OWN SHEET, for a person already in Montana (the author's word 06.10.2026 18:3x MSK: «attach the number at
/// once»): the door of the sign-in from the profile; confirmed, the number stands in the profile, and the card is offered.
/// A CONFIRMED NUMBER IS TAKEN BACK HERE, the account staying (App Review 5.1.1(ii): «an easily accessible and understandable way
/// to withdraw consent»): the number lives on this phone alone (no service keeps one, 10.10.2026), so taking it back is
/// forgetting it here -- at once, with or without a network.
struct MTPhoneSheet: View {
    var done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var held = MTPhoneProof.shownNumber
    @State private var asking = false
    var body: some View {
        NavigationStack {
            Group {
                if let n = held {
                    List {
                        Section {
                            // USER-DATA: the person's own confirmed number
                            Text(verbatim: n).foregroundColor(.white)
                        } footer: {
                            Text("This number is kept on this phone and in your sealed copies. Montana keeps no phone numbers.")
                        }
                        .listRowBackground(MTGlassRowPlate())
                        Section {
                            Button(role: .destructive) { asking = true } label: { Text("Remove Number") }
                        }
                        .listRowBackground(MTGlassRowPlate())
                    }
                    .scrollContentBackground(.hidden)
                } else {
                    VStack(spacing: 18) {
                        MTPhoneDoor(onConfirmed: done)
                        Spacer()
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .montanaPageGround()
            .navigationTitle("Phone number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { MontanaCloseMark { dismiss() } } }
            .confirmationDialog("Remove this number?", isPresented: $asking, titleVisibility: .visible) {
                Button("Remove Number", role: .destructive) { remove() }
            }
        }
        .preferredColorScheme(.dark)
    }
    private func remove() {
        MTPhoneProof.forget()
        held = nil
        MontanaTrace.mark("phone_dir", "removed by the person")
        done()
    }
}

extension View {
    /// One word of the number's door to the person, in the platform's alert; the alert ends the word.
    func mtPhoneWord(_ word: Binding<String?>, title: LocalizedStringKey) -> some View {
        alert(title, isPresented: Binding(get: { word.wrappedValue != nil }, set: { if !$0 { word.wrappedValue = nil } })) {
            Button("OK", role: .cancel) { word.wrappedValue = nil }
        } message: { Text(LocalizedStringKey(word.wrappedValue ?? "")) }
    }
}
