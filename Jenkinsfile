pipeline {
    agent { label 'docker-linux' }
    environment {
        NEXUS_URL = 'https://nexus.ohmvir.dev/repository/maven-releases/'
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build and test') {
            steps {
                withCredentials([
                    usernamePassword(credentialsId: 'nexus-credentials', usernameVariable: 'NEXUS_USER', passwordVariable: 'NEXUS_PASS'),
                    string(credentialsId: 'nexus-cf-access-client-id', variable: 'CF_ACCESS_CLIENT_ID'),
                    string(credentialsId: 'nexus-cf-access-client-secret', variable: 'CF_ACCESS_CLIENT_SECRET')
                ]) {
                    sh '''
                        set +x
                        set -eu
                        IMAGE="localhost:5000/jenkins-update-center:${BUILD_NUMBER}"
                        TEST_CONTAINER="jenkins-update-center-test-${BUILD_NUMBER}"
                        cleanup() {
                            docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true
                        }
                        trap cleanup EXIT

                        docker build -t "$IMAGE" .
                        docker run -d --rm --name "$TEST_CONTAINER" -p 127.0.0.1::80 \
                            --env NEXUS_URL --env NEXUS_USER --env NEXUS_PASS \
                            --env CF_ACCESS_CLIENT_ID --env CF_ACCESS_CLIENT_SECRET \
                            "$IMAGE" >/dev/null

                        TEST_PORT="$(docker port "$TEST_CONTAINER" 80/tcp | awk -F: '{print $NF}')"
                        TEST_URL="http://127.0.0.1:${TEST_PORT}/update-center.json"
                        for attempt in $(seq 1 120); do
                            if curl --fail --silent "$TEST_URL" -o /dev/null; then
                                break
                            fi
                            sleep 5
                        done
                        if ! curl --fail --silent "$TEST_URL" -o /dev/null; then
                            docker logs --tail 80 "$TEST_CONTAINER"
                            exit 1
                        fi

                        docker exec "$TEST_CONTAINER" python3 -c "
import json, urllib.request
text = urllib.request.urlopen('http://127.0.0.1/update-center.json', timeout=15).read().decode()
wrapper = 'updateCenter.post('
assert text.startswith(wrapper) and text.rstrip().endswith(');'), 'invalid update-center wrapper'
document = json.loads(text[len(wrapper):-2].strip())
plugins = document.get('plugins')
assert str(document.get('updateCenterVersion')) == '1', 'unexpected update-center version'
assert isinstance(plugins, dict) and plugins, 'Nexus produced no plugin entries'
print('Validated non-empty served update-center: %d plugins' % len(plugins))
"

                        docker tag "$IMAGE" localhost:5000/jenkins-update-center:latest
                    '''
                }
            }
        }
        stage('Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker_serv_priv_registry', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        set +x
                        set -eu
                        DOCKER_CONFIG="$(mktemp -d)"
                        export DOCKER_CONFIG
                        cleanup() {
                            docker logout localhost:5000 >/dev/null 2>&1 || true
                            rm -rf "$DOCKER_CONFIG"
                        }
                        trap cleanup EXIT

                        printf '%s' "$DOCKER_PASS" | docker login localhost:5000 --username "$DOCKER_USER" --password-stdin
                        docker push localhost:5000/jenkins-update-center:latest
                    '''
                }
            }
        }
    }
}
