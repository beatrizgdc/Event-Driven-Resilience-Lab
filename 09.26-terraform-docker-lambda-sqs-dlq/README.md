# AWS Event-Driven Resilience Lab (SRE/DevOps)

[![LocalStack](https://img.shields.io/badge/LocalStack-3.8.1-blue?logo=localstack)](https://localstack.cloud/)
[![Terraform](https://img.shields.io/badge/IaC-Terraform_1.5+-purple?logo=terraform)](https://www.terraform.io/)
[![AWS Lambda](https://img.shields.io/badge/Serverless-AWS_Lambda-orange?logo=awslambda)](https://aws.amazon.com/lambda/)
[![SRE Practice](https://img.shields.io/badge/SRE-Failure_Injection_%26_DLQ-green)](#)

Este repositório contém uma demonstração **100% gratuita** e local de uma arquitetura orientada a eventos (*event-driven architecture*) resiliente na AWS, utilizando **LocalStack Community Edition**, **Terraform** e **AWS Lambda**.

O projeto foi desenhado focando nos pilares de **Site Reliability Engineering (SRE)**: desacoplamento de microsserviços, automação via IaC, manipulação e isolamento de falhas (*Failure Injection*) e estratégias de *Dead-Letter Queue (DLQ)*.

---

## Arquitetura da Solução

```text
[ S3 Bucket ] ─── (Event Notification) ───> [ SQS Queue Principal ]
                                                    │
                                                    ▼
                                           [ AWS Lambda Worker ]
                                                    │
                                           (Falha / Retries > 2)
                                                    │
                                                    ▼
                                          [ SQS Dead-Letter Queue ]
```

### Fluxo de Eventos e Resiliência:
1. **Ingestão:** Um arquivo JSON é enviado ao Bucket S3 (`sre-ingestion-bucket`).
2. **Notificação:** O S3 dispara automaticamente uma notificação contendo o metadado do arquivo para a fila SQS (`sre-processing-queue`).
3. **Processamento:** A AWS Lambda (`sre-processor-function`) é engatada via *Event Source Mapping* para processar a mensagem.
4. **Falha & Retry:** Se o evento contiver uma flag de erro, a Lambda lança uma exceção. O SQS re-tenta a entrega até 2 vezes (`maxReceiveCount = 2`).
5. **Isolamento (DLQ):** Superado o limite de retentativas, a mensagem é movida automaticamente para a **Dead-Letter Queue (`sre-dead-letter-queue`)**, impedindo bloqueios (*head-of-line blocking*) e preservando o payload para análise de causa raiz (RCA).

---

## ⚡ Verificação e Instalação de Pré-requisitos

Para verificar se todas as ferramentas necessárias estão instaladas no seu ambiente Linux/macOS, abra o terminal e cole o script abaixo:

```bash
echo -e "--- Verificação de Ferramentas ---"
command -v docker >/dev/null 2>&1 && echo -e "Docker: [0;32mInstalado[0m ($(docker --version))" || echo -e "Docker: [0;31mNão instalado[0m"
docker compose version >/dev/null 2>&1 && echo -e "Docker Compose: [0;32mInstalado[0m ($(docker compose version))" || echo -e "Docker Compose: [0;31mNão instalado[0m"
command -v terraform >/dev/null 2>&1 && echo -e "Terraform: [0;32mInstalado[0m ($(terraform --version | head -n 1))" || echo -e "Terraform: [0;31mNão instalado[0m"
command -v aws >/dev/null 2>&1 && echo -e "AWS CLI: [0;32mInstalado[0m ($(aws --version))" || echo -e "AWS CLI: [0;31mNão instalado[0m"
command -v zip >/dev/null 2>&1 && echo -e "zip: [0;32mInstalado[0m ($(zip -v | head -n 2 | tail -n 1))" || echo -e "zip: [0;31mNão instalado[0m"
```

### Instruções de Instalação (Ubuntu/Debian)
Caso alguma ferramenta apareça como **Não instalado**, execute os comandos abaixo para instalar:

* **Docker & Docker Compose:**
  ```bash
  sudo apt-get update
  sudo apt-get install -y docker.io docker-compose-v2
  sudo usermod -aG docker $USER && newgrp docker
  ```

* **Terraform:**
  ```bash
  sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt-get update && sudo apt-get install terraform
  ```

* **AWS CLI v2 & Zip:**
  ```bash
  sudo apt-get update && sudo apt-get install -y zip curl unzip
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip aws
  ```

---

## Passo a Passo de Execução

### 1. Clonar o Repositório
```bash
git clone https://github.com/seu-usuario/aws-event-resilience-lab.git
cd aws-event-resilience-lab
```

### 2. Exportar Credenciais Fictícias no Terminal
Como o LocalStack roda totalmente local, defina as variáveis fictícias exigidas pela AWS CLI:
```bash
export AWS_ACCESS_KEY_ID=mock
export AWS_SECRET_ACCESS_KEY=mock
export AWS_DEFAULT_REGION=us-east-1
```

### 3. Iniciar o LocalStack
```bash
docker compose up -d
```

Confirme se o container subiu corretamente acessando:
```bash
curl http://localhost:4566/_localstack/health
```

### 4. Empacotar a Lambda e Deploy com Terraform
```bash
# Empacota a Lambda Python
cd lambda && zip -r ../lambda.zip lambda_function.py && cd ..

# Provisiona a infraestrutura no LocalStack
terraform init
terraform apply -auto-approve
```

---

## Validando a Resiliência (Hands-on SRE)

### Teste 1: Caminho Feliz (Processamento Bem-sucedido)
Envie um evento válido para o S3:
```bash
aws --endpoint-url=http://localhost:4566 s3 cp samples/valid_event.json s3://sre-ingestion-bucket/valid_event.json
```

Verifique nos logs do CloudWatch se a Lambda processou com sucesso:
```bash
aws --endpoint-url=http://localhost:4566 logs tail /aws/lambda/sre-processor-function
```

---

### Teste 2: Injeção de Falhas e Roteamento para DLQ
Envie um evento configurado para provocar erro (`invalid_event.json`):
```bash
aws --endpoint-url=http://localhost:4566 s3 cp samples/invalid_event.json s3://sre-ingestion-bucket/invalid_event.json
```

Acompanhe as falhas no log da Lambda:
```bash
aws --endpoint-url=http://localhost:4566 logs tail /aws/lambda/sre-processor-function
```

Valide que a SQS encaminhou o payload não processável para a Dead-Letter Queue (DLQ):
```bash
aws --endpoint-url=http://localhost:4566 sqs receive-message --queue-url http://localhost:4566/000000000000/sre-dead-letter-queue 
```

---

## Limpeza do Ambiente

Para destruir os recursos e desligar os containers:
```bash
aws --endpoint-url=http://localhost:4566 s3 rm s3://sre-ingestion-bucket --recursive
terraform destroy -auto-approve
docker compose down -v
rm -f lambda.zip
```

---

## 📄 Licença
Este projeto está sob a licença [MIT](LICENSE).
