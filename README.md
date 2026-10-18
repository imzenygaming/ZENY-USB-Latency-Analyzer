# ZENY+ USB LATENCY ANALYZER

Herramienta de análisis de topología USB para Windows enfocada en jugadores que quieren entender cómo está conectado su control al sistema.

**ZENY+ USB Latency Analyzer** analiza la ruta USB de tus dispositivos, detecta hubs intermedios y te ayuda a comparar diferentes puertos USB de tu PC.

---

## 🎮 ¿Qué hace ZENY+ USB Latency Analyzer?

El programa analiza la estructura USB de Windows para mostrar:

- Controladores USB Host detectados.
- Controles y dispositivos gaming conectados.
- Hubs USB intermedios.
- Ruta USB detectada por Windows.
- Cantidad de hubs entre el dispositivo y el USB Host Controller.
- Comparación entre diferentes conexiones.
- Recomendación de topología para tu control.
- Árbol visual de la conexión USB.

---

## 🔌 ¿Por qué analizar los puertos USB?

No todos los dispositivos USB necesariamente siguen la misma ruta dentro de una PC.

Una conexión puede ser:

```text
CONTROL
   |
   +---- USB HOST
```

Mientras otra puede tener hubs intermedios:

```text
CONTROL
   |
   +---- USB HUB
           |
           +---- USB HUB
                   |
                   +---- USB HOST
```

ZENY+ identifica estas diferencias para ayudarte a encontrar una **ruta USB más simple** para tu control.

---

## 🟢 Clasificación de topología

### 0 HUBS — Mejor candidato

```text
DEVICE ---> USB HOST
```

No se detectaron hubs USB adicionales entre el dispositivo y el USB Host Controller.

### 1 HUB — Hub intermedio

```text
DEVICE ---> HUB ---> USB HOST
```

Se detectó un hub USB intermedio.

### 2+ HUBS — Múltiples hubs

```text
DEVICE ---> HUB ---> HUB ---> USB HOST
```

Se detectaron múltiples hubs USB intermedios.

---

## ⚠️ Importante

**ZENY+ USB Latency Analyzer no mide directamente el input lag en milisegundos.**

La herramienta analiza la **topología USB** reportada por Windows.

Tener menos hubs significa que el dispositivo tiene una ruta USB más simple, pero esto **no garantiza automáticamente una reducción del input lag**.

Por esta razón, ZENY+ utiliza términos como:

> **BEST TOPOLOGY CANDIDATE**

en lugar de afirmar que un puerto tiene una latencia específica.

---

## 🖥️ Requisitos

- Windows 10 o Windows 11
- Windows PowerShell
- Un dispositivo USB conectado
- Recomendado: ejecutar PowerShell como administrador

---

## 🚀 Cómo usarlo

### 1. Descarga el script

Descarga:

```text
ZENY-USB-Latency-Analyzer.ps1
```

desde este repositorio.

### 2. Abre Windows PowerShell

Para obtener mejores resultados, puedes abrir **Windows PowerShell como administrador**.

### 3. Ejecuta el script

Ejecuta:

```powershell
.\ZENY-USB-Latency-Analyzer.ps1
```

Si Windows bloquea la ejecución del script debido a la política de PowerShell, revisa la configuración de ejecución de scripts de tu sistema antes de modificarla.

---

## 🎮 Cómo probar tu control

Conecta tu control y ejecuta el análisis.

ZENY+ intentará identificar automáticamente controles como:

- GameSir
- Xbox Controller
- Gamepads compatibles
- DualSense
- DualShock
- Joysticks
- Otros dispositivos gaming detectables por Windows

Después del análisis verás la conexión actual y la cantidad de hubs detectados.

Por ejemplo:

```text
ZENY+ GAMING RECOMMENDATION

CONTROLLER
Xbox 360 Controller for Windows

CURRENT CONNECTION
USB(5)

HUBS DETECTADOS: 0

[ BEST TOPOLOGY CANDIDATE ]

POR QUE?

No se detectaron hubs USB adicionales entre
tu control y el USB Host Controller.
```

---

## 🔄 Comparar diferentes puertos USB

Una de las funciones principales de ZENY+ es ayudarte a comparar diferentes conexiones.

Después del primer análisis:

1. Desconecta tu control.
2. Conéctalo en otro puerto USB.
3. Espera a que Windows reconozca el control.
4. Presiona `R` para volver a analizar.
5. Compara la nueva topología con la anterior.

ZENY+ puede indicar si la nueva conexión tiene:

```text
[ MEJOR CONEXION ]

La conexion actual tiene menos hubs intermedios.
```

o:

```text
[ CONEXION ANTERIOR PREFERIBLE ]

La conexion anterior tenia menos hubs intermedios.
```

---

## 🧠 ¿Qué significa USB(5), USB(8), etc.?

Durante el análisis puedes encontrar rutas como:

```text
PCIROOT(0)#PCI(1400)#USBROOT(0)#USB(5)
```

`USB(5)` forma parte de la **ruta lógica reportada por Windows**.

No significa necesariamente que sea el puerto físico número 5 de tu computadora o motherboard.

La forma más sencilla de identificar diferentes conexiones es cambiar físicamente el control de puerto y volver a ejecutar el análisis.

---

## 🔍 Ejemplo de árbol USB

ZENY+ puede mostrar una estructura similar a:

```text
[USB HOST]
Intel(R) USB 3.20 eXtensible Host Controller
   |
   +-- USB(5)
   |    |
   |    +-- Xbox 360 Controller for Windows
   |         [0 HUBS] BEST TOPOLOGY
   |
   +-- USB(8)
        |
        +-- Generic USB Hub
             |
             +-- Generic USB Hub
                  |
                  +-- HID-compliant system controller
                       [2 HUBS] MULTIPLE HUBS
```

Esto permite visualizar más fácilmente cómo Windows está reportando la conexión de los dispositivos USB.

---

## 🛡️ Seguridad

El proyecto es PowerShell y el código fuente está disponible públicamente en este repositorio.

Recomendamos revisar el contenido del archivo `.ps1` antes de ejecutarlo, especialmente cuando se descargan scripts desde Internet.

ZENY+ no necesita modificar el hardware de tu computadora para realizar el análisis de topología.

---

## 🧪 Estado del proyecto

ZENY+ USB Latency Analyzer está en desarrollo.

La detección puede variar dependiendo de:

- Motherboard
- Chipset
- Controlador USB
- Drivers
- Dispositivo conectado
- Forma en que Windows expone la topología USB

Los resultados deben utilizarse como información de diagnóstico y comparación, no como una medición absoluta de latencia.

---

## 🎯 Objetivo de ZENY+

El objetivo es hacer que información USB que normalmente es difícil de interpretar sea más fácil de entender para jugadores.

En lugar de mostrar solamente IDs y propiedades técnicas, ZENY+ intenta convertir la información en una representación visual y una recomendación fácil de interpretar.

---

## 👤 Creado por

**ZENY+ / imzenygaming**

Herramientas y optimización para gaming.

---

## 📄 Disclaimer

Este proyecto no está afiliado con Microsoft, Intel, AMD, GameSir, Xbox, Sony ni otros fabricantes mencionados.

Los nombres de productos y marcas pertenecen a sus respectivos propietarios.

Los resultados proporcionados por ZENY+ USB Latency Analyzer dependen de la información que Windows expone sobre el hardware y no constituyen una medición física directa de latencia.
