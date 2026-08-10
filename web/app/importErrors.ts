export function rosterImportError(message:string){
  if(/IMPORT_WOULD_DISABLE_ACTIVE_LOGIN/.test(message))return "File đang thiếu một công nhân được gắn tài khoản đăng nhập đang hoạt động. Hãy chuyển hoặc gỡ liên kết tài khoản đó trước khi thay danh sách.";
  if(/DUPLICATE_MNV/.test(message))return "File có Mã nhân viên bị trùng. Mỗi MNV chỉ được xuất hiện một lần.";
  if(/UNKNOWN_OR_AMBIGUOUS_TEAM|AMBIGUOUS_TEAM/.test(message))return "Có tên Tổ trùng hoặc không xác định được duy nhất. Hãy kiểm tra lại cột Tên Tổ.";
  if(/TEAM_MAPPING_FAILED/.test(message))return "Không ánh xạ được một hoặc nhiều Tổ sau khi kiểm tra file.";
  if(/INVALID_WORKER_ROW/.test(message))return "Có dòng thiếu MNV, họ tên, chức vụ, Tên Tổ hoặc số thứ tự trong Tổ.";
  if(/INVALID_WORKER_ROSTER_SIZE/.test(message))return "Danh sách phải có từ 1 đến 10.000 công nhân.";
  if(/UPDATE requires a WHERE clause/.test(message))return "Máy chủ đang dùng phiên bản RPC nhập Excel cũ. Hãy tải lại trang rồi thử lại.";
  return message;
}

export function catalogImportError(message:string){
  if(/FORBIDDEN/.test(message))return "Chỉ tài khoản ADMIN được nhập danh mục/đơn giá/bảng lương.";
  if(/DUPLICATE_PRICE_KEY/.test(message))return "File có dòng trùng khóa Hạng mục Cấp 1 + Nội dung Cấp 2. Mỗi khóa chỉ được xuất hiện một lần.";
  if(/MISSING_UNIT/.test(message))return "Có dòng thiếu Đơn vị.";
  if(/INVALID_PRICE_VALUE/.test(message))return "Có dòng đơn giá trống hoặc âm.";
  if(/ILLEGAL_LOOKUP_SEPARATOR/.test(message))return "Có ô chứa ký tự ‡ dành riêng cho khóa tra cứu của hệ thống.";
  if(/INVALID_PRICE_ROW/.test(message))return "Có dòng thiếu Hạng mục Cấp 1 hoặc Nội dung công việc Cấp 2.";
  if(/INVALID_PRICE_CATALOG_SIZE/.test(message))return "Danh mục đơn giá phải có từ 1 đến 20.000 dòng.";
  if(/DUPLICATE_SALARY_KEY/.test(message))return "File có dòng trùng khóa Hệ + Chức danh.";
  if(/AMBIGUOUS_SYSTEM_NAME/.test(message))return "Có hai cách viết khác nhau cho cùng một Hệ. Hãy viết thống nhất một cách.";
  if(/AMBIGUOUS_GRADE_NAME/.test(message))return "Có hai cách viết khác nhau cho cùng một Chức danh. Hãy viết thống nhất một cách.";
  if(/NEGATIVE_SALARY/.test(message))return "Có dòng mức lương âm.";
  if(/INVALID_SALARY_ROW/.test(message))return "Có dòng thiếu Hệ hoặc Chức danh.";
  if(/INVALID_SALARY_TABLE_SIZE/.test(message))return "Bảng lương phải có từ 1 đến 5.000 dòng.";
  if(/UNRESOLVED_SYSTEM_OR_GRADE/.test(message))return "Không tạo hoặc không tìm được Hệ/Chức danh tương ứng. Kiểm tra lại cách viết trong file.";
  if(/INVALID_SOURCE_HASH|IMPORT_METADATA_REQUIRED/.test(message))return "Thiếu thông tin nhận dạng file. Hãy chọn lại file rồi thử lại.";
  if(/Could not find the function|schema cache/.test(message))return "Máy chủ chưa có RPC nhập danh mục (migration 032/033). Hãy chạy migration rồi tải lại trang.";
  return message;
}
