//! TCP+TLS configs of the testbed (Stage 1; spec §152 -- TCP/TLS-443 is mandatory). The TLS 1.3
//! transport hop = admission A-3 ([I-16]): the postman has a self-signed cert, the client accepts it without PKI.
//! Participant authenticity is carried by the ML-DSA registration (RegProof) + the E2E envelope, NOT the cert.

use std::sync::Arc;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, CryptoProvider};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use thiserror::Error;
use tokio_rustls::{TlsAcceptor, TlsConnector};

pub const STAND_SNI: &str = "montana-postman";

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("self-signed cert: {0}")]
    Cert(String),
    #[error("rustls: {0}")]
    Rustls(#[from] rustls::Error),
}

fn ring_provider() -> Arc<CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// Server rustls config of the postman: self-signed cert, TLS 1.3 only.
pub fn stand_server_config() -> Result<Arc<rustls::ServerConfig>, ConfigError> {
    let cert = rcgen::generate_simple_self_signed(vec![STAND_SNI.to_string()])
        .map_err(|e| ConfigError::Cert(e.to_string()))?;
    let cert_der: CertificateDer<'static> = cert.cert.der().clone();
    let key_der = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(cert.key_pair.serialize_der()));
    let sc = rustls::ServerConfig::builder_with_provider(ring_provider())
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .with_no_client_auth()
        .with_single_cert(vec![cert_der], key_der)?;
    Ok(Arc::new(sc))
}

/// Client rustls config: accepts the postman's self-signed cert (skips transport PKI).
/// [I-16]: the transport cert is not security; authenticity is the ML-DSA registration + E2E.
pub fn stand_client_config() -> Result<Arc<rustls::ClientConfig>, ConfigError> {
    let p = ring_provider();
    let cc = rustls::ClientConfig::builder_with_provider(p.clone())
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(SkipTransportPki(p)))
        .with_no_client_auth();
    Ok(Arc::new(cc))
}

/// Server TLS acceptor (wraps a TCP connection in TLS 1.3).
pub fn tls_acceptor() -> Result<TlsAcceptor, ConfigError> {
    Ok(TlsAcceptor::from(stand_server_config()?))
}

/// Client TLS connector (wraps a TCP connection in TLS 1.3).
pub fn tls_connector() -> Result<TlsConnector, ConfigError> {
    Ok(TlsConnector::from(stand_client_config()?))
}

#[derive(Debug)]
struct SkipTransportPki(Arc<CryptoProvider>);

impl ServerCertVerifier for SkipTransportPki {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls12_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        verify_tls13_signature(
            message,
            cert,
            dss,
            &self.0.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.0.signature_verification_algorithms.supported_schemes()
    }
}
