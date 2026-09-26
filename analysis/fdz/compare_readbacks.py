# SPDX-License-Identifier: MIT
# Copyright (c) 2018 John Vrachnis
import pandas as pd
import numpy as np
import glob
from Entry import Entry
import progressbar
import logging

# Setting up Logger
logging.basicConfig(filename='compare_readbacks.log', level=logging.INFO,
                    format='%(message)s')

# Setting up progressbar
widgets = [
        ' ', progressbar.Percentage(),
        ' (', progressbar.SimpleProgress(), ')',
        ' ', progressbar.Bar(marker='#', left='[', right=']'),
        ' ', progressbar.ETA(),
        ]

bar = progressbar.ProgressBar(widgets=widgets, term_width=80)


# Opening as DataFrame every main file here.
# More efficient to keep them open, than open and close in each iteration.
readback_golden = pd.read_csv('files/readback-golden.rbd', header=None, names=['Golden'])
frame_address = pd.read_csv('files/frame_address_list.txt', header=None, names=['Address'])
masked_addresses = pd.read_csv('generated files/masked_frames.txt', header=None, names=['Masked'])
essential_address = pd.read_csv('files/rad_test_1.ebd', header=None, names=['Essential'])
masked_bit_addresses = pd.read_csv('files/rad_test_1.msd', header=None, names=['Bits'])

print('\nWhat are you waiting for? Script Info? Here get a nice looking progressbar.\n')

# Paths to available readback-XXX are stored here.
readbacks_available = [file for file in glob.glob('files/readback/*.rbd')]
#readbacks_available = [file for file in glob.glob('files/readback/readback-1542412825.477164.rbd')]
# Iterate all files
for file in bar(readbacks_available):

    readback_current = pd.read_csv(file, header=None, names=['Current'])

    # Continue to next file if they are identical
    if readback_current.equals(readback_golden):
        continue

    readbacks = pd.merge(readback_current, readback_golden, left_index=True, right_index=True)

    readbacks['IsEqual'] = readbacks.Current.eq(readbacks.Golden)

    # Keep only those who are different.
    readbacks = readbacks[readbacks.IsEqual == False]

    # Iterate for every row
    for row in range(len(readbacks.index)):

        # List 2 different rows one next to the other as series.
        # Then i can check which bits are not similar.
        # Basically, same concept as before, but comparing words instead of frames.
        different_row = pd.DataFrame(data=[list(readbacks.Current.iloc[row]), list(readbacks.Golden.iloc[row])])
        different_row = different_row.T
        different_row.columns = ['Current', 'Golden']
        different_row['IsEqual'] = different_row.Current.eq(different_row.Golden)

        # Keep only instances of different bits
        different_bits = different_row[different_row.IsEqual == False]

        # Get time_tag contained in file name
        time_tag = file.split('-')[1].split('.')

        

        logging.info(160 * '-')

        logging.info('[BitFlip] Parsing file: readback_{}, row: {}, found: {}, wanted: {}, error(s): {}.'
                     .format(time_tag[0] + '.' + time_tag[1], readbacks.index[row], readbacks.Current.iloc[row],
                             readbacks.Golden.iloc[row], len(different_bits.index)))


        # Iterate for every different bit
        for bit in range(len(different_bits.index)):

            # Start building database entry
            entry = Entry()

            # Get time_tag contained in file name
            entry.time_tag = time_tag[0] + '.' + time_tag[1]

            # This script works only for readbacks
            entry.readback_capture = False

            # Golden's Bit value
            entry.golden_bit_value = different_bits.Golden.iloc[bit]

            # Frame index, do i need +1 ??
            entry.frame_index = int(np.ceil(readbacks.index[row] / 101) - 1)

            # Frame address
            entry.frame_address = frame_address.Address.iloc[entry.frame_index]

            # Holds converted value of frame_address
            binary_address = ''

            if frame_address.Address.iloc[entry.frame_index].startswith('DUMMY'):
                entry.block_type = ''
                entry.top_bottom = ''
                entry.row_address = ''
                entry.column_address = ''
                entry.minor_address = ''

            else:
                # Convert hex address to 32 bit binary, '032b' = 0: pads zeros, 32: char length, b: binary
                binary_address = format(int(entry.frame_address, base=16), '032b')

                # CAUTION. Strings are sliced from left to right. BIT VALUE IS CONSIDERED VICE VERSA
                # Need to add 1, so string includes every character of given range
                # e.x [3:5] prints 2 characters, i need to include 5 as well
                # thus instead of [3:5] use [3:5+1]
                # Use table below to find corresponding word indices
                # str: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
                # bit: 31 30 29 28 27 26 25 24 23 22 21 20 19 18 17 16 15 14 13 12 11 10 09 08 07 06 05 04 03 02 01 00

                # block_type = 25-23 bits
                entry.block_type = 'CLB' if binary_address[6: 8+1] == '000' else 'BRAM'
                # top_bottom = 22 bit
                entry.top_bottom = 'Bottom' if binary_address[9] == '1' else 'Top'
                # row_address = 21-17 bits
                entry.row_address = int(binary_address[10: 14+1], base=2)
                # column_address = 16-7 bits
                entry.column_address = int(binary_address[15: 24+1], base=2)
                # minor_address = 6-0 bits
                entry.minor_address = int(binary_address[25:], base=2)

            entry.bit_word = 31 - different_bits.index[bit]

            # Calculate word index based on frame index (= row - frame index * 101).
            word_index = readbacks.index[row] - (entry.frame_index * 101)

            # Calculate position of bit in word using word index.
            entry.bit_frame = (word_index - 1) * 32 + entry.bit_word



            logging.info('[DEBUG]   Bit position in Word: {}, found: {}, wanted: {}'
                         .format(entry.bit_word, different_bits.Current.iloc[bit], entry.golden_bit_value))

            logging.info('          Frame Address: ({})hex = ({})bin'
                         .format(entry.frame_address, binary_address))

            logging.info('          Bits [25-23]: {}, [22]: {}, [21-17]: {}, [16-7]: {}, [6-0]: {}'
                         .format(entry.block_type, entry.top_bottom, entry.row_address, entry.column_address,
                                 entry.minor_address))

            logging.info('          Frame Index = ceil(row/101) = ceil({}/101) = {} (1-10.009) -> {} (0-10.008)'
                         .format(readbacks.index[row], entry.frame_index+1, entry.frame_index))

            logging.info('          Word Index = row - (frame index * 101) = {} - ({} * 101) = {} (0-100)'
                         .format(readbacks.index[row], entry.frame_index, word_index))

            logging.info('          Bit position in Frame = (word index - 1) * 32 + bit position in word = ({} - 1) * 32 + {} = {} (0-3231)'
                         .format(word_index, entry.bit_word, entry.bit_frame))



            # Check if current address is inside masked addresses.
            entry.masked_frame = (entry.frame_address in masked_addresses.Masked)

            if entry.block_type == 'BRAM':
                entry.essential_bit = 0
                #logging.info('          BRAM Block Type. No essential bit. Setting in to 0.')

            else:
                # else, open .ebd file and search there
                # get value of row in .ebd, then make it a list so i can select bits individually.
                # e.x row = 11111111111111111111111111111111, listing them produces a list every 1 character
                # then just cast index of wanted bit
                entry.essential_bit = list(essential_address.Essential.iloc[readbacks.index[row]])[entry.bit_word]

                #logging.info('          Row in .ebd: {}, actual row: {}, position: {}, value: {}'
                #             .format(readbacks.index[row], essential_address.Essential.iloc[readbacks.index[row]],
                #                     entry.bit_word, entry.essential_bit))

            # same thing as before
            entry.masked_bit = list(masked_bit_addresses.Bits.iloc[readbacks.index[row]])[entry.bit_word]

            #logging.info('          Row in .msd: {}, actual row: {}, position: {}, value: {}'
            #             .format(readbacks.index[row], masked_bit_addresses.Bits.iloc[readbacks.index[row]],
            #                     entry.bit_word, entry.masked_bit))

            # TO DO
            entry.logic_block = ''
            entry.specific_logic = ''
            entry.specific_logic_2 = ''

            logging.info(entry)

            # print(entry)

# logging.info(73 * '-' + ' END OF SCRIPT ' + 73 * '-')

print('\nDone. Go ask the database now.. Wait, i guess you can check the log file too..')
print('Go open it yourself, i did the writing.')
