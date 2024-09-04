#!/bin/bash


# how to run:
# ./multi_echo_brain_reconstruction_kcl.sh [complete path to folder with files] [scan_number] [number of echos] [dyn to exclude]
# ex - ./multi_echo_brain_reconstruction.sh /home/user/case_number_001 59 3 1,2,3
# this example is for a 3 echo sequence where the first 3 dynamics are motion corrupted  
# if no dynamics are bad, put '0'
# Format of the input files:
# *e1*.nii.gz*, *e2*.nii.gz, *ex*.nii.gz, where x = number of echos in the 
# multi-echo sequence to be fitted. Each echo file is 4D, containing all 
# of the dynamics. For example, if e1.nii.gz is 256 x 256 x 80 x 20, there 
# are 20 dynamics.
# Input File Structure:
# folder structure assumed in the path to files:
# Folder with multi-echo files in nifti format: ME/n[scan_number]/*nii.gz
# Folder with multi-echo dicom files: ME/d[scan_number]/*.dcm


# setting up directories
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo "Running script: ${SCRIPT_DIR}/multi-echo_brain_reconstruction.sh"
cd $SCRIPT_DIR

monai_check_path_roi=${SCRIPT_DIR}/monai-checkpoints-unet-t2s-brain-body-placenta-loc-3-lab
check_path_roi_reo_4lab=${SCRIPT_DIR}/monai-checkpoints-unet-notmasked-body-reo-4-lab

# folder with input files to be processed
org_files=$1
nr_me=$2
nr_echos=$3
dyn_to_exclude=$4

echo ""
echo "Processing Scan: ${org_files}"
echo "Sequence number to process: ${nr_me}"
echo "Number of echos: ${nr_echos}"
echo "dynamics to exclude: ${dyn_to_exclude}"
echo ""

# setting up stuff
monai_check_path_roi=${SCRIPT_DIR}/monai-checkpoints-unet-t2s-brain-body-placenta-loc-3-lab
monai_check_path_brain_roi=${SCRIPT_DIR}/monai-checkpoints-unet-svr-brain-reo-5-lab


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Concatenating and denoising input files ..."
echo

conda activate Segmentation_FetalMRI_MONAI
python remove_corrupted_brain_dynamics.py $org_files $nr_me $nr_echos $dyn_to_exclude

cd $org_files/ME/n$nr_me

if [[ ! -d processing_brain ]];then
	echo "ERROR: NO INPUT FILES FOUND !!!!" 
	exit
fi

if [[ ! -d reconstructions ]];then
	mkdir reconstructions
else
    echo "dir exists"
fi


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "INPUT FILES ..."
echo

cd processing_brain
echo "files to be processed: " ${org_files}

num_packages=1

dims=$(mrinfo ${org_files}/ME/n${nr_me}/processing_brain/e1_denoised.nii.gz -spacing)
thickness=( $dims )
default_thickness=$(printf "%.1f" ${thickness[0]})

default_resolution=1.2

echo
echo "Slice thickness: ${default_thickness}"
echo "Reconstruction Resolution: ${default_resolution}"
echo

roi_recon="SVR"
roi_names="brain"

# stack_names: list of filenames of concat echo files
stack_names=$(ls *e*.nii*)
# all_og_stacks: list of stack_names
IFS=$'\n' read -rd '' -a all_og_stacks <<<"$stack_names"

echo "Echo files: " ${all_og_stacks[*]}

# processing multi-echo concat files, iterates through the echo concat files
for ((i=0;i<${#all_og_stacks[@]};i++));
do
    echo "-----------------------------------------------------------------------------"
    echo
    echo "Iteration $i - ${all_og_stacks[i]}"
    echo 

    mkdir stack-t2s-e0${i}
    mkdir stack-t2s-e0${i}/org-files-packages
    mkdir stack-t2s-e0${i}/original-files
    
    # sets voxels = nan and voxels >100000000 to 0
	mirtk nan ${all_og_stacks[i]}  100000000
	# set time resolution to 10ms
	mirtk edit-image ${all_og_stacks[i]}  ${all_og_stacks[i]} -dt 10 
	
	# rescales images to be between 0 and 1500
    mirtk convert-image ${all_og_stacks[i]} ${all_og_stacks[i]::-7}_rescaled.nii.gz -rescale 0 1500
	mirtk extract-image-region ${all_og_stacks[i]} stack-t2s-e0${i}/original-files/t2s -split $nr_echos 	
    mirtk extract-image-region ${all_og_stacks[i]::-7}_rescaled.nii.gz stack-t2s-e0${i}/org-files-packages/${i}-t2s-e0${i} -split $nr_echos 	

done
 
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "3D UNET SEGMENTATION ..."
echo

echo 
echo "-----------------------------------------------------------------------------"
echo "GLOBAL ... brain / body / placenta"
echo 

#perform segmentations on the 2nd echo (e01) and apply them to the rest of the echos
mkdir stack-t2s-e01/monai-segmentation-results-global

res=128
monai_lab_num=3

#calculate number of files to be segmented    
Num_stacks=$(find stack-t2s-e01/org-files-packages/ -name "*.nii*" | wc -l)
echo "Number of stacks to segment: " $Num_stacks
    
cd stack-t2s-e01/
# prepare files for segmentation (changes files to 128x128x128)
mirtk prepare-for-monai res-files/ stack-files/ global-stack-info.json global-stack-info.csv ${res} ${Num_stacks} org-files-packages/*nii*
# segment the files into 3 labels: body, brain, placenta
python ${SCRIPT_DIR}/run_monai_unet_segmentation-2022.py $(pwd)/ ${monai_check_path_roi}/ global-stack-info.json monai-segmentation-results-global ${res} ${monai_lab_num}

      
out_mask_names=$(ls monai-segmentation-results-global/cnn-*.nii*)
out_stack_names=$(ls original-files/*.nii*)
    
IFS=$'\n' read -rd '' -a all_masks <<<"$out_mask_names"
IFS=$'\n' read -rd '' -a all_stacks <<<"$out_stack_names"
cd ../

echo    
echo "Global Masks: " ${all_masks[*]}
echo "Files that were segmented: " ${all_stacks[*]}
echo
     
# Perform segmentation for just the first echo

for ((k=0; k<3; k++));
do
mkdir stack-t2s-e0${k}/recon-stacks-brain
mkdir stack-t2s-e0${k}/recon-masks-brain
mkdir stack-t2s-e0${k}/global-roi-masks
done
i=1
#extract the individual labels, dilate them, crop input images for brain   
for ((b=0;b<${#all_stacks[@]};b++));
do 
	jj=$((${b}+1000))
    
    # extracts the labels for brain and saves them
    #input: monai-segmentation-results-global/cnn-* output: global-roi-masks/mask-brain-${jj}-0.nii.gz
	mirtk extract-label stack-t2s-e0${i}/${all_masks[$b]} stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz 2 2 
	
	# extracts the largest connected components from the labelmap
	#input: global-roi-masks/mask-brain-${jj}-0.nii.gz output: global-roi-masks/mask-brain-${jj}-0.nii.gz
	mirtk extract-connected-components stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz
	
	# dilate the extracted label
	#input: global-roi-masks/mask-brain-${jj}-0.nii.gz output: global-roi-masks/mask-brain-${jj}-0.nii.gz
	mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz -iterations 2
	
	# erode label
	#input: global-roi-masks/mask-brain-${jj}-0.nii.gz output: global-roi-masks/mask-brain-${jj}-0.nii.gz
    mirtk erode-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz -iterations 2
    
    # dilate label again, creates a temporary very dilated label image (dl-brain-m.nii.gz) that gets written over in every loop
    #input: global-roi-masks/mask-brain-${jj}-0.nii.gz output: stack-t2s-e0${i}/dl-brain-m.nii.gz
	mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/dl-brain-m.nii.gz -iterations 7
    
    for ((k=0; k<3; k++));
    do
        
    	#input: stack-files/*.nii* mask: dl-brain-m.nii.gz output: recon-stacks-brain/cropped-stack-${jj}.nii.gz 
    	mirtk crop-image stack-t2s-e0${k}/${all_stacks[$b]} stack-t2s-e0${i}/dl-brain-m.nii.gz stack-t2s-e0${k}/recon-stacks-brain/cropped-stack-${jj}.nii.gz
    	mirtk crop-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/dl-brain-m.nii.gz stack-t2s-e0${k}/recon-masks-brain/cropped-mask-${jj}.nii.gz
    	
    	#mask image
    	#input: recon-stacks-brain/cropped-stack-${jj}.nii.gz mask: dl-brain-m.nii.gz output: recon-stacks-brain/cropped-stack-${jj}.nii.gz
    	mirtk mask-image stack-t2s-e0${k}/recon-stacks-brain/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/dl-brain-m.nii.gz stack-t2s-e0${k}/recon-stacks-brain/cropped-stack-${jj}.nii.gz
       
    done 
done


echo
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "RUNNING RECONSTRUCTION ..."
echo

echo "ROI : " ${roi_names} " ... "
echo


cd stack-t2s-e02/

#calculate the median average template
nStacks=$(ls recon-stacks-brain/*.nii* | wc -l)

mirtk average-images selected_template.nii.gz recon-stacks-brain/*.nii*
mirtk resample-image selected_template.nii.gz selected_template.nii.gz -size 1 1 1
mirtk average-images selected_template.nii.gz recon-stacks-brain/*.nii* -target selected_template.nii.gz

mirtk average-images average_mask_cnn.nii.gz recon-masks-brain/*.nii* -target selected_template.nii.gz
mirtk convert-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -short
mirtk dilate-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 2
    	
mirtk mask-image selected_template.nii.gz average_mask_cnn.nii.gz masked-selected_template.nii.gz


cd ../
echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING SVR" 
echo "-----------------------------------------------------------------------------"
echo

number_of_stacks=$(ls stack-t2s-e01/recon-stacks-brain/*.nii* | wc -l)
mkdir out-proc
cd out-proc
echo mirtk reconstruct ${roi_recon}-output.nii.gz ${number_of_stacks} ../stack-t2s-e02/recon-stacks-brain/*.nii.gz --mc_n 2 --mc_stacks ../stack-t2s-e00/recon-stacks-brain/*.nii.gz ../stack-t2s-e01/recon-stacks-brain/*.nii.gz -mask ../stack-t2s-e02/average_mask_cnn.nii.gz -default_thickness ${default_thickness} -iterations 2 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching

mirtk reconstruct ${roi_recon}-output.nii.gz ${number_of_stacks} ../stack-t2s-e02/recon-stacks-brain/*.nii.gz --mc_n 2 --mc_stacks ../stack-t2s-e00/recon-stacks-brain/*.nii.gz ../stack-t2s-e01/recon-stacks-brain/*.nii.gz -mask ../stack-t2s-e02/average_mask_cnn.nii.gz -default_thickness ${default_thickness} -iterations 2 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching

echo "-----------"
echo "segmenting landmarks"
echo "-----------"

monai_lab_num=5
brain_recon=${org_files}/*_t2_recon_2.nii.gz
mkdir t2recon-labelmaps/
mkdir met2srecon-labelmaps/

mirtk prepare-for-monai res-t2recon stack-t2recon t2recon-info.json t2recon-info.csv ${res} 1 ${brain_recon}
python ${SCRIPT_DIR}/run_monai_unet_segmentation-2022.py $(pwd)/ ${monai_check_path_brain_roi}/ t2recon-info.json t2recon-labelmaps/ ${res} ${monai_lab_num}

mirtk prepare-for-monai res-met2srecon stack-met2srecon met2srecon-info.json met2srecon-info.csv ${res} 1 SVR-output.nii.gz
python ${SCRIPT_DIR}/run_monai_unet_segmentation-2022.py $(pwd)/ ${monai_check_path_brain_roi}/ met2srecon-info.json met2srecon-labelmaps/ ${res} ${monai_lab_num}

q1=1; q2=2; q3=3; q4=4; q5=5

new_roi=(1 2 3 4 5)
mkdir t2recon_roi
mkdir met2srecon_roi

# extracts each of the 5 labels
for ((j=0;j<${#new_roi[@]};j++));
do

    q=${new_roi[$j]}
    #extract each label, store in local roi folder
    # input: monai-segmentation-results-local/cnn-*.nii*; output: local-roi-masks/mask-brain-${jj}-${q}.nii.gz
	mirtk extract-label t2recon-labelmaps/*gz t2recon_roi/mask-brain-${q}.nii.gz ${q} ${q}
	mirtk extract-label met2srecon-labelmaps/*gz met2srecon_roi/mask-brain-${q}.nii.gz ${q} ${q}
	# input: local-roi-masks/mask-brain-${jj}-${q}.nii.gz; output: local-roi-masks/mask-brain-${jj}-${q}.nii.gz
	mirtk extract-connected-components t2recon_roi/mask-brain-${q}.nii.gz t2recon_roi/mask-brain-${q}.nii.gz
    mirtk extract-connected-components met2srecon_roi/mask-brain-${q}.nii.gz met2srecon_roi/mask-brain-${q}.nii.gz
    
done


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "LANDMARK-BASED REGISTRATION ..."
echo

mkdir reo-dofs
# creates an affine dof matrix 
mirtk init-dof init.dof  

z1=1; z2=2; z3=3; z4=4; z5=5
	
total_n_landmarks=5
selected_n_landmarks=5

#mirtk register-landmarks ${template_path}/in-atlas-space-dsvr.nii.gz stack-t2s-e0${i}/stack-files/stack-${jj}.nii.gz stack-t2s-e0${i}/init.dof stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof ${total_n_landmarks} ${selected_n_landmarks} ${template_path}/final-mask-${z1}.nii.gz ${template_path}/final-mask-${z2}.nii.gz ${template_path}/final-mask-${z3}.nii.gz ${template_path}/final-mask-${z4}.nii.gz  stack-t2s-e0${i}/organ-roi-masks/mask-${jj}-${z1}.nii.gz stack-t2s-e0${i}/organ-roi-masks/mask-${jj}-${z2}.nii.gz stack-t2s-e0${i}/organ-roi-masks/mask-${jj}-${z3}.nii.gz stack-t2s-e0${i}/organ-roi-masks/mask-${jj}-${z4}.nii.gz 
# Function for rigid landmark-based point registration of two images (the 
# minimum number of landmarks is 4).
# The landmark corrdinates are computed as the centre of the input binary masks
# Usage: mirtk register-landmarks [target_image] [source_image] [init_dof] 
# [output_dof_name] [number_of_landmarks_to_be_used_for_registration] 
# [number_of_input_landmarks_n] [target_landmark_image_1] ... [target_landmark_image_2] 
# [source_landmark_image_1] ... [source_landmark_image_n]
# register generated local masks to template masks
    
echo "registering me-t2s recon to t2 recon"

mirtk register-landmarks ${brain_recon} met2srecon_roi/mask-brain-${z1}.nii.gz init.dof reo-dofs/dof-to-atl.dof ${total_n_landmarks} ${selected_n_landmarks} t2recon_roi/mask-brain-${z1}.nii.gz t2recon_roi/mask-brain-${z2}.nii.gz t2recon_roi/mask-brain-${z3}.nii.gz t2recon_roi/mask-brain-${z4}.nii.gz t2recon_roi/mask-brain-${z5}.nii.gz met2srecon_roi/mask-brain-${z1}.nii.gz met2srecon_roi/mask-brain-${z2}.nii.gz met2srecon_roi/mask-brain-${z3}.nii.gz met2srecon_roi/mask-brain-${z4}.nii.gz met2srecon_roi/mask-brain-${z5}.nii.gz 
# take dof file and apply it to the header of the me-t2s recon
mirtk edit-image SVR-output.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e02.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
mirtk transform-image ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e02.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e02.nii.gz -target ${brain_recon}

mirtk edit-image mc-output-0.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e00.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
mirtk transform-image ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e00.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e00.nii.gz -target ${brain_recon}

mirtk edit-image mc-output-1.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e01.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
mirtk transform-image ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e01.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_brain_e01.nii.gz -target ${brain_recon}

  
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Brain Segmentation ..."
echo


# segment images
source ${SCRIPT_DIR}/run-segmentation-brain_bounti.sh ${org_files} ${nr_me}


# recon T2* fitting

python ${SCRIPT_DIR}/t2s_brain_fitting.py ${org_files} ${nr_me}

cd ../
mirtk edit-image reconstructions/${org_files}_${nr_me}_recon_struct_brain_e00.nii.gz reconstructions/${org_files}_${nr_me}_recon_struct_brain_e00.nii.gz -origin 0 0 0 
mirtk edit-image reconstructions/${org_files}_${nr_me}_recon_struct_brain_e01.nii.gz reconstructions/${org_files}_${nr_me}_recon_struct_brain_e01.nii.gz -origin 0 0 0 
mirtk edit-image reconstructions/${org_files}_${nr_me}_recon_struct_brain_e02.nii.gz reconstructions/${org_files}_${nr_me}_recon_struct_brain_e02.nii.gz -origin 0 0 0    
mirtk edit-image reconstructions/${org_files}_${nr_me}_t2map_from_recon_brain.nii.gz reconstructions/${org_files}_${nr_me}_t2map_from_recon_brain.nii.gz -origin 0 0 0    

conda deactivate


cd $SCRIPT_DIR
