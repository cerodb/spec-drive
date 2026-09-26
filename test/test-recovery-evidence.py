#!/usr/bin/env python3
"""Synthetic reader tests, not a guided coordinator or recovery dispatcher."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location('evidence', Path(__file__).with_name('verify-recovery-evidence.py'))
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)

class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.put('prompt', 'synthetic prompt')
        self.put('stderr', '')
        self.put('reject.jsonl', (Path(__file__).parent / 'fixtures/model-recovery/positive-rejection.jsonl').read_text())
        self.put('success.jsonl', '{"type":"thread.started"}\n{"type":"turn.started"}\n{"type":"turn.completed"}\n')
        self.put('artifact', '# Synthetic tasks\n- [ ] 1.1 Fixture\n')
        self.template = ['codex', 'exec', '--json', '--skip-git-repo-check', '-m', '{MODEL}']
        self.data = dict(schemaVersion=2, guided=False, shellReplay=True, kind='Agent',
                         role='task-planner', scenario='success', unitKey='design/task-planner',
                         episodeKey='fixture', dispatches=2, choiceQueries=1,
                         templateArgv=self.template, invocations=['call0.json', 'call1.json'])
        for i, model in enumerate(['fixture-model-a', 'fixture-model-b']):
            self.put(f'call{i}.json', dict(unitKey=self.data['unitKey'], role='task-planner',
                cli='codex', tier='standard', mechanism='subprocess', provider='codex',
                model=model, argv=[model if a == '{MODEL}' else a for a in self.template],
                prompt='prompt', stderr='stderr', stdoutJsonl='reject.jsonl' if i == 0 else 'success.jsonl',
                exitCode=1 if i == 0 else 0))
        before = dict(name='fixture', basePath=str(self.root), phase='design', taskIndex=0,
                      taskIteration=1, globalIteration=1, awaitingApproval=False)
        self.data['snapshots'] = {}
        for name, status, retries in [('before', None, 0), ('afterRejection', 'awaiting_choice', 0),
                                       ('afterReservation', 'retry_reserved', 1),
                                       ('afterSuccess', 'resolved', 1), ('afterRestart', 'resolved', 1)]:
            state = copy.deepcopy(before)
            if status:
                state['modelRecovery'] = {'episodes': {'fixture': dict(unitKey=self.data['unitKey'],
                    selectionFingerprint='a'*64, status=status, choiceQueries=1, retryReservations=retries)}}
            if status == 'resolved':
                state.update(phase='tasks', awaitingApproval=True)
            self.put(name+'.json', state)
            self.data['snapshots'][name] = name+'.json'
        self.data['artifact'] = dict(path='artifact', sha256=hashlib.sha256((self.root/'artifact').read_bytes()).hexdigest())

    def put(self, name, data):
        (self.root/name).write_text(data if isinstance(data, str) else json.dumps(data))

    def run_check(self):
        self.put('capture.json', self.data)
        v.verify(self.root/'capture.json', guided=False)

    def mutate(self, name, key, value):
        data = v.read(self.root/name)
        data[key] = value
        self.put(name, data)

    def test_success(self):
        self.run_check()

    def test_interrupted(self):
        self.data.update(scenario='interrupted', dispatches=1, invocations=['call0.json'])
        self.put('afterRestart.json', v.read(self.root/'afterReservation.json'))
        self.put('hook.txt', 'Recovery Episode Pending')
        self.data['hookAfterRestart'] = 'hook.txt'
        self.run_check()
        self.put('hook.txt', 'Continue spec')
        with self.assertRaises(ValueError):
            self.run_check()

    def test_bad_captures(self):
        mutations = [
            lambda: self.data.update(dispatches=1),
            lambda: self.data.update(choiceQueries=0),
            lambda: self.data.update(invocations=['missing.json', 'call1.json']),
            lambda: self.put('reject.jsonl', '{"type":"thread.started"}\n'),
            lambda: self.put('reject.jsonl', '{"type":'),
            lambda: self.mutate('call0.json', 'model', 'wrong'),
            lambda: self.mutate('call1.json', 'argv', ['invented']),
            lambda: (self.put('changed', 'different'), self.mutate('call1.json', 'prompt', 'changed')),
            lambda: self.mutate('afterRejection.json', 'taskIndex', 1),
            lambda: self.mutate('afterRestart.json', 'globalIteration', 2),
            lambda: self.put('artifact', 'tampered'),
            lambda: self.mutate('call1.json', 'unitKey', 'other'),
        ]
        baseline = {p.name: p.read_bytes() for p in self.root.iterdir()}
        original = copy.deepcopy(self.data)
        for i, mutation in enumerate(mutations):
            with self.subTest(case=i):
                self.data = copy.deepcopy(original)
                for name, data in baseline.items():
                    (self.root/name).write_bytes(data)
                mutation()
                with self.assertRaises((ValueError, KeyError, OSError)):
                    self.run_check()

    def test_booleans_are_not_evidence(self):
        self.data = dict(guided=True, samePromptAndUnit=True, preservedAfterInitialRejection=True)
        with self.assertRaises(KeyError):
            self.run_check()

    def test_episode_models_and_identity(self):
        names = ('afterRejection', 'afterReservation', 'afterSuccess', 'afterRestart')
        for name in names:
            state = v.read(self.root/(name+'.json'))
            episode = state['modelRecovery']['episodes']['fixture']
            episode['failedModel'] = 'fixture-model-a'
            episode['selectedModel'] = 'fixture-model-a' if name == 'afterRejection' else 'fixture-model-b'
            self.put(name+'.json', state)
        self.run_check()
        baseline = {name: v.read(self.root/(name+'.json')) for name in names}
        cases = [('selectedModel', 'contradictory-model'), ('failedModel', 'wrong'),
                 ('selectionFingerprint', 'invalid'), ('selectionFingerprint', 'b'*64),
                 ('status', 'resolved')]
        for field, value in cases:
            with self.subTest(field=field, value=value):
                for name, state in baseline.items():
                    self.put(name+'.json', state)
                target = 'afterRejection' if field == 'status' else 'afterReservation'
                state = copy.deepcopy(baseline[target])
                state['modelRecovery']['episodes']['fixture'][field] = value
                self.put(target+'.json', state)
                with self.assertRaises(ValueError):
                    self.run_check()
        for name, state in baseline.items():
            changed = copy.deepcopy(state)
            changed['modelRecovery']['episodes']['fixture']['selectedModel'] = 'contradictory-model'
            self.put(name+'.json', changed)
        with self.assertRaises(ValueError):
            self.run_check()

    def test_unrelated_episode_preserved(self):
        for path in self.data['snapshots'].values():
            state = v.read(self.root/path)
            episodes = state.setdefault('modelRecovery', {}).setdefault('episodes', {})
            episodes['historical'] = {'status': 'archived', 'retryReservations': 1}
            self.put(path, state)
        self.run_check()
        state = v.read(self.root/'afterRejection.json')
        del state['modelRecovery']['episodes']['historical']
        self.put('afterRejection.json', state)
        with self.assertRaises(ValueError):
            self.run_check()

    def test_warning_and_work_event(self):
        rows = v.events(self.root/'reject.jsonl')
        warning = {'type': 'item.completed', 'item': {'id': 'item_0', 'type': 'error',
            'message': 'Model metadata for `fixture-model-a` not found. Defaulting to fallback metadata; this can degrade performance and cause issues.'}}
        rows.insert(1, warning)
        self.put('reject.jsonl', ''.join(json.dumps(x)+'\n' for x in rows))
        self.run_check()
        warning['item']['message'] = 'Wrong model metadata'
        self.put('reject.jsonl', ''.join(json.dumps(x)+'\n' for x in rows))
        with self.assertRaises(ValueError):
            self.run_check()
        rows[1] = {'type': 'item.started', 'item': {'type': 'command_execution'}}
        self.put('reject.jsonl', ''.join(json.dumps(x)+'\n' for x in rows))
        with self.assertRaises(ValueError):
            self.run_check()

if __name__ == '__main__':
    unittest.main()
