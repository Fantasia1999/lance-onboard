unsafe extern "C" {
    fn native_add(a: i32, b: i32) -> i32;
}

fn main() {
    let sum = unsafe { native_add(20, 22) };
    assert_eq!(sum, 42);
    println!("rust-native-check: ok ({sum})");
}
