export type GroupableJob={id:string;team_id:string;start_date:string;end_date:string;content:string;location:string|null;count_leader:number;count_worker1:number;count_worker2:number;count_worker3:number;count_helper:number;group_code:string|null;unit_price:number|null;work_days:number;production_value:number|null;actual_labor_cost:number|null};

export function validateJobGroup(jobs:GroupableJob[]){
  if(jobs.length<2)return "Phải chọn ít nhất 2 công việc để tạo Mã Nhóm.";
  const first=jobs[0],counts:(keyof GroupableJob)[]=["count_leader","count_worker1","count_worker2","count_worker3","count_helper"];
  if(!(first.location||"").trim())return `Công việc “${first.content}” chưa có Vị trí thi công.`;
  for(const job of jobs){
    if(job.group_code)return `Công việc “${job.content}” đã thuộc nhóm ${job.group_code}. Hãy xóa mã nhóm cũ trước.`;
    if(job.team_id!==first.team_id)return `Công việc “${job.content}” không cùng Tổ với công việc đầu tiên.`;
    if(job.start_date!==first.start_date||job.end_date!==first.end_date)return `Công việc “${job.content}” không cùng khoảng ngày.`;
    if((job.location||"").trim()!==(first.location||"").trim())return `Công việc “${job.content}” không cùng Vị trí.`;
    if(counts.some(k=>Number(job[k]||0)!==Number(first[k]||0)))return `Công việc “${job.content}” không cùng cơ cấu nhân sự.`;
    if(!(Number(job.unit_price)>0)||!(Number(job.work_days)>0)||!(Number(job.production_value)>0)||Number(job.actual_labor_cost)<0)return `Công việc “${job.content}” chưa đủ Đơn giá, Số ngày, Giá trị sản lượng hoặc Chi phí nhân công.`;
  }
  return "";
}
