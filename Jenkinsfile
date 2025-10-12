pipeline {
    when {
        anyOf {
            branch 'develop'
            branch 'main'
            changeRequest target: 'develop'
        }
    }

    agent {
        label 'podman-deploy-host'
    }

    environment {
        // --- Configuration ---
        DOCKER_USER = 'mydevuser'
        APP_NAME = 'vue-ci-cd-app-jenkins-nginx'
        REGISTRY_HOST = 'docker.io'

        // --- Ports and Names ---
        E2E_PORT = 8081
        PROD_PORT = 8080
        PROD_CONTAINER_NAME = 'vue-spa-app'

        // --- Final Tag (used only in Deployment) ---
        FINAL_PROD_TAG = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:latest"

        // CI Tag is now temporary, only used for E2E testing
        TEMP_CI_IMAGE_TAG = ''
    }

    // ---------------------------------------------------------------- //
    // Helper Variables (Replaced repeated when/agent blocks)
    // ---------------------------------------------------------------- //
    def nodeCiAgent = [
        docker: [
            image: 'node:20-alpine',
        ]
    ]

    def ciWhenCondition = {
        when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
    }


    stages {
        // --- 1. PULL ---
        stage('PULL') {
            steps {
                git branch: env.BRANCH_NAME,
                url: 'https://github.com/IT-WIBRC/vue-ci-cd-app-jenkins-nginx.git'
            }
        }

        // --- 2. INIT & AUDIT ---
        stage('INIT & AUDIT') {
            agent nodeCiAgent
            options { ciWhenCondition() }
            steps {
                sh 'npm ci'
                sh 'npm audit --production || true'
            }
        }

        // --- 3. LINT ---
        stage('LINT') {
            agent nodeCiAgent
            options { ciWhenCondition() }
            steps {
                sh 'npm run lint'
            }
        }

        // 4. TEST:UNIT
        stage('TEST:UNIT') {
            agent nodeCiAgent
            options { ciWhenCondition() }
            steps {
                sh 'npm run test:ci'
            }
            post {
                failure {
                    // Use the junit step to publish JUnit XML reports, which Jenkins parses for failure details.
                    junit 'coverages/unit-tests.xml'

                    // Archive the raw report folder if needed
                    archiveArtifacts artifacts: 'coverages/**/*', onlyIfSuccessful: false
                }
            }
        }

        // --- 5. BUILD ---
        stage('BUILD') {
            agent nodeCiAgent
            options { ciWhenCondition() }
            steps {
                sh 'npm run build'
            }
        }

       // --- 6. TEST:E2E (Builds LOCALLY, Tests, and DISCARDS) ---
        stage('TEST:E2E') {
            agent {
                docker {
                    image 'mcr.microsoft.com/playwright:v1.45.0-jammy'
                    // Mount Podman socket for local container build/run
                    args '-u root -v /var/run/podman/podman.sock:/var/run/podman/podman.sock'
                }
            }
            options { ciWhenCondition() }
            steps {
                script {
                    // Create a temporary, local tag for testing
                    env.TEMP_CI_IMAGE_TAG = "local/${APP_NAME}:test-${BUILD_NUMBER}"

                    // BUILD LOCALLY - Note: NO 'podman push' here
                    sh "podman build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx ."

                    // Run the temporary container for E2E testing
                    sh "podman run -d --name e2e-runner -p ${E2E_PORT}:${PROD_PORT} ${env.TEMP_CI_IMAGE_TAG}"
                }

                // Execute Playwright tests
                sh 'npm run test:e2e'
            }
            post {
                always {
                    // Clean up the application container even if tests fail
                    sh 'podman rm -f e2e-runner || true'
                }
                failure {
                    // Archive Playwright artifacts like screenshots, videos, and trace files.
                    // Adjust the paths ('playwright-report/', 'test-results/') based on your actual Playwright config.
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**, e2e-report/**' , onlyIfSuccessful: false

                    // You might also want to log the container output if it crashed, using a step like:
                    sh "podman logs e2e-runner > e2e-runner-logs.txt"
                    archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false
                }
            }
        }

        // --- 7. CLEANUP CI (Runs on default 'podman-deploy-host') ---
        stage('CLEANUP CI') {
            options { ciWhenCondition() }
            steps {
                // Remove the E2E runner and the temporary local image to save disk space
                sh 'podman rm -f e2e-runner || true'
                sh "podman rmi ${env.TEMP_CI_IMAGE_TAG} || true"
            }
        }
        // --- 8. DEPLOYMENT (Only on main branch) ---
        stage('DEPLOYMENT') {
            when { branch 'main' }
            steps {
                script {
                    echo "Starting final build and production deployment..."

                    // 1. FINAL BUILD & PUSH (Only happens on main, only if all previous stages passed)
                    // The build number acts as the permanent tag for the release
                    def finalReleaseTag = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:${BUILD_NUMBER}"

                    sh "podman build -t ${finalReleaseTag} -f Dockerfile.prod.nginx ."
                    sh "podman push ${finalReleaseTag}" // Push the permanent image

                    // 2. Tag the final image as :latest for atomic deployment
                    sh "podman tag ${finalReleaseTag} ${env.FINAL_PROD_TAG}"
                    sh "podman push ${env.FINAL_PROD_TAG}" // Push the :latest tag

                    // 3. Deployment logic
                    sh "podman stop ${PROD_CONTAINER_NAME} || true"
                    sh "podman rm ${PROD_CONTAINER_NAME} || true"

                    // Secret handling
                    sh 'podman secret rm prod_app_ssl_key prod_app_ssl_cert || true'
                    sh 'podman secret create prod_app_ssl_key /path/to/ssl/key'
                    sh 'podman secret create prod_app_ssl_cert /path/to/ssl/cert'

                    // 4. Deploy the new service
                    sh """
                    podman run -d \
                      --name ${PROD_CONTAINER_NAME} \
                      --restart always \
                      -p 80:8080 \
                      --secret prod_app_ssl_key \
                      --secret prod_app_ssl_cert \
                      ${env.FINAL_PROD_TAG}
                    """
                }
            }
        }

        // --- 9. NOTIFICATION ---
        stage('NOTIFICATION') {
            steps {
                echo "Pipeline finished for branch ${env.BRANCH_NAME}. Status: ${currentBuild.result}"
            }
        }
    }
}

// Helper function
@NonCPS
def isPR() {
    return env.CHANGE_ID != null && env.CHANGE_ID.isInteger()
}
