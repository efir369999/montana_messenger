// The ordered map and set the verdict keeps its parts, keys, votes and pledges in.
//
// In every build of the protocol `Map` and `Set` are std's `BTreeMap` and `BTreeSet` and nothing
// else: the names below are a re-export, and the code a machine runs is the code it ran before
// them. Under `cfg(kani)` alone they are `sorted`, a vector kept in ascending order of its keys,
// which answers every question the verdict asks of it as the B-tree does. The reason is the model
// checker and not the protocol: cbmc unwinds the node code of std's B-tree
// (`alloc::collections::btree`, `insert_recursing`, `correct_childrens_parent_links`) into a
// program it does not reach the solver on, whatever the count of entries (the harness of Lemma 2
// in `montana-node/src/certificate.rs`, issue #10), while a sorted vector of three or four entries
// is a loop it unwinds whole. That the two answer alike is held by the tests of `sorted`, every
// sequence of operations over a small domain against the B-tree, and nothing of the protocol
// stands on `sorted` outside that check.

#[cfg(not(kani))]
pub use std::collections::{BTreeMap as Map, BTreeSet as Set};

#[cfg(kani)]
pub use sorted::{Map, Set};

#[cfg(any(kani, test))]
pub mod sorted {
    use std::slice;

    // A map over a vector of its entries, ascending by key and each key once.
    #[derive(Clone, Debug, PartialEq, Eq, Hash)]
    pub struct Map<K, V> {
        entries: Vec<(K, V)>,
    }

    impl<K, V> Default for Map<K, V> {
        fn default() -> Self {
            Self {
                entries: Vec::new(),
            }
        }
    }

    // The entry of a key, held or not, as `BTreeMap::entry` gives it.
    pub struct Entry<'a, K, V> {
        entries: &'a mut Vec<(K, V)>,
        at: Result<usize, usize>,
        key: K,
    }

    impl<'a, K, V> Entry<'a, K, V> {
        pub fn or_insert_with<F: FnOnce() -> V>(self, make: F) -> &'a mut V {
            let at = match self.at {
                Ok(at) => at,
                Err(at) => {
                    self.entries.insert(at, (self.key, make()));
                    at
                }
            };
            &mut self.entries[at].1
        }

        pub fn or_insert(self, value: V) -> &'a mut V {
            self.or_insert_with(|| value)
        }

        pub fn or_default(self) -> &'a mut V
        where
            V: Default,
        {
            self.or_insert_with(V::default)
        }
    }

    type Pair<'a, K, V> = fn(&'a (K, V)) -> (&'a K, &'a V);

    fn pair<K, V>(entry: &(K, V)) -> (&K, &V) {
        (&entry.0, &entry.1)
    }

    impl<K: Ord, V> Map<K, V> {
        pub fn new() -> Self {
            Self::default()
        }

        fn find(&self, key: &K) -> Result<usize, usize> {
            self.entries.binary_search_by(|(held, _)| held.cmp(key))
        }

        pub fn get(&self, key: &K) -> Option<&V> {
            self.find(key).ok().map(|at| &self.entries[at].1)
        }

        pub fn get_mut(&mut self, key: &K) -> Option<&mut V> {
            self.find(key).ok().map(|at| &mut self.entries[at].1)
        }

        pub fn contains_key(&self, key: &K) -> bool {
            self.find(key).is_ok()
        }

        pub fn insert(&mut self, key: K, value: V) -> Option<V> {
            match self.find(&key) {
                Ok(at) => Some(std::mem::replace(&mut self.entries[at].1, value)),
                Err(at) => {
                    self.entries.insert(at, (key, value));
                    None
                }
            }
        }

        pub fn remove(&mut self, key: &K) -> Option<V> {
            self.find(key).ok().map(|at| self.entries.remove(at).1)
        }

        pub fn entry(&mut self, key: K) -> Entry<'_, K, V> {
            let at = self.find(&key);
            Entry {
                entries: &mut self.entries,
                at,
                key,
            }
        }

        pub fn len(&self) -> usize {
            self.entries.len()
        }

        pub fn is_empty(&self) -> bool {
            self.entries.is_empty()
        }

        pub fn iter(&self) -> std::iter::Map<slice::Iter<'_, (K, V)>, Pair<'_, K, V>> {
            self.entries.iter().map(pair as Pair<'_, K, V>)
        }

        pub fn keys(&self) -> impl DoubleEndedIterator<Item = &K> + ExactSizeIterator {
            self.entries.iter().map(|(key, _)| key)
        }

        pub fn values(&self) -> impl DoubleEndedIterator<Item = &V> + ExactSizeIterator {
            self.entries.iter().map(|(_, value)| value)
        }
    }

    impl<'a, K: Ord, V> IntoIterator for &'a Map<K, V> {
        type Item = (&'a K, &'a V);
        type IntoIter = std::iter::Map<slice::Iter<'a, (K, V)>, Pair<'a, K, V>>;

        fn into_iter(self) -> Self::IntoIter {
            self.iter()
        }
    }

    impl<K, V> IntoIterator for Map<K, V> {
        type Item = (K, V);
        type IntoIter = std::vec::IntoIter<(K, V)>;

        fn into_iter(self) -> Self::IntoIter {
            self.entries.into_iter()
        }
    }

    impl<K: Ord, V> FromIterator<(K, V)> for Map<K, V> {
        fn from_iter<I: IntoIterator<Item = (K, V)>>(items: I) -> Self {
            let mut map = Self::new();
            for (key, value) in items {
                map.insert(key, value);
            }
            map
        }
    }

    // A set over a vector of its members, ascending and each once.
    #[derive(Clone, Debug, PartialEq, Eq, Hash)]
    pub struct Set<T> {
        members: Vec<T>,
    }

    impl<T> Default for Set<T> {
        fn default() -> Self {
            Self {
                members: Vec::new(),
            }
        }
    }

    impl<T: Ord> Set<T> {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn contains(&self, member: &T) -> bool {
            self.members.binary_search(member).is_ok()
        }

        pub fn insert(&mut self, member: T) -> bool {
            match self.members.binary_search(&member) {
                Ok(_) => false,
                Err(at) => {
                    self.members.insert(at, member);
                    true
                }
            }
        }

        pub fn remove(&mut self, member: &T) -> bool {
            match self.members.binary_search(member) {
                Ok(at) => {
                    self.members.remove(at);
                    true
                }
                Err(_) => false,
            }
        }

        pub fn len(&self) -> usize {
            self.members.len()
        }

        pub fn is_empty(&self) -> bool {
            self.members.is_empty()
        }

        pub fn iter(&self) -> slice::Iter<'_, T> {
            self.members.iter()
        }
    }

    impl<'a, T> IntoIterator for &'a Set<T> {
        type Item = &'a T;
        type IntoIter = slice::Iter<'a, T>;

        fn into_iter(self) -> Self::IntoIter {
            self.members.iter()
        }
    }

    impl<T> IntoIterator for Set<T> {
        type Item = T;
        type IntoIter = std::vec::IntoIter<T>;

        fn into_iter(self) -> Self::IntoIter {
            self.members.into_iter()
        }
    }

    impl<T: Ord> Extend<T> for Set<T> {
        fn extend<I: IntoIterator<Item = T>>(&mut self, items: I) {
            for member in items {
                self.insert(member);
            }
        }
    }

    impl<T: Ord> FromIterator<T> for Set<T> {
        fn from_iter<I: IntoIterator<Item = T>>(items: I) -> Self {
            let mut set = Self::new();
            set.extend(items);
            set
        }
    }
}

// Every sequence of operations over a small domain, on the sorted vector and on std's B-tree side by
// side: after each, the two answer every question the verdict asks alike.
#[cfg(test)]
mod tests {
    use super::sorted;
    use std::collections::{BTreeMap, BTreeSet};

    const KEYS: u8 = 3;

    #[derive(Clone, Copy, Debug)]
    enum Op {
        Insert(u8, u8),
        Remove(u8),
        OrInsert(u8, u8),
        OrDefaultBump(u8),
    }

    fn ops() -> Vec<Op> {
        let mut all = Vec::new();
        for key in 0..KEYS {
            for value in 0..2 {
                all.push(Op::Insert(key, value));
                all.push(Op::OrInsert(key, value));
            }
            all.push(Op::Remove(key));
            all.push(Op::OrDefaultBump(key));
        }
        all
    }

    fn apply(op: Op, vector: &mut sorted::Map<u8, u8>, tree: &mut BTreeMap<u8, u8>) {
        match op {
            Op::Insert(key, value) => {
                assert_eq!(vector.insert(key, value), tree.insert(key, value))
            }
            Op::Remove(key) => assert_eq!(vector.remove(&key), tree.remove(&key)),
            Op::OrInsert(key, value) => {
                assert_eq!(
                    *vector.entry(key).or_insert(value),
                    *tree.entry(key).or_insert(value)
                )
            }
            Op::OrDefaultBump(key) => {
                let one = vector.entry(key).or_default();
                *one = one.wrapping_add(1);
                let other = tree.entry(key).or_default();
                *other = other.wrapping_add(1);
            }
        }
    }

    fn alike(vector: &sorted::Map<u8, u8>, tree: &BTreeMap<u8, u8>) {
        assert_eq!(vector.len(), tree.len());
        assert_eq!(vector.is_empty(), tree.is_empty());
        assert!(vector.iter().eq(tree.iter()));
        assert!(vector.iter().rev().eq(tree.iter().rev()));
        assert!(vector.keys().eq(tree.keys()));
        assert!(vector.values().rev().eq(tree.values().rev()));
        assert!((&vector.clone()).into_iter().eq(tree));
        assert!(vector.clone().into_iter().eq(tree.clone()));
        for key in 0..=KEYS {
            assert_eq!(vector.get(&key), tree.get(&key));
            assert_eq!(vector.contains_key(&key), tree.contains_key(&key));
        }
        let collected: sorted::Map<u8, u8> = tree.clone().into_iter().collect();
        assert_eq!(&collected, vector);
    }

    fn walk(
        depth: usize,
        vector: &sorted::Map<u8, u8>,
        tree: &BTreeMap<u8, u8>,
        all: &[Op],
    ) -> usize {
        if depth == 0 {
            return 1;
        }
        let mut walked = 0;
        for op in all {
            let (mut one, mut other) = (vector.clone(), tree.clone());
            apply(*op, &mut one, &mut other);
            alike(&one, &other);
            walked += walk(depth - 1, &one, &other, all);
        }
        walked
    }

    #[test]
    fn a_sorted_map_answers_as_a_btree_map_after_every_sequence_of_four_operations() {
        let all = ops();
        let walked = walk(4, &sorted::Map::new(), &BTreeMap::new(), &all);
        assert_eq!(walked, all.len().pow(4));
    }

    fn walk_set(depth: usize, vector: &sorted::Set<u8>, tree: &BTreeSet<u8>) -> usize {
        if depth == 0 {
            return 1;
        }
        let mut walked = 0;
        for key in 0..KEYS {
            for insert in [true, false] {
                let (mut one, mut other) = (vector.clone(), tree.clone());
                if insert {
                    assert_eq!(one.insert(key), other.insert(key));
                } else {
                    assert_eq!(one.remove(&key), other.remove(&key));
                }
                assert_eq!(one.len(), other.len());
                assert_eq!(one.is_empty(), other.is_empty());
                assert!(one.iter().eq(other.iter()));
                assert!(one.iter().rev().eq(other.iter().rev()));
                assert!(one
                    .clone()
                    .into_iter()
                    .rev()
                    .eq(other.clone().into_iter().rev()));
                for probe in 0..=KEYS {
                    assert_eq!(one.contains(&probe), other.contains(&probe));
                }
                let mut extended = one.clone();
                extended.extend(other.iter().copied().chain(0..KEYS));
                let mut extended_tree = other.clone();
                extended_tree.extend(0..KEYS);
                assert!(extended.iter().eq(extended_tree.iter()));
                walked += walk_set(depth - 1, &one, &other);
            }
        }
        walked
    }

    #[test]
    fn a_sorted_set_answers_as_a_btree_set_after_every_sequence_of_five_operations() {
        let walked = walk_set(5, &sorted::Set::new(), &BTreeSet::new());
        assert_eq!(walked, (2 * usize::from(KEYS)).pow(5));
    }
}
