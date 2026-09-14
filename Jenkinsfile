pipeline {
    agent any
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
    }
    agent any
    stages {
        stage('terraform') {
            steps {
                // commands go here
            }
        }
    }
    agent any
    stages {
        stage('ansible') {
            steps {
                // commands go here
            }
        }
    }
    agent any
    stages {
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
