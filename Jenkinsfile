pipeline {
    agent {
        label 'docker-deploy-host'
    }

    environment {
        REGISTRY_HOST = 'docker.io'
        DOCKER_USER = 'itwibrc'
        CONTAINER_CLI = 'docker'
        APP_NAME = 'vue-ci-cd-app-jenkins-nginx'
        NODE_IMAGE = 'node:22-alpine'
        E2E_PORT = 8081
        PROD_PORT = 8080
        PROD_CONTAINER_NAME = 'vue-spa-app'
        FINAL_PROD_TAG = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:latest"
        PLAYWRIGHT_IMAGE = 'mcr.microsoft.com/playwright:v1.56.0-jammy'
        TEMP_CI_IMAGE_TAG = ""
        CI_BUILD_CONTAINER = 'node-ci-runner'
    }

    stages {
        stage('PULL') {
            steps {
                script {
                    def scm = [
                        $class: 'GitSCM',
                        branches: [[name: "refs/heads/${env.BRANCH_NAME}"]],
                        userRemoteConfigs: [[url: 'https://github.com/IT-WIBRC/vue-ci-cd-app-jenkins-nginx.git']],
                        extensions: [[$class: 'CleanBeforeCheckout']]
                    ]
                    checkout(scm)
                    echo "Code pulled and workspace cleaned before checkout."
                }
            }
        }

        stage('INIT & AUDIT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    echo "Starting Dependency Installation using TAR PIPE with the chown fix."

                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    echo "Agent UID:GID detected as ${runUser}"

                    sh(label: 'Clean up previous node_modules', script: 'rm -rf node_modules')

                    sh(label: 'Install Dependencies via Tar Pipe', script: """
                    ${CONTAINER_CLI} rm -f ${env.CI_BUILD_CONTAINER} || true

                    ${CONTAINER_CLI} run -d --name ${env.CI_BUILD_CONTAINER} -w /tmp/app ${env.NODE_IMAGE} sleep infinity

                    echo "Copying workspace content into container via tar pipe..."
                    tar -cf - --exclude=node_modules . | ${CONTAINER_CLI} cp - ${env.CI_BUILD_CONTAINER}:/tmp/app/

                    echo "Fixing permissions inside container..."
                    ${CONTAINER_CLI} exec ${env.CI_BUILD_CONTAINER} /bin/sh -c "chown -R ${runUser} /tmp/app"

                    echo "Running npm ci and audit inside container as ${runUser}..."
                    ${CONTAINER_CLI} exec -u ${runUser} -w /tmp/app ${env.CI_BUILD_CONTAINER} /bin/sh -c '
                        npm ci || exit 1
                        npm audit --production || true
                    '

                    echo "Copying node_modules back to workspace..."
                    ${CONTAINER_CLI} cp ${env.CI_BUILD_CONTAINER}:/tmp/app/node_modules .

                    echo "Cleaning up runner container..."
                    ${CONTAINER_CLI} stop ${env.CI_BUILD_CONTAINER} && ${CONTAINER_CLI} rm -f ${env.CI_BUILD_CONTAINER}
                    """)

                    echo "INIT & AUDIT complete. Dependencies are now available in the Jenkins workspace."
                }
            }
        }

        stage('LINT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def lintContainer = 'node-lint-runner'

                    sh(label: 'Run Code Linting', script: """
                    ${CONTAINER_CLI} rm -f ${lintContainer} || true
                    ${CONTAINER_CLI} run -d --name ${lintContainer} -w /tmp/app ${env.NODE_IMAGE} sleep infinity

                    echo "Copying workspace into LINT container..."
                    tar -cf - . | ${CONTAINER_CLI} cp - ${lintContainer}:/tmp/app/

                    ${CONTAINER_CLI} exec ${lintContainer} /bin/sh -c "chown -R ${runUser} /tmp/app"

                    echo "Executing npm run lint..."
                    ${CONTAINER_CLI} exec -u ${runUser} -w /tmp/app ${lintContainer} /bin/sh -c '
                        npm run lint
                    '

                    echo "Cleaning up LINT container..."
                    ${CONTAINER_CLI} stop ${lintContainer} && ${CONTAINER_CLI} rm -f ${lintContainer}
                    """)
                }
            }
        }

        stage('TEST:UNIT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def testContainer = 'node-test-runner'

                    sh(label: 'Run Unit Tests', script: """
                    ${CONTAINER_CLI} rm -f ${testContainer} || true
                    ${CONTAINER_CLI} run -d --name ${testContainer} -w /tmp/app ${env.NODE_IMAGE} sleep infinity

                    echo "Copying workspace into TEST container..."
                    tar -cf - . | ${CONTAINER_CLI} cp - ${testContainer}:/tmp/app/

                    ${CONTAINER_CLI} exec ${testContainer} /bin/sh -c "chown -R ${runUser} /tmp/app"

                    echo "Executing npm run test:ci..."
                    ${CONTAINER_CLI} exec -u ${runUser} -w /tmp/app ${testContainer} /bin/sh -c '
                        npm run test:ci
                    '

                    echo "Cleaning up TEST container..."
                    ${CONTAINER_CLI} stop ${testContainer} && ${CONTAINER_CLI} rm -f ${testContainer}
                    """)
                }
            }
            post {
                failure {
                    junit 'coverages/unit-tests.xml'
                    archiveArtifacts artifacts: 'coverages/**/*', onlyIfSuccessful: false
                }
            }
        }

        stage('BUILD') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def buildContainer = 'node-build-runner'

                    sh(label: 'Build App', script: """
                    ${CONTAINER_CLI} rm -f ${buildContainer} || true
                    ${CONTAINER_CLI} run -d --name ${buildContainer} -w /tmp/app ${env.NODE_IMAGE} sleep infinity

                    echo "Copying workspace into BUILD container..."
                    tar -cf - . | ${CONTAINER_CLI} cp - ${buildContainer}:/tmp/app/

                    ${CONTAINER_CLI} exec ${buildContainer} /bin/sh -c "chown -R ${runUser} /tmp/app"

                    echo "Executing npm run build..."
                    ${CONTAINER_CLI} exec -u ${runUser} -w /tmp/app ${buildContainer} /bin/sh -c '
                        npm run build
                    '

                    echo "Copying build artifacts (dist) back to workspace..."
                    ${CONTAINER_CLI} cp ${buildContainer}:/tmp/app/dist .

                    echo "Cleaning up BUILD container..."
                    ${CONTAINER_CLI} stop ${buildContainer} && ${CONTAINER_CLI} rm -f ${buildContainer}
                    """)
                    echo "Build artifacts available in the workspace (dist/)."
                }
            }
        }

        stage('TEST:E2E') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    env.TEMP_CI_IMAGE_TAG = "local/${env.APP_NAME}:test-${env.BUILD_NUMBER}"
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def e2eContainerName = 'e2e-ci-runner'

                    sh(label: 'Build Temporary E2E Runner Image', script: "${CONTAINER_CLI} build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx .")

                    sh(label: 'Clean up Previous App Server Container', script: "${CONTAINER_CLI} rm -f e2e-runner || true")
                    sh(label: 'Start E2E App Server Container', script: "${CONTAINER_CLI} run -d --name e2e-runner -p ${env.E2E_PORT}:${env.PROD_PORT} ${env.TEMP_CI_IMAGE_TAG}")

                    sh(label: 'Run E2E Tests', script: """
                    ${CONTAINER_CLI} rm -f ${e2eContainerName} || true

                    ${CONTAINER_CLI} run -d --name ${e2eContainerName} \\
                      --network=host \\
                      -e CI=true \\
                      -e PLAYWRIGHT_HEADLESS=1 \\
                      -w /tmp/app ${env.PLAYWRIGHT_IMAGE} sleep infinity

                    echo "Copying workspace into E2E container..."
                    tar -cf - . | ${CONTAINER_CLI} cp - ${e2eContainerName}:/tmp/app/

                    ${CONTAINER_CLI} exec ${e2eContainerName} /bin/sh -c "chown -R ${runUser} /tmp/app"

                    echo "Executing npm run test:e2e:ci..."
                    ${CONTAINER_CLI} exec -u ${runUser} -w /tmp/app ${e2eContainerName} /bin/sh -c '
                          npm run test:e2e:ci
                      '

                    echo "Copying E2E reports back to workspace..."
                    ${CONTAINER_CLI} cp ${e2eContainerName}:/tmp/app/playwright-report . || true
                    ${CONTAINER_CLI} cp ${e2eContainerName}:/tmp/app/test-results . || true
                    ${CONTAINER_CLI} cp ${e2eContainerName}:/tmp/app/e2e-report . || true

                    echo "Cleaning up E2E Test Runner container..."
                    ${CONTAINER_CLI} stop ${e2eContainerName} && ${CONTAINER_CLI} rm -f ${e2eContainerName}
                    """)
                }
            }
            post {
                failure {
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**, e2e-report/**' , onlyIfSuccessful: false
                }
            }
        }

        stage('DEPLOYMENT') {
            when { branch 'main' }
            steps {
                script {
                    echo "Starting final build and production deployment..."

                    def finalReleaseTag = "${env.REGISTRY_HOST}/${env.DOCKER_USER}/${env.APP_NAME}:${env.BUILD_NUMBER}"

                    sh(label: 'Build Final Production Image', script: "${CONTAINER_CLI} build -t ${finalReleaseTag} -f Dockerfile.prod.nginx .")

                    withCredentials([usernamePassword(credentialsId: 'DOCKERHUB_CREDENTIALS', usernameVariable: 'DOCKER_USER_ENV', passwordVariable: 'DOCKER_PASSWORD_ENV')]) {
                        sh(label: 'Docker Login', script: "echo ${DOCKER_PASSWORD_ENV} | ${CONTAINER_CLI} login -u ${DOCKER_USER_ENV} --password-stdin ${env.REGISTRY_HOST}")
                        sh(label: 'Push Build Number Tag', script: "${CONTAINER_CLI} push ${finalReleaseTag}")
                        sh(label: 'Tag as Latest', script: "${CONTAINER_CLI} tag ${finalReleaseTag} ${env.FINAL_PROD_TAG}")
                        sh(label: 'Push Latest Tag', script: "${CONTAINER_CLI} push ${env.FINAL_PROD_TAG}")
                        sh(label: 'Docker Logout', script: "${CONTAINER_CLI} logout ${env.REGISTRY_HOST}")
                    }

                    sh(label: 'Stop Existing Production Container', script: "${CONTAINER_CLI} stop ${env.PROD_CONTAINER_NAME} || true")
                    sh(label: 'Remove Existing Production Container', script: "${CONTAINER_CLI} rm ${env.PROD_CONTAINER_NAME} || true")

                    sh(label: 'Deploy New Production Container', script: """
                    ${CONTAINER_CLI} run -d \\
                      --name ${env.PROD_CONTAINER_NAME} \\
                      --restart always \\
                      -p 80:8080 \\
                      ${env.FINAL_PROD_TAG}
                    """)
                }
            }
        }

        stage('NOTIFICATION') {
            steps {
                echo "Pipeline finished for branch ${env.BRANCH_NAME}. Status: ${currentBuild.result}"
            }
        }
    }

    post {
        always {
            script {
                echo "Running final post-build cleanup for E2E App Server and temporary images."

                sh(label: 'Capture E2E App Server Logs', script: "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt || true")
                archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false

                sh(label: 'Remove E2E App Server Container', script: "${CONTAINER_CLI} rm -f e2e-runner || true")

                sh(label: 'Remove Temporary CI Image', script: "${CONTAINER_CLI} rmi ${env.TEMP_CI_IMAGE_TAG} || true")
            }
        }
    }
}
