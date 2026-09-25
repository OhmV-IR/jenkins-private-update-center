pipeline {
	agent { label 'docker-linux' }
	stages {
        stage("Checkout"){
            steps {
                checkout scm
            }
        }
        stage("Build docker file"){
            steps {
                sh "docker build -t localhost:5000/jenkins-update-center:latest ."
            }
        }
        stage("Push to registry"){
            steps {
                sh "docker push localhost:5000/jenkins-update-center:latest"
            }
        }
	}
}