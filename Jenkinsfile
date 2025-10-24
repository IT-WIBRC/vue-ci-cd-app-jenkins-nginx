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
    }

    stages {
        stage('PULL') {
            steps {
                git branch: env.BRANCH_NAME,
                url: 'https://github.com/IT-WIBRC/vue-ci-cd-app-jenkins-nginx.git'
            }
        }

        stage('INIT & AUDIT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                // DNS REMOVED
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} rm -rf node_modules"

                // DNS REMOVED
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} sh -c \"npm ci && npm audit --production || true\""
            }
        }

        stage('LINT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} npm run lint"
            }
        }

        stage('TEST:UNIT') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
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
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                sh "${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app ${env.NODE_IMAGE} npm run build"
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

                    sh "${CONTAINER_CLI} build -t ${env.TEMP_CI_IMAGE_TAG} -f Dockerfile.prod.nginx ."

                    sh "${CONTAINER_CLI} rm -f e2e-runner || true"

                    sh "${CONTAINER_CLI} run -d --name e2e-runner -p ${env.E2E_PORT}:${env.PROD_PORT} ${env.TEMP_CI_IMAGE_TAG}"

                    sh """
                    ${CONTAINER_CLI} run --rm -v \$(pwd):/app -w /app \\
                    --network=host \\
                    -e CI=true \\
                    -e PLAYWRIGHT_HEADLESS=1 \\
                    ${env.PLAYWRIGHT_IMAGE} \\
                    npm run test:e2e:ci
                    """
                }
            }
            post {
                failure {
                    archiveArtifacts artifacts: 'playwright-report/**, test-results/**, e2e-report/**' , onlyIfSuccessful: false
                }
            }
        }

        stage('CLEANUP CI') {
            when {
                expression {
                    return env.BRANCH_NAME.matches('''^(main|develop|fix[-/].*|release[-/].*|refactor[-/].*|feat[-/].*|chore[-/].*|ci[-/].*|build[-/].*|perf[-/].*|docs[-/].*|style[-/].*|test[-/].*|revert[-/].*)$''')
                }
            }
            steps {
                sh "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt || true"
                archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false

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
                    ${CONTAINER_CLI} run -d \\
                      --name ${env.PROD_CONTAINER_NAME} \\
                      --restart always \\
                      -p 80:8080 \\
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

    post {
        always {
            script {
                if (env.BRANCH_NAME != 'main') {
                    sh "${CONTAINER_CLI} logs e2e-runner > e2e-runner-logs.txt || true"
                    archiveArtifacts artifacts: 'e2e-runner-logs.txt', onlyIfSuccessful: false

                    sh "${CONTAINER_CLI} rm -f e2e-runner || true"
                    sh "${CONTAINER_CLI} rmi ${env.TEMP_CI_IMAGE_TAG} || true"
                }
            }
        }
    }
}
