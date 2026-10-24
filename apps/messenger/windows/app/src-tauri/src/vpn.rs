//! THE VPN'S SERVERS (iOS MontanaVPN.swift: MontanaVPNConfig, MontanaVPNParse, MontanaXrayConfig, MontanaVPNSubscription).
//! The deterministic side of the VPN wall: a server link of every scheme the Xray engine speaks (vless, vmess, trojan, ss,
//! hysteria2, wireguard, socks) and a row for the schemes it does not; the plan's body in its forms (a base64 blob of links,
//! plain text with `#profile-*` lines, the JSON array of whole engine configs, the sing-box JSON); the outbound in the engine's
//! own config words; the link again from the row (copy). The engine itself is not here (see `docs/WINDOWS.md`, VPN).
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

#[derive(Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Proto {
    Vless,
    Vmess,
    Trojan,
    Shadowsocks,
    Hysteria2,
    Wireguard,
    Socks,
    #[serde(other)]
    Unsupported,
}

impl Proto {
    pub fn word(self) -> &'static str {
        match self {
            Proto::Vless => "vless",
            Proto::Vmess => "vmess",
            Proto::Trojan => "trojan",
            Proto::Shadowsocks => "shadowsocks",
            Proto::Hysteria2 => "hysteria2",
            Proto::Wireguard => "wireguard",
            Proto::Socks => "socks",
            Proto::Unsupported => "unsupported",
        }
    }
    /// The engine's own name for the protocol in its config.
    pub fn engine_name(self) -> &'static str {
        if self == Proto::Hysteria2 { "hysteria" } else { self.word() }
    }
}

/// A server as iOS keeps it (MontanaVPNConfig): every field a link may carry, the optional ones absent when it did not.
#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Config {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub uid: Option<String>,
    pub proto: Proto,
    pub name: String,
    pub host: String,
    pub port: u16,
    pub uuid_or_password: String,
    pub network: String,
    pub security: String,
    pub flow: String,
    pub sni: String,
    pub fingerprint: String,
    pub public_key: String,
    pub short_id: String,
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub host_header: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub extra: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub service_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub spider_x: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub subscription: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub encryption: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub pqv: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub alpn: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub allow_insecure: Option<bool>,
    #[serde(default, rename = "pinSHA256", skip_serializing_if = "Option::is_none")] pub pin_sha256: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub header_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub seed: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub authority: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub multi_mode: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub obfs_password: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub up: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub down: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub mport: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub preshared_key: Option<String>,
    #[serde(default, rename = "localIPs", skip_serializing_if = "Option::is_none")] pub local_ips: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub reserved: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub mtu: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub user: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub scheme: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub raw: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub reason: Option<String>,
    /// the outbound exactly as a JSON plan served it (sorted keys); none for a row that came as a link
    #[serde(default, skip_serializing_if = "Option::is_none")] pub engine_outbound: Option<String>,
}

impl Config {
    pub fn empty(p: Proto) -> Config {
        Config {
            uid: None, proto: p, name: String::new(), host: String::new(), port: 443, uuid_or_password: String::new(),
            network: "tcp".into(), security: "none".into(), flow: String::new(), sni: String::new(), fingerprint: String::new(),
            public_key: String::new(), short_id: String::new(), method: String::new(), path: None, host_header: None, mode: None,
            extra: None, service_name: None, spider_x: None, subscription: None, encryption: None, pqv: None, alpn: None,
            allow_insecure: None, pin_sha256: None, header_type: None, seed: None, authority: None, multi_mode: None,
            obfs_password: None, up: None, down: None, mport: None, preshared_key: None, local_ips: None, reserved: None,
            mtu: None, user: None, scheme: None, raw: None, reason: None, engine_outbound: None,
        }
    }
    /// The row's identity (iOS id): its stable uid, else five of its fields.
    pub fn id(&self) -> String {
        self.uid.clone().unwrap_or_else(|| format!("{}:{}:{}:{}:{}", self.proto.word(), self.host, self.port, self.uuid_or_password, self.name))
    }
}

// ── the link's own spelling ──

/// A percent-encoded word read back (iOS removingPercentEncoding): None when an escape is broken.
fn unpercent(s: &str) -> Option<String> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let h = std::str::from_utf8(b.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(h, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).ok()
}
fn unpercent_or(s: &str) -> String {
    unpercent(s).unwrap_or_else(|| s.to_string())
}
/// The link's query words spelled as iOS spells them: what urlQueryAllowed keeps, less `& = # ?`.
fn percent(s: &str) -> String {
    let mut out = String::new();
    for &c in s.as_bytes() {
        if c.is_ascii_alphanumeric() || b"!$'()*+,-./:;@_~".contains(&c) {
            out.push(c as char);
        } else {
            out.push_str(&format!("%{c:02X}"));
        }
    }
    out
}
/// Base64 as the links write it: either alphabet, with or without its padding (iOS pad).
fn unb64(s: &str) -> Option<Vec<u8>> {
    let mut t: String = s.chars().map(|c| match c { '-' => '+', '_' => '/', c => c }).collect();
    while !t.len().is_multiple_of(4) {
        t.push('=');
    }
    crate::wire::unb64(&t)
}
fn unb64_text(s: &str) -> Option<String> {
    unb64(s).and_then(|d| String::from_utf8(d).ok())
}
fn flag(v: Option<&String>) -> Option<bool> {
    let v = v?.to_lowercase();
    if v.is_empty() { None } else { Some(v == "1" || v == "true" || v == "yes") }
}

fn query(s: &str) -> std::collections::HashMap<String, String> {
    let mut q = std::collections::HashMap::new();
    for kv in s.split('&') {
        if let Some((k, v)) = kv.split_once('=') {
            q.insert(k.to_string(), unpercent_or(v));
        }
    }
    q
}

type Q = std::collections::HashMap<String, String>;
/// `userinfo@host:port?query#fragment` (iOS splitURL): the userinfo is required unless said otherwise; a path before the query is
/// dropped; a port missing stands as 443.
fn split_url(s: &str, user_required: bool) -> Option<(String, String, u16, Q, String)> {
    let mut rest = s.to_string();
    let mut frag = String::new();
    if let Some(h) = rest.find('#') {
        frag = unpercent(&rest[h + 1..]).unwrap_or_default();
        rest.truncate(h);
    }
    let mut q = Q::new();
    if let Some(qi) = rest.find('?') {
        q = query(&rest[qi + 1..]);
        rest.truncate(qi);
    }
    let mut user = String::new();
    if let Some(at) = rest.rfind('@') {
        user = rest[..at].to_string();
        rest = rest[at + 1..].to_string();
    } else if user_required {
        return None;
    }
    if let Some(slash) = rest.find('/') {
        rest.truncate(slash);
    }
    let (mut host, mut port) = (rest.clone(), 443u16);
    if !rest.ends_with(']') {
        if let Some(colon) = rest.rfind(':') {
            if !rest[colon + 1..].contains(':') {
                host = rest[..colon].to_string();
                port = rest[colon + 1..].parse().ok()?;
            }
        }
    }
    if host.is_empty() {
        return None;
    }
    Some((user, host, port, q, frag))
}

/// The schemes the wild writes that the engine does not speak: each is kept as a row that says so (iOS unspoken).
const UNSPOKEN: &[&str] = &["tuic", "tuic5", "anytls", "ssh", "naive+https", "naive+quic", "snell", "ssr", "hysteria", "hy", "mieru",
                            "juicity", "shadowtls"];

/// One server link (iOS MontanaVPNParse.parse): by its scheme; None for malformed input or a scheme nobody names.
pub fn parse(raw: &str) -> Option<Config> {
    let s = raw.trim();
    let sep = s.find("://")?;
    let scheme = s[..sep].to_lowercase();
    let rest = &s[sep + 3..];
    match scheme.as_str() {
        "vless" => parse_vless(rest),
        "trojan" => parse_trojan(rest),
        "vmess" => parse_vmess(rest),
        "ss" => parse_ss(rest),
        "hysteria2" | "hy2" => parse_hysteria2(rest),
        "wireguard" | "wg" => parse_wireguard(rest),
        "socks" | "socks5" => parse_socks(rest),
        _ if UNSPOKEN.contains(&scheme.as_str()) => Some(unsupported(s, &scheme, "protocol")),
        _ => None,
    }
}

/// The row of a link the engine cannot speak: kept whole, its host and name read for the list, its identity the link.
pub fn unsupported(link: &str, scheme: &str, reason: &str) -> Config {
    let mut c = Config::empty(Proto::Unsupported);
    c.scheme = Some(scheme.into());
    c.raw = Some(link.into());
    c.reason = Some(reason.into());
    c.uuid_or_password = link.into();
    let body = link.find("://").map_or(link, |i| &link[i + 3..]);
    if let Some((_, host, port, _, frag)) = split_url(body, false) {
        c.host = host;
        c.port = port;
        c.name = frag;
    } else if let Some(h) = body.find('#') {
        c.name = unpercent(&body[h + 1..]).unwrap_or_default();
    }
    if c.name.is_empty() {
        c.name = if c.host.is_empty() { scheme.into() } else { c.host.clone() };
    }
    c
}

/// What a body's lines became (iOS Report): the servers, and the lines with a scheme that were no server link.
#[derive(Default, Debug)]
pub struct Report {
    pub servers: Vec<Config>,
    pub dropped: usize,
}
/// Many lines, or a base64 blob of them (iOS report): every newline the platform knows ends a line.
pub fn report(raw: &str) -> Report {
    let mut text = raw.trim().to_string();
    if !text.contains("://") {
        if let Some(dec) = unb64_text(&text) {
            text = dec;
        }
    }
    let mut r = Report::default();
    for line in text.lines() {
        let l = line.trim();
        if !l.contains("://") || l.starts_with('#') || l.starts_with("//") {
            continue;
        }
        match parse(l) {
            Some(c) => r.servers.push(c),
            None => r.dropped += 1,
        }
    }
    r
}
#[cfg(test)]
pub fn parse_many(raw: &str) -> Vec<Config> {
    report(raw).servers
}

// vless://UUID@host:port?flow=..&type=..&security=reality&fp=..&sni=..&pbk=..&sid=..&pqv=..&encryption=..#Name
fn parse_vless(s: &str) -> Option<Config> {
    let (uuid, host, port, q, frag) = split_url(s, true)?;
    let mut c = Config::empty(Proto::Vless);
    c.uuid_or_password = uuid;
    c.name = if frag.is_empty() { host.clone() } else { frag };
    c.host = host;
    c.port = port;
    c.flow = q.get("flow").cloned().unwrap_or_default();
    if let Some(e) = q.get("encryption").filter(|e| !e.is_empty() && *e != "none") {
        c.encryption = Some(e.clone());
    }
    stream(&mut c, &q);
    (!c.host.is_empty() && !c.uuid_or_password.is_empty()).then_some(c)
}

/// The query keys every scheme shares for the stream layer (the Xray share-link form).
fn stream(c: &mut Config, q: &Q) {
    let g = |k: &str| q.get(k).cloned();
    if let Some(t) = g("type").filter(|t| !t.is_empty()) {
        c.network = t;
    }
    if let Some(s) = g("security").filter(|s| !s.is_empty()) {
        c.security = s;
    }
    c.sni = g("sni").or_else(|| g("host")).unwrap_or_else(|| c.sni.clone());
    c.fingerprint = g("fp").unwrap_or_else(|| c.fingerprint.clone());
    c.public_key = g("pbk").unwrap_or_else(|| c.public_key.clone());
    c.short_id = g("sid").unwrap_or_else(|| c.short_id.clone());
    c.path = g("path");
    c.host_header = g("host");
    c.extra = g("extra");
    c.service_name = g("serviceName");
    c.spider_x = g("spx");
    c.pqv = g("pqv");
    c.alpn = g("alpn");
    c.seed = g("seed");
    c.authority = g("authority");
    c.allow_insecure = flag(q.get("allowInsecure").or_else(|| q.get("insecure")));
    if let Some(h) = g("headerType").filter(|h| !h.is_empty() && h != "none") {
        c.header_type = Some(h);
    }
    if c.network == "grpc" {
        c.multi_mode = (g("mode").as_deref() == Some("multi")).then_some(true);
    } else {
        c.mode = g("mode");
    }
}

fn parse_trojan(s: &str) -> Option<Config> {
    let (pw, host, port, q, frag) = split_url(s, true)?;
    let mut c = Config::empty(Proto::Trojan);
    c.uuid_or_password = pw;
    c.name = if frag.is_empty() { host.clone() } else { frag };
    c.host = host;
    c.port = port;
    c.security = "tls".into();
    c.flow = q.get("flow").cloned().unwrap_or_default();
    stream(&mut c, &q);
    (!c.host.is_empty()).then_some(c)
}

// vmess://base64(json)
fn parse_vmess(b64: &str) -> Option<Config> {
    let j: Value = serde_json::from_slice(&unb64(b64)?).ok()?;
    let j = j.as_object()?;
    let str_ = |k: &str| -> Option<String> {
        match j.get(k)? {
            Value::String(s) => (!s.is_empty()).then(|| s.clone()),
            Value::Number(n) => n.as_i64().map(|n| n.to_string()),
            _ => None,
        }
    };
    let mut c = Config::empty(Proto::Vmess);
    c.host = str_("add").unwrap_or_default();
    c.port = str_("port").and_then(|p| p.parse().ok()).unwrap_or(443);
    c.uuid_or_password = str_("id").unwrap_or_default();
    c.name = str_("ps").unwrap_or_else(|| c.host.clone());
    c.network = str_("net").unwrap_or_else(|| "tcp".into());
    let tls = str_("tls").unwrap_or_default().to_lowercase();
    c.security = if tls.is_empty() || tls == "none" { "none".into() } else { tls };
    c.sni = str_("sni").or_else(|| str_("host")).unwrap_or_default();
    c.fingerprint = str_("fp").unwrap_or_default();
    c.alpn = str_("alpn");
    c.public_key = str_("pbk").unwrap_or_default();
    c.short_id = str_("sid").unwrap_or_default();
    c.spider_x = str_("spx");
    c.method = str_("scy").unwrap_or_default();
    c.allow_insecure = flag(str_("allowInsecure").or_else(|| str_("insecure")).as_ref());
    c.path = str_("path");
    c.host_header = str_("host");
    if c.network == "grpc" {
        c.service_name = str_("path");
        c.multi_mode = (str_("mode").as_deref() == Some("multi")).then_some(true);
    }
    if c.network == "kcp" {
        c.seed = str_("path");
    }
    if c.network == "xhttp" {
        c.mode = str_("mode");
    }
    if let Some(t) = str_("type").filter(|t| t != "none") {
        if c.network == "tcp" || c.network == "kcp" {
            c.header_type = Some(t);
        }
    }
    (!c.host.is_empty() && !c.uuid_or_password.is_empty()).then_some(c)
}

// ss://base64(method:password)@host:port?..#name, ss://method:password@host:port (SIP002 in the clear), ss://base64(all)#name
fn parse_ss(rest: &str) -> Option<Config> {
    let mut body = rest.to_string();
    let mut name = String::new();
    if let Some(h) = body.find('#') {
        name = unpercent(&body[h + 1..]).unwrap_or_default();
        body.truncate(h);
    }
    let mut q = Q::new();
    if let Some(qi) = body.find('?') {
        q = query(&body[qi + 1..]);
        body.truncate(qi);
    }
    let (mut method, mut password, mut host, mut port_s) = (String::new(), String::new(), String::new(), String::new());
    if let Some(at) = body.rfind('@') {
        let creds = &body[..at];
        let mut dec = unb64_text(creds).unwrap_or_default();
        if !dec.contains(':') {
            dec = unpercent_or(creds);
        }
        if let Some((m, p)) = dec.split_once(':') {
            method = m.into();
            password = p.into();
        }
        let hp = &body[at + 1..];
        if let Some(c) = hp.rfind(':') {
            host = hp[..c].into();
            port_s = hp[c + 1..].into();
        }
    } else if let Some(dec) = unb64_text(&body) {
        if let (Some(at), Some(colon)) = (dec.rfind('@'), dec.find(':')) {
            if colon < at {
                method = dec[..colon].into();
                password = dec[colon + 1..at].into();
                let hp = &dec[at + 1..];
                if let Some(c) = hp.rfind(':') {
                    host = hp[..c].into();
                    port_s = hp[c + 1..].into();
                }
            }
        }
    }
    let mut c = Config::empty(Proto::Shadowsocks);
    c.host = host;
    c.port = port_s.parse().unwrap_or(443);
    c.uuid_or_password = password;
    c.method = method;
    c.name = if name.is_empty() { c.host.clone() } else { name };
    stream(&mut c, &q);
    if c.host.is_empty() {
        return None;
    }
    // a SIP003 plugin is not in the engine: the row says so instead of failing at the dial
    if q.get("plugin").is_some_and(|p| !p.is_empty()) {
        return Some(unsupported(&format!("ss://{rest}"), "ss+plugin", "plugin"));
    }
    Some(c)
}

// hysteria2://AUTH@host:port?sni=..&insecure=1&obfs=salamander&obfs-password=..&pinSHA256=..&mport=..&up=..&down=..#Name
fn parse_hysteria2(s: &str) -> Option<Config> {
    let (auth, host, port, q, frag) = split_url(s, false)?;
    let mut c = Config::empty(Proto::Hysteria2);
    c.uuid_or_password = unpercent_or(&auth);
    c.name = if frag.is_empty() { host.clone() } else { frag };
    c.host = host;
    c.port = port;
    c.network = "hysteria".into();
    c.security = "tls".into();
    c.sni = q.get("sni").or_else(|| q.get("peer")).cloned().unwrap_or_default();
    c.alpn = q.get("alpn").cloned();
    c.allow_insecure = flag(q.get("insecure").or_else(|| q.get("allowInsecure")));
    c.pin_sha256 = q.get("pinSHA256").cloned();
    if q.get("obfs").map(|o| o.to_lowercase()).as_deref() == Some("salamander") {
        c.obfs_password = q.get("obfs-password").filter(|p| !p.is_empty()).cloned();
    }
    c.mport = q.get("mport").cloned();
    c.up = q.get("up").or_else(|| q.get("upmbps")).cloned();
    c.down = q.get("down").or_else(|| q.get("downmbps")).cloned();
    (!c.host.is_empty()).then_some(c)
}

// wireguard://PRIVATEKEY@host:port?publickey=..&address=..&reserved=1,2,3&mtu=1280&presharedkey=..#Name
fn parse_wireguard(s: &str) -> Option<Config> {
    let (key, host, port, q, frag) = split_url(s, true)?;
    let mut c = Config::empty(Proto::Wireguard);
    c.uuid_or_password = unpercent_or(&key);
    c.name = if frag.is_empty() { host.clone() } else { frag };
    c.host = host;
    c.port = port;
    c.network = "udp".into();
    c.security = "none".into();
    c.public_key = q.get("publickey").or_else(|| q.get("pk")).or_else(|| q.get("peer")).cloned().unwrap_or_default();
    c.preshared_key = q.get("presharedkey").or_else(|| q.get("psk")).cloned();
    c.local_ips = q.get("address").or_else(|| q.get("ip")).cloned();
    c.reserved = q.get("reserved").cloned();
    c.mtu = q.get("mtu").and_then(|m| m.parse().ok());
    (!c.host.is_empty() && !c.uuid_or_password.is_empty() && !c.public_key.is_empty()).then_some(c)
}

// socks://base64(user:pass)@host:port#Name, socks://user:pass@host:port#Name, socks://host:port#Name
fn parse_socks(s: &str) -> Option<Config> {
    let (creds, host, port, _, frag) = split_url(s, false)?;
    let mut c = Config::empty(Proto::Socks);
    c.name = if frag.is_empty() { host.clone() } else { frag };
    c.host = host;
    c.port = port;
    let mut dec = if creds.contains(':') { unpercent_or(&creds) } else { unb64_text(&creds).unwrap_or_default() };
    if !dec.contains(':') {
        dec.clear();
    }
    if let Some((u, p)) = dec.split_once(':') {
        c.user = Some(u.into());
        c.uuid_or_password = p.into();
    }
    (!c.host.is_empty()).then_some(c)
}

// ── the engine's config (iOS MontanaXrayConfig) ──

/// A comma-separated word of a link as the list the engine takes.
fn list(s: Option<&String>) -> Vec<String> {
    s.map(|s| s.split(',').map(|x| x.trim().to_string()).filter(|x| !x.is_empty()).collect()).unwrap_or_default()
}
fn nonempty(s: &Option<String>) -> Option<&String> {
    s.as_ref().filter(|v| !v.is_empty())
}

/// The outbound a JSON plan served, as it is: the tag ours, and the one TLS key this engine refuses taken out.
fn served_outbound(c: &Config) -> Option<Value> {
    if c.proto == Proto::Unsupported {
        return None;
    }
    let mut ob: Value = serde_json::from_str(c.engine_outbound.as_deref()?).ok()?;
    if ob.get("protocol").and_then(|p| p.as_str()) != Some(c.proto.engine_name()) {
        return None;
    }
    ob["tag"] = json!("proxy");
    if let Some(ts) = ob.pointer_mut("/streamSettings/tlsSettings").and_then(|t| t.as_object_mut()) {
        ts.remove("allowInsecure");
    }
    Some(ob)
}

/// THE OUTBOUND (iOS MontanaXrayConfig.outbound): every protocol the engine speaks, in its own config words.
pub fn outbound(c: &Config) -> Value {
    if let Some(s) = served_outbound(c) {
        return s;
    }
    let endpoint = if c.host.starts_with('[') && c.host.ends_with(']') { c.host[1..c.host.len() - 1].to_string() } else { c.host.clone() };
    match c.proto {
        Proto::Unsupported => return json!({"protocol": "blackhole", "tag": "proxy"}),
        Proto::Wireguard => {
            let mut peer = json!({"publicKey": c.public_key, "endpoint": format!("{}:{}", c.host, c.port)});
            if let Some(psk) = nonempty(&c.preshared_key) {
                peer["preSharedKey"] = json!(psk);
            }
            let ips = list(c.local_ips.as_ref());
            let mut settings = json!({"secretKey": c.uuid_or_password, "peers": [peer],
                                      "address": if ips.is_empty() { vec!["10.0.0.2/32".to_string()] } else { ips }});
            if let Some(m) = c.mtu.filter(|m| *m > 0) {
                settings["mtu"] = json!(m);
            }
            let reserved: Vec<i64> = list(c.reserved.as_ref()).iter().filter_map(|r| r.parse().ok()).collect();
            if !reserved.is_empty() {
                settings["reserved"] = json!(reserved);
            }
            return json!({"protocol": "wireguard", "settings": settings, "tag": "proxy"});
        }
        _ => {}
    }
    let mut stream = json!({"network": c.network, "security": c.security});
    if c.security == "reality" {
        let mut rs = json!({"serverName": c.sni, "fingerprint": c.fingerprint, "publicKey": c.public_key, "shortId": c.short_id, "show": false});
        if let Some(x) = nonempty(&c.spider_x) {
            rs["spiderX"] = json!(x);
        }
        if let Some(v) = nonempty(&c.pqv) {
            rs["mldsa65Verify"] = json!(v);
        }
        stream["realitySettings"] = rs;
    } else if c.security == "tls" {
        let mut ts = json!({"serverName": c.sni, "fingerprint": c.fingerprint});
        let alpn = list(c.alpn.as_ref());
        if !alpn.is_empty() {
            ts["alpn"] = json!(alpn);
        }
        // the link's allowInsecure is never written (the engine refuses it); its road is the pinned hash
        if let Some(pin) = nonempty(&c.pin_sha256) {
            ts["pinnedPeerCertSha256"] = json!(pin);
        }
        stream["tlsSettings"] = ts;
    }
    match c.network.as_str() {
        "tcp" | "raw" => {
            if c.header_type.as_deref() == Some("http") {
                let mut request = json!({"path": [c.path.clone().unwrap_or_else(|| "/".into())]});
                let host_word = c.host_header.clone().unwrap_or_else(|| c.sni.clone());
                if !host_word.is_empty() {
                    request["headers"] = json!({"Host": list(Some(&host_word))});
                }
                stream["tcpSettings"] = json!({"header": {"type": "http", "request": request}});
            }
        }
        "kcp" | "mkcp" => {
            let mut k = Map::new();
            if let Some(v) = nonempty(&c.seed) {
                k.insert("seed".into(), json!(v));
            }
            if let Some(h) = nonempty(&c.header_type) {
                k.insert("header".into(), json!({"type": h}));
            }
            stream["kcpSettings"] = Value::Object(k);
        }
        "ws" | "httpupgrade" => {
            let mut w = json!({"path": c.path.clone().unwrap_or_else(|| "/".into())});
            if let Some(h) = nonempty(&c.host_header) {
                w["host"] = json!(h);
            }
            stream[if c.network == "ws" { "wsSettings" } else { "httpupgradeSettings" }] = w;
        }
        "xhttp" | "splithttp" => {
            let mut x = json!({"path": c.path.clone().unwrap_or_else(|| "/".into()), "mode": c.mode.clone().unwrap_or_else(|| "auto".into())});
            if let Some(h) = nonempty(&c.host_header) {
                x["host"] = json!(h);
            }
            if let Some(j) = c.extra.as_deref().and_then(|e| serde_json::from_str::<Value>(e).ok()).filter(|j| j.is_object()) {
                x["extra"] = j;
            }
            stream["xhttpSettings"] = x;
        }
        "grpc" => {
            let mut g = json!({"serviceName": c.service_name.clone().unwrap_or_default()});
            if let Some(a) = nonempty(&c.authority) {
                g["authority"] = json!(a);
            }
            if c.multi_mode == Some(true) {
                g["multiMode"] = json!(true);
            }
            stream["grpcSettings"] = g;
        }
        "hysteria" => {
            stream["hysteriaSettings"] = json!({"version": 2, "auth": c.uuid_or_password});
            let mut mask = Map::new();
            if let Some(o) = nonempty(&c.obfs_password) {
                mask.insert("udp".into(), json!([{"type": "salamander", "settings": {"password": o}}]));
            }
            let mut quic = Map::new();
            if let Some(n) = c.up.as_deref().and_then(|u| u.parse::<i64>().ok()).filter(|n| *n > 0) {
                quic.insert("brutalUp".into(), json!(format!("{n} mbps")));
            }
            if let Some(n) = c.down.as_deref().and_then(|d| d.parse::<i64>().ok()).filter(|n| *n > 0) {
                quic.insert("brutalDown".into(), json!(format!("{n} mbps")));
            }
            if let Some(m) = nonempty(&c.mport) {
                quic.insert("udpHop".into(), json!({"ports": m}));
            }
            if !quic.is_empty() {
                mask.insert("quicParams".into(), Value::Object(quic));
            }
            if !mask.is_empty() {
                stream["finalmask"] = Value::Object(mask);
            }
        }
        _ => {}
    }
    let port = c.port as i64;
    let settings = match c.proto {
        Proto::Vless => {
            let enc = c.encryption.clone().unwrap_or_default();
            let mut user = json!({"id": c.uuid_or_password, "encryption": if enc.is_empty() { "none".to_string() } else { enc }});
            if !c.flow.is_empty() {
                user["flow"] = json!(c.flow);
            }
            json!({"vnext": [{"address": endpoint, "port": port, "users": [user]}]})
        }
        Proto::Vmess => json!({"vnext": [{"address": endpoint, "port": port,
                                           "users": [{"id": c.uuid_or_password, "security": if c.method.is_empty() { "auto" } else { &c.method }}]}]}),
        Proto::Trojan => json!({"servers": [{"address": endpoint, "port": port, "password": c.uuid_or_password}]}),
        Proto::Shadowsocks => json!({"servers": [{"address": endpoint, "port": port, "password": c.uuid_or_password, "method": c.method}]}),
        Proto::Hysteria2 => json!({"version": 2, "address": endpoint, "port": port}),
        Proto::Socks => {
            let mut server = json!({"address": endpoint, "port": port});
            if let Some(u) = nonempty(&c.user) {
                server["users"] = json!([{"user": u, "pass": c.uuid_or_password}]);
            }
            json!({"servers": [server]})
        }
        Proto::Wireguard | Proto::Unsupported => json!({}),
    };
    json!({"protocol": c.proto.engine_name(), "settings": settings, "streamSettings": stream, "tag": "proxy"})
}

/// The JSON of a server, copied (iOS shareJSON): the whole engine config the panels serve, keys sorted; none for a row the engine
/// cannot speak.
pub fn share_json(c: &Config) -> Option<String> {
    if c.proto == Proto::Unsupported {
        return None;
    }
    let full = json!({"remarks": c.name, "outbounds": [outbound(c), {"protocol": "freedom", "tag": "direct"}]});
    serde_json::to_string_pretty(&full).ok()
}

/// The probe's config (iOS MontanaVPNDelay.probeConfig): the outbound and nothing else -- no inbound, no routing, no dns.
#[cfg(test)]
pub fn probe_config(c: &Config) -> Option<String> {
    if c.proto == Proto::Unsupported {
        return None;
    }
    serde_json::to_string(&json!({"outbounds": [outbound(c), {"protocol": "freedom", "tag": "direct"}]})).ok()
}

// ── the link again (iOS MontanaVPNParse.serialize) ──

fn wrapper_query(c: &Config) -> Vec<String> {
    let mut q = Vec::new();
    if !c.sni.is_empty() { q.push(format!("sni={}", percent(&c.sni))); }
    if !c.fingerprint.is_empty() { q.push(format!("fp={}", c.fingerprint)); }
    if !c.public_key.is_empty() { q.push(format!("pbk={}", percent(&c.public_key))); }
    if !c.short_id.is_empty() { q.push(format!("sid={}", c.short_id)); }
    if let Some(v) = nonempty(&c.pqv) { q.push(format!("pqv={}", percent(v))); }
    if let Some(v) = nonempty(&c.alpn) { q.push(format!("alpn={}", percent(v))); }
    if c.allow_insecure == Some(true) { q.push("allowInsecure=1".into()); }
    if let Some(v) = nonempty(&c.pin_sha256) { q.push(format!("pinSHA256={}", percent(v))); }
    q
}
fn transport_query(c: &Config) -> Vec<String> {
    let mut q = Vec::new();
    if let Some(v) = nonempty(&c.path) { q.push(format!("path={}", percent(v))); }
    if let Some(v) = nonempty(&c.host_header) { q.push(format!("host={}", percent(v))); }
    if let Some(v) = nonempty(&c.mode) { q.push(format!("mode={v}")); }
    if c.multi_mode == Some(true) { q.push("mode=multi".into()); }
    if let Some(v) = nonempty(&c.extra) { q.push(format!("extra={}", percent(v))); }
    if let Some(v) = nonempty(&c.service_name) { q.push(format!("serviceName={}", percent(v))); }
    if let Some(v) = nonempty(&c.authority) { q.push(format!("authority={}", percent(v))); }
    if let Some(v) = nonempty(&c.spider_x) { q.push(format!("spx={}", percent(v))); }
    if let Some(v) = nonempty(&c.header_type) { q.push(format!("headerType={v}")); }
    if let Some(v) = nonempty(&c.seed) { q.push(format!("seed={}", percent(v))); }
    q
}

pub fn serialize(c: &Config) -> String {
    let frag = if c.name.is_empty() { String::new() } else { format!("#{}", percent(&c.name)) };
    match c.proto {
        Proto::Vless | Proto::Trojan => {
            let mut q = vec![format!("type={}", c.network), format!("security={}", c.security)];
            if !c.flow.is_empty() { q.push(format!("flow={}", c.flow)); }
            if c.proto == Proto::Vless {
                if let Some(v) = nonempty(&c.encryption) { q.push(format!("encryption={}", percent(v))); }
            }
            q.extend(wrapper_query(c));
            q.extend(transport_query(c));
            format!("{}://{}@{}:{}?{}{}", c.proto.word(), c.uuid_or_password, c.host, c.port, q.join("&"), frag)
        }
        Proto::Vmess => {
            let path = if c.network == "grpc" { c.service_name.clone() } else if c.network == "kcp" { c.seed.clone() } else { c.path.clone() };
            let mut j = json!({"v": "2", "ps": c.name, "add": c.host, "port": c.port.to_string(), "id": c.uuid_or_password, "net": c.network,
                               "type": c.header_type.clone().unwrap_or_else(|| "none".into()),
                               "tls": if c.security == "none" { String::new() } else { c.security.clone() }, "sni": c.sni,
                               "host": c.host_header.clone().unwrap_or_default(), "path": path.unwrap_or_default(), "aid": "0",
                               "scy": if c.method.is_empty() { "auto".to_string() } else { c.method.clone() }, "fp": c.fingerprint});
            if let Some(a) = nonempty(&c.alpn) { j["alpn"] = json!(a); }
            if !c.public_key.is_empty() { j["pbk"] = json!(c.public_key); j["sid"] = json!(c.short_id); }
            if let Some(m) = nonempty(&c.mode) { j["mode"] = json!(m); }
            format!("vmess://{}", crate::wire::b64(j.to_string().as_bytes()))
        }
        Proto::Shadowsocks => {
            let creds = crate::wire::b64(format!("{}:{}", c.method, c.uuid_or_password).as_bytes());
            let mut q = wrapper_query(c);
            q.extend(transport_query(c));
            let tail = if c.network == "tcp" && q.is_empty() {
                String::new()
            } else {
                let mut all = vec![format!("type={}", c.network), format!("security={}", c.security)];
                all.extend(q);
                format!("?{}", all.join("&"))
            };
            format!("ss://{creds}@{}:{}{tail}{frag}", c.host, c.port)
        }
        Proto::Hysteria2 => {
            let mut q = Vec::new();
            if !c.sni.is_empty() { q.push(format!("sni={}", percent(&c.sni))); }
            if c.allow_insecure == Some(true) { q.push("insecure=1".into()); }
            if let Some(o) = nonempty(&c.obfs_password) { q.push("obfs=salamander".into()); q.push(format!("obfs-password={}", percent(o))); }
            if let Some(v) = nonempty(&c.pin_sha256) { q.push(format!("pinSHA256={}", percent(v))); }
            if let Some(v) = nonempty(&c.mport) { q.push(format!("mport={}", percent(v))); }
            if let Some(v) = nonempty(&c.up) { q.push(format!("up={}", percent(v))); }
            if let Some(v) = nonempty(&c.down) { q.push(format!("down={}", percent(v))); }
            if let Some(v) = nonempty(&c.alpn) { q.push(format!("alpn={}", percent(v))); }
            format!("hysteria2://{}@{}:{}?{}{}", percent(&c.uuid_or_password), c.host, c.port, q.join("&"), frag)
        }
        Proto::Wireguard => {
            let mut q = vec![format!("publickey={}", percent(&c.public_key))];
            if let Some(v) = nonempty(&c.local_ips) { q.push(format!("address={}", percent(v))); }
            if let Some(v) = nonempty(&c.reserved) { q.push(format!("reserved={}", percent(v))); }
            if let Some(v) = c.mtu { q.push(format!("mtu={v}")); }
            if let Some(v) = nonempty(&c.preshared_key) { q.push(format!("presharedkey={}", percent(v))); }
            format!("wireguard://{}@{}:{}?{}{}", percent(&c.uuid_or_password), c.host, c.port, q.join("&"), frag)
        }
        Proto::Socks => {
            let creds = match nonempty(&c.user) {
                Some(u) => format!("{}@", crate::wire::b64(format!("{u}:{}", c.uuid_or_password).as_bytes())),
                None => String::new(),
            };
            format!("socks://{creds}{}:{}{frag}", c.host, c.port)
        }
        Proto::Unsupported => c.raw.clone().unwrap_or_default(),
    }
}

// ── the plan (iOS MontanaVPNSubscription) ──

/// A plan's link: http(s), its fragment (a name for a human) left off what is fetched.
pub fn subscription_url(s: &str) -> Option<String> {
    let raw = s.trim();
    let low = raw.to_lowercase();
    if !(low.starts_with("https://") || low.starts_with("http://")) || raw.contains(char::is_whitespace) {
        return None;
    }
    Some(raw.split('#').next().unwrap_or(raw).to_string())
}

/// A panel's header in its two spellings: `base64:...` or plain.
pub fn header_text(raw: Option<&str>) -> String {
    let Some(raw) = raw.map(str::trim).filter(|r| !r.is_empty()) else { return String::new() };
    if raw.to_lowercase().starts_with("base64:") {
        if let Some(s) = unb64_text(&raw[7..]) {
            return s;
        }
    }
    raw.to_string()
}

/// "upload=0; download=40333815636; total=0; expire=1820218794"
pub fn userinfo(s: &str) -> std::collections::BTreeMap<String, i64> {
    let mut out = std::collections::BTreeMap::new();
    for part in s.split(';') {
        if let Some((k, v)) = part.split_once('=') {
            if let Ok(v) = v.trim().parse() {
                out.insert(k.trim().to_string(), v);
            }
        }
    }
    out
}

/// What a body became and in what form it came (iOS Body).
#[derive(Default, Debug)]
pub struct Body {
    pub servers: Vec<Config>,
    pub dropped: usize,
    pub form: String,
}

/// A plan's body in its forms (iOS body): sing-box JSON, the engine configs' JSON, an HTML page (no plan), the Clash YAML, the
/// profile files (WireGuard, Hysteria 2, OpenVPN; the iOS platform profile is named only), links or a base64 blob of them.
pub fn body(data: &[u8], name: &str) -> Body {
    let Ok(text) = std::str::from_utf8(data) else { return Body { form: "binary".into(), ..Default::default() } };
    let s = text.trim();
    if s.starts_with('[') || s.starts_with('{') {
        if let Ok(j) = serde_json::from_str::<Value>(s) {
            if let Some(outs) = j.get("outbounds").and_then(|o| o.as_array()) {
                if j.is_object() && outs.iter().any(|o| o.get("type").is_some() && o.get("protocol").is_none()) {
                    return Body { servers: outs.iter().filter_map(from_sing_box).collect(), dropped: 0, form: "sing-box".into() };
                }
            }
            let configs: Vec<Value> = match j {
                Value::Array(a) => a,
                v @ Value::Object(_) => vec![v],
                _ => vec![],
            };
            let servers: Vec<Config> = configs.iter().filter_map(|c| from_engine_config(c, name)).collect();
            return Body { dropped: configs.len() - servers.len(), servers, form: "engine-json".into() };
        }
    }
    // THE PROFILE FILES, each by its shape, never by its extension (iOS body): the platform's own profile of iOS is XML and is named
    // before the page; the Clash body, whose `proxies:` names it first; then the WireGuard interface, the Hysteria 2 config, OpenVPN
    if s.starts_with("<?xml") && s.contains("com.apple.vpn.managed") {
        return Body { form: "profile".into(), ..Default::default() };
    }
    if s.starts_with('<') {
        return Body { form: "html".into(), ..Default::default() };
    }
    if clash::looks_like(s) {
        return Body { servers: clash::items(s).iter().filter_map(from_clash).collect(), dropped: 0, form: "clash".into() };
    }
    let low = s.to_lowercase();
    if low.contains("[interface]") && low.contains("privatekey") {
        return Body { servers: from_wireguard_file(s, name).into_iter().collect(), dropped: 0, form: "wireguard".into() };
    }
    if looks_like_hysteria(s) {
        return Body { servers: from_hysteria_file(s, name).into_iter().collect(), dropped: 0, form: "hysteria".into() };
    }
    if looks_like_openvpn(s) {
        return Body { servers: vec![openvpn_row(text, name)], dropped: 0, form: "openvpn".into() };
    }
    let r = report(s);
    Body { form: if s.contains("://") { "links".into() } else { "base64".into() }, servers: r.servers, dropped: r.dropped }
}

fn port_of(v: Option<&Value>) -> u16 {
    match v {
        Some(Value::Number(n)) => n.as_u64().and_then(|n| u16::try_from(n).ok()).unwrap_or(0),
        Some(Value::String(s)) => s.parse().unwrap_or(0),
        _ => 0,
    }
}
fn s_of(v: Option<&Value>) -> Option<String> {
    v.and_then(|v| v.as_str()).map(str::to_string)
}
fn strs(v: Option<&Value>) -> Option<Vec<String>> {
    v.and_then(|v| v.as_array()).map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_string)).collect())
}

/// The engine's Bandwidth word ("100 mbps", "1 gbps", a bare number of bps) to the link's mbps number.
fn mbps(v: Option<&Value>) -> Option<String> {
    if let Some(n) = v.and_then(|v| v.as_i64()) {
        return (n >= 1_000_000).then(|| (n / 1_000_000).to_string());
    }
    let s = v?.as_str()?.trim().to_lowercase();
    let digits: String = s.chars().take_while(|c| c.is_ascii_digit() || *c == '.').collect();
    let n: f64 = digits.parse().ok().filter(|n| *n > 0.0)?;
    match s[digits.len()..].trim() {
        "g" | "gb" | "gbps" => Some(((n * 1000.0) as i64).to_string()),
        "k" | "kb" | "kbps" => (n >= 1000.0).then(|| ((n / 1000.0) as i64).to_string()),
        "" | "b" | "bps" => (n >= 1_000_000.0).then(|| ((n / 1_000_000.0) as i64).to_string()),
        _ => Some((n as i64).to_string()),
    }
}

/// One whole engine config as the panels serve it (iOS fromEngineConfig): the outbound tagged "proxy", or the first of a protocol
/// we speak; the rest of the config is that client's own policy.
pub fn from_engine_config(c: &Value, fallback: &str) -> Option<Config> {
    let speak = |p: &str| match p {
        "vless" => Some(Proto::Vless), "vmess" => Some(Proto::Vmess), "trojan" => Some(Proto::Trojan),
        "shadowsocks" => Some(Proto::Shadowsocks), "hysteria" => Some(Proto::Hysteria2), "wireguard" => Some(Proto::Wireguard),
        "socks" => Some(Proto::Socks), _ => None,
    };
    let outs = c.get("outbounds").and_then(|o| o.as_array())?;
    let proto_of = |o: &Value| o.get("protocol").and_then(|p| p.as_str()).and_then(speak);
    let ob = outs.iter().find(|o| o.get("tag").and_then(|t| t.as_str()) == Some("proxy") && proto_of(o).is_some())
        .or_else(|| outs.iter().find(|o| proto_of(o).is_some()))?;
    let proto = proto_of(ob)?;
    let settings = ob.get("settings")?;
    let mut cfg = Config::empty(proto);
    cfg.name = s_of(c.get("remarks")).unwrap_or_default();
    if cfg.name.is_empty() {
        cfg.name = fallback.into();
    }
    cfg.engine_outbound = serde_json::to_string(ob).ok();
    match proto {
        Proto::Vless | Proto::Vmess => {
            let v = settings.get("vnext")?.as_array()?.first()?;
            let u = v.get("users")?.as_array()?.first()?;
            cfg.host = s_of(v.get("address")).unwrap_or_default();
            cfg.port = port_of(v.get("port"));
            cfg.uuid_or_password = s_of(u.get("id")).unwrap_or_default();
            cfg.flow = s_of(u.get("flow")).unwrap_or_default();
            if proto == Proto::Vless {
                cfg.encryption = s_of(u.get("encryption")).filter(|e| !e.is_empty() && e != "none");
            } else if let Some(sec) = s_of(u.get("security")).filter(|s| s != "auto") {
                cfg.method = sec;
            }
        }
        Proto::Trojan | Proto::Shadowsocks => {
            let v = settings.get("servers")?.as_array()?.first()?;
            cfg.host = s_of(v.get("address")).unwrap_or_default();
            cfg.port = port_of(v.get("port"));
            cfg.uuid_or_password = s_of(v.get("password")).unwrap_or_default();
            cfg.method = s_of(v.get("method")).unwrap_or_default();
        }
        Proto::Socks => {
            let v = settings.get("servers")?.as_array()?.first()?;
            cfg.host = s_of(v.get("address")).unwrap_or_default();
            cfg.port = port_of(v.get("port"));
            if let Some(u) = v.get("users").and_then(|u| u.as_array()).and_then(|u| u.first()) {
                cfg.user = s_of(u.get("user"));
                cfg.uuid_or_password = s_of(u.get("pass")).unwrap_or_default();
            }
        }
        Proto::Hysteria2 => {
            cfg.host = s_of(settings.get("address")).unwrap_or_default();
            cfg.port = port_of(settings.get("port"));
        }
        Proto::Wireguard => {
            cfg.uuid_or_password = s_of(settings.get("secretKey")).unwrap_or_default();
            cfg.local_ips = strs(settings.get("address")).map(|a| a.join(","));
            cfg.mtu = settings.get("mtu").and_then(|m| m.as_i64()).filter(|m| *m > 0);
            cfg.reserved = settings.get("reserved").and_then(|r| r.as_array())
                .map(|r| r.iter().filter_map(|x| x.as_i64()).map(|x| x.to_string()).collect::<Vec<_>>().join(","));
            if let Some(peer) = settings.get("peers").and_then(|p| p.as_array()).and_then(|p| p.first()) {
                cfg.public_key = s_of(peer.get("publicKey")).unwrap_or_default();
                cfg.preshared_key = s_of(peer.get("preSharedKey"));
                let ep = s_of(peer.get("endpoint")).unwrap_or_default();
                if let Some(colon) = ep.rfind(':') {
                    cfg.host = ep[..colon].into();
                    cfg.port = ep[colon + 1..].parse().unwrap_or(0);
                }
            }
            cfg.network = "udp".into();
            if cfg.name.is_empty() {
                cfg.name = cfg.host.clone();
            }
            return (!cfg.host.is_empty() && cfg.port != 0 && !cfg.uuid_or_password.is_empty() && !cfg.public_key.is_empty()).then_some(cfg);
        }
        Proto::Unsupported => return None,
    }
    let empty = json!({});
    let ss = ob.get("streamSettings").unwrap_or(&empty);
    cfg.network = s_of(ss.get("network")).unwrap_or_else(|| if proto == Proto::Hysteria2 { "hysteria".into() } else { "tcp".into() });
    cfg.security = s_of(ss.get("security")).unwrap_or_else(|| if proto == Proto::Hysteria2 { "tls".into() } else { "none".into() });
    cfg.network = match cfg.network.as_str() { "splithttp" => "xhttp".into(), "raw" => "tcp".into(), "mkcp" => "kcp".into(), n => n.into() };
    if let Some(rs) = ss.get("realitySettings") {
        cfg.sni = s_of(rs.get("serverName")).unwrap_or_default();
        cfg.fingerprint = s_of(rs.get("fingerprint")).unwrap_or_default();
        cfg.public_key = s_of(rs.get("publicKey")).unwrap_or_default();
        cfg.short_id = s_of(rs.get("shortId")).unwrap_or_default();
        cfg.spider_x = s_of(rs.get("spiderX"));
        cfg.pqv = s_of(rs.get("mldsa65Verify"));
    } else if let Some(ts) = ss.get("tlsSettings") {
        cfg.sni = s_of(ts.get("serverName")).unwrap_or_default();
        cfg.fingerprint = s_of(ts.get("fingerprint")).unwrap_or_default();
        cfg.alpn = strs(ts.get("alpn")).map(|a| a.join(","));
        if ts.get("allowInsecure").and_then(|b| b.as_bool()) == Some(true) {
            cfg.allow_insecure = Some(true);
        }
        cfg.pin_sha256 = s_of(ts.get("pinnedPeerCertSha256"));
    }
    if let Some(x) = ss.get("xhttpSettings").or_else(|| ss.get("splithttpSettings")) {
        cfg.path = s_of(x.get("path"));
        cfg.host_header = s_of(x.get("host"));
        cfg.mode = s_of(x.get("mode"));
        cfg.extra = x.get("extra").map(|e| e.to_string());
    } else if let Some(w) = ss.get("wsSettings") {
        cfg.path = s_of(w.get("path"));
        cfg.host_header = s_of(w.get("host")).or_else(|| s_of(w.pointer("/headers/Host")));
    } else if let Some(h) = ss.get("httpupgradeSettings") {
        cfg.path = s_of(h.get("path"));
        cfg.host_header = s_of(h.get("host"));
    } else if let Some(g) = ss.get("grpcSettings") {
        cfg.service_name = s_of(g.get("serviceName"));
        cfg.authority = s_of(g.get("authority"));
        if g.get("multiMode").and_then(|b| b.as_bool()) == Some(true) {
            cfg.multi_mode = Some(true);
        }
    } else if let Some(k) = ss.get("kcpSettings") {
        cfg.seed = s_of(k.get("seed"));
        cfg.header_type = s_of(k.pointer("/header/type"));
    } else if let Some(h) = ss.get("tcpSettings").or_else(|| ss.get("rawSettings")).and_then(|t| t.get("header")) {
        if h.get("type").and_then(|t| t.as_str()) == Some("http") {
            cfg.header_type = Some("http".into());
            cfg.path = strs(h.pointer("/request/path")).and_then(|p| p.into_iter().next());
            cfg.host_header = strs(h.pointer("/request/headers/Host")).and_then(|p| p.into_iter().next());
        }
    }
    if let Some(hs) = ss.get("hysteriaSettings") {
        cfg.uuid_or_password = s_of(hs.get("auth")).unwrap_or_default();
    }
    if let Some(fm) = ss.get("finalmask") {
        for m in fm.get("udp").and_then(|u| u.as_array()).into_iter().flatten() {
            if m.get("type").and_then(|t| t.as_str()) == Some("salamander") {
                cfg.obfs_password = s_of(m.pointer("/settings/password"));
            }
        }
        if let Some(qp) = fm.get("quicParams") {
            cfg.up = mbps(qp.get("brutalUp"));
            cfg.down = mbps(qp.get("brutalDown"));
            if let Some(hop) = qp.get("udpHop") {
                cfg.mport = s_of(hop.get("ports")).or_else(|| hop.get("ports").and_then(|p| p.as_i64()).map(|p| p.to_string()));
            }
        }
    }
    if cfg.name.is_empty() {
        cfg.name = cfg.host.clone();
    }
    (!cfg.host.is_empty() && cfg.port != 0 && (proto == Proto::Socks || !cfg.uuid_or_password.is_empty())).then_some(cfg)
}

/// One outbound of a sing-box config (iOS fromSingBox): a type the engine lacks keeps a row that says so; the selector, urltest,
/// direct, block and dns outbounds are no servers.
pub fn from_sing_box(o: &Value) -> Option<Config> {
    let kind = s_of(o.get("type")).unwrap_or_default().to_lowercase();
    let name = s_of(o.get("tag")).unwrap_or_default();
    let proto = match kind.as_str() {
        "vless" => Proto::Vless, "vmess" => Proto::Vmess, "trojan" => Proto::Trojan, "shadowsocks" => Proto::Shadowsocks,
        "hysteria2" => Proto::Hysteria2, "wireguard" => Proto::Wireguard, "socks" => Proto::Socks,
        "selector" | "urltest" | "direct" | "block" | "dns" | "" => return None,
        _ => {
            let mut u = Config::empty(Proto::Unsupported);
            u.scheme = Some(kind.clone());
            u.reason = Some("protocol".into());
            u.name = if name.is_empty() { kind.clone() } else { name.clone() };
            u.host = s_of(o.get("server")).unwrap_or_default();
            u.port = port_of(o.get("server_port"));
            u.uuid_or_password = format!("{kind}:{}:{}:{name}", u.host, u.port);
            u.raw = Some(o.to_string());
            return Some(u);
        }
    };
    let mut c = Config::empty(proto);
    c.name = name;
    c.host = s_of(o.get("server")).unwrap_or_default();
    c.port = port_of(o.get("server_port"));
    match proto {
        Proto::Vless => {
            c.uuid_or_password = s_of(o.get("uuid")).unwrap_or_default();
            c.flow = s_of(o.get("flow")).unwrap_or_default();
        }
        Proto::Vmess => {
            c.uuid_or_password = s_of(o.get("uuid")).unwrap_or_default();
            if let Some(sec) = s_of(o.get("security")).filter(|s| s != "auto") {
                c.method = sec;
            }
        }
        Proto::Trojan => c.uuid_or_password = s_of(o.get("password")).unwrap_or_default(),
        Proto::Shadowsocks => {
            c.uuid_or_password = s_of(o.get("password")).unwrap_or_default();
            c.method = s_of(o.get("method")).unwrap_or_default();
            if s_of(o.get("plugin")).is_some_and(|p| !p.is_empty()) {
                let mut u = c;
                u.proto = Proto::Unsupported;
                u.scheme = Some("ss+plugin".into());
                u.reason = Some("plugin".into());
                return Some(u);
            }
        }
        Proto::Hysteria2 => {
            c.uuid_or_password = s_of(o.get("password")).unwrap_or_default();
            c.network = "hysteria".into();
            c.security = "tls".into();
            if o.pointer("/obfs/type").and_then(|t| t.as_str()) == Some("salamander") {
                c.obfs_password = s_of(o.pointer("/obfs/password"));
            }
            c.up = o.get("up_mbps").and_then(|n| n.as_i64()).filter(|n| *n > 0).map(|n| n.to_string());
            c.down = o.get("down_mbps").and_then(|n| n.as_i64()).filter(|n| *n > 0).map(|n| n.to_string());
            if let Some(ports) = strs(o.get("server_ports")).filter(|p| !p.is_empty()) {
                c.mport = Some(ports.join(",").replace(':', "-"));
            }
        }
        Proto::Wireguard => {
            c.uuid_or_password = s_of(o.get("private_key")).unwrap_or_default();
            c.public_key = s_of(o.get("peer_public_key")).unwrap_or_default();
            c.preshared_key = s_of(o.get("pre_shared_key"));
            c.local_ips = strs(o.get("local_address")).map(|a| a.join(","));
            c.reserved = o.get("reserved").and_then(|r| r.as_array())
                .map(|r| r.iter().filter_map(|x| x.as_i64()).map(|x| x.to_string()).collect::<Vec<_>>().join(","));
            c.mtu = o.get("mtu").and_then(|m| m.as_i64()).filter(|m| *m > 0);
            c.network = "udp".into();
        }
        Proto::Socks => {
            c.user = s_of(o.get("username"));
            c.uuid_or_password = s_of(o.get("password")).unwrap_or_default();
        }
        Proto::Unsupported => return None,
    }
    if let Some(t) = o.get("tls").filter(|t| t.get("enabled").and_then(|e| e.as_bool()) == Some(true)) {
        if proto != Proto::Wireguard {
            c.security = "tls".into();
            c.sni = s_of(t.get("server_name")).unwrap_or_default();
            if t.get("insecure").and_then(|b| b.as_bool()) == Some(true) {
                c.allow_insecure = Some(true);
            }
            c.alpn = strs(t.get("alpn")).map(|a| a.join(","));
            c.fingerprint = s_of(t.pointer("/utls/fingerprint")).unwrap_or_default();
            if let Some(r) = t.get("reality").filter(|r| r.get("enabled").and_then(|e| e.as_bool()) == Some(true)) {
                c.security = "reality".into();
                c.public_key = s_of(r.get("public_key")).unwrap_or_default();
                c.short_id = s_of(r.get("short_id")).unwrap_or_default();
            }
        }
    }
    if let Some(tr) = o.get("transport").filter(|_| proto != Proto::Hysteria2 && proto != Proto::Wireguard) {
        match s_of(tr.get("type")).unwrap_or_default().to_lowercase().as_str() {
            "ws" => {
                c.network = "ws".into();
                c.path = s_of(tr.get("path"));
                c.host_header = s_of(tr.pointer("/headers/Host"));
            }
            "grpc" => {
                c.network = "grpc".into();
                c.service_name = s_of(tr.get("service_name"));
            }
            "httpupgrade" => {
                c.network = "httpupgrade".into();
                c.path = s_of(tr.get("path"));
                c.host_header = s_of(tr.get("host"));
            }
            "http" => {
                let mut u = c;
                u.proto = Proto::Unsupported;
                u.scheme = Some(format!("{kind}+h2"));
                u.reason = Some("transport".into());
                return Some(u);
            }
            _ => {}
        }
    }
    if c.name.is_empty() {
        c.name = c.host.clone();
    }
    (!c.host.is_empty() && c.port != 0 && (proto == Proto::Socks || !c.uuid_or_password.is_empty())).then_some(c)
}

// ── the Clash body and the profile files (iOS MontanaVPNClash, MontanaVPNFile): read by their shape ──

/// The Clash YAML read by a small reader of its own shape (iOS MontanaVPNClash): the maps under `proxies:`, nested maps by
/// indentation, flow maps and flow lists on one line, quoted scalars -- no YAML library, as on iOS.
mod clash {
    use serde_json::{json, Map, Value};

    pub struct Line {
        pub indent: usize,
        pub text: String,
    }
    fn indent_of(l: &str) -> usize {
        l.chars().take_while(|c| *c == ' ').count()
    }
    pub fn looks_like(s: &str) -> bool {
        s.lines().any(|l| l.starts_with("proxies:"))
    }
    /// The maps under `proxies:`, each as its lines with the indentation relative to the item's first key.
    pub fn items(s: &str) -> Vec<Value> {
        let lines: Vec<String> = s.lines().map(|l| l.replace('\t', "  ")).collect();
        let Some(start) = lines.iter().position(|l| l.starts_with("proxies:")) else { return vec![] };
        let mut out = Vec::new();
        let mut block: Vec<Line> = Vec::new();
        let mut base = 0;
        for line in &lines[start + 1..] {
            let t = line.trim();
            if t.is_empty() || t.starts_with('#') {
                continue;
            }
            let indent = indent_of(line);
            if indent == 0 {
                break; // the next top-level key: the list has ended
            }
            if let Some(rest) = t.strip_prefix("- ") {
                if !block.is_empty() {
                    out.push(map(&block));
                    block.clear();
                }
                base = indent + 2;
                block.push(Line { indent: 0, text: rest.trim().to_string() });
            } else if !block.is_empty() {
                block.push(Line { indent: indent.saturating_sub(base), text: t.to_string() });
            }
        }
        if !block.is_empty() {
            out.push(map(&block));
        }
        out
    }
    /// The whole document as one map (a Hysteria 2 client config).
    pub fn document(s: &str) -> Value {
        let lines: Vec<Line> = s.lines().map(|l| l.replace('\t', "  ")).filter(|l| !l.trim().is_empty() && !l.trim().starts_with('#'))
            .map(|l| Line { indent: indent_of(&l), text: l.trim().to_string() }).collect();
        map(&lines)
    }
    /// The lines of one map: `key: scalar`, `key:` with deeper lines (a nested map or a list of scalars), or a flow map.
    pub fn map(lines: &[Line]) -> Value {
        let mut m = Map::new();
        let mut i = 0;
        while i < lines.len() {
            let l = &lines[i];
            if l.text.starts_with('{') {
                if let Value::Object(f) = flow_map(&l.text) {
                    m.extend(f);
                }
                i += 1;
                continue;
            }
            let Some(colon) = key_colon(&l.text) else { i += 1; continue };
            let key = l.text[..colon].trim().to_string();
            let rest = l.text[colon + 1..].trim().to_string();
            let mut j = i + 1;
            while j < lines.len() && l.indent < lines[j].indent {
                j += 1;
            }
            if rest.is_empty() && i + 1 < j {
                let inner = &lines[i + 1..j];
                if inner[0].text.starts_with("- ") {
                    m.insert(key, Value::Array(inner.iter().map(|x| scalar(&x.text[2..])).collect()));
                } else {
                    m.insert(key, map(inner));
                }
            } else {
                m.insert(key, value(&rest));
            }
            i = j;
        }
        Value::Object(m)
    }
    /// The colon that ends a key: the first one followed by a space or the end of the line (a URL's "://" is never one).
    fn key_colon(t: &str) -> Option<usize> {
        let b = t.as_bytes();
        (0..b.len()).find(|&i| b[i] == b':' && (i + 1 == b.len() || b[i + 1] == b' '))
    }
    fn value(rest: &str) -> Value {
        if rest.starts_with('{') {
            return flow_map(rest);
        }
        if let Some(inner) = rest.strip_prefix('[') {
            let inner = inner.strip_suffix(']').unwrap_or(inner);
            return Value::Array(split_top(inner).iter().map(|x| scalar(x)).collect());
        }
        scalar(rest)
    }
    /// A scalar: a quoted word bare, true and false as booleans, digits as a number, the rest as text.
    fn scalar(raw: &str) -> Value {
        let mut t = raw.trim();
        if t.len() >= 2 && ((t.starts_with('"') && t.ends_with('"')) || (t.starts_with('\'') && t.ends_with('\''))) {
            t = &t[1..t.len() - 1];
        }
        match t {
            "true" => json!(true),
            "false" => json!(false),
            _ if !t.is_empty() && t.chars().all(|c| c.is_ascii_digit()) => t.parse::<i64>().map(|n| json!(n)).unwrap_or_else(|_| json!(t)),
            _ => json!(t),
        }
    }
    fn flow_map(s: &str) -> Value {
        let inner = s.strip_prefix('{').unwrap_or(s);
        let inner = inner.strip_suffix('}').unwrap_or(inner);
        let mut m = Map::new();
        for part in split_top(inner) {
            if let Some(colon) = key_colon(&part) {
                m.insert(part[..colon].trim().to_string(), value(part[colon + 1..].trim()));
            }
        }
        Value::Object(m)
    }
    /// Split on the commas outside braces, brackets and quotes.
    fn split_top(s: &str) -> Vec<String> {
        let (mut out, mut cur, mut depth, mut quote) = (Vec::new(), String::new(), 0i32, None::<char>);
        for ch in s.chars() {
            if let Some(q) = quote {
                cur.push(ch);
                if ch == q {
                    quote = None;
                }
                continue;
            }
            if ch == '"' || ch == '\'' {
                quote = Some(ch);
                cur.push(ch);
                continue;
            }
            if ch == '{' || ch == '[' {
                depth += 1;
            } else if ch == '}' || ch == ']' {
                depth -= 1;
            }
            if ch == ',' && depth == 0 {
                out.push(std::mem::take(&mut cur));
                continue;
            }
            cur.push(ch);
        }
        if !cur.trim().is_empty() {
            out.push(cur);
        }
        out
    }
}

/// One Clash proxy map to a server, in the engine's words (iOS MontanaVPNClash.server).
fn from_clash(m: &Value) -> Option<Config> {
    let str_ = |k: &str| -> Option<String> {
        match m.get(k)? {
            Value::String(t) => (!t.is_empty()).then(|| t.clone()),
            Value::Number(n) => Some(n.to_string()),
            _ => None,
        }
    };
    let bool_ = |k: &str| -> Option<bool> {
        match m.get(k)? {
            Value::Bool(b) => Some(*b),
            Value::String(t) if t == "true" => Some(true),
            Value::String(t) if t == "false" => Some(false),
            _ => None,
        }
    };
    let kind = str_("type").unwrap_or_default().to_lowercase();
    let name = str_("name").unwrap_or_default();
    let proto = match kind.as_str() {
        "vless" => Proto::Vless, "vmess" => Proto::Vmess, "trojan" => Proto::Trojan, "ss" => Proto::Shadowsocks,
        "hysteria2" => Proto::Hysteria2, "wireguard" => Proto::Wireguard, "socks5" => Proto::Socks,
        "" => return None,
        _ => {
            let mut u = Config::empty(Proto::Unsupported);
            u.scheme = Some(kind.clone());
            u.reason = Some("protocol".into());
            u.host = str_("server").unwrap_or_default();
            u.port = str_("port").and_then(|p| p.parse().ok()).unwrap_or(0);
            u.name = if name.is_empty() { kind.clone() } else { name.clone() };
            u.uuid_or_password = format!("{kind}:{}:{}:{name}", u.host, u.port);
            return Some(u);
        }
    };
    let mut c = Config::empty(proto);
    c.name = name;
    c.host = str_("server").unwrap_or_default();
    c.port = str_("port").and_then(|p| p.parse().ok()).unwrap_or(0);
    c.sni = str_("servername").or_else(|| str_("sni")).or_else(|| str_("peer")).unwrap_or_default();
    c.fingerprint = str_("client-fingerprint").unwrap_or_default();
    c.alpn = m.get("alpn").and_then(|a| a.as_array()).map(|a| a.iter().filter_map(|x| x.as_str()).collect::<Vec<_>>().join(","));
    if bool_("skip-cert-verify") == Some(true) {
        c.allow_insecure = Some(true);
    }
    match proto {
        Proto::Vless => {
            c.uuid_or_password = str_("uuid").unwrap_or_default();
            c.flow = str_("flow").unwrap_or_default();
            c.security = if bool_("tls") == Some(true) { "tls".into() } else { "none".into() };
        }
        Proto::Vmess => {
            c.uuid_or_password = str_("uuid").unwrap_or_default();
            if let Some(cipher) = str_("cipher").filter(|c| c != "auto") {
                c.method = cipher;
            }
            c.security = if bool_("tls") == Some(true) { "tls".into() } else { "none".into() };
        }
        Proto::Trojan => {
            c.uuid_or_password = str_("password").unwrap_or_default();
            c.security = "tls".into();
        }
        Proto::Shadowsocks => {
            c.uuid_or_password = str_("password").unwrap_or_default();
            c.method = str_("cipher").unwrap_or_default();
            if str_("plugin").is_some() {
                let mut u = c;
                u.proto = Proto::Unsupported;
                u.scheme = Some("ss+plugin".into());
                u.reason = Some("plugin".into());
                return Some(u);
            }
        }
        Proto::Hysteria2 => {
            c.uuid_or_password = str_("password").unwrap_or_default();
            c.network = "hysteria".into();
            c.security = "tls".into();
            if str_("obfs").as_deref() == Some("salamander") {
                c.obfs_password = str_("obfs-password");
            }
            let word = |s: Option<String>| s.and_then(|s| s.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse::<i64>().ok()).filter(|n| *n > 0).map(|n| n.to_string());
            c.up = word(str_("up"));
            c.down = word(str_("down"));
            c.mport = str_("ports");
            c.pin_sha256 = str_("fingerprint");
        }
        Proto::Wireguard => {
            c.uuid_or_password = str_("private-key").unwrap_or_default();
            c.public_key = str_("public-key").unwrap_or_default();
            c.preshared_key = str_("pre-shared-key");
            let ips: Vec<String> = [str_("ip"), str_("ipv6")].into_iter().flatten()
                .map(|x| if x.contains('/') { x } else if x.contains(':') { format!("{x}/128") } else { format!("{x}/32") }).collect();
            c.local_ips = Some(ips.join(","));
            c.reserved = m.get("reserved").and_then(|r| r.as_array())
                .map(|r| r.iter().filter_map(|x| x.as_i64().map(|n| n.to_string()).or_else(|| x.as_str().map(str::to_string))).collect::<Vec<_>>().join(","));
            c.mtu = str_("mtu").and_then(|m| m.parse().ok());
            c.network = "udp".into();
        }
        Proto::Socks => {
            c.user = str_("username");
            c.uuid_or_password = str_("password").unwrap_or_default();
        }
        Proto::Unsupported => return None,
    }
    if let Some(r) = m.get("reality-opts").filter(|r| r.is_object()) {
        c.security = "reality".into();
        c.public_key = s_of(r.get("public-key")).unwrap_or_default();
        c.short_id = s_of(r.get("short-id")).or_else(|| r.get("short-id").and_then(|x| x.as_i64()).map(|n| n.to_string())).unwrap_or_default();
    }
    let network = str_("network").unwrap_or_else(|| "tcp".into()).to_lowercase();
    if proto != Proto::Hysteria2 && proto != Proto::Wireguard {
        match network.as_str() {
            "ws" => {
                c.network = "ws".into();
                let w = m.get("ws-opts");
                c.path = w.and_then(|w| s_of(w.get("path")));
                c.host_header = w.and_then(|w| w.get("headers")).and_then(|h| h.as_object())
                    .and_then(|h| h.iter().find(|(k, _)| k.to_lowercase() == "host")).and_then(|(_, v)| v.as_str().map(str::to_string));
            }
            "grpc" => {
                c.network = "grpc".into();
                c.service_name = m.get("grpc-opts").and_then(|g| s_of(g.get("grpc-service-name")));
            }
            "h2" | "http" => {
                let mut u = c;
                u.proto = Proto::Unsupported;
                u.scheme = Some(format!("{kind}+{network}"));
                u.reason = Some("transport".into());
                return Some(u);
            }
            _ => {}
        }
    }
    if c.name.is_empty() {
        c.name = c.host.clone();
    }
    (!c.host.is_empty() && c.port != 0 && (proto == Proto::Socks || !c.uuid_or_password.is_empty())).then_some(c)
}

/// The host and the port of `host:port` (an IPv6 literal in brackets keeps its colons).
fn host_port(e: &str) -> Option<(String, String)> {
    if e.ends_with(']') {
        return None;
    }
    let colon = e.rfind(':')?;
    (!e[colon + 1..].contains(':')).then(|| (e[..colon].to_string(), e[colon + 1..].to_string()))
}

/// A WireGuard interface file (iOS MontanaVPNFile.wireGuard): the first peer is the server.
fn from_wireguard_file(s: &str, name: &str) -> Option<Config> {
    let (mut iface, mut peer) = (std::collections::HashMap::new(), std::collections::HashMap::new());
    let (mut section, mut peers) = (String::new(), 0);
    for raw in s.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        if line.starts_with('[') {
            section = line.to_lowercase();
            if section == "[peer]" {
                peers += 1;
            }
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        let (k, v) = (k.trim().to_lowercase(), v.trim().to_string());
        if section == "[interface]" {
            iface.insert(k, v);
        } else if section == "[peer]" && peers == 1 {
            peer.insert(k, v);
        }
    }
    let mut c = Config::empty(Proto::Wireguard);
    c.network = "udp".into();
    c.uuid_or_password = iface.get("privatekey").cloned().unwrap_or_default();
    c.public_key = peer.get("publickey").cloned().unwrap_or_default();
    c.preshared_key = peer.get("presharedkey").cloned();
    let ips = list(iface.get("address"));
    c.local_ips = (!ips.is_empty()).then(|| ips.join(","));
    c.mtu = iface.get("mtu").and_then(|m| m.parse().ok());
    let reserved = list(peer.get("reserved").or_else(|| iface.get("reserved")));
    c.reserved = (!reserved.is_empty()).then(|| reserved.join(","));
    let endpoint = peer.get("endpoint").cloned().unwrap_or_default();
    match host_port(&endpoint) {
        Some((h, p)) => { c.host = h; c.port = p.parse().unwrap_or(0); }
        None => { c.host = endpoint; c.port = 51820; }
    }
    c.name = if name.is_empty() { c.host.clone() } else { name.into() };
    (!c.host.is_empty() && c.port != 0 && !c.uuid_or_password.is_empty() && !c.public_key.is_empty()).then_some(c)
}

/// A Hysteria 2 client config (iOS MontanaVPNFile.hysteria): one map from the top.
fn from_hysteria_file(s: &str, name: &str) -> Option<Config> {
    let m = clash::document(s);
    let server = s_of(m.get("server")).filter(|x| !x.is_empty())?;
    let mut c = Config::empty(Proto::Hysteria2);
    c.network = "hysteria".into();
    c.security = "tls".into();
    let (host, ports) = host_port(&server).unwrap_or((server.clone(), String::new()));
    c.host = host;
    let words: Vec<String> = ports.split(',').map(|w| w.trim().to_string()).filter(|w| !w.is_empty()).collect();
    let plain = words.iter().find(|w| w.parse::<u16>().is_ok()).cloned();
    let leading: String = words.first().map(|w| w.chars().take_while(|c| c.is_ascii_digit()).collect()).unwrap_or_default();
    c.port = plain.as_deref().and_then(|p| p.parse().ok()).or_else(|| leading.parse().ok()).unwrap_or(443);
    let hopping: Vec<String> = words.iter().filter(|w| Some(*w) != plain.as_ref()).cloned().collect();
    if !hopping.is_empty() {
        c.mport = Some(hopping.join(","));
    }
    c.uuid_or_password = match m.get("auth") {
        Some(Value::String(a)) => a.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => String::new(),
    };
    if let Some(tls) = m.get("tls").filter(|t| t.is_object()) {
        c.sni = s_of(tls.get("sni")).unwrap_or_default();
        if tls.get("insecure").and_then(|b| b.as_bool()) == Some(true) {
            c.allow_insecure = Some(true);
        }
        c.pin_sha256 = s_of(tls.get("pinSHA256"));
    }
    if m.pointer("/obfs/type").and_then(|t| t.as_str()) == Some("salamander") {
        c.obfs_password = s_of(m.pointer("/obfs/salamander/password"));
    }
    if let Some(bw) = m.get("bandwidth") {
        c.up = mbps(bw.get("up"));
        c.down = mbps(bw.get("down"));
    }
    c.name = if name.is_empty() { c.host.clone() } else { name.into() };
    (!c.host.is_empty() && !c.uuid_or_password.is_empty()).then_some(c)
}

/// An OpenVPN profile (iOS MontanaVPNFile.openVPN): a protocol the engine does not speak -- the row says so, the profile is kept
/// whole, its `remote host port` names the machine.
fn openvpn_row(s: &str, name: &str) -> Config {
    let mut c = Config::empty(Proto::Unsupported);
    c.scheme = Some("openvpn".into());
    c.reason = Some("protocol".into());
    c.raw = Some(s.into());
    c.port = 1194;
    for l in s.lines() {
        let words: Vec<&str> = l.trim().split(' ').collect();
        if words.first() == Some(&"remote") && words.len() > 1 {
            c.host = words[1].into();
            if let Some(p) = words.get(2).and_then(|p| p.parse().ok()) {
                c.port = p;
            }
            break;
        }
    }
    c.name = if name.is_empty() { c.host.clone() } else { name.into() };
    c.uuid_or_password = format!("openvpn:{}:{}:{}", c.host, c.port, c.name);
    c
}
fn looks_like_hysteria(s: &str) -> bool {
    s.lines().any(|l| l.starts_with("server:")) && s.lines().any(|l| l.starts_with("auth:"))
}
fn looks_like_openvpn(s: &str) -> bool {
    let t: Vec<&str> = s.lines().map(str::trim).collect();
    t.iter().any(|l| l.starts_with("remote ")) && t.iter().any(|l| *l == "client" || l.starts_with("dev ") || l.starts_with("proto ") || l.starts_with("<ca>"))
}

// ── the store (iOS MontanaVPNStore, MontanaVPNPlans): sealed in the person's vault ──

/// A plan: the link the person pasted, its title and counters as the panel told them, folded or not.
#[derive(Serialize, Deserialize, Clone, Debug, Default, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Plan {
    pub url: String,
    pub title: String,
    pub updated_at: i64,
    pub count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub folded: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub upload: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub download: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub total: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub expire: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")] pub last_error: Option<String>,
    #[serde(default)] pub form: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, Default)]
pub struct Store {
    pub servers: Vec<Config>,
    pub plans: Vec<Plan>,
}

const KEY: &str = "vpnBook";
const HWID: &str = "vpnHwid";

pub fn load(v: &crate::vault::Vault) -> Store {
    v.get(KEY).and_then(|b| serde_json::from_slice(&b).ok()).unwrap_or_default()
}
pub fn save(v: &crate::vault::Vault, s: &Store) -> bool {
    serde_json::to_vec(s).is_ok_and(|b| v.set(KEY, &b))
}

/// Rows added once each (iOS add): a row whose identity stands already is not added twice; the count of the new.
pub fn add(s: &mut Store, fresh: Vec<Config>) -> usize {
    let mut n = 0;
    for mut c in fresh {
        if c.uid.is_none() {
            c.uid = Some(c.id());
        }
        if s.servers.iter().any(|x| x.id() == c.id()) {
            continue;
        }
        s.servers.push(c);
        n += 1;
    }
    n
}

/// The device's number for the panels (iOS deviceId): random, minted once, sealed -- the provider learns a number of ours, never
/// this computer's own identifier.
pub fn device_id(v: &crate::vault::Vault) -> String {
    if let Some(s) = v.get(HWID).and_then(|b| String::from_utf8(b).ok()).filter(|s| !s.is_empty()) {
        return s;
    }
    let mut r = crate::crypto::random(16).unwrap_or_else(|| crate::wire::now_ms().to_le_bytes().repeat(2));
    r[6] = (r[6] & 0x0f) | 0x40;
    r[8] = (r[8] & 0x3f) | 0x80;
    let h = crate::wire::hex(&r);
    let fresh = format!("{}-{}-{}-{}-{}", &h[..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32]);
    v.set(HWID, fresh.as_bytes());
    fresh
}

/// What the panel gave: its servers, title, counters, the body's form.
pub struct Fetched {
    pub servers: Vec<Config>,
    pub title: String,
    pub info: std::collections::BTreeMap<String, i64>,
    pub form: String,
}

/// THE PLAN'S BODY FETCHED (iOS MontanaVPNSubscription.fetch): the panel behind the person's own link and nothing of ours; a 5xx
/// or no answer is asked again (four attempts, a short pause), a 4xx is the panel's word. The failure's label as iOS writes it.
pub fn fetch(v: &crate::vault::Vault, url: &str) -> Result<Fetched, String> {
    let hwid = device_id(v);
    let headers = [("Accept", "*/*"), ("x-hwid", hwid.as_str()), ("x-device-os", "Windows"), ("x-ver-os", "10"), ("x-device-model", "PC")];
    let mut last = "network".to_string();
    for attempt in 1..=4 {
        match crate::http::get_with(url, "Montana/0.1 (Windows)", &headers, 30_000, 8_000_000, false) {
            Some((code, data, heads)) if (200..300).contains(&code) => {
                let head = |n: &str| heads.iter().find(|(k, _)| k == n).map(|(_, v)| v.as_str());
                let b = body(&data, "");
                let servers: Vec<Config> = b.servers.into_iter().map(|mut c| { c.subscription = Some(url.to_string()); c }).collect();
                crate::trace_line(&format!("vpn_sub try={attempt} status={code} bytes={} form={} servers={} dropped={}", data.len(), b.form, servers.len(), b.dropped));
                if servers.is_empty() {
                    return Err(if ["links", "base64", "engine-json", "sing-box", "clash"].contains(&b.form.as_str()) { "empty".into() } else { format!("body: {}", b.form) });
                }
                return Ok(Fetched { servers, title: header_text(head("profile-title")), info: userinfo(&header_text(head("subscription-userinfo"))), form: b.form });
            }
            Some((code, _, _)) => {
                crate::trace_line(&format!("vpn_sub try={attempt} status={code}"));
                last = format!("HTTP {code}");
                if code < 500 {
                    return Err(last);
                }
            }
            None => last = "network".into(),
        }
        if attempt < 4 {
            std::thread::sleep(std::time::Duration::from_millis(1500));
        }
    }
    Err(last)
}

/// A plan taken (or taken again): its servers stand in its place, its title and counters as the panel told them. The count.
pub fn take_plan(v: &crate::vault::Vault, url: &str) -> Result<usize, String> {
    let got = fetch(v, url);
    let mut s = load(v);
    let i = s.plans.iter().position(|p| p.url == url).unwrap_or_else(|| {
        s.plans.push(Plan { url: url.into(), ..Default::default() });
        s.plans.len() - 1
    });
    match got {
        Ok(f) => {
            s.servers.retain(|c| c.subscription.as_deref() != Some(url));
            let n = add(&mut s, f.servers);
            let p = &mut s.plans[i];
            p.title = if f.title.is_empty() { url.split('/').nth(2).unwrap_or(url).to_string() } else { f.title };
            p.updated_at = crate::wire::now_ms() / 1000;
            p.count = n;
            p.form = f.form;
            p.last_error = None;
            (p.upload, p.download, p.total, p.expire) = (f.info.get("upload").copied(), f.info.get("download").copied(),
                                                          f.info.get("total").copied(), f.info.get("expire").copied());
            save(v, &s);
            Ok(n)
        }
        Err(e) => {
            s.plans[i].last_error = Some(e.clone());
            if s.plans[i].title.is_empty() {
                s.plans[i].title = url.split('/').nth(2).unwrap_or(url).to_string();
            }
            save(v, &s);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // the vectors of iOS 2251's own tests (MontanaTests.swift, MontanaVPNTests), the same links, the same answers
    #[test]
    fn vless_reality_from_the_snapshot() {
        let link = "vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?flow=xtls-rprx-vision&type=tcp&headerType=none&security=reality&fp=safari&sni=www.example.com&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=0123456789abcdef#Amsterdam Montana 1";
        let c = parse(link).expect("vless Reality parse");
        assert_eq!(c.proto, Proto::Vless);
        assert_eq!((c.host.as_str(), c.port), ("192.0.2.3", 443));
        assert_eq!(c.uuid_or_password, "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee");
        assert_eq!((c.flow.as_str(), c.security.as_str(), c.sni.as_str()), ("xtls-rprx-vision", "reality", "www.example.com"));
        assert_eq!((c.fingerprint.as_str(), c.short_id.as_str()), ("safari", "0123456789abcdef"));
        assert_eq!(c.public_key, "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
        assert_eq!(c.name, "Amsterdam Montana 1");
    }

    #[test]
    fn the_xray_outbound_of_reality() {
        let c = parse("vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?flow=xtls-rprx-vision&type=tcp&security=reality&fp=safari&sni=www.example.com&pbk=PBK&sid=SID#N").unwrap();
        let ob = outbound(&c);
        assert_eq!(ob["protocol"], "vless");
        assert_eq!(ob["streamSettings"]["security"], "reality");
        assert_eq!(ob["streamSettings"]["realitySettings"]["serverName"], "www.example.com");
        assert_eq!(ob["streamSettings"]["realitySettings"]["publicKey"], "PBK");
        assert_eq!(ob["settings"]["vnext"][0]["users"][0]["flow"], "xtls-rprx-vision");
    }

    #[test]
    fn trojan_and_the_malformed() {
        let c = parse("trojan://secretpw@1.2.3.4:8443?security=tls&sni=example.com#Node").unwrap();
        assert_eq!((c.proto, c.uuid_or_password.as_str(), c.port, c.sni.as_str()), (Proto::Trojan, "secretpw", 8443, "example.com"));
        assert!(parse("https://example.com").is_none());
        assert!(parse("vless://").is_none());
        assert!(parse("garbage").is_none());
        let two = "vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?security=reality&pbk=A&sid=B#AMS\ntrojan://pw@5.6.7.8:443?security=tls#TRJ";
        assert_eq!(parse_many(two).len(), 2);
    }

    #[test]
    fn vless_over_xhttp_and_its_round_trip() {
        let extra = "{\"xmux\":{\"maxConcurrency\":\"16-32\"},\"xPaddingBytes\":\"333-1777\"}";
        let enc: String = extra.bytes().map(|b| if b.is_ascii_alphanumeric() { (b as char).to_string() } else { format!("%{b:02X}") }).collect();
        let link = format!("vless://11111111-2222-3333-4444-555555555555@203.0.113.7:48991?encryption=none&type=xhttp&path=%2F&mode=auto&extra={enc}&security=reality&sni=yahoo.com&fp=firefox&pbk=PBK#Auto");
        let c = parse(&link).unwrap();
        assert_eq!((c.network.as_str(), c.path.as_deref(), c.mode.as_deref()), ("xhttp", Some("/"), Some("auto")));
        assert_eq!(c.extra.as_deref(), Some(extra));
        assert_eq!(c.fingerprint, "firefox");
        assert!(c.short_id.is_empty());
        let xh = &outbound(&c)["streamSettings"]["xhttpSettings"];
        assert_eq!((xh["path"].as_str(), xh["mode"].as_str()), (Some("/"), Some("auto")));
        assert_eq!(xh["extra"]["xmux"]["maxConcurrency"], "16-32");
        let back = parse(&serialize(&c)).unwrap();
        assert_eq!((back.extra.as_deref(), back.mode.as_deref(), back.path.as_deref()), (Some(extra), Some("auto"), Some("/")));
    }

    #[test]
    fn a_plan_served_as_engine_json() {
        let body_ = r#"[{"remarks":"Netherlands","outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.7","port":48992,"users":[{"id":"11111111-2222-3333-4444-555555555555","flow":"xtls-rprx-vision","encryption":"none"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"cdn8-68.yahoo.com","publicKey":"PBK","fingerprint":"firefox"}}},{"tag":"direct","protocol":"freedom"}]},
         {"remarks":"Auto","outbounds":[{"tag":"proxy","protocol":"vless","settings":{"vnext":[{"address":"203.0.113.7","port":48991,"users":[{"id":"11111111-2222-3333-4444-555555555555","encryption":"none"}]}]},"streamSettings":{"network":"xhttp","security":"reality","realitySettings":{"serverName":"cdn3-25.yahoo.com","publicKey":"PBK","fingerprint":"firefox"},"xhttpSettings":{"mode":"auto","host":"","path":"/","extra":{"xmux":{"maxConcurrency":"16-32"}}}}}]},
         {"remarks":"Broken","outbounds":[{"tag":"direct","protocol":"freedom"}]}]"#;
        let b = body(body_.as_bytes(), "");
        assert_eq!(b.form, "engine-json");
        assert_eq!(b.servers.len(), 2);
        assert_eq!((b.servers[0].name.as_str(), b.servers[0].flow.as_str(), b.servers[0].port), ("Netherlands", "xtls-rprx-vision", 48992));
        assert_eq!((b.servers[1].network.as_str(), b.servers[1].mode.as_deref(), b.servers[1].sni.as_str()), ("xhttp", Some("auto"), "cdn3-25.yahoo.com"));
        assert!(b.servers[1].extra.as_deref().unwrap().contains("16-32"));
        // the served outbound reaches the engine as the panel wrote it, under our tag
        assert_eq!(outbound(&b.servers[1])["streamSettings"]["xhttpSettings"]["extra"]["xmux"]["maxConcurrency"], "16-32");
    }

    #[test]
    fn the_text_bodies_and_the_headers() {
        let links = "vless://11111111-2222-3333-4444-555555555555@203.0.113.7:443?security=reality&pbk=A&sid=B#One\ntrojan://pw@203.0.113.8:443?security=tls#Two";
        let blob = crate::wire::b64(links.as_bytes());
        assert_eq!(body(blob.as_bytes(), "").servers.len(), 2);
        let plain = format!("\r\n#profile-update-interval: 1\r\n#profile-title: Plan\r\n{links}\r\n");
        assert_eq!(body(plain.as_bytes(), "").servers.len(), 2);
        assert_eq!(subscription_url("https://example.org/sub/abc#Name").as_deref(), Some("https://example.org/sub/abc"));
        assert!(subscription_url("vless://x@1.2.3.4:443").is_none());
        assert_eq!(header_text(Some("base64:bWF4aW11bS12cG4uY29t")), "maximum-vpn.com");
        let ui = userinfo("upload=0; download=40333815636; total=0; expire=1820218794");
        assert_eq!((ui["download"], ui["total"], ui["expire"]), (40333815636, 0, 1820218794));
    }

    #[test]
    fn the_probe_config_is_the_outbound_only() {
        let c = parse("vless://11111111-2222-3333-4444-555555555555@203.0.113.7:48991?encryption=none&type=xhttp&path=%2F&mode=auto&security=reality&sni=yahoo.com&fp=firefox&pbk=PBK#Auto").unwrap();
        let j: Value = serde_json::from_str(&probe_config(&c).unwrap()).unwrap();
        assert!(j.get("inbounds").is_none() && j.get("routing").is_none() && j.get("dns").is_none());
        assert_eq!(j["outbounds"].as_array().unwrap().len(), 2);
        assert_eq!((j["outbounds"][0]["tag"].as_str(), j["outbounds"][1]["protocol"].as_str()), (Some("proxy"), Some("freedom")));
    }

    #[test]
    fn hysteria2_from_its_link_to_the_outbound() {
        let c = parse("hy2://secret%3Apass@hy.example.com:8443/?sni=cdn.example.com&insecure=1&obfs=salamander&obfs-password=salt&mport=20000-30000&up=100&down=200&pinSHA256=AB%3ACD#Fast").unwrap();
        assert_eq!((c.proto, c.uuid_or_password.as_str(), c.port), (Proto::Hysteria2, "secret:pass", 8443));
        assert_eq!((c.network.as_str(), c.security.as_str(), c.sni.as_str()), ("hysteria", "tls", "cdn.example.com"));
        assert_eq!((c.allow_insecure, c.obfs_password.as_deref(), c.mport.as_deref()), (Some(true), Some("salt"), Some("20000-30000")));
        assert_eq!((c.pin_sha256.as_deref(), c.name.as_str()), (Some("AB:CD"), "Fast"));
        let ob = outbound(&c);
        assert_eq!(ob["protocol"], "hysteria");
        assert_eq!((ob["settings"]["version"].as_i64(), ob["settings"]["port"].as_i64()), (Some(2), Some(8443)));
        let st = &ob["streamSettings"];
        assert_eq!(st["network"], "hysteria");
        assert_eq!(st["hysteriaSettings"]["auth"], "secret:pass");
        assert!(st["tlsSettings"].get("allowInsecure").is_none());
        assert_eq!(st["tlsSettings"]["pinnedPeerCertSha256"], "AB:CD");
        assert_eq!((st["finalmask"]["udp"][0]["type"].as_str(), st["finalmask"]["udp"][0]["settings"]["password"].as_str()), (Some("salamander"), Some("salt")));
        let quic = &st["finalmask"]["quicParams"];
        assert_eq!((quic["brutalUp"].as_str(), quic["brutalDown"].as_str()), (Some("100 mbps"), Some("200 mbps")));
        assert_eq!(quic["udpHop"]["ports"], "20000-30000");
        let bare = parse("hysteria2://pw@hy.example.com/?sni=x#Bare").unwrap();
        assert_eq!((bare.port, bare.obfs_password.is_none()), (443, true));
        assert!(outbound(&bare)["streamSettings"].get("finalmask").is_none());
        let back = parse(&serialize(&c)).unwrap();
        assert_eq!((back.obfs_password.as_deref(), back.mport.as_deref(), back.uuid_or_password.as_str()), (Some("salt"), Some("20000-30000"), "secret:pass"));
    }

    #[test]
    fn every_scheme_comes_back_from_its_own_link() {
        for link in [
            "vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?flow=xtls-rprx-vision&type=tcp&security=reality&fp=safari&sni=www.example.com&pbk=PBK&sid=ab#Один",
            "trojan://pw@1.2.3.4:443?type=ws&security=tls&sni=t.example.com&path=%2Fws&host=t.example.com#T",
            "ss://YWVzLTI1Ni1nY206c2VjcmV0@5.6.7.8:8388#SS",
            "wireguard://cHJpdmF0ZQ%3D%3D@9.9.9.9:51820?publickey=cHVibGlj&address=10.0.0.2%2F32&reserved=1%2C2%2C3&mtu=1280#WG",
            "socks://dXNlcjpwYXNz@7.7.7.7:1080#S5",
        ] {
            let c = parse(link).unwrap_or_else(|| panic!("{link}"));
            let back = parse(&serialize(&c)).unwrap_or_else(|| panic!("back {link}"));
            assert_eq!((back.proto, &back.host, back.port, &back.uuid_or_password, &back.name), (c.proto, &c.host, c.port, &c.uuid_or_password, &c.name), "{link}");
        }
        let vm = serialize(&parse("vless://aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee@192.0.2.3:443?type=grpc&security=tls&serviceName=svc#G").unwrap());
        assert!(vm.contains("serviceName=svc"));
        let w = parse("wireguard://cHJpdmF0ZQ%3D%3D@9.9.9.9:51820?publickey=cHVibGlj&address=10.0.0.2%2F32&reserved=1%2C2%2C3&mtu=1280#WG").unwrap();
        let ob = outbound(&w);
        assert_eq!((ob["settings"]["secretKey"].as_str(), ob["settings"]["mtu"].as_i64()), (Some("cHJpdmF0ZQ=="), Some(1280)));
        assert_eq!(ob["settings"]["reserved"], json!([1, 2, 3]));
        assert_eq!(ob["settings"]["peers"][0]["endpoint"], "9.9.9.9:51820");
        let unspoken = parse("tuic://x@h.example:443#T").unwrap();
        assert_eq!((unspoken.proto, unspoken.scheme.as_deref(), unspoken.name.as_str()), (Proto::Unsupported, Some("tuic"), "T"));
        assert_eq!(serialize(&unspoken), "tuic://x@h.example:443#T");
        assert!(share_json(&unspoken).is_none());
    }

    #[test]
    fn a_clash_plan_and_the_profile_files() {
        let y = "port: 7890\nproxies:\n  - name: \"Reality NL\"\n    type: vless\n    server: 203.0.113.7\n    port: 443\n    uuid: 11111111-2222-3333-4444-555555555555\n    flow: xtls-rprx-vision\n    tls: true\n    servername: cdn.example\n    client-fingerprint: chrome\n    reality-opts:\n      public-key: PBK\n      short-id: ab12\n  - {name: WS, type: vmess, server: v.example, port: 8443, uuid: 22222222-2222-3333-4444-555555555555, cipher: auto, tls: true, network: ws, ws-opts: {path: /ray, headers: {Host: h.example}}}\n  - name: Old\n    type: ssr\n    server: s.example\n    port: 1\nproxy-groups:\n  - name: auto\n";
        let b = body(y.as_bytes(), "");
        assert_eq!(b.form, "clash");
        assert_eq!(b.servers.len(), 3);
        let r = &b.servers[0];
        assert_eq!((r.proto, r.name.as_str(), r.security.as_str(), r.public_key.as_str(), r.short_id.as_str()), (Proto::Vless, "Reality NL", "reality", "PBK", "ab12"));
        assert_eq!((r.sni.as_str(), r.fingerprint.as_str(), r.flow.as_str()), ("cdn.example", "chrome", "xtls-rprx-vision"));
        let w = &b.servers[1];
        assert_eq!((w.proto, w.network.as_str(), w.path.as_deref(), w.host_header.as_deref(), w.port), (Proto::Vmess, "ws", Some("/ray"), Some("h.example"), 8443));
        assert_eq!((b.servers[2].proto, b.servers[2].scheme.as_deref()), (Proto::Unsupported, Some("ssr")));
        let wg = "[Interface]\nPrivateKey = cHJpdmF0ZQ==\nAddress = 10.0.0.2/32, fd00::2/128\nMTU = 1280\n\n[Peer]\nPublicKey = cHVibGlj\nEndpoint = 9.9.9.9:51820\n";
        let b = body(wg.as_bytes(), "home.conf");
        assert_eq!(b.form, "wireguard");
        let c = &b.servers[0];
        assert_eq!((c.host.as_str(), c.port, c.local_ips.as_deref(), c.mtu, c.name.as_str()), ("9.9.9.9", 51820, Some("10.0.0.2/32,fd00::2/128"), Some(1280), "home.conf"));
        let hy = "server: hy.example:443,20000-30000\nauth: secret\ntls:\n  sni: cdn.example\nobfs:\n  type: salamander\n  salamander:\n    password: salt\nbandwidth:\n  up: 100 mbps\n  down: 1 gbps\n";
        let b = body(hy.as_bytes(), "");
        assert_eq!(b.form, "hysteria");
        let c = &b.servers[0];
        assert_eq!((c.host.as_str(), c.port, c.mport.as_deref(), c.uuid_or_password.as_str()), ("hy.example", 443, Some("20000-30000"), "secret"));
        assert_eq!((c.sni.as_str(), c.obfs_password.as_deref(), c.up.as_deref(), c.down.as_deref()), ("cdn.example", Some("salt"), Some("100"), Some("1000")));
        let ovpn = "client\ndev tun\nproto udp\nremote vpn.example 1195\n<ca>\n</ca>\n";
        let b = body(ovpn.as_bytes(), "");
        assert_eq!((b.form.as_str(), b.servers[0].proto, b.servers[0].host.as_str(), b.servers[0].port), ("openvpn", Proto::Unsupported, "vpn.example", 1195));
    }
}
