#!/bin/bash

TEST_URL="https://microsoft.com"

function log_msg() {
    echo "[$(date +"%x %r %Z")] ${1}"
    echo "[$(date +"%x %r %Z")] ${1}" >> "./TestExecution.log"
}
function log_err() {
    echo "[$(date +"%x %r %Z")] ${1}"
    echo "[$(date +"%x %r %Z")] ${1}" >> "./TestExecutionError.log"
}

function cleanup() {
    rm -rf Current*
}

function update_test_state() {
    echo "${1}" > ./TestState.log
}

function run() {
    rm -rf CurrentOutput.txt
    rm -rf CurrentError.txt
    log_msg "Running $1"
    $1 > CurrentOutput.txt 2> CurrentError.txt
    exit_code=$?
    CurrentOutput="$(<CurrentOutput.txt)"
    CurrentError="$(<CurrentError.txt)"
    log_msg "STDOUT: $CurrentOutput"
    log_err "STDERR: $CurrentError"
    if [[ "$exit_code" == "0" ]]; then
        true
    else
        false
    fi
}

function main() {

    # Clean the logs and Create empty files
    rm -rf ./TestExecution.log
    rm -rf ./TestExecutionError.log
    touch ./TestExecution.log
    touch ./TestExecutionError.log

    # Source constants file
    if [[ -f "constants.sh" ]]; then
        log_msg "Sourcing constants.sh"
        source "constants.sh"
    fi

    test_result=0

    if [[ "$TestIterations" == "" ]] || [[ -z $TestIterations ]]; then
        log_msg "Setting Test Iterations to $TestIterations"
        TestIterations=1
    else
        log_msg "Setting Test Iterations to $TestIterations from constants.sh"
    fi

    log_msg "*********INFO: Starting test execution ... *********"
    network_interface_prefix="eth"
    network_interface_count=8

    test_iteration=0
    while [[ $test_iteration -lt $TestIterations ]];
    do
        test_iteration=$(( test_iteration + 1 ))
        log_msg "Test Iteration : $test_iteration"

        for eth_number in $(seq 0 $(( $network_interface_count - 1 ))); do
            eth_name="${network_interface_prefix}${eth_number}"
            log_msg "Checking if ${eth_name} is up and has a valid IP"
            eth_ip=$(ip a | grep "${eth_name}" | sed -n '2 p' | awk '{print $2}')
            if [[ "${eth_ip}" != '' ]];then
                log_msg "IP for ${eth_name} is ${eth_ip}"
                # Note(avladu): Enable testing Internet connectivity
                #run "curl --connect-timeout 10 --max-time 10 --interface ${eth_name} ${TEST_URL}"
                #if [[ "$?" -ne '0' ]]; then
                #    log_err "CURL failed for ${eth_name} with output ${curl_test_output}"
                #    test_result=$(( $test_result + 1 ))
                #else
                #    log_msg "CURL succeeded for ${eth_name}"
                #fi
            else
                log_err "IP for ${eth_name} is not set"
                test_result=$(( $test_result + 1 ))
            fi
         done

        log_msg "Sleeping 5 seconds"
        sleep 5
    done


    #####################################################
    # Conclude the result
    if [[ "$test_result" == "0" ]]; then
        update_test_state "PASS"
    else
        update_test_state "FAIL"
    fi

    log_msg "*********INFO: Script execution completed. *********"
}

main
cleanup
exit 0