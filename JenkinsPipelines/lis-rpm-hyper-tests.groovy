#!/usr/bin/env groovy

properties ([
    disableConcurrentBuilds(),
    [$class: 'ParametersDefinitionProperty',
        parameterDefinitions: [
        [$class: 'StringParameterDefinition',
            name: 'DISTRO_VERSIONS',
            defaultValue: 'centos_all,rhel_all,oracle_all',
            description: 'Distros to be tested (default all)'],
        [$class: 'StringParameterDefinition',
            name: 'LIS_ARCHIVE_LINK',
            defaultValue: 'http://download.microsoft.com/download/6/8/F/68FE11B8-FAA4-4F8D-8C7D-74DA7F2CFC8C/lis-rpms-4.2.8.tar.gz',
            description: 'Link to the lis archive to be tested'],
        [$class: 'StringParameterDefinition',
            name: 'LIS_OLD_ARCHIVE_LINK',
            defaultValue: "http://download.microsoft.com/download/6/8/F/68FE11B8-FAA4-4F8D-8C7D-74DA7F2CFC8C/lis-rpms-4.2.7.tar.gz",
            description: 'Link to the previous lis version'],
        [$class: 'ChoiceParameterDefinition', choices: 'no\nyes',
            name: 'FULL_PERF_RUN',
            description: 'Full run local Hyper-V perf switch.'],
        [$class: 'StringParameterDefinition',
            name: 'ENABLED_TEST_CATEGORIES',
            defaultValue: "Functional,BVT,Stress",
            description: 'What test categories to run'],
        [$class: 'StringParameterDefinition',
            name: 'ENABLED_TEST_AREAS',
            defaultValue: "BVT,LIS_DEPLOY,LIS,BACKUP,CORE,DYNAMIC_MEMORY,FCOPY,KDUMP,KVP,MIGRATION,NETWORK,PROD_CHECKPOINT,RUNTIME_MEMORY,SRIOV,STORAGE,stress",
            description: 'What test areas to run'],
        [$class: 'StringParameterDefinition',
            name: 'EXCLUDE_TESTS',
            defaultValue: "",
            description: ''],
        [$class: 'StringParameterDefinition',
            name: 'RUN_SELECTED_TESTS',
            defaultValue: "",
            description: ''],
        [$class: 'StringParameterDefinition',
            name: 'GIT_REPO',
            defaultValue: "https://github.com/iamshital/LISAv2.git",
            description: ''],
        [$class: 'StringParameterDefinition',
            name: 'GIT_BRANCH',
            defaultValue: "lisav2hyperv",
            description: '']
        ]
    ]
])

// defines deploy scenarios coverage - platform independent
def nodesMap = ["sriov":"rhel_7.3,rhel_7.4,centos_7.4,centos_7.3,rhel_7.3_gen2vm,rhel_7.5,centos_7.5,", \
                "ws2012":"centos_6.8_32bit,centos_6.8_x64,centos_6.9_32bit,rhel_6.7_gen2vm,rhel_6.8_x64,", \
                "ws2012r2":"rhel_6.4_32bit,rhel_6.4_x64,rhel_6.5,rhel_6.6_x64,rhel_6.6_32bit, \
                    centos_6.4_x64,centos_6.5_x64,rhel_6.9_x64,", \
                "ws2016":"oracle_6.5_rhck,oracle_6.9_rhck,oracle_7.4_rhck,oracle_7.0_rhck,centos_7.0_x64, \
                    centos_7.0_gen2vm,centos_7.2_x64,rhel_7.0,rhel_7.1,rhel_7.2,rhel_6.10_x64,"]
//def nodesMap = ["ws2016":"centos_6.8_x64,centos_7.2_x64"]

// defines host version mapping for functional test validation
def validationNodesMap = ["ws2016":"rhel_6.10_x64,rhel_7.4,centos_6.5_x64,centos_7.3,centos_7.2_x64,rhel_7.5,centos_7.5,", \
                          "ws2012r2":"rhel_6.6_x64,centos_7.4_gen2vm,rhel_6.4_32bit,rhel_7.0,centos_6.4_x64,rhel_6.9_x64,", \
                          "ws2012_fvt":"centos_6.8_x64,", \
                          "ws2012_bvt":"rhel_7.1,"]

def PassingDistros = ["centos_7.5","centos_7.4","centos_7.3","rhel_7.5","rhel_7.3_gen2vm","centos_6.8_x64","centos_6.8_32bit","centos_6.9_32bit","rhel_6.8_x64","centos_7.0_x64"," centos_7.2_x64","rhel_7.2","oracle_6.9_rhck","rhel_7.0","oracle_7.4_rhck","oracle_7.0_rhck","rhel_7.1"]

def supportedDistros = nodesMap["ws2012"] + nodesMap["ws2012r2"] + nodesMap["ws2016"] + nodesMap["sriov"]
//def supportedDistros = nodesMap["ws2016"]

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
    //powershell (psCmd)
    //println(psCmd)
}

def getDistros (distros, supportedDistros) {
    def validatedDistros = []
    suppList = supportedDistros.split(",")
    distros = distros.split(",")

    for (distro in distros) {
        distroType = distro.split("_")[0]
        distroVersion = distro.split("_")[1]

        if (distroVersion.toLowerCase() == "all") {
            for (suppDistro in suppList){
                if (distroType.toLowerCase() == suppDistro.split("_")[0]) {
                    validatedDistros << suppDistro
                }
            }
        } else {
            if (supportedDistros.contains(distro.toLowerCase())) {
                validatedDistros << distro.toLowerCase()
            }
        }
    }
    return validatedDistros
}

def ErrorCount = 0
def FVTDistros = "centos_6.8_x64,centos_7.2_x64,rhel_6.6_x64,centos_7.4_gen2vm,rhel_6.10_x64,rhel_7.4,rhel_7.5,"
def BVTDistros = "centos_6.4_x64,rhel_7.1,rhel_6.4_32bit,rhel_6.9_x64,rhel_7.0,centos_6.5_x64,centos_7.3,centos_7.5,"
def SRIOVDistros = "rhel_7.3,rhel_7.4,centos_7.4,centos_7.3,rhel_7.3_gen2vm,rhel_7.5,centos_7.5,"

def CategoryAreaMap = ["Functional" : "LIS_DEPLOY,LIS,DYNAMIC_MEMORY,KVP,MIGRATION,NETWORK,SRIOV,STORAGE,BACKUP,CORE,FCOPY,KDUMP,PROD_CHECKPOINT,RUNTIME_MEMORY",\
                "BVT":"BVT,CORE,NETWORK",\
                "Stress":"stress" ]

def TestAndDistroMap = ["Functional-LIS_DEPLOY" : "${supportedDistros}",\
                "Functional-LIS" : "${supportedDistros}",\
                "Functional-DYNAMIC_MEMORY": "${FVTDistros}",\
                "Functional-KVP": "${FVTDistros}",\
                "Functional-MIGRATION": "${FVTDistros}",\
                "Functional-NETWORK": "${FVTDistros}",\
                "Functional-SRIOV": "${SRIOVDistros}",\
                "Functional-STORAGE": "${FVTDistros}",\
                "Functional-BACKUP": "${FVTDistros}",\
                "Functional-CORE": "${FVTDistros}",\
                "Functional-FCOPY": "${FVTDistros}",\
                "Functional-KDUMP": "${FVTDistros}",\
                "Functional-PROD_CHECKPOINT": "${FVTDistros}",\
                "Functional-RUNTIME_MEMORY": "${FVTDistros}",\
                "BVT-BVT": "${BVTDistros}",\
                "BVT-CORE": "${BVTDistros}",\
                "BVT-NETWORK": "${BVTDistros}",\
                "Stress-stress": "${FVTDistros}"
                ]

node("meta_slave") {

    DISTROS = getDistros (DISTRO_VERSIONS, supportedDistros)

    CategoryAreaMapKeySet=CategoryAreaMap.keySet()
    //println(CategoryAreaMapKeySet)

    CategoryAreaMapSize=CategoryAreaMap.size()
    //println(CategoryAreaMapSize)

    for (i=0;i<CategoryAreaMapSize; i++)
    {
    def CategoryAreaMapKeySetCounter = i
    def CurrentTestCategory= CategoryAreaMapKeySet[CategoryAreaMapKeySetCounter]
    //println (CurrentTestCategory)
    CurrentTestAreas=CategoryAreaMap[CurrentTestCategory]
    //println(CurrentTestAreas)

    for (j=0;j< CurrentTestAreas.split(",").length; j++)
    {
        def AreaCounter = j
        def CurrentArea = CurrentTestAreas.split(",")[AreaCounter]
        try {
            if ((env.ENABLED_TEST_CATEGORIES.split(",").contains(CurrentTestCategory)) && (env.ENABLED_TEST_AREAS.split(",").contains(CurrentArea))) {
                def CurrentLogs = currentBuild.rawBuild.getLog(10000)
                if (CurrentLogs == null) {
                    CurrentLogs = "Unable_To_Get_Logs"
                }
                stage ("${CurrentTestCategory}-${CurrentArea}") {
                    if ((!(CurrentLogs.contains("Aborted by")) && (!(CurrentLogs.contains("FlowInterruptedException"))))) {
                        def globalSleepTime = 0;
                        def branches = 0
                        def runs = [:]
                        def nodesMapLenght = nodesMap.size()
                        def nodesMapKeySet=nodesMap.keySet()
                        for (k=0; k < nodesMapLenght; k++) {
                            def CurrentNodeCounter = k
                            def testNode = nodesMapKeySet[CurrentNodeCounter]
                            def mappedDistros = nodesMap[testNode]
                            if (testNode != 'sriov') {
                                testNode = 'ws2016'
                            }
                            def DISTROS_lenght = DISTROS.size()
                            for (l=0; l < DISTROS_lenght; l++) {
                                def CurrentDistroCounter = l
                                def CurrentDistro = DISTROS[CurrentDistroCounter]
                                def CurrentStageDistros = TestAndDistroMap["${CurrentTestCategory}-${CurrentArea}"]
                                if (mappedDistros.contains("${CurrentDistro},") && CurrentStageDistros != null) {
                                    if ((CurrentArea == "SRIOV" && testNode != 'sriov')) {
                                        //Skip the SRIOV Tests if testnode is not sriov.
                                    } else if (!(CurrentStageDistros.split(",").contains(CurrentDistro))) {
                                        println("${CurrentTestCategory}-${CurrentArea} is not enabled for ${CurrentDistro}")
                                    } else if (!(PassingDistros.contains(CurrentDistro))) {
                                        println(" ${CurrentDistro} is not in PassingDistros.")
                                    }
                                    else {
                                        branches = branches + 1
                                        runs ["${CurrentDistro}-${testNode}"] = {
                                            node ("${testNode}") {
                                                try {
                                                    stage ("${CurrentDistro}-${testNode}") {
                                                    println ("stage ${CurrentDistro}-${testNode}")
                                                        withCredentials([string(credentialsId: 'REDMOND_VHD_SHARE', variable: 'LISAImagesShareUrl'),
                                                            file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
                                                            def sleepTime = globalSleepTime
                                                            globalSleepTime = globalSleepTime + 30
                                                            def lisSuite = ''
                                                            dir ("d${BUILD_NUMBER}") {
                                                                git branch: "${GIT_BRANCH}", url: "${GIT_REPO}"
                                                                RunPowershellCommand(".\\JenkinsPipelines\\Scripts\\lis-rpm-hyperv-tests.ps1" +
                                                                    " -JobId '${CurrentDistro}-d-${BUILD_NUMBER}'" +
                                                                    " -DistroVersion '${CurrentDistro}'" +
                                                                    " -TestCategory ${CurrentTestCategory}" +
                                                                    " -TestArea ${CurrentArea}" +
                                                                    " -LISAImagesShareUrl '${env:LISAImagesShareUrl}'" +
                                                                    " -LisUrl '${env:LIS_ARCHIVE_LINK}'" +
                                                                    " -LisOldUrl '${env:LIS_OLD_ARCHIVE_LINK}'" +
                                                                    " -ExcludeTests '${env:EXCLUDE_TESTS}'" +
                                                                    " -IncludeTests '${env:RUN_SELECTED_TESTS}'" +
                                                                    " -Delay '${sleepTime}'"
                                                                )
                                                                junit "Report\\*-junit.xml"
                                                                archiveArtifacts '*-TestLogs.zip'
                                                            }
                                                        }
                                                    }
                                                } catch (exc) {
                                                    currentBuild.result = 'SUCCESS'
                                                    ErrorCount = ErrorCount + 1
                                                } finally {
                                                    cleanWs()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        try {
                            if ( branches != 0) {
                                parallel runs
                            } else {
                                println ("No tests in this stage.")
                            }
                        } catch (exc) {
                            currentBuild.result = 'SUCCESS'
                            ErrorCount = ErrorCount + 1
                        }                    
                    } else {
                        println("Aborting Stage : ${CurrentTestCategory}-${CurrentArea}")
                    }
                }
            }
        } catch (exc) {
            currentBuild.result = 'SUCCESS'
            println("EXCEPTION")
            println(exc.toString());
            ErrorCount = ErrorCount + 1
        }
    }
    }

    if (ErrorCount == 0) {
        currentBuild.result = 'SUCCESS'
    } else {
        currentBuild.result = 'FAILURE'
    }

}