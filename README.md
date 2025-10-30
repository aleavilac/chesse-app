![Image](https://github.com/user-attachments/assets/d63eec0c-05d0-4453-82a1-b63472bd5a52)
# 🧀 CHEESE-APP con Terraform + AWS — README

Infraestructura como código que despliega **3 contenedores** (wensleydale, cheddar, stilton) en **EC2** detrás de un **Application Load Balancer (ALB)** dentro de una **VPC** creada con Terraform.  
Incluye buenas prácticas, pruebas y guía de troubleshooting.

---

## 0) Requisitos

- **Windows + VS Code** (terminal integrada).
- **Terraform** instalado (por ej. con Chocolatey):
  ```powershell
  choco install terraform -y
  terraform -version
  ```
- **AWS CLI** instalado:
  ```powershell
  choco install awscli -y
  aws --version
  ```
- **Cuenta AWS** (puede ser AWS Academy).  
  Región usada en este proyecto: **us-east-1**.

---

## 1) Estructura del repositorio

```
chesse-app/
├─ main.tf
├─ variables.tf
├─ outputs.tf
├─ user_data.tpl               # script de arranque (EOL: LF)
├─ terraform.tfvars            # valores locales (NO subir)
├─ terraform.tfvars.example    # ejemplo para el repositorio
├─ README.md
└─ .gitignore
```

### EOL del `user_data.tpl`
Guarda el archivo con fin de línea **LF**, no CRLF.  
En VS Code: barra de estado (abajo derecha) → “CRLF” → cambiar a **LF**.

---

## 2) ¿Qué se crea? (Arquitectura)

- **VPC** `10.0.0.0/16`
- **3 subnets públicas** `/24` (cálculo con `cidrsubnet()`).
- **Internet Gateway + Route Table** pública.
- **Security Groups**:
  - ALB: abre **HTTP:80** a Internet.
  - EC2: permite **HTTP:80 SOLO desde el SG del ALB** y **SSH:22** desde tu IP `/32`.
- **ALB** (HTTP 80) + **Target Group** + **Listener**.
- **3 instancias EC2** (Amazon Linux 2) en subnets/AZ distintas.
  - Arrancan Docker y ejecutan 1 contenedor cada una.
  - **Etiquetas**:
    - `Flavor = wensleydale | cheddar | stilton`
    - `IsPrimary = true` solo en la primera (condicional con `count.index == 0 ? ...`).

> Funciones nativas usadas: `cidrsubnet()` y `element()`.

---

## 3) Variables y `tfvars`

### `variables.tf` (resumen esperado)
```hcl
variable "aws_region"        { type = string }
variable "vpc_cidr"          { type = string }
variable "instance_type"     { type = string }
variable "allowed_ssh_cidr"  { type = string }   # Ej: "201.123.45.67/32"
variable "aws_key_name"      { type = string, default = null } # opcional
variable "cheese_images" {
  type = list(string)
  default = [
    "errm/cheese:wensleydale",
    "errm/cheese:cheddar",
    "errm/cheese:stilton",
  ]
}
```

### `terraform.tfvars.example` (para subir al repo)
```hcl
aws_region       = "us-east-1"
vpc_cidr         = "10.0.0.0/16"
instance_type    = "t2.micro"
allowed_ssh_cidr = "X.X.X.X/32"   # reemplazar por tu IP pública/32
aws_key_name     = ""             # opcional si usarás SSH
# cheese_images  = [...]
```

### Tu `terraform.tfvars` local (NO commitear)
Rellena con tus valores reales. Para tu IP:
```powershell
(Invoke-RestMethod ifconfig.me/ip) + "/32"
```

---

## 4) Credenciales AWS

Seteamos con Access Keys para que Terraform pueda crear recursos.

**¿Dónde se guarda?** En tu home:  
`C:\Users\TU_USUARIO\.aws\credentials` y `...\config`.

### Crear perfil `cheese-lab`
```powershell
aws configure --profile cheese-lab
# AWS Access Key ID: AKIA...
# AWS Secret Access Key: ...
# Default region name: us-east-1
# Default output format: json
```

Verifica:
```powershell
aws sts get-caller-identity --profile cheese-lab
```

### Provider en `main.tf`
```hcl
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = "cheese-lab"   # usa tu perfil del CLI
}
```

> Alternativa: `setx AWS_PROFILE cheese-lab` y deja el `provider` sin `profile`.

---

## 5) Inicializar y desplegar

En la carpeta del proyecto:

```powershell
terraform init
terraform fmt
terraform validate
terraform plan -var-file="terraform.tfvars" -out=tfplan
terraform apply tfplan
```

Al finalizar:
```powershell
terraform output alb_dns_name
# Ej: cheese-alb-xxxxxx.us-east-1.elb.amazonaws.com
```

Abre en el navegador y **refresca**; verás los sabores.  
*Nota:* Los navegadores reutilizan conexiones; si quieres ver rotación más evidente, mira la sección 7.
<img width="2879" height="878" alt="cheddar" src="https://github.com/user-attachments/assets/30b66799-14c3-46be-979d-77da4f00830e" />

<img width="2876" height="1009" alt="wensleydale" src="https://github.com/user-attachments/assets/398dd802-94af-416b-8a8f-e14536263294" />

<img width="2871" height="1110" alt="Image" src="https://github.com/user-attachments/assets/b3700478-086d-46d3-a2bf-22e2bc432c21" />
---

## 6) Comprobaciones útiles

### A) Targets HEALTHY
Consola AWS → EC2 → **Target Groups** → `cheese-tg` → **Targets** (3 en healthy).

CLI:
```powershell
$tg = (aws elbv2 describe-target-groups --names cheese-tg --query "TargetGroups[0].TargetGroupArn" --output text --profile cheese-lab)
aws elbv2 describe-target-health --target-group-arn $tg --profile cheese-lab --output table
```

### B) Etiquetas (IsPrimary / Flavor)
```powershell
aws ec2 describe-instances `
  --filters "Name=tag:Name,Values=cheese-*" `
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Flavor:Tags[?Key=='Flavor']|[0].Value,IsPrimary:Tags[?Key=='IsPrimary']|[0].Value}" `
  --output table --profile cheese-lab
```

---

## 7) Ver 3 quesos con reparto “equitativo” en pruebas

El ALB balancea por **conexión**; el navegador usa **keep-alive/HTTP2**. Para evidenciar la rotación:

### Opción rápida (PowerShell con `curl.exe`)
```powershell
$alb = "http://$(terraform output -raw alb_dns_name)"
1..20 | % {
  curl.exe -s --no-keepalive -H "Cache-Control: no-cache" $alb |
    Select-String -Pattern "wensleydale|cheddar|stilton"
}
```
Para contar:
```powershell
$counts = @{wensleydale=0; cheddar=0; stilton=0}
1..90 | % {
  $html = curl.exe -s --no-keepalive -H "Cache-Control: no-cache" $alb
  if ($html -match "wensleydale") {$counts.wensleydale++}
  elseif ($html -match "cheddar") {$counts.cheddar++}
  elseif ($html -match "stilton") {$counts.stilton++}
}
$counts
```

### Ajustes opcionales para la demo (en `aws_lb`)
```hcl
resource "aws_lb" "alb" {
  # ...
  enable_http2 = false   # evita multiplexación del browser
  idle_timeout = 1       # cierra conexiones ociosas rápido (solo demo)
}
```

### Algoritmo del Target Group
```hcl
resource "aws_lb_target_group" "tg" {
  # ...
  load_balancing_algorithm_type = "round_robin" # default
  # Alternativa si una instancia responde más lento:
  # load_balancing_algorithm_type = "least_outstanding_requests"

  stickiness { type = "lb_cookie", enabled = false }
}
```

*(Opcional) limpieza local:*
```powershell
Remove-Item -Recurse -Force .terraform
Remove-Item .terraform.lock.hcl
Remove-Item *.tfstate*
```

---

## 8) Buenas prácticas

- **Nunca** subas claves ni `terraform.tfvars` (usa `.gitignore`).
- Usa **perfiles** del AWS CLI, no pongas `access_key/secret_key` en `.tf`.
- Etiquetas claras (`Name`, `Flavor`, `IsPrimary`) para trazabilidad.
- Para producción, revierte `idle_timeout` a `60` y deja `enable_http2 = true`.

### `.gitignore` sugerido
```
.terraform/
*.tfstate
*.tfstate.*
*.tfvars
.crash
.terraform.lock.hcl
```

---
