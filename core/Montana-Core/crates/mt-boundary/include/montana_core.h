/* The boundary a client stands on: the birth of a person, the wallet, the machine, its pulse and
 * the mint of a window. Every door answers zero when the work was done and a negative number when
 * it refused; the reason of a refusal is read by `mtc_last_said` in the words the crate that
 * refused used.
 *
 *   0  the work was done
 *  -1  refused, and the reason stands in `mtc_last_said`
 *  -2  a pointer that is nothing was handed where a value was asked for
 *  -3  a buffer smaller than what it must hold; the length written says how much is needed
 *  -4  a door broke rather than answering
 *
 * A buffer of bytes is written at the width stated beside it and never at another; a buffer of
 * text is written with the byte that ends it, and the length written excludes that byte.
 *
 * One device is one machine and one person: the doors take no handle, and a second opening is
 * refused rather than shadowing the first.
 */
#ifndef MONTANA_CORE_H
#define MONTANA_CORE_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The reason the last door refused. */
int32_t mtc_last_said(char *out, size_t cap, size_t *len);

/* Which network this core is of: thirty-two bytes. */
int32_t mtc_genesis_state_hash(uint8_t *out);

/* The draw of this device, tested rather than trusted. */
int32_t mtc_self_test(void);

/* How many sources of entropy are alive on this device. */
int32_t mtc_sources_alive(size_t *out);

/* The device: the machine at its directory answering at its address, and the wallet beside it.
 * `born` is written one when this call drew the machine's secret and zero when it read one that
 * already stood. */
int32_t mtc_device_open(const char *dir, const char *listen, int32_t *born);
int32_t mtc_device_standing(int32_t *out);

/* The person. The words come back once and the caller wipes them. */
int32_t mtc_person_bear(char *out, size_t cap, size_t *len);
int32_t mtc_person_recall(const char *words);
int32_t mtc_person_stands(int32_t *out);

/* What a payer needs of this person: two values of thirty-two bytes, neither of them a name. */
int32_t mtc_person_payee(uint8_t *half, uint8_t *note_pk);

/* What this wallet holds: the sum as sixteen bytes, least significant first, and the count of the
 * notes behind it. */
int32_t mtc_wallet_balance(uint8_t *out);
int32_t mtc_wallet_notes(size_t *out);

/* The machine. The line an operator hands over carries the key this machine answers with, so
 * it is thousands of bytes rather than tens: a buffer too small is answered with the width it
 * must hold and the line is asked for again. */
int32_t mtc_machine_acquaintance(char *out, size_t cap, size_t *len);
int32_t mtc_machine_naming_half(uint8_t *out);
int32_t mtc_machine_reach(const char *line);
int32_t mtc_machine_answer(void);
int32_t mtc_machine_head(uint64_t *window, int32_t *present);
int32_t mtc_machine_links(size_t *held, size_t *ceiling, size_t *reached);
int32_t mtc_machine_account(char *out, size_t cap, size_t *len);

/* What the machine does of its own inside the window it lives, asked before the pulse begins. */
int32_t mtc_errand_redeem(uint64_t of_the_window, size_t living);
int32_t mtc_errand_pay(const uint8_t *half, const uint8_t *note_pk, const uint8_t *amount);

/* The pulse: the cohort as the naming halves laid one after another, thirty-two bytes each. */
int32_t mtc_pulse_begin(const uint8_t *halves, size_t count, uint64_t from, uint64_t windows);
int32_t mtc_pulse_running(int32_t *out);
int32_t mtc_pulse_lived(size_t *out);
int32_t mtc_pulse_lived_at(size_t at, uint64_t *window, uint32_t *rounds, size_t *living,
                           uint64_t *share, uint64_t *accepted_in);

/* What the last payment left for its payee: the value as sixteen bytes, the blinding factor and
 * the key the note is paid to as thirty-two each, and the place the note took. */
int32_t mtc_paid_last(uint8_t *value, uint8_t *rcm, uint8_t *note_pk, uint64_t *position,
                      int32_t *present);

/* The note a payee was paid, entered into their own wallet. */
int32_t mtc_wallet_enter(const uint8_t *value, const uint8_t *rcm, const uint8_t *note_pk,
                         uint64_t position);

/* What proving costs on this device, measured on the frame that turns the right of a window into a
 * note. It publishes nothing and enters nothing. */
int32_t mtc_measure_redemption(uint64_t *milliseconds, size_t *width);

#ifdef __cplusplus
}
#endif

#endif /* MONTANA_CORE_H */
