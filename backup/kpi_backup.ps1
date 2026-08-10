<#
.SYNOPSIS
  Sao lưu toàn bộ database Supabase ra file dump nén, tự xoay vòng.

.DESCRIPTION
  Dùng khi KHÔNG mua gói trả phí của Supabase, tức không có backup tự động nào ở phía
  nhà cung cấp. Đây là bản backup nằm trong tay bạn.

  Chạy pg_dump bằng Docker nên không cần cài PostgreSQL lên máy. Ảnh postgres:17 khớp
  với phiên bản 17.6 của Supabase; dump từ server mới hơn client sẽ bị từ chối.

  Chuỗi kết nối KHÔNG nằm trong file này và không được commit. Script đọc từ biến môi
  trường, mặc định KPI_BACKUP_DB_URL. Lấy chuỗi đó ở Supabase Dashboard →
  Project Settings → Database → Connection string → URI.

.EXAMPLE
  # Đặt một lần (mở PowerShell mới sau khi chạy để biến có hiệu lực)
  setx KPI_BACKUP_DB_URL "postgresql://postgres.xxxx:MATKHAU@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres"

  # Chạy thử
  .\backup\kpi_backup.ps1 -Label staging -OutputDir C:\KPI-Backups\staging

.NOTES
  PHẠM VI: chỉ các schema của ứng dụng — public, app, staging, mapping, reconciliation.

  KHÔNG bao gồm:
    * Tài khoản đăng nhập (schema auth). Mất project thì phải mời lại người dùng.
      Cố ý không sao lưu: trong đó có mã băm mật khẩu, để ngoài file backup thì an toàn hơn.
    * File trong Supabase Storage (bucket kpi-week-backups chứa Excel backup tuần).
      Tải riêng — xem backup/README.md.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Label,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$UrlEnvVar = "KPI_BACKUP_DB_URL",
  [int]$KeepCount = 30,
  [string]$PostgresImage = "postgres:17"
)

$ErrorActionPreference = "Stop"
$started = Get-Date

function Write-Log {
  param([string]$Message, [string]$Level = "INFO")
  $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
  Write-Output $line
  if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding utf8 }
}

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$script:LogFile = Join-Path $OutputDir "backup.log"

Write-Log "=== Bắt đầu sao lưu '$Label' ==="

$dbUrl = [Environment]::GetEnvironmentVariable($UrlEnvVar)
if ([string]::IsNullOrWhiteSpace($dbUrl)) {
  Write-Log "Không tìm thấy biến môi trường $UrlEnvVar. Xem phần hướng dẫn ở đầu file." "ERROR"
  exit 2
}

# Che chuỗi kết nối trong log: chỉ giữ host, bỏ hẳn user và mật khẩu.
$maskedHost = if ($dbUrl -match "@([^/:]+)") { $Matches[1] } else { "(không đọc được host)" }
Write-Log "Máy chủ đích: $maskedHost"

try { docker version --format "{{.Server.Version}}" | Out-Null }
catch { Write-Log "Docker chưa chạy. Bật Docker Desktop rồi thử lại." "ERROR"; exit 3 }

$stamp    = Get-Date -Format "yyyyMMdd-HHmmss"
$dumpName = "kpi_${Label}_${stamp}.dump"
$dumpPath = Join-Path $OutputDir $dumpName
$tmpPath  = "$dumpPath.partial"

Write-Log "Đang chạy pg_dump…"

# Gắn thư mục đích vào container và để pg_dump tự ghi file bên trong.
# TUYỆT ĐỐI không cho dữ liệu nhị phân đi qua pipeline của PowerShell: nó sẽ diễn giải
# thành text và làm hỏng file dump mà không báo lỗi gì.
$dumpArgs = @(
  "run", "--rm",
  "-v", "${OutputDir}:/out",
  $PostgresImage,
  "pg_dump", $dbUrl,
  "--format=custom",      # nén sẵn, khôi phục bằng pg_restore, chọn được từng bảng
  "--no-owner",           # tránh lỗi quyền khi khôi phục sang project khác
  "--no-privileges",
  # CHỈ sao lưu các schema của ứng dụng.
  # Dump toàn bộ database KHÔNG khôi phục lại được vào Supabase: bên trong có những đối
  # tượng thuộc quyền sở hữu của Supabase (ví dụ event trigger pgrst_drop_watch) mà tài
  # khoản postgres của project không có quyền tạo lại, và pg_restore sẽ dừng giữa chừng.
  "--schema=public", "--schema=app", "--schema=staging",
  "--schema=mapping", "--schema=reconciliation",
  "--file=/out/$dumpName.partial"
)
# Không dùng 2>&1: PowerShell 5.1 biến stderr của chương trình ngoài thành ErrorRecord.
& docker @dumpArgs
$code = $LASTEXITCODE

if ($code -ne 0) {
  Write-Log "pg_dump thất bại, mã lỗi $code. KHÔNG tạo bản backup nào." "ERROR"
  Remove-Item $tmpPath -ErrorAction SilentlyContinue
  exit 4
}

if (-not (Test-Path $tmpPath)) {
  Write-Log "pg_dump báo thành công nhưng không thấy file. KHÔNG giữ lại." "ERROR"
  exit 4
}
$size = (Get-Item $tmpPath).Length
if ($size -lt 10KB) {
  Write-Log "File dump chỉ $size byte — quá nhỏ, coi như hỏng. KHÔNG giữ lại." "ERROR"
  Remove-Item $tmpPath -ErrorAction SilentlyContinue
  exit 5
}

Move-Item $tmpPath $dumpPath -Force

# Ghi kèm SHA-256 để lần khôi phục sau còn kiểm tra file có nguyên vẹn không.
$hash = (Get-FileHash -Path $dumpPath -Algorithm SHA256).Hash.ToLower()
Set-Content -Path "$dumpPath.sha256" -Value "$hash  $dumpName" -Encoding ascii

Write-Log ("Đã tạo {0} ({1:N1} MB), sha256 {2}…" -f $dumpName, ($size / 1MB), $hash.Substring(0, 16))

# Xoay vòng: chỉ giữ $KeepCount bản mới nhất.
$all = Get-ChildItem -Path $OutputDir -Filter "kpi_${Label}_*.dump" | Sort-Object LastWriteTime -Descending
if ($all.Count -gt $KeepCount) {
  $old = $all | Select-Object -Skip $KeepCount
  foreach ($f in $old) {
    Remove-Item $f.FullName -Force
    Remove-Item "$($f.FullName).sha256" -Force -ErrorAction SilentlyContinue
    Write-Log "Đã xóa bản cũ: $($f.Name)"
  }
}

$kept = (Get-ChildItem -Path $OutputDir -Filter "kpi_${Label}_*.dump").Count
Write-Log ("=== Xong sau {0:N1} giây. Đang giữ {1} bản backup. ===" -f ((Get-Date) - $started).TotalSeconds, $kept)
exit 0
