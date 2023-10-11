#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Tue Apr 25 17:11:59 2023

@author: kpa19

create concat files for reconstruction
python concat_files_new.py [case num] [sequence num]

output: concat files e1, e2, e3
"""


import os
import sys
from os import listdir
from os.path import isfile, join, dirname, exists
import numpy as np
import nibabel as nib
import get_TE
import get_dims
from scipy.optimize import least_squares 
from subprocess import call
# from numba import jit

print('')
print('*****************************')
print('Script for T2* Pre-processing')
print('Prepares T2* images for DSVR')
print('*****************************')
print('')



fm_id = sys.argv[1] 
# '59'
nr_me = sys.argv[2] 

freemax_info = '/home/kpa19/t2s_body/'
freemax_data = '/home/jhu14/Dropbox/placentaJhu/'


denoised_filenames=[]

print('processing scan: ' + fm_id + '\n')

case_dir = freemax_data + fm_id
data_directory = case_dir + '/ME/d' + nr_me + '/'

# need a nifti in order to save with nibabel
# or need dicom directory in order to get TE times 
nifti_directory = case_dir + '/ME/n' + nr_me + '/'
print(nifti_directory)

merged_filename = nifti_directory + fm_id + '_all_echos_denoised_concat.nii.gz'
merged = nifti_directory + fm_id + '_all_echos_concat.nii.gz'
print(merged_filename)
text_files = ''
files_to_process = []

for file in sorted(os.listdir(nifti_directory)):
    if 's0' + nr_me in file:
        files_to_process.append(file)
        text_files += ' ' + nifti_directory + file 


# get TE, image dimensions
te = get_TE.read(data_directory)
nO_echos = len(te)
size = get_dims.read(data_directory)
nO_slices = size[0]

x_dim = size[1]
y_dim = size[2]
print(te)
# print(size)
# exit()
te = (np.array(te,dtype=float))[0:3]

print(text_files)

if not os.path.isfile(merged_filename):
    print('Merging dynamics in ' + nifti_directory)
    call('fslmerge -t ' + merged + ' ' + text_files, shell=True)
    print('denoising images')
    call('dwidenoise ' + merged + ' ' + merged_filename, shell=True)
   
    
else:
    print('Concatenated and denoised file exists')


dyn_count = 0
# create individual denoised images from concatenated file
for dyn in files_to_process:
    img = nib.load(merged_filename)
    n_img = img.get_fdata()
    # n_img_header = img.header

    denoised_img_path = nifti_directory + fm_id +"_" + str(nr_me) + '_dyn_' + str(dyn[5:8]) + '_denoised.nii.gz'
    denoised_filenames.append(denoised_img_path)
    if not os.path.isfile(denoised_img_path):   
        print('file to take header from: ' + nifti_directory + dyn)
        img2 = nib.load(nifti_directory + dyn)
        n_img2 = img2.get_fdata()
        dyn_img = n_img[:,:,:,dyn_count:dyn_count+3]
        
        if nO_echos == 4:
            img_denoised = nib.Nifti1Image(n_img[:,:,:,dyn_count:dyn_count+4], img2.affine, img2.header)
            nib.save(img_denoised, denoised_img_path)
            dyn_count+=4
        else:
            img_denoised = nib.Nifti1Image(n_img[:,:,:,dyn_count:dyn_count+3], img2.affine, img2.header)
            nib.save(img_denoised, denoised_img_path)
            dyn_count+=3
        print('new count: ' + str(dyn_count))
    else:
        print(denoised_img_path + ' already exists.')
        if nO_echos == 4:
            dyn_count+=4
        else:
            dyn_count+=3
# exit()            


merged_folder = nifti_directory + fm_id + '/'
# merge 2nd echo of each dynamic into one file
# merge t2maps of each dynamic into one file
if not os.path.isfile(merged_folder + fm_id + '_e2_' + str(len(denoised_filenames)) + '_concat.nii.gz'):
    # print(denoised_filenames)
    denoised_echos = ''
    denoised_echos_0 = ''
    denoised_echos_2 = ''
    # create merged files for reconstruction
    if not os.path.exists(nifti_directory + 'echos_denoised'):
        os.mkdir(nifti_directory + 'echos_denoised')
    
    # merged_folder = nifti_directory + fm_id + '_denoised_' + str(len(denoised_filenames)) + '/'
    if not os.path.exists(nifti_directory + fm_id):
        os.mkdir(nifti_directory + fm_id)
        
    for file in denoised_filenames:
        
        # split denoised images into separate echos
        # print('fslsplit ' + file + ' ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e')
        call('fslsplit ' + file + ' ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e', shell=True)
        denoised_echos +=  ' ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e0001.nii.gz'
        denoised_echos_0 +=  ' ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e0000.nii.gz'
        denoised_echos_2 +=  ' ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e0002.nii.gz'
        #call('rm ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e0000.nii.gz',shell=True)
        #call('rm ' + nifti_directory + 'echos_denoised/s0' + nr_me +'_' + file[-19:-16] + '_e0002.nii.gz',shell=True)   
        # exit()
    # print()
    print(denoised_echos)

    call('fslmerge -t ' + merged_folder + fm_id + '_e2_' + str(len(denoised_filenames)) + '_concat.nii.gz' + ' ' + denoised_echos, shell=True)
    call('fslmerge -t ' + merged_folder + fm_id + '_e1_' + str(len(denoised_filenames)) + '_concat.nii.gz' + ' ' + denoised_echos_0, shell=True)
    call('fslmerge -t ' + merged_folder + fm_id + '_e3_' + str(len(denoised_filenames)) + '_concat.nii.gz' + ' ' + denoised_echos_2, shell=True)
    
    # remove intermediary files
    call('rm ' + merged, shell=True) 
    call('rm ' + merged_filename, shell=True)
else:
    print('Merged files already exist for ' + fm_id)



