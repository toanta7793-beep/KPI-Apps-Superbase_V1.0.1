<#
.SYNOPSIS
  Tạo MỘT ĐIỂM KHÔI PHỤC có tên: chốt lại đồng thời mã nguồn, dữ liệu và trạng thái database.

.DESCRIPTION
  Sao lưu database không đủ để "quay lại đúng thời điểm này". Một thời điểm của hệ thống
  gồm BA phần, nằm ở ba nơi khác nhau:

    1. Mã nguồn + các file migration  -> nằm trong Git
    2. Dữ liệu (dòng trong bảng)      -> nằm trong file dump
    3. Cấu trúc bảng/hàm của database -> KHÔNG có bản chụp riêng

  Phần 3 là chỗ dễ nhầm nhất. kpi_restore.ps1 dùng --data-only, tức chỉ nạp lại DỮ LIỆU;
  nó KHÔNG đưa cấu trúc bảng về như cũ. Hệ thống cũng KHÔNG có migration lùi (down) nào.
  Vì vậy có hai kiểu quay lại, khác nhau nhiều về công sức — xem file .md sinh ra.

  Script không gửi gì ra ngoài và không in chuỗi kết nối. Chuỗi kết nối đọc từ biến môi
  trường, giống kpi_backup.ps1.

.EXAMPLE
  .\backup\kpi_restore_point.ps1 -Name truoc-khi-doi-cong-thuc-luong -OutputDir C:\KPI-Backups\staging
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Name,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$Label = "staging",
  [string]$UrlEnvVar = "KPI_BACKUP_DB_URL",
  [string]$PostgresImage = "postgres:17",
  [switch]$AllowDirtyTree
)

$ErrorActionPreference = "Stop"

# setx ghi bien o pham vi User, nhung cua so PowerShell dang mo tu truoc do khong duoc nap
# lai. Doc theo thu tu Process -> User -> Machine de khong bao "khong tim thay bien" trong
# khi bien that su da duoc dat - loi do rat kho doan ra.
function Get-DbUrl {
  param([string]$Name)
  foreach ($scope in @("Process", "User", "Machine")) {
    $v = [Environment]::GetEnvironmentVariable($Name, $scope)
    if (-not [string]::IsNullOrWhiteSpace($v)) { return $v }
  }
  return $null
}

function Say { param([string]$m, [string]$c = "White") Write-Host $m -ForegroundColor $c }

if ($Name -notmatch '^[a-z0-9][a-z0-9-]{2,58}$') {
  Say "Ten diem khoi phuc chi dung chu thuong, so va dau gach ngang, 3-59 ky tu." Red
  exit 2
}

$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
  # --- Phần 1: mã nguồn ------------------------------------------------------------
  # Cây làm việc còn thay đổi chưa commit thì nửa mã nguồn của điểm khôi phục là thứ không
  # tái tạo được: commit ghi trong manifest KHÔNG chứa các sửa đổi đang dang dở.
  $dirty = @(& git status --porcelain)
  if ($dirty.Count -gt 0 -and -not $AllowDirtyTree) {
    Say "Cay lam viec con thay doi chua commit. Commit truoc, neu khong diem khoi phuc se sai." Red
    $dirty | ForEach-Object { Say "    $_" DarkYellow }
    Say "Co tinh bo qua thi them -AllowDirtyTree, nhung phan ma nguon se khong quay lai dung duoc." DarkYellow
    exit 3
  }
  $commit = (& git rev-parse HEAD).Trim()
  $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
  $tags   = @(& git tag --points-at HEAD)
  Say "Ma nguon : $($commit.Substring(0,8)) tren nhanh $branch" Cyan

  # --- Phần 2: dữ liệu -------------------------------------------------------------
  $before = @(Get-ChildItem -Path $OutputDir -Filter "kpi_${Label}_*.dump" -ErrorAction SilentlyContinue |
              ForEach-Object { $_.Name })
  & (Join-Path $PSScriptRoot "kpi_backup.ps1") -Label $Label -OutputDir $OutputDir `
      -UrlEnvVar $UrlEnvVar -PostgresImage $PostgresImage
  if ($LASTEXITCODE -ne 0) { Say "Sao luu that bai. KHONG tao diem khoi phuc." Red; exit 4 }

  $dump = Get-ChildItem -Path $OutputDir -Filter "kpi_${Label}_*.dump" |
          Where-Object { $before -notcontains $_.Name } |
          Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $dump) { Say "Khong thay file dump vua tao. KHONG tao diem khoi phuc." Red; exit 4 }
  $sha = (Get-Content "$($dump.FullName).sha256" -Raw).Split(" ")[0]
  Say "Du lieu  : $($dump.Name)" Cyan

  # --- Phần 3: chụp TRẠNG THÁI để đối chiếu (không phải để nạp lại) ------------------
  # Ghi lại sổ migration và số dòng các bảng cốt lõi. Khôi phục xong thì đối chiếu với
  # các con số này; lệch là biết ngay chứ không phải đoán.
  $dbUrl = Get-DbUrl $UrlEnvVar
  if ([string]::IsNullOrWhiteSpace($dbUrl)) { Say "Thieu bien moi truong $UrlEnvVar." Red; exit 2 }
  $probe = @"
select 'migration=' || string_agg(version, ',' order by version) from supabase_migrations.schema_migrations;
select 'to=' || count(*) from public.teams where deleted_at is null;
select 'cong_nhan=' || count(*) from public.workers where deleted_at is null;
select 'viec=' || count(*) from public.jobs where deleted_at is null;
select 'don_gia=' || count(*) from public.price_items where is_active;
select 'tuan=' || count(*) from public.shared_work_weeks where status = 'ACTIVE';
select 'tai_khoan=' || count(*) from public.profiles where is_active;
"@
  $probeOut = & docker run --rm -i $PostgresImage psql "$dbUrl" -tA -v ON_ERROR_STOP=1 -c $probe
  if ($LASTEXITCODE -ne 0) { Say "Khong doc duoc trang thai database. KHONG tao diem khoi phuc." Red; exit 5 }
  $state = @{}
  foreach ($line in $probeOut) { if ($line -match '^([a-z_]+)=(.*)$') { $state[$Matches[1]] = $Matches[2] } }
  Say "Migration: $($state['migration'])" Cyan

  # --- Ghi manifest ----------------------------------------------------------------
  $stamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
  $manifest = [ordered]@{
    ten               = $Name
    tao_luc           = $stamp
    moi_truong        = $Label
    git_commit        = $commit
    git_nhanh         = $branch
    git_tag           = $tags
    cay_lam_viec_sach = [bool]($dirty.Count -eq 0)
    dump_file         = $dump.Name
    dump_sha256       = $sha
    dump_bytes        = $dump.Length
    trang_thai        = $state
  }
  $jsonPath = Join-Path $OutputDir "diem-khoi-phuc_$Name.json"
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $jsonPath -Encoding utf8

  $lastMigration = ($state['migration'] -split ',' | Select-Object -Last 1)
  $tagText = if ($tags.Count -gt 0) { $tags -join ', ' } else { '(chua dat tag)' }

  # Bản sao trong repo để đi theo lịch sử Git. KHÔNG chứa chuỗi kết nối hay đường dẫn máy.
  # Trong here-string @"..."@ dấu backtick là ký tự thoát, nên muốn in ra MỘT backtick
  # phải viết HAI, và hàng rào code ba backtick phải viết thành sáu.
  $repoDir = Join-Path $PSScriptRoot "restore-points"
  if (-not (Test-Path $repoDir)) { New-Item -ItemType Directory -Path $repoDir -Force | Out-Null }
  $md = @"
# Điểm khôi phục: $Name

| | |
|---|---|
| Tạo lúc | $stamp |
| Môi trường | $Label |
| Git commit | ``$commit`` |
| Nhánh | $branch |
| Tag | $tagText |
| File dump | ``$($dump.Name)`` |
| SHA-256 | ``$sha`` |
| Migration đã chạy | $($state['migration']) |

Số liệu tại thời điểm chụp — dùng để đối chiếu SAU KHI khôi phục:

| Bảng | Số dòng |
|---|---|
| Tổ | $($state['to']) |
| Công nhân | $($state['cong_nhan']) |
| Việc đã giao | $($state['viec']) |
| Dòng đơn giá đang dùng | $($state['don_gia']) |
| Tuần đang mở | $($state['tuan']) |
| Tài khoản đang hoạt động | $($state['tai_khoan']) |

## Cách quay lại điểm này

**Trường hợp 1 — chỉ dữ liệu sai, cấu trúc bảng không đổi.**
Thường gặp: nhập nhầm file đơn giá, xóa nhầm việc, sửa hỏng danh sách công nhân.

``````
git checkout $commit
.\backup\kpi_restore.ps1 -DumpFile <thu-muc>\$($dump.Name) -ConfirmLabel $Label -Execute
``````

Nạp xong phải mở ứng dụng đối chiếu đúng các con số trong bảng trên rồi mới coi là xong.

**Trường hợp 2 — đã chạy thêm migration sau thời điểm này, cấu trúc bảng đã đổi.**
kpi_restore.ps1 dùng ``--data-only`` nên KHÔNG đưa cấu trúc bảng về như cũ, và hệ thống
không có migration lùi. Hai đường:

* *Chắc chắn* — tạo project Supabase MỚI, chạy migration tới đúng mốc $lastMigration,
  rồi nạp dump vào đó. Đây là bản sao đúng nguyên trạng, đổi lại phải trỏ ứng dụng sang
  project mới.
* *Nhanh* — viết một migration mới đảo ngược thay đổi. Nhanh hơn nhưng phải tự kiểm
  chứng từng thứ, và với thay đổi lớn thì dễ sót.

## Điểm này KHÔNG chứa

* **Tài khoản đăng nhập.** Schema ``auth`` cố tình không sao lưu vì trong đó có mã băm
  mật khẩu; để ngoài file backup thì an toàn hơn. Mất project là phải mời lại người dùng.
* **File trong Storage**, gồm cả Excel lưu khi xóa tuần. Phải tải riêng.
* **Mọi thay đổi xảy ra sau $stamp.** Khôi phục là mất hẳn phần đó, không lấy lại được.
"@
  Set-Content -Path (Join-Path $repoDir "$Name.md") -Value $md -Encoding utf8

  Say ""
  Say "Da tao diem khoi phuc '$Name'." Green
  Say "  $jsonPath" DarkGray
  Say "  $repoDir\$Name.md  <- nho commit file nay" DarkGray
  exit 0
}
finally { Pop-Location }
