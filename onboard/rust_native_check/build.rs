fn main() {
    println!("cargo:rerun-if-changed=src/native_check.c");
    cc::Build::new().file("src/native_check.c").compile("native_check");
}
