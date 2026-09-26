from itertools import combinations
from collections import OrderedDict
import operator
import csv

input_file = csv.DictReader(open("temp/CERN2018/CERN2018_UPSETS.csv"))
accept_values=[('block_type','CLB'),('is_angled','True')]#
def is_row_accepted(row,accept_values):
	d={}
	for k,v in accept_values:
		if k in d and d[k]:
			continue
		d[k]=(row[k]==v)
	return all(d[k] for k in d)
test={}
data_dict={}
alldata=[]
for row in input_file:

	key = row['time_tag']

	if not is_row_accepted(row,accept_values):
		continue
	if row['masked_bit']=='1' and( not 'Latch' in row['specific_logic']):
		continue
	if 'Latch' in row['specific_logic']:
		print(row)
	key2 = int(row['frame_index'])
	if not key in test:
		test[key]={}

	value=((int(row['bit_frame']),int(row['frame_address'],16),int(row['golden_bit_value']),int(row['masked_bit'])),row)

	if (key2 in test[key]):
		test[key][key2].append(value)
	else:
		test[key][key2]=[value]
	alldata.append(row)
	data_dict[value[0]]=value[1]

first_row = alldata[0]

errors_per_time_tag={}

for key in test:
	t= test[key]
	for k in t:
		for v in t[k]:
			value=(k,)+v[0]
			if key in errors_per_time_tag:
				errors_per_time_tag[key].append(value)
			else:
				errors_per_time_tag[key]=[value]
distances={}

for time_tag in test:
	frames=test[time_tag]


	for frame in frames:
		distances_per_frame=[]
		if len(frames[frame])!=2:
			continue
		l=[f[0][0] for f in frames[frame]]

		l.sort()
		prev_i=None
		for item in l:
			if prev_i:
				distances_per_frame.append(abs(item-prev_i))
				prev_i=item
			else:
				prev_i=item
		if tuple(distances_per_frame) in distances:
			distances[tuple(distances_per_frame)]+=1
		else:
			distances[tuple(distances_per_frame)]=1
sorted_distances = sorted(distances.items(), key=operator.itemgetter(1))
for d in sorted_distances:
    print(d)
