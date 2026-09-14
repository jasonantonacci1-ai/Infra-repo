pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('terraform') {
            steps {
                sh 'terraform init'
                sh 'terraform apply -auto-approve'
            }
        }
        stage('ansible') {
            steps {
                // commands go here
            }
        }
        stage('Name of Stage') {
            steps {
                // commands go here
            }
        }
    }
}
post {
        always {
            echo 'Tearing down infrastructure...'
            sh 'terraform destroy -auto-approve'
        }
    }
 }
