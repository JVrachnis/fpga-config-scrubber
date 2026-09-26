#!/usr/bin/python
from multiprocessing import Process
import argparse
import sys
from os import listdir,chdir,makedirs
from glob import glob
from os.path import isdir,isfile,exists,basename,abspath
import re
from projectTools.binaryStringTools import KeepOnlyBinary,binaryString_to_rawBinary
from projectTools.arrayTools import split_array_by_length
from projectTools.stopwatch import Stopwatch
from projectTools.fileTools import get_file_paths
import logging
stopwatch = Stopwatch()
stopwatch.Start()

paths=[]
output_dir='./'
processes_amount=4

keepOnlyBinary =KeepOnlyBinary()

parser = argparse.ArgumentParser()

parser.add_argument('paths',metavar='file',nargs='+',
                    default=paths,help='files to be processed')
parser.add_argument('-o','--output', action='store', dest='output_directory',
                    default=output_dir,help='output directory')
parser.add_argument('-p','--processes', action='store',type=int,dest='processes_amount',
                    default=processes_amount, help='set amount of processes to use for this program')

logging.basicConfig(level=logging.INFO,format='[%(levelname)s] (%(processName)-10s) %(message)s',)

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

def mainProcess(rbdyfiles):
    stopwatch = Stopwatch()

    for rbdyfile in rbdyfiles:
        stopwatch.Start()

        input = open(rbdyfile, 'r')
        output_file = rbdyfile+'.bin'

        if(re.match('.*(!?/)$',output_file)):
            output_file=output_dir+basename(rbdyfile)+'.bin'
        else:
            output_file=output_dir+'/'+basename(rbdyfile)+'.bin'
        output = open(output_file, 'wb')

        string = input.read()
        binaryString = string.translate(keepOnlyBinary)

        newFileByteArray = binaryString_to_rawBinary(binaryString)
        output.write(newFileByteArray)

        output.close()
        input.close()
        logging.info('output %s at %f' % (abspath(output_file),stopwatch.Elapsed(),))


args = parser.parse_args()
paths =args.paths
output_dir = args.output_directory
processes_amount= args.processes_amount

file_paths = get_file_paths(paths)

number_of_files = len(file_paths)

if ( not( exists(output_dir))):
    makedirs(output_dir)


if (number_of_files<processes_amount):
    processes_amount=number_of_files

thread_file_paths = split_work(file_paths,processes_amount)
#initialize and start threads

processes=[]
for i in range(0,processes_amount):
    processes.append(Process(target=mainProcess, args=(thread_file_paths[i],)))
    processes[i].start()
#wait for every thread to finish

for i in range(0,processes_amount):
    processes[i].join()

logging.info('total time: %f'% (stopwatch.Elapsed()))
