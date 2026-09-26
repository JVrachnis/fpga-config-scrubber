import re
import ast
import os
import shutil

from os import listdir
from os.path import isfile, join
from PIL import Image, ImageDraw, ImageFont

from itertools import combinations
from collections import OrderedDict
import operator
import csv


csv_folder = 'visualizetion/patterns_images_threshold4/test1/csv_files/'
csv_regex = 'test1_app_paterns.*'

files = [f for f in listdir(csv_folder)if isfile(join(csv_folder,f)) and re.match(csv_regex, f)]
for file in files:
    distances={}
    points=[]
    output_name='test1_4_tests_distances'+file
    with open(csv_folder+file) as file:
        data = file.readlines()
        for i in data:
            l = ast.literal_eval(i)
            freq = l[0]
            points.append(([ast.literal_eval(k)[:2] for k in list(l[1:])],freq))
    for p in points:
        errors=p[0]
        print(len(p[0]),p[1])
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
                distances[key]+=p[1]
            else:
                distances[key]=p[1]
    sorted_distances = sorted(distances.items(), key=operator.itemgetter(1))
    print(sorted_distances[::-1][0])

    with open(output_name, 'w') as myfile:
        wr = csv.writer(myfile)
        for sd in sorted_distances[::-1]:
            wr.writerow(sd)
