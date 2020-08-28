#!/usr/bin/env python3

'''\
json-rpc server
===============

This is json-rpc server for call python function.

USAGE:

   $ cat << EOF | curl -X POST -H "Content-Type: application/json" --data @- http://localhost:4000/
   {
     "jsonrpc": "2.0",
     "method": "call_obj",
     "params": [
       {
         "cwd": "~",
         "module": "os",
         "func": "getcwd",
         "params": {
         }
       }
     ],
     "id": 1
   }
   EOF

'''

from datetime import datetime
from jsonrpc import JSONRPCResponseManager, dispatcher
from .jsonrpcdummy import call_by_jsonrpc
from werkzeug.serving import run_simple
from werkzeug.wrappers import Request, Response
import json
import sys
import logging

logging.basicConfig(stream=sys.stderr, format='%(asctime)s:%(message)s', level=logging.DEBUG)
logger = logging.getLogger()

# add json encoder handler
json.JSONEncoder.default = lambda self,obj: (obj.isoformat() if isinstance(obj, datetime) else None)

@dispatcher.add_method
def call_obj(*kwlist):
    obj = kwlist[0]
    logger.info(kwlist)
    ret = call_by_jsonrpc(obj)
    logger.debug(ret)
    return ret

@Request.application
def application(request):
    logger.debug(request.data)
    response = JSONRPCResponseManager.handle(
        request.get_data(cache=False, as_text=True), dispatcher)
    return Response(response.json, mimetype='application/json')

def get_parser():
    import argparse
    parser = argparse.ArgumentParser(description='json rpc server')
    parser.add_argument('-a', '--addr', help='address to bind', default='localhost')
    parser.add_argument('-p', '--port', help='port(default: 4000)', default=4000, type=int)
    return parser

if __name__ == '__main__':
    args = get_parser().parse_args()
    run_simple(args.addr, args.port, application)
