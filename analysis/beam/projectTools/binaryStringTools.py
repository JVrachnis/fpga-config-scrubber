import string
def filter_binary(unFiltered_string):
    all=string.maketrans('','')
    nodigs=all.translate(all, '01')
    Filtered_string = unFiltered_string.translate(all, nodigs)
    return Filtered_string
class KeepOnlyBinary:
    def __init__(self, keep='01'):
        self.comp = dict((ord(c),c) for c in keep)
    def __getitem__(self, k):
        return self.comp.get(k)
    def translate(self,string):
        return string.translate(self.comp)
def binaryString_to_FrameArray(binaryString,frame_bit_size):
    from arrayTools import split_array_by_length
    frameArray = split_array_by_length(binaryString,frame_bit_size)
    return frameArray
def binaryString_to_rawBinary(string):
    rawBinary =  bytearray(b'')
    length = 101*32
    for i in range(0, len(string),length):
        rawBinary.extend(int(string[i:i+length],2).to_bytes(length//8, 'big'))
    return rawBinary
