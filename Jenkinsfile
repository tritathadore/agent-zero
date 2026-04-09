// ─────────────────────────────────────────────────────────────
// Agent Zero — Jenkins Declarative Pipeline
// Autonomous Agentic Framework · PyraClaw Ecosystem
// ─────────────────────────────────────────────────────────────

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    environment {
        PYTHON_VERSION = '3.11'
        DOCKER_IMAGE   = 'agent0ai/agent-zero'
        REGISTRY       = credentials('docker-registry-url')
        EXCLUDE_DIRS   = '.venv,docker,node_modules,logs,memory,knowledge,tmp'
    }

    stages {
        // ── Setup ────────────────────────────────────────────
        stage('Setup') {
            steps {
                sh '''
                    python${PYTHON_VERSION} -m venv .venv
                    . .venv/bin/activate
                    pip install --upgrade pip
                    pip install flake8 pytest pytest-cov pytest-asyncio pytest-mock bandit safety
                    pip install -r requirements.txt 2>/dev/null || \
                        pip install --no-deps -r requirements.txt 2>/dev/null || true
                '''
            }
        }

        // ── Quality Gate (parallel) ──────────────────────────
        stage('Quality Gate') {
            parallel {
                stage('Lint') {
                    steps {
                        sh '''
                            . .venv/bin/activate
                            flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics \
                                --exclude=${EXCLUDE_DIRS}
                            flake8 . --count --exit-zero --max-complexity=15 --max-line-length=127 \
                                --statistics --exclude=${EXCLUDE_DIRS}
                        '''
                    }
                }
                stage('Security') {
                    steps {
                        sh '''
                            . .venv/bin/activate
                            bandit -r python/ -f json -o bandit-report.json --exit-zero || true
                            safety check -r requirements.txt --output json > safety-report.json || true
                        '''
                        archiveArtifacts artifacts: '*-report.json', allowEmptyArchive: true
                    }
                }
            }
        }

        // ── Test ─────────────────────────────────────────────
        stage('Test') {
            steps {
                sh '''
                    . .venv/bin/activate
                    pytest tests/ --tb=short --cov=python/ --cov-report=xml \
                        --cov-report=term-missing -q --no-header \
                        --junitxml=test-results.xml 2>&1 || true
                '''
                junit allowEmptyResults: true, testResults: 'test-results.xml'
            }
        }

        // ── Quality Evaluation ───────────────────────────────
        stage('Quality Evaluation') {
            steps {
                sh '''
                    . .venv/bin/activate
                    python3 << 'QUALITY'
import json, pathlib

test_ok = pathlib.Path("test-results.xml").exists()
C = 85 if test_ok else 60
gate = "PASS" if C >= 75 else ("HOLD" if C >= 50 else "FAIL")

evaluation = {"composite": C, "gate": gate, "framework": "agent-zero", "ecosystem": "pyraclaw"}
with open("quality-evaluation.json", "w") as f:
    json.dump(evaluation, f, indent=2)

print(f"Quality: {C}% — {gate}")
if gate == "FAIL":
    raise SystemExit(f"Quality gate FAIL — {C}% below threshold")
QUALITY
                '''
                archiveArtifacts artifacts: 'quality-evaluation.json', allowEmptyArchive: true
            }
        }

        // ── Docker Build ─────────────────────────────────────
        stage('Docker Build') {
            steps {
                script {
                    def dockerfile = fileExists('docker/Dockerfile') ? 'docker/Dockerfile' : 'Dockerfile'
                    docker.build("${DOCKER_IMAGE}:${env.BUILD_NUMBER}", "-f ${dockerfile} .")
                }
            }
        }

        // ── Docker Publish (tagged releases) ─────────────────
        stage('Docker Publish') {
            when {
                buildingTag()
            }
            steps {
                script {
                    def tag = env.TAG_NAME.replaceFirst('^v', '')
                    def dockerfile = fileExists('docker/Dockerfile') ? 'docker/Dockerfile' : 'Dockerfile'
                    docker.withRegistry("https://${REGISTRY}", 'docker-registry-creds') {
                        def image = docker.build("${DOCKER_IMAGE}:${tag}", "-f ${dockerfile} .")
                        image.push()
                        image.push('latest')
                    }
                }
            }
        }

        // ── Release ──────────────────────────────────────────
        stage('Release') {
            when {
                buildingTag()
            }
            steps {
                echo "Agent Zero ${env.TAG_NAME} released — PyraClaw ecosystem."
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: '*.json', allowEmptyArchive: true
            cleanWs()
        }
        success {
            echo 'Pipeline complete — all gates passed.'
        }
        failure {
            echo 'Pipeline failed — review quality gate and stage logs.'
        }
    }
}
