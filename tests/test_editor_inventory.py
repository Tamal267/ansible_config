import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    'editor_inventory', Path(__file__).resolve().parents[1] / 'scripts/editor_inventory.py')
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class EditorInventoryTests(unittest.TestCase):
    def test_calculator_image_viewer_mpv_and_videos_are_selected_when_installed(self):
        with tempfile.TemporaryDirectory() as directory:
            selected, _ = inventory.apt_editors(
                {'gnome-calculator', 'eog', 'loupe', 'mpv', 'totem', 'firefox'},
                directory, lambda _: set())
        self.assertEqual(selected, ['eog', 'gnome-calculator', 'loupe', 'mpv', 'totem'])

    def test_desktop_categories_find_apps_without_selecting_browser_or_pdf_viewer(self):
        categories = {
            'custom-calc': 'Utility;Calculator;',
            'custom-image': 'Graphics;Viewer;',
            'custom-video': 'AudioVideo;Video;Player;',
            'firefox': 'Network;WebBrowser;',
            'pdf-viewer': 'Office;Viewer;',
            'music': 'AudioVideo;Audio;Player;',
        }
        with tempfile.TemporaryDirectory() as directory:
            for name, value in categories.items():
                (Path(directory) / (name + '.desktop')).write_text(
                    '[Desktop Entry]\nCategories=' + value + '\n')
            selected, _ = inventory.apt_editors(set(categories), directory, lambda path: {path.stem})
        self.assertEqual(selected, ['custom-calc', 'custom-image', 'custom-video'])

    def test_store_calculator_and_viewers_prevent_duplicate_apt_install(self):
        current = {'snap': [{'key': 'mpv'}], 'flatpak': [
            {'key': 'system:org.gnome.Calculator'}, {'key': 'system:org.gnome.eog'},
            {'key': 'user:student:org.gnome.Totem'}]}
        self.assertEqual(inventory.non_apt_packages(current), ['eog', 'gnome-calculator', 'mpv', 'totem'])

    def test_discovers_terminal_and_desktop_editors_without_selecting_browser(self):
        with tempfile.TemporaryDirectory() as directory:
            for name, categories in [('custom-editor', 'Utility;TextEditor;'),
                                     ('custom-ide', 'Development;IDE;'),
                                     ('firefox', 'Network;WebBrowser;')]:
                (Path(directory) / (name + '.desktop')).write_text(
                    '[Desktop Entry]\nType=Application\nCategories=' + categories + '\n')
            installed = {'nano', 'vim-tiny', 'custom-editor', 'custom-ide', 'firefox', 'openssh-server'}
            selected, unmanaged = inventory.apt_editors(
                installed, directory, lambda path: {path.stem})
            self.assertEqual(selected, ['custom-editor', 'custom-ide', 'nano', 'vim-tiny'])
            self.assertEqual(unmanaged, [])

    def test_unmanaged_editor_is_reported_without_guessing_a_package(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'portable.desktop'
            path.write_text('[Desktop Entry]\nCategories=TextEditor;\n')
            selected, unmanaged = inventory.apt_editors(set(), directory, lambda _: set())
            self.assertEqual(selected, [])
            self.assertEqual(unmanaged, [str(path)])

    def test_second_cleanup_retains_the_restore_record(self):
        saved = {'apt': ['gedit', 'nano'], 'snap': [
            {'key': 'code', 'remove': ['snap', 'remove', 'code'],
             'install': ['snap', 'install', 'code', '--channel=latest/stable', '--classic']}],
            'flatpak': []}
        empty = {'apt': [], 'snap': [], 'flatpak': []}
        self.assertEqual(inventory.merge_manifest(saved, empty), saved)
        merged = inventory.merge_manifest(saved, {'apt': ['nano', 'mousepad'], 'snap': [], 'flatpak': []})
        self.assertEqual(merged['apt'], ['gedit', 'mousepad', 'nano'])
        self.assertEqual(merged['snap'], saved['snap'])

    def test_snap_plan_retains_channel_and_classic_mode(self):
        output = ('Name Version Rev Tracking Publisher Notes\n'
                  'code 1.99 123 latest/stable vscode classic\n'
                  'firefox 140 456 latest/stable mozilla -\n')
        result = subprocess.CompletedProcess(['snap', 'list'], 0, stdout=output, stderr='')
        with patch.object(inventory.shutil, 'which', return_value='/usr/bin/snap'), \
             patch.object(inventory.subprocess, 'run', return_value=result), \
             patch.object(inventory.Path, 'glob', return_value=[]):
            records = inventory.snap_inventory()
        self.assertEqual(len(records), 1)
        self.assertEqual(records[0]['key'], 'code')
        self.assertEqual(records[0]['remove'], ['snap', 'remove', 'code'])
        self.assertEqual(records[0]['install'], ['snap', 'install', 'code', '--channel=latest/stable', '--classic'])

    def test_local_snap_is_not_removed_without_a_restorable_source(self):
        result = subprocess.CompletedProcess(['snap', 'list'], 0,
            stdout='Name Version Rev Tracking Publisher Notes\nnano 1 x1 - - dangerous\n', stderr='')
        with patch.object(inventory.shutil, 'which', return_value='/usr/bin/snap'), \
             patch.object(inventory.subprocess, 'run', return_value=result), \
             patch.object(inventory.Path, 'glob', return_value=[]):
            with self.assertRaises(ValueError):
                inventory.snap_inventory()

    def test_flatpak_plan_preserves_user_origin_and_branch(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = ['runuser', '-u', 'student', '--', 'env', 'HOME=/home/student', 'flatpak', '--user']
            scopes = [(prefix, Path(directory), 'user:student')]
            output = 'org.gnome.TextEditor\tflathub\tstable\norg.mozilla.firefox\tflathub\tstable\n'
            with patch.object(inventory.shutil, 'which', return_value='/usr/bin/flatpak'), \
                 patch.object(inventory, 'flatpak_scopes', return_value=scopes), \
                 patch.object(inventory, 'run', return_value=output):
                records = inventory.flatpak_inventory()
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0]['key'], 'user:student:org.gnome.TextEditor')
            self.assertEqual(records[0]['install'], prefix + [
                'install', '--noninteractive', '-y', 'flathub', 'org.gnome.TextEditor//stable'])
            self.assertNotIn('--delete-data', records[0]['remove'])

    def test_present_store_editor_prevents_duplicate_apt_install(self):
        current = {'snap': [{'key': 'geany'}], 'flatpak': [
            {'key': 'user:student:org.gnome.TextEditor'}]}
        self.assertEqual(inventory.non_apt_packages(current),
                         ['geany', 'geany-common', 'geany-plugins-common', 'gnome-text-editor'])


if __name__ == '__main__':
    unittest.main()
