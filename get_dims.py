#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Mon Nov 21 10:50:42 2022

@author: kpa19

python get_dims
"""

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Nov 15 15:01:36 2022

@author: kpa19

read dicom in, get image array and list of TEs
"""

import os
from os import listdir
from os.path import isfile, join
import numpy as np
import SimpleITK as sitk
from dicom_parser import Header
import sys

def read(data_dir):
    # print('Processing scan: ',data_dir)
    # check if given directory exists, if it doesn't, exits
    if os.path.isdir(data_dir):
        
        # list all dicom files (*.dcm) in folder
        dicomfile = [f for f in listdir(data_dir) if ((isfile(join(data_dir, f))) & (f.endswith(".dcm")))]
        
        # checks that there were actually dicoms in folder, if none, exits
        if len(dicomfile)>0:
            
            # read in first dicom in list to get dicom dimensions 
            dicomf=os.path.join(data_dir,dicomfile[0])
            reader = sitk.ImageFileReader()
            reader.SetFileName(dicomf)
            reader.LoadPrivateTagsOn()
            main_image = reader.Execute()
            main_image_arr = sitk.GetArrayFromImage(main_image)
            size = main_image_arr.shape + (len(dicomfile),)

        else:
            print('\nNo Dicom files (*.dcm) found in directory\n')
            exit()
    else:
        print('\nDirectory does not exist, please double check directory location\n')
        exit()

    return list(size)

 