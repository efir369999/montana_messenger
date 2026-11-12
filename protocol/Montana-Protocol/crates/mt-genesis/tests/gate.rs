// The gate travels with the crate: a consumer that runs the tests of what it depends on runs the
// comparison of the set and the code over it. The invocation is one declaration in `mt-conformance`
// and this is its call, so fourteen crates carry one gate rather than fourteen readings of it.
mt_conformance::gate!();
