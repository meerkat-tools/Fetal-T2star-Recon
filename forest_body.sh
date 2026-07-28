#!/bin/bash


# how to run:
# source forest_body.sh [complete path to folder with files] [scan_number] [number of echos] [dyn to exclude]
# ex - source forest_body.sh /home/user/case_number_001 59 3 1,2,3
# this example is for a 3 echo sequence where the first 3 dynamics are motion corrupted
# if no dynamics are bad, put '0'
# ex - source forest_body.sh /home/user/case_number_001 59 3 0
# if the body masking fails, there is the option to use a manual mask. This can be added as an additional input argument:
# source forest_body.sh  /home/user/case_number_001 59 3 0 /home/user/case001/case001_body_mask.nii.gz
# Format of the input files:
# *e1*.nii.gz*, *e2*.nii.gz, *ex*.nii.gz, where x = number of echos in the 
# multi-echo sequence to be fitted. Each echo file is 4D, containing all 
# of the dynamics. For example, if e1.nii.gz is 256 x 256 x 80 x 20, there 
# are 20 dynamics.
# Input File Structure:
# folder structure assumed in the path to files:
# Folder with multi-echo files in nifti format: ME/n[scan_number]/*nii.gz
# In the this ME/n[scan_number] folder, place a .txt file listing the echo times in ms


# setting up directories
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
echo "Running script: ${SCRIPT_DIR}/forest_body.sh"
cd $SCRIPT_DIR

template_path=$SCRIPT_DIR/late-ref-organ-atlas-all-2021
thorax_template=$SCRIPT_DIR/cropped-thorax-late-ref-organ-atlas-all-2021/in-atlas-space-dsvr.nii.gz
echo
echo "Fetal Template: " $template_path
echo "Fetal Thorax Template: " $thorax_template
echo

export nnUNet_raw="$SCRIPT_DIR/fetal_nnunet/nnUNet_raw/"
export nnUNet_results="$SCRIPT_DIR/fetal_nnunet/nnUNet_results/"
export nnUNet_preprocessed="$SCRIPT_DIR/fetal_nnunet/nnUNet_preprocessed/"

# folder with input files to be processed
org_files=$1
nr_me=$2
nr_echos=$3
dyn_to_exclude=$4

if [ -n "$5" ]

then
body_mask=$5
echo "Manual body mask exists: " ${body_mask}
fi

echo ""

echo "Processing Scan: ${org_files}"
echo "Sequence number to process: ${nr_me}"
echo "Number of echos: ${nr_echos}"
echo "dynamics to exclude: ${dyn_to_exclude}"
echo ""


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Concatenating and denoising input files ..."
echo

# this script rearranges the files into the correct format and removes dynamics
conda activate t2s_venv
python remove_corrupted_body_dynamics.py $org_files $nr_me $nr_echos $dyn_to_exclude

cd $org_files/ME/n$nr_me

if [[ ! -d processing_body ]];then
	echo "ERROR: NO INPUT FILES FOUND !!!!" 
	exit
fi


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "INPUT FILES ..."
echo

cd processing_body
echo "files to be processed: " ${org_files}
echo

num_packages=1

dims=$(mrinfo ${org_files}/ME/n${nr_me}/processing_body/e1_denoised.nii.gz -spacing)
thickness=( $dims )
default_thickness=$(printf "%.1f" ${thickness[0]})

default_resolution=1.2

echo
echo "Slice thickness: ${default_thickness}"
echo "Reconstruction Resolution: ${default_resolution}"
echo

roi_recon="DSVR"
roi_names="body"

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
    mkdir stack-t2s-e0${i}/recon-stacks-body/
    
    # sets voxels = nan and voxels >100000000 to 0
	mirtk nan ${all_og_stacks[i]}  100000000
	# set time resolution to 10ms
	mirtk edit-image ${all_og_stacks[i]}  ${all_og_stacks[i]} -dt 10 
	
	# rescales images to be between 0 and 1500
    mirtk convert-image ${all_og_stacks[i]} ${all_og_stacks[i]::-7}_rescaled.nii.gz -rescale 0 1500
	mirtk extract-image-region ${all_og_stacks[i]} stack-t2s-e0${i}/original-files/${i}-t2s-e0${i} -split 3 	
    mirtk extract-image-region ${all_og_stacks[i]::-7}_rescaled.nii.gz stack-t2s-e0${i}/org-files-packages/${i}-t2s-e0${i} -split 3 	

done

if [ -n "$5" ]

then

echo "Use manual body mask instead of automatically generating them: " ${body_mask}
mkdir stack-t2s-e01/segmentation-results-global
mkdir stack-t2s-e01/segmentation-results-global_dilated
for orig_file_img in $(ls stack-t2s-e01/original-files);
do
cp ${body_mask} stack-t2s-e01/segmentation-results-global/$orig_file_img
done

else
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "3D UNET SEGMENTATION ... Body Localization"
echo
echo "-----------------------------------------------------------------------------"
echo 


#perform segmentations on the 2nd echo (e01) and apply them to the rest of the echos

mkdir stack-t2s-e01/segmentation-results-global_pre
mkdir stack-t2s-e01/segmentation-results-global
mkdir stack-t2s-e01/segmentation-results-global_dilated

for og_file in $(ls stack-t2s-e01/org-files-packages/)
do
mv stack-t2s-e01/org-files-packages/$og_file stack-t2s-e01/org-files-packages/${og_file::-7}_0000.nii.gz

done
conda deactivate

conda activate venv_nnunetv2 


nnUNetv2_predict -d Dataset003_body-localization -i stack-t2s-e01/org-files-packages/ -o stack-t2s-e01/segmentation-results-global_pre -f 0 1 2 3 4 -tr nnUNetTrainer -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i stack-t2s-e01/segmentation-results-global_pre -o stack-t2s-e01/segmentation-results-global -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset003_body-localization/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset003_body-localization/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json

conda deactivate
conda activate t2s_venv
fi

b=0
for mask_file in $(ls stack-t2s-e01/segmentation-results-global/)
do
	# dilate and erode the extracted label
	mirtk dilate-image stack-t2s-e01/segmentation-results-global/$mask_file stack-t2s-e01/segmentation-results-global_dilated/$mask_file -iterations 2
	
	mirtk erode-image stack-t2s-e01/segmentation-results-global_dilated/$mask_file stack-t2s-e01/segmentation-results-global_dilated/$mask_file -iterations 2
    
        # dilate label again, creates a temporary very dilated label image (dl-body-m.nii.gz, dl-brain-m.nii.gz) that gets written over in every loop
        mirtk dilate-image stack-t2s-e01/segmentation-results-global_dilated/$mask_file stack-t2s-e01/segmentation-results-global_dilated/$mask_file -iterations 7
		
	# crop images from all echos for reconstruction
        for ((k=0; k<$nr_echos; k++)); do
    
        if [ -f stack-t2s-e0${k}/original-files/${k}-t2s-e0${k}_0${b}.nii.gz ]; then
   
            mirtk mask-image stack-t2s-e0${k}/original-files/${k}-t2s-e0${k}_0${b}.nii.gz stack-t2s-e01/segmentation-results-global_dilated/$mask_file stack-t2s-e0${k}/recon-stacks-body/${k}-${mask_file:2:-7}_masked.nii.gz
        else
            mirtk mask-image stack-t2s-e0${k}/original-files/${k}-t2s-e0${k}_${b}.nii.gz stack-t2s-e01/segmentation-results-global_dilated/$mask_file stack-t2s-e0${k}/recon-stacks-body/${k}-${mask_file:2:-7}_masked.nii.gz

    fi
   
    done
    b=$((b + 1))
done


#calculate number of files to be segmented    
Num_stacks=$(find stack-t2s-e01/org-files-packages/ -name "*.nii*" | wc -l)
echo "Number of stacks to segment: " $Num_stacks  
    

echo
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "RUNNING RECONSTRUCTION ..."
echo

echo "ROI : " ${roi_names} " ... "
echo

cd stack-t2s-e01/

#calculate the median average template
nStacks=$(ls recon-stacks-body/*.nii* | wc -l)

mirtk average-images selected_template.nii.gz recon-stacks-body/*.nii*
mirtk resample-image selected_template.nii.gz selected_template.nii.gz -size 1 1 1
mirtk average-images selected_template.nii.gz recon-stacks-body/*.nii* -target selected_template.nii.gz

mirtk average-images average_mask_cnn.nii.gz segmentation-results-global/*.nii* -target selected_template.nii.gz
mirtk convert-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -short
mirtk dilate-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 2
    	
mirtk mask-image selected_template.nii.gz average_mask_cnn.nii.gz masked-selected_template.nii.gz

number_of_stacks=$(ls recon-stacks-body/*.nii* | wc -l)
cd ../ 
i=1



echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING DSVR" 
echo "-----------------------------------------------------------------------------"
echo

nr_channels=$(($nr_echos-1))
echo "number of additional channels for reconstruction: ${nr_channels}" 
channel_text=''

for nr_channel in $(seq 0 $nr_channels); do
if [ $nr_channel != 1 ] ;
then
channel_text="${channel_text} ../stack-t2s-e0${nr_channel}/recon-stacks-body/*.nii.gz "
fi
done

mkdir out-proc-recon 
cd out-proc-recon
echo mirtk reconstructFFD ${roi_recon}-output.nii.gz ${number_of_stacks} ../stack-t2s-e01/recon-stacks-body/*.nii.gz --mc_n ${nr_channels} --mc_stacks ${channel_text} -mask ../stack-t2s-e01/average_mask_cnn.nii.gz -template ../stack-t2s-e01/selected_template.nii.gz -default_thickness ${default_thickness} -iterations 2 -cp 12 5 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching -dilation 7

mirtk reconstructFFD ${roi_recon}-output.nii.gz ${number_of_stacks} ../stack-t2s-e01/recon-stacks-body/*.nii.gz --mc_n ${nr_channels} --mc_stacks ${channel_text} -mask ../stack-t2s-e01/average_mask_cnn.nii.gz -template ../stack-t2s-e01/selected_template.nii.gz -default_thickness ${default_thickness} -iterations 2 -cp 12 5 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching -dilation 7

mv DSVR-output.nii.gz ../recon_struct_body_e01.nii.gz
for nr_channel in $(seq 0 $nr_channels); do
if [ $nr_channel -lt 1 ] ;
then
mv mc-output-${nr_channel}.nii.gz ../recon_struct_body_e0${nr_channel}.nii.gz
else
new_nr=$((nr_channel+1))
mv mc-output-${nr_channel}.nii.gz ../recon_struct_body_e0${new_nr}.nii.gz
fi
done
cd ../

#mask body images
for nr_channel in $(seq 0 $nr_channels); do
mirtk mask-image recon_struct_body_e0${nr_channel}.nii.gz stack-t2s-e01/average_mask_cnn.nii.gz recon_struct_body_e0${nr_channel}_masked.nii.gz 
done

echo 
echo "-----------------------------------------------------------------------------"
echo "Reorientation of Reconstruction ... thorax / abdomen / heart / liver"
echo 

mkdir t2recon-labelmaps/

mkdir reo_file
mkdir reo_labels
mkdir reo_labels_PP
mkdir reo_sep_labels
cp recon_struct_body_e01_masked.nii.gz reo_file/recon_struct_body_e01_masked_0000.nii.gz
conda deactivate
conda activate venv_nnunetv2

nnUNetv2_predict -d Dataset004_body-reorientation -i reo_file -o reo_labels -f 0 1 2 3 4 -tr nnUNetTrainer -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i reo_labels -o reo_labels_PP -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset004_body-reorientation/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset004_body-reorientation/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json
	
conda deactivate
conda activate t2s_venv

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "EXTRACTING LABELS ..."
echo
    
q1=1; q2=2; q3=3; q4=4

new_roi=(1 2 3 4)

# extracts each of the 4 labels
for ((j=0;j<${#new_roi[@]};j++));
do
    q=${new_roi[$j]}
        
    #extract each label, store in local roi folder
    
    mirtk extract-label reo_labels_PP/*gz reo_sep_labels/mask-body-${q}.nii.gz ${q} ${q}
	
    mirtk extract-connected-components reo_sep_labels/mask-body-${q}.nii.gz reo_sep_labels/mask-body-${q}.nii.gz

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
		

z1=1; z2=2; z3=3; z4=4
	
total_n_landmarks=4
selected_n_landmarks=4

mkdir ../reconstructions
echo "registering me recon to template"
mirtk register-landmarks ${template_path}/in-atlas-space-dsvr.nii.gz ../reconstructions/recon_struct_body_e01.nii.gz init.dof reo-dofs/dof-to-atl.dof ${total_n_landmarks} ${selected_n_landmarks} ${template_path}/final-mask-${z1}.nii.gz ${template_path}/final-mask-${z2}.nii.gz ${template_path}/final-mask-${z3}.nii.gz ${template_path}/final-mask-${z4}.nii.gz  reo_sep_labels/mask-body-${z1}.nii.gz reo_sep_labels/mask-body-${z2}.nii.gz reo_sep_labels/mask-body-${z3}.nii.gz reo_sep_labels/mask-body-${z4}.nii.gz 

for nr_channel in $(seq 0 $nr_channels); do
mirtk edit-image recon_struct_body_e0${nr_channel}_masked.nii.gz ../reconstructions/recon_struct_body_e0${nr_channel}.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
mirtk transform-image ../reconstructions/recon_struct_body_e0${nr_channel}.nii.gz ../reconstructions/recon_struct_body_e0${nr_channel}.nii.gz -target ${template_path}/in-atlas-space-dsvr.nii.gz

done


#mirtk edit-image t2map_from_recon_body.nii.gz ../reconstructions/t2map_from_recon_body.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
#mirtk transform-image ../reconstructions/t2map_from_recon_body.nii.gz ../reconstructions/t2map_from_recon_body.nii.gz -target ${template_path}/in-atlas-space-dsvr.nii.gz
#mirtk edit-image stack-t2s-e01/average_mask_cnn.nii.gz ../reconstructions/recon_struct_body_mask.nii.gz -dofin_i reo-dofs/dof-to-atl.dof
#mirtk transform-image ../reconstructions/recon_struct_body_mask.nii.gz ../reconstructions/recon_struct_body_mask.nii.gz -target ${template_path}/in-atlas-space-dsvr.nii.gz -labels 

cd ../
for nr_channel in $(seq 0 $nr_channels); do
mirtk edit-image reconstructions/recon_struct_body_e0${nr_channel}.nii.gz reconstructions/recon_struct_body_e0${nr_channel}.nii.gz -origin 0 0 0 

done


echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING T2* Fitting" 
echo "-----------------------------------------------------------------------------"
echo


# recon T2* fitting
python ${SCRIPT_DIR}/t2s_fitting_body.py ${org_files} ${nr_me} ${nr_echos}


echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING Body Segmentation" 
echo "-----------------------------------------------------------------------------"
echo

conda deactivate
mkdir reconstructions/body_seg

conda activate venv_nnunetv2 
cp reconstructions/recon_struct_body_e01.nii.gz reconstructions/body_seg/recon_struct_body_e01_0000.nii.gz

nnUNetv2_predict -d Dataset002_FOREST_Body -i  reconstructions/body_seg/ -o reconstructions/body_seg_results/ -f 0 1 2 3 4 -tr nnUNetTrainer -c 3d_fullres -p nnUNetPlans
nnUNetv2_apply_postprocessing -i reconstructions/body_seg_results -o reconstructions/body_seg_results_PP -pp_pkl_file ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset002_FOREST_Body/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/postprocessing.pkl -np 8 -plans_json ${SCRIPT_DIR}/fetal_nnunet/nnUNet_results/Dataset002_FOREST_Body/nnUNetTrainer__nnUNetPlans__3d_fullres/crossval_results_folds_0_1_2_3_4/plans.json


cp reconstructions/body_seg_results_PP/recon_struct_body_e01.nii.gz reconstructions/recon_struct_body_organ_labels.nii.gz
rm -r reconstructions/body_seg/
rm -r reconstructions/body_seg_results/
rm -r reconstructions/body_seg_results_PP/
conda deactivate

rm -r processing_body



cd $SCRIPT_DIR
