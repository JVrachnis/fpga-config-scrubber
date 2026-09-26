from itertools import combinations
from collections import OrderedDict
import operator
import csv
import itertools

def multiple_on_column(pattern):
    for a, b in itertools.combinations(pattern, 2):
        if a[0]==b[0]:
            return True
    return False
def split_pattern(pattern):
    pattern_column={}
    for point in pattern:

        if point[0] in  pattern_column  :
            pattern_column[point[0]].append(point[1:])
        else:
            pattern_column[point[0]]=[point[1:]]
    return pattern_column
multiple_on_column_rows=[]
with open('temp/CERN2018/CERN2018_paterns.block_type=CLB.is_angled=False.csv') as csv_file:
    csv_reader = csv.reader(csv_file, delimiter=',')
    for row in csv_reader:


        key=row[0]
        times=row[1]
        pattern=[eval(pat) for pat in row[2:]]


        if multiple_on_column(pattern):
            t=[key,times]
            t.append(pattern)
            print(t)
            print(pattern)
            multiple_on_column_rows.append(t)
            continue
print(multiple_on_column_rows)
for row in multiple_on_column_rows:
    pattern=row[2]
    sp = split_pattern(pattern)
    flag=False
    for c in sp:

        if len(sp[c])>1:
            first_point=sp[c][0]
            for i,point in enumerate(sp[c][1:]):
                if (point[0] -first_point[0]) != (i+1):
                    flag=True
    print(row,flag)
