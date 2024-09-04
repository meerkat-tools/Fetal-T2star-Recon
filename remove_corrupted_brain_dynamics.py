#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""

create remove motion-corrupted files from concatenated echo files 
python remove_corrupted_brain_dynamics.py [file location] [sequence num] [number of echos] [dyn to exclude]

output: concat files e1, e2, e3 in folder 'files for recon' with the corrupted
motion dynamics removed. 

dyn to exclude counting starts at 1, dynamic numbers separated by a comma

concatenated echo files should be along in a folder

if no dynamics are to be excluded, [dyn to exclude] = 0


@author: kpa19
"""

import os
import sys
import nibabel as nib
from subprocess import call
import glob
import numpy as np

print('')
print('*************************************************')
print('Prepares multi-echo gradient echo images for DSVR')
print('Removes motion-corrupted dynamics, concatenates ')
print('all echoes, and performs denoising. Echos must ')
print('have "e1", "e2", "e3" etc. somewhere in filename.')

print('*************************************************')
print('')


# read in case num and scan num
case_dir = sys.argv[1] 
nr_me = sys.argv[2] 
nr_echos = sys.argv[3]
dyn_to_exclude = sys.argv[4]

print('processing scan ' + case_dir + ' and sequence number ' + str(nr_me))
print()
#setting up variables
nifti_directory = case_dir + '/ME/n' + nr_me + '/'
print('NIFTI directory: ' + nifti_directory)
print()

echo_filenames = []
for x in range(1,int(nr_echos)+1):
    echo_filenames.append(glob.glob(nifti_directory+'*e' + str(x) + '*')[0])


print('Echo files for processing: ')
print(echo_filenames)
print()

dyn_to_exclude = dyn_to_exclude.split(',')
excluded_dyns=[] 
for dyn in dyn_to_exclude:
    excluded_dyns.append(int(dyn)-1)
    
    
print('Dynamics to exclude: ')
print(dyn_to_exclude)
print()


if not os.path.exists(nifti_directory + 'files_for_brain_recon/'):
    os.mkdir(nifti_directory + 'files_for_brain_recon/')

for x,file in enumerate(echo_filenames):
    echo_img = nib.load(file)
    nifti_echo_img = echo_img.get_fdata()
    # print(nifti_echo_img.shape)
    if dyn_to_exclude != ['0']:     
        # remove corrupted dynamics       
        nifti_new_img = np.delete(nifti_echo_img,excluded_dyns,3)
    else:
        print('all dynamics are included in this reconstrucion.')
        nifti_new_img = nifti_echo_img
    new_image = nib.Nifti1Image(nifti_new_img, echo_img.affine, echo_img.header)
    nib.save(new_image, nifti_directory + 'files_for_brain_recon/e' +  str(x+1) + '.nii.gz')
    
print("New nifti echo dimensions: " + str(nifti_new_img.shape))


# read in echo files and concat everything together for denoising

if not os.path.exists(nifti_directory + 'processing_brain'):
    os.mkdir(nifti_directory + 'processing_brain')

# perform concatenation and denoising
if not os.path.isfile(nifti_directory + 'concat_denoised.nii.gz'):
    new_echos = os.listdir(nifti_directory + 'files_for_brain_recon/')

    for x,file in enumerate(new_echos):
        echo_img = nib.load(nifti_directory + 'files_for_brain_recon/' + file)
        nifti_echo_img = echo_img.get_fdata()
        if x ==0:
            nifti_concat=nifti_echo_img
        else:
            nifti_concat = np.concatenate((nifti_concat,nifti_echo_img),axis=3)
     
    concat_image = nib.Nifti1Image(nifti_concat, echo_img.affine, echo_img.header)
    nib.save(concat_image, nifti_directory + 'concat.nii.gz')
    
    #perform denoising
    call('dwidenoise ' + nifti_directory + 'concat.nii.gz' + ' ' + nifti_directory + 'concat_denoised.nii.gz', shell=True)
    
    
# create denoised echo files
concat_denoised_img = nib.load(nifti_directory + 'concat_denoised.nii.gz')
nifti_concat_denoised = concat_denoised_img.get_fdata()
num_dyn = int(nifti_concat_denoised.shape[3] / int(nr_echos))

print("Remaining dynamics: " + str(num_dyn) )

for x in range(0,int(nr_echos)):
    denoised_echo_nifti = nifti_concat_denoised[:,:,:,num_dyn*x:num_dyn*(x+1)]
    new_denoised_image = nib.Nifti1Image(denoised_echo_nifti, concat_denoised_img.affine, concat_denoised_img.header)
    nib.save(new_denoised_image, nifti_directory + 'processing_brain/e' +  str(x+1) + '_denoised.nii.gz')

call('rm ' + nifti_directory + 'concat_denoised.nii.gz',shell=True)
call('rm ' + nifti_directory + 'concat.nii.gz',shell=True)
    

    

        
    




