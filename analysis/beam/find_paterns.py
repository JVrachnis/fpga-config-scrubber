from itertools import combinations
import operator
import random
import csv
import ast
min_valid_distance_count=10
input_file = csv.DictReader(open("test2_output_CLB_corrected.csv"))
errors_per_time_tag={}
for row in input_file:
	key = row['time_tag']
	#if row['readback_capture']=='False':
	#	continue
	if row['block_type']=='BRAM':
		continue
	value=(int(row['frame_index']),int(row['bit_frame']),int(row['frame_address'],16),int(row['golden_bit_value']))
	if key in errors_per_time_tag:
		errors_per_time_tag[key].append(value)
	else:
		errors_per_time_tag[key]=[value]
print('finished loading data')
distances={}
errors_with_distances={}
points_w_d_per_time_tag={}
for time_tag in errors_per_time_tag:

	errors_with_distances={}
	errors=errors_per_time_tag[time_tag]
	print(time_tag,len(errors))
	if len(errors)>1000:
		continue
	l=errors
	lc = combinations(l, 2)
	for item in lc:
		key = (item[0][0]-item[1][0],item[0][1]-item[1][1])
		if key[0]*key[1]>=0:
			key= (abs(key[0]),abs(key[1]))
		elif key[0]<0:
			k=key[0]/abs(key[0])
			key=(k*key[0],k*key[1])
		if key in distances:
			distances[key]+=1
		else:
			distances[key]=1
		if not item[0] in errors_with_distances:
			errors_with_distances[item[0]]={}
		error_key = item[0]
		value=errors_with_distances[error_key]
		if key in value:
			if not (item[1] in value[key]):
				errors_with_distances[error_key][key].append(item[1])
		else:
			errors_with_distances[error_key][key]=[item[1]]

		if not item[1] in errors_with_distances:
			errors_with_distances[item[1]]={}
		error_key = item[1]
		value=errors_with_distances[error_key]
		if key in value:
			if not (item[0] in value[key]):
				errors_with_distances[error_key][key].append(item[0])
		else:
			errors_with_distances[error_key][key]=[item[0]]

	points_w_d_per_time_tag[time_tag]=dict(errors_with_distances)
print('calculated distances')
sorted_distances = sorted(distances.items(), key=operator.itemgetter(1))
count={}
#for item in sorted_distances:
#	print (item)
with open('test2_distances_readback_clb.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_distances[::-1]:
		wr.writerow(sd)


final_distances={}
for distance in distances:
	if distances[distance]>=min_valid_distance_count:
		final_distances[distance]=distances[distance]
#print (final_distances)
paterns ={}
"""
sorted_distances = sorted(final_distances.items(), key=operator.itemgetter(1))
with open('final_distances.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_distances[::-1]:
		wr.writerow(sd)

for time_tag in list(points_w_d_per_time_tag.keys()):
	errors=points_w_d_per_time_tag[time_tag]
	for point in errors:
		legit_dists=list(set(errors[point].keys()).intersection(final_distances.keys()))
		if len(legit_dists)==0:
			continue
		for dist in legit_dists:
			for pnt in errors[point][dist]:
				if abs(point[2]-pnt[2])>1:
					print(point,pnt)
"""
for time_tag in list(points_w_d_per_time_tag.keys()):
	errors=points_w_d_per_time_tag[time_tag]
	groups=[]

	for point in errors:
		legit_dists=list(set(errors[point].keys()).intersection(final_distances.keys()))
		if len(legit_dists)==0:
			continue
		flag=False
		for i,group in enumerate(groups):
			if point in group:
				for dist in legit_dists:
					for pnt in errors[point][dist]:
						if pnt in group:
							continue
						groups[i].append(pnt)
				flag=True
				break
			for dist in legit_dists:
				for pnt in errors[point][dist]:
					if pnt in group:
						if point in group:
							continue
						groups[i].append(point)
						flag=True
						break
		for i,group in enumerate(groups):
			if point in group:
				for dist in legit_dists:
					for pnt in errors[point][dist]:
						if pnt in group:
							continue
						groups[i].append(pnt)
				flag=True
				break
		if flag:
			continue
		group=[point]
		for dist in legit_dists:
			for pnt in errors[point][dist]:
				group.append(pnt)
		groups.append(group)

	lc = combinations(groups, 2)
	for group in lc:
		if(group[0]==group[1]):
			continue
		if len(list(set(group[0]).intersection(group[1])))>0:
			print(group,'problem',time_tag)
	for group in groups:
		lx,ly,l1,l2= zip(*group)
		minx=min(lx)
		miny=min(ly)
		patern = []

		for pnt in group:
			patern.append((pnt[0]-minx,pnt[1]-miny,pnt[3]))
		if str(patern) in paterns:
			paterns[str(patern)]+=1
		else:
			paterns[str(patern)]=1
#	break
sorted_paterns = sorted(paterns.items(), key=operator.itemgetter(1))
with open('test2_paterns_readback_clb.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	for sd in sorted_paterns[::-1]:
		wr.writerow([sd[1]]+ast.literal_eval(sd[0]))
