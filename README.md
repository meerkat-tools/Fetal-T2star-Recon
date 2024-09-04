# FOREST - Fetal Organ T2* Relaxometry at Low Field Strength
Here, we present an automatic pipeline for quantitatively analyzing fetal body organs using T2* relaxometry as described in Payette et al "An Automated Pipeline for Quantitative T2* Fetal Body MRI and Segmentation at Low Field" - https://link.springer.com/chapter/10.1007/978-3-031-43990-2_34

The pipieline was developed and tested on Ubuntu 20.04.

New: We have added an automatic pipeline for quantitatively analyzing fetal brain tissues using T2* relaxometry!!

Note: The script is currently a work in progress for sharing. We are in the process of making the pipeline more distributable via a Docker container

## Software pre-requisites: 

MIRTK/SVRTK (https://github.com/SVRTK/SVRTK) install as per instructions
MRTrix3 (https://www.mrtrix.org/download/)

In addition to the software, the fetal body atlas ased in the pipeline is the one described in https://www.sciencedirect.com/science/article/pii/S1361841522001311

nnUNet

MONAI

Python libraries required: 

numpy, nibabel, scipy.optimize, subprocess.call, SimpleITK, dicom_parser


## How to run the pipeline

1. Ensure that all multi-echo multi-gradient dynamics to be used as part of the pipeline are located in the same folder (dynamics with excessive artefact should be removed).
2. A separate folder containing the DICOMS should be created 
3. Run the pipeline with the following command:

   `./fetal_t2star_multi-echo_reconstruction_pipeline.sh [folder containing .nii.gz dyamics] [sequence number]`


## License
The this repository is distributed under the terms of the Apache License Version 2. The license enables usage in both commercial and non-commercial applications, without restrictions on the licensing applied to the combined work.

## Disclaimer
This software has been developed for research purposes only, and hence should not be used as a diagnostic tool. In no event shall the authors or distributors be liable to any direct, indirect, special, incidental, or consequential damages arising of the use of this software, its documentation, or any derivatives thereof, even if the authors have been advised of the possibility of such damage.

## Citation and acknowledgement

Please cite the following work if using this pipeline: 

Payette, K., Uus, A., Aviles Verdera, J., Avena Zampieri, C., Hall, M., Story, L., Deprez, M., Rutherford, M.A., Hajnal, J.V., Ourselin, S., Tomi-Tricot, R., Hutter, J., 2023. An Automated Pipeline for Quantitative T2* Fetal Body MRI and Segmentation at Low Field, in: Greenspan, H., Madabhushi, A., Mousavi, P., Salcudean, S., Duncan, J., Syeda-Mahmood, T., Taylor, R. (Eds.), Medical Image Computing and Computer Assisted Intervention – MICCAI 2023, Lecture Notes in Computer Science. Springer Nature Switzerland, Cham, pp. 358–367. https://doi.org/10.1007/978-3-031-43990-2_34

Please also cite the fetal body deformable reconstruction method work: 

Uus, A., Zhang, T., Jackson, L., Roberts, T., Rutherford, M., Hajnal, J.V., Deprez, M. (2020). Deformable Slice-to-Volume Registration for Motion Correction in Fetal Body MRI and Placenta. IEEE Transactions on Medical Imaging, 39(9), 2750-2759: http://dx.doi.org/10.1109/TMI.2020.2974844
   
   

