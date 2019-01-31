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
            defaultValue: '',
            description: 'Link to the lis archive to be tested'],
        [$class: 'StringParameterDefinition',
            name: 'LIS_OLD_ARCHIVE_LINK',
            defaultValue: "TEST2",
            description: 'Link to the previous lis version'],
        [$class: 'ChoiceParameterDefinition', choices: 'no\nyes',
            name: 'FULL_PERF_RUN',
            description: 'Full run local Hyper-V perf switch.'],
        [$class: 'StringParameterDefinition',
            name: 'ENABLED_STAGES',
            defaultValue: "deployment_scenarios,perf,validation",
            description: 'What stages to run']
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

def PassingDistros = ["centos_7.5","centos_7.4","centos_7.3","rhel_7.5",\
                        "rhel_7.3_gen2vm","centos_6.8_x64","centos_6.8_32bit","centos_6.9_32bit", \
                        "rhel_6.8_x64","centos_7.0_x64"," centos_7.2_x64","rhel_7.2", \ 
                        "oracle_6.9_rhck","rhel_7.0","oracle_7.4_rhck","oracle_7.0_rhck", \ 
                        "rhel_7.1"]
                        
// defines test validation type - FVT or BVT
def validationXmlMap = ["lis_pipeline_fvt.xml":"centos_6.8_x64,centos_7.2_x64,rhel_6.6_x64,centos_7.4_gen2vm,rhel_6.10_x64,rhel_7.4,rhel_7.5,", \
                        "lis_pipeline_bvt.xml":"centos_6.4_x64,rhel_7.1,rhel_6.4_32bit,rhel_6.9_x64,rhel_7.0,centos_6.5_x64,centos_7.3,centos_7.5,"]

def supportedDistros = nodesMap["ws2012"] + nodesMap["ws2012r2"] + nodesMap["ws2016"] + nodesMap["sriov"]
//def supportedDistros = nodesMap["ws2016"]
def supportedValidationDistros = validationNodesMap["ws2012_fvt"] + validationNodesMap["ws2012_bvt"] + validationNodesMap["ws2012r2"] + validationNodesMap["ws2016"]

def PowerShellWrapper (psCmd) {
    psCmd = psCmd.replaceAll("\r", "").replaceAll("\n", "")
    bat (script: "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"\$ErrorActionPreference='Stop';[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\"",returnStatus: true)
}

def RunPowershellCommand(psCmd) {
    bat "powershell.exe -NonInteractive -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;$psCmd;EXIT \$global:LastExitCode\""
    //powershell (psCmd)
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

def getValidationXml (map, distro) {
    def xmlName = ''
    def testType = ''
    for (key in map.keySet()) {
        if (map[key].contains("${distro},")) {
            xmlName = key
            if(xmlName.contains("fvt")) {
                testType = "fvt"
            } else if (xmlName.contains("bvt")) {
                testType = "bvt"
            }
            break
        }
    }
    return [xmlName, testType]
}

DISTROS = getDistros (DISTRO_VERSIONS, supportedDistros)

stage ("Deploy stage") {
    def globalSleepTime = 0;
    def runs = [:]
    nodesMap.keySet().each {
        def testNode = it
        def mappedDistros = nodesMap[it]
        if (testNode != 'sriov') {
            testNode = 'ws2016'
        }
        DISTROS.each {
            println ("Distros.each ${it}")
            if (mappedDistros.contains("${it},")) {
                runs ["${it}-${testNode}"] = {
                    node ("${testNode}") {
                        stage ("${it}-${testNode}") {
                            println ("stage ${it}-${testNode}")
                                if (PassingDistros.contains("${it}")) {
                                    withCredentials([string(credentialsId: 'REDMOND_VHD_SHARE', variable: 'LISAImagesShareUrl'), 
                                        file(credentialsId: 'Azure_Secrets_File', variable: 'Azure_Secrets_File')]) {
                                        def sleepTime = globalSleepTime
                                        globalSleepTime = globalSleepTime + 30
                                        def lisSuite = ''
                                        if (testNode == 'sriov') {
                                            lisSuite = 'lis_deploy_scenarios_sriov'
                                        } else {
                                            lisSuite = 'lis_deploy_scenarios'
                                        }
                                        dir ("d${BUILD_NUMBER}") {
                                            git branch: 'lisav2hyperv', url: 'https://github.com/iamshital/LISAv2.git'
                                            RunPowershellCommand(".\\JenkinsPipelines\\Scripts\\lis-rpm-hyperv-tests.ps1" +
                                                " -JobId '${it}-d-${BUILD_NUMBER}'" +
                                                " -DistroVersion '${it}'" +
                                                " -TestCategory BVT" +
                                                " -TestArea BVT" +
                                                //" -TestNames BVT-VERIFY-DEPLOYMENT-PROVISION" +
                                                " -LISAImagesShareUrl '${env:LISAImagesShareUrl}'" +
                                                " -LisUrl '${env:LIS_ARCHIVE_LINK}'" +
                                                " -LisOldUrl '${env:LIS_OLD_ARCHIVE_LINK}'" +
                                                " -Delay '${sleepTime}'"
                                            )
                                            junit "Report\\*-junit.xml"
                                            archiveArtifacts '*-TestLogs.zip'
                                        }
                                        cleanWs()
                                    }
                                } else {
                                    println ("SKIPPED. stage ${it}-${testNode}")
                                }
                            }
                        }
                    }
                }
            }
        }
    try {
        if(env.ENABLED_STAGES.contains("deployment_scenarios")) {
            parallel runs
        }
    } catch (exc) { 
        currentBuild.result = 'SUCCESS'
    }
}