#!/bin/bash
#
#This script takes any number of .zip files from the myCourses site
#   and organizes the code submissions appropriately.
#
#Authors:
#
#   Schuyler Martin @schuylermartin45
#

#Work through the sym links back to the script's actual running directory 
SOURCE="${BASH_SOURCE[0]}"
while [ -h "${SOURCE}" ]; do 
    DIR="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
    SOURCE="$(readlink "${SOURCE}")"
    [[ ${SOURCE} != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
declare -r DIR="$( cd -P "$( dirname "${SOURCE}" )" && pwd )"
#load up the common library
source ${DIR}"/.commonLib.sh"

####  CONSTANTS  ####
#Usage message string
declare -r USAGEFLAGS="[-c] [-f] [-l] [-o] [-q] [-s]"
declare -r USAGE="Usage: ./organize.sh ${USAGEFLAGS} [due_date] file.zip [file(s) ...]"

####    FLAGS    ####
#All flags are = 0 for on
#Cleans up top-level zip automatically
CLEANUP=1
#Removes older submissions; indicated by ending in (#).ext
CLEANOLD=1
#First name mode, folders organized by first name
FIRSTNAME=1
#Late submissions are marked with MRKLATE folders
LATESUB=1
#Splits up the section names scheme into multiple parts
#Change for Fall 2014 with the new student registration system
RMSEC=1

#### GLOBAL VARS ####
#List of zip files passed in
zipList=()
#Localized pathing that aligns with the files passed in
pathList=()
#Due date, which may be specified by the user via a flag
dueDate=""

####  FUNCTIONS  ####

#Builds the common lab directories; to store files given to graders per
#each lab assignment
#@param: 
#        $1 lab directory (lab#)
#
#@return: 
#
#@global:
#
function mkLabDirs {
    local labDir=$1
    if [[ ! -d "${labDir}/${TEST_DIR}" ]]; then
        mkdir "${labDir}/${TEST_DIR}"
    fi
    if [[ ! -d "${labDir}/${EXPECTED_DIR}" ]]; then
        mkdir "${labDir}/${EXPECTED_DIR}"
    fi
    if [[ ! -d "${labDir}/${PROVIDED_DIR}" ]]; then
        mkdir "${labDir}/${PROVIDED_DIR}"
    fi
    if [[ ! -d "${labDir}/${CHEAT_DIR}" ]]; then
        mkdir "${labDir}/${CHEAT_DIR}"
    fi
    if [[ ! -d "${labDir}/${SOL_DIR}" ]]; then
        mkdir "${labDir}/${SOL_DIR}"
    fi
}

#Takes the zip files and makes the appropriate directory structure
#@param: 
#        $1..$N top-level zip files to organize. Each one will be put into
#           a lab folder, then a section. This can be a path to a file.
#           Example: "Lab 10 Download Jun 8, 2014 1110 AM.zip" will go into 
#           lab10/sec_a and then the next file passed in will become sec_b, etc
#
#@return: 
#        - failCntr return the number of failures occured (acts as $?)
#@global:
#        - pathList is set with the local pathings to extracted file structures
function mkZipDirs {
    failCntr=0
    #starting code to count up letters
    local asciiCode=97
    #local naming vars
    local secChar=""
    local labNum=0
    local zip=""
    #counters
    local i=0
    for zipPath in "${@}"; do
        #extract just the zip name from a possible directory
        zip="$(basename "${zipPath}")"
        #Fall 2014: labs are labeled with letters
        labNum="$(echo ${zip} | grep -oe "Lab [A-K0-9][0-9]*" | sed 's/Lab //')"
        #Spring 2016: They removed the space between lab and ID; so run this
        #check and attempt to recover
        if [ -z "${labNum}" ]; then
            labNum="$(echo ${zip} | grep -oe "Lab[A-K0-9][0-9]*" \
                | sed 's/Lab//')"
        fi
        if [[ ${RMSEC} = 0 ]]; then
            secChar="$(printf "\x$(printf %x ${asciiCode})")"
        else
            secChar="all"
        fi
        pathList[$i]="${LABNAME}${labNum}/${SECNAME}${secChar}"
        mkdir -p "${pathList[$i]}"
        mkLabDirs "${LABNAME}${labNum}"
        #if folder creation is successful, continue with unpacking the zips
        if [[ $? = 0 ]]; then
            #now unzip the file into the newly created folder
            unzip -q "${zipPath}" -d ${pathList[$i]} 
            if [[ $? = 0 ]]; then
                #if cleanup mode is enabled, remove the original zip
                if [[ ${CLEANUP} = 0 ]]; then
                    rm "${zipPath}"
                    if [[ ! $? = 0 ]]; then
                        echoerr "Clean up mode: failed to delete ${zipPath}"
                    fi
                fi
            else
                echoerr "Failed to unpack ${zip}"
                #mark failures to keep list in alignment and for future checks
                pathList[$i]=${MRKFAIL}"${pathList[$i]}"
                let failCntr++
            fi
        else
            echoerr "Failed create folder for ${zip}"
            pathList[$i]=${MRKFAIL}"${pathList[$i]}"
            let failCntr++
        fi
        let asciiCode++
        let i++
    done
    if [[ ${failCntr} = 0 ]]; then
        echosucc "Top-level zip files successfully unpacked!"
    else
        echoerr "${failCntr} failures unpacking the top-level zip files"
    fi
}

#Parses file names into user folder names
#@param: 
#        $1 file name to parse
#
#@return: 
#        - The sanitized folder name (via echo; use subshell to retrieve)
#
#@global:
#        
function fileToFolder {
    local file="$1"
    #extract various pieces out of the file name
    local first=""
    first="$(echo "${file}" | grep -oe ", .* -" | sed 's/ -//' | sed 's/, //' | sed 's/ /_/')"
    local last="$(echo "${file}" | grep -oe "- .*," | sed 's/- //' | sed 's/,//')"
    local uid="$(echo "${file}" | grep -oe "[0-9]*-" | sed 's/-//')"
    #organize first/last name as indicated by flag
    if [[ ${FIRSTNAME} = 0 ]]; then
        echo "${first}_${last}_${uid}"
    else
        echo "${last}_${first}_${uid}"
    fi
}

#Parses file names to a "base name" (file name and extension)
#@param: 
#        $1 file name to parse
#
#@return: 
#        - The sanitized file name (via echo; use subshell to retrieve)
#
#@global:
#        
function fileToBasename {
    local file="$1"
    #extract the last portion of the file name and sanitize
    local newFile="$(echo "${file}" | grep -oe ", .* - .*\..*" | sed 's/, .* - //')"
    echo "${newFile}"
}

#Detects if a file name is an old submission
#@param: 
#        $1 file name to check
#
#@return: 
#        - 0 for true, 1 for false (via echo; use subshell to retrieve)
#
#@global:
#        
function checkIfCopy {
    local file="$1"
    local check=$(echo "${file}" | grep -oe "([0-9][0-9]*)\..*")
    #return accordingly
    if [[ -z ${check} ]]; then
        echo "1"
    else
        echo "0"
    fi
}

#Detects if a file is a zip file
#@param: 
#        $1 file name to check
#
#@return: 
#        - 0 for true, 1 for false (via echo; use subshell to retrieve)
#
#@global:
#        
function checkIfZip {
    local file="$1"
    local check=$(echo "${file}" | grep -oe ".*\.zip$")
    #return accordingly
    if [[ -z ${check} ]]; then
        echo "1"
    else
        echo "0"
    fi
}

#Detects if a submission is late or not
#@param: 
#        $1 folder to check (full path)
#
#@return: 
#        - 0 for true, 1 for false (via echo; use subshell to retrieve)
#
#@global:
#        - dueDate date that the assignment is due (in Epoch milliseconds)
#          Valid user input examples: 
#              "1/1/1970 02:00", "1/1/1970" or other accepted forms
#
function checkIfLate {
    local folder="$1"
    #get the file's last modified time in terms of milliseconds since the epoch
    local fileTime=""
    for file in "${folder}"/*; do
        fileTime=$(stat -c %Y "${file}")
        #if one file is late, then it is a late submission
        if [[ ${fileTime} -gt ${dueDate} ]]; then
            echo 0
            break
        else
            echo 1
        fi
    done
}

#Groups files into folders by user and Unique IDs and renames files per
#   directory
#@param: 
#        $1 local directory to check files in 
#
#@return: 
#        - failCntr return the number of failures occured (acts as $?)
#@global:
#
function organizeFiles {
    failCntr=0
    local dir="$1"
    local folderName=""
    local newFile=""
    #to shorten compound vars; and to fit in 80 chars
    local newFilePath=""
    for file in "${dir}"/*; do
        #file includes path in the current form, which we need to correct
        file=$(basename "${file}")
        #check if we want to remove any copies
        if [[ ${CLEANOLD} = 0 && $(checkIfCopy "${file}") = 0 ]]; then
            rm "${dir}/${file}"
            #break out of current iteration upon clean-up
            continue
        fi
        #check for and then make a user folder if it's missing
        folderName=$(fileToFolder "${file}")
        #invalid files result in __ (like the index file or directories)
        if [[ ! "${folderName}" = "__" ]]; then
            if [[ ! -d "${dir}/${folderName}" ]]; then
                mkdir "${dir}/${folderName}"
                if [[ ! $? = 0 ]]; then
                    echoerr "Failed to create directory ${dir}/${folderName}"
                    let failCntr++
                fi
            fi
            newFile=$(fileToBasename "${file}")
            #move the file to the folder with the new name
            newFilePath="${dir}/${folderName}/${newFile}"
            mv "${dir}/${file}" "${newFilePath}" 
            if [[ ! $? = 0 ]]; then
                echoerr "Failed to move file ${dir}/${file}"
                let failCntr++
            fi
            #unzip the latest zips; do not unzip duplicate submissions
            #in fear of stomping-out the latest copy
            copyCheck=$(checkIfCopy "${newFile}")
            if [[ $(checkIfZip "${newFile}") = 0 && ! ${copyCheck} = 0 ]]; then
                unzip -q "${newFilePath}" -d "${dir}/${folderName}"
                if [[ ! $? = 0 ]]; then
                    echoerr "Failed to unzip file ${newFilePath}"
                    let failCntr++
                fi
                #if the unzipping resulted in a folder with the same name,
                #as the zip file (minus the zip), move those files up
                local noZip=$(basename "${newFilePath}" .zip)
                if [[ -d "${dir}/${folderName}/${noZip}" ]]; then
                    mv "${dir}/${folderName}/${noZip}"/* "${dir}/${folderName}"
                    #if the move worked, delete the empty folder
                    if [[ $? = 0 ]]; then
                        rm -r "${dir}/${folderName}/${noZip}"
                    fi
                fi
                #clean up that stupid Mac temp folder that some kids always
                #end up zipping up by mistake
                if [[ -d "${dir}/${folderName}/__MACOSX"  ]]; then
                    rm -r "${dir}/${folderName}/__MACOSX"
                fi
                # correct for IntelliJ submissions
                if [[ -d "${dir}/${folderName}/src" ]]; then
                    cp "${dir}/${folderName}/"src/* "${dir}/${folderName}/"
                fi
                #MyCourses added an extra directory to sanitize, that is the 
                #student's RIT user name
                local idDir=""
                for idDir in "${dir}/${folderName}/*/"; do
                    if [[ "$(basename ${idDir})" =~ [a-z]{2,3}[0-9]{4} ]]; then
                        mv "${dir}/${folderName}/$(basename ${idDir})"/* "${dir}/${folderName}/"
                        rm -r "${dir}/${folderName}/$(basename ${idDir})"
                    fi
                done
            fi
        fi
    done
    if [[ ${failCntr} = 0 ]]; then
        echosucc "Files in directory ${dir} have been organized"
    else
        echoerr "${failCntr} failures trying to organize ${dir}"
    fi
}

#Groups files into folders by user and Unique IDs, renames files accordingly,
#   and marks late submissions
#@param: 
#
#@return: 
#
#@global:
#        - pathList is used to loop over directories to organize
function groupFiles {
    for dir in "${pathList[@]}"; do
        #only organize the file if there wasn't a failure
        if [[ ! ${dir:0:5} = ${MRKFAIL} ]]; then
            organizeFiles "${dir}"
            #loop over all new folders in the top-level directory
            for submission in "${dir}"/*/; do
                #make a folder to store a student's output
                mkdir ${submission}${OUTPUT_DIR}
                #mark late submissions as such
                if [[ ${LATESUB} = 0 && ${failCntr} = 0 ]]; then
                    isLate=$(checkIfLate "${submission}")
                    if [[ ${isLate} = 0 ]]; then
                        lateName="${dir}/${MRKLATE}$(basename "${submission}")"
                        mv "${submission}" "${lateName}"
                    fi
                fi
            done
        else 
            echoerr "Previous errors prevent ${dir:5} from being organized"
        fi
    done
}

####   GETOPTS   ####
#Flags for modes of operation
while getopts ":cfloqs" opt; do
    case $opt in
        c)
            CLEANUP=0
            ;;
        f)
            FIRSTNAME=0
            ;;
        l)
            LATESUB=0
            ;;
        o)
            CLEANOLD=0
            ;;
        q)
            QUIET=0
            ;;
        s)
            RMSEC=0
            ;;
        *)
            echoerr "${USAGE}"
            exit 1
            ;;
    esac
done

####    MAIN     ####
function main {
    #shift after reading getopts
    shift $(($OPTIND - 1))
    #if the late flag is specified, then the first arg has to be a date
    if [[ ${LATESUB} = 0 ]]; then
        #check if date is well-formed
        local dateTest="$(date -d "$1" +%s)"
        if [[ $? = 0 ]]; then
            shift 1
            dueDate="${dateTest}"
        else
            echoerr "Date is not in a valid format. 'man date' for more info"
            echoerr "Exiting..."
            exit 1
        fi
    fi
    #record list of file names from command line args
    zipList=("${@}")
    #no args after flags, present usage message
    if [[ ${#zipList[@]} = 0 ]]; then
        echoerr ${USAGE}
        exit 1
    fi
    #turn the zips into a local file structure
    mkZipDirs "${zipList[@]}"
    #group, name, and organize files
    groupFiles
}

main "${@}"
