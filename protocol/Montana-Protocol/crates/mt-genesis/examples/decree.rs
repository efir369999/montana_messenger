// Prints the parameter block that enters the Genesis State Hash. The hash itself is taken over
// the genesis-state domain, this block, and the five empty roots after it, so a reader hashing
// this output alone reproduces an input of that value and not the value itself; the trees supply
// the roots. The output carries no expected value of its own.
//
// While the set names a parameter it has not published, the block of the complete Decree does not
// exist. What is printed then is the block of the parameters that do, and the name of every one
// that does not — never a stand-in written in place of it.
fn main() {
    for (name, what) in mt_genesis::unpublished() {
        println!("unpublished {name}: {what}");
    }
    let bytes = mt_genesis::encode_published();
    println!("length {}", bytes.len());
    for b in &bytes {
        print!("{b:02x}");
    }
    println!();
    match mt_genesis::encode() {
        Some(whole) => println!("the Decree is complete at {} bytes", whole.len()),
        None => println!("no block of the whole Decree exists yet"),
    }
}
