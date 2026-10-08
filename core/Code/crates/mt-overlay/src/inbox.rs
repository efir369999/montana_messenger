//! Padding buckets (Stage 2). The mailbox addressing (epoch_tag) is replaced by Montana Unlinkable
//! Queues — see muq.rs / queue_host.rs. Only padding remains here (reused by MUQ).

// spec: padding buckets {256, 1024, 4096, 16384, 65536, 262144, 1048576} (powers of two, ×4).
pub const PADDING_BUCKETS: [usize; 7] = [256, 1024, 4096, 16384, 65536, 262144, 1_048_576];

/// The smallest bucket ≥ n. None if n exceeds the top bucket (1 MiB = MAX_PLAINTEXT).
pub fn bucket_len(n: usize) -> Option<usize> {
    PADDING_BUCKETS.iter().copied().find(|&b| b >= n)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bucket_len_rounds_up_power_of_four() {
        assert_eq!(bucket_len(0), Some(256));
        assert_eq!(bucket_len(256), Some(256));
        assert_eq!(bucket_len(257), Some(1024));
        assert_eq!(bucket_len(1_048_576), Some(1_048_576));
        assert_eq!(bucket_len(1_048_577), None);
    }
}
