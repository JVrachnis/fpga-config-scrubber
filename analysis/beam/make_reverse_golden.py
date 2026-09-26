import time,re
file_path='files/readback-golden.rbd'
file = open(file_path,'r')
lines = file.readlines()
file.close()

word_filled_with_ones = 4294967295


reverse_lines=[]
for line in lines:
    reverse=("{0:032b}").format(int(line,2)^word_filled_with_ones)
    reverse_lines.append(reverse)
file1 = open("reverse_readback-golden-0.0.rbd","w")
file1.write('\n'.join(reverse_lines))
file1.close()
