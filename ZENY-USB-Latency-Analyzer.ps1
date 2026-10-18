& {
    Clear-Host
    $ErrorActionPreference = 'SilentlyContinue'

    function Z-Line([string]$Text = '', [string]$Color = 'Gray') {
        Write-Host $Text -ForegroundColor $Color
    }
    function Z-Title([string]$Text) {
        Z-Line ''
        Z-Line ('=' * 68) DarkCyan
        Z-Line ('  ' + $Text) Cyan
        Z-Line ('=' * 68) DarkCyan
    }
    function Z-Bar([int]$Percent, [string]$Label) {
        $Percent = [Math]::Max(0, [Math]::Min(100, $Percent))
        $fill = [int][Math]::Floor($Percent * 28 / 100)
        $bar = ('#' * $fill) + ('-' * (28 - $fill))
        $line = ('  [{0}] {1,3}%  {2}' -f $bar, $Percent, $Label)
        $width = 78
        try { $width = [Math]::Max(35, [Console]::WindowWidth - 2) } catch {}
        if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
        Write-Host ("`r" + $line.PadRight([Math]::Min($width, 78))) -NoNewline -ForegroundColor Yellow
        if ($Percent -eq 100) { Write-Host '' }
    }
    function Z-Prop([string]$Id, [string]$Key) {
        if (-not $Id) { return $null }
        $cacheKey = $Id + '|' + $Key
        if ($script:zeny.Cache.ContainsKey($cacheKey)) {
            return $script:zeny.Cache[$cacheKey]
        }
        $data = $null
        try {
            $data = (Get-PnpDeviceProperty -InstanceId $Id -KeyName $Key -ErrorAction Stop).Data
        } catch {}
        $script:zeny.Cache[$cacheKey] = $data
        return $data
    }
    function Z-FirstLocation([string]$Id) {
        $v = Z-Prop $Id 'DEVPKEY_Device_LocationPaths'
        if ($null -eq $v) { return 'No disponible' }
        $first = @($v) | Select-Object -First 1
        if (-not $first) { return 'No disponible' }
        return [string]$first
    }
    function Z-PortLabel([string]$Path) {
        $matches = [regex]::Matches($Path, 'USB\(\d+\)')
        if ($matches.Count -eq 0) { return 'Puerto logico no disponible' }
        return (($matches | ForEach-Object { $_.Value }) -join ' > ')
    }
    function Z-IsHub([string]$Id, [string]$Name, [string]$Service) {
        if ($Id -match '^USB\\ROOT_HUB' -or $Name -match 'Root Hub') { return $false }
        return [bool](($Service -match '^USBHUB3?$') -or
            ($Name -match '^(Generic |SuperSpeed )?USB Hub$|^Generic SuperSpeed USB Hub$'))
    }
    function Z-Trace([string]$StartId) {
        $current = $StartId
        $seen = @{}
        $hubs = New-Object System.Collections.ArrayList
        $anchor = $null
        $controllerId = $null
        $controllerName = $null
        $hasUsbNode = $false
        for ($i = 0; $i -lt 50; $i++) {
            if (-not $current -or $seen.ContainsKey($current)) { break }
            $seen[$current] = $true
            if ($current -match '^USB\\') { $hasUsbNode = $true }
            $node = $script:zeny.Index[$current]
            $name = if ($node) { [string]$node.FriendlyName } else { '' }
            $service = [string](Z-Prop $current 'DEVPKEY_Device_Service')
            if (-not $anchor -and $current -match '^USB\\VID_' -and
                $current -notmatch '&MI_[0-9A-F]{2}') { $anchor = $current }
            if ($script:zeny.ControllerMap.ContainsKey($current)) {
                $controllerId = $current
                $controllerName = $script:zeny.ControllerMap[$current]
                break
            }
            if ($service -match '^(USBXHCI|USBEHCI|USBOHCI|USBUHCI)$' -or
                $name -match 'Host Controller|eXtensible Host') {
                $controllerId = $current
                $controllerName = if ($name) { $name } else { $service }
                break
            }
            if (Z-IsHub $current $name $service) {
                [void]$hubs.Add([PSCustomObject]@{
                    Id = $current
                    Name = $(if ($name) { $name } else { 'USB Hub' })
                })
            }
            $parent = Z-Prop $current 'DEVPKEY_Device_Parent'
            if ($parent -is [array]) { $parent = $parent[0] }
            $current = [string]$parent
        }
        return [PSCustomObject]@{
            Complete = [bool]$controllerId
            HostId = $controllerId
            HostName = $controllerName
            Hubs = @($hubs.ToArray())
            Anchor = $anchor
            HasUSB = $hasUsbNode
        }
    }
    function Z-Scan {
        $script:zeny = @{
            Cache = @{}; Index = @{}; ControllerMap = @{}
            Controllers = @(); Hubs = @(); Devices = @()
        }
        Z-Title 'ZENY+ USB LATENCY ANALYZER'
        Z-Line '  GAMING USB TOPOLOGY | ESCANEO AUTOMATICO' Green
        Z-Line '  No necesitas desconectar ningun dispositivo.' White
        Z-Line '  El porcentaje refleja el avance del escaneo.' DarkGray
        Z-Line ''
        Z-Line '  [1/4] Leyendo dispositivos y controladores...' Yellow
        Z-Bar 0 'Preparando'
        try {
            $all = @(Get-PnpDevice -ErrorAction Stop)
            $present = @(Get-PnpDevice -PresentOnly -ErrorAction Stop)
            $script:zeny.Controllers = @(Get-CimInstance Win32_USBController -ErrorAction Stop)
        } catch {
            Z-Line ''
            Z-Line '  No se pudo acceder al inventario USB de Windows.' Red
            Z-Line '  Abre Windows PowerShell 5.1 como administrador.' Yellow
            return $false
        }
        foreach ($d in $all) {
            if ($d.InstanceId) { $script:zeny.Index[$d.InstanceId] = $d }
        }
        foreach ($c in $script:zeny.Controllers) {
            if ($c.PNPDeviceID) {
                $script:zeny.ControllerMap[[string]$c.PNPDeviceID] = [string]$c.Name
            }
        }
        Z-Bar 100 'Inventario listo'
        Z-Line '  [2/4] Reconstruyendo arbol de USB...' Yellow

        # All present PnP nodes are examined, so USB interfaces in
        # non-USB classes can still appear in the final topology.
        $raw = New-Object System.Collections.ArrayList
        $hubMap = @{}
        $total = [Math]::Max(1, $present.Count)
        $lastPercent = -1
        $n = 0
        foreach ($d in $present) {
            $n++
            $pct = [int][Math]::Floor(100.0 * $n / $total)
            if ($pct -ne $lastPercent) {
                Z-Bar $pct "Analizando $n de $total"
                $lastPercent = $pct
            }
            if (-not $d.InstanceId) { continue }
            $trace = Z-Trace ([string]$d.InstanceId)
            if (-not $trace.HasUSB) { continue }
            $name = [string]$d.FriendlyName
            if (-not $name) { $name = [string]$d.InstanceId }
            $service = [string](Z-Prop $d.InstanceId 'DEVPKEY_Device_Service')
            foreach ($h in $trace.Hubs) {
                if (-not $hubMap.ContainsKey($h.Id)) {
                    $hubMap[$h.Id] = [PSCustomObject]@{
                        Id = $h.Id; Name = $h.Name
                        HostId = $trace.HostId; ParentHub = $null
                        Path = (Z-FirstLocation $h.Id)
                        Complete = $trace.Complete
                    }
                }
            }
            if (Z-IsHub $d.InstanceId $name $service) { continue }
            if ($name -match 'Root Hub|Host Controller') { continue }
            if ($d.InstanceId -match '^USB\\ROOT_HUB') { continue }
            $physicalId = if ($trace.Anchor) { $trace.Anchor } else { [string]$d.InstanceId }
            $location = Z-FirstLocation $physicalId
            if ($location -eq 'No disponible') { $location = Z-FirstLocation $d.InstanceId }
            $priority = 20
            if ($name -match 'GameSir|Tarantula|Xbox.*Controller|DualSense|DualShock|Gamepad|Joystick|Wireless Controller') { $priority = 100 }
            elseif ($name -match 'Keyboard|Mouse|Camera|Headset|Microphone|Audio|Storage|Printer') { $priority = 65 }
            elseif ($name -match '^HID-compliant system controller$') { $priority = 45 }
            elseif ($name -match '^USB Input Device$|^USB Composite Device$|^HID-compliant') { $priority = 5 }
            [void]$raw.Add([PSCustomObject]@{
                Name = $name; Id = [string]$d.InstanceId
                GroupId = $physicalId; HostId = $trace.HostId
                HostName = $trace.HostName; Complete = $trace.Complete
                Hubs = @($trace.Hubs); HubCount = $trace.Hubs.Count
                Path = $location; Priority = $priority
            })
        }
        if ($lastPercent -lt 100) { Z-Bar 100 'Analisis terminado' }
        $script:zeny.Devices = @($raw | Group-Object GroupId | ForEach-Object {
            $_.Group | Sort-Object Priority -Descending | Select-Object -First 1
        } | Sort-Object Name,Path)
        # Assign parent hubs by tracing each hub itself (closest-to-host
        # path is obtained after its own entry in the hub chain).
        foreach ($hub in @($hubMap.Values)) {
            $trace = Z-Trace $hub.Id
            $hub.HostId = $trace.HostId
            $hub.Complete = $trace.Complete
            $ids = @($trace.Hubs | ForEach-Object { $_.Id })
            $position = [array]::IndexOf($ids, $hub.Id)
            if ($position -ge 0 -and ($position + 1) -lt $ids.Count) {
                $hub.ParentHub = $ids[$position + 1]
            }
        }
        $script:zeny.Hubs = @($hubMap.Values | Sort-Object Path)
        $valid = @($script:zeny.Devices | Where-Object Complete)
        $invalid = @($script:zeny.Devices | Where-Object { -not $_.Complete })
        Z-Line ''
        Z-Line ('  Dispositivos USB agrupados: ' + $script:zeny.Devices.Count) Cyan
        Z-Line ('  Rutas verificadas: ' + $valid.Count) Green
        Z-Line ('  Rutas no verificadas: ' + $invalid.Count) Yellow
        Z-Line ('  Hubs intermedios encontrados: ' + $script:zeny.Hubs.Count) Yellow
        return $true
    }
    function Z-PrintChildren([string]$Parent, [string]$Indent = '', [int]$Depth = 0, [hashtable]$Visited = @{}) {
        if ($Depth -gt 16 -or $Visited.ContainsKey($Parent)) { return }
        $Visited[$Parent] = $true
        $hubs = @($script:zeny.Hubs | Where-Object {
            $_.Complete -and (
                ($(if ($_.ParentHub) { 'H:' + $_.ParentHub } else { 'C:' + $_.HostId })) -eq $Parent
            )
        })
        $devices = @($script:zeny.Devices | Where-Object {
            $_.Complete -and (
                ($(if ($_.HubCount -gt 0) { 'H:' + $_.Hubs[0].Id } else { 'C:' + $_.HostId })) -eq $Parent
            )
        })
        $entries = @()
        foreach ($h in $hubs) { $entries += [PSCustomObject]@{ Kind = 'H'; Item = $h } }
        foreach ($d in $devices) { $entries += [PSCustomObject]@{ Kind = 'D'; Item = $d } }
        for ($i = 0; $i -lt $entries.Count; $i++) {
            $entry = $entries[$i]
            $last = ($i -eq $entries.Count - 1)
            $branch = if ($last) { '\-- ' } else { '|-- ' }
            $nextIndent = $Indent + $(if ($last) { '    ' } else { '|   ' })
            if ($entry.Kind -eq 'H') {
                $h = $entry.Item
                Z-Line ($Indent + $branch + '[HUB] ' + $h.Name + '  ' + (Z-PortLabel $h.Path)) Yellow
                Z-PrintChildren ('H:' + $h.Id) $nextIndent ($Depth + 1) $Visited
            } else {
                $d = $entry.Item
                $color = if ($d.HubCount -eq 0) { 'Green' } elseif ($d.HubCount -eq 1) { 'Yellow' } else { 'Red' }
                Z-Line ($Indent + $branch + $d.Name + '  [' + $d.HubCount + ' HUBS]') $color
                Z-Line ($nextIndent + (Z-PortLabel $d.Path)) DarkGray
            }
        }
    }
    function Z-Tree {
        Z-Title '[3/4] ARBOL COMPLETO DE CONEXIONES USB'
        Z-Line '  VERDE = sin hubs intermedios | AMARILLO = 1 | ROJO = 2+' White
        Z-Line '  Son rutas logicas detectadas, no todos los puertos fisicos.' DarkGray
        Z-Line ''
        $knownHosts = @{}
        foreach ($c in $script:zeny.Controllers) {
            $id = [string]$c.PNPDeviceID
            if (-not $id) { continue }
            $knownHosts[$id] = $true
            Z-Line ('  [USB HOST] ' + $c.Name) Cyan
            Z-Line ('    ' + $id) DarkGray
            Z-PrintChildren ('C:' + $id) '    ' 0 @{}
            Z-Line ''
        }
        # Controllers found in PnP but missing from CIM list
        $extraHosts = @($script:zeny.Devices | Where-Object {
            $_.Complete -and $_.HostId -and -not $knownHosts.ContainsKey($_.HostId)
        } | Select-Object -ExpandProperty HostId -Unique)
        foreach ($id in $extraHosts) {
            $d = $script:zeny.Devices | Where-Object HostId -eq $id | Select-Object -First 1
            Z-Line ('  [USB HOST] ' + $d.HostName) Cyan
            Z-PrintChildren ('C:' + $id) '    ' 0 @{}
        }
        $unknown = @($script:zeny.Devices | Where-Object { -not $_.Complete })
        if ($unknown.Count -gt 0) {
            Z-Line '  [RUTAS SIN VERIFICAR]' DarkYellow
            foreach ($d in $unknown) { Z-Line ('    - ' + $d.Name) DarkYellow }
        }
    }
    function Z-HubDetails {
        Z-Title 'ZENY+ FULL USB HUB VIEW'
        if ($script:zeny.Hubs.Count -eq 0) {
            Z-Line '  No se detectaron hubs USB intermedios.' Yellow
            return
        }
        $i = 0
        foreach ($hub in $script:zeny.Hubs) {
            $i++
            Z-Line ''
            Z-Line ('  HUB ' + $i + ': ' + $hub.Name) Yellow
            Z-Line ('  Ruta: ' + $hub.Path) DarkGray
            $connected = @($script:zeny.Devices | Where-Object {
                $_.Hubs.Count -gt 0 -and $_.Hubs[0].Id -eq $hub.Id
            })
            $subHubs = @($script:zeny.Hubs | Where-Object { $_.ParentHub -eq $hub.Id })
            foreach ($child in $subHubs) { Z-Line ('    -> [HUB] ' + $child.Name) Yellow }
            foreach ($child in $connected) { Z-Line ('    -> ' + $child.Name) White }
            if ($connected.Count + $subHubs.Count -eq 0) {
                Z-Line '    Sin dispositivos finales identificados.' DarkGray
            }
        }
    }
    function Z-Advice {
        Z-Title '[4/4] ZENY+ RECOMENDACION PARA GAMING'
        $pads = @($script:zeny.Devices | Where-Object {
            $_.Name -match 'GameSir|Tarantula|Xbox.*Controller|DualSense|DualShock|Gamepad|Joystick|Wireless Controller'
        })
        if ($pads.Count -eq 0) {
            Z-Line '  No se reconocio un control por su nombre.' Yellow
            Z-Line '  Algunos GameSir se identifican como Xbox Controller.' Gray
        }
        foreach ($pad in $pads) {
            Z-Line ''
            Z-Line ('  CONTROL: ' + $pad.Name) Cyan
            if (-not $pad.Complete) {
                Z-Line '  ESTADO: RUTA NO VERIFICADA' DarkYellow
                Z-Line '  No es correcto asumir que tiene 0 hubs.' White
            } elseif ($pad.HubCount -eq 0) {
                Z-Line '  ESTADO: BUENA RUTA USB (0 HUBS INTERMEDIOS)' Green
                Z-Line '  POR QUE: No se detectaron hubs adicionales.' White
            } else {
                $color = if ($pad.HubCount -eq 1) { 'Yellow' } else { 'Red' }
                Z-Line ('  ESTADO: ' + $pad.HubCount + ' HUB(S) INTERMEDIOS') $color
                Z-Line '  POR QUE: La ruta pasa por hubs USB adicionales.' White
                Z-Line '  Una ruta con menos hubs seria candidata a comparar.' Gray
            }
            Z-Line ('  CONTROLADOR: ' + $pad.HostName) Gray
            Z-Line ('  PUERTO LOGICO: ' + (Z-PortLabel $pad.Path)) Yellow
            Z-Line ('  RUTA: ' + $pad.Path) DarkGray
        }
        Z-Line ''
        Z-Line ('-' * 68) DarkGray
        Z-Line '  RECOMENDACION FINAL' Green
        Z-Line '  Usa una ruta verificada sin hubs extra como primera opcion.' White
        Z-Line '  La topologia NO mide input lag ni polling rate.' Yellow
        Z-Line '  Sin probar conectores vacios no podemos elegir el puerto' Gray
        Z-Line '  fisico de menor latencia de toda la computadora.' Gray
        if ($script:zenyPrevious -and $script:zenyPrevious.Count -gt 0) {
            Z-Line ''
            Z-Line '  COMPARACION CON EL ESCANEO ANTERIOR:' Cyan
            foreach ($pad in $pads) {
                $old = @($script:zenyPrevious | Where-Object { $_.Name -eq $pad.Name } | Select-Object -First 1)
                if ($old.Count -eq 0) { continue }
                if ($old[0].Path -eq $pad.Path) {
                    Z-Line ('  ' + $pad.Name + ': misma ruta logica.') Gray
                } else {
                    Z-Line ('  ANTES: ' + $old[0].Path) DarkGray
                    Z-Line ('  AHORA: ' + $pad.Path) Cyan
                    if ($old[0].Complete -and $pad.Complete) {
                        if ($pad.HubCount -lt $old[0].HubCount) {
                            Z-Line '  AHORA: menos hubs intermedios detectados.' Green
                        } elseif ($pad.HubCount -gt $old[0].HubCount) {
                            Z-Line '  AHORA: mas hubs intermedios detectados.' Yellow
                        } else {
                            Z-Line '  Ambas rutas tienen igual cantidad de hubs.' White
                        }
                    }
                    Z-Line '  Diferencia de input lag: no medida.' Yellow
                }
            }
        }
        Z-Line ''
        Z-Line '  PARA PROBAR OTROS PUERTOS USB:' Yellow
        Z-Line '  Desconecta y vuelve a conectar tu control en otro puerto.' White
        Z-Line '  Selecciona [4] para volver a analizar las conexiones.' White
    }
    $continue = Z-Scan
    if (-not $continue) { return }
    Z-Tree
    Z-Advice
    while ($true) {
        Z-Title 'ZENY+ USB ANALYZER | MENU PRINCIPAL'
        Z-Line '  [1] Ver arbol USB y resultados' Cyan
        Z-Line '  [2] Ver todos los hubs USB' Cyan
        Z-Line '  [3] Recomendacion para gaming' Cyan
        Z-Line '  [4] Volver a analizar (barra amarilla)' Yellow
        Z-Line '  [0] Salir' Red
        Z-Line ''
        $choice = Read-Host '  Selecciona una opcion'
        switch ($choice) {
            '1' { Z-Tree }
            '2' { Z-HubDetails }
            '3' { Z-Advice }
            '4' {
                $script:zenyPrevious = @($script:zeny.Devices | Where-Object {
                    $_.Name -match 'GameSir|Tarantula|Xbox.*Controller|DualSense|DualShock|Gamepad|Joystick|Wireless Controller'
                })
                Clear-Host
                if (Z-Scan) { Z-Tree; Z-Advice }
            }
            '0' {
                Z-Line '  Gracias por usar ZENY+.' Green
                return
            }
            default { Z-Line '  Opcion no valida. Intenta de nuevo.' Yellow }
        }
    }
}
