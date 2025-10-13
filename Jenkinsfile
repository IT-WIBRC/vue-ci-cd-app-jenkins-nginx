pipeline {
    agent {
        label 'docker-deploy-host'
    }

    environment {
        DOCKER_USER = 'itwibrc'
        APP_NAME = 'vue-ci-cd-app-jenkins-nginx'
        REGISTRY_HOST = 'docker.io'
        NODE_IMAGE = 'node:20-alpine'
        CONTAINER_CLI = 'docker'
        E2E_PORT = 8081
        PROD_PORT = 8080
        PROD_CONTAINER_NAME = 'vue-spa-app'
        FINAL_PROD_TAG = "${REGISTRY_HOST}/${DOCKER_USER}/${APP_NAME}:latest"
        TEMP_CI_IMAGE_TAG = ''
        PLAYWRIGHT_IMAGE = 'mcr.microsoft.com/playwright:v1.56.0-jammy'
    }

    stages {
        stage('PULL') {
            steps {
                git branch: env.BRANCH_NAME,
                url: 'https://github.com/IT-WIBRC/vue-ci-cd-app-jenkins-nginx.git'
            }
        }

        stage('INIT & AUDIT') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} sh -c 'npm ci && npm audit --production || true'"
            }
        }

        stage('LINT') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} npm run lint"
            }
        }

        stage('TEST:UNIT') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} npm run test:ci"
            }
            post {
                failure {
                    junit 'coverages/unit-tests.xml'
                    archiveArtifacts artifacts: 'coverages/**/*', onlyIfSuccessful: false
                }
            }
        }

        stage('BUILD') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} npm run build"
            }
        }

        stage('TEST:E2E') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                script {
                    env.TEMP_CI_IMAGE_TAG = "local/${env.APP_NAME}:test-${env.BUILD_NUMBER}"

                    sh "${CONTAINER_CLI} build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx ."

                    sh "${CONTAINER_CLI} run -d --name e2e-runner -p ${env.E2E_PORT}:${env.PROD_PORT} ${env.TEMP_CI_IMAGE_TAG}"

                    sh """
                    ${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app \
                    --network=host \
                    ${env.PLAYWRIGHT_IMAGE} \
                    npm run test:e2e:ci
                    """
                }
            }
            post {
                always {
                    sh "${CONTAINER_CLI} rm -f e2e-runner || true"
                }
                failure {
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**, e2e-report/**' , onlyIfSuccessful: false
                    sh "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt"
                    archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false
                }
            }
        }

        stage('CLEANUP CI') {
            when { anyOf { branch 'develop'; branch 'main'; changeRequest target: 'develop' } }
            steps {
                sh "${CONTAINER_CLI} rm -f e2e-runner || true"
                sh "${CONTAINER_CLI} rmi ${env.TEMP_CI_IMAGE_TAG} || true"
            }
        }

        stage('DEPLOYMENT') {
            when { branch 'main' }
            steps {
                script {
                    echo "Starting final build and production deployment..."

                    def finalReleaseTag = "${env.REGISTRY_HOST}/${env.DOCKER_USER}/${env.APP_NAME}:${env.BUILD_NUMBER}"

                    sh "${CONTAINER_CLI} build -t ${finalReleaseTag} -f Dockerfile.prod.nginx ."
                    sh "${CONTAINER_CLI} push ${finalReleaseTag}"
                    sh "${CONTAINER_CLI} tag ${finalReleaseTag} ${env.FINAL_PROD_TAG}"
                    sh "${CONTAINER_CLI} push ${env.FINAL_PROD_TAG}"

                    sh "${CONTAINER_CLI} stop ${env.PROD_CONTAINER_NAME} || true"
                    sh "${CONTAINER_CLI} rm ${env.PROD_CONTAINER_NAME} || true"

                    sh """
                    ${CONTAINER_CLI} run -d \
                      --name ${env.PROD_CONTAINER_NAME} \
                      --restart always \
                      -p 80:8080 \
                      ${env.FINAL_PROD_TAG}
                    """
                }
            }
        }

        stage('NOTIFICATION') {
            steps {
                echo "Pipeline finished for branch ${env.BRANCH_NAME}. Status: ${currentBuild.result}"
            }
        }
    }
}
