fn main() {
    println!("cargo:rerun-if-changed=proto/hello.proto");

    prost_build::Config::new()
        .compile_protos(&["proto/hello.proto"], &["proto"])
        .expect("failed to compile proto files");
}
