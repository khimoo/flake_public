import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from config import ConfigError, Settings, identity


class ConfigTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.home = Path(tmp.name)
        self.config = self.home / 'custom.json'
        self.config.write_text(json.dumps({'agents': {
            'sol': {'kind': 'hermes', 'profile': 'aiboard-sol', 'model': 'gpt-sol'},
            'mock_agent': {'kind': 'custom', 'command': ['true']},
        }}))
        self.env = patch.dict(os.environ, {'HOME': str(self.home)}, clear=True)
        self.addCleanup(self.env.stop)
        self.env.start()

    def test_uses_profile_basename_with_optional_trailing_slash(self):
        cfg = Settings.load(config=self.config)
        for value in ('/fake/profiles/aiboard-sol', '/fake/profiles/aiboard-sol/'):
            with self.subTest(value=value), patch.dict(os.environ, {'HERMES_HOME': value, 'AIBOARD_AGENT': ''}):
                self.assertEqual(identity(cfg), ('sol', 'agent'))

    def test_explicit_agent_takes_precedence_and_unknown_is_error(self):
        cfg = Settings.load(config=self.config)
        with patch.dict(os.environ, {'HERMES_HOME': '/fake/aiboard-sol', 'AIBOARD_AGENT': 'mock_agent'}):
            self.assertEqual(identity(cfg), ('mock_agent', 'agent'))
        with patch.dict(os.environ, {'HERMES_HOME': '/fake/aiboard-sol', 'AIBOARD_AGENT': 'oops'}):
            with self.assertRaises(ConfigError):
                identity(cfg)

    def test_main_uses_default_home_model_even_with_another_profile(self):
        cfg = Settings.load(config=self.config)
        with patch.dict(os.environ, {'HERMES_HOME': '/fake/other-profile'}):
            self.assertEqual(identity(cfg), ('main(unknown)', 'main'))
            path = self.home / '.hermes' / 'config.yaml'
            path.parent.mkdir()
            path.write_text('model:\n  default: gpt-sol\n')
            self.assertEqual(identity(cfg), ('main(sol)', 'main'))
            path.write_text('model: vendor/other\n')
            self.assertEqual(identity(cfg), ('main(other)', 'main'))

    def test_path_precedence_and_nondefault_notice(self):
        cfg = Settings.load(config=self.config)
        self.assertEqual(cfg.db_path, self.home / '.local/share/aiboard/aiboard.db')
        self.assertTrue(cfg.nondefault_paths)
        with patch.dict(os.environ, {'XDG_DATA_HOME': str(self.home / 'xdg'), 'AIBOARD_DATA_DIR': str(self.home / 'data'), 'AIBOARD_DB': str(self.home / 'env.db'), 'AIBOARD_CONFIG': '/missing'}):
            cfg = Settings.load(db=self.home / 'option.db', config=self.config)
            self.assertEqual(cfg.data_dir, self.home / 'data')
            self.assertEqual(cfg.db_path, self.home / 'option.db')
            self.assertEqual(cfg.config_path, self.config)

    def test_reserved_handles_cannot_be_residents(self):
        self.config.write_text('{"agents":{"user":{"kind":"custom","command":["true"]}}}')
        with self.assertRaises(ConfigError):
            Settings.load(config=self.config)
