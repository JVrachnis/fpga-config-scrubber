def generate_information_from_frame_address(frame_address):
    bin_of_frame_address=(bin(int(frame_address,16)).zfill(33)).replace('b','')
    clb_bram=''
    top_bottom=''
    if(bin_of_frame_address[6:9]=='000'):
        clb_bram='CLB'
    elif(bin_of_frame_address[6:9]=='001'):
        clb_bram='BRAM'
#--------------/---------------------
    if(bin_of_frame_address[9]=='0'):
        top_bottom='Top'
    elif(bin_of_frame_address[9]=='1'):
        top_bottom='Bottom'
#--------------/---------------------
    row_address=int(bin_of_frame_address[10:15],2)
#--------------/---------------------
    column_address=int(bin_of_frame_address[15:25],2)
#--------------/---------------------
    minor_address=int(bin_of_frame_address[25:32],2)
#--------------/---------------------
    return clb_bram,top_bottom,row_address,column_address,minor_address
def frame_address_information(frame_address):
    if(not ('DUMMY' in frame_address)):
        frame_address_bit = ("{0:032b}").format(int(frame_address,16))
        block_type_bit = frame_address_bit[-26:-23]
        if(block_type_bit == '000'):
            block_type = 'CLB'
        elif(block_type_bit == '001'):
            block_type = 'BRAM'
            print(block_type_bit)
        else:
            block_type=''
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

        block_type=''
        top_bot=None
        row_address = None
        column_address = None
        minor_address = None
    return block_type,top_bot,row_address,column_address,minor_address

with open('freerun_address_only.csv') as address_file:
    address_data = address_file.readlines()
    for address in address_data:
        d1=frame_address_information(address)
        d2=generate_information_from_frame_address(address)
        if(d1!=d2):
            print(address,d1,d2)
