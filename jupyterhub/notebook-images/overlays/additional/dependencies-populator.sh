#!/usr/bin/env bash

############################################################################ Description ############################################################################
# This script is used to get the python packages of the images that are taged into the ImageStreams objects                                                         #
#                                                                                                                                                                   #
# The user first should change/update the image name from the ImageStreams (.spec.tags.from.name)                                                                   #
# And then run the script ./dependencies-populator.sh to update the python packages on (.spec.tags.annotations.opendatahub.io/notebook-python-dependencies)         #
# In case that the local machine doesn't have yq tool, use the following instructions                                                                               #
# Install yq tool                                                                                                                                                   #
# curl -L --output yq https://github.com/mikefarah/yq/releases/download/2.4.0/yq_linux_amd64                                                                        #
# chmod 700 ./yq                                                                                                                                                    #
#####################################################################################################################################################################


# Packages Filters
MIN_FLT=("notebook" "jupyterlab")
DS_FLT=("boto3" "kafka-python" "matplotlib" "numpy" "pandas" "scikit-learn" "scipy")
TS_FLT=("tensorflow-gpu" "tensorboard" "boto3" "kafka-python" "matplotlib" "numpy" "pandas" "scikit-learn" "scipy")
PT_FLT=("torch" "tensorboard" "boto3" "kafka-python" "matplotlib" "numpy" "pandas" "scikit-learn" "scipy")

# -- Name : fn_get_pkgs
# -- Descr: Function to retrive the packages from a given image
# -- Usage: pkgs=$(fn_get_pkgs $container_name $image); echo "${pkgs[*]}"
fn_get_pkgs() {
   podman run -d --rm -it --name=$1 $2 >> /dev/null 2>&1
   local result=$(podman exec -it $1 pip list --disable-pip-version-check --format=freeze)
   podman rm --force $2 >> /dev/null 2>&1
   echo "${result[*]}"
}

# -- Name : fn_generate_annotation
# -- Descr: Function to generate the json format from the given packages
# -- Usage: json=$(fn_generate_annotation $pkgs); echo "$json"
fn_generate_annotation() {
    local result="["
    local array=("$@")
    for pkg in "${array[@]}"
    do
        pkg_parts=($(echo "$pkg" | tr '==' '\n'))
        name=($(echo ${pkg_parts[0]} | tr -d '[:space:]'))
        version=($(echo ${pkg_parts[1]} | tr -d '[:space:]'))
        result="$result{\\\"name\\\":\\\"$name\\\",\\\"version\\\":\\\"$version\\\"},"
    done
    result=${result::-1}"]"
    echo $result
}

# -- Name : fn_get_filter
# -- Descr: Function to get the correct list of pkgs based on the type of the images (described in the filename)
# -- Usage: filter=$(fn_get_filter $file); echo "$filter"
fn_get_filter() {
    local img=$1
    if [[ $img == *"minimal-"* ]]; then
        echo "${MIN_FLT[*]}"
    elif [[ $img == *"data-science-"* ]]; then
        echo "${DS_FLT[*]}"
    elif [[ $img == *"tensorflow-"* ]]; then
        echo "${TS_FLT[*]}"
    elif [[ $img == *"pytorch-"* ]]; then
        echo "${PT_FLT[*]}"
    else
        echo ""
    fi
}

# -- Name : fn_get_annotation_from_image
# -- Descr: Function to get the annotations from a given image and file
# -- Usage: annotations=$(fn_get_annotation_from_image $image $file); echo "$annotations"
fn_get_annotation_from_image() {
    local img=$1
    local fl=$2
    local container_name=$(uuidgen)
    local pkgs_filter=($(fn_get_filter "$fl"))

    if [[ $pkgs_filter == "" ]]; then
        return
    fi

    local pkgs=($(fn_get_pkgs $container_name "$img"));
    local fnd_pkgs=()

    for pkg in "${pkgs[@]}"
    do
        for fpkg in "${pkgs_filter[@]}"
        do
            pkg_parts=($(echo "$pkg" | tr '==' '\n'))
            name=($(echo ${pkg_parts[0]} | tr -d '[:space:]'))
            if [[ "$name" == "$fpkg" ]]; then
                fnd_pkgs+=("$pkg")
            fi
        done
    done
    local annotations=$(fn_generate_annotation ${fnd_pkgs[@]});
    echo "$annotations"
}

#########################################################################################################
## MAIN PROGRAM                                                                                        ##
#########################################################################################################
T_RST='\033[0m' # No Color
T_UNDERLINE='\033[4m'
# Get all yaml or yml files
files=($(ls *.yaml *.yml 2>&-))

# We iterate the list of files to parse properly the yaml and perform the requested operations
for file in "${files[@]}"
do
    echo -e "${T_UNDERLINE}Parsing file:${T_RST} $file"
    # Finds the images from the tag node
    images=( $(yq '.spec.tags[].from.name' $file 2>/dev/null) )
    # For each image find and generate the annotation bundle
    cur_pos=0

    if [[ $images == "" ]]; then
             echo -e "  - No Images Found."
    else
        for image in "${images[@]}"
        do
            image=($(echo "$image" | tr -d '"'))
            echo "  - Selected Image: $image"
            str_annotations=$(fn_get_annotation_from_image $image $file)
            if [[ $str_annotations == "" ]]; then
                echo -e "    - Ignored."
            else
                echo -e  "    - Generated Annotations: $str_annotations " | tr -d '\\'
                yq -i -Y '.spec.tags['$cur_pos'].annotations."opendatahub.io/notebook-python-dependencies" = "'$str_annotations'"' $file
            fi
            ((cur_pos=cur_pos+1))
        done
    fi
done
