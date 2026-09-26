import operator
import csv

input_file = csv.DictReader(open("test1_output.csv"))
errors_non_capture={}
errorscapture={}
for row in input_file:
	key = float(row['time_tag'])
	is_capture=row['readback_capture']=='True'
	r = dict(row)
	del r['time_tag']
	del r['readback_capture']
	value = [row[k] for k in r]
	value=','.join(value)
	if is_capture:
		if key in errorscapture:
			errorscapture[key].append(value)
		else:
			errorscapture[key]=[value]
	else:
		if key in errors_non_capture:
			errors_non_capture[key].append(value)
		else:
			errors_non_capture[key]=[value]
comp=[]
non_comp=[]
for key in errorscapture:
	flag=True
	for k in errors_non_capture:
		if key-10 <=k<=key+10:
			comp.append((k,key))
			flag=False
	if flag:
		non_comp.append((key,True))
for key in errors_non_capture:
	flag=True
	for k in errorscapture:
		if key-10 <=k<=key+10:
			if (k,key) not in comp:
				comp.append((key,k))
			flag=False
	if flag:
		non_comp.append((key,False))

with open('pairs.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	for c in comp:
		wr.writerow(c)
print(len(comp))
print(non_comp)
with open('with_no_pair.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	for nc in non_comp:
		wr.writerow(nc)
common=[]
diff=[]
for nc in non_comp:
	if nc[1]:
		for ec in errorscapture[nc[0]]:
			diff.append([nc[0],nc[1]]+ec.split(','))
	else:
		for enc in errors_non_capture[nc[0]]:
			diff.append([nc[0],nc[1]]+enc.split(','))
n=0
for c in comp:
	print(n,c)
	rbnc=set(errorscapture[c[1]])
	rbc=set(errors_non_capture[c[0]])
	com=rbc.intersection(rbnc)
	dif1=rbc-rbnc
	dif2=rbnc-rbc
	for co in com:
		v=[c[0],c[1]]+co.split(',')
		common.append(v)
	for d in dif1:
		diff.append([c[0],False]+d.split(','))
	for d in dif2:
		diff.append([c[1],True]+d.split(','))
	n+=1
output_keys=['readback_time_tag', 'readback_capture_time_tag','is_angled', 'golden_bit_value', 'frame_address', 'frame_index', 'block_type', 'top_bot', 'row_address', 'column_address', 'minor_address', 'word_of_frame', 'bit_word', 'bit_frame', 'masked_bit', 'masked_frame', 'essential_bit', 'non_essential_frame', 'logic_block', 'specific_logic', 'specific_logic_2']
with open('common.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	wr.writerow(output_keys)
	for c in common:
		wr.writerow(c)

output_keys=['time_tag', 'readback_capture','is_angled', 'golden_bit_value', 'frame_address', 'frame_index', 'block_type', 'top_bot', 'row_address', 'column_address', 'minor_address', 'word_of_frame', 'bit_word', 'bit_frame', 'masked_bit', 'masked_frame', 'essential_bit', 'non_essential_frame', 'logic_block', 'specific_logic', 'specific_logic_2']
with open('diff.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	wr.writerow(output_keys)
	for d in diff:
		wr.writerow(d)
with open('Unmasked_CLB_diff.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	wr.writerow(output_keys)
	for d in diff:
		if(d[14]=='0' and d[6]=='CLB'):
			wr.writerow(d)
with open('BRAM_diff.csv', 'w') as myfile:
	wr = csv.writer(myfile)
	wr.writerow(output_keys)
	for d in diff:
		if(d[6]=='BRAM'):
			wr.writerow(d)
print(len(common),len(diff))
