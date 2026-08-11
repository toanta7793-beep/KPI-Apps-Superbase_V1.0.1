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

test("nhiều mã nhóm khác nhau: mỗi nhóm tính một lần, dòng lẻ tính từng dòng", () => {
  const job = (id, group_code, w1 = 0, w2 = 0, w3 = 0, helper = 0) =>
    ({ id, team_id: "T", group_code, count_worker1: w1, count_worker2: w2, count_worker3: w3, count_helper: helper });
  const jobs = [
    // Nhóm A: 2 dòng, cùng cơ cấu 1 thợ bậc 1 -> chỉ tính MỘT lần
    job("a1", "MN-20260902-01", 1), job("a2", "MN-20260902-01", 1),
    // Nhóm B: 3 dòng, cùng cơ cấu 2 thợ bậc 2 -> chỉ tính MỘT lần
    job("b1", "MN-20260902-02", 0, 2), job("b2", "MN-20260902-02", 0, 2), job("b3", "MN-20260902-02", 0, 2),
    // Hai dòng KHÔNG nhóm -> tính từng dòng
    job("c1", null, 0, 0, 1), job("c2", null, 0, 0, 1),
  ];
  const payroll = [
    { role_name: "Thợ bậc 1", worker_count: 1, unknown_workers: [] },
    { role_name: "Thợ bậc 2", worker_count: 2, unknown_workers: [] },
    { role_name: "Thợ bậc 3", worker_count: 2, unknown_workers: [] },
    { role_name: "Thợ phụ", worker_count: 0, unknown_workers: [] },
  ];
  const r = calculateStaffingCoverage(jobs, payroll);
  const by = Object.fromEntries(r.rows.map(x => [x.role, x.assigned]));
  assert.equal(by["Thợ bậc 1"], 1, "nhóm A gồm 2 dòng nhưng chỉ tính 1 lần");
  assert.equal(by["Thợ bậc 2"], 2, "nhóm B gồm 3 dòng nhưng chỉ tính 1 lần");
  assert.equal(by["Thợ bậc 3"], 2, "hai dòng lẻ tính hai lần");
  assert.equal(r.countedStructures, 4, "2 nhóm + 2 dòng lẻ = 4 cơ cấu");
  assert.deepEqual(r.issues, []);
  assert.equal(r.balanced, true, "quân số phải khớp");
});

test("tổ trưởng không bị tính vào quân số đã giao dù khai bao nhiêu", () => {
  const jobs = [{ id: "x", team_id: "T", group_code: null,
    count_leader: 5, count_worker1: 1, count_worker2: 0, count_worker3: 0, count_helper: 0 }];
  const payroll = [{ role_name: "Thợ bậc 1", worker_count: 1, unknown_workers: [] }];
  const r = calculateStaffingCoverage(jobs, payroll);
  assert.equal(r.rows.every(x => x.role !== "Tổ trưởng"), true, "không có dòng Tổ trưởng trong bảng đối chiếu");
  assert.equal(r.rows.find(x => x.role === "Thợ bậc 1").assigned, 1);
  assert.equal(r.balanced, true, "5 tổ trưởng khai ra không được làm lệch quân số");
});
