from collections import OrderedDict
import time,csv,re
def read_file(file_path,mode=''):
    file = open(file_path,'r'+mode)
    data = file.read()
    file.close()
    return data
class KeepOnlyBinary:
  def __init__(self, keep='01'):
    self.comp = dict((ord(c),c) for c in keep)
  def __getitem__(self, k):
    return self.comp.get(k)

file_path = 'test1_app/readback-files/readback-1542439656.316203.rbd'
golden_path='files/readback-golden.rbd'
mask_file_path = "files/rad_test_1.msd"
essential_bits_path = "files/rad_test_1.ebd"
address_list_path = "files/frame_address_list.txt"
logic_path = "files/logic_data.json"
output_path = "data_test.csv"

keepOnlyBinary = KeepOnlyBinary()

mask_file_data=read_file(mask_file_path)
mask_file_data = mask_file_data.translate(keepOnlyBinary)

essential_bits = read_file(essential_bits_path)
essential_bits = essential_bits.translate(keepOnlyBinary)





golden_binary = read_file(golden_path)
golden_binary = golden_binary.translate(keepOnlyBinary)

binary = read_file(file_path)
binary = binary.translate(keepOnlyBinary)

file = open(address_list_path,'r')
address_list = file.readlines()
file.close()

g_b_int = int(golden_binary,2)

b_int = int(binary,2)

error_int = g_b_int ^ b_int

error_bits = bin(error_int)[2:]
initial_bit_index = len(golden_binary)- len(error_bits)
bit_indexs = [m.start()+initial_bit_index for m in re.finditer('1',error_bits)]

error_data=OrderedDict()
start_time = time.time()
data=[]
for bit_index in bit_indexs:

    frame_index = bit_index//(101*32)
    bit_index_in_frame = bit_index%frame_index
    word_in_frame = bit_index_in_frame//32
    bit_index_in_word = bit_index_in_frame%32
    bit_pos_in_word = 31 - bit_index_in_word

    bit_pos_in_frame =word_in_frame*32+ bit_pos_in_word
    golden_bit = golden_binary[bit_index]

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

    masked_bit = int(mask_file_data[bit_index])

    if (bit_index>len(essential_bits)):
        essential_bit = 0
    else:
        essential_bit = int(essential_bits[bit_index])


    error_data['golden_bit_value']=golden_bit
    error_data['frame_address']=frame_address
    error_data['frame_index']=frame_index
    error_data['block_type']=block_type
    error_data['top_bot']=top_bot
    error_data['row_address']=row_address
    error_data['column_address']=column_address
    error_data['minor_address']=minor_address
    error_data['bit_word']=bit_pos_in_word
    error_data['bit_frame']=bit_pos_in_frame
    error_data['masked_bit']=masked_bit
    error_data['essential_bit']=essential_bit
    data.append(error_data)


elapsed_time = time.time() - start_time
print(elapsed_time)
"""
keys = data[0].keys()
with open(output_path, 'w') as output_file:
    dict_writer = csv.DictWriter(output_file, keys)
    dict_writer.writeheader()
    dict_writer.writerows(data)
"""
