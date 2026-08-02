<#
  Druckt eine fertige Tassen-Druckdatei direkt auf den Sublimationsdrucker.
  Ohne Illustrator, ohne Dialog, ohne verstellbare Skalierung.

  Hintergrund: Der Druckbogen aus dem Designer ist 23,3 x 9 cm bei 300 dpi.
  Wird er auf A5 (14,8 x 21 cm) gedruckt, passt die lange Kante in keine
  Blattrichtung und das Motiv wird angeschnitten. Dieses Skript setzt die
  Blattgroesse fest auf das Bogenmass und zeichnet das Bild 1:1 hinein,
  ohne "an Seite anpassen".

  Das Bild wird standardmaessig gespiegelt, weil Sublimation seitenverkehrt
  gedruckt wird und der Designer bewusst seitenrichtig exportiert. Kommt das
  Bild schon aus tools/spiegeln/, dann -NichtSpiegeln setzen.

  Aufruf:
    .\Drucke-Tassenbogen.ps1                      Bild aus der Zwischenablage
    .\Drucke-Tassenbogen.ps1 -Bild bogen.png      Bild aus einer Datei
    .\Drucke-Tassenbogen.ps1 -Liste               Drucker und Blattgroessen zeigen
    .\Drucke-Tassenbogen.ps1 -VersatzXmm 1.5      Druckbild 1,5 mm nach rechts
#>
param(
  [string] $Bild,
  [string] $Drucker    = 'Epson Sublimation',
  [double] $BreiteMm   = 233,
  [double] $HoeheMm    = 90,
  [switch] $NichtSpiegeln,
  [switch] $NichtDrehen,
  [double] $VersatzXmm = 0,
  [double] $VersatzYmm = 0,
  [int]    $Kopien     = 1,
  [switch] $Liste,
  [string] $ProbePdf,
  [string] $Profil      = 'C:\Windows\System32\spool\drivers\color\Epson SC-F100-1 (Rigid).icc',
  [string] $QuellProfil = 'C:\Windows\System32\spool\drivers\color\sRGB Color Space Profile.icm',
  [switch] $OhneProfil
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

# .NET rechnet beim Drucken in Hundertstel Zoll. 1 Hundertstel = 0,254 mm.
$MM_JE_EINHEIT = 0.254

function Schreib($text, $farbe = 'Gray') { Write-Host $text -ForegroundColor $farbe }

# ---------- Farbumrechnung ueber das ICC-Profil ----------
# Windows' Farbmodul mscms rechnet von sRGB in den Farbraum des Druckers, mit
# perzeptivem Rendering. Das ist derselbe Weg, den Illustrator mit
# "Farben von Illustrator verwalten lassen" gegangen ist. Wichtig: danach
# stehen im Bild Geraetewerte, keine sRGB-Werte mehr. Der Treiber darf also
# nicht noch einmal korrigieren, sonst wird zweimal gerechnet.
if (-not ('Icm' -as [type])) {
  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class Icm {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct PROFILE { public uint dwType; public IntPtr pProfileData; public uint cbDataSize; }
  [DllImport("mscms.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr OpenColorProfileW(ref PROFILE p, uint access, uint share, uint creation);
  [DllImport("mscms.dll", SetLastError=true)] public static extern bool CloseColorProfile(IntPtr h);
  [DllImport("mscms.dll", SetLastError=true)]
  public static extern IntPtr CreateMultiProfileTransform(IntPtr[] profiles, uint nProfiles,
      uint[] intents, uint nIntents, uint flags, uint cmm);
  [DllImport("mscms.dll", SetLastError=true)] public static extern bool DeleteColorTransform(IntPtr h);
  [DllImport("mscms.dll", SetLastError=true)]
  public static extern bool TranslateBitmapBits(IntPtr h, IntPtr src, uint srcFmt,
      uint width, uint height, uint srcStride, IntPtr dst, uint dstFmt, uint dstStride,
      IntPtr cb, IntPtr data);
  public const uint PROFILE_FILENAME = 1, PROFILE_READ = 1, FILE_SHARE_READ = 1, OPEN_EXISTING = 3;
  public const uint BM_BGRTRIPLETS = 0x0004, INTENT_PERCEPTUAL = 0, BEST_MODE = 0x0003;
  public static IntPtr Oeffne(string pfad) {
    IntPtr name = Marshal.StringToHGlobalUni(pfad);
    PROFILE p = new PROFILE();
    p.dwType = PROFILE_FILENAME; p.pProfileData = name;
    p.cbDataSize = (uint)((pfad.Length + 1) * 2);
    IntPtr h = OpenColorProfileW(ref p, PROFILE_READ, FILE_SHARE_READ, OPEN_EXISTING);
    Marshal.FreeHGlobal(name);
    return h;
  }
}
'@
}

function Wandle-Farben($bild, $quellProfil, $zielProfil) {
  # mscms erwartet 24 Bit BGR am Stueck, deshalb erst umkopieren.
  $flach = New-Object System.Drawing.Bitmap($bild.Width, $bild.Height,
             [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  $flach.SetResolution($bild.HorizontalResolution, $bild.VerticalResolution)
  $gg = [System.Drawing.Graphics]::FromImage($flach)
  $gg.DrawImage($bild, 0, 0, $bild.Width, $bild.Height)
  $gg.Dispose()

  $hQ = [Icm]::Oeffne($quellProfil)
  $hZ = [Icm]::Oeffne($zielProfil)
  if ($hQ -eq [IntPtr]::Zero -or $hZ -eq [IntPtr]::Zero) {
    if ($hQ -ne [IntPtr]::Zero) { [void][Icm]::CloseColorProfile($hQ) }
    if ($hZ -ne [IntPtr]::Zero) { [void][Icm]::CloseColorProfile($hZ) }
    throw 'Profil liess sich nicht oeffnen.'
  }
  $hT = [Icm]::CreateMultiProfileTransform([IntPtr[]]@($hQ,$hZ), 2,
          [uint32[]]@([Icm]::INTENT_PERCEPTUAL), 1, [Icm]::BEST_MODE, 0)
  if ($hT -eq [IntPtr]::Zero) {
    [void][Icm]::CloseColorProfile($hQ); [void][Icm]::CloseColorProfile($hZ)
    throw "Farbtransformation fehlgeschlagen (Fehler $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))."
  }

  $r = New-Object System.Drawing.Rectangle(0, 0, $flach.Width, $flach.Height)
  $d = $flach.LockBits($r, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, $flach.PixelFormat)
  $ok = [Icm]::TranslateBitmapBits($hT, $d.Scan0, [Icm]::BM_BGRTRIPLETS,
          [uint32]$flach.Width, [uint32]$flach.Height, [uint32]$d.Stride,
          $d.Scan0, [Icm]::BM_BGRTRIPLETS, [uint32]$d.Stride, [IntPtr]::Zero, [IntPtr]::Zero)
  $flach.UnlockBits($d)

  [void][Icm]::DeleteColorTransform($hT)
  [void][Icm]::CloseColorProfile($hQ)
  [void][Icm]::CloseColorProfile($hZ)
  if (-not $ok) { throw 'Umrechnung der Bildpunkte fehlgeschlagen.' }
  return $flach
}

# ---------- Nur nachsehen, was der Drucker kann ----------
if ($Liste) {
  Schreib "`nInstallierte Drucker:" 'Cyan'
  foreach ($name in [System.Drawing.Printing.PrinterSettings]::InstalledPrinters) {
    $markierung = if ($name -eq $Drucker) { '  <-- eingestellt' } else { '' }
    Schreib "  $name$markierung"
  }
  $ps = New-Object System.Drawing.Printing.PrinterSettings
  $ps.PrinterName = $Drucker
  if (-not $ps.IsValid) { Schreib "`nDrucker '$Drucker' nicht gefunden." 'Red'; exit 1 }
  Schreib "`nBlattgroessen von '$Drucker':" 'Cyan'
  foreach ($g in $ps.PaperSizes) {
    $b = [math]::Round($g.Width  * $MM_JE_EINHEIT, 1)
    $h = [math]::Round($g.Height * $MM_JE_EINHEIT, 1)
    Schreib ("  {0,-40} {1} x {2} mm" -f $g.PaperName, $b, $h)
  }
  exit 0
}

# ---------- Bild besorgen ----------
if ($Bild) {
  if (-not (Test-Path -LiteralPath $Bild)) { Schreib "Datei nicht gefunden: $Bild" 'Red'; exit 1 }
  $quelle = [System.Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Bild))
  Schreib "Bild: $Bild"
} else {
  $quelle = [System.Windows.Forms.Clipboard]::GetImage()
  if (-not $quelle) {
    Schreib "In der Zwischenablage liegt kein Bild." 'Red'
    Schreib "Entweder ein Bild kopieren oder -Bild <pfad> angeben." 'Yellow'
    exit 1
  }
  Schreib "Bild: aus der Zwischenablage"
}

# ---------- Quer einlegen ----------
# Der Drucker nimmt keine 233 mm Breite ein, der Bogen laeuft mit der kurzen
# Kante voran: Blatt 90 mm breit, 233 mm lang, Motiv um 90 Grad gedreht.
# Das ist der Normalfall, deshalb ohne Schalter. -NichtDrehen schaltet es ab.
if (-not $NichtDrehen) {
  $quelle.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone)
  $tausch    = $BreiteMm
  $BreiteMm  = $HoeheMm
  $HoeheMm   = $tausch
  Schreib ("Gedreht: 90 Grad, Blatt also {0} x {1} mm" -f $BreiteMm, $HoeheMm)
}

# ---------- Aufloesung pruefen ----------
# Entscheidend ist nicht die dpi-Angabe in der Datei, sondern wie viele Pixel
# tatsaechlich auf der Zielbreite landen.
$effektivDpi = [math]::Round($quelle.Width / ($BreiteMm / 25.4))
Schreib ("Pixel: {0} x {1}  ->  {2} dpi auf {3} mm Breite" -f `
         $quelle.Width, $quelle.Height, $effektivDpi, $BreiteMm)
if ($effektivDpi -lt 250) {
  Schreib "Achtung: unter 250 dpi. Fuer Sublimation sichtbar unscharf." 'Yellow'
}
$sollVerhaeltnis = $BreiteMm / $HoeheMm
$istVerhaeltnis  = $quelle.Width / $quelle.Height
if ([math]::Abs($sollVerhaeltnis - $istVerhaeltnis) -gt 0.02) {
  Schreib ("Achtung: Seitenverhaeltnis weicht ab (Bild {0:N3}, Bogen {1:N3})." -f `
           $istVerhaeltnis, $sollVerhaeltnis) 'Yellow'
  Schreib "Das Bild wird auf das Bogenmass gezogen und dadurch verzerrt." 'Yellow'
}

# ---------- Spiegeln ----------
if (-not $NichtSpiegeln) {
  $quelle.RotateFlip([System.Drawing.RotateFlipType]::RotateNoneFlipX)
  Schreib "Gespiegelt: ja (Sublimation)"
} else {
  Schreib "Gespiegelt: nein (-NichtSpiegeln gesetzt)"
}

# ---------- Farben ins Druckerprofil rechnen ----------
if ($OhneProfil) {
  Schreib "Farbprofil: uebersprungen (-OhneProfil), der Treiber rechnet." 'Yellow'
} elseif (-not (Test-Path -LiteralPath $Profil)) {
  Schreib "Farbprofil: '$Profil' nicht gefunden, der Treiber rechnet." 'Yellow'
} elseif (-not (Test-Path -LiteralPath $QuellProfil)) {
  Schreib "Farbprofil: sRGB-Profil nicht gefunden, der Treiber rechnet." 'Yellow'
} else {
  try {
    $vorher  = $quelle.GetPixel([int]($quelle.Width/2), [int]($quelle.Height/2))
    $gewandelt = Wandle-Farben $quelle $QuellProfil $Profil
    $quelle.Dispose()
    $quelle = $gewandelt
    $nachher = $quelle.GetPixel([int]($quelle.Width/2), [int]($quelle.Height/2))
    Schreib ("Farbprofil: {0}" -f (Split-Path $Profil -Leaf))
    Schreib ("            perzeptiv, Probepunkt {0},{1},{2} -> {3},{4},{5}" -f `
             $vorher.R, $vorher.G, $vorher.B, $nachher.R, $nachher.G, $nachher.B)
    Schreib "            Im Treiber muss die Farbanpassung AUS sein, sonst wird zweimal gerechnet." 'Yellow'
  } catch {
    Schreib "Farbprofil: $($_.Exception.Message) Es rechnet der Treiber." 'Yellow'
  }
}

# ---------- Druckauftrag aufsetzen ----------
# Probelauf: schreibt eine PDF statt zu drucken. Gleiche Geometrie, gleicher
# Weg, nur ohne Papier. Zum Nachmessen, bevor der erste Bogen durchlaeuft.
if ($ProbePdf) {
  $Drucker = 'Microsoft Print to PDF'
  if (-not [System.IO.Path]::IsPathRooted($ProbePdf)) {
    $ProbePdf = Join-Path (Get-Location) $ProbePdf
  }
  if (Test-Path -LiteralPath $ProbePdf) { Remove-Item -LiteralPath $ProbePdf -Force }
  Schreib "Probelauf: schreibt nach $ProbePdf" 'Cyan'
}

$doc = New-Object System.Drawing.Printing.PrintDocument
$doc.PrinterSettings.PrinterName = $Drucker
if ($ProbePdf) {
  $doc.PrinterSettings.PrintToFile   = $true
  $doc.PrinterSettings.PrintFileName = $ProbePdf
}
if (-not $doc.PrinterSettings.IsValid) {
  Schreib "Drucker '$Drucker' nicht gefunden. Mit -Liste nachsehen." 'Red'
  exit 1
}
$doc.DocumentName = 'Tassenbogen'
$doc.PrinterSettings.Copies = $Kopien

# Passende Blattgroesse im Treiber suchen, in beiden Ausrichtungen.
$treffer = $null
foreach ($g in $doc.PrinterSettings.PaperSizes) {
  $b = $g.Width * $MM_JE_EINHEIT
  $h = $g.Height * $MM_JE_EINHEIT
  $passtDirekt = ([math]::Abs($b - $BreiteMm) -lt 2) -and ([math]::Abs($h - $HoeheMm) -lt 2)
  $passtQuer   = ([math]::Abs($b - $HoeheMm)  -lt 2) -and ([math]::Abs($h - $BreiteMm) -lt 2)
  if ($passtDirekt -or $passtQuer) { $treffer = $g; break }
}

if ($treffer) {
  $doc.DefaultPageSettings.PaperSize = $treffer
  Schreib ("Blatt: {0} ({1} x {2} mm)" -f $treffer.PaperName,
           [math]::Round($treffer.Width * $MM_JE_EINHEIT, 1),
           [math]::Round($treffer.Height * $MM_JE_EINHEIT, 1))
} else {
  # Ein selbst gebautes PaperSize akzeptiert nicht jeder Treiber. Wenn der
  # Ausdruck danach falsch skaliert ist, muss das Format einmalig in den
  # Epson-Treibereinstellungen als benutzerdefinierte Groesse angelegt werden.
  $eigen = New-Object System.Drawing.Printing.PaperSize(
             'Tassenbogen',
             [int][math]::Round($BreiteMm / $MM_JE_EINHEIT),
             [int][math]::Round($HoeheMm  / $MM_JE_EINHEIT))
  $eigen.RawKind = 256
  $doc.DefaultPageSettings.PaperSize = $eigen
  Schreib "Blatt: keine passende Treibergroesse gefunden, eigene gesetzt." 'Yellow'
  Schreib "Falls der Ausdruck falsch skaliert: im Epson-Treiber einmalig eine" 'Yellow'
  Schreib ("benutzerdefinierte Groesse {0} x {1} mm anlegen." -f $BreiteMm, $HoeheMm) 'Yellow'
}

$doc.DefaultPageSettings.Landscape = $false
$doc.DefaultPageSettings.Margins = New-Object System.Drawing.Printing.Margins(0, 0, 0, 0)
# false: Nullpunkt liegt an der Ecke des bedruckbaren Bereichs, nicht am Rand.
$doc.OriginAtMargins = $false

# Ueber diese Hashtable meldet der Handler zurueck. Ein Eventhandler laeuft in
# eigenem Geltungsbereich, einfache Variablen kaemen hier nie an; eine
# Hashtable ist ein Verweis und laesst sich von innen veraendern.
$status = @{ Ok = $true; Gemessen = '' }

$handler = {
  param($sender, $e)

  # ---------- Sicherung ----------
  # Nicht jeder Treiber uebernimmt eine selbst gesetzte Blattgroesse, und man
  # merkt es ihm nicht an: PageBounds meldet brav das gewuenschte Mass zurueck,
  # gedruckt wird trotzdem das Standardformat. Nachgemessen mit Microsoft Print
  # to PDF: PageBounds sagte 232,9 x 89,9 mm, im PDF stand Letter.
  # Verlaesslich ist allein VisibleClipBounds - das ist die Flaeche, auf die
  # der Treiber tatsaechlich zeichnen laesst. Noch in Hundertstel Zoll, weil
  # PageUnit erst weiter unten umgestellt wird.
  $sicht = $e.Graphics.VisibleClipBounds
  $physBmm = ($sicht.Width  + 2 * $e.PageSettings.HardMarginX) * $MM_JE_EINHEIT
  $physHmm = ($sicht.Height + 2 * $e.PageSettings.HardMarginY) * $MM_JE_EINHEIT
  $passt = ([math]::Abs($physBmm - $BreiteMm) -lt 5) -and
           ([math]::Abs($physHmm - $HoeheMm)  -lt 5)

  if (-not $passt) {
    $status.Ok = $false
    $status.Gemessen = "{0} x {1} mm" -f [math]::Round($physBmm,1), [math]::Round($physHmm,1)
    $e.Cancel = $true
    return
  }

  $g = $e.Graphics
  $g.PageUnit          = [System.Drawing.GraphicsUnit]::Millimeter
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode   = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode     = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality

  # Jeder Drucker hat einen nicht bedruckbaren Rand. Der Nullpunkt liegt hinter
  # diesem Rand, das Motiv soll aber an der Blattkante beginnen: also
  # zuruecksetzen, damit 0/0 wirklich die Blattecke ist.
  $randXmm = $e.PageSettings.HardMarginX * $MM_JE_EINHEIT
  $randYmm = $e.PageSettings.HardMarginY * $MM_JE_EINHEIT

  $ziel = New-Object System.Drawing.RectangleF(
            (-$randXmm + $VersatzXmm), (-$randYmm + $VersatzYmm), $BreiteMm, $HoeheMm)
  $g.DrawImage($quelle, $ziel)
}.GetNewClosure()   # bindet quelle, Masse und status an den Handler

$doc.add_PrintPage($handler)

Schreib ("Versatz: {0} / {1} mm" -f $VersatzXmm, $VersatzYmm)
Schreib "Drucker: $Drucker"
Schreib "`nSende Auftrag ..." 'Cyan'
$doc.Print()

if ($status.Ok) {
  Schreib "Gesendet." 'Green'
} else {
  Schreib "`nABGEBROCHEN - kein Papier verbraucht." 'Red'
  Schreib ("Der Treiber hat {0} eingestellt, gebraucht wird {1} x {2} mm." -f `
           $status.Gemessen, $BreiteMm, $HoeheMm) 'Red'
  Schreib ""
  Schreib "Das Blattmass muss einmalig im Treiber angelegt werden:" 'Yellow'
  Schreib "  Systemsteuerung > Geraete und Drucker > '$Drucker'" 'Yellow'
  Schreib "  > Druckeinstellungen > Benutzerdefiniertes Papierformat" 'Yellow'
  Schreib ("  > neu anlegen mit {0} x {1} mm, speichern" -f $BreiteMm, $HoeheMm) 'Yellow'
  Schreib "Danach findet dieses Skript das Format von allein." 'Yellow'
  exit 2
}

$quelle.Dispose()
$doc.Dispose()
