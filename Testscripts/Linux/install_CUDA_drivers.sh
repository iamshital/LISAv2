#!/bin/bash

########################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
########################################################################
########################################################################
#
# Description:
#   This script installs nVidia GPU drivers.
#   Refer to the below link for supported releases:
#   https://docs.microsoft.com/en-us/azure/virtual-machines/linux/n-series-driver-setup
#
# Steps:
#   1. Install dependencies
#   2. Compile and install GPU drivers
#
########################################################################

#######################################################################
#
# Install dependencies and GPU drivers
#
#######################################################################
function InstallGPUDrivers() {
    GetDistro
    update_repos
    install_package wget lshw gcc

    case $DISTRO in
    redhat_7|centos_7)
        CUDA_REPO_PKG="cuda-repo-rhel7-${CUDADriverVersion}.x86_64.rpm"
        LogMsg "Using ${CUDA_REPO_PKG}"

        if [[ $DISTRO -eq centos_7 ]]; then
            # for all releases that are moved into vault.centos.org
            # we have to update the repositories first
            yum -y install centos-release
            yum clean all
            yum -y install --enablerepo=C*-base --enablerepo=C*-updates kernel-devel-$(uname -r) kernel-headers-$(uname -r)
        else
            yum -y install kernel-devel-$(uname -r) kernel-headers-$(uname -r)
        fi

        install_epel
        yum --nogpgcheck -y install dkms hyperv-tools

        wget http://developer.download.nvidia.com/compute/cuda/repos/rhel7/x86_64/"${CUDA_REPO_PKG}" -O /tmp/"${CUDA_REPO_PKG}"
        if [ $? -ne 0 ]; then
            LogErr "Failed to download ${CUDA_REPO_PKG}"
            SetTestStateAborted
            return 1
        fi

        rpm -ivh /tmp/"${CUDA_REPO_PKG}"
        rm -f /tmp/"${CUDA_REPO_PKG}"
        yum --nogpgcheck -y install cuda-drivers
        if [ $? -ne 0 ]; then
            LogErr "Failed to install the cuda-drivers!"
            SetTestStateAborted
            return 1
        fi
        ;;

    ubuntu*)
        GetOSVersion
        CUDA_REPO_PKG="cuda-repo-ubuntu${os_RELEASE//./}_${CUDADriverVersion}_amd64.deb"
        LogMsg "Using ${CUDA_REPO_PKG}"

        wget http://developer.download.nvidia.com/compute/cuda/repos/ubuntu"${os_RELEASE//./}"/x86_64/"${CUDA_REPO_PKG}" -O /tmp/"${CUDA_REPO_PKG}"
        if [ $? -ne 0 ]; then
            LogErr "Failed to download ${CUDA_REPO_PKG}"
            SetTestStateAborted
            return 1
        fi

        apt-key adv --fetch-keys http://developer.download.nvidia.com/compute/cuda/repos/ubuntu"${os_RELEASE//./}"/x86_64/7fa2af80.pub
        dpkg -i /tmp/"${CUDA_REPO_PKG}"
        rm -f /tmp/"${CUDA_REPO_PKG}"

        dpkg_configure
        apt -y --allow-unauthenticated install linux-tools-generic linux-cloud-tools-generic
        apt update
        apt -y --allow-unauthenticated install cuda-drivers
        if [ $? -ne 0 ]; then
            LogErr "Failed to install the cuda-drivers!"
            SetTestStateAborted
            return 1
        fi
        ;;

    *)
        LogWarn "Distro '${DISTRO}' not supported."
        SetTestStateAborted
        return 1
    ;;
esac
}

#######################################################################
#
# Main script body
#
#######################################################################
# Source utils.sh
. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 0
}
UtilsInit

if ! InstallGPUDrivers; then
    LogErr "Could not install the CUDA drivers!"
    SetTestStateFailed
    exit 0
fi

SetTestStateCompleted
exit 0
