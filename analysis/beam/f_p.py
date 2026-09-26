from itertools import combinations
from collections import OrderedDict
import operator
import csv
max_errors_per_time_tag=50000
min_valid_distance_count=10
max_errors_per_frame=7
dont_count_set=True
input_file = csv.DictReader(open("temp/GSI2019/GSI2019_UPSETS.csv"))
errors_per_time_tag={}
#aterns_to_analize=[((0, 3, 1, 1),(3, 0, 0, 1)),((0, 3, 0, 1),(3, 0, 1, 1)),((0, 0, 0, 1),(0, 16, 0, 1),(0, 32, 0, 1)),((0, 0, 1, 1),(0, 16, 1, 1),(0, 32, 1, 1))]
#headers:
# time_tag,readback_capture,is_angled,golden_bit_value,frame_address,frame_index,block_type,
# top_bot,row_address,column_address,minor_address,word_of_frame,bit_word,bit_frame,
# masked_bit,masked_frame,essential_bit,non_essential_frame,logic_block,specific_logic,specific_logic_2
# time_tag,readback_capture,is_angled,golden_bit_value,frame_address,frame_index,block_type,top_bot,row_address,column_address,minor_address,word_of_frame,bit_word,bit_frame,masked_bit,masked_frame,essential_bit,non_essential_frame,logic_block,specific_logic,specific_logic_2
accept_values=[('block_type','CLB'),('masked_bit','0')]
base_name='temp/GSI2019/GSI2019'
extetion_name='.'+'.'.join([str(k)+'='+str(v) for k,v in accept_values]+['csv'])

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
with open(base_name+'_loaded_data'+extetion_name, 'w') as outfile:
    wr = csv.DictWriter(outfile, fieldnames=list(first_row))
    wr.writeheader()
    wr.writerows(alldata)
del alldata
print('finished loading data')

set_errors=[]
non_set_data=[]
non_set_data_dict={}
set_data=[]
for key in test:
	t= test[key]
	for k in t:
		if len(t[k])<=max_errors_per_frame or dont_count_set:

			for v in t[k]:
				value=(k,)+v[0]
				non_set_data.append(v[1])
				non_set_data_dict[(key,)+value]=v[1]
				if key in errors_per_time_tag:
					errors_per_time_tag[key].append(value)
				else:
					errors_per_time_tag[key]=[value]
		else:
			for v in t[k]:
				set_data.append(v[1])

if len(non_set_data)>0:
	first_row = non_set_data[0]
	with open(base_name+'_non_sets'+extetion_name, 'w') as outfile:
		wr = csv.DictWriter(outfile, fieldnames=list(first_row))
		wr.writeheader()
		wr.writerows(non_set_data)
del non_set_data

if len(set_data)>0:
	first_row = set_data[0]
	with open(base_name+'_sets'+extetion_name, 'w') as outfile:
		wr = csv.DictWriter(outfile, fieldnames=list(first_row))
		wr.writeheader()
		wr.writerows(set_data)

del set_data
print('removed and outputed sets')

distances={}
errors_with_distances={}
points_w_d_per_time_tag={}
for time_tag in errors_per_time_tag:
	errors_with_distances={}
	errors=errors_per_time_tag[time_tag]

	if len(errors)>max_errors_per_time_tag:
		continue

	l=errors
	lc = combinations(l, 2)
	for item in lc:
		key = (item[0][0]-item[1][0],item[0][1]-item[1][1])
		if key[0]*key[1]>=0:
			key= (abs(key[0]),abs(key[1]))
		elif key[0]<0:
			k=int(key[0]/abs(key[0]))
			key=(k*key[0],k*key[1])
		if key in distances:
			distances[key]+=1
		else:
			distances[key]=1
sorted_distances = sorted(distances.items(), key=operator.itemgetter(1))


with open(base_name+'_distances'+extetion_name, 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_distances[::-1]:
		wr.writerow(sd)
print('calculated distances')


del sorted_distances
final_distances={}
for distance in distances:
	if distances[distance]>=min_valid_distance_count:
		final_distances[distance]=distances[distance]
del distances
distances={}
address_anomalies=[]
for time_tag in errors_per_time_tag:
	errors_with_distances={}
	errors=errors_per_time_tag[time_tag]

	if len(errors)>max_errors_per_time_tag:
		continue
	l=errors
	lc = combinations(l, 2)
	for item in lc:
		key = (item[0][0]-item[1][0],item[0][1]-item[1][1])
		if key[0]*key[1]>=0:
			key= (abs(key[0]),abs(key[1]))
		elif key[0]<0:
			k=int(key[0]/abs(key[0]))
			key=(k*key[0],k*key[1])

		if key not in final_distances:
			continue
		if key in distances:
			distances[key]+=1
		else:
			distances[key]=1
		if (item[0][0]-item[1][0]!=item[0][2]-item[1][2]):
			key=(time_tag,item[0],item[1])
			address_anomalies.append(key)

		if item[0] in errors_with_distances:
			errors_with_distances[item[0]].append(item[1])
		else:
			errors_with_distances[item[0]]=[item[1]]

		if item[1] in errors_with_distances:
			errors_with_distances[item[1]].append(item[0])
		else:
			errors_with_distances[item[1]]=[item[0]]

	points_w_d_per_time_tag[time_tag]=dict(errors_with_distances)
print('pre calculated paterns')

sorted_distances = sorted(distances.items(), key=operator.itemgetter(1))
with open(base_name+'_distances_passed'+extetion_name, 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_distances[::-1]:
		wr.writerow(sd)

mbu_errors=[]
for key in points_w_d_per_time_tag:
	t= points_w_d_per_time_tag[key]
	for k in t:
		mbu_errors.append((key,)+k)

mbu_data=[]
sbu_data=[]
tmp = dict(non_set_data_dict)
for mbu in mbu_errors:
	mbu_data.append(non_set_data_dict[mbu])
	del tmp[mbu]
del mbu_errors
for key in tmp:
	sbu_data.append(tmp[key])
first_row = mbu_data[0]
with open(base_name+'_mbus'+extetion_name, 'w') as outfile:
    wr = csv.DictWriter(outfile, fieldnames=list(first_row))
    wr.writeheader()
    wr.writerows(mbu_data)
del mbu_data

first_row = sbu_data[0]
with open(base_name+'_sbus'+extetion_name, 'w') as outfile:
    wr = csv.DictWriter(outfile, fieldnames=list(first_row))
    wr.writeheader()
    wr.writerows(sbu_data)
del sbu_data
print('outputed mbus and sbus')
del errors_per_time_tag
del final_distances
paterns ={}
final_groups={}



with open(base_name+'_address_anomalies'+extetion_name, 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in address_anomalies:
		wr.writerow(sd)
print('found address anomalies')
analitical_group=[]
for time_tag in list(points_w_d_per_time_tag.keys()):
	errors=points_w_d_per_time_tag[time_tag]
	groups=[]

	for point in errors:

		if any(point in group for group in groups):
			i,group = next((i,set(group)) for i,group in enumerate(groups) if point in group)
			err =set(errors[point])
			groups[i]+=list(err-group)
			continue
		if any(len(set(errors[point]).intersection(group))>0 for group in groups):
			i,group = next((i,set(group)) for i,group in enumerate(groups) if len(set(errors[point]).intersection(group))>0)
			groups[i]+=[point]
			continue

		group=[point]+errors[point]

		groups.append(group)

	lc = combinations(groups, 2)
	for group in lc:
		if(group[0]==group[1]):
			continue
		if len(set(group[0]).intersection(group[1]))>0:
			print(group,'problem',time_tag)

	for group in groups:
		l = list(zip(*group))
		lx,ly=l[:2]
		minx=min(lx)
		miny=min(ly)
		patern = [(pnt[0]-minx,pnt[1]-miny,pnt[3],pnt[4]) for pnt in group]
		patern = sorted(patern)
		for g in group:
			data=non_set_data_dict[(time_tag,)+g]
			data['pattern']=hash(tuple(patern))
			data['pos_in_pattern']=(g[0]-minx,g[1]-miny)
			analitical_group.append(data)
		if tuple(patern) in paterns:
			paterns[tuple(patern)]+=1
		else:
			paterns[tuple(patern)]=1
		group = sorted(group)

		if tuple(group) in final_groups:
			final_groups[tuple(group)][0]+=1
			final_groups[tuple(group)][1].append(time_tag)
		else:
			final_groups[tuple(group)]=[1,[time_tag]]

print('found groups')
#	break
#sorted_final_groups = sorted(final_groups.items(), key=operator.itemgetter(1))
#for sd in sorted_final_groups:
#	print(sd)
sorted_paterns = sorted(paterns.items(), key=operator.itemgetter(1))
print(sorted_paterns[0])
with open(base_name+'_paterns'+extetion_name, 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_paterns[::-1]:

		wr.writerow([hash(sd[0]),sd[1]]+list(sd[0]))

first_row=analitical_group[0]
with open(base_name+'_groups'+extetion_name, 'w') as outfile:
    wr = csv.DictWriter(outfile, fieldnames=list(first_row))
    wr.writeheader()
    wr.writerows(analitical_group)
