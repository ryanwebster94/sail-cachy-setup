"""Linux regression checks: python3 -m unittest discover -s tests -v.

Requires bash, git, jq, file, flock and coreutils. Desktop/image programs are
stubbed; tests never invoke a real compositor, package manager or user service.
"""
import base64
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII=')


class RegressionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=os.environ.get('QS_TEST_TMPDIR'))
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        XDG_CONFIG_HOME=str(self.root / 'config with spaces'),
                        XDG_DATA_HOME=str(self.root / 'data'),
                        XDG_CACHE_HOME=str(self.root / 'cache'),
                        XDG_STATE_HOME=str(self.root / 'state'),
                        NOCTALIA_CONFIG_HOME=str(self.root / 'noctalia config'),
                        CALL_LOG=str(self.root / 'calls'), TEST_ROOT=str(self.root),
                        GIT_AUTHOR_NAME='Regression Test', GIT_AUTHOR_EMAIL='test@example.invalid',
                        GIT_COMMITTER_NAME='Regression Test', GIT_COMMITTER_EMAIL='test@example.invalid')
        (self.root / 'tiny.png').write_bytes(PNG)
        self.stub('noctalia', 'case "$*" in\n"msg wallpaper-get") printf "%s\\n" "${CURRENT_WALLPAPER:-}"; exit "${QUERY_FAIL:-0}";;\nesac\nprintf "%s\\n" "$*" >> "$CALL_LOG"\n')
        self.stub('vipsthumbnail', 'printf "thumbnail\\n" >> "$CALL_LOG"\nwhile (( $# )); do if [[ $1 == -o ]]; then shift; out=${1%%\\[*}; fi; shift; done\ncp "$TEST_ROOT/tiny.png" "$out"\n')
        self.stub('quickshell', 'cp "$PICKER_JSON" "$TEST_ROOT/seen.json"\nif [[ -n ${PICK_CHOICE:-} ]]; then printf "%s\\n" "$PICK_CHOICE" > "$PICKER_SEL"; fi\n: > "$PICKER_DONE"\n')

    def stub(self, name, body):
        target = self.bin / name
        target.write_text('#!/bin/bash\n' + body)
        target.chmod(0o755)

    def run_cmd(self, args, cwd=None, ok=True):
        result = subprocess.run([str(a) for a in args], cwd=cwd or self.root,
                                env=self.env, text=True, capture_output=True, timeout=25)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def rows(self, mode, folder):
        out = self.root / 'rows.json'
        self.run_cmd(['bash', REPO / 'files/quickshell-picker/build-rows.sh', mode, folder, out])
        return json.loads(out.read_text())

    def test_wallpaper_cache_refresh_and_special_names(self):
        pics = self.root / 'pictures'
        pics.mkdir()
        names = ['first.png', 'space # % ?.jpg', 'newline\nname.png']
        for name in names:
            (pics / name).write_bytes(PNG)
        self.env['CURRENT_WALLPAPER'] = str(pics / names[1])
        first = self.rows('wallpaper', pics)
        self.assertEqual({i['path'] for i in first['items']}, {str(pics / n) for n in names})
        self.assertEqual(first['selected'], self.env['CURRENT_WALLPAPER'])
        before = (self.root / 'calls').read_text()
        self.assertEqual(self.rows('wallpaper', pics), first)
        self.assertEqual((self.root / 'calls').read_text(), before)
        old = next(i['thumb'] for i in first['items'] if i['path'].endswith('first.png'))
        (pics / names[0]).write_bytes(PNG + b'changed')
        fresh = self.rows('wallpaper', pics)
        self.assertNotEqual(old, next(i['thumb'] for i in fresh['items'] if i['path'].endswith('first.png')))
        Path(fresh['items'][0]['thumb']).unlink()
        self.rows('wallpaper', pics)
        self.assertTrue(Path(fresh['items'][0]['thumb']).exists())

    def test_folder_representative_refresh_and_missing_directory(self):
        pics = self.root / 'pictures'
        folder = pics / 'theme'
        folder.mkdir(parents=True)
        empty = pics / 'empty'
        empty.mkdir()
        (folder / 'b.png').write_bytes(PNG)
        first = self.rows('folder', pics)
        old = next(i['thumb'] for i in first['items'] if i['path'] == str(folder))
        (folder / 'a.png').write_bytes(PNG)
        fresh = self.rows('folder', pics)
        self.assertNotEqual(old, next(i['thumb'] for i in fresh['items'] if i['path'] == str(folder)))
        old = next(i['thumb'] for i in fresh['items'] if i['path'] == str(folder))
        (folder / 'a.png').write_bytes(PNG + b'edited in place')
        fresh = self.rows('folder', pics)
        self.assertNotEqual(old, next(i['thumb'] for i in fresh['items'] if i['path'] == str(folder)))
        self.assertTrue(Path(next(i['thumb'] for i in fresh['items'] if i['path'] == str(empty))).exists())
        self.assertEqual(self.rows('wallpaper', self.root / 'absent')['items'], [])

    def test_failed_decode_is_retried(self):
        pics = self.root / 'pictures'
        pics.mkdir()
        (pics / 'a.png').write_bytes(PNG)
        good_thumbnailer = (self.bin / 'vipsthumbnail').read_text()
        self.stub('vipsthumbnail', 'exit 1\n')
        self.assertEqual(self.rows('wallpaper', pics)['items'], [])
        (self.bin / 'vipsthumbnail').write_text(good_thumbnailer)
        self.assertEqual(len(self.rows('wallpaper', pics)['items']), 1)

    def test_linked_picker_and_failed_wallpaper_query(self):
        picker = self.root / 'installed picker'
        shutil.copytree(REPO / 'files/quickshell-picker', picker)
        for p in (picker / 'bin').iterdir():
            p.chmod(0o755)
            (self.bin / p.name).symlink_to(p)
        (picker / 'build-rows.sh').chmod(0o755)
        pics = self.root / 'pictures'
        pics.mkdir()
        (pics / 'a.png').write_bytes(PNG)
        self.env['QUERY_FAIL'] = '1'
        self.run_cmd([self.bin / 'qs-wallpaper-pick', pics])
        self.assertEqual(len(json.loads((self.root / 'seen.json').read_text())['items']), 1)
        (pics / 'theme').mkdir()
        self.run_cmd([self.bin / 'qs-folder-pick', pics])
        self.assertEqual(json.loads((self.root / 'seen.json').read_text())['items'][0]['label'], 'theme')

    def test_webapp_two_args_xdg_and_quoted_launcher(self):
        scripts = self.root / 'web apps'
        shutil.copytree(REPO / 'files/webapps/bin', scripts)
        for p in scripts.iterdir(): p.chmod(0o755)
        (self.bin / 'qs-webapp-install').symlink_to(scripts / 'qs-webapp-install')
        self.stub('curl', 'while (( $# )); do if [[ $1 == -o ]]; then shift; cp "$TEST_ROOT/tiny.png" "$1"; exit 0; fi; shift; done\nprintf "<html></html>"\n')
        self.run_cmd([self.bin / 'qs-webapp-install', 'Example', 'https://example.com'])
        entry = Path(self.env['XDG_DATA_HOME']) / 'applications/Example.desktop'
        text = entry.read_text()
        self.assertIn('Exec="' + str(scripts / 'qs-webapp-launch') + '" "https://example.com"', text)
        bad = self.run_cmd([scripts / 'qs-webapp-install', 'Bad', 'https://', 'icon'], ok=False)
        self.assertNotEqual(bad.returncode, 0)
        self.stub('fzf', 'exit 130\n')
        self.run_cmd([scripts / 'qs-webapp-remove'])
        self.assertTrue(entry.exists())
        self.run_cmd([scripts / 'qs-webapp-remove', 'Example'])
        self.assertFalse(entry.exists())
        svg = self.root / 'icon.svg'
        svg.write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        icons = []
        for name in ['Example!', 'Example?']:
            self.run_cmd([scripts / 'qs-webapp-install', name, 'https://example.com', svg])
            entry_text = (entry.parent / (name + '.desktop')).read_text()
            icons.append(re.search(r'^Icon=(.*)$', entry_text, re.M)[1])
        self.assertNotEqual(*icons)
        icon_dir = Path(self.env['XDG_DATA_HOME']) / 'icons/hicolor/256x256/apps'
        self.run_cmd([scripts / 'qs-webapp-remove', 'Example!'])
        self.assertFalse((icon_dir / (icons[0] + '.svg')).exists())
        self.assertTrue((icon_dir / (icons[1] + '.svg')).exists())

    def make_git_pair(self):
        remote, checkout = self.root / 'remote.git', self.root / 'checkout'
        self.run_cmd(['git', 'init', '--bare', '--initial-branch=main', remote])
        self.run_cmd(['git', 'init', '--initial-branch=main', checkout])
        for name in ['qs-loop.sh']:
            shutil.copy2(REPO / name, checkout / name)
            (checkout / name).chmod(0o755)
        (checkout / 'sync.sh').write_text('#!/bin/bash\nif [[ -n ${CAPTURE:-} ]]; then printf "%s" "$CAPTURE" > managed.txt; fi\n')
        (checkout / 'setup.sh').write_text('#!/bin/bash\nprintf "apply\\n" >> "$CALL_LOG"\n')
        for name in ['sync.sh', 'setup.sh']: (checkout / name).chmod(0o755)
        (checkout / 'managed.txt').write_text('base')
        self.run_cmd(['git', 'add', '.'], checkout)
        self.run_cmd(['git', 'commit', '-m', 'base'], checkout)
        self.run_cmd(['git', 'remote', 'add', 'origin', remote], checkout)
        self.run_cmd(['git', 'push', '-u', 'origin', 'main'], checkout)
        return remote, checkout

    def test_sync_uses_tracking_branch_and_preserves_dirty_changes(self):
        remote, checkout = self.make_git_pair()
        main = self.run_cmd(['git', 'rev-parse', 'main'], remote).stdout.strip()
        self.run_cmd(['git', 'checkout', '-b', 'feature/theme'], checkout)
        self.run_cmd(['git', 'push', '-u', 'origin', 'feature/theme'], checkout)
        self.env['CAPTURE'] = 'captured change'
        self.run_cmd([checkout / 'qs-loop.sh', 'save'])
        self.assertEqual(self.run_cmd(['git', 'rev-parse', 'main'], remote).stdout.strip(), main)
        self.assertEqual(self.run_cmd(['git', 'show', 'feature/theme:managed.txt'], remote).stdout, 'captured change')
        (checkout / 'managed.txt').write_text('uncommitted edit')
        result = self.run_cmd([checkout / 'qs-loop.sh', 'once'], ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((checkout / 'managed.txt').read_text(), 'uncommitted edit')

    def test_idle_sync_skips_deploy_but_explicit_apply_still_runs(self):
        _, checkout = self.make_git_pair()
        self.run_cmd([checkout / 'qs-loop.sh', 'once'])
        self.run_cmd([checkout / 'qs-loop.sh', 'once'])
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['apply'])
        self.run_cmd([checkout / 'qs-loop.sh', 'apply'])
        self.assertEqual((self.root / 'calls').read_text().splitlines(), ['apply', 'apply'])

    def test_conflicting_pull_preserves_commit_and_never_deploys(self):
        remote, checkout = self.make_git_pair()
        peer = self.root / 'peer'
        self.run_cmd(['git', 'clone', remote, peer])
        (peer / 'managed.txt').write_text('remote change')
        self.run_cmd(['git', 'commit', '-am', 'remote edit'], peer)
        self.run_cmd(['git', 'push'], peer)
        (checkout / 'managed.txt').write_text('local change')
        self.run_cmd(['git', 'commit', '-am', 'local edit'], checkout)
        before = self.run_cmd(['git', 'rev-parse', 'HEAD'], checkout).stdout
        result = self.run_cmd([checkout / 'qs-loop.sh', 'apply'], ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.run_cmd(['git', 'rev-parse', 'HEAD'], checkout).stdout, before)
        self.assertEqual((checkout / 'managed.txt').read_text(), 'local change')
        self.assertFalse((self.root / 'calls').exists())
        self.assertEqual(self.run_cmd(['git', 'status', '--porcelain'], checkout).stdout, '')

    def test_installers_dependencies_assets_and_service_start(self):
        for name in ['chromium', 'file', 'hyprctl', 'fzf', 'vipsthumbnail', 'quickshell', 'curl']:
            self.stub(name, 'exit 0\n')
        self.stub('sudo', 'printf "sudo %s\\n" "$*" >> "$CALL_LOG"\nif [[ $1 == pacman ]]; then\nfor name in quickshell chromium; do printf "#!/bin/bash\\nexit 0\\n" > "$TEST_ROOT/bin/$name"; chmod +x "$TEST_ROOT/bin/$name"; done\nfi\n')
        for name in ['qs-picker-install.sh', 'qs-webapp-install.sh']:
            # The dependency is initially absent; pacman must run before checks.
            (self.bin / ('quickshell' if 'picker' in name else 'chromium')).unlink()
            self.run_cmd(['bash', REPO / 'dist' / name, '--install-deps'])
            self.run_cmd(['bash', REPO / 'dist' / name])
        self.assertIn('sudo pacman', (self.root / 'calls').read_text())
        installed = Path(self.env['XDG_CONFIG_HOME']) / 'quickshell/picker'
        for rel in ['shell.qml', 'colors.json.tmpl', 'build-rows.sh', 'bin/qs-picker']:
            self.assertEqual((installed / rel).read_bytes(), (REPO / 'files/quickshell-picker' / rel).read_bytes())
        for p in (REPO / 'dist').glob('*.sh'):
            self.assertNotRegex(p.read_text(), r'@@[A-Z_]+@@')
        self.stub('systemctl', 'printf "%s\\n" "$*" >> "$CALL_LOG"\n')
        setup = (REPO / 'setup.sh').read_text()
        functions = setup[setup.index('install_auto_units()'):setup.index('remove_auto_units()')]
        unusual = self.root / 'repo & 100% | space'
        shutil.copytree(REPO / 'systemd', unusual / 'systemd')
        self.env['TEST_REPO'] = str(unusual)
        self.run_cmd(['bash', '-c', 'set -euo pipefail\nREPO_DIR="$TEST_REPO"\nCONFIG_HOME="$XDG_CONFIG_HOME"\nsay() { :; }\n' + functions + '\ninstall_auto_units'])
        calls = (self.root / 'calls').read_text()
        self.assertNotIn('start qs-apply.service', calls)
        self.assertNotIn('enable --now', calls)
        unit = Path(self.env['XDG_CONFIG_HOME']) / 'systemd/user/qs-apply.service'
        self.assertIn('ExecStart="' + str(unusual).replace('%', '%%') + '/qs-loop.sh" apply', unit.read_text())


if __name__ == '__main__':
    unittest.main()
