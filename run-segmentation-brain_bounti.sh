#!/bin/bash

echo
echo "-----------------------------------------------------------------------------"
echo " Segment Fetal Brains "
echo "-----------------------------------------------------------------------------"
echo

# folder with input files to be processed
org_files=$1
echo $org_files

nr_me=$2
echo $nr_me

res=128
echo $SCRIPT_DIR

monai_check_path_bet=$SCRIPT_DIR/monai-checkpoints-atunet-brain_bet-1-lab
monai_check_path_all_brain_roi=$SCRIPT_DIR/monai-checkpoints-atunet-red-brain_dhcp-seg-19-lab
monai_check_path_all_brain_roi_2=$SCRIPT_DIR/monai-checkpoints-unet-brain_dhcp-seg-19-lab


cd $org_files/ME/n$nr_me
main_dir=$(pwd)

test_file=reconstructions/recon_struct_brain_e02.nii.gz
#test_file=reconstructions/recon_struct_brain_e01.nii.gz
if [[ ! -f ${test_file} ]];then

	echo "ERROR: NO INPUT FILES FOUND !!!!" 
	exit
fi

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "3D UNET SEGMENTATION ..."
echo

echo 
echo "GLOBAL ..."
echo 

number_of_stacks=1
stack_names=$brain_recon

res=128
monai_lab_num=1
Num_stacks=1

prepare-for-monai res-global-files/ stack-global-files stack-global-info.json stack-global-info.csv ${res} ${Num_stacks} ${test_file}
mkdir monai-segmentation-results-bet

python $SCRIPT_DIR/run_monai_atunet_segmentation-2023-cpu.py $(pwd)/ ${monai_check_path_bet}/ stack-global-info.json monai-segmentation-results-bet ${res} ${monai_lab_num}
mkdir cropped-input-files
mirtk mask-image res-global-files/*gz monai-segmentation-results-bet/*gz cropped-input-files/masked-brain.nii.gz 


echo 
echo "Brain Tissue Segmentation ..."
echo 

res=256
monai_lab_num=19
Num_stacks=1

prepare-for-monai res-masked-files/ stack-masked-stack-files/ masked-label-info.json masked-label-info.csv ${res} ${Num_stacks} cropped-input-files/*nii*


mkdir monai-segmentation-results
#monai_check_path_all_brain_roi=/home/${run_user_id}/Segmentation_FetalMRI/trained_models/monai-checkpoints-atunet-red-brain_dhcp_early-seg-19-lab
#monai_check_path_all_brain_roi_2=/home/${run_user_id}/Segmentation_FetalMRI/trained_models/monai-checkpoints-unet-brain_dhcp_early-seg-19-lab
#
  
python $SCRIPT_DIR/run_monai_comb_atunet_red_unet_segmentation-2022-lr-cpu.py $(pwd)/ ${monai_check_path_all_brain_roi}/ ${monai_check_path_all_brain_roi_2}/ masked-label-info.json monai-segmentation-results ${res} ${monai_lab_num}


 
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "TRANSFORMING TO THE ORIGINAL SPACE ..."
echo



transform-image monai-segmentation-results/*gz reconstructions/recon_struct_brain_labels.nii.gz -target ${test_file} -labels 
rm -r monai-segmentation-results-bet/
rm -r cropped-input-files
rm -r monai-segmentation-results
rm -r res-*
rm -r stack-*
rm masked-label*
rm tmp-log.txt
rm pwd.txt





