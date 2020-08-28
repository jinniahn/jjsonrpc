import os
from setuptools import setup

setup(
    name = "jjsonrpc",
    version = "1.0",
    author = "jinsub ahn",
    author_email = "jinniahn@gmail.com",
    description = ("it provides json rpc to call python function"),
    license = "BSD",
    keywords = "jsonrpc",
    url = "https://github.com/jinniahn/jjsonrpc",
    packages=['jjsonrpc'],
    install_requires=[
        'json-rpc==1.12.1',
        'werkzeug',
        'requests'
    ],    
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Topic :: Utilities",
        "License :: OSI Approved :: BSD License",
    ],
)

