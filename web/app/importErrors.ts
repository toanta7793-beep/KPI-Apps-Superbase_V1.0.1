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

/**
 * Dịch mã lỗi RPC sang tiếng Việt cho các thao tác Tuần / Giao việc / Nhóm việc / Xóa tuần.
 * Trả lại nguyên văn nếu không nhận ra, để không nuốt mất thông tin gỡ lỗi.
 */
const OPERATION_MESSAGES:Array<[RegExp,string]>=[
  // Tuần
  [/INVALID_WEEK_RANGE_MAX_9_DAYS/,"Một tuần chỉ được tối đa 9 ngày, tính cả ngày đầu và ngày cuối. Hãy rút ngắn khoảng ngày."],
  [/SHARED_WEEK_OVERLAP/,"Khoảng ngày này chồng lên một Tuần đang hoạt động khác. Các tuần không được trùng ngày nào."],
  [/INVALID_WEEK_SLOT/,"Chỉ có 4 slot Tuần (1–4). Hãy chọn lại số tuần."],
  [/INVALID_DATES/,"Ngày không hợp lệ. Nhập theo dd/mm/yyyy và ngày kết thúc không được trước ngày bắt đầu."],
  [/SHARED_WEEK_NOT_FOUND/,"Không tìm thấy Tuần dùng chung đang hoạt động cho slot này. Hãy tạo Tuần trước."],
  [/WEEK_NOT_FOUND/,"Không tìm thấy Tuần của Tổ này. Hãy tải lại trang rồi thử lại."],
  [/WEEK_NOT_ACTIVE/,"Tuần này không còn ở trạng thái hoạt động."],
  [/EDIT_WOULD_EXCLUDE_ASSIGNED_JOB/,"Khoảng ngày mới sẽ đẩy một việc đã gộp ra ngoài Tuần. Hãy gỡ việc đó khỏi Tuần trước khi sửa."],
  // Gộp việc vào tuần
  [/JOB_ALREADY_IN_WEEK/,"Có việc đã thuộc một Tuần rồi. Hãy bỏ chọn việc đó, hoặc hủy gộp nó trước."],
  [/JOB_DATES_OUTSIDE_SHARED_WEEK/,"Có việc nằm ngoài khoảng ngày của Tuần. Sửa ngày của việc hoặc chọn Tuần khác."],
  [/JOB_MUST_FIT_SHARED_WEEK/,"Có việc đã thuộc Tuần khác, hoặc ngày của việc nằm ngoài khoảng Tuần."],
  [/PARTIAL_SHARED_WEEK_ASSIGNMENT|PARTIAL_ASSIGNMENT/,"Không gộp được đủ các việc đã chọn nên hệ thống đã hủy toàn bộ thao tác. Không có việc nào bị thay đổi."],
  [/EMPTY_JOB_SELECTION/,"Chưa chọn việc nào."],
  [/DUPLICATE_JOB_IDS|JOB_NOT_FOUND_OR_DUPLICATE_IDS/,"Danh sách việc bị lặp. Hãy tải lại trang rồi chọn lại."],
  [/JOB_NOT_FOUND/,"Không tìm thấy một hoặc nhiều việc đã chọn. Có thể việc vừa bị người khác xóa."],
  [/JOB_OUTSIDE_ASSIGNED_WEEK|JOB_WEEK_VALIDATION_FAILED|DATE_OUTSIDE_ACTIVE_WEEK/,"Ngày của việc không nằm trong Tuần đang gán."],
  // Giao việc
  [/CONTENT_NOT_IN_CATALOG|INVALID_CONTENT/,"Nội dung công việc không có trong danh mục cấp 2. Hãy chọn từ danh sách gợi ý."],
  [/INVALID_CATEGORY/,"Hạng mục cấp 1 không hợp lệ."],
  [/PRICE_NOT_UNIQUE_OR_MISSING/,"Không tra được đơn giá duy nhất cho công việc này. Kiểm tra lại danh mục đơn giá."],
  [/INVALID_QUANTITY/,"Khối lượng phải là số dương."],
  [/INVALID_COUNTS/,"Số lượng nhân công không hợp lệ."],
  [/REMOVE_GROUP_BEFORE_EDIT/,"Việc này đang nằm trong một mã nhóm. Hãy xóa mã nhóm trước khi sửa."],
  [/IDEMPOTENCY_KEY_REUSED/,"Thao tác này đã được ghi nhận trước đó. Hãy tải lại trang để xem kết quả."],
  // Nhóm việc
  [/AT_LEAST_TWO_JOBS/,"Cần chọn ít nhất 2 việc để tạo mã nhóm."],
  [/REMOVE_EXISTING_GROUP_FIRST/,"Có việc đã thuộc một mã nhóm khác. Hãy xóa mã nhóm cũ trước."],
  [/GROUP_TEAM_MISMATCH/,"Các việc trong một nhóm phải cùng một Tổ."],
  [/GROUP_DATE_MISMATCH/,"Các việc trong một nhóm phải cùng khoảng ngày."],
  [/GROUP_LOCATION_MISMATCH/,"Các việc trong một nhóm phải cùng vị trí thi công."],
  [/GROUP_LOCATION_REQUIRED/,"Phải nhập vị trí thi công trước khi tạo mã nhóm."],
  [/GROUP_STAFFING_MISMATCH/,"Các việc trong một nhóm phải cùng cơ cấu nhân sự."],
  [/GROUP_METRICS_INCOMPLETE/,"Thiếu số liệu để tính nhóm. Kiểm tra khối lượng và đơn giá."],
  [/GROUP_NOT_FOUND|GROUP_CODE_REQUIRED/,"Không tìm thấy mã nhóm."],
  [/GROUP_VALIDATION_FAILED/,"Nhóm việc không hợp lệ nên hệ thống đã hủy toàn bộ thao tác."],
  // Xóa tuần / backup
  [/BACKUP_NOT_VERIFIED|INVALID_BACKUP_PROOF/,"Chưa xác minh được file backup nên hệ thống KHÔNG xóa gì. Dữ liệu tuần vẫn nguyên vẹn."],
  [/ARCHIVE_COUNT_MISMATCH|DELETE_COUNT_MISMATCH/,"Số dòng backup không khớp số dòng thực tế nên hệ thống đã dừng và KHÔNG xóa gì."],
  [/WEEK_CHANGED_AFTER_SNAPSHOT/,"Dữ liệu tuần đã thay đổi sau khi chụp ảnh backup. Hãy chạy lại từ đầu."],
  [/ARCHIVE_OPERATION_NOT_FOUND/,"Không tìm thấy thao tác backup. Hãy bấm lại nút Backup & Xóa Tuần."],
  [/INVALID_EXCEL_BACKUP_SIZE/,"File backup rỗng hoặc quá lớn nên hệ thống KHÔNG xóa gì."],
  [/SERVER_ARCHIVE_NOT_CONFIGURED/,"Máy chủ chưa cấu hình khóa quản trị cho chức năng backup. Liên hệ quản trị hệ thống."],
  // Chung
  [/FORBIDDEN/,"Bạn không có quyền thực hiện thao tác này, hoặc Tổ này nằm ngoài phạm vi của bạn."],
  [/TEAM_NOT_ACTIVE/,"Tổ này không còn hoạt động."],
  [/TEAM_NOT_FOUND/,"Không tìm thấy Tổ."],
  [/Could not find the function|schema cache/,"Máy chủ chưa có phiên bản RPC mới nhất. Hãy chạy migration rồi tải lại trang."],
];

export function operationError(message:string){
  for(const [pattern,text] of OPERATION_MESSAGES){ if(pattern.test(message)) return text; }
  return message;
}
