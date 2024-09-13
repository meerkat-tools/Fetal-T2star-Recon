#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Fri Apr 21 09:51:43 2023

@author: kpa19

create T2* maps
input: multi-echo reconstructions
python t2s_fitting_from_reconstructions.py [case_id] [sequence number] [num echos]
example:
python t2s_fitting_from_reconstructions.py fm0046 59
three echos assumed

output: T2* map of reconstructed echos

"""

import os
import sys
from os import listdir
from os.path import isfile, join, dirname, exists
import numpy as np
import nibabel as nib
import get_TE
from scipy.optimize import least_squares 
from subprocess import call

# from numba import jit

print('')
print('*****************************')
print('Script for T2* Reconstruction Fitting')
print('*****************************')
print('')


# T2 fit function
def t2fit(X,data,TEs):
    TEs=np.array(TEs,dtype=float)
    X=np.array(X,dtype=float)
    S = X[0] * ((np.exp(-(TEs/X[1]))))                  
    return data - S


case_dir = sys.argv[1] 
nr_me = sys.argv[2] 
num_echos =sys.argv[3]

nr_me = str(nr_me)

print('processing scan ' + case_dir + ' and sequence number ' + str(nr_me) + ' with ' + str(num_echos) + ' echos.')
print()

# nifti_directory = case_dir + '/ME/n' + nr_me + '/reconstructions/'
nifti_directory = case_dir + '/ME/n' + nr_me + '/processing_brain/out-proc/'
print('NIFTI directory: ' + nifti_directory)

# get echo filenames
echo_filenames = []
for echo in range(int(num_echos)):
    echo_location = nifti_directory + 'recon_struct_brain_e0' + str(echo) + '.nii.gz'
    # echo_location = 'recon_struct_brain_e0' + str(echo) + '.nii.gz'
    echo_img = nib.load(echo_location)
    nifti_echo_img = echo_img.get_fdata()
    nifti_echo_img[nifti_echo_img < 0] = 0 
    nifti_echo = nib.Nifti1Image(nifti_echo_img, echo_img.affine, echo_img.header)
    nib.save(nifti_echo, echo_location)
    
    

    echo_filenames.append(echo_location)

dicom_directory = case_dir + '/ME/d' + nr_me + '/'

t2map_path =  nifti_directory + 't2map_from_recon_brain.nii.gz'

for x,file in enumerate(echo_filenames):
    echo_img = nib.load(file)
    nifti_echo_img = echo_img.get_fdata()
    nifti_echo_img = nifti_echo_img [..., np.newaxis]
    if x == 0:
        nifti_concat=nifti_echo_img
    else:
        nifti_concat = np.concatenate((nifti_concat,nifti_echo_img),axis=3)

print(nifti_concat.shape)

T2_map = np.zeros((nifti_concat.shape))
print(T2_map.shape)
nO_slices=nifti_concat.shape[2]
x_dim=nifti_concat.shape[0]
y_dim=nifti_concat.shape[1]

te = get_TE.read(dicom_directory)
# te = [42, 107, 172]

print(te)
print(x_dim, y_dim, nO_slices)

for iz in range(0,nO_slices):
    print(iz,end='-')
    print(iz)
    for ix in range(0,x_dim):
        for iy in range(0,y_dim):
            if nifti_concat[ix,iy,iz,0] != 0:
                pix_array = np.array(nifti_concat[ix,iy,iz, :], dtype=float)
                param_init = np.squeeze([pix_array[2], np.average(te)])
                # print(pix_array)
                result = least_squares(t2fit, param_init, args = (pix_array,te), bounds=([0,0],[10000,1000]))
                T2_map[ix,iy,iz, 0]= result.x[0]
                T2_map[ix,iy,iz, 1]= result.x[1]
            else:
                T2_map[ix,iy,iz, 0]= 0
                T2_map[ix,iy,iz, 1]= 0
t2_val = T2_map[:,:,:,1]
fit_result = nib.Nifti1Image(t2_val, echo_img.affine, echo_img.header)
nib.save(fit_result, t2map_path)
    
        
    
 


    

    
                
                
            
    
    

        
                    
    
    
           
    
