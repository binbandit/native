//! Embeds Info.plist in the executable: the App Sandbox reads a command-line tool's bundle
//! identifier from it to set up the tool's container.
fn main() {
    println!("cargo:rerun-if-changed=Info.plist");
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let plist = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("Info.plist");
    println!("cargo:rustc-link-arg-bins=-Wl,-sectcreate,__TEXT,__info_plist,{}", plist.display());
    // V8 built with its sandbox uses PartitionAlloc, which checks the process's JIT entitlement.
    if std::env::var_os("CARGO_FEATURE_SANDBOX").is_some() {
        println!("cargo:rustc-link-lib=framework=Security");
        println!("cargo:rustc-link-lib=framework=CoreFoundation");
    }
}
