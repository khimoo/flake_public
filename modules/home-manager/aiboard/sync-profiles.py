"""Update only settings owned by aiboard; preserve provider credentials and state."""
import json
import os
from pathlib import Path
import subprocess
import sys

import yaml


def main(home, hermes, agents_file):
    root = Path(home) / '.hermes'
    env = os.environ | {'HOME': str(home), 'HERMES_HOME': str(root)}
    manifest = json.loads(Path(agents_file).read_text(encoding='utf-8'))
    for handle, agent in manifest['agents'].items():
        if agent.get('kind', 'hermes') != 'hermes':
            continue
        profile = agent['profile']
        config = root / 'profiles' / profile / 'config.yaml'
        if not config.exists():
            subprocess.run([hermes, 'profile', 'create', profile, '--no-alias'], env=env, check=True)
        value = yaml.safe_load(config.read_text(encoding='utf-8')) or {}
        toolsets = agent.get('toolsets', manifest['defaults']['toolsets'])
        if isinstance(toolsets, str):
            toolsets = toolsets.split(',')
        reasoning = agent.get('reasoning', manifest['defaults']['reasoning'])
        options = {
            'model.default': agent['model'],
            'model.provider': agent['provider'],
            'platform_toolsets.cli': toolsets,
            'agent.reasoning_effort': reasoning,
        }
        for key, desired in options.items():
            current = value
            for segment in key.split('.'):
                current = current.get(segment) if isinstance(current, dict) else None
            if desired is not None and current != desired:
                subprocess.run([hermes, '-p', profile, 'config', 'set', key, json.dumps(desired) if isinstance(desired, list) else desired], env=env, check=True)


if __name__ == '__main__':
    main(*sys.argv[1:])
