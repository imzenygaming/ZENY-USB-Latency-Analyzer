& {
$ErrorActionPreference = "SilentlyContinue"

function ZText($Text="", $Color="Gray") {
    Write-Host $Text -ForegroundColor $Color
}

function ZHeader($Text) {
    ZText ""
    ZText ("=" * 68) DarkCyan
    ZText ("  " + $Text) Cyan
    ZText ("=" * 68) DarkCyan
}

function ZProp($Id,$Key) {
    if (-not $Id) { return $null }

    try {
        return (Get-PnpDeviceProperty `
            -InstanceId $Id `
            -KeyName $Key `
            -ErrorAction Stop).Data
    }
    catch {
        return $null
    }
}

function ZProgress($Percent,$Text) {

    $Percent = [Math]::Max(
        0,
        [Math]::Min(100,[int]$Percent)
    )

    $Width = 32

    $Filled = [Math]::Floor(
        ($Percent / 100) * $Width
    )

    $Empty = $Width - $Filled

    $Bar = ("#" * $Filled) + ("-" * $Empty)

    Write-Host "`r  [" -NoNewline -ForegroundColor DarkGray
    Write-Host $Bar -NoNewline -ForegroundColor Yellow
    Write-Host "] " -NoNewline -ForegroundColor DarkGray
    Write-Host ("{0,3}%" -f $Percent) -NoNewline -ForegroundColor Yellow
    Write-Host "  $Text          " -NoNewline -ForegroundColor Gray

    if ($Percent -ge 100) {
        Write-Host ""
    }
}

function Get-PortLabel($Path) {

    if (-not $Path) {
        return "UNKNOWN"
    }

    $matches = [regex]::Matches(
        $Path,
        'USB\((\d+)\)'
    )

    if ($matches.Count -gt 0) {

        return "USB(" +
            $matches[$matches.Count-1].Groups[1].Value +
            ")"
    }

    return "UNKNOWN"
}

function Start-ZenyScan {

    Clear-Host

    # ==========================================================
    # ZENY+ TITLE
    # ==========================================================

    ZHeader "ZENY+ USB LATENCY ANALYZER"

    ZText "        GAMING USB TOPOLOGY SCANNER" Green
    ZText "        Analisis automatico de conexiones USB" White
    ZText ""
    ZText "  Analizando controladores, hubs y dispositivos..." Yellow
    ZText ""

    ZProgress 5 "Preparando Windows PnP"

    try {

        $devices = @(
            Get-PnpDevice `
                -PresentOnly `
                -ErrorAction Stop
        )

        $allDevices = @(
            Get-PnpDevice `
                -ErrorAction Stop
        )

        $controllers = @(
            Get-CimInstance `
                Win32_USBController `
                -ErrorAction Stop
        )

    }
    catch {

        Write-Host ""

        ZText "  ERROR: No se pudieron leer los dispositivos USB." Red
        ZText "  Ejecuta Windows PowerShell como Administrador." Yellow

        return $null
    }

    ZProgress 15 "Dispositivos encontrados"

    # ==========================================================
    # DEVICE INDEX
    # ==========================================================

    $index = @{}

    foreach ($d in $allDevices) {

        if ($d.InstanceId) {

            $index[$d.InstanceId] = $d

        }
    }

    ZProgress 25 "Creando mapa USB"

    # ==========================================================
    # TRACE USB ROUTE
    # ==========================================================

    function TraceUSB($StartId) {

        $current = $StartId

        $visited = @{}

        $hubs = 0

        $hubNames = @()

        $usbHostName = $null

        $usbAnchor = $null

        $complete = $false

        for ($i=0; $i -lt 45; $i++) {

            if (-not $current) {
                break
            }

            if ($visited.ContainsKey($current)) {
                break
            }

            $visited[$current] = $true

            $node = $index[$current]

            $name = ""

            if ($node) {
                $name = [string]$node.FriendlyName
            }

            $service = [string](
                ZProp `
                    $current `
                    "DEVPKEY_Device_Service"
            )

            if ($current -match '^USB\\VID_') {

                $usbAnchor = $current

            }

            # USB HOST CONTROLLER

            if (
                $service -match '^(USBXHCI|USBEHCI|USBOHCI|USBUHCI)$' -or
                $name -match 'Host Controller|eXtensible Host Controller'
            ) {

                if ($name) {

                    $usbHostName = $name

                }
                else {

                    $usbHostName = $service

                }

                $complete = $true

                break
            }

            # USB HUB

            $isHub = (

                $service -match '^USBHUB3?$' -or

                $name -match
                'Generic USB Hub|Generic SuperSpeed USB Hub'

            )

            # ROOT HUB IS NOT COUNTED AS AN EXTRA HUB

            $isRoot = (

                $name -match 'Root Hub' -or

                $current -match '^USB\\ROOT_HUB'

            )

            if ($isHub -and -not $isRoot) {

                $hubs++

                if ($name) {

                    $hubNames += $name

                }
                else {

                    $hubNames += "USB Hub"

                }
            }

            $parent = ZProp `
                $current `
                "DEVPKEY_Device_Parent"

            if ($parent -is [array]) {

                $parent = $parent[0]

            }

            $current = [string]$parent
        }

        return [PSCustomObject]@{

            Hubs        = $hubs

            HubNames    = $hubNames

            USBHostName = $usbHostName

            Anchor      = $usbAnchor

            Complete    = $complete

        }
    }

    # ==========================================================
    # USB HOST CONTROLLERS
    # ==========================================================

    ZHeader "USB HOST CONTROLLERS"

    foreach ($controller in $controllers) {

        ZText ""

        ZText "  [USB HOST]" Cyan

        ZText "  $($controller.Name)" White

        ZText `
            "  Manufacturer: $($controller.Manufacturer)" `
            Gray

        ZText `
            "  Hardware: $($controller.DeviceID)" `
            DarkGray
    }

    # ==========================================================
    # CONNECTION QUALITY
    # ==========================================================

    ZHeader "USB CONNECTION QUALITY"

    ZText `
        "  [ 0 HUBS  ]  DEVICE ---> USB HOST" `
        Green

    ZText `
        "              Mejor topologia detectada" `
        Green

    ZText ""

    ZText `
        "  [ 1 HUB   ]  DEVICE ---> HUB ---> USB HOST" `
        Yellow

    ZText `
        "              Un hub intermedio" `
        Yellow

    ZText ""

    ZText `
        "  [ 2+ HUBS ]  DEVICE ---> HUB ---> HUB ---> USB HOST" `
        Red

    ZText `
        "              Multiples hubs intermedios" `
        Red

    ZText ""

    ZText `
        "  NOTA: Esta clasificacion analiza topologia." `
        DarkGray

    ZText `
        "  No es una medicion directa de input lag." `
        DarkGray

    # ==========================================================
    # SCAN USB DEVICES
    # ==========================================================

    ZHeader "ESCANEANDO DISPOSITIVOS USB"

    $candidates = @(

        $devices |

        Where-Object {

            $_.Class -in @(

                "USB",
                "HIDClass",
                "Xbox",
                "XnaComposite",
                "Mouse",
                "Keyboard"

            )

        }

    )

    $rawResults = @()

    $count = $candidates.Count

    $position = 0

    foreach ($device in $candidates) {

        $position++

        $scanPercent = 30

        if ($count -gt 0) {

            $scanPercent = 30 +

                [Math]::Floor(

                    ($position / $count) * 60

                )
        }

        ZProgress `
            $scanPercent `
            "Leyendo USB $position de $count"

        $name = [string]$device.FriendlyName

        if (-not $name) {
            continue
        }

        if ($name -match 'Root Hub|Host Controller') {
            continue
        }

        $route = TraceUSB $device.InstanceId

        if (
            -not $route.Anchor -and
            $device.InstanceId -notmatch '^USB\\'
        ) {

            continue

        }

        $locationId = $device.InstanceId

        if ($route.Anchor) {

            $locationId = $route.Anchor

        }

        $location = ZProp `
            $locationId `
            "DEVPKEY_Device_LocationPaths"

        if ($location) {

            $path = [string](
                @($location)[0]
            )

        }
        else {

            $path = "No disponible"

        }

        $priority = 10

        # GAMING CONTROLLERS

        if (
            $name -match
            'GameSir|Tarantula|Xbox|Controller|Gamepad|DualSense|DualShock|Joystick'
        ) {

            $priority = 100

        }

        # OTHER GAMING PERIPHERALS

        elseif (
            $name -match
            'Keyboard|Mouse|Headset|Camera|Microphone'
        ) {

            $priority = 60

        }

        # GENERIC HID

        elseif (
            $name -match
            'USB Input Device|USB Composite Device|HID-compliant'
        ) {

            $priority = 20

        }

        if ($route.Anchor) {

            $group = $route.Anchor

        }
        else {

            $group = $device.InstanceId

        }

        $rawResults += [PSCustomObject]@{

            Name        = $name

            Group       = $group

            Hubs        = $route.Hubs

            HubNames    = $route.HubNames

            HostName    = $route.USBHostName

            Complete    = $route.Complete

            Path        = $path

            Port        = Get-PortLabel $path

            Priority    = $priority

        }
    }

    ZProgress 95 "Organizando topologia"

    # ==========================================================
    # REMOVE DUPLICATE INTERFACES
    # ==========================================================

    $results = @(

        $rawResults |

        Group-Object Group |

        ForEach-Object {

            $_.Group |

            Sort-Object `
                Priority `
                -Descending |

            Select-Object -First 1

        } |

        Sort-Object Path,Name

    )

    ZProgress 100 "ANALISIS COMPLETADO"

    Start-Sleep -Milliseconds 300

    # ==========================================================
    # USB TREE
    # ==========================================================

    ZHeader "USB CONNECTION TREE"

    foreach ($controller in $controllers) {

        ZText ""

        ZText `
            "  [USB HOST] $($controller.Name)" `
            Cyan
    }

    foreach ($r in $results) {

        ZText ""

        ZText "       |" DarkGray

        ZText `
            "       +-- $($r.Port)" `
            White

        ZText "           |" DarkGray

        if ($r.Hubs -gt 0) {

            $hubNumber = 0

            foreach ($hub in $r.HubNames) {

                $hubNumber++

                if ($r.Hubs -eq 1) {

                    ZText `
                        "           +-- [HUB $hubNumber] $hub" `
                        Yellow

                }
                else {

                    ZText `
                        "           +-- [HUB $hubNumber] $hub" `
                        Red

                }

                ZText `
                    "               |" `
                    DarkGray
            }
        }

        ZText `
            "           +-- $($r.Name)" `
            White

        if (-not $r.Complete) {

            ZText `
                "               [UNKNOWN] Ruta no verificada" `
                DarkYellow

        }

        elseif ($r.Hubs -eq 0) {

            ZText `
                "               [0 HUBS] BEST TOPOLOGY" `
                Green

        }

        elseif ($r.Hubs -eq 1) {

            ZText `
                "               [1 HUB] INTERMEDIATE HUB" `
                Yellow

        }

        else {

            ZText `
                "               [$($r.Hubs) HUBS] MULTIPLE HUBS" `
                Red

        }

        ZText `
            "               $($r.Path)" `
            DarkGray
    }

    # ==========================================================
    # GAMING RECOMMENDATION
    # ==========================================================

    ZHeader "ZENY+ GAMING RECOMMENDATION"

    $gamepads = @(

        $results |

        Where-Object {

            $_.Name -match
            'GameSir|Tarantula|Xbox.*Controller|Wireless Controller|DualSense|DualShock|Gamepad|Joystick'

        }

    )

    if ($gamepads.Count -eq 0) {

        ZText ""

        ZText `
            "  No se identifico automaticamente un control." `
            Yellow

        ZText `
            "  Algunos controles aparecen como dispositivos HID genericos." `
            Gray

    }
    else {

        foreach ($pad in $gamepads) {

            ZText ""

            ZText "  CONTROLLER" Cyan

            ZText `
                "  $($pad.Name)" `
                White

            ZText ""

            ZText "  CURRENT CONNECTION" Cyan

            ZText `
                "  $($pad.Port)" `
                White

            ZText `
                "  $($pad.Path)" `
                DarkGray

            ZText ""

            ZText `
                "  HUBS DETECTADOS: $($pad.Hubs)" `
                Cyan

            if (-not $pad.Complete) {

                ZText ""

                ZText `
                    "  [ RUTA NO VERIFICADA ]" `
                    Yellow

                ZText ""

                ZText `
                    "  Windows no mostro toda la cadena USB." `
                    Gray

            }

            elseif ($pad.Hubs -eq 0) {

                ZText ""

                ZText `
                    "  [ BEST TOPOLOGY CANDIDATE ]" `
                    Green

                ZText ""

                ZText "  POR QUE?" Cyan

                ZText `
                    "  No se detectaron hubs USB adicionales entre" `
                    White

                ZText `
                    "  tu control y el USB Host Controller." `
                    White

                ZText ""

                ZText `
                    "  Esta es una buena conexion para gaming." `
                    Green

            }

            elseif ($pad.Hubs -eq 1) {

                ZText ""

                ZText `
                    "  [ 1 HUB INTERMEDIO ]" `
                    Yellow

                ZText ""

                ZText "  POR QUE?" Cyan

                ZText `
                    "  Tu control pasa por un hub USB adicional." `
                    White

                ZText `
                    "  Una ruta con 0 hubs puede ser mejor candidata." `
                    Yellow

            }

            else {

                ZText ""

                ZText `
                    "  [ $($pad.Hubs) HUBS INTERMEDIOS ]" `
                    Red

                ZText ""

                ZText "  POR QUE?" Cyan

                ZText `
                    "  Tu control pasa por multiples hubs USB." `
                    White

                ZText `
                    "  Recomendamos probar otra conexion con menos hubs." `
                    Yellow

            }
        }
    }

    # ==========================================================
    # RESULT
    # ==========================================================

    ZHeader "ZENY+ RESULTADO"

    $verified = @(

        $results |

        Where-Object Complete

    )

    if ($verified.Count -gt 0) {

        $minimumHubs = (

            $verified |

            Measure-Object `
                Hubs `
                -Minimum

        ).Minimum

        ZText ""

        ZText `
            "  Mejor topologia encontrada:" `
            Cyan

        ZText `
            "  $minimumHubs HUB(S) INTERMEDIOS" `
            Green

        $bestPaths = @(

            $verified |

            Where-Object {

                $_.Hubs -eq $minimumHubs

            } |

            Select-Object -First 5

        )

        ZText ""

        ZText `
            "  Conexiones detectadas con esta topologia:" `
            White

        foreach ($best in $bestPaths) {

            ZText `
                "    > $($best.Port) - $($best.Name)" `
                Green

        }
    }

    ZText ""

    ZText "  IMPORTANTE" Yellow

    ZText `
        "  Menos hubs significa una ruta USB mas simple." `
        White

    ZText `
        "  No significa automaticamente menos input lag." `
        White

    ZText `
        "  Este analisis no mide latencia en milisegundos." `
        DarkGray

    return [PSCustomObject]@{

        Results  = $results

        Gamepads = $gamepads

    }
}

# ==============================================================
# ZENY+ RESCAN SYSTEM
# ==============================================================

$previousGamepad = $null

$running = $true

while ($running) {

    $scan = Start-ZenyScan

    if (
        $scan -and
        $scan.Gamepads.Count -gt 0
    ) {

        $currentPad =

            $scan.Gamepads |

            Select-Object -First 1

        if ($previousGamepad) {

            ZHeader "COMPARACION CON EL ESCANEO ANTERIOR"

            ZText ""

            ZText `
                "  ANTERIOR: $($previousGamepad.Port)" `
                Gray

            ZText `
                "  Hubs: $($previousGamepad.Hubs)" `
                Gray

            ZText ""

            ZText `
                "  ACTUAL:   $($currentPad.Port)" `
                White

            ZText `
                "  Hubs: $($currentPad.Hubs)" `
                White

            ZText ""

            if (
                $currentPad.Hubs -lt
                $previousGamepad.Hubs
            ) {

                ZText `
                    "  [ MEJOR CONEXION ]" `
                    Green

                ZText `
                    "  La conexion actual tiene menos hubs intermedios." `
                    Green

            }

            elseif (
                $currentPad.Hubs -gt
                $previousGamepad.Hubs
            ) {

                ZText `
                    "  [ CONEXION ANTERIOR PREFERIBLE ]" `
                    Yellow

                ZText `
                    "  La conexion anterior tenia menos hubs intermedios." `
                    Yellow

            }

            else {

                ZText `
                    "  [ MISMA CANTIDAD DE HUBS ]" `
                    Cyan

                ZText `
                    "  Ambas conexiones tienen una topologia similar." `
                    White

            }
        }

        $previousGamepad = $currentPad
    }

    # ==========================================================
    # TEST ANOTHER USB PORT
    # ==========================================================

    ZHeader "PROBAR OTRO PUERTO USB"

    ZText ""

    ZText `
        "  Desconecta y vuelve a conectar tu control en otro" `
        White

    ZText `
        "  puerto USB para probar diferentes conexiones." `
        White

    ZText ""

    ZText `
        "  Cuando Windows reconozca nuevamente el control," `
        Gray

    ZText `
        "  presiona R para volver a analizar." `
        Gray

    ZText ""

    ZText `
        "  [R]  VOLVER A ANALIZAR" `
        Yellow

    ZText `
        "  [Q]  SALIR" `
        DarkGray

    ZText ""

    $choice = (

        Read-Host "  Selecciona una opcion"

    ).Trim().ToUpper()

    switch ($choice) {

        "R" {

            ZText ""

            ZText `
                "  Esperando que Windows actualice los dispositivos..." `
                Yellow

            Start-Sleep -Seconds 2
        }

        "Q" {

            $running = $false

        }

        default {

            ZText ""

            ZText `
                "  Opcion no valida. Presiona R o Q." `
                Yellow

            Start-Sleep -Seconds 1

        }
    }
}

# ==============================================================
# EXIT
# ==============================================================

Clear-Host

ZHeader "ZENY+ USB LATENCY ANALYZER"

ZText ""

ZText `
    "  Analisis terminado." `
    Green

ZText `
    "  Gracias por usar ZENY+." `
    Cyan

ZText ""

}
