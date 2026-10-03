//! Плоскость пользовательских операций узла — Этап 1: приём и локальная проверка.
//!
//! **Состояние сети этот модуль НЕ меняет.** Он только принимает операции, проверяет их по
//! действующим правилам (`mt_account::validate`) и держит в памяти до тех пор, пока их не
//! возьмут в подтверждение окна. Пока приёмник выключен — а по умолчанию он выключен, — узел
//! ведёт себя ровно как прежде: `op_hashes` в подтверждении остаётся пустым, корень состояния
//! считается тем же путём.
//!
//! Почему приём отделён от применения. Применить операцию значит изменить корень состояния;
//! узел, применивший то, чего не применили остальные, вылетает из кворума. Приём же ничего не
//! меняет и потому безопасен сам по себе — его можно включить и наблюдать, не рискуя сетью.

use mt_account::{op_hash, validate, OpError, Operation, ValidationContext};
use mt_crypto::Hash32;
use mt_state::AccountTable;
use std::collections::BTreeMap;

/// Потолок очереди приёма. Без него узел рос бы в памяти от чужого потока — это тот же
/// slow-bloat, только в оперативной памяти вместо состояния.
pub const MEMPOOL_MAX: usize = 4096;

/// Почему операция не принята.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum IntakeError {
    Disabled,
    Full,
    Duplicate,
    Invalid(OpError),
}

/// Очередь приёма. Порядок хранения — по `op_hash` лексикографически: это канонический порядок
/// применения (spec, «settle (apply at window close)»), и держать его сразу дешевле, чем
/// сортировать в момент окна.
pub struct OpMempool {
    enabled: bool,
    pending: BTreeMap<Hash32, Operation>,
}

impl OpMempool {
    /// Выключенный приёмник: узел ведёт себя как до появления плоскости операций.
    pub fn disabled() -> Self {
        Self {
            enabled: false,
            pending: BTreeMap::new(),
        }
    }
    pub fn enabled() -> Self {
        Self {
            enabled: true,
            pending: BTreeMap::new(),
        }
    }
    pub fn is_enabled(&self) -> bool {
        self.enabled
    }
    pub fn len(&self) -> usize {
        self.pending.len()
    }
    pub fn is_empty(&self) -> bool {
        self.pending.is_empty()
    }

    /// Принять операцию. Проверка — те же правила, что и при применении: узел не берёт в
    /// подтверждение то, что сам считает недействительным.
    pub fn submit(
        &mut self,
        op: Operation,
        state: &AccountTable,
        ctx: &ValidationContext,
    ) -> Result<Hash32, IntakeError> {
        if !self.enabled {
            return Err(IntakeError::Disabled);
        }
        if self.pending.len() >= MEMPOOL_MAX {
            return Err(IntakeError::Full);
        }
        validate(&op, state, ctx).map_err(IntakeError::Invalid)?;
        let h = op_hash(&op);
        if self.pending.contains_key(&h) {
            return Err(IntakeError::Duplicate);
        }
        self.pending.insert(h, op);
        Ok(h)
    }

    /// Что узел готов подтвердить в этом окне: первые `limit` хешей в каноническом порядке.
    /// Порядок канонический, а не «как пришло»: иначе два честных узла подтвердили бы разное
    /// при одинаковом наборе, и кворум распался бы на ровном месте.
    pub fn attest(&self, limit: usize) -> Vec<Hash32> {
        self.pending.keys().copied().take(limit).collect()
    }

    /// Забрать операции, закреплённые кворумом, в каноническом порядке применения.
    /// Незакреплённые остаются ждать следующего окна — терять их нельзя.
    pub fn take_cemented(&mut self, cemented: &[Hash32]) -> Vec<Operation> {
        let mut out = Vec::new();
        let mut ordered: Vec<Hash32> = cemented.to_vec();
        ordered.sort_unstable();
        ordered.dedup();
        for h in ordered {
            if let Some(op) = self.pending.remove(&h) {
                out.push(op);
            }
        }
        out
    }

    /// Выбросить то, что перестало быть действительным (например, отправитель успел сдвинуть
    /// свою цепочку другой операцией). Иначе очередь копила бы мёртвое.
    pub fn prune_invalid(&mut self, state: &AccountTable, ctx: &ValidationContext) {
        if !self.enabled {
            return;
        }
        self.pending
            .retain(|_, op| validate(op, state, ctx).is_ok());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_account::Anchor;
    use mt_crypto::{Signature, SIGNATURE_SIZE};

    fn ctx() -> ValidationContext {
        ValidationContext {
            current_window: 10,
            tau2_windows: 20_160,
        }
    }

    fn anchor(data: u8) -> Operation {
        Operation::Anchor(Anchor {
            prev_hash: [0x44; 32],
            sender: [0xAA; 32],
            app_id: [0x88; 32],
            data_hash: [data; 32],
            signature: Signature::from_array([0u8; SIGNATURE_SIZE]),
        })
    }

    /// Выключенный приёмник не принимает ничего: поведение узла прежнее.
    #[test]
    fn disabled_takes_nothing() {
        let mut m = OpMempool::disabled();
        let st = AccountTable::new();
        assert_eq!(m.submit(anchor(1), &st, &ctx()), Err(IntakeError::Disabled));
        assert!(m.is_empty());
        assert!(m.attest(10).is_empty());
    }

    /// Недействительная операция не попадает в очередь: узел не подтверждает то, что сам
    /// считает негодным. Здесь отправителя нет в таблице — это и есть отказ.
    #[test]
    fn invalid_operation_is_refused() {
        let mut m = OpMempool::enabled();
        let st = AccountTable::new();
        assert_eq!(
            m.submit(anchor(1), &st, &ctx()),
            Err(IntakeError::Invalid(OpError::AccountNotFound))
        );
        assert!(m.is_empty(), "негодное в очередь не попало");
    }

    /// Порядок подтверждения канонический: два узла с одним набором подтвердят одно и то же.
    #[test]
    fn attestation_order_is_canonical() {
        let mut a = OpMempool::enabled();
        let mut b = OpMempool::enabled();
        let ops = [anchor(3), anchor(1), anchor(2)];
        // порядок поступления РАЗНЫЙ
        for op in [&ops[0], &ops[1], &ops[2]] {
            a.pending.insert(op_hash(op), op.clone());
        }
        for op in [&ops[2], &ops[0], &ops[1]] {
            b.pending.insert(op_hash(op), op.clone());
        }
        assert_eq!(
            a.attest(10),
            b.attest(10),
            "подтверждение не зависит от порядка прихода"
        );
        let mut sorted = a.attest(10);
        sorted.sort_unstable();
        assert_eq!(a.attest(10), sorted, "порядок лексикографический");
    }

    /// Закреплённые уходят, незакреплённые остаются ждать: терять операцию нельзя.
    #[test]
    fn cemented_leave_others_stay() {
        let mut m = OpMempool::enabled();
        let ops = [anchor(1), anchor(2), anchor(3)];
        for op in &ops {
            m.pending.insert(op_hash(op), op.clone());
        }
        let taken = m.take_cemented(&[op_hash(&ops[0]), op_hash(&ops[2])]);
        assert_eq!(taken.len(), 2);
        assert_eq!(m.len(), 1, "незакреплённая осталась ждать следующего окна");
    }

    /// Взятое отдаётся в каноническом порядке, независимо от порядка в списке закреплённых.
    #[test]
    fn cemented_are_returned_in_canonical_order() {
        let mut m = OpMempool::enabled();
        let ops = [anchor(1), anchor(2), anchor(3)];
        for op in &ops {
            m.pending.insert(op_hash(op), op.clone());
        }
        let mut hashes: Vec<Hash32> = ops.iter().map(op_hash).collect();
        hashes.reverse();
        let taken = m.take_cemented(&hashes);
        let got: Vec<Hash32> = taken.iter().map(op_hash).collect();
        let mut want = got.clone();
        want.sort_unstable();
        assert_eq!(got, want);
    }

    /// Потолок очереди держит: чужой поток не растит узел в памяти без границы.
    #[test]
    fn mempool_has_a_ceiling() {
        let mut m = OpMempool::enabled();
        for i in 0..MEMPOOL_MAX {
            let op = anchor((i % 251) as u8);
            let mut o = op;
            if let Operation::Anchor(ref mut a) = o {
                a.prev_hash[0] = (i % 256) as u8;
                a.prev_hash[1] = (i / 256) as u8;
            }
            m.pending.insert(op_hash(&o), o);
        }
        assert_eq!(m.len(), MEMPOOL_MAX);
        let st = AccountTable::new();
        assert_eq!(m.submit(anchor(9), &st, &ctx()), Err(IntakeError::Full));
    }
}

/// Какие операции закреплены кворумом в окне.
///
/// Операция закреплена, если её `op_hash` встречается в подтверждениях узлов, суммарный вес
/// которых достиг `need`. Вес узла — длина его цепочки, та же величина, что и в кворуме окна:
/// второй меры веса в протоколе не существует, и заводить её здесь нельзя.
///
/// Порядок результата канонический (лексикографический по `op_hash`) — тот же, в котором
/// операции применяются при закрытии окна.
pub fn cemented_op_hashes(confirmations: &[(Hash32, u64, Vec<Hash32>)], need: u64) -> Vec<Hash32> {
    let mut weight: BTreeMap<Hash32, u64> = BTreeMap::new();
    let mut counted: BTreeMap<Hash32, Vec<Hash32>> = BTreeMap::new();
    for (node, node_weight, hashes) in confirmations {
        for h in hashes {
            // Один узел учитывается за операцию ОДИН раз, сколько бы раз он её ни назвал:
            // иначе повтор в собственном подтверждении давал бы вес из воздуха.
            let seen = counted.entry(*h).or_default();
            if seen.contains(node) {
                continue;
            }
            seen.push(*node);
            *weight.entry(*h).or_insert(0) += *node_weight;
        }
    }
    weight
        .into_iter()
        .filter(|(_, w)| *w >= need)
        .map(|(h, _)| h)
        .collect()
}

#[cfg(test)]
mod cementing_tests {
    use super::*;

    fn h(b: u8) -> Hash32 {
        [b; 32]
    }

    /// Операция закреплена, когда вес подтвердивших достиг порога, и не раньше.
    #[test]
    fn quorum_by_weight_not_by_count() {
        let conf = vec![
            (h(1), 30u64, vec![h(0xAA)]),
            (h(2), 20u64, vec![h(0xAA)]),
            (h(3), 10u64, vec![h(0xBB)]),
        ];
        assert_eq!(cemented_op_hashes(&conf, 50), vec![h(0xAA)]);
        assert_eq!(cemented_op_hashes(&conf, 51), Vec::<Hash32>::new());
        assert_eq!(cemented_op_hashes(&conf, 10), vec![h(0xAA), h(0xBB)]);
    }

    /// Повтор в собственном подтверждении веса не добавляет.
    #[test]
    fn repeat_in_one_confirmation_adds_nothing() {
        let conf = vec![(h(1), 40u64, vec![h(0xAA), h(0xAA), h(0xAA)])];
        assert_eq!(cemented_op_hashes(&conf, 41), Vec::<Hash32>::new());
        assert_eq!(cemented_op_hashes(&conf, 40), vec![h(0xAA)]);
    }

    /// Результат канонически упорядочен: у всех узлов один и тот же список.
    #[test]
    fn result_is_canonically_ordered() {
        let conf = vec![(h(1), 100u64, vec![h(0xCC), h(0xAA), h(0xBB)])];
        assert_eq!(
            cemented_op_hashes(&conf, 1),
            vec![h(0xAA), h(0xBB), h(0xCC)]
        );
    }

    /// Пустой набор подтверждений закрепляет пустоту — и это не ошибка, а обычное тихое окно.
    #[test]
    fn empty_confirmations_cement_nothing() {
        assert_eq!(cemented_op_hashes(&[], 1), Vec::<Hash32>::new());
    }
}
