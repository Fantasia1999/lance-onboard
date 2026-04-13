pub mod hello {
    include!(concat!(env!("OUT_DIR"), "/toolchain.hello.rs"));
}

fn main() {
    let message = hello::Hello {
        name: "LanceDB".to_string(),
        id: 42,
    };

    assert_eq!(message.name, "LanceDB");
    assert_eq!(message.id, 42);

    println!(
        "rust-protoc-check: ok (name={}, id={})",
        message.name, message.id
    );
}
