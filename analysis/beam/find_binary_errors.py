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
#   golden_path,capture_golden_path,mask_file_path,essential_bits_path
paths=[]
golden_path='files/readback-golden.rbd'
capture_golden_path='files/readbackCapture-golden.rbd'
mask_file_path = "files/rad_test_1.msd"
essential_bits_path = "files/rad_test_1.ebd"
address_list_path = "files/frame_address_list.txt"
logic_path = "files/logic_data.json"
output_path = "data.csv"
processes_amount=4
use_binary=False

#starting timer:
#using timer to calculate performance
stopwatch = Stopwatch()
stopwatch.Start()

#initializing this object:
#   this object is use for the ascii parsing to keep only 0,1 caracters.
#   i read the whole file and new line caracters are included
keepOnlyBinary = KeepOnlyBinary()

#initializing the argument parser:
#   i use this object to have input in a user friendly way
#   -h can be used to see all the options
parser = argparse.ArgumentParser()

parser.add_argument('paths',metavar='file',nargs='+',
                    default=None,help='files to check')

parser.add_argument('-b', action='store_true',dest='use_binary',
                    default=use_binary,help='use Binary parsing')

parser.add_argument('-g','--golden', action='store', dest='golden_path',
                    default=None,help='set path for golden file')
parser.add_argument('-cg','--CaptureGolden', action='store', dest='capture_golden_path',
                    default=None,help='set path for capture golden file')

parser.add_argument('-m', action='store', dest='mask_file_path',
                    default=None,help='set the mask file')
parser.add_argument('-e', action='store', dest='essential_bits_path',
                    default=None,help='set the essential file')

parser.add_argument('-l', action='store', dest='logic_path',
                    default=logic_path,help='set the logic file')
parser.add_argument('-a', action='store', dest='address_list_path',
                    default=address_list_path,help='set the frame address file')
parser.add_argument('-p','--processes', action='store',type=int,dest='processes_amount',
                    default=processes_amount, help='set amount of processes to use for this program')
parser.add_argument('-o', action='store',dest='output_path',
                    default=output_path,help='Set the output file')

#initializing the log method:

logging.basicConfig(level=logging.INFO,format='[%(levelname)s] (%(processName)-10s) %(message)s',)

#this should be moved to an other file and be imported

#       It takes an array (in this case an array of paths to readback files),
#   and splits it in multiple (processes_amount) equal arrays ,and then added to
#   an master array with length of processes_amount.
#       If the input array cant be divided equaly (len(rbdyfiles)%processes_amount!=0)
#   the excess paths will be splited
#   among the the at the output arrays
def split_work(rbdyfiles,processes_amount):
    number_of_files = len(rbdyfiles)
    rbdyfiles_per_thread=int(len(rbdyfiles)/processes_amount)
    thread_rbdyfiles=[]
    for i in range(0,number_of_files,rbdyfiles_per_thread):
        thread_rbdyfiles.append(rbdyfiles[i:i+rbdyfiles_per_thread])

    htrbdfs= thread_rbdyfiles[processes_amount:]
    heaping_thread_rbdyfiles=[]
    for htrbdf in htrbdfs:
        for f in htrbdf:
            heaping_thread_rbdyfiles.append(f)
    thread_rbdyfiles = thread_rbdyfiles[:processes_amount]
    index =0
    for file in heaping_thread_rbdyfiles:
        thread_rbdyfiles[index].append(file)
        index+=1
    return thread_rbdyfiles

#this is the main process that handles the ascii readbacks:
def mainProcess(file_paths,results,process_intex):
    #starting an timer for performance debuging
    stopwatch = Stopwatch()

    stopwatch.Start()

    result=[]
    #file loop:
    for file_path in file_paths:
        errors=[]

        #reading the readback file:
        binary = read_file(file_path)
        #keeping only 0,1 characters (removing newline characters)
        binary = binary.translate(keepOnlyBinary)

        #spliting the readback data stream into frames
        frames = split_array_by_length(binary,frame_bit_size)

        #determine if readback file is readback capture
        readbackCapture = is_readbackCapture(file_path)

        #use readback capture golden for golden frames
        #if it is a readback capture
        #else use readback golden as golden frames
        if readbackCapture:
            g_frames = capture_golden_frames
        else:
            g_frames = golden_frames

        #if golden frames are equal to the frames that we check
        #go to the next file
        #this is realy fast and saves as from high level parsing that is slow
        if g_frames == frames:
            logging.info('found %i Errors at %s, search lasted %f sec' % (len(errors),file_path,stopwatch.ReStart()))
            continue

        #extracting the timetag from the file name
        timeTag = find_timeTag(file_path)

        #--
        date_time=str(datetime.fromtimestamp(float(timeTag))+ timedelta(hours=1))

        #main loop:
        #   now we need to find where the error is
        #   we enumerate the frames tha we need to check so we can find the equal
        #   golden frame and so we can use it to find the exact possition of the
        #   error

        for frame_index , frame in enumerate(frames):
            golden_frame=g_frames[frame_index]
            #if golden frame is equal to the frame that we checking
            #go to the next frame
            if(frame==golden_frame):
                continue
            #now we need to find the exact possition of the bit with in the frame
            for bit_in_frame_index, bit in enumerate(frame):
                #if golden bit is equal to the bit that we checking
                #go to the next bit
                if (golden_frame[bit_in_frame_index]==bit):
                    continue

                # calculating the intex of the error word relative to the frame
                word_intex_in_frame=bit_in_frame_index//word_bit_size

                # calculating the intex of the error bit relative to the word
                bit_intex_in_word = bit_in_frame_index -word_intex_in_frame*word_bit_size

                # POSsition is counting from the less to the most significant bit (rigth to left), deferent to index as intex counts from left to rigth
                # translating index to pos. to do the translation we subtract from the maximum intex value (word_bit_size-1=31) to the curent one (bit_in_frame_index)
                bit_pos_in_word = word_bit_size-1 -bit_intex_in_word

                # to find the possition of the bit with in the Index we need to translate the word_intex_in_frame to bits a.k.a. to multiply
                # by the amount of bits that create a word (word_bit_size) and the add up the possition of the bit within the word (bit_pos_in_word)
                bit_pos_in_frame = word_intex_in_frame*word_bit_size + bit_pos_in_word


                bit_index= frame_index*frame_bit_size+word_intex_in_frame*word_bit_size+bit_intex_in_word

                bit_pos=frame_index*frame_bit_size+word_intex_in_frame*word_bit_size+bit_pos_in_word

                golden_bit = golden_frame[bit_in_frame_index]
                frame_address = address_list[frame_index]
                frame_address ="".join(frame_address.split())
                if(not ('DUMMY' in frame_address)):
                    frame_address_bit = ("{0:032b}").format(int(frame_address,16))
                    block_type_bit = frame_address_bit[-26:-23]
                    if(block_type_bit == '000'):
                        block_type = 'CLB'
                    elif(block_type_bit == '001'):
                        block_type = 'BRAM'
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
                masked_frame = masked_frames[frame_index]

                masked_bit = int(mask_file_data[bit_index])
                if (bit_index>len(essential_bits)):
                    essential_bit = 0
                else:
                    essential_bit = int(essential_bits[bit_index])

                logic_block=None
                specific_logic=None
                specific_logic_2=None
                if(str(bit_pos) in logic_data):
                    l_d = logic_data[str(bit_pos)]
                    logic_block=l_d[0]
                    if(len(l_d)>1):
                        specific_logic=l_d[1]
                    if(len(l_d)>2):
                        specific_logic_2=l_d[2]

                if(frame_index<max_non_essential_frames):
                    non_essential_frame = non_essential_frames[frame_index]
                else:
                    non_essential_frame = True

                error_data=OrderedDict()
                error_data['time_tag']=timeTag
                error_data['date']=date_time.split(' ')[0]
                error_data['time']=date_time.split(' ')[1].split('.')[0]
                error_data['microseconds']=("{0:06}").format(int(date_time.split(' ')[1].split('.')[1]))
                error_data['readback_capture']=readbackCapture
                error_data['golden_bit_value']=golden_bit
                error_data['frame_address']=frame_address
                error_data['frame_index']=frame_index
                error_data['block_type']=block_type
                error_data['top_bot']=top_bot
                error_data['row_address']=row_address
                error_data['column_address']=column_address
                error_data['minor_address']=minor_address
                error_data['word_of_frame']=word_intex_in_frame
                error_data['bit_word']=bit_pos_in_word
                error_data['bit_frame']=bit_pos_in_frame
                error_data['masked_bit']=masked_bit
                error_data['masked_frame']=masked_frame
                error_data['essential_bit']=essential_bit
                error_data['non_essential_frame']=non_essential_frame
                error_data['logic_block']=logic_block
                error_data['specific_logic']=specific_logic
                error_data['specific_logic_2']=specific_logic_2

                errors.append(error_data)

        result.extend(errors)
        logging.info('found %i Errors at %s, search lasted %f sec' % (len(errors),file_path,stopwatch.ReStart()))
    results[process_intex]=result

def binaryMainProcess(file_paths,results,process_intex):

    stopwatch = Stopwatch()
    stopwatch.Start()
    result=[]
    for file_path in file_paths:
        errors=[]

        binary = read_file(file_path,'b')

        frames = split_array_by_length(binary,frame_byte_size)

        readbackCapture = is_readbackCapture(file_path)

        if readbackCapture:
            g_frames = capture_golden_frames
        else:
            g_frames = golden_frames

        if g_frames== frames:
            logging.info('found %i Errors at %s, search lasted %f sec' % (len(errors),file_path,stopwatch.ReStart()))
            continue

        timeTag = find_timeTag(file_path)



        date_time=str(datetime.fromtimestamp(float(timeTag))+ timedelta(hours=1))

        for frame_index, frame in enumerate(frames):
            golden_frame=g_frames[frame_index]
            if(frame==golden_frame):
                continue
            for index,binary_int in enumerate(frame):
                g_binary_int=golden_frame[index]

                if(binary_int==g_binary_int):
                    continue

                int_error = binary_int^g_binary_int

                byte_index=frame_index*frame_byte_size + index

                essential_byte = 0
                if (byte_index<len(essential_bits)):
                    essential_byte = essential_bits[byte_index]

                essential_byte = byteInt_to_binary_format.format(essential_byte)


                masked_byte =byteInt_to_binary_format.format(mask_file_data[byte_index])

                golden_byte =byteInt_to_binary_format.format(g_binary_int)

                binary_error=byteInt_to_binary_format.format(int_error)
                for i,bit in enumerate(binary_error):
                    if(bit =='1'):
                        word_intex_in_frame = index//word_byte_size

                        byte_index_in_word = index- word_intex_in_frame*word_byte_size

                        bit_index_in_byte = i
                        bit_intex_in_word = byte_index_in_word*byte_bit_size + bit_index_in_byte
                        bit_pos_in_word = word_bit_size-1 -bit_intex_in_word
                        bit_pos_in_frame = word_intex_in_frame*word_bit_size + bit_pos_in_word

                        bit_pos=frame_index*frame_bit_size+word_intex_in_frame*word_bit_size+bit_pos_in_word
                        bit_index= frame_index*frame_bit_size+word_intex_in_frame*word_bit_size+bit_intex_in_word

                        golden_bit = golden_byte[i]

                        frame_address = address_list[frame_index]
                        frame_address ="".join(frame_address.split())
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
                        masked_frame = masked_frames[frame_index]
                        masked_bit = int(masked_byte[i])
                        essential_bit = int(essential_byte[i])

                        logic_block=None
                        specific_logic=None
                        specific_logic_2=None

                        if(str(bit_pos) in logic_data):
                            l_d = logic_data[str(bit_pos)]
                            logic_block=l_d[0]
                            if(len(l_d)>1):
                                specific_logic=l_d[1]
                            if(len(l_d)>2):
                                specific_logic_2=l_d[2]
                        if(frame_index<max_non_essential_frames):
                            non_essential_frame = non_essential_frames[frame_index]
                        else:
                            non_essential_frame = True

                        error_data=OrderedDict()
                        error_data['time_tag']=timeTag
                        error_data['date']=date_time.split(' ')[0]
                        error_data['time']=date_time.split(' ')[1].split('.')[0]
                        error_data['microseconds']=("{0:06}").format(int(date_time.split(' ')[1].split('.')[1]))
                        error_data['readback_capture']=readbackCapture
                        error_data['golden_bit_value']=golden_bit
                        error_data['frame_address']=frame_address
                        error_data['frame_index']=frame_index
                        error_data['block_type']=block_type
                        error_data['top_bot']=top_bot
                        error_data['row_address']=row_address
                        error_data['column_address']=column_address
                        error_data['minor_address']=minor_address
                        error_data['word_of_frame']=word_intex_in_frame
                        error_data['bit_word']=bit_pos_in_word
                        error_data['bit_frame']=bit_pos_in_frame
                        error_data['masked_bit']=masked_bit
                        error_data['masked_frame']=masked_frame
                        error_data['essential_bit']=essential_bit
                        error_data['non_essential_frame']=non_essential_frame
                        error_data['logic_block']=logic_block
                        error_data['specific_logic']=specific_logic
                        error_data['specific_logic_2']=specific_logic_2

                        errors.append(error_data)

        result.extend(errors)
        logging.info('found %i Errors at %s, search lasted %f sec' % (len(errors),file_path,stopwatch.ReStart()))
    results[process_intex]=result

args = parser.parse_args()

paths =args.paths
use_binary = args.use_binary
address_list_path = args.address_list_path
logic_path = args.logic_path
output_path = args.output_path

if(args.golden_path is not None):
    golden_path = args.golden_path
elif(use_binary):
    golden_path=golden_path+'.bin'

if(args.capture_golden_path is not None):
    capture_golden_path = args.capture_golden_path
elif(use_binary):
    capture_golden_path = capture_golden_path+'.bin'
print(golden_path)
if(args.mask_file_path is not None):
    mask_file_path = args.mask_file_path
elif(use_binary):
    mask_file_path=mask_file_path+'.bin'

if(args.essential_bits_path is not None):
    essential_bits_path = args.essential_bits_path
elif(use_binary):
    essential_bits_path=essential_bits_path+'.bin'

processes_amount= args.processes_amount

file_paths = get_file_paths(paths)

number_of_files = len(file_paths)


if (number_of_files<processes_amount):
    processes_amount=number_of_files


with open(logic_path) as f:
    logging.info('loading logic data from json, it migth take some time')
    logic_data = json.load(f)

splited_file_paths = split_work(file_paths,processes_amount)
file = open(address_list_path,'r')
address_list = file.readlines()
file.close()
if(use_binary):
    mask_file_data=read_file(mask_file_path,'b')
    masked_frames = find_binary_masked_frames(mask_file_data,frame_byte_size)

    golden_binary = read_file(golden_path,'b')
    golden_frames = split_array_by_length(golden_binary,frame_byte_size)

    capture_golden_binary = read_file(capture_golden_path,'b')
    capture_golden_frames = split_array_by_length(capture_golden_binary,frame_byte_size)

    essential_bits = read_file(essential_bits_path,'b')
    non_essential_frames = find_binary_non_essential_frames(essential_bits,frame_byte_size)

    mainProcess=binaryMainProcess
else:
    mask_file_data=read_file(mask_file_path)
    mask_file_data = mask_file_data.translate(keepOnlyBinary)
    masked_frames = find_masked_frames(mask_file_data,frame_bit_size)

    golden_binary = read_file(golden_path)
    golden_binary = golden_binary.translate(keepOnlyBinary)

    golden_frames = split_array_by_length(golden_binary,frame_bit_size)

    capture_golden_binary = read_file(capture_golden_path)
    capture_golden_binary = capture_golden_binary.translate(keepOnlyBinary)
    capture_golden_frames = split_array_by_length(capture_golden_binary,frame_bit_size)

    essential_bits = read_file(essential_bits_path)
    essential_bits = essential_bits.translate(keepOnlyBinary)
    non_essential_frames =  find_non_essential_frames(essential_bits,frame_bit_size)
    mainProcess=mainProcess
#initialize and start threads
manager = Manager()
return_dict = manager.dict()
max_non_essential_frames= len(non_essential_frames)

processes = []
for i in range(processes_amount):
    processes.append(Process(target=mainProcess, args=[splited_file_paths[i],return_dict,i]))
    processes[i].start()
#wait for every thread to finish

for i in range(processes_amount):
    processes[i].join()
logging.info('gathering all the data, it might take some time')
data = []
for i in range(processes_amount):
    data.extend(return_dict[i])

keys = data[0].keys()
print(keys)
with open(output_path, 'w') as output_file:
    logging.info('saving data to csv, it might take some time')
    dict_writer = csv.DictWriter(output_file, keys)
    dict_writer.writeheader()
    dict_writer.writerows(data)
logging.info('total time: %f s'% (stopwatch.Elapsed()))
