//! A NODE PUT UP FROM THIS COMPUTER, BY ADDRESS, LOGIN AND PASSWORD (iOS MontanaNodeSetup, MTSSHRun; the author's word 28.09.2026:
//! «a way into your own node by the root login, the password and the IP address»). A machine the person rents stands bare; the app
//! reaches it the one way a bare machine can be reached -- its SSH door -- puts the door of Montana on it (the very two files iOS
//! carries, Code/Node, in src-tauri\node byte for byte), lets install.sh make a certificate of the machine's own, and keeps that
//! certificate's digest: from then on the app speaks TLS to the address straight and trusts that digest alone (homenode, http::
//! exchange's pin). SSH here is the admission ticket of an external standard: the machine's own door speaks it and nothing else
//! before Montana stands on it. The password rides once and is kept nowhere; the first meeting takes the machine's host key as it
//! is -- the person named the machine by address and password, exactly as the first `ssh` of every operator does.

use russh::client;
use russh::ChannelMsg;
use std::sync::Arc;
use std::time::Duration;

/// The door and its set-up, one source (iOS Code/Node): the door a person runs by hand from the public tree, and install.sh.
pub const DOOR: &[u8] = include_bytes!("../node/montana-home-node.py");
pub const SCRIPT: &[u8] = include_bytes!("../node/install.sh");

/// The first meeting: the machine's host key taken as it is (iOS FirstMeeting).
struct FirstMeeting;
impl client::Handler for FirstMeeting {
    type Error = russh::Error;
    async fn check_server_key(&mut self, _key: &russh::keys::PublicKeyOrCertificate) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

/// What one command on the machine left: its exit status, its output, its errors.
#[derive(Debug)]
pub struct Outcome {
    pub status: u32,
    pub out: String,
    pub err: String,
}

/// ONE COMMAND ON THE MACHINE (iOS MTSSHRun.run): its standard input handed whole, its output and exit status brought back, within
/// `seconds`. One password, offered once.
pub async fn run(host: &str, user: &str, password: &str, command: &str, stdin: &[u8], seconds: u64) -> Result<Outcome, String> {
    let work = async {
        let config = Arc::new(client::Config { inactivity_timeout: Some(Duration::from_secs(seconds)), ..Default::default() });
        let mut session = client::connect(config, (host, 22), FirstMeeting).await.map_err(|e| format!("connect {e}"))?;
        let auth = session.authenticate_password(user, password).await.map_err(|e| format!("auth {e}"))?;
        if !auth.success() {
            return Err("the password was refused".to_string());
        }
        let mut ch = session.channel_open_session().await.map_err(|e| format!("channel {e}"))?;
        ch.exec(true, command).await.map_err(|e| format!("exec {e}"))?;
        if !stdin.is_empty() {
            ch.data(stdin).await.map_err(|e| format!("stdin {e}"))?;
        }
        ch.eof().await.map_err(|e| format!("eof {e}"))?;
        let (mut out, mut err, mut status) = (Vec::new(), Vec::new(), None);
        while let Some(msg) = ch.wait().await {
            match msg {
                ChannelMsg::Data { ref data } => out.extend_from_slice(data),
                ChannelMsg::ExtendedData { ref data, ext: 1 } => err.extend_from_slice(data),
                ChannelMsg::ExitStatus { exit_status } => status = Some(exit_status),
                _ => {}
            }
        }
        let _ = session.disconnect(russh::Disconnect::ByApplication, "", "en").await;
        Ok(Outcome { status: status.ok_or("closed")?, out: String::from_utf8_lossy(&out).into_owned(), err: String::from_utf8_lossy(&err).into_owned() })
    };
    tokio::time::timeout(Duration::from_secs(seconds), work).await.map_err(|_| "timeout".to_string())?
}

/// The digest install.sh prints (openssl's own word «…Fingerprint=AB:CD:…»): 64 hex, small letters.
pub fn fingerprint(out: &str) -> Option<String> {
    let line = out.lines().rev().find(|l| l.contains("Fingerprint="))?;
    let fp = line.split_once('=')?.1.replace(':', "").trim().to_lowercase();
    (fp.len() == 64 && fp.chars().all(|c| c.is_ascii_hexdigit())).then_some(fp)
}

/// PUTS THE DOOR UP ON THE MACHINE (iOS MontanaNodeSetup.run) and brings back the digest of its certificate, 64 hex.
pub async fn set_up(host: &str, user: &str, password: &str) -> Result<String, String> {
    let put = run(host, user, password, "mkdir -p /opt/montana-node-store && cat > /opt/montana-node-store/montana-node-store.py", DOOR, 120).await?;
    if put.status != 0 {
        return Err(format!("{} {}", put.status, put.err.trim()));
    }
    let ran = run(host, user, password, &format!("bash -s -- {host}"), SCRIPT, 300).await?;
    if ran.status != 0 {
        return Err(format!("{} {}", ran.status, if ran.err.trim().is_empty() { ran.out.trim() } else { ran.err.trim() }));
    }
    crate::trace_line(&format!("home_node set up: active={}", if ran.out.contains("active") { 1 } else { 0 }));
    fingerprint(&ran.out).ok_or_else(|| "no fingerprint".to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_door_is_ios_own_and_the_fingerprint_is_read_as_openssl_prints_it() {
        // the two files iOS 2251 carries (Code/Node, blobs 993d59bc… and 80eefc44…), byte for byte
        assert_eq!(crate::wire::hex(&crate::wire::sha(&[DOOR])), "5f8ad2bc0b06d5de36bdde324cb40ff7f6db4e3865a4580102b0a62e7530e141");
        assert_eq!(crate::wire::hex(&crate::wire::sha(&[SCRIPT])), "e344aedf6894558f471716a76d3d1a7b4305e932d3d291800533eb9a54ad30b5");
        let out = "active\nsha256 Fingerprint=AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89\n";
        assert_eq!(fingerprint(out).as_deref(), Some("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"));
        assert_eq!(fingerprint("active\n"), None);
        assert_eq!(fingerprint("SHA256 Fingerprint=AB:CD\n"), None);
    }
}
