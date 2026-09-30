#!/bin/bash


# how to run:
# source forest_brain.sh [complete path to folder with files] [scan_number] [number of echos] [dyn to exclude]
# ex - source forest_brain.sh /home/user/case_number_001 59 3 1,2,3
# this example is for a 3 echo sequence where the first 3 dynamics are motion corrupted
# if no dynamics are bad, put '0'
# ex - source forest_brain.sh /home/user/case_number_001 59 3 0
# if the brain masking fails, there is the option to use a manual mask. This can be added as an additional input argument:
# source forest_brain.sh  /home/user/case_number_001 59 3 0 /home/user/case001/case001_brain_mask.nii.gz
# Format of the input files:
# *e1*.nii.gz*, *e2*.nii.gz, *ex*.nii.gz, where x = number of echos in the 
# multi-echo sequence to be fitted. Each echo file is 4D, containing all 
# of the dynamics. For example, if e1.nii.gz is 256 x 256 x 80 x 20, there 
# are 20 dynamics.
# Input File Structure:
# folder structure assumed in the path to files:
# Folder with multi-echo files in nifti format: ME/n[scan_number]/*nii.gz
# In the ME/n[scan_number] folder, place a .txt file listing the echo times in ms


# setting up directories
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo "Running script: ${SCRIPT_DIR}/forest_brain.sh"
cd $SCRIPT_DIR

# folder with input files to be processed
org_files=$1
nr_me=$2
nr_echos=$3
dyn_to_exclude=$4

if [ -n "$5" ]

then
brain_mask=$5
echo "Manual brain mask exists: " ${brain_mask}
fi


echo ""
echo "Processing Scan: ${org_files}"
echo "Sequence number to process: ${nr_me}"
echo "Number of echos: ${nr_echos}"
echo "dynamics to exclude: ${dyn_to_exclude}"
echo ""

export nnUNet_raw="$SCRIPT_DIR/fetal_nnunet/nnUNet_raw/"
export nnUNet_results="$SCRIPT_DIR/fetal_nnunet/nnUNet_results/"
export nnUNet_preprocessed="$SCRIPT_DIR/fetal_nnunet/nnUNet_preprocessed/"

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Concatenating and denoising input files ..."
echo

conda activate t2s_venv

if [[ -d $org_files/ME/n$nr_me/processing_brain ]];then
	rm -r $org_files/ME/n$nr_me/processing_brain
fi

roi_recon="SVR"
roi_names="brain"

python remove_corrupted_dynamics.py $org_files $nr_me $nr_echos $dyn_to_exclude $roi_names

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
	nan ${all_og_stacks[i]}  100000000
	# set time resolution to 10ms
	edit-image ${all_og_stacks[i]}  ${all_og_stacks[i]} -dt 10 
	
	# rescales images to be between 0 and 1500
    convert-image ${all_og_stacks[i]} ${all_og_stacks[i]::-7}_rescaled.nii.gz -rescale 0 1500
	extract-image-region ${all_og_stacks[i]} stack-t2s-e0${i}/original-files/t2s -split 3 	
    extract-image-region ${all_og_stacks[i]::-7}_rescaled.nii.gz stack-t2s-e0${i}/org-files-packages/${i}-t2s-e0${i} -split 3 	

done
 
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo " brain segmentation ... "
echo 

conda deactivate
conda activate venv_nnunetv2
i=2
#perform segmentations on the 2nd echo (e01) and apply them to the rest of the echos
mkdir stack-t2s-e0${i}/brain-segmentation-results
mkdir stack-t2s-e0${i}/brain-masks-final

for ((k=0; k<$nr_echos; k++)); do

for rename_file in $(ls stack-t2s-e0${k}/org-files-packages/); do 
mv stack-t2s-e0${k}/org-files-packages/$rename_file stack-t2s-e0${k}/org-files-packages/${rename_file::-7}_0000.nii.gz
done

mkdir stack-t2s-e0${k}/recon-stacks-brain
done


if [ -n "$5" ]

then

echo "Use manual brain mask instead of automatically generating them: " ${brain_mask}
for orig_file_img in $(ls stack-t2s-e0${i}/org-files-packages); do 
cp ${brain_mask} stack-t2s-e0${i}/brain-masks-final/${orig_file_img::-12}.nii.gz

done



else

cd stack-t2s-e02/
nnUNetv2_predict -d Dataset602_brainsv2 -i org-files-packages/ -o brain-segmentation-results -f  0 1 2 3 4 -tr nnUNetTrainer -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i brain-segmentation-results -o brain-masks-final -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset602_brainsv2/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset602_brainsv2/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json
cd ../

for dilate_file in $(ls stack-t2s-e0${i}/brain-masks-final/); do 

# dilate the extracted label
dilate-image stack-t2s-e0${i}/brain-masks-final/$dilate_file stack-t2s-e0${i}/brain-masks-final/$dilate_file -iterations 1
done
 

fi
conda deactivate
conda activate t2s_venv


# crop images for reconstruction
for dilate_file in $(ls stack-t2s-e0${i}/brain-masks-final/); do
for ((k=0; k<$nr_echos; k++)); do
mask-image stack-t2s-e0${k}/org-files-packages/${k}${dilate_file:1:7}${k}${dilate_file:9:-7}_0000.nii.gz stack-t2s-e0${i}/brain-masks-final/$dilate_file stack-t2s-e0${k}/recon-stacks-brain/${k}${dilate_file:1:7}${k}${dilate_file:9:-7}_cropped.nii.gz
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


cd stack-t2s-e0${i}/

#calculate the median average template
nStacks=$(ls recon-stacks-brain/*.nii* | wc -l)

average-images selected_template.nii.gz recon-stacks-brain/*.nii*
resample-image selected_template.nii.gz selected_template.nii.gz -size 1 1 1
average-images selected_template.nii.gz recon-stacks-brain/*.nii* -target selected_template.nii.gz

average-images average_mask_cnn.nii.gz brain-masks-final/*.nii* -target selected_template.nii.gz
convert-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -short
dilate-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 2
    	
mask-image selected_template.nii.gz average_mask_cnn.nii.gz masked-selected_template.nii.gz


cd ../
echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING SVR" 
echo "-----------------------------------------------------------------------------"
echo

number_of_stacks=$(ls stack-t2s-e0${i}/recon-stacks-brain/*.nii* | wc -l)
mkdir out-proc

nr_channels=$(($nr_echos-1))

channel_text=''
for nr_channel in $(seq 0 $nr_channels); do
if [ $nr_channel != 2 ] ;
then
channel_text="${channel_text} ../stack-t2s-e0${nr_channel}/recon-stacks-brain/*.nii.gz "
fi
done
 
 
echo "number of additional channels for reconstruction: ${nr_channels}" 
cd out-proc
reconstruct ${roi_recon}-output.nii.gz ${number_of_stacks} ../stack-t2s-e02/recon-stacks-brain/*.nii.gz --mc_n $nr_channels --mc_stacks ${channel_text} -mask ../stack-t2s-e0${i}/average_mask_cnn.nii.gz -default_thickness ${default_thickness} -iterations 2 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching





for nr_channel in $(seq 0 $nr_channels); do
echo $nr_channel
if [ $nr_channel -lt 2 ] ;
then
mv mc-output-${nr_channel}.nii.gz recon_struct_brain_e0${nr_channel}.nii.gz
else
new_nr=$((nr_channel+1))
mv mc-output-${nr_channel}.nii.gz recon_struct_brain_e0${new_nr}.nii.gz
fi
done
mv SVR-output.nii.gz recon_struct_brain_e02.nii.gz


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Reorienting Brain Reconstruction ..."
echo

mkdir reo_file
mkdir reo_labels
mkdir reo_labels_PP
mkdir reo_sep_labels
cp recon_struct_brain_e02.nii.gz reo_file/recon_struct_brain_e02_0000.nii.gz

conda deactivate
conda activate venv_nnunetv2


nnUNetv2_predict -d Dataset005_brain-reorientation -i reo_file -o reo_labels -f 0 1 2 3 4 -tr nnUNetTrainerDA5 -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i reo_labels -o reo_labels_PP -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset005_brain-reorientation/nnUNetTrainerDA5__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset005_brain-reorientation/nnUNetTrainerDA5__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json
	
conda deactivate
conda activate t2s_venv

new_roi=(1 2 3 4 5)
mkdir met2srecon_roi

# extracts each of the 5 labels
for ((j=0;j<${#new_roi[@]};j++));
do
    q=${new_roi[$j]}
        
    #extract each label, store in local roi folder
	extract-label reo_labels_PP/recon_struct_brain_e02.nii.gz reo_sep_labels/mask-brain-e02-${q}.nii.gz ${q} ${q}
	extract-connected-components reo_sep_labels/mask-brain-e02-${q}.nii.gz reo_sep_labels/mask-brain-e02-${q}.nii.gz
	

done    

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "LANDMARK-BASED REGISTRATION ..."
echo

mkdir reo-dofs
# creates an affine dof matrix 
init-dof init.dof  

z1=1; z2=2; z3=3; z4=4; z5=5


total_n_landmarks=5
selected_n_landmarks=5

# Function for rigid landmark-based point registration of two images (the 
# minimum number of landmarks is 4).
# The landmark corrdinates are computed as the centre of the input binary masks
# register generated local masks to template masks
    
echo "registering me-t2s recon to t2 recon"

register-landmarks ${SCRIPT_DIR}/brain_atlas/reo_brain_template.nii.gz reo_sep_labels/mask-brain-e02-${z1}.nii.gz init.dof reo-dofs/dof-to-atl.dof ${total_n_landmarks} ${selected_n_landmarks} ${SCRIPT_DIR}/brain_atlas/mask-brain-${z1}.nii.gz ${SCRIPT_DIR}/brain_atlas/mask-brain-${z2}.nii.gz ${SCRIPT_DIR}/brain_atlas/mask-brain-${z3}.nii.gz ${SCRIPT_DIR}/brain_atlas/mask-brain-${z4}.nii.gz ${SCRIPT_DIR}/brain_atlas/mask-brain-${z5}.nii.gz reo_sep_labels/mask-brain-e02-${z1}.nii.gz reo_sep_labels/mask-brain-e02-${z2}.nii.gz reo_sep_labels/mask-brain-e02-${z3}.nii.gz reo_sep_labels/mask-brain-e02-${z4}.nii.gz reo_sep_labels/mask-brain-e02-${z5}.nii.gz 

# take dof file and apply it to the header of the me-t2s recon

for nr_channel in $(seq 0 $nr_channels); do
edit-image recon_struct_brain_e0${nr_channel}.nii.gz ../../reconstructions/recon_struct_brain_e0${nr_channel}.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
transform-image ../../reconstructions/recon_struct_brain_e0${nr_channel}.nii.gz ../../reconstructions/recon_struct_brain_e0${nr_channel}.nii.gz -target ${SCRIPT_DIR}/brain_atlas/reo_brain_template.nii.gz

done

cd ../../
for nr_channel in $(seq 0 $nr_channels); do
edit-image reconstructions/recon_struct_brain_e0${nr_channel}.nii.gz reconstructions/recon_struct_brain_e0${nr_channel}.nii.gz -origin 0 0 0 

done

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "T2* Fitting ..."
echo

# recon T2* fitting
python ${SCRIPT_DIR}/t2s_fitting.py ${org_files} ${nr_me} ${nr_echos} ${roi_names}

edit-image reconstructions/t2map_from_recon_brain.nii.gz reconstructions/t2map_from_recon_brain.nii.gz -origin 0 0 0    

  
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Brain Segmentation ..."
echo

mkdir reconstructions/brain_seg
conda deactivate

conda activate venv_nnunetv2 
cp reconstructions/recon_struct_brain_e02.nii.gz reconstructions/brain_seg/recon_struct_brain_e02_0000.nii.gz


nnUNetv2_predict -d Dataset001_prestobrain -i reconstructions/brain_seg/ -o reconstructions/brain_seg_results/ -f 0 1 2 3 4 -tr nnUNetTrainer -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i reconstructions/brain_seg_results -o reconstructions/brain_seg_results_PP -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset001_prestobrain/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset001_prestobrain/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json

cp reconstructions/brain_seg_results_PP/recon_struct_brain_e02.nii.gz reconstructions/recon_struct_brain_labels.nii.gz
rm -r reconstructions/brain_seg_results_PP
rm -r reconstructions/brain_seg_results
rm -r reconstructions/brain_seg
conda deactivate

#rm -r processing_brain

cd $SCRIPT_DIR
