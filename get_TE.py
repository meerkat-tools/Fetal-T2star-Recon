#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Nov 21 10:42:04 2022

@author: kpa19
read dicom in, get TE values

function read(data_dir) takes the directory where the dicoms are stored as
input: outputs the TE values as an array. 

"""



import os
from os import listdir
from os.path import isfile, join
from dicom_parser import Header

def read(data_dir):
    # print('Processing scan: ',data_dir)
    # check if given directory exists, if it doesn't, exits
    if os.path.isdir(data_dir):
        
        # list all dicom files (*.dcm) in folder
        dicomfile = [f for f in listdir(data_dir) if ((isfile(join(data_dir, f))) & (f.endswith(".dcm")))]
        
        # checks that there were actually dicoms in folder, if none, exits
        if len(dicomfile)>0:
            
            TE_array = []
            dicomfile_s = sorted(dicomfile, key = lambda x:x[-12:-4])
            # reads in dicoms
            for dyn, dicom in enumerate(dicomfile_s):
                dicomf=os.path.join(data_dir,dicom)
  
                # Get TE array          
                header = Header(dicomf)
                csa_TE = header.get('PerFrameFunctionalGroupsSequence')[0]['MREchoSequence'][0]
                TE = int(csa_TE.get('EffectiveEchoTime'))
                if TE not in TE_array:
                    TE_array.append(TE)
            TE_array.sort()

        else:
            print('\nNo Dicom files (*.dcm) found in directory\n')
            exit()
    else:
        print('\nDirectory does not exist, please double check directory location\n')
        exit()

    return TE_array

 