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
