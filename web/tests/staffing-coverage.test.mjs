import test from "node:test";import assert from "node:assert/strict";import {calculateStaffingCoverage} from "../app/staffingCoverageLogic.ts";
const payroll=[
  {role_name:"Thợ bậc 1",worker_count:2,unknown_workers:[]},{role_name:"Thợ bậc 2",worker_count:3,unknown_workers:[]},
  {role_name:"Thợ bậc 3",worker_count:4,unknown_workers:[]},{role_name:"Thợ phụ",worker_count:5,unknown_workers:[]},
];
test("counts ungrouped rows once and a shared group structure once",()=>{
  const jobs=[
    {id:"a",team_id:"t",group_code:null,count_worker1:1,count_worker2:0,count_worker3:0,count_helper:0},
    {id:"b",team_id:"t",group_code:"MN-1",count_worker1:0,count_worker2:2,count_worker3:1,count_helper:0},
    {id:"c",team_id:"t",group_code:"MN-1",count_worker1:0,count_worker2:2,count_worker3:1,count_helper:0},
    {id:"d",team_id:"t",group_code:null,count_worker1:0,count_worker2:0,count_worker3:1,count_helper:2},
  ];
  const result=calculateStaffingCoverage(jobs,payroll);assert.equal(result.countedStructures,3);assert.deepEqual(result.rows.map(row=>row.assigned),[1,2,2,2]);assert.equal(result.issues.length,0);
});
test("flags inconsistent staffing inside the same group",()=>{
  const jobs=[
    {id:"b",team_id:"t",group_code:"MN-1",count_worker1:0,count_worker2:2,count_worker3:1,count_helper:0},
    {id:"c",team_id:"t",group_code:"MN-1",count_worker1:0,count_worker2:3,count_worker3:1,count_helper:0},
  ];
  const result=calculateStaffingCoverage(jobs,payroll);assert.equal(result.countedStructures,1);assert.equal(result.issues.length,1);assert.equal(result.balanced,false);
});
