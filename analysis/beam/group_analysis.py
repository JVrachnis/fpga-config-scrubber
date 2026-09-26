from itertools import combinations
from collections import OrderedDict
import operator
import csv

input_file = csv.DictReader(open("test1__groups.readback_capture=False.block_type=CLB.is_angled=False.csv"))

accept_values=[('minor_address','26')]
extetion_name='.'+'.'.join([str(k)+'='+str(v) for k,v in accept_values]+['csv'])
base_name='column_analysis_cern'
def is_row_accepted(row,accept_values):
	d={}
	for k,v in accept_values:
		if k in d and d[k]:
			continue
		d[k]=(row[k]==v)
	return all(d[k] for k in d)


test=OrderedDict()
data_dict={}
alldata=[]
for row in input_file:
    key = row['pattern']
    if not key in test: test[key]=[0]*76;
    test[key][75]+=1;
    if not is_row_accepted(row,accept_values):continue;


    key2 = int(row['column_address'])
    test[key][key2]+=1;
    test[key][74]+=1;

test = OrderedDict(sorted(test.items(), key = lambda i: i[1][75],reverse=True))


test.update({'column address':list(range(0,108))+['total']})
test.move_to_end('column address', last=False)

with open(base_name+extetion_name, "w") as outfile:
   writer = csv.writer(outfile)
   writer.writerow(test.keys())
   writer.writerows(zip(*test.values()))
test2=OrderedDict()

for k in test:
	test2[k]=[]
	for i,v in enumerate(test[k]):
		if v != 0:
			test2[k].append(i)

with open(base_name+'_list'+extetion_name, "w") as outfile:
   writer = csv.writer(outfile)
   writer.writerows(zip(test2.keys(),test2.values()))
