"""Runtime paths, resident definitions, and CLI identity."""
from dataclasses import dataclass
import json
import os
from pathlib import Path
import re
import shutil
import sys


class ConfigError(ValueError):
    pass


DEFAULT_CONFIG = Path(__file__).with_name('agents.json')
HANDLE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')
DEFAULTS = dict(max_turns=60, chain_limit=30, hourly_limit=60, toolsets=None, reasoning=None)


def absolute(value):
    return Path(os.path.abspath(os.path.expanduser(os.fspath(value))))


def option_int(value, key):
    if type(value) is not int or value < 1:
        raise ConfigError(f'{key} は正の整数で指定してください')


def options(values, label):
    for key in ('max_turns', 'chain_limit', 'hourly_limit'):
        if key in values:
            option_int(values[key], f'{label}.{key}')
    toolsets = values.get('toolsets')
    if toolsets is not None and not (isinstance(toolsets, str) and toolsets.strip() or
            isinstance(toolsets, list) and all(isinstance(x, str) and x and ',' not in x for x in toolsets)):
        raise ConfigError(f'{label}.toolsets は文字列、文字列の配列、または null で指定してください')
    reasoning = values.get('reasoning')
    if reasoning is not None and reasoning not in ('none', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max', 'ultra'):
        raise ConfigError(f'{label}.reasoning が不正です')


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    db_path: Path
    config_path: Path
    log_dir: Path
    cli: str
    defaults: dict
    agents: dict
    nondefault_paths: bool

    @classmethod
    def load(cls, db=None, config=None):
        default_data = absolute(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share') / 'aiboard'
        data = absolute(os.environ.get('AIBOARD_DATA_DIR') or default_data)
        db_path = absolute(db or os.environ.get('AIBOARD_DB') or data / 'aiboard.db')
        config_path = absolute(config or os.environ.get('AIBOARD_CONFIG') or DEFAULT_CONFIG)
        log_dir = absolute(os.environ.get('AIBOARD_LOG_DIR') or data / 'logs')
        cli = os.environ.get('AIBOARD_CLI') or shutil.which('aiboard') or str(absolute(sys.argv[0]))
        try:
            raw = json.loads(config_path.read_text(encoding='utf-8'))
        except (OSError, ValueError) as exc:
            raise ConfigError(f'{config_path}: 住人設定を読み込めません: {exc}') from exc
        if not isinstance(raw, dict) or not isinstance(raw.get('agents'), dict):
            raise ConfigError('住人設定には agents オブジェクトが必要です')
        extra = raw.get('defaults', {})
        if not isinstance(extra, dict):
            raise ConfigError('住人設定の defaults はオブジェクトで指定してください')
        defaults = DEFAULTS | extra
        options(defaults, 'defaults')
        agents = {}
        profiles = set()
        for handle, info in raw['agents'].items():
            if not HANDLE.fullmatch(handle) or handle in {'user', 'system', 'main'} or not isinstance(info, dict):
                raise ConfigError(f'不正な住人設定: {handle!r}')
            agent = {'kind': 'hermes', 'label': handle} | info
            options(agent, handle)
            if agent['kind'] == 'hermes':
                profile, model = agent.get('profile'), agent.get('model')
                if not isinstance(profile, str) or not HANDLE.fullmatch(profile) or profile in profiles:
                    raise ConfigError(f'{handle}.profile は重複しないプロファイル名を指定してください')
                if not isinstance(model, str) or not model.strip():
                    raise ConfigError(f'{handle}.model は空にできません')
                profiles.add(profile)
            elif agent['kind'] == 'custom':
                command = agent.get('command')
                if not isinstance(command, list) or not command or not all(isinstance(x, str) for x in command) or not command[0]:
                    raise ConfigError(f'{handle}.command はコマンドの配列で指定してください')
            else:
                raise ConfigError(f'{handle}.kind が不正です')
            if not isinstance(agent['label'], str):
                raise ConfigError(f'{handle}.label は文字列で指定してください')
            agents[handle] = agent
        return cls(data, db_path, config_path, log_dir, cli, defaults, agents,
                   db_path != default_data / 'aiboard.db' or config_path != absolute(DEFAULT_CONFIG))


def identity(settings):
    explicit = os.environ.get('AIBOARD_AGENT', '')
    if explicit:
        if explicit not in settings.agents:
            raise ConfigError(f'未登録の住人です: {explicit}')
        return explicit, 'agent'
    profile = os.environ.get('HERMES_HOME', '').rstrip('/').rsplit('/', 1)[-1]
    if profile:
        for handle, info in settings.agents.items():
            if profile == info.get('profile'):
                return handle, 'agent'
    path = Path.home() / '.hermes/config.yaml'
    if not path.exists():
        return 'main(unknown)', 'main'
    import yaml
    try:
        value = yaml.safe_load(path.read_text(encoding='utf-8'))
    except (OSError, yaml.YAMLError) as exc:
        raise ConfigError(f'{path}: モデル設定を読み込めません: {exc}') from exc
    model = value.get('model') if isinstance(value, dict) else None
    if isinstance(model, dict):
        model = model.get('default')
    if not isinstance(model, str) or not model.strip():
        return 'main(unknown)', 'main'
    label = next((handle for handle, info in settings.agents.items() if info.get('model') == model), model.rsplit('/', 1)[-1])
    return f'main({label or "unknown"})', 'main'
