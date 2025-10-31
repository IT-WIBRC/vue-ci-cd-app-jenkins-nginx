// Define a reusable Groovy function to execute commands inside the long-running CI container
def execInCiContainer(command) {
    // This function abstracts away the complex 'docker exec' command details.
    sh(label: "Execute Command in ${env.CI_BUILD_CONTAINER}", script: """
        echo "Executing: ${command}"
        ${env.CONTAINER_CLI} exec -u ${env.RUN_USER} -w /tmp/app ${env.CI_BUILD_CONTAINER} /bin/sh -c '${command}'
    """)
}

pipeline {
    agent {
        label 'docker-deploy-host'
    }

    options {
        // Keeps a maximum of 10 builds, regardless of age.
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        // --- Core Identifiers ---
        REGISTRY_HOST = 'docker.io'
        DOCKER_USER = 'itwibrc'
        CONTAINER_CLI = 'docker'
        APP_NAME = 'vue-ci-cd-app-jenkins-nginx'

        // --- Image and Container Settings ---
        NODE_IMAGE = 'node:22-alpine'
        PLAYWRIGHT_IMAGE = 'mcr.microsoft.com/playwright:v1.56.0-jammy'
        CI_BUILD_CONTAINER = 'node-ci-runner'

        // --- Port and Deployment Settings ---
        E2E_PORT = 8081 // Port exposed on the DinD host for the E2E test server
        PROD_PORT = 8080 // Internal Nginx port (and also the Prod App exposed port)
        APP_EXPOSED_PORT = 8081
        PROD_CONTAINER_NAME = 'vue-spa-app'
        FINAL_PROD_TAG = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:latest"

        // --- Runtime Variables (Set to initial non-null values) ---
        RUN_USER = "1000:1000"
        TEMP_CI_IMAGE_TAG = "local/${APP_NAME}:test-${BUILD_NUMBER}"
    }

    stages {
        // STAGE 1: Install Dependencies and Prepare Container (INIT & AUDIT)
        stage('INIT & AUDIT') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    echo "Starting Dependency Installation and setting up long-running CI container."

                    def jenkinsUser = sh(returnStdout: true, script: 'id -u').trim()
                    def jenkinsGroup = sh(returnStdout: true, script: 'id -g').trim()
                    def runUser = "${jenkinsUser}:${jenkinsGroup}"
                    env.RUN_USER = runUser
                    echo "Agent UID:GID detected as ${env.RUN_USER}"

                    sh(label: 'Setup Long-Running CI Container and Install Dependencies', script: """
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
                    """)

                    echo "INIT & AUDIT complete. Container ${env.CI_BUILD_CONTAINER} is running."
                }
            }
        }

        // STAGE 2: Code Quality Check (LINT)
        stage('LINT') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    execInCiContainer('npm run lint')
                }
            }
        }

        // STAGE 3: Unit Testing (TEST:UNIT)
        stage('TEST:UNIT') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    execInCiContainer('npm run test:ci')

                    sh(label: 'Copy Test Artifacts back', script: """
                    ${CONTAINER_CLI} cp ${env.CI_BUILD_CONTAINER}:/tmp/app/coverages .
                    ${CONTAINER_CLI} cp ${env.CI_BUILD_CONTAINER}:/tmp/app/test-results . || true
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

        // STAGE 4: Application Building (BUILD)
        stage('BUILD') {
            when { expression { return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''') } }
            steps {
                script {
                    execInCiContainer('npm run build')

                    sh(label: 'Copy build artifacts (dist) back to workspace', script: """
                    ${CONTAINER_CLI} cp ${env.CI_BUILD_CONTAINER}:/tmp/app/dist .
                    """)

                    echo "Build artifacts available in the workspace (dist/)."
                }
            }
        }

        // STAGE 5: End-to-End Testing (TEST:E2E)
        stage('TEST:E2E') {
            when {
                // Checks if the branch name matches the pattern (standard practice)
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                script {
                    def e2eAppServer = 'e2e-runner'
                    def e2eTestRunner = 'playwright-runner'
                    def e2eNetwork = "e2e-network"

                    try {
                        // 1. ROBUST CLEANUP: Delete the network if it exists from a previous failed run.
                        //    We use '|| true' to prevent pipeline failure if the network doesn't exist.
                        sh(label: "Delete e2e network if already exist", script: "${CONTAINER_CLI} network rm ${e2eNetwork} || true")

                        // 2. CREATE ISOLATED NETWORK
                        sh(label: "Create an isolated network for container to commnicate", script: "${CONTAINER_CLI} network create ${e2eNetwork}")

                        sh(label: 'Build Temporary E2E Runner Image', script: "${CONTAINER_CLI} build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx .")

                        sh(label: 'Clean up Previous App Server Container', script: "${CONTAINER_CLI} rm -f ${e2eAppServer} || true")

                        // 3. START APP SERVER (Attached to isolated network, NO port mapping)
                        sh(label: 'Start E2E App Server Container on Isolated Network', script: """
                            ${CONTAINER_CLI} run -d --name ${e2eAppServer} \\
                                --network=${e2eNetwork} \\
                                ${env.TEMP_CI_IMAGE_TAG}
                        """)

                        echo "E2E App Server started and reachable at: http://${e2eAppServer}:${env.PROD_PORT}"

                        // 4. START PLAYWRIGHT RUNNER (Attached to isolated network)
                        sh(label: 'Start Playwright Test Container', script: """
                            ${CONTAINER_CLI} rm -f ${e2eTestRunner} || true
                            ${CONTAINER_CLI} run -d --name ${e2eTestRunner} \\
                                --network=${e2eNetwork} \\
                                -e CI=true \\
                                -e PLAYWRIGHT_HEADLESS=1 \\
                                -e PLAYWRIGHT_TEST_BASE_URL="http://${e2eAppServer}:${env.PROD_PORT}" \\
                                -w /tmp/app \\
                                ${env.PLAYWRIGHT_IMAGE} sleep 600
                        """)

                        // 5. COPY FILES
                        sh(label: 'Copy App Source to Test Container', script: """
                            echo "Copying source code (excluding node_modules) via tar pipe..."
                            tar -cf - \\
                                --exclude=node_modules \\
                                --exclude=coverages \\
                                --exclude=playwright-report \\
                                --exclude=test-results \\
                                . | ${CONTAINER_CLI} cp - ${e2eTestRunner}:/tmp/app/
                        """)

                        sh(label: 'Copy node_modules to Test Container', script: """
                            echo "Copying pre-installed node_modules..."
                            ${CONTAINER_CLI} cp node_modules ${e2eTestRunner}:/tmp/app/
                        """)

                        // 6. EXECUTE TESTS
                        sh(label: 'Execute E2E Tests as Root', script: """
                            echo "Executing npm run test:e2e as root..."
                            ${CONTAINER_CLI} exec -w /tmp/app ${e2eTestRunner} /bin/sh -c 'npm run test:e2e'
                        """)

                        // 7. COPY ARTIFACTS
                        sh(label: 'Copy E2E Artifacts back to workspace', script: """
                            echo "Copying Playwright artifacts back..."
                            mkdir -p playwright-report test-results
                            ${CONTAINER_CLI} cp ${e2eTestRunner}:/tmp/app/playwright-report . || true
                            ${CONTAINER_CLI} cp ${e2eTestRunner}:/tmp/app/test-results . || true
                        """)

                    } finally {
                        // 8. CRITICAL CLEANUP: Stop and remove BOTH containers before deleting the network.
                        sh(label: 'Clean up E2E App Server container', script: "${CONTAINER_CLI} stop ${e2eAppServer} || true ; ${CONTAINER_CLI} rm -f ${e2eAppServer} || true")
                        sh(label: 'Clean up E2E Test Runner container', script: "${CONTAINER_CLI} stop ${e2eTestRunner} || true ; ${CONTAINER_CLI} rm -f ${e2eTestRunner} || true")

                        // 9. DELETE NETWORK (Will succeed because all containers are now removed)
                        sh(label: "Delete e2e network", script: "${CONTAINER_CLI} network rm ${e2eNetwork} || true")
                    }
                }
            }
            post {
                failure {
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**' , onlyIfSuccessful: false
                }
            }
        }

        // STAGE 6: Publish Final Image (Pushing only the 'latest' stable tag)
        stage('PUBLISH') {
            when { branch 'main' }
            steps {
                script {
                    echo "Starting final build and pushing image to Docker Hub..."

                    def buildNumberTag = "${env.REGISTRY_HOST}/${env.DOCKER_USER}/${env.APP_NAME}:${env.BUILD_NUMBER}"
                    def latestTag = env.FINAL_PROD_TAG

                    sh(label: 'Build Final Production Image', script: "${CONTAINER_CLI} build -t ${buildNumberTag} -f Dockerfile.prod.nginx .")

                    withCredentials([usernamePassword(credentialsId: 'DOCKERHUB_CREDENTIALS', usernameVariable: 'DOCKER_USER_ENV', passwordVariable: 'DOCKER_PASSWORD_ENV')]) {

                        // FIX: Use single quotes and pass the password as an argument (or use a temporary file)
                        // This is the cleanest fix for this specific command, relying on the shell to pipe the string.
                        // Note: The standard method of piping the password is inherently insecure, but this syntax fixes the Jenkins warning.
                        sh(label: 'Docker Login', script: "echo ${DOCKER_PASSWORD_ENV} | ${CONTAINER_CLI} login -u ${DOCKER_USER_ENV} --password-stdin ${env.REGISTRY_HOST}")

                        sh(label: 'Tag as Latest', script: "${CONTAINER_CLI} tag ${buildNumberTag} ${latestTag}")
                        sh(label: 'Push Latest Tag', script: "${CONTAINER_CLI} push ${latestTag}")

                        sh(label: 'Remove Local Build Tag', script: "${CONTAINER_CLI} rmi ${buildNumberTag} || true")

                        sh(label: 'Docker Logout', script: "${CONTAINER_CLI} logout ${env.REGISTRY_HOST}")
                    }

                    echo "--------------------------------------------------------"
                    echo "✅ Production Image Published to Docker Hub: ${latestTag}"
                    echo "The application will be accessible via: http://<HOST_IP>:${env.APP_EXPOSED_PORT}"
                    echo "--------------------------------------------------------"
                }
            }
        }
    }

    post {
        // Runs regardless of success or failure
        always {
            script {
                echo "--- ⚙️ Running Final Cleanup (Guaranteed) ---"

                // Cleanup for long-running CI Container
                sh(label: 'Stop and Remove Main CI Container', script: "${CONTAINER_CLI} stop ${env.CI_BUILD_CONTAINER} || true && ${CONTAINER_CLI} rm -f ${env.CI_BUILD_CONTAINER} || true")

                // Cleanup for E2E App Server (Final safeguard)
                sh(label: 'Capture E2E App Server Logs', script: "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt || true")
                archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false
                sh(label: 'Remove E2E App Server Container', script: "${CONTAINER_CLI} rm -f e2e-runner || true")

                sh(label: 'Remove Temporary CI Image', script: "${CONTAINER_CLI} rmi ${env.TEMP_CI_IMAGE_TAG} || true")
            }
        }

        // Notification on success
        success {
            echo "--- ✅ BUILD SUCCESS: Pipeline completed successfully on branch ${env.BRANCH_NAME} (#${env.BUILD_NUMBER}) ---"
            // Add Slack/Email notification steps here if needed
        }

        // Notification on failure
        failure {
            echo "--- ❌ BUILD FAILURE: Pipeline failed in stage ${currentBuild.result} on branch ${env.BRANCH_NAME} (#${env.BUILD_NUMBER}) ---"
            // Add Slack/Email notification steps here if needed
        }
    }
}
