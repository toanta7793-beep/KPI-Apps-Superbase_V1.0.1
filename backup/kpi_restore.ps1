<#
.SYNOPSIS
  Khôi phục database từ file dump do kpi_backup.ps1 tạo ra.

.DESCRIPTION
  KHÔI PHỤC LÀ THAO TÁC GHI ĐÈ. Script này cố ý khó dùng sai:

    * Mặc định chỉ CHẠY THỬ, in ra mọi thứ sẽ làm mà không ghi gì. Muốn ghi thật phải
      thêm -Execute.
    * Phải nhập -ConfirmLabel đúng bằng nhãn nằm trong tên file dump.
    * Kiểm tra SHA-256 trước; sai là dừng, không khôi phục từ file hỏng.
    * Đích khôi phục đọc từ MỘT biến môi trường KHÁC với biến dùng để sao lưu, nên
      không thể vô tình ghi đè nhầm chỉ vì gõ thiếu tham số.

  QUAN TRỌNG — trên Supabase phải dựng CẤU TRÚC trước rồi mới nạp DỮ LIỆU.

  Không dùng được pg_restore --clean, đã thử và đều hỏng:
    * --clean với schema-scoped dump sinh ra DROP SCHEMA public, mà Supabase có đối tượng
      phụ thuộc vào schema đó -> "cannot drop schema public because other objects depend on it".
    * Nếu một bảng đã bị xóa hẳn thì DROP TRIGGER ... ON bảng-đó vẫn lỗi, vì --if-exists
      chỉ bỏ qua trigger chứ không bỏ qua bảng không tồn tại.
    * Dump toàn bộ database còn hỏng sớm hơn: "must be owner of event trigger pgrst_drop_watch".

  Nên quy trình đúng gồm HAI bước, và bước 1 do người vận hành chạy trước:

    Bước 1 — dựng lại cấu trúc từ chính mã nguồn, KHÔNG nạp seed:
        supabase db reset --no-seed          (môi trường cục bộ)
        supabase db push                     (project mới, còn trống)
      Làm vậy còn bảo đảm cấu trúc khớp đúng phiên bản mã nguồn đang dùng.

    Bước 2 — chạy script này để nạp dữ liệu vào cấu trúc rỗng đó.

  Script nạp bằng --data-only nên bảng đích PHẢI RỖNG, nếu không sẽ đụng khóa chính.

.EXAMPLE
  # Bước 1 — xem trước, không ghi gì
  .\backup\kpi_restore.ps1 -DumpFile C:\KPI-Backups\staging\kpi_staging_20260811-020000.dump -ConfirmLabel staging

  # Bước 2 — ghi thật, sau khi đã đọc kỹ bước 1
  setx KPI_RESTORE_DB_URL "postgresql://..."
  .\backup\kpi_restore.ps1 -DumpFile ... -ConfirmLabel staging -Execute

.NOTES
  Khôi phục KHÔNG mang lại file trong Supabase Storage. Xem backup/README.md.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$DumpFile,
  [Parameter(Mandatory = $true)][string]$ConfirmLabel,
  [string]$UrlEnvVar = "KPI_RESTORE_DB_URL",
  [switch]$Execute,
  [string]$PostgresImage = "postgres:17"
)

$ErrorActionPreference = "Stop"

function Say { param([string]$m, [string]$c = "White") Write-Host $m -ForegroundColor $c }

if (-not (Test-Path $DumpFile)) { Say "Không thấy file: $DumpFile" Red; exit 2 }
$dump = Get-Item $DumpFile

if ($dump.Name -notmatch '^kpi_(?<label>.+?)_\d{8}-\d{6}\.dump$') {
  Say "Tên file không đúng dạng kpi_<nhãn>_<ngày giờ>.dump — không xác định được nhãn." Red
  exit 3
}
$fileLabel = $Matches['label']
if ($fileLabel -ne $ConfirmLabel) {
  Say "Nhãn không khớp. File thuộc '$fileLabel' nhưng bạn xác nhận '$ConfirmLabel'." Red
  Say "Dừng lại để tránh khôi phục nhầm môi trường." Red
  exit 4
}

Say "=== KIỂM TRA FILE ===" Cyan
$sidecar = "$($dump.FullName).sha256"
if (Test-Path $sidecar) {
  $expected = ((Get-Content $sidecar -Raw) -split '\s+')[0].ToLower()
  $actual = (Get-FileHash -Path $dump.FullName -Algorithm SHA256).Hash.ToLower()
  if ($expected -ne $actual) {
    Say "SHA-256 KHÔNG khớp. File đã hỏng hoặc bị sửa. KHÔNG khôi phục." Red
    Say "  ghi khi backup: $expected" Red
    Say "  tính lại bây giờ: $actual" Red
    exit 5
  }
  Say "SHA-256 khớp: $($actual.Substring(0,16))…" Green
} else {
  Say "CẢNH BÁO: không có file .sha256 kèm theo, không kiểm tra được tính nguyên vẹn." Yellow
}

Say ("File   : {0}" -f $dump.Name)
Say ("Kích cỡ: {0:N1} MB" -f ($dump.Length / 1MB))
Say ("Tạo lúc: {0}" -f $dump.LastWriteTime)
Say ("Nhãn   : {0}" -f $fileLabel)

$dbUrl = [Environment]::GetEnvironmentVariable($UrlEnvVar)
if ([string]::IsNullOrWhiteSpace($dbUrl)) {
  Say ""
  Say "Chưa đặt biến môi trường $UrlEnvVar nên chưa có đích khôi phục." Yellow
  Say "Đây là biến RIÊNG, khác với biến dùng khi sao lưu — cố ý như vậy." Yellow
  exit 6
}
$maskedHost = if ($dbUrl -match "@([^/:]+)") { $Matches[1] } else { "(không đọc được host)" }

Say ""
Say "=== SẼ GHI ĐÈ LÊN ===" Yellow
Say "  $maskedHost" Yellow
Say ""
Say "pg_restore chạy với --data-only: chỉ nạp DỮ LIỆU, không đụng cấu trúc."
Say ""
Say "Trước khi chạy bước này, cấu trúc phải đã được dựng lại và các bảng phải RỖNG:" 
Say "    supabase db reset --no-seed     (môi trường cục bộ)"
Say "    supabase db push                (project mới, còn trống)"
Say "Nếu bảng đích còn dữ liệu, lệnh sẽ đụng khóa chính và quay lui toàn bộ." 

if (-not $Execute) {
  Say ""
  Say "ĐANG CHẠY THỬ — chưa ghi gì cả." Green
  Say "Đọc kỹ dòng máy chủ đích ở trên. Nếu đúng, chạy lại kèm -Execute." Green
  exit 0
}

Say ""
Say "=== KIỂM TRA BẢN DUMP CÓ ĐỌC ĐƯỢC KHÔNG (chưa ghi gì) ===" Cyan
$dumpDirPre = $dump.DirectoryName
# Không dùng 2>&1 với chương trình ngoài: PowerShell 5.1 biến mọi dòng stderr thành
# ErrorRecord, kể cả NOTICE vô hại, và làm hỏng việc kiểm tra kết quả.
$listOut = & docker run --rm -v "${dumpDirPre}:/in" $PostgresImage pg_restore --list "/in/$($dump.Name)"
if ($LASTEXITCODE -ne 0) {
  Say "Không đọc được bản dump. KHÔNG làm gì thêm." Red
  exit 8
}
$entries = ($listOut | Where-Object { $_ -notmatch '^;' }).Count
Say "Bản dump hợp lệ, chứa $entries mục dữ liệu." Green

Say ""
Say "=== LÀM RỖNG BẢNG ĐÍCH TRƯỚC KHI NẠP ===" Yellow
# Bắt buộc vì --data-only sẽ đụng khóa chính nếu bảng còn dòng. Một số bảng đã có sẵn dữ
# liệu ngay sau khi chạy migration (ví dụ public.roles do migration 020 chèn).
# Chỉ chạy sau khi bản dump đã qua được bước kiểm tra ở trên.
$truncateSql = @"
set client_min_messages = warning;
do `$`$ declare r record; begin
  for r in select schemaname, tablename from pg_tables
           where schemaname in ('public','app','staging','mapping','reconciliation')
  loop execute format('truncate table %I.%I cascade', r.schemaname, r.tablename); end loop;
end `$`$;
"@
& docker run --rm -i $PostgresImage psql "$dbUrl" -v ON_ERROR_STOP=1 -q -c $truncateSql
if ($LASTEXITCODE -ne 0) {
  Say "Không làm rỗng được bảng đích. Dừng, chưa nạp gì." Red
  exit 9
}
Say "Đã làm rỗng các bảng trong 5 schema ứng dụng." Green

Say ""
Say "Bắt đầu nạp dữ liệu…" Yellow
# Gắn thư mục chứa dump vào container. Không đưa file nhị phân qua pipeline PowerShell.
#
# Vì sao phải nối pg_restore qua psql thay vì gọi pg_restore thẳng:
# pg_restore nạp dữ liệu theo thứ tự trong bản dump, thứ tự đó KHÔNG bảo đảm thỏa khóa
# ngoại — thực tế đã vỡ ở salary_standards vì nó được nạp trước systems.
# Cách xử lý thông thường là --disable-triggers, nhưng cờ đó cần quyền superuser mà tài
# khoản postgres của Supabase không có ("permission denied: ... is a system trigger").
# Nên ở đây xuất SQL ra rồi cho chạy qua psql với session_replication_role = replica —
# tạm ngưng kiểm tra khóa ngoại trong đúng phiên nạp, và quyền postgres làm được điều này.
# Toàn bộ nằm trong MỘT transaction: lỗi ở bất kỳ đâu là quay lui sạch.
$dumpDir = $dump.DirectoryName
# pipefail là bắt buộc: không có nó thì mã thoát chỉ phản ánh psql ở cuối ống, và
# pg_restore hỏng vẫn cho ra "thành công". Đã dính đúng bẫy này khi diễn tập.
# Dùng bash chứ không phải sh: sh trong ảnh này là dash, không có pipefail.
$inner = "set -o pipefail; " +
         "{ echo 'set session_replication_role = replica;'; " +
         "pg_restore --data-only --no-owner --no-privileges -f - /in/$($dump.Name); } | " +
         "psql '$dbUrl' -v ON_ERROR_STOP=1 --single-transaction -q"
& docker run --rm -v "${dumpDir}:/in" $PostgresImage bash -c $inner
$code = $LASTEXITCODE

if ($code -ne 0) {
  Say "pg_restore thất bại, mã lỗi $code. Vì chạy trong một transaction nên database đã quay lui, không bị nửa vời." Red
  exit 7
}
Say "Khôi phục xong. Hãy mở ứng dụng đối chiếu số liệu trước khi coi là hoàn tất." Green
exit 0
