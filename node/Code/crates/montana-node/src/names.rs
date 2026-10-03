//! Слой имён на узле: пачка, индекс, корзина, приём обращений (чек-лист C-14, C-16..C-18).
//!
//! **Подсистема выключена по умолчанию.** Пока автор не проверил её вживую, узел ведёт себя
//! ровно как прежде: `NamesService::disabled()` не собирает пачек, не сканирует цепь и не
//! отвечает на запросы. Ни одна существующая ветка узла этот модуль не вызывает — включение
//! делается явно и отдельным решением.

use mt_account::Anchor;
use mt_crypto::Hash32;
use mt_names::{NameCommit, NameRenew, NameReveal, ServeError};
use mt_state::AccountId;
use std::collections::VecDeque;

/// Сколько окон узел держит обращение для отсутствующего владельца.
/// Одно окно: дольше — значит хранить чужое, а хранение у третьей стороны в модели отсутствует.
pub const REQUEST_HOLD_WINDOWS: u32 = 1;

/// Что узел собрал за окно и что из этого уйдёт в цепь.
#[derive(Default)]
pub struct NamesBatch {
    objects: Vec<Vec<u8>>,
}

impl NamesBatch {
    fn objects_push(&mut self, o: Vec<u8>) {
        self.objects.push(o);
    }
    pub fn push_commit(&mut self, c: &NameCommit) {
        self.objects.push(c.encode());
    }
    pub fn push_reveal(&mut self, r: &NameReveal) {
        self.objects.push(r.encode());
    }
    pub fn push_renew(&mut self, r: &NameRenew) {
        self.objects.push(r.encode());
    }
    pub fn len(&self) -> usize {
        self.objects.len()
    }
    pub fn is_empty(&self) -> bool {
        self.objects.is_empty()
    }
    /// Корень пачки. В цепь уходит только он и `app_id` — ни имени, ни ячейки, ни якоря.
    pub fn root(&self) -> [u8; 32] {
        mt_names::batch_root(&self.objects)
    }
    /// Якорь для цепи. Отправитель — САМ УЗЕЛ: клиент со своего аккаунта объекты слоя не якорит,
    /// иначе якорение выдавало бы, кто именно взял имя.
    pub fn anchor_op(&self, node_account: AccountId, prev_hash: Hash32) -> Option<Anchor> {
        if self.is_empty() {
            return None;
        }
        Some(Anchor {
            prev_hash,
            sender: node_account,
            app_id: mt_names::app_id(),
            data_hash: self.root(),
            // Подпись ставит вызывающий: ключ узла живёт не здесь. Пустая — метка «не подписано»,
            // и узел обязан подписать перед отправкой; неподписанный якорь цепь не примет.
            signature: mt_crypto::Signature::from_array([0u8; mt_crypto::SIGNATURE_SIZE]),
        })
    }
    pub fn take(&mut self) -> Vec<Vec<u8>> {
        std::mem::take(&mut self.objects)
    }
}

/// Обращение, ждущее владельца.
pub struct HeldRequest {
    pub slot: [u8; 32],
    pub sealed: Vec<u8>,
    pub window: u32,
}

/// Слой имён на узле. Создаётся выключенным; включается явным решением.
pub struct NamesService {
    enabled: bool,
    batch: NamesBatch,
    index: Vec<[u8; 32]>,
    held: VecDeque<HeldRequest>,
}

impl NamesService {
    /// Выключенная служба: узел ведёт себя ровно как до появления слоя.
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            batch: NamesBatch::default(),
            index: Vec::new(),
            held: VecDeque::new(),
        }
    }
    pub fn enabled() -> Self {
        Self {
            enabled: true,
            ..Self::disabled()
        }
    }
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    /// Индекс занятости строится сканом РАСКРЫТИЙ из цепи предложений, а не таблицы состояния:
    /// он производный и авторитетом не является.
    pub fn rebuild_index(&mut self, reveals: &[NameReveal]) {
        if !self.enabled {
            return;
        }
        self.index = mt_names::occupancy_index(reveals);
    }
    pub fn occupied(&self) -> u64 {
        self.index.len() as u64
    }

    /// Отдать корзину целиком. Запрос одной ячейки отвергается — узел не должен узнавать,
    /// кем интересуется спрашивающий.
    pub fn serve(
        &self,
        wanted_bucket: u64,
        single_slot: bool,
    ) -> Result<Vec<[u8; 32]>, ServeError> {
        if single_slot {
            return Err(ServeError::SingleSlotRequested);
        }
        Ok(mt_names::serve_bucket(
            &self.index,
            wanted_bucket,
            self.occupied(),
        ))
    }

    /// Принять обращение к владельцу: задача проверяется одним хешем, и только потом обращение
    /// кладётся в очередь. Владельца нет на связи — обращение ждёт РОВНО одно окно.
    pub fn accept(
        &mut self,
        slot: [u8; 32],
        eph_pk: &[u8],
        nonce: &[u8],
        sealed: Vec<u8>,
        window: u32,
    ) -> Result<(), ServeError> {
        if !self.enabled {
            return Ok(()); // выключено — молча ничего не делаем, поведение узла прежнее
        }
        mt_names::accept_request(&slot, eph_pk, nonce, false)?;
        self.held.push_back(HeldRequest {
            slot,
            sealed,
            window,
        });
        Ok(())
    }

    /// Забрать обращения владельцу и выбросить просроченные. Хранение чужого не накапливается.
    pub fn drain_for(&mut self, slot: &[u8; 32], now: u32) -> Vec<Vec<u8>> {
        self.held
            .retain(|r| now.saturating_sub(r.window) <= REQUEST_HOLD_WINDOWS);
        let mut out = Vec::new();
        let mut keep = VecDeque::new();
        while let Some(r) = self.held.pop_front() {
            if r.slot == *slot {
                out.push(r.sealed);
            } else {
                keep.push_back(r);
            }
        }
        self.held = keep;
        out
    }
    pub fn held_count(&self) -> usize {
        self.held.len()
    }

    /// Приём объекта слоя от клиента: он копится до конца окна и уходит в цепь ОДНОЙ пачкой.
    /// Пачка вместо отдельных якорей — не экономия, а укрытие: по одному якорю на объект было бы
    /// видно, сколько имён берут прямо сейчас.
    pub fn intake(&mut self, object: Vec<u8>) {
        if !self.enabled {
            return;
        }
        self.batch.objects_push(object);
    }
    pub fn batch_len(&self) -> usize {
        self.batch.len()
    }

    /// Собрать якорь окна и очистить пачку. Возвращает НЕподписанный якорь: подпись ставит
    /// вызывающий ключом узла — ключ живёт в identity, а не в этом модуле.
    pub fn take_anchor(&mut self, node_account: AccountId, prev_hash: Hash32) -> Option<Anchor> {
        if !self.enabled || self.batch.is_empty() {
            return None;
        }
        let a = self.batch.anchor_op(node_account, prev_hash);
        self.batch = NamesBatch::default();
        a
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reveal(name: &str) -> NameReveal {
        NameReveal {
            slot: mt_names::slot(name),
            anchor: [0; 32],
            nonce: [0; 32],
            commit_win: 1,
        }
    }

    /// Выключенная служба не делает НИЧЕГО: узел ведёт себя как до появления слоя.
    #[test]
    fn disabled_service_is_inert() {
        let mut s = NamesService::disabled();
        s.rebuild_index(&[reveal("alicemontana")]);
        assert_eq!(s.occupied(), 0, "выключенная служба индекс не строит");
        assert_eq!(s.accept([0; 32], &[], &[], vec![1, 2, 3], 1), Ok(()));
        assert_eq!(s.held_count(), 0, "выключенная служба ничего не держит");
    }

    /// Пустая пачка не якорится: пустой якорь был бы сообщением «слой жив», то есть шумом в цепи.
    #[test]
    fn empty_batch_is_not_anchored() {
        let b = NamesBatch::default();
        assert!(b.anchor_op([1; 32], [0; 32]).is_none());
    }

    /// В цепь уходит app_id слоя и корень пачки — и ничего больше.
    #[test]
    fn anchor_carries_only_app_id_and_root() {
        let mut b = NamesBatch::default();
        b.push_commit(&NameCommit { commit: [7; 32] });
        let a = b.anchor_op([1; 32], [2; 32]).expect("пачка непуста");
        assert_eq!(a.app_id, mt_names::app_id());
        assert_eq!(a.data_hash, b.root());
        assert_eq!(a.sender, [1; 32], "отправитель — узел, не клиент");
    }

    #[test]
    fn index_and_bucket_serving() {
        let mut s = NamesService::enabled();
        let names: Vec<String> = (0..600).map(|i| format!("user{i:05}")).collect();
        let reveals: Vec<NameReveal> = names.iter().map(|n| reveal(n)).collect();
        s.rebuild_index(&reveals);
        assert_eq!(s.occupied(), 600);
        let target = mt_names::slot(&names[0]);
        let b = mt_names::bucket(&target, s.occupied());
        let served = s.serve(b, false).expect("корзина отдаётся");
        assert!(served.contains(&target));
        assert!(
            served.len() > 1,
            "в корзине больше одной ячейки — иначе укрытия нет"
        );
        assert_eq!(s.serve(b, true), Err(ServeError::SingleSlotRequested));
    }

    /// Обращение ждёт ровно одно окно: хранение чужого не накапливается.
    #[test]
    fn request_is_held_for_one_window_only() {
        let mut s = NamesService::enabled();
        let sl = mt_names::slot("anna");
        let eph = vec![0x5A; 1184];
        let nonce = 810_487u64.to_le_bytes();
        assert_eq!(s.accept(sl, &eph, &nonce, vec![9, 9], 100), Ok(()));
        assert_eq!(s.held_count(), 1);
        assert!(s.drain_for(&sl, 102).is_empty(), "просроченное выброшено");
        assert_eq!(s.held_count(), 0);

        assert_eq!(s.accept(sl, &eph, &nonce, vec![9, 9], 100), Ok(()));
        assert_eq!(s.drain_for(&sl, 101).len(), 1, "в срок — отдано");
    }

    /// Нерешённая задача отвергается до всякой очереди.
    #[test]
    fn unsolved_puzzle_never_enters_the_queue() {
        let mut s = NamesService::enabled();
        let sl = mt_names::slot("anna");
        assert_eq!(
            s.accept(sl, &[0x5A; 1184], &[0; 8], vec![1], 1),
            Err(ServeError::PuzzleUnsolved)
        );
        assert_eq!(s.held_count(), 0);
    }

    /// Чужое обращение не отдаётся: слот сверяется.
    #[test]
    fn other_slot_is_not_handed_over() {
        let mut s = NamesService::enabled();
        let mine = mt_names::slot("anna");
        let other = mt_names::slot("bobbbb");
        let eph = vec![0x5A; 1184];
        let nonce = 810_487u64.to_le_bytes();
        let _ = s.accept(mine, &eph, &nonce, vec![1], 5);
        assert!(s.drain_for(&other, 5).is_empty());
        assert_eq!(s.held_count(), 1, "чужое осталось лежать своему владельцу");
    }
}

#[cfg(test)]
mod publish_tests {
    use super::*;

    /// Выключенная служба ничего не принимает и якоря не даёт — цепь не меняется ни на байт.
    #[test]
    fn disabled_publishes_nothing() {
        let mut s = NamesService::disabled();
        s.intake(vec![1, 2, 3]);
        assert_eq!(s.batch_len(), 0);
        assert!(s.take_anchor([1; 32], [0; 32]).is_none());
    }

    /// Включённая: объекты копятся и уходят ОДНОЙ пачкой, после чего пачка пуста.
    #[test]
    fn enabled_publishes_one_anchor_per_window() {
        let mut s = NamesService::enabled();
        s.intake(NameCommit { commit: [1; 32] }.encode());
        s.intake(NameCommit { commit: [2; 32] }.encode());
        assert_eq!(s.batch_len(), 2);
        let a = s.take_anchor([9; 32], [7; 32]).expect("пачка непуста");
        assert_eq!(a.app_id, mt_names::app_id());
        assert_eq!(a.sender, [9; 32]);
        assert_eq!(s.batch_len(), 0, "пачка ушла целиком");
        assert!(
            s.take_anchor([9; 32], [7; 32]).is_none(),
            "пустое окно якоря не даёт"
        );
    }

    /// Число объектов в окне по якорю не видно: два разных набора дают якорь одного размера.
    #[test]
    fn anchor_size_hides_the_count() {
        let mut a = NamesService::enabled();
        a.intake(NameCommit { commit: [1; 32] }.encode());
        let one = a.take_anchor([9; 32], [7; 32]).unwrap();
        let mut b = NamesService::enabled();
        for i in 0..50u8 {
            b.intake(NameCommit { commit: [i; 32] }.encode());
        }
        let fifty = b.take_anchor([9; 32], [7; 32]).unwrap();
        assert_eq!(one.data_hash.len(), fifty.data_hash.len());
        assert_ne!(one.data_hash, fifty.data_hash);
    }
}
