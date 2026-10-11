#!/usr/bin/env python3
"""Read installed editor inventory and merge a previous restore manifest.

This script never installs or removes software. Ansible applies the returned plan.
"""
import argparse
import configparser
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess


APT_NAMES = {
    'nano', 'gedit', 'gnome-text-editor', 'mousepad', 'leafpad', 'pluma',
    'xed', 'kate', 'kwrite', 'geany', 'sublime-text', 'code', 'code-insiders',
    'codium', 'atom', 'neovim', 'neovim-qt', 'vim', 'vim-tiny', 'vim-gtk3',
    'vim-athena', 'vim-nox', 'emacs', 'emacs-nox', 'emacs-gtk', 'emacs-lucid',
    'emacs-common', 'emacs-bin-common', 'emacs-el', 'xemacs21', 'jed', 'xjed',
    'joe', 'jove', 'micro', 'ne', 'ed', 'scite', 'medit', 'notepadqq',
    'bluefish', 'beaver', 'gobby', 'gobby-0.5', 'tea', 'nedit', 'nedit-ng',
    'kakoune', 'helix', 'codeblocks', 'codeblocks-common', 'codeblocks-contrib',
}
SNAP_NAMES = {
    'nano', 'gedit', 'gnome-text-editor', 'kate', 'kwrite', 'geany', 'sublime-text',
    'code', 'code-insiders', 'codium', 'atom', 'nvim', 'neovim', 'vim', 'emacs',
    'micro', 'notepadqq', 'notepad-plus-plus', 'intellij-idea-community',
    'intellij-idea-ultimate', 'pycharm-community', 'pycharm-professional',
    'codeblocks', 'helix',
}
FLATPAK_IDS = {
    'org.gnome.TextEditor', 'org.gnome.gedit', 'org.kde.kate', 'org.kde.kwrite',
    'org.xfce.mousepad', 'org.geany.Geany', 'com.visualstudio.code',
    'com.vscodium.codium', 'com.sublimetext.three', 'io.atom.Atom',
    'org.gnu.emacs', 'io.neovim.nvim', 'org.codeblocks.codeblocks',
}
APP_APT_PACKAGES = {
    'geany': ['geany', 'geany-common', 'geany-plugins-common'],
    'kate': ['kate'], 'kwrite': ['kwrite'], 'gedit': ['gedit'],
    'gnome-text-editor': ['gnome-text-editor'], 'nano': ['nano'],
    'vim': ['vim', 'vim-gtk3', 'vim-gui-common'],
    'neovim': ['neovim', 'neovim-qt'],
    'code': ['code'], 'code-insiders': ['code-insiders'],
    'sublime-text': ['sublime-text'],
    'intellij-idea-community': ['intellij-idea-community'],
    'intellij-idea-ultimate': ['intellij-idea-community'],
    'pycharm-community': ['pycharm-community'],
    'pycharm-professional': ['pycharm-community'],
}
FLATPAK_APP_NAMES = {
    'org.gnome.TextEditor': 'gnome-text-editor', 'org.gnome.gedit': 'gedit',
    'org.kde.kate': 'kate', 'org.kde.kwrite': 'kwrite',
    'org.geany.Geany': 'geany', 'io.neovim.nvim': 'neovim',
    'com.visualstudio.code': 'code', 'com.sublimetext.three': 'sublime-text',
    'com.jetbrains.IntelliJ-IDEA-Community': 'intellij-idea-community',
    'com.jetbrains.IntelliJ-IDEA-Ultimate': 'intellij-idea-community',
    'com.jetbrains.PyCharm-Community': 'pycharm-community',
    'com.jetbrains.PyCharm-Professional': 'pycharm-community',
}


def run(argv):
    env = dict(os.environ, LC_ALL='C')
    return subprocess.run(argv, env=env, text=True, capture_output=True, check=True).stdout


def desktop_metadata(path):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read(path, encoding='utf-8')
        entry = parser['Desktop Entry']
        categories = set(entry.get('Categories', '').split(';'))
        return bool(categories & {'TextEditor', 'IDE'}), entry.get('X-Flatpak', '')
    except (OSError, UnicodeError, configparser.Error, KeyError):
        return False, ''


def apt_editors(installed, desktop_dir, owner_lookup):
    selected = installed & APT_NAMES
    unmanaged = []
    for desktop in Path(desktop_dir).glob('*.desktop'):
        editor, _ = desktop_metadata(desktop)
        if not editor:
            continue
        owners = owner_lookup(desktop)
        selected.update(owners & installed)
        if not owners and desktop.name not in {'intellij.desktop', 'pycharm.desktop'}:
            unmanaged.append(str(desktop))
    return sorted(selected), sorted(unmanaged)


def apt_inventory():
    output = run(['dpkg-query', '-W', '-f=${Package}\t${db:Status-Status}\n'])
    installed = {line.split('\t')[0] for line in output.splitlines()
                 if line.endswith('\tinstalled')}

    def owners(path):
        result = subprocess.run(['dpkg-query', '-S', str(path)], text=True, capture_output=True)
        if result.returncode == 1:
            return set()
        result.check_returncode()
        names = set()
        for line in result.stdout.splitlines():
            prefix, sep, _ = line.partition(': ')
            if sep:
                names.update(name.split(':')[0] for name in prefix.split(', '))
        return names

    return apt_editors(installed, '/usr/share/applications', owners)


def snap_inventory():
    if not shutil.which('snap'):
        return []
    result = subprocess.run(['snap', 'list'], text=True, capture_output=True,
                            env=dict(os.environ, LC_ALL='C'))
    if result.returncode and 'No snaps are installed' in result.stderr + result.stdout:
        return []
    result.check_returncode()
    editor_names = set(SNAP_NAMES)
    for desktop in Path('/var/lib/snapd/desktop/applications').glob('*.desktop'):
        if desktop_metadata(desktop)[0]:
            editor_names.add(desktop.name.split('_', 1)[0])
    records = []
    for line in result.stdout.splitlines()[1:]:
        columns = line.split()
        if len(columns) < 6 or columns[0] not in editor_names:
            continue
        name, channel, notes = columns[0], columns[3], columns[-1]
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', name):
            raise ValueError('Unexpected Snap name')
        if channel == '-' or 'devmode' in notes or 'dangerous' in notes:
            raise ValueError(f'{name}: local/devmode Snap needs its original installer for restoration')
        install = ['snap', 'install', name, '--channel=' + channel]
        if 'classic' in notes.split(','):
            install.append('--classic')
        records.append({'key': name, 'remove': ['snap', 'remove', name], 'install': install})
    return records


def flatpak_scopes():
    yield ['flatpak', '--system'], Path('/var/lib/flatpak'), 'system'
    for user in pwd.getpwall():
        location = Path(user.pw_dir) / '.local/share/flatpak'
        if location.is_dir():
            yield (['runuser', '-u', user.pw_name, '--', 'env', 'HOME=' + user.pw_dir,
                    'flatpak', '--user'], location, 'user:' + user.pw_name)


def flatpak_inventory():
    if not shutil.which('flatpak'):
        return []
    records = []
    for prefix, location, scope in flatpak_scopes():
        editor_ids = set(FLATPAK_IDS)
        for desktop in (location / 'exports/share/applications').glob('*.desktop'):
            editor, app_id = desktop_metadata(desktop)
            if editor and app_id:
                editor_ids.add(app_id)
        output = run(prefix + ['list', '--app', '--columns=application,origin,branch'])
        for line in output.splitlines():
            columns = line.split('\t')
            if len(columns) != 3 or columns[0] not in editor_ids:
                continue
            app_id, origin, branch = columns
            if not all(re.fullmatch(r'[A-Za-z0-9_.-]+', value) for value in columns):
                raise ValueError('Unexpected Flatpak application metadata')
            records.append({'key': scope + ':' + app_id,
                            'remove': prefix + ['uninstall', '--noninteractive', '-y', app_id],
                            'install': prefix + ['install', '--noninteractive', '-y', origin,
                                                app_id + '//' + branch]})
    return records


def merge_manifest(saved, current):
    merged = {'apt': sorted(set(saved.get('apt', [])) | set(current['apt']))}
    for manager in ('snap', 'flatpak'):
        entries = {entry['key']: entry for entry in saved.get(manager, [])}
        entries.update({entry['key']: entry for entry in current[manager]})
        merged[manager] = [entries[key] for key in sorted(entries)]
    return merged


def non_apt_packages(current):
    apps = {entry['key'] for entry in current['snap']}
    apps.update(FLATPAK_APP_NAMES.get(entry['key'].split(':')[-1], '')
                for entry in current['flatpak'])
    return sorted({package for app in apps for package in APP_APT_PACKAGES.get(app, [])})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', default='/var/lib/ansible_config/editor-restore.json')
    args = parser.parse_args()
    path = Path(args.manifest)
    if path.exists() and (path.stat().st_uid != 0 or path.stat().st_mode & 0o022):
        raise ValueError('Editor restore record must be owned by root and not writable by other users')
    saved = json.loads(path.read_text()) if path.is_file() else {}
    apt, unmanaged = apt_inventory()
    current = {'apt': apt, 'snap': snap_inventory(), 'flatpak': flatpak_inventory()}
    merged = merge_manifest(saved, current)
    missing = {}
    for manager in ('snap', 'flatpak'):
        installed = {entry['key'] for entry in current[manager]}
        missing[manager] = [entry for entry in saved.get(manager, []) if entry['key'] not in installed]
    print(json.dumps({'current': current, 'saved': saved, 'merged': merged,
                      'missing': missing, 'unmanaged': unmanaged,
                      'non_apt_packages': non_apt_packages(current)}))


if __name__ == '__main__':
    main()
