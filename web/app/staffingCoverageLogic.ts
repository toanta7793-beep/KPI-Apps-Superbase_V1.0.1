export type StaffingJob={id:string;team_id:string;group_code:string|null;count_worker1:number;count_worker2:number;count_worker3:number;count_helper:number};
export type StaffingPayrollRow={role_name:string;worker_count:number;unknown_workers:Array<{mnv:string;full_name?:string;job_title?:string}>};
export type StaffingRole="Thợ bậc 1"|"Thợ bậc 2"|"Thợ bậc 3"|"Thợ phụ";
export const staffingRoles:StaffingRole[]=["Thợ bậc 1","Thợ bậc 2","Thợ bậc 3","Thợ phụ"];
const fields:Record<StaffingRole,keyof StaffingJob>={"Thợ bậc 1":"count_worker1","Thợ bậc 2":"count_worker2","Thợ bậc 3":"count_worker3","Thợ phụ":"count_helper"};

export function calculateStaffingCoverage(jobs:StaffingJob[],payroll:StaffingPayrollRow[]){
  const headcount=Object.fromEntries(staffingRoles.map(role=>[role,Number(payroll.find(row=>row.role_name===role)?.worker_count||0)])) as Record<StaffingRole,number>;
  const assigned=Object.fromEntries(staffingRoles.map(role=>[role,0])) as Record<StaffingRole,number>,signatures=new Map<string,string>(),counted=new Set<string>(),issues:string[]=[];
  for(const job of jobs){const key=job.group_code?`GROUP:${job.group_code}`:`ROW:${job.id}`,counts=staffingRoles.map(role=>Number(job[fields[role]])||0),signature=counts.join("|");if(job.group_code&&signatures.has(key)&&signatures.get(key)!==signature)issues.push(`Mã nhóm ${job.group_code} có cơ cấu nhân sự không đồng nhất.`);if(job.group_code&&!signatures.has(key))signatures.set(key,signature);if(counted.has(key))continue;counted.add(key);staffingRoles.forEach((role,index)=>assigned[role]+=counts[index])}
  const rows=staffingRoles.map(role=>({role,headcount:headcount[role],assigned:assigned[role],difference:headcount[role]-assigned[role]}));
  const unknownCount=payroll.find(row=>row.unknown_workers?.length)?.unknown_workers.length||0;
  return {rows,issues,unknownCount,balanced:rows.every(row=>row.difference===0)&&!issues.length&&!unknownCount,countedStructures:counted.size};
}
