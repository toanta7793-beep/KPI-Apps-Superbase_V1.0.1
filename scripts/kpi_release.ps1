<#
.SYNOPSIS
  Cắt một phiên bản (ví dụ v1.0.1) và chốt lại mọi thứ cần để sau này quay về được.

.DESCRIPTION
  Một phiên bản không phải chỉ là cái tên. Muốn quay về được nguyên trạng thì tại thời
  điểm cắt phải có đủ BỐN thứ, và script này bắt buộc đủ cả bốn:

    1. Mã nguồn         -> tag Git
    2. Bản chạy web     -> mã version của Cloudflare Worker
    3. Đường đi ngược   -> script hoàn tác cho từng migration mới
    4. Dữ liệu          -> điểm khôi phục (dump + số dòng để đối chiếu)

  Thứ 3 là thứ hay bị bỏ quên nhất, và là thứ duy nhất KHÔNG thể bù lại sau. Nếu cắt
  phiên bản xong mới nhớ ra thì lược đồ đã đi tiếp rồi. Nên script từ chối cắt phiên bản
  khi còn migration chưa có script hoàn tác.

.EXAMPLE
  # Xem trước, không ghi gì
  .\scripts\kpi_release.ps1 -Version 1.0.2 -OutputDir C:\KPI-Backups\staging

  # Cắt thật
  .\scripts\kpi_release.ps1 -Version 1.0.2 -OutputDir C:\KPI-Backups\staging -Execute
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$Label = "staging",
  [string]$UrlEnvVar = "KPI_BACKUP_DB_URL",
  [string]$WorkerVersionId = "",
  [switch]$Execute
)

$ErrorActionPreference = "Stop"
function Say  { param([string]$m, [string]$c = "White") Write-Host $m -ForegroundColor $c }
function Fail { param([string]$m) Say "DUNG: $m" Red; exit 1 }

# Mốc nền: 001-044 dựng nên hệ thống hiện tại, không cần đường quay về trước chúng.
$BASELINE = 44

if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "Phien ban phai co dang X.Y.Z, vi du 1.0.2." }
$tag  = "v$Version"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
  Say "=== Cat phien ban $tag ===" Cyan
  if (-not $Execute) { Say "(Che do xem truoc - khong ghi gi. Them -Execute de lam that.)" Yellow }
  Say ""

  # --- 1. Mã nguồn ------------------------------------------------------------------
  $dirty = @(& git status --porcelain)
  if ($dirty.Count -gt 0) {
    $dirty | ForEach-Object { Say "    $_" DarkYellow }
    Fail "Cay lam viec con thay doi chua commit. Tag se khong tro dung thu dang chay."
  }
  if ((& git tag --list $tag)) { Fail "Tag $tag da ton tai. Moi phien ban chi cat mot lan." }
  $commit = (& git rev-parse HEAD).Trim()
  Say "[1/4] Ma nguon    : $($commit.Substring(0,8))" Green

  # --- 2. Đường đi ngược ------------------------------------------------------------
  # Kiểm tra TRƯỚC khi chạy bộ kiểm thử: nếu thiếu thì hỏng ngay từ đầu, không việc gì
  # bắt người dùng chờ mấy phút rồi mới báo.
  $migrations = Get-ChildItem "$repo\supabase\migrations" -Filter "*.sql" | Sort-Object Name
  $missing = @()
  foreach ($m in $migrations) {
    if ($m.Name -notmatch '^(\d+)_') { continue }
    if ([int]$Matches[1] -le $BASELINE) { continue }
    if (-not (Test-Path "$repo\supabase\rollback\$($m.Name)")) { $missing += $m.Name }
  }
  if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Say "    thieu: supabase/rollback/$_" DarkYellow }
    Fail "Con migration chua co script hoan tac. Khong cat phien ban duoc - xem supabase/rollback/README.md."
  }
  $newCount = @($migrations | Where-Object { $_.Name -match '^(\d+)_' -and [int]$Matches[1] -gt $BASELINE }).Count
  Say "[2/4] Duong nguoc : $newCount migration moi, du script hoan tac" Green

  # --- 3. Bộ kiểm thử ---------------------------------------------------------------
  Push-Location "$repo\web"
  try {
    & npm.cmd run test | Out-String -OutVariable testOut | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "Bo kiem thu that bai. Khong cat phien ban tu ban dang hong." }
    & npm.cmd run lint | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "eslint bao loi." }
  } finally { Pop-Location }
  Say "[3/4] Kiem thu    : dat" Green

  if (-not $Execute) {
    Say ""
    Say "Xem truoc xong. Moi thu san sang de cat $tag." Cyan
    Say "Chay lai voi -Execute de tao tag va diem khoi phuc." Cyan
    exit 0
  }

  # --- 4. Dữ liệu + tag -------------------------------------------------------------
  $rpName = "release-$($Version -replace '\.','-')"
  & (Join-Path $repo "backup\kpi_restore_point.ps1") -Name $rpName -OutputDir $OutputDir `
      -Label $Label -UrlEnvVar $UrlEnvVar
  if ($LASTEXITCODE -ne 0) { Fail "Khong tao duoc diem khoi phuc. Chua tao tag." }
  Say "[4/4] Du lieu     : diem khoi phuc '$rpName'" Green

  & git tag -a $tag -m "Phien ban $Version"
  if ($LASTEXITCODE -ne 0) { Fail "Khong tao duoc tag." }

  # Điểm khôi phục được tạo TRƯỚC khi có tag, nên lúc đó nó ghi "(chua dat tag)". Nếu để
  # nguyên thì file điểm khôi phục không chỉ ngược về được phiên bản nào — mà cả điểm việc
  # gắn hai thứ với nhau là để sau này nhìn một file biết ngay file kia. Điền lại ở đây.
  $rpFile = Join-Path $repo "backup\restore-points\$rpName.md"
  if (Test-Path $rpFile) {
    $rpText = Get-Content $rpFile -Raw -Encoding utf8
    $rpText = $rpText -replace '\| Tag \| \(chua dat tag\) \|', "| Tag | ``$tag`` |"
    Set-Content -Path $rpFile -Value $rpText -Encoding utf8 -NoNewline
  }

  # Ghi lại phiếu phiên bản. Mã version của Worker phải điền vào đây, nếu không sau này
  # không biết quay bản web về đâu.
  $relDir = Join-Path $repo "docs\releases"
  if (-not (Test-Path $relDir)) { New-Item -ItemType Directory -Path $relDir -Force | Out-Null }
  $workerText = if ($WorkerVersionId) { $WorkerVersionId } else { "(CHUA DIEN - chay: npx wrangler versions list)" }
  $md = @"
# Phien ban $Version

| | |
|---|---|
| Cat luc | $(Get-Date -Format "yyyy-MM-ddTHH:mm:ssK") |
| Git tag | ``$tag`` |
| Git commit | ``$commit`` |
| Diem khoi phuc | ``$rpName`` (xem backup/restore-points/$rpName.md) |
| Cloudflare Worker version | ``$workerText`` |
| Moi truong | $Label |

## Quay ve phien ban nay

Xem quy trinh day du o [docs/VERSIONING.md](../VERSIONING.md).
"@
  Set-Content -Path (Join-Path $relDir "$Version.md") -Value $md -Encoding utf8

  Say ""
  Say "Da cat phien ban $tag." Green
  if (-not $WorkerVersionId) {
    Say "CON THIEU: ma version cua Cloudflare Worker." Yellow
    Say "  cd web; npx wrangler versions list" DarkGray
    Say "  roi dien vao docs/releases/$Version.md" DarkGray
  }
  Say "Nho: git push --follow-tags va commit docs/releases/ + backup/restore-points/" Cyan
  exit 0
}
finally { Pop-Location }
