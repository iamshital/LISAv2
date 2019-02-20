#!/bin/bash

#######################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the Apache License.
#
#######################################################################

#######################################################################
#
# olq_vm_utils.sh
#
# Description:
#   common functions for OL cases
# Dependency:
#   utils.sh
#######################################################################

. utils.sh || {
    echo "ERROR: unable to source utils.sh!"
    echo "TestAborted" > state.txt
    exit 2
}

ICA_TESTABORTED="TestAborted"      # Error during the setup of the test
ICA_TESTFAILED="TestFailed"        # Error occurred during the test
OL_BUILD_DIR="$LIS_HOME/OLBuild"

Update_Test_State()
{
    echo "${1}" > state.txt
}

Mock_Sudo()
{
while echo "$1" | grep -q ^-; do
        declare $( echo "$1" | sed 's/^-//' )=$2
        shift
        shift
done

if [ "x$user" == "x" ] || [ "x$passwd" == "x" ] || [ "x$olip" == "x" ] || [ "x$port" == "x" ]  ; then
        echo "Usage: mock_sudo -user <username> -passwd <user password> -olip <olip> -port <port> "
        Update_Test_State $ICA_TESTABORTED
        exit 0
    fi
cat << EOF > ./sudo
#!/bin/bash
POSITIONAL=()
while [[ \$# -gt 0 ]]
do
key="\$1"
case \$key in
    -S*)
    shift
    ;;
    -s*)
    shift
    ;;
    *)
    POSITIONAL+=("\$1")
    shift # past argument
    ;;

esac
done
"\${POSITIONAL[@]}"
EOF
    remote_copy -host $OLip -user $user -passwd $passwd -port $port -filename "./sudo" -remote_path "/bin" -cmd "put"
    remote_exec -host $OLip -user $user -passwd $passwd -port $port "chmod 777 /bin/sudo"
} 

Install_QEMU()
{
#Currenty only ubuntu is supported.
    sudo add-apt-repository -y ppa:jacob/virtualisation 
    update_repos
    install_package aria2
    install_package qemu-system 
    install_package qemu-system-arm 
    sudo apt-get upgrade -y qemu 
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        echo "Failed to install QEMU"
        Update_Test_State $ICA_TESTFAILED
        exit 0
    else
        echo "Install QEMU succeed"
    fi
    which qemu-system-aarch64
    if [ $? -ne 0 ]; then
        echo "Cannot find qemu-system-aarch64"
        Update_Test_State $ICA_TESTFAILED
        exit 0
    fi
}

Download_Image_Files()
{
    while echo $1 | grep -q ^-; do
       declare $( echo $1 | sed 's/^-//' )=$2
       shift
       shift
    done
    if [ "x$destination_image_name" == "x" ] || [ "x$source_image_url" == "x" ] ; then
        echo "Usage: GetImageFiles -destination_image_name <destination image name> -source_image_url <source OL image url>"
        Update_Test_State $ICA_TESTABORTED
        exit 0
    fi
    echo "Downloading $OLImageUrl..."
    rm -f $destination_image_name
    aria2c -o $destination_image_name -x 10 $source_image_url
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        echo "Download OL image fail $OLImageUrl"
        Update_Test_State $ICA_TESTFAILED
        exit 0
    else
        echo "Download OL image succeed"
    fi
    rm -rf $OL_BUILD_DIR
    mkdir $OL_BUILD_DIR && tar xf $destination_image_name -C $OL_BUILD_DIR
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        echo "untar of OL image failed"
        Update_Test_State $ICA_TESTFAILED
        exit 0    
    fi
    cp -r $OL_BUILD_DIR/* $LIS_HOME && gunzip $OL_IMAGE_NAME
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        echo "gunzip of OL image failed"
        Update_Test_State $ICA_TESTFAILED
        exit 0
    else
        echo "gunzip of OL image succeed"
    fi

}

Start_OL_VM()
{
    while echo $1 | grep -q ^-; do
       declare $( echo $1 | sed 's/^-//' )=$2
       shift
       shift
    done

    if [ "x$user" == "x" ] || [ "x$passwd" == "x" ] || [ "x$olip" == "x" ] || [ "x$port" == "x" ]  ; then
        echo "Usage: StartQemuVM -user <username> -passwd <user password> -olip <olip> -port <port> "
        Update_Test_State $ICA_TESTABORTED
        exit 0 
    fi

    ROOTFS=$(echo ${OL_IMAGE_NAME::-3})
    KERNEL="Image"
    qemu-system-aarch64 \
                -device virtio-net-device,netdev=network0,mac=52:54:00:12:34:02 \
                -netdev user,id=network0,hostfwd=tcp:$OLip:$port-:22 \
                -drive id=disk0,file=$ROOTFS,if=none,format=raw \
                -device virtio-blk-device,drive=disk0 \
                -kernel $KERNEL \
                -machine virt -cpu cortex-a57 -m "1024" -smp "1" \
                -display none -daemonize \
                -append "root=/dev/vda rw highres=off console=ttyAMA0,38400 ip=dhcp selinux=0" \
                -monitor null -serial null -show-cursor
    exit_status=$?
    if [ $exit_status -ne 0 ]; then
        LogMsg "starting OL image failed"
        Update_Test_State $ICA_TESTFAILED
        exit 0
    fi    
    echo "Wait for the OL VM to boot up ..."
    sleep 30
    retry_times=40
    exit_status=1
    while [ $exit_status -ne 0 ] && [ $retry_times -gt 0 ];
    do
        retry_times=$(expr $retry_times - 1)
        if [ $retry_times -eq 0 ]; then
            echo "Timeout to connect to the OL VM"
            Update_Test_State $ICA_TESTFAILED
	    LogMsg "Could not connect OL VM"
            exit 0
        else
            sleep 10
            echo "Try to connect to the OL VM, left retry times: $retry_times"
            remote_exec -host $OLip -user $user -passwd $passwd -port $port "hostname"
            exit_status=$?
        fi
    done
    if [ $exit_status -ne 0 ]; then
        Update_Test_State $ICA_TESTFAILED
	    LogMsg "Could not Start OL VM"
        exit 0
    fi
    Mock_Sudo -user $user -passwd $passwd -port $port -olip $OLip 
}

Log_Msg()
{
    echo $(date "+%b %d %Y %T") : "$1" >> $2
}


###########################################################################################
# main
###########################################################################################
ImageName="ol"
UtilsInit

LogMsg "logfolder is $LIS_HOME"
while echo "$1" | grep -q ^-; do
        declare $( echo "$1" | sed 's/^-//' )=$2
        shift
        shift
done

if [ -z "$OLImageUrl" ] ||  [ -z "$OLip" ] ||  [ -z "$HostFwdPort" ] ||  [ -z "$OLUser" ] || [ -z "$OLUserPassword" ] || [ -z "$OLImageName" ]; then
        echo "Please mention -OLImageUrl -OLip -HostFwdPort -OLUser -OLUserPassword -OLImageName]"
        exit 1
fi
OL_IMAGE_NAME=$OLImageName

Install_QEMU
if [ 0 -eq $? ]; then
    LogMsg "Installed QEMU successfully"
fi

Download_Image_Files -destination_image_name $ImageName  -source_image_url $OLImageUrl
if [ 0 -eq $? ]; then
    LogMsg "Downloaded and extracted OL image successfully"
fi

Start_OL_VM -user $OLUser -passwd $OLUserPassword -olip $OLip -port $HostFwdPort
if [ 0 -eq $? ]; then
    LogMsg "OL image successfully booted"    
fi

Mock_Sudo -user $OLUser -passwd $OLUserPassword -olip $OLip -port $HostFwdPort
if [ 0 -eq $? ]; then
    LogMsg "copy sudo successfully"
    SetTestStateCompleted
fi

