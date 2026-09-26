import re
from os.path import isfile,basename
def get_file_paths(paths):
    file_paths=[]
    for path in paths:
        if(isfile(path)):
            file_paths.append(path)
    return file_paths

def read_file(file_path,mode=''):
    file = open(file_path,'r'+mode)
    data = file.read()
    file.close()
    return data

def find_timeTag(s):
    filename = basename(s)
    return re.findall('-(\d+?\.\d+?)\.',filename)[-1]

def is_readbackCapture(s):
    filename = basename(s)
    return bool(re.match('.*readbackCapture-\d+\.\d+\..*$',filename))
