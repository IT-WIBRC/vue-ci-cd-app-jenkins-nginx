# 📚 Jenkins CI/CD Environment Guide (Secure Docker-in-Docker)

This guide is structured into two main parts: **Part I** covers the secure, one-time setup of the resilient CI/CD platform using **Docker-in-Docker (DinD)**, and **Part II** demonstrates how easily that platform supports dynamic application pipelines.

## 💾 Configuration Files & Source Code

All configuration files are located in the project repository root.

| File                     | Description                                                                                            | Link                                                       |
| :----------------------- | :----------------------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| **`docker-compose.yml`** | Defines all services (Controller, Agent, **Isolated Daemon**) and includes **secure DinD networking**. | **[docker-compose.yaml](./docker-compose.yaml)**           |
| **`Dockerfile.agent`**   | Custom build file for the Agent, installing the necessary **Docker CLI** to talk to the DinD daemon.   | **[Dockerfile.agent](./Dockerfile.agent)**                 |
| **`.env`**               | Environment variable storage (URLs, Agent Name, and Agent Secret).                                     | **[.env file](./env)**                                     |
| **Language Pipelines**   | Repository with example pipelines for Node.js, Python, Go, and more.                                   | **[Jenkins Docs GitHub](https://github.com/jenkins-docs)** |

---

# PART I: ⚙️ CI/CD INFRASTRUCTURE SETUP (The Hard Part)

This section focuses on establishing the permanent, self-healing **Jenkins Platform** using a **secure Docker-in-Docker (DinD)** architecture. The complexity here ensures the entire system is stable, **secure from host compromise**, and ready to execute dynamic build jobs.

## 💡 Role of the Jenkins Agent: The Construction Firm Analogy 🏗️

To understand why the Agent is necessary, think of your Jenkins environment as a **Construction Firm**.

| Component                   | Analogy                              | Role in CI/CD                                                                                                                                                                                           |
| :-------------------------- | :----------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Jenkins Controller**      | **The Main Office**                  | The Controller is the central command structure, managing blueprints (job definitions) and schedules. It **never performs the physical work**.                                                          |
| **Jenkins Agent**           | **The Specialized Crew Chief**       | The Agent is the **dedicated worker machine** that executes all build commands. It must only contain the **Docker Client** (CLI) to communicate with its isolated daemon.                               |
| **Docker-in-Docker (DinD)** | **Calling a Specialized Contractor** | The Agent communicates over the network with the isolated `jenkins-dind` container, which runs the actual Docker daemon. This guarantees a clean, **isolated environment**, protecting the host system. |

### The Agent's Deep Role: Secure Decentralization

The Agent's primary function is **decentralization and specialization** via **secure networking**:

1.  **Offload Processing:** Prevents the Controller from crashing under heavy CPU/memory loads from compiling large projects.
2.  **Security:** The Agent does **NOT** mount the host's Docker socket. Instead, it uses the `DOCKER_HOST=tcp://jenkins-dind:2375` variable to connect to the isolated Docker daemon. This is the **Principle of Least Privilege** in action.
3.  **Isolation:** If a bad script or a process failure occurs, it only affects the Agent and the temporary **isolated `jenkins-dind` environment**, leaving the host system secure.

- **Advantage:** **Host Security and Isolation.** A compromised build process cannot gain control of the underlying host machine.
- **Use Case:** Mandatory for any production environment where build containers run potentially untrusted code.

## 🛑 PREREQUISITES & Initial Setup

### A. Environment Preparation (Host)

| Action                | Command                                                                   | Purpose                                                                                            |
| :-------------------- | :------------------------------------------------------------------------ | :------------------------------------------------------------------------------------------------- |
| **Install Docker**    | Follow instructions at [Docker Docs](https://docs.docker.com/get-docker/) | Installs Docker Engine to run containers.                                                          |
| **Build Agent Image** | `docker build -t jenkins-agent:latest -f Dockerfile.agent .`              | Builds the custom image. It includes the **Docker CLI**, necessary for DinD network communication. |

## 1\. 🚀 LAUNCHING THE INFRASTRUCTURE

### A. Initial Launch Command

```bash
docker compose up -d
```

### B. Controller Setup

1.  **Retrieve Initial Password:** `docker logs jenkins | grep 'initialAdminPassword'`
2.  **Access Jenkins:** `http://localhost:8080`. Complete setup.

## 2\. 🔑 AGENT CONFIGURATION (The Critical Manual Step)

This process is required every time the `jenkins_home` volume is deleted because the Agent's security token is regenerated.

### A. Create and Configure the Agent Node

1.  In the Jenkins UI, go to **Manage Jenkins** → **Nodes**. Click **New Node**.
2.  **Node Name:** `docker-deploy-host`.
3.  Configure the node carefully:
    - **Remote Root Directory:** `/home/jenkins/workspace`
    - **Launch Method:** **Launch agent by connecting it to the controller (WebSocket)**

---

### B. Retrieve and Apply the Secret

1.  After configuring and saving, go to the node's **Status** page and copy the **Agent Secret** (the long hexadecimal string).

---

2.  **Stop Agent:** `docker compose down jenkins-agent`
3.  **Update `.env`:** Paste the secret into the `JENKINS_AGENT_SECRET` variable.
4.  **Restart Agent:** `docker compose up -d jenkins-agent`

## 3\. 🛡️ MASTERY POINTS: Key Architecture & Networking

| Feature             | Service & Configuration            | Explanation (Security Focus)                                                                                                                                                                                                                                              |
| :------------------ | :--------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **DinD Connection** | `jenkins-agent: environment:`      | **Mechanism:** The `DOCKER_HOST=tcp://jenkins-dind:2375` environment variable redirects the Agent's Docker CLI to the isolated `jenkins-dind` service over the internal network. **Security:** **No host socket is mounted**, making host compromise extremely difficult. |
| **Docker CLI**      | `Dockerfile.agent: RUN apk add...` | **Requirement:** The Agent container needs the `docker` binary to execute pipeline commands. **Solution:** It is installed directly onto the custom agent image, as the binary is no longer mounted from the host.                                                        |
| **DNS Resolution**  | `networks: driver_opts:`           | **Problem:** Docker's default DNS setup can be unreliable for external calls. **Solution:** Explicitly defining public DNS servers (`8.8.8.8, 1.1.1.1`) ensures the container can reliably resolve external hostnames for tasks like cloning repos.                       |

---

# PART II: 💻 APPLICATION CI/CD (The Easy Part)

With the secure DinD platform stable, we use the Agent's D-I-D capability to easily define clean execution environments within the pipeline script.

## 4\. CI/CD EXAMPLE: Node.js Project Pipeline

### A. Create the Jenkins Job

1.  In the Jenkins UI, click **New Item**, name it, and select **Pipeline**.
2.  In the job configuration, set the **Definition** to **Pipeline script**.
3.  Paste the following script into the **Script** text area.

### B. Declarative Pipeline Script

This pipeline uses the permanent Agent to clone the repository, but executes all **build steps inside a temporary `node:lts-buster-slim` container** that the Agent spawns within the isolated DinD environment.

```groovy
pipeline {
    agent {
        // The Agent uses its DOCKER_HOST to run this clean container
        // inside the isolated DinD daemon.
        docker {
            image 'node:lts-buster-slim'
            args '-p 3000:3000'
        }
    }
    environment {
        CI = 'true'
    }
    stages {
        stage('Checkout') {
            steps {
                git url: '[https://github.com/jenkins-docs/simple-node-js-react-npm-app.git](https://github.com/jenkins-docs/simple-node-js-react-npm-app.git)'
            }
        }
        stage('Build') {
            steps {
                sh 'npm install'
            }
        }
        stage('Test') {
            steps {
                sh './jenkins/scripts/test.sh'
            }
        }
        stage('Deliver') {
            steps {
                sh './jenkins/scripts/deliver.sh'
                input message: 'Finished using the web site? (Click "Proceed" to continue)'
                sh './jenkins/scripts/kill.sh'
            }
        }
    }
}
```

### C. Run the Job

Click **Save** and then **Build Now**.

---

## 5\. ♻️ MAINTENANCE

| Action                              | Command                  | Purpose                                                                                             |
| :---------------------------------- | :----------------------- | :-------------------------------------------------------------------------------------------------- |
| **Regular Stop** (Preserve Data)    | `docker compose down`    | Stops containers while preserving the `jenkins_home` and `docker_data` volumes.                     |
| **Clean Restart** (Delete ALL Data) | `docker compose down -v` | Stops containers and **deletes ALL named volumes**. This requires repeating **Section 2** entirely. |

# What i used

- Jenkins container `2.534`
- `mcr.microsoft.com/playwright:v1.56.0-jammy` for e2e tests
- `node:22-alpine` for npm command availability

> [!NOTE]
> This is an important to know for a seamless configuration.
> When configuring Jenkins, `I installed all the recommended plugin in addition to the Docker API plugin`

# Illustrations

Some the Illustrations are located in the [public folder](./public) folder.

# Resources

- [Webhook configuration using ngrok](https://dev.to/selmaguedidi/understanding-github-webhooks-leveraging-reverse-proxy-with-ngrok-for-local-development-2k7n)
- [For local testing, you can use ngrok](https://ngrok.com/)
