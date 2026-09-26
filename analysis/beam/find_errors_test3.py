from multiprocessing import Process,Manager
from projectTools.arrayTools import split_array_by_length
from projectTools.binaryStringTools import KeepOnlyBinary
from projectTools.maskTools import find_masked_frames,find_binary_masked_frames
from projectTools.non_essetial_frame_tools import find_non_essential_frames,find_binary_non_essential_frames
from projectTools.stopwatch import Stopwatch
from collections import OrderedDict
from projectTools.fileTools import get_file_paths,read_file,find_timeTag,is_readbackCapture
from datetime import datetime, timedelta
import argparse
import logging
import csv
import json





output_keys=['time_tag','time_tag2','set','type', 'golden_bit_value', 'frame_address', 'frame_index', 'block_type', 'top_bot', 'row_address', 'column_address', 'minor_address', 'word_of_frame', 'bit_word', 'bit_frame', 'masked_bit', 'masked_frame', 'essential_bit', 'non_essential_frame', 'logic_block', 'specific_logic', 'specific_logic_2']

#constands:
#   basics:
#       how many words a frame contains:
frame_word_size=101

#       how many bits a word contains:
word_bit_size=32

#       how many bits a byte contains:
byte_bit_size=8

#   sinthetic:
#       how many bytes a word contains:
word_byte_size=word_bit_size//byte_bit_size

#       how many bits a frame contains:
frame_bit_size=frame_word_size*word_bit_size
#       how many bytes a frame contains:
frame_byte_size=frame_word_size*word_byte_size
#       this is used to format an int into and standar length binary string
byteInt_to_binary_format = "{0:0"+str(byte_bit_size)+"b}"

#default values:
#   if binary parsing is enabled '.bin' will be added to the default values of
#   golden1_path,golden2_path,mask_file_path,essential_bits_path
paths=[]
base_path='radiation_test_files/GSI2019/designfiles'

golden1_path=base_path+'/golden-1.rbd.bin'
golden2_path=base_path+'/golden-2.rbd.bin'
mask_file_path =base_path+ "/rad_test_3.msd.bin"
essential_bits_path = base_path+"/rad_test_3.ebd.bin"
address_list_path = base_path+"/frame_addresses.txt"
logic_path = base_path+"/rad_test_3.json"
output_path = "temp/GSI2019/GSI2019_UPSETS.csv"
processes_amount=4
use_binary=True
#starting timer:
#using timer to calculate performance
stopwatch = Stopwatch()
stopwatch.Start()

#initializing this object:
#   this object is use for the ascii parsing to keep only 0,1 caracters.
#   i read the whole file and new line caracters are included

#initializing the argument parser:
#   i use this object to have input in a user friendly way
#   -h can be used to see all the options
parser = argparse.ArgumentParser()

parser.add_argument('paths',metavar='file',nargs='+',
                    default=None,help='files to check')


parser.add_argument('-g1','--golden1', action='store', dest='golden1_path',
                    default=None,help='set path for golden file')
parser.add_argument('-g2','--golden2', action='store', dest='golden2_path',
                    default=None,help='set path for capture golden file')

parser.add_argument('-m', action='store', dest='mask_file_path',
                    default=None,help='set the mask file')
parser.add_argument('-e', action='store', dest='essential_bits_path',
                    default=None,help='set the essential file')

parser.add_argument('-l', action='store', dest='logic_path',
                    default=logic_path,help='set the logic file')
parser.add_argument('-a', action='store', dest='address_list_path',
                    default=address_list_path,help='set the frame address file')
parser.add_argument('-o', action='store',dest='output_path',
                    default=output_path,help='Set the output file')

#initializing the log method:

logging.basicConfig(level=logging.INFO,format='[%(levelname)s] (%(processName)-10s) %(message)s',)

# gathers frame address information
# didnt change
def frame_address_information(frame_address,error_data):

    if(not ('DUMMY' in frame_address)):
        frame_address_bit = ("{0:032b}").format(int(frame_address,16))
        block_type_bit = frame_address_bit[-26:-23]
        if(block_type_bit == '000'):
            block_type = 'CLB'
        elif(block_type_bit == '001'):
            block_type = 'BRAM'
        else:
            print(block_type_bit)
        top_bot_bit = frame_address_bit[-23]
        if(top_bot_bit == '0'):
            top_bot = 'Top'
        elif(top_bot_bit == '1'):
            top_bot = 'Bottom'

        row_address = int(frame_address_bit[-22:-17],2)
        column_address = int(frame_address_bit[-17:-7],2)
        minor_address = int(frame_address_bit[-7:],2)
    else:
        block_type=None
        top_bot=None
        row_address = None
        column_address = None
        minor_address = None
    error_data['frame_address']=frame_address
    error_data['block_type']=block_type
    error_data['top_bot']=top_bot
    error_data['row_address']=row_address
    error_data['column_address']=column_address
    error_data['minor_address']=minor_address
    return error_data


# didnt change
def is_masked_frame(frame_index):
    return masked_frames[frame_index]

# didnt change
def is_non_essential_frame(frame_index):
    if(frame_index<max_non_essential_frames):
        non_essential_frame = non_essential_frames[frame_index]
    else:
        non_essential_frame = True
    return non_essential_frame

# didnt change
def logic_data_info(frame_address,bit_pos_in_frame,error_data):
    logic_block=None
    specific_logic=None
    specific_logic_2=None

    key =str((str(frame_address),str(bit_pos_in_frame)))
    if(key in logic_data):
        l_d = logic_data[key]
        logic_block=l_d[0]
        if(len(l_d)>1):
            specific_logic=l_d[1]
        if(len(l_d)>2):
            specific_logic_2=l_d[2]

    error_data['logic_block']=logic_block
    error_data['specific_logic']=specific_logic
    error_data['specific_logic_2']=specific_logic_2
    return error_data

# didnt change
def find_errors_in_binary_frame(frame_index,frame,golden_frame,frame_address,error_data,dict_writer):
    for index,binary_int in enumerate(frame):
        g_binary_int=golden_frame[index]

        if(binary_int==g_binary_int):
            continue

        int_error = binary_int^g_binary_int

        byte_index=frame_index*frame_byte_size + index

        essential_byte = 0
        if (byte_index<len(essential_bits)):
            essential_byte = essential_bits[byte_index]

        word_intex_in_frame = index//word_byte_size
        byte_index_in_word = index- word_intex_in_frame*word_byte_size

        essential_byte = byteInt_to_binary_format.format(essential_byte)

        masked_byte =byteInt_to_binary_format.format(mask_file_data[byte_index])

        golden_byte =byteInt_to_binary_format.format(g_binary_int)

        binary_error=byteInt_to_binary_format.format(int_error)
        for i,bit in enumerate(binary_error):
            if(bit =='1'):

                bit_index_in_byte = i
                bit_intex_in_word = byte_index_in_word*byte_bit_size + bit_index_in_byte
                bit_pos_in_word = word_bit_size-1 -bit_intex_in_word
                bit_pos_in_frame = word_intex_in_frame*word_bit_size + bit_pos_in_word

                bit_pos=frame_index*frame_bit_size+word_intex_in_frame*word_bit_size+bit_pos_in_word
                golden_bit = golden_byte[i]

                masked_bit = int(masked_byte[i])
                essential_bit = int(essential_byte[i])

                error_data=logic_data_info(frame_address,bit_pos_in_frame,error_data)

                error_data['golden_bit_value']=golden_bit
                error_data['word_of_frame']=word_intex_in_frame
                error_data['bit_word']=bit_pos_in_word
                error_data['bit_frame']=bit_pos_in_frame
                error_data['masked_bit']=masked_bit
                error_data['essential_bit']=essential_bit

                dict_writer.writerow(error_data)

#has new logic
def MainProcess(file_paths):
    error_data=OrderedDict()

    output_file = open(output_path, 'w')
    dict_writer = csv.DictWriter(output_file, output_keys)

    find_errors_in_frame=find_errors_in_binary_frame

    stopwatch = Stopwatch()
    stopwatch.Start()

    counter=0
    set_counter=0

    for file_path in file_paths:
        type = counter
        set = set_counter

        # if the file is the 1st in the set , it will be compared with the golden_1
        # if the its the 2nd it will be compared with the golden_2 but XORed with
        # the previous errors
        # else if it is the 3rd to 9nth it will be compared with the previous file
        if counter == 0:
            g_frames = golden1_frames
            counter+=1;
        elif counter == 1:
            t = [bytearray([g1b^pb^g2b for g1b,pb,g2b in zip(g1f,pf,g2f)]) for g1f,pf,g2f in zip(golden1_frames,prev_frames,golden2_frames)]
            g_frames= t
            counter+=1;
        elif counter <9:
            g_frames = prev_frames
            counter+=1
        else :
            g_frames = prev_frames
            counter=0
            set_counter+=1

        #reading the binary
        binary = read_file(file_path,'b')
        #spliting it into frames
        frames = split_array_by_length(binary,frame_byte_size)
        #extracting the timeTag from the file name
        timeTag = find_timeTag(file_path)

        #coping the frames into the prev_frames to be used on the next file
        prev_frames=frames.copy()

        # checking the golden frames if equal to frames to avoid extensive search
        if g_frames == frames:
            logging.info('found No Errors at %s, search lasted %f sec' % (file_path,stopwatch.ReStart()))
            with open(output_path+".no_errors.txt", 'a') as myfile:
            	myfile.write(timeTag+','+str(set)+','+str(type)+'\n')
            continue


        error_data['time_tag']=timeTag
        error_data['time_tag2']=timeTag
        error_data['set']=set
        error_data['type']=type


        #didnt change
        # checking each frame to find the erroneous frames
        for frame_index, frame in enumerate(frames):
            golden_frame=g_frames[frame_index]
            # checking the golden frame if equal to frame to avoid extensive search
            if(frame==golden_frame):
                continue

            error_data['frame_index']=frame_index
            frame_address = address_list[frame_index]
            frame_address ="".join(frame_address.split())

            error_data=frame_address_information(frame_address,error_data)
            error_data['masked_frame']=is_masked_frame(frame_index)
            error_data['non_essential_frame']=is_non_essential_frame(frame_index)

            # extensive search to find where exactly is the error
            find_errors_in_frame(frame_index,frame,golden_frame,frame_address,error_data,dict_writer)

        logging.info('finish search at %s lasted %f sec' % (file_path,stopwatch.ReStart()))

args = parser.parse_args()

paths =args.paths
address_list_path = args.address_list_path
logic_path = args.logic_path
output_path = args.output_path

file_paths = get_file_paths(paths)


with open(logic_path) as f:
    logging.info('loading logic data from json, it migth take some time')
    logic_data = json.load(f)

file = open(address_list_path,'r')
address_list = file.readlines()
file.close()

mask_file_data=read_file(mask_file_path,'b')
masked_frames = find_binary_masked_frames(mask_file_data,frame_byte_size)

golden1_binary = read_file(golden1_path,'b')
golden1_frames = split_array_by_length(golden1_binary,frame_byte_size)

golden2_binary = read_file(golden2_path,'b')
golden2_frames = split_array_by_length(golden2_binary,frame_byte_size)

essential_bits = read_file(essential_bits_path,'b')
non_essential_frames = find_binary_non_essential_frames(essential_bits,frame_byte_size)


max_non_essential_frames= len(non_essential_frames)

MainProcess(file_paths)


logging.info('total time: %f s'% (stopwatch.Elapsed()))
