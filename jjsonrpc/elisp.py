import re

__all__ = ['to_lisp', 'sym']

class sym:
    def __init__(self, val):
        self.val = val

def to_lisp_str(obj, **kwlist):
    return '"{}"'.format(obj.replace("\\", "\\\\").replace('"', '\\\"'))

def to_lisp_list(obj, **kwlist):
    ret = []
    for i in obj:
        ret.append(to_lisp(i, **kwlist))
    return '( {} )'.format(' '.join(ret))

def to_lisp_dict(obj, **kwlist):
    ret = []
    for i in obj:
        ret.append(to_lisp(i, **kwlist))
        ret.append(to_lisp(obj[i], **kwlist))
    return '( {} )'.format(' '.join(ret))

def to_lisp_dict2(obj, **kwlist):
    ret = []
    for i in obj:
        ret.append(":" + i)
        ret.append(to_lisp(obj[i], **kwlist))
    return '( {} )'.format(' '.join(ret))

def to_lisp(obj, **kwlist):
    if isinstance(obj, list):
        ret = to_lisp_list(obj, **kwlist)
    elif isinstance(obj, tuple):
        ret = to_lisp_list(obj, **kwlist)
    elif isinstance(obj, str):
        ret = to_lisp_str(obj, **kwlist)
    elif isinstance(obj, dict):
        if 'dicttype' in kwlist and kwlist['dicttype'] == 'alist':
            ret = to_lisp_dict(obj, **kwlist)
        else:
            ret = to_lisp_dict2(obj, **kwlist)
    elif isinstance(obj, sym):
        ret = ':{}'.format(obj.val)
    elif isinstance(obj, int):
        ret = str(obj)
    elif isinstance(obj, float):
        ret = str(obj)
    else:
        ret = to_lisp_str(str(obj), **kwlist)
        
    return ret

def gen_autoload_defuns(fname):
    import os.path
    text = open(fname).read()

    tag = ';;;###autoload'
    defun_re = re.compile(r'\s*\(defun\s+(?P<name>[a-zA-Z0-9-_]+)\s*\((?P<params>.*?)\)\s+("(?P<comment>[^"]*?)")?\s+(\(interactive)?', re.M)

    def make_autoload(func, fname, help_str, active):
        fname = os.path.basename(fname).rsplit('.',1)[0]

        active = 't' if active else 'nil'
        
        if help_str:
            help_str = help_str.replace('"', '\\"')
            return '''
            (autoload '{} "{}" "{}" {})
            '''.strip().format(func, fname, help_str, active)
        else:
            return '''
            (autoload '{} "{}" nil {})
            '''.strip().format(func, fname, active)

    pos = text.find(tag)
    pos += len(tag)
    ret = []
    while pos != -1:
        m = defun_re.match(text[pos:pos+200])
        if m:
            func, params, _, help_str,active = m.groups()
            ret.append(make_autoload(func, fname, help_str, active))

        pos = text.find(tag, pos+len(tag))
        if pos != -1:
            pos += len(tag)

    return '\n'.join(ret)

def test():
    val = [ "asdf", { "1" : 'a', '2': 'b'} ]
    print(to_lisp(val, dicttype='plist'))

def test_gen_autoload_defuns():
    path = '/Users/jinni/.emacs.d/mylib/helm-english.el'
    print(gen_autoload_defuns(path))

if __name__ == '__main__':
    test_gen_autoload_defuns()

