// -------------------------------------------------------------------------------------------------
// PIPELINE DEFINITION: Full CI/CD flow for a Vue SPA, using Docker containers for isolated build steps.
// -------------------------------------------------------------------------------------------------
pipeline {
    // AGENT DIRECTIVE: Specifies where the pipeline should run.
    agent {
        // Runs on the Jenkins agent node with the label 'docker-deploy-host' (your configured Docker host).
        label 'docker-deploy-host'
    }

    // ENVIRONMENT DIRECTIVE: Defines global variables used throughout the pipeline.
    environment {
        REGISTRY_HOST = 'docker.io'                   // The target Docker registry (e.g., Docker Hub).
        DOCKER_USER = 'itwibrc'                      // Your Docker username/namespace.
        CONTAINER_CLI = 'docker'                     // Command alias for running containers.
        APP_NAME = 'vue-ci-cd-app-jenkins-nginx'     // Application name for image tagging.
        NODE_IMAGE = 'node:22-alpine'                // Base image for running Node CI tasks (lint, test, build).
        E2E_PORT = 8081                              // Host port for running the temporary E2E test server.
        PROD_PORT = 8080                             // The internal port the application container exposes (Nginx default in your Dockerfile).
        APP_EXPOSED_PORT = 8082                      // The final port the deployed production container will be exposed on (on the host).
        PROD_CONTAINER_NAME = 'vue-spa-app'          // Name of the running production container.
        FINAL_PROD_TAG = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:latest" // Full tag for the 'latest' image.
        PLAYWRIGHT_IMAGE = 'mcr.microsoft.com/playwright:v1.56.0-jammy' // Image with E2E testing tools.
        TEMP_CI_IMAGE_TAG = ""                       // Variable to hold the tag of the temporary image built during E2E.
        CI_BUILD_CONTAINER = 'node-ci-runner'        // Name for the temporary container used for CI steps.
    }

    // STAGES BLOCK: Contains the sequential steps of the CI/CD process.
    stages {
        // STAGE 1: Source Code Retrieval
        stage('PULL') {
            steps {
                script {
                    // Define the SCM (Source Control Management) for checking out code.
                    def scm = [
                        $class: 'GitSCM',
                        branches: [[name: "refs/heads/${env.BRANCH_NAME}"]],
                        userRemoteConfigs: [[url: 'https://github.com/IT-WIBRC/vue-ci-cd-app-jenkins-nginx.git']],
                        extensions: [[$class: 'CleanBeforeCheckout']] // Ensure a clean workspace before pulling.
                    ]
                    checkout(scm) // Execute the checkout step.
                    echo "Code pulled and workspace cleaned before checkout."
                }
            }
        }

        // STAGE 2: Install Dependencies and Security Audit
        stage('INIT & AUDIT') {
            // WHEN DIRECTIVE: Only execute this stage for branches matching the regex pattern.
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    echo "Starting Dependency Installation using TAR PIPE with the chown fix."

                    // Get the Jenkins agent's user ID and group ID to match permissions inside the container.
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    echo "Agent UID:GID detected as ${runUser}"

                    sh(label: 'Clean up previous node_modules', script: 'rm -rf node_modules')

                    // The Tar Pipe Technique: A high-performance and secure way to manage workspace content.
                    sh(label: 'Install Dependencies via Tar Pipe', script: """
                    ${CONTAINER_CLI} rm -f ${env.CI_BUILD_CONTAINER} || true // Clean up old container instance.

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

        // STAGE 3: Code Quality Check
        stage('LINT') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def lintContainer = 'node-lint-runner' // Unique container name for this stage.

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

        // STAGE 4: Unit Testing
        stage('TEST:UNIT') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def testContainer = 'node-test-runner' // Unique container name.

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
                    junit 'coverages/unit-tests.xml' // Publish JUnit test results.
                    archiveArtifacts artifacts: 'coverages/**/*', onlyIfSuccessful: false // Archive coverage reports on failure.
                }
            }
        }

        // STAGE 5: Application Building
        stage('BUILD') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
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

        // STAGE 6: End-to-End Testing
        stage('TEST:E2E') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    // Create a unique tag for the temporary application image.
                    env.TEMP_CI_IMAGE_TAG = "local/${env.APP_NAME}:test-${env.BUILD_NUMBER}"
                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    def e2eContainerName = 'e2e-ci-runner'

                    sh(label: 'Build Temporary E2E Runner Image', script: "${CONTAINER_CLI} build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx .")

                    sh(label: 'Clean up Previous App Server Container', script: "${CONTAINER_CLI} rm -f e2e-runner || true")
                    // Start the built application server container. Maps host port E2E_PORT to container PROD_PORT.
                    sh(label: 'Start E2E App Server Container', script: "${CONTAINER_CLI} run -d --name e2e-runner -p ${env.E2E_PORT}:${env.PROD_PORT} ${env.TEMP_CI_IMAGE_TAG}")

                    sh(label: 'Run E2E Tests', script: """
                    ${CONTAINER_CLI} rm -f ${e2eContainerName} || true

                    ${CONTAINER_CLI} run -d --name ${e2eContainerName} \\
                      --network=host \\
                      -e CI=true \\
                      -e PLAYWRIGHT_HEADLESS=1 \\
                      -w /tmp/app ${env.PLAYWRIGHT_IMAGE} sleep infinity

                    echo "Cleaning up E2E Test Runner container..."
                    ${CONTAINER_CLI} stop ${e2eContainerName} && ${CONTAINER_CLI} rm -f ${e2eContainerName}
                    """)
                }
            }
            post {
                failure {
                    // Archive E2E reports on failure for debugging.
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**, e2e-report/**' , onlyIfSuccessful: false
                }
            }
        }

        // STAGE 7: Production Deployment
        stage('DEPLOYMENT') {
            // WHEN DIRECTIVE: The final deployment only runs for the 'main' branch.
            when { branch 'main' }
            steps {
                script {
                    echo "Starting final build and production deployment..."

                    def finalReleaseTag = "${env.REGISTRY_HOST}/${env.DOCKER_USER}/${env.APP_NAME}:${env.BUILD_NUMBER}"

                    sh(label: 'Build Final Production Image', script: "${CONTAINER_CLI} build -t ${finalReleaseTag} -f Dockerfile.prod.nginx .")

                    // Use Jenkins credentials store for secure login to Docker Hub.
                    withCredentials([usernamePassword(credentialsId: 'DOCKERHUB_CREDENTIALS', usernameVariable: 'DOCKER_USER_ENV', passwordVariable: 'DOCKER_PASSWORD_ENV')]) {
                        sh(label: 'Docker Login', script: "echo ${DOCKER_PASSWORD_ENV} | ${CONTAINER_CLI} login -u ${DOCKER_USER_ENV} --password-stdin ${env.REGISTRY_HOST}")
                        sh(label: 'Push Build Number Tag', script: "${CONTAINER_CLI} push ${finalReleaseTag}")
                        sh(label: 'Tag as Latest', script: "${CONTAINER_CLI} tag ${finalReleaseTag} ${env.FINAL_PROD_TAG}")
                        sh(label: 'Push Latest Tag', script: "${CONTAINER_CLI} push ${env.FINAL_PROD_TAG}")
                        sh(label: 'Docker Logout', script: "${CONTAINER_CLI} logout ${env.REGISTRY_HOST}")
                    }

                    sh(label: 'Stop Existing Production Container', script: "${CONTAINER_CLI} stop ${env.PROD_CONTAINER_NAME} || true")
                    sh(label: 'Remove Existing Production Container', script: "${CONTAINER_CLI} rm ${env.PROD_CONTAINER_NAME} || true")

                    // Final deployment command: runs container, sets restart policy, and exposes final app port.
                    sh(label: 'Deploy New Production Container', script: """
                    ${CONTAINER_CLI} run -d \\
                      --name ${env.PROD_CONTAINER_NAME} \\
                      --restart always \\
                      -p ${env.APP_EXPOSED_PORT}:8080 \\
                      ${env.FINAL_PROD_TAG}
                    """)
                }
            }
        }

        // STAGE 8: Post-Deployment Notification
        stage('NOTIFICATION') {
            steps {
                echo "Pipeline finished for branch ${env.BRANCH_NAME}. Status: ${currentBuild.result}"
            }
        }
    }

    // POST BLOCK: Actions that run after all stages, regardless of overall pipeline status.
    post {
        always {
            script {
                echo "Running final post-build cleanup for E2E App Server and temporary images."

                sh(label: 'Capture E2E App Server Logs', script: "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt || true")
                archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false // Archive logs before removal.

                sh(label: 'Remove E2E App Server Container', script: "${CONTAINER_CLI} rm -f e2e-runner || true") // Remove the temporary app server.

                sh(label: 'Remove Temporary CI Image', script: "${CONTAINER_CLI} rmi ${env.TEMP_CI_IMAGE_TAG} || true") // Remove the temporary image.
            }
        }
    }
}
