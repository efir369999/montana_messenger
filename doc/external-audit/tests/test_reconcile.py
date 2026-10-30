from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reconcile import collect, report, statements

AIR = '5a' * 32
FRAME = '0f' * 32
WINDOW = '1e' * 32
GENESIS = '7c' * 32
PARAMETERS = 'e5' * 32
BYTES = ', '.join('0x' + AIR[i:i + 2] for i in range(0, 64, 2)).split(', ')


def canon(version='9.5.0', genesis=GENESIS):
    return f"""# Montana — Canon

**Version:** {version}

```
air_hash = the hash, under the domain of a description's identifier, of the identifiers of the
           descriptions the network accepts proofs under

identifier of the frame     = {FRAME}
identifier of the window    = {WINDOW}
```

| `air_hash` — the constraint sets the proofs of this network are accepted under | {AIR} |

```
genesis_state_hash = SHA-256("mt-genesis-state" || 0x00 || parameters
                             || note_root || operations_root)

                   = {genesis}

published_parameters = SHA-256("mt-genesis-state" || 0x00 || the parameters that are published,
                               in the order and the encoding above)
                     = {PARAMETERS}
```
"""


DECREE = f"""pub const DECREE: &[Entry] = &[
    Entry::Scalar("k_max", 8),
    Entry::Hash(
        "air_hash",
        [
            {', '.join(BYTES[:14])},
            {', '.join(BYTES[14:28])},
            {', '.join(BYTES[28:])},
        ],
    ),
];
"""

VERSION = '| What | Where it lives | Value |\n|---|---|---|\n| Canon, the set this tree reproduces | the header | 9.5.0 |\n'

FIXTURE = {
    'core/docs/Montana Canon.md': canon(),
    'core/Montana-Core/crates/mt-genesis/src/lib.rs': DECREE,
    'core/Montana-Core/VERSION.md': VERSION,
    'Audit/Protocol-13/source/docs/Montana Canon.md': canon(),
    'Audit/Protocol-13/source/Montana-Core/crates/mt-genesis/src/lib.rs': DECREE,
    'Audit/Protocol-13/source/Montana-Core/VERSION.md': VERSION,
    'Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md':
        f'Historical closure prose is not current end-to-end proof.\n\n'
        f'The current candidate Genesis is\n`{GENESIS}`.\n',
    'README.md': 'The core reproduces Canon 9.5.0.\n',
}
# Canon: version, two identifiers, air_hash, Genesis, digest; code: air_hash, VERSION.md: version.
STATED = 2 * (6 + 1 + 1) + 1 + 1


def flip(text, line, value):
    """The text with one digit of the value on that line changed."""
    lines = text.split('\n')
    row = lines[line - 1]
    at = row.index(value) if value in row else row.index('0x' + value[:2]) + 2
    lines[line - 1] = row[:at] + ('1' if row[at] == '0' else '0') + row[at + 1:]
    return '\n'.join(lines)


class ReconcileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Audit fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')
        self.git('config', 'core.hooksPath', '/dev/null')
        for path, text in FIXTURE.items():
            self.write(path, text)
        self.commit()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE).decode().strip()

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self):
        self.git('add', '.')
        self.git('commit', '-qm', 'synthetic reconcile fixture', '--allow-empty')

    def test_agreement_exits_zero(self):
        # Rejects a reader that splits one value into two, such as a byte array against its hex,
        # or that binds the prose after `air_hash =` to the identifier of the frame below it.
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 0, '\n'.join(out))
        self.assertEqual(len(collect(self.root, 'HEAD')[1]), STATED)

    def test_one_flipped_digit_anywhere_fails_and_names_its_place(self):
        # Rejects a reader that skips any place a value is stated, or names the wrong line of it.
        found = collect(self.root, 'HEAD')[1]
        self.assertEqual(len(found), STATED)
        for key, value, path, line, _ in found:
            with self.subTest(place=f'{path}:{line}'):
                self.write(path, flip(FIXTURE[path], line, value))
                self.commit()
                code, out = report(self.root, 'HEAD')
                self.write(path, FIXTURE[path])
                self.commit()
                self.assertEqual(code, 1)
                self.assertTrue(any(row.startswith(f'DISAGREE {key}:') for row in out), '\n'.join(out))
                stated = [row for row in out if row.startswith('  ')
                          and f'{path}:{line}' in row.split(' at ', 1)[1].split(', ')]
                self.assertEqual(len(stated), 1, '\n'.join(out))
                self.assertNotIn(value, stated[0])

    def test_conflicting_values_on_one_line_both_orders_are_retained(self):
        # Rejects last-match-wins: a later correct assertion cannot erase an earlier conflict.
        wrong = 'ee' * 32
        for first, second in [(wrong, GENESIS), (GENESIS, wrong)]:
            with self.subTest(first=first):
                self.write('README.md', f'Canon 9.5.0.\ngenesis_state_hash = {first}; '
                           f'genesis_state_hash = {second}\n')
                self.commit()
                code, out = report(self.root, 'HEAD')
                self.assertEqual(code, 1, '\n'.join(out))
                values = {s[1] for s in collect(self.root, 'HEAD')[1]
                          if s[2:] == ('README.md', 2, False)}
                self.assertEqual(values, {wrong, GENESIS})
                self.assertTrue(any(row.startswith(f'  {wrong} at ') and 'README.md:2' in row
                                    for row in out), '\n'.join(out))

    def test_same_line_equal_claims_do_not_create_a_disagreement(self):
        # Rejects treating the number of assertions as the number of distinct values.
        self.write('README.md', f'Canon 9.5.0.\ngenesis_state_hash = {GENESIS}; '
                   f'genesis_state_hash = {GENESIS}\n')
        self.commit()
        self.assertEqual(report(self.root, 'HEAD')[0], 0)

    def test_historical_mark_on_the_line_removes_the_value(self):
        # Rejects a reader that compares a value its own document marks as historical.
        self.write('Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md',
                   FIXTURE['Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md']
                   + f'The historical Genesis of Canon 5.0.1 is `{"ee" * 32}`.\n')
        self.commit()
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 0, '\n'.join(out))
        self.assertIn(f'genesis_state_hash | {"ee" * 32} | Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md:5 | historical', out)

    def test_historical_word_elsewhere_in_the_document_does_not_remove_a_value(self):
        # Rejects a reader that exempts every value of a document mentioning history anywhere,
        # as item 12 itself does two lines above its own current Genesis.
        self.write('Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md',
                   FIXTURE['Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md'].replace(GENESIS, 'ee' * 32))
        self.commit()
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 1)
        self.assertIn(f'  {"ee" * 32} at Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md:4', out)

    def test_three_genesis_values_are_all_named(self):
        # Rejects a report that stops at the first pair of differing values.
        self.write('core/docs/Montana Canon.md', canon(genesis='0e' * 32))
        self.write('Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md',
                   FIXTURE['Audit/Protocol-13/12-SOURCE-AND-CLAIMS.md'].replace(GENESIS, 'ee' * 32))
        self.commit()
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 1)
        self.assertIn('DISAGREE genesis_state_hash: 3 current values', out)

    def test_an_unstated_quantity_fails(self):
        # Rejects a reader that passes because it found nothing to compare.
        for path, text in FIXTURE.items():
            self.write(path, text.replace(GENESIS, 'none'))
        self.commit()
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 1)
        self.assertIn('MISSING genesis_state_hash: no document states a current value', out)

    def test_working_tree_edits_are_not_read(self):
        # Rejects a reader of the checkout rather than of the committed revision.
        self.write('core/docs/Montana Canon.md', canon(version='9.6.0'))
        self.assertEqual(report(self.root, 'HEAD')[0], 0)

    def test_values_outside_the_compared_documents_are_ignored(self):
        # Rejects a reader that treats a dated log, such as AUDIT.md, as a current statement.
        self.write('core/Montana-Core/AUDIT.md', 'Canon 5.0.1 / Core 0.21.1 carries the revised AIR.\n')
        self.commit()
        self.assertEqual(report(self.root, 'HEAD')[0], 0)

    def test_command_line_exit_codes(self):
        # Rejects a command line that prints a disagreement and still exits 0.
        script = Path(__file__).resolve().parents[1] / 'reconcile.py'
        run = [sys.executable, '-B', str(script), '--repo', str(self.root), '--revision', 'HEAD']
        self.assertEqual(subprocess.run(run, capture_output=True).returncode, 0)
        self.write('README.md', 'The core reproduces Canon 9.4.0.\n')
        self.commit()
        result = subprocess.run(run, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('9.4.0 at README.md:1', result.stdout)
        self.assertEqual(subprocess.run(run[:-1] + ['does-not-exist'], capture_output=True).returncode, 2)

    def test_uppercase_hex_conflict_cannot_disappear(self):
        # Rejects skipping a valid hex spelling while other documents still agree.
        self.write('README.md', f'Canon 9.5.0.\ngenesis_state_hash = {"EE" * 32}\n')
        self.commit()
        code, out = report(self.root, 'HEAD')
        self.assertEqual(code, 1, '\n'.join(out))
        self.assertTrue(any(row.startswith(f'  {"ee" * 32} at ') and 'README.md:2' in row
                            for row in out), '\n'.join(out))

    def test_hex_case_is_normalized_for_every_text_quantity(self):
        # Rejects both dropped uppercase values and false disagreements over case alone.
        for label, key, value in [
            ('air_hash', 'air_hash', AIR),
            ('published_parameters', 'published_parameters', PARAMETERS),
            ('genesis_state_hash', 'genesis_state_hash', GENESIS),
            ('identifier of the frame', 'air identifier of the frame', FRAME),
        ]:
            for spelling in [value.upper(), ''.join(c.upper() if (i // 2) % 2 else c
                                                    for i, c in enumerate(value))]:
                with self.subTest(label=label, spelling=spelling):
                    text = f'{label} = {spelling}\n'
                    found = statements('README.md', text, {'any', 'prose'})
                    self.assertEqual([(row[0], row[1]) for row in found], [(key, value)])
                    self.write('README.md', 'Canon 9.5.0.\n' + text)
                    self.commit()
                    self.assertEqual(report(self.root, 'HEAD')[0], 0)

    def test_byte_array_reads_as_its_hex(self):
        # Rejects a code reader that keeps the 0x prefixes or the case of the bytes.
        found = statements('x.rs', DECREE.replace('0x5a', '0x5A'), {'any', 'rs'})
        self.assertEqual([(s[0], s[1], s[3]) for s in found], [('air_hash', AIR, 6)])


if __name__ == '__main__':
    unittest.main()
