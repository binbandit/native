//! `--probe-sandbox <path>`: reports whether this process can read `path` and open a network
//! connection, so tests can prove the operating-system sandbox applies to the signed helper. It
//! runs no script and adds no capability: it only uses the process's own permissions.

use serde_json::json;
use std::io::ErrorKind;
use std::net::{SocketAddr, TcpStream};
use std::time::Duration;

pub fn run(path: &str) {
    let file = match std::fs::read(path) {
        Ok(_) => "allowed".to_string(),
        Err(error) if error.kind() == ErrorKind::PermissionDenied => "denied".to_string(),
        Err(error) => format!("error: {error}"),
    };
    let address = SocketAddr::from(([1, 1, 1, 1], 443));
    let network = match TcpStream::connect_timeout(&address, Duration::from_secs(3)) {
        Ok(_) => "allowed".to_string(),
        Err(error) if error.kind() == ErrorKind::PermissionDenied => "denied".to_string(),
        Err(error) => format!("error: {error}"),
    };
    println!("{}", json!({ "fileRead": file, "network": network }));
}
