<#
.SYNOPSIS
  Đóng gói toàn bộ dự án thành một bộ tài liệu để đưa sang công cụ khác (ChatGPT Desktop…).

.DESCRIPTION
  Sinh ra hai thứ:
    * Một THƯ MỤC có cấu trúc: tài liệu, migration, mã nguồn, script vận hành.
    * Một FILE DUY NHẤT gộp tất cả — thứ thực sự dán/nạp vào công cụ khác.

  Trước khi đóng gói, script QUÉT SECRET và DỪNG nếu tìm thấy. Gói này được tạo ra để gửi
  ra ngoài, nên một khóa lọt vào đây là lọt ra ngoài thật. Thà không đóng gói được còn hơn.

  Những thứ CỐ Ý không đưa vào gói:
    * config/project.local.json  — cấu hình triển khai, có URL và thông tin project
    * .env, .dev.vars, .wrangler — nơi chứa khóa
    * supabase/.temp             — thông tin project đã link
    * node_modules, dist, uat/evidence — rác và ảnh chụp màn hình

.EXAMPLE
  .\scripts\kpi_handover.ps1 -OutputDir C:\KPI-BanGiao
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$UrlEnvVar = "KPI_BACKUP_DB_URL",
  [string]$PostgresImage = "postgres:17",
  [switch]$SkipSchemaDump
)

$ErrorActionPreference = "Stop"
function Say  { param([string]$m, [string]$c = "White") Write-Host $m -ForegroundColor $c }
function Fail { param([string]$m) Say "DUNG: $m" Red; exit 1 }

function Get-DbUrl {
  param([string]$Name)
  foreach ($scope in @("Process","User","Machine")) {
    $v = [Environment]::GetEnvironmentVariable($Name, $scope)
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
  }
  return $null
}

$repo = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd"
$pack = Join-Path $OutputDir "kpi-mep-bangiao-$stamp"
Push-Location $repo
try {
  Say "=== Dong goi du an KPI MEP ===" Cyan

  # --- 1. Gom danh sach file --------------------------------------------------------
  $excludeDir = @("node_modules","dist",".next",".wrangler",".git","evidence","restore-points")
  $excludeFile = @("project.local.json")
  function Take {
    param([string]$Root, [string]$Filter)
    if (-not (Test-Path $Root)) { return @() }
    Get-ChildItem -Path $Root -Filter $Filter -Recurse -File |
      Where-Object {
        $rel = $_.FullName.Substring($repo.Length).TrimStart('\')
        $parts = $rel -split '\\'
        (-not ($parts | Where-Object { $excludeDir -contains $_ })) -and
        ($excludeFile -notcontains $_.Name) -and
        ($_.Name -notlike ".env*") -and ($_.Name -notlike "*.dev.vars")
      }
  }

  $groups = [ordered]@{
    "01_tai_lieu"    = @(Take (Join-Path $repo "handover") "*.md") + @(Take (Join-Path $repo "docs") "*.md") + @(Take (Join-Path $repo "backup") "README.md")
    "02_sql"         = @(Take (Join-Path $repo "supabase\migrations") "*.sql") + @(Take (Join-Path $repo "supabase\rollback") "*.sql") + @(Take (Join-Path $repo "supabase") "config.toml")
    "03_giao_dien"   = @(Take (Join-Path $repo "web\app") "*.tsx") + @(Take (Join-Path $repo "web\app") "*.ts") + @(Take (Join-Path $repo "web\lib") "*.ts") + @(Take (Join-Path $repo "web\tests") "*.mjs") + @(Take (Join-Path $repo "web\app") "*.css")
    "04_van_hanh"    = @(Take (Join-Path $repo "backup") "*.ps1") + @(Take (Join-Path $repo "scripts") "*.ps1")
  }
  $all = @($groups.Values | ForEach-Object { $_ })
  if ($all.Count -eq 0) { Fail "Khong gom duoc file nao." }
  Say ("[1/5] Da gom {0} file" -f $all.Count) Green

  # --- 2. QUET SECRET ---------------------------------------------------------------
  # Bat GIA TRI that, khong bat ten bien. "SUPABASE_SECRET_KEY" la ten - khong sao;
  # "sb_secret_abc123..." la gia tri - chan.
  $patterns = @(
    @{ Name = "khoa secret Supabase"; Rx = 'sb_secret_[A-Za-z0-9_\-]{8,}' },
    @{ Name = "JWT (co the la service_role)"; Rx = 'eyJ[A-Za-z0-9_\-]{15,}\.[A-Za-z0-9_\-]{15,}' },
    @{ Name = "chuoi ket noi co mat khau"; Rx = '://[^:@/\s]+:[^@/\s]{6,}@' },
    @{ Name = "gan mat khau truc tiep"; Rx = '(?i)(password|passwd|pwd)\s*[:=]\s*["''][^"'']{6,}["'']' }
  )
  $hits = @()
  foreach ($f in $all) {
    $text = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    foreach ($p in $patterns) {
      foreach ($m in [regex]::Matches($text, $p.Rx)) {
        # Bo qua vi du ro rang la gia trong tai lieu.
        if ($m.Value -match 'MATKHAU|YOUR-PASSWORD|<[^>]+>|xxxx|MAT_KHAU') { continue }
        $hits += [pscustomobject]@{ File = $f.FullName.Substring($repo.Length).TrimStart('\'); Kind = $p.Name }
      }
    }
  }
  if ($hits.Count -gt 0) {
    $hits | Group-Object File, Kind | ForEach-Object { Say ("    {0}" -f $_.Name) DarkYellow }
    Fail "Tim thay thu giong secret. KHONG dong goi. Xoa hoac che di roi chay lai."
  }
  Say "[2/5] Quet secret: sach" Green

  # --- 3. Chep vao thu muc goi -------------------------------------------------------
  if (Test-Path $pack) { Remove-Item $pack -Recurse -Force }
  New-Item -ItemType Directory -Path $pack -Force | Out-Null
  foreach ($g in $groups.Keys) {
    $dest = Join-Path $pack $g
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    foreach ($f in $groups[$g]) { Copy-Item $f.FullName (Join-Path $dest $f.Name) -Force }
  }
  Say "[3/5] Da chep vao $pack" Green

  # --- 4. Cau truc database (chi LUOC DO, khong co du lieu) --------------------------
  $schemaFile = Join-Path $pack "02_sql\_luoc_do_hien_tai.sql"
  if ($SkipSchemaDump) {
    Say "[4/5] Bo qua ban chup luoc do (-SkipSchemaDump)" DarkGray
  } else {
    $dbUrl = Get-DbUrl $UrlEnvVar
    if ([string]::IsNullOrWhiteSpace($dbUrl)) {
      Say "[4/5] Khong co $UrlEnvVar - bo qua ban chup luoc do. Goi van dung duoc." DarkYellow
    } else {
      # --schema-only: KHONG co mot dong du lieu nghiep vu nao trong file nay.
      & docker run --rm -v "${pack}:/out" $PostgresImage pg_dump $dbUrl --schema-only --no-owner --no-privileges `
          "--schema=public" "--schema=app" "--file=/out/02_sql/_luoc_do_hien_tai.sql"
      if ($LASTEXITCODE -ne 0) { Say "[4/5] pg_dump that bai - bo qua." DarkYellow }
      else { Say "[4/5] Da chup luoc do (khong kem du lieu)" Green }
    }
  }

  # --- 5. Gop tat ca vao MOT file ----------------------------------------------------
  $one = Join-Path $pack "TAT_CA_TRONG_MOT.md"
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine("# KPI MEP - Goi ban giao day du")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("Sinh tu dong ngay $(Get-Date -Format 'dd/MM/yyyy HH:mm'). Day la MOT file chua toan bo du an:")
  [void]$sb.AppendLine("tai lieu nghiep vu, toan bo migration SQL, ma nguon giao dien, va script van hanh.")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("Doc PHAN 0 cua tai lieu ban giao ngay ben duoi de biet nen doc muc nao truoc.")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("**Goi nay KHONG chua bat ky khoa, mat khau hay chuoi ket noi nao** - da quet tu dong truoc khi dong goi.")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("---")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("## Huong dan cho tro ly AI doc file nay")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("Ban vua nhan toan bo mot he thong dang chay that: quan ly giao viec va dinh muc KPI")
  [void]$sb.AppendLine("cho cac to doi thi cong co dien (MEP). Truoc khi de xuat bat ky thay doi nao:")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine("1. **Doc PHAN 2** (12 quy tac nghiep vu) va **PHAN 9** (18 loi da gap) cua tai lieu")
  [void]$sb.AppendLine("   ban giao truoc tien. Phan 9 la nhung loi da ton thoi gian that - dung lap lai.")
  [void]$sb.AppendLine("2. **Moi quy tac nghiep vu nam o tang database**, khong phai o giao dien. Sua quy tac thi")
  [void]$sb.AppendLine("   sua o SQL, va phai ra soat xem quy tac do co ban sao o giao dien hay trong view khong.")
  [void]$sb.AppendLine("3. **Migration chi chay tien**, danh so tang dan. Tu 045 tro di, moi migration BAT BUOC")
  [void]$sb.AppendLine("   co file hoan tac cung ten trong 02_sql (ten bat dau bang cung so).")
  [void]$sb.AppendLine("4. Khi dung ban sao cho du an khac: **khong tai su dung ref/URL/khoa/tai khoan/dump**")
  [void]$sb.AppendLine("   cua he thong nguon. Xem PHAN 10.")
  [void]$sb.AppendLine("5. `app.v_job_metrics` la trai tim tinh toan. Doc PHAN 4 truoc khi dung vao bat cu thu")
  [void]$sb.AppendLine("   gi lien quan den tien.")
  [void]$sb.AppendLine("")
  [void]$sb.AppendLine('Neu duoc hoi -sua/them tinh nang X-, hay tra loi kem: migration nao can them, ham RPC')
  [void]$sb.AppendLine("nao doi, file giao dien nao doi, quy tac nghiep vu nao bi anh huong, va script hoan tac.")
  [void]$sb.AppendLine("")

  $order = @(
    @{ Dir = "01_tai_lieu";  Lang = "";     Title = "TAI LIEU" },
    @{ Dir = "02_sql";       Lang = "sql";  Title = "SQL - MIGRATION, HOAN TAC, LUOC DO" },
    @{ Dir = "03_giao_dien"; Lang = "tsx";  Title = "MA NGUON GIAO DIEN" },
    @{ Dir = "04_van_hanh";  Lang = "powershell"; Title = "SCRIPT VAN HANH" }
  )
  foreach ($o in $order) {
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("---")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("# ===== $($o.Title) =====")
    $files = Get-ChildItem (Join-Path $pack $o.Dir) -File | Sort-Object Name
    foreach ($f in $files) {
      $body = Get-Content $f.FullName -Raw
      [void]$sb.AppendLine("")
      [void]$sb.AppendLine("## FILE: $($o.Dir)/$($f.Name)")
      [void]$sb.AppendLine("")
      if ($o.Lang -eq "" -and $f.Extension -eq ".md") {
        # Tai lieu markdown chen thang, khong boc code fence - de doc hon nhieu.
        [void]$sb.AppendLine($body)
      } else {
        $lang = $o.Lang
        if ($f.Extension -eq ".toml") { $lang = "toml" }
        if ($f.Extension -eq ".css")  { $lang = "css" }
        if ($f.Extension -eq ".mjs" -or $f.Extension -eq ".ts") { $lang = "ts" }
        [void]$sb.AppendLine('```' + $lang)
        [void]$sb.AppendLine($body.TrimEnd())
        [void]$sb.AppendLine('```')
      }
    }
  }
  Set-Content -Path $one -Value $sb.ToString() -Encoding utf8

  # Manifest de doi chieu ve sau
  $manifest = Get-ChildItem $pack -Recurse -File | Where-Object { $_.Name -ne "MANIFEST.sha256" } |
    ForEach-Object { "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.FullName.Substring($pack.Length).TrimStart('\') }
  Set-Content -Path (Join-Path $pack "MANIFEST.sha256") -Value $manifest -Encoding ascii

  $size = (Get-Item $one).Length
  Say ("[5/5] Da gop vao mot file: {0:N0} KB" -f ($size / 1KB)) Green
  Say ""
  Say "Xong. Dua file nay sang cong cu khac:" Cyan
  Say "  $one" White
  Say "Hoac ca thu muc neu muon giu cau truc:" Cyan
  Say "  $pack" White
  exit 0
}
finally { Pop-Location }
