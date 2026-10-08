//! Standalone MUQ postman (backend always-on relay/queue-host) with a persistent ML-KEM
//! identity. Arguments: [bind_addr=0.0.0.0:8445] [seed_path=postman-identity.bin].
//! Clients use the printed bind address and host_kem_pk (hex) for sealing.

use std::net::SocketAddr;
use std::path::Path;

use mt_postman::server::PostmanServer;

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

fn load_or_generate_seed(path: &Path) -> [u8; mt_crypto::MLKEM_SEED_SIZE] {
    let mut seed = [0u8; mt_crypto::MLKEM_SEED_SIZE];
    if let Ok(bytes) = std::fs::read(path) {
        if bytes.len() == seed.len() {
            seed.copy_from_slice(&bytes);
            return seed;
        }
    }
    getrandom::getrandom(&mut seed).expect("OS CSPRNG");
    std::fs::write(path, seed).expect("persist identity seed");
    seed
}

#[tokio::main]
async fn main() {
    let bind: SocketAddr = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "0.0.0.0:8445".to_string())
        .parse()
        .expect("valid bind addr");
    let seed_path = std::env::args()
        .nth(2)
        .unwrap_or_else(|| "postman-identity.bin".to_string());

    let seed = load_or_generate_seed(Path::new(&seed_path));
    let server = PostmanServer::bind_with_seed(bind, &seed)
        .await
        .expect("bind postman");
    let addr = server.local_addr().expect("local addr");
    let host_kem_pk = server.muq().host_kem_pubkey();

    // A lone genesis postman = courier+host: self-route host_overlay -> loopback,
    // otherwise the client's two-hop deposit does not find the host in proxy_routes.
    let host_overlay = mt_crypto::sha256_raw(&host_kem_pk.as_bytes()[..]);
    let loopback = SocketAddr::new(std::net::Ipv4Addr::LOCALHOST.into(), addr.port());
    server.muq().add_proxy_route(host_overlay, loopback);

    println!("Montana postman listening: {addr}");
    println!("host_kem_pk: {}", hex(host_kem_pk.as_bytes()));
    println!("host_overlay: {}", hex(&host_overlay));
    println!("identity seed: {seed_path} (persist -- do not lose)");
    server.run().await;
}
