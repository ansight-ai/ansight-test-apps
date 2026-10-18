#!/usr/bin/env python3
"""Verify a fresh harness run using only retained artifacts, including after a host restart."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

REPORT = '{"schema":"ansight.artifact-harness/v1","message":"Published from the app — café 🚀","value":42}'.encode('utf-8')
BINARY = bytes(index % 251 for index in range(131089))


def cli(*arguments):
    result = subprocess.run(['ansight', *arguments, '--json'], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify(session_id):
    collection = cli('session', 'artifacts', session_id, '--limit', '10000')
    require(collection['totalCount'] == len(collection['items']), 'Artifact listing is truncated')
    snapshots = [item for item in collection['items'] if item['rootAlias'] == 'artifact-harness']
    require(Counter(item['relativePath'] for item in snapshots) == {'report': 3, 'binary': 1},
            'Expected three reports and one binary, with no invalid or cancelled artifacts')
    require(len({item['snapshotId'] for item in snapshots}) == 4, 'Snapshot IDs must be distinct')
    verified = []
    with tempfile.TemporaryDirectory(prefix='ansight-artifact-harness-') as temporary:
        for index, snapshot in enumerate(snapshots):
            require(snapshot['source'] == 'ansight.app.artifacts', 'Unexpected artifact source')
            require(not snapshot['truncated'] and snapshot['fileCount'] == 1, 'Snapshot must contain one complete file')
            require(len(snapshot['entries']) == 1, 'Snapshot must contain exactly one entry')
            entry = snapshot['entries'][0]
            report = snapshot['relativePath'] == 'report'
            expected = REPORT if report else BINARY
            require(entry['mimeType'] == ('application/json' if report else 'application/octet-stream'), 'MIME type changed')
            require(entry['name'] == ('report.json' if report else 'fixture.bin'), 'Filename changed')
            destination = Path(temporary) / str(index)
            cli('session', 'artifact', 'export', session_id, '--snapshot-id', snapshot['snapshotId'],
                '--path', entry['snapshotRelativePath'], '--output', str(destination))
            actual = destination.read_bytes()
            require(actual == expected, f"Content mismatch in {snapshot['snapshotId']}")
            require(entry['sizeBytes'] == len(actual) == snapshot['byteCount'], 'Retained byte lengths disagree')
            verified.append({'snapshotId': snapshot['snapshotId'], 'artifactId': snapshot['relativePath'],
                             'bytes': len(actual), 'sha256': hashlib.sha256(actual).hexdigest()})
    return {'sessionId': session_id, 'passed': True, 'artifacts': verified}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('session_ids', nargs='+', help='Session IDs from fresh artifacts.publish test runs')
    args = parser.parse_args()
    print(json.dumps({'sessions': [verify(session) for session in args.session_ids]}, indent=2))
