#!/bin/bash
#
#This script compiles, runs, records output, and diff's student submissions.
#
#We assume that ./organize.sh has been run prior to executing this script (as
#   in the lab folder passed-in has been "organized") and that the provided,
#   test, and expected output files are stored in the correct folders
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
declare -r USAGE="Usage: ./batchRun.sh [-q] [-t] [time_out] #_tests lab exec_file"

#file extensions for comparison purposes; does not include dot for pattern 
#   purposes (issue with escaping the character in a variable)
declare -r EXT_JAVA="java"
declare -r EXT_PY="py"

#timeout exits with a 124 error code
declare -r TIME_ERR=124

####    FLAGS    ####
#All flags are = 0 for on

#User-specified timeout for the program runs
TIMEFLAG=1

#### GLOBAL VARS ####
#Default timeout given to a program's run time; this value can change with flag
TIME_OUT="60s"

#values passed in
#number of tests to run
numTests=0
#path to lab
labDIR=""
#file that gets run
execFile=""

#determined file type for this lab
fileType=""

#array of test arguments; one index for test
testArgs=()
#expected output files for each test; these are the files we diff against
expectedOut=()

#global stat tracking
statComplete=0
statFail=0
statTime=0
#only applies to Java programs
statCompile=0

####  FUNCTIONS  ####

#Determine if this is a Python (CS1) or Java (CS2) lab
#   Exits the script if a file type can't be determined
#@param: 
#
#@return: 
#
#@global:
#        - execFile used to determine the type of project
#        - fileType type of lab this is
function determineFileType {
    local check=""
    check="$(echo "${execFile}" | grep -oe ".*\.${EXT_PY}$")"
    if [[ ! -z ${check} ]]; then
        fileType=${EXT_PY}
    fi
    check="$(echo "${execFile}" | grep -oe ".*\.${EXT_JAVA}$")"
    if [[ ! -z ${check} ]]; then
        fileType=${EXT_JAVA}
    fi
    if [[ -z ${fileType} ]]; then
        echoerr "Lab type (Java/Python) could not be determined."
        echoerr "Make sure your directory structure is correct"
        echoerr "Exiting..."
        exit 1
    fi
}

#Asks for the arguments to pass to each program for each test and stores them
#as a list of test arguments; for simplicity files 
#@param: 
#
#@return: 
#
#@global:
#        - testArgs List of test arguments that is set
function testArgMenu {
    local index=0
    #pathing to test files relative to file execution
    local labPath="$(echo "${labDIR}" | sed 's/\//\\\//g')"
    local relPath="${labPath}\/${TEST_DIR}\/"
    local relPath2="${labPath}\/${EXPECTED_DIR}\/"
    #subsitution system to handle relative pathing to files in test_files
    local subsArray=()
    local subsArrayDiff=()
    #don't ask for files to diff against if they aren't in the folder
    local askForDiff=0
    echosucc "==== Setting Test Arguments ===="
    #display all files in the test files folder, for user's convenience
    #Note that users can use substitutions ($n) to automatically handle
    #pathing to the test files; users can also manually do this
    if [[ -z "$(ls ${labDIR}/${TEST_DIR})" ]]; then
        #warn that test files are missing
        echowarn "No files were found in the ${TEST_DIR} directory"
    else
        echo "Files found in the ${TEST_DIR} directory:"
        for file in "${labDIR}/${TEST_DIR}"/*; do
            echo "    \$${index} = $(basename "${file}")"
            subsArray[${index}]="${relPath}$(basename "${file}")"
            let index++
        done
        echo "Use '\$num' to automatically substitute-in these files and paths"
    fi
    #reset to count-off again
    index=0
    #display all files in the expected output files folder
    #Note that the subsitution system is not applied here because there
    #should only need to be one file to diff against, not a list of args
    if [[ -z "$(ls ${labDIR}/${EXPECTED_DIR})" ]]; then
        #warn that test files are missing
        echowarn "No files were found in the ${EXPECTED_DIR} directory"
        askForDiff=1
    else
        echo "Files found in the ${EXPECTED_DIR} directory:"
        for file in "${labDIR}/${EXPECTED_DIR}"/*; do
            echo "    \$${index} = $(basename "${file}")"
            subsArrayDiff[${index}]="${relPath2}$(basename "${file}")"
            let index++
        done
    fi
    #read in the arguments
    local i=0
    local args=""
    local exOutFile=""
    while [[ $i -lt ${numTests} ]]; do
        #do not check input(s) for empty strings, in case a program doesn't
        #need arguments or have expected output files to test against
        read -p "Enter args for test[$i]: " args
        #parse through subsitutions
        local cntr=0
        for sub in "${subsArray[@]}"; do
            args="$(echo "${args}" | sed 's/$'"${cntr}"'/'"${sub}"'/g')"
            let cntr++
        done
        testArgs[$i]="${args}"
        cntr=0
        if [[ ${askForDiff} = 0 ]]; then
            read -p "Enter an expected output file for test[$i]: " exOutFile
            #this can probably get cleaned-up a bit
            for sub in "${subsArrayDiff[@]}"; do
                exOutFile="$(echo "${exOutFile}" | sed 's/$'"${cntr}"'/'"${sub}"'/g')"
                let cntr++
            done
            expectedOut[$i]="${exOutFile}"
        fi
        let i++
    done
}

#Copy all provided files into a student's directory
#   This will not stomp over any files with the same name; if students submit
#   modified files they were not supposed to change, their programs will fail 
#   to run initially, but the original will be preserved for partial credit
#   Note: these backups will be hidden and numbered
#@param: 
#        $1 current student directory
#
#@return: 
#
#@global:
#
function cpProvidedFiles {
    local stuDIR="$1"
    local file=""
    local errCode=0
    #check if the provided_files directory is empty
    if [[ ! -z "$(ls "${labDIR}/${PROVIDED_DIR}/")" ]]; then
        echo "Starting to copy provided files for $(basename "${stuDIR}")"
        for file in "${labDIR}/${PROVIDED_DIR}/"*; do
            cp -r --backup=t "${file}" "${stuDIR}"
            errCode=$?
            if [[ ${errCode} = 0 ]]; then
                echosucc "Successfully copied ${file}"
            else
                echoerr "Failed to copy ${file} with error code: ${errCode}"
            fi
        done
    fi
}

#Run a Python program
#@param:
#        $1 Path to student's directory
#        $2 Test number
#@return:
#        - errCode Exit Code returned after run
#@global:
#
function runPy { 
    local stuDIR="$1"
    local testNum=$2
    errCode=0
    #location to store output
    local outFile="${stuDIR}${OUTPUT_DIR}/${OUT_FILE}${execFile%.*}_$i"
    #set a processing time-out per execution, push test arguments in (CS1 does 
    #not go over cmd line args and uses user input instead) and records output
    local parsed="$(echo ${testArgs[$i]} | sed 's/ /\\n/')"
    #execute the run in a new shell so that time-out can kill the process
    timeout "${TIME_OUT}" bash -c \
        "printf '${parsed}' | python3 '${stuDIR}${execFile}' &> '${outFile}'"
    #if the program timed-out, it'll be recorded in $? as an error code
    errCode=$?
}

#Run a Java program
#@param:
#        $1 Path to student's directory
#        $2 Test number
#@return:
#        - errCode Exit Code returned after run
#@global:
#
function runJava {
    local stuDIR="$1"
    local testNum=$2
    #tracks if the build failed
    local buildFail=0
    errCode=0
    #location to store output
    local outFile="${stuDIR}${OUTPUT_DIR}/${OUT_FILE}${execFile%.*}_$i"
    #pathing local to student directory
    local outFileLocal="${OUTPUT_DIR}/${OUT_FILE}${execFile%.*}_$i"
    #create/clear-out the output file for each run
    printf "" > "${outFile}"
    local runFile="$(echo "${execFile}" | sed 's/\.java//')"
    #compile process; only compile once if successful
    if [[ ! -f "${stuDIR}${runFile}.class" ]]; then
        echo "Compiling project..."
        #simplified compilation process attempts to compile all java files in
        #the student directory
        #push dir
        local st_dir="$(pwd)"
        cd "${stuDIR}"
        javac *.java >> "${outFileLocal}" 2>&1
        buildFail=$?
        #pop dir
        cd "${st_dir}"
    fi
    #run only after a successfull build
    if [[ ${buildFail} = 0 ]]; then
        #might need to break args up by spaces
        #execute the run in a new shell so that time-out can kill the process
        echo "Running project..."
        #b/c I like 80 char limits
        local argCopy="${testArgs[$testNum]}"
        timeout "${TIME_OUT}" bash -c \
            "java -cp '${stuDIR}' '${runFile}' ${argCopy} >> '${outFile}' 2>&1"
        #if the program timed-out, it'll be recorded in $? as an error code
        errCode=$?
    else
        echowarn "Student submission failed to compile."
        #increment the compile fails
        let statCompile++
        #errCode set to 404 (compile not found =P); b/c the test did not finish
        errCode=404
    fi
}

#Handle running either kind of program; dumping all the output to a file
#@param:
#        $1 Path to student's directory
#@return:
#
#@global:
#        - fileType type of lab this is
function runProgram {
    local stuDIR="$1"
    local i=0
    local outFile=""
    local diffFile=""
    local exOutFile=""
    #highlight the student's name in echo
    local clearScr="\033[1m\033[0m"
    local hlStu='\E[1;35m'
    #looping structure for all tests provided by the user
    while [[ $i -lt ${numTests} ]]; do
        printf "Starting test[$i] for student${hlStu} $(basename "${stuDIR}")"
        printf "${clearScr}...\n"
        #echo "Starting test[$i] for student $(basename "${stuDIR}")..."
        if [[ ${fileType} = ${EXT_PY} ]]; then
            runPy "${stuDIR}" $i
        else
            runJava "${stuDIR}" $i
        fi
        #output file for run
        outFile="${stuDIR}${OUTPUT_DIR}/${OUT_FILE}${execFile%.*}_$i"
        #error code processing
        if [[ ! ${errCode} = 0 ]]; then
            #specific phrasing
            local errOut=""
            if [[ ${errCode} = ${TIME_ERR} ]]; then
                errOut="timed-out"
                let statTime++
            else
                errOut="exited-out"
                let statFail++
            fi
            echo "Program ${errOut} with error code: ${errCode}" >> "${outFile}"
            echoerr "$(basename "${stuDIR}") ${errOut} on test[$i] with \
                error code: ${errCode}"
        else
            let statComplete++
        fi
        #run diff of the output after the run, if applicable
        if [[ ! -z ${expectedOut[$i]} ]]; then
            echo "Running diff for test[$i]..."
            diffFile="${stuDIR}${OUTPUT_DIR}/${DIFF_FILE}${execFile%.*}_$i"
            exOutFile="${expectedOut[$i]}"
            diff -w "${outFile}" "${exOutFile}" &> "${diffFile}"
        fi
        let i++
    done
}

####   GETOPTS   ####
while getopts ":qt" opt; do
    case $opt in
        q)
            QUIET=0
            ;;
        t)
            TIMEFLAG=0
            ;;
        *)
            echoerr ${USAGE} 
            exit 1
            ;;
    esac
done

####    MAIN     ####
function main {
    #shift after reading getopts
    shift $(($OPTIND - 1))
    #if the time out is specified, it becomes the first arg
    if [[ ${TIMEFLAG} = 0 ]]; then
        TIME_OUT="$1"
        shift 1
    fi
    #no args after flags, present usage message
    if [[ ${#@} -lt 3 ]]; then
        echoerr ${USAGE}
        exit 1
    fi
    #set args passed in
    numTests=$1
    labDIR="$2"
    execFile="$3" 
    if [[ ! -d "${labDIR}" ]]; then
        echoerr "Could not find lab: ${labDIR}"
        exit 1
    fi  
    #check what kind of lab this is
    determineFileType
    #define arguments passed in for each test
    testArgMenu
    #loop over all sections in a lab; only folders
    echosucc "==== Starting Tests ===="
    for sec in "${labDIR}/${SECNAME}"*/; do
        echosucc "==== Starting on: $(basename "${sec}") ===="
        #loop over all students in a section; only folders
        for student in "${sec}"*/; do
            cpProvidedFiles "${student}"
            #run the student's program
            runProgram "${student}"
        done
    done
    echosucc "==== Tests Completed ===="
    #Report some basic stats
    echo "+++++  Final Report  +++++"
    echo "=========================="
    if [[ ${fileType} = ${EXT_JAVA} ]]; then
        echo "Failed to compile:    ${statCompile}"
        echo "=========================="
    fi
    echo "Tests completed:      ${statComplete}"
    echo "Tests timed-out:      ${statTime}"
    echo "Tests failed:         ${statFail}"
    echo "--------------------------"
    statTotal="$((statComplete + statTime + statFail))"
    echo "Total # of tests:     ${statTotal}"
}

main "${@}"
