#!/usr/bin/env python3
"""Test-only capture reader. Never dispatches or mutates recovery state."""
import hashlib
import json
import re
from pathlib import Path
import sys

def check(ok, why):
    if not ok:
        raise ValueError(why)

def read(path):
    return json.loads(Path(path).read_text())

def events(path):
    raw = Path(path).read_text()
    check(raw.endswith('\n'), 'incomplete JSONL')
    rows = [json.loads(line) for line in raw.splitlines()]
    check(rows and all(isinstance(x, dict) for x in rows), 'invalid events')
    return rows

def rejection(path, model):
    rows = events(path)
    if len(rows) == 5:
        check(rows[1] == {'type': 'item.completed', 'item': {
            'id': 'item_0', 'type': 'error', 'message':
            f'Model metadata for `{model}` not found. Defaulting to fallback metadata; '
            'this can degrade performance and cause issues.'}}, 'metadata warning mismatch')
        rows.pop(1)
    check([x.get('type') for x in rows] ==
          ['thread.started', 'turn.started', 'error', 'turn.failed'], 'unknown rejection sequence')
    expected = {'type': 'error', 'status': 400, 'error': {
        'type': 'invalid_request_error',
        'message': f"The '{model}' model is not supported when using Codex with a ChatGPT account."}}
    check(json.loads(rows[2]['message']) == expected and
          json.loads(rows[3]['error']['message']) == expected, 'model/error mismatch')

def verify(path, guided=True):
    path = Path(path)
    data = read(path)
    base = path.parent
    def file(name):
        p = (base / name).resolve()
        check(p.is_relative_to(base.resolve()) and p.is_file(), 'missing/outside capture')
        return p
    check(data['schemaVersion'] == 2, 'unsupported schema')
    check(data['guided'] is guided and data['shellReplay'] is (not guided), 'capture provenance')
    check(data['kind'] in ('Agent', 'Task'), 'kind')
    success = data['scenario'] == 'success'
    check(data['scenario'] in ('success', 'interrupted'), 'scenario')
    count = 2 if success else 1
    check(data['dispatches'] == count == len(data['invocations']), 'dispatch count')
    check(len(set(data['invocations'])) == count, 'duplicate invocation')
    calls = [read(file(p)) for p in data['invocations']]
    template = data['templateArgv']
    check(template.count('{MODEL}') == 1, 'model slot')
    first = calls[0]
    for call in calls:
        check(call['unitKey'] == data['unitKey'] and call['role'] == data['role'], 'unit/role')
        for key in ('cli', 'tier', 'mechanism', 'provider'):
            check(call[key] == first[key], 'selection drift')
        check(call['argv'] == [call['model'] if a == '{MODEL}' else a for a in template], 'argv mismatch')
        for flag in ('--json', '--skip-git-repo-check'):
            check(call['argv'].count(flag) == 1, 'flags')
        check(file(call['prompt']).read_bytes() == file(first['prompt']).read_bytes(), 'prompt changed')
        file(call['stderr']).read_bytes()
    check(first['exitCode'] == 1, 'initial exit')
    rejection(file(first['stdoutJsonl']), first['model'])
    shots = {k: read(file(v)) for k, v in data['snapshots'].items()}
    normal = lambda s: {k: v for k, v in s.items() if k != 'modelRecovery'}
    before = shots['before']
    def other_episodes(state):
        return {k: value for k, value in state.get('modelRecovery', {}).get('episodes', {}).items()
                if k != data['episodeKey']}
    for state in shots.values():
        check(other_episodes(state) == other_episodes(before), 'unrelated recovery episode changed')
    for key in ('afterRejection', 'afterReservation'):
        check(normal(shots[key]) == normal(before), 'normal state changed before work')
    def episode(shot):
        e = shots[shot]['modelRecovery']['episodes'][data['episodeKey']]
        check(e['unitKey'] == data['unitKey'], 'episode unit')
        fingerprint = e['selectionFingerprint']
        check(isinstance(fingerprint, str) and re.fullmatch('[a-f0-9]{64}', fingerprint),
              'invalid episode fingerprint')
        check(fingerprint == shots['afterRejection']['modelRecovery']['episodes'][
            data['episodeKey']]['selectionFingerprint'], 'episode fingerprint changed')
        if 'failedModel' in e:
            check(e['failedModel'] == first['model'], 'episode failed model mismatch')
        if 'selectedModel' in e:
            if shot == 'afterRejection':
                check(e['selectedModel'] == first['model'], 'rejected model mismatch')
            elif success:
                check(e['selectedModel'] == calls[1]['model'], 'retry model mismatch')
            else:
                check(isinstance(e['selectedModel'], str) and e['selectedModel'] and
                      e['selectedModel'] != first['model'], 'reserved model is not a replacement')
        check(type(e['choiceQueries']) is int and 0 <= e['choiceQueries'] <= 1, 'query count')
        check(e['choiceQueries'] == data['choiceQueries'], 'query mismatch')
        return e
    rejected = episode('afterRejection')
    reserved = episode('afterReservation')
    check(rejected['status'] == 'awaiting_choice' and rejected['retryReservations'] == 0 and
          reserved['retryReservations'] == 1 and
          reserved['status'] == 'retry_reserved', 'reservation counters/status')
    if success:
        second = calls[1]
        check(second['model'] != first['model'] and second['exitCode'] == 0, 'retry selection/exit')
        rows = events(file(second['stdoutJsonl']))
        check([r['type'] for r in rows[:2]] == ['thread.started', 'turn.started'] and
              rows[-1]['type'] == 'turn.completed' and not any(
            x['type'] in ('error', 'turn.failed') for x in rows), 'retry not successful')
        artifact = file(data['artifact']['path'])
        check(artifact.stat().st_size > 0 and hashlib.sha256(artifact.read_bytes()).hexdigest() ==
              data['artifact']['sha256'], 'artifact mismatch')
        expected = normal(before)
        if data['kind'] == 'Agent' and data['role'] == 'task-planner':
            check(expected['phase'] == 'design', 'planner initial phase')
            expected.update(phase='tasks', awaitingApproval=True)
        else:
            expected['taskIndex'] += 1
        check(normal(shots['afterSuccess']) == expected, 'unexpected success state')
        resolved = episode('afterSuccess')
        check(resolved['status'] == 'resolved' and resolved['retryReservations'] == 1, 'unresolved success')
        check(shots['afterRestart'] == shots['afterSuccess'], 'restart changed success')
    else:
        check(shots['afterRestart'] == shots['afterReservation'], 'restart changed reservation')
        hook = file(data['hookAfterRestart']).read_text()
        check('Recovery Episode Pending' in hook and 'Continue spec' not in hook,
              'restart hook did not block')

if __name__ == '__main__':
    try:
        if len(sys.argv) == 3 and sys.argv[1] == '--evidence':
            for name, kind in [('agent.json', 'Agent'), ('task.json', 'Task')]:
                path = Path(sys.argv[2]) / name
                check(read(path)['kind'] == kind, 'delegation kind')
                verify(path)
            print('PASS: guided captures checked; no provider availability claimed')
        else:
            rejection(Path(__file__).parent / 'fixtures/model-recovery/positive-rejection.jsonl', 'fixture-model-a')
            print('PASS: synthetic fixture, not guided integration or provider evidence')
    except (ValueError, KeyError, TypeError, OSError, IndexError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
