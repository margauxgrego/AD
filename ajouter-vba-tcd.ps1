# =============================================================
# ajouter-vba-tcd.ps1
# Injecte le VBA Option E (VeryHidden) dans un fichier .xls
# généré par l'application Gestion de stock Samsung.
#
# Usage :
#   .\ajouter-vba-tcd.ps1 "C:\Exports\STOCK KUBE 06052026.xls"
#
# Prérequis Excel :
#   Fichier > Options > Centre de gestion de la confidentialité
#   > Paramètres des macros > cocher
#   "Approuver l'accès au modèle d'objet du projet VBA"
# =============================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ExcelPath
)

# ---- Constantes Excel COM ----
$xlSheetVeryHidden = 2
$xlSheetVisible    = -1
$xlOpenXMLWorkbookMacroEnabled = 52  # .xlsm

# ---- Vérification du fichier ----
if (-not (Test-Path $ExcelPath)) {
    Write-Error "Fichier introuvable : $ExcelPath"
    exit 1
}
$fullPath = (Resolve-Path $ExcelPath).Path
$xlsmPath = [System.IO.Path]::ChangeExtension($fullPath, ".xlsm")

$excel    = $null
$workbook = $null

try {
    Write-Host "Ouverture de Excel..."
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible        = $false
    $excel.DisplayAlerts  = $false

    $workbook = $excel.Workbooks.Open($fullPath)

    # ---- Masquer tous les onglets D* (mini-détails du TCD) ----
    foreach ($sheet in @($workbook.Sheets)) {
        if ($sheet.Name -match "^D\d+$") {
            $sheet.Visible = $xlSheetVeryHidden
        }
    }

    # ---- Créer ou récupérer l'onglet Détail ----
    $detailSheet = $null
    foreach ($sheet in @($workbook.Sheets)) {
        if ($sheet.Name -eq "Détail") { $detailSheet = $sheet; break }
    }
    if ($null -eq $detailSheet) {
        $lastSheet   = $workbook.Sheets.Item($workbook.Sheets.Count)
        $detailSheet = $workbook.Sheets.Add([System.Reflection.Missing]::Value, $lastSheet)
        $detailSheet.Name = "Détail"
    }
    $detailSheet.Visible = $xlSheetVeryHidden

    # ---- Helper : vider un module et injecter du code ----
    function Set-VbaCode {
        param($Module, [string]$Code)
        $n = $Module.CountOfLines
        if ($n -gt 0) { $Module.DeleteLines(1, $n) }
        $Module.AddFromString($Code)
    }

    # ---- VBA ThisWorkbook ----
    $codeThisWorkbook = @'
Private Sub Workbook_Open()
    On Error Resume Next
    ThisWorkbook.Sheets("Détail").Visible = xlSheetVeryHidden
    On Error GoTo 0
End Sub
'@
    $twModule = $workbook.VBProject.VBComponents.Item("ThisWorkbook").CodeModule
    Set-VbaCode -Module $twModule -Code $codeThisWorkbook

    # ---- VBA Feuille TCD ----
    $codeTCD = @'
' Quand l'utilisateur revient sur TCD -> Détail se cache
Private Sub Worksheet_SelectionChange(ByVal Target As Range)
    Call MasquerDetail
End Sub

' Double-clic sur une cellule de données -> affiche Détail filtré
Private Sub Worksheet_BeforeDoubleClick(ByVal Target As Range, Cancel As Boolean)
    If Target.Row <= 2 Then Exit Sub          ' Lignes d'en-tête
    If Target.Column <= 1 Then Exit Sub       ' Colonne A = noms produits
    If Me.Cells(Target.Row, 1).Value = "Total général" Then Exit Sub

    Cancel = True

    Dim nomProduit As String
    Dim statut     As String
    nomProduit = Trim(Me.Cells(Target.Row, 1).Value)
    statut     = Trim(Me.Cells(2, Target.Column).Value)

    Dim wsDetail As Worksheet
    Dim wsBDD    As Worksheet
    Set wsDetail = ThisWorkbook.Sheets("Détail")
    Set wsBDD    = ThisWorkbook.Sheets("BDD")

    Call RemplirDetail(wsDetail, wsBDD, nomProduit, statut)

    wsDetail.Visible = xlSheetVisible
    wsDetail.Activate
End Sub

' Cache l'onglet Détail (VeryHidden)
Private Sub MasquerDetail()
    On Error Resume Next
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("Détail")
    If Not ws Is Nothing Then
        If ws.Visible <> xlSheetVeryHidden Then ws.Visible = xlSheetVeryHidden
    End If
    On Error GoTo 0
End Sub

' Remplit l'onglet Détail avec les lignes BDD correspondant à nomProduit x statut
Private Sub RemplirDetail(wsDetail As Worksheet, wsBDD As Worksheet, _
                           nomProduit As String, statut As String)
    Dim lastRow  As Long
    Dim lastCol  As Long
    Dim colNom   As Long
    Dim colStat  As Long
    Dim writeRow As Long
    Dim i As Long, j As Long

    wsDetail.Cells.Clear

    lastRow = wsBDD.Cells(wsBDD.Rows.Count, 1).End(xlUp).Row
    lastCol = wsBDD.Cells(1, wsBDD.Columns.Count).End(xlToLeft).Column

    ' Localise MARKETING_NAME et STATUT dans l'en-tête BDD
    colNom = 0 : colStat = 0
    For j = 1 To lastCol
        Select Case UCase(Trim(wsBDD.Cells(1, j).Value))
            Case "MARKETING_NAME" : colNom  = j
            Case "STATUT"         : colStat = j
        End Select
    Next j

    If colNom = 0 Or colStat = 0 Then
        wsDetail.Cells(1, 1).Value = "Colonnes MARKETING_NAME ou STATUT introuvables dans BDD."
        Exit Sub
    End If

    ' Ligne de titre colorée
    With wsDetail.Cells(1, 1)
        .Value      = "Détail : " & nomProduit & IIf(statut <> "", "  |  " & statut, "")
        .Font.Bold  = True
        .Font.Color = RGB(255, 255, 255)
        .Interior.Color = RGB(0, 112, 192)
    End With
    wsDetail.Range(wsDetail.Cells(1, 1), wsDetail.Cells(1, lastCol)).Merge

    ' En-tête BDD en ligne 2
    wsBDD.Rows(1).Copy wsDetail.Rows(2)

    ' Copie des lignes filtrées
    writeRow = 3
    For i = 2 To lastRow
        If Trim(wsBDD.Cells(i, colNom).Value) = nomProduit And _
           Trim(wsBDD.Cells(i, colStat).Value) = statut Then
            wsBDD.Rows(i).Copy wsDetail.Rows(writeRow)
            writeRow = writeRow + 1
        End If
    Next i

    wsDetail.Columns.AutoFit
End Sub
'@
    $tcdCodeName = $workbook.Sheets.Item("TCD").CodeName
    $tcdModule   = $workbook.VBProject.VBComponents.Item($tcdCodeName).CodeModule
    Set-VbaCode -Module $tcdModule -Code $codeTCD

    # ---- VBA Feuille Détail ----
    $codeDetail = @'
' Dès que l'utilisateur quitte Détail -> le recacher automatiquement
Private Sub Worksheet_Deactivate()
    Me.Visible = xlSheetVeryHidden
End Sub
'@
    $detailCodeName = $detailSheet.CodeName
    $detailModule   = $workbook.VBProject.VBComponents.Item($detailCodeName).CodeModule
    Set-VbaCode -Module $detailModule -Code $codeDetail

    # ---- Sauvegarde en .xlsm ----
    Write-Host "Sauvegarde en : $xlsmPath"
    $workbook.SaveAs($xlsmPath, $xlOpenXMLWorkbookMacroEnabled)
    Write-Host "Terminé. Ouvrez : $xlsmPath"

}
catch {
    Write-Error "Erreur : $_"
}
finally {
    if ($null -ne $workbook) { try { $workbook.Close($false) } catch {} }
    if ($null -ne $excel)    { try { $excel.Quit() } catch {} }
    if ($null -ne $workbook) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null }
    if ($null -ne $excel)    { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel)    | Out-Null }
    [System.GC]::Collect()
}
