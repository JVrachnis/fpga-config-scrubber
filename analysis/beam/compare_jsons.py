import json
with open('data.json') as f:
    data = json.load(f)
with open('data1.json') as f:
    data1 = json.load(f)

def build_dict(seq, key):
    return dict((d[key], dict(d)) for (index, d) in enumerate(seq))

for d in data:
    if (not (d in data1)):
        print(d)
for d in data1:
    if (not (d in data)):
        print(d)
