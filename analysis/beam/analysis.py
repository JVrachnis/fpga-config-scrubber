import csv
import operator

with open('output.csv','r') as csv_file:
    csv_reader = csv.reader(csv_file, delimiter=',')
    data = list(list(rec) for rec in csv_reader)

data=data[1:]
print(len(data))
golden_zeros=0
golden_ones=0
bram=0
clb=0
errors_per_file={}
for entry in data:
    epoch_time=float(entry[0])
    is_readbackCapture='True'==entry[1]
    if((epoch_time,is_readbackCapture) in errors_per_file.keys()):
        errors_per_file[epoch_time,is_readbackCapture][0]+=1
    else:
        errors_per_file[epoch_time,is_readbackCapture]=[1,0,0]

    if(entry[5]=='BRAM'):
        errors_per_file[epoch_time,is_readbackCapture][1]+=1
        bram+=1
    else:
        errors_per_file[epoch_time,is_readbackCapture][2]+=1
        clb+=1
    if(entry[2]=='0'):
        golden_zeros+=1
    else:
        golden_ones+=1
print('golden ones= %i ,zeros=%i'%(golden_ones,golden_zeros))
print('BRAM:%i vs CLB:%i'%(bram,clb))
file_compos=[]
capture_compos={}
for key in errors_per_file:
    if key[1]:
        epoch_time=key[0]
        for k in errors_per_file:
            if not k[1]:
                if epoch_time-5<= k[0] <=epoch_time+5:
                    file_compos.append([epoch_time,k[0]])
                    capture_compos[epoch_time]=k[0]
tlist = list(zip(*file_compos))
times = {}
for file in tlist[0]:
    if file in times:
        times[file]+=1
    else:
        times[file]=1
    if(times[file]>1):
        print(file)

print(len(file_compos),len(errors_per_file)/2)
sorted_errors_per_file = sorted(errors_per_file.items(), key=operator.itemgetter(1))
compo_sorted_files=[]
for file in sorted_errors_per_file:
    if(file[0][1]):
        file_c_epoch=file[0][0]
        if(file_c_epoch in capture_compos):
            compo_sorted_files.append([(file_c_epoch,file[1]),(capture_compos[file_c_epoch],errors_per_file[capture_compos[file[0][0]],False])])
        else:
            compo_sorted_files.append([(file_c_epoch,file[1]),])

for compo in compo_sorted_files:
    if(len(compo)<2):
        print(compo,'less than 2')
    elif(compo[0][1][1]!=compo[1][1][1]):
        print(compo)
