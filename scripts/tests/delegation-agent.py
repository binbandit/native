#!/usr/bin/env python3
"""Local ACP fixture for delegated admission. No tools or provider calls."""
import json
import pathlib
import sys
import time
import uuid

root = pathlib.Path(sys.argv[1])
states = {}


def options(session):
    state = states[session]
    return [dict(id=category, name=category, category=category, type='select',
                 currentValue=state[category], options=[dict(value=v, name=v) for v in values])
            for category, values in [('model', ['alpha', 'beta']), ('mode', ['default', 'acceptEdits'])]]


for line in sys.stdin:
    message = json.loads(line)
    method = message.get('method')
    params = message.get('params', {})
    with (root / 'calls.jsonl').open('a') as log:
        log.write(json.dumps(dict(method=method, params=params)) + '\n')
    if 'id' not in message or method is None:
        continue
    result = {}
    if method == 'initialize':
        result = dict(protocolVersion=1, authMethods=[], agentCapabilities=dict(
            sessionCapabilities=dict(close={})))
    elif method == 'session/new':
        session = str(uuid.uuid4())
        states[session] = dict(model='alpha', mode='default')
        result = dict(sessionId=session, configOptions=options(session))
    elif method == 'session/set_config_option':
        session = params['sessionId']
        if params['value'] == 'beta':
            (root / 'preparing').touch()
            while not (root / 'release').exists():
                time.sleep(0.01)
        states[session][params['configId']] = params['value']
        result = dict(configOptions=options(session))
    elif method == 'session/prompt':
        result = dict(stopReason='end_turn')
    print(json.dumps(dict(jsonrpc='2.0', id=message['id'], result=result)), flush=True)
