# 📚 Jenkins CI/CD Environment Guide (Docker Compose)

This guide is structured into two main parts: **Part I** covers the complex, one-time setup of the resilient CI/CD platform, and **Part II** demonstrates how easily that platform supports dynamic application pipelines.

## 💾 Configuration Files & Source Code

All configuration files are located in the project repository root.

| File                     | Description                                                                                            | Link                                                       |
| :----------------------- | :----------------------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| **`docker-compose.yml`** | Defines all services (Controller, Agent, Volumes, Networks) and includes **runtime permission fixes**. | **[docker-compose.yaml](./docker-compose.yaml)**           |
| **`Dockerfile.agent`**   | Custom build file for the Agent, adding the required Docker CLI and `bash`.                            | **[Dockerfile.agent](./Dockerfile.agent)**                 |
| **`.env`**               | Environment variable storage (URLs, Agent Name, and Agent Secret).                                     | **[.env file](./env)**                                     |
| **Language Pipelines**   | Repository with example pipelines for Node.js, Python, Go, and more.                                   | **[Jenkins Docs GitHub](https://github.com/jenkins-docs)** |

---

# PART I: ⚙️ CI/CD INFRASTRUCTURE SETUP (The Hard Part)

This section focuses on establishing the permanent, self-healing **Jenkins Platform**. The complexity here ensures the entire system is stable, secure, and ready to execute dynamic build jobs.

## 💡 Role of the Jenkins Agent: The Construction Firm Analogy 🏗️

To understand why the Agent is necessary, think of your Jenkins environment as a **Construction Firm**.

| Component                    | Analogy                              | Role in CI/CD                                                                                                                                                                                                  |
| :--------------------------- | :----------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Jenkins Controller**       | **The Main Office**                  | The Controller is the central command structure, managing blueprints (job definitions) and schedules. It **never performs the physical work**.                                                                 |
| **Jenkins Agent**            | **The Specialized Crew Chief**       | The Agent is the **dedicated worker machine** that executes all build commands. Its primary function is to **manage the tools and execution environment** at the job site (the workspace).                     |
| **Docker-in-Docker (D-I-D)** | **Calling a Specialized Contractor** | The Agent's ability to run Docker means it can instantly spin up a temporary container (like a plumber or electrician) for a specific stage, guaranteeing a clean, isolated environment for every single task. |

### The Agent's Deep Role:

The Agent's primary function is **decentralization and specialization**:

1.  **Offload Processing:** It prevents the Controller from crashing under heavy CPU/memory loads from compiling large projects.
2.  **Specialization:** Our Agent is specialized to handle the **Docker Socket**, allowing it to interact with the Docker daemon and launch build containers.
3.  **Isolation:** If a bad script or a process failure occurs, it only affects the Agent, leaving the central Controller stable.

<!-- end list -->

- **Advantage:** **Isolation and Scalability.** The platform can easily scale by adding more specialized Agents.
- **Use Case:** Necessary for any production setup where **performance and resilience** are critical.

## 🛑 PREREQUISITES & Initial Setup

### A. Environment Preparation (Host)

| Action                | Command                                                      | Purpose                                                                                                                                   |
| :-------------------- | :----------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| **Create Workspace**  | `mkdir -p /home/pc/workspace`                                | Creates the **host directory** that the Agent will mount. This volume is persistent and holds all cloned source code and build artifacts. |
| **Build Agent Image** | `docker build -t jenkins-agent:latest -f Dockerfile.agent .` | Builds the custom image. It includes the **Docker CLI** and `bash`, necessary for Docker-in-Docker (D-I-D) execution.                     |

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

## 3\. 🛡️ MASTERY POINTS: Why the Fixes Were Necessary

| Fix                        | Location                          | Explanation                                                                                                                                                                                                                                                                                                                                                                    |
| :------------------------- | :-------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Runtime Permission Fix** | `jenkins-agent: command:`         | **Problem:** The host volume (`/home/pc/workspace`) is typically owned by `root`, but the Agent runs as the secure, non-root `jenkins` user, causing workspace errors. **Solution:** We run `chown -R jenkins:jenkins` as root _at runtime_ to fix permissions on the mounted volume, then switch back to the non-root `jenkins` user for execution via `su jenkins -c '...'`. |
| **DNS Resolution**         | `jenkins: networks: driver_opts:` | **Problem:** The Controller often fails initial setup with `UnknownHostException` because Docker's default DNS setup can be unreliable. **Solution:** Explicitly defining public DNS servers (`8.8.8.8, 1.1.1.1`) ensures the container can reliably resolve external hostnames.                                                                                               |

---

# PART II: 💻 APPLICATION CI/CD (The Easy Part)

With the platform stable, we use the Agent's D-I-D capability to easily define clean execution environments within the pipeline script.

## 4\. CI/CD EXAMPLE: Node.js Project Pipeline

### A. Create the Jenkins Job

1.  In the Jenkins UI, click **New Item**, name it, and select **Pipeline**.
2.  In the job configuration, set the **Definition** to **Pipeline script**.
3.  Paste the following script into the **Script** text area.

### B. Declarative Pipeline Script

This pipeline uses the permanent Agent to clone the repository, but executes all **build steps inside a temporary `node:lts-buster-slim` container**.

```groovy
pipeline {
    agent {
        // The Agent uses its D-I-D access to run this clean container.
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
                git url: 'https://github.com/jenkins-docs/simple-node-js-react-npm-app.git'
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

| Action                              | Command                  | Purpose                                                                                                     |
| :---------------------------------- | :----------------------- | :---------------------------------------------------------------------------------------------------------- |
| **Regular Stop** (Preserve Data)    | `docker compose down`    | Stops containers while preserving the `jenkins_home` volume and all configurations.                         |
| **Clean Restart** (Delete ALL Data) | `docker compose down -v` | Stops containers and **deletes the `jenkins_home` volume**. This requires repeating **Section 2** entirely. |
