// Jenkinsfile — CS411 capstone (Node.js)
//
// Test (in a Node 24 container) -> build image -> push to ttl.sh ->
// deploy to three targets: the docker VM (container), the Kubernetes
// cluster (Deployment + Service), and the target VM (systemd).
//
// The build runs on the Jenkins node (which has docker + kubectl); Node
// itself is only needed inside the test container, so the agent doesn't
// need a Node install.

pipeline {
    agent any

    environment {
        IMAGE        = 'ttl.sh/maydamv-capstone-cs411:2h'
        APP_PORT     = '4444'
        TARGET_VM    = 'target'
        DOCKER_VM    = 'docker'
        SSH_USER     = 'laborant'
        SSH_CRED_ID  = 'target-ssh'
        K8S_TOKEN_ID = 'k8s-token'
        KUBE_ARGS    = '--server=https://kubernetes:6443 --insecure-skip-tls-verify=true'
        SSH_OPTS     = '-o StrictHostKeyChecking=no'
    }

    stages {

        stage('Unit test') {
            steps {
                // run the given index.test.js on Node 24, no Node needed on the agent
                sh 'docker run --rm -v "$PWD":/app -w /app node:24-alpine sh -c "npm install && node --test"'
            }
        }

        stage('Build image') {
            steps {
                sh 'docker build -t ${IMAGE} .'
            }
        }

        stage('Push') {
            steps {
                sh 'docker push ${IMAGE}'
            }
        }

        stage('Deploy: docker VM') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED_ID, keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        ssh ${SSH_OPTS} -i "$SSH_KEY" ${SSH_USER}@${DOCKER_VM} '
                            docker pull '${IMAGE}'
                            docker rm -f myapp 2>/dev/null || true
                            docker run -d --name myapp -p '${APP_PORT}':'${APP_PORT}' '${IMAGE}'
                        '
                    '''
                }
            }
        }

        stage('Deploy: Kubernetes') {
            steps {
                withCredentials([string(credentialsId: env.K8S_TOKEN_ID, variable: 'K8S_TOKEN')]) {
                    sh '''
                        kubectl ${KUBE_ARGS} --token="$K8S_TOKEN" apply -f k8s/deployment.yaml
                        kubectl ${KUBE_ARGS} --token="$K8S_TOKEN" apply -f k8s/service.yaml
                        kubectl ${KUBE_ARGS} --token="$K8S_TOKEN" rollout status deployment/myapp --timeout=120s
                    '''
                }
            }
        }

        stage('Deploy: target VM (systemd)') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED_ID, keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        scp ${SSH_OPTS} -i "$SSH_KEY" index.js package.json deploy/myapp.service ${SSH_USER}@${TARGET_VM}:/tmp/
                        ssh ${SSH_OPTS} -i "$SSH_KEY" ${SSH_USER}@${TARGET_VM} '
                            set -e
                            command -v node >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y nodejs npm; }
                            id myapp >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin myapp
                            sudo mkdir -p /opt/myapp
                            sudo cp /tmp/index.js /tmp/package.json /opt/myapp/
                            sudo npm install --omit=dev --prefix /opt/myapp
                            sudo chown -R myapp:myapp /opt/myapp
                            sudo install -m 0644 /tmp/myapp.service /etc/systemd/system/myapp.service
                            sudo systemctl daemon-reload
                            sudo systemctl enable myapp
                            sudo systemctl restart myapp
                        '
                    '''
                }
            }
        }

        stage('Health check (target + docker)') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: env.SSH_CRED_ID, keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        for host in ${TARGET_VM} ${DOCKER_VM}; do
                            ssh ${SSH_OPTS} -i "$SSH_KEY" ${SSH_USER}@$host '
                                for i in $(seq 1 10); do
                                    if curl -fsS http://localhost:'${APP_PORT}'/ | grep -q "\\"name\\":\\"Hello\\""; then
                                        echo "OK serving on '"$host"':'${APP_PORT}'"; exit 0
                                    fi
                                    sleep 2
                                done
                                echo "not healthy on '"$host"'"; exit 1
                            '
                        done
                    '''
                }
            }
        }
    }

    post {
        success { echo "Capstone deployed: image ${IMAGE} -> docker VM, Kubernetes, target VM" }
        failure { echo "Pipeline failed — check the stage logs above" }
    }
}
