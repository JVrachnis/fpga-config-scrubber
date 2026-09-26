import json
def read_file(file_path):
    file = open(file_path,'r')
    data = file.readlines()
    file.close()
    return data

lines = read_file('post-processing/rad_test_3.ll')
data={}
for line in lines:
    if line[0]==";":
        continue
    d=line.split()
    d = d[1:7]
    d[3] = d[3][6:]
    data[str((d[1][2:],d[2]))]=d[3:]

with open('post-processing/rad_test_3.json', 'w') as outfile:
    json.dump(data, outfile)

print(len(lines))
