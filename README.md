# FOREST - Fetal Organ T2* Relaxometry at Low Field Strength
Here, we present an automatic pipeline for quantitatively analyzing fetal body organs using T2* relaxometry as described in Payette et al "An Automated Pipeline for Quantitative T2* Fetal Body MRI and Segmentation at Low Field" - https://link.springer.com/chapter/10.1007/978-3-031-43990-2_34

The pipieline was developed and tested on Ubuntu 20.04.

New: We have added an automatic pipeline for quantitatively analyzing fetal brain tissues using T2* relaxometry!!

Note: The script is currently a work in progress for sharing. 

## Software pre-requisites: 

•	SVRTK (https://github.com/SVRTK/SVRTK) - install as per instructions

•	Anaconda/miniconda

•	Mrtrix3 (https://www.mrtrix.org/download/linux-anaconda/)


There are two conda virtual environments (.yml) that need to be installed:

•	t2s_venv

•	venv_nnunetv2

The environments can be created with the following command: 

`$ conda env create -f t2s_venv.yml`

`$ conda env create -f venv_nnunetv2.yml`

Network weights can be found here: 

https://huggingface.co/kpayette/FOREST/tree/main/fetal_nnunet

The folder 'fetal_nnunet' should be placed in the same folder where the script 'forest_body.sh' is located. 

In addition to the software, the fetal body atlas used in the pipeline is the one described in https://www.sciencedirect.com/science/article/pii/S1361841522001311


## How to run the pipeline

1. Format the input data. The script requires a certain folder setup. All files for each subject should be in a folder called ‘ME’ (multi-echo), and within the ME folder there should be a folder for each sequence you want to process. These are called ‘n[sequence number]’ and they should contain the niftis. The nifti files should be 4D, each file should contain all the dynamics for each echo. The text ‘e1’, ‘e2’, ‘e3’, etc should be in the filename. 

   	`$ mkdir /home/user/case0001/ME`

   	`$ mkdir /home/user/case0001/ME/n[scan_number]`
   
   	i.e. `$ mkdir /home/user/case0001/ME/n17`
   
3. Place a text file in the nifti folder called 'tes.txt' that lists the echo times (can be in ms or s). 

4. Review all acquired dynamics, note which dynamics (if any) you would like to exclude from the reconstruction due to motion artefact, noise, etc. (dynamic numbering starts at 1 (NOT 0). If no dynamics are being excluded, put 0.
   
5.	 Run FOREST (for the Fetal Body):

 ` $ source forest_body.sh [complete path to folder with files] [scan_number] [number of echos] [dyn to exclude] `

         forest_body.sh /home/user/case0001 59 3 0 – no dynamics excluded
          i.e. forest_body.sh /home/user/case0001 59 3 2,3,4,5,12 – 2nd,3rd,4th, 5th, and 12th dynamic excluded from reconstruction

6. Run FOREST (for the Fetal Brain):

   [Work in Progress....coming soon!!]
   
7.	If the automated body masking fails, there is the option to use a manual mask. This can be added as an additional input argument:
           `$ source forest_body.sh  /home/user/case0001 59 3 0 /home/user/case0001/case0001_body_mask.nii.gz`


## Updates to the pipeline
There have been a few changes to the pipeline since the publication. There were minor modifications to how the registration and reorientation are done, and we also added some left/right splitting to the segmentation of the lungs, kidneys, and adrenal glands. 

## License
The this repository is distributed under the terms of the Apache License Version 2. The license enables usage in both commercial and non-commercial applications, without restrictions on the licensing applied to the combined work.

## Disclaimer
This software has been developed for research purposes only, and hence should not be used as a diagnostic tool. In no event shall the authors or distributors be liable to any direct, indirect, special, incidental, or consequential damages arising of the use of this software, its documentation, or any derivatives thereof, even if the authors have been advised of the possibility of such damage.

## Citation and acknowledgement

Please cite the following work if using this pipeline: 

Payette, K., Uus, A., Aviles Verdera, J., Avena Zampieri, C., Hall, M., Story, L., Deprez, M., Rutherford, M.A., Hajnal, J.V., Ourselin, S., Tomi-Tricot, R., Hutter, J., 2023. An Automated Pipeline for Quantitative T2* Fetal Body MRI and Segmentation at Low Field, in: Greenspan, H., Madabhushi, A., Mousavi, P., Salcudean, S., Duncan, J., Syeda-Mahmood, T., Taylor, R. (Eds.), Medical Image Computing and Computer Assisted Intervention – MICCAI 2023, Lecture Notes in Computer Science. Springer Nature Switzerland, Cham, pp. 358–367. https://doi.org/10.1007/978-3-031-43990-2_34

Please also cite the fetal body deformable reconstruction method work: 

Uus, A., Zhang, T., Jackson, L., Roberts, T., Rutherford, M., Hajnal, J.V., Deprez, M. (2020). Deformable Slice-to-Volume Registration for Motion Correction in Fetal Body MRI and Placenta. IEEE Transactions on Medical Imaging, 39(9), 2750-2759: http://dx.doi.org/10.1109/TMI.2020.2974844
   
   

