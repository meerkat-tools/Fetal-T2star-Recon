# Fetal-T2star-Recon
Here, we present an automatic pipeline for quantitatively analyzing fetal body organs using T2* relaxometry as described in Payette et al "An Automated Pipeline for Quantitative T2* Fetal Body MRI and Segmentation at Low Field" - https://link.springer.com/chapter/10.1007/978-3-031-43990-2_34

The pipieline was developed and tested on Ubuntu 20.04.

Note: The script is currently a work in progress for sharing, everything is hard-coded for local computers. We are in the process of making the pipeilne more distributable via a Docker container

## Software pre-requisites: 

MIRTK/SVRTK (https://github.com/SVRTK/SVRTK) install as per instructions
MRTrix3 (https://www.mrtrix.org/download/)

In addition to the software, the fetal body atlas ased in the pipelineis the one described in https://www.sciencedirect.com/science/article/pii/S1361841522001311

nnUNet
MONAI
fsl

Python libraries required: 

numpy, nibabel, scipy.optimize, subprocess.call, SimpleITK, dicom_parser


## How to run the pipeline

1. Ensure that all multi-echo multi-gradient dynamics to be used as part of the pipeline are located in the same folder (dynamics with excessive artefact should be removed).
2. A separate folder containing the DICOMS should be created 
3. Run the pipeline with the following command:

   `./fetal_t2star_multi-echo_reconstruction_pipeline.sh [folder containing .nii.gz dyamics] [sequence number]`



   
   

