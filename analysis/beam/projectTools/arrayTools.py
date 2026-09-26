def split_array_by_length(array,length):
    return [ array[i:i+length] for i in range(0, len(array), length) ]#coped code
