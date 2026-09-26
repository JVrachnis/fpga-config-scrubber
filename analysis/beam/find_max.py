import operator
import csv

input_file = csv.DictReader(open("test1_output2.csv"))
flag=True
for row in input_file:
    r = dict(row)
    if flag:
        flag=False
        max_count=[0]*len(r)
        max=['']*len(r)
    value = [row[k] for k in r]
    for i,col in enumerate(value):
        if max_count[i] < len(col):
            max_count[i]=len(col)
            max[i]=col
print(max_count)
print(max)
