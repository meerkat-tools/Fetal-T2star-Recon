#!/bin/bash


# how to run:
# ./fetal_t2star_multi-echo_reconstruction_pipeline.sh folder_to_process/ scan_number
# ex - ./multi-echo_reconstruction.sh freemax_0046 59  

# setting up stuff
default_run_dir=/home/kpa19/reorientation/
template_path=/home/kpa19/reorientation/late-ref-organ-atlas-all-2021
thorax_template=/home/kpa19/reorientation/networks/cropped-thorax-late-ref-organ-atlas-all-2021/in-atlas-space-dsvr.nii.gz
mirtk_path=/home/kpa19/software/MIRTK/build/bin
mirtk_au_path=/home/au18/software/MIRTK/build/lib/tools
recon_user_id=kpa19
recon_server_id=gpubeastie04
freemax_data=/home/jhu14/Dropbox/placentaJhu/

monai_check_path_roi=${default_run_dir}/monai-checkpoints-unet-t2s-brain-body-placenta-loc-3-lab
check_path_roi_reo_4lab=/home/kpa19/reorientation/monai-checkpoints-unet-notmasked-body-reo-4-lab

# folder with input files to be processed
org_files=$1
echo $org_files

nr_me=$2
echo $nr_me

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Concatenating and denoising input files ..."
echo

conda activate t2s_fitting

python concat_files_new.py $org_files $nr_me

conda deactivate

conda activate Segmentation_FetalMRI_MONAI

cd $freemax_data/$org_files/ME/n$nr_me/
if [[ ! -d ${org_files} ]];then
	echo "ERROR: NO INPUT FILES FOUND !!!!" 
	exit
fi


echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "INPUT FILES ..."
echo

cd ${org_files}
echo "files to be processed: " ${org_files}

num_packages=1

# slice thickness hard-coded in for now - update?
default_thickness=3.1
default_resolution=1.2

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
    
    # sets voxels = nan and voxels >100000000 to 0
	${mirtk_path}/mirtk nan ${all_og_stacks[i]}  100000000
	# set time resolution to 10ms
	${mirtk_path}/mirtk edit-image ${all_og_stacks[i]}  ${all_og_stacks[i]} -dt 10 
	
	# rescales images to be between 0 and 1500
    ${mirtk_path}/mirtk convert-image ${all_og_stacks[i]} ${all_og_stacks[i]::-7}_rescaled.nii.gz -rescale 0 1500
	${mirtk_path}/mirtk extract-image-region ${all_og_stacks[i]} stack-t2s-e0${i}/original-files/${i}-t2s-e0${i} -split 3 	
    ${mirtk_path}/mirtk extract-image-region ${all_og_stacks[i]::-7}_rescaled.nii.gz stack-t2s-e0${i}/org-files-packages/${i}-t2s-e0${i} -split 3 	

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
${mirtk_path}/mirtk prepare-for-monai res-files/ stack-files/ global-stack-info.json global-stack-info.csv ${res} ${Num_stacks} org-files-packages/*nii*
# segment the files into 3 labels: body, brain, placenta
python ${default_run_dir}/run_monai_unet_segmentation-2022.py $(pwd)/ ${monai_check_path_roi}/ global-stack-info.json monai-segmentation-results-global ${res} ${monai_lab_num}
cd ../

      
out_mask_names=$(ls stack-t2s-e01/monai-segmentation-results-global/cnn-*.nii*)
out_stack_names=$(ls stack-t2s-e01/stack-files/*.nii*)
    
IFS=$'\n' read -rd '' -a all_masks <<<"$out_mask_names"
IFS=$'\n' read -rd '' -a all_stacks <<<"$out_stack_names"

echo    
echo "Global Masks: " ${all_masks[*]}
echo "Files that were segmented: " ${all_stacks[*]}
echo
     
mkdir stack-t2s-e01/recon-stacks-body
mkdir stack-t2s-e01/recon-masks-body
mkdir stack-t2s-e01/recon-stacks-brain
mkdir stack-t2s-e01/global-roi-masks

# Perform segmentation for just the first echo
i=1

#extract the individual labels, dilate them, crop input images for brain and body   
for ((b=0;b<${#all_stacks[@]};b++));
do 
	jj=$((${b}+1000))
    
    # extracts the labels for brain and body and saves them in separate files
    #input: monai-segmentation-results-global/cnn-* output: global-roi-masks/mask-body-${jj}-0.nii.gz
	${mirtk_path}/mirtk extract-label ${all_masks[$b]} stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz 1 1 
	${mirtk_path}/mirtk extract-label ${all_masks[$b]} stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz 2 2 
	
	# extracts the largest connected components from the labelmap
	#input: global-roi-masks/mask-body-${jj}-0.nii.gz output: global-roi-masks/mask-body-${jj}-0.nii.gz
	${mirtk_path}/mirtk extract-connected-components stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz
	${mirtk_path}/mirtk extract-connected-components stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz
	
	# dilate the extracted label
	#input: global-roi-masks/mask-body-${jj}-0.nii.gz output: global-roi-masks/mask-body-${jj}-0.nii.gz
	${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz -iterations 2
	${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz -iterations 2
	
	# erode label
	#input: global-roi-masks/mask-body-${jj}-0.nii.gz output: global-roi-masks/mask-body-${jj}-0.nii.gz
	${mirtk_path}/mirtk erode-image stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz -iterations 2
    ${mirtk_path}/mirtk erode-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz -iterations 2
    
    # dilate label again, creates a temporary very dilated label image (dl-body-m.nii.gz, dl-brain-m.nii.gz) that gets written over in every loop
    #input: global-roi-masks/mask-body-${jj}-0.nii.gz output: stack-t2s-e0${i}/dl-body-m.nii.gz
    ${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz stack-t2s-e0${i}/dl-body-m.nii.gz -iterations 7
	${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/global-roi-masks/mask-brain-${jj}-0.nii.gz stack-t2s-e0${i}/dl-brain-m.nii.gz -iterations 7
	
	# crop image
	#input: stack-files/*.nii* mask: dl-body-m.nii.gz output: recon-stacks-body/cropped-stack-${jj}.nii.gz 
	${mirtk_path}/mirtk crop-image ${all_stacks[$b]} stack-t2s-e0${i}/dl-body-m.nii.gz stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz
	${mirtk_path}/mirtk crop-image stack-t2s-e0${i}/global-roi-masks/mask-body-${jj}-0.nii.gz stack-t2s-e0${i}/dl-body-m.nii.gz stack-t2s-e0${i}/recon-masks-body/cropped-mask-${jj}.nii.gz
	
	${mirtk_path}/mirtk crop-image ${all_stacks[$b]} stack-t2s-e0${i}/dl-brain-m.nii.gz stack-t2s-e0${i}/recon-stacks-brain/cropped-stack-${jj}.nii.gz
	
	#mask image
	#input: recon-stacks-body/cropped-stack-${jj}.nii.gz mask: dl-body-m.nii.gz output: recon-stacks-body/cropped-stack-${jj}.nii.gz
	${mirtk_path}/mirtk mask-image stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/dl-body-m.nii.gz stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz
	${mirtk_path}/mirtk mask-image stack-t2s-e0${i}/recon-stacks-brain/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/dl-brain-m.nii.gz stack-t2s-e0${i}/recon-stacks-brain/cropped-stack-${jj}.nii.gz
	
	
	# auto-thorax-recon script has another round of dilation and saving to two seaprate files, if masking problems, double check this script
	
	# histomatch files to thorax template
	${mirtk_path}/mirtk match-histogram $thorax_template stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz -Sp 0 -Tp 0  
    ${mirtk_path}/mirtk match-histogram $thorax_template stack-t2s-e0${i}/recon-stacks-brain/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/recon-stacks-brain/cropped-stack-${jj}.nii.gz -Sp 0 -Tp 0
    
done 

echo 
echo "-----------------------------------------------------------------------------"
echo "LOCAL ... thorax / abdomen / heart / liver"
echo 
    
mkdir stack-t2s-e0${i}/local-cropped-stack-files
mkdir stack-t2s-e0${i}/local-cropped-res-files
mkdir stack-t2s-e0${i}/monai-segmentation-results-local
mkdir stack-t2s-e0${i}/local-roi-masks

res=128
monai_lab_num=4
Num_stacks=$(find stack-t2s-e0${i}/recon-stacks-body/ -name "*.nii*" | wc -l)
echo $Num_stacks   

cd stack-t2s-e0${i}/
mirtk prepare-for-monai local-cropped-res-files/ local-cropped-stack-files/ local-stack-info.json local-stack-info.csv ${res} ${Num_stacks} recon-stacks-body/cropped-stack-*
python ${default_run_dir}/run_monai_unet_segmentation-2022.py $(pwd)/ ${check_path_roi_reo_4lab}/ local-stack-info.json monai-segmentation-results-local ${res} ${monai_lab_num}
cd ../
    
echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "EXTRACTING LABELS ..."
echo
    
out_mask_names=$(ls stack-t2s-e0${i}/monai-segmentation-results-local/cnn-*.nii*)
IFS=$'\n' read -rd '' -a all_masks <<<"$out_mask_names"

org_stack_names=$(ls stack-t2s-e0${i}/recon-stacks-body/*.nii*)
IFS=$'\n' read -rd '' -a all_org_stacks <<<"$org_stack_names"

for ((b=0;b<${#all_org_stacks[@]};b++));
do
	echo " - " ${all_org_stacks[$b]} " : " ${all_masks[$b]}

	jj=$((${b}+1000))

	#z1=12; z2=2; z3=6; z4=116
	q1=1; q2=2; q3=3; q4=4

	#org_roi=(12 2 6 116)
	new_roi=(1 2 3 4)

    # extracts each of the 4 labels
	for ((j=0;j<${#new_roi[@]};j++));
	do
		q=${new_roi[$j]}
		z=${org_roi[$j]}
        
        #extract each label, store in local roi folder
        # input: monai-segmentation-results-local/cnn-*.nii*; output: local-roi-masks/mask-body-${jj}-${q}.nii.gz
		${mirtk_path}/mirtk extract-label ${all_masks[$b]} stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${q}.nii.gz ${q} ${q}
		# input: local-roi-masks/mask-body-${jj}-${q}.nii.gz; output: local-roi-masks/mask-body-${jj}-${q}.nii.gz
		${mirtk_path}/mirtk extract-connected-components stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${q}.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${q}.nii.gz 

	done

	z='done'
	# extract lungs and heart (thorax) labels
	# input: monai-segmentation-results-local/cnn-*.nii*; output: local-roi-masks/mask-body-${jj}-thorax.nii.gz
	${mirtk_path}/mirtk extract-label ${all_masks[$b]} stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz 1 2	
    # extract largest connected thorax component
    # input: local-roi-masks/mask-body-${jj}-thorax.nii.gz; output: local-roi-masks/mask-body-${jj}-thorax.nii.gz
    ${mirtk_path}/mirtk extract-connected-components stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz
	
	# Dilate and erode thorax mask
	# input: local-roi-masks/mask-body-${jj}-thorax.nii.gz; output: local-roi-masks/mask-body-${jj}-thorax.nii.gz
	
	${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz -iterations 3
    ${mirtk_path}/mirtk erode-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz -iterations 1
	# transfrom thorax labelmap to cropped stack
	# input: local-roi-masks/mask-body-${jj}-thorax.nii.gz; target: recon-stacks-body/cropped-stack-${jj}.nii.gz; output: local-roi-masks/mask-body-${jj}-thorax.nii.gz
	#${mirtk_path}/mirtk transform-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz -target stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz -labels
	${mirtk_path}/mirtk transform-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz -target stack-t2s-e0${i}/local-cropped-res-files/in-res-stack-${jj}.nii.gz -labels
	
	# one more thorax dilation
	#input: local-roi-masks/mask-body-${jj}-thorax.nii.gz; output: stack-t2s-e0${i}/dl-thorax.nii.gz
	${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-thorax.nii.gz stack-t2s-e0${i}/dl-thorax.nii.gz -iterations 4
	
	
	# extract torso mask (all 4 labels)
	# input: monai-segmentation-results-local/cnn-*.nii*; output: local-roi-masks/mask-body-${jj}-torso.nii.gz
	${mirtk_path}/mirtk extract-label ${all_masks[$b]} stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-torso.nii.gz 1 4
	# extract largest connected thorax component
	# input: output
	${mirtk_path}/mirtk extract-connected-components stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-torso.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-torso.nii.gz 
    # dilate image
    # input: local-roi-masks/mask-body-${jj}-torso.nii.gz; output: local-roi-masks/mask-body-${jj}-torso.nii.gz
    ${mirtk_path}/mirtk dilate-image stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-torso.nii.gz  stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-torso.nii.gz -iterations 3

done
    

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "LANDMARK-BASED REGISTRATION ..."
echo

mkdir stack-t2s-e0${i}/reo-dofs
# creates an affine dof matrix 
mirtk init-dof stack-t2s-e0${i}/init.dof  
# nn: number of files to process
nn=$(ls stack-t2s-e0${i}/stack-files/*.nii* | wc -l)

 
for ((j=0;j<${nn};j++));
do

	jj=$((${j}+1000))
	
	echo
	echo " ---------------------------------------------------------------------"
	echo " - " ${jj} " ... "
		
	#z1=12; z2=2; z3=6; z4=116	
	z1=1; z2=2; z3=3; z4=4
	
	total_n_landmarks=4
	selected_n_landmarks=4


    echo "registering ${jj}"
    mirtk register-landmarks ${template_path}/in-atlas-space-dsvr.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${z1}.nii.gz stack-t2s-e0${i}/init.dof stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof ${total_n_landmarks} ${selected_n_landmarks} ${template_path}/final-mask-${z1}.nii.gz ${template_path}/final-mask-${z2}.nii.gz ${template_path}/final-mask-${z3}.nii.gz ${template_path}/final-mask-${z4}.nii.gz  stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${z1}.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${z2}.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${z3}.nii.gz stack-t2s-e0${i}/local-roi-masks/mask-body-${jj}-${z4}.nii.gz 
    # take dof file and apply it to the header of the cropped stack and mask
    ${mirtk_path}/mirtk edit-image stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz -dofin_i stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof
    
    ${mirtk_path}/mirtk edit-image stack-t2s-e0${i}/recon-masks-body/cropped-mask-${jj}.nii.gz stack-t2s-e0${i}/recon-masks-body/cropped-mask-${jj}.nii.gz -dofin_i stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof
    # transform global mask to be in the space of recon-stacks cropped image
    ${mirtk_path}/mirtk transform-image stack-t2s-e0${i}/recon-masks-body/cropped-mask-${jj}.nii.gz stack-t2s-e0${i}/recon-masks-body/cropped-mask-${jj}.nii.gz -target stack-t2s-e0${i}/recon-stacks-body/cropped-stack-${jj}.nii.gz -labels
    
done
 
mkdir stack-t2s-e0${i}/proc-stacks

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

# list cropped and reoriented images
reo_stack_names=$(ls recon-stacks-body/*.nii*)
IFS=$'\n' read -rd '' -a all_reo_stacks <<<"$reo_stack_names"

reo_mask_names=$(ls recon-masks-body/*.nii*)
IFS=$'\n' read -rd '' -a all_reo_masks <<<"$reo_mask_names"

number_of_stacks=$(ls recon-stacks-body/*.nii* | wc -l)

echo
echo "Running stack selection"
echo
#${mirtk_path}/mirtk stacks-selection ${number_of_stacks} $(echo $reo_stack_names) $(echo $reo_mask_names) proc-stacks 12 1 0.3     

test_file=selected_template.nii.gz
    if [[ ! -f ${test_file} ]];then
        echo
        echo "-----------------------------------------------------------------------------"
        echo "COMPUTING GLOBAL AVERAGE ..."
        echo "-----------------------------------------------------------------------------"
        echo
         
        ${mirtk_path}/mirtk average-images selected_template.nii.gz recon-stacks-body/*.nii*
        ${mirtk_path}/mirtk resample-image selected_template.nii.gz selected_template.nii.gz -size 1 1 1
        ${mirtk_path}/mirtk average-images selected_template.nii.gz recon-stacks-body/*.nii* -target selected_template.nii.gz
        ${mirtk_path}/mirtk average-images average_mask_cnn.nii.gz recon-masks-body/*.nii* -target selected_template.nii.gz
        ${mirtk_path}/mirtk convert-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -short
        ${mirtk_path}/mirtk dilate-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 2
    	
        
         
        ${mirtk_path}/mirtk mask-image selected_template.nii.gz average_mask_cnn.nii.gz masked-selected_template.nii.gz

        out_mask_names=$(ls recon-masks-body/*.nii*)
        IFS=$'\n' read -rd '' -a all_masks <<<"$out_mask_names"
        
        org_stack_names=$(ls recon-stacks-body/*.nii*)
        IFS=$'\n' read -rd '' -a all_org_stacks <<<"$org_stack_names"
        
        ${mirtk_path}/mirtk init-dof init.dof
                
    fi

# transform the selected template from stack selection to the reference space
${mirtk_path}/mirtk transform-image selected_template.nii.gz transf-selected_template.nii.gz -target ${default_run_dir}/ref-space.nii.gz -interp Linear 
# crop the selected template 
${mirtk_path}/mirtk crop-image transf-selected_template.nii.gz transf-selected_template.nii.gz transf-selected_template.nii.gz

#dilate and erode average mask 
${mirtk_path}/mirtk dilate-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 2 
${mirtk_path}/mirtk erode-image average_mask_cnn.nii.gz average_mask_cnn.nii.gz -iterations 1


#calculate the median average template
nStacks=$(ls recon-stacks-body/*.nii* | wc -l)

${mirtk_path}/mirtk median-average transf-selected_template.nii.gz median_template.nii.gz 3 recon-stacks-body/*1000* recon-stacks-body/*1001* recon-stacks-body/*1002* 

${mirtk_path}/mirtk median-average transf-selected_template.nii.gz median_template.nii.gz 3 recon-stacks-body/*1000* recon-stacks-body/*1001* recon-stacks-body/*1002* 

cd ../ 
i=1

echo
echo "-----------------------------------------------------------------------------"
echo "-----------------------------------------------------------------------------"
echo
echo "Echo REORIENTATION ..."
echo

mkdir stack-t2s-e00/final-reo-stacks
mkdir stack-t2s-e01/final-reo-stacks
mkdir stack-t2s-e02/final-reo-stacks

stack_names_0=$(ls stack-t2s-e00/original-files/*.nii*)
stack_names_1=$(ls stack-t2s-e01/original-files/*.nii*)
stack_names_2=$(ls stack-t2s-e02/original-files/*.nii*)

IFS=$'\n' read -rd '' -a all_stacks_0 <<<"$stack_names_0"
IFS=$'\n' read -rd '' -a all_stacks_1 <<<"$stack_names_1"
IFS=$'\n' read -rd '' -a all_stacks_2 <<<"$stack_names_2"

for ((j=0;j<${nn};j++));
do
 
 	jj=$((${j}+1000))
 	
 	echo
 	echo " ---------------------------------------------------------------------"
 	echo " - " ${jj} " ... " 	

 	${mirtk_path}/mirtk edit-image ${all_stacks_0[$j]} stack-t2s-e00/final-reo-stacks/stack-${jj}.nii.gz -dofin_i stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof

    ${mirtk_path}/mirtk edit-image ${all_stacks_1[$j]} stack-t2s-e01/final-reo-stacks/stack-${jj}.nii.gz -dofin_i stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof
    
    ${mirtk_path}/mirtk edit-image ${all_stacks_2[$j]} stack-t2s-e02/final-reo-stacks/stack-${jj}.nii.gz -dofin_i stack-t2s-e0${i}/reo-dofs/dof-to-atl-${jj}.dof

done  


echo 
echo "-----------------------------------------------------------------------------"
echo "RUNNING DSVR" 
echo "-----------------------------------------------------------------------------"
echo

scp -r stack-t2s-e00/final-reo-stacks/ ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/${org_files}_stack-t2s-e00/
scp -r stack-t2s-e01/final-reo-stacks/ ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/${org_files}_stack-t2s-e01/
scp -r stack-t2s-e01/average_mask_cnn.nii.gz ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/${org_files}_stack-t2s-e01/
scp -r stack-t2s-e01/median_template.nii.gz ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/${org_files}_stack-t2s-e01/
scp -r stack-t2s-e02/final-reo-stacks/ ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/${org_files}_stack-t2s-e02/


echo ssh ${recon_user_id}@${recon_server_id} "cd /home/${recon_user_id}/reorientation/working_dir/; mkdir out-proc-${org_files}; cd out-proc-${org_files}; ${mirtk_path}/mirtk reconstructFFD ${roi_recon}-output.nii.gz ${number_of_stacks} ../${org_files}_stack-t2s-e01/stack*.nii.gz --mc_n 2 --mc_stacks  ../${org_files}_stack-t2s-e00/*.nii.gz ../${org_files}_stack-t2s-e02/*.nii.gz -mask ../${org_files}_stack-t2s-e01/average_mask_cnn.nii.gz -template ../${org_files}_stack-t2s-e01/median_template.nii.gz -default_thickness ${default_thickness} -iterations 2 -cp 12 5 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching -dilation 7 ; "
ssh ${recon_user_id}@${recon_server_id} "cd /home/${recon_user_id}/reorientation/working_dir/; mkdir out-proc-${org_files}; cd out-proc-${org_files}; ${mirtk_path}/mirtk reconstructFFD ${roi_recon}-output.nii.gz ${number_of_stacks} ../${org_files}_stack-t2s-e01/stack*.nii.gz --mc_n 2 --mc_stacks ../${org_files}_stack-t2s-e00/*.nii.gz ../${org_files}_stack-t2s-e02/*.nii.gz -mask ../${org_files}_stack-t2s-e01/average_mask_cnn.nii.gz -template ../${org_files}_stack-t2s-e01/median_template.nii.gz -default_thickness ${default_thickness} -iterations 2 -cp 12 5 -no_robust_statistics -resolution ${default_resolution} -delta 150 -lambda 0.02 -structural -lastIter 0.015 -no_intensity_matching -dilation 7; "

scp -r ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/out-proc-${org_files}/mc*nii* .
scp -r ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/reorientation/working_dir/out-proc-${org_files}/DSVR*nii* .

ssh ${recon_user_id}@${recon_server_id} "cd /home/kpa19/reorientation/working_dir; rm -r ${org_files}_stack-t2s-e00/; rm -r ${org_files}_stack-t2s-e01/; rm -r ${org_files}_stack-t2s-e02/; rm -r ${org_files}_t2maps/; rm -r out-proc-${org_files}"
	

number_of_stacks=$(ls stack-t2s-e01/final-reo-stacks/*.nii* | wc -l) 
j=0

	test_file=${roi_recon}-output.nii.gz
	if [[ -f ${test_file} ]]; then
        mkdir ../reconstructions
		${mirtk_path}/mirtk transform-image stack-t2s-e01/average_mask_cnn.nii.gz stack-t2s-e01/average_mask_cnn.nii.gz -target DSVR-output.nii.gz -labels 
		${mirtk_path}/mirtk edit-image mc-output-0.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_body_e00.nii.gz -origin 0 0 0 
		${mirtk_path}/mirtk edit-image mc-output-1.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_body_e02.nii.gz -origin 0 0 0 
		${mirtk_path}/mirtk edit-image DSVR-output.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_body_e01.nii.gz -origin 0 0 0 
		${mirtk_path}/mirtk edit-image stack-t2s-e01/average_mask_cnn.nii.gz ../reconstructions/${org_files}_${nr_me}_recon_struct_body_mask.nii.gz -origin 0 0 0
		
		echo "Reconstruction was successful: " 
		
		
	else 
		echo "Reconstruction failed ... " 
	fi
	
# recon T2* fitting
conda deactivate
conda activate t2s_fitting
python /home/kpa19/reorientation/t2s_fitting_from_reconstructions_new.py ${org_files} ${nr_me}

conda deactivate

cd $freemax_data/$org_files/ME/n$nr_me/
# segment images
ssh ${recon_user_id}@${recon_server_id} "mkdir /home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/labels-${org_files}_${nr_me}; mkdir /home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/images-${org_files}_${nr_me};"
scp -r reconstructions/${org_files}_${nr_me}_recon_struct_body_e00_masked.nii.gz ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/images-${org_files}_${nr_me}/${org_files}_${nr_me}_recon_struct_body_0000.nii.gz
scp -r reconstructions/${org_files}_${nr_me}_recon_struct_body_e01_masked.nii.gz ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/images-${org_files}_${nr_me}/${org_files}_${nr_me}_recon_struct_body_0001.nii.gz
scp -r reconstructions/${org_files}_${nr_me}_recon_struct_body_e02_masked.nii.gz ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/images-${org_files}_${nr_me}/${org_files}_${nr_me}_recon_struct_body_0002.nii.gz

ssh ${recon_user_id}@${recon_server_id} "source  miniconda3/etc/profile.d/conda.sh; conda activate venv_nnunet; export nnUNet_raw_data_base=/home/kpa19/fetal_nnunet/nnUNet_raw_data_base; export nnUNet_preprocessed=/home/kpa19/fetal_nnunet/nnUNet_preprocessed; export RESULTS_FOLDER=/home/kpa19/fetal_nnunet/nnUNet_trained_models; cd fetal_nnunet; nnUNet_predict -i segment_fetal_t2s/images-${org_files}_${nr_me}/ -o segment_fetal_t2s/labels-${org_files}_${nr_me} -tr nnUNetTrainerV2 -ctr nnUNetTrainerV2CascadeFullRes -m 3d_fullres -p nnUNetPlansv2.1 -t Task505_threechannels_body_t2s; "
scp -r ${recon_user_id}@${recon_server_id}:/home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/labels-${org_files}_${nr_me}/*gz reconstructions/${org_files}_${nr_me}_recon_struct_body_organ_labels.nii.gz
ssh ${recon_user_id}@${recon_server_id} "rm -r /home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/labels-${org_files}_${nr_me}/; rm -r /home/${recon_user_id}/fetal_nnunet/segment_fetal_t2s/images-${org_files}_${nr_me}/;"

cd /home/kpa19/reorientation/
