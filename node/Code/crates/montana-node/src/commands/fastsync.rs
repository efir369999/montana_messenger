use mt_net::{FastSyncResponseChunk, TableId};
use mt_sync::{FastSyncChunk, FastSyncTableId};

#[derive(Debug, Eq, PartialEq)]
pub enum WireChunkError {
    RecordCountZero,
    EmptyRecords,
    RecordsIndivisible { len: usize, count: usize },
}

// Преобразование сетевого чанка fast-sync в чанк mt-sync: разбивает плоскую
// конкатенацию records на record_count равных записей. Канонический размер
// записи на таблицу не дублируется здесь — Snapshot::add_record проверяет его
// сам (единый источник истины по размеру). Маппинг TableId тотальный; таблица
// Proposals доходит до клиента и отклоняется там (ProposalsNotImplementedYet).
pub fn wire_chunk_to_sync(wire: FastSyncResponseChunk) -> Result<FastSyncChunk, WireChunkError> {
    let table_id = match wire.table_id {
        TableId::Account => FastSyncTableId::Account,
        TableId::Node => FastSyncTableId::Node,
        TableId::Candidate => FastSyncTableId::Candidate,
        TableId::Proposals => FastSyncTableId::Proposals,
    };
    let count = wire.record_count as usize;
    if count == 0 {
        return Err(WireChunkError::RecordCountZero);
    }
    if wire.records.is_empty() {
        return Err(WireChunkError::EmptyRecords);
    }
    if wire.records.len() % count != 0 {
        return Err(WireChunkError::RecordsIndivisible {
            len: wire.records.len(),
            count,
        });
    }
    let rec_size = wire.records.len() / count;
    let records: Vec<Vec<u8>> = wire
        .records
        .chunks_exact(rec_size)
        .map(<[u8]>::to_vec)
        .collect();
    Ok(FastSyncChunk {
        chunk_index: wire.chunk_index,
        total_chunks: wire.total_chunks,
        table_id,
        anchor_window: wire.anchor_window,
        records,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use mt_codec::CanonicalEncode;
    use mt_crypto::PUBLIC_KEY_SIZE;
    use mt_state::{AccountRecord, ACCOUNT_RECORD_SIZE};

    fn acct(seed: u8) -> Vec<u8> {
        let rec = AccountRecord {
            account_id: [seed; 32],
            balance: 1000,
            suite_id: 1,
            is_node_operator: false,
            frontier_hash: [seed; 32],
            op_height: 0,
            account_chain_length: 0,
            account_chain_length_snapshot: 0,
            current_pubkey: [seed; PUBLIC_KEY_SIZE],
            creation_window: 0,
            last_op_window: 0,
            last_activation_window: 0,
        };
        let mut buf = Vec::with_capacity(ACCOUNT_RECORD_SIZE);
        rec.encode(&mut buf);
        buf
    }

    fn flat(records: &[Vec<u8>]) -> Vec<u8> {
        let mut f = Vec::new();
        for r in records {
            f.extend_from_slice(r);
        }
        f
    }

    #[test]
    fn splits_flat_records_preserving_bytes() {
        let recs = vec![acct(0x11), acct(0x22), acct(0x33)];
        let wire = FastSyncResponseChunk {
            chunk_index: 2,
            total_chunks: 5,
            table_id: TableId::Account,
            record_count: 3,
            anchor_window: 0,
            records: flat(&recs),
        };
        let out = wire_chunk_to_sync(wire).expect("convert");
        assert_eq!(out.chunk_index, 2);
        assert_eq!(out.total_chunks, 5);
        assert_eq!(out.table_id, FastSyncTableId::Account);
        assert_eq!(out.records, recs);
    }

    #[test]
    fn maps_every_table_id() {
        for (net, sync) in [
            (TableId::Account, FastSyncTableId::Account),
            (TableId::Node, FastSyncTableId::Node),
            (TableId::Candidate, FastSyncTableId::Candidate),
            (TableId::Proposals, FastSyncTableId::Proposals),
        ] {
            let wire = FastSyncResponseChunk {
                chunk_index: 0,
                total_chunks: 1,
                table_id: net,
                record_count: 1,
                anchor_window: 0,
                records: vec![0u8; 8],
            };
            assert_eq!(wire_chunk_to_sync(wire).unwrap().table_id, sync);
        }
    }

    #[test]
    fn rejects_zero_record_count() {
        let wire = FastSyncResponseChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: TableId::Account,
            record_count: 0,
            anchor_window: 0,
            records: vec![0u8; 10],
        };
        assert_eq!(
            wire_chunk_to_sync(wire),
            Err(WireChunkError::RecordCountZero)
        );
    }

    #[test]
    fn rejects_empty_records() {
        let wire = FastSyncResponseChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: TableId::Account,
            record_count: 2,
            anchor_window: 0,
            records: Vec::new(),
        };
        assert_eq!(wire_chunk_to_sync(wire), Err(WireChunkError::EmptyRecords));
    }

    #[test]
    fn rejects_indivisible_records() {
        let wire = FastSyncResponseChunk {
            chunk_index: 0,
            total_chunks: 1,
            table_id: TableId::Account,
            record_count: 3,
            anchor_window: 0,
            records: vec![0u8; 10],
        };
        assert_eq!(
            wire_chunk_to_sync(wire),
            Err(WireChunkError::RecordsIndivisible { len: 10, count: 3 })
        );
    }
}
