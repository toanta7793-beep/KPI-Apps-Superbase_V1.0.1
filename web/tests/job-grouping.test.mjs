import test from "node:test";import assert from "node:assert/strict";import {validateJobGroup} from "../app/jobGrouping.ts";

// Quy tắc ở đây phải khớp đúng create_job_group trong database. Trước đây không có test nào
// phủ hàm này, nên khi migration 041 bỏ yêu cầu trùng vị trí ở database mà bản sao ở giao
// diện vẫn giữ, không có gì phát hiện ra. Người dùng vẫn bị chặn y như cũ.
const base={
  id:"a",team_id:"T1",start_date:"2026-09-02",end_date:"2026-09-03",content:"Lắp ống",
  location:"Tầng 3",count_leader:0,count_worker1:1,count_worker2:0,count_worker3:0,count_helper:0,
  group_code:null,unit_price:1000,work_days:2,production_value:5000,actual_labor_cost:1000,
};
const job=(over={})=>({...base,...over});

test("gộp được khi khác vị trí — đây là điều 041 muốn cho phép",()=>{
  assert.equal(validateJobGroup([
    job({id:"a",location:"Tầng 3"}),
    job({id:"b",location:"Tầng 5 trục A-B"}),
    job({id:"c",location:"Ngoài trời"}),
  ]),"");
});

test("vẫn phải CÓ vị trí — kiểm mọi việc, không chỉ việc đầu",()=>{
  // Việc đầu có vị trí, việc sau bỏ trống. Trước đây chỉ kiểm việc đầu nên lọt xuống
  // database rồi mới bị chặn, người dùng nhận một mã lỗi thay vì một câu tiếng Việt.
  const issue=validateJobGroup([job({id:"a"}),job({id:"b",content:"Đi dây",location:"  "})]);
  assert.match(issue,/Đi dây/);
  assert.match(issue,/chưa có Vị trí/);
  assert.equal(validateJobGroup([job({id:"a"}),job({id:"b",location:null})])===""
    ,false);
});

test("các điều kiện còn lại vẫn chặn",()=>{
  assert.match(validateJobGroup([job()]),/ít nhất 2/);
  assert.match(validateJobGroup([job({id:"a"}),job({id:"b",team_id:"T2"})]),/không cùng Tổ/);
  assert.match(validateJobGroup([job({id:"a"}),job({id:"b",start_date:"2026-09-04"})]),/không cùng khoảng ngày/);
  assert.match(validateJobGroup([job({id:"a"}),job({id:"b",count_worker2:2})]),/không cùng cơ cấu nhân sự/);
  assert.match(validateJobGroup([job({id:"a"}),job({id:"b",group_code:"MN-1"})]),/đã thuộc nhóm/);
  assert.match(validateJobGroup([job({id:"a"}),job({id:"b",unit_price:null})]),/chưa đủ Đơn giá/);
});
