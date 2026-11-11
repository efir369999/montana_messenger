// Draws a person on this machine and reports what it stood on. What is printed is the measure of
// every source — how many samples it gave, how many of them differed, how often the most frequent
// repeated, and the verdict — and never a byte of any source, of the entropy, of the seed or of a
// branch. A person is entitled to see what their identity stands on; nobody is entitled to see the
// bytes.

fn main() {
    match mt_seed::birth(None) {
        Ok(born) => {
            println!("sources, in the order the set states them:");
            for m in &born.measures {
                println!(
                    "  {:?}: {} samples, {} distinct, most frequent {} — {}",
                    m.source,
                    m.samples,
                    m.distinct,
                    m.most_frequent,
                    if m.alive { "alive" } else { "not alive" }
                );
            }
            println!(
                "living sources: {} of {}, the floor being {}",
                born.alive(),
                born.measures.len(),
                mt_seed::MIN_LIVE_SOURCES
            );
            println!("the twenty-four words stay on this device and are not printed here");
        }
        Err(refusal) => println!("refused: {refusal:?}"),
    }
}
