from itertools import combinations
from collections import OrderedDict
import operator
import csv

input_file = csv.DictReader(open("./test1_groups.readback_captureFalse.block_typeCLB.is_angledFalse.csv"))

data=[]
prev_pattern=''
for row in input_file:
    key = (row['time_tag'],row['pattern'])

    if(prev_pattern==''):
        prev_pattern=row['pattern']

    if(prev_pattern!=row['pattern']):
        data=[]
    else:
        for d in data :
            if row['word_of_frame'] != d:
                print(row['word_of_frame'], d,row['pattern'])
        data.append(row['word_of_frame'])
