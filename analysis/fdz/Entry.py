# SPDX-License-Identifier: MIT
# Copyright (c) 2018 John Vrachnis
import json

class Entry:

    database_name       : str   = 'FPGA.Zynq'

    time_tag            : str   = None  # rbd's time value
    readback_capture    : bool  = None  # 0: readback, 1: readbackCapture
    golden_bit_value    : bool  = None  # value from golden.rbd
    frame_address       : str   = None  # actual frame address corresponding to frame_address_list.txt
    frame_index         : int   = None  # position in frame_address_list.txt
    block_type          : str   = None  # "CLB" or "BRAM" -- 000: CLB, 001: BRAM
    top_bottom          : bool  = None  # 0: Top, 1: Bot
    row_address         : int   = None  # frame address bits 27-17, NON-DUMMIES ONLY!!!
    column_address      : int   = None  # frame address bits 16-7 , NON-DUMMIES ONLY!!!
    minor_address       : int   = None  # frame address bits 6-0  , NON-DUMMIES ONLY!!!
    bit_word            : int   = None  # int [0, 31]  : bit's word position
    bit_frame           : int   = None  # int [0, 3231]: bit's frame position
    masked_bit          : bool  = None  # bit's value in time_tag.msd
    masked_frame        : bool  = None  # False: address does not exist in masked_frames.txt, True: otherwise
    essential_bit       : bool  = None  # Bit's value in .ebd file. 0: if block type is BRAM.
    logic_block         : str   = None  # 5th column's value in .ll e.x (SLICE_X0Y0, RAMB36_X10Y5)
    specific_logic      : str   = None  # 6th column's value in .ll e.x (Latch=D5FF.Q, RAM=A:1)
    specific_logic_2    : str   = None  # 7th column's value in .ll e.x (Net=XXXX)

    def __init__(self):
        pass


    def __str__(self):

        return ('{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}'
                 .format(self.time_tag, self.readback_capture, self.golden_bit_value,
                         self.frame_address, self.frame_index, self.block_type, self.top_bottom,
                         self.row_address, self.column_address, self.minor_address, self.bit_word,
                         self.bit_frame, self.masked_bit, self.masked_frame, self.essential_bit,
                         self.logic_block, self.specific_logic, self.specific_logic_2))


    def get_query(self):

        return ('INSERT INTO {} VALUES({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {});'
                .format(self.database_name, self.time_tag, self.readback_capture, self.golden_bit_value,
                         self.frame_address, self.frame_index, self.block_type, self.top_bottom,
                         self.row_address, self.column_address, self.minor_address, self.bit_word,
                         self.bit_frame, self.masked_bit, self.masked_frame, self.essential_bit,
                         self.logic_block, self.specific_logic, self.specific_logic_2))

