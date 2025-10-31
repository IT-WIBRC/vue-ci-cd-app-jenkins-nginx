# 🚀 Secure CI/CD and Monitoring Platform (Jenkins + DinD + Prometheus/Grafana)

This repository provides a robust, production-ready CI/CD and M-Stack environment using Docker Compose. The architecture is designed for **security, isolation, and scalability**.

## 💾 Project Overview & Files

| File                         | Description                                                                                                                                                 |
| :--------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`docker-compose.yml`**     | Defines all **7 services**: Jenkins Controller/Agent, Isolated Docker Daemon (DinD), Application (`app-prod`), Prometheus, Grafana, and the Nginx Exporter. |
| **`Dockerfile.agent`**       | Custom build file for the Jenkins Agent, installing the necessary **Docker CLI** for DinD communication.                                                    |
| **`.env`**                   | Stores sensitive environment variables (Jenkins secrets, registry credentials, Grafana login).                                                              |
| **`prometheus.yml`**         | Prometheus configuration, defining scrape jobs for **Prometheus, Jenkins, and the Nginx Exporter**.                                                         |
| **`Dockerfile.nginx-vts`**   | **[Custom Base Image]** Builds the reusable `itwibrc/nginx-vts:latest` image with the **Vhost Traffic Status (VTS)** module for monitoring.                 |
| **`nginx-vts-main.conf`**    | The **Master Nginx Configuration** (used in `Dockerfile.nginx-vts`) that activates the VTS monitoring zone and performs critical binary path overrides.     |
| **`nginx-vts-metrics.conf`** | **VTS Metrics Endpoint:** Defines a separate server block listening on port `7777` with the `/metrics` path, serving VTS data in the **Prometheus format**. |
| **`default.conf`**           | The **Application Nginx Server Block** (SPA configuration) that defines listening port `8080` and the client-side routing logic (`try_files`).              |
| **`Dockerfile.prod.nginx`**  | The **Application Dockerfile** that starts `FROM itwibrc/nginx-vts:latest` and copies the final application assets and `default.conf`.                      |

---

# PART I: ⚙️ INFRASTRUCTURE SETUP (The Platform)

This section focuses on establishing the permanent, self-healing **Jenkins Platform** and **Monitoring Stack**.

## 🛑 PREREQUISITES

1.  **Docker Engine:** Must be installed and running on the host machine.
2.  **Custom Images:**

| Action                                 | Command                                                              | Purpose                                                                            |
| :------------------------------------- | :------------------------------------------------------------------- | :--------------------------------------------------------------------------------- |
| **Option 1: Use Pre-built Nginx Base** | `docker pull itwibrc/nginx-vts:latest`                               | **RECOMMENDED:** Pulls the reusable Nginx binary with VTS support from Docker Hub. |
| **Option 2: Build Nginx Base**         | `docker build -t itwibrc/nginx-vts:latest -f Dockerfile.nginx-vts .` | Builds the Nginx VTS base image locally (required for customization).              |
| **Push Nginx Base**                    | `docker push itwibrc/nginx-vts:latest`                               | Pushes the image for use in pipelines.                                             |
| **Build Agent Image**                  | `docker build -t jenkins-agent:latest -f Dockerfile.agent .`         | Creates the Agent with the necessary Docker CLI.                                   |
| **Create Configs**                     | `touch prometheus.yml`                                               | Ensure the required Prometheus config file is present.                             |

### Specific Versions Used 🛠️

| Component              | Version/Details                                                                            |
| :--------------------- | :----------------------------------------------------------------------------------------- |
| **Jenkins Controller** | `jenkins/jenkins:2.534-jdk17`                                                              |
| **Jenkins Plugins**    | All recommended, plus **Docker API Plugin**.                                               |
| **Pipeline Images**    | `node:22-alpine` for general builds, `mcr.microsoft.com/playwright:v1.56.0-jammy` for E2E. |

## 1\. 🚀 LAUNCHING THE INFRASTRUCTURE

Execute the following command to launch all 7 services (Jenkins, DinD, Prometheus, Grafana, Exporter, App):

```bash
docker compose up -d
```

| Service                | Host Access URL         | Purpose                       |
| :--------------------- | :---------------------- | :---------------------------- |
| **Jenkins Controller** | `http://localhost:8080` | CI/CD Orchestration.          |
| **Prometheus UI**      | `http://localhost:9090` | Metrics Storage and Querying. |
| **Grafana UI**         | `http://localhost:3000` | Visualization Dashboard.      |
| **Production App**     | `http://localhost:8081` | Final Deployed Application.   |
| **Nginx Exporter**     | `http://localhost:9113` | Exporter Debug Endpoint.      |

## 2\. 🔑 JENKINS AGENT CONFIGURATION (Manual Step)

This step must be repeated if the `jenkins_home` volume is deleted.

1.  **Retrieve Password:** `docker logs jenkins | grep 'initialAdminPassword'`
2.  **Access UI** (`http://localhost:8080`) and complete the initial setup, installing the required plugins.
3.  Go to **Manage Jenkins** → **Nodes**. Create a **New Node** named `docker-deploy-host`.
4.  Set **Launch Method** to **Launch agent by connecting it to the controller (WebSocket)**.
5.  After saving, copy the **Agent Secret** from the node's **Status** page.
6.  **Stop Agent:** `docker compose down jenkins-agent`
7.  **Update `.env`:** Paste the secret into the `JENKINS_AGENT_SECRET` variable.
8.  **Restart Agent:** `docker compose up -d jenkins-agent`

---

# PART II: 🛡️ ARCHITECTURE & MONITORING DETAILS

## A. Secure DinD Architecture

| Feature               | Configuration                                              | Security / Rationale                                                                                                    |
| :-------------------- | :--------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------- |
| **Host Isolation**    | `jenkins-agent` does **not** mount `/var/run/docker.sock`. | **CRITICAL SECURITY:** Prevents pipeline containers from gaining root access to the host machine.                       |
| **DinD Connection**   | `DOCKER_HOST=tcp://jenkins-dind:2375` (in `.env`)          | Forces the Agent's Docker CLI to communicate with the isolated `jenkins-dind` service over the internal Docker network. |
| **Image Persistence** | `docker_data:/var/lib/docker` (in `docker-compose.yml`)    | Ensures that pulled and built image layers are **cached** and reused across pipeline runs, speeding up CI/CD.           |

## B. Monitoring Configuration (Prometheus & Nginx VTS)

The monitoring stack provides end-to-end visibility into the CI platform and the deployed application.

### `prometheus.yml` Targets:

| Job Name         | Target Service        | Metrics Path   | Purpose                                                        |
| :--------------- | :-------------------- | :------------- | :------------------------------------------------------------- |
| `prometheus`     | `localhost:9090`      | `/metrics`     | Self-monitoring.                                               |
| `jenkins`        | `jenkins:8080`        | `/prometheus/` | CI/CD performance (build times, queue size).                   |
| `nginx-exporter` | `nginx_exporter:9113` | `/metrics`     | Deployed App's Nginx metrics (traffic, connections, VTS data). |

### Nginx VTS Flow:

1.  **VTS Metrics Endpoint:** The Nginx VTS base image exposes the metrics endpoint on **port 7777** via `nginx-vts-metrics.conf`.
2.  **Application Nginx (in `app-prod`)** serves the application on port **8080**.
3.  **Nginx Exporter** (service `nginx_exporter`) scrapes the VTS data via `NGINX_SCRAPE_URL=http://app-prod:7777/metrics`.
4.  **Prometheus** scrapes the processed Nginx metrics from the Exporter at `nginx_exporter:9113`.

---

# PART III: 💻 CI/CD USAGE

## 4\. APPLICATION BUILD & DEPLOYMENT

The CI pipeline uses the D-I-D architecture to build your application image and update the running `app-prod` service.

### A. Application Dockerfile (`Dockerfile.prod.nginx`)

Your application uses the pre-built, reusable Nginx base:

```dockerfile
FROM itwibrc/nginx-vts:latest
# Copies the application's default.conf and compiled assets
# ... (Copy dist files and default.conf)
ENTRYPOINT ["nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]
```

### B. Example Pipeline (Deployment Stage)

```groovy
        stage('Deploy & Monitor Setup') {
            steps {
                sh '''
                # 1. Build and push image using the D-I-D daemon
                docker build -t ${DOCKER_USER}/${APP_NAME}:${BUILD_NUMBER} .
                docker push ${DOCKER_USER}/${APP_NAME}:${BUILD_NUMBER}

                # 2. Update running service (Pulls new image and restarts)
                docker compose up -d app-prod

                # 3. Allow time for exporter to reconnect
                sleep 15
                '''
            }
        }
```

## 5\. 🛡️ ISOLATED E2E TESTING (Security Feature)

To ensure security and prevent test environments from interfering with the main services (like Prometheus or Jenkins), E2E tests are run on a **dedicated, temporary bridge network** inside the DinD environment.

### Pipeline Logic:

- **Communication:** Containers communicate using their **service names** (e.g., `e2e-runner`), not `localhost` or published ports.
- **Isolation:** The network is created at the start of the stage and destroyed in the `finally` block.

<!-- end list -->

```groovy
        stage('TEST:E2E') {
            steps {
                script {
                    def e2eAppServer = 'e2e-runner'
                    def e2eTestRunner = 'playwright-runner'
                    def e2eNetwork = "e2e-network-${env.BUILD_ID}"

                    sh(label: "Delete previous network", script: "${CONTAINER_CLI} network rm ${e2eNetwork} || true")
                    sh(label: "Create isolated network", script: "${CONTAINER_CLI} network create ${e2eNetwork}")

                    try {
                        // 1. Start App Container (attached to isolated network, NO port mapping)
                        sh(label: 'Start App Server', script: """
                            ${CONTAINER_CLI} run -d --name ${e2eAppServer} \\
                                --network=${e2eNetwork} \\
                                ${env.TEMP_CI_IMAGE_TAG}
                        """)

                        // 2. Start Test Container (uses App Server's name for target URL)
                        sh(label: 'Start Playwright Runner', script: """
                            ${CONTAINER_CLI} run -d --name ${e2eTestRunner} \\
                                --network=${e2eNetwork} \\
                                -e PLAYWRIGHT_TEST_BASE_URL="http://${e2eAppServer}:${env.PROD_PORT}" \\
                                ${env.PLAYWRIGHT_IMAGE} sleep 600
                        """)

                        // ... (Copy files, execute tests, copy artifacts) ...

                        sh(label: 'Execute E2E Tests', script: """
                            ${CONTAINER_CLI} exec -w /tmp/app ${e2eTestRunner} /bin/sh -c 'npm run test:e2e'
                        """)

                    } finally {
                        // CRITICAL: Ensure containers are stopped/removed before deleting the network
                        sh(label: 'Clean up App Server', script: "${CONTAINER_CLI} stop ${e2eAppServer} || true ; ${CONTAINER_CLI} rm -f ${e2eAppServer} || true")
                        sh(label: 'Clean up Test Runner', script: "${CONTAINER_CLI} stop ${e2eTestRunner} || true ; ${CONTAINER_CLI} rm -f ${e2eTestRunner} || true")
                        sh(label: "Delete isolated network", script: "${CONTAINER_CLI} network rm ${e2eNetwork} || true")
                    }
                }
            }
        }
```

## 6\. ♻️ MAINTENANCE

| Action                              | Command                  | Purpose                                                                   |
| :---------------------------------- | :----------------------- | :------------------------------------------------------------------------ |
| **Regular Stop** (Preserve Data)    | `docker compose down`    | Preserves all named volumes (Jenkins, Docker data, Prometheus, Grafana).  |
| **Clean Restart** (Delete ALL Data) | `docker compose down -v` | **Deletes ALL named volumes**. Requires repeating **Section 2** entirely. |

---

## 📌 APPENDIX: Resources

| Section            | Content                                                      | Link                                                                                                                                                          |
| :----------------- | :----------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Illustrations**  | Supporting visuals for the architecture and configuration.   | [public folder](./public)                                                                                                                                     |
| **Webhook Config** | Guide for configuring GitHub webhooks using a reverse proxy. | [Webhook configuration using ngrok](https://dev.to/selmaguedidi/understanding-github-webhooks-leveraging-reverse-proxy-with-ngrok-for-local-development-2k7n) |
| **Local Testing**  | External tool for local testing and exposure.                | [For local testing, you can use ngrok](https://ngrok.com/)                                                                                                    |
