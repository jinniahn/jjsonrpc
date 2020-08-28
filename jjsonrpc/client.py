'''\

Processing Json Commmand
========================

json 형태의 명령을 실행한다. 지정한 파이썬 함수를 실행한다.

Options:
  - path : sys.path에 등록할 경로
  - module : 함수가 있는 모듈 이름
  - func : 실행할 함수
  - cwd : 명령을 수행할 디렉토리
  - params: 함수에 전달할 파라미터 리스트

USAGE:

  echo '{"path": "/", "module":"os", "func":"getcwd", "cwd": "/" }' | python3 -m jjsonrpc.client -
'''

import importlib
import json
import os
import os.path
import random
import sys

from .elisp import *

# logging
import logging
logger = logging.getLogger()

loaded_modules = {}

class SysPathScope:
    "sys.path 업데이트 스코프"
    
    def __init__(self, path):
        self.is_updated = False
        self.path = None
        if path:
            self.path = os.path.expanduser(path)
    def __enter__(self):
        if self.path and os.path.exists(self.path):
            print('enter', self.path)
            sys.path.insert(0, self.path)
            self.is_updated = True

    def __exit__(self, exc_type, exc_value, traceback):
        if self.is_updated:
            del sys.path[0]

class CurDirectoryScope:
    "현재 Directory 변경 스코프"

    def __init__(self, cwd):
        self.cwd = os.path.expanduser(cwd) if cwd else None
        self.old = None

    def __enter__(self):
        if self.cwd and os.path.exists(self.cwd):
            self.old = os.getcwd()
            os.chdir(self.cwd)
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        if self.old:
            os.chdir(self.old)
            
def handle_resource(params):
    '''params에 간접 방식으로 지정된 리소스를 불러온다.

    형식:
       - file:    file:<path>
    '''

    for idx, param in enumerate(params):
        if isinstance(param, str) and param.startswith('file:'):
            fname = param[5:]
            if os.path.exists(fname):
                with open(fname) as f:
                    params[idx] = f.read()
                os.unlink(fname)
    return params

def call_by_jsonrpc(obj):
    'json 명령을 실행'

    global loaded_modules

    ret = {}

    with CurDirectoryScope(obj.get('cwd')):
        try:
            # 모듈 처리
            with SysPathScope(obj.get('path')):
                if obj.get('module', None):
                    m = importlib.import_module(obj['module'])
        
                    m_path = 'not_exists'
                    if hasattr(m, '__file__'):
                        m_path = m.__file__

                    # 사용하는 모듈이 업데이트 되었는지 확인
                    if os.path.exists(m_path):
                        if m_path not in loaded_modules:
                            # update mtime
                            loaded_modules[m_path] = os.path.getmtime(m_path)
                        
                        is_updated = m_path in loaded_modules and loaded_modules[m_path] != os.path.getmtime(m_path)
                        if is_updated:
                            importlib.reload(m)
                            loaded_modules[m_path] = os.path.getmtime(m_path)
                else:
                    # 지정된 모듈이 없으면 builtins
                    m = sys.modules['builtins']

                # 함수 실행
                func = getattr(m, obj['func'], None)
                if func:
                    if 'params' in obj and obj['params']:
                        # 파라미터 처리
                        params = handle_resource(obj['params'])
                        if isinstance(params, list):
                            ret['result'] = func(*obj['params'])
                        else:
                            ret['result'] = func(obj['params'])
                    else:
                        ret['result'] = func()
                else:
                    raise Exception('there is no function : ' + obj['func'])

        except Exception as e:
            # 에러가 발생
            ret['error'] = str(e)
            from io import StringIO
            import traceback
            log = StringIO()
            traceback.print_exc(file=log)
            logger.debug(log.getvalue())
    return ret

def run_jsonrpc(server_url, module, func, params=[]):
    import requests
    headers = {'content-type': 'application/json'}
    payload = {
        "method": "call_obj",
        "params": [{"module": module, "func": func, "params":params}],
        "jsonrpc": "2.0",
        "id": random.randint(0, 10000000),
    }

    return requests.post(server_url, data=json.dumps(payload), headers=headers).json()

def get_parser():
    import argparse
    parser = argparse.ArgumentParser(description='json rpc call dummy')
    parser.add_argument('file', type=argparse.FileType('r'))
    return parser

def main():
    args = get_parser().parse_args()

    jsonstr = args.file.read()
    obj = json.loads(jsonstr)
    ret = call_by_jsonrpc(obj)
    ret = to_lisp(ret)
    print(ret)

if __name__ == '__main__':
    main()
