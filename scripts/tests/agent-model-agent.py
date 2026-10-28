#!/usr/bin/env python3
"""Local ACP fixture for model switching. No tools, model calls, network or credentials.

Each adapter reports its own models. calls.jsonl records method names only, so selecting
and undoing can be checked for the absence of session/prompt.
"""
import argparse
import json
import pathlib
import sys
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--kind', choices=['source', 'target'], required=True)
parser.add_argument('--store', type=pathlib.Path, required=True)
parser.add_argument('--project', required=True)
parser.add_argument('--reject-unsent-load', action='store_true')
parser.add_argument('--model-switch', action='store_true')
args = parser.parse_args()
args.store.mkdir(parents=True, exist_ok=True)
source = args.kind == 'source'
current = 'model-source' if source else 'model-target'
state = {}


def option(identifier, category, value, choices):
    return dict(id=identifier, name=identifier.title(), category=category, type='select',
                currentValue=state.get(identifier, value),
                options=[dict(value=v, name=n) for v, n in choices])


def options():
    models = [('haiku', 'Haiku 5.5'), ('sonnet', 'Sonnet 5.5'), ('opus', 'Opus 5.5')] if source else [
        ('gpt-6.1-sol', '6.1 Sol'), ('gpt-6-astra', '6 Astra'), ('gpt-6-sol', '6 Sol'),
        ('gpt-6-luna', '6 Luna'), ('gpt-5.6-sol', '5.6 Sol')]
    levels = [('default', 'Manual'), ('acceptEdits', 'Accept edits'), ('auto', 'Auto'),
              ('bypassPermissions', 'Bypass permissions')] if source else [
        ('read-only', 'Read only'), ('workspace-write', 'Workspace write'), ('agent', 'Auto review'),
        ('agent-full-access', 'Full access')]
    mode_file = args.store / 'default-mode'
    initial_mode = mode_file.read_text().strip() if mode_file.exists() else levels[0][0]
    return ([dict(option('fast', 'model_config', 'off', [('off', 'Off'), ('on', 'On')]), name='Fast mode')] if args.model_switch else []) + [option('model', 'model', models[0][0], models),
            option('effort', 'thought_level', 'low', [(v, v.title()) for v in ['default', 'low', 'medium', 'high', 'xhigh', 'max']]),
            option('mode', 'mode', initial_mode, levels)]


def send(message):
    print(json.dumps(dict(jsonrpc='2.0', **message)), flush=True)


def update(text, role='agent_message_chunk'):
    send(dict(method='session/update', params=dict(sessionId=current,
              update=dict(sessionUpdate=role, content=dict(type='text', text=text)))))


for line in sys.stdin:
    message = json.loads(line)
    if 'id' not in message or 'method' not in message:
        continue
    identifier, method = message['id'], message['method']
    params = message.get('params', {})
    with (args.store / 'calls.jsonl').open('a') as log:
        log.write(json.dumps(dict(method=method)) + '\n')
    result = {}
    if method == 'initialize':
        result = dict(protocolVersion=1, agentInfo=dict(name=args.kind, version='1'), authMethods=[],
                      agentCapabilities=dict(loadSession=True, sessionCapabilities=dict(list={}, close={})))
    elif method == 'session/list':
        result = dict(sessions=[dict(sessionId='model-source', cwd=args.project,
                      title='Keep edited messages in place', updatedAt='2026-10-26T02:00:00Z')] if source else [])
    elif method in ('session/new', 'session/load'):
        current = params.get('sessionId', f'{args.kind}-{uuid.uuid4()}')
        if method == 'session/load' and args.reject_unsent_load:
            send(dict(id=identifier, error=dict(code=-32602, message='This unsent conversation was never saved')))
            continue
        if method == 'session/load':
            update('Keep edited messages in place.', 'user_message_chunk')
            update('The queue now preserves its order. Tests cover editing, moving and sending a queued message.')
        result = dict(configOptions=options())
        if method == 'session/new':
            result['sessionId'] = current
    elif method == 'session/set_config_option':
        state[params['configId']] = params['value']
        result = dict(configOptions=options())
    elif method == 'session/prompt':
        record = args.store / 'context-deliveries.json'
        delivered = json.loads(record.read_text()) if record.exists() else []
        delivered.append(any('task-continuation' in part.get('text', '') for part in params.get('prompt', [])))
        record.write_text(json.dumps(delivered))
        update('Received your explicit message. The draft stayed with this task.')
        result = dict(stopReason='end_turn')
    send(dict(id=identifier, result=result))
