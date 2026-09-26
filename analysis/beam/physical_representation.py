from itertools import combinations
from collections import OrderedDict
import operator
import csv

input_file = csv.DictReader(open("test1__groups.readback_capture=False.block_type=CLB.is_angled=False.csv"))
Pattern_Column_Types={3608168208687122484:,-6661062253119182454:,-381917555165728029}
"""
Frames={bit_frame:frame_data}
Minors={0-127:Frames}
Columns={0-127:{'Column_Type':Column_Type,Minors:Minors}}
Rows={0-5:Columns}
FPGA={'top':Rows,'bot':Row}
"""
