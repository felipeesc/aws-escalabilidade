# aws-escalabilidade

Projeto de estudo de escalabilidade na AWS com Spring Boot, Redis, PostgreSQL e Terraform.

A aplicação expõe uma API REST de produtos com cache em Redis e persistência em PostgreSQL. A infraestrutura é provisionada inteiramente via Terraform com Auto Scaling automático baseado em CPU e volume de requisições.

---

## Pipeline de CI/CD

```
Você faz git push
       │
       ▼
GitHub Actions (roda na nuvem do GitHub)
       │
       ├── 1. Compila o projeto (mvn package)
       ├── 2. Faz login no ECR (sua conta AWS)
       ├── 3. Faz docker build + push da imagem pro ECR
       └── 4. Chama o ASG pra fazer instance refresh
                    │
                    ▼
              AWS substitui as EC2s
              com a nova imagem
              (rolling, zero downtime)
```

O código do pipeline fica no próprio repositório GitHub (`.github/workflows/deploy.yml`). As credenciais AWS ficam nos **Secrets** do repositório — o GitHub injeta como variáveis de ambiente em tempo de execução, sem expor no código.

| Onde | O quê |
|---|---|
| GitHub (`.github/workflows/`) | Arquivo YAML do pipeline |
| GitHub Secrets | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, nome do ECR |
| AWS ECR | Imagem Docker buildada e versionada |
| AWS ASG | Consome a nova imagem via instance refresh (rolling, zero downtime) |

---

## Visão geral da arquitetura

```
Internet
   │
   ▼
[ALB - porta 80]          ← único ponto de entrada público
   │
   ├── /api/health         ← health check do próprio ALB
   │
   ▼
[Auto Scaling Group]
 ┌─────────────────────┐
 │  EC2 (t3.small)     │  × 2 a 10 instâncias, subnets privadas
 │  Docker → Spring Boot│
 └─────────────────────┘
        │           │
        ▼           ▼
   [RDS Postgres]  [ElastiCache Redis]
   multi-AZ        single-node
   subnets privadas
```

O tráfego nunca chega direto nas instâncias EC2 — só passa pelo ALB. As instâncias ficam em subnets privadas sem IP público. Banco e cache também ficam em subnets privadas e só aceitam conexões vindas das instâncias de aplicação.

---

## Estrutura do projeto

```
aws-escalabilidade/
├── k6-load-test.js          # script de carga
├── app/
│   ├── Dockerfile
│   ├── docker-compose.yml   # ambiente local completo
│   ├── pom.xml
│   └── src/main/
│       ├── resources/
│       │   └── application.yml
│       └── java/com/example/loadsim/
│           ├── LoadSimApplication.java
│           ├── config/RedisConfig.java
│           ├── controller/
│           │   ├── HealthController.java
│           │   └── ProductController.java
│           ├── model/Product.java
│           ├── repository/ProductRepository.java
│           └── service/ProductService.java
└── terraform/
    ├── main.tf
    ├── variables.tf
    ├── terraform.tfvars.example
    ├── vpc.tf
    ├── security_groups.tf
    ├── alb.tf
    ├── asg.tf
    ├── rds.tf
    ├── elasticache.tf
    ├── iam.tf
    ├── outputs.tf
    └── user_data.sh.tpl
```

---

## A aplicação Spring Boot

### pom.xml

Declara as dependências do projeto. Cada starter carrega um conjunto de bibliotecas pré-configuradas:

| Dependência | Para que serve |
|---|---|
| `spring-boot-starter-web` | Servidor HTTP embutido (Tomcat) e suporte a REST |
| `spring-boot-starter-data-jpa` | Integração com banco relacional via Hibernate/JPA |
| `spring-boot-starter-data-redis` | Cliente Redis com pool de conexões (Lettuce) |
| `spring-boot-starter-cache` | Abstração de cache — `@Cacheable`, `@CacheEvict` |
| `spring-boot-starter-actuator` | Endpoints de observabilidade: `/actuator/health`, `/actuator/metrics` |
| `postgresql` | Driver JDBC para PostgreSQL (só em runtime, não em compilação) |
| `lombok` | Gera getters, setters, construtores via anotações — menos código boilerplate |
| `jackson-datatype-jsr310` | Serialização correta de datas Java 8+ (`Instant`, `LocalDate`) em JSON |

### application.yml

Centraliza toda a configuração da aplicação. As variáveis com `${VAR:default}` permitem que o mesmo arquivo funcione local (com os defaults) e na AWS (com as variáveis de ambiente injetadas pelo Docker).

**Seções importantes:**

- **datasource/hikari**: pool de conexões com o banco. `maximum-pool-size: 20` significa que no máximo 20 queries rodam em paralelo por instância.
- **jpa/hibernate**: `ddl-auto: update` cria ou atualiza as tabelas automaticamente ao subir. `batch_size: 50` agrupa inserts em lotes, reduzindo round-trips ao banco.
- **data/redis/lettuce/pool**: pool de conexões com o Redis. `max-active: 16` é o número máximo de conexões simultâneas por instância.
- **cache/redis/time-to-live: 60000**: entradas no cache expiram em 60 segundos (em milissegundos).
- **management**: expõe health, info e metrics via Actuator para monitoramento.

### LoadSimApplication.java

Ponto de entrada da aplicação. A anotação `@EnableCaching` ativa o mecanismo de cache do Spring — sem ela, `@Cacheable` e `@CacheEvict` no service são ignorados.

### model/Product.java

Entidade JPA mapeada para a tabela `products`. Ponto relevante: a estratégia de ID usa `SEQUENCE` com `allocationSize=50`. Isso significa que o Hibernate reserva 50 IDs de uma vez no banco, evitando uma query ao banco a cada insert — importante quando há muitas escritas simultâneas.

### repository/ProductRepository.java

Interface que estende `JpaRepository`. O Spring Data JPA gera automaticamente toda a implementação de CRUD em tempo de compilação — não há código SQL manual.

### service/ProductService.java

Onde o cache é aplicado:

- `@Cacheable("products", key="...")`: antes de executar o método, verifica se já existe um resultado no Redis com aquela chave. Se sim, retorna do cache sem tocar no banco.
- `@CacheEvict(allEntries=true)`: qualquer operação de escrita (create, delete) invalida todo o cache de produtos, garantindo que a próxima leitura busque dados atualizados.
- `@Transactional(readOnly=true)`: informa ao Hibernate que a operação só lê dados, permitindo otimizações internas e uso de réplicas de leitura se configuradas.

### controller/HealthController.java

Endpoint `GET /api/health` que retorna `{"status": "UP"}`. É o alvo do health check do ALB — se retornar 200, a instância permanece no pool de tráfego. Se falhar, o ALB remove a instância automaticamente.

### controller/ProductController.java

API REST de produtos:

| Método | Caminho | Ação |
|---|---|---|
| GET | `/api/products?page=0&size=20` | Lista paginada (cache Redis) |
| GET | `/api/products/{id}` | Busca por ID (cache Redis) |
| POST | `/api/products` | Cria produto (invalida cache) |
| DELETE | `/api/products/{id}` | Remove produto (invalida cache) |

### config/RedisConfig.java

Configura como os objetos Java são armazenados no Redis. Por padrão, o Spring usaria serialização binária Java (não legível). Aqui sobrescrevemos para JSON com Jackson, o que permite inspecionar os valores no Redis com `redis-cli` e garante compatibilidade entre versões da JVM.

O `activateDefaultTyping` adiciona o nome da classe no JSON armazenado — necessário para o Spring saber em qual tipo desserializar o objeto ao ler do cache.

---

## Docker

### Dockerfile

Usa **multi-stage build** — duas fases em um único arquivo:

**Fase 1 (build):** usa a imagem Maven com JDK 21 para compilar o projeto. O truque de copiar o `pom.xml` antes do código-fonte aproveita o cache de camadas do Docker: se o código mudar mas as dependências não, o Maven não baixa nada novamente.

**Fase 2 (runtime):** usa apenas o JRE Alpine (imagem muito menor, sem Maven nem JDK). Copia só o `.jar` gerado. Cria um usuário sem privilégios (`app`) e o usa para rodar o processo — container não roda como root.

Flags da JVM:
- `-XX:+UseContainerSupport`: faz a JVM ler os limites de CPU/memória do cgroup Docker, não do host.
- `-XX:MaxRAMPercentage=75`: usa no máximo 75% da RAM do container para o heap Java, deixando margem para o SO e threads.

### docker-compose.yml

Sobe o ambiente local completo com três serviços: `postgres`, `redis` e `app`. O `depends_on` com `condition: service_healthy` garante que a aplicação só sobe após o banco e o cache estarem prontos para aceitar conexões — evita erros de startup por race condition.

---

## Terraform

O Terraform descreve a infraestrutura como código. Cada arquivo `.tf` agrupa recursos relacionados. Todos os recursos usam o prefixo `var.project` no nome, facilitando identificação no console AWS.

### main.tf

Define a versão mínima do Terraform (`>= 1.7`) e o provider AWS com a versão travada (`~> 5.0` — aceita 5.x mas não 6.x). O provider usa a região definida em `var.aws_region`.

### variables.tf

Declara todas as variáveis configuráveis do projeto. Funciona como a "interface pública" do Terraform — você não precisa editar os `.tf` para customizar, só o `terraform.tfvars`. Variáveis com `sensitive = true` (como `db_password`) não aparecem em logs nem no `terraform output` sem flag explícita.

Principais variáveis:

| Variável | Default | Significado |
|---|---|---|
| `aws_region` | `us-east-1` | Região onde tudo será criado |
| `project` | `loadsim` | Prefixo de nome de todos os recursos |
| `az_count` | `2` | Quantas zonas de disponibilidade usar |
| `instance_type` | `t3.small` | Tipo de EC2 para a aplicação |
| `asg_min/max/desired` | `2/10/2` | Limites do Auto Scaling |
| `scale_out_cpu` | `60` | CPU % que dispara scale-out |
| `db_password` | obrigatória | Senha do RDS — nunca tem default |
| `app_image` | vazio | URI da imagem Docker no ECR |

### vpc.tf

Cria toda a rede privada do projeto.

**VPC** (`10.0.0.0/16`): bloco de endereços IP isolado na AWS. Nada de fora entra sem regra explícita.

**Subnets públicas** (uma por AZ): onde ficam o ALB e os NAT Gateways. Têm rota para o Internet Gateway, então recursos com IP público podem acessar a internet e ser acessados.

**Subnets privadas** (uma por AZ): onde ficam EC2, RDS e ElastiCache. Não têm IP público. Acessam a internet saindo pelo NAT Gateway — útil para baixar imagens Docker ou atualizações.

**Internet Gateway (IGW)**: porta de entrada e saída para a internet nas subnets públicas. Sem ele, nem o ALB seria acessível externamente.

**NAT Gateway** (um por AZ): permite que instâncias privadas iniciem conexões para fora (para baixar imagens, por exemplo) sem serem acessíveis de fora. Fica na subnet pública e tem um IP elástico fixo.

**Route Tables**: tabelas de rotas que dizem "para onde vai o pacote". A pública envia `0.0.0.0/0` para o IGW. Cada privada envia `0.0.0.0/0` para o NAT da mesma AZ — se uma AZ cair, a outra continua funcionando.

### security_groups.tf

Define o firewall de cada recurso. A regra geral é mínimo privilégio — cada componente só aceita tráfego de quem precisa.

```
Internet → ALB (porta 80)
ALB → EC2 (porta 8080)
EC2 → RDS (porta 5432)
EC2 → Redis (porta 6379)
```

Nenhum recurso de dados (RDS, Redis) é acessível diretamente da internet ou do ALB. Se uma instância EC2 for comprometida, o atacante ainda não consegue acessar o banco de outro IP.

### alb.tf

**ALB (Application Load Balancer)**: recebe requisições HTTP na porta 80 e distribui entre as instâncias do Auto Scaling Group. Por ser "Application", entende HTTP/HTTPS e pode rotear por caminho ou header.

**Target Group**: o grupo de instâncias que o ALB conhece como destino. O health check bate em `GET /api/health` a cada 15 segundos. Se uma instância falhar 3 vezes seguidas, é removida do grupo automaticamente. Se passar 2 vezes seguidas, volta.

**Listener**: a regra que diz "requisições na porta 80 vão para este target group". Aqui é simples (forward), mas poderia ter regras de redirecionamento ou resposta fixa.

### asg.tf

**AMI**: busca automaticamente a AMI mais recente do Amazon Linux 2023. Sempre pega a mais atual — sem precisar atualizar o código manualmente quando a Amazon lança patches.

**Launch Template**: o "molde" de cada instância. Define tipo, AMI, security group, IAM profile, se tem IP público (não, nesse caso) e o script de inicialização (`user_data`). O `user_data` é o `user_data.sh.tpl` renderizado com as variáveis do ambiente (endereços do banco e Redis, imagem Docker, etc).

**Auto Scaling Group (ASG)**: mantém entre 2 e 10 instâncias rodando. Usa o Launch Template para criar novas. Registra automaticamente instâncias novas no Target Group do ALB. O `health_check_type = "ELB"` faz o ASG confiar no health check do ALB para decidir se uma instância está boa — não só se a VM está viva.

**`instance_refresh`**: quando o Launch Template muda (por exemplo, nova versão da imagem), o ASG substitui as instâncias gradualmente (rolling update), mantendo pelo menos 50% saudáveis durante a troca. Zero downtime.

**Política de scaling por CPU** (`cpu_tracking`): usa `TargetTrackingScaling` — o ASG adiciona ou remove instâncias automaticamente para manter a CPU média do grupo próxima de 60%. É mais inteligente que um threshold simples: escala suavemente em vez de em degraus.

**Política de scaling por RPS** (`alb_rps`): mesma estratégia, mas baseada em requisições por segundo por instância (target: 1000 req/s/instância). Complementa a política de CPU — uma aplicação I/O-bound pode ter muitas requisições com pouca CPU.

### rds.tf

**Subnet Group**: lista de subnets privadas onde o RDS pode ser colocado. A AWS escolhe em qual ficará a instância primária e a réplica.

**RDS PostgreSQL 16**:
- `multi_az = true`: cria uma réplica síncrona em outra AZ. Se a primária falhar, o failover é automático em ~1 minuto.
- `storage_type = "gp3"`: armazenamento SSD de terceira geração, mais barato que gp2 com performance garantida.
- `storage_encrypted = true`: dados em repouso criptografados.
- `max_allocated_storage = 100`: autoscaling de storage — o disco cresce automaticamente até 100 GB se necessário.
- `backup_retention_period = 7`: 7 dias de backups automáticos diários, permitindo point-in-time recovery.
- `performance_insights_enabled = true`: dashboard da AWS que mostra quais queries estão consumindo mais recursos.
- `skip_final_snapshot = true` e `deletion_protection = false`: configuração para ambiente de estudo — em produção, inverter ambos.

### elasticache.tf

**Subnet Group**: subnets privadas onde o ElastiCache pode ser criado.

**ElastiCache Redis 7.1**: instância única (não cluster) do Redis. Para este projeto de estudo é suficiente. Em produção com alta disponibilidade, usaria `aws_elasticache_replication_group` com réplicas.

- `parameter_group_name = "default.redis7"`: configurações padrão do Redis 7 gerenciadas pela AWS.
- `snapshot_retention_limit = 1`: mantém 1 snapshot diário do Redis — útil para recuperar dados de sessão ou cache em caso de problema.

### iam.tf

**IAM Role**: identidade que as instâncias EC2 assumem. A AWS usa isso no lugar de credenciais estáticas — a instância ganha tokens temporários automaticamente rotacionados.

**`AmazonSSMManagedInstanceCore`**: permite usar o SSM Session Manager para abrir um terminal na instância sem precisar de chave SSH ou porta 22 aberta. Mais seguro e auditável.

**`AmazonEC2ContainerRegistryReadOnly`**: permite que a instância baixe imagens Docker do ECR privado sem precisar de login manual. A `user_data.sh.tpl` usa isso para autenticar automaticamente.

**Instance Profile**: "embrulho" que associa a Role à instância EC2. Uma Role pode existir sem Instance Profile, mas o EC2 só aceita Instance Profile (não Role diretamente).

### iam_ci.tf

Cria um usuário IAM exclusivo para o pipeline do GitHub Actions, com política de mínimo privilégio — só o que o CI precisa, nada mais.

**Permissões concedidas:**

| Ação | Por quê |
|---|---|
| `ecr:GetAuthorizationToken` | Obter token temporário de login no ECR (necessário antes de qualquer push) |
| `ecr:BatchCheckLayerAvailability`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`, `ecr:PutImage` | Push da imagem Docker camada por camada |
| `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage` | Verificar se uma camada já existe antes de reenviar (evita upload redundante) |
| `autoscaling:StartInstanceRefresh` | Disparar a substituição gradual das instâncias com a nova imagem |
| `autoscaling:DescribeInstanceRefreshes` | Consultar o status do refresh em andamento |

O `StartInstanceRefresh` só é permitido no ASG cujas instâncias têm a tag `Name = loadsim-app` — o usuário de CI não pode mexer em outros Auto Scaling Groups da conta.

**Outputs gerados:**
- `ci_access_key_id`: valor para o secret `AWS_ACCESS_KEY_ID` no GitHub.
- `ci_secret_access_key`: valor para o secret `AWS_SECRET_ACCESS_KEY` no GitHub (marcado como `sensitive`).

### outputs.tf

Valores exportados após o `terraform apply`. São referências úteis sem precisar entrar no console AWS:

- `alb_dns`: endereço público do ALB, pronto para usar no k6 ou no browser.
- `rds_endpoint` e `redis_endpoint`: marcados como `sensitive = true` — não aparecem no terminal sem `terraform output -raw <nome>`, evitando vazamento acidental em logs de CI.
- `vpc_id`: útil para referenciar em outros módulos Terraform.

### user_data.sh.tpl

Script Bash executado uma vez quando cada instância EC2 inicia. O Terraform renderiza o template substituindo as variáveis (endereços do banco, Redis, imagem Docker) antes de enviar para a AWS.

O script:
1. Instala o Docker no Amazon Linux 2023 via `dnf`.
2. Habilita e inicia o serviço Docker.
3. Se a imagem for do ECR (URL contém `.dkr.ecr.`), faz login automaticamente usando as credenciais da IAM Role.
4. Sobe o container da aplicação com `docker run`, passando todas as variáveis de ambiente necessárias. `--restart unless-stopped` garante que o container sobe automaticamente se a instância for reiniciada.

---

## Load test com k6

### Como funciona

Cada "virtual user" (VU) executa a função `default` em loop com 100ms de pausa entre iterações. A carga é distribuída aleatoriamente entre três tipos de operação, simulando uso real:

| Probabilidade | Operação | Por quê |
|---|---|---|
| 70% | `GET /api/products` (lista paginada) | Leitura é sempre a maioria em APIs de catálogo |
| 15% | `GET /api/products/{id}` (busca por ID) | Acesso direto a item específico |
| 15% | `POST /api/products` (escrita) | Escrita é minoria, mas invalida o cache |

### Estágios de carga

```
50 VUs  ─ 30s
200 VUs ─ 1m   (ramp-up gradual)
500 VUs ─ 2m
1000 VUs─ 3m   (pico sustentado)
1000 VUs─ 1m   (plateau)
0 VUs   ─ 30s  (ramp-down)
```

### Métricas customizadas

- `write_errors` (Counter): conta quantas escritas falharam. Threshold: menos de 50 erros no total.
- `read_cache_hit_rate` (Rate): proporção de leituras que retornaram 200. Indiretamente indica se o cache está funcionando.
- `write_duration_ms` (Trend): latência das escritas em percentis. Separada da latência geral para comparar writes vs reads.

### Thresholds (critérios de aprovação)

```
p95 de latência < 500ms    — 95% das requisições respondem em menos de 500ms
p99 de latência < 1500ms   — 99% em menos de 1.5s
taxa de erro < 1%           — menos de 1% das requisições falham
write_errors < 50           — menos de 50 erros de escrita no teste inteiro
```

Se qualquer threshold for violado, o k6 termina com exit code não-zero — útil para falhar um pipeline de CI.

---

## Como executar

### Local (Docker)

```bash
cd app
docker-compose up --build
```

Testar:
```bash
curl http://localhost:8080/api/health
curl -X POST http://localhost:8080/api/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Produto Teste","price":99.90,"stock":10}'
curl http://localhost:8080/api/products
```

### Na AWS

**1. Pré-requisitos**
- AWS CLI configurado (`aws configure`)
- Terraform >= 1.7 instalado
- Docker e k6 instalados

**2. Build e push da imagem para o ECR**

```bash
# criar repositório (só na primeira vez)
aws ecr create-repository --repository-name loadsim --region us-east-1

# build
docker build -t loadsim app/

# tag e push
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1
docker tag loadsim:latest $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/loadsim:latest
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ACCOUNT.dkr.ecr.$REGION.amazonaws.com
docker push $ACCOUNT.dkr.ecr.$REGION.amazonaws.com/loadsim:latest
```

**3. Provisionar infraestrutura**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# editar terraform.tfvars: definir db_password e app_image

terraform init
terraform plan
terraform apply
```

**4. Load test apontando para o ALB**

```bash
BASE_URL=http://$(terraform output -raw alb_dns) k6 run ../k6-load-test.js
```

**5. Configurar o CI/CD (uma vez só)**

Após o `terraform apply`, pegue as credenciais do usuário de CI:

```bash
cd terraform
terraform output ci_access_key_id
terraform output -raw ci_secret_access_key
```

Adicione os dois valores como **Secrets** no repositório GitHub:
`Settings → Secrets and variables → Actions → New repository secret`

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | saída de `ci_access_key_id` |
| `AWS_SECRET_ACCESS_KEY` | saída de `ci_secret_access_key` |

A partir daí, qualquer `git push` na branch `main` que altere arquivos dentro de `app/` dispara o pipeline automaticamente.

**6. Destruir (para não gerar custos)**

```bash
terraform destroy
```

---

## Custos estimados (us-east-1)

| Recurso | Especificação | Custo aproximado/mês |
|---|---|---|
| EC2 x2 | t3.small | ~$30 |
| NAT Gateway x2 | — | ~$65 |
| RDS | db.t3.micro, multi-AZ | ~$30 |
| ElastiCache | cache.t3.micro | ~$15 |
| ALB | — | ~$18 |
| **Total** | | **~$160/mês** |

O NAT Gateway é o componente mais caro proporcionalmente. Para reduzir custos em ambientes de desenvolvimento, é possível usar `az_count = 1`.
