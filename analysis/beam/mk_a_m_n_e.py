#!/usr/bin/python
from projectTools.binaryStringTools import KeepOnlyBinary
from projectTools.stopwatch import Stopwatch
from projectTools.maskTools import find_masked_frames,find_binary_masked_frames
from projectTools.non_essetial_frame_tools import find_non_essential_frames,find_binary_non_essential_frames
from projectTools.addressTools import frames_to_addresses
import argparse
import re
stopwatch = Stopwatch()
stopwatch.Start()
address_file_name= "files/frame_address_list.txt"

mask_file_name = "files-test2/rad_test_2.msd"

essentials_file_name ="files-test2/rad_test_2.ebd"

output_file_name="masked_frames.txt"

use_binary=False

frame_word_size=101
word_bit_size=32
byte_bit_size=8

word_byte_size=word_bit_size//byte_bit_size
frame_bit_size=frame_word_size*word_bit_size
frame_byte_size=frame_word_size*word_byte_size

keepOnlyBinary =KeepOnlyBinary()

parser = argparse.ArgumentParser(description='Create masked frames file.')

parser.add_argument('-a', action='store', dest='address_file_name',
                    default=address_file_name,help='set the frame address file')
parser.add_argument('-m', action='store', dest='mask_file_name',
                    default=mask_file_name,help='set the mask file')
parser.add_argument('-o', action='store',dest='output_file_name',
                    default=output_file_name,help='Set the output file')
parser.add_argument('-f', action='store',type=int,dest='frame_bit_size',
                    default=frame_bit_size,help='set the size of the frame (in bits)')
parser.add_argument('-b', action='store_true',dest='use_binary',
                    default=use_binary,help='use Binary parsing for the masked frames file')
args = parser.parse_args()

address_file_name= args.address_file_name

mask_file_name = args.mask_file_name

output_file_name= args.output_file_name

frame_bit_size= args.frame_bit_size
use_binary = args.use_binary

def read_mask():
    mask_file = open(mask_file_name,'r')
    mask = mask_file.read()
    mask_file.close()
    return mask.translate(keepOnlyBinary)

def read_mask_binary():
    mask_file = open(mask_file_name,'rb')
    mask = mask_file.read()

    mask_file.close()
    return mask

def read_addresses():
    address_file = open(address_file_name,'r')
    address_list = address_file.readlines()
    address_file.close()
    return address_list

def output_masked_addresses(masked_addresses):
    output_file = open("test_2_masked_addresses.txt",'w')
    for masked_address in masked_addresses:
        output_file.write(str(masked_address))
    output_file.close()

#main:

addresses = read_addresses()


mask = read_mask()
are_masked_frames = find_masked_frames(mask,frame_bit_size)
with open(essentials_file_name,'r') as input:
    essentials = input.read()
    essentials=essentials.translate(keepOnlyBinary)
are_non_essential_frames=find_non_essential_frames(essentials,frame_bit_size)
only_masked_frames=[]
only_non_essential_frames=[]
for i in range(len(are_non_essential_frames)):
    if(are_non_essential_frames[i]):
        only_non_essential_frames.append(i)
for i in range(len(are_masked_frames)):
    if(are_masked_frames[i]):
        only_masked_frames.append(i)
masked_addresses = frames_to_addresses(only_masked_frames,addresses)
non_essential_addresses = frames_to_addresses(only_non_essential_frames,addresses)
output_masked_addresses(masked_addresses)

with open("test_2_non_essential_addresses.txt",'w') as output_file:
    for non_essential_address in non_essential_addresses:
        output_file.write(str(non_essential_address))
print(stopwatch.Elapsed())
