#!/usr/bin/groovy

/*
*
* This script will create a tag out of releaseBranch branch with name
* `<releaseBranch_RC{number}> specified in `releaseBranch` parameter variable.
* Checks for upstream branch with same name; then stops execution with and exception if same branch found in upstream.
*
* Parameters:
*   Name:   gitCredentialId
*      Type:   jenkins parameter; default value is githubPassword
*      Description:    contains github username and password for the user to be used
*   Name:   releaseBranch
*      Type:   jenkins parameter; default `public_repo_branch` variable
*      Description:    Name of the branch to create
*
* Author: Rajesh Rajendran<rjshrjndrn@gmail.com>
*
* This script uses curl and jq from the machine.
*
*/

// Error message formatting
def errorMessage(message){
    // Creating color code strings
    String ANSI_GREEN = "\u001B[32m"
    String ANSI_NORMAL = "\u001B[0m"
    String ANSI_BOLD = "\u001B[1m"
    String ANSI_RED = "\u001B[31m"
    println (ANSI_BOLD + ANSI_RED + message.stripIndent()+ANSI_NORMAL)
}

repos = [
'Sunbird-Ed/SunbirdEd-portal',
'Sunbird-Ed/SunbirdEd-mobile',
'Sunbird-Ed/SunbirdEd-portal',
'Sunbird-Ed/SunbirdEd-mobile',
'project-sunbird/sunbird-lms-service',
'project-sunbird/sunbird-data-pipeline',
'project-sunbird/sunbird-content-service',
'project-sunbird/sunbird-auth',
'project-sunbird/sunbird-learning-platform',
'project-sunbird/sunbird-content-plugins',
'project-sunbird/sunbird-lms-mw',
'project-sunbird/sunbird-ml-workbench',
'project-sunbird/sunbird-utils',
'project-sunbird/sunbird-analytics',
'project-sunbird/sunbird-telemetry-service',
'project-sunbird/secor',
'project-sunbird/sunbird-devops'
]

// getting Repos to which we've to stop release
upstreamRepos = params.repos
releaseBranch = params.releaseBranch

node {

    // Defining variables
    def gitCredentialId = env.githubPassword
    try{
        // Checking first build and creating parameters
        if (params.size() == 0){
            // Creating active choice compatible choices list
            localRepoList = "['"+repos.join("','")+"']"
            properties([parameters([[$class: 'ChoiceParameter',
                choiceType: 'PT_CHECKBOX', description: '<font color=black size=2><b>Choose the repo to create tag</b></font>',
                filterLength: 1, filterable: true, name: 'repos', randomName: 'choice-parameter-115616285976692',
                script: [$class: 'GroovyScript',
                    fallbackScript: [classpath: [], sandbox: false,
                    script: ''],
                script: [classpath: [], sandbox: false, script: """return $localRepoList """]]],
                string(defaultValue: '', description: '<font color=black size=2><b>Enter the branch name from which tag will be created</b></font>',
                name: 'releaseBranch', trim: false)])])

            ansiColor('xterm') {
                errorMessage '''
                        First run of the job. Parameters created. Stopping the current build.
                        Please trigger new build and provide parameters if required.
                        '''
            }
        return
        }

        // Making sure prerequisites are met
        // All release branch name should be release-*
        if ( ! releaseBranch.contains('release-') ){
            errorMessage 'Release branch name is not proper\nName should be `release-*`'
            error 'release branch name format error'
        }


        // Make sure prerequisites are met
        // If releaseBranch variable not set
        if (releaseBranch == ''){
            ansiColor('xterm'){
               errorMessage 'Release branch name not set'
            }
               error 'Release branch name not set'
        } else if (upstreamRepos == ''){
            errorMessage 'No Repos Selected'
            error 'no repos selected'
        }
        // Checking out public repo
        stage('Ending Release'){
                upstreamRepos.split(',').each { repo ->
                // Cleaning workspace
                cleanWs()
                // Checking out code
                checkout changelog: false, poll: false,
                scm: [$class: 'GitSCM', branches: [[name: '*/master']],
                doGenerateSubmoduleConfigurations: false,
                extensions: [[$class: 'CloneOption', noTags: false, reference: '', shallow: true]],
                submoduleCfg: [], userRemoteConfigs: [[url: "https://github.com/$repo"]]]

                ansiColor('xterm'){
                    if( sh(
                    script:  "git ls-remote --exit-code --heads origin ${params.releaseBranch}",
                    returnStatus: true
                    ) != 0) {
                        errorMessage'Release branch does not exist'
                        error 'Branch not exist'
                    }
                }
                stage('pushing tag to upstream'){
                    // Using withCredentials as gitpublish plugin is not yet ported for pipelines
                    // Defining credentialsId for default value passed from Parameter or environment value.
                    // gitCredentialId is username and password type
                    withCredentials([usernamePassword(credentialsId: "${gitCredentialId}",
                    passwordVariable: 'gitPassword', usernameVariable: 'gitUser')]) {

                        // Getting git remote url
                        origin = "https://${gitUser}:${gitPassword}@"+sh (
                        script: 'git config --get remote.origin.url',
                        returnStdout: true
                        ).trim().split('https://')[1]
                        echo "Git Hash: ${origin}"

                        /*
                         * Creating tagname
                         * Each tag should be of the naming convention `release<version>_RC<count>
                         * Count will increment as RC0 - for the first time, then RC1..n
                         */

                        tagRefBranch = sh(
                            script: "git ls-remote --tags origin ${releaseBranch}* | grep -o 'release-.*' | tail -n1",
                            returnStdout: true
                        ).trim()
                        if (tagRefBranch == ''){
                            tagName = releaseBranch+'_RC1'
                        } else {
                            // Checking whether there is any changes in the branch
                            if ( sh(
                            script: "git diff --exit-code refs/remotes/origin/$releaseBranch tags/$tagRefBranch > /dev/null",
                            returnStatus: true
                            ) == 0 ){
                                errorMessage('''
                                Same as previous branch
                                pleaseCheck''')
                                error 'No changes found from last tag'}
                            refCount = tagRefBranch.split('_RC')[-1].toInteger() + 1
                            tagName = releaseBranch + '_RC' + refCount
                        }
                        // Checks whether remtoe branch is present
                        ansiColor('xterm'){
                            // If remote tag exists
                            if( sh(script: "git ls-remote --exit-code --tags ${origin} ${tagName}", returnStatus: true) == 0 ) {
                                errorMessage("Upstream has tag with same name: ${tagName}")
                                error 'remote tag found with same name'
                            }
                        }

                        // Pushing tag
                        sh("git push ${origin} refs/remotes/origin/$releaseBranch:refs/tags/${tagName}")
                    }
                }
            }
        }
    }
    catch(org.jenkinsci.plugins.credentialsbinding.impl.CredentialNotFoundException e){
        ansiColor('xterm'){
            errorMessage '''
            Create environment variable `githubPassword` and store the `credential id`.
            '''
        }
        error 'either gitCredentialId is not set or wrong value'
    }
}
