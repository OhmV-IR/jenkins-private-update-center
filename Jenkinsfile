pipeline {
	agent { label 'docker-linux' }
	stages {
        stage("Checkout"){
            checkout scm
        }
        stage("Build docker file"){
            sh "docker build -t localhost:5000/jenkins-update-center:latest ."
        }
        stage("Push to registry"){
            sh "docker push localhost:5000/jenkins-update-center:latest"
        }
	}
}