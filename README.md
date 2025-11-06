![Image](https://github.com/user-attachments/assets/d63eec0c-05d0-4453-82a1-b63472bd5a52)
# 🧀 Cheese Factory App (Refactorizado con Módulos)

Infraestructura como código que despliega **3 contenedores** (wensleydale, cheddar, stilton) en **EC2** detrás de un **Application Load Balancer (ALB)** dentro de una **VPC** creada con Terraform, usando una arquitectura profesional, modular y con estado remoto en S3.

Cumple con todos los requisitos de la Actividad 2.1, incluyendo el uso de módulos públicos para la VPC y el backend S3, y lógica condicional.

## 🏗️ Estructura del Proyecto

Este proyecto se divide en dos fases/carpetas:
Incluye buenas prácticas, pruebas y guía de troubleshooting.
```
chesse-app/ (Carpeta raíz del proyecto)
│
├─ 1-s3-backend-bootstrap/       # 🚀 FASE 1: Crea el backend S3
│  ├─ main.tf                   # Define el bucket S3 (módulo) y la tabla DynamoDB
│  ├─ variables.tf              # Declara la variable 's3_bucket_name'
│  ├─ outputs.tf                # Devuelve el nombre del bucket y la tabla
│  ├─ terraform.tfvars          # (Local) Asigna el nombre a 's3_bucket_name' (Ignorado por Git)
│  └─ terraform.tfvars.example  # Archivo de ejemplo
│
├─ 2-chesse-app-refactored/      # 🏗️ FASE 2: Despliega la aplicación
│  ├─ main.tf                   # Define el backend "s3", módulo VPC, ALB, EC2, SGs
│  ├─ variables.tf              # Declara 'environment', 'allowed_ssh_cidr', etc.
│  ├─ outputs.tf                # Devuelve la URL del ALB
│  ├─ user_data.tpl             # Script de arranque (¡Formato LF!)
│  ├─ terraform.tfvars          # (Local) Asigna tu IP, key_name, etc. (Ignorado por Git)
│  └─ terraform.tfvars.example  # Archivo de ejemplo
│
├─ .gitattributes                # (Nuevo) Fuerza el formato LF para .tpl
├─ .gitignore                    # (Actualizado) Ignora **/.terraform/ y **/*.tfvars
└─ README.md                     # (Actualizado) Explica el nuevo flujo de 2 Fases

```
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

## 📋 Prerrequisitos

Para desplegar este proyecto, necesitará:

1.  **Terraform:** Instalado localmente.
2.  **AWS CLI:** Instalada localmente.
3.  **Credenciales de AWS:** Una Access Key ID y Secret Access Key con permisos de administrador.
4.  **Par de Llaves EC2:** El **nombre** de un Par de Llaves (Key Pair) existente en la región `us-east-1`.
5.  **Su IP Pública:** Para añadirla a la regla de SSH.

---

## ⚠️ ¡Advertencia Importante! (CRLF vs. LF)

Este proyecto usa un script `user_data.tpl` que se ejecuta en **Linux (Amazon Linux 2)**.
* Los scripts de Linux **requieren** finales de línea **LF**.
* Windows usa finales de línea **CRLF**.

Si el proyecto se clona en Windows, Git puede corromper este archivo. Si el script se aplica con formato CRLF, **el despliegue fallará** (las instancias EC2 quedarán como `unhealthy`).

**Solución:**
Este repositorio incluye un archivo `.gitattributes` que instruye a Git para forzar el formato `LF`.

Si, por alguna razón, el despliegue falla (las instancias quedan `unhealthy`), por favor verifique en su editor (ej. VS Code) que el archivo `2-chesse-app-refactored/user_data.tpl` muestre **"LF"** en la barra de estado azul de abajo a la derecha antes de volver a aplicar.


---

## 🚀 Flujo de Despliegue

### Fase 1: Desplegar el Backend S3

Esta fase crea el bucket S3 y la tabla DynamoDB para el estado remoto.

1.  **Configurar Credenciales de AWS:**
    * Este proyecto está configurado para usar el perfil `default`.
    * Ejecute `aws configure` para guardar sus credenciales en el perfil `default`.
    ```bash
    aws configure
    ```
    (Ingrese su Key ID, Secret Key, `us-east-1` y `json`).

2.  **Navegar a la Carpeta 1:**
    ```bash
    cd 1.s3-backend-bootstrap
    ```

3.  **Crear Archivo de Variables:**
    * Copie `terraform.tfvars.example` a un nuevo archivo llamado `terraform.tfvars`.
    * Edite `terraform.tfvars` y asigne un **nombre globalmente único** al bucket S3.
    ```hcl
    # 1.s3-backend-bootstrap/terraform.tfvars
    
    s3_bucket_name = "tf-state-profesor-nombre-unico-2025"
    ```

4.  **Inicializar y Aplicar:**
    ```bash
    terraform init
    terraform apply -auto-approve
    ```

5.  **¡Anote las Salidas!**
    * Al finalizar, copie los valores `s3_bucket_name` y `dynamodb_table_name` de la terminal. Los necesitará en la siguiente fase.

---

### Fase 2: Desplegar la Aplicación (Cheese App)

Esta fase despliega la VPC, ALB e instancias EC2.

1.  **Navegar a la Carpeta 2:**
    ```bash
    cd ..\2.chesse-app-refactored
    ```
    (O `cd ../2.chesse-app-refactored` en Mac/Linux).

2.  **Conectar el Backend Remoto (Paso Manual):**
    * Abra el archivo `2.chesse-app-refactored/main.tf`.
    * Busque el bloque `backend "s3" { ... }` al principio.
    * **Pegue los valores** que anotó en la Fase 1:
    ```terraform
    backend "s3" {
      bucket         = "tf-state-profesor-nombre-unico-2025" # <- SU BUCKET
      key            = "cheese-app/terraform.tfstate"
      region         = "us-east-1"
      dynamodb_table = "terraform-cheese-lock" # <- SU TABLA
      encrypt        = true
    }
    ```

3.  **Crear Archivo de Variables:**
    * Copie `terraform.tfvars.example` a un nuevo archivo `terraform.tfvars` en esta carpeta.
    * Edítelo y rellene su **IP pública** (con `/32`) y el **nombre de su Key Pair** existente:
    ```hcl
    # 2.chesse-app-refactored/terraform.tfvars
    
    environment      = "dev"
    allowed_ssh_cidr = "SU.IP.PUBLICA.AQUI/32"
    aws_key_name     = "su-keypair-existente"
    ```

4.  **Inicializar y Aplicar:**
    ```bash
    terraform init
    ```
    *(Verá un mensaje que dice "Successfully configured the backend 's3'".)*
    
    ```bash
    terraform apply -auto-approve
    ```
    *(Esto tardará de 3 a 5 minutos, principalmente por el NAT Gateway).*

---

## 🧪 Comprobación

1.  Una vez que `apply` termine, copie la salida `alb_dns_name` de la terminal.
2.  **Espere 1-2 minutos** para que las instancias EC2 ejecuten el script `user_data` (instalación de Docker) y pasen los chequeos de salud.
3.  Pegue la URL en su navegador.
4.  Refresque la página (`F5`) varias veces. Verá cómo la página rota entre los quesos `wensleydale`, `cheddar` y `stilton`.

---

## 🧹 Limpieza (Destroy)

Para borrar todos los recursos y no generar costos, ejecute `destroy` en **orden inverso**:

1.  **Destruir la Aplicación (Fase 2):**
    ```bash
    cd 2.chesse-app-refactored
    terraform destroy -auto-approve
    ```
2.  **Destruir el Backend (Fase 1):**
    ```bash
    cd ..\1.s3-backend-bootstrap
    terraform destroy -auto-approve
    ```


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
