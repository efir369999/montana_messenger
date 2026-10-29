// The ordered collections of this crate. Every build of a machine takes the standard library's own;
// the model checker takes a sorted vector with the same order and the part of the interface this crate
// calls. The symbolic execution of the standard tree never ended: on Lauterbourg-3 the classes of
// Lemma 2 ran some 70 000 s each and stood in the node code of `btree` (insert_recursing,
// correct_childrens_parent_links) with no verdict, while what a harness asks of a map is only its
// order and its contents. A field of a public type is one of these, so the whole crate names them
// through this module and never through `std::collections`; a harness then reads the same order the
// node does.
//
// The vector is kept sorted by its key at every step and holds a key once, so iteration, `first`,
// `last` and equality agree with the tree's; its own tests run every operation against the standard
// collections on the same sequence.

#[cfg(not(kani))]
pub use std::collections::{BTreeMap, BTreeSet};

#[cfg(kani)]
pub use ordered::{BTreeMap, BTreeSet};

// A crate beyond this one takes the standard map, and never this module's: `mt_proof::records` reads
// the records of a machine as one. Every build of a machine hands over its own, borrowed; the model
// checker hands over a standard map of the same entries in the same order, so the root and the path
// it reads are the node's.
#[cfg(not(kani))]
pub fn standard<K: Clone, V: Clone>(
    map: &BTreeMap<K, V>,
) -> std::borrow::Cow<'_, std::collections::BTreeMap<K, V>> {
    std::borrow::Cow::Borrowed(map)
}

#[cfg(kani)]
pub fn standard<K: Ord + Clone, V: Clone>(
    map: &BTreeMap<K, V>,
) -> std::borrow::Cow<'_, std::collections::BTreeMap<K, V>> {
    std::borrow::Cow::Owned(
        map.iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect(),
    )
}

#[cfg(any(kani, test))]
pub mod ordered {
    use std::borrow::Borrow;
    use std::cmp::Ordering;
    use std::fmt;

    // Where `key` stands among the sorted `keys`: found at an index, or the index it would be
    // inserted at to keep the order.
    fn place<'a, K: 'a + Borrow<Q>, Q: Ord + ?Sized>(
        keys: impl Iterator<Item = &'a K>,
        key: &Q,
    ) -> Result<usize, usize> {
        let mut at = 0;
        for held in keys {
            match held.borrow().cmp(key) {
                Ordering::Less => at += 1,
                Ordering::Equal => return Ok(at),
                Ordering::Greater => return Err(at),
            }
        }
        Err(at)
    }

    #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub struct BTreeMap<K, V> {
        entries: Vec<(K, V)>,
    }

    pub type Iter<'a, K, V> = std::iter::Map<std::slice::Iter<'a, (K, V)>, fn(&(K, V)) -> (&K, &V)>;
    pub type IterMut<'a, K, V> =
        std::iter::Map<std::slice::IterMut<'a, (K, V)>, fn(&mut (K, V)) -> (&K, &mut V)>;

    fn pair<K, V>(entry: &(K, V)) -> (&K, &V) {
        (&entry.0, &entry.1)
    }

    fn pair_mut<K, V>(entry: &mut (K, V)) -> (&K, &mut V) {
        let (key, value) = entry;
        (&*key, value)
    }

    impl<K, V> Default for BTreeMap<K, V> {
        fn default() -> Self {
            Self {
                entries: Vec::new(),
            }
        }
    }

    impl<K, V> BTreeMap<K, V> {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn len(&self) -> usize {
            self.entries.len()
        }

        pub fn is_empty(&self) -> bool {
            self.entries.is_empty()
        }

        pub fn clear(&mut self) {
            self.entries.clear();
        }

        pub fn iter(&self) -> Iter<'_, K, V> {
            self.entries.iter().map(pair as fn(&(K, V)) -> (&K, &V))
        }

        pub fn iter_mut(&mut self) -> IterMut<'_, K, V> {
            self.entries
                .iter_mut()
                .map(pair_mut as fn(&mut (K, V)) -> (&K, &mut V))
        }

        pub fn keys(&self) -> impl DoubleEndedIterator<Item = &K> + ExactSizeIterator {
            self.entries.iter().map(|(key, _)| key)
        }

        pub fn values(&self) -> impl DoubleEndedIterator<Item = &V> + ExactSizeIterator {
            self.entries.iter().map(|(_, value)| value)
        }

        pub fn values_mut(
            &mut self,
        ) -> impl DoubleEndedIterator<Item = &mut V> + ExactSizeIterator {
            self.entries.iter_mut().map(|(_, value)| value)
        }

        pub fn first_key_value(&self) -> Option<(&K, &V)> {
            self.entries.first().map(pair)
        }

        pub fn last_key_value(&self) -> Option<(&K, &V)> {
            self.entries.last().map(pair)
        }

        pub fn retain<F: FnMut(&K, &mut V) -> bool>(&mut self, mut keep: F) {
            self.entries.retain_mut(|(key, value)| keep(key, value));
        }
    }

    impl<K: Ord, V> BTreeMap<K, V> {
        fn at<Q: Ord + ?Sized>(&self, key: &Q) -> Result<usize, usize>
        where
            K: Borrow<Q>,
        {
            place(self.entries.iter().map(|(held, _)| held), key)
        }

        pub fn get<Q: Ord + ?Sized>(&self, key: &Q) -> Option<&V>
        where
            K: Borrow<Q>,
        {
            let at = self.at(key).ok()?;
            self.entries.get(at).map(|(_, value)| value)
        }

        pub fn get_mut<Q: Ord + ?Sized>(&mut self, key: &Q) -> Option<&mut V>
        where
            K: Borrow<Q>,
        {
            let at = self.at(key).ok()?;
            self.entries.get_mut(at).map(|(_, value)| value)
        }

        pub fn contains_key<Q: Ord + ?Sized>(&self, key: &Q) -> bool
        where
            K: Borrow<Q>,
        {
            self.at(key).is_ok()
        }

        pub fn insert(&mut self, key: K, value: V) -> Option<V> {
            match self.at(&key) {
                Ok(at) => Some(std::mem::replace(&mut self.entries[at].1, value)),
                Err(at) => {
                    self.entries.insert(at, (key, value));
                    None
                }
            }
        }

        pub fn remove<Q: Ord + ?Sized>(&mut self, key: &Q) -> Option<V>
        where
            K: Borrow<Q>,
        {
            let at = self.at(key).ok()?;
            Some(self.entries.remove(at).1)
        }

        pub fn entry(&mut self, key: K) -> Entry<'_, K, V> {
            Entry { map: self, key }
        }
    }

    // The entry of one key: only the three ways this crate fills one.
    pub struct Entry<'a, K, V> {
        map: &'a mut BTreeMap<K, V>,
        key: K,
    }

    impl<'a, K: Ord, V> Entry<'a, K, V> {
        pub fn or_insert_with<F: FnOnce() -> V>(self, make: F) -> &'a mut V {
            let Entry { map, key } = self;
            let at = match map.at(&key) {
                Ok(at) => at,
                Err(at) => {
                    map.entries.insert(at, (key, make()));
                    at
                }
            };
            &mut map.entries[at].1
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

    impl<K: Ord, V> FromIterator<(K, V)> for BTreeMap<K, V> {
        fn from_iter<I: IntoIterator<Item = (K, V)>>(items: I) -> Self {
            let mut map = Self::new();
            map.extend(items);
            map
        }
    }

    impl<K: Ord, V> Extend<(K, V)> for BTreeMap<K, V> {
        fn extend<I: IntoIterator<Item = (K, V)>>(&mut self, items: I) {
            for (key, value) in items {
                self.insert(key, value);
            }
        }
    }

    impl<K, V> IntoIterator for BTreeMap<K, V> {
        type Item = (K, V);
        type IntoIter = std::vec::IntoIter<(K, V)>;
        fn into_iter(self) -> Self::IntoIter {
            self.entries.into_iter()
        }
    }

    impl<'a, K, V> IntoIterator for &'a BTreeMap<K, V> {
        type Item = (&'a K, &'a V);
        type IntoIter = Iter<'a, K, V>;
        fn into_iter(self) -> Self::IntoIter {
            self.iter()
        }
    }

    impl<'a, K, V> IntoIterator for &'a mut BTreeMap<K, V> {
        type Item = (&'a K, &'a mut V);
        type IntoIter = IterMut<'a, K, V>;
        fn into_iter(self) -> Self::IntoIter {
            self.iter_mut()
        }
    }

    impl<K: fmt::Debug, V: fmt::Debug> fmt::Debug for BTreeMap<K, V> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.debug_map().entries(self.iter()).finish()
        }
    }

    #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
    pub struct BTreeSet<T> {
        items: Vec<T>,
    }

    impl<T> Default for BTreeSet<T> {
        fn default() -> Self {
            Self { items: Vec::new() }
        }
    }

    impl<T> BTreeSet<T> {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn len(&self) -> usize {
            self.items.len()
        }

        pub fn is_empty(&self) -> bool {
            self.items.is_empty()
        }

        pub fn clear(&mut self) {
            self.items.clear();
        }

        pub fn iter(&self) -> std::slice::Iter<'_, T> {
            self.items.iter()
        }

        pub fn first(&self) -> Option<&T> {
            self.items.first()
        }

        pub fn last(&self) -> Option<&T> {
            self.items.last()
        }

        pub fn retain<F: FnMut(&T) -> bool>(&mut self, keep: F) {
            self.items.retain(keep);
        }
    }

    impl<T: Ord> BTreeSet<T> {
        pub fn contains<Q: Ord + ?Sized>(&self, item: &Q) -> bool
        where
            T: Borrow<Q>,
        {
            place(self.items.iter(), item).is_ok()
        }

        pub fn insert(&mut self, item: T) -> bool {
            match place(self.items.iter(), &item) {
                Ok(_) => false,
                Err(at) => {
                    self.items.insert(at, item);
                    true
                }
            }
        }

        pub fn remove<Q: Ord + ?Sized>(&mut self, item: &Q) -> bool
        where
            T: Borrow<Q>,
        {
            match place(self.items.iter(), item) {
                Ok(at) => {
                    self.items.remove(at);
                    true
                }
                Err(_) => false,
            }
        }
    }

    impl<T: Ord> FromIterator<T> for BTreeSet<T> {
        fn from_iter<I: IntoIterator<Item = T>>(items: I) -> Self {
            let mut set = Self::new();
            set.extend(items);
            set
        }
    }

    impl<T: Ord> Extend<T> for BTreeSet<T> {
        fn extend<I: IntoIterator<Item = T>>(&mut self, items: I) {
            for item in items {
                self.insert(item);
            }
        }
    }

    impl<'a, T: 'a + Ord + Copy> Extend<&'a T> for BTreeSet<T> {
        fn extend<I: IntoIterator<Item = &'a T>>(&mut self, items: I) {
            for item in items {
                self.insert(*item);
            }
        }
    }

    impl<T> IntoIterator for BTreeSet<T> {
        type Item = T;
        type IntoIter = std::vec::IntoIter<T>;
        fn into_iter(self) -> Self::IntoIter {
            self.items.into_iter()
        }
    }

    impl<'a, T> IntoIterator for &'a BTreeSet<T> {
        type Item = &'a T;
        type IntoIter = std::slice::Iter<'a, T>;
        fn into_iter(self) -> Self::IntoIter {
            self.items.iter()
        }
    }

    impl<T: fmt::Debug> fmt::Debug for BTreeSet<T> {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            f.debug_set().entries(self.iter()).finish()
        }
    }

    #[cfg(test)]
    mod tests {
        use super::{BTreeMap, BTreeSet};
        use std::collections::{BTreeMap as StdMap, BTreeSet as StdSet};

        // A sequence of small keys that repeats some of them, the same on every run.
        fn keys(count: usize) -> Vec<u8> {
            let mut state = 0x2545_f491_u32;
            (0..count)
                .map(|_| {
                    state = state.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                    (state >> 24) as u8 % 23
                })
                .collect()
        }

        #[test]
        fn the_sorted_map_answers_as_the_standard_map_at_every_step() {
            let mut ours: BTreeMap<u8, u32> = BTreeMap::new();
            let mut theirs: StdMap<u8, u32> = StdMap::new();
            for (step, key) in keys(600).into_iter().enumerate() {
                let value = step as u32;
                match step % 7 {
                    0 | 1 => assert_eq!(ours.insert(key, value), theirs.insert(key, value)),
                    2 => assert_eq!(ours.remove(&key), theirs.remove(&key)),
                    3 => *ours.entry(key).or_default() += value,
                    4 => {
                        if let Some(held) = ours.get_mut(&key) {
                            *held ^= value;
                        }
                    }
                    5 => {
                        ours.entry(key).or_insert(value);
                    }
                    _ => {
                        ours.entry(key).or_insert_with(|| value + 1);
                    }
                }
                match step % 7 {
                    3 => *theirs.entry(key).or_default() += value,
                    4 => {
                        if let Some(held) = theirs.get_mut(&key) {
                            *held ^= value;
                        }
                    }
                    5 => {
                        theirs.entry(key).or_insert(value);
                    }
                    6 => {
                        theirs.entry(key).or_insert_with(|| value + 1);
                    }
                    _ => {}
                }
                if step % 97 == 0 {
                    ours.retain(|key, value| (u32::from(*key) + *value) % 3 != 0);
                    theirs.retain(|key, value| (u32::from(*key) + *value) % 3 != 0);
                }
                assert_eq!(ours.len(), theirs.len());
                assert_eq!(ours.is_empty(), theirs.is_empty());
                assert_eq!(ours.get(&key), theirs.get(&key));
                assert_eq!(ours.contains_key(&key), theirs.contains_key(&key));
                assert_eq!(ours.first_key_value(), theirs.first_key_value());
                assert_eq!(ours.last_key_value(), theirs.last_key_value());
                assert!(ours.iter().eq(theirs.iter()));
            }
            assert!(ours.keys().rev().eq(theirs.keys().rev()));
            assert!(ours.values().eq(theirs.values()));
            for (key, value) in &mut ours {
                *value += u32::from(*key);
            }
            for (key, value) in &mut theirs {
                *value += u32::from(*key);
            }
            for value in ours.values_mut() {
                *value += 1;
            }
            for value in theirs.values_mut() {
                *value += 1;
            }
            assert_eq!(format!("{ours:?}"), format!("{theirs:?}"));
            assert!(ours.into_iter().rev().eq(theirs.into_iter().rev()));
        }

        #[test]
        fn the_sorted_set_answers_as_the_standard_set_at_every_step() {
            let mut ours: BTreeSet<u8> = BTreeSet::new();
            let mut theirs: StdSet<u8> = StdSet::new();
            for (step, key) in keys(600).into_iter().enumerate() {
                if step % 3 == 2 {
                    assert_eq!(ours.remove(&key), theirs.remove(&key));
                } else {
                    assert_eq!(ours.insert(key), theirs.insert(key));
                }
                if step % 89 == 0 {
                    ours.retain(|key| key % 4 != 1);
                    theirs.retain(|key| key % 4 != 1);
                }
                assert_eq!(ours.len(), theirs.len());
                assert_eq!(ours.contains(&key), theirs.contains(&key));
                assert_eq!(ours.first(), theirs.first());
                assert_eq!(ours.last(), theirs.last());
                assert!(ours.iter().eq(theirs.iter()));
            }
            let more = keys(40);
            ours.extend(more.iter());
            theirs.extend(more.iter());
            assert_eq!(format!("{ours:?}"), format!("{theirs:?}"));
            assert!(ours.into_iter().rev().eq(theirs.into_iter().rev()));
        }

        #[test]
        fn what_is_collected_stands_in_the_order_of_the_standard_collections() {
            let pairs: Vec<(u8, usize)> = keys(200).into_iter().zip(0..).collect();
            let ours: BTreeMap<u8, usize> = pairs.iter().copied().collect();
            let theirs: StdMap<u8, usize> = pairs.iter().copied().collect();
            assert!(ours.iter().eq(theirs.iter()));
            let ours: BTreeSet<u8> = keys(200).into_iter().collect();
            let theirs: StdSet<u8> = keys(200).into_iter().collect();
            assert!(ours.iter().eq(theirs.iter()));
            let mut emptied = ours.clone();
            emptied.clear();
            assert!(emptied.is_empty() && emptied < ours);
        }
    }
}
