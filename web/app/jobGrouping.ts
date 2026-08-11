export type GroupableJob={id:string;team_id:string;start_date:string;end_date:string;content:string;location:string|null;count_leader:number;count_worker1:number;count_worker2:number;count_worker3:number;count_helper:number;group_code:string|null;unit_price:number|null;work_days:number;production_value:number|null;actual_labor_cost:number|null};

// Các điều kiện dưới đây phải khớp ĐÚNG với create_job_group trong database. Đây là bản
// sao ở giao diện, chỉ để báo lỗi sớm và bằng tiếng người; database mới là nơi chặn thật.
//
// Đã có lúc hai bên lệch nhau: migration 041 bỏ yêu cầu trùng vị trí ở database, nhưng bản
// sao ở đây vẫn giữ. Vì giao diện chặn TRƯỚC khi gọi database nên bản sửa ở database không
// hề có tác dụng nhìn thấy được. Sửa quy tắc gộp ở một bên thì phải sửa cả bên kia.
export function validateJobGroup(jobs:GroupableJob[]){
  if(jobs.length<2)return "Phải chọn ít nhất 2 công việc để tạo Mã Nhóm.";
  const first=jobs[0],counts:(keyof GroupableJob)[]=["count_leader","count_worker1","count_worker2","count_worker3","count_helper"];
  for(const job of jobs){
    if(job.group_code)return `Công việc “${job.content}” đã thuộc nhóm ${job.group_code}. Hãy xóa mã nhóm cũ trước.`;
    if(job.team_id!==first.team_id)return `Công việc “${job.content}” không cùng Tổ với công việc đầu tiên.`;
    if(job.start_date!==first.start_date||job.end_date!==first.end_date)return `Công việc “${job.content}” không cùng khoảng ngày.`;
    // Phải CÓ vị trí, nhưng KHÔNG cần trùng nhau: một tổ trong cùng một ngày có thể làm ở
    // hai vị trí khác nhau. Kiểm mọi việc chứ không chỉ việc đầu — database cũng kiểm mọi việc.
    if(!(job.location||"").trim())return `Công việc “${job.content}” chưa có Vị trí thi công.`;
    if(counts.some(k=>Number(job[k]||0)!==Number(first[k]||0)))return `Công việc “${job.content}” không cùng cơ cấu nhân sự.`;
    if(!(Number(job.unit_price)>0)||!(Number(job.work_days)>0)||!(Number(job.production_value)>0)||Number(job.actual_labor_cost)<0)return `Công việc “${job.content}” chưa đủ Đơn giá, Số ngày, Giá trị sản lượng hoặc Chi phí nhân công.`;
  }
  return "";
}
