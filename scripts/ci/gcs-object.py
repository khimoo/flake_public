"""Read and write small GCS objects without requiring bucket listing."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib import parse, request
from urllib.error import HTTPError, URLError

BASE = 'https://storage.googleapis.com'
MAX_BYTES = 256 * 1024


class NoRedirect(request.HTTPRedirectHandler):
    # Never forward an Authorization header to a different endpoint.
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = request.build_opener(NoRedirect())


def access_token():
    result = subprocess.run(['gcloud', 'auth', 'print-access-token', '--quiet'],
                            stdout=subprocess.PIPE, text=True, check=True, timeout=45)
    token = result.stdout.strip()
    if not token or any(c.isspace() for c in token):
        raise ValueError('gcloud did not return an access token')
    return token


def split_uri(uri):
    match = re.fullmatch(r'gs://([a-z0-9][a-z0-9.-]{1,61}[a-z0-9])/([a-zA-Z0-9_./-]+)', uri)
    if not match or any(p in ('', '.', '..') for p in match[2].split('/')):
        raise ValueError('expected an exact gs://bucket/object URI')
    return match[1], match[2]


def generation_value(value, *, allow_zero=False):
    if not isinstance(value, str) or not re.fullmatch(r'[0-9]{1,20}', value):
        raise ValueError('invalid object generation')
    if not allow_zero and int(value) == 0:
        raise ValueError('generation zero is only valid as a write precondition')
    return value


def call(path, params, data=None):
    headers = {'Authorization': f'Bearer {access_token()}'}
    if data is not None:
        headers['Content-Type'] = 'application/json'
    req = request.Request(BASE + path + '?' + parse.urlencode(params), data=data, headers=headers)
    with OPENER.open(req, timeout=30) as response:
        payload = response.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise ValueError('object response exceeded the size limit')
    return payload


def read_object(uri, *, generation=None):
    bucket, key = split_uri(uri)
    params = {'alt': 'media'}
    if generation is not None:
        params['generation'] = generation_value(generation)
    return call(f'/storage/v1/b/{bucket}/o/{parse.quote(key, safe="")}', params)


def object_generation(uri):
    bucket, key = split_uri(uri)
    data = call(f'/storage/v1/b/{bucket}/o/{parse.quote(key, safe="")}', {'fields': 'generation'})
    return generation_value(json.loads(data)['generation'])


def put_object(uri, data, if_generation_match):
    bucket, key = split_uri(uri)
    if len(data) > MAX_BYTES:
        raise ValueError('object exceeds the upload size limit')
    return call(f'/upload/storage/v1/b/{bucket}/o', {
        'uploadType': 'media', 'name': key,
        'ifGenerationMatch': generation_value(if_generation_match, allow_zero=True),
    }, data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='op', required=True)
    get = commands.add_parser('get')
    get.add_argument('uri')
    get.add_argument('--generation')
    commands.add_parser('generation').add_argument('uri')
    put = commands.add_parser('put')
    put.add_argument('uri')
    put.add_argument('file', type=Path)
    put.add_argument('--if-generation-match', required=True)
    args = parser.parse_args(argv)
    try:
        if args.op == 'get':
            sys.stdout.buffer.write(read_object(args.uri, generation=args.generation))
        elif args.op == 'generation':
            print(object_generation(args.uri))
        else:
            with args.file.open('rb') as stream:
                put_object(args.uri, stream.read(MAX_BYTES + 1), args.if_generation_match)
    except HTTPError as exc:
        print(f'GCS {args.op} failed: HTTP {exc.code}', file=sys.stderr)
        return {404: 44, 412: 12}.get(exc.code, 1)
    except (ValueError, OSError, KeyError, URLError, subprocess.SubprocessError) as exc:
        print(f'GCS {args.op} failed: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
