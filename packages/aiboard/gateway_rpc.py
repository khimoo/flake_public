"""Worker-side adaptor for Hermes 0.23's authenticated local gateway.

Run the CLI entry point with the Hermes Python environment. The supervisor
uses only the small JSON projection, not Hermes internals or credentials.
"""

import argparse
import asyncio
import hashlib
import json
import os
import re
import subprocess
import sys


SESSION = re.compile(r'local-[A-Za-z0-9_-]+\Z')
PROFILE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*\Z')


class GatewayError(RuntimeError):
    pass


def prompt_digest(text):
    # The CLI's text stdin normalizes newline sequences.
    text = text.replace('\r\n', '\n').replace('\r', '\n').strip()
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def call(profile, operation, sid, generation=None, *, timeout=5):
    executable = os.environ.get('AIBOARD_HERMES_RPC') or 'aiboard-hermes-rpc'
    args = [executable, profile, operation, sid]
    if generation is not None:
        args.append(str(generation))
    try:
        result = subprocess.run(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, timeout=timeout, check=True)
        reply = json.loads(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError) as exc:
        # Do not copy subprocess output or upstream connection exceptions into
        # board posts; transport diagnostics can contain secret material.
        raise GatewayError(f'Hermes gateway {operation} failed ({type(exc).__name__})') from None
    if (not isinstance(reply, dict) or type(reply.get('running')) is not bool
            or (reply.get('execution_generation') is not None
                and (type(reply['execution_generation']) is not int or reply['execution_generation'] < 0))
            or (reply['running'] and reply.get('execution_generation') is None)):
        raise GatewayError(f'Hermes gateway {operation} returned an invalid response')
    return reply


async def _project(client, operation, sid, generation, rpc_error):
    """Never expose the stored history or use an unrelated turn's generation."""
    try:
        snapshot = await client.rpc('session.resume', session_id=sid, omit_messages=True)
    except rpc_error as exc:
        if str(exc) == 'not_found':
            return {'running': False, 'execution_generation': None}
        raise
    if snapshot.get('stored_session_id') != sid:
        raise GatewayError('Hermes gateway resolved a different session')
    running, current = snapshot['running'], snapshot['execution_generation']
    if type(running) is not bool or type(current) is not int or current < 0:
        raise GatewayError('Hermes gateway returned an invalid session snapshot')
    result = {'running': running, 'execution_generation': current}
    if operation == 'inspect':
        # A resumed session can already be running (for example, a prior
        # viewer detached). Only a matching started admission belongs to us.
        for admission in snapshot.get('pending', ()):
            if (admission.get('status') == 'started' and admission.get('execution_generation') == current
                    and isinstance(admission.get('text'), str)):
                result['prompt_sha256'] = prompt_digest(admission['text'])
                break
    elif running and current == generation:
        try:
            response = await client.rpc('session.interrupt', session_id=sid, execution_generation=generation)
        except rpc_error as exc:
            if str(exc) == 'stale_generation':
                return {'running': False, 'execution_generation': generation}
            raise
        if response['execution_generation'] != generation:
            raise GatewayError('Hermes gateway returned a different interrupt generation')
        result['running'] = response['execution_state'] == 'running'
    return result


async def _local_rpc(profile, operation, sid, generation):
    from hermes_cli.profiles import resolve_profile_env

    # Same profile resolution as `hermes -p`. This process is disposable; no
    # import-time Hermes profile state can leak into another resident's call.
    os.environ['HERMES_HOME'] = resolve_profile_env(profile)
    from hermes_cli.gateway_client import GatewayClientError, connect_gateway
    from hermes_cli.gateway_runtime import attachable, discover_gateway_endpoint, gateway_profile_home

    home = gateway_profile_home(os.environ['HERMES_HOME'])
    discovery = discover_gateway_endpoint(home, timeout=1)
    if discovery.state == 'absent':
        return {'running': False, 'execution_generation': None}
    if not attachable(discovery):
        raise GatewayError('local Hermes gateway is not attachable')
    # Pass the existing endpoint: Hermes mints its same-UID ticket and opens
    # /api/ws. Never start an owner or use a remote override for a stop.
    async with connect_gateway(endpoint=discovery.endpoint) as client:
        return await _project(client, operation, sid, generation, GatewayClientError)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile')
    parser.add_argument('operation', choices=('inspect', 'interrupt'))
    parser.add_argument('sid')
    parser.add_argument('generation', nargs='?', type=int)
    args = parser.parse_args(argv)
    if not PROFILE.fullmatch(args.profile) or not SESSION.fullmatch(args.sid):
        parser.error('invalid profile or session ID')
    if args.operation == 'interrupt':
        if args.generation is None or args.generation < 0:
            parser.error('interrupt requires a nonnegative execution generation')
    elif args.generation is not None:
        parser.error('inspect does not take an execution generation')
    try:
        result = asyncio.run(_local_rpc(args.profile, args.operation, args.sid, args.generation))
    except Exception as exc:
        print(f'Hermes gateway {args.operation} failed ({type(exc).__name__})', file=sys.stderr)
        return 1
    print(json.dumps(result))
    return 0


if __name__ == '__main__':
    sys.exit(main())
