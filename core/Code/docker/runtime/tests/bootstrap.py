#!/usr/bin/env python3
"""Run the real entrypoint with isolated command fixtures and a controlling terminal.

No Docker, node build, network or real mnemonic is used. Artifacts are retained.
These tests reject recovery output in logs/argv, delayed permissions, a lost init
exit code, overwritten recovery output, and unsolicited reporting commands.
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import stat
import subprocess
import tempfile
import termios
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "node-entrypoint.sh"
MARKER = "TEST_RECOVERY_MARKER_NOT_A_MNEMONIC"


def executable(path, source):
    path.write_text(source)
    path.chmod(0o700)


class Bootstrap(unittest.TestCase):
    def setUp(self):
        self.at = Path(tempfile.mkdtemp(prefix="montana-bootstrap-test-"))
        self.data = self.at / "data"
        self.data.mkdir()
        self.bin = self.at / "bin"
        self.bin.mkdir()
        self.log = self.at / "calls.jsonl"
        node = self.bin / "node"
        executable(node, '''#!/usr/bin/env python3
import json, os, pathlib, stat, sys
args = sys.argv[1:]
with open(os.environ['TEST_CALLS'], 'a') as out:
    out.write(json.dumps(args) + '\\n')
assert 'MONTANA_MNEMONIC' not in os.environ
at = pathlib.Path(args[args.index('--data-dir') + 1])
if args[0] == 'init':
    assert '--mnemonic' not in args
    try:
        tty = open('/dev/tty', 'w')
    except OSError:
        pass
    else:
        tty.close()
        raise SystemExit(92)  # init could bypass stream redirection through this terminal.
    assert stat.S_IMODE((at / 'init.log').stat().st_mode) == 0o400
    fd = os.open(at / 'mnemonic.txt', os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    with os.fdopen(fd, 'w') as recovery:
        recovery.write(os.environ['TEST_MARKER'] + '\\n')
    if '--mnemonic-stdin' in args:
        assert sys.stdin.read().strip() == os.environ['TEST_MARKER']
    print(os.environ['TEST_MARKER'], flush=True)
    print(os.environ['TEST_MARKER'] + '_STDERR', file=sys.stderr, flush=True)
    if os.environ.get('TEST_FAIL'):
        raise SystemExit(17)
    (at / 'identity.bin').write_bytes(b'test identity only')
elif args[0] != 'start':
    raise SystemExit(93)
''')
        executable(self.bin / "runuser", '''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:4] == ['-u', 'montana', '--']
os.execvp(sys.argv[4], sys.argv[4:])
''')
        # util-linux setsid is supplied by the runtime image. This fixture uses the
        # host's real setsid syscall and propagates the child exit status.
        executable(self.bin / "setsid", '''#!/usr/bin/env python3
import subprocess, sys
assert sys.argv[1] == '--wait'
sys.exit(subprocess.run(sys.argv[2:], start_new_session=True).returncode)
''')
        executable(self.bin / "chown", "#!/bin/sh\nexit 0\n")
        executable(self.bin / "curl", "#!/bin/sh\nexit 94\n")
        text = SOURCE.read_text()
        assert text.count('DATA_DIR="/var/lib/montana"') == 1
        text = text.replace('DATA_DIR="/var/lib/montana"', f'DATA_DIR="{self.data}"')
        text = text.replace('/usr/local/bin/montana-node', str(node))
        self.script = self.at / "entrypoint.sh"
        self.script.write_text(text)
        self.manifest = self.at / 'genesis-manifest.json'
        self.manifest.write_text('{}\n')
        self.env = {**os.environ, 'PATH': str(self.bin) + os.pathsep + os.environ['PATH'],
                    'TEST_CALLS': str(self.log), 'TEST_MARKER': MARKER,
                    'MONTANA_GENESIS_MANIFEST': str(self.manifest)}
        for name in ('MONTANA_MNEMONIC', 'MONTANA_D_TEST_OVERRIDE', 'MONTANA_MANIFEST_SHA256',
                     'MONTANA_OPEN'):
            self.env.pop(name, None)

    def run_entrypoint(self):
        master, slave = pty.openpty()

        def terminal():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        try:
            result = subprocess.run(['bash', str(self.script)], env=self.env,
                                    stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                    preexec_fn=terminal, timeout=30)
        finally:
            os.close(master)
            os.close(slave)
        self.assertNotIn(MARKER.encode(), result.stdout + result.stderr)
        return result

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_generated_recovery_is_private_before_init_and_no_report_runs(self):
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.calls()], ['init', 'start'])
        recovery = self.data / 'mnemonic.txt'
        self.assertEqual(stat.S_IMODE(recovery.stat().st_mode), 0o400)
        self.assertEqual(recovery.read_text().splitlines(), [MARKER])
        self.assertEqual((self.data / 'init.log').read_text().splitlines(), [MARKER, MARKER + '_STDERR'])
        self.assertEqual(stat.S_IMODE((self.data / 'init.log').stat().st_mode), 0o400)
        self.assertNotIn('MONTANA_REPORT_URL', SOURCE.read_text())

    def test_provided_recovery_uses_stdin_and_is_not_in_the_child_environment(self):
        self.env['MONTANA_MNEMONIC'] = MARKER
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--mnemonic-stdin', self.calls()[0])
        self.assertNotIn(MARKER, self.log.read_text())

    def test_init_failure_is_not_hidden_and_never_starts_the_node(self):
        self.env['TEST_FAIL'] = 'yes'
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 17)
        self.assertEqual([call[0] for call in self.calls()], ['init'])
        self.assertFalse((self.data / 'identity.bin').exists())
        self.assertEqual(stat.S_IMODE((self.data / 'mnemonic.txt').stat().st_mode), 0o400)

    def test_provided_recovery_failure_preserves_pipeline_exit(self):
        self.env['MONTANA_MNEMONIC'] = MARKER
        self.env['TEST_FAIL'] = 'yes'
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 17)
        self.assertEqual([call[0] for call in self.calls()], ['init'])
        self.assertIn('--mnemonic-stdin', self.calls()[0])
        self.assertNotIn(MARKER, self.log.read_text())

    def test_empty_recovery_environment_is_not_inherited_by_init(self):
        self.env['MONTANA_MNEMONIC'] = ''
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.calls()], ['init', 'start'])
        self.assertNotIn('--mnemonic-stdin', self.calls()[0])

    def test_existing_recovery_is_not_overwritten_or_followed(self):
        target = self.at / 'retained'
        target.write_text('keep this artifact')
        (self.data / 'mnemonic.txt').symlink_to(target)
        result = self.run_entrypoint()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(target.read_text(), 'keep this artifact')
        self.assertEqual(self.calls(), [])

    def test_existing_identity_does_not_generate_another_recovery(self):
        (self.data / 'identity.bin').write_bytes(b'existing test identity')
        self.env['MONTANA_MNEMONIC'] = MARKER
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([call[0] for call in self.calls()], ['start'])
        self.assertFalse((self.data / 'mnemonic.txt').exists())

    def test_start_carries_listen_and_manifest(self):
        (self.data / 'identity.bin').write_bytes(b'existing test identity')
        # A release image refuses the test-only D override; the entrypoint does not pass it.
        self.env['MONTANA_D_TEST_OVERRIDE'] = '1'
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        start = self.calls()[0]
        self.assertEqual(start[start.index('--genesis-manifest') + 1], str(self.manifest))
        self.assertIn('--listen', start)
        self.assertNotIn('--d-test-override', start)
        self.assertNotIn('--open', start)

    def test_open_is_passed_only_when_the_operator_asks(self):
        # issue #17 K5: window zero opens only by the operator's explicit act.
        (self.data / 'identity.bin').write_bytes(b'existing test identity')
        self.env['MONTANA_OPEN'] = '1'
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--open', self.calls()[0])

    def test_no_manifest_never_starts_the_node(self):
        # issue #17 K5: no single mode without a manifest.
        (self.data / 'identity.bin').write_bytes(b'existing test identity')
        self.env['MONTANA_GENESIS_MANIFEST'] = str(self.at / 'no-manifest')
        self.env['MONTANA_D_TEST_OVERRIDE'] = '1'
        result = self.run_entrypoint()
        self.assertEqual(result.returncode, 1)
        self.assertIn(b'no genesis manifest', result.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
