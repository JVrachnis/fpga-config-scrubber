import itertools
import numpy
from collections import Counter
from collections import deque
from itertools import combinations_with_replacement,permutations
import string
import time
import gzip
digs = string.digits + string.ascii_letters
def get_pm_from_spm(n,l):
    x=0
    y=n
    pm2=[]
    for i in range(0,len(l)-n+1):

        #print(l[x+i:y+i])
        pm2.append(tuple(l[x+i:y+i]))
    return pm2
c=list(digs)
l=range(0,7)
n=len(l)
pms=permutations(l)
pms = list(pms)
spm=list(pms[0])
print(spm)
tpms=set(pms[1:])
j=0

sspm = ''.join([c[x] for x in spm])
the_file = open('aspm'+str(n)+'.txt', 'w')
lspm=tuple(spm)
t=time.time()
while len(tpms)>0:
    #t=time.time()

    offset=1
    flag =False
    for i in range(n,-1,-1):
        tail=lspm[:-i][::-1]
        tpm=lspm[::-1][:i][::-1]+tail
        if tpm in tpms:
            print(j,n-i)
            spm.extend(list(tail))
            sspm+=''.join([c[x] for x in tail])

            lspm=tpm
            tpms.remove(tpm)
            flag=True
            break
    if not flag:
        print('failed')
        break
    #print(j,time.time()-t)
    j+=1
print(len(spm),time.time()-t)
setpms =set(pms)
pm2 = set(get_pm_from_spm(n,spm))
pms=permutations(l)
j=0
f = gzip.open('aspm'+str(n)+'.txt.gz', 'w')
for pm in pms:

    sspm+=''.join([c[pm[x]] for x in spm])
    print(j)
    f.write((sspm+'\n').encode('utf-8'))
    j+=1
